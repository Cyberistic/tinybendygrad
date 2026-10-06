#!/usr/bin/env python3
"""The gap between the corpus and `WANT`, by name, with the BEND ARM status of each.

    usage: .venv/bin/python .agents/slop/corpuswire2/armcensus.py

Populations, all by DISCOVERY (AGENTS.md doctrine 1):
  * corpus  `graphcmp.GRAPHS`                 -- imported by path, the generator's own dict
  * table   `differ.WANT`                     -- imported by path
  * armed   the names `graphcmp.bend`'s `rows.pick3` dispatches to their own `g_*` fixture;
            an unknown name falls through the bottom rung to `g_matmul()`, so an UNARMED
            graph is rendered with MATMUL's nodes -- a disagreement of the DISPATCHER.
No number is typed; the corpus is written by another unit and moves.
"""
from __future__ import annotations
import importlib.util
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]


def _load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def armed() -> set[str]:
    """The graph names `rows.pick3` names in a `String.eq(name, "X")` rung."""
    src = (ROOT / ".agents/slop/graphcmp.bend").read_text()
    body = src.split("def rows.pick3", 1)[1].split("def rows.pick(", 1)[0]
    return set(re.findall(r'String\.eq\(name,\s*"([^"]+)"', body))


def main() -> int:
    gc = _load("gc_corpus", ".agents/slop/graphcmp.py")
    differ = _load("differ_want", "checks/differ.py")
    corpus = sorted(gc.GRAPHS)
    want = set(differ.WANT)
    arm = armed()
    gap = [g for g in corpus if g not in want]
    fallthrough = [g for g in corpus if g not in arm]

    print(f"corpus  graphcmp.GRAPHS     : {len(corpus)}")
    print(f"table   differ.WANT         : {len(want)}")
    print(f"armed   rows.pick3 rungs    : {len(arm)}")
    print(f"WANT but not in corpus      : {sorted(want - set(corpus))}")
    print(f"THE GAP: corpus not in WANT : {len(gap)}")
    for g in gap:
        print(f"  {g:<16} {'ARMED' if g in arm else 'NO ARM -> substitutes g_matmul()'}")
    print(f"\nUNARMED over the WHOLE corpus ({len(fallthrough)}): "
          f"{' '.join(fallthrough)}")
    print("  matmul is the bottom rung itself; allred cdiv late are IN WANT as DISAGREE and")
    print("  unarmed -- the matmul substitution; custom_function mselect mstack stage are the")
    print("  four that substitute and have no row.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
