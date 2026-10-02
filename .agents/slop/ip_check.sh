#!/usr/bin/env bash
# The three-lane check for tinybendygrad/runtime/support/am/ip.bend.
#
#   1. the INTERPRETED lane           (./bin/bend FILE)
#   2. the NATIVE lane                (./bin/bend FILE -o BIN && BIN)
#   3. the CPYTHON ORACLE             (.agents/slop/ip_oracle.py)
#
# Every expectation in the oracle is produced by CALLING CPython -- see the
# header of ip_oracle.py. Nothing there is typed from memory.
set -uo pipefail
cd "$(dirname "$0")/../.."
F=tinybendygrad/runtime/support/am/ip.bend
TMP="${TMPDIR:-/tmp}/ip_gate.$$"
mkdir -p "$TMP"

echo "=== check ==="
./bin/bend "$F" --check-only

./bin/bend "$F" > "$TMP/interp.txt" 2>&1 || { echo "INTERPRETED LANE FAILED"; cat "$TMP/interp.txt"; exit 1; }
./bin/bend "$F" -o "$TMP/native" >/dev/null 2>&1 || { echo "NATIVE COMPILE FAILED"; exit 1; }
"$TMP/native" > "$TMP/native.txt" 2>&1 || { echo "NATIVE RUN FAILED"; cat "$TMP/native.txt"; exit 1; }
python3 .agents/slop/ip_oracle.py > "$TMP/oracle.txt" 2>&1 || { echo "ORACLE FAILED"; tail -5 "$TMP/oracle.txt"; exit 1; }

echo "=== rows: interp $(wc -l < "$TMP/interp.txt") native $(wc -l < "$TMP/native.txt") oracle $(wc -l < "$TMP/oracle.txt") ==="

echo "=== lane diff (interp vs native) ==="
if diff -q "$TMP/interp.txt" "$TMP/native.txt" >/dev/null; then echo "IDENTICAL"; else diff "$TMP/interp.txt" "$TMP/native.txt" | head -40; fi

echo "=== oracle diff (interp vs cpython) ==="
python3 - "$TMP/interp.txt" "$TMP/oracle.txt" <<'PY'
import sys
def load(p):
  d = {}
  for line in open(p):
    line = line.rstrip('\n')
    if '=' not in line: continue
    k, v = line.split('=', 1)
    d.setdefault(k, []).append(v)
  return d
a, b = load(sys.argv[1]), load(sys.argv[2])
bad = 0
for k in sorted(set(a) | set(b)):
  if k not in a: print(f"ORACLE-ONLY {k}"); bad += 1
  elif k not in b: print(f"GATE-ONLY   {k} = {a[k]}"); bad += 1
  elif a[k] != b[k]:
    print(f"DISAGREE    {k}\n  gate   = {a[k]}\n  oracle = {b[k]}"); bad += 1
print(f"{bad} disagreements over {len(set(a) | set(b))} row names")
sys.exit(1 if bad else 0)
PY
RC=$?
echo "=== files: $TMP ==="
exit $RC