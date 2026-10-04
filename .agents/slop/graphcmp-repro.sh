#!/bin/sh
# graphcmp-repro.sh -- THE TWO-CLEAN-RUN CHECK, with the substrate WAIT in front of it.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT AS A PROSE CLAIM. `graphcmp-run.sh` step 15 used to
# claim, in a comment, that two consecutive clean runs leave every file under
# `runs/graphcmp/D` byte-identical, and to back it with `find | md5 -q`. That command is
# wrong: macOS `md5 -q` takes exactly ONE file and prints nothing given several, so it is
# not a digest of anything and the claim behind it was unfalsifiable. MEASURED 2026-10-04:
# when the check was finally written properly it found a real nondeterminism on its FIRST
# run (a `dict` printed in set-iteration order, now graphcmp-oracle.py's defect 20), and
# on its second it was defeated by a CONCURRENT EDIT to `tinybendygrad/uop/ops.bend` that
# made every bend emission return 0 rows.
#
# THE WAIT IS PART OF THE CHECK, not a workaround. `emit_bend`'s 5-attempt re-run guard
# turned that concurrent edit into `0 rows after 5 attempts -- a FAILURE, not a verdict` on
# all sixteen graphs, which is exactly right, and `D2-cmp-*` said `NOT COMPARED` rather
# than `BYTE-IDENTICAL` -- but a FAILURE is still not a reproducibility measurement, so the
# honest thing is to wait for the substrate and then measure.
#
#     sh .agents/slop/graphcmp-repro.sh [WAIT_MINUTES]
set -u
cd "$(dirname "$0")/../.." || exit 2
WAIT=${1:-9}
snap() {
  find runs/graphcmp/D -type f | sort | while read -r f; do
    printf '%s  %s\n' "$(grep -v '^[[:space:]]*$' "$f" | shasum -a 256 | cut -d' ' -f1)" "$f"
  done
}
settled() {
  # ONE probe line, and it is `--check-only`'s FIRST line only: agent-core.md's trap is
  # that it exits 1 even on a clean file (dtype.bend's 14 permanently-red laws), so the
  # exit status is not the signal and the text is.
  ./bin/bend .agents/slop/graphcmp.bend --check-only 2>&1 | sed -n '1p'
}
ready() { i=0; while [ "$i" -lt "$WAIT" ]; do
    case "$(settled)" in "ALL PROOFS CHECK") return 0 ;; esac
    i=$((i+1)); sleep 60
  done; return 1; }

echo "# waiting for the substrate (graphcmp.bend --check-only == ALL PROOFS CHECK)"
ready || { echo "SUBSTRATE DID NOT SETTLE in $WAIT minutes -- this is NOT a measurement"; exit 2; }
sh .agents/slop/graphcmp-run.sh > /dev/null 2>&1 || { echo "RUN A FAILED -- NOT a measurement"; exit 2; }
snap > /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha
echo "# run A done: $(wc -l < /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha | tr -d ' ') files snapshotted"
ready || { echo "SUBSTRATE DID NOT SETTLE for run B -- this is NOT a measurement"; exit 2; }
sh .agents/slop/graphcmp-run.sh > /dev/null 2>&1 || { echo "RUN B FAILED -- NOT a measurement"; exit 2; }
snap > /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha
N=$(wc -l < /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha | tr -d ' ')
if cmp -s /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha; then
  echo "REPRO: $N of $N files identical across two clean runs (sha256 over non-blank lines)"
else
  echo "REPRO: NOT IDENTICAL -- $N files:"; diff /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha | head -40
  exit 1
fi