#!/usr/bin/env python3
"""reporoot.py -- THE REPO ROOT, FOUND BY A MARKER AND NOT BY A DEPTH.

    .venv/bin/python -c "import sys;sys.path.insert(0,'gates');import reporoot;print(reporoot.root())"

WHY A SEARCH UPWARD AND NOT `parents[N]`. A depth is a CONSTANT that says "this file sits
exactly N levels below the root", and a cleanup that moves the file does not move the
constant -- `gates/gates-pop.py`'s own header calls that "the tree's depth baked into a
constant", and its plant 1 asserts that a gate at the WRONG DEPTH is red.

It is not a theoretical hazard for the files this module exists for. THE PAIR OF NUMBERS
COULD NOT BE RIGHT FOR BOTH PLACES: `gates/fold-vbase-oracle.py` and
`gates/fold-vbase-mutate.py` were BOTH under `.agents/slop/` (three `dirname`s) and are
now under `gates/` (one), and a `parents[N]` that is right for one of them is wrong for
the other. A number that cannot be right for both is a number that will be wrong for one.

THE MARKERS, AND WHY ALL THREE. `pyproject.toml` is the file `gates/gates-pop.py`'s own
root clause looks for (`MARKER`), so finding it is finding what that instrument reads.
`tinybendygrad/` and `tinygrad/` are the two trees `checks/differ.py`'s `substrate_digest()`
walks (`SUBSTRATE_WALKS`), so a directory holding BOTH is a directory the port and the
reference it is measured against are both in.

ONE MARKER IS NOT ENOUGH, AND THIS TREE SAYS WHY. There is a `pyproject.toml` at
`.agents/slop/denominator/probe/`, and a marker that a probe can satisfy is a marker that
can be satisfied by the wrong thing. The three together are a shape no directory in this
tree but the root has.

AND IT REFUSES INSTEAD OF GUESSING. `RootNotFound` is a REFUSAL and not a fallback: a
caller that cannot find the root prints "REFUSED, NOT A VERDICT" and exits 3, because a
gate that measures a tree it could not identify is a gate whose answer is about nothing.
"""
from pathlib import Path

# THE MARKERS, AS A TUPLE AND NOT A LIST OF ALTERNATIVES: all of them, or it is not the root.
MARKERS = ("pyproject.toml", "tinybendygrad", "tinygrad")


class RootNotFound(RuntimeError):
  """The root was not found, and a caller must REFUSE rather than guess."""


def root(start=None):
  """The repo root: the first ancestor of `start` holding every marker, or `RootNotFound`.

  `start` is a FILE OR A DIRECTORY and the walk handles both without being told which:
  the candidate list is the path itself followed by its parents, so a file's own
  directory is the first candidate and a directory is the first candidate for itself.
  """
  here = Path(start or __file__).resolve()
  for cand in (here, *here.parents):
    if all((cand / m).exists() for m in MARKERS):
      return cand
  raise RootNotFound(
    f"no ancestor of {here} holds all of {', '.join(MARKERS)} -- this file is not inside "
    "the tinybendygrad tree")
