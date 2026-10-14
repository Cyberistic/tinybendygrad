#!/usr/bin/env python3
"""Per-poll timestamps for the guard's TWO reads, and a second reader at each read.

The guard's loop takes two independent snapshots per iteration and conjoins them:

    now, group = group_rss(pgid)          # READ A: `pgrep -g <pgid>`
    ...
    if proc.poll() is not None and not group:   # READ B: has the DIRECT child exited?

READ A is older than READ B by whatever A costs plus the spawner's own startup, and the spawner is
precisely the thing that creates the grandchild. So `not group` can be true of an instant BEFORE
the grandchild exists, while `poll()` is true of a LATER instant after it does -- and the
conjunction is asserted at B. This harness measures that gap instead of assuming it, and puts a
SECOND reader (`ps`, asking for the column it filters on) beside `pgrep` on every read.

    usage: .venv/bin/python .agents/slop/grandchild/clocked.py TRIALS OUT.rows
"""
import importlib.util
import subprocess
import sys
import tempfile
import time
from pathlib import Path

GUARD = Path(__file__).resolve().parents[3] / "checks" / "bounded.py"
BOMB = "a=[]\nwhile 1: a.append(b'x'*10000000)\n"
SPAWNER = "import subprocess,sys; subprocess.Popen([sys.executable, sys.argv[1]])"
SLEEPER = "import time\ntime.sleep(40)\n"


def by_ps(pgid: int) -> list[str]:
    return subprocess.run(["sh", "-c", f"ps -o pid=,pgid= -ax | awk '$2 == {pgid} {{print $1}}'"],
                          capture_output=True, text=True).stdout.split()


def main() -> int:
    n, dest = int(sys.argv[1]), Path(sys.argv[2])
    bomb = Path(tempfile.gettempdir()) / "bounded-grandchild.py"
    bomb.write_text(BOMB)
    grand = str(bomb)
    spec = importlib.util.spec_from_file_location("guarded", GUARD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    real_group_rss, polls = mod.group_rss, []
    t0 = [0.0]

    def clocked(pgid: int):
        a0 = time.monotonic() - t0[0]
        rows = real_group_rss(pgid)
        a1 = time.monotonic() - t0[0]
        b = time.monotonic() - t0[0]
        polls.append({"a0": a0, "a1": a1, "b": b, "pgrep": rows[1], "ps": by_ps(pgid),
                      "rss": rows[0]})
        return rows

    class Popen(mod.subprocess.Popen):
        def poll(self, *a):
            out = super().poll(*a)
            if polls and polls[-1].get("poll") is None:
                polls[-1]["poll"] = time.monotonic() - t0[0]
                polls[-1]["dead"] = out is not None
            return out

    mod.group_rss = clocked
    mod.subprocess.Popen = Popen
    misses = 0
    with dest.open("w") as fh:
        for i in range(1, n + 1):
            polls.clear()
            t0[0] = time.monotonic()
            sys.argv = ["bounded.py", "--seconds", "120", "--mb", "300", "--", sys.executable,
                        "-c", SPAWNER, grand]
            rc = mod.main()
            _, err = sys.stderr, None
            if rc == 0:
                misses += 1
                for k, row in enumerate(polls):
                    print(f"run {i} MISS poll {k}: readA [{row['a0'] * 1000:.0f}..{row['a1'] * 1000:.0f}]ms "
                          f"pgrep={row['pgrep'] or '[]'} ps={row['ps'] or '[]'} "
                          f"readB(poll)={row.get('poll', float('nan')) * 1000:.0f}ms "
                          f"dead={row.get('dead')}")
            for row in polls:
                fh.write(f"run={i} rc={rc} a0={row['a0'] * 1000:.0f} a1={row['a1'] * 1000:.0f} "
                         f"b={row.get('poll', -1) * 1000:.0f} dead={row.get('dead')} "
                         f"pgrep={row['pgrep']} ps={row['ps']} rss={row['rss']:.0f}\n")
            fh.flush()
    bomb.unlink(missing_ok=True)
    print(f"\n=== {n} runs, {misses} MISS ({misses / n:.4f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())