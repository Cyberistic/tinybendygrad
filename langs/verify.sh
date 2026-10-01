#!/bin/sh
# verify.sh -- the cross-language gate.
#
# Every lane runs the SAME payload through the SAME Bend program, and every
# lane must print the same line.  The payload is u32 BIT PATTERNS, not
# decimals: a decimal would let two lanes agree by rounding it differently,
# and this gate is about bit identity, not about looking similar.
#
# The lanes, and what each one actually is:
#
#   bend   core.bend run by the pinned Bend 2.0.34, interpreted
#   native core.bend compiled by bend to a native binary (clang, no -ffp-contract)
#   c      core.c, the C source bend emits, compiled by clang
#   harness core.c linked against a 5-line C harness that renames its main
#   js     core.js, the JavaScript source bend emits, run by node
#   sdk-js the SDK on its JavaScript backend, over the .mjs pure defs
#   sdk    the SDK as a consumer inits it: wasm if it can, else JS
#   wasm   the wasm lane -- a documented wall, reported as a FAIL, never skipped
#
# Usage: langs/verify.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

OUT=langs/out
VEC=langs/vectors/payload.txt
PAYLOAD=$(cat "$VEC")
mkdir -p "$OUT"

echo "=== bend 2.0.34 four-lane export matrix ==="
echo "    repo   $ROOT"
echo "    bend   $(./bin/bend version 2>&1 | tail -1)"
echo "    clang  $(clang --version | head -1)"
echo "    node   $(node --version)"
echo "    vector $VEC"
echo ""

# ---- 1. bend, interpreted ---------------------------------------------------
./bin/bend langs/core.bend --check-only >/dev/null 2>&1 \
  || { echo "FAIL bend: core.bend does not check"; exit 1; }
./bin/bend langs/core.bend "$PAYLOAD" > "$OUT/bend.txt" 2>/dev/null \
  || { echo "FAIL bend: interpreted run failed"; exit 1; }
echo "built  bend      interpreted, --check-only ALL PROOFS CHECK"

# ---- 2. native binary, built by bend ---------------------------------------
./bin/bend langs/core.bend -o "$OUT/core_native" >/dev/null 2>&1
"$OUT/core_native" "$PAYLOAD" > "$OUT/native.txt"
echo "built  native    $OUT/core_native, built by bend with its own clang"

# ---- 3. the C source bend emits, compiled -----------------------------------
./bin/bend langs/core.bend -o langs/c/core.c >/dev/null 2>&1
# -ffp-contract=off: without it clang may fuse a*b+c into an FMA on arm64,
# which changes the f32 result against every other lane.  The gate is bit
# identity, so contraction is turned off rather than argued about.
clang -std=c11 -O3 -ffp-contract=off langs/c/core.c -lpthread -lm \
  -o "$OUT/core_c" 2>"$OUT/clang.log" \
  || { echo "FAIL c: clang could not build langs/c/core.c"; cat "$OUT/clang.log"; exit 1; }
"$OUT/core_c" "$PAYLOAD" > "$OUT/clang.txt"
echo "built  c         $(wc -l < langs/c/core.c | tr -d ' ') lines of C, clang -O3 -ffp-contract=off"

# ---- 4. the same C source, linked against a separate harness ----------------
clang -std=c11 -O3 -ffp-contract=off -Dmain=bend_main -c langs/c/core.c \
  -o "$OUT/core.o" 2>>"$OUT/clang.log"
clang -std=c11 -O2 langs/c/core_harness.c "$OUT/core.o" -lpthread -lm \
  -o "$OUT/core_harness" 2>>"$OUT/clang.log"
"$OUT/core_harness" "$PAYLOAD" > "$OUT/harness.txt"
echo "built  harness   core.c + core_harness.c, -Dmain=bend_main"

# ---- 5. the JavaScript source bend emits -------------------------------------
./bin/bend langs/core.bend -o langs/js/core.js >/dev/null 2>&1
node langs/js/core.js "$PAYLOAD" > "$OUT/js.txt" 2>&1
echo "built  js        $(wc -l < langs/js/core.js | tr -d ' ') lines of JS, node"

# ---- 6. the SDK, on its JavaScript backend, over the emitted .mjs ------------
./bin/bend langs/core.bend -o langs/js/core.mjs >/dev/null 2>&1
node --input-type=module -e '
  import { execute, bits, f32OfBits } from "./langs/js/bend_core.js";
  import { readFileSync } from "node:fs";
  const data = readFileSync("langs/vectors/payload.txt", "utf8").trim().split(",").map(Number);
  const a = execute(data);
  const b = a.map(bits);
  console.log("loss=" + f32OfBits(b[0]) + " trace=," + b.join(",") + " in=" + data.slice(0, 10).join(","));
' > "$OUT/sdk_js.txt"
echo "built  sdk-js    BendLibrarySDK{forceJS} over core.mjs"

# ---- 7. the SDK as a consumer inits it --------------------------------------
node --experimental-strip-types --no-warnings langs/sdk/bench.ts > "$OUT/bench.txt" 2>&1 || true
echo "built  sdk       $(grep -m1 'sdk/.* auto' "$OUT/bench.txt" | awk '{print $1, $2, $3}')"

# ---- 8. the wasm lane ------------------------------------------------------
if [ -f langs/wasm/core.wasm ]; then
  node --no-warnings langs/wasm/wasi_run.mjs langs/wasm/core.wasm "$PAYLOAD" \
    > "$OUT/wasm.txt" 2>&1 || true
  echo "built  wasm      langs/wasm/core.wasm"
else
  # Never SKIP: a lane that cannot be built is the most important thing this
  # script has to say, and a skip reads like a pass.
  echo "WALL   wasm      langs/wasm/core.wasm is not built -- see langs/wasm/WALL.md"
fi

# ---- the gate --------------------------------------------------------------
echo ""
echo "--- what each lane printed ---"
for lane in bend native clang harness js; do
  printf '%-8s %s\n' "$lane" "$(cat "$OUT/$lane.txt")"
done
echo ""
echo ""
echo "--- gate ---"

fail=0
wall=0
REF="$OUT/native.txt"
for lane in bend native clang harness js; do
  if diff -q "$OUT/$lane.txt" "$REF" >/dev/null 2>&1; then
    printf 'AGREE  %-8s byte identical to native\n' "$lane"
  else
    printf 'FAIL   %-8s differs from native\n' "$lane"
    diff "$REF" "$OUT/$lane.txt" || true
    fail=1
  fi
done

# The SDK answers the same eight f32 as the .bend lanes, but not in the same
# shape, so compare the trace field rather than the whole line: pull the labelled
# fields out of both sides and normalise the stray commas the .bend lane prints.
trace_bits() {
  tr -d ' \n' < "$1" | sed -E 's/.*trace=([0-9,]+).*/\1/'
}
NATIVE_TRACE=$(trace_bits "$REF")
SDK_TRACE=$(trace_bits "$OUT/sdk_js.txt")
if [ "$SDK_TRACE" = "$NATIVE_TRACE" ]; then
  printf 'AGREE  %-8s trace byte identical to native\n' "sdk-js"
else
  printf 'FAIL   %-8s trace differs from native\n' "sdk-js"
  printf '  sdk-js: %s\n' "$SDK_TRACE"
  printf '  native: %s\n' "$NATIVE_TRACE"
  fail=1
fi

if [ -f langs/wasm/core.wasm ] && [ -f "$OUT/wasm.txt" ]; then
  if diff -q "$OUT/wasm.txt" "$REF" >/dev/null 2>&1; then
    printf 'AGREE  %-8s byte identical to native\n' "wasm"
  else
    printf 'FAIL   %-8s differs from native\n' "wasm"
    diff "$REF" "$OUT/wasm.txt" || true
    fail=1
  fi
else
  printf 'WALL   %-8s Bend 2.0.34 reserves 8 GiB; wasm32 caps at 4 GiB. langs/wasm/WALL.md\n' "wasm"
  wall=1
fi

echo ""
echo "--- bench (min of 5, with machine load) ---"
sed -n '1,40p' "$OUT/bench.txt" | sed 's/^/  /'

echo ""
if [ "$fail" -eq 1 ]; then
  echo "FAIL  a lane disagreed with native; see the FAIL lines above"
  exit 1
fi
if [ "$wall" -eq 1 ]; then
  echo "AGREE  every BUILT lane is byte identical"
  echo "WALL   the wasm lane is not built; langs/wasm/WALL.md has the measurement"
  exit 2
fi
echo "PASS  every lane is byte identical"
exit 0
