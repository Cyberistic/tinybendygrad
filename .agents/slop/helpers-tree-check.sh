#!/bin/sh
# helpers-tree-check.sh -- the blast-radius measurement for a change to
# tinybendygrad/helpers.bend, which 88 files import.
#
#   sh .agents/slop/helpers-tree-check.sh
#
# `--check-only` EXITS 1 EVEN ON A CLEAN FILE, so this script NEVER reads an exit
# status: it reads the FIRST LINE of stdout, which is `ALL PROOFS CHECK` or
# `SOME PROOFS FAIL`. That is the rule in agent-core.md and it is here because the
# obvious `if bend --check-only` is wrong by construction here.
#
# A RED FILE IS NOT AUTOMATICALLY MY BLAST RADIUS: `dtype.bend` has 14 permanently
# unfilled laws and any file that reaches them reports SOME PROOFS FAIL. So the
# script prints every red file's first line AND whether its own text names one of
# those 14 laws, which is how a red file is attributed rather than counted.
set -u
cd "$(dirname "$0")/../.."

OUT=.agents/slop/helpers-tree-check.txt
: > "$OUT"
green=0; red=0; redlist=""
for f in $(find tinybendygrad examples -name '*.bend' | sort) .bend; do
  [ -f "$f" ] || continue
  first=$(./bin/bend "$f" --check-only 2>/dev/null | head -1)
  case "$first" in
    "ALL PROOFS CHECK")
      green=$((green + 1))
      echo "GREEN $f" >> "$OUT"
      ;;
    *)
      red=$((red + 1))
      redlist="$redlist $f"
      echo "RED   $f  |  $first" >> "$OUT"
      ;;
  esac
done
echo "" >> "$OUT"
echo "green=$green red=$red" >> "$OUT"
echo "TREE CHECK: $green green, $red red, of $((green + red)) .bend files"
echo "red:$redlist"