#!/bin/sh
# dd-sweep.sh -- run `.agents/slop/dd-sweep.bend` at SEVERAL arena sizes and say whether
# the sensitive rows move.
#
# The `l2i_cdiv.abs` precedent: an arena-aliasing defect in dtype.bend AGREED at one
# node-count configuration and broke at the next, so a fix is not evidence until it has
# held at several sizes. `dd-sweep.bend` prepends `pad` PARAMs to the arena and re-runs the
# gate's own row sequence, printing the four rows that have already failed once
# (`lgqk/lgrk/lgsk/lgtk`, as cone size plus the cone's CONST list) and the four cone sizes.
#
# bend's machine stack overflows on ~1 run in 20 and prints ZERO rows, which is
# indistinguishable from "not started", so every attempt is LOOPED and a run with no
# `lgq` block is retried. Never gate on the exit code.
#
# usage: dd-sweep.sh "0 1 2 5 17 64"
set -u
PROBE=.agents/slop/dd-sweep.bend
for K in ${1:-"0 1 2 5 17 64"}; do
  perl -pi -e "s/pad\([0-9]+, O\.Arena\.empty\(\)\)/pad($K, O.Arena.empty())/; s/\"# pad=\", U32\.show\([0-9]+\)/\"# pad=\", U32.show($K)/" "$PROBE"
  OUT="/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/dd-sweep-$K.txt"
  i=0
  while [ "$i" -lt 10 ]; do
    i=$((i + 1))
    perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$PROBE" > "$OUT" 2>"$OUT.err"
    if grep -q '^lgqcone=' "$OUT"; then break; fi
    sleep 10
  done
  if grep -q '^lgqcone=' "$OUT"; then
    # the `# pad=` line is the SIZE, so it is excluded from the comparison
    grep -v '^# pad=' "$OUT" > "$OUT.rows"
    echo "pad=$K ok (attempt $i)"
  else
    echo "pad=$K FAILED after $i attempts" >&2
    head -3 "$OUT.err" >&2
  fi
done