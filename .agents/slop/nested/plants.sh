#!/bin/zsh
# .agents/slop/nested/plants.sh -- THE PLANT AND THE DISARM, ON THE NESTED BACK EDGE.
#
#   zsh .agents/slop/nested/plants.sh
#
# THE LIVE TREE IS ONLY EVER READ.  Each control gets its OWN copy from mkproof.sh,
# which copies tinybendygrad -- the .bend imports are RELATIVE -- and symlinks bin/,
# references/, tinygrad/ and .venv/, the shape e2e_port/run-port-mm.sh uses, for the
# measured reason that a scratch copy which cannot resolve them produced 22 phantom
# blind spots in one unit.
#
# A PLANT THAT CHANGES THE SHAPE PROVES YOU CHANGED THE FIXTURE, NOT THE LOOP, so
# every plant here is the del, the BOUND or the INCREMENT -- never the nesting and
# never the packet.  Each has a paired DISARM: the EXACT REVERSE EDIT, applied to the
# SAME copy and rebuilt, which must go GREEN again.  A red with no paired disarm says
# nothing about where it landed.
#
# NO BACKTICKS IN THE say STRINGS: zsh runs them, and one of them ate the word `del`
# out of a header on the first run of this file.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PY="$ROOT/.venv/bin/python"
W=${1:-${TMPDIR}/nested-plants}
MINE="$ROOT/.agents/slop/nested"
PLANT="$ROOT/.agents/slop/e2e_port/plant.py"
DEL_OLD='case True{}: Prog.at(Prog.rng.del(p, u), U32.add(Prog.loop(p, Prog.pc(p)), 1))'
DEL_NEW='case True{}: Prog.at(p, U32.add(Prog.loop(p, Prog.pc(p)), 1))'
INC_OLD='Bool.pick(U32, seen, U32.add(Prog.cur(p, u), 1), Prog.cur(p, u))'
INC_NEW='Bool.pick(U32, seen, U32.add(Prog.cur(p, u), 2), Prog.cur(p, u))'
FLG_OLD='U32.add(Uop.slot(u), 1), elem_of(0, Uop.dt(u))))'
FLG_NEW='U32.add(Uop.slot(u), 1), elem_of(1, Uop.dt(u))))'
rc=0
say() { print -r -- "$@" }
mkdir -p "$W"

# A build that fails on a def in ANOTHER file is SUBSTRATE, not a verdict, and it is
# retried: another agent moved uop/ops.bend out from under this one mid-run.
build() {  # build <copy> <exe>
  local i=0 out
  while [ $i -lt 4 ]; do
    i=$((i + 1))
    "$ROOT/bin/bend" "$1/tinybendygrad/runtime/ops_python.bend" -o "$2" > "$1.build" 2>&1 && return 0
    out=$(sed -n 's/^>| *//p' "$1.build" | head -1)
    out=$(grep -E '^[0-9]+ \|' "$1.build" | tail -1)
    case "$out" in
      *ops_python.bend*) say "      build failed IN ops_python.bend: $out"; return 1 ;;
      *) say "      build failed in another file (SUBSTRATE, attempt $i): $out" ;;
    esac
    sleep 10
  done
  return 1
}

gate() {  # gate <exe> <tag>
  "$PY" "$MINE/gate.py" "$1" > "$W/$2.txt" 2>&1
  local g=$?
  grep -E '^(case|mm2|mm3|mm4|perm3|perm4|flat3|red2step|cases=)' "$W/$2.txt" | sed 's/^/    /'
  return $g
}

setup() {  # setup <tag> <old> <new>
  sh "$MINE/mkproof.sh" "$W/$1" > "$W/$1.mk" 2>&1 || return 1
  if [ -n "$2" ]; then "$PY" "$PLANT" "$W/$1/tinybendygrad/runtime/ops_python.bend" "$2" "$3" || return 1; fi
  build "$W/$1" "$W/exe-$1" || return 1
  return 0
}

expect_red() {  # expect_red <tag> <regex>
  if grep -qE "$2" "$W/$1.txt"; then say "  RED   [$1]"; return 0; fi
  say "  *** went wrong, but NOT on the row naming the break [$1] ***"; rc=1; return 1
}
expect_green() {  # expect_green <tag>
  if [ $1 -eq 0 ]; then say "  GREEN [$2]"; return 0; fi
  say "  *** NOT GREEN [$2] ***"; rc=1; return 1
}

say "== C0  THE COPY, UNPLANTED.  Mandatory: without a GREEN copy, C1..C3 prove NOTHING."
if setup c0 "" ""; then gate "$W/exe-c0" c0; expect_green $? "C0 the unplanted copy"
else say "  *** C0 DID NOT BUILD -- C1..C3 would prove NOTHING ***"; rc=1; fi

say ""
say "== C1  THE BACK EDGE.  Remove the del from the RANGE exit path -- the skipped"
say "        del of values[u], and nothing else.  Only the DEPTH>=2 rows may move."
if setup c1 "$DEL_OLD" "$DEL_NEW"; then
  gate "$W/exe-c1" c1
  expect_red c1 '^mm2 +2 +2 .* False'
  expect_red c1 '^perm3 +2 +2 .* False'
  grep -qE '^red2step +1 +1 .* True' "$W/c1.txt" && say "  and the DEPTH-1 rows stayed green, which is what makes this the nested defect and not a loop defect"
  say "-- C1d DISARM: the exact reverse edit, same copy, rebuilt."
  "$PY" "$PLANT" "$W/c1/tinybendygrad/runtime/ops_python.bend" "$DEL_NEW" "$DEL_OLD" && build "$W/c1" "$W/exe-c1d" && gate "$W/exe-c1d" c1d
  expect_green $? "C1d disarmed"
else rc=1; fi

say ""
say "== C2  THE INCREMENT.  cur+1 becomes cur+2, so every other index is skipped."
say "        A depth-1 row must move too: that is what makes the depth-1 rows live."
if setup c2 "$INC_OLD" "$INC_NEW"; then
  gate "$W/exe-c2" c2
  expect_red c2 '^flat3 +1 +1 .* False'
  say "-- C2d DISARM."
  "$PY" "$PLANT" "$W/c2/tinybendygrad/runtime/ops_python.bend" "$INC_NEW" "$INC_OLD" && build "$W/c2" "$W/exe-c2d" && gate "$W/exe-c2d" c2d
  expect_green $? "C2d disarmed"
else rc=1; fi

say ""
say "== C3  THE del's FLAG CLEAR, 0 becomes 1.  The counter is still zeroed, so the"
say "        loop DOES re-enter -- one pass late, and the first body pass of every"
say "        later pass is lost.  A back-edge off-by-one, not a shape change."
if setup c3 "$FLG_OLD" "$FLG_NEW"; then
  gate "$W/exe-c3" c3
  expect_red c3 '^mm2 +2 +2 .* False'
  say "-- C3d DISARM."
  "$PY" "$PLANT" "$W/c3/tinybendygrad/runtime/ops_python.bend" "$FLG_NEW" "$FLG_OLD" && build "$W/c3" "$W/exe-c3d" && gate "$W/exe-c3d" c3d
  expect_green $? "C3d disarmed"
else rc=1; fi

say ""
say "== MEASURED AND NOT COUNTED: the BOUND plant is_eq becomes is_gt on the RANGE exit."
say "   Every lane FELL OVER with Prog.bad (a store one element past the buffer) rather"
say "   than answering wrongly, so it is a refusal and not a catch.  Recorded, not counted."
say ""
if [ $rc -eq 0 ]; then say "PLANTS PASS -- C0 green; C1/C2/C3 red on the named rows; every disarm green."
else say "PLANTS FAILED -- see $W"; fi
exit $rc
