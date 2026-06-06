#!/usr/bin/env python3
"""
Compiled AI — Spec Embedding & Qdrant Ingestion

Reads a spec file and a verified Rust source, generates a semantic embedding
using a local sentence-transformers model, and pushes the complete record
into the Qdrant vector database.
"""

import argparse
import hashlib
import json
import os
import sys
import time
import uuid

import numpy as np
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

MODEL_NAME = os.environ.get("EMBED_MODEL", "all-MiniLM-L6-v2")
VECTOR_SIZE = int(os.environ.get("EMBED_VECTOR_SIZE", "384"))
COLLECTION_NAME = os.environ.get("QDRANT_COLLECTION", "compiled_ai_specs")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant:6333")


def load_embeddings_model():
    """Lazy-load the sentence-transformers model."""
    from sentence_transformers import SentenceTransformer
    return SentenceTransformer(MODEL_NAME)


def ensure_collection(client: QdrantClient):
    """Create collection if it does not exist."""
    try:
        client.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE),
        )
    except Exception as exc:
        if "already exists" not in str(exc):
            raise


def compute_spec_embedding(model, spec_text: str):
    """Return dense embedding vector for the spec."""
    embedding = model.encode(spec_text, convert_to_numpy=True, show_progress_bar=False)
    return embedding.tolist()


def load_ctx_metadata(work_dir: str) -> dict:
    """Read ctx audit, complexity, and graph JSON files from the work directory."""
    meta = {}
    # Audit score
    audit_path = os.path.join(work_dir, ".ctx_audit.json")
    if os.path.exists(audit_path):
        try:
            with open(audit_path, "r", encoding="utf-8") as f:
                audit = json.load(f)
            meta["ctx_audit_score"] = audit.get("overall_score")
            meta["ctx_audit_passed"] = audit.get("passed")
            meta["ctx_audit_categories"] = audit.get("categories", [])
        except Exception:
            pass

    # Complexity analysis
    complexity_path = os.path.join(work_dir, ".ctx_complexity.json")
    if os.path.exists(complexity_path):
        try:
            with open(complexity_path, "r", encoding="utf-8") as f:
                comp = json.load(f)
            if isinstance(comp, list):
                meta["ctx_functions"] = comp
                meta["ctx_symbol_count"] = len(comp)
                scores = [fn.get("complexity_score", 0) for fn in comp if isinstance(fn, dict)]
                meta["ctx_max_complexity"] = max(scores) if scores else None
        except Exception:
            pass

    # Call graph — enables structural similarity search
    graph_path = os.path.join(work_dir, ".ctx_graph.json")
    if os.path.exists(graph_path):
        try:
            with open(graph_path, "r", encoding="utf-8") as f:
                graph = json.load(f)
            edges = graph.get("edges", [])
            nodes = graph.get("nodes", [])
            # Deduplicate nodes by name (ctx graph JSON sometimes has dups)
            seen = set()
            unique_nodes = []
            for n in nodes:
                name = n.get("name") if isinstance(n, dict) else n
                if name and name not in seen:
                    seen.add(name)
                    unique_nodes.append(n)
            meta["ctx_graph"] = {
                "nodes": [n.get("name", str(n)) for n in unique_nodes],
                "edges": edges,
            }
            # Graph metrics for filtering
            node_count = len(unique_nodes)
            edge_count = len(edges)
            meta["ctx_graph_node_count"] = node_count
            meta["ctx_graph_edge_count"] = edge_count
            # Edge density = edges / (nodes * (nodes-1)) for directed graph
            if node_count > 1:
                meta["ctx_graph_density"] = round(
                    edge_count / (node_count * (node_count - 1)), 4
                )
            else:
                meta["ctx_graph_density"] = 0.0
            # Cyclomatic complexity proxy: edges - nodes + 2*connected_components
            # Simplified: edges - nodes + 2 (assume 1 component for single-file primitives)
            meta["ctx_graph_cyclomatic_proxy"] = max(1, edge_count - node_count + 2)
        except Exception:
            pass

    # Mermaid diagram (for visual reference)
    mermaid_path = os.path.join(work_dir, ".ctx_graph.mmd")
    if os.path.exists(mermaid_path):
        try:
            with open(mermaid_path, "r", encoding="utf-8") as f:
                mermaid_text = f.read().strip()
            if mermaid_text:
                meta["ctx_graph_mermaid"] = mermaid_text
        except Exception:
            pass

    return meta


def build_payload(hash_val: str, code: str, spec: str, manifest: dict, model_name: str, ctx_meta: dict) -> dict:
    """Build Qdrant point payload with flattened ctx metadata."""
    payload = {
        "ast_hash": hash_val,
        "code": code,
        "spec": spec,
        "manifest": manifest,
        "llm_model": model_name,
        "timestamp": manifest.get("timestamp", "unknown"),
        "intent": extract_frontmatter_intent(spec),
        "category": extract_frontmatter_field(spec, "category"),
        "complexity": extract_frontmatter_field(spec, "complexity"),
    }
    # Flatten ctx metadata for direct Qdrant filtering
    payload.update(ctx_meta)
    return payload


def extract_frontmatter_field(spec_text: str, key: str) -> str:
    """Extract a simple YAML frontmatter field."""
    lines = spec_text.splitlines()
    in_fm = False
    for line in lines:
        stripped = line.strip()
        if stripped == "---":
            if not in_fm:
                in_fm = True
                continue
            break
        if in_fm and stripped.startswith(f"{key}:"):
            return stripped.split(":", 1)[1].strip().strip('"')
    return ""


def extract_frontmatter_intent(spec_text: str) -> str:
    """Extract the intent field from YAML frontmatter."""
    return extract_frontmatter_field(spec_text, "intent")


def push_to_qdrant(client: QdrantClient, point_id: str, vector: list, payload: dict):
    """Upsert a single point into Qdrant."""
    client.upsert(
        collection_name=COLLECTION_NAME,
        points=[
            PointStruct(
                id=point_id,
                vector=vector,
                payload=payload,
            )
        ],
        wait=True,
    )


def main():
    parser = argparse.ArgumentParser(description="Embed spec and push to Qdrant")
    parser.add_argument("--spec", required=True, help="Path to spec.txt")
    parser.add_argument("--code", required=True, help="Path to src/lib.rs")
    parser.add_argument("--hash", required=True, help="AST content hash")
    parser.add_argument("--manifest", required=True, help="Path to sentinel manifest JSON")
    parser.add_argument("--work-dir", default=".", help="Working directory where ctx .json files live")
    parser.add_argument("--model", default="unknown", help="LLM model name")
    args = parser.parse_args()

    with open(args.spec, "r", encoding="utf-8") as f:
        spec_text = f.read()
    with open(args.code, "r", encoding="utf-8") as f:
        code_text = f.read()
    with open(args.manifest, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    # Load ctx metadata
    ctx_meta = load_ctx_metadata(args.work_dir)

    # Connect to Qdrant
    client = QdrantClient(url=QDRANT_URL)
    ensure_collection(client)

    # Compute embedding
    print("[Embed] Loading model...", file=sys.stderr)
    model = load_embeddings_model()
    print("[Embed] Computing embedding...", file=sys.stderr)
    vector = compute_spec_embedding(model, spec_text)

    # Build payload and deterministic point ID (Qdrant requires UUID format for string IDs)
    payload = build_payload(args.hash, code_text, spec_text, manifest, args.model, ctx_meta)
    point_id = str(uuid.uuid5(uuid.NAMESPACE_OID, args.hash))

    # Push
    print("[Embed] Pushing to Qdrant...", file=sys.stderr)
    push_to_qdrant(client, point_id, vector, payload)
    print(f"[Embed] Done. Point ID: {point_id}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
