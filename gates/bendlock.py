#!/usr/bin/env python3
"""bendlock.py -- THE BEND LOCK, in Python, for the gates that need one.

    from bendlock import bend_lock
    with bend_lock() as waited:
        subprocess.run([str(BEND), str(driver)])

WHY IT EXISTS, AND IT IS NOT A TASTE.  `AGENTS.md`'s rule is that the SUM of concurrently
running files' measured peak RSS must be under 60% of `hw.memsize` -- a rule about a SUM,
not about a COUNT.  But a machine that had 14 units running at once measured `loadavg
193.85` ON 12 CORES, and one unit's `--plant` waited **289 s** for the compiler.  So the
bend runs are SERIALISED, and a serialisation needs a lock that a DEAD PROCESS cannot
keep.

THE HAZARD THIS FIXES, MEASURED 2026-10-22: a plain `mkdir` lock was found **HELD FOR
MINUTES WITH NO COMPILER ALIVE BEHIND IT**, and every unit waited on it.  A lock whose
owner is gone must be reclaimable -- and the reclamation must NOT steal a LIVE owner's
lock, or two compilers run at once and the memory precondition is what breaks.

THE OWNER IS A PID, AND THE COMPILER IS CHECKED TOO.  The compiler is `bun`, not the
shell that invoked it, so "is the owner alive" is necessary but NOT sufficient: a shell
can be alive while its `bun` child is gone.  Hence the second check.

THE PATH IS THE ONE THE UNITS WERE TOLD TO USE, AND THAT IS DELIBERATE.  A script with a
repo-named lock and an ad-hoc `mkdir` recipe with a different path are **TWO LOCKS**, AND
TWO LOCKS DO NOT EXCLUDE EACH OTHER -- one would be held while this one was held, and
two compilers would run at once, which is the exact thing the lock is for.  **A LOCK IS
ONLY A LOCK IF EVERY FORM SHARES IT.**  `checks/bendlock.sh` is the SHELL form of this
lock and it names the SAME directory, so the two exclude each other.

AN UNOWNED LOCK IS RECLAIMED FASTER THAN A DEAD-OWNED ONE.  A lock with no `owner` file
has nobody who can prove they own it, so waiting the full stale window for it is waiting
for nothing.  A lock whose owner PID is ALIVE is NEVER reclaimed.

THE COMPILER IS `bin/bend`, NOT bare `bend`: `command -v bend` FAILS in this tree.

WHAT IT DOES NOT DO: it does not bound the child's memory.  For that, use
`checks/bounded.py --mb 2048 -- <command>` -- and READ THE VERDICT TOKEN ON ITS
`[bounded]` LINE (`WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`), NOT THE EXIT
CODE.  `AGENTS.md` records a unit that lost 425 rows by believing the status.
"""
import contextlib
import os
import subprocess
import time
from pathlib import Path

# WHERE THE LOCK LIVES.  `${TMPDIR}/opencode/bend.lock` is the path `checks/bendlock.sh`
# and the ad-hoc recipe in `AGENTS.md` both use, and the default here is the same one.
LOCK = Path(os.environ.get("TMPDIR", "/tmp")) / "opencode" / "bend.lock"
# HOW OLD A DEAD OWNER'S LOCK MAY BE BEFORE IT IS RECLAIMED, AND HOW OLD AN UNOWNED ONE
# MAY BE.  THE SAME TWO WINDOWS `checks/bendlock.sh` USES.
STALE_S = 300
UNOWNED_S = 30


def compiler_alive() -> bool:
  """IS A COMPILER ALIVE?  `bun .../main.ts` IS THE COMPILER, and a bare `bend` does
  not exist in this tree."""
  return subprocess.run(["pgrep", "-f", r"main\.ts"], capture_output=True).returncode == 0


def owner_alive(pid: int) -> bool:
  """`kill -0` ASKS THE KERNEL, so it is true for a live process and false for a dead
  one.  A PID that is not ours is still ours to test."""
  if pid <= 0:
    return False
  try:
    os.kill(pid, 0)
  except OSError:
    return False
  return True


@contextlib.contextmanager
def bend_lock():
  """HOLD THE LOCK FOR THE WHOLE COMPILER INVOCATION AND RELEASE IT IMMEDIATELY AFTER.
  YIELDS THE SECONDS SPENT WAITING, because a wait that is not reported is a wait
  nobody can see."""
  LOCK.parent.mkdir(parents=True, exist_ok=True)
  waited = 0
  while True:
    try:
      LOCK.mkdir()
      break
    except FileExistsError:
      pass
    try:
      op = int((LOCK / "owner").read_text().strip())
    except (OSError, ValueError):
      op = 0
    limit = STALE_S if op > 0 else UNOWNED_S
    try:
      age = int(time.time() - LOCK.stat().st_mtime)
    except OSError:
      age = 0
    if not owner_alive(op) and not compiler_alive() and age > limit:
      (LOCK / "owner").unlink(missing_ok=True)
      with contextlib.suppress(OSError):
        LOCK.rmdir()
      continue
    time.sleep(2)
    waited += 2
  (LOCK / "owner").write_text(str(os.getpid()))
  try:
    yield waited
  finally:
    (LOCK / "owner").unlink(missing_ok=True)
    with contextlib.suppress(OSError):
      LOCK.rmdir()
