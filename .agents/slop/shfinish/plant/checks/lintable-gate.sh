#!/bin/sh
# lintable-gate.sh -- the CPython gate for the ops.py linear rule table in
# `tinybendygrad/uop/ops.bend`.
#
#   sh .agents/slop/lintable/lintable-gate.sh
#   sh .agents/slop/lintable/lintable-gate.sh --plant    # plant, show red
#   sh .agents/slop/lintable/lintable-gate.sh --disarm   # remove plant, show green
#
# THREE LANES, and the diff IS the test:
#   * CPython    -- `.agents/slop/lintable/lintable-oracle.py`, every expectation
#                   COMPUTED by running tinygrad, never typed
#   * interpreted -- `./bin/bend <probe>`
#   * native      -- `./bin/bend <probe> -o bin && ./bin/bend bin`
#
# It runs the lanes ITSELF rather than calling another gate, because a script that
# exits non-zero ON a diff cannot tell "the row moved" from "the file stopped
# compiling" -- two different findings one exit code cannot separate. And it gates on
# the string `ALL PROOFS CHECK` being PRINTED, not on an exit status: `bend
# --check-only` exits 1 for 14 of the tree's 136 .bend files, and a harness gated on
# the status let a mutant with an UNDEFINED CALLEE pass and counted its empty output
# as "moved 0 rows".
#
# A THROW-AWAY COPY IS NOT USED. A `$TMPDIR` scratch copy cannot resolve a relative
# import -- it produced 22 phantom blind spots in one unit -- so the plant edits a
# COPY OF THE REPO TREE under `.agents/slop/lintable/plant/`, which keeps the relative
# depth, and the live tree is never patched from a harness.
set -e
cd "$(dirname "$0")/../../.."
GT=.agents/slop/lintable
PROBE=$GT/lintable-probe.bend

need_check() {  # $1 = file, $2 = label
  line=$(./bin/bend "$1" --check-only 2>&1 | head -1)
  if [ "$line" != "ALL PROOFS CHECK" ]; then
    echo "lintable-gate: $2 --check-only says '$line'" >&2
    exit 1
  fi
}

run_lane() {  # $1 = out file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^[a-z0-9_]*=' > "$out.tmp" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "lintable-gate: lane produced 0 rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

# ---------------------------------------------------------------------------
# THE PLANT, AND ITS PAIRED DISARM. Both live in this script so a red cannot be
# reported without the green that puts it back, and both are the SAME edit at the
# SAME place -- a plant that lands somewhere else proves nothing.
#
# WHAT IS PLANTED, and why this mutation and not another. The mutation inverts
# `pm_r_tag_m.of`'s two arms, so `remove_all_tags` becomes its own negation: it
# strips the tag off an UNTAGGED node and keeps it on a TAGGED one. It is the one
# mutation here that a rule-table gate is FOR, because the claim (`all_ops()`) is
# unchanged and every necessary-condition row stays green -- only
# `rat_strips` / `rat_keeps_untagged` / `rat_tag_before` / `rat_tag_after` move.
#
# IT IS A REAL MUTATION, not an abort. A mutation table that aborts is not the table:
# two units this session published a green mutation for a mutant that never applied,
# one calling `U32.nand`, which does not exist in Bend 2.0.35 and silently aborted a
# 28-entry table at entry 19. This edit keeps the file `ALL PROOFS CHECK` and every
# rule reachable, and the harness CHECKS that before believing the red.
# ---------------------------------------------------------------------------
PLANT_OLD='  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})'
PLANT_NEW='  Bool.pick(Maybe<&2, Found>, untagged, Some{made}, None{})'

plant() {
  rm -rf "$GT/plant"
  mkdir -p "$GT/plant/$GT" "$GT/plant/tinybendygrad/uop" "$GT/plant/tinybendygrad/LAWS"
  for f in tinybendygrad/helpers.bend tinybendygrad/dtype.bend \
           tinybendygrad/LAWS/spec.bend tinybendygrad/uop/ops.bend; do
    [ -f "$f" ] && cp "$f" "$GT/plant/$f"
  done
  cp "$PROBE" "$GT/plant/$PROBE"
  cp .agents/slop/lintable/lintable-oracle.py "$GT/plant/$GT/lintable-oracle.py"
  python3 - "$GT/plant/$PLANT" "ops.bend" <<'PY'
import sys
path, old, new = sys.argv[1], "  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})", \
                       "  Bool.pick(Maybe<&2, Found>, untagged, Some{made}, None{})"
f = path + "/tinybendygrad/uop/ops.bend"
s = open(f).read()
assert s.count(old) == 1, "plant anchor is not unique: %d" % s.count(old)
open(f, "w").write(s.replace(old, new))
print("planted at", f)
PY
}

disarm() {
  python3 - "$GT/plant/$PLANT/tinybendygrad/uop/ops.bend" <<'PY'
import sys
path = sys.argv[1]
old = "  Bool.pick(Maybe<&2, Found>, untagged, Some{made}, None{})"
new = "  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})"
s = open(path).read()
assert s.count(old) == 1, "disarm anchor is not unique: %d" % s.count(old)
open(path, "w").write(s.replace(old, new))
print("disarmed at", path)
PY
}

# ---------------------------------------------------------------------------
MODE=${1:-plain}
case "$MODE" in
  --plant)
    if [ ! -s "$GT-py.txt" ] || [ ! -s "$GT-bendonly.txt" ]; then
      echo "lintable-gate: run the plain gate first -- the plant needs the oracle files" >&2
      exit 1
    fi
    plant
    P=$GT/plant/$PROBE
    need_check "$GT/plant/tinybendygrad/uop/ops.bend" "the PLANTED ops.bend"
    echo "lintable-gate: plant is ALL PROOFS CHECK, so it applied and did not abort"
    run_lane "$GT/plant-bd.txt" ./bin/bend "$P"
    awk -F= 'NR==FNR{b[$1]=1;next} !($1 in b)' "$GT-bendonly.txt" - < "$GT/plant-bd.txt" | sort > "$GT/plant-bd.s.txt"
    if diff -q "$GT/AFTER-probe.txt" "$GT/plant-bd.txt" > /dev/null; then
      echo "lintable-gate: PLANT DID NOT MOVE ANY ROW -- the gate is BLIND to it" >&2
      exit 1
    fi
    echo "lintable-gate: plant moved these rows:"
    diff "$GT/AFTER-probe.txt" "$GT/plant-bd.txt" | grep '^<' | sed 's/^< /  /'
    # AND THE GATE ITSELF MUST GO RED ON THE PLANT. A mutation table that reports "the
    # rows moved" is not the same claim as "the gate fails", and only the second one
    # says the harness can see a wrong answer. Two units this session published a green
    # mutation for a mutant that never applied. So the planted lane is diffed against
    # the SAME oracle and a clean diff is treated as a failure of this script.
    if diff -q "$GT-py.txt" "$GT/plant-bd.s.txt" > /dev/null 2>&1; then
      echo "lintable-gate: THE PLANT DID NOT MAKE THE GATE RED -- the harness is blind" >&2
      exit 1
    fi
    echo "lintable-gate: and the GATE goes red on the plant, on these rows:"
    diff "$GT-py.txt" "$GT/plant-bd.s.txt" | grep '^<' | sed 's/^< /    /'
    disarm
    need_check "$GT/plant/tinybendygrad/uop/ops.bend" "the DISARMED ops.bend"
    run_lane "$GT/disarm-bd.txt" ./bin/bend "$P"
    if diff -q "$GT/AFTER-probe.txt" "$GT/disarm-bd.txt" > /dev/null; then
      echo "lintable-gate: disarm restored the baseline EXACTLY"
    else
      echo "lintable-gate: DISARM DID NOT RESTORE -- the plant is still live" >&2
      diff "$GT/AFTER-probe.txt" "$GT/disarm-bd.txt" >&2
      exit 1
    fi
    ;;

  --disarm)
    echo "lintable-gate: nothing is planted in the live tree; --disarm is the paired"
    echo "  counterpart of --plant and --plant already disarms itself. This exits 0"
    echo "  ONLY because there is no plant to remove:"
    if grep -q "$PLANT_NEW" tinybendygrad/uop/ops.bend; then
      echo "lintable-gate: THE LIVE TREE IS PLANTED" >&2
      exit 1
    fi
    echo "lintable-gate: live ops.bend carries neither arm of the mutation"
    ;;

  *)
    need_check tinybendygrad/uop/ops.bend "ops.bend"
    need_check "$PROBE" "the probe"
    if grep -q "$PLANT_NEW" tinybendygrad/uop/ops.bend; then
      echo "lintable-gate: THE LIVE TREE IS PLANTED" >&2
      exit 1
    fi
    # The oracle prints `#bend_only_<name>: <reason>` INSTEAD of a row for the ones
    # CPython cannot decide, and those names are then dropped from the bend lanes
    # too. A row only one lane can decide is not a check.
    .venv/bin/python "$GT/lintable-oracle.py" > "$GT-oracle.txt"
    grep '^#bend_only_' "$GT-oracle.txt" | sed 's/^#bend_only_\([a-z0-9_]*\):.*/\1/' | sort > "$GT-bendonly.txt"
    grep '^[a-z0-9_]*=' "$GT-oracle.txt" | sort > "$GT-py.txt"
    run_lane "$GT-bd.txt" ./bin/bend "$PROBE"
    ./bin/bend "$PROBE" -o "$GT.bin"
    run_lane "$GT-bn.txt" "$GT.bin"
    # Filter on the NAME FIELD, not the whole line: `grep -vxF` compares whole lines and
    # the bend lane's lines are `name=value` while the bend-only list is bare names, so
    # `-x` would drop nothing at all.
    awk -F= 'NR==FNR{b[$1]=1;next} !($1 in b)' "$GT-bendonly.txt" - < "$GT-bd.txt" | sort > "$GT-bd.s.txt"
    awk -F= 'NR==FNR{b[$1]=1;next} !($1 in b)' "$GT-bendonly.txt" - < "$GT-bn.txt" | sort > "$GT-bn.s.txt"
    cut -d= -f1 "$GT-py.txt" | sort > "$GT-py.keys"
    cut -d= -f1 "$GT-bd.s.txt" | sort > "$GT-bd.keys"
    if ! diff -q "$GT-py.keys" "$GT-bd.keys" > /dev/null; then
      echo "lintable-gate: the two lanes do not carry the SAME ROW NAMES:" >&2
      diff "$GT-py.keys" "$GT-bd.keys" >&2
      echo "lintable-gate: add the extra one to BEND_ONLY with a reason, or to the oracle" >&2
      exit 1
    fi
    diff "$GT-py.txt" "$GT-bd.s.txt" || { echo "lintable-gate: DISAGREE (interpreted)" >&2; exit 1; }
    diff "$GT-py.txt" "$GT-bn.s.txt" || { echo "lintable-gate: DISAGREE (native)" >&2; exit 1; }
    echo "lintable-gate: $(wc -l < "$GT-py.txt" | tr -d ' ') rows, 3 lanes identical"
    ;;
esac