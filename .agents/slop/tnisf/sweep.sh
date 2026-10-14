#!/bin/sh
# ONE gate at a time, never two `bend` processes. The census gate first (it is the
# one whose pin was dropped), then every other gate in gates/, serially.
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad || exit 3
OUT=.agents/slop/tnisf/sweep.rows
: > "$OUT"

run() {
  g="$1"
  .venv/bin/python "gates/$g" > ".agents/slop/tnisf/last.out" 2> ".agents/slop/tnisf/last.err"
  rc=$?
  printf '%s\t%s\t%s\n' "$g" "$rc" "$(head -c 200 .agents/slop/tnisf/last.err | tr '\n' '|')" >> "$OUT"
}

run tn_graph_census-gate.py

for f in gates/*-gate.py; do
  b=$(basename "$f")
  case "$b" in
    tn_graph_census-gate.py) continue ;;
  esac
  run "$b"
done
echo "SWEEP-DONE" >> "$OUT"