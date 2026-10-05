#!/bin/zsh
# plant.sh -- PLANT A DEFECT IN A ROW, THEN DISARM IT, AND COUNT WHAT MOVED.
#
# WHY A PLANT, AND WHY THIS ONE. Every number this unit reports can be produced by a harness
# that is wrong in the same direction as the thing it measures. So the instrument gets a
# defect it has never seen and has to notice.
#
# THE PLANT IS CHOSEN TO MOVE THE *FOURTH* COLUMN. `cc` accepts a file, the binary runs, and
# the numbers match tinygrad are three obligations, and the plant is aimed at the third
# precisely because the first two cannot see it. A plant that broke `cc` would only prove the
# first gate works.
#
# THE PLANT IS ONE TOKEN in `cstyle.bend`'s OWN fixture, `g_kernel()`: `val0[0]+1.0f` becomes
# `val0[0]-1.0f`. That is the kernel body every `kern2` row splices, so a correct instrument
# must report 6 rows changing their NUMBERS while `cc` and the link stay green. An
# instrument that reported "22 compiled, 30 ran" for the planted tree exactly as for the
# clean one would be measuring nothing.
#
# THE PLANT LIVES IN $TMPDIR. The live `tinybendygrad/` tree is never written to, and this
# script ASSERTS that by hashing `renderer/cstyle.bend` before and after.
set -euo pipefail
REPO=${REPO:?set REPO to the repo root}
W=${W:?set W to a $TMPDIR workdir}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$W"
SNAP="$W/tree/tinybendygrad/renderer/cstyle.bend"

live_before=$(shasum -a 256 "$REPO/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)
if [ ! -f "$SNAP" ]; then
  mkdir -p "$W/tree"
  cp -R "$REPO/tinybendygrad" "$W/tree/"
fi
clean=$(shasum -a 256 "$SNAP" | cut -d' ' -f1)
cp "$SNAP" "$W/cstyle.clean.bend"

run () {  # run <label>  -- the whole chain, from the bend run to gate 3
  local label=$1
  ( cd "$REPO" && ./bin/bend "$W/tree/tinybendygrad/renderer/cstyle.bend" \
      > "$W/port.$label.txt" 2> "$W/port.$label.err" )
  python3 "$HERE/derive.py" "$W/tree/tinybendygrad/renderer/cstyle.bend" "$W/port.$label.txt" \
      > "$W/derive.$label.txt" 2>&1 || true
  python3 "$HERE/measure.py" "$W/tree/tinybendygrad/renderer/cstyle.bend" "$W/port.$label.txt" \
      --tsv "$W/four-col.$label.tsv" > "$W/four-col.$label.txt" 2>&1 || true
  python3 "$HERE/convert2.py" "$W/port.$label.txt" --preamble "$HERE/preamble.txt" \
      --decl-from hipocml --tsv "$W/convert2.$label.tsv" > "$W/convert2.$label.txt" 2>&1
  CS2_REPO="$REPO" python3 "$HERE/agree.py" "$W/convert2.$label.tsv" \
      > "$W/agree.$label.txt" 2> "$W/agree.$label.err" || true
}

plant () {
  # ONE token, in the port's own fixture. The guard asserts the anchor occurred EXACTLY once:
  # a sed that matched nothing would leave a "planted" tree identical to the clean one and
  # every number below would be a green lie.
  # The anchor is the WHOLE g_kernel list literal, not the `+` alone: `val0[0]+1.0f` occurs
  # 31 times (30 of them in `kern2_row`'s `py=` oracle literals), and an anchor that matched
  # them all would be a 31-row plant. The first version of this guard DID match 31, printed
  # the count, and refused -- which is the guard working and is why the anchor is this long.
  local anchor=', "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]'
  local before after
  before=$(grep -cF -- "$anchor" "$W/tree/tinybendygrad/renderer/cstyle.bend")
  [ "$before" = 1 ] || { echo "plant: anchor occurs $before times, expected 1. REFUSING."; return 1; }
  perl -0pi -e 's/\Q= (float4){(val0[0]+1.0f)};"\E/= (float4){(val0[0]-1.0f)};"/g' \
    "$W/tree/tinybendygrad/renderer/cstyle.bend"
  after=$(grep -cF ', "  *((float4*)((data0_4+0))) = (float4){(val0[0]-1.0f)};"]' \
    "$W/tree/tinybendygrad/renderer/cstyle.bend")
  [ "$after" = 1 ] || { echo "plant: the edit did not land. REFUSING."; return 1; }
  echo "plant: 1 token changed in g_kernel(); cstyle.bend $clean -> $(shasum -a 256 "$W/tree/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)"
}

disarm () {
  cp "$W/cstyle.clean.bend" "$W/tree/tinybendygrad/renderer/cstyle.bend"
  local now
  now=$(shasum -a 256 "$W/tree/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)
  [ "$now" = "$clean" ] || { echo "disarm: hash $now != clean $clean. REFUSING."; return 1; }
  echo "disarm: restored, hash back to $clean"
}

echo "=== the live tree, hashed before anything runs ==="
echo "  renderer/cstyle.bend $live_before"
echo
echo "=== BASELINE (clean snapshot) ==="
run clean
grep -E "GATE (1|2)" "$W/convert2.clean.txt"
grep -E "^GATE 3" "$W/agree.clean.txt"
grep -E "COMPILES|TEXT  |EXECUTES|AGREES " "$W/four-col.clean.txt" | head -4
echo
echo "=== PLANT ==="
plant
run planted
grep -E "GATE (1|2)" "$W/convert2.planted.txt"
grep -E "^GATE 3" "$W/agree.planted.txt"
grep -E "COMPILES|TEXT  |EXECUTES|AGREES " "$W/four-col.planted.txt" | head -4
echo
echo "=== DISARM ==="
disarm
run disarmed
grep -E "GATE (1|2)" "$W/convert2.disarmed.txt"
grep -E "^GATE 3" "$W/agree.disarmed.txt"
grep -E "COMPILES|TEXT  |EXECUTES|AGREES " "$W/four-col.disarmed.txt" | head -4
echo
echo "=== WHAT MOVED, BY ROW NAME (never by row index) ==="
for col in four-col convert2; do
  for f in "gate1_cc" "gate2_run" "bits"; do
    :
  done
  echo "-- $col.tsv: rows whose value in any column differs between clean and planted"
  python3 - "$W/$col.clean.tsv" "$W/$col.planted.tsv" <<'PY'
import csv, sys
def load(p):
    with open(p) as fh:
        return {r["row"]: r for r in csv.DictReader(fh, delimiter="\t")}
a, b = load(sys.argv[1]), load(sys.argv[2])
moved = [k for k in sorted(a) if a[k] != b.get(k)]
print(f"   rows present clean={len(a)} planted={len(b)}   rows whose record differs: {len(moved)}")
for k in moved[:12]:
    diff = [c for c in a[k] if a[k][c] != b[k].get(c)]
    print(f"     {k!r:<28} columns changed: {','.join(diff)}")
PY
done
echo
echo "=== PLANT 2 -- aimed at the FIRST gate, to show it is load-bearing too ==="
echo '    sig_args joins the kernel parameters with ", "; changed to "; ". One token,'
echo '    and it makes every kern2 signature invalid C, so cc must notice.' 
cp "$W/cstyle.clean.bend" "$W/tree/tinybendygrad/renderer/cstyle.bend"
before=$(grep -cF 'String.join(add(args, extra), ", ")' "$W/tree/tinybendygrad/renderer/cstyle.bend")
[ "$before" = 1 ] || { echo "plant2: anchor occurs $before times, expected 1. REFUSING."; exit 1; }
perl -0pi -e 's/\QString.join(add(args, extra), ", ")\E/String.join(add(args, extra), "; ")/g' \
  "$W/tree/tinybendygrad/renderer/cstyle.bend"
after=$(grep -cF 'String.join(add(args, extra), "; ")' "$W/tree/tinybendygrad/renderer/cstyle.bend")
[ "$after" = 1 ] || { echo "plant2: the edit did not land. REFUSING."; exit 1; }
echo "plant2: sig_args now joins with \"; \"; cstyle.bend $clean -> $(shasum -a 256 "$W/tree/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)"
run planted2
grep -E "GATE (1|2)" "$W/convert2.planted2.txt"
grep -E "^GATE 3" "$W/agree.planted2.txt"
grep -E "COMPILES|TEXT  " "$W/four-col.planted2.txt" | head -2
disarm
run disarmed2
grep -E "GATE (1|2)" "$W/convert2.disarmed2.txt"
grep -E "^GATE 3" "$W/agree.disarmed2.txt"
python3 - "$W/convert2.clean.tsv" "$W/convert2.planted2.tsv" <<'PY'
import csv, sys
def load(p):
    with open(p) as fh:
        return {r["row"]: r for r in csv.DictReader(fh, delimiter="\t")}
a, b = load(sys.argv[1]), load(sys.argv[2])
moved = [k for k in sorted(a) if a[k] != b.get(k)]
print(f"   plant2 moved {len(moved)} rows: {[k for k in moved][:8]}")
PY
echo
echo "=== THE LIVE TREE, hashed after ==="
live_after=$(shasum -a 256 "$REPO/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)
echo "  renderer/cstyle.bend $live_after"
[ "$live_before" = "$live_after" ] && echo "  UNTOUCHED: the plant never left \$TMPDIR" || { echo "  *** THE LIVE TREE CHANGED ***"; exit 3; }