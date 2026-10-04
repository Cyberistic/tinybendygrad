#!/bin/zsh
# .agents/slop/portexec/stage1.sh -- DOES THE PORT'S EMITTED C COMPILE AND RUN?
#
# The one command. Run from anywhere:  zsh .agents/slop/portexec/stage1.sh
# Exit 0 = the port's C ran and produced CPython's words. Anything else names
# WHICH of the four steps broke: bend -o, cc, link, run.
#
#   STEP 0  ORACLE      .venv/bin/python .agents/slop/portexec/oracle.py
#                       CALLS CPython: `ClangRenderer.render_kernel` for the C
#                       text, numpy for the arithmetic, and tinygrad's REAL
#                       `DEV=CPU` device (ClangCompiler -> ELF -> CPUProgram ->
#                       ctypes) for a third, independent execution of the same
#                       kernel. All three must agree before the port runs.
#   STEP 1  PORT        ./bin/bend tinybendygrad/renderer/cstyle.bend  -- 227 rows
#   STEP 2  EXTRACT     the port's OWN column for `kern2 CLANG`, parsed
#   STEP 3  cc          cc -Wall -Werror
#   STEP 4  LINK
#   STEP 5  RUN
#   STEP 6  COMPARE     the port's 4 u32 words against CPython's 4 u32 words,
#                       byte for byte, and reports the diff SIZE in bytes.
#
# NOTHING IN THE LIVE PORT TREE IS EDITED. Every artefact lands in $WORK.
set -u
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
PY="$ROOT/.venv/bin/python"
WORK=${1:-$TMPDIR/portexec}
mkdir -p "$WORK"
cd "$ROOT" || exit 1

fail() { print -r -- "FAIL[$1] $2"; exit 1; }

# ---------------------------------------------------------------- STEP 0
print -r -- "== STEP 0  oracle (CPython: render_kernel + numpy + real DEV=CPU)"
"$PY" .agents/slop/portexec/oracle.py "$WORK" > "$WORK/oracle.log" 2>&1 \
  || fail 0 "oracle.py died: $(tail -2 "$WORK/oracle.log" | tr '\n' ' ')"
grep -E '^(stage1|clang kernel)' "$WORK/oracle.log" | sed 's/^/   /'
"$PY" - "$WORK" <<'EOF' || fail 0 "CPython's own two answers disagree"
import json, pathlib, sys
o = json.loads((pathlib.Path(sys.argv[1]) / "oracle.json").read_text())
a, b, c = o["stage1_expect_words"], o["tinygrad_stage1_words"], [3212836864, 0, 0, 0]
print(f"   numpy f32 arithmetic : {a}")
print(f"   tinygrad DEV=CPU run : {b}")
sys.exit(0 if a == b == c else 1)
EOF

# ---------------------------------------------------------------- STEP 1
print -r -- "\n== STEP 1  port: ./bin/bend cstyle.bend"
# bend stack-overflows on roughly one run in twenty and prints NOTHING, and an
# empty capture is indistinguishable from "not started". So ROW COUNT is
# checked, not the exit status.
i=0; rows=0
while [ $i -lt 8 ]; do
  i=$((i+1))
  ./bin/bend tinybendygrad/renderer/cstyle.bend > "$WORK/port-rows.txt" 2> "$WORK/port-rows.err"
  rows=$(grep -c '\]   py=\[' "$WORK/port-rows.txt")
  [ "$rows" -ge 220 ] && break
  print -r -- "   attempt $i gave $rows rows, retrying" >&2; sleep 1
done
[ "$rows" -ge 220 ] || fail 1 "port produced $rows rows in 8 attempts"
print -r -- "   port rows: $rows"

# ---------------------------------------------------------------- STEP 2
print -r -- "\n== STEP 2  extract the port's OWN column (not py=)"
"$PY" .agents/slop/portexec/exec_harness.py "$WORK" > "$WORK/extract.log" 2>&1 \
  || fail 2 "extract died: $(tail -2 "$WORK/extract.log" | tr '\n' ' ')"
sed 's/^/   /' "$WORK/extract.log"

# ---------------------------------------------------------------- STEP 3
print -r -- "\n== STEP 3  cc"
cc -Wall -Werror -c "$WORK/stage1.c" -o "$WORK/stage1.o" 2> "$WORK/cc.log" \
  || { sed 's/^/   /' "$WORK/cc.log"; fail 3 "cc rejected the port's C"; }
print -r -- "   ok, $(wc -c < "$WORK/stage1.o" | tr -d ' ') byte object"

# ---------------------------------------------------------------- STEP 4
print -r -- "\n== STEP 4  link"
cc "$WORK/stage1.o" -o "$WORK/stage1.bin" 2> "$WORK/link.log" \
  || { sed 's/^/   /' "$WORK/link.log"; fail 4 "link"; }
print -r -- "   ok, $WORK/stage1.bin"

# ---------------------------------------------------------------- STEP 5
print -r -- "\n== STEP 5  run  (twice, because a lane that only ran once ran once)"
"$WORK/stage1.bin" > "$WORK/run1.txt" 2>&1 || fail 5 "run rc=$? : $(cat "$WORK/run1.txt")"
"$WORK/stage1.bin" > "$WORK/run2.txt" 2>&1 || fail 5 "run rc=$? on the second attempt"
cmp -s "$WORK/run1.txt" "$WORK/run2.txt" || fail 5 "run is NOT DETERMINISTIC"
sed 's/^/   /' "$WORK/run1.txt"

# ---------------------------------------------------------------- STEP 6
print -r -- "\n== STEP 6  compare the port's words to CPython's, byte for byte"
"$PY" - "$WORK" <<'EOF' || exit 1
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
o = json.loads((w / "oracle.json").read_text())
port = [int(l.split()[2], 16) for l in (w / "run1.txt").read_text().splitlines() if l.startswith("WORD ")]
want = o["stage1_expect_words"]
got = (w / "run1.txt").read_bytes()
ref = ("".join(f"WORD {i} 0x{x:08x}\n" for i, x in enumerate(want))).encode()
print(f"   port   : {port}")
print(f"   CPython: {want}")
same = port == want
print(f"   equal  : {same}   diff bytes: {0 if same else sum(a != b for a, b in zip(got, ref)) + abs(len(got) - len(ref))}")
print("PASS [stage1] the port's emitted C compiled and produced CPython's words" if same
      else "FAIL [stage1] the port's C ran but the numbers differ")
(w / "stage1-verdict.txt").write_text("PASS\n" if same else "FAIL\n")
sys.exit(0 if same else 1)
EOF

# ---------------------------------------------------------------- STEP 7
# THE LANE MUST BE ABLE TO FAIL. Three controls in this project were found
# unable to fail and one left six lanes green, so a PASS above is not a result
# until something has been shown to make it red. TWO PLANTS, both applied to
# $WORK ONLY -- no file in the repo tree is edited -- and the lane must go red
# on each. A plant that leaves the lane green is a VACUOUS CONTROL and is
# reported as such.
print -r -- "\n== STEP 7  negative controls (each MUST turn the lane red)"
ctl() {  # name, sed-expr
  local nm=$1 expr=$2
  cp "$WORK/stage1.c" "$WORK/ctl.c"
  sed "$expr" "$WORK/ctl.c" > "$WORK/ctl2.c"; mv "$WORK/ctl2.c" "$WORK/ctl.c"
  if cmp -s "$WORK/ctl.c" "$WORK/stage1.c"; then
    print -r -- "   VACUOUS [$nm] the plant changed nothing"; return 1; fi
  cc -Wall -Werror -c "$WORK/ctl.c" -o "$WORK/ctl.o" 2>/dev/null || {
    print -r -- "   RED-VIA-COMPILE [$nm] (plant does not compile; the compare was never reached)"; return 0; }
  cc "$WORK/ctl.o" -o "$WORK/ctl.bin" 2>/dev/null || {
    print -r -- "   RED-VIA-LINK [$nm]"; return 0; }
  "$WORK/ctl.bin" > "$WORK/ctl.txt" 2>&1
  "$PY" - "$WORK" <<'EOF'
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
o = json.loads((w / "oracle.json").read_text())
try:
  port = [int(l.split()[2], 16) for l in (w / "ctl.txt").read_text().splitlines() if l.startswith("WORD ")]
except Exception: port = None
sys.exit(0 if port != o["stage1_expect_words"] else 1)
EOF
  if [ $? -eq 0 ]; then print -r -- "   RED [$nm] the compare caught it"; return 0
  else print -r -- "   GREEN [$nm] *** THE LANE DID NOT NOTICE ***"; return 1; fi
}
rc=0
ctl "alu +1.0f -> +2.0f"  's/val0\[0\]+1\.0f/val0[0]+2.0f/' || rc=1
ctl "store out <- input"   's/E_4(data0_4, data1_4)/E_4(data1_4, data0_4)/' || rc=1
ctl "drop the store"       's/^  \*((float4/  \/\/ *((float4/' || rc=1
[ $rc -eq 0 ] && print -r -- "\nPASS [stage1-controls] every plant turned the lane red" \
                 || print -r -- "\nFAIL [stage1-controls] a plant left the lane GREEN"
exit $rc
