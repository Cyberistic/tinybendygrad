#!/bin/sh
# f2f-pad.sh -- arena-size sweep for the `f2f` fixtures, BEFORE and AFTER a candidate
# dtype.bend, plus CPython first. Refuses to trust itself twice.
#
# WHY A SIZE SWEEP. A wrong value that is an ARENA INDEX is a function of the fixture's
# POSITION, not of its value: `dd_band`'s third parameter is `dc_cint(ar, k)`, so passing
# `O.Found.i(s)` interns `CONST <the slot number of s>`. Nothing about the fixture's value
# changes that. PREPENDING PARAMs shifts every index by exactly `pad`, so a wrong index
# mask moves by `pad` and a right one does not move at all. agent-core.md records
# `l2i_cdiv.abs` agreeing at one arena size and breaking at the next.
#
# **AND THE CALIBRATION, which matters more than the sweep.** Four injected defect
# classes were measured against this sweep. It catches ONE of them:
#
#     class                                  caught by the sweep?
#     a FIXED WRONG INDEX                    YES -- moves by exactly `pad`
#     a WRONG CONSTANT                       no  -- position-independent
#     a WRONG OFFSET (x+1 vs x)              no  -- position-independent
#     a STALE ARENA                          no  -- the stale arena still prints
#
# So a clean sweep is NOT evidence about the `f2f.up.tail` / `f2f.fnuz` / `f2f.ocp`
# fix. That fix's evidence is the FORWARD REFERENCE and the CPython cone, both of which
# this sweep cannot see: a stale arena is still an arena, and reading out of range answers
# the arena bottom rather than failing. `tools/inject` is `.agents/slop/f2f-inject.py`.
#
# SUBSTRATE. `uop/ops.bend` is another unit's and changed under this one mid-session
# (3 observed digests). The sweep pins a SNAPSHOT and prints snapshot-vs-live on both
# files, so a row that moved is attributable. `md5 -q` on macOS takes ONE file.
set -u
S=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
SNAP=$S/f2f-snap
PROBE=.agents/slop/dd-bandpad.bend
PADS="0 1 2 5 17 64"

for f in codegen/decomp/dtype.bend uop/ops.bend; do
  printf 'SUBSTRATE %-26s snap=%s live=%s\n' "$f" \
    "$(md5 -q "$SNAP/tinybendygrad/$f")" "$(md5 -q "tinybendygrad/$f")"
done

run() { # run NAME SRCDIR OUT
  W=$S/f2f-padwork/repo
  rm -rf "$S/f2f-padwork"
  mkdir -p "$W/.agents/slop"
  cp -R "$SNAP/tinybendygrad" "$W/tinybendygrad"
  cp "$2" "$W/tinybendygrad/codegen/decomp/dtype.bend"
  cp "$PROBE" "$W/.agents/slop/"
  i=0
  while [ "$i" -lt 14 ]; do
    i=$((i + 1))
    perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$W/.agents/slop/dd-bandpad.bend" \
      > "$3" 2> "$3.err"
    if [ "$(grep -c '^[A-Za-z0-9_]' "$3")" -ge 54 ]; then
      echo "  ok $1 attempt $i ($(grep -c '^[A-Za-z0-9_]' "$3") rows)"
      return 0
    fi
    sleep 8
  done
  echo "  FAILED $1: no complete row set in $i attempts" >&2
  head -6 "$3.err" >&2
  return 1
}

echo "== CPython first, the same six pads"
.venv/bin/python .agents/slop/f2f-padoracle.py > $S/f2f-pad-oracle.txt || exit 1
echo "  $(grep -c '^[a-z0-9]' $S/f2f-pad-oracle.txt) oracle rows"

FIXED="$1"
[ -n "$FIXED" ] || { echo "usage: f2f-pad.sh AFTER_BEND [BEFORE_BEND]" >&2; exit 2; }
BEFORE="${2:-}"
if [ -z "$BEFORE" ]; then
  # No pre-fix tree supplied, so the sweep runs on the CURRENT file twice, and the
  # "did the sweep move" leg below is expected to be 0 by construction. Stated rather
  # than dressed up: only the CPython leg means anything in that mode.
  BEFORE="$FIXED"
  echo "== BEFORE  (no pre-fix tree given; BEFORE == AFTER, so the MOVE leg is vacuous)"
else
  echo "== BEFORE  $(md5 -q "$BEFORE")"
fi
echo "== AFTER   $(md5 -q "$FIXED")"
run BEFORE "$BEFORE" $S/f2f-pad-before.txt || exit 1
run AFTER "$FIXED" $S/f2f-pad-after.txt || exit 1

echo "== did the sweep MOVE? whole name=value lines"
.venv/bin/python .agents/slop/f2f-pad-diff.py $S/f2f-pad-before.txt $S/f2f-pad-after.txt
echo "== does AFTER agree with CPython?"
.venv/bin/python .agents/slop/f2f-pad-diff.py $S/f2f-pad-after.txt $S/f2f-pad-oracle.txt
echo "== pads measured: $PADS"