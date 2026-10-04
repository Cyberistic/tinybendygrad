#!/bin/bash
# cmod gate: one process per batch (a single 852-row program overflows the stack),
# rows-present against rows-expected, whole `name=value` lines diffed.
cd "$(dirname "$0")"
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
python3 gen_cmod.py > cgen.out 2>&1 || { echo "GENERATOR FAILED"; cat cgen.out; exit 1; }
: > cgot.txt
for f in cgate*.bend; do
  "$BEND" "$f" 2>/dev/null | grep -E '^(cd|cm)_' >> cgot.txt
done
exp_n=$(wc -l < cexpected.txt | tr -d ' ')
got_n=$(wc -l < cgot.txt | tr -d ' ')
miss=$(comm -23 <(sort cexpected.txt) <(sort cgot.txt) | grep -c '^' || true)
extra=$(comm -13 <(sort cexpected.txt) <(sort cgot.txt) | grep -c '^' || true)
echo "rows_expected=$exp_n rows_present=$got_n missing=$miss extra=$extra"
if [ "$miss" -ne 0 ] || [ "$extra" -ne 0 ]; then
  echo "--- DISAGREEMENTS ---"
  comm -3 <(sort cexpected.txt) <(sort cgot.txt) | head -30
  exit 1
fi
echo "ALL CMOD/CDIV ROWS AGREE"