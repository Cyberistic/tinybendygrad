#!/bin/zsh
# t.sh -- try.py on each argument, with a header.
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
for line in "$@"; do
  print -r -- "=== $line"
  .venv/bin/python .agents/slop/citefix9/try.py "$line"
done
