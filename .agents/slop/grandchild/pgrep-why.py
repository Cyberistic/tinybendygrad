#!/usr/bin/env python3
"""Does `pgrep -g <pgid>` still see a grandchild after its group leader has exited?

NO MEMORY BOMB: the subject is the PROCESS VISIBILITY only, so this cannot be confused with the
ceiling. The parent is exactly the selftest case's spawner -- `subprocess.Popen` and exit -- and
the grandchild is a 30 s sleeper, which cannot be mistaken for a bomb.

Three questions, answered by measurement rather than by reading:

  1. DOES THE PARENT EXIT AT ONCE, OR BLOCK IN `subprocess._cleanup`?  CPython registers an
     `atexit` hook that `waitpid`s every live `Popen`, so a `-c` program that spawns and exits may
     wait for its child forever. If it does, the group is never empty and the guard is safe.
  2. AT THE INSTANT `pgrep -g <pgid>` RETURNS NOTHING, WHAT DOES THE PROCESS TABLE SAY?  The
     grandchild's real pgid, ppid and state, from `ps`, which is the other reader of the same fact.
  3. IS THE DIRECT CHILD STILL ALIVE AT THAT INSTANT?  The guard's break needs BOTH: the child
     gone AND the group empty.

One row per poll: `t_ms spawner_alive grandchild_alive pgrep_g pgrep_p ps_row`.
"""
import os
import subprocess
import sys
import time

GRAND = "import time\ntime.sleep(30)\n"
SPAWNER = "import subprocess,sys; subprocess.Popen([sys.executable, '-c', %r])" % GRAND


def table(psids: list[int]) -> str:
    out = subprocess.run(["ps", "-o", "pid=,ppid=,pgid=,stat=,rss=", "-p", ",".join(map(str, psids))],
                         capture_output=True, text=True).stdout.strip()
    return " | ".join(out.splitlines())


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    for run in range(1, n + 1):
        p = subprocess.Popen([sys.executable, "-c", SPAWNER], start_new_session=True)
        pgid = p.pid
        seen_empty_at, parent_alive_at_empty = None, None
        t0, rows = time.monotonic(), []
        while time.monotonic() - t0 < 3.0:
            t_ms = (time.monotonic() - t0) * 1000
            g = subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True).stdout.split()
            gc = subprocess.run(["pgrep", "-P", str(pgid)], capture_output=True, text=True).stdout.split()
            alive = p.poll() is None
            if not g and not alive and seen_empty_at is None:
                seen_empty_at = t_ms
                parent_alive_at_empty = alive
                by_walk = subprocess.run(
                    ["sh", "-c", f"ps -o pid=,ppid=,pgid=,stat=,comm= -ax | awk '$3=={pgid}'"],
                    capture_output=True, text=True).stdout.strip() or "(none)"
                rows.append(f"t_ms={t_ms:.0f} spawner_alive={alive} pgrep_g=[] "
                            f"ps[{pgid}]={table([pgid]) or 'GONE'}  ps-ax-walk-in-pgid={by_walk}")
                break
            rows.append(f"t_ms={t_ms:.0f} spawner_alive={alive} pgrep_g={g or '[]'} pgrep_P={gc or '[]'}")
            time.sleep(0.02)
        print(f"--- run {run} pgid={pgid} empty_group_first_seen_at_ms="
              f"{seen_empty_at if seen_empty_at is not None else 'never'}")
        for r in rows[-6:]:
            print("   ", r)
        for pid in subprocess.run(["sh", "-c", f"pgrep -g {pgid}"], capture_output=True,
                                  text=True).stdout.split():
            subprocess.run(["kill", "-9", pid], capture_output=True)
        if p.poll() is None:
            p.kill()
        p.wait()
    return 0


if __name__ == "__main__":
    sys.exit(main())