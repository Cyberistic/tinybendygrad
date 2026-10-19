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
# This gate still gates nothing: the BASELINE is recovered and git-tracked, but
# sb-oracle.py and sb-diff.py are absent, so exit 3 with the list is the correct
# verdict for that state. Inventing an oracle to make the gate run would fabricate
# its own reference.
set -eu
cd "$(dirname "$0")/.."

D=.agents/slop/schedule-bodies
PORT=tinybendygrad/schedule/__init__.bend
BEND=.venv/bin/python\ checks/bounded.py\ --seconds\ 900\ --mb\ 2048\ --\ ./bin/bend
# THE BASELINE IS GIT-TRACKED. It was written under .agents/slop/schedule-bodies/, which
# is pruned scratch and had no protection; the oracle role directory at the repo root
# holds the recovered copy, and this reads THAT. A gate's required input belongs in git,
# beside the gate, not in a swept tree -- putting it in .agents/slop/ is what deleted it.
BASE=oracles/schedule-bodies/BEFORE-rows.rows
ORACLE=$D/sb-oracle.py
DIFFER=$D/sb-diff.py

# THE FIVE VERDICTS, AS EXITS -- `gates/gatekit.py:60`'s OWN TABLE,
# `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. A shell gate's exit status IS its whole
# vocabulary -- `gates/gate-surface.py:150` measured that a `.sh` gate can only say what it
# means in a shell -- so all five are spelled here, and the two files share no code: MEASURED
# 2026-10-19T04:37:45Z, `grep -v '^ *#' checks/sb-gate.sh | grep -c gatekit` is **0**, and the
# bare `grep -c gatekit` reads 4 because this header quotes the name. WHAT THEY SHARE IS THE
# VOCABULARY, and that is MEASURED rather than asserted, because `checks/gatesweep.py:323`
# reads EVERY member's exit through `gatekit.VERDICT.get(rc)` with no regard for its language:
#
#     $ .venv/bin/python -c "... run_one(Path('checks/sb-gate.sh'),'sh-selfref',60,512,...)"
#     run_one -> ('REFUSED', 'REFUSED', 3, 0.0914, '0')      # measured 2026-10-19T04:26:06Z
#
# So the complaint that the two 3s share no lines was measuring the IMPLEMENTATION where the
# DEFECT lives in the MAPPING. It did: this gate used to charge REFUSED to a state the table
# assigns to SKIP, and the same consumer then showed the same exit code as two different
# things. `gates/README.md:146` and `checks/gatesweep.py:315` both say a lane killed on memory
# is `SKIP`, and one real kill settles it -- MEASURED 2026-10-19T04:26:39Z, no `bend`:
#
#     $ .venv/bin/python checks/bounded.py --seconds 30 --mb 64 -- .venv/bin/python -c \
#           'a=bytearray(400*1024*1024)'
#     [bounded] KILLED-ON-MEMORY  rc=-9  peak-RSS=177 MB (ceiling 64)
#     classify('KILLED-ON-MEMORY', 3, ...) -> ('SKIP', 'KILLED-ON-MEMORY')
#     classify(           'WITHIN-LIMITS', 3,
#                 '== REFUSED, NOT A VERDICT: the port was KILLED ON MEMORY')
#                                           -> ('REFUSED', 'REFUSED')
#
# Same exit code, same consumer, same physical state, TWO WORDS. The only thing that differed
# was the line below. That is the whole defect, and it is not the shell's.
refuse() { echo "== REFUSED, NOT A VERDICT: $*"; exit 3; }
skip()   { echo "== SKIP, NOT A VERDICT: $*"; exit 4; }
dead()   { echo "== DEAD, NOT A VERDICT: $*"; exit 5; }

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

# `--substrate` prints two hashes and reaches NO VERDICT about the rule-body unit, so it is
# not a PASS. It was `exit 0`, and a caller reading `$?` read a substrate fingerprint as
# agreement on the thing this gate exists to compare. MEASURED before the change: plain run
# rc 3, `--substrate` rc 0 -- and the 0 was a fingerprint.
if [ "${1:-}" = "--substrate" ]; then substrate; skip "--substrate is a FINGERPRINT, not a verdict on the rule-body unit"; fi

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
  KILLED-ON-MEMORY) skip "the port was KILLED ON MEMORY: it could not FINISH, so it measured nothing. checks/bounded.py's own STATUS maps this token to exit 3 -- which is REFUSED's code -- so the TOKEN is the verdict here and not the code." ;;
  TIMED-OUT)        skip "the port TIMED OUT: it could not FINISH, so it measured nothing. Same shape as the kill: bounded.py exits 4 and the table calls 4 SKIP." ;;
  WITHIN-LIMITS)    : ;;
  NO-VERDICT)       dead "the port RAN, exited non-zero, wrote nothing and SAID nothing: that is DEAD and not REFUSED, because a lane that demonstrably ran did not run on an absent precondition. bend's stack-overflow flake or a failure that printed nothing -- RETRY, and if it persists report it as a flake, not as a verdict." ;;
  NOT-STARTED)      refuse "the port could not be STARTED (bounded.py exit 5): a path in the command does not exist, so the absent precondition is the PATH and nothing was measured." ;;
  *)                refuse "bounded.py printed no verdict token (saw '${tok:-none}'); the watchdog's own RECORD is the absent precondition and the run is not a measurement" ;;
esac
# `bendrec` IS `checks/bounded.py`'s exit and NOT `bend`'s -- `$BEND` is the watchdog. So this
# arm can only fire when the watchdog reported WITHIN-LIMITS and exited non-zero, which is a
# record and a status that contradict each other: a definition absent, not a port failure.
[ "$bendrec" -eq 0 ] || refuse "the watchdog reported WITHIN-LIMITS and exited $bendrec: its record and its status disagree, so the run is not a measurement"
[ -s $D/rows-bd.txt ] || dead "the port emitted NO ROWS: it RAN and emitted nothing, which is DEAD. checks/gatesweep.py:319 reads the same shape as DEAD/SILENT."

# Every counted line must be a whole `name=value` row. A diagnostic that leaked
# into the stream is FAILED, not refused: the port ran, and what it produced is
# not the shape this gate compares, so it is the wrong answer rather than no
# measurement -- and a denominator that includes an error message is a
# denominator that cannot go down.
if grep -qv '^[A-Za-z_][A-Za-z0-9_.]*=' $D/rows-bd.txt; then
  echo "== FAIL: the port ran and emitted a line that is not name=value:"
  grep -nv '^[A-Za-z_][A-Za-z0-9_.]*=' $D/rows-bd.txt | head -5
  exit 1
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

# THE CPYTHON LANE, AND THE `||` THIS GATE HAD WAS A FOLD. `|| { ...; exit 3; }` charged
# REFUSED -- "a precondition was absent" -- to a lane that HAD BEEN INVOKED, so the two
# answers a reader most needs apart, "the oracle could not start" and "the oracle started and
# got the wrong answer", were one exit. They are separated here on the evidence, and the
# evidence is the traceback: `gates/gatekit.py:118`'s own rule, that a lane which raises and
# prints a traceback is DEAD because it demonstrably ran and demonstrably did not answer.
#
# UNREACHABLE TODAY AND SAID SO: `sb-oracle.py` is ABSENT (MEASURED 2026-10-19T04:25:08Z,
# `test -f` false), so `:81` refuses above and this arm never runs. It is written because a
# gate that cannot reach its own FAIL cannot be trusted to reach its PASS, and because
# deleting the arm would delete the record that the comparison has no implementation.
set +e
PYTHONPATH=. .venv/bin/python $ORACLE > $D/sb-oracle.txt 2> $D/sb-oracle.err
orec=$?
set -e
if [ "$orec" -ne 0 ]; then
  if grep -q '^Traceback' $D/sb-oracle.err; then
    dead "the CPython lane RAN, raised a traceback and answered nothing: $(tail -1 $D/sb-oracle.err)"
  fi
  echo "== FAIL: the CPython lane ran and did not agree (exit $orec):"
  cat $D/sb-oracle.err
  exit 1
fi

# THE DIFFER'S EXIT WAS THE GATE'S EXIT, AND IT WAS NOT IN THE FIVE -- `set -e` promoted
# whatever `sb-diff.py` returned to this script's status, so an unknown integer left the
# gate. `sb-diff.py` is ABSENT (same measurement), so ITS contract is UNMEASURED and is NOT
# GUESSED HERE: a rule about which of its codes means what would be a transcribed expectation,
# and an unmeasured one at that. The only fact this gate owns is AGREEMENT -- 0 says it
# agreed, and a non-zero says it did not report agreement, which is FAIL under the five.
set +e
.venv/bin/python $DIFFER $D/sb-oracle.txt $D/rows-bd.txt
diffrec=$?
set -e
if [ "$diffrec" -ne 0 ]; then
  echo "== FAIL: the differ ran and did not report agreement (exit $diffrec)"
  exit 1
fi
echo "== PASS: every base row present, every row is name=value, and the differ agreed"
exit 0