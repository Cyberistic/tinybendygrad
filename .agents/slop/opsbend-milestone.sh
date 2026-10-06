#!/bin/sh
# .agents/slop/opsbend-milestone.sh -- THE ops_bend MILESTONE, ONE COMMAND.
#
#   ./.agents/slop/opsbend-milestone.sh
#
# prints PASS or FAIL and exits 0 or 1. It builds the executor from
# tinybendygrad/runtime/ops_python.bend (which IS the executor -- ops_bend.py:151
# builds it with ./bin/bend ... -o), then runs the port's OWN lane, which
# allocates three buffers in Bend's memory, writes a known pattern, launches the
# kernel, reads the result back and compares it against the expectation.
#
# THE EXPECTATION LIVES IN A FILE, WRITTEN BEFORE ANY RUN:
#   .agents/slop/ops_bend-milestone-expected.txt
# and the comparison row is ms_pass, over the WHOLE of PACKET.out. ms_got and
# ms_want print beside it, so a reader who disagrees can see which side moved.
#
# NO PYTHON IN THE PATH. ./bin/bend ops_bend.bend opsbend is the whole runtime:
# the allocator, the hex codec, the launch (Process.run) and the readback all run
# inside Bend. The harness below only builds a binary and diffs text.
#
# bend --check-only EXITS 1 EVEN ON A CLEAN FILE, and this file is not exempt:
# read the FIRST LINE and expect ALL PROOFS CHECK, never gate on $?.
set -e
# THE ROOT, IN TWO STEPS. MEASURED: the one-liner
#   ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# is a PARSE ERROR here -- the closing paren of the substitution is found early
# because the path also contains one -- and sh reports the failure at an unrelated
# line. Separating the directory computation from the cd avoids it and is no
# longer to read.
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/../.." && pwd)
cd "$ROOT"
RUN="$ROOT/.agents/slop/opsbend-milestone"
# The row pattern lives in a VARIABLE, not inline. MEASURED: a bare equals sign
# inside command substitution is a shell parse error here -- the substitution ends
# the quoting early and sh reports "unexpected EOF while looking for matching".
# One variable, two uses, and the comment above no longer contains a backtick
# (which had the same effect for the same reason).
EQ="="
EXE="$RUN/bend-executor"
SRC="tinybendygrad/runtime/ops_python.bend"
PORT="tinybendygrad/runtime/ops_bend.bend"
mkdir -p "$RUN"

# ---- 1. the executor, built once and reused -------------------------------
# MEASURED: ~2.5 minutes interpreted, and the launch itself needs the BINARY --
# ./bin/bend ops_python.bend PACKET ... stack-overflows on roughly one run in
# twenty and prints nothing, so the compiled path is the one that is reproducible.
if [ ! -x "$EXE" ] || [ "$SRC" -nt "$EXE" ]; then
  echo "== 1/3 building the executor from $SRC (this takes ~2.5 min)"
  ./bin/bend "$SRC" -o "$EXE" > "$RUN/build.txt" 2>&1 || {
    echo "FAIL: the executor did not build; see $RUN/build.txt" >&2; exit 2; }
else
  echo "== 1/3 executor up to date ($EXE)"
fi

# ---- 2. the port's own lane -------------------------------------------------
# bend --check-only FIRST, because a type error here would otherwise surface as
# a launch failure and be misread as a kernel bug. Its exit status is meaningless.
echo "== 2/3 checking $PORT"
./bin/bend "$PORT" --check-only > "$RUN/check.txt" 2>&1 || true
head -1 "$RUN/check.txt" | grep -q "ALL PROOFS CHECK" || {
  echo "FAIL: $PORT does not check; first line was:" >&2
  head -6 "$RUN/check.txt" >&2; exit 2; }

echo "== 2/3 running the port's own ops_bend lane"
rm -f "$RUN/PACKET.out"
./bin/bend "$PORT" opsbend > "$RUN/milestone.txt" 2>&1 || true
n=$(grep -c "$EQ" "$RUN/milestone.txt" || echo 0)
# bend stack-overflows on roughly one run in twenty and prints NOTHING, and a
# zero-row result is indistinguishable from "not started". So the run is RETRIED
# and the ROW COUNT is checked -- the same discipline e2e.sh uses, for the same
# measured reason.
i=0
while [ "$i" -lt 8 ]; do
  i=$((i + 1))
  if [ "$n" -gt 40 ]; then break; fi
  rm -f "$RUN/PACKET.out"
  ./bin/bend "$PORT" opsbend > "$RUN/milestone.txt" 2>&1 || true
  n=$(grep -c "$EQ" "$RUN/milestone.txt" || echo 0)
  echo "   attempt $i produced $n rows, retrying" >&2
done
if [ "$n" -le 40 ]; then
  echo "FAIL: no attempt produced rows in 8 tries -- SUBSTRATE OR FIXTURE, not a verdict" >&2
  head -5 "$RUN/milestone.txt" >&2
  exit 2
fi
echo "   $n rows (attempt $i)"

# ---- 3. the verdict, plus the checks that make it mean something -----------
echo "== 3/3 gate"
set +e
"$ROOT/.venv/bin/python" .agents/slop/opsbend_milestone_gate.py \
  "$RUN/milestone.txt" "$RUN/PACKET.in" "$RUN/PACKET.out" > "$RUN/gate.txt" 2>&1
rc=$?
set -e
cat "$RUN/gate.txt"
[ "$rc" -eq 0 ] && echo PASS || echo FAIL
exit "$rc"