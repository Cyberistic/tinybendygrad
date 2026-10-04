#!/bin/bash
# The previous unit's cmod fixture set, its own generator, run from HERE so that
# nothing is written into `.agents/slop/i64mul/`. Reports rows present vs expected
# and how many disagree -- this is where the "54" comes from.
set -u
cd "$(dirname "$0")"
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
OUT="${1:-got54.txt}"
python3 run54.py > gen54.out 2>&1 || { echo "GENERATOR FAILED"; cat gen54.out; exit 1; }
cat gen54.out
: > "$OUT"
for f in $(ls cgate*.bend | sort -V); do
  perl -e 'alarm 900; exec @ARGV' "$BEND" "$f" 2>/dev/null | grep -E '^(cd|cm)_' >> "$OUT"
done
exp_n=$(wc -l < cexpected.txt | tr -d ' ')
got_n=$(wc -l < "$OUT" | tr -d ' ')
dis=$(comm -3 <(sort cexpected.txt) <(sort "$OUT") | grep -c '^' || true)
chg=$(comm -3 <(sort cexpected.txt) <(sort "$OUT") | grep -c '^[^ \t]' || true)
echo "rows_expected=$exp_n rows_present=$got_n lines_disagreeing=$dis rows_changed=$chg"
cd_rows=$(comm -3 <(sort cexpected.txt) <(sort "$OUT") | grep -c '^[^ \t]cd_' || true)
cm_rows=$(comm -3 <(sort cexpected.txt) <(sort "$OUT") | grep -c '^[^ \t]cm_' || true)
echo "  of which cdiv rows changed=$cd_rows   cmod rows changed=$cm_rows"
comm -3 <(sort cexpected.txt) <(sort "$OUT") | grep '^[^ \t]' | head -6 | sed 's/^/      /'
