#!/bin/zsh
# SUBSTRATE CHECK. EXISTS BECAUSE `bend --check-only` REPORTS **ALL PROOFS CHECK** FOR
# AN EMPTY FILE, MEASURED:
#     : > empty.bend ; bend empty.bend --check-only   ->  ALL PROOFS CHECK
#     printf '# nothing\n' > c.bend ; bend c.bend ...  ->  ALL PROOFS CHECK
#     printf 'def f(:\n'  > d.bend ; bend d.bend ...   ->  SOME PROOFS FAIL
#
# SO `ALL PROOFS CHECK` DOES NOT MEAN THE FILE HAS CONTENT. Every "the substrate is
# warm" statement this project has made was therefore compatible with a truncated
# file -- and `helpers.bend` WAS truncated to 0 bytes three times, each time by a unit
# that then ran --check-only, saw ALL PROOFS CHECK, and reported it fine.
#
# THIS SCRIPT ADDS THE MISSING HALF OF THE TEST: SIZE FIRST, VERDICT SECOND.
# A file of 0 lines is EMPTY, whatever bend says about it.
cd "$(dirname "$0")/../.." || exit 2
BEND=./bin/bend
[ -x "$BEND" ] || BEND=bend
fail=0
for f in "$@"; do
  [ -f "$f" ] || { print -r -- "MISSING   $f"; fail=$((fail+1)); continue }
  lines=$(wc -l < "$f" | tr -d ' ')
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$lines" -eq 0 ] || [ "$bytes" -eq 0 ]; then
    print -r -- "EMPTY     $f  ($lines lines, $bytes bytes)  <-- THE VERDICT IS MEANINGLESS"
    fail=$((fail+1)); continue
  fi
  v=$(perl -e 'alarm 300; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | head -1)
  if [ "$v" = "ALL PROOFS CHECK" ]; then
    print -r -- "WARM      $f  ($lines lines)"
  else
    print -r -- "COLD      $f  ($lines lines)  :: $v"
    fail=$((fail+1))
  fi
done
if [ "$fail" -gt 0 ]; then
  print -r -- "SUBSTRATE NOT CLEAN: $fail of $# file(s) empty, missing, or cold."
  print -r -- "ANY VERDICT TAKEN AGAINST THESE FILES IS **INCONCLUSIVE**, NOT A RESULT."
  exit 1
fi
print -r -- "SUBSTRATE CLEAN: $# file(s), all non-empty and ALL PROOFS CHECK."
