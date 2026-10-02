#!/bin/zsh
# The codegen/{simplify,late/coalesce,gpudims} GATE, post-split. `codegen/
# rewriter.bend` was ONE file for all three; the 1:1 ruling made it three plus a
# substrate. The 54 rows they print CONCATENATE IN PYTHON'S ORDER (simplify.py,
# late/coalesce.py, gpudims.py) to exactly the 54 the old file printed, and that
# concatenation is what this script diffs against the PRE-SPLIT snapshot.
#
#   .agents/slop/codegen3-gate.sh          # rows + diff against the snapshot
#   .agents/slop/codegen3-gate.sh --fp     # and the compiled lane (byte-identical?)
#   .agents/slop/codegen3-gate.sh --reds   # just the four known-red rows
#
# THE FOUR KNOWN REDS ARE NOT FIXED AND NOT MASKED. `rs_claim_warp`,
# `rs_claim_loop`, `rs_rewrite_warp` and `rs_rewrite_loop` came in with the
# rebase batch of 2026-10-03 and belong to `pm_range_to_special`; another unit owns
# them. They are printed here before and after so that unit can attribute them.
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started", so every file is retried
# AND the row count is asserted against the snapshot -- a gate whose lane emitted 0
# rows and still said MATCHES is a gate that never ran.
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
N=0
for f in codegen/simplify codegen/late/coalesce codegen/gpudims; do
  n=$(basename $f)
  for i in 1 2 3 4 5; do
    ./bin/bend "tinybendygrad/$f.bend" > "$OUT/$n.txt" 2>"$OUT/$n.err" || true
    [ -s "$OUT/$n.txt" ] && break
  done
  # the oracle's EXIT PATH, checked rather than assumed: a non-empty file with zero
  # rows is a crash, not a clean run
  rows=$(grep -c '=' "$OUT/$n.txt" || true)
  [ "$rows" -gt 0 ] || { echo "FAIL: $f.bend emitted $rows rows -- bend did not run"; cat "$OUT/$n.err"; exit 1; }
  echo "$f.bend  $rows rows"
  N=$((N + rows))
done
cat "$OUT/simplify.txt" "$OUT/coalesce.txt" "$OUT/gpudims.txt" > "$OUT/all.txt"
echo "--------------------------------------------- union: $(grep -c '=' "$OUT/all.txt") rows"
echo "                                             $N counted above -- THEY MUST AGREE"
[ "$N" = "$(grep -c '=' "$OUT/all.txt")" ] || { echo "FAIL: per-file rows and the union disagree"; exit 1; }
diff .agents/slop/runs/base_codegen_rewriter.bend.txt "$OUT/all.txt" \
  && echo "MATCHES the pre-split snapshot"

if [ "$1" = --fp ]; then
  for f in codegen/simplify codegen/late/coalesce codegen/gpudims; do
    n=$(basename $f)
    ./bin/bend "tinybendygrad/$f.bend" -o "$OUT/$n.bin" >/dev/null 2>&1
    "$OUT/$n.bin" > "$OUT/$n.fp" 2>/dev/null || true
    echo "compiled $f.bend  $(grep -c '=' "$OUT/$n.fp" || echo 0) rows"
  done
  cat "$OUT/simplify.fp" "$OUT/coalesce.fp" "$OUT/gpudims.fp" > "$OUT/all.fp"
  diff "$OUT/all.txt" "$OUT/all.fp" && echo "BOTH LANES BYTE-IDENTICAL"
  diff .agents/slop/runs/base_codegen_rewriter.bend.txt "$OUT/all.fp" \
    && echo "the compiled lane MATCHES the pre-split snapshot too"
fi

if [ "$1" = --reds ]; then
  echo "--- the four rows another unit owns"
  grep -E '^(rs_claim_warp|rs_claim_loop|rs_rewrite_warp|rs_rewrite_loop)=' \
    .agents/slop/runs/base_codegen_rewriter.bend.txt | sed 's/^/BEFORE  /'
  grep -E '^(rs_claim_warp|rs_claim_loop|rs_rewrite_warp|rs_rewrite_loop)=' \
    "$OUT/all.txt" | sed 's/^/AFTER   /'
fi
rm -rf "$OUT"