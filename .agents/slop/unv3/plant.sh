#!/usr/bin/env bash
# plant.sh -- THE PLANT: A TEXT EDIT ON A COPY THAT BREAKS ONE RE-POINTED CITATION.
#
#   .agents/slop/unv3/plant.sh
#
# THE PLANT IS A TEXT EDIT ON A COPY. NEVER ON THE TREE.
#
# IT TAKES TWO COPIES OF THE FROZEN TREE:
#   1. THE CONTROL -- byte-identical to the tree under test. The gate must stay GREEN.
#   2. THE PLANT   -- ONE re-pointed citation broken, so the gate goes RED on THAT ROW.
#
# TWO PLANTS, ONE PER GATE, AND BOTH BREAK A CITATION THIS SLICE FIXED:
#
#   PLANT A -- `gates/pin-cite-gate.py`. The claim token of a re-pointed UPSTREAM
#     citation is broken (`synchronize` -> `synchronise`), so the row's claim tokens no
#     longer occur in the cited upstream file. `unverifiable` is a COUNTED class, so the
#     gate's COUNT moves (36 -> 37) and the row is NAMED. The gate does not go RED on
#     it, because `unverifiable` is by design counted and not verdicted -- and THAT IS
#     THE POINT: the class this slice emptied is a class the gate REPORTS, and the
#     report is what says the count went up.
#
#   PLANT B -- `gates/bendcite-gate.py`. The claim token of a re-pointed PORT-to-PORT
#     citation is broken (`nn_linear` -> `nn_linea`), so the cited line no longer HOLDS
#     the claim. `WRONG-LINE` IS A FAILURE, so the gate's EXIT CODE MOVES.
set -u
cd "$(dirname "$0")/../../.." || exit 3
ROOT="$PWD"
BASE=".agents/slop/unv3/work-plant"
rm -rf "$BASE"; mkdir -p "$BASE"
for d in control plant; do
  cp -R ".agents/slop/unv3/work-final2/." "$BASE/$d/"
done
echo "=== PLANT A -- pin-cite-gate: break the CLAIM TOKEN of a re-pointed UPSTREAM citation."
.venv/bin/python - "$BASE/plant/tinybendygrad/runtime/ops_disk.bend" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
old = "#   tinygrad/runtime/ops_disk.py:14  `synchronize`              PORTED  `dev_sync` -- it is `pass`\n"
new = "#   tinygrad/runtime/ops_disk.py:14  `synchronise`              PORTED  `dev_sync` -- it is `pass`\n"
assert t.count(old) == 1, t.count(old)
p.write_text(t.replace(old, new))
print("PLANTED A: `synchronize` -> `synchronise`")
PY
for d in control plant; do
  .venv/bin/python gates/pin-cite-gate.py --tree "$BASE/$d" --rows "$BASE/$d.rows" --no-report >"$BASE/$d.pin.out" 2>&1
  rc=$?
  n=$(awk -F'\t' 'NR>1 && $11=="unverifiable" && $1=="tinybendygrad/runtime/ops_disk.bend"' "$BASE/$d.rows" | wc -l | tr -d ' ')
  tot=$(awk -F'\t' 'NR>1 && $11=="unverifiable"' "$BASE/$d.rows" | wc -l | tr -d ' ')
  echo "  $d: rc=$rc  ops_disk.bend unverifiable=$n  tree unverifiable=$tot"
  grep -E "pin-cite-gate:" "$BASE/$d.pin.out"
done
echo "  THE PLANTED ROW:"
awk -F'\t' 'NR>1 && $1=="tinybendygrad/runtime/ops_disk.bend" && $2==67' "$BASE/plant.rows" | cut -f2,3,4,5,9,11
echo "  THE CONTROL'S SAME ROW:"
awk -F'\t' 'NR>1 && $1=="tinybendygrad/runtime/ops_disk.bend" && $2==67' "$BASE/control.rows" | cut -f2,3,4,5,9,11

echo
echo "=== PLANT B -- bendcite-gate: break the CLAIM TOKEN of a re-pointed PORT-to-PORT citation."
rm -rf "$BASE/plant2"; cp -R "$BASE/control" "$BASE/plant2"
.venv/bin/python - "$BASE/plant2/tinybendygrad/extra/models/llama.bend" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
old = "#   `nn.Linear`           nn/layers.bend:530 symbol=nn_linear `nn_linear`   (:45,:46,:47,:48,:51,:123,:124,:125,:202)\n"
new = "#   `nn.Linear`           nn/layers.bend:527 symbol=nn_linear `nn_linear`   (:45,:46,:47,:48,:51,:123,:124,:125,:202)\n"
assert t.count(old) == 1, t.count(old)
p.write_text(t.replace(old, new))
print("PLANTED B: the POINTER moves :530 -> :527, so the cited line no longer HOLDS `nn_linear`")
PY
for d in control plant2; do
  .venv/bin/python gates/bendcite-gate.py --tree "$BASE/$d" --rows "$BASE/$d.bend.rows" >"$BASE/$d.bend.out" 2>&1
  rc=$?
  n=$(awk -F'\t' 'NR>1 && ($6=="WRONG-LINE" || $6=="DANGLING-LINE") && $1=="tinybendygrad/extra/models/llama.bend"' "$BASE/$d.bend.rows" | wc -l | tr -d ' ')
  tot=$(awk -F'\t' 'NR>1 && ($6=="WRONG-LINE" || $6=="DANGLING-LINE")' "$BASE/$d.bend.rows" | wc -l | tr -d ' ')
  echo "  $d: rc=$rc  llama.bend WRONG-LINE+DANGLING-LINE=$n  tree=$tot"
  grep -E "bendcite-gate:" "$BASE/$d.bend.out"
done
echo "  THE PLANTED ROW:"
awk -F'\t' 'NR>1 && $1=="tinybendygrad/extra/models/llama.bend" && ($6=="WRONG-LINE" || $6=="DANGLING-LINE")' "$BASE/plant2.bend.rows" | cut -f2,3,4,5,6,7,9,11,12
echo "  THE CONTROL'S SAME FILE (it must be EMPTY -- the row RESOLVES):"
awk -F'\t' 'NR>1 && $1=="tinybendygrad/extra/models/llama.bend" && ($6=="WRONG-LINE" || $6=="DANGLING-LINE")' "$BASE/control.bend.rows" | cut -f2,3,4,5,6,7,9,11,12
