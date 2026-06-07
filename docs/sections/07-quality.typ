= The Quality Analysis Gate

Compilation correctness is necessary but not sufficient. The system enforces a mandatory quality gate using `ctx`, a code intelligence tool that computes structural and stylistic metrics after every successful `cargo check`.

== Pipeline

After compilation, the orchestrator runs four ctx commands in sequence inside the worktree:

1. `ctx index` — Build the symbol database for the current codebase.
2. `ctx audit` — Compute an overall quality score across five categories: complexity, duplication, coverage, modularity, and naming.
3. `ctx complexity` — Calculate per-function cyclomatic complexity and fan-out.
4. `ctx graph` — Generate the call graph (JSON and Mermaid).

If any step fails, the artifact is rejected. Only code that compiles AND passes the quality gate is eligible for embedding and storage.

== The Audit Score

The audit score is a weighted average:

$
  "Score"_("audit") = Sigma_i "Score"_i dot "Weight"_i
$

The weights and categories are fixed by the ctx implementation. A score near 10.0 indicates clean, modular, well-documented code. Scores below 7.0 suggest significant duplication, missing documentation, or functions with excessive branching. The prototype filters on exit code, not score value, but the score is preserved in the Qdrant payload for downstream ranking.

== Call Graph Metrics

The call graph yields additional payload fields used for semantic filtering: node count, edge count, graph density, and a cyclomatic proxy (edges minus nodes plus two). These metrics let researchers correlate structural complexity with audit scores and identify well-designed primitives independent of their surface complexity.
