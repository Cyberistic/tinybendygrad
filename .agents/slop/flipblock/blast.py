#!/usr/bin/env python3
"""FLIPBLOCK blast radius, by DISCOVERY (doctrine 1).

Population: every `.bend` under `tinybendygrad/`, found by `os.walk` (a directory
walk, NOT a hand list and NOT a glob that returns [] when `.bend` is on disk).

Three classes, each a regex over the tree's OWN write sites:
  CONSTRUCT  a line that builds a node with `OpsFLIP` as its op.
  READER     a `def NAME(... O.Arg ...)` whose body arms on `O.ATuple` -- the
             marg readers a new bool-carrying Arg variant must teach.
  DISPATCH   a `case O.OpsFLIP` arm (where a FLIP's arg is routed).
Token-list occurrences (`OpsFLIP{}` inside a `List<Op>`) are NOT construction and
are reported separately so the count is not inflated.
"""
from __future__ import annotations

import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "tinybendygrad")

NEW = re.compile(r"OpsFLIP\{\}")
DEF = re.compile(r"^def\s+([A-Za-z0-9_.]+)\s*\(")
ARG_PARAM = re.compile(r":\s*O\.Arg\b|O\.Arg\s*[,)]")
TUPLE_ARM = re.compile(r"case\s+O\.ATuple\{")
FLIP_CASE = re.compile(r"case\s+O\.OpsFLIP\{")


def walk() -> list[str]:
    out: list[str] = []
    for base, _dirs, files in os.walk(ROOT):
        for f in files:
            if f.endswith(".bend"):
                out.append(os.path.join(base, f))
    return sorted(out)


def classify(path: str) -> dict[str, list[int]]:
    hits: dict[str, list[int]] = {"construct": [], "reader": [], "dispatch": [], "tokenlist": []}
    cur_is_reader = False
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            m = DEF.match(line)
            if m:
                cur_is_reader = bool(ARG_PARAM.search(line))
            if NEW.search(line):
                if ".new(" in line or "UOp.new" in line:
                    hits["construct"].append(n)
                else:
                    hits["tokenlist"].append(n)
            if cur_is_reader and TUPLE_ARM.search(line):
                hits["reader"].append(n)
            if FLIP_CASE.search(line):
                hits["dispatch"].append(n)
    return hits


def main() -> None:
    files = walk()
    rel = lambda p: os.path.relpath(p, os.path.dirname(__file__)).replace("\\", "/")
    print(f"# population: {len(files)} .bend under tinybendygrad/ (os.walk)")
    print("file\tconstruct\treader\tdispatch\ttokenlist")
    totals = {"construct": 0, "reader": 0, "dispatch": 0, "tokenlist": 0}
    touched: set[str] = set()
    for p in files:
        h = classify(p)
        for k, v in h.items():
            totals[k] += len(v)
        if h["construct"] or h["reader"]:
            touched.add(rel(p))
        print(f"{rel(p)}\t{','.join(map(str,h['construct'])) or '-'}\t"
              f"{','.join(map(str,h['reader'])) or '-'}\t"
              f"{','.join(map(str,h['dispatch'])) or '-'}\t"
              f"{','.join(map(str,h['tokenlist'])) or '-'}")
    print(f"# TOTAL construct={totals['construct']} reader={totals['reader']} "
          f"dispatch={totals['dispatch']} tokenlist={totals['tokenlist']}")
    print(f"# FILES constructing or reading a FLIP arg: {len(touched)} -> {sorted(touched)}")


if __name__ == "__main__":
    main()
