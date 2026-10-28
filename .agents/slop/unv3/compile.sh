#!/usr/bin/env bash
# compile.sh -- COMPILE EVERY FILE THE SLICE OWNS, ONE BEND AT A TIME.
#
#   .agents/slop/unv3/compile.sh
#
# ONE AT A TIME, AND THE VERDICT TOKEN IS READ, NOT THE EXIT CODE:
# `checks/bounded.py` is a PER-PROCESS WATCHDOG, and `AGENTS.md` records the unit
# that lost 425 rows by believing the status.
#
# THE SUM PRECONDITION: `AGENTS.md`'s rule is that the SUM of the concurrently
# running files' MEASURED peak RSS is under 60% of `hw.memsize`, and this script
# runs them SEQUENTIALLY, so the sum is the largest single file (745 MB, measured
# in `.agents/slop/peakrss/census.rows`) against a 9,830 MB budget.
set -u
cd "$(dirname "$0")/../../.." || exit 3
ROOT="$PWD"
SLICE="/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unv3.rows"
OUT=".agents/slop/unv3/compile.rows"
: > "$OUT"
printf 'file\tverdict\tpeak\n' >> "$OUT"
cut -f1 "$SLICE" | sort -u | while read -r f; do
  [ -f "$ROOT/$f" ] || continue
  log="$ROOT/.agents/slop/unv3/.compile-$$.err"
  .venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend "$f" >/dev/null 2>"$log"
  tok=$(grep -oE "WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT" "$log" | tail -1)
  peak=$(grep -oE "peak[^0-9]*[0-9]+" "$log" | tail -1)
  [ -z "$tok" ] && tok="(no-token)"
  printf '%s\t%s\t%s\n' "$f" "$tok" "$peak" >> "$OUT"
  rm -f "$log"
done
cat "$OUT"
echo "--- NOT-WITHIN-LIMITS:"
awk -F'\t' 'NR>1 && $2!="WITHIN-LIMITS"' "$OUT"
