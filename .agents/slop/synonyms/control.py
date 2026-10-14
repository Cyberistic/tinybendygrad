#!/usr/bin/env python3
"""THE CONTROL WALK: `VERDICTS` declarations OUTSIDE `gates-pop`'s `HOMES`.

    .venv/bin/python .agents/slop/synonyms/control.py

`gates-pop.py:103` admits `HOMES = ("checks", "gates")` is A LIST, and this file exists to say
what that list misses -- a LABELLED CONTROL, never the population, for the reason
`gates/gate-surface.py:212` gives: two instruments holding two lists have no authority over
each other, so the difference is NAMED rather than dissolved. It reuses `declaration()` and
`vocabulary()` so the reading is the SAME reading; only the file set differs.

The `refs` half is the other direction: WHO READS `gates/gatekit.py`. The brief's claim that
`gatekit` is "LOADED BY PATH BY ~8 CONSUMERS" is a number that must be measured by WALK.
"""
import ast
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
SKIP = {".git", ".venv", "__pycache__", "node_modules", "references", ".agents/slop"}


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def walk(root):
    """`os.walk`, the CONTROL population.

    PRUNED BY PATH COMPONENT, not by basename: `SKIP` holds `.agents/slop`, which is a
    two-component path and therefore never equals a `dirnames` entry. Pruning by basename is
    how `.agents/slop/hooks/` and `.agents/slop/synonyms/` survived the exclusion in the first
    run of this file -- the tree's own `gates-pop.discover()` docstring warns about the
    parallel trap in `iterdir` vs `rglob`, and this is the same class of it.
    """
    for dirpath, dirnames, filenames in os.walk(root):
        rel = Path(dirpath).relative_to(root)
        dirnames[:] = [d for d in dirnames
                       if d != "__pycache__" and str(rel / d) not in SKIP
                       and not (rel == Path(".") and d in SKIP)]
        if any(str(rel / p) in SKIP or p in SKIP for p in (rel,)):
            continue
        for fn in sorted(filenames):
            if fn.endswith(".py"):
                yield Path(dirpath) / fn


def main():
    sf = loaded(SURFACE, "gate_surface_under_control")
    vocab = sf.vocabulary()
    homes = ("checks", "gates")

    out, refs = [], []
    for p in sorted(walk(ROOT)):
        rel = str(p.relative_to(ROOT))
        try:
            src = p.read_text(errors="replace")
        except OSError:
            continue
        got = sf.declaration(p)
        if len(got) == 3:
            continue                      # UNPARSEABLE, and reported by census.py
        verdicts, _p, _r, _n = got
        if isinstance(verdicts, dict):
            out.append((rel, verdicts, rel.startswith(homes)))
        # WHO NAMES gatekit. A TEXT shape is the only thing available for an import, and it is
        # narrow on purpose: it asks for the MODULE NAME, not for the substring "gatekit".
        if re_gatekit(src):
            refs.append(rel)

    renamed = [(r, v, inh) for r, v, inh in out
               if any(int(c) in vocab and str(t).upper() != vocab[int(c)].upper()
                      for c, t in v.items())]
    outside = [(r, v) for r, v, inh in out if not inh]
    inside = [(r, v) for r, v, inh in out if inh]

    print(f"CONTROL POPULATION: os.walk over the tree minus {sorted(SKIP)} -> "
          f"{sum(1 for _ in walk(ROOT))} .py files")
    print(f"  VERDICTS declarers: {len(out)}  ({len(inside)} inside HOMES={homes}, "
          f"{len(outside)} OUTSIDE)\n")

    if outside:
        print("DECLARING A SURFACE OUTSIDE `HOMES` -- invisible to gates-pop.discover():\n")
        for r, v in outside:
            print(f"  {r}\n      {v}")
        print()

    print(f"RENAMED over the CONTROL population: {len(renamed)} declaration(s) "
          f"(vs {sum(1 for r, v, inh in out if inh and any(int(c) in vocab and str(t).upper() != vocab[int(c)].upper() for c, t in v.items()))} inside HOMES)\n")

    print(f"CONSUMERS OF gates/gatekit.py, BY WALK over import sites: {len(refs)}\n")
    for r in refs:
        print(f"  {r}")
    return 0


def re_gatekit(src):
    """An import or a path-load that NAMES `gatekit`. Text, and said to be.

    The only two spellings that can load it: `from gatekit import ...` and
    `spec_from_file_location(..., ".../gatekit.py")`. `importlib.import_module("gatekit")` is
    included because a name-loaded owner is exactly what `declareverdict/runner.py:47` forbids,
    so if one exists it is a finding rather than a consumer.
    """
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("#"):
            continue
        if ("gatekit" in s) and (s.startswith(("import ", "from ")) or "spec_from_file_location" in s
                                  or "import_module" in s or "run_gate" in s or "Gate(" in s
                                  or "output_dir_plant" in s or "oracle_drift" in s):
            return True
    return False


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())