#!/usr/bin/env python3
"""THE CENSUS, ON A NAMED SUBSET. `.agents/slop/execfix/census.py`'s OWN runner.

    .venv/bin/python .agents/slop/vslane/subset.py <exe> <out.rows> <fixture> [<fixture> ...]

THE FULL CENSUS IS 153 FIXTURES AND 27 MINUTES (MEASURED), WHICH IS TOO SLOW
TO ITERATE ON. THIS RUNS THE TREE'S OWN `execfix/census.py:run_one` — the same
reader, the same spelling, the same one-process-per-fixture contract — ON A
NAMED SUBSET. THE POPULATION IS STILL THE TREE's OWN FIXTURE FILE, READ IN
PLACE; A SUBSET IS A SUBSET OF IT AND INVENTS NOTHING.

THE SUBSET IS WRITTEN DOWN IN `SUBSETS` BELOW, BY NAME, AND THE NAMES ARE THE
TREE's OWN FIXTURE NAMES -- so a name that is not a fixture is a refusal, not a
silent skip.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3] / ".agents" / "slop" / "execfix"))
import census  # noqa: E402

# THE 29 PINNED NAMES, DERIVED FROM THE TREE's OWN PINS FILE -- NOT TYPED HERE.
PINS = pathlib.Path(__file__).resolve().parents[3] / "gates" / "ops_python_exec-pins.rows"


def pinned_names():
    out = []
    for ln in PINS.read_text().splitlines():
        if ln.strip() and not ln.startswith("#"):
            out.append(ln.split()[0].rsplit(".b", 1)[0])
    return out


def main():
    exe = pathlib.Path(sys.argv[1]).resolve()
    dest = pathlib.Path(sys.argv[2])
    want = sys.argv[3:] or pinned_names()
    have = {n for n, _, _ in census.fixtures()}
    missing = [w for w in want if w not in have]
    if missing:
        print(f"# REFUSED: {len(missing)} names are not fixtures: {missing[:8]}", file=sys.stderr)
        return 3
    rows = []
    import tempfile
    with tempfile.TemporaryDirectory(prefix="vslane-census-") as td:
        td = pathlib.Path(td)
        for n, a, p in census.fixtures():
            if n not in want:
                continue
            rows.extend(census.run_one(exe, td, n, a, p))
    dest.write_text("\n".join(sorted(rows)) + "\n")
    print(f"# {len(want)} fixtures, {len(rows)} rows -> {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
