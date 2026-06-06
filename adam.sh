#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# but we handle the compiler check exit code manually.
set -o pipefail

# =====================================================================
# Helper: run opencode and capture text output (for Phase 1)
# Uses --format json for machine-readable text extraction.
# --dangerously-skip-permissions not needed here (read-only).
# =====================================================================
invoke_opencode_text() {
  local model="$1"
  local prompt="$2"
  local timeout_sec="${3:-300}"

  timeout "$timeout_sec" \
    opencode run "$prompt" --model "$model" --format json 2>&1 | \
    python3 -c "
import json, sys
text_parts = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        event = json.loads(line)
        if event.get('type') == 'text':
            part = event.get('part', {})
            if part.get('type') == 'text':
                text_parts.append(part.get('text', ''))
    except json.JSONDecodeError:
        continue
result = ''.join(text_parts)
if not result.strip():
    sys.stderr.write('Error: No text content found in JSON events\n')
    sys.exit(1)
sys.stdout.write(result)
"
}

# =====================================================================
# Helper: run opencode with full tool access (for Phase 2)
# --dangerously-skip-permissions auto-approves all tool calls,
# enabling the model to write src/lib.rs without interactive confirmation.
# =====================================================================
invoke_opencode_tools() {
  local model="$1"
  local prompt="$2"
  local timeout_sec="${3:-300}"

  timeout "$timeout_sec" \
    opencode run "$prompt" --model "$model" --dangerously-skip-permissions \
    > /dev/null 2>&1

  return $?
}

# =====================================================================
# Configuration
# =====================================================================
OUTPUT_DIR="${OUTPUT_DIR:-.}"
SPEC_FILE="spec.txt"
CACHE_DB="$OUTPUT_DIR/compiled_cache.json"
MAX_LOOPS=15
MODEL_NAME="opencode/deepseek-v4-flash-free"

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

ROOT_DIR="$(pwd)"

# =====================================================================
# 1. Core Sanity Checks
# =====================================================================
if ! command -v rustc &>/dev/null; then
  echo "Error: 'rustc' not in PATH."
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "Error: 'git' required for worktrees."
  exit 1
fi

if ! command -v opencode &>/dev/null; then
  echo "Error: 'opencode' not in PATH."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: Must run inside a Git repo."
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
echo " adam: Initializing Git Worktree Environment"
echo "======================================================"
echo " Creating isolated worktree at: $WORKTREE_DIR"

mkdir -p "$OUTPUT_DIR/.adam_worktrees"
git worktree add -b "$TEMP_BRANCH" "$WORKTREE_DIR" &>/dev/null

if [ $? -ne 0 ]; then
  echo "Failed to create Git worktree."
  exit 1
fi

cd "$WORKTREE_DIR" || exit 1

mkdir -p src
echo -e '[package]\nname = "mined_primitive"\nversion = "0.1.0"\nedition = "2021"' >Cargo.toml
touch "$TEMP_CODE"
touch "$ERROR_LOG"

cp /app/AGENTS.md ./AGENTS.md
cp -r /app/.opencode ./.opencode

# =====================================================================
# 3. Phase 1 — Autonomous Spec Crystallization
# =====================================================================
echo "======================================================"
echo " Phase 1: Autonomous Spec Crystallization"
echo "======================================================"

SHUFFLED_CATEGORIES=$(printf '%s\n' "${CATEGORIES[@]}" | sort -R | tr '\n' ', ' | sed 's/, $//')

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

echo "   [LLM] Generating spec via opencode (text mode)..."
GENERATED_SPEC=$(invoke_opencode_text "$MODEL_NAME" "$SPEC_PROMPT" 120)
spec_exit=$?

if [ "$spec_exit" -ne 0 ] && [ "$spec_exit" -ne 124 ]; then
  echo "   Error: opencode failed (exit $spec_exit)."
  cd "$ROOT_DIR"
  git worktree remove --force "$WORKTREE_DIR" &>/dev/null
  git branch -D "$TEMP_BRANCH" &>/dev/null
  rm -rf "$OUTPUT_DIR/.adam_worktrees"
  exit 1
fi

if [ -z "$GENERATED_SPEC" ]; then
  echo "   Error: could not extract specification from opencode output."
  cd "$ROOT_DIR"
  git worktree remove --force "$WORKTREE_DIR" &>/dev/null
  git branch -D "$TEMP_BRANCH" &>/dev/null
  rm -rf "$OUTPUT_DIR/.adam_worktrees"
  exit 1
fi

# Strip markdown wrappers
GENERATED_SPEC=$(echo "$GENERATED_SPEC" | sed -e 's/```yaml//g' -e 's/```markdown//g' -e 's/```//g')

echo "$GENERATED_SPEC" > "$SPEC_FILE"

echo "   [Spec] Autonomous specification generated and saved to $SPEC_FILE"
echo "   [Spec] Content preview (first 5 lines):"
head -n 5 "$SPEC_FILE" | sed 's/^/      /'

# =====================================================================
# 4. Phase 2 — The Pure Bash Ralph Loop
# =====================================================================
echo "======================================================"
echo " Phase 2: The Ralph Loop (Compiler Sentinel)"
echo "======================================================"

iteration=1
success=false

while [ $iteration -le $MAX_LOOPS ]; do
  echo "-> Iteration $iteration/$MAX_LOOPS"

  # Strategy: use script(1) to give opencode a pseudo-TTY, enabling
  # its write tool. The model reads spec.txt and compiler_errors.log,
  # then writes src/lib.rs directly.
  CODE_PROMPT="You are a stateless Rust code generator.

Read the specification from ./spec.txt and the compiler errors from ./compiler_errors.log.

Write a complete, compilable Rust library to ./src/lib.rs that satisfies the specification and fixes all errors.

Use the write tool to create the file. Do not wrap your response in markdown code blocks."

  echo "   [LLM] Running opencode with tool access (5min timeout)..."
  invoke_opencode_tools "$MODEL_NAME" "$CODE_PROMPT" 300
  gen_exit=$?

  if [ "$gen_exit" -eq 124 ]; then
    echo "   Warning: timed out after 5 minutes."
  fi

  # Read whatever the model wrote
  if [ ! -s "$TEMP_CODE" ]; then
    echo "   Error: src/lib.rs is empty after opencode run."
    break
  fi

  # Sentinel: Compiler Check
  echo "   [Sentinel] Compiling..."
  cargo check &> "$ERROR_LOG"
  compile_status=$?

  if [ $compile_status -eq 0 ]; then
    echo "   [Sentinel] Compile Success!"
    success=true
    break
  else
    echo "   [Sentinel] Failed. Error preview:"
    head -n 5 "$ERROR_LOG" | sed 's/^/     /'
  fi

  iteration=$((iteration + 1))
  echo "-----------------------------------------"
done

# =====================================================================
# 5. Phase 3 — Harvesting & Teardown
# =====================================================================
cd "$ROOT_DIR"

if [ "$success" = true ]; then
  echo "======================================================"
  echo " SUCCESS: Primitive verified successfully."

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cp "$WORKTREE_DIR/$SPEC_FILE" "$OUTPUT_DIR/spec_$TIMESTAMP.md"
  cp "$WORKTREE_DIR/$TEMP_CODE" "$OUTPUT_DIR/lib_$TIMESTAMP.rs"
  echo "   Spec:  $OUTPUT_DIR/spec_$TIMESTAMP.md"
  echo "   Code:  $OUTPUT_DIR/lib_$TIMESTAMP.rs"

  VERIFIED_CODE=$(cat "$WORKTREE_DIR/$TEMP_CODE")
  SPEC_RAW=$(cat "$WORKTREE_DIR/$SPEC_FILE")
  HASH=$(python3 -c "
import json, hashlib, os
code = '''$VERIFIED_CODE'''
spec = '''$SPEC_RAW'''
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
  echo "   Hash:  $HASH"
  echo "   Cache: $CACHE_DB"
else
  echo "======================================================"
  echo " FAILURE: Loop exceeded max iterations."

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cp "$WORKTREE_DIR/$SPEC_FILE" "$OUTPUT_DIR/spec_failed_$TIMESTAMP.md" 2>/dev/null || true
  cp "$WORKTREE_DIR/$TEMP_CODE" "$OUTPUT_DIR/lib_failed_$TIMESTAMP.rs" 2>/dev/null || true
  cp "$WORKTREE_DIR/$ERROR_LOG" "$OUTPUT_DIR/errors_$TIMESTAMP.log" 2>/dev/null || true
fi

echo " Cleaning up..."
git worktree remove --force "$WORKTREE_DIR" &>/dev/null
git branch -D "$TEMP_BRANCH" &>/dev/null
rm -rf "$OUTPUT_DIR/.adam_worktrees"

echo " Done."
echo "======================================================"

[ "$success" = true ] && exit 0 || exit 1
