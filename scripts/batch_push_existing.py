#!/usr/bin/env python3
"""
batch_push_existing.py
──────────────────────
One-shot ingestion of all spec_*.md + lib_*.rs pairs sitting in output/
into the Qdrant vector database.

Usage:
  python3 scripts/batch_push_existing.py [--output-dir /path/to/output]

Pairs are matched by timestamp (spec_YYYYMMDD_HHMMSS.md → lib_YYYYMMDD_HHMMSS.rs).
"""

import json, hashlib, uuid, pathlib, sys, re, argparse
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient, models

MODEL_NAME = "all-MiniLM-L6-v2"
COLLECTION_NAME = "compiled_ai_specs"
VECTOR_SIZE = 384

def get_args():
    p = argparse.ArgumentParser()
    p.add_argument("--output-dir", default="output", help="Directory with spec_*.md and lib_*.rs")
    return p.parse_args()

def get_model():
    print(f"[Embed] Loading {MODEL_NAME}...")
    return SentenceTransformer(MODEL_NAME)

def get_qdrant():
    print("[DB] Connecting to Qdrant at localhost:6333...")
    client = QdrantClient(host="localhost", port=6333)
    if not client.collection_exists(COLLECTION_NAME):
        client.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=models.VectorParams(size=VECTOR_SIZE, distance=models.Distance.COSINE),
        )
        print(f"[DB] Created collection '{COLLECTION_NAME}'")
    else:
        print(f"[DB] Collection '{COLLECTION_NAME}' already exists")
    return client

def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def embed(text: str, model) -> list[float]:
    return model.encode(text, normalize_embeddings=True).tolist()

def parse_spec_frontmatter(text: str) -> dict:
    """Extract YAML frontmatter keys: intent, category, complexity, rfc2119_level"""
    meta = {}
    if text.startswith("---"):
        end = text.find("---", 3)
        if end != -1:
            fm = text[3:end].strip()
            for line in fm.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip().lower()] = v.strip()
    return meta

def load_manifest_stub(ast_hash: str) -> dict:
    return {
        "sentinel_identity": "rustc (corpus fallback)",
        "sentinel_version": "unknown",
        "cargo_version": "unknown",
        "target_triple": "unknown",
        "optimization_level": "dev",
        "timestamp": "",
        "ctx_audit_score": None,
        "ctx_max_complexity": None,
        "ctx_symbol_count": None,
    }

def main():
    args = get_args()
    out = pathlib.Path(args.output_dir)
    if not out.is_dir():
        print(f"❌ Directory not found: {out}")
        sys.exit(1)

    # Collect pairs
    specs = sorted(out.glob("spec_*.md"))
    libs  = sorted(out.glob("lib_*.rs"))

    # Map by stem timestamp
    spec_map = {}
    for s in specs:
        m = re.search(r"spec_(\d{8}_\d{6})\.md", s.name)
        if m:
            spec_map[m.group(1)] = s

    lib_map = {}
    for l in libs:
        m = re.search(r"lib_(\d{8}_\d{6})\.rs", l.name)
        if m:
            lib_map[m.group(1)] = l

    # Find matching pairs
    pairs = []
    for ts in sorted(spec_map.keys()):
        if ts in lib_map:
            pairs.append((ts, spec_map[ts], lib_map[ts]))

    if not pairs:
        print("❌ No matching spec+lib pairs found.")
        sys.exit(1)

    print(f"[Scan] Found {len(pairs)} matched spec+code pairs in {out}")

    model = get_model()
    qdrant = get_qdrant()

    inserted = 0
    skipped = 0
    for ts, spec_path, lib_path in pairs:
        spec_text = spec_path.read_text(encoding="utf-8")
        code_text = lib_path.read_text(encoding="utf-8")

        meta = parse_spec_frontmatter(spec_text)
        code_hash = sha256(code_text)
        point_id = str(uuid.uuid5(uuid.NAMESPACE_OID, code_hash))

        # Check if already exists
        existing = qdrant.retrieve(
            collection_name=COLLECTION_NAME,
            ids=[point_id],
            with_vectors=False,
        )
        if existing:
            skipped += 1
            print(f"  ⏭  {ts} already in Qdrant (skipped)")
            continue

        manifest = load_manifest_stub(code_hash)
        manifest["timestamp"] = ts
        manifest["category"] = meta.get("category", "unknown")
        manifest["complexity"] = meta.get("complexity", "unknown")
        manifest["intent"] = meta.get("intent", "")
        manifest["rfc2119_level"] = meta.get("rfc2119_level", "")

        vector = embed(spec_text, model)

        qdrant.upsert(
            collection_name=COLLECTION_NAME,
            points=[
                models.PointStruct(
                    id=point_id,
                    vector=vector,
                    payload={
                        "spec": spec_text,
                        "code": code_text,
                        "ast_hash": code_hash,
                        "manifest": manifest,
                        "model": "corpus_fallback",
                    },
                )
            ],
        )
        inserted += 1
        print(f"  ✅ {ts} → Qdrant ({spec_path.name} + {lib_path.name})")

    print(f"\n[Done] Skipped: {skipped} | Inserted: {inserted} | Total pairs: {len(pairs)}")

if __name__ == "__main__":
    main()
