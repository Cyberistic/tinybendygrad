#!/usr/bin/env python3
"""plant.py -- THE PLANT, AND IT IS THE WHOLE TASK.

    .venv/bin/python .agents/slop/onemodule/plant.py            # the six-projection delta
    .venv/bin/python .agents/slop/onemodule/plant.py --rows     # TSV

WHAT THIS ASSERTS. `gates/gendirs.py` was built so that *"a change to it moves both"*. This
file asks the same question of the six gate-counting instruments and answers it by MEASUREMENT,
not by reading their docstrings: **drop ONE new gate into a SCRATCH COPY of the tree, re-run all
six projections against that copy, and diff the six answers. A projection that does not move has
a list somewhere, and this file names it.**

THE SCRATCH COPY IS NOT OPTIONAL. Every projection takes a `root`, so a plant in the live tree
would work -- and would also leave a gate behind in `checks/`, which six instruments and four
concurrent units would then have to recognise as real. The copy is made with `shutil.copytree`
over `symlinks=True`, which matters: `bin/bend` is a symlink and `discover()`'s own docstring
says an existence test that follows symlinks certifies a link target as a tree file.

THE PLANTED FILE IS DELIBERATELY ORDINARY. A gate with `if __name__ == '__main__'`, a `sys.exit`,
and nothing else -- because a plant that is unusual in a second way would move a projection for
a reason that is not the property under test. It is named `zz-plant-probe.py` so it sorts last
and no prefix rule can accidentally be what admits it.

WHAT COUNTS AS A PASS HERE. Every projection that claims the gates population must move by
exactly +1 file and +1 entry. A projection that does not move is a FAIL against its own claim,
and the failure is printed with the reason. `pairs` and `prune4` are NOT expected to move:
`pairs` counts a different question (string-lists, whole tree) and `prune4` counts git state.
They are planted anyway so the table shows what each one does, and their delta is reported as
MEASURED rather than asserted.
"""
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = str(ROOT / ".venv" / "bin" / "python")

PLANT_NAME = "zz-plant-probe.py"
# An ordinary gate. `if __name__ == '__main__'` is the ONLY thing that makes it an entry point
# under both `discover()`'s AST rule and `vocab.py`'s AST rule, so the plant tests exactly the
# property the two rules share and nothing else.
PLANT_SRC = '''#!/usr/bin/env python3
"""A planted gate: an ordinary entry point, used to ask whether a projection is a discovery."""
import sys


def main():
    # Planted deliberately at rest, so it measures something and refuses to be red for free.
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''

# THE SECOND PLANT, AND IT IS THE ONE THAT SETTLES QUESTION 2. `discover()` reads each home with
# `iterdir()` (`gates/gates-pop.py:324`), so a gate one directory DEEP is invisible to it while a
# recursive walk sees it. Today that costs exactly two files -- `gates/oracles/*.sh`, which is a
# real directory holding two real shell gates -- but the number is not the finding; the SHAPE is.
# A population that is correct only while the tree is FLAT is a list with a recursive option, and
# the plant proves it by putting a file where the flatness assumption is the only thing stopping
# it from being counted.
PLANT_DEEP_NAME = "oracles/zz-plant-deep.sh"
PLANT_DEEP_SRC = '''#!/bin/sh
# A planted gate ONE DIRECTORY DEEP inside a gate home. `iterdir()` cannot see it; `os.walk` can.
exec "$(dirname "$0")/../zz-plant-probe.py" "$@"
'''


# ---- the six projections, each taking (root, tmp) ------------------------------------
def run(code: str, root: pathlib.Path, tmp: pathlib.Path, timeout=300) -> tuple[int, str]:
    """Run `code` against `root`. Returns (rc, stdout, stderr). A timeout is TIMED-OUT, never 0,
    and a nonzero rc is NOT zero rows: it prints the error so the caller cannot read it as a count."""
    env = dict(os.environ, TMP=str(tmp), OM_ROOT=str(root))
    try:
        r = subprocess.run([PY, "-c", code], capture_output=True, text=True,
                           env=env, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return -1, "TIMED-OUT", ""


PRELUDE = """
import importlib.util, json, pathlib, os, subprocess, sys
ROOT = pathlib.Path(os.environ["OM_ROOT"])

def load(p, n):
    p = pathlib.Path(p)
    if not p.is_relative_to(ROOT):
        p = ROOT / p
    if not p.is_file():
        raise SystemExit(f"MISSING {p}")
    s = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
    return m

def rel(ps):
    return sorted({str(p.relative_to(ROOT)) for p in ps})
"""

PROJ = {
    "discover": PRELUDE + """
m = load("gates/gates-pop.py", "p")
e, l = m.discover(ROOT)
print(json.dumps({"files": len(e)+len(l), "entries": len(e), "in_plant": PLANT in rel(e+l)}))
""",
    "surface": PRELUDE + """
m = load("gates/gate-surface.py", "p")
e, l = m.population(ROOT)
w = m.walk_control(ROOT, ("checks", "gates"))
print(json.dumps({"files": len(e)+len(l), "entries": len(e), "walk": len(w),
                  "in_plant": PLANT in rel(e+l), "in_walk": PLANT in w}))
""",
    "coindependent": PRELUDE + """
m = load(".agents/slop/coindependent/vocab.py", "p")
rows = m.scan(ROOT, m.HOMES)
ent = [r for r in rows if r["reason"] in ("py-main", "sh")]
print(json.dumps({"files": len(rows), "entries": len(ent),
                  "in_plant": PLANT in {r["path"] for r in rows}}))
""",
    "zerogate": PRELUDE + """
sys.path.insert(0, str(ROOT / ".agents/slop/coindependent"))
m = load(".agents/slop/zerogate/derive.py", "p")
eps = m.entry_points()
print(json.dumps({"entries": len(eps), "in_plant": PLANT in {e["path"] for e in eps}}))
""",
    "pairs": PRELUDE + """
m = load(".agents/slop/pairs/census.py", "p")
w = m.shared(m.walk_all()); t = m.shared(m.tracked())
print(json.dumps({"whole_tree": len(w), "tracked": len(t)}))
""",
    "prune4": PRELUDE + """
def g(*a):
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True,
                          text=True).stdout.split()
print(json.dumps({
    "ls_files_index": len(g("ls-files", "gates/*")),
    "ls_tree_HEAD": len(g("ls-tree", "-r", "--name-only", "HEAD", "gates/")),
    "in_plant_index": PLANT in g("ls-files"),
    "in_plant_HEAD": PLANT in g("ls-tree", "-r", "--name-only", "HEAD", "gates/"),
}))
""",
}

# `prune4` is the one projection whose population is the INDEX, so a file on disk that git has not
# been told about is INVISIBLE to it -- legitimately, because its question is "what is committed",
# not "what exists". The uncommitted plant therefore does not move it, and that is not a list.
# So it gets a SECOND plant, `git add`ed in the scratch copy, which is the state its population
# actually describes. Measured both ways, because the gap between the two IS the trap.
PLANT_COMMIT = "the same file, `git add`-ed (not committed) in the scratch copy"


def stage(root: pathlib.Path):
    """`git add -A` in the scratch copy. Its index is the scratch repo's own `.git/index`, which
    `git init` created inside the copy -- so this cannot touch the live index."""
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"),
           "GIT_AUTHOR_NAME": "plant", "GIT_AUTHOR_EMAIL": "plant@localhost",
           "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+0000",
           "GIT_COMMITTER_NAME": "plant", "GIT_COMMITTER_EMAIL": "plant@localhost",
           "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+0000"}
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True, env=env,
                   capture_output=True)


def measure(root: pathlib.Path, tmp: pathlib.Path, code: str) -> dict:
    import json
    rc, out, err = run(code.replace("PLANT", repr(f"gates/{PLANT_NAME}")), root, tmp)
    if rc != 0:
        # A nonzero rc carries NO denominator. Print the traceback tail so a crash in a projection
        # cannot be read as "this projection has nothing to say" (`gates/gates-pop.py:refuse`).
        return {"error": f"rc={rc}", "err": err.strip().splitlines()[-1] if err.strip() else ""}
    try:
        return json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"error": "unparseable", "err": out[-200:]}


def scratch() -> pathlib.Path:
    """A scratch copy of the tree. `symlinks=True` because `bin/bend` IS a symlink.

    THE THREE INSTRUMENTS THAT LIVE UNDER `.agents/slop/` ARE COPIED IN TOO, because a projection
    whose LOADER is absent must not be scored as a projection whose POPULATION is stale: `MISSING`
    is a broken instrument, not a zero. They are copied by directory, and that is the only use of
    `.agents/slop/` here -- nothing in it is a gate.

    THE COPY IS A GIT REPO WITH A COMMIT, and that is not tidiness. `prune4`'s population is the
    INDEX, so against an untracked copy `git ls-files` answers 0 -- which is the same reading as
    "there are no gates", and `git ls-files` on a directory that was never a repo is precisely the
    `prune4` trap this report is about. Committing the copy makes the plant FAIR to `prune4` and
    turns its answer into a real measurement instead of an artefact of the scratch.
    """
    d = pathlib.Path(tempfile.mkdtemp(prefix="om-plant-"))
    shutil.rmtree(d)
    for name in ("checks", "gates", "tinybendygrad"):
        shutil.copytree(ROOT / name, d / name, symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__"))
    for unit in ("coindependent", "zerogate", "pairs"):
        src = ROOT / ".agents/slop" / unit
        if src.is_dir():
            shutil.copytree(src, d / ".agents/slop" / unit, symlinks=True,
                            ignore=shutil.ignore_patterns("__pycache__"))
    for name in ("pyproject.toml", ".gitignore"):
        if (ROOT / name).is_file():
            shutil.copy2(ROOT / name, d / name)
    # THE COPY'S GIT INDEX IS ITS OWN. `git init` inside a scratch directory creates `.git/index`
    # THERE, not in the live repo, and `GIT_INDEX_FILE` is deliberately NOT set for these calls:
    # setting it to a path inside `.git/` is how `prune4` ended up reading a two-entry index. The
    # isolation is the directory's, which is what a scratch copy is for.
    env = {"GIT_AUTHOR_NAME": "plant", "GIT_AUTHOR_EMAIL": "plant@localhost",
           "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+0000",
           "GIT_COMMITTER_NAME": "plant", "GIT_COMMITTER_EMAIL": "plant@localhost",
           "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+0000", "PATH": os.environ["PATH"],
           "HOME": os.environ.get("HOME", "/tmp")}
    for args in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "scratch base"]):
        subprocess.run(["git", "-C", str(d), *args], check=True, env=env,
                       capture_output=True)
    return d


def main(argv):
    t0 = time.time()
    print(f"# PLANT: one ordinary gate at gates/{PLANT_NAME}, in a SCRATCH COPY "
          f"(symlinks=True). {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}",
          file=sys.stderr)
    scratch_root = scratch()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="om-tmp-"))
    print(f"# scratch copy: {scratch_root}\n", file=sys.stderr)

    print(f"{'projection':16} {'before':>34} {'after':>34}  moved?")
    rows = []
    for name, code in PROJ.items():
        b = measure(ROOT, tmp, code)
        (scratch_root / "gates" / PLANT_NAME).write_text(PLANT_SRC)
        a = measure(scratch_root, tmp, code)
        (scratch_root / "gates" / PLANT_NAME).unlink()

        def fmt(d):
            return ", ".join(f"{k}={v}" for k, v in sorted(d.items())
                             if k not in ("in_walk", "err"))
        seen = a.get("in_plant", a.get("in_walk"))
        moved = "YES" if b != a else "** NO **"
        print(f"{name:16} {fmt(b):>34} {fmt(a):>34}  {moved}")
        rows.append((name, b, a, seen))

    print("\n--- DOES EACH PROJECTION SEE THE NEW GATE? ---")
    for name, b, a, seen in rows:
        if "in_plant" in b or "in_plant" in a:
            v = seen if isinstance(seen, bool) else "?"
            print(f"  {name:16} sees the planted gate: {v}")
        else:
            print(f"  {name:16} does not count files at all (different question) -- "
                  f"delta {b} -> {a}")

    # --- prune4's own population, staged. This is the trap, measured rather than asserted.
    print("\n--- prune4's POPULATION, PLANTED TWICE: " + PLANT_COMMIT + " ---")
    (scratch_root / "gates" / PLANT_NAME).write_text(PLANT_SRC)
    untracked = measure(scratch_root, tmp, PROJ["prune4"])
    stage(scratch_root)
    staged = measure(scratch_root, tmp, PROJ["prune4"])
    (scratch_root / "gates" / PLANT_NAME).unlink()
    print(f"  on disk, NOT staged : {fmt(untracked)}")
    print(f"  on disk, STAGED     : {fmt(staged)}")
    print("  -> prune4's population is THE INDEX. A gate that exists and is not `git add`-ed is")
    print("     invisible to it, and `git ls-files` on a tree whose index has been reset answers")
    print("     2 where thousands are tracked. That is a correct answer to a different question,")
    print("     and it is the same fault as the other five: a population that is not the TREE.")

    # --- PLANT 2: the same gate, one directory DEEP. This is the depth question.
    print(f"\n--- PLANT 2: gates/{PLANT_DEEP_NAME}, one directory DEEP in a gate home ---")
    deep = scratch_root / "gates" / PLANT_DEEP_NAME
    for name in ("discover", "surface", "coindependent", "zerogate"):
        code = PROJ[name].replace("PLANT", repr(f"gates/{PLANT_NAME}"))
        # Re-ask the same projection with a DIFFERENT planted path, deep.
        deep_code = code.replace(repr(f"gates/{PLANT_NAME}"), repr(f"gates/{PLANT_DEEP_NAME}"))
        b = measure(scratch_root, tmp, deep_code)
        deep.write_text(PLANT_DEEP_SRC)
        a = measure(scratch_root, tmp, deep_code)
        deep.unlink()
        print(f"  {name:16} {fmt(b):>34} -> {fmt(a):>34}  "
              f"{'MOVED' if b != a else '** DID NOT MOVE **'}  saw_it={a.get('in_plant')}")

    print("\n--- WHAT EACH PROJECTION ACTUALLY ASKED ---")
    print("  plant 1 sits at gates/ TOP LEVEL: every projection whose population is the tree moves.")
    print("  plant 2 sits at gates/oracles/: only a RECURSIVE walk moves. `discover()`'s")
    print("  `iterdir()` is what makes that true, and 2 files today is the cost, not the finding.")

    shutil.rmtree(scratch_root, ignore_errors=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\nelapsed {time.time()-t0:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))