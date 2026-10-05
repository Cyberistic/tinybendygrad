#!/bin/sh
# THE PLANT/DISARM HARNESS for `compute_gradient`'s walk.  ONE STEP, run from the repo
# root:  sh checks/walk-mutate.sh <arm>
#
# arms: base plant_reverse plant_noguard disarm_comment disarm_name
#
# WHY IT IS BUILT THE WAY IT IS, and each of these is a trap this repo has already paid
# for:
#   * $TMPDIR AND A REAL `cp -R`.  Notes T-2: an absolute `import` is refused and a
#     SYMLINK mirror breaks hub detection, so an ordinary `import ./helpers.bend` fails
#     with the error a symlink mirror produces.  The live tree is never patched.
#   * A CONTROL PROBE FIRST.  Notes T-1: a plant that fails for MY OWN reason is not a
#     result, so the base arm is compiled and printed before any plant, and a plant that
#     does not reach the port is reported as INCONCLUSIVE rather than as a verdict.
#   * EVERY EDIT ASSERTS THE REPLACED FILE, BY RE-READING IT.  Counting occurrences is
#     NOT asserting an edit -- this harness's first version did `s.count(old)` and never
#     called `s.replace`, printed "1 occurrence(s) replaced", and produced a VACUOUS plant
#     that reported "rows that MOVED: 0" for a mutation that had changed nothing.  That is
#     the brief's own failure mode ("two units this session published a green mutation for
#     a mutant that never applied") and the assertion below is what catches it.
#   * THE DIFFER DIFFS WHOLE `name=value` LINES.  agent-core: "a name-comparing harness
#     reported 0 for all 30 mutations in one unit and 0 for all 68 in another".  This one
#     diffs two whole runs and names each row that moved.
#   * A PLANT WITH NO PAIRED DISARM IS NOT REPORTED AS A RESULT.  Both are run.
#   * stderr IS PRINTED on any zero, so a substrate failure is distinguishable from a
#     real one.  It fired once for real: see walk-plant.md, "THE SUBSTRATE MOVED".
set -u
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
W="$TMPDIR/walkplant"
# THE BASE IS PERSISTED OUTSIDE $W, because each arm wipes and re-copies $W and a differ
# that compares against a base it just deleted reports nothing at all.
BASE="$TMPDIR/walkbase.txt"
ARM="${1:-base}"

rm -rf "$W"; mkdir -p "$W"
cp -R "$ROOT/tinybendygrad" "$W/tinybendygrad"
F="$W/tinybendygrad/mixin/gradient.bend"
BASE_SHA=$(shasum -a 256 "$F" | cut -d' ' -f1)
echo "=== arm=$ARM  live tree NOT touched; working copy sha256=$BASE_SHA"

# $1 = file, $2 = old, $3 = new, $4 = label.  Replaces, writes, RE-READS, asserts.
apply() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, pathlib
f, old, new, label = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(f); s = p.read_text()
n = s.count(old)
if n != 1:
    print("    %s: %d occurrence(s) of the target, expected 1 -- VACUOUS, NO VERDICT" % (label, n))
    sys.exit(3)
out = s.replace(old, new)
p.write_text(out)
# THE ASSERTION IS THE BYTES, NOT THE STRINGS: an earlier version of this harness tested
# `old in back`, which is TRUE for any `new` that merely EXTENDS `old`, so a perfectly good
# edit was rejected and a perfectly bad one would have been too.  What matters is that the
# file on disk is DIFFERENT from the file that was read, and that the new text is in it.
back = p.read_text()
if back == s or back.count(new) != 1:
    print("    %s: WRITE DID NOT LAND (bytes unchanged, or the new text is absent) -- VACUOUS, NO VERDICT" % label)
    sys.exit(3)
print("    %s: applied and VERIFIED (the file on disk differs and contains the new text)" % label)
PY
}

case "$ARM" in
  base) : ;;
  # PLANT 1 -- the WALK'S CONTROL FLOW.  gradient.py:119 is `for t0 in reversed(walk)`;
  # dropping the `reverse` walks in TOPOSORT order instead, so the root -- the LAST node
  # the toposort completes, and the only seeded key -- is visited first and every other
  # walk node then hits gradient.py:120's `continue`.
  plant_reverse)
    apply "$F" \
      "cg_step(List.reverse(&2, U32, Deep.walk_of(_deepwalk(root, targets, ar)))," \
      "cg_step(Deep.walk_of(_deepwalk(root, targets, ar))," \
      "plant_reverse: reversed(walk) -> walk" || exit 3 ;;
  # PLANT 2 -- the INPATH GUARD.  gradient.py:114 is
  # `[node for node in in_target_path if node.op is not Ops.DETACH and in_target_path[node]]`;
  # dropping the flag keeps every toposort node, targets included.
  plant_noguard)
    apply "$F" \
      "  Bool.and(f, Bool.not(O.op_is(ar, x, O.OpsDETACH{})))" \
      "  Bool.and(True{}, Bool.not(O.op_is(ar, x, O.OpsDETACH{})))" \
      "plant_noguard: in_target_path[node] -> True{}" || exit 3 ;;
  # DISARM A -- a COMMENT's text.  Nothing the walk reads.
  disarm_comment)
    apply "$F" \
      "# THE FLAG PASS. ONE forward pass over the toposort, and the FLAG IS COMPUTED ON THE" \
      "# THE FLAG PASS. ONE forward pass over the toposort, and the FLAG IS COMPUTED ON THE -- DISARMED COMMENT, TEXT ONLY" \
      "disarm_comment: comment text" || exit 3 ;;
  # DISARM B -- a LOCAL PARAMETER NAME, renamed in its signature AND in its body, in one
  # def the walk does not reach.
  disarm_name)
    apply "$F" \
      "def dag_join(+tok: String, +acc: String) -> String:" \
      "def dag_join(+tok_renamed_for_disarm: String, +acc: String) -> String:" \
      "disarm_name: parameter tok -> tok_renamed_for_disarm (signature)" || exit 3
    apply "$F" \
      "            String.concat([acc, tok]), String.concat([acc, \" \", tok]))" \
      "            String.concat([acc, tok_renamed_for_disarm]), String.concat([acc, \" \", tok_renamed_for_disarm]))" \
      "disarm_name: parameter tok -> tok_renamed_for_disarm (body)" || exit 3 ;;
  *) echo "UNKNOWN ARM $ARM"; exit 2 ;;
esac

"$ROOT/bin/bend" "$F" --check-only > "$W/check.txt" 2>&1
echo "=== arm=$ARM  check-only: $(head -1 "$W/check.txt")"
"$ROOT/bin/bend" "$F" > "$W/$ARM.txt" 2> "$W/$ARM.err"
RC=$?
echo "=== arm=$ARM  run rc=$RC  rows=$(wc -l < "$W/$ARM.txt" | tr -d ' ')"
if [ "$RC" != 0 ] || [ ! -s "$W/$ARM.txt" ]; then
  echo "=== INCONCLUSIVE (T-1): the substrate failed, not the code.  stderr:"; cat "$W/$ARM.err"; exit 1
fi
grep '^walk_' "$W/$ARM.txt"

echo "=== DIFFER vs base (whole name=value lines, NOT row names):"
if [ "$ARM" = base ]; then
  cp "$W/$ARM.txt" "$BASE"
  echo "    (this IS the base; persisted at $BASE)"
  exit 0
fi
[ -f "$BASE" ] || { echo "    NO BASE -- run 'sh $0 base' FIRST, or the differ has nothing to compare against"; exit 1; }
echo "    sha256 of the planted file: $(shasum -a 256 "$F" | cut -d' ' -f1)  (base was $BASE_SHA)"
echo "    sha256 of the port's OUTPUT: $(shasum -a 256 "$W/$ARM.txt" | cut -d' ' -f1)"
echo "    sha256 of the BASE OUTPUT : $(shasum -a 256 "$BASE" | cut -d' ' -f1)"
MOVED=$(diff "$BASE" "$W/$ARM.txt" | grep -c '^<' || true)
echo "    rows that MOVED: $MOVED"
diff "$BASE" "$W/$ARM.txt" | grep -E '^[<>]' | sed 's/^/    /' || echo "    NOTHING MOVED -- THE PLANT DID NOT APPLY"