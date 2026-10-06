"""PLANT: the pre-import REFUSAL lane of `graphcmp-oracle.py:237`.

It is the only way to make the exit red while `# ORACLE SELFCHECK` is ABSENT rather
than `FAIL` -- i.e. the one shape where `differ.py`'s two pinned facts, `census-rc`
and `oracle-selfcheck`, CAN disagree. It runs the oracle as `__main__` after tinygrad
is already imported, which freezes `Device.DEFAULT` so `DEV` can no longer choose the
device. Exit 1, zero bytes on stdout.
"""
import pathlib
import sys

sys.path.insert(0, ".agents/slop")
import tinygrad  # noqa: F401  -- the precondition the refusal refuses

_oracle = pathlib.Path(".agents/slop/graphcmp-oracle.py")
exec(compile(_oracle.read_text(), str(_oracle), "exec"),
     {"__name__": "__main__", "__file__": str(_oracle)})
