#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# but we handle the compiler check exit code manually.
set -o pipefail

# =====================================================================
# Configuration
# =====================================================================
OUTPUT_DIR="${OUTPUT_DIR:-.}"
SPEC_FILE="spec.txt"
CACHE_DB="$OUTPUT_DIR/compiled_cache.json"
MAX_LOOPS=15
MODEL_NAME="opencode/deepseek-v4-flash-free" # Or any open-source model of your choice supported by opencode

# Autonomous task categories (will be shuffled randomly before each run)
CATEGORIES=(
  "algorithms"
  "data_structures"
  "design_patterns"
  "string_utilities"
  "concurrency_primitives"
  "error_handling_idioms"
  "mathematical_utilities"
  "io_and_serialization"
  "cryptographic_utilities"
  "memory_management"
)

# Save the root directory so we can always navigate back safely
ROOT_DIR="$(pwd)"

# =====================================================================
# 1. Core Sanity Checks
# =====================================================================
if ! command -v rustc &>/dev/null; then
  echo "Error: 'rustc' compiler is not installed or not in PATH."
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "Error: 'git' is required to manage worktrees."
  exit 1
fi

if ! command -v opencode &>/dev/null; then
  echo "Error: 'opencode' utility is not installed or not in PATH."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: Must run inside a Git repository to use worktrees."
  exit 1
fi

# =====================================================================
# 2. Worktree Initialization
# =====================================================================
RUN_ID=$(date +%s)_$RANDOM
WORKTREE_DIR="$OUTPUT_DIR/.adam_worktrees/wt_$RUN_ID"
TEMP_BRANCH="adam-temp-$RUN_ID"
TEMP_CODE="src/lib.rs"
ERROR_LOG="compiler_errors.log"

echo "======================================================"
echo " adam: Initializing Git Worktree Environment "
echo "======================================================"
echo " Creating isolated worktree at: $WORKTREE_DIR"

# Ensure clean setup of the worktree directory
mkdir -p "$OUTPUT_DIR/.adam_worktrees"

# Create a new, isolated orphan branch and check it out in a new worktree
git worktree add -b "$TEMP_BRANCH" "$WORKTREE_DIR" &>/dev/null

if [ $? -ne 0 ]; then
  echo "Failed to create Git worktree."
  exit 1
fi

# Move into the worktree
cd "$WORKTREE_DIR" || exit 1

# Initialize a minimal Cargo structure inside the worktree
mkdir -p src
echo -e '[package]\nname = "mined_primitive"\nversion = "0.1.0"\nedition = "2021"' >Cargo.toml
touch "$TEMP_CODE"
touch "$ERROR_LOG"

# Copy the system prompt and opencode config into the worktree so opencode can find them
cp /app/AGENTS.md ./AGENTS.md
cp -r /app/.opencode ./.opencode

# =====================================================================
# 3. Phase 1 — Autonomous Spec Crystallization
# =====================================================================
echo "======================================================"
echo " Phase 1: Autonomous Spec Crystallization "
echo "======================================================"

# Shuffle the category list randomly using sort -R
SHUFFLED_CATEGORIES=$(printf '%s\n' "${CATEGORIES[@]}" | sort -R | tr '\n' ', ' | sed 's/, $//')

# Construct the explicit autonomous spec-generation prompt
SPEC_PROMPT="You are the Autonomous Rust Specification Crystallization Engine.

Your task is to invent a completely new, open-ended Rust library primitive and crystallize it into a formal specification.

INSTRUCTIONS:
1. Pick ONE category at random from the following list (presented in random order): $SHUFFLED_CATEGORIES
2. Within that category, invent a specific, non-trivial primitive. Be creative and architecturally sound.
3. Generate a complete specification document that conforms exactly to the format defined in AGENTS.md.
4. The specification MUST use RFC 2119 key words (MUST, MUST NOT, SHOULD, SHOULD NOT, MAY) for all requirements.
5. The specification MUST include YAML frontmatter with exactly these keys: intent, category, complexity, rfc2119_level.
6. The specification MUST contain these three sections in order: Structural Contract, Behavioral Contract, Conformance Tests.
7. Output ONLY the raw specification document. No markdown code wrappers. No preamble. No apologies.
8. The first line of your output MUST be '---' (the YAML frontmatter opener)."

echo "   [LLM] Generating autonomous specification via opencode using $MODEL_NAME..."
GENERATED_SPEC=$(opencode run "$SPEC_PROMPT" --model "$MODEL_NAME")

if [ $? -ne 0 ] || [ -z "$GENERATED_SPEC" ]; then
  echo "Error: opencode failed to generate a specification or returned empty output."
  cd "$ROOT_DIR"
  git worktree remove --force "$WORKTREE_DIR" &>/dev/null
  git branch -D "$TEMP_BRANCH" &>/dev/null
  rm -rf "$OUTPUT_DIR/.adam_worktrees"
  exit 1
fi

# Clean up any potential markdown wrappers if the model still generated them
GENERATED_SPEC=$(echo "$GENERATED_SPEC" | sed -e 's/```yaml//g' -e 's/```markdown//g' -e 's/```//g')

# Save the generated specification
echo "$GENERATED_SPEC" >"$SPEC_FILE"

echo "   [Spec] Autonomous specification generated and saved to $SPEC_FILE"
echo "   [Spec] Content preview (first 5 lines):"
head -n 5 "$SPEC_FILE" | sed 's/^/      /'

# =====================================================================
# 4. Phase 2 — The Pure Bash Ralph Loop
# =====================================================================
echo "======================================================"
echo " Phase 2: The Ralph Loop (Compiler Sentinel) "
echo "======================================================"

iteration=1
success=false

while [ $iteration -le $MAX_LOOPS ]; do
  echo "-> Iteration $iteration/$MAX_LOOPS"

  # Read current state safely in Bash
  SPEC_CONTENT=$(cat "$SPEC_FILE")
  LAST_CODE=$(cat "$TEMP_CODE")
  LAST_ERROR=$(cat "$ERROR_LOG")

  # Construct the stateless prompt
  CODE_PROMPT="You are a stateless Rust code generator. Write a library function for this specification:
$SPEC_CONTENT

PREVIOUS CODE:
$LAST_CODE

COMPILER ERROR:
$LAST_ERROR

Output ONLY raw Rust code without apologies or markdown wrappers."

  # Invoke local Open-Source model directly via opencode CLI
  echo "   [LLM] Querying via opencode using $MODEL_NAME..."
  GENERATED_CODE=$(opencode run "$CODE_PROMPT" --model "$MODEL_NAME")

  if [ $? -ne 0 ] || [ -z "$GENERATED_CODE" ]; then
    echo "Error: opencode failed to run or returned empty code."
    break
  fi

  # Clean up any potential markdown wrappers if the model still generated them
  GENERATED_CODE=$(echo "$GENERATED_CODE" | sed -e 's/```rust//g' -e 's/```//g')

  # Overwrite the worktree target (Tabula Rasa step)
  echo "$GENERATED_CODE" >"$TEMP_CODE"

  # Sentinel: Compiler Check inside the Worktree
  echo "   [Sentinel] Compiling inside isolated worktree..."
  cargo check &>"$ERROR_LOG"
  compile_status=$?

  if [ $compile_status -eq 0 ]; then
    echo "   [Sentinel] Compile Success!"
    success=true
    break
  else
    echo "   [Sentinel] Failed. Error recorded."
  fi

  iteration=$((iteration + 1))
  echo "-----------------------------------------"
done

# =====================================================================
# 5. Phase 3 — Harvesting, Artifact Persistence, and Worktree Teardown
# =====================================================================
cd "$ROOT_DIR" # Move back to root directory

if [ "$success" = true ]; then
  echo "======================================================"
  echo " SUCCESS: Primitive verified successfully."

  # Persist artifacts to OUTPUT_DIR for human inspection
  echo " Persisting artifacts to $OUTPUT_DIR..."
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cp "$WORKTREE_DIR/$SPEC_FILE" "$OUTPUT_DIR/spec_$TIMESTAMP.md"
  cp "$WORKTREE_DIR/$TEMP_CODE" "$OUTPUT_DIR/lib_$TIMESTAMP.rs"
  echo "   Spec saved as: $OUTPUT_DIR/spec_$TIMESTAMP.md"
  echo "   Code saved as: $OUTPUT_DIR/lib_$TIMESTAMP.rs"

  # Store the verified code into our JSON database
  VERIFIED_CODE_CONTENT=$(cat "$WORKTREE_DIR/$TEMP_CODE")
  SPEC_CONTENT_RAW=$(cat "$WORKTREE_DIR/$SPEC_FILE")

  HASH=$(python3 -c "
import json, hashlib, os
code = '''$VERIFIED_CODE_CONTENT'''
spec = '''$SPEC_CONTENT_RAW'''
normalized = '\n'.join([l.strip() for l in code.splitlines() if l.strip() and not l.strip().startswith('//')])
sha = hashlib.sha256(normalized.encode('utf-8')).hexdigest()

db = {}
if os.path.exists('$CACHE_DB'):
    try:
        with open('$CACHE_DB', 'r') as f: db = json.load(f)
    except: pass

db[sha] = {'code': code, 'spec': spec, 'sentinel': 'rustc_worktree'}
with open('$CACHE_DB', 'w') as f: json.dump(db, f, indent=2)
print(sha)
")

  echo " Unique Content-Address: $HASH"
  echo " Saved safely in: $CACHE_DB"
else
  echo "======================================================"
  echo " FAILURE: Loop exceeded max iterations without compiling."

  # Even on failure, persist the spec for debugging
  echo " Persisting failed spec to $OUTPUT_DIR for inspection..."
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cp "$WORKTREE_DIR/$SPEC_FILE" "$OUTPUT_DIR/spec_failed_$TIMESTAMP.md" 2>/dev/null || true
fi

# ALWAYS clean up worktrees and branches to leave a zero-footprint workspace
echo " Cleaning up temporary worktree and branches..."
git worktree remove --force "$WORKTREE_DIR" &>/dev/null
git branch -D "$TEMP_BRANCH" &>/dev/null
rm -rf "$OUTPUT_DIR/.adam_worktrees"

echo " Done."
echo "======================================================"

[ "$success" = true ] && exit 0 || exit 1
