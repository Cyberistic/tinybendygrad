#!/bin/sh
# groupflip-baseline.sh -- the BEFORE/AFTER lane for gates/groupflip-gate.py, and NOT A GATE.
#
# **IT PRODUCES NO VERDICT AND ITS EXIT STATUS IS NOT ONE.** It is a MEASUREMENT HARNESS, and
# `gates/README.md`'s reason the shell form was retired is that a shell gate can pass having
# measured nothing; this file cannot pass or fail at all, it only writes rows. `gates/*.py` is
# the gate surface, and `ls gates/*.sh | wc -l` = 1 BECAUSE OF THIS FILE -- MEASURED -- so the
# "gates are Python, never shell" rule is read here as "a `.sh` in `gates/` may not be a gate",
# which this file is not. It is here because it IS the command line that produced the corpus's
# BEFORE and AFTER `D1` rows -- which are the evidence for the finding that the two are
# BYTE-IDENTICAL. Everything it runs is `checks/differ.py`'s own corpus driver, one graph at a
# time.
#
# ONE GRAPH PER `checks/bounded.py --mb 2048` INVOCATION, SEQUENTIALLY, so at most one `bend`
# process exists at a time: `AGENTS.md`'s parallelism precondition is on the SUM of the
# concurrently-running files' peak RSS, and the census that table comes from
# (`.agents/slop/peakrss/census.rows`) puts `graphcmp` in the heavy half.
#
# usage: gates/groupflip-baseline.sh <outdir>
#        every graph's `--side bend` emission lands in <outdir>/<graph>.bend.rows and every
#        verdict record in <outdir>/<graph>.bounded
cd "$(dirname "$0")/.." || exit 2
OUT="$1"
[ -n "$OUT" ] || { echo "usage: gates/groupflip-baseline.sh <outdir>" >&2; exit 2; }
mkdir -p "$OUT" || exit 2
for g in alu bit bw cdiv commute group late move sym threefry where flip; do
  DEV=CPU SPEC=1 .venv/bin/python checks/bounded.py --mb 2048 -- \
    .venv/bin/python .agents/slop/graphcmp.py emit --graph "$g" --side bend \
    > "$OUT/$g.bend.rows" 2> "$OUT/$g.bounded"
done