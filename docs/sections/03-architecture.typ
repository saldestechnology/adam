= Architecture Overview

The current prototype is a single-node Docker deployment consisting of two services: a Qdrant vector database and a miner daemon. The miner runs an infinite loop that mines, verifies, and indexes Rust primitives autonomously.

== System Diagram

#figure(
  grid(
    columns: (3cm, 0.5cm, 3cm, 0.5cm, 3cm),
    align: horizon + center,
    gutter: 0cm,
    rect(fill: luma(240), stroke: 0.5pt, inset: 4pt, radius: 2pt)[
      #set align(center)
      #text(size: 8pt, weight: "bold")[Phase 1]
      #text(size: 8pt)[Spec Gen]
    ],
    text(size: 12pt)[→],
    rect(fill: luma(240), stroke: 0.5pt, inset: 4pt, radius: 2pt)[
      #set align(center)
      #text(size: 8pt, weight: "bold")[Phase 2]
      #text(size: 8pt)[Ralph Loop]
    ],
    text(size: 12pt)[→],
    rect(fill: luma(240), stroke: 0.5pt, inset: 4pt, radius: 2pt)[
      #set align(center)
      #text(size: 8pt, weight: "bold")[Phase 3]
      #text(size: 8pt)[Harvest + Qdrant]
    ],
  ),
  caption: [Mining pipeline: three phases executed in sequence per worktree cycle.],
)

== Deployment

The entire stack is defined in a single `docker-compose.yml` file. Qdrant (port 6333) stores specification embeddings and metadata. The miner container runs the loop daemon, built from a multi-stage Dockerfile that includes the Rust toolchain, the `opencode` CLI, Python dependencies for embedding, and a prebuilt `ctx` binary.

Both services share a Docker bridge network and a bind-mounted `output/` directory for persisting artifacts.

== File Map

#figure(
  table(
    columns: (1fr, 2fr),
    [File], [Role],
    [`adam.sh`], [Loop daemon; Phase 1 and 2 implement corpus fallback],
    [`docker-compose.yml`], [Qdrant + miner services with bind mounts],
    [`Dockerfile`], [Multi-stage: harvest-builder + runtime with opencode and ctx],
    [`Makefile`], [Orchestration commands: up, down, logs, db, query, stats, artifacts, stop, clean, rebuild],
    [`SYSTEM.md`], [LLM prompt for spec generation (Platonic Primitive Directive)],
    [`scripts/embed_and_push.py`], [One-shot: spec to embedding to Qdrant upsert with ctx metadata],
    [`scripts/batch_push_existing.py`], [Backfill script for `output/` orphans],
    [`harvest/src/main.rs`], [Rust crate: parse with syn, emit deterministic JSON, SHA-256 hash],
    [`ctx-linux-aarch64`], [Prebuilt ctx v0.2.0 binary (71MB ELF)],
  ),
  caption: [Key files in the repository and their roles.],
)
