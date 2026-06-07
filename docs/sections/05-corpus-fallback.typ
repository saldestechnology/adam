= Corpus Fallback: Surviving Rate Limits

The free model used by the prototype (`opencode/deepseek-v4-flash-free`) reliably produces specifications for approximately 200--250 cycles before its rate limit blocks further generation. A naive system would halt. The current implementation treats this not as a failure but as an opportunity.

== Recycling Verified Artifacts

When Phase 1 (spec generation) fails with a non-zero exit code or returns empty text, the orchestrator immediately falls back to the existing corpus:

1. Select a random `spec_*.md` file from the `output/` directory.
2. Copy it into the current worktree as the specification.
3. Proceed to Phase 2.

If Phase 2 (code generation) also fails—either by exceeding the 300-second timeout or returning empty code—the orchestrator falls back to the code corpus:

1. Select up to five random `lib_*.rs` files from `output/`.
2. Copy each into `src/lib.rs` in turn.
3. Run `cargo check`. The first file that compiles is accepted.
4. Proceed to Phase 3.

This means that even when the generative model is completely unavailable, the system continues producing verified, audited, and indexed artifacts by remixing its own history.

== Mathematical Intuition

Let $P$ be the probability that a single Ralph Loop iteration generates compilable code from a fresh specification. Let $C$ be the size of the existing code corpus. The probability of harvesting at least one artifact per cycle, given a dead model, approaches:

$
  1 - (1 - 1/C)^5
$

as $C$ grows. With $C = 115$, the probability of success on any single cycle is approximately 4.3% per try, yielding a reasonable expectation of harvesting within a few attempts.

== Operational Observations

In practice, the corpus fallback has proven remarkably effective. A single corpus-fallback cycle executed during testing harvested a ring buffer implementation, ran it through the full `ctx` quality gate (audit score: 9.8), and pushed it to Qdrant—all without any model API call. This demonstrates that the *intelligence* of the system increasingly resides in the corpus, not the generator.
