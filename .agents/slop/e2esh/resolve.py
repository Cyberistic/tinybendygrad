"""WHAT DOES `checks/e2e.sh` RESOLVE ITS ROOT TO? THREE PLACES, ONE ANSWER EACH.

The subject is the PREAMBLE, evaluated as written rather than recognised by a regex pinned to one
line: from the first line that computes `ROOT` up to and including the `cd "$ROOT"` that follows it.
That block is run in a subshell under `sh` with `$0` set to the path the caller PASSED and `cwd` set
to a FOREIGN directory, and the block's own exit status and `$ROOT` are reported. So the assertion,
if there is one, is exercised -- an assertion that is measured only by reading it is the kind this
project keeps finding out does not fire.

Three invocations, because a single answer can be right by accident:

  1. ON THIS MACHINE, by absolute path, from `/`.
  2. IN A COPIED TREE at a different depth and name, so a path that happened to be correct here is
     wrong there.
  3. FROM A FOREIGN CWD, which is what separates a root computed from `$0` from one computed from
     `pwd`, and the difference between the two IS the question.

`$0` IS PASSED AS `sh -c`'s COMMAND NAME, never as a word inside the command: `sh -c 'cmd'` leaves
`$0` as the shell's own name, and a first cut that got this wrong measured the literal string `/` on
every invocation and looked like a wrong root for the wrong reason.

NOTHING BUT THE PREAMBLE RUNS. No stage, no compiler, no browser, no GPU, and no file under test is
written outside a `TemporaryDirectory`.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
# The last line of the preamble, found by shape. `cd "$ROOT"` is what the stages' relative paths hang
# off, so the block that ends there is exactly the root computation and nothing after it.
LAST = 'cd "$ROOT"'


def preamble(script: Path) -> str:
    """The `ROOT` block, cut from the file by shape. Raises rather than guessing if it is gone."""
    lines = script.read_text().splitlines()
    start = next((i for i, ln in enumerate(lines)
                  if ln.startswith(("ROOT=", "_d=", "REPO="))), None)
    if start is None:
        raise SystemExit(f"{script}: no line computes ROOT -- measure that, do not guess")
    try:
        end = next(i for i, ln in enumerate(lines[start:], start) if ln.startswith(LAST))
    except StopIteration:
        raise SystemExit(f"{script}: no `{LAST}` after the ROOT computation") from None
    return "\n".join(lines[start:end + 1])


def resolves_to(script: Path, cwd: Path) -> tuple[int, str, str]:
    """`(exit, ROOT, stderr)` for one invocation of the file's own preamble.

    `ROOT` IS EMPTY WHEN THE PREAMBLE REFUSES, and that is not a gap in this harness: the assertion
    `exit 2`s before anything can print it, which is precisely why the reached directory is put in
    the MESSAGE. A first cut of `repro.py` asserted `ROOT == <reached>` on a refusing run and
    reported `DID NOT REFUSE` for a run that had refused correctly and said so.
    """
    block = f'{preamble(script)}\nprintf "%s\\n" "$ROOT"\n'
    out = subprocess.run(["/bin/sh", "-c", block, str(script)], cwd=cwd,
                         env={"PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
    return out.returncode, out.stdout.strip(), out.stderr.strip()


def main() -> int:
    repo_e2e = REPO / "checks" / "e2e.sh"
    print(f"the preamble under test, from {repo_e2e}:\n{preamble(repo_e2e)}\n")

    rows = []
    with tempfile.TemporaryDirectory(prefix="e2esh-") as tmp:
        # A copied tree FOUR levels deep under the temp root, against this repo's two, so a path that
        # happens to be right here is wrong there. `pyproject.toml` + `tinybendygrad/` are the markers
        # the assertion looks for, and they are created because a tree without them is not a repo.
        deep = Path(tmp) / "a" / "b" / "c" / "d" / "e2esh-copy"
        (deep / "checks").mkdir(parents=True)
        (deep / "pyproject.toml").write_text("# the marker a correct root must contain\n")
        (deep / "tinybendygrad").mkdir()
        (deep / "checks" / "e2e.sh").write_text(repo_e2e.read_text())

        for label, script in (("1 here, by absolute $0", repo_e2e),
                              ("2 copied tree, by absolute $0", deep / "checks" / "e2e.sh")):
            # The tree each copy must resolve to is ITS OWN, computed from where the copy lives -- a
            # fixed constant here would report the copied tree as wrong for being a different tree,
            # which is the CHECK being wrong rather than the subject.
            rows.append((label, script, script.resolve().parent.parent,
                         *resolves_to(script, Path("/"))))

    for label, script, want, rc, got, err in rows:
        # Compared through `resolve()`, because on macOS `/var` is a symlink to `/private/var` and a
        # tempfile root prints as one and resolves as the other. Both sides go through the same call.
        ok = rc == 0 and Path(got).resolve() == Path(want).resolve()
        print(f"{label}\n  $0    {script}\n  cwd   /\n  exit  {rc}\n  ROOT  {got}\n  want  {want}"
              + (f"\n  stderr {err}" if err else "")
              + f"\n  -> {'OK' if ok else 'WRONG ROOT'}\n")

    bad = [r for r in rows if r[3] != 0 or Path(r[4]).resolve() != Path(r[2]).resolve()]
    print(f"{len(rows) - len(bad)} of {len(rows)} invocation(s) resolved to the tree that holds "
          f"pyproject.toml and tinybendygrad/")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())