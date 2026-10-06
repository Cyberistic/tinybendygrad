#!/bin/sh
# .agents/slop/e2e_negctl.sh -- THE NEGATIVE CONTROL. An E2E that has never failed
# is not known to work, so this breaks three things on a COPY and shows the gate
# going red for each, with the ROW that died named.
#
# NOTHING HERE TOUCHES THE LIVE TREE. Every mutation is applied to a copy under
# $TMPDIR, and the live tree is only ever READ -- three units have been killed by
# servers restarting under a harness that patched in place. The copy keeps the
# RELATIVE LAYOUT (`.agents/slop/` beside `tinybendygrad/`, both two levels under a
# root) because `.bend` imports are relative and a flat copy cannot resolve them;
# that is the `$TMPDIR`-copy trap recorded in agent-core.md, and it produced 22
# phantom blind spots in one unit.
#
# `bin/` and `references/` are SYMLINKS, not copies: `references/` is 227 MB of the
# Bend checkout and the compiler is read-only for our purposes.
#
# THE THREE MUTATIONS, chosen because each kills a DIFFERENT row:
#
#   NC1 ONE BYTE OF AN UPLOADED MATRIX.
#       The most obvious possible break. It must kill `mm_e2e_out_bits_equal`
#       AND `mm_e2e_in_bits_equal`, because the readback of the probe buffer is
#       the row that says whether a wrong answer is arithmetic or data.
#   NC2 THE BINDING ORDER OF THE SECOND LAUNCH.
#       `bufs1` names the buffers in `ProgramInfo.globals` order, and swapping two
#       of them is a silent wrong answer that every SIZE-reading row and every
#       COUNT row would call green. If this does not go red, the binding rows have
#       no teeth.
#   NC3 THE PORT. `Cs.caller` is the def `webgpu_call.bend`'s own header records as
#       having been wrong once ("all three `bufs` entries bound id 0", and NO row in
#       either file saw it). Putting that bug back must stop the WALK. This is the
#       only one of the three that mutates the port rather than the fixture, and it
#       is the one that matters: NC1 and NC2 prove the harness listens, NC3 proves
#       the harness listens to the PORT.
#
# RUN:  ./.agents/slop/e2e_negctl.sh
# EXIT: 0 only if all three controls FAILED as they must.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NC="${TMPDIR:-/tmp}/e2e-negctl.$$"
PY="$ROOT/.venv/bin/python"
cleanup() { rm -rf "$NC"; }
trap cleanup EXIT

# ---- the copy, with the layout the imports need ------------------------------
mkdir -p "$NC/.agents/slop" "$NC/runs/e2e"
cp -R "$ROOT/tinybendygrad" "$NC/tinybendygrad"
cp -R "$ROOT/.agents/slop/xd2" "$NC/.agents/slop/xd2"
for f in e2e_mm.py e2e_mm_run.mjs e2e_mm_gate.py e2e_mm.bend e2e_gpu_probe.mjs; do
  cp "$ROOT/.agents/slop/$f" "$NC/.agents/slop/$f"
done
mkdir -p "$NC/.agents/slop/e2e"
cp "$ROOT/.agents/slop/e2e/index.html" "$NC/.agents/slop/e2e/index.html"
cp "$ROOT/.agents/slop/e2e/cc-no-fma.sh" "$NC/.agents/slop/e2e/cc-no-fma.sh"
ln -s "$ROOT/bin" "$NC/bin"
ln -s "$ROOT/references" "$NC/references"
echo "copy at $NC (tinybendygrad copied, bin/ and references/ symlinked)"

# run_one: bend, then the GPU lane, then the gate. It EXITS with the GATE's status.
#
# NOT `... | tee`. The first version of this script printed `gate-exit=0` after the
# gate had CRASHED, because a crash writes a traceback to the file and no
# `# FAILED` lines, so a crash and a pass look identical to a `grep -c FAILED`. So
# the status is taken from the gate process itself, and `control 0` would have
# declared the copy green on a stack trace.
run_one() {
  cd "$NC" || return 2
  ./bin/bend .agents/slop/e2e_mm.bend > runs/e2e/bend.txt 2> runs/e2e/bend.err || return 2
  node .agents/slop/e2e_mm_run.mjs > runs/e2e/run.txt 2>&1
  "$PY" .agents/slop/e2e_mm_gate.py runs/e2e/bend.txt > runs/e2e/gate.txt 2>&1
}

died() { grep '^# FAILED ' "$NC/runs/e2e/gate.txt" | sed 's/^# FAILED /    died: /' | head -6; }

expect_red() {  # expect_red <label> <must-die-regex>
  run_one; out=$?
  failed=$(grep -c '^# FAILED ' "$NC/runs/e2e/gate.txt" || true)
  printf '%-52s gate-exit=%s failed_rows=%s\n' "$1" "$out" "$failed"
  if [ "$failed" -eq 0 ]; then
    echo "    *** THE CONTROL DID NOT GO RED. The gate cannot detect this class of bug. ***"
    tail -3 "$NC/runs/e2e/gate.txt" | sed 's/^/    /'
    return 1
  fi
  died
  grep -qE "$2" "$NC/runs/e2e/gate.txt" && return 0 || { echo "    *** went red, but not on the row naming the break ***"; return 1; }
}

rc=0

# ---- control 0: the UNBROKEN copy must be GREEN -----------------------------
echo
echo "== control 0: the copy, unmutated"
# THE ORACLE MUST BE BUILT IN THE COPY TOO. It is not committed as a fixture that a
# mutation run inherits -- `e2e_mm.py` writes it, and it is what makes the copy's
# gate have expectations at all. The first version of this script skipped that and
# every control below "failed_rows=0" because the gate died on a missing file.
( cd "$NC" && "$PY" .agents/slop/e2e_mm.py ) || { echo "  *** the copy could not build its oracle ***"; rc=1; }
run_one; out=$?
failed=$(grep -c '^# FAILED ' "$NC/runs/e2e/gate.txt" || true)
echo "gate-exit=$out failed_rows=$failed"
[ "$out" -eq 0 ] && [ "$failed" -eq 0 ] || { echo "  *** the copy is NOT green, so the controls below prove nothing ***"; died; rc=1; }

# ---- NC1: one byte of an uploaded matrix -------------------------------------
echo
echo "== NC1: one byte of an uploaded matrix"
# `bytes_b1` is the FIRST byte of the first uploaded matrix's byte list. Flipping
# bit 0 of one byte changes one f32 by a huge amount and nothing else.
"$PY" - "$NC/.agents/slop/e2e_mm.bend" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
m = re.search(r"def bytes_b1\(\) -> List<&2, U32>: \[(\d+),", s)
assert m, "bytes_b1 not found -- the fixture shape changed and this control needs updating"
first = int(m.group(1))
s = s[:m.start(1)] + str(first ^ 1) + s[m.end(1):]
open(p, "w").write(s)
print(f"    bytes_b1[0] {first} -> {first ^ 1}")
EOF
expect_red "NC1 one uploaded byte" "mm_e2e_(out_bits_equal|in_bits_equal)=False" || rc=1

# ---- NC2: swap two buffers in the SECOND launch's bind list ------------------
echo
echo "== NC2: the second launch's binding order"
# NC1's mutation is still on disk: `e2e_mm.py` runs once, in control 0, and every
# control after that inherits the previous one's break unless the fixture is put
# back. MEASURED: NC2 reported NC1's two rows, which would have been a control that
# passes for the wrong reason.
cp "$ROOT/.agents/slop/e2e_mm.bend" "$NC/.agents/slop/e2e_mm.bend"
"$PY" - "$NC/.agents/slop/e2e_mm.bend" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
m = re.search(r"def bufs1\(\) -> List<&2, W\.Buf>: \[(.*)\]", s)
assert m, "bufs1 not found"
# SPLIT ON THE `W.Buf{...}` UNITS, not on commas: each unit contains commas of its
# own, so a plain `split(",")` shreds it. The first version asserted on three
# fragments and got three fragments.
import re as _re
parts = _re.findall(r"W\.Buf\{[^}]*\}", m.group(1))
assert len(parts) == 3, parts
parts[0], parts[2] = parts[2], parts[0]     # the intermediate and C trade places
s = s[:m.start(1)] + ", ".join(parts) + s[m.end(1):]
open(p, "w").write(s)
print(f"    bufs1 {parts[0]} {parts[1]} {parts[2]}")
EOF
expect_red "NC2 second launch's binding order" "mm_e2e_(l1_bg_bufs|out_bits_equal)" || rc=1

# ---- NC3: THE PORT. Put `Cs.caller`'s documented bug back. ------------------
echo
echo "== NC3: the port -- Cs.caller binding every bufs slot to id 0"
cp "$ROOT/.agents/slop/e2e_mm.bend" "$NC/.agents/slop/e2e_mm.bend"   # undo NC1+NC2
"$PY" - "$NC/tinybendygrad/runtime/webgpu_call.bend" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
old = """  Bool.pick(U32, is_buf,
    Cs.buf_id(List.get(&2, W.Buf, bs, Nat.sub(U32.to_nat(i), 1n))), 0)"""
new = """  Bool.pick(U32, is_buf, 0, 0)"""
assert old in s, "Cs.caller's shape changed -- this control needs updating"
open(p, "w").write(s.replace(old, new))
print("    Cs.caller -> Bool.pick(U32, is_buf, 0, 0)   (the bug webgpu_call.bend's header records)")
EOF
run_one; out=$?
failed=$(grep -c '^# FAILED ' "$NC/runs/e2e/gate.txt" || true)
echo "the walk itself: $(grep -E '^(WALK FAILED|adapter )' "$NC/runs/e2e/run.txt" | head -2 | tr '\n' ' ')"
printf '%-52s gate-exit=%s failed_rows=%s\n' "NC3 Cs.caller binds every buffer to id 0" "$out" "$failed"
# A PORT mutation is allowed to stop the walk rather than merely turn a row red --
# `Cs.caller` returning 0 for every buffer makes Chrome reject the bind group, which
# is exactly what `webgpu_call.bend`'s own header says happened. So "the gate
# exited non-zero OR named a dead row" is the pass condition, and a non-zero exit
# with no `# FAILED` line is a CRASH, which is not a catch.
if [ "$out" -ne 0 ] && [ "$failed" -eq 0 ] && grep -q 'Traceback' "$NC/runs/e2e/gate.txt"; then
  echo "    *** the gate CRASHED rather than reporting a red row ***"; rc=1
elif [ "$out" -eq 0 ]; then
  echo "    *** THE PORT MUTATION DID NOT GO RED ***"; rc=1
else
  died
  [ "$failed" -gt 0 ] || echo "    (the walk stopped, which is the catch)"
fi

echo
if [ "$rc" -eq 0 ]; then echo "NEGATIVE CONTROL PASS: all three breaks were caught"; else echo "NEGATIVE CONTROL FAIL"; fi
# THE ARTIFACT, so a reader can see that the controls bite without spending ten
# minutes on Chrome. It is this script's whole output, which is why the script is
# run with `> runs/e2e/e2e-negctl.txt` rather than teed at the end: a reader must
# not have to trust that a partial run wrote a complete file.
exit "$rc"
