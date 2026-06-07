= Harvest: Content-Addressable Retrieval

When a worktree successfully breaks out of the Ralph Loop, the generated code moves to the harvesting phase. To prevent duplicate generation of common patterns and ensure origin authenticity, the code is transformed into a content-addressable block of logic.

== AST Normalization and Hashing

Storing raw text leads to cache misses due to variable formatting, spacing, or comments. The harvesting primitive parses the successfully compiled source code into a clean Abstract Syntax Tree. It strips out all non-functional formatting, standardizes variable names, serializes the AST into a deterministic byte stream, and runs it through a cryptographic hash function.

Let $"Hash"_("AST")$ denote the content address:

$
  "Hash"_("AST") = "SHA-256"("Serialize"("Normalize"("AST")))
$

This hash is the primary key for deduplication. Because it is derived purely from functional structure, any two independent Ralph Loops anywhere on earth that produce the same logical solution to a spec will generate the exact same hash.

== The Harvest Crate

The `harvest` Rust crate uses `syn` to extract a deterministic skeleton from compilable source. It emits a JSON representation containing only:

- Struct definitions: name, generics, field names and types
- Enum definitions: name, variants with their field types
- Function signatures: name, generics, parameter list, and return type
- Trait definitions and implementation blocks

All spans, whitespace, and comments are stripped. The resulting JSON is normalized using `serde_json` with `preserve_order`, producing a consistent byte sequence for hashing independent of the original formatting.

== Semantic Embeddings

Each verified specification is embedded using the `all-MiniLM-L6-v2` sentence-transformers model, which produces a 384-dimensional dense vector from the specification text. The embedding captures the functional intent of the artifact, not the syntax of its implementation. A query for a ring buffer should retrieve not just ring buffers, but any specification whose intent aligns with bounded storage or FIFO semantics.

The embedding is normalized to unit length so that cosine similarity and dot product are equivalent:

$
  "cos"(accent(u, arrow), accent(v, arrow)) = (accent(u, arrow) dot accent(v, arrow)) / (||accent(u, arrow)|| ||accent(v, arrow)||)
$

== Qdrant Vector Database

Qdrant stores each entry as a point with:

- An id derived from the AST hash via UUIDv5, guaranteeing deterministic deduplication
- A 384-dimensional normalized embedding vector
- A flat payload containing the spec text, code, manifest, and all ctx-derived quality metrics

The flat payload structure enables direct filtering queries, such as retrieving all audit-scored artifacts.
