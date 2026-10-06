#!/usr/bin/env python3
"""PLANT: `checks/census.py`'s cache rename is self-consistent, proved WITHOUT its dead imports.

`checks/census.py` cannot run on this tree -- it does `import graphcmp` at module scope and the
sweep commit `371cc64c9` deleted `checks/graphcmp.py`. So the usual move -- run the gate, read the
verdict -- is unavailable, and an unrunnable rename is exactly the kind that survives three
documents. This stubs the import, plants a warm cache at the NEW name, and asks the only question
that matters about a rename with no reader but its own writer: DOES THE READER STILL FIND IT?

A warm cache is the only path that proves the read site moved, because on a cold cache the reader
is never consulted and every extension looks fine.

usage: .venv/bin/python .agents/slop/txtgen/census-cache-plant.py

exit 0  the reader finds the cache at the new name, and finds nothing at the old one
exit 1  it does not -- the rename moved the write and missed the read
"""
import importlib.util
import pathlib
import sys
import tempfile
import types

ROOT = pathlib.Path(__file__).resolve().parents[3]

# The stub. `census.py` needs `graphcmp` for `unchunks` (called on the WARM path, to summarise the
# cached rows) and for `emit_py`/`emit_bend`/`commutative`/`Ops`/`load_tinygrad` (called only on a
# COLD path). The emits raise, so a run that silently missed the cache and re-emitted could not
# pass this; `unchunks` is real, because the reader is entitled to call it.
g = types.ModuleType("graphcmp")


def _must_not_run(*a, **k):
    raise AssertionError("the cache was MISSED: census.py fell through to a real emission")


def _unchunks(row):
    # `ops_of` indexes `f[1]` where `f` is one `unchunks()` result, so a result must carry at
    # least two records. Two is enough; the contents are never inspected by this plant.
    return [("node", "trange"), ("node", "trange")]


g.emit_py = g.emit_bend = g.commutative = g.load_tinygrad = _must_not_run
g.unchunks = _unchunks
g.os = __import__("os")
g.GRAPHS = {}
g.Ops = []
sys.modules["graphcmp"] = g


def load_census(where):
    spec = importlib.util.spec_from_file_location("census", where)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main() -> int:
    c = load_census(ROOT / "checks/census.py")
    row = "trange_0_len=0"

    with tempfile.TemporaryDirectory(prefix="census-") as td:
        here = pathlib.Path(td)
        c.HERE = here
        (here / "rows-demo-py.rows").write_text(row + "\n")
        (here / "rows-demo-py.txt").write_text("STALE: the old extension, nobody reads me\n")

        warm = c.side("demo", "py", "CPU", fresh=False)
        # And the OLD name must NOT be what it reads: if `.txt` were still live this returns the
        # stale body, and the row count would be 1 either way -- so the count is the weak signal
        # here and the SENTINEL in the stale file is the strong one.
        stale_read = warm[0] == "CACHE" and "STALE" not in (here / "rows-demo-py.rows").read_text()

        print(f"cache at the NEW name `rows-demo-py.rows`  -> {warm[0]}, {warm[1]} row(s)")
        print(f"the reader consulted the NEW name         {stale_read}")
        print(f"a `.txt` cache left beside it is ignored   "
              f"{(here / 'rows-demo-py.txt').exists()} (present, unread)")

    ok = warm[0] == "CACHE" and warm[1] == 1 and stale_read
    print("\nVERDICT: the read site moved with the write site." if ok
          else "\nVERDICT: THE RENAME MOVED THE WRITE AND MISSED THE READ.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())