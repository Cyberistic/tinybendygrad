#!/bin/zsh
# Measure BOTH instruments on a COPY of the LIVE port tree, and report the counts for
# MY 26 files.
#
# WHY A COPY: the tree is owned by other units and moves under the gate's feet, and the
# two readings (before and after) must be of the SAME tree or they compare two trees.
# WHY THE LIVE TREE AND NOT `git archive HEAD`: `git archive` freezes the OTHER units'
# files at HEAD while my 26 files are the LIVE ones, so a pointer into a file I do not
# own would be measured against the wrong revision of that file.
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
SL=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slice2
FILES=(
  codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
  codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
  extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
  mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
  renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
  runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
  runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend
)
rm -rf "$SL/try"
mkdir -p "$SL/try"
cp -R "$ROOT/tinybendygrad" "$SL/try/tinybendygrad"
# `references/` is GITIGNORED, so `git archive` never carried it, and the COMPILER's
# `base.bend` is the corpus the port's `base.bend:N` pointers are about.
mkdir -p "$SL/try/references/bend"
cp -R "$ROOT/references/bend/bend2" "$SL/try/references/bend/"
cd "$ROOT"
.venv/bin/python gates/pin-cite-gate.py --tree "$SL/try" --rows "$SL/try.rows" --report > "$SL/try.pin.out" 2>&1
.venv/bin/python gates/bendcite-gate.py --tree "$SL/try" --rows "$SL/try.bc.rows" --report > "$SL/try.bc.out" 2>&1
.venv/bin/python - "$SL" <<'PY'
import csv, sys, collections
sl = sys.argv[1]
MINE = set()
for f in """codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend""".split():
  MINE.add("tinybendygrad/"+f)
pin = list(csv.DictReader(open(sl+'/try.rows'), delimiter='\t'))
bc  = list(csv.DictReader(open(sl+'/try.bc.rows'), delimiter='\t'))
pm = [r for r in pin if r['rel'] in MINE]
bm = [r for r in bc if r['rel'] in MINE]
print("PIN-CITE, my 26 files:")
for k,v in sorted(collections.Counter(r['class'] for r in pm).items()): print("   %-22s %d" % (k,v))
print("   unverifiable =", sum(1 for r in pm if r['class']=='unverifiable'))
print("BENDCITE, my 26 files:")
for k,v in sorted(collections.Counter(r['verdict'] for r in bm).items()): print("   %-22s %d" % (k,v))
print("   WRONG-LINE + DANGLING-LINE =", sum(1 for r in bm if r['verdict'] in ('WRONG-LINE','DANGLING-LINE')))
print()
print("REMAINING PIN unverifiable:")
for r in pm:
  if r['class']=='unverifiable': print("   %s:%s %s:%s  tokens=%s" % (r['rel'],r['at'],r['subject'],r['lo'],r['claim']))
print("REMAINING BENDCITE stale:")
for r in bm:
  if r['verdict'] in ('WRONG-LINE','DANGLING-LINE'): print("   %s:%s %s:%s  claim=%s decl=%s target=%s" % (r['rel'],r['at'],r['subject'],r['lo'],r['claim'],r['decl'],r['target']))
PY
