= Empirical Results

The prototype has been running autonomously for several days at the time of this writing. The following metrics are extracted from the live Qdrant database and local artifact store.

== Corpus Size

- Total specifications generated: over 115
- Total verified code artifacts: over 115
- Total entries in Qdrant vector database: 116 (with approximately 5 local-only orphans not yet backfilled)

== Quality Distribution

The average ctx audit score across the corpus is approximately 9.0 out of 10. Individual scores range from 7.5 to 9.8. The high average reflects the Platonic Primitive Directive: simpler primitives are easier to verify and score well on modularity, naming, and complexity metrics.

== Corpus Fallback Effectiveness

After the free model's rate limit was encountered at approximately cycle 250, the corpus fallback mechanism successfully produced additional verified artifacts by recycling existing specs and code. A single test cycle achieved the full pipeline--compilation, audit score 9.8, and Qdrant upsert--without any model API call, demonstrating that the system's intelligence increasingly resides in the corpus rather than the generator.

== Artifact Categories

The generated primitives span the full range of the Platonic categories: data structures, algorithms, string utilities, concurrency primitives, error handling idioms, mathematical utilities, and memory management patterns. The bias toward low complexity is visible in the category distribution, with single-purpose primitives--ring buffers, sparse vectors, ticket locks--comprising the majority of high-scoring entries.
