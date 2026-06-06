#!/usr/bin/env bash
set -o pipefail

# =====================================================================
# Compiled AI — Loop Daemon
# Continuously generates specs, mines implementations via the Ralph Loop,
# and harvests verified artifacts into the vector database.
#
# Architecture:
#   Outer Loop (this script)  →  Per-iteration Git Worktree
#                                ↓
#                           Git Worktree (isolated)
#                                ↓
#   ┌─────────────┐         ┌──────────────┐         ┌───────────────┐
#   │  Phase 1    │ ──────► │  Phase 2     │ ──────► │   Phase 3     │
#   │ Spec Gen    │         │ Ralph Loop   │         │ Harvest +     │
#   │ (LLM text)  │         │ (compile OK) │         │ Qdrant Push   │
#   └─────────────┘         └──────────────┘         └───────────────┘
#
# On failure: worktree wiped, loop restarts with fresh intent.
# On SIGTERM: finish current iteration, clean up, exit gracefully.
# =====================================================================

# =====================================================================
# Global Configuration
# =====================================================================
OUTPUT_DIR="${OUTPUT_DIR:-.}"
SPEC_FILE="spec.txt"
ERROR_LOG="compiler_errors.log"
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

# Sentinel manifest components
SENTINEL_IDENTITY="rustc"
SENTINEL_VERSION=""
TARGET_TRIPLE=""
CARGO_VERSION=""

# Graceful shutdown flag
SHUTDOWN_REQUESTED=false

# =====================================================================
# Signal Traps
# =====================================================================
trap 'echo "[SIGTERM/SIGINT] Graceful shutdown requested. Finishing current iteration..."; SHUTDOWN_REQUESTED=true' SIGTERM SIGINT

# =====================================================================
# Helpers: opencode invocation
# =====================================================================
invoke_opencode_text() {
  local model="$1"
  local prompt="$2"
  local timeout_sec="${3:-120}"

  timeout "$timeout_sec" \
    opencode run "$prompt" --model "$model" --format json 2>&1 |
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

invoke_opencode_tools() {
  local model="$1"
  local prompt="$2"
  local timeout_sec="${3:-300}"

  timeout "$timeout_sec" \
    opencode run "$prompt" --model "$model" --dangerously-skip-permissions \
    >/dev/null 2>&1

  return $?
}

# =====================================================================
# Helper: build sentinel manifest JSON with optional ctx quality scores
# =====================================================================
build_manifest() {
  local ast_hash="$1"
  # Populate versions once if empty
  if [ -z "$SENTINEL_VERSION" ]; then
    SENTINEL_VERSION="$(rustc --version 2>/dev/null || echo 'unknown')"
    CARGO_VERSION="$(cargo --version 2>/dev/null || echo 'unknown')"
    TARGET_TRIPLE="$(rustc --version --verbose 2>/dev/null | grep 'host:' | cut -d' ' -f2 || echo 'unknown')"
  fi

  local optimization_level="dev"
  if [ -f Cargo.toml ]; then
    if grep -q '\[profile.release\]' Cargo.toml 2>/dev/null; then
      optimization_level="release"
    fi
  fi

  # Base manifest
  cat > manifest.json <<MANIFEST
{
  "sentinel_identity": "$SENTINEL_IDENTITY",
  "sentinel_version": "$SENTINEL_VERSION",
  "cargo_version": "$CARGO_VERSION",
  "target_triple": "$TARGET_TRIPLE",
  "optimization_level": "$optimization_level",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFEST
}

# =====================================================================
# Helper: enrich manifest with ctx quality scores
# =====================================================================
enrich_manifest_with_ctx() {
  if ! command -v ctx >/dev/null 2>&1; then
    echo "  [Analyze] ctx not available, skipping quality analysis."
    return
  fi

  echo "  [Analyze] Indexing codebase with ctx..."
  if ctx index > .ctx_index.log 2>&1; then
    echo "  [Analyze] Index complete."
  else
    echo "  [Analyze] ctx index failed (likely non-Rust or unsupported). Skipping."
    return
  fi

  echo "  [Analyze] Running audit..."
  local audit_score="null"
  if ctx audit --output json > .ctx_audit.json 2> .ctx_audit.err; then
    audit_score=$(python3 -c "
import json, sys
try:
    with open('.ctx_audit.json') as f:
        data = json.load(f)
    print(data.get('overall_score', 'null'))
except Exception:
    print('null')
" 2>/dev/null)
  fi
  if [ -z "$audit_score" ] || [ "$audit_score" = "null" ]; then
    audit_score="null"
  fi
  echo "  [Analyze] Audit score: $audit_score"

  echo "  [Analyze] Running complexity analysis..."
  local max_complexity="null"
  local symbol_count="null"
  if ctx complexity --output json > .ctx_complexity.json 2> .ctx_complexity.err; then
    max_complexity=$(python3 -c "
import json, sys
try:
    with open('.ctx_complexity.json') as f:
        data = json.load(f)
    funcs = data.get('high_complexity_functions', [])
    if funcs:
        print(max(f.get('complexity_score', 0) for f in funcs))
    else:
        print('null')
except Exception:
    print('null')
" 2>/dev/null)

    symbol_count=$(python3 -c "
import json, sys
try:
    with open('.ctx_complexity.json') as f:
        data = json.load(f)
    print(data.get('total_functions', 'null'))
except Exception:
    print('null')
" 2>/dev/null)
  fi
  if [ -z "$max_complexity" ] || [ "$max_complexity" = "null" ]; then
    max_complexity="null"
  fi
  if [ -z "$symbol_count" ] || [ "$symbol_count" = "null" ]; then
    symbol_count="null"
  fi
  echo "  [Analyze] Max complexity: $max_complexity, Symbols: $symbol_count"

  # Merge into manifest
  python3 -c "
import json
with open('manifest.json', 'r') as f:
    manifest = json.load(f)

manifest['ctx_audit_score'] = ${audit_score:-null}
manifest['ctx_max_complexity'] = ${max_complexity:-null}
manifest['ctx_symbol_count'] = ${symbol_count:-null}

with open('manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
" 2>/dev/null

  echo "  [Analyze] Manifest enriched with ctx quality metrics."
}
MANIFEST
}

# =====================================================================
# Helper: sentinel manifest → JSON output for logging
# =====================================================================
read_manifest() {
  cat manifest.json 2>/dev/null || echo '{}'
}

# =====================================================================
# Sanity Checks
# =====================================================================
command -v rustc >/dev/null || {
  echo "Error: rustc not in PATH."
  exit 1
}
command -v git >/dev/null || {
  echo "Error: git not in PATH."
  exit 1
}
command -v opencode >/dev/null || {
  echo "Error: opencode not in PATH."
  exit 1
}
command -v harvest >/dev/null || {
  echo "Error: harvest not in PATH."
  exit 1
}
# ctx is optional but nice to have
if command -v ctx >/dev/null; then
  echo "[Sanity] ctx (code intelligence) available."
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Must run inside a Git repo."
  exit 1
fi

echo "=========================================="
echo " Compiled AI — Loop Daemon Started"
echo " Model:  $MODEL_NAME"
echo " Output: $OUTPUT_DIR"
echo "=========================================="
echo ""
echo "[Daemon] Press Ctrl+C once to initiate graceful shutdown"
echo "         (current cycle will finish before exiting)."
echo ""

# =====================================================================
# Main Loop
# =====================================================================
iteration_counter=0
while :; do
  iteration_counter=$((iteration_counter + 1))
  echo "=========================================="
  echo " Cycle #$iteration_counter"
  echo "=========================================="

  if [ "$SHUTDOWN_REQUESTED" = true ]; then
    echo "[Shutdown] Graceful exit after cycle $((iteration_counter - 1))."
    exit 0
  fi

  # ------------------------------------------------------------------
  # 1. Worktree Provisioning (Tabula Rasa)
  # ------------------------------------------------------------------
  RUN_ID=$(date +%s)_$RANDOM
  WORKTREE_DIR="$OUTPUT_DIR/.adam_worktrees/wt_$RUN_ID"
  TEMP_BRANCH="adam-temp-$RUN_ID"

  echo "[Worktree] Creating isolated worktree: $WORKTREE_DIR"

  mkdir -p "$OUTPUT_DIR/.adam_worktrees"
  if ! git worktree add -b "$TEMP_BRANCH" "$WORKTREE_DIR" >/dev/null 2>&1; then
    echo "[Worktree] Failed to create. Sleeping 5s and retrying..."
    sleep 5
    continue
  fi

  cd "$WORKTREE_DIR" || {
    echo "[Worktree] cd failed. Retrying."
    sleep 5
    continue
  }

  mkdir -p src
  echo -e '[package]\nname = "mined_primitive"\nversion = "0.1.0"\nedition = "2021"' >Cargo.toml
  touch src/lib.rs
  touch "$ERROR_LOG"

  cp /app/AGENTS.md ./AGENTS.md
  cp -r /app/.opencode ./.opencode

  # ------------------------------------------------------------------
  # 2. Phase 1 — Autonomous Spec Crystallization
  # ------------------------------------------------------------------
  echo "[Phase 1] Generating autonomous specification..."

  SHUFFLED_CATEGORIES=$(printf '%s\n' "${CATEGORIES[@]}" | sort -R | tr '\n' ', ' | sed 's/, $//')

  SPEC_PROMPT="You are the Autonomous Rust Specification Crystallization Engine.
Your task is to invent a completely new Rust library primitive and crystallize it into a formal specification.
CRITICAL INSTRUCTIONS:
1. Pick ONE category at random from: $SHUFFLED_CATEGORIES
2. Within that category, invent a specific, atomic, single-purpose primitive. Think building blocks, not monoliths.
3. Default to 'low' complexity. The primitive should be understandable in 30 seconds and solve exactly ONE problem.
4. Only use 'medium' or 'high' complexity when the category strictly demands it (e.g., lock-free concurrency).
5. Generate a complete specification document conforming to AGENTS.md format.
6. The specification MUST use RFC 2119 key words for all requirements.
7. The specification MUST include YAML frontmatter with keys: intent, category, complexity, rfc2119_level.
8. The specification MUST contain these three sections in order: Structural Contract, Behavioral Contract, Conformance Tests.
9. Output ONLY the raw specification document. No markdown wrappers. No preamble. No apologies.
10. The first line of your output MUST be '---'."

  GENERATED_SPEC=$(invoke_opencode_text "$MODEL_NAME" "$SPEC_PROMPT" 120)
  spec_exit=$?

  if [ "$spec_exit" -ne 0 ] && [ "$spec_exit" -ne 124 ]; then
    echo "[Phase 1] Error: opencode failed (exit $spec_exit). Wiping worktree."
    cd "$ROOT_DIR"
    git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1
    git branch -D "$TEMP_BRANCH" >/dev/null 2>&1
    rm -rf "$OUTPUT_DIR/.adam_worktrees"
    sleep 5
    continue
  fi

  if [ -z "$GENERATED_SPEC" ]; then
    echo "[Phase 1] Error: empty spec. Wiping worktree."
    cd "$ROOT_DIR"
    git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1
    git branch -D "$TEMP_BRANCH" >/dev/null 2>&1
    rm -rf "$OUTPUT_DIR/.adam_worktrees"
    sleep 5
    continue
  fi

  # Strip markdown wrappers
  GENERATED_SPEC=$(echo "$GENERATED_SPEC" | sed -e 's/```yaml//g' -e 's/```markdown//g' -e 's/```//g')
  echo "$GENERATED_SPEC" >"$SPEC_FILE"

  echo "[Phase 1] Spec saved. Preview:"
  head -n 5 "$SPEC_FILE" | sed 's/^/  /'

  # ------------------------------------------------------------------
  # 3. Phase 2 — The Ralph Loop
  # ------------------------------------------------------------------
  echo "[Phase 2] Entering Ralph Loop (max $MAX_LOOPS iterations)..."

  loop_iter=1
  compile_ok=false

  while [ $loop_iter -le $MAX_LOOPS ]; do
    echo "  -> Ralph iteration $loop_iter/$MAX_LOOPS"

    CODE_PROMPT="You are a stateless Rust code generator.
Read the specification from ./spec.txt and the compiler errors from ./compiler_errors.log.
Write a complete, compilable Rust library to ./src/lib.rs that satisfies the specification and fixes all errors.
Use the write tool to create the file. Do not wrap your response in markdown code blocks."

    invoke_opencode_tools "$MODEL_NAME" "$CODE_PROMPT" 300
    gen_exit=$?

    if [ "$gen_exit" -eq 124 ]; then
      echo "  Warning: timed out after 5 minutes."
    fi

    if [ ! -s src/lib.rs ]; then
      echo "  Error: src/lib.rs is empty."
      break
    fi

    # Sentinel
    echo "  [Sentinel] Compiling..."
    cargo check >"$ERROR_LOG" 2>&1
    compile_status=$?

    if [ $compile_status -eq 0 ]; then
      echo "  [Sentinel] Compile Success!"
      compile_ok=true
      break
    else
      echo "  [Sentinel] Failed. Errors:"
      head -n 5 "$ERROR_LOG" | sed 's/^/    /'
    fi

    loop_iter=$((loop_iter + 1))
  done

  if [ "$compile_ok" != true ]; then
    echo "[Phase 2] Ralph Loop failed after $MAX_LOOPS iterations."
    echo "          Spec discarded. No artifacts harvested."
    cd "$ROOT_DIR"
    git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1
    git branch -D "$TEMP_BRANCH" >/dev/null 2>&1
    rm -rf "$OUTPUT_DIR/.adam_worktrees"
    sleep 5
    continue
  fi

  # ------------------------------------------------------------------
  # 4. Phase 3 — Harvest: AST Hash, Manifest, Embedding, Qdrant Push
  # ------------------------------------------------------------------
  echo "[Phase 3] Harvesting verified artifact..."

  # 4a. AST Hash
  echo "  [Harvest] Computing AST semantic hash..."
  AST_HASH=$(harvest src/lib.rs)
  if [ $? -ne 0 ] || [ -z "$AST_HASH" ]; then
    echo "  [Harvest] Failed to compute AST hash. Discarding."
    cd "$ROOT_DIR"
    git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1
    git branch -D "$TEMP_BRANCH" >/dev/null 2>&1
    rm -rf "$OUTPUT_DIR/.adam_worktrees"
    sleep 5
    continue
  fi
  echo "  [Harvest] AST hash: $AST_HASH"

  # 4b. Sentinel Manifest
  build_manifest "$AST_HASH"
  echo "  [Harvest] Manifest built."
  
  # 4c. Code Quality Analysis (ctx)
  enrich_manifest_with_ctx
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cp "$SPEC_FILE" "$OUTPUT_DIR/spec_$TIMESTAMP.md"
  cp src/lib.rs "$OUTPUT_DIR/lib_$TIMESTAMP.rs"

  # 4d. Embed + Push to Qdrant
  echo "  [Harvest] Embedding spec and pushing to vector DB..."
  if python3 /app/scripts/embed_and_push.py \
    --spec "$SPEC_FILE" \
    --code src/lib.rs \
    --hash "$AST_HASH" \
    --manifest manifest.json \
    --model "$MODEL_NAME" 2>&1; then
    echo "  [Harvest] ✅ Pushed to Qdrant."
  else
    echo "  [Harvest] ⚠️  Qdrant push failed (vector DB may be down)."
    echo "             Local files still preserved at:"
    echo "               Spec: $OUTPUT_DIR/spec_$TIMESTAMP.md"
    echo "               Code: $OUTPUT_DIR/lib_$TIMESTAMP.rs"
  fi

  # ------------------------------------------------------------------
  # 5. Cleanup — wipe worktree, return to root
  # ------------------------------------------------------------------
  echo "[Cleanup] Destroying worktree..."
  cd "$ROOT_DIR"
  git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1
  git branch -D "$TEMP_BRANCH" >/dev/null 2>&1
  rm -rf "$OUTPUT_DIR/.adam_worktrees"

  echo "[Cycle] Finished. Sleeping 5 seconds before next intent..."
  echo ""
  sleep 5
done
