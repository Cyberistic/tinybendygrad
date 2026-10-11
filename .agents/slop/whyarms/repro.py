#!/usr/bin/env python3
"""repro.py -- the causal chain, isolated, one fresh colocated repo per scenario.

Never touches the real repository's index: every scenario runs in its own
mkdtemp.  Each row prints a BEFORE and an AFTER, because a shape that cannot
print both is a shape that cannot distinguish.

The jj config supplied here is copied verbatim from the REAL repo's per-repo
config, which lives at
  ~/.config/jj/repos/1013720a994d3c872163/config.toml
-- i.e. OUTSIDE the repository, keyed by a hash of the repo path.  It is not in
git, not in .jj, not in .git/config.

Scenarios (each on a fresh `git init` + `jj git init --colocate`):
  A  jj status with NO changes         -- does jj write the index when idle?
  B  create file, jj status            -- does a plain READ command write it?
  C  delete tracked file, jj status    -- does jj stage the deletion into GIT's index?
  D  file COMES BACK on disk           -- does the staged deletion PERSIST (the shape
                                          this session found: staged-D, file on disk)?
  E  bare `git commit` on that index   -- does the phantom deletion actually COMMIT?
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

JJ = shutil.which("jj")
CONFIG = """\
[revset-aliases]
"trunk()" = "master@origin"

[ui]
conflict-marker-style = "git"

[snapshot]
auto-update-stale = true
max-new-file-size = 3000000

[visualjj]
snapshot-workspaces = true
"""


def run(cwd, *args):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)


def state(cwd) -> dict:
    idx = Path(cwd) / ".git" / "index"
    ls = run(cwd, "git", "--no-optional-locks", "ls-files", "--stage").stdout
    return {
        "n_index": len(ls.splitlines()),
        "n_tree": len(run(cwd, "git", "--no-optional-locks", "ls-tree", "-r", "HEAD", "--name-only").stdout.splitlines()),
        "staged_D": run(cwd, "git", "--no-optional-locks", "diff", "--cached", "--name-only",
                        "--diff-filter=D", "HEAD").stdout.split(),
        "empty_blobs": sum(1 for ln in ls.splitlines() if ln.startswith("0" * 40)),
        "index_mtime": int(idx.stat().st_mtime) if idx.exists() else -1,
    }


def fmt(tag, s):
    return (f"{tag:36s} nidx={s['n_index']:3d} ntree={s['n_tree']:3d} "
            f"stagedD={len(s['staged_D']):2d} empty={s['empty_blobs']:2d} "
            f"mtime={s['index_mtime']} {s['staged_D']}")


def fresh(d: Path, cfgdir: str, name: str) -> Path:
    r = d / name
    r.mkdir()
    env = {**os.environ, "JJ_CONFIG": cfgdir}
    run(r, "git", "init", "-q", "-b", "master")
    run(r, "git", "config", "user.email", "t@t")
    run(r, "git", "config", "user.name", "t")
    (r / "a.rows").write_text("keep\n")
    run(r, "git", "add", "-A")
    run(r, "git", "commit", "-q", "-m", "seed")
    p = subprocess.run([JJ, "git", "init", "--colocate", "."], cwd=r, env=env,
                       capture_output=True, text=True, check=False)
    if p.returncode != 0:
        raise SystemExit(f"jj init failed in {r}: {p.stderr}")
    return r


def main() -> int:
    if not JJ:
        print("DEAD: no jj on PATH")
        return 5
    d = Path(tempfile.mkdtemp(prefix="whyarms-"))
    cfg = d / "cfg"
    cfg.mkdir()
    (cfg / "config.toml").write_text(CONFIG)
    env = {**os.environ, "JJ_CONFIG": str(cfg)}
    print(f"REPRO root={d}")
    got = subprocess.run([JJ, "config", "get", "snapshot.auto-update-stale"],
                         cwd=d, env=env, capture_output=True, text=True).stdout.strip()
    print(f"CONFIG auto-update-stale={got}")
    try:
        # ---- A: idle ----
        a = fresh(d, str(cfg), "A")
        print(fmt("A0 before", state(a)))
        run(a, JJ, "status")
        print(fmt("A1 after 'jj status' (idle)", state(a)))

        # ---- B: a file appears ----
        b = fresh(d, str(cfg), "B")
        (b / "b.rows").write_text("new\n")
        print(fmt("B0 before", state(b)))
        run(b, JJ, "status")
        print(fmt("B1 after 'jj status' (1 new file)", state(b)))

        # ---- C: a tracked file is deleted ----
        c = fresh(d, str(cfg), "C")
        (c / "a.rows").unlink()
        print(fmt("C0 before", state(c)))
        run(c, JJ, "status")
        print(fmt("C1 after 'jj status' (file deleted)", state(c)))

        # ---- D: the file comes BACK, and jj is never re-run ----
        e = fresh(d, str(cfg), "D")
        (e / "a.rows").unlink()
        run(e, JJ, "status")                        # jj view: a.rows absent
        print(fmt("D1 jj believes a.rows deleted", state(e)))
        (e / "a.rows").write_text("keep\n")         # restored on disk
        print(fmt("D2 restored on disk, NO jj run", state(e)))
        print(f"{'D3 a.rows on disk right now?':36s} {(e / 'a.rows').exists()}")
        print(f"{'D3 a.rows in HEAD right now?':36s} "
              f"{'a.rows' in run(e, 'git', '--no-optional-locks', 'ls-tree', '-r', 'HEAD', '--name-only').stdout.split()}")
        # ---- E: bare git commit, exactly what a unit types ----
        run(e, "git", "commit", "-q", "-m", "unit commit, bare")
        tree = run(e, "git", "--no-optional-locks", "ls-tree", "-r", "HEAD", "--name-only").stdout.split()
        print(fmt("E1 after BARE git commit", state(e)))
        print(f"{'E2 a.rows survives in HEAD?':36s} {'a.rows' in tree}   tree={sorted(tree)}")
        ok = "a.rows" in tree
        print(f"VERDICT bare-git-commit-on-a-jj-written-index: {'SURVIVED (chain not reproduced)' if ok else 'DESTROYED (chain reproduced)'}")
        return 0 if ok else 1
    finally:
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
