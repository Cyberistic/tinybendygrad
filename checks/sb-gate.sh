#!/bin/sh
# The gate for the rule-body unit. THREE LANES, and the comparison is on whole
# `name=value` LINES -- never on row NAMES (agent-core.md: a name-comparing
# harness reported 0 for all 30 mutations in one unit and 0 for all 68 in
# another).
#
#   lane bd   ./bin/bend tinybendygrad/schedule/__init__.bend
#   lane bn   the native build, if the tree has one
#   lane py   .venv/bin/python oracles/schedule-bodies/sb-oracle.py
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
# ---------------------------------------------------------------------------
# THIS GATE GATES SOMETHING AGAIN, AND THE DATE IT STOPPED IS THE POINT.
# It used to end here: "This gate still gates nothing: the BASELINE is recovered
# and git-tracked, but sb-oracle.py and sb-diff.py are absent, so exit 3 with the
# list is the correct verdict for that state. Inventing an oracle to make the gate
# run would fabricate its own reference." **THAT WAS HONEST, AND IT WAS ALSO TRUE
# ONLY WHILE BOTH FILES WERE ABSENT.**
#
# MEASURED 2026-10-22, WHAT CHANGED:
#   * the CPython ORACLE IS NOW IN GIT, at `oracles/schedule-bodies/sb-oracle.py`,
#     and it is a RE-DERIVATION against the pin by a unit that ported the schedule
#     lane -- not the old script moved. It answers 81 `name=value` rows, the same
#     shape and the same row names as the floor and as the port's own rows.
#   * `sb-diff.py` is still GONE, and it is still gone because the sweep took it
#     (`371cc64c9`: "THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION PATHS
#     WITH THEM"). **IT IS NOT NEEDED.** Its contract was "0 says it agreed, a
#     non-zero says it did not", which was never MEASURED and was a transcribed
#     expectation of a differ's exit codes. The comparison this gate now uses is
#     `rows_agree`: THE COMPARISON THE FILE ALREADY HAD, in the same idiom, on the
#     same unit, in BOTH directions, and it PRINTS the counts it compared.
#   * the run's FILES now go to a WORK DIRECTORY (`mktemp -d`), not to a tracked
#     directory of expected values -- a transcript written beside the expected
#     values would dirty them on every run.
#
# **AND THE SHELL FORM IS RETIRED** -- `gates/README.md` says so, and this file is
# the last `.sh` gate that still compares the port to CPython. IT IS NOT A NEW
# SHELL GATE, IT IS THE OLD ONE REPOINTED, AND **PORTING IT TO PYTHON IS OWED.**
# The five verdicts are already spelled as EXITS, which is what a Python port
# would read from `gates/gatekit.py` instead.
#
# ---------------------------------------------------------------------------
# THE REGRESSION FLOOR WAS RE-FROZEN, AND THE DELTA IS DECLARED HERE BECAUSE A BARE
# RE-FREEZE IS NOT ENOUGH -- it moves the complaint from "the floor is stale" to
# "the floor is the port", and a floor that IS the port measures nothing.
#
# THE FLOOR's POPULATION IS UNCHANGED: the same 81 ROW NAMES, and the port still
# prints every one of them. WHAT MOVED IS SIX VALUES, and they split in two:
#
#   CPYTHON-CONFIRMED -- CPython's OWN toposort answers these exactly:
#     fx1_topo   19 -> 12     (CPython: fx1_topo=12)
#     fx2_topo   22 -> 11     (CPython: fx2_topo=11)
#     fx5_topo   15 ->  8     (CPython: fx5_topo=8)
#     These moved because the port's toposort now DOES NOT descend into a CALL's
#     body (`src_without_body`, upstream's `enter_calls=False`), and the two rows
#     that WITNESS it are the toposort's own order and the toposort's size.
#
#   THE PORT's OWN -- CPython ANSWERS NO SUCH ROW, and these are the port's ARENA
#   bookkeeping, so they moved on the PORT's word:
#     fx1_nodes  21 -> 22     fx2_nodes  23 -> 24     fx5_nodes  16 -> 17
#     The port's own account, quoted from the unit that made the change: the
#     substrate's `UOp.new.param` interns the shape node the old `param_src`
#     dropped (+3), the fixture no longer interns the unbound variable (-2), and
#     the shared size CONST is +1 for the fixtures that have no PARAM. **A NODE
#     COUNT IS A PORT-SIDE QUANTITY AND CPython CANNOT ANSWER IT, SO THESE THREE
#     ARE THE PORT'S AND NOT A WITNESS.**
#
# ---------------------------------------------------------------------------
# WHAT THE TWO LANES COVER, AND WHAT THEY DO NOT. The port prints 111 rows.
#   the BASE lane  covers 81 -- the port's OLDER population, the 81 names the floor
#                       holds, and it is a REGRESSION floor: it says those answers
#                       must not change.
#   the CPYTHON lane covers 81 -- the rows CPython ANSWERS, which is the port's
#                       NEWER population (the two sets share 53 names), and it is
#                       the INDEPENDENT witness: it says CPython's values are the
#                       port's values.
#   between them  109 of the port's 111 rows.
#   NOT COVERED BY EITHER: `gate_ki=0` and `gate_plain=1` -- the port's OWN
#                       witnesses that its `gate_kernel_sink` arm fires, and CPython
#                       has no answer for a port's witness about a port's gate.
#                       **TWO UNCOVERED ROWS ARE NAMED, WHICH IS THE POINT: AN
#                       UNCOVERED ROW THAT IS NOT NAMED IS A ROW NOBODY CAN FIND.**
set -eu
cd "$(dirname "$0")/.."

# THE INPUTS LIVE IN GIT, BESIDE THE GATE, AND THE RUN's FILES LIVE IN A WORK DIRECTORY.
# `IN` is the oracle role directory at the repo root, and it is the SAME directory the
# regression floor was already read from -- so the floor and the oracle now come from ONE
# place, and that place is in git.  `D` is a WORK DIRECTORY: the rows this run produces are a
# run's TRANSCRIPT, not an expected value, and a transcript written into a TRACKED directory
# of expected values would dirty it on every run.
IN=oracles/schedule-bodies
D=$(mktemp -d) || { echo "== REFUSED, NOT A VERDICT: mktemp -d failed: the gate cannot write its run's files without a work directory"; exit 3; }
trap 'rm -rf "$D"' EXIT INT TERM
PORT=tinybendygrad/schedule/__init__.bend
BEND=.venv/bin/python\ checks/bounded.py\ --seconds\ 900\ --mb\ 2048\ --\ ./bin/bend
# THE BASELINE IS GIT-TRACKED. It was written under .agents/slop/schedule-bodies/, which is
# pruned scratch and had no protection; the oracle role directory at the repo root
# holds the recovered copy, and this reads THAT. A gate's required input belongs in git,
# beside the gate, not in a swept tree -- putting it in .agents/slop/ is what deleted it.
BASE=$IN/BEFORE-rows.rows
# THE ORACLE MOVED TOO, AND IT MOVED BECAUSE A UNIT RE-DERIVED IT AGAINST THE PIN -- the old
# one is gone from .agents/slop/ (MEASURED 2026-10-19T04:25:08Z, `test -f` false), and the
# new one is in git at $IN, where it SURVIVES. MEASURED 2026-10-22: it answers 81 `name=value`
# rows, the same shape and the same row names as the floor and as the port's own rows -- so
# THE COMPARISON BELOW IS A SET COMPARISON ON WHOLE `name=value` LINES, AND IT NEEDS NO DIFFER.
ORACLE=$IN/sb-oracle.py

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

# THE REGRESSION FLOOR, AS ONE SET DIFFERENCE. The line this replaces was
#   grep -F -x -f $BASE $D/rows-bd.txt
# and `-f` ORs the pattern file: it succeeds if ANY pattern matches ANY line. MEASURED
# 2026-10-19T15:41:25Z, on the shipped 81-row floor, with a `rows` file holding row 1 of
# it -- rc 0, and the gate printed "== BASE rows: byte-identical (all present)". The same
# command on an EMPTY `rows` file prints "NOT ALL PRESENT". So what was implemented was
# "the port shares ONE row with the floor", which is neither a floor nor this file's own
# wording ("every base row present", :226). `sort -u` both files and `comm -23` IS the
# strong claim as ONE comparison over two files: no 81 patterns are transcribed, and the
# denominator is the floor's own line count rather than a number in a comment. LC_ALL=C on
# all three, because `comm` compares under ONE collation. `-u` makes it a SET claim --
# "every DISTINCT floor row appears", which is the existence claim `grep -x -f` was trying
# to be; the floor holds 81 lines and 81 distinct ones, so set and multiset coincide here.
floor_check() {
  w=$(mktemp -d) || refuse "mktemp -d failed: the floor cannot be compared without a work directory"
  lb=${3:-BASE}
  LC_ALL=C sort -u "$1" > "$w/base"; LC_ALL=C sort -u "$2" > "$w/rows"
  LC_ALL=C comm -23 "$w/base" "$w/rows" > "$w/missing"
  b=$(wc -l < "$w/base" | tr -d ' '); r=$(wc -l < "$w/rows" | tr -d ' '); m=$(wc -l < "$w/missing" | tr -d ' ')
  if [ "$m" -eq 0 ]; then
    echo "== $lb rows: COMPLETE -- $b of $b $lb rows present in the $r rows the port emitted"
    rm -rf "$w" || :; return 0
  fi
  echo "== $lb rows: *** INCOMPLETE -- $m of $b $lb rows ABSENT from the $r rows the port emitted ***"
  head -20 "$w/missing"
  rm -rf "$w" || :; return 1
}

# A SECOND COPY OF THE COMPARISON WAS WRITTEN HERE AND DELETED. It was a two-way set
# comparison (`rows_agree`), and it was WRONG for the CPython lane: the oracle answers
# 81 rows and the port prints 111, so a two-way comparison reports the port's own 30
# rows -- the `COUNT_fx*` census, the node counts, the gate's own witnesses -- as
# disagreements, and CPython HAS NO ANSWER for them. **A COMPARISON THAT REPORTS A
# DISAGREEMENT FOR A ROW CPYTHON NEVER ANSWERED IS NOT A STRICTER CHECK, IT IS A WRONG
# ONE.** The CPython lane now uses `floor_check` with the ORACLE as the FLOOR, so there
# is ONE comparison in this file, on ONE unit, with TWO floors.

# `--plant` drives `floor_check` ITSELF, not a second copy of the comparison, on `rows`
# files built FROM the shipped floor so the count is READ and never transcribed
# (AGENTS.md doctrine 1). THE THIRD CASE IS THE CONTROL: a comparison that answered
# INCOMPLETE to everything would pass the first two, and a `floor_check` that printed
# NOTHING is scored by its exit, so silence cannot read as agreement. It needs only the
# floor, so it is dispatched before the two absent inputs are checked, and it exits before
# any `bend`.
plant() {
  mkdir -p "$D"
  head -1 "$BASE" > "$D/plant-one.rows"; : > "$D/plant-zero.rows"; cp "$BASE" "$D/plant-all.rows"
  rc=0
  for c in one zero all; do
    case $c in all) want=COMPLETE ;; *) want=INCOMPLETE ;; esac
    if floor_check "$BASE" "$D/plant-$c.rows"; then got=COMPLETE; else got=INCOMPLETE; fi
    if [ "$got" = "$want" ]; then say=ok; else say=FAIL; rc=1; fi
    echo "PLANT $c rows: want $want, the gate said $got  [$say]"
  done
  rm -f "$D/plant-one.rows" "$D/plant-zero.rows" "$D/plant-all.rows"

  # THE CPYTHON LANE'S OWN PLANT, ON THE SAME COMPARISON AND THE SAME UNIT. The oracle
  # is RUN -- it needs no compiler -- and its rows are the CPYTHON lane's FLOOR. The arm
  # mutates ONE row's VALUE in a COPY of the floor and asks the lane to notice.
  #
  # **AND THIS IS THE LANE'S REAL FAILURE SHAPE, NOT A PROXY FOR IT.** The CPython
  # lane's claim is "every row CPython ANSWERS is present in the port's rows, with
  # CPython's VALUE". So when CPython and the port disagree about a value, the floor's
  # line `name=value` is simply ABSENT from the port's set -- which is exactly what a
  # mutated floor reproduces. The port's own rows are not needed to prove the first half
  # of the claim can go red, and using the oracle's rows as the stand-in is honest
  # because they ARE the same 81 values the port prints for those 81 names (MEASURED
  # 2026-10-22: 81 of 81 present).
  if [ -f "$ORACLE" ]; then
    PYTHONPATH=. .venv/bin/python "$ORACLE" > "$D/plant-py.rows" 2>"$D/plant-py.err" || :
    cp "$D/plant-py.rows" "$D/plant-py-same.rows"
    # THE MUTATION IS ONE VALUE, IN A COPY, AND IT MUST MOVE THE VERDICT.
    sed 's/^\(unwrap_A1=\).*/\199/' "$D/plant-py.rows" > "$D/plant-py-changed.rows"
    for c in same changed; do
      case $c in same) want=COMPLETE ;; *) want=INCOMPLETE ;; esac
      if floor_check "$D/plant-py-$c.rows" "$D/plant-py.rows" "CPYTHON"; then got=COMPLETE; else got=INCOMPLETE; fi
      if [ "$got" = "$want" ]; then say=ok; else say=FAIL; rc=1; fi
      echo "PLANT cpython-$c rows: want $want, the gate said $got  [$say]"
    done
    rm -f "$D/plant-py.rows" "$D/plant-py.err" "$D/plant-py-same.rows" "$D/plant-py-changed.rows"
  fi
  [ "$rc" -eq 0 ] || exit 1
  echo "== PLANT PASS: a partial floor and an absent floor are both INCOMPLETE, a whole floor is COMPLETE, and the CPython lane's floor goes red on ONE changed value"
  exit 0
}
if [ "${1:-}" = "--plant" ]; then plant; fi

[ -f "$ORACLE" ] || refuse "the CPython oracle is absent: $ORACLE"

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

# 1. the regression floor: the rows the previous unit left. `floor_check` owns the claim,
# its diagnostic and its wording together, so the three cannot drift apart again. Its
# diagnostic is the ABSENT floor rows; the line this replaced printed the other side --
# `grep -F -x -v -f $BASE rows`, the emitted rows that are not floor rows -- which on the
# arm it could reach was every row the port emitted, so it answered a different question.
floor_check "$BASE" $D/rows-bd.txt || exit 1

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

# THE TWO LANES, ONE COMPARISON. The CPYTHON LANE is `floor_check` with the ORACLE's
# output as the FLOOR -- THE SAME COMPARISON, ON THE SAME UNIT, WITH A DIFFERENT FLOOR.
# The old `sb-diff.py` is GONE -- it lived under .agents/slop/ and the sweep took it
# (MEASURED: `371cc64c9` -- "THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION
# PATHS WITH THEM") -- and its contract was UNMEASURED, because a rule about which of
# its exit codes means what would be a transcribed expectation of a differ's behaviour.
# The comparison this gate uses instead is the one it ALREADY HAD, in its own idiom, on
# its own unit: `LC_ALL=C sort -u` both sides, then `comm -23` -- "every DISTINCT floor
# row is present in the port's rows" -- with the DENOMINATOR PRINTED.
#
# ONE DIRECTION IS RIGHT FOR THE CPYTHON LANE, AND IT IS NOT AN ACCIDENT. The oracle
# answers 81 rows and the port prints 111: the port's other 30 rows are its OWN (the
# `COUNT_fx*` census, the node counts, the gate's own witnesses), and CPython has no
# answer for them. So the CPython lane's claim is "every row CPython ANSWERS is
# present in the port's rows, with CPython's value" -- which is exactly what
# `floor_check` says. A TWO-WAY comparison here would report the port's own 30 rows as
# disagreements, and a comparison that reports a disagreement for a row CPython never
# answered is not a stricter check, it is a wrong one.
#
# `set -e` is lifted around it so a disagreement is this gate's FAIL (1) and not
# `set -e`'s promotion of a raw exit.
set +e
floor_check "$D/sb-oracle.txt" "$D/rows-bd.txt" "CPYTHON"
agree=$?
set -e
if [ "$agree" -ne 0 ]; then
  echo "== FAIL: the CPython lane's rows are not all present in the port's rows"
  exit 1
fi
echo "== PASS: every base row present, every row is name=value, and every row CPython answered is present in the port's"
exit 0