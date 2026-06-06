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


def build_payload(hash_val: str, code: str, spec: str, manifest: dict, model_name: str) -> dict:
    """Build Qdrant point payload."""
    return {
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
    parser.add_argument("--model", default="unknown", help="LLM model name")
    args = parser.parse_args()

    with open(args.spec, "r", encoding="utf-8") as f:
        spec_text = f.read()
    with open(args.code, "r", encoding="utf-8") as f:
        code_text = f.read()
    with open(args.manifest, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    # Connect to Qdrant
    client = QdrantClient(url=QDRANT_URL)
    ensure_collection(client)

    # Compute embedding
    print("[Embed] Loading model...", file=sys.stderr)
    model = load_embeddings_model()
    print("[Embed] Computing embedding...", file=sys.stderr)
    vector = compute_spec_embedding(model, spec_text)

    # Build payload and deterministic point ID (Qdrant requires UUID format for string IDs)
    payload = build_payload(args.hash, code_text, spec_text, manifest, args.model)
    point_id = str(uuid.uuid5(uuid.NAMESPACE_OID, args.hash))

    # Push
    print("[Embed] Pushing to Qdrant...", file=sys.stderr)
    push_to_qdrant(client, point_id, vector, payload)
    print(f"[Embed] Done. Point ID: {point_id}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
