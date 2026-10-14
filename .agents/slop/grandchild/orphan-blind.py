#!/usr/bin/env python3
"""After the group LEADER is reaped, can `pgrep -g <pgid>` still name the surviving member?

THE CONTROL IS NOT OPTIONAL. An empty `pgrep` result means nothing on its own -- it is equally
consistent with "pgrep is blind" and with "the member was never there" -- so every trial also runs
the SAME setup with the leader held open, and a trial whose control sees nothing is reported as
NOT COUNTED rather than as a disagreement.

Both readers ask for the column they filter on. The first reading of this experiment asked `ps`
for `pid=` alone and compared `$3`, so the second reader returned nothing for every pgid ever
handed it and all three of its questions came back `0` -- a `DEAD` lane wearing a clean number.

    usage: .venv/bin/python .agents/slop/grandchild/orphan-blind.py TRIALS
"""
import subprocess
import sys
import time

SPAWNER = "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time;time.sleep(40)'])"
HOLDER = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c','import time;time.sleep(40)']); time.sleep(40)"


def readers(pgid: int) -> tuple[list[str], str]:
    g = subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True).stdout.split()
    s = subprocess.run(["sh", "-c", f"ps -o pid=,pgid= -ax | awk '$2 == {pgid} {{print $1}}'"],
                       capture_output=True, text=True).stdout.split()
    return g, ",".join(s)


def kill(pgid: int) -> None:
    for pid in subprocess.run(
            ["sh", "-c", f"ps -o pid= -ax | awk '$2 == {pgid} {{print $1}}'"],
            capture_output=True, text=True).stdout.split():
        subprocess.run(["kill", "-9", pid], capture_output=True)


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    blind = counted = not_counted = 0
    for i in range(1, n + 1):
        # CONTROL: the leader is held open, so the group must be visible to both readers.
        ctl = subprocess.Popen([sys.executable, "-c", HOLDER], start_new_session=True)
        time.sleep(0.6)
        cg, cs = readers(ctl.pid)
        if not (cg and cs):
            print(f"trial {i:2d}: CONTROL FAILED pgrep_g={cg or '[]'} ps={cs or '[]'} -- NOT COUNTED")
            not_counted += 1
        else:
            counted += 1
        kill(ctl.pid)
        ctl.wait()

        # SUBJECT: the leader exits and is REAPED; the member survives.
        p = subprocess.Popen([sys.executable, "-c", SPAWNER], start_new_session=True)
        p.wait()
        time.sleep(0.6)
        g, s = readers(p.pid)
        print(f"trial {i:2d}: CONTROL pgrep_g={cg} ps={cs or '[]'} | LEADER REAPED "
              f"pgrep_g={g or '[]'} ps={s or '[]'}")
        blind += not g and bool(s)
        kill(p.pid)
    print(f"\n=== {counted} counted trials of {n} ({not_counted} controls failed): `pgrep -g` was "
          f"BLIND to a live member of a reaped leader's group in {blind}, "
          f"rate {blind / counted if counted else float('nan'):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())