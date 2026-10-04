#!/usr/bin/env python3
"""Run a command under BOTH a time bound and a memory bound, and say which one fired.

    usage: checks/bounded.py [--seconds N] [--mb N] -- <command> [args ...]
    exit  0  ran to completion, within both bounds
          3  KILLED ON MEMORY -- peak RSS reached the ceiling
          4  TIMED OUT
          5  the command could not be started

WHY THIS EXISTS, AND IT IS NOT HYPOTHETICAL.  2026-10-05, twice in one afternoon, two
`references/bend/bend2/main.ts` processes consumed all system memory and crashed the machine:
swap went to 1.6 of 2.0 GB and free pages to ~19 MB. The project's own timeout idiom is
`perl -e 'alarm N; exec @ARGV'` and **it appears in `agent-core.md`, in every unit's brief, and in
every gate -- and `ulimit` appears ZERO times in `agent-core.md`, `substrate-check.sh` and
`e2e.sh` combined.** An alarm bounds TIME. A compiler that allocates without bound is killed by
neither an alarm nor a reviewer watching a load average.

WHY A WATCHDOG AND NOT `ulimit -v`.  `ulimit -v` is unreliable on macOS -- it exists in the shell
but address-space limits are not consistently enforced -- and `RLIMIT_AS` from Python is subject
to the same kernel behaviour. **A GUARD THAT DOES NOT ENFORCE ON THE PLATFORM IT IS WRITTEN FOR
IS A COMMENT**, which is the same defect this project has now catalogued seventeen of. So the
bound is enforced by the only mechanism that cannot be ignored: watch the child's RSS and kill it.

WHY IT PRINTS THE PEAK.  A guard that reports only "killed" leaves the next reader with no number,
and a kill with no number is indistinguishable from a hang. **THE PEAK IS THE FACT.**

DISTINGUISHING THE TWO BOUNDS IS THE POINT.  The project's alarm exits 142 (128+SIGALRM), and a
kill exits 137 (128+SIGKILL) -- **and 142 has been read in this project as "the run failed" when it
means "my own alarm killed it, so it proves nothing."** A caller must be able to tell a slow build
from a hungry one, because the fixes are unrelated.
"""
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time

# 4 GB. This machine has 8-ish; a build that wants more than this is a build with a term that
# did not terminate, not a build that needs the memory. Adjust per machine, never upward to
# accommodate one failure -- that is how the ceiling stops being a ceiling.
DEFAULT_MB = 4096
DEFAULT_SECONDS = 900
POLL = 0.25


def rss_mb(pid: int) -> float:
    """Resident size of one pid, in MB. `ps` rather than a library: no external dependencies."""
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return int(out) / 1024 if out else 0.0
    except Exception:
        return 0.0


def tree_rss_mb(pid: int) -> float:
    """RSS of the child AND its descendants.

    MEASURED, and this is not a refinement: the runaway was `bun references/bend/bend2/main.ts`,
    i.e. the child *spawned* the thing that ate the machine. Watching only the direct child
    reports a few MB while the machine dies. `pgrep -P` finds children; the loop is bounded so a
    process tree that forks faster than it is walked cannot hang the guard itself.
    """
    total, frontier, seen = 0.0, [pid], set()
    while frontier and len(seen) < 4096:
        cur = frontier.pop()
        if cur in seen:
            continue
        seen.add(cur)
        total += rss_mb(cur)
        try:
            kids = subprocess.run(["pgrep", "-P", str(cur)],
                                  capture_output=True, text=True, timeout=5).stdout.split()
        except Exception:
            kids = []
        frontier.extend(int(k) for k in kids)
    return total


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=int, default=DEFAULT_SECONDS)
    ap.add_argument("--mb", type=int, default=DEFAULT_MB)
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        print("usage: checks/bounded.py [--seconds N] [--mb N] -- <command> [args ...]",
              file=sys.stderr)
        return 5

    ceiling = float(args.mb)
    started = time.monotonic()
    peak = 0.0
    # Its own process group, so a kill reaches a grandchild. `start_new_session` detaches it
    # from ours, which also means a Ctrl-C here does not race the watchdog.
    proc = subprocess.Popen(cmd, start_new_session=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    verdict = "WITHIN-LIMITS"
    while True:
        rc = proc.poll()
        if rc is not None:
            break
        now_rss = tree_rss_mb(proc.pid)
        peak = max(peak, now_rss)
        if now_rss >= ceiling:
            verdict = "KILLED-ON-MEMORY"
            break
        if time.monotonic() - started > args.seconds:
            verdict = "TIMED-OUT"
            break
        time.sleep(POLL)

    if verdict != "WITHIN-LIMITS":
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            proc.kill()
        try:
            out = proc.communicate(timeout=10)[0]
        except Exception:
            out = ""
        rc = proc.returncode
    else:
        out = proc.communicate()[0]
        rc = proc.returncode

    if out:
        sys.stdout.write(out)
        if not out.endswith("\n"):
            sys.stdout.write("\n")
    elapsed = time.monotonic() - started
    print(f"[bounded] {verdict}  rc={rc}  peak-RSS={peak:.0f} MB (ceiling {ceiling:.0f})  "
          f"{elapsed:.0f}s  :: {' '.join(cmd[:3])}")

    if verdict == "KILLED-ON-MEMORY":
        print("[bounded] THIS IS NOT A TIMEOUT. rc=137 is SIGKILL, so it looks like the "
              "project's alarm (rc=142) but is not: the term being built did not terminate. "
              "Look for Peano `Nat` arithmetic near its 2^48-1 ceiling, or a plant that made a "
              "multiplier symbolic.")
        return 3
    if verdict == "TIMED-OUT":
        print("[bounded] rc=142 would be SIGALRM; here the watchdog sent SIGKILL. Either way THIS "
              "RUN PROVES NOTHING -- it was killed, it did not fail.")
        return 4
    return rc if rc else 0


if __name__ == "__main__":
    sys.exit(main())