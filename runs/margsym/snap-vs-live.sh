#!/bin/sh
# snap-vs-live.sh -- PRINT THE PINNED SNAPSHOT'S CHECKSUMS BESIDE THE LIVE TREE'S, for
# the four files `fold.bend`'s answer depends on. A 0-row bend run and a fold.bend
# that another agent has left mid-write look IDENTICAL from the exit status, and this
# repo has measured that cost: `ops.bend` has repeatedly gone cold under other units
# and a mutation baseline captured across the transition moves on every mutation.
#   sh runs/margsym/snap-vs-live.sh
set -u
cd "$(dirname "$0")/../.." || exit 2
for f in uop/fold.bend uop/ops.bend ../helpers.bend ../LAWS/spec.bend; do
  case "$f" in
    ../*) live="tinybendygrad/${f#../}"; snap="runs/margsym/snap/tinybendygrad/${f#../}" ;;
    *)    live="tinybendygrad/$f";      snap="runs/margsym/snap/tinybendygrad/$f" ;;
  esac
  a=$(md5 -q "$snap"); b=$(md5 -q "$live")
  if [ "$a" = "$b" ]; then s="SAME"; else s="** DIFFERS **"; fi
  echo "$f  snap=$a live=$b  $s"
done
