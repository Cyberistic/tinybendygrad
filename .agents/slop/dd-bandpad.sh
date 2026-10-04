#!/bin/sh
# dd-bandpad.sh -- run dd-bandpad.bend on the UNFIXED and the FIXED dtype.bend and diff.
#
# WHY A SIZE SWEEP IS LOAD-BEARING HERE. `agent-core.md` records `l2i_cdiv.abs` as a defect
# that AGREED at one arena size and broke at the next, and four arena-aliasing defects
# whose signature is "count barely moves, cone collapses". A wrong mask that is an ARENA
# INDEX is the purest case of that: it is a function of the fixture's POSITION, so `pad = k`
# moves it by exactly `k` while the right mask does not move at all.
#
# BOTH TREES CARRY THE SAME `uop/ops.bend`. It is another unit's and was observed in three
# states inside forty minutes, the third not compiling (`type Arg` declared twice, lines
# 1110 and 1349), so the substrate is a FROZEN SNAPSHOT and `md5 -q` is asserted on it.
# `md5 -q` on macOS takes exactly ONE file: two prints nothing and reads as a silent pass.
#
# UNFIXED is the LIVE dtype.bend (read-only copy). FIXED is the same file with
# dd-band-fix.sh applied. Neither tree is ever written by a run.
set -u
S=/private/var/folders/yd/qy2_4kv13kq_b0dsnv_71wvr0000gn/T/opencode
S=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
SNAP=$S/dd-band-snap/tinybendygrad
LIVE=tinybendygrad/codegen/decomp/dtype.bend
OPS=9833ceab6b5fd24eee5ffd471a66678c

[ "$(md5 -q "$SNAP/uop/ops.bend")" = 3cd6e0dffc617f0c3bbf1e942af86705 ] \
  || { echo "RULE I: frozen ops.bend is not the snapshot's" >&2; exit 2; }

rm -rf $S/dd-band-fixsrc
mkdir -p $S/dd-band-fixsrc
cp -R $SNAP $S/dd-band-fixsrc/tinybendygrad
.agents/slop/dd-band-fix.sh > $S/pad-fixlog.txt 2>&1 || { echo "FIX DID NOT APPLY" >&2; cat $S/pad-fixlog.txt >&2; exit 2; }

build() { # build NAME SRCDIR
  rm -rf "$S/$1"
  mkdir -p "$S/$1"
  cp -R "$SNAP" "$S/$1/tinybendygrad"
  cp "$2" "$S/$1/tinybendygrad/codegen/decomp/dtype.bend"
  md5 -q "$S/$1/tinybendygrad/codegen/decomp/dtype.bend"
}

run() { # run NAME OUT
  W=$S/dd-band-padwork/repo
  rm -rf "$W"
  mkdir -p "$W/.agents/slop"
  cp -R "$S/$1/tinybendygrad" "$W/tinybendygrad"
  cp .agents/slop/dd-bandpad.bend "$W/.agents/slop/"
  i=0
  while [ "$i" -lt 14 ]; do
    i=$((i + 1))
    perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$W/.agents/slop/dd-bandpad.bend" \
      > "$2" 2>"$2.err"
    # RULE E/H: an empty run is bend's stack overflow and is NOT "no rows moved".
    if grep -q '^w1.p0=' "$2" && [ "$(grep -c '^[A-Za-z0-9_]' "$2")" -ge 54 ]; then
      echo "  ok attempt $i ($(grep -c '^[A-Za-z0-9_]' "$2") rows)"
      return 0
    fi
    sleep 8
  done
  echo "  FAILED: no complete row set in $i attempts" >&2
  head -8 "$2.err" >&2
  return 1
}

echo "== UNFIXED  md5 $(build padU $LIVE)"
run padU $S/pad-before.txt || exit 1
echo "== FIXED    md5 $(build padF $S/dd-band-fixsrc/tinybendygrad/codegen/decomp/dtype.bend)"
run padF $S/pad-after.txt || exit 1

echo "== DIFF, whole name=value lines"
.venv/bin/python .agents/slop/dd-band-paddiff.py $S/pad-before.txt $S/pad-after.txt