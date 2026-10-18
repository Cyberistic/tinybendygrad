#!/bin/sh
# Two independent corpus runs, each snapshotted, SEQUENTIALLY (never two concurrent bend).
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
OUT=.agents/slop/reproloop
for i in 1 2; do
  echo "=== RUN $i start $(date -u +%H:%M:%SZ) ==="
  .venv/bin/python checks/bounded.py --mb 2048 .venv/bin/python checks/differ.py run \
    > "$OUT/run$i.out" 2> "$OUT/run$i.err"
  echo "RUN $i token: $(grep -o 'WITHIN-LIMITS\|KILLED-ON-MEMORY\|TIMED-OUT' "$OUT/run$i.err" | tail -1)"
  cp runs/graphcmp/D/D0-run-summary.txt "$OUT/summary$i.txt"
  .venv/bin/python - "$i" <<'PY'
import importlib.util, pathlib, sys
ROOT = pathlib.Path.cwd()
spec = importlib.util.spec_from_file_location("differ", ROOT/"checks/differ.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with (ROOT/".agents/slop/reproloop"/f"snap-{sys.argv[1]}.sha").open("w") as f: m.snap(f)
print(f"run {sys.argv[1]}: {len(list((ROOT/'runs/graphcmp/D').rglob('*')))} paths")
PY
  echo "=== RUN $i end $(date -u +%H:%M:%SZ) ==="
done
