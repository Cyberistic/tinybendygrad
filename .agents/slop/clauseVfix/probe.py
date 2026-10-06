#!/usr/bin/env python3
"""Clause V's THREE numbers, computed under BOTH algorithms on the SAME tree.

NEW = the code as it stands: `gates/gendirs.py:481` `git ls-tree -r HEAD`, consumed by
`retention-check.py:443` `gendirs.table()`.
OLD = the pre-705e7a644 algorithm, reproduced verbatim from gendirs' own docstring
(`ls-files -s`, field 1 = SHA) -- the code the emptyblob unit measured at c53ace4e8.

It imports the LIVE `gates/gendirs.py` for NEW, so this is not a copy that can drift.
"""
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GIT_EMPTY_BLOB = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def load_gendirs():
    p = ROOT / "gates" / "gendirs.py"
    spec = importlib.util.spec_from_file_location("gendirs", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def old_tracked_dirs():
    """The pre-repair algorithm: `ls-files -s`, compare SHA field. This is the INDEX."""
    out, empty = {}, {}
    for line in git("ls-files", "-s").splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) < 2:
            continue
        sha = parts[1]
        d = os.path.dirname(path)
        out[d] = out.get(d, 0) + 1
        if sha == GIT_EMPTY_BLOB:
            empty[d] = empty.get(d, 0) + 1
    return ({d: n for d, n in out.items() if d and n},
            {d: n for d, n in empty.items() if n})


def main():
    g = load_gendirs()
    rows = g.table()                       # NEW, exactly what clause V consumes
    old_all, old_empty = old_tracked_dirs()
    rows_old = {r["dir"]: r for r in rows}

    print("=== clause V's three numbers, OLD (index, ls-files -s) vs NEW (HEAD, ls-tree) ===")
    print(f"{'number':34} {'OLD/index':>12} {'NEW/HEAD':>12}")
    old_census_n = sum(old_all.get(r['dir'], 0) for r in rows)
    new_census_n = sum(r['n_tracked'] for r in rows)
    old_census_dirs = sum(1 for r in rows if old_all.get(r['dir'], 0))
    new_census_dirs = sum(1 for r in rows if r['n_tracked'])
    old_empty_n = sum(old_empty.get(r['dir'], 0) for r in rows)
    new_empty_n = sum(r['n_empty_blob'] for r in rows)
    print(f"{'CENSUS entries':34} {old_census_n:>12} {new_census_n:>12}")
    print(f"{'CENSUS dirs indexed':34} {old_census_dirs:>12} {new_census_dirs:>12}")
    print(f"{'CENSUS entries at EMPTY BLOB':34} {old_empty_n:>12} {new_empty_n:>12}")

    ign = g.ignored(sorted(r["dir"] for r in rows))
    contrad_old = [r['dir'] for r in rows if old_all.get(r['dir'], 0) and ign.get(r['dir'])]
    contrad_new = [r['dir'] for r in rows if r['n_tracked'] and ign.get(r['dir'])]
    print(f"{'IGNORED-BUT-INDEXED dirs':34} {len(contrad_old):>12} {len(contrad_new):>12}")

    print("\n=== per-dir lines that MOVE (OLD != NEW), sorted by |delta entries| ===")
    moves = []
    for r in rows:
        o_n, n_n = old_all.get(r['dir'], 0), r['n_tracked']
        o_e, n_e = old_empty.get(r['dir'], 0), r['n_empty_blob']
        if (o_n, o_e) != (n_n, n_e):
            moves.append((r['dir'], o_n, n_n, o_e, n_e))
    for d, o_n, n_n, o_e, n_e in moves:
        print(f"  {d:52} entries {o_n:>4}->{n_n:<4}  empty {o_e:>4}->{n_e:<4}")
    if not moves:
        print("  (none -- the two algorithms agree everywhere on this tree)")
    print(f"MOVED DIRS: {len(moves)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
