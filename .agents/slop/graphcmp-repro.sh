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

# A HEALTHY RUN, not merely a FINISHED one. MEASURED, and this is the whole reason the
# substrate wait is not enough on its own: `ready` passed, `graphcmp-run.sh` started, and a
# concurrent edit to `tinybendygrad/uop/ops.bend` landed PART WAY THROUGH -- so the first
# twelve graphs wrote real reports and the last four wrote "0 rows after 5 attempts". Both
# halves are files, both halves hash, and the diff between two such runs is a wall of
# unrelated changes that has nothing to do with reproducibility.
#
# **AND THE PINNED NUMBERS MOVE, which is worth stating rather than fixing quietly.** This
# gate pins `graphs-agree=14`. It pinned `13` an hour earlier, and the reason it changed is
# that the `fold` unit CLOSED the `ssimplify` wall and `sym` started AGREEING. So the gate
# reported "not healthy" for a run that was entirely correct and this script sat retrying it.
# A health gate pinned to a verdict COUNT is therefore a gate that can be wrong in the
# direction of refusing to measure; the numbers it pins are named here so a reader can see
# which claim moved and go and check whether the move was a fix or a break.
healthy() {
  s=runs/graphcmp/D/D0-run-summary.txt
  # EVERY LINE IS MATCHED BY ITS CONTENT, NOT BY ITS LINE NUMBER. `sed -n '4p'` was the
  # first version and it is a positional claim about a file another agent's edits can
  # renumber -- which is this file's own rule about `smallest changes carry the most risk`
  # applied to a shell script.
  grep -q '^graphs=16$' "$s" &&
  grep -q '^graphs-agree=14$' "$s" &&
  grep -q '^byte-identical=14$' "$s" &&
  grep -q '^not-comparable=0$' "$s" &&
  grep -q '^selfcheck=# SELFCHECK: OK$' "$s" &&
  grep -q '^census-rc=rc=0$' "$s" &&
  # THE THREE COUNTS THAT KEEP A SILENT STEP FROM LOOKING HEALTHY. MEASURED, and this is
  # the sharpest form of the trap in this project: with the substrate cold, BOTH members of a
  # stability pair wrote the same one-line `0 rows after 5 attempts` file, so `cmp -s` called
  # the pair BYTE-IDENTICAL and `stable-pairs` read 5 of 5. **Two identical FAILURES compare
  # equal.** So the health gate reads the FAILED and DIFFER counts, not the identical one --
  # a positive count alone cannot distinguish "it worked" from "it failed the same way
  # twice", and only the negative counts can.
  grep -q '^stable-pairs=5 of 5$' "$s" &&
  grep -q '^stable-failed=0 of 5$' "$s" &&
  grep -q '^stable-differ=0 of 5$' "$s" &&
  grep -q '^plants-disagree=6 of 6$' "$s" &&
  grep -q '^cross=1 of 1$' "$s" &&
  grep -q '^controls=5 of 5$' "$s" &&
  grep -q '^conflations=4 of 4$' "$s" &&
  grep -q '^oracle-selfcheck=# ORACLE SELFCHECK: OK$' "$s"
}
clean_run() { # clean_run <label>: run until healthy, bounded.
  i=0
  while [ "$i" -lt "$WAIT" ]; do
    ready && sh .agents/slop/graphcmp-run.sh > /dev/null 2>&1
    if healthy; then echo "# $1: healthy run"; return 0; fi
    echo "# $1: run $((i+1)) was NOT healthy (a concurrent edit to uop/ops.bend most likely) -- waiting"
    i=$((i+1)); sleep 30
  done
  echo "# $1: no healthy run in $WAIT attempts -- this is NOT a measurement"; return 1
}

clean_run "run A" || exit 2
snap > /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha
echo "# run A done: $(wc -l < /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha | tr -d ' ') files snapshotted"
clean_run "run B" || exit 2
snap > /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha
N=$(wc -l < /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha | tr -d ' ')
if cmp -s /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha; then
  echo "REPRO: $N of $N files identical across two clean runs (sha256 over non-blank lines)"
else
  echo "REPRO: NOT IDENTICAL -- $N files:"; diff /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproA.sha /private/tmp/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gcreproB.sha | head -40
  exit 1
fi