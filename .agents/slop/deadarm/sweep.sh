#!/bin/zsh
# deadarm/sweep.sh -- the tree-wide census, sharded, never touching the live tree.
#
#   zsh .agents/slop/deadarm/sweep.sh [SHARDS]
#
# WHY SHARDED.  The census runs one instrument at a time under `sys.settrace`, and the traced run
# of `nv-oracle.py` costs ~20s against ~7s for the same oracle in a subprocess -- so 875
# instruments serially is a multi-hour run that would starve the rest of the session.  Sharding
# by index keeps every instrument in exactly one shard (no double counting) and each shard writes
# its own TSV, which `deadarm-merge.py` reads.
#
# NOTHING HERE EDITS THE TREE.  Every instrument is COPIED TO $TMPDIR and run there, for the reason
# `.agents/slop/portexec/run-kernel.sh:22` records: a hard-coded absolute ROOT= means a lane cannot
# be planted against a copy, and a plant that cannot be planted cannot be a control.
set -u
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
N=${1:-8}
OUT="${TMPDIR:-/tmp}/deadarm-sweep"
mkdir -p "$OUT"; rm -f "$OUT"/shard-*.tsv "$OUT"/shard-*.log
cd "$ROOT" || exit 1
i=0
while [ $i -lt "$N" ]; do
  ( .venv/bin/python .agents/slop/deadarm/deadarm.py --shard "$i/$N" \
      --report "$OUT/shard-$i.tsv" > "$OUT/shard-$i.log" 2>&1 ; echo "shard $i rc=$?" \
      >> "$OUT/shard-$i.log" ) &
  i=$((i+1))
done
wait
print -r -- "sweep done: $OUT"
grep -h 'instruments examined' "$OUT"/shard-*.log