= Toward a Distributed Semantic Graph

The current prototype is a single-node proof of concept. The logical next step is to distribute the content-addressable cache and the verification pipeline across a peer-to-peer network, enabling edge models to query a global pool of verified knowledge rather than relying on their own limited parameters.

== Design Goal

The distributed architecture envisions a network of autonomous mining nodes, each running the same three-phase pipeline. Nodes are untrusted by default. Verification is local via the compiler sentinel; trust is emergent from repeated verification history.

== Content-Routing via Distributed Hash Table

The AST hash serves as the routing key in a Kademlia-style Distributed Hash Table. When a node needs a primitive, it hashes the spec and queries the DHT. If the artifact exists, it is retrieved from the closest node by XOR metric.

Gossip is not used for the verified artifacts themselves, as they are content-addressable and can be retrieved on demand. Instead, nodes gossip lightweight announcements of newly verified primitives: a small tuple of (AST hash, sentinel manifest, node signature) that lets peers know the artifact exists and where to fetch it.

== Trust and Reputation

Nodes are not trusted. However, a reputation weight accrues to nodes that have historically supplied verified artifacts that pass remote compilation on requesting nodes. A node that repeatedly publishes code that fails the sentinel is deprioritized in the routing table.

== The Smaller Model Thesis

The primary motivation for distribution is to make the corpus accessible to Small Language Models running at the edge. A model with a billion parameters can retrieve and reason about a verified ring buffer implementation from the corpus, dramatically exceeding what it could generate via its own internal weights. The corpus effectively acts as an externalized long-term memory, compensating for the model's limited reasoning budget.

In the limit, the system approaches a scenario where the generative model is only invoked for genuinely novel specifications. Common patterns are retrieved, compiled, and returned without ever touching the model, reducing both latency and variable compute costs.
