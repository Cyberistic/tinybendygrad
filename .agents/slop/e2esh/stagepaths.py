"""WHAT THE OLD ROOT MEANT FOR THE SEVEN STAGES: EVERY PATH THEY RESOLVE, BOTH WAYS.

`checks/e2e.sh`'s stages are all RELATIVE (`./bin/bend`, `.agents/slop/e2e_mm.py`) or are built from
`$ROOT` (`$ROOT/.venv/bin/python`, `$ROOT/runs/e2e`), so the root is not a detail of where the script
reads from -- it IS the tree every stage is measured in. `cd "$ROOT"` SUCCEEDED on the old root
because `/Users/cyberistic/src/tries` exists, so nothing refused, and the run then measured a tree
that is not the repository.

So this asks the only question that matters: does each stage's path exist under the OLD root and
under the NEW one? Seven stages, five paths, two roots, and both roots computed by RUNNING each
file's own `ROOT` computation -- the old one is `git show HEAD:checks/e2e.sh`'s, so this does not
hard-code either answer.

TWO METHODS THAT SHARE NO REGEX, because one list of names read through one `Path.exists()` is one
assumption with two chances to be wrong: this also walks each root with `os.walk` and reports the
count of the stage's own first path component, so a path that "exists" as a symlink target but is not
reachable by walking is visible. (`Path.exists()` follows symlinks; the walk does not.)
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE))
from resolve import preamble  # noqa: E402  -- this unit's own module
REPO = HERE.parents[3]
E2E = REPO / "checks" / "e2e.sh"
# `git show HEAD:checks/e2e.sh` -- the body as it was BEFORE this unit, which is where `../..` came
# from. Read from history rather than transcribed, so a stale copy of the old line cannot make this
# report the old root for the wrong reason.
OLD_BODY = subprocess.run(["git", "show", "HEAD:checks/e2e.sh"], cwd=REPO, capture_output=True,
                          check=True).stdout.decode()
OLD_ROOT_LINE = next(ln for ln in OLD_BODY.splitlines() if ln.startswith("ROOT="))

# Every path a stage reaches, and which stage. `PY`/`RUN` are `$ROOT`-prefixed in the file; the rest
# are relative and resolve against the cwd, which is `$ROOT`.
PATHS = [
    ("1 e2e_mm.py", ".venv/bin/python"),
    ("2 ./bin/bend", "bin/bend"),
    ("3 e2e_mm_run.mjs", ".agents/slop/e2e_mm_run.mjs"),
    ("4 e2e_mm_gate.py", ".agents/slop/e2e_mm_gate.py"),
    ("5 opsbend-milestone.sh", ".agents/slop/opsbend-milestone.sh"),
    ("6 run-port-mm.sh", ".agents/slop/e2e_port/run-port-mm.sh"),
    ("7 run-f64.sh", ".agents/slop/f64/run-f64.sh"),
    ("- runs/e2e", "runs"),
    ("- pyproject.toml (the marker)", "pyproject.toml"),
]


def root_of(line: str) -> Path:
    """The root ONE LINE produces. The old line is self-contained; the new one is NOT, because the
    fixed file computes `$_d` on the line above it -- so the caller passes the fixed file's whole
    preamble, and a bare `ROOT=` line evaluated alone yields `/`. That mistake printed
    `NEW root -> /` on the first run of this script, with all nine paths ABSENT under both roots and
    the summary reading `0 changed`, which is a script measuring nothing and calling it agreement.
    """
    out = subprocess.run(["/bin/sh", "-c", f'{line}\nprintf "%s\\n" "$ROOT"', str(E2E)],
                         cwd="/", env={"PATH": "/usr/bin:/bin"}, capture_output=True, text=True,
                         check=True)
    return Path(out.stdout.strip())


# The old root is `/Users/cyberistic/src/tries`, the PARENT of every repo anyone keeps here, so an
# unbounded walk of it is a walk of the user's whole checkout area. `depth` is what keeps this
# measurable, and its cost is named rather than assumed: a stage path is at most three components
# below the root, so 6 is generous, and a hit found at depth 6 is not missed at depth 7 in practice
# for the names in PATHS. This is why the walk is a BELT and not the check -- `Path.exists()` above
# is the check, and it does not walk.
WALK_DEPTH = 6


def walk_count(root: Path, top: str) -> int:
    """How many entries named `top` are reachable by WALKING `root`, to `WALK_DEPTH`. 0 if not a tree."""
    if not root.is_dir():
        return 0
    base, hit = len(root.parts), 0
    for dirpath, dirs, files in os.walk(root):
        if len(Path(dirpath).parts) - base >= WALK_DEPTH:
            dirs[:] = []
            continue
        # Directories AND files: `pyproject.toml` is a file and `bin` is a directory, and a walk that
        # counted only one of them would report a marker as unreachable when it is right there.
        hit += dirs.count(top) + files.count(top)
    return hit


def main() -> int:
    # The fixed file's PREAMBLE, cut by shape rather than transcribed -- see `resolve.preamble`, and
    # the assertion in `root_of` about why the `ROOT=` line alone is not the subject.
    old = root_of(OLD_ROOT_LINE)
    new = root_of(preamble(E2E))
    # A root that is not the repo, or not a tree at all, means this script is measuring nothing. Said
    # out loud instead of averaged into a summary that would read as agreement.
    assert new.resolve() == REPO.resolve(), f"the fixed file's preamble resolves to {new}, not {REPO}"
    print(f"OLD root, from HEAD's line {OLD_ROOT_LINE!r}\n  -> {old}")
    print(f"NEW root, from the fixed file's own computation\n  -> {new}\n")
    print(f"{'stage':<26} {'path':<40} {'OLD root':<11} {'NEW root':<11} walk(old)")
    lost = []
    for stage, rel in PATHS:
        top = rel.split("/")[0]
        o, n = (old / rel).exists(), (new / rel).exists()
        print(f"{stage:<26} {rel:<40} {'present' if o else 'ABSENT':<11} "
              f"{'present' if n else 'ABSENT':<11} {walk_count(old, top)}")
        if o != n:
            lost.append(stage)
    print(f"\n{len(PATHS) - len(lost)} of {len(PATHS)} path(s) resolve under both roots; "
          f"{len(lost)} changed")
    if lost:
        print("  changed: " + ", ".join(lost))
        print("\nEVERY stage path above was ABSENT under the old root: the old run did not measure "
              "the\nrepository, and `cd \"$ROOT\"` into its parent SUCCEEDED, so nothing refused.")
    return 0


if __name__ == "__main__":
    sys.exit(main())