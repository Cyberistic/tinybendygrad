#!/usr/bin/env python3
"""race.py -- CAN A SHARED INDEX SWEEP A `git commit --only`?  A CONTROL THAT CANNOT FAIL IS NOT A CONTROL.

Runs N trials of K concurrent committers, each naming ONE DISTINCT path, in a THROWAWAY repo under
a temp dir. Two arms, identical except for how the index path is chosen:

  shared   K committers, ONE GIT_INDEX_FILE path        -- what AGENTS.md prescribes today
  private  K committers, K DISTINCT GIT_INDEX_FILE paths -- what this change prescribes

A trial FAILS when any commit's `--stat` names other than its own single path. The arm's score is
its failure count, so a fix that cannot fail is a claim rather than a measurement.

TWO THINGS THIS HARNESS GOT WRONG FIRST, KEPT HERE BECAUSE BOTH ARE INSTRUMENT CLASSES, NOT BUGS:

  1. IT SCORED `git log -n K` INSTEAD OF THE UNITS' OWN SHAs. A unit that loses a ref race commits
     nothing, so the window slides back over the 1500-path SEED commit and the harness reported a
     sweep in an arm that had none. **A VERDICT ABOUT A POPULATION YOU DID NOT NAME.**
  2. IT CALLED EVERY rc=128 THE SAME THING. They are different locks: `agent-index.lock` is the
     shared INDEX, `cannot lock ref HEAD` is the REF, and they do not appear in the same arm.
     "3 of 3 trials failed" cannot tell a contended index from a contended branch.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

K = 3  # concurrent committers
NFILES = 1500  # committed paths, so a sweep is a COUNT rather than a guess

UNIT = """\
while [ ! -f "{gate}.{k}" ]; do sleep 0.02; done
tries=0
while :; do
  tries=$((tries+1))
  err=$({{ git add -- {path} && git commit --only -q -m "unit {path}" -- {path}; }} 2>&1) && {{
    git rev-parse HEAD > "{root}/.sha{k}"; echo "$tries" > "{root}/.tries{k}"; exit 0; }}
  [ "$tries" -ge 20 ] && {{ printf '%s\\n' "$err" > "{root}/.err{k}"; exit 1; }}
  sleep 0.05
done
"""


def git(root, *args, env=None, check=True):
    p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True,
                       env=env, check=False)
    if check and p.returncode:
        raise RuntimeError(f"git {' '.join(args)} rc={p.returncode}: {p.stderr.strip()}")
    return p


def seed(root: Path, n: int) -> None:
    """n committed files in one commit, so HEAD is real and the index is full."""
    git(root, "init", "-q", "-b", "main")
    git(root, "config", "user.email", "r@x")
    git(root, "config", "user.name", "r")
    bulk = root / "bulk"
    bulk.mkdir()
    for i in range(n):
        (bulk / f"f{i:05d}.rows").write_text(f"seed {i}\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "seed")


def trial(root: Path, arm: str, tag: str) -> tuple[list[str], int]:
    """K committers released by a common barrier. Returns (defects, total ref-race retries)."""
    paths = [f"u{tag}_{k}.rows" for k in range(K)]
    for p in paths:
        (root / p).write_text(f"unit {tag} wrote {p}\n")
    envs = [dict(os.environ, GIT_INDEX_FILE=str(root / ".git" / (
        "agent-index" if arm == "shared" else f"agent-index-u{tag}-{k}")))
        for k in range(K)]
    procs = []
    for k, (p, env) in enumerate(zip(paths, envs)):
        sh = root / f".unit{k}.sh"
        sh.write_text(UNIT.format(gate=root / ".gate", k=k, path=p, root=root))
        procs.append(subprocess.Popen(["sh", str(sh)], cwd=root, env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True))
    for k in range(K):  # release the barrier only once every committer is parked on it
        (root / f".gate.{k}").write_text("go")
    defects, retries = [], 0
    for k, pr in enumerate(procs):
        _, err = pr.communicate()
        er = (root / f".err{k}").read_text().strip() if (root / f".err{k}").exists() else ""
        tr = (root / f".tries{k}").read_text().strip() if (root / f".tries{k}").exists() else "0"
        retries += int(tr or 1) - 1
        if pr.returncode:
            lock = ("INDEX-LOCK" if "agent-index.lock" in er else
                    "REF-LOCK" if "lock ref" in er else "OTHER")
            defects.append(f"unit{k} rc={pr.returncode} {lock}: {er.splitlines()[0] if er else err.strip()}")
            continue
        sha = (root / f".sha{k}").read_text().strip()
        n = len(git(root, "show", "--numstat", "--format=", sha).stdout.strip().splitlines())
        if n != 1:
            defects.append(f"SWEEP {sha[:12]} carried {n} paths, not 1")
    return defects, retries


def arm_run(arm: str, trials: int) -> None:
    sweeps = lockcoll = other = retries = 0
    detail = []
    for t in range(trials):
        d = Path(tempfile.mkdtemp(prefix=f"idxrace-{arm}-"))
        try:
            seed(d, NFILES)
            defects, r = trial(d, arm, f"{t}")
            retries += r
            for x in defects:
                if x.startswith("SWEEP"):
                    sweeps += 1
                elif "INDEX-LOCK" in x:
                    lockcoll += 1
                elif "REF-LOCK" in x:
                    other += 1  # a lost ref race is retried; it is not a sweep
                else:
                    other += 1
                detail.append(f"trial {t}: {x}")
        finally:
            shutil.rmtree(d, ignore_errors=True)
    print(f"ARM {arm}: SWEEP={sweeps} INDEX-LOCK={lockcoll} OTHER={other} "
          f"ref-retries={retries} over {trials} trials")
    for line in detail[:4]:
        print(f"    {line}")


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    for arm in ("shared", "private"):
        arm_run(arm, n)
