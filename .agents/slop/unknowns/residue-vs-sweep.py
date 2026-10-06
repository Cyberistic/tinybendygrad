#!/usr/bin/env python3
"""Where the two instruments now disagree, counted; whether a citer is a `COPY`; and how big the
committed-vs-working corpus gap is.

    usage: .venv/bin/python .agents/slop/unknowns/residue-vs-sweep.py

`checks/sweep.py` IS MINE AND `checks/residue.py` IS NOT. This file therefore READS residue, CALLS it,
and changes nothing: no `checks/*.py` is edited, no report is regenerated, and `residue.OUT` is never
written. Every number below is produced by residue's own functions over one walk of one tree.

**A SECOND INSTRUMENT THAT DISAGREES WITH THE FIRST IS WORTH MORE THAN A REPLACEMENT THAT AGREES WITH
NEITHER** -- so the disagreement is the output, not a defect to be reconciled. And the fifth verdict
CHANGES THE DENOMINATOR, which is the first thing to get right here: `residue.main` classifies only the
rows `sweep.verdict_for` called `DELETE`, so the moment `verdict_for` grows a verdict for "I cannot
tell", those rows leave residue's census entirely. Counting residue's own headline would therefore
MEASURE MY OWN EDIT. So this file classifies the UNION of rows, one instant, both instruments, and
reports the disagreement over all of them.

THE FOUR MEASUREMENTS, AND WHY EACH ONE EXISTS

    DISAGREE       `sweep` != `residue`, over every row, not just the ones sweep would destroy.
    G8             a CITATION is not a dependency if the thing doing the citing is itself a `COPY`.
                   One lookup against the twin map residue already computes, and it is the
                   discriminator a finished unit's row dumps need: a shadow tree names its own copies.
    COMMITTED      `committed_named_text()` reads `git show HEAD:` while the sweep runs against the
    VS WORKING     WORKING tree, so the citation index and the tree disagree by exactly the
                   UNCOMMITTED SET. Bounded ("6 of 174") and, as far as this project knows, UNQUANTIFIED.
    LIVE-UNITS     the measurement that says the list cannot be deleted on its own: of the files it
                   holds, how many the mtime window would hold anyway.
"""
from __future__ import annotations

import collections
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CHECKS = os.path.join(ROOT, "checks")


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(CHECKS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    sweep, residue = load("sweep"), load("residue")
    named = sweep.mentioned_filenames(sweep.committed_named_text())
    tracked = residue.git_tracked(ROOT)
    files = residue.walk(ROOT)
    age = residue.dir_ages(ROOT, files)
    auth = residue.authorities()
    facts = sweep.facts()
    now = time.time()

    # residue's own globals, so ONE walk feeds both instruments and neither re-reads the corpus.
    residue.SLOP, residue.RUNS = ".agents/slop", "runs"
    first = lambda rel, n: sweep.verdict_for(rel, n, facts)          # noqa: E731
    rows = [(rel, sz, first(rel, named)) for rel, sz in files]
    print(f"# {len(rows)} rows, {sum(sz for _r, sz, _v in rows) / 1048576:.1f} MB, "
          f"HEAD={subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()}"
          f", window 0m, at {time.strftime('%Y-%m-%dT%H:%M:%S')}")

    twins = residue.outside_twins(ROOT, tracked, rows)
    cites: dict[str, set[str]] = collections.defaultdict(set)
    for rel in sorted(tracked):
        if residue.excluded(rel):
            continue
        try:
            with open(os.path.join(ROOT, rel), "rb") as fh:
                residue.index_citations(cites, ROOT, rel, fh.read(4 << 20).decode("utf-8", "replace"))
        except OSError:
            continue

    # ---- 1. THE DISAGREEMENT, OVER EVERY ROW AND NOT JUST THE ONES SWEEP WOULD DESTROY.
    both = collections.Counter()
    detail: list[tuple[str, str, str, str]] = []
    for rel, sz, sw in rows:
        _f, v, why = residue.classify(ROOT, rel, sz, sweep_named=named, first_pass=first, auth=auth,
                                      age=age, window=0, twins=twins, cites=cites, tracked=tracked,
                                      disabled=set())
        pair = (sweep.bucket(sw), v)
        both[pair] += 1
        if pair[0] != pair[1]:
            detail.append((sw, v, rel, why))
    print(f"\n# 1. `sweep` vs `residue`, over ALL {len(rows)} rows (residue's own census sees only the "
          f"{sum(1 for _r, _s, v in rows if v == 'DELETE')}):")
    for (a, b), n in both.most_common():
        mark = "" if a == b else "   <-- DISAGREE"
        print(f"#   sweep={a:9s} residue={b:9s} {n:5d}{mark}")
    print(f"#   DISAGREE ON {sum(n for (a, b), n in both.items() if a != b)} of {len(rows)} rows")
    doomed = [n for (a, b), n in both.items() if a == "DELETE"]
    contested = sum(n for (a, b), n in both.items() if a == "DELETE" and b != "DELETE")
    print(f"#   of the {sum(doomed)} rows `sweep` would DELETE, residue dissents on {contested}"
          f" -- i.e. the two instruments agree about DELETING {sum(doomed) - contested} rows")
    res_only = collections.Counter(v for sw, v, _r, _w in detail
                                   if sweep.bucket(sw) == "UNKNOWN")
    print(f"#   and where sweep now says UNKNOWN, residue says: "
          f"{dict(res_only.most_common()) or 'NOTHING -- the two agree on every one of them'}")

    # ---- 2. G8: IS THE CITER ITSELF A COPY?
    # A citation is a claim that SOMEBODY DEPENDS ON THIS FILE. A shadow tree, a staged blob and a
    # finished unit's `slopcopies/` all CITE their own copies, and `residue.outside_twins` already
    # knows which files are byte-identical to something outside the residue -- so the discriminator is
    # one lookup, and the question it answers is the one the whole corpus is blind to by construction.
    copied = {r for r, ts in twins.items() if ts}
    cited_rows = [rel for rel, _sz, sw in rows if sweep.bucket(sw) == "KEEP-CITED"]
    facets = collections.Counter()
    for rel in cited_rows:
        who = cites.get(os.path.basename(rel), set())
        inside = {c for c in who if residue.in_residue(c)}
        if not who:
            facets["no citer in residue's index at all"] += 1
            continue
        if who <= copied:
            facets["EVERY citer is a COPY -- G8 as specified"] += 1
        if inside:
            facets["at least one citer is INSIDE the residue"] += 1
        if who <= inside:
            facets["EVERY citer is inside the residue"] += 1
        if who <= copied | inside:
            facets["every citer is a copy or inside the residue"] += 1
    print(f"\n# 2. G8 -- IS THE CITER ITSELF A `COPY`?")
    print(f"#   rows `sweep` keeps as KEEP-CITED: {len(cited_rows)}")
    for k, n in facets.most_common():
        print(f"#     {k:48s} {n:5d} rows")
    print("#   A CITATION IS A CLAIM THAT SOMEBODY DEPENDS ON THIS FILE. A shadow tree, a staged blob and\n"
          "#   a finished unit's `slopcopies/` all cite their OWN copies, so `every citer is a COPY` and\n"
          "#   `every citer is inside the residue` are two readings of one question. The first is the\n"
          "#   discriminator the prompt specifies; the second is the one this residue tree can see,\n"
          "#   because `checks/*.py` and `AGENTS.md` are outside it and are copies of nothing.")

    # ---- 3. COMMITTED vs WORKING. THE CITATION INDEX AND THE TREE DISAGREE BY THE UNCOMMITTED SET.
    corpus = subprocess.run(["git", "ls-files", "-z", "--"] + sweep.NAMED_BY, cwd=ROOT,
                            capture_output=True, text=True).stdout.split("\0")
    corpus = [c for c in corpus if c]
    dirty, gone = [], []
    work_only: set[str] = set()
    head_names: set[str] = set()
    for c in corpus:
        p = os.path.join(ROOT, c)
        if not os.path.exists(p):
            gone.append(c)
            continue
        at_head = subprocess.run(["git", "show", f"HEAD:{c}"], cwd=ROOT, capture_output=True,
                                 text=True, errors="replace")
        if at_head.returncode != 0:
            continue
        h = sweep.mentioned_filenames(at_head.stdout)
        w = sweep.mentioned_filenames(_read(p))
        head_names |= h
        work_only |= w - h
        if at_head.stdout != _read(p):
            dirty.append(c)
    extra = work_only - named
    print(f"\n# 3. `committed_named_text()` READS `git show HEAD:` AND THE SWEEP RUNS ON THE WORKING TREE")
    print(f"#   corpus files NAMED_BY tracks: {len(corpus)}   dirty in the worktree: {len(dirty)}"
          f"   tracked-but-deleted: {len(gone)}")
    print(f"#   filenames the corpus mentions at HEAD: {len(named)}")
    print(f"#   filenames a WORKING-TREE read would ADD: {len(extra)}"
          f"   and would REMOVE: {len(head_names - named)}")
    for n in sorted(extra)[:10]:
        row = [r for r, _s, _v in rows if os.path.basename(r) == n]
        print(f"#     +{n}  -> {row[0] if row else 'no residue row'}")
    for c in dirty[:10]:
        print(f"#     dirty: {c}")

    # ---- 4. LIVE_UNITS: WHY THE LIST CANNOT BE DELETED ON ITS OWN.
    lu = [rel for rel, _s, v in rows if v == "LIVE-UNIT"]
    in60 = [r for r in lu if age.get(os.path.dirname(r), 1e9) <= 60 * 60]
    print(f"\n# 4. LIVE_UNITS holds {len(lu)} rows. The 60-minute window would hold {len(in60)} of them "
          f"anyway;\n#   {len(lu) - len(in60)} would NOT be, so removing the list on its own exposes them."
          + " Proposal 2 says land the\n#   per-directory aggregation and the list in ONE change, and this is that "
          "measurement.")

    # ---- 5. `PROTECTED` RETURNS BEFORE THE CITATION TEST. HOW MUCH IS NEVER EVEN CLASSIFIED?
    prot = [rel for rel, _s, v in rows if v == "PROTECTED"]
    unclassifiable = [r for r in prot if facts.cites[0].get(os.path.basename(r))]
    print(f"\n# 5. PROTECTED returns before the citation test: {len(prot)} rows, of which "
          f"{len(unclassifiable)} ARE named by the corpus\n#   and so would be kept by the citation "
          f"test anyway -- an early return is a blind spot that looks like a decision.")
    return 0


def _read(p: str) -> str:
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


if __name__ == "__main__":
    sys.exit(main())
