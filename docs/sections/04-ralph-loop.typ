= Parallel Stateless Worktrees and the Ralph Loop

Once a specification is crystallized, the generation phase begins. Rather than relying on a single agent running sequentially, the system leverages strict environmental isolation and statelessness to weaponize non-determinism as an exploration tool.

== Worktree Provisioning

Each cycle of the loop daemon provisions an isolated worktree inside the bind-mounted `output/` volume. The worktree contains a `Cargo.toml` for a new `mined_primitive` crate, an empty `src/lib.rs`, the specification copied into `spec.txt`, and an empty `compiler_errors.log`. The worktree is destroyed after every cycle, whether the compilation succeeds or fails. This tabula rasa approach prevents context poisoning; the model never sees its own previous mistakes.

== The Stateless Ralph Loop

Within each worktree, the orchestrator places a prompt into a stateless Small Language Model. The core rules of the Ralph Loop are:

- *The compiler is the sentinel.* The model has no agency to declare success. Only `cargo check` returning exit code zero can advance the artifact to harvesting.
- *Tabula rasa state recovery.* If compilation fails, the workspace is wiped. The next iteration receives only the specification, the last invalid code state, and the compiler error trace. No conversational memory persists.
- *Closed loop until convergence.* The cycle repeats until the sentinel returns zero, or until a configurable timeout or iteration limit is reached.

In formal terms, the state transition function is:

$
  S_(t+1) = "Sentinel"("SLM"("Spec", "Error"_t))
$

where $S_t$ is the code state at iteration $t$, and `"Sentinel"` is the deterministic compilation check. A cycle succeeds when the sentinel produces exit code zero. A cycle fails when the outer timeout is reached or the iteration budget is exhausted.

== Compiler as Oracle

Unlike interactive coding assistants, the model in the Ralph Loop is not permitted to explain, apologize, or reason about its output. It is a pure text-to-text function that receives the current state of the codebase and must produce a file that satisfies the compiler. The sentinel provides the only ground truth. This design removes the epistemic drift that occurs when a model is allowed to self-evaluate; the compiler has no bias, no training set, and no hallucination capacity.

== Parallelism

The current prototype runs a single worktree per miner, but the architecture is designed for horizontal scaling. Running $N$ parallel worktrees on the same specification produces $N$ independent explorations of the solution space without the $O(n)$ conversation history that sequential interaction requires.
