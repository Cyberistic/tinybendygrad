#!/bin/zsh
# The runtime/{ops_cpu,ops_null} GATE, post-split. `ops_cpu_null.bend` was ONE file
# for ops_cpu.py + ops_null.py; the 1:1 ruling made it two, and the 308 rows they
# print CONCATENATE IN PYTHON'S ORDER to exactly the 308 the old file printed.
#
#   .agents/slop/cpunull-gate.sh          # rows + diff against the pre-split snapshot
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started", so every file is retried.
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
for f in ops_cpu ops_null; do
  for i in 1 2 3 4 5; do
    ./bin/bend "tinybendygrad/runtime/$f.bend" > "$OUT/$f.txt" 2>/dev/null || true
    [ -s "$OUT/$f.txt" ] && break
  done
  echo "runtime/$f.bend  $(grep -c '=' "$OUT/$f.txt") rows"
done
cat "$OUT/ops_cpu.txt" "$OUT/ops_null.txt" > "$OUT/all.txt"
echo "--------------------------------------------- union: $(grep -c '=' "$OUT/all.txt") rows"
diff .agents/slop/ops_cpu_null-pre-split.txt "$OUT/all.txt" && echo "MATCHES the pre-split snapshot" || { echo "DISAGREE with the pre-split snapshot" >&2; exit 1; }
rm -rf "$OUT"
