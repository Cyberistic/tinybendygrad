#!/bin/sh
# THE HARNESS for the RESTORED `walk_*` rows.
#
#   sh .agents/slop/backward3/run.sh <arm>
#
# arms:
#   base        the port's clean run, persisted as the differ's baseline.
#   check       THE GATE: the port's 16 `walk_*` rows against `walk.rows` (CPython's
#               own bytes, transcribed by script) AND the previous unit's 14
#               `gs_*`/`bw_*` rows against `../backward2/rows.rows`.
#   head        HEAD's `gradient.bend` against the live one.  Every row HEAD has must
#               still be there; the ONLY rows whose VALUE may change are the five the
#               fixture fix was supposed to move, and they are NAMED.
#   ctl         the CONTROLS: a wrong-but-non-empty expectation must be `MISMATCH` and
#               an empty one must be `UNCHECKABLE` -- TWO CLASSES, not one.
#   oracleplant THE CONTROL ON THE CONTROL: perturbing the ORACLE moves the
#               expectation file and does NOT move the port.  A file that were a
#               transcript of the port's output could not move.
#   walkplants  the PRIOR ART's own plant/disarm harness (`checks/walk-mutate.sh`),
#               run verbatim -- its `plant_reverse` and `plant_noguard` are the walk
#               rows' plants and its two disarms are the vacuity control.
#   prev        the PREVIOUS UNIT's harness (`../backward2/run.sh`), run verbatim:
#               its `check` arm is the 14 rows' gate and its eight plants are the
#               `gs_*`/`bw_*` rows' plants.
#
# EVERY EDIT ASSERTS THE REPLACED FILE BY RE-READING IT.  A plant that did not apply
# is reported as VACUOUS, not as a verdict.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
ROOT=$PWD
W="$TMPDIR/bw3"
BASE="$TMPDIR/bw3base.rows"
ARM="${1:-base}"
export BEND_NO_TELEMETRY=1

rm -rf "$W"; mkdir -p "$W"
cp -R "$ROOT/tinybendygrad" "$W/tinybendygrad"
F="$W/tinybendygrad/mixin/gradient.bend"

# $1 = file, $2 = old, $3 = new, $4 = label.  Replaces, writes, RE-READS, asserts.
apply() {
  "$ROOT/.venv/bin/python" - "$1" "$2" "$3" "$4" <<'PY'
import sys, pathlib
f, old, new, label = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(f); s = p.read_text()
n = s.count(old)
if n != 1:
    print("    %s: %d occurrence(s) of the target, expected 1 -- VACUOUS, NO VERDICT" % (label, n))
    sys.exit(3)
out = s.replace(old, new)
p.write_text(out)
back = p.read_text()
if back == s or back.count(new) != 1:
    print("    %s: WRITE DID NOT LAND -- VACUOUS, NO VERDICT" % label)
    sys.exit(3)
print("    %s: applied and VERIFIED" % label)
PY
}

run_port() {
  # $1 = the file to run, $2 = where the rows go.  Prints the verdict line.
  "$ROOT/bin/bend" "$1" --check-only > "$W/check.out" 2>&1
  CHK=$(head -1 "$W/check.out")
  "$ROOT/bin/bend" "$1" > "$2" 2> "$W/run.err"
  RC=$?
  echo "=== check-only: $CHK  run rc=$RC  rows=$(wc -l < "$2" | tr -d ' ')"
  if [ "$RC" != 0 ] || [ ! -s "$2" ]; then
    echo "=== INCONCLUSIVE: the substrate failed, not the code.  stderr:"; cat "$W/run.err"; exit 1
  fi
}

case "$ARM" in
  base|check|ctl|oracleplant) : ;;
  head)
    env -u GIT_INDEX_FILE git show HEAD:tinybendygrad/mixin/gradient.bend > "$F" || exit 3
    echo "    HEAD's gradient.bend installed: $(shasum -a 256 "$F" | cut -d' ' -f1)"
    ;;
  walkplants|prev) : ;;
  *) echo "UNKNOWN ARM $ARM"; exit 2 ;;
esac

case "$ARM" in
  base)
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/base.rows"
    cp "$W/base.rows" "$BASE"
    echo "    (this IS the base; persisted at $BASE)"
    exit 0 ;;

  check)
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    echo "=== THE GATE (a): the port's walk rows against walk.rows -- CPython's own bytes"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/gate.py" \
      "$W/live.rows" "$ROOT/.agents/slop/backward3/walk.rows"
    A=$?
    echo "=== THE GATE (b): the previous unit's gs_*/bw_* rows against backward2/rows.rows"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/gate.py" \
      "$W/live.rows" "$ROOT/.agents/slop/backward2/rows.rows"
    B=$?
    echo "=== VERDICT: walk-rows rc=$A   gs/bw-rows rc=$B"
    [ "$A" = 0 ] && [ "$B" = 0 ] && exit 0 || exit 1 ;;

  head)
    run_port "$F" "$W/head.rows"
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    echo "=== HEAD vs LIVE: rows head=$(wc -l < "$W/head.rows" | tr -d ' ') live=$(wc -l < "$W/live.rows" | tr -d ' ')"
    sort "$W/head.rows" > "$W/head.sorted"
    sort "$W/live.rows" > "$W/live.sorted"
    echo "--- rows HEAD has whose WHOLE LINE is not in LIVE (a row whose VALUE changed shows up here too -- the VALUE diff at the foot is the precise one):"
    comm -23 "$W/head.sorted" "$W/live.sorted" | sed 's/^/    /'
    echo "--- rows LIVE has that HEAD does NOT (must be EXACTLY the previous unit's 14):"
    comm -13 "$W/head.sorted" "$W/live.sorted" | sed 's/^/    /'
    echo "--- rows whose VALUE changed (must be EXACTLY the five the leaf fix moved):"
    "$ROOT/.venv/bin/python" - "$W/head.rows" "$W/live.rows" <<'PY'
import sys
def load(p):
  d = {}
  for line in open(p):
    line = line.rstrip("\n")
    if "=" in line:
      k, _, v = line.partition("=")
      d[k] = v
  return d
h, l = load(sys.argv[1]), load(sys.argv[2])
n = 0
for k in h:
  if k in l and h[k] != l[k]:
    n += 1
    print("    %s:" % k)
    print("      head: %s" % h[k])
    print("      live: %s" % l[k])
print("    rows whose VALUE changed: %d" % n)
print("    rows byte-identical: %d of %d" % (len([k for k in h if k in l and h[k] == l[k]]), len(h)))
PY
    exit 0 ;;

  ctl)
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    echo "=== THE CONTROLS"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/ctl-rows.py" \
      "$W/live.rows" "$ROOT/.agents/slop/backward3/walk.rows"
    exit $? ;;

  oracleplant)
    # THE CONTROL ON THE CONTROL.  The ORACLE is perturbed; the PORT IS NOT TOUCHED.
    O="$W/oracle-planted.py"
    cp "$ROOT/.agents/slop/backward/oracle-cg.py" "$O"
    apply "$O" "    q = UOp(Ops.ADD, src=(a, c))" "    q = UOp(Ops.MUL, src=(a, c))" \
      "oracleplant: the DAG's second ADD became a MUL" || exit 3
    export LC_ALL=C DEV=NULL
    unset PYTHONPATH
    "$ROOT/.venv/bin/python" "$O" > "$W/oracle-planted.rows" || { echo "THE PLANTED ORACLE FAILED"; exit 1; }
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/mkrows.py" \
      "$W/oracle-planted.rows" "$W/walk-planted.rows" || exit 1
    echo "=== the EXPECTATIONS moved (the oracle moved, the port did NOT):"
    diff "$ROOT/.agents/slop/backward3/walk.rows" "$W/walk-planted.rows" | grep -E '^[<>]' | sed 's/^/    /'
    echo "=== the PORT's rows did NOT move (this arm never touched it):"
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    if [ -f "$BASE" ]; then
      diff "$BASE" "$W/live.rows" > "$W/portdiff.out" 2>&1 \
        && echo "    the port's output is byte-identical to the base -- NOTHING MOVED" \
        || { echo "    THE PORT MOVED, which this arm must never do:"; sed 's/^/    /' "$W/portdiff.out"; exit 1; }
    else
      echo "    (no base persisted; run 'sh $0 base' first for this comparison)"
    fi
    exit 0 ;;

  walkplants)
    # THE PRIOR ART'S OWN HARNESS, run verbatim.  Its base must be re-persisted AFTER
    # the leaf fix, or every row would move.
    for a in base plant_reverse plant_noguard disarm_comment disarm_name; do
      echo "################ ARM $a"
      sh "$ROOT/checks/walk-mutate.sh" "$a" | grep -E '^(===|    )' | sed 's/^/  /'
    done
    exit 0 ;;

  prev)
    # THE PREVIOUS UNIT'S OWN HARNESS, run verbatim.
    for a in base check plant_gswap plant_nozero plant_setorder plant_nohole \
             plant_noguard plant_skipseed plant_droptarget plant_flags \
             disarm_comment disarm_name; do
      echo "################ ARM $a"
      sh "$ROOT/.agents/slop/backward2/run.sh" "$a" | grep -E '^(===|    |<|>)' | sed 's/^/  /'
    done
    exit 0 ;;
esac
