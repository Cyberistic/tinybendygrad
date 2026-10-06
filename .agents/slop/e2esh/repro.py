"""TWO COLUMNS, AND THE COLUMN THAT PROVES THE MARKER CAN FAIL.

THE SUBJECT IS `checks/e2e.sh`'s ROOT, so the columns are about the ROOT, not about the seven stages
underneath it. Running all seven needs `bend`, `cc`, `node` and a browser, takes minutes, and would
make this repro's verdict depend on whether stage 6 happened to be reproducible that minute -- the
`checks/e2e.py` docstring records stage 6 green on one run and red on the next of an unmodified tree.
So each column runs the file's own ROOT PREAMBLE (`.agents/slop/e2esh/resolve.py` cuts it out by
shape) and asserts on `(exit, $ROOT, stderr)`.

  COLUMN 1  the file where it lives, invoked by ABSOLUTE PATH from `/`. Must reach the repo: before
            the fix `$ROOT` was `/Users/cyberistic/src/tries`, the repo's parent, and `cd` into it
            SUCCEEDED, so every stage after it ran against a tree that is not the repository.
  COLUMN 2  the same file MOVED ONE DIRECTORY DEEPER -- `checks/deeper/e2e.sh` -- still invoked by
            absolute path, still from `/`. Must go red NAMING THE DIRECTORY IT REACHED, so a reader
            knows which of two plausible roots was wrong rather than only that something was.

`$ROOT` IS NOT ASSERTED ON COLUMN 2, and its absence there is the design rather than a gap: the
assertion `exit 2`s before anything can print `$ROOT`, which is exactly why the reached directory is
carried in the MESSAGE. A first cut asserted `ROOT == <reached>` on the refusing run, reported
`DID NOT REFUSE` for a run that had refused correctly and said so, and would have passed a
preamble that refused for the wrong reason and named the wrong directory.

**THE MARKER IS READ WITH A METHOD THAT DOES NOT SHARE A TOKENIZER WITH THE WRITER.** The preamble
writes `not at the repo root (pwd $ROOT)`; column 2 asserts three separate `in` tests over the raw
stderr -- `not at the repo root`, `(pwd `, and the expected reached directory -- rather than one
regex. A repro whose matcher shares an assumption with the thing it matches inherits that
assumption's blind spot and reports the plant as unmoved: that is the `[A-Za-z0-9_.-]*`-ate-a-full-
stop failure, where the belt was built out of the tokenizer's own characters.

**AND THE ROW THAT PROVES THE BELT IS NOT A CONSTANT.** Column 2's check is run a second time with
the file NOT relocated, and the harness requires the two to DISAGREE. An assertion that passes for
both a planted and an unplanted tree is an assertion that cannot fail, which is the defect one level
up from a plant that cannot move. The `checks/deeper/` copy is removed in a `finally`, and the
cleanup is itself asserted -- a repro that leaves its plant behind is a repro that changes the tree it
is measuring.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
sys.path.insert(0, str(HERE))
from resolve import resolves_to  # noqa: E402  -- it is this unit's own module

E2E = REPO / "checks" / "e2e.sh"
# The directory the relocated copy REACHES, not the repo it should have reached: the assertion exists
# to name the wrong one, so a test that asserted the right one would prove nothing.
REACHED = str((REPO / "checks").resolve())
MARKERS = ("not at the repo root", "(pwd ", REACHED)


def column(label: str, script: Path) -> dict:
    rc, root, err = resolves_to(script, Path("/"))
    return {"label": label, "script": script, "rc": rc, "root": root, "stderr": err}


def main() -> int:
    bad = []
    print(f"subject: {E2E.relative_to(REPO)}'s root preamble, run from /\n")

    c1 = column("COLUMN 1  where it lives", E2E)
    ok1 = c1["rc"] == 0 and Path(c1["root"]).resolve() == REPO.resolve()
    print(f"COLUMN 1  where it lives, absolute $0, from /\n  $0    {c1['script']}\n  exit  "
          f"{c1['rc']}\n  ROOT  {c1['root']}\n  -> {'OK: the repo' if ok1 else 'WRONG ROOT'}\n")
    bad += [] if ok1 else ["column 1"]

    deeper = REPO / "checks" / "deeper"
    try:
        deeper.mkdir(exist_ok=True)
        copy = deeper / "e2e.sh"
        copy.write_text(E2E.read_text())
        copy.chmod(0o755)
        assert copy.resolve() != E2E.resolve()

        c2 = column("COLUMN 2  moved one deeper", copy)
        missing = [m for m in MARKERS if m not in c2["stderr"]]
        # rc 2 is this script's "NOTHING WAS MEASURED" status, shared with eight fruitless `bend`
        # attempts -- the number cannot say which refusal it was, which is why stderr must.
        ok2 = c2["rc"] == 2 and not missing
        print(f"COLUMN 2  moved one deeper, absolute $0, from /\n  $0    {c2['script']}\n  exit  "
              f"{c2['rc']}\n  ROOT  {c2['root'] or '(unprinted: the refusal exits before it)'}"
              f"\n  said  {c2['stderr']}\n  markers missing: {missing or 'none'}"
              f"\n  -> {'OK: refused, and named the directory it reached' if ok2 else 'DID NOT REFUSE'}\n")
        bad += [] if ok2 else ["column 2"]
    finally:
        for p in sorted(deeper.glob("*"), reverse=True):
            p.unlink()
        deeper.rmdir()

    c3 = column("CONTROL  not relocated", E2E)
    fires = c3["rc"] == 2
    print(f"\nCONTROL -- the belt's own direction of failure\n  column 2's check, file NOT relocated: "
          f"exit {c3['rc']}, {'refused' if fires else 'did NOT refuse'}"
          f"\n  -> {'OK: the two disagree, so the check tells them apart' if not fires else 'BROKEN: it passes either way'}\n")
    bad += [] if not fires else ["control"]

    # The cleanup is asserted too, because a repro that leaves its plant behind changes the tree it
    # measures. `deeper.exists()` is the whole check; comparing `checks/e2e.sh` to itself would be
    # the tautology this project treats as harmful.
    clean = not deeper.exists()
    print(f"plant removed: {'OK' if clean else 'FAIL -- checks/deeper/ is still there'}")
    bad += [] if clean else ["cleanup"]

    for b in bad:
        print(f"  FAIL {b}")
    print("both columns hold" if not bad else f"{len(bad)} check(s) failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())