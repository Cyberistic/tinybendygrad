#!/bin/zsh
# EVERY `.bend` FILE, `--check-only`, three at a time, each under checks/bounded.py.
#   usage: zsh .agents/slop/coldness/sweep.sh
cd "$(dirname "$0")/../../.." || exit 2
mkdir -p .agents/slop/coldness/raw
find tinybendygrad -name '*.bend' | sort | xargs -P 3 -I{} zsh .agents/slop/coldness/one.sh {}
print -r -- "SWEEP DONE: $(find .agents/slop/coldness/raw -name '*.txt' | wc -l | tr -d ' ') file(s)"