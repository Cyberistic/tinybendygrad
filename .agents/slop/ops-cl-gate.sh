#!/bin/zsh
# The runtime/{ops_cl,ops_cuda,ops_hip} GATE, post-split. `ops_cl.bend` was ONE
# file for ops_cl.py + ops_cuda.py + ops_hip.py; the 1:1 ruling made it three, and
# the 445 rows they print are the SAME 445 `name=value` LINES the old file printed.
#
#   .agents/slop/ops-cl-gate.sh
#
# FOUR CHECKS, and each answers a question the others cannot.
#
#   1. THE ROWS.      229 + 120 + 96 = 445, and the sorted diff against the
#                     PRE-SPLIT snapshot is empty: every `name=value` pair is
#                     byte-identical. WHY SORTED: the old `main` ran t_vend,
#                     t_check and t_err as three blocks whose rows INTERLEAVE the
#                     three vendors -- row 1 `vend_count_cl`, row 2
#                     `vend_count_cuda`, row 3 `vend_count_hip`, row 4
#                     `vend_names_cl` -- and one concatenation of three programs
#                     cannot interleave, so 444 of 445 rows changed position. The
#                     sorted diff is STRICTLY STRONGER on values than the ordered
#                     one: it compares every line character for character. What
#                     it cannot see is a reordering, and check 2 counts those.
#   2. THE ORDERING.  `cl_split_rows.py` prints how many rows moved and asserts
#                     that NO ROW LANDED IN THE WRONG FILE -- every `x_*` and
#                     `*_hp` row in `ops_hip.bend`, every `*_cu` in
#                     `ops_cuda.bend`, every `cl_*` in `ops_cl.bend`.
#   3. NO LINE LOST.  `cl_split_noloss.py` compares every non-blank pre-split
#                     line against the union of the three files. A def COUNT
#                     cannot see a dropped comment, and three load-bearing ones
#                     were dropped on the first pass.
#   4. VERBATIM.      `cl_split_names.py` reverse-applies the call-site
#                     qualifiers and diffs all 446 moved defs' CODE against the
#                     pre-split source, and prints the name correspondence.
#
# MUTATIONS: `.agents/slop/cl_split_mutate.py`, 17 of them, rows moved by name.
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started". Every file is retried
# up to five times and a ZERO-ROW run is a FAILURE, not a result -- an oracle that
# emitted nothing and exited 1 once got read as a passing gate.
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
# THE EXIT TRAP RE-RAISES. `trap 'rm -rf "$OUT"' EXIT` makes the script exit with the
# STATUS OF `rm`, so a successful cleanup turns any earlier failure into exit 0 -- and this
# gate's whole job is to fail loudly on a byte difference. `$?` is captured first, the
# cleanup runs, and the original status is restored. This is the second of the two shapes
# that let a gate lie here; the first is `diff ... && echo`, which `set -e` does not fire
# on because the failing command is inside an && list.
trap 'st=$?; rm -rf "$OUT"; exit $st' EXIT
for f in ops_cl ops_cuda ops_hip; do
  for i in 1 2 3 4 5; do
    ./bin/bend "tinybendygrad/runtime/$f.bend" > "$OUT/$f.txt" 2>/dev/null || true
    [ -s "$OUT/$f.txt" ] && break
  done
  n=$(grep -c '=' "$OUT/$f.txt" || true)
  echo "runtime/$f.bend  $n rows"
  [ "$n" -gt 0 ] || { echo "FAIL: $f printed ZERO rows -- rerun, that is the stack overflow"; exit 1; }
done
cat "$OUT/ops_cl.txt" "$OUT/ops_cuda.txt" "$OUT/ops_hip.txt" > "$OUT/all.txt"
echo "--------------------------------------------- union: $(grep -c '=' "$OUT/all.txt") rows (445 expected)"
# TEMP FILES, NOT `<( ... )`. The process substitution is a BASHISM, so under `sh` this
# script did not PARSE -- and because the parse error happened before the EXIT trap's
# masking mattered, the gate was unrunnable and unreadable at the same time. Two sorted
# files and an ordinary `diff` are POSIX and say the same thing.
sort .agents/slop/runs/base_runtime_ops_cl.bend.txt > "$OUT/a.sorted"
sort "$OUT/all.txt" > "$OUT/b.sorted"
diff "$OUT/a.sorted" "$OUT/b.sorted" \
  && echo "MATCHES the pre-split snapshot: all 445 name=value lines byte-identical" \
  || { echo "DISAGREE with the pre-split snapshot" >&2; exit 1; }
echo
echo "== 2. the ordering, and the file each row landed in =="
python3 .agents/slop/cl_split_rows.py
echo
echo "== 3. no pre-split line was dropped =="
python3 .agents/slop/cl_split_noloss.py
echo
echo "== 4. verbatim bodies, and the name correspondence =="
python3 .agents/slop/cl_split_names.py