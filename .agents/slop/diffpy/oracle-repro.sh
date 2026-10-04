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
cd "${GCMP_REPO:-$(dirname "$0")/../..}" || exit 2   # ORACLE COPY: the ONLY edit, and it is
# a path. Frozen verbatim at the shas below so the copy cannot drift unnoticed.
WAIT=${1:-9}
snap() {
  # DOTFILES ARE EXCLUDED, and that is not cosmetic: `run()` stages each output as
  # `$D/.tmp.<name>` and `mv`s it into place, so a run killed mid-write leaves a temp behind.
  # A temp that exists in one snapshot and not the other is a difference in the HARNESS's
  # staging, not in the artefact. `find -name '.*' -prune` skips the dotfiles and their
  # directories.
  find runs/graphcmp/D -name '.*' -prune -o -type f -print | sort | while read -r f; do
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
  grep -q '^graphs=24$' "$s" &&
  grep -q '^graphs-agree=22$' "$s" &&
  grep -q '^byte-identical=21$' "$s" &&
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
  grep -q '^plants-disagree=7 of 7$' "$s" &&
  grep -q '^cross=1 of 1$' "$s" &&
  grep -q '^controls=5 of 5$' "$s" &&
  grep -q '^conflations=4 of 4$' "$s" &&
  grep -q '^oracle-selfcheck=# ORACLE SELFCHECK: OK$' "$s"
}
# THE ARTEFACTS THEMSELVES, not the summary about them. MEASURED, and this is the fourth
# time in this file that a summary line was the wrong thing to gate on:
#   * `D2-canon-bend-*.txt` is written by a BARE redirect in step 02 (it needs stdout in two
#     files, so it cannot use `run()`), so a 0-byte bend side there is caught only by the
#     byte-count guard downstream -- and a whole RUN's snapshot was taken with one of them
#     empty, which `not-comparable=0` in the summary did not describe;
#   * `run()` is now atomic (LIMITS 25), so a 1-line `rc=N` file can only be a genuine
#     0-row FAILURE -- and two identical ones compared equal (LIMITS 22).
# A gate that reads the summary trusts that the summary and the files were written at the
# same time by the same attempt. They were not, when a step can fail. So this counts the
# SHAPE of every artefact: no `D*.txt` may be empty, and none may be a single `rc=` line.
# `*.err` files are legitimately empty (stderr was empty) and are excluded -- and that
# exclusion is the other half of the rule, because a gate that flagged them would be a gate
# that always fails.
artefacts_ok() {
  # EVERY artefact must be non-empty. MEASURED: `D2-canon-bend-indexed.txt` was 0 bytes in a
  # run whose summary said `not-comparable=0`.
  find runs/graphcmp/D -name '*.txt' ! -name '*.err' | while read -r f; do
    [ -s "$f" ] || echo "EMPTY $f"
  done
  # A `diff` REPORT must have more than one line -- a one-line `rc=N` file IS the 0-row
  # failure shape, and two of them compared equal. The other artefacts are legitimately one
  # line (`D2-cmp-*` is a verdict line, `D1-verdicts.txt` is an assertion line,
  # `D8-dbg-012.txt` is a verdict line), so the rule is stated over the `diff` reports by
  # name rather than over every file: a rule that flags a correct file is a rule that always
  # fails, and then it is not a rule.
  find runs/graphcmp/D \( -name 'D1-graph-*.txt' -o -name 'D3-control-*.txt' \
    -o -name 'D5-plant-*.txt' -o -name 'D6-*.txt' -o -name 'D9-stability-*.txt' \) \
    ! -name '*.err' | while read -r f; do
    [ "$(wc -l < "$f" | tr -d ' ')" -le 1 ] && echo "ONE-LINE $f"
  done
}

clean_run() { # clean_run <label>: run until healthy, bounded.
  i=0
  while [ "$i" -lt "$WAIT" ]; do
    ready && sh "${GCMP_RUN:-.agents/slop/graphcmp-run.sh}" > /dev/null 2>&1  # ORACLE COPY edit 2/2
    if healthy; then
      bad=$(artefacts_ok)
      if [ -z "$bad" ]; then
        echo "# $1: healthy run, and every artefact has a body"
        return 0
      fi
      echo "# $1: summary healthy but $(echo "$bad" | wc -l | tr -d ' ') malformed artefact(s): $(echo "$bad" | head -2 | tr '\n' ' ')"
    else
      echo "# $1: run $((i+1)) summary was NOT healthy -- waiting"
    fi
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