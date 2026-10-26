#!/usr/bin/env python3
"""THE 153-FIXTURE CENSUS, IN CHUNKS, AGAINST ONE COMPILED EXECUTOR.

    .venv/bin/python .agents/slop/vslane/census.py <executor> <out.rows> [lo] [hi]

IT REUSES `.agents/slop/execfix/census.py`'s OWN `fixtures()` and `run_one()` --
the tree's record of the population and the tree's own spelling of a row -- so
this file invents NEITHER. It only adds two things:

  * a RANGE, because one foreground call cannot hold 153 fixtures (MEASURED:
    4.2 s per fixture on this machine, so 153 is ~11 minutes, and the harness's
    foreground timeout is 120 s), and
  * an APPEND, so the chunks accumulate into one file.

THE POPULATION IS THE TREE's OWN FIXTURE FILE, READ IN PLACE AND NEVER WRITTEN:
`gates/ops_python_exec-fixtures.rows`, 153 records. ONE FIXTURE AT A TIME: the
brief's machine rule, and the executor's 606 MB peak RSS is why.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "execfix"))

import census as EX  # noqa: E402


def main():
    exe = pathlib.Path(sys.argv[1]).resolve()
    dest = pathlib.Path(sys.argv[2])
    lo = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    hi = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
    fx = EX.fixtures()
    todo = [(i, f) for i, f in enumerate(fx) if lo <= i < hi]
    rows = []
    import tempfile
    with tempfile.TemporaryDirectory(prefix="vslane-census-") as td:
        td = pathlib.Path(td)
        for i, (n, a, p) in todo:
            print(f"# {i} {n}", file=sys.stderr, flush=True)
            rows.extend(EX.run_one(exe, td, n, a, p))
    with dest.open("a") as fh:
        fh.write("\n".join(rows) + "\n")
    print(f"# chunk [{lo},{hi}) of {len(fx)} fixtures -> {len(rows)} rows appended to {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
