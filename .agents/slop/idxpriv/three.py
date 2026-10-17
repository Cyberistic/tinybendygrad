#!/usr/bin/env python3
"""three.py -- THE PROOF, IN THIS TREE, ON THROWAWAY PATHS, WITH THREE PRIVATE INDEXES.

Three committers, three DISTINCT GIT_INDEX_FILE paths, three DISTINCT paths named, released on one
barrier, each committing exactly one path with `--only`. Then `git show --stat` on all three.

EACH PRIVATE INDEX IS DELIBERATELY CONTAMINATED FIRST, with 300 of HEAD's OWN paths staged
UNCHANGED. An uncontaminated index cannot prove isolation -- it is empty, and an empty index carries
nothing for any reason. Staging unchanged blobs means that IF a path leaked into a commit the diff
would be a no-op, so the worst case of this proof is harmless to real work.

THE SHARED-INDEX ARM IS NOT RUN HERE, AND THAT IS THE POINT: running it in this tree is the event
this change exists to prevent. Its evidence is route.py's ISOLATED arm, in a throwaway repo.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SLOP = Path(".agents/slop/idxpriv")
STAGE = 300

UNIT = """\
while [ ! -f "{bar}.{k}" ]; do sleep 0.02; done
tries=0
while :; do
  tries=$((tries+1))
  err=$({{ git add -- {path} && git commit --only -q -F "{root}/{SLOP}/msg{k}.rows" -- {path}; }} 2>&1) && {{
    git rev-parse HEAD > "{root}/.idxpriv.sha{k}"; exit 0; }}
  [ "$tries" -ge 20 ] && {{ printf '%s\\n' "$err" > "{root}/.idxpriv.err{k}"; exit 1; }}
  sleep 0.05
done
"""


def git(*args, env=None):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True,
                          env=env, check=False)


def main() -> int:
    # A RUN NONCE. Without it the second run of this harness commits nothing, because the paths it
    # names were committed by the first run and git answers "no changes added to commit" -- which
    # the harness then reported as three failures. A probe that cannot tell "nothing to commit"
    # from "failed to commit" is a probe with two failure modes and one exit.
    run = str(int(ROOT.stat().st_mtime) % 100000)
    for k in range(3):
        idx = str(ROOT / ".git" / f"agent-index-idxpriv-{k}")
        env = dict(os.environ, GIT_INDEX_FILE=idx)
        # Contaminate: stage HEAD's own paths, unchanged, so a leak would be a no-op diff.
        victim = git("ls-tree", "-r", "--name-only", "HEAD").stdout.split()[100:100 + STAGE]
        (ROOT / f".idxpriv.victim{k}").write_text("\n".join(victim) + "\n")
        r = subprocess.run(["git", "-C", str(ROOT), "add", "--pathspec-from-file",
                            f".idxpriv.victim{k}"], capture_output=True, text=True, env=env)
        staged = len(git("diff", "--cached", "--name-only", env=env).stdout.split())
        path = f"{SLOP}/p{k}.rows"
        (ROOT / path).write_text(f"unit {k} wrote exactly this one path, run {run}\n")
        (ROOT / f"{SLOP}/msg{k}.rows").write_text(
            f"idxpriv: unit {k} commits ONE path through PRIVATE index "
            f"`{os.path.basename(idx)}`\n\n"
            f"MEASURED: that private index was contaminated with {staged} of HEAD's own paths "
            f"(UNCHANGED blobs, so a leak would be a no-op diff) before this commit.\n"
            f"`git show --stat` on this commit is the check, and it is the check that never ran\n"
            f"in the session's one destructive commit.\n")
        print(f"unit{k}: index={os.path.basename(idx)} contaminated-with={staged} paths "
              f"(git add rc={r.returncode})")
    procs = []
    for k in range(3):
        env = dict(os.environ, GIT_INDEX_FILE=str(ROOT / ".git" / f"agent-index-idxpriv-{k}"))
        sh = ROOT / f".idxpriv.unit{k}.sh"
        sh.write_text(UNIT.format(bar=str(ROOT / ".idxpriv.bar"), k=k,
                                  path=f"{SLOP}/p{k}.rows", root=ROOT, SLOP=SLOP))
        procs.append(subprocess.Popen(["sh", str(sh)], cwd=ROOT, env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    for k in range(3):
        (ROOT / f".idxpriv.bar.{k}").write_text("go")
    rc = 0
    for k, pr in enumerate(procs):
        # JOIN THE CHILD. The first version of this harness Popen'd and never waited, so it
        # reported "NO COMMIT" for three units that were still running and retrying -- a gate that
        # measured nothing and called it failure. That is the DEAD state in doctrine 2.
        prc = pr.wait()
        sha_f = ROOT / f".idxpriv.sha{k}"
        err_f = ROOT / f".idxpriv.err{k}"
        if prc or not sha_f.exists():
            first = err_f.read_text().strip().splitlines()[-1] if err_f.exists() else "?"
            print(f"unit{k}: rc={prc} NO COMMIT -- {first}")
            rc = 1
            continue
        sha = sha_f.read_text().strip()
        stat = git("show", "--stat", "--format=", sha).stdout
        # COUNT THE SUMMARY LINE, NOT THE LINES. The first version counted non-blank `--stat`
        # lines, which counts the trailing "1 file changed, ..." summary TOO, so every correct
        # one-path commit read as a 2-path SWEEP. A verdict computed from a shape the tool did not
        # print is a false positive, and three of them at once.
        n = 0
        for line in stat.splitlines():
            m = re.search(r"(\d+) files? changed", line)
            if m:
                n = int(m.group(1))
        subj = git("log", "-1", "--format=%s", sha).stdout.strip()
        print(f"\n--- unit{k} {sha[:12]} ---")
        print(git("show", "--stat", "--format=%h %s", sha).stdout.rstrip())
        ok = n == 1
        rc |= 0 if ok else 1
        print(f"    VERDICT unit{k}: summary line says {n} file(s) changed -> "
              f"{'ONE PATH, CORRECT' if ok else '*** SWEEP ***'}")
    print(f"\nTHREE CONCURRENT COMMITS, THREE PRIVATE INDEXES: "
          f"{'ALL THREE CARRIED EXACTLY ONE PATH' if rc == 0 else 'FAILED'}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
