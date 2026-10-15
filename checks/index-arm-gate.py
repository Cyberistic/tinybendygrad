#!/usr/bin/env python3
"""index-arm-gate.py -- IS THE DEFAULT INDEX ARMED?

A commit diffs the INDEX against HEAD. So every path the index lacks is a deletion and every
path the index has and HEAD lacks is an addition. That is arithmetic, not opinion, and it is
why fourteen commits in this tree have destroyed work: an index that no longer agrees with
HEAD makes `git commit` do something nobody asked of it.

THIS GATE IS `REFUSED` (3) WHEN ARMED, NOT `FAIL` (1). An armed index is not a wrong TREE --
the tree is fine, the blobs are fine, the files are on disk. It is a wrong TOOL pointed at a
right repository, and a caller that reads `$?` needs to be able to tell those apart from "your
content is wrong".

    PASS 0   the index agrees with HEAD; a bare `git commit` carries nothing it did not stage
    REFUSED 3 the index is armed. The offending paths and the SHAPE are named on stdout
    DEAD 5   the gate could not measure (no repo, no HEAD, or an empty tree)

READ-ONLY, BY CONSTRUCTION. Every git call carries `--no-optional-locks`, which is what stops
git from refreshing (and therefore rewriting) `.git/index` as a side effect of being read. A
gate that arms the thing it is inspecting is worse than no gate.

FOUR SHAPES, ALL MEASURED, NONE GUESSED:

  DELETION   HEAD has the path, the index does not. Reproduced as a bare-commit destroyer in
             `.agents/slop/whyarms/repro2.py` R2 (`git rm --cached`) and R6 (`git add -A`
             while the file was transiently absent): R6 committed the deletion and the file was
             gone from HEAD afterwards.
  INTENT     the index carries git's empty blob `e69de29b` for a path HEAD lacks and the
             worktree has content for. `git status --porcelain=v2` calls it `N...`.
             MEASURED in isolation: `jj status` in a colocated repo writes exactly this for
             every new untracked file, and so does `jj util snapshot` -- the command the
             visualjj branching server issues on its own. 350 such paths, 7.89 MB, live at
             HEAD 05aab2165 on 2026-10-11T02:04:42Z.
  STALE      the index has the path under a different blob than HEAD does.
  UNTRACKED  the path is in the index, absent from HEAD, and NOT at the empty blob -- i.e.
             somebody else's fully staged work is sitting in the shared index waiting for
             your `git commit`.

THE INTENT SHAPE IS LATENT ON GIT 2.50.1, AND THIS GATE SAYS SO IN ITS OWN OUTPUT. Measured:
a bare `git commit` over an index holding only intent-to-add placeholders answers "no changes
added to commit" and writes nothing; `git commit -a` writes the real bytes, not the empty
ones. So INTENT is reported as armed -- it is, it is invisible to `git diff --cached` (0 of
350), and it is the residue a `git add -A` later converts into a real destruction -- but it is
not counted as an imminent loss, because claiming otherwise is the failure this gate exists to
stop.

Run:  .venv/bin/python checks/index-arm-gate.py
      .venv/bin/python checks/index-arm-gate.py --json
      .venv/bin/python checks/index-arm-gate.py --tree <path>     # another checkout
      .venv/bin/python checks/index-arm-gate.py --plant            # two states, scratch repo

The five verdicts and their exits come from `gates/gatekit.py`, imported by path -- one
definition, not a second copy. `SKIP` is deliberately not imported: this gate has no
"could not run" state distinct from DEAD.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gates"))
from gatekit import DEAD, PASS, REFUSED, VERDICT  # noqa: E402

EMPTY_BLOB = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
GIT_VERSION = "2.50.1 (Apple Git-155), measured 2026-10-11 -- on this version a bare `git commit` REFUSES intent-to-add entries"


# THE SUBJECT IS `root`'s REPOSITORY, SO THE ENVIRONMENT MUST NOT POINT ELSEWHERE. The prescribed
# commit one-liner EXPORTS `GIT_INDEX_FILE`, and git INHERITS it: MEASURED 2026-10-15, with it
# pointing at `.git/agent-index` this gate printed `PASS: the index agrees with HEAD on all 7231
# paths` while the DEFAULT index held 38 stale paths -- a PASS about a DIFFERENT FILE, which is
# the one verdict that hides the hazard this gate exists for. Scrub, never inherit.
REDIRECTS = ("GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE")
ENV = {k: v for k, v in os.environ.items() if k not in REDIRECTS}


def git(root: Path, *args: str) -> tuple[int, str, str]:
    p = subprocess.run(["git", "--no-optional-locks", *args], cwd=root,
                       capture_output=True, text=True, check=False, env=ENV)
    return p.returncode, p.stdout, p.stderr


def index_entries(root: Path) -> dict[str, tuple[str, str]]:
    """path -> (sha, stage). THE INDEX. `git ls-files --stage`."""
    rc, out, err = git(root, "ls-files", "--stage")
    if rc != 0:
        raise RuntimeError(f"ls-files rc={rc}: {err.strip()}")
    ent = {}
    for line in out.splitlines():
        meta, _, path = line.partition("\t")
        fields = meta.split()
        if len(fields) == 3:
            ent[path] = (fields[1], fields[2])
    return ent


def head_tree(root: Path, rev: str) -> dict[str, str]:
    """path -> sha. THE TREE. `git ls-tree -r <rev>`. Never the index."""
    rc, out, err = git(root, "ls-tree", "-r", rev)
    if rc != 0:
        raise RuntimeError(f"ls-tree rc={rc}: {err.strip()}")
    ent = {}
    for line in out.splitlines():
        meta, _, path = line.partition("\t")
        fields = meta.split()
        if len(fields) >= 3:
            ent[path] = fields[2]
    return ent


def census(root: Path, rev: str) -> dict:
    idx = index_entries(root)
    tree = head_tree(root, rev)
    deleted = sorted(set(tree) - set(idx))            # SHAPE D: absent from the index entirely
    intent, foreign, stale = [], [], []
    for p in sorted(set(idx) - set(tree)):            # SHAPE B / E: index has it, HEAD does not
        sha = idx[p][0]
        if sha == EMPTY_BLOB:
            intent.append(p)
        else:
            foreign.append(p)
    for p in sorted(set(idx) & set(tree)):            # SHAPE C: same path, different blob
        if idx[p][0] != tree[p]:
            stale.append(p)
    return {
        "rev": rev, "n_index": len(idx), "n_tree": len(tree),
        "DELETION": deleted, "INTENT": intent, "FOREIGN": foreign, "STALE": stale,
    }


def destructive(c: dict) -> list[str]:
    """The shapes a bare `git commit` acts on TODAY, measured, not predicted.

    MEASURED 2026-10-11, git 2.50.1, `.agents/slop/whyarms/repro2.py`:
      DELETION -> committed (R2, R6: the file was gone from HEAD afterwards)
      STALE    -> committed (it is a normal staged modification)
      INTENT   -> REFUSED by git; the commit writes nothing and says "no changes added"
      FOREIGN  -> committed (it is a normal staged addition) -- but it is someone ELSE's work
    """
    return c["DELETION"] + c["STALE"] + c["FOREIGN"]


def disk_bytes(root: Path, paths: list[str]) -> int:
    total = 0
    for p in paths:
        try:
            total += (root / p).stat().st_size
        except OSError:
            pass
    return total


def report(root: Path, rev: str | None = None) -> tuple[int, dict]:
    rc, out, err = git(root, "rev-parse", "--verify", "HEAD")
    if rc != 0:
        print(f"INDEX-ARM DEAD: no HEAD here ({root}); a gate with no tree measures nothing")
        return DEAD, {}
    rev = rev or out.strip()
    try:
        c = census(root, rev)
    except RuntimeError as e:
        print(f"INDEX-ARM DEAD: {e}")
        return DEAD, {}
    if not c["n_tree"]:
        print("INDEX-ARM DEAD: the tree has 0 paths. A census over nothing is not a clean census.")
        return DEAD, {}

    kills = destructive(c)
    n_i, n_d, n_f, n_s = (len(c["INTENT"]), len(c["DELETION"]), len(c["FOREIGN"]), len(c["STALE"]))
    print(f"INDEX-ARM HEAD {rev[:12]}  TREE {c['n_tree']}  INDEX {c['n_index']}")
    print(f"INDEX-ARM SHAPES deletion={n_d} stale={n_s} foreign-add={n_f} intent-to-add={n_i}")
    print(f"INDEX-ARM INTENT detail: {n_i} paths, {disk_bytes(root, c['INTENT'])} bytes with content "
          f"on disk; {GIT_VERSION}")

    for shape in ("DELETION", "STALE", "FOREIGN", "INTENT"):
        paths = c[shape]
        if not paths:
            continue
        shown = paths[:10]
        print(f"INDEX-ARM {shape} ({len(paths)}): " + ", ".join(shown)
              + (f", ... and {len(paths) - 10} more" if len(paths) > 10 else ""))

    if kills:
        print(f"INDEX-ARM REFUSED, NOT A VERDICT: {len(kills)} path(s) a bare `git commit` acts on "
              f"RIGHT NOW ({n_d} deletion, {n_s} stale, {n_f} foreign addition). "
              f"The tree is fine; the TOOL is pointed wrong.")
        return REFUSED, c
    if n_i:
        print(f"INDEX-ARM REFUSED, NOT A VERDICT: {n_i} intent-to-add placeholder(s) carry "
              f"{disk_bytes(root, c['INTENT'])} bytes of real work that `git diff --cached` names 0 of. "
              f"git 2.50.1 refuses to commit them, so nothing is lost YET -- and a later `git add -A` "
              f"converts every one of them into a committed empty file.")
        return REFUSED, c
    print(f"INDEX-ARM PASS: the index agrees with HEAD on all {c['n_tree']} paths. "
          f"A bare `git commit` carries nothing it did not stage.")
    return PASS, c


def plant(root: Path) -> int:
    """A control that CANNOT DISTINGUISH IS NOT A CONTROL: two states, both reachable."""
    import shutil
    import tempfile
    bad = []
    d = Path(tempfile.mkdtemp(prefix="armgate-"))
    try:
        a = d / "A"
        a.mkdir()
        for argv in (["git", "init", "-q", "-b", "master"],
                     ["git", "config", "user.email", "t@t"],
                     ["git", "config", "user.name", "t"]):
            subprocess.run(argv, cwd=a, capture_output=True, check=False, env=ENV)
        (a / "keep.rows").write_text("x\n")
        subprocess.run(["git", "add", "-A"], cwd=a, capture_output=True, check=False, env=ENV)
        subprocess.run(["git", "commit", "-q", "-m", "seed"], cwd=a, capture_output=True, check=False, env=ENV)

        b = d / "B"
        shutil.copytree(a, b)
        # ARM IT THE WAY jj DOES, with no jj present: an intent-to-add placeholder.
        (b / "fresh.rows").write_text("y" * 400)
        subprocess.run(["git", "add", "--intent-to-add", "--", "fresh.rows"],
                       cwd=b, capture_output=True, check=False, env=ENV)
        # ... and a staged deletion, the shape that actually destroys.
        subprocess.run(["git", "rm", "--cached", "-q", "--", "keep.rows"],
                       cwd=b, capture_output=True, check=False, env=ENV)

        ra, _ = report(a, None)
        rb, _ = report(b, None)
        if ra != PASS:
            bad.append(f"plant STATE A: expected PASS(0), got {VERDICT.get(ra, ra)}")
        if rb != REFUSED:
            bad.append(f"plant STATE B: expected REFUSED(3), got {VERDICT.get(rb, rb)}")
        for line in bad:
            print(f"INDEX-ARM PLANT {line}")
        if bad:
            return DEAD
        print("INDEX-ARM PLANT STATE A (clean index)  -> PASS(0)")
        print("INDEX-ARM PLANT STATE B (armed index)   -> REFUSED(3)")
        print("INDEX-ARM PLANT OK: the control distinguishes ARMED from DISARMED.")
        return PASS
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main() -> int:
    root = Path.cwd()
    args = sys.argv[1:]
    if "--plant" in args:
        return plant(root)
    rev = None
    if "--tree" in args:
        i = args.index("--tree")
        if i + 1 >= len(args):
            print("USAGE: --tree <path>", file=sys.stderr)
            return REFUSED
        root = Path(args[i + 1]).resolve()
    if root != Path.cwd():
        os.chdir(root)
    rc, c = report(root, rev)
    if "--json" in args and c:
        print("INDEX-ARM JSON " + json.dumps(
            {k: (v if not isinstance(v, list) else v[:200]) for k, v in c.items()}, indent=1))
    return rc


if __name__ == "__main__":
    sys.exit(main())
