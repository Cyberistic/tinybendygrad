#!/bin/sh
# arena-sweep-control.sh -- REVERT the fix and re-run the sweep, to show the sweep CAN see it.
#
# A sweep that reports "NO SIZE-SENSITIVE ROW" on a fixed port proves nothing unless the same
# sweep reports a size-sensitive row on the DEFECTIVE one. This does exactly that: it puts
# the literal `0` back into `pl_step`'s two arms in a $TMPDIR COPY, never in the live tree,
# asserts the copy's digest differs from the live file's, runs the same sweep at the same six
# sizes, and reports whether the reverted port is size-sensitive.
#
# NEVER PATCH THE LIVE TREE FROM A HARNESS. The copy is made with the whole `tinybendygrad/`
# subtree beside it, because a $TMPDIR scratch file cannot resolve a relative import and
# that produced 22 phantom blind spots in one unit (agent-core).
set -u
T=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/arena-sweep-control
SRC=$PWD

rm -rf "$T"
mkdir -p "$T/.agents/slop"
cp -R "$SRC/tinybendygrad" "$T/tinybendygrad"
cp "$SRC/bin/bend" "$T/bend" 2>/dev/null || true
cp "$SRC/.agents/slop/arena-sweep-jit.bend" "$T/.agents/slop/"

# TWO INJECTIONS, BECAUSE THE FIRST ONE ANSWERED "THE SWEEP IS BLIND" AND THAT IS A FINDING
# ABOUT THE SWEEP, NOT A FINDING ABOUT THE FIX.
#
#   INJECTION A -- WRONG CONSTANT (`[h]` -> `[0]`). This is the defect just fixed. The sweep
#     reports it as CONSTANT, and that is CORRECT: index 0 is the arena bottom in EVERY size,
#     so padding cannot separate "the node" from "the bottom". A wrong constant is a
#     NOOP-scan finding, not a size-sweep finding, and conflating the two detectors would
#     have had me report a clean size sweep as evidence for a fix it cannot see.
#
#   INJECTION B -- WRONG INDEX (`h` -> `U32.add(h, 1)`). This is the `l2i_cdiv.abs` class the
#     sweep was BUILT for: a wrong index that names a real node in some arena and a different
#     real node in another. `next=` in the banner moves with k, so the index the wrong read
#     resolves to moves with it, and the sweep must report size-sensitivity.
case "${1:-A}" in
  A) DESC="WRONG CONSTANT: pl_step appends the arena bottom [0] instead of the node [h]" ;;
  B) DESC="WRONG INDEX: pl_step appends [h+1] instead of the node [h]" ;;
  C) DESC="STALE ARENA: the probe reads a node index out of the arena from BEFORE the last mint" ;;
  D) DESC="FIXED WRONG INDEX: pl_step appends the literal [2], whose MEANING depends on how many nodes precede it" ;;
  *) echo "usage: arena-sweep-control.sh [A|B|C|D]"; exit 1 ;;
esac
echo "=== INJECTION ${1:-A}: $DESC"

if [ "${1:-A}" = "C" ]; then
  # The probe is INJECTED, not the tree: `sig.of` is made to read the kept node's index out
  # of an arena that predates it, which is the codegen/__init__.bend:117 shape verbatim.
  python3 - "$T" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1]) / ".agents/slop/arena-sweep-jit.bend"
s = f.read_text()
old = "def sig.of(+r: O.Found) -> String: J.j_sig(O.Found.ar(r), O.Found.i(r))"
new = ("def sig.of(+r: O.Found) -> String:\n"
       "  # STALE: the node was interned into `r`, but this reads it out of the arena `r` had\n"
       "  # BEFORE the mint. The index is past that arena's end, so `Arena.node` answers NOOP.\n"
       "  J.j_sig(O.Arena.empty(), O.Found.i(r))")
if old not in s: sys.exit("INJECTION C DID NOT APPLY")
f.write_text(s.replace(old, new))
PY
  if [ "$?" -ne 0 ]; then echo "injection C failed"; exit 1; fi
else
python3 - "$T" "${1:-A}" <<'PY'
import sys, pathlib
T, which = pathlib.Path(sys.argv[1]), sys.argv[2]
f = T / "tinybendygrad/engine/jit.bend"
s = f.read_text()
rep = {"A": "[0]", "B": "[U32.add(h, 1)]", "D": "[2]"}[which]
a = s.replace("List.append(&2, U32, Prune.kept(p), [h])",
              "List.append(&2, U32, Prune.kept(p), " + rep + ")")
a = a.replace("List.append(&2, U32, Prune.once(p), [h])",
              "List.append(&2, U32, Prune.once(p), " + rep + ")")
if a == s:
    sys.exit("INJECTION DID NOT APPLY -- the fix is not in the expected shape")
f.write_text(a)
PY
  if [ "$?" -ne 0 ]; then echo "injection failed"; exit 1; fi
fi

# ASSERT THE DIGESTS DIFFER, so "I edited the copy" is a checked claim and not an assumption.
# BOTH files are asserted, because injection C edits the PROBE and not the tree, and an
# assertion that only looked at the tree correctly refused C as a no-op.
d_live=$(md5 -q "$SRC/tinybendygrad/engine/jit.bend")
d_copy=$(md5 -q "$T/tinybendygrad/engine/jit.bend")
p_live=$(md5 -q "$SRC/.agents/slop/arena-sweep-jit.bend")
p_copy=$(md5 -q "$T/.agents/slop/arena-sweep-jit.bend")
echo "tree  jit.bend  live $d_live / copy $d_copy"
echo "probe sweep.bend live $p_live / copy $p_copy"
if [ "$d_live" = "$d_copy" ] && [ "$p_live" = "$p_copy" ]; then
  echo "BOTH DIGESTS EQUAL -- the injection did not land, the control is meaningless"
  exit 1
fi
echo "at least one digest differs: the control copy carries the injection and the live tree does not"
echo

OUT=$T/sweep.txt
i=0
while [ "$i" -lt 12 ]; do
  i=$((i + 1))
  # Run bend FROM THE REPO ROOT so `references/bend` resolves, on the COPY's probe. The
  # probe's own relative imports (`./../../tinybendygrad/...`) then resolve to the copy,
  # because the copy carries the same `.agents/slop/` -> repo layout.
  (cd "$SRC" && perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$T/.agents/slop/arena-sweep-jit.bend") > "$OUT" 2>"$OUT.err"
  if grep -q '^# k=' "$OUT"; then break; fi
  sleep 8
done

if ! grep -q '^# k=' "$OUT"; then
  echo "CONTROL SWEEP FAILED after $i attempts -- zero rows" >&2
  head -3 "$OUT.err" >&2
  exit 1
fi

echo "=== CONTROL: the sweep on the REVERTED port, same six sizes"
grep '^# k=' "$OUT"
echo
grep -E '^prune_sig' "$OUT" | sort | uniq -c | sed 's/^/  /'
echo
grep -v '^# k=' "$OUT" | grep -v '^[[:space:]]*$' > "$OUT.rows"
sizes=$(grep -c '^# k=' "$OUT")
n=$(wc -l < "$OUT.rows" | tr -d ' ')
u=$(sort -u "$OUT.rows" | wc -l | tr -d ' ')
maxc=$(sort "$OUT.rows" | uniq -c | sort -rn | head -1 | awk '{print $1}')
echo "  $n lines, $u distinct, max copies of one row = $maxc over $sizes sizes"
if [ "$u" = "$((n / sizes))" ] && [ "$maxc" = "$sizes" ]; then
  case "${1:-A}" in
    A) echo "  RESULT: CONSTANT -- CORRECT. A wrong CONSTANT is not size-sensitive: index 0 is"
       echo "    the arena bottom in every size, so padding cannot separate it from a node."
       echo "    This defect class belongs to arena-noop-scan.py, which DOES detect it." ;;
    B) echo "  RESULT: CONSTANT -- MEASURED BLIND SPOT. Prepending k nodes shifts EVERY index by"
       echo "    k, so a wrong index at a FIXED OFFSET keeps naming the same relative node." ;;
    C) echo "  RESULT: CONSTANT -- MEASURED BLIND SPOT, and it is the same mechanism as B: a read"
       echo "    past the end of an arena reads NOOP at every size, because the pre-mint arena"
       echo "    never contains the index at any k. Stale-arena reads are caught by the NOOP scan." ;;
    D) echo "  RESULT: SIZE-SENSITIVE -- padding HAS POWER, and only on this shape: an index"
       echo "    whose MEANING depends on how many nodes precede it. This is the class dd-sweep"
       echo "    was written for, and it is NARROWER than 'arena aliasing'." ;;
  esac
else
  echo "  RESULT: SIZE-SENSITIVE -- the sweep DETECTS the injected defect; it has power"
  sort "$OUT.rows" | uniq -c | sort -rn | sed 's/^/    /'
fi