#!/bin/sh
# nl-control.sh -- THE CONTROL MATRIX for `renderer/nir_llvmir.bend`.  Every cell is a real process
# and every `rc` is the rc of THAT process, captured immediately after it and before any `grep`.
#
# The shape of the argument, and why each cell is there:
#
#   0   `--unrename` reproduces the captured PRE-rename lane BYTE FOR BYTE, so cell 2 is the tree's
#       own pre-rename output and not a reconstruction of it.
#   1   PRE-GUARD gate (nl-gate-noguard.py, no reshape) on the PRE-RENAME bytes: the verdict the
#       tree had.  MUST be AGREE, rc=0.
#   2   GUARDED gate on the SAME bytes: same values, same byte diff.  MUST move to BROKEN.
#   3   GUARDED gate on the POST-RENAME bytes: the rename, measured.  `=` MUST be 0.
#   4   GUARDED gate + a NAME PLANT on BOTH lanes -- the control a value plant cannot fake:
#       `disagree=[]`, every VALUE agrees, the byte diff is empty, and the verdict moves on the
#       NAME lane alone.
#   5   GUARDED gate + a VALUE PLANT -- the falsification: `eq` stays 0 while the lane goes
#       BROKEN, so a name check that a value plant can turn green is not testing the name.
#   6   `--selftest` over the real 205-line lane.
#
# NOTHING HERE PATCHES THE TREE.  `--unrename`, `--plant` and `--plant-shape` rewrite CAPTURED
# BYTES in memory, on both lanes, and say so on every run.
set -u
G=.agents/slop/eq/nl-gate.py
N=.agents/slop/eq/nl-gate-noguard.py
PRE=.agents/slop/eq/nl-pre-port.txt
POST=.agents/slop/eq/nl-port-post.txt
C=.agents/slop/eq
PY=.venv/bin/python

# One cell: run the gate, capture ITS rc, then show only the lines that carry the numbers.
cell() {
  title="$1"; shift
  out="$C/nl-cell-$1.txt"; shift
  echo "=============================================================================="
  echo "$title"
  echo "=============================================================================="
  $PY "$@" > "$out" 2>&1
  echo "rc=$?"
  grep -E 'planted |unrenamed|^port |^lane |^port +[0-9]|^oracle +[0-9]|^gated|^  (clean|value|shape|collide) |^SELFTEST|^BROKEN|^AGREE|^STALE|^port rows|BYTE-IDENTICAL' "$out" \
    | cut -c1-190
}

{
echo "=============================================================================="
echo "0. --unrename REPRODUCES THE CAPTURED PRE-RENAME LANE (so cell 2 is not a reconstruction)"
echo "=============================================================================="
$PY - <<'EOF'
import importlib.util, hashlib, pathlib
spec = importlib.util.spec_from_file_location("g", ".agents/slop/eq/nl-gate.py")
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
live = pathlib.Path(".agents/slop/eq/nl-port-post.txt").read_text()
pre = pathlib.Path(".agents/slop/eq/nl-pre-port.txt").read_text()
un = g.unrename(live)
eq = sum(1 for l in un.splitlines() if "=" in (g.row_strict(l)[0] or ""))
print(f"unrename(post) == the captured pre-rename port stdout: {un == pre}   "
      f"md5 {hashlib.md5(un.encode()).hexdigest()[:8]} vs "
      f"{hashlib.md5(pre.encode()).hexdigest()[:8]}   "
      f"names containing '=' in the unrenamed lane: {eq}")
EOF

echo
cell "1. PRE-GUARD gate (no coverage guard) on the PRE-RENAME bytes -- the verdict the tree had" \
     1 $N --port-stdout "$PRE" --oracle-stdout "$PRE"

echo
cell "2. GUARDED gate on the SAME PRE-RENAME bytes -- same values, same byte diff" \
     2 $G --port-stdout "$PRE" --oracle-stdout "$PRE"

echo
cell "3. GUARDED gate on the POST-RENAME bytes" \
     3 $G --port-stdout "$POST" --oracle-stdout "$POST"

echo
cell "4. GUARDED gate, POST-RENAME + a NAME PLANT on BOTH lanes -- THE CONTROL" \
     4 $G --port-stdout "$POST" --oracle-stdout "$POST" \
     --plant-shape "sd cpullvm LLVM osx True" "sd cpullvm LLVM osx=True" \
     --plant-shape "sd cpullvm LLVM osx False" "sd cpullvm LLVM osx=False" \
     --plant-shape "sd cpullvm arm osx True" "sd cpullvm arm osx=True" \
     --plant-shape "sd cpullvm arm osx False" "sd cpullvm arm osx=False"

echo
cell "5. GUARDED gate, POST-RENAME + a VALUE PLANT -- THE FALSIFICATION" \
     5 $G --port-stdout "$POST" --oracle-stdout "$POST" --plant "ldt f32"

echo
cell "6. --selftest over the real 205-line lane" 6 $G --selftest
} 2>&1 | tee "$C/nl-control-matrix.txt"