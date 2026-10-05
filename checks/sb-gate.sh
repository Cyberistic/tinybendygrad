#!/bin/sh
# The gate for the rule-body unit. THREE LANES, and the comparison is on whole
# `name=value` LINES -- never on row NAMES (agent-core.md: a name-comparing
# harness reported 0 for all 30 mutations in one unit and 0 for all 68 in
# another).
#
#   lane bd   ./bin/bend tinybendygrad/schedule/__init__.bend
#   lane bn   the native build, if the tree has one
#   lane py   .venv/bin/python .agents/slop/schedule-bodies/sb-oracle.py
#
# DENOMINATOR: the number of `name=value` rows the port emits. It is PRINTED on
# every run, and it is printed BEFORE any verdict, because a gate whose
# denominator is unknown cannot be read either way.
#
# ---------------------------------------------------------------------------
# WHY EVERY INPUT IS ASSERTED, WHICH IS THE WHOLE OF THIS REVISION.
# This gate used to `cd "$(dirname "$0")/../../.."` -- three levels up from
# checks/, i.e. /Users/cyberistic/src, a directory OUTSIDE the repo. Every
# relative path after that line therefore named a file that does not exist, the
# redirect on the bend line failed, `|| true` swallowed it, and `--substrate`
# still printed `helpers= ops=` and exited 0. MEASURED before the fix:
#
#     $ sh checks/sb-gate.sh --substrate ; echo $?
#     helpers= ops=
#     0
#
# A gate that exits 0 having run nothing is WORSE THAN NO GATE, because it is
# trusted. gates/README.md records four ways a shell gate lied here; this is a
# fifth, and it arrived by the same road as shape #1 with the `cd` moved into it.
# The three rules below are what close it:
#
#   1. `cd` to the repo root and PROVE it. A cd that lands outside is exit 3.
#   2. Every input is asserted to EXIST before it is used. A missing baseline is
#      NOT a passing baseline: it is exit 3 and nothing else. The old
#      `[ -f $BASE ]` had no else arm, so the regression floor was skipped in
#      silence whenever the baseline was gone -- which it now is.
#   3. No `|| true` on a producer. The bend exit status is captured and
#      separated from the row census, so "bend died" and "bend emitted no rows"
#      are different findings and neither is green.
#
# This gate gates NOTHING at present and says so: sb-oracle.py, sb-diff.py and
# BEFORE-rows.txt are all absent from .agents/slop/schedule-bodies/. Exit 3 with
# the list is the correct verdict for that state, not a failure to fix here --
# inventing an oracle to make the gate run would fabricate its own reference.
set -eu
cd "$(dirname "$0")/.."

D=.agents/slop/schedule-bodies
PORT=tinybendygrad/schedule/__init__.bend
BEND=.venv/bin/python\ checks/bounded.py\ --seconds\ 900\ --mb\ 2048\ --\ ./bin/bend
BASE=$D/BEFORE-rows.txt
ORACLE=$D/sb-oracle.py
DIFFER=$D/sb-diff.py

# exit 3 = REFUSED. The instrument measured nothing, and it must not be able to
# report 0 for that: a refusal and a pass are different exit statuses, and the
# old gate's only exits were 0 and "whatever errexit caught".
refuse() { echo "== REFUSED, NOT A VERDICT: $*"; exit 3; }

# The cd is asserted, not assumed. `../../..` from checks/ is two levels above
# the repo and the shell does not care; only this does.
[ -f "$PORT" ] || refuse "cd landed outside the repo: $PORT is absent here (pwd $(pwd))"
[ -x ./bin/bend ] || refuse "./bin/bend is absent here (pwd $(pwd))"

substrate() {
  h=$(sha256sum tinybendygrad/helpers.bend | cut -d' ' -f1)
  o=$(sha256sum tinybendygrad/uop/ops.bend  | cut -d' ' -f1)
  [ -n "$h" ] && [ -n "$o" ] || refuse "substrate hash is empty: helpers.bend or uop/ops.bend is unreadable"
  echo "helpers=$h ops=$o"
}

if [ "${1:-}" = "--substrate" ]; then substrate; exit 0; fi

# The floor is asserted BEFORE the run, so a missing baseline can never be
# reached as a skip on the way past a comparison.
[ -f "$BASE" ]   || refuse "the regression floor is absent: $BASE (a missing baseline is not a passing baseline)"
[ -f "$ORACLE" ] || refuse "the CPython oracle is absent: $ORACLE"
[ -f "$DIFFER" ] || refuse "the differ is absent: $DIFFER"

echo "== substrate: $(substrate)"

# THE PRODUCER'S STATUS IS THE PRODUCER'S. No `|| true` here and none below: a
# bend that dies on a def it does not own emits no line to count, so the row
# census is the wrong instrument for it and saying "INCONCLUSIVE" is the only
# honest verdict. Rule 3 of gate.sh's own header, which this gate never had.
#
# bounded.py MERGES the child's stderr into its own stdout (bounded.py:103,
# `stderr=subprocess.STDOUT`), so `$RAW` holds the rows AND the diagnostics AND
# bounded.py's verdict line. All three are separated here rather than counted as
# one, which is why the row census below additionally REFUSES any line that is
# not a whole `name=value` row: this gate's comparison unit is that shape, so a
# line of any other shape is not a row and must never reach the denominator.
set +e
$BEND $PORT > $D/rows-bd.raw 2> $D/rows-bd.err
bendrec=$?
set -e
cat $D/rows-bd.err

# The verdict TOKEN, where bounded.py actually prints it (stdout), not the exit
# code: bounded.py returns 3 for a memory kill AND passes a child's own 3
# straight through (bounded.py:152), so a correct refusal and a killed compiler
# are the same status. bounded-selftest.sh and run-port-mm.sh both refuse with 3.
tok=$(sed -n 's/^\[bounded\] \([A-Z-]*\)  rc=.*/\1/p' $D/rows-bd.raw | tail -1)
sed '/^\[bounded\] [A-Z-]*  rc=/d' $D/rows-bd.raw > $D/rows-bd.txt
case "${tok:-NONE}" in
  KILLED-ON-MEMORY) refuse "the port was KILLED ON MEMORY: this proves nothing, it was killed" ;;
  TIMED-OUT)        refuse "the port TIMED OUT: this proves nothing, it was killed" ;;
  WITHIN-LIMITS)    : ;;
  *)                refuse "bounded.py printed no verdict token (saw '${tok:-none}'); the run is not a measurement" ;;
esac
[ "$bendrec" -eq 0 ] || refuse "the port exited $bendrec: that is the PORT failing, not a row census result"
[ -s $D/rows-bd.txt ] || refuse "the port emitted NO ROWS: a die produces no line to count"

# Every counted line must be a whole `name=value` row. A diagnostic that leaked
# into the stream is refused, not counted -- a denominator that includes an error
# message is a denominator that cannot go down.
if grep -qv '^[A-Za-z_][A-Za-z0-9_.]*=' $D/rows-bd.txt; then
  echo "== REFUSED, NOT A VERDICT: the row stream holds a line that is not name=value:"
  grep -nv '^[A-Za-z_][A-Za-z0-9_.]*=' $D/rows-bd.txt | head -5
  exit 3
fi

ROWS=$(wc -l < $D/rows-bd.txt | tr -d ' ')
echo "== DENOMINATOR: $ROWS rows; base rows: $(wc -l < $BASE | tr -d ' ')"

# 1. the regression floor: the rows the previous unit left
if grep -F -x -f $BASE $D/rows-bd.txt > /dev/null 2>&1; then
  echo "== BASE rows: byte-identical (all present)"
else
  echo "== BASE rows: *** NOT ALL PRESENT ***"
  grep -F -x -v -f $BASE $D/rows-bd.txt | head -20
  exit 1
fi

# 2. the port against CPython, on whole lines
PYTHONPATH=. .venv/bin/python $ORACLE > $D/sb-oracle.txt 2> $D/sb-oracle.err || {
  echo "== REFUSED, NOT A VERDICT: the CPython lane failed"; cat $D/sb-oracle.err; exit 3; }
.venv/bin/python $DIFFER $D/sb-oracle.txt $D/rows-bd.txt