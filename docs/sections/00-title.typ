#let title = "Compiled AI: Augmenting Language Models with Verified Semantic Corpora"
#let author = "Johan Saldes"
#let date = "June 2026"
#let version = "1.0.0"

#align(center + top)[
  #text(2em, weight: "bold", title)
  #v(1cm)
  #text(1.2em, author)
  #v(0.3cm)
  #text(1em, date)
  #v(0.2cm)
  #text(0.9em, "Version " + version)
  #v(1.5cm)
]

#align(center)[
  #text(1.3em, weight: "bold")[Abstract]
  #v(0.5cm)
]

#par(justify: true)[
Large Language Models (LLMs) have democratized software generation yet remain fundamentally constrained by a probabilistic ceiling: their outputs are non-deterministic, context-dependent, and subject to architectural drift. This phenomenon is especially acute with smaller, faster models deployed at the edge, which lack the capacity for deep reasoning but must nonetheless produce correct code.
]

#par(justify: true)[
This paper presents _Compiled AI_, a system architecture that addresses this limitation by shifting the center of intelligence from the model to a _verified, content-addressable corpus_ of compilable software artifacts. Rather than prompting a model in isolation, we argue that a modest language model, augmented with access to a database of previously verified, compiler-certified code primitives, can exceed the reliability and architectural consistency of a larger model operating alone. The corpus itself is constructed autonomously via a self-correcting generation loop that uses compiler feedback as an oracle, normalizes artifacts via AST-based deduplication, and indexes them by semantic intent through vector embeddings.
]

#par(justify: true)[
We describe the current single-node prototype, which has autonomously generated, verified, and indexed over 115 distinct Rust primitives with an average code quality audit score of 9.0 out of 10. We further outline a design path toward distributing this corpus over a peer-to-peer network, enabling edge models to query a global pool of verified knowledge rather than relying on their own limited parameters.
]