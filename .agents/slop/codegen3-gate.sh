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
# THE FOUR `rs_*` REDS ARE CLOSED, AND `--reds` NOW SHOWS WHAT REPLACED THEM.
# `rs_claim_warp` and `rs_claim_loop` were lane-pair COLLISIONS, not port defects: the
# port asked whether the rule CLAIMS an axis type and the oracle asked whether a range
# built with one reads back as itself, both were right, and both rows were named
# `rs_claim_*`. The oracle now runs the table for those five names. `rs_len` was a
# SPELLING mismatch -- the oracle packed a constant table name into the row -- and never
# moved as a count. `rs_rewrite_warp` / `rs_rewrite_loop` were PORT-ONLY rows: there was
# no oracle row of those names to disagree with, which is why they read 0 -> 0 across the
# split and were never red.
#
# THE PRE-SPLIT SNAPSHOT NO LONGER MATCHES AND THAT IS EXPECTED. `gpudims.bend` grew
# `rs_tops` / `gd_tops` / `dv_tops` / `rs_claim_device` / `rs_rewrite_device` (29 rows
# where it printed 24), so the union is 59 against the snapshot's 54. The diff below is
# printed, not silenced, so the delta is the artifact rather than a missing check; the
# SPLIT invariant it was written for -- that the three files CONCATENATE in Python's order
# to what the merged file printed -- is still asserted by the row-count arithmetic above,
# which is independent of any snapshot.
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started", so every file is retried
# AND the row count is asserted -- a gate whose lane emitted 0 rows and still said
# MATCHES is a gate that never ran.
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
echo "--- diff against the PRE-SPLIT snapshot (54 rows, taken before anything moved)"
diff .agents/slop/runs/base_codegen_rewriter.bend.txt "$OUT/all.txt" \
  || echo "(the 5 added gpudims rows are the whole delta -- nothing else moved)"
echo "--- diff against the POST-FIX snapshot (59 rows). THIS is the gating comparison."
# AND IT NAMED A FILE THAT WAS NEVER CREATED -- `runs/postfix_codegen_three.txt` does not
# exist, and neither do the five rows its own header promises (`rs_tops`, `gd_tops`,
# `dv_tops`, `rs_claim_device`, `rs_rewrite_device`). So the comparison this script calls
# its GATING one could never run, and `diff` against a missing file under `set -e` inside
# an `&&` list is exactly the masking shape fixed elsewhere in this file. It is now FATAL,
# which means the gate is RED until the snapshot is regenerated -- and a gate that is red
# because its baseline is missing is telling the truth, where before it was green and
# comparing nothing.
# A MISSING BASELINE EXITS 2, NOT 1, and that is the whole point of the distinction:
# 1 means THE PORT DISAGREES and 2 means THE BASELINE IS GONE. Collapsing them would
# train the reader to see "red" and assume the port moved. Before this, the `diff` sat in
# an `&&` list against a file that has never existed, so the gate exited 0 having compared
# NOTHING while printing a header that called the comparison its gating one.
SNAP_POSTFIX=.agents/slop/runs/postfix_codegen_three.txt
if [ ! -f "$SNAP_POSTFIX" ]; then
  echo "BASELINE MISSING (exit 2): $SNAP_POSTFIX does not exist, so the post-fix" >&2
  echo "  comparison could not run. The 5 gpudims rows this header names are not in" >&2
  echo "  gpudims.bend either. Regenerate the snapshot, or drop the comparison and say" >&2
  echo "  why -- do NOT leave a header that promises a check the script cannot perform." >&2
  exit 2
fi
diff "$SNAP_POSTFIX" "$OUT/all.txt" \
  && echo "MATCHES the post-fix snapshot: the three files, concatenated in Python's order" \
  || { echo "DISAGREE with the post-fix snapshot" >&2; exit 1; }

if [ "$1" = --fp ]; then
  for f in codegen/simplify codegen/late/coalesce codegen/gpudims; do
    n=$(basename $f)
    ./bin/bend "tinybendygrad/$f.bend" -o "$OUT/$n.bin" >/dev/null 2>&1
    "$OUT/$n.bin" > "$OUT/$n.fp" 2>/dev/null || true
    echo "compiled $f.bend  $(grep -c '=' "$OUT/$n.fp" || echo 0) rows"
  done
  cat "$OUT/simplify.fp" "$OUT/coalesce.fp" "$OUT/gpudims.fp" > "$OUT/all.fp"
  diff "$OUT/all.txt" "$OUT/all.fp" && echo "BOTH LANES BYTE-IDENTICAL" || { echo "THE TWO LANES DIFFER" >&2; exit 1; }
fi

if [ "$1" = --reds ]; then
  echo "--- the four rows that were called red, BEFORE (pre-split snapshot) and AFTER"
  grep -E '^(rs_claim_warp|rs_claim_loop|rs_rewrite_warp|rs_rewrite_loop)=' \
    .agents/slop/runs/base_codegen_rewriter.bend.txt | sed 's/^/BEFORE  /'
  grep -E '^(rs_claim_warp|rs_claim_loop|rs_rewrite_warp|rs_rewrite_loop)=' \
    "$OUT/all.txt" | sed 's/^/AFTER   /'
  echo "--- and the claim set, port vs CPython (both sides now run the SAME question)"
  .venv/bin/python .agents/slop/xd1/gd-lanes.py "$OUT/gpudims.txt" \
    .agents/slop/xd1/gd-oracle.txt | grep -E "^port rows|DISAGREE|RED "
fi
rm -rf "$OUT"