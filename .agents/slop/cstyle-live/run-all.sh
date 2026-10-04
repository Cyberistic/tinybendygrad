#!/bin/zsh
# run-all.sh -- every number in `.agents/slop/CSTYLE-LIVE.md`, from a clean $TMPDIR.
#
#   zsh .agents/slop/cstyle-live/run-all.sh
#
# NOTHING IN THE REPO TREE IS PATCHED. The scratch tree is a COPY of the whole of
# `tinybendygrad/` (a whole tree, because `agent-core.md` records that a single-file scratch
# copy cannot resolve a relative import and produced 22 phantom blind spots), plus the two
# `.bend` files Stages 1 and 3 add INSIDE that copy. The live `renderer/cstyle.bend` is only
# ever READ.
#
# IF THE LIVE TREE IS MID-EDIT BY ANOTHER UNIT, STAGE 0 SAYS SO AND NAMES THE FILE. It
# happened once during this unit: `./bin/bend tinybendygrad/renderer/cstyle.bend` gave rc=1
# and zero rows, naming `i64_dec.go2` at `helpers.bend:2583` -- a DO-NOT-TOUCH file that is
# not this unit's. The snapshot is taken either way and its `helpers.bend` hash is printed, so
# every downstream number is attributable to a tree state.
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
BEND=$REPO/bin/bend
L=$REPO/.agents/slop/cstyle-live
W="$TMPDIR/cstyle-live"

print -r -- "=== STAGE 0: snapshot the tree, and report the live tree's health ==="
"$BEND" "$REPO/tinybendygrad/renderer/cstyle.bend" > "$W.probe" 2>"$W.probe.err"
rc=$?
print -r -- "  live ./bin/bend tinybendygrad/renderer/cstyle.bend  rc=$rc  rows=$(grep -c . "$W.probe")"
if [[ $rc -ne 0 ]]; then
  print -r -- "  !! THE LIVE TREE DOES NOT COMPILE RIGHT NOW. Not this unit's file:"
  head -8 "$W.probe.err" | sed 's/^/     /'
  print -r -- "     Everything below runs against the SNAPSHOT, whose hashes are printed."
fi
rm -f "$W.probe" "$W.probe.err"

rm -rf "$W"
mkdir -p "$W/tree"
# ⚠ `cp -R src "$W/tree/"` when `$W/tree` DOES NOT EXIST renames the directory to `tree`, so
# the whole tree lands at `$W/tree/*` and every downstream `$W/tree/tinybendygrad/...` path is
# missing. The `mkdir -p` is load-bearing, not hygiene: without it the hashes print EMPTY
# (shasum writes its "No such file" to stderr and nothing to stdout) and the script then
# reports "the snapshot DIFFERS from the live one" and exits 3 -- a FALSE alarm about a
# concurrent agent, manufactured by a missing directory. MEASURED, twice.
cp -R "$REPO/tinybendygrad" "$W/tree/"
for f in "$W/tree/tinybendygrad/helpers.bend" "$W/tree/tinybendygrad/renderer/cstyle.bend"; do
  [[ -f $f ]] || { print -r -- "  !! the snapshot is missing $f -- nothing below can run"; exit 3; }
done
# THE ONE FILE THIS UNIT ADDS TO THE SNAPSHOT, and it lives in `.agents/slop/cstyle-live/`
# rather than in the repo tree: it imports `./cstyle.bend`, so it has to sit BESIDE it to
# resolve, and the snapshot is the only place it ever does. MEASURED: a fresh snapshot
# without this line fails at step 1 of every stage with "step1 bend FAILED for
# emit-real.bend", which names a missing HARNESS rather than a missing kernel.
cp "$L/emit-real.bend" "$W/tree/tinybendygrad/renderer/emit-real.bend"
print -r -- "  snapshot helpers.bend sha256 $(shasum -a 256 "$W/tree/tinybendygrad/helpers.bend" | cut -d' ' -f1)"
print -r -- "  snapshot cstyle.bend  sha256 $(shasum -a 256 "$W/tree/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)"
print -r -- "  live    cstyle.bend  sha256 $(shasum -a 256 "$REPO/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)"
if cmp -s "$W/tree/tinybendygrad/renderer/cstyle.bend" "$REPO/tinybendygrad/renderer/cstyle.bend"; then
  print -r -- "  the snapshot's cstyle.bend is IDENTICAL to the live one"
else
  print -r -- "  !! the snapshot's cstyle.bend DIFFERS from the live one -- a concurrent agent"
  print -r -- "     is mid-edit on renderer/cstyle.bend. STOP and reconcile before trusting"
  print -r -- "     any number below.  (This unit's mandate is cstyle.bend, so that is exactly"
  print -r -- "     the file a conflicting unit would be holding.)"
  exit 3
fi

# The gate's own stdout, captured once and used by every stage, so the "recorded text" the
# stages read is the SAME bytes every time rather than a fresh run per stage.
"$BEND" "$W/tree/tinybendygrad/renderer/cstyle.bend" > "$L/port.txt" 2>"$L/port.err" \
  || { print -r -- "  snapshot does not compile either; stopping"; exit 1; }
print -r -- "  port.txt: $(grep -c . "$L/port.txt") lines captured from the snapshot"

print -r -- ""
print -r -- "######################################################## STAGE 1"
print -r -- ""
zsh "$L/stage1.sh" 2>&1 | tee "$L/stage1.log"
print -r -- ""
print -r -- "######################################################## STAGE 2"
print -r -- ""
zsh "$L/stage2.sh" 2>&1 | tee "$L/stage2.log"
print -r -- ""
print -r -- "######################################################## STAGE 3"
print -r -- ""
zsh "$L/stage3.sh" 2>&1 | tee "$L/stage3.log"
print -r -- ""
print -r -- "######################################################## STAGE 4 (the conversion)"
print -r -- ""
python3 "$L/convert.py" "$L/port.txt" --tsv "$L/conversion.tsv"