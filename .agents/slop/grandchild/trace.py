#!/usr/bin/env python3
"""Trace what `checks/bounded.py`'s watchdog SEES on each poll, for the GRANDCHILD case.

The guard is IMPORTED, not copied, and only its module-global `group_rss` is wrapped -- the loop in
`main()` looks that name up in the module it was defined in, so the wrap is seen on every poll and
the file under study is not edited to be measured.

Each run prints one `poll` row: `t=<ms since spawn> pids=<pgrep -g pgid> alive=<guard sees the
direct child alive?> rss=<MB the guard summed>`. A run that ends WITHIN-LIMITS has an EMPTY `pids`
on its LAST row, and that row is the race: the guard decided the run was over at that instant.

    usage: .venv/bin/python .agents/slop/grandchild/trace.py N OUT.rows
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GUARD = REPO / "checks" / "bounded.py"
BOMB = "a=[]\nwhile 1: a.append(b'x'*10000000)\n"
SPAWNER = "import subprocess,sys; subprocess.Popen([sys.executable, sys.argv[1]])"

TOKENS: dict[int, str] = {}


def load() -> object:
    spec = importlib.util.spec_from_file_location("bounded_under_test", GUARD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    n, dest = int(sys.argv[1]), Path(sys.argv[2])
    grand = Path(tempfile.gettempdir()) / "bounded-grandchild.py"
    grand.write_text(BOMB)
    mod = load()
    real = mod.group_rss

    def traced(pgid: int):
        rows = real(pgid)
        log = TOKENS.get(pgid)
        if log is not None:
            log.append(rows[1])   # the pids `pgrep -g` returned, at this instant
        return rows

    mod.group_rss = traced

    runs, flakes = [], 0
    with dest.open("w") as fh:
        for i in range(1, n + 1):
            pid_box: list[int] = []
            real_popen = subprocess.Popen

            def spy(cmd, **kw):                     # capture the pgid the guard will poll for
                p = real_popen(cmd, **kw)
                pid_box.append(p.pid)
                TOKENS[p.pid] = []
                return p

            mod.subprocess.Popen = spy
            started = time.monotonic()
            sys.argv = ["bounded.py", "--seconds", "120", "--mb", "300", "--", sys.executable,
                        "-c", SPAWNER, str(grand)]
            rc = mod.main()
            pids = TOKENS.get(pid_box[0], []) if pid_box else []
            elapsed = (time.monotonic() - started) * 1000
            verdict = "MISSED" if rc == 0 else ("KILLED" if rc == 3 else f"rc={rc}")
            empties = sum(1 for r in pids if not r)
            runs.append(verdict)
            flakes += rc == 0
            fh.write(f"run={i} rc={rc} verdict={verdict} ms={elapsed:.0f} polls={len(pids)} "
                     f"empty_polls={empties} last={pids[-1] if pids else 'NO-POLL'}\n")
            fh.flush()
            print(f"run {i:3d} {verdict:6s} ms={elapsed:6.0f} polls={len(pids):3d} "
                  f"empty={empties} last={pids[-1] if pids else 'NO-POLL'}", flush=True)
            mod.subprocess.Popen = real_popen
    grand.unlink(missing_ok=True)
    print(f"\n=== {len(runs)} runs, {flakes} MISSED, rate {flakes / len(runs):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())