#!/usr/bin/env python3
"""Three questions about `pgrep -g <pgid>`, the reader `checks/bounded.py` uses for its whole tree.

Q1  WITH THE GROUP LEADER ALIVE, does `pgrep -g` ever return NOTHING while `ps` finds a member?
Q2  AFTER THE LEADER IS KILLED AND REAPED, does `pgrep -g` still name the surviving orphan?
Q3  AT THE INSTANT THE GUARD'S BREAK CONDITION IS TRUE -- the direct child observed dead -- does
    `pgrep -g` return NOTHING while `ps -ax` walks the same pgid and finds a live member?

Q3 is the one the selftest's GRANDCHILD case depends on, and it is measured over FRESH spawns
because a fresh spawn is the only way to sample the instant the leader dies.

`ps` is the second reader, not the oracle: the point is not that pgrep is wrong, it is that the
guard takes its decision from ONE reader at ONE instant and a second reader disagrees.

    usage: .venv/bin/python .agents/slop/grandchild/three-q.py SPAWNS
"""
import subprocess
import sys
import time

SLEEPER = ["/bin/sleep", "40"]


def by_pgrep(pgid: int) -> list[str]:
    return subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True).stdout.split()


def by_ps(pgid: int) -> list[str]:
    """A DIRECTORY-WALK-EQUIVALENT of the process table: every pid whose pgid matches, from `ps`.

    IT MUST ASK FOR THE COLUMN IT FILTERS ON. The first reading of this line asked `ps` for `pid=`
    alone and compared `$3`, so this reader returned NOTHING for every pgid ever handed it and Q1
    and Q3 below reported `0 disagreements` -- which is `DEAD` wearing a clean number.
    """
    return subprocess.run(["sh", "-c", f"ps -o pid=,pgid= -ax | awk '$2 == {pgid} {{print $1}}'"],
                          capture_output=True, text=True).stdout.split()


def q1() -> tuple[int, int]:
    p = subprocess.Popen(SLEEPER, start_new_session=True)
    disagree = 0
    try:
        for _ in range(400):
            if not by_pgrep(p.pid) and by_ps(p.pid):
                disagree += 1
    finally:
        p.kill()
        p.wait()
    return disagree, 400


def q2() -> bool:
    """Leader alive -> killed and REAPED -> is the orphan still named by `pgrep -g`?"""
    leader = subprocess.Popen(["/bin/sh", "-c", "/bin/sleep 40 & exit 0"], start_new_session=True)
    time.sleep(0.5)
    pgid = leader.pid
    leader.wait()
    time.sleep(0.3)
    return bool(by_pgrep(pgid)) and bool(by_ps(pgid))


def q3(n: int) -> tuple[int, list[str]]:
    """Fresh spawns; sample the instant the guard would break. Records every disagreement."""
    spawner = "import subprocess,sys; subprocess.Popen(['/bin/sleep','40'])"
    bad, log = 0, []
    for _ in range(n):
        p = subprocess.Popen([sys.executable, "-c", spawner], start_new_session=True)
        while p.poll() is None:        # the guard's own condition: poll() before reading the group
            time.sleep(0.001)
        g, s = by_pgrep(p.pid), by_ps(p.pid)
        if not g and s:
            bad += 1
            states = subprocess.run(
                ["sh", "-c", f"ps -o pid=,ppid=,pgid=,stat=,rss=,comm= -ax | awk '$3 == {p.pid}'"],
                capture_output=True, text=True).stdout.strip().replace("\n", " | ")
            log.append(f"pgrep_g=[] ps_says=[{','.join(s)}] leader_rc={p.returncode} states={states}")
        for pid in s:
            subprocess.run(["kill", "-9", pid], capture_output=True)
    return bad, log


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    d1, t1 = q1()
    print(f"Q1 leader alive: {d1} disagreements in {t1} back-to-back reads")
    print(f"Q2 leader killed and reaped: pgrep_g={bool(by_pgrep(1)) or 'see below'} -- "
          f"orphan still named = {q2()}")
    bad, log = q3(n)
    print(f"Q3 at the guard's break instant: {bad} disagreements in {n} fresh spawns")
    for row in log[:6]:
        print("   ", row)
    return 0


if __name__ == "__main__":
    sys.exit(main())