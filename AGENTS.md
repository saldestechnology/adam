# AGENTS.md — Compiled AI

## What This Is

A Dockerized autonomous Rust spec miner. It runs an infinite loop (adam.sh) that:
1. **Phase 1**: Generates a spec (or recycles one from corpus)
2. **Phase 2**: Feeds the spec to `opencode run` → compiles → harvests
3. **Phase 3**: Runs `ctx` analysis (audit/complexity/graph), embeds the spec (all-MiniLM-L6-v2, 384d), pushes to Qdrant (cosine, port 6333)

## Key Architecture Facts

### The Model Sucks (Plan For It)
- **opencode/deepseek-v4-flash-free** rate-limits aggressively after ~200–250 cycles.
- The loop survives this: **corpus fallback**. If Phase 1 or Phase 2 fails, adam.sh recycles a random spec/lib from `output/` and still runs ctx + Qdrant. This is intentional.
- Phase 2 timeout is **300s**. The model can take minutes.

### Docker Bind Mounts (No Rebuild Needed)
- `adam.sh` and `scripts/*.py` are **live-mounted** in `docker-compose.yml`.
- Script changes take effect on next `make up` (or `docker compose up -d miner`).
- If you change the Dockerfile itself, use `make rebuild`.

### ctx Is Heavy
- `ctx` (~70MB ELF aarch64) is **prebuilt externally** and `COPY`-baked into the image.
- Do NOT try to compile ctx inside Docker build — DuckDB C++ needs 1.5–2GB peak RAM and kills buildkit.
- Prebuild: `CARGO_BUILD_JOBS=1` inside a standalone `rust:latest` container, then commit the binary.

### Qdrant Is Often Overlooked
- Collection: `compiled_ai_specs`; API: `http://localhost:6333`
- **Always query Qdrant first** before assuming database state.
- Point IDs are `uuid.uuid5(NAMESPACE_OID, ast_hash)`.
- The system has ~116 points already; ~5 may be local-only orphans.

## Exact Commands

```bash
# Stack
make up         # Build + start Qdrant + miner
make down       # Stop all
make logs       # Stream miner logs (live)
make db         # Open Qdrant dashboard

# Qdrant quick checks
# Count points
make query

# Count by shell (direct)
curl -s -X POST http://localhost:6333/collections/compiled_ai_specs/points/count \
  -H 'Content-Type: application/json' -d '{}' | python3 -m json.tool

# Scroll sample payload (with vectors false for speed)
curl -s -X POST http://localhost:6333/collections/compiled_ai_specs/points/scroll \
  -H 'Content-Type: application/json' \
  -d '{"limit": 10, "with_payload": true, "with_vectors": false}'

# Miner
make stop       # Stop miner only (Qdrant stays for inspect)
make clean      # Stop all, remove image, delete output/
make rebuild    # `--no-cache` rebuild
make artifacts  # List local spec_*.md + lib_*.rs
make stats      # Scroll Qdrant and print basics

# Harvest Rust binary (for one-off AST hashing)
cd harvest && cargo run --release -- /path/to/code.rs
```

## File Map

| File | Role |
|------|------|
| `adam.sh` | Loop daemon (outer loop); lives in container via bind mount. Phase 1 + 2 have corpus fallback. |
| `docker-compose.yml` | Qdrant + miner; miner depends_on Qdrant; binds `./output`, `./adam.sh`, `./scripts/` |
| `Dockerfile` | Multi-stage: harvest-builder (Rust), runtime (Rust + Python + opencode + prebuilt ctx binary) |
| `Makefile` | `up/down/logs/db/query/stats/artifacts/stop/clean/rebuild` |
| `SYSTEM.md` | LLM prompt for spec generation (Platonic Primitive Directive) |
| `scripts/embed_and_push.py` | One-shot: spec → embedding → Qdrant upsert; includes ctx metadata extraction |
| `scripts/batch_push_existing.py` | Backfill script for `output/` orphans. **Pre-check Qdrant first** — most locals are already in DB. |
| `harvest/src/main.rs` | Rust crate: parse Rust with `syn`, emit deterministic JSON, SHA-256 hash (formatting-agnostic) |
| `ctx-linux-aarch64` | Prebuilt `saldestechnology/ctx` v0.2.0. Must be in repo root for Dockerfile COPY. |

## Common Pitfalls

1. **Assuming DB is empty.** A `scroll` with `limit: 200` is the first thing to do when investigating data state.
2. **Forgetting the entrypoint.** `compiled-ai-miner`'s ENTRYPOINT is `/app/adam.sh`. If it restloops with `permission denied`, run `chmod +x adam.sh` **host-side**, then recreate.
3. **Mermaid sed warning.** `ctx graph --output mermaid` is post-processed by `sed -i` then `sed -e ... > .tmp && mv`. The fallback to `.tmp` occasionally logs a harmless `mv: cannot stat '.ctx_graph.mmd.tmp'` — non-fatal.
4. **`local` in bash loops.** In bash 5.x (Debian in container), `local` is only valid inside functions. The main loop body uses plain variables. This was a live fix.
5. **`ctx index` before `ctx audit`.** `audit`, `complexity`, and `graph` all require a prior `ctx index` in the working directory. adam.sh does this in `enrich_manifest_with_ctx()`.
