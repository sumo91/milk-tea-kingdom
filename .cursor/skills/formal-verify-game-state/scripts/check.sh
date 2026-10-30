#!/usr/bin/env bash
# One-command formal check for GameState economy invariants.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SKILL_DIR/../../.." && pwd)
MODEL_DIR="$SKILL_DIR/models"
OUT_DIR="${FORMAL_OUT:-$SKILL_DIR/artifacts/last-run}"
mkdir -p "$OUT_DIR"

JAVA_BIN="${JAVA_BIN:-}"
if [[ -z "$JAVA_BIN" ]]; then
  if [[ -x /home/box/tools/jdk-21.0.13+9-jre/bin/java ]]; then
    JAVA_BIN=/home/box/tools/jdk-21.0.13+9-jre/bin/java
  elif command -v java >/dev/null 2>&1; then
    JAVA_BIN=$(command -v java)
  fi
fi
TLA_JAR="${TLA_JAR:-/home/box/tools/tla2tools.jar}"
[[ -f "$TLA_JAR" ]] || TLA_JAR=/tmp/tla2tools.jar

if [[ -z "${JAVA_BIN:-}" ]] || ! "$JAVA_BIN" -version >/dev/null 2>&1; then
  echo "FAIL: java not found. Install a JRE 21+ and set JAVA_BIN." >&2
  exit 2
fi
if [[ ! -f "$TLA_JAR" ]]; then
  echo "FAIL: tla2tools.jar not found at TLA_JAR=$TLA_JAR" >&2
  exit 2
fi

cd "$REPO_ROOT"
echo "== sync_gate (scripts/game_state.gd ↔ model assumptions) =="
python3 "$SCRIPT_DIR/sync_gate.py"

echo "== TLC GameStateEconomy =="
set +e
"$JAVA_BIN" -XX:+UseParallelGC -cp "$TLA_JAR" tlc2.TLC \
  -config "$MODEL_DIR/GameStateEconomy.cfg" \
  -workers auto \
  -cleanup \
  -metadir "$OUT_DIR/states" \
  "$MODEL_DIR/GameStateEconomy.tla" 2>&1 | tee "$OUT_DIR/tlc.out"
TLC_EC=${PIPESTATUS[0]}
set -e

# Drop TLC trace specs if written next to the model
rm -f "$MODEL_DIR"/GameStateEconomy_TTrace_*.tla "$MODEL_DIR"/GameStateEconomy_TTrace_*.cfg "$MODEL_DIR"/GameStateEconomy_TTrace_*.bin 2>/dev/null || true

if grep -q "Error: Invariant" "$OUT_DIR/tlc.out"; then
  echo ""
  echo "INVARIANT violated. Read the counterexample with pstack /statechart"
  echo "(load that skill — do not copy its CLI flags from memory)."
  echo "TLC log: $OUT_DIR/tlc.out"
  exit 1
fi
if grep -q "Fingerprint collision" "$OUT_DIR/tlc.out"; then
  echo "FAIL: TLC fingerprint collision" >&2
  exit 1
fi
if [[ "$TLC_EC" -ne 0 ]]; then
  echo "FAIL: TLC exit $TLC_EC — see $OUT_DIR/tlc.out" >&2
  exit "$TLC_EC"
fi
if ! grep -q "Model checking completed. No error has been found." "$OUT_DIR/tlc.out"; then
  echo "FAIL: TLC finished without success banner — see $OUT_DIR/tlc.out" >&2
  exit 1
fi
echo "OK formal-verify-game-state"
exit 0
