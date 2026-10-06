#!/bin/zsh
# LL-2 -- whole-tree foreign-law census, as a SCRIPT.
#
# Inline `xargs -P 6 -I{} sh -c '...'` lost every line of its own output once in this
# session -- 137 files in, 0 out, no error -- so the walk is a file. A census that
# reports "0 red" because it printed nothing is exactly the zero-denominator trap
# with an extra step, and this one also REFUSES an empty census.
#
# Usage: sweep.sh <tinybendygrad-dir>   -> "<n> <relative-path>" per line, red only
set -u
ROOT=$1
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
OUT=$(mktemp)
find "$ROOT" -name '*.bend' | while read -r f; do
  n=$("$REPO/bin/bend" "$f" --check-only 2>&1 | grep -oE '^Error: [0-9]+ defs rely' | grep -oE '[0-9]+' | head -1)
  print -r -- "${n:-0} ${f#$ROOT/}"
done > "$OUT"
tot=$(wc -l < "$OUT" | tr -d ' ')
if [[ "$tot" -eq 0 ]]; then
  print -u2 "SWEEP REFUSES AN EMPTY CENSUS (0 of 137 files examined)"
  exit 2
fi
print -r -- "TOTAL $tot  red $(awk '$1!=0' "$OUT" | wc -l | tr -d ' ')"
awk '$1!=0' "$OUT"
rm -f "$OUT"