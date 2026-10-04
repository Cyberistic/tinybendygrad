#!/bin/zsh
# ONE FILE, UNDER BOTH BOUNDS, raw output kept so the verdict is auditable.
#
# substrate-check.sh runs bend with `perl -e 'alarm 300; exec @ARGV'` -- a TIME bound
# and no memory bound, which is the invocation that took the machine down twice on
# 2026-10-05. Same question, asked through checks/bounded.py so both bounds hold.
#   usage: zsh one.sh <file.bend>
f=$1 || exit 2
cd "$(dirname "$0")/../../.." || exit 2
.venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
  ./bin/bend "$f" --check-only > ".agents/slop/coldness/raw/$(print -r -- "$f" | tr '/' '_').txt" 2>&1 \
  || true