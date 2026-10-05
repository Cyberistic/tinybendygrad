#!/bin/bash
# gr-diff.sh -- compare the port's gate output to CPython's pm_post_sched_cache.
#
# BOTH SIDES PRINT op+arg, NOT arena indices. The port's arena indices are its
# own and mean nothing outside the file, so a numeric diff would compare two
# unrelated numberings. The comparable thing is the MAPPING's SHAPE: how many
# repl entries, and for each, which op the source is and which op the
# destination is.
#
# A DISAGREEMENT PRINTS BOTH LANES AND EXITS 1. A COUNT MATCH PRINTS THE
# COUNTS AND EXITS 0 -- the count is the coarse gate, and the per-entry
# comparison is a FUTURE unit once the port's printer can name ops.

set -e
cd "$(dirname "$0")/../.."

py_line=$(python3 .agents/slop/gr-oracle.py | grep "^repl=")
bend_line=$(./bin/bend tinybendygrad/codegen/__init__.bend)

py_count=$(printf '%s' "$py_line" | tr ',' '\n' | grep -c -- '->')
bend_count=$(printf '%s' "$bend_line" | tr ',' '\n' | grep -c -- '->')

echo "gr-diff: py_count=$py_count bend_count=$bend_count"
if [ "$py_count" -eq "$bend_count" ]; then
  echo "gr-diff: AGREE on $py_count repl entries"
  exit 0
fi

echo "gr-diff: DISAGREE"
echo "  CPython: $py_line"
echo "  Port:    $bend_line"
exit 1
