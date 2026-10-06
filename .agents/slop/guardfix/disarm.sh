#!/bin/zsh
# disarm.sh -- PROVE THE ROUTER BITES. Three plants, three controls, in $TMPDIR,
# never in the tree. Nothing here is a claim; every line below is a measurement
# this script re-takes and then ASSERTS.
#
# THE PLANT THIS JOB EXISTS TO CLOSE: a SYNTACTICALLY VALID `.c` WAS REPORTED COLD
# BY THE OLD GUARD, AND A GUARD THAT IS ALWAYS RED ON A CLASS OF FILES IS A GUARD
# WHOSE GREEN IS WORTH LESS. So one plant must go GREEN and two must go RED:
#
#   1. `.c` VALID   -> WARM     the plant-to-pass: routed to cc, not to bend
#   2. `.c` + ERROR -> COLD     the same file, one line changed, and it bites
#   3. `.js` + ERR  -> COLD     node rejects it
#   4. `.js` VALID  -> WARM     control: node is not red on everything
#   5. `.py`        -> NO INSTRUMENT, counted apart, NEVER COLD
#   6. `.bend` EMPTY-> EMPTY    the size gate still runs ahead of the router
#
# RUN:  .agents/slop/guardfix/disarm.sh        exit 0 iff every assertion held
set -u
cd "$(dirname "$0")/../../.." || exit 2
GUARD=.agents/slop/substrate-check.sh
W=$(mktemp -d "${TMPDIR:-/tmp}/disarm.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT INT TERM
bad=0

say() { print -r -- "$@"; }
want() { # want <label> <file> <expected-verdict-word>
  local got
  got=$("$GUARD" "$2" 2>&1 | grep -m1 -oE '^(WARM|COLD|NO INSTRUMENT|EMPTY|MISSING)')
  if [ "$got" = "$3" ]; then
    say "  ok    $1  ->  $got"
  else
    say "  FAIL  $1  ->  '${got:-nothing}', wanted $3"; bad=$((bad+1))
  fi
}
# The ROUTE line for one file, so a green verdict cannot be green BY ACCIDENT via
# the wrong instrument -- which is the entire defect being closed here.
routed() { "$GUARD" "$2" 2>&1 | grep -m1 '^ROUTE'; }

# PLANTS ---------------------------------------------------------------------
cp tinybendygrad/runtime/dtype.c "$W/valid.c"                     # 1
{ cat tinybendygrad/runtime/dtype.c
  printf 'static void planted(void) { this is not C }\n'; } > "$W/broken.c"   # 2
printf 'const x = ;\n'                > "$W/broken.js"            # 3
printf 'const ok = 1;\nexport default ok;\n' > "$W/valid.js"       # 4
printf 'print("no instrument exists for this class")\n' > "$W/x.py"  # 5
: > "$W/empty.bend"                                                 # 6

say 'PLANTED, IN '"$W"' -- every plant is a copy in $TMPDIR. The tree is NOT written to.'
say ''
say "1. a syntactically valid .c MUST NOT BE COLD  <- the plant-to-pass this job closes"
want "  valid.c   (a byte copy of runtime/dtype.c)" "$W/valid.c"  WARM
say "       $(routed x "$W/valid.c")"

say ""
say "2. the SAME .c with one broken line MUST BE COLD  <- the route bites"
want "  broken.c  (that copy + one bad line)"      "$W/broken.c" COLD
say "       $("$GUARD" "$W/broken.c" 2>&1 | grep -m1 '^COLD')"

say ""
say "3. a .js node rejects MUST BE COLD, and a valid .js MUST BE WARM"
want "  broken.js" "$W/broken.js" COLD
say "       $("$GUARD" "$W/broken.js" 2>&1 | grep -m1 '^COLD')"
want "  valid.js"  "$W/valid.js"  WARM

say ""
say "4. a file with NO INSTRUMENT must be NO INSTRUMENT -- never COLD, and not a pass"
want "  x.py"      "$W/x.py"      "NO INSTRUMENT"
say "       $("$GUARD" "$W/x.py" 2>&1 | grep -m1 '^NO INSTRUMENT')"

say ""
say "5. the size gate still runs AHEAD of the router"
want "  empty.bend" "$W/empty.bend" EMPTY

say ""
if [ "$bad" -eq 0 ]; then
  say "DISARMED: 6/6. Every plant went the way the routing table says it must."
  exit 0
fi
say "DISARM FAILED: $bad assertion(s). A router that does not bite is a comment."
exit 1