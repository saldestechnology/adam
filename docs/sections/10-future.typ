= Limitations and Future Work

== Known Limitations

- *Single-node operation*. The current prototype runs on one machine. The distributed architecture remains a design goal.
- *Free model dependency*. The prototype relies on a free-tier SLM with strict rate limits. Future work will evaluate whether the corpus can sustain itself entirely through fallback once it reaches sufficient size.
- *Rust-only*. The prototype targets Rust due to its strong compiler sentinel properties. Support for other languages with deterministic type checking is future work.
- *No human review*. The system is fully autonomous; there is no mechanism for human-in-the-loop approval before artifacts enter the corpus.
- *Mermaid post-processing*. The mermaid diagram generation occasionally produces spurious warnings during sed post-processing. This is harmless but should be cleaned up.

== Roadmap

1. *Clustered mining*. Deploy multiple miner containers on a single node with shared Qdrant, increasing throughput through parallel worktree provisioning within a single machine.
2. *Cross-node synchronization*. Implement a gossip protocol for artifact announcements, followed by DHT-based content retrieval.
3. *Model-corpus co-evolution*. Query the corpus before invoking the model, reducing generation load and improving retrieval performance as the database grows.
4. *Multi-language support*. Extend the compiler sentinel to include Go, Zig, or ML-family languages with strong type systems.
5. *Formal verification integration*. Integrate Rust proof assistants such as Kani or Prusti to raise the semantic verification bar beyond compilation.
