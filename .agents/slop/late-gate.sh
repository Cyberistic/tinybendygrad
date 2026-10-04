#!/bin/zsh
# The codegen/late GATE, post-split. `codegen/late.bend` was one file for
# linearizer.py + regalloc.py + gater.py; the 1:1 ruling made it three, and the
# 128 rows they print CONCATENATE IN PYTHON'S ORDER to exactly the 128 the old file
# printed. This script is that invariant, and the acceptance test against CPython.
#
#   .agents/slop/late-gate.sh          # rows + diff against .agents/slop/late-oracle.txt
#   .agents/slop/late-gate.sh --base   # diff against the PRE-SPLIT 128-row snapshot
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started", so every file is retried.
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
for f in linearizer regalloc gater; do
  for i in 1 2 3 4 5; do
    ./bin/bend "tinybendygrad/codegen/late/$f.bend" > "$OUT/$f.txt" 2>/dev/null || true
    [ -s "$OUT/$f.txt" ] && break
  done
  echo "codegen/late/$f.bend  $(grep -c '=' "$OUT/$f.txt") rows"
done
cat "$OUT/linearizer.txt" "$OUT/regalloc.txt" "$OUT/gater.txt" > "$OUT/all.txt"
echo "--------------------------------------------- union: $(grep -c '=' "$OUT/all.txt") rows"
diff .agents/slop/late-oracle.txt "$OUT/all.txt" && echo "MATCHES the CPython oracle" || { echo "DISAGREE with the CPython oracle" >&2; exit 1; }
[ "$1" = --base ] && { diff .agents/slop/late-pre-split.txt "$OUT/all.txt" && echo "MATCHES the pre-split snapshot"; }
rm -rf "$OUT"
