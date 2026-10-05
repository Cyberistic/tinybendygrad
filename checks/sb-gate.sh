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
# bounded.py's two streams land in two files here because that is its contract now:
# `rows-bd.raw` is the PORT's stdout and NOTHING ELSE -- not the diagnostics, not the
# verdict -- and `rows-bd.err` carries the diagnostics and the one `[bounded]` record.
# (It used to merge: `stderr=subprocess.STDOUT` at the old bounded.py:103, so all three
# arrived in one stream and this gate had to separate them by hand.) The census below
# still REFUSES any line that is not a whole `name=value` row: this gate's comparison
# unit is that shape, so a line of any other shape is not a row and must never reach the
# denominator -- which is a check on the PORT now, not on the guard.
set +e
$BEND $PORT > $D/rows-bd.raw 2> $D/rows-bd.err
bendrec=$?
set -e
cat $D/rows-bd.err

# The verdict TOKEN, read from STDERR, and read as a token rather than as an exit
# code because the two are not the same claim. bounded.py's contract is now
# `stdout = the child's stdout, byte for byte` and `stderr = the child's stderr plus
# ONE [bounded] record line`, so the token is in rows-bd.err and rows-bd.raw needs
# no filtering at all -- which is what the census below wanted all along.
#
# It is a TOKEN and not the exit code because the code is a coarse summary: exit 3 is
# both a memory kill and a child's own refusal that printed something (bounded.py's
# `STATUS` table and its COLLISION selftest case say so), so a reader that asks "was it
# killed?" from the status alone cannot tell a correct refusal from a killed compiler.
# bounded-selftest.sh and run-port-mm.sh both refuse with 3.
tok=$(sed -n 's/^\[bounded\] \([A-Z-]*\)  rc=.*/\1/p' $D/rows-bd.err | tail -1)
# No `sed` to strip anything: bounded.py's stdout is the port's stdout and nothing else, so
# rows-bd.txt IS rows-bd.raw. A copy, because the diff below reads the published name.
cat $D/rows-bd.raw > $D/rows-bd.txt
case "${tok:-NONE}" in
  KILLED-ON-MEMORY) refuse "the port was KILLED ON MEMORY: this proves nothing, it was killed" ;;
  TIMED-OUT)        refuse "the port TIMED OUT: this proves nothing, it was killed" ;;
  WITHIN-LIMITS)    : ;;
  NO-VERDICT)       refuse "bounded.py reports the run MEASURED NOTHING (exit 6): the port exited non-zero having written nothing and said nothing. That is `bend`'s stack-overflow flake or a failure that printed nothing -- RETRY, and if it persists report it as a flake, not as a verdict." ;;
  NOT-STARTED)      refuse "the port could not be STARTED (exit 5): a path in the command does not exist. A command that never ran has proved nothing." ;;
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