#!/bin/sh
# THE HARNESS for `gr_21` (PERMUTE).
#
#   sh .agents/slop/backward4/run.sh <arm>
#
# arms:
#   base        the port's clean run, persisted as the differ's baseline.
#   check       THE GATE: the port's `pm_*`/`pm1_*` rows against `perm.rows` (CPython's
#               own bytes, transcribed by script) AND the pre-existing rows against
#               `../backward3/walk.rows` and `../backward2/rows.rows`.
#   head        HEAD's `gradient.bend` against the live one.  EVERY pre-existing row
#               must be byte-identical; the ONLY rows that may be new are this unit's.
#   ctl         THE CONTROLS: a wrong-but-non-empty expectation must be `MISMATCH` and
#               an emptied one must be `UNCHECKABLE` -- TWO CLASSES, not one.
#   oracleplant THE CONTROL ON THE CONTROL: perturbing the ORACLE moves the
#               expectation file and does NOT move the port.  A file that were a
#               transcript of the port's output could not move.
#   plants      THE MUTATIONS: each one must move a NAMED set of rows, and the UNION
#               of the rows every mutation moved must COVER every new row.
#
# EVERY EDIT ASSERTS THE REPLACED FILE BY RE-READING IT.  A plant that did not apply
# is reported as VACUOUS, not as a verdict.
#
# THE GATE AND THE CONTROLS ARE CALLED BY PATH -- `../backward3/gate.py` and
# `../backward3/ctl-rows.py` -- so there is ONE gate implementation in the tree.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
ROOT=$PWD
W="$TMPDIR/bw4"
BASE="$TMPDIR/bw4base.rows"
OUT=".agents/slop/backward4"
ARM="${1:-base}"
export BEND_NO_TELEMETRY=1

rm -rf "$W"; mkdir -p "$W"
cp -R "$ROOT/tinybendygrad" "$W/tinybendygrad"
F="$W/tinybendygrad/mixin/gradient.bend"

# $1 = the file to run, $2 = where the rows go.  Prints the verdict line.
run_port() {
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
  base|check|ctl|oracleplant|head|plants) : ;;
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
    echo "=== THE GATE (a): this unit's pm_*/pm1_* rows against perm.rows -- CPython's own bytes"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/gate.py" \
      "$W/live.rows" "$ROOT/$OUT/perm.rows"
    A=$?
    echo "=== THE GATE (b): the prior art's walk_* rows against backward3/walk.rows"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/gate.py" \
      "$W/live.rows" "$ROOT/.agents/slop/backward3/walk.rows"
    B=$?
    echo "=== THE GATE (c): the prior art's gs_*/bw_* rows against backward2/rows.rows"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/gate.py" \
      "$W/live.rows" "$ROOT/.agents/slop/backward2/rows.rows"
    C=$?
    echo "=== VERDICT: pm-rows rc=$A   walk-rows rc=$B   gs/bw-rows rc=$C"
    [ "$A" = 0 ] && [ "$B" = 0 ] && [ "$C" = 0 ] && exit 0 || exit 1 ;;

  head)
    env -u GIT_INDEX_FILE git show HEAD:tinybendygrad/mixin/gradient.bend > "$F" || exit 3
    echo "    HEAD's gradient.bend installed: $(shasum -a 256 "$F" | cut -d' ' -f1)"
    run_port "$F" "$W/head.rows"
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    echo "=== HEAD vs LIVE: rows head=$(wc -l < "$W/head.rows" | tr -d ' ') live=$(wc -l < "$W/live.rows" | tr -d ' ')"
    "$ROOT/.venv/bin/python" - "$W/head.rows" "$W/live.rows" "$ROOT/$OUT/perm.rows" <<'PY'
import sys
def load(p):
  d = {}
  for line in open(p):
    line = line.rstrip("\n")
    if "=" in line:
      k, _, v = line.partition("=")
      d[k] = v
  return d
h, l, new = load(sys.argv[1]), load(sys.argv[2]), set(load(sys.argv[3]))
changed = [k for k in h if k in l and h[k] != l[k]]
lost = [k for k in h if k not in l]
gained = sorted(k for k in l if k not in h)
print("--- rows whose VALUE changed (must be EMPTY: this unit must not move a pre-existing row):")
for k in sorted(changed):
  print("    %s:" % k)
  print("      head: %s" % h[k])
  print("      live: %s" % l[k])
print("    rows whose VALUE changed: %d of %d" % (len(changed), len(h)))
print("--- rows LIVE has that HEAD does NOT (must be EXACTLY this unit's %d):" % len(new))
for k in gained:
  print("    %s" % k)
extra = [k for k in gained if k not in new]
print("    gained: %d   of which NOT in this unit's row set: %d %s"
      % (len(gained), len(extra), " ".join(extra)))
print("--- rows HEAD has that LIVE does NOT (must be EMPTY):")
for k in sorted(lost):
  print("    %s" % k)
ok = not changed and not lost and not extra
print("VERDICT: %s" % ("PASS -- no pre-existing row moved" if ok else "FAIL"))
raise SystemExit(0 if ok else 1)
PY
    exit $? ;;

  ctl)
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    echo "=== THE CONTROLS (the prior art's ctl-rows.py, called BY PATH)"
    "$ROOT/.venv/bin/python" "$ROOT/.agents/slop/backward3/ctl-rows.py" \
      "$W/live.rows" "$ROOT/$OUT/perm.rows"
    exit $? ;;

  oracleplant)
    # THE CONTROL ON THE CONTROL.  THE ORACLE IS PERTURBED; THE PORT IS NOT TOUCHED.
    O="$W/oracle-planted.py"
    cp "$ROOT/$OUT/oracle-pm.py" "$O"
    "$ROOT/.venv/bin/python" - "$O" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "  per = UOp(Ops.PERMUTE, src=(a,), arg=(1, 2, 0))"
new = "  per = UOp(Ops.PERMUTE, src=(a,), arg=(2, 1, 0))"
assert s.count(old) == 1, "the plant target did not land -- VACUOUS, NO VERDICT"
p.write_text(s.replace(old, new))
print("    oracleplant: the fixture's PERMUTE order (1,2,0) became (2,1,0)")
PY
    [ $? = 0 ] || exit 3
    export LC_ALL=C DEV=NULL
    unset PYTHONPATH
    "$ROOT/.venv/bin/python" "$O" > "$W/oracle-planted.rows" || { echo "THE PLANTED ORACLE FAILED"; exit 1; }
    "$ROOT/.venv/bin/python" "$ROOT/$OUT/mkrows.py" "$W/oracle-planted.rows" "$W/perm-planted.rows" || exit 1
    echo "=== the EXPECTATIONS moved (the oracle moved, the port did NOT):"
    diff "$ROOT/$OUT/perm.rows" "$W/perm-planted.rows" | grep -E '^[<>]' | sed 's/^/    /'
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

  plants)
    run_port "$ROOT/tinybendygrad/mixin/gradient.bend" "$W/live.rows"
    "$ROOT/.venv/bin/python" "$ROOT/$OUT/plants.py" "$W/live.rows" "$ROOT/$OUT/perm.rows"
    exit $? ;;
esac
