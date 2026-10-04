#!/bin/sh
# ops501-plant.sh -- PLANT one disagreement in a STAGED copy of ops.bend and prove the
# gate goes red AND NAMES THE ROW.
#
#   sh .agents/slop/ops501-plant.sh @-      # at rest: already red, so plant nothing
#   sh .agents/slop/ops501-plant.sh @       # green: expect rc 0 clean, rc 1 planted
#
# A GATE NEVER SEEN RED IS NOT KNOWN TO WORK. ops-501-gate.sh was red at rest only
# because the PORT was missing 19 rows -- a MISSING-ROW failure, never a WRONG-VALUE one.
# So this drops one op from `UOp.getaddr.op`'s nine-op ladder, which is a wrong-VALUE
# failure on a row that EXISTS on both sides, and checks two things the at-rest failure
# could not check: the gate says DISAGREE, and it says WHICH row.
#
# WHY A STAGED COPY. ops.bend is another unit's file and is being edited right now.
# ops-501-mutate.py used to write it in place (line 168 `OPS.write_text(...)`), which is
# "patching the live tree from a harness" -- a kill between the read and the write
# destroys their edit. Nothing here writes tinybendygrad/uop/ops.bend.
set -e
cd "$(dirname "$0")/../.."

REV=${1:-@}
F=.agents/slop/oracles/ops501
STAGE=tinybendygrad/uop/ops-PLANT-$$.bend
trap 'rm -f "$STAGE"' EXIT INT TERM

jj file show -r "$REV" tinybendygrad/uop/ops.bend > "$STAGE"
live=$(md5 -q tinybendygrad/uop/ops.bend)
before=$(md5 -q "$STAGE")
echo "== rev=$REV  live ops.bend=$live  staged=$before"

echo "== 1. CLEAN"
TG_TREE=.agents/slop/opstree .venv/bin/python .agents/slop/ops-501-oracle.py | grep '^s5_' > "$F-plant-py.txt"
./bin/bend "$STAGE" | grep '^s5_' > "$F-plant-clean.txt"
rc_clean=0
.venv/bin/python .agents/slop/ops501-agree.py "$F-plant-py.txt" "$F-plant-clean.txt" || rc_clean=$?
echo "clean rc=$rc_clean (0 = AGREE)"

echo "== 2. PLANTED: one op out of UOp.getaddr.op's nine-op ladder"
python3 - "$STAGE" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
# `case OpsPARAM{}: True{}` alone occurs FOUR times in ops.bend, so an unanchored
# replace is ambiguous and would silently edit a different ladder. Three lines, once.
old = ("    case OpsMSELECT{}: True{}\n    case OpsPARAM{}: True{}\n"
       "    case OpsLINEAR{}: True{}\n")
new = "    case OpsMSELECT{}: True{}\n    case OpsLINEAR{}: True{}\n"
assert t.count(old) == 1, f"pattern count {t.count(old)}, wanted 1"
p.write_text(t.replace(old, new, 1))
PY
./bin/bend "$STAGE" | grep '^s5_' > "$F-plant-bad.txt" || true
rc_plant=0
.venv/bin/python .agents/slop/ops501-agree.py "$F-plant-py.txt" "$F-plant-bad.txt" > "$F-plant-report.txt" || rc_plant=$?
cat "$F-plant-report.txt"
echo "planted rc=$rc_plant (1 = DISAGREE)"
grep -c . "$F-plant-bad.txt" | sed 's/^/planted lane rows: /'

echo "== 3. RESTORE"
cp "$STAGE" /dev/null 2>/dev/null || true
rm -f "$STAGE"
after=$(md5 -q tinybendygrad/uop/ops.bend)
echo "live ops.bend after: $after  $([ "$live" = "$after" ] && echo IDENTICAL || echo CHANGED)"
[ "$live" = "$after" ] || { echo "ops501-plant: THE LIVE FILE MOVED -- someone else edited it" >&2; exit 1; }
[ "$rc_clean" = 0 ] && [ "$rc_plant" = 1 ] && { echo "CONTROL PASS: clean rc=0, planted rc=1"; exit 0; }
echo "CONTROL FAIL: clean rc=$rc_clean planted rc=$rc_plant" >&2
exit 1