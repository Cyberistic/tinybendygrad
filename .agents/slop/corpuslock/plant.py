#!/usr/bin/env python3
"""THE PLANT: two corpus runs, and the second one is REFUSED.

    .venv/bin/python .agents/slop/corpuslock/plant.py

WHAT IT PROVES, AND WHAT IT COSTS.

  1. A REAL corpus run (`checks/differ.py run`) starts and TAKES THE LOCK.
  2. A SECOND real corpus run, started while the first is running, is REFUSED: exit 3, the
     message says "another corpus run holds the lock" and NAMES THE HOLDER (its pid).
  3. The SECOND run wrote NOTHING: the first run's artifacts are byte-identical before and
     after the second run's refusal.
  4. The TREE's evidence (`runs/graphcmp/D/`) is byte-identical before and after the plant.

THE ARTEFACT DIRECTORY IS REDIRECTED (`GRAPHCMP_ARTIFACTS`) so the plant cannot destroy the
tree's 319 files of evidence, and so a broken lock would damage a scratch directory instead
of the corpus.  The first run is killed as soon as the second one has been refused: the plant
is about the LOCK, not about a green run, and a corpus run takes 271 s.

NOTHING IS LEFT BEHIND: the scratch directory and the lock are removed, and the process group
of the first run is killed so no `bend` child outlives it.
"""
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRATCH = ROOT / "runs" / "graphcmp" / f".plant-{os.getpid()}"
LOCK = ROOT / "runs" / "graphcmp" / ".corpus.lock"
LIVE = ROOT / "runs" / "graphcmp" / "D"


def digest(root: Path) -> str:
    """A CONTENT digest of a directory: `(relpath, sha256)` for every file, sorted."""
    h = hashlib.sha256()
    for p in sorted(q for q in root.rglob("*") if q.is_file()):
        h.update(str(p.relative_to(root)).encode())
        h.update(b"\0")
        h.update(hashlib.sha256(p.read_bytes()).hexdigest().encode())
        h.update(b"\0")
    return h.hexdigest()


def lock_holder() -> tuple[int, float]:
    try:
        pid_s, epoch_s = LOCK.read_text().split()
        return int(pid_s), time.time() - float(epoch_s)
    except (OSError, ValueError):
        return (0, 0.0)


def main() -> int:
    env = dict(os.environ, GRAPHCMP_ARTIFACTS=str(SCRATCH))
    live_before = digest(LIVE)
    SCRATCH.mkdir(parents=True, exist_ok=True)

    first = subprocess.Popen([sys.executable, str(ROOT / "checks/differ.py"), "run"],
                             cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, start_new_session=True)
    print(f"# first run: pid {first.pid}, artefacts -> {SCRATCH.relative_to(ROOT)}")

    deadline = time.time() + 60
    holder = (0, 0.0)
    while time.time() < deadline:
        holder = lock_holder()
        if holder[0] == first.pid:
            break
        if first.poll() is not None:
            print(f"# first run EXITED EARLY rc={first.returncode}")
            print(first.stdout.read()[-2000:])
            shutil.rmtree(SCRATCH, ignore_errors=True)
            return 1
        time.sleep(0.2)
    print(f"# the first run holds the lock: pid {holder[0]} (held for {holder[1]:.1f}s)")
    if holder[0] != first.pid:
        print("# PLANT REFUSED: the first run never took the lock")
        os.killpg(first.pid, signal.SIGTERM)
        shutil.rmtree(SCRATCH, ignore_errors=True)
        return 1

    # WAIT FOR THE FIRST ARTIFACT, so "the second run wrote nothing" has SOMETHING to be
    # true about.  Bounded: a corpus run that has not written anything in 90 s is a fact
    # about the plant, not a licence to wait longer.
    deadline = time.time() + 90
    while time.time() < deadline and not any(SCRATCH.iterdir()):
        time.sleep(0.3)
    before = sorted(p.name for p in SCRATCH.iterdir())
    before_digest = digest(SCRATCH) if before else ""
    print(f"# the first run has written {len(before)} artefact(s): {before[:4]}")

    second = subprocess.run([sys.executable, str(ROOT / "checks/differ.py"), "run"],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    after = sorted(p.name for p in SCRATCH.iterdir())
    after_digest = digest(SCRATCH) if after else ""
    print(f"# second run: rc={second.returncode}")
    print((second.stdout + second.stderr).rstrip())
    print(f"# artefacts after the second run: {len(after)} -> {after[:4]}")
    print(f"# artefacts byte-identical across the refusal: {before_digest == after_digest}")

    os.killpg(first.pid, signal.SIGTERM)
    try:
        first.wait(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(first.pid, signal.SIGKILL)
        first.wait(timeout=30)
    print(f"# first run killed (rc={first.returncode})")

    live_after = digest(LIVE)
    print(f"# the tree's evidence byte-identical across the plant: {live_before == live_after}")
    shutil.rmtree(SCRATCH, ignore_errors=True)
    print(f"# scratch removed: {not SCRATCH.exists()}")

    ok = (second.returncode == 3
          and "another corpus run holds the lock" in (second.stdout + second.stderr)
          and str(first.pid) in (second.stdout + second.stderr)
          and before_digest == after_digest
          and live_before == live_after)
    print(f"# PLANT {'PASSED' if ok else 'FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
