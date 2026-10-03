#!/bin/bash
# gr-diff.sh -- run the CPython oracle and the port, diff the repl.
# 
# usage: bash .agents/slop/gr-diff.sh
# 
# Returns 0 if the two repls agree node-for-node and key-for-key.
# Returns 1 with a diff if they don't.

set -e
cd "$(dirname "$0")/../.."

# Run the CPython oracle
py_out=$(python3 .agents/slop/gr-oracle.py)

# Run the port gate
bend_out=$(./bin/bend tinybendygrad/codegen/__init__.bend)

if [ "$py_out" = "$bend_out" ]; then
  echo "gr-diff: AGREE"
  echo "  $py_out"
  exit 0
fi

echo "gr-diff: DISAGREE"
echo "  CPython: $py_out"
echo "  Port:    $bend_out"
exit 1
