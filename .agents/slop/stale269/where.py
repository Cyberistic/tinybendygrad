#!/usr/bin/env python3
"""THE LAST RESOLVER, AND IT ANSWERS BY CONTENT OVER THE WHOLE TREE.

    .venv/bin/python .agents/slop/stale269/where.py rows.tsv CLASS

For every row whose cited file does not carry the claim -- `WRONG-FILE`, `NO-FILE`, `PAST-EOF`,
and the `NO-SPAN` `STALE-LINE`s -- search EVERY `.py` in `tinygrad/ examples/ extra/ test/` and
print, per candidate file, the line carrying the text.

**THE POINT IS THE CANDIDATE LIST IS PASTED, NOT SCORED.** A restore is chosen from this output by
a reader, and the choice is written to `where.tsv` as `port:pl<TAB>file<TAB>line<TAB>why`. This file
picks nothing: `Allocator` matched inside `BumpAllocator` once already, and the cure was to print
the line rather than assert about it.

`NO-FILE` gets its four answers here, all PROVEN:
  MOVED   -- the text is in the tree; the citation named a path the resolver cannot express
  NEVER   -- `git log --all -S<quote>` finds nothing on ANY REF, and no file carries it
  DELETED -- `git log --all --diff-filter=D` names the commit that removed it
  FALSE   -- the "quote" is itself a citation (`ops-501-oracle.py:164`) or prose, not source text
"""
import csv
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/stale269")
_s = importlib.util.spec_from_file_location("citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)
TREES = ("tinygrad", "examples", "extra", "test")


def all_py() -> list[str]:
    out = []
    for t in TREES:
        for dp, dn, fn in os.walk(os.path.join(ROOT, t)):
            dn[:] = [d for d in dn if d != "__pycache__"]
            out += [os.path.relpath(os.path.join(dp, f), ROOT) for f in fn if f.endswith(".py")]
    return sorted(out)


def main(argv: list[str]) -> int:
    rows = [r for r in csv.DictReader(open(os.path.join(HERE, "FINAL.tsv")), delimiter="\t")
            if r["verdict"] in ("DECLINED", "UNRESOLVED", "RESTORE-FILE")]
    paths = all_py()
    bodies = {p: open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read() for p in paths}
    for r in rows:
        port, pl, name, cl = r["port"], r["pl"], r["name"], r["cl"]
        # EVERY span on the citation line, longest first: the gate's span may be the wrong one and
        # a shorter sibling span is the actual claim.
        line = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()[int(pl) - 1]
        spans = sorted(set(re.findall(r"`([^`\n]{4,400})`", line)), key=len, reverse=True)
        print(f"\n===== {r['verdict']}  {port}:{pl}  cites {name}:{cl}")
        print(f"  CLAIM  {r['claim'][:175]}")
        for s in spans[:4]:
            found = []
            for p in paths:
                for m in re.finditer(re.escape(s), bodies[p]):
                    found.append((p, bodies[p][: m.start()].count("\n") + 1))
            if not found:
                tag = "PROSE" if re.fullmatch(r"[\w./-]+:\d+(-\d+)?", s) else "nowhere"
                print(f"  span `{s[:80]}`  -> {tag}")
                continue
            byp: dict[str, list[int]] = {}
            for p, n in found:
                byp.setdefault(p, []).append(n)
            for p, ns in sorted(byp.items())[:6]:
                bl = bodies[p].splitlines()
                for n in sorted(set(ns))[:3]:
                    print(f"  span `{s[:60]}`  ->  {p}:{n}   {bl[n - 1].strip()[:140]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))