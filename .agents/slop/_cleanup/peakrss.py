#!/usr/bin/env python3
"""Measure PEAK RSS and exit status of `./bin/bend FILE --check-only` for every port .bend.

    usage: .venv/bin/python .agents/slop/_cleanup/peakrss.py [--mb 1024] [--top 25]

WHY THIS FILE EXISTS.  On 2026-10-05 two `bun references/bend/bend2/main.ts` processes consumed
all system memory and crashed the machine. The project's timeout idiom bounds TIME
(`perl -e 'alarm N; exec @ARGV'`), so nothing bounded the memory, and `ulimit` appeared zero times
in `agent-core.md`, `substrate-check.sh` and `e2e.sh` combined.

`checks/bounded.py` fixed the mechanism -- it is a watchdog that watches the whole process tree and
kills on RSS. But a bound that fires is a crash avoided, not a cause found. **`dtype.bend
--check-only` was measured at 240 MB PEAK and exit 1 on a file the project believes is
`ALL PROOFS CHECK`.** That is the signature of a term that does not terminate, and it will take the
machine down again the next time somebody compiles it.

So this walks every `.bend` in the port ONCE, sequentially, each under its own hard ceiling, and
reports which files are expensive. Sequential is not an optimisation: 139 unbounded compiler runs in
parallel is the workload that caused the original crash.

WHAT IT DOES NOT DO.  It does not report a verdict about any file's correctness, and it does not
treat a kill as a failure. `KILLED` means the ceiling was reached, which is a fact about the file's
term size -- the single most useful number in this project right now, and the one nobody had.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
BEND = os.path.join(ROOT, "bin/bend")
BOUNDED = os.path.join(ROOT, "checks/bounded.py")
PORT = os.path.join(ROOT, "tinybendygrad")
PEAK = re.compile(r"peak-RSS=(\d+) MB .*?(\d+)s")


def port_bends() -> list[str]:
    out = []
    for dirpath, _d, files in os.walk(PORT):
        for f in sorted(files):
            if f.endswith(".bend"):
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mb", type=int, default=1024, help="hard ceiling per file")
    ap.add_argument("--seconds", type=int, default=300)
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()

    files = port_bends()
    print(f"# peak-RSS census over {len(files)} port .bend files, "
          f"ceiling {args.mb} MB each, SEQUENTIAL")
    rows = []
    for i, rel in enumerate(files, 1):
        r = subprocess.run(
            ["env", "-u", "PYTHONPATH", ".venv/bin/python", BOUNDED,
             "--seconds", str(args.seconds), "--mb", str(args.mb), "--",
             BEND, os.path.join(ROOT, rel), "--check-only"],
            cwd=ROOT, capture_output=True, text=True, timeout=args.seconds + 120)
        blob = r.stdout + r.stderr
        m = PEAK.search(blob)
        peak = int(m.group(1)) if m else -1
        secs = int(m.group(2)) if m else -1
        killed = "KILLED-ON-MEMORY" in blob
        timed = "TIMED-OUT" in blob
        rows.append({"path": rel, "peak_mb": peak, "sec": secs, "rc": r.returncode,
                     "killed": killed, "timed_out": timed,
                     "empty": os.path.getsize(os.path.join(ROOT, rel)) == 0})
        verdict = "KILLED" if killed else ("TIMEOUT" if timed else
                                           ("EMPTY" if rows[-1]["empty"] else "-"))
        print(f"  {peak:6d} MB {secs:5d}s  rc={r.returncode:<4} {verdict:7s} {rel}"
              f"   [{i}/{len(files)}]")

    rows.sort(key=lambda d: -d["peak_mb"])
    print(f"\n# TOP {args.top} BY PEAK RSS")
    for d in rows[:args.top]:
        print(f"  {d['peak_mb']:6d} MB  {d['sec']:5d}s  rc={d['rc']:<4} {d['path']}")

    empties = [d["path"] for d in rows if d["empty"]]
    killed = [d["path"] for d in rows if d["killed"]]
    timeouts = [d["path"] for d in rows if d["timed_out"]]
    # `--check-only` reports ALL PROOFS CHECK FOR AN EMPTY FILE, so an empty file that "passes" has
    # passed nothing. Counting them here is the whole reason this census is not just a size table.
    print(f"\n# EMPTY FILES THAT WOULD REPORT `ALL PROOFS CHECK`: {len(empties)} of {len(rows)}")
    for p in empties:
        print(f"    {p}")
    print(f"# KILLED ON THE {args.mb} MB CEILING: {len(killed)} of {len(rows)}")
    for p in killed:
        print(f"    {p}")
    print(f"# TIMED OUT: {len(timeouts)} of {len(rows)}")
    for p in timeouts:
        print(f"    {p}")
    print(f"# peak over all files: {rows[0]['peak_mb']} MB")

    out = os.path.join(ROOT, "runs/peakrss.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        json.dump(rows, fh, indent=1)
    print(f"# wrote {os.path.relpath(out, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())