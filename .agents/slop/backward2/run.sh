#!/bin/sh
# THE HARNESS for `grad_set` and the `bw` graph.
#
#   sh .agents/slop/backward2/run.sh <arm>
#
# arms:
#   check           THE GATE: the port's new rows against `rows.rows` (CPython's values).
#   head            THE PRE-EXISTING ROWS: HEAD's `gradient.bend` run against the live
#                   one.  Every pre-existing row must be BYTE-IDENTICAL.
#   base            the clean run, persisted as the differ's baseline.
#   plant_gswap     the MUL rule's operands UNCROSSED -- upstream gradient.py:80 says
#                   `ret.src[1]*ctx`, `ret.src[0]*ctx`.  The swap is invisible to every
#                   count and to the class-only token, so it is the plant that says the
#                   `bw` signature is worth its LOC.
#   plant_nozero    the ZERO SUBSTITUTE replaced by the arena's reserved index 0 -- the
#                   `tensor.bend` DIVERGENCE, moved here.  `gs_set_sig` must go red.
#   plant_setorder  the gradient SET built in reverse order.  The COUNTS do not move;
#                   the order does.  That is the whole reason `gs_set_sig` is a
#                   signature and not a count.
#   plant_nohole    the EXPAND's HOLE filled in -- `gr_18`'s `(ctx, None)` becomes
#                   `(ctx, ctx)`.  `gs_hole_n` must go red.
#   disarm_comment  a comment's text.  Nothing the rows read.
#   disarm_name     a local parameter name.  Nothing the rows read.
#
# EVERY EDIT ASSERTS THE REPLACED FILE BY RE-READING IT.  A plant that did not apply
# is reported as VACUOUS, not as a verdict.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
ROOT=$PWD
W="$TMPDIR/bw2"
BASE="$TMPDIR/bw2base.rows"
ARM="${1:-base}"

rm -rf "$W"; mkdir -p "$W"
cp -R "$ROOT/tinybendygrad" "$W/tinybendygrad"
F="$W/tinybendygrad/mixin/gradient.bend"
export BEND_NO_TELEMETRY=1

# $1 = old, $2 = new, $3 = label.  Replaces, writes, RE-READS, asserts.
apply() {
  python3 - "$F" "$1" "$2" "$3" <<'PY'
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

case "$ARM" in
  base) : ;;
  check) : ;;
  head)
    # HEAD's `gradient.bend`, so the PRE-EXISTING rows can be compared byte for byte.
    env -u GIT_INDEX_FILE git show HEAD:tinybendygrad/mixin/gradient.bend > "$F" || exit 3
    echo "    HEAD's gradient.bend installed: $(shasum -a 256 "$F" | cut -d' ' -f1)"
    ;;
  plant_gswap)
    apply "  +f1 = gmul(ar, O.Arena.src(ar, ret, 1), ctx)" \
          "  +f1 = gmul(ar, O.Arena.src(ar, ret, 0), ctx)" \
          "plant_gswap: the MUL rule's operands UNCROSSED (gradient.py:80)" || exit 3 ;;
  plant_nozero)
    apply "    case Some{d}: gcast(ar, x, d)" \
          "    case Some{d}: O.Found{ar, 0}" \
          "plant_nozero: the ZERO SUBSTITUTE replaced by the reserved index 0" || exit 3 ;;
  plant_setorder)
    apply "    case Some{sl}: GSet{List.append(&2, U32, GSet.slots_of(acc), [GSlot.v_of(sl)])," \
          "    case Some{sl}: GSet{GSlot.v_of(sl) <> GSet.slots_of(acc)," \
          "plant_setorder: the gradient SET built in REVERSE order" || exit 3 ;;
  plant_nohole)
    apply "def gr_18(ar: O.Arena, ctx: U32, +self: U32) -> GRes: fired([ctx, 0], ar)" \
          "def gr_18(ar: O.Arena, +ctx: U32, +self: U32) -> GRes: fired([ctx, ctx], ar)" \
          "plant_nohole: the EXPAND's HOLE filled in (gradient.py:86)" || exit 3 ;;
  plant_noguard)
    apply "  Bool.and(f, Bool.not(O.op_is(ar, x, O.OpsDETACH{})))" \
          "  Bool.and(True{}, Bool.not(O.op_is(ar, x, O.OpsDETACH{})))" \
          "plant_noguard: the in_target_path GUARD dropped (gradient.py:114)" || exit 3 ;;
  plant_skipseed)
    apply "gput.new(Grads{Nil{}, Nil{}}, root, root_grad)" \
          "gput.new(Grads{Nil{}, Nil{}}, root, 0)" \
          "plant_skipseed: the SEED dropped, so the root SKIPS (gradient.py:120)" || exit 3 ;;
  plant_droptarget)
    apply "def gs_targets.of(a: U32, b: U32, z: U32) -> List<&2, U32>: [a, b, z]" \
          "def gs_targets.of(a: U32, b: U32, z: U32) -> List<&2, U32>: [a, b]" \
          "plant_droptarget: the THIRD TARGET dropped, so the set is one shorter" || exit 3 ;;
  plant_flags)
    apply "  Bool.or(dw_read_of(p, x), dw_hit(targets, x))" \
          "  Bool.or(True{}, dw_hit(targets, x))" \
          "plant_flags: the in_target_path FLAG always true (gradient.py:112)" || exit 3 ;;
  disarm_comment)
    apply "# THE GRADIENT SET -- mixin/op.py:471 -- AND THE \`bw\` GRAPH." \
          "# THE GRADIENT SET -- mixin/op.py:471 -- AND THE \`bw\` GRAPH. -- DISARMED COMMENT, TEXT ONLY" \
          "disarm_comment: comment text" || exit 3 ;;
  disarm_name)
    apply "def gs_slot_n(+ar: O.Arena, v: U32) -> String:" \
          "def gs_slot_n(+ar: O.Arena, v_renamed_for_disarm: U32) -> String:" \
          "disarm_name: parameter v (signature)" || exit 3
    apply "  U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, v))))" \
          "  U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, v_renamed_for_disarm))))" \
          "disarm_name: parameter v (body)" || exit 3 ;;
  *) echo "UNKNOWN ARM $ARM"; exit 2 ;;
esac

"$ROOT/bin/bend" "$F" --check-only > "$W/check.out" 2>&1
CHK=$(head -1 "$W/check.out")
"$ROOT/bin/bend" "$F" > "$W/$ARM.rows" 2> "$W/$ARM.err"
RC=$?
echo "=== arm=$ARM  check-only: $CHK  run rc=$RC  rows=$(wc -l < "$W/$ARM.rows" | tr -d ' ')"
if [ "$RC" != 0 ] || [ ! -s "$W/$ARM.rows" ]; then
  echo "=== INCONCLUSIVE: the substrate failed, not the code.  stderr:"; cat "$W/$ARM.err"; exit 1
fi

case "$ARM" in
  head)
    # THE PRE-EXISTING ROWS.  The live tree's run is the reference; HEAD's must be a
    # PREFIX of it, and every difference must be an ADDITION of a NEW row.
    "$ROOT/bin/bend" "$ROOT/tinybendygrad/mixin/gradient.bend" > "$W/live.rows" 2>/dev/null
    echo "=== HEAD vs LIVE: rows head=$(wc -l < "$W/head.rows" | tr -d ' ') live=$(wc -l < "$W/live.rows" | tr -d ' ')"
    # NO PROCESS SUBSTITUTION: `<( )` does not parse under `sh` (the four shell-gate
    # failures `gates/README.md` records), so the sorted files are written out.
    sort "$W/head.rows" > "$W/head.sorted"
    sort "$W/live.rows" > "$W/live.sorted"
    echo "--- rows HEAD has that LIVE does NOT (must be EMPTY):"
    comm -23 "$W/head.sorted" "$W/live.sorted" | sed 's/^/    /'
    echo "--- rows LIVE has that HEAD does NOT (must be EXACTLY the new rows):"
    comm -13 "$W/head.sorted" "$W/live.sorted" | sed 's/^/    /'
    echo "--- rows that CHANGED VALUE (must be EMPTY):"
    "$ROOT/.venv/bin/python" - "$W/head.rows" "$W/live.rows" <<'PY2'
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
    print("    %s: head=%s live=%s" % (k, h[k], l[k]))
print("    rows whose VALUE changed: %d" % n)
PY2
    exit 0 ;;
  check)
    echo "=== THE GATE: the port's new rows against rows.rows (CPython's values)"
    "$ROOT/.venv/bin/python" - "$W/$ARM.rows" "$ROOT/.agents/slop/backward2/rows.rows" <<'PY'
import sys
got = {}
for line in open(sys.argv[1]):
  line = line.rstrip("\n")
  if "=" in line:
    k, _, v = line.partition("=")
    got[k] = v
want = {}
for line in open(sys.argv[2]):
  line = line.rstrip("\n")
  k, _, v = line.partition("=")
  want[k] = v
bad = 0
for k, v in want.items():
  g = got.get(k)
  if g != v:
    bad += 1
    print("    MISMATCH %s" % k)
    print("      want: %s" % v)
    print("      got : %s" % g)
missing = [k for k in want if k not in got]
for k in missing: print("    MISSING ROW %s" % k)
print("    rows compared: %d of %d   mismatched: %d   VERDICT: %s" % (len(want), len(want), bad, "PASS" if bad == 0 and not missing else "FAIL"))
sys.exit(0 if bad == 0 and not missing else 1)
PY
    exit $? ;;
esac

if [ "$ARM" = base ]; then
  cp "$W/$ARM.rows" "$BASE"
  echo "    (this IS the base; persisted at $BASE)"
  exit 0
fi
[ -f "$BASE" ] || { echo "    NO BASE -- run 'sh $0 base' FIRST"; exit 1; }
echo "=== DIFFER vs base (whole name=value lines, NOT row names):"
MOVED=$(diff "$BASE" "$W/$ARM.rows" | grep -c '^<' || true)
echo "    rows that MOVED: $MOVED"
diff "$BASE" "$W/$ARM.rows" | grep -E '^[<>]' | sed 's/^/    /' || echo "    NOTHING MOVED -- THE PLANT DID NOT APPLY"
