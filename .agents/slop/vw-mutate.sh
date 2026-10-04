#!/bin/sh
# vw-mutate.sh -- prove `dv_where_walk` DETECTS duplication rather than merely describing a
# green walk. Run TWICE per step; a 0-row bend run is indistinguishable from "not started"
# (bend's machine stack overflows ~1 run in 20), so every step reports its line count.
#
# M1 REVERTS THE FIX. `vz_step.seen` is the third branch `ops.py:302` has and the file lacked;
# it is replaced by the two-branch shape the file shipped with, where `seen` is CPython's
# `visited` flag and the cache membership is never consulted. EXPECTED: `dv_where_walk` and
# `dv_where_cs` both go red and `dv_where_walk` NAMES `Ops.PARAM` twice.
#
# M2 IS THE OPPOSITE BLIND SPOT and it is the row this whole exercise turned on: `dv_where` is
# the only fixture with a REPEATED node, so a mutation of the fixture's SHARING cannot be seen
# by any other row. Reported as a blind spot with its denominator, not closed with a fixture.
set -e
cd "$(dirname "$0")/../.."
F=tinybendygrad/uop/validate.bend
OUT=.agents/slop/vw-mut-baseline.txt

run() { DEV=NULL ./bin/bend "$F" > "$1" 2>/dev/null; echo "  $2: $(wc -l < "$1" | tr -d ' ') rows"; }

echo "== baseline =="
run "$OUT" baseline
grep -E "^dv_where_walk|^dv_where_cs" "$OUT"

cp "$F" "$F.vwfrozen"
# NO trap: this script restores explicitly after each step, and a trap that fires on an
# already-restored file is a second `mv` of a name that is gone.

echo "== M1: revert vz_step.seen to the two-branch shape =="
python3 - <<'PY'
import pathlib
p = pathlib.Path("tinybendygrad/uop/validate.bend")
s = p.read_text()
old = "    case False{}: vz_step.seen(cache, n, ar, fx, rest, cache)"
new = "    case False{}: vz_step.fresh(ar, fx, n, rest, cache)"
assert old in s, "M1 anchor moved"
p.write_text(s.replace(old, new, 1))
PY
run .agents/slop/vw-mut-M1.txt M1
grep -E "^dv_where_walk|^dv_where_cs" .agents/slop/vw-mut-M1.txt
mv "$F.vwfrozen" "$F"

echo "== M2: nothing mutated; the CONTROL run, to show the file was restored =="
run .agents/slop/vw-mut-M2.txt control
grep -E "^dv_where_walk|^dv_where_cs" .agents/slop/vw-mut-M2.txt
cmp "$OUT" .agents/slop/vw-mut-M2.txt && echo "  control == baseline: the revert was undone"
test -e "$F.vwfrozen" && echo "  LEFTOVER FROZEN COPY" || echo "  no leftover frozen copy"