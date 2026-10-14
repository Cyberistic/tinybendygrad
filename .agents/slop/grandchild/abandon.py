#!/usr/bin/env python3
"""The guard's MISS, with the runaway replaced by a SLEEPER: same code path, no memory risk.

The break condition is `proc.poll() is not None and not group` -- it never looks at what the
grandchild IS, only at whether `pgrep -g` found anybody. So a 40 s sleeper reproduces the MISS
that a memory bomb produces, and it does it for the price of a fork instead of gigabytes. On a
MISS the guard also skips `os.killpg`, so the sleeper SURVIVES the guard that just reported
WITHIN-LIMITS: that is the half of the defect that matters, and here it is measured rather than
argued.

Every survivor is killed before the next trial, and the loop is ONE TRIAL AT A TIME.

    usage: .venv/bin/python .agents/slop/grandchild/abandon.py TRIALS OUT.rows
"""
import subprocess
import sys
import time
from pathlib import Path

GUARD = Path(__file__).resolve().parents[3] / "checks" / "bounded.py"
SPAWNER = "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time;time.sleep(40)'])"


def members(pgid: int) -> list[str]:
    return subprocess.run(["sh", "-c", f"ps -o pid=,pgid= -ax | awk '$2 == {pgid} {{print $1}}'"],
                          capture_output=True, text=True).stdout.split()


def kill(pids: list[str]) -> None:
    for pid in pids:
        subprocess.run(["kill", "-9", pid], capture_output=True)


def main() -> int:
    n, dest = int(sys.argv[1]), Path(sys.argv[2])
    miss = abandoned = dead = 0
    with dest.open("w") as fh:
        fh.write("# trial verdict survivors_leaked ms\n")
        for i in range(1, n + 1):
            started = time.monotonic()
            # The spawner exits immediately and the guard reports what it reports; the sleeper is
            # found by walking the group AFTER the guard is gone, which is the only way to see
            # whether the watchdog left the process it was supposed to be watching.
            p = subprocess.Popen(["/bin/sh", "-c",
                                  f"exec {sys.executable} {GUARD} --seconds 3 --mb 300 -- "
                                  f"{sys.executable} -c {SPAWNER!r}"], start_new_session=False)
            pgid = subprocess.run(["sh", "-c", f"pgrep -P {p.pid}"], capture_output=True,
                                  text=True).stdout.split()
            out, _ = p.communicate(timeout=60)
            verdict = "MISS" if p.returncode == 0 else f"rc={p.returncode}"
            leftover = members(pgid[0]) if pgid else []
            if p.returncode == 0:
                miss += 1
                abandoned += bool(leftover)
                dead += not leftover
            kill(leftover)
            ms = (time.monotonic() - started) * 1000
            fh.write(f"trial={i} verdict={verdict} survivors={len(leftover)} ms={ms:.0f}\n")
            fh.flush()
            if p.returncode == 0:
                print(f"trial {i:3d} {verdict} survivors={leftover} ms={ms:.0f}", flush=True)
    print(f"\n=== {n} trials: {miss} MISS ({miss / n:.4f}), of which {abandoned} left the "
          f"watched process RUNNING and {dead} had nothing left to watch")
    return 0


if __name__ == "__main__":
    sys.exit(main())