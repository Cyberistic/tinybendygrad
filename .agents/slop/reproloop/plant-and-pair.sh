#!/bin/sh
# NOTHING may edit checks/differ.py between these: it is SUBSTRATE_INPUTS[0], so an edit
# makes every run in flight a MIXTURE (measured: runs 1 and 2 both read start != end).
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
OUT=.agents/slop/reproloop
echo "=== A: repro 1 (the Q3 plant: reach the bound) $(date -u +%H:%M:%SZ) ==="
.venv/bin/python checks/bounded.py --mb 2048 .venv/bin/python checks/differ.py repro 1 \
  > "$OUT/repro1.out" 2> "$OUT/repro1.err"
echo "repro 1 EXIT=$?"
grep -o 'WITHIN-LIMITS\|KILLED-ON-MEMORY\|TIMED-OUT' "$OUT/repro1.err" | tail -1
cat "$OUT/repro1.out"
echo "--- D0-repro.txt mtime after the refusal (must still be Oct 17) ---"
stat -f '%Sm %z bytes' -t '%Y-%m-%d %H:%M:%S' runs/graphcmp/D/D0-repro.txt
for i in 3 4; do
  echo "=== RUN $i start $(date -u +%H:%M:%SZ) ==="
  .venv/bin/python checks/bounded.py --mb 2048 .venv/bin/python checks/differ.py run \
    > "$OUT/run$i.out" 2> "$OUT/run$i.err"
  grep -o 'peak-RSS=[0-9]* MB (ceiling [0-9]*)  *[0-9]*s' "$OUT/run$i.err" | tail -1
  cp runs/graphcmp/D/D0-run-summary.txt "$OUT/summary$i.txt"
  .venv/bin/python - "$i" <<'PY'
import importlib.util, pathlib, sys
ROOT = pathlib.Path.cwd()
spec = importlib.util.spec_from_file_location("differ", ROOT/"checks/differ.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with (ROOT/".agents/slop/reproloop"/f"snap-{sys.argv[1]}.sha").open("w") as f: m.snap(f)
PY
  echo "=== RUN $i end $(date -u +%H:%M:%SZ) ==="
done
echo "ALL DONE $(date -u +%H:%M:%SZ)"
