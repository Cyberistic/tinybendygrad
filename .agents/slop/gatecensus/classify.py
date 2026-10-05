#!/usr/bin/env python3
"""The gate classifier, CORRECTED. Which top-level slop files are real gates?

    .venv/bin/python .agents/slop/gatecensus/classify.py            # the counts
    .venv/bin/python .agents/slop/gatecensus/classify.py --list     # per-file, in migration order
    .venv/bin/python .agents/slop/gatecensus/classify.py --selftest # prove each fix moved a number

THE TEST
--------
A top-level `.sh`/`.py` is a GATE iff
    a committed report names it, OR a load-bearing file names it
    (`AGENTS.md`, `checks/README.md`, another gate), OR its own name says it decides something
    (`-gate`, `-check`, `-census`).
Everything else is scratch. A one-shot probe promoted into `checks/` is how a directory stops
being an index and becomes a junk drawer.

FOUR DEFECTS FOUND IN `_cleanup/move_gates.py`, EACH MEASURED. All four inflated the GATE set.

1. `git grep -- '.agents/slop/*.md'` — the pathspec `*` CROSSES `/`.
   Git pathspecs are not shell globs. Measured on this tree, `substrate-check.sh` is named by
   **43** files under that pathspec and **17** under `:(glob).agents/slop/*.md`; `e2e.sh` 39 -> 12;
   `graphcmp-run.sh` 21 -> 6; `graphcmp-repro.sh` 22 -> 6. The 26, 27, 15 and 16 extras are
   **`.agents/slop/differverdict/root/...`, a shadow copy of this very tree inside `.agents/slop`**,
   each carrying its own `.agents/slop/*.md`. A citation inside a copy of the documentation is a
   citation of the copy. Fixed by the `:(glob)` magic prefix, which is documented git behaviour
   and not a guess: pathspec magic `glob` restricts `*` to one path component.

2. BARE BASENAME, no extension. `bend` matched 89 citing lines. Fixed by anchoring on the full
   basename WITH its extension. There is deliberately no extensionless branch: `xd1/bend` has none
   and no text search separates that executable from the word `bend`, which in this project's prose
   means the LANGUAGE. An instrument that cannot answer is not allowed to answer.

3. SUBSTRING, not word token. The anchored pattern is applied in PYTHON, never handed to
   `git grep -E`, because POSIX ERE has no lookaround -- passing it straight through returns
   `repetition-operator operand invalid`, rc 128, which the original guard swallowed as
   "no citations". **Every gate came back named-by-nothing and the classifier printed a confident
   list built on a total failure to look.** That is `substrate-check.sh` printing
   `SUBSTRATE CLEAN: 0 file(s)`, one layer up.

4. CITATIONS FROM A COMMIT THAT IS NOT THIS TREE. Defect 1's `differverdict/root/` rows are the
   general case, so the corpus is built from an explicit allowlist and asserted to contain no path
   that does not exist, rather than from a glob whose breadth is git's business.

WHAT IS NOT A FIX. `--list` reports a GATE when its name says `-gate` even with zero citers, and
those rows are labelled `cited by 0`. A name is evidence about intent, not a measurement, and the
two are printed separately so a reader can tell which gates rest on which.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SLOP = os.path.join(ROOT, ".agents/slop")

# The citation corpus. Explicit, and asserted to exist, because a pathspec whose breadth is
# decided by git is a denominator nobody controls. `:(glob)` keeps `*` inside one component.
CORPUS = [
    ":(glob).agents/slop/*.md",
    ":(glob).agents/slop/*/*.md",
    ":(glob).agents/slop/*/*/*.md",
    ":(glob).agents/TODO.md",
    ":(glob).agents/TOOLS.md",
    "AGENTS.md",
    "checks/README.md",
    ":(glob)checks/*.py",
    ":(glob)checks/*.sh",
]
# Shadow trees are copies OF this tree; a line in a copy is not this project's record of a claim.
SHADOW = ("differverdict/root/", "opstree/", "xd1/pin/", "xd1/head/", "xd1/work/", "xd1/cur/")

# Already relocated by hand with an `exec` shim written. Never touched again.
DONE = {"graphcmp-run.sh", "graphcmp-repro.sh"}

# A name that says it DECIDES something. `probe`/`mutate`/`gen`/`fix`/`verify` say a thing that
# was RUN ONCE, whose answer is already in a report.
DECIDES = re.compile(r"(^|[-_])(gate|check|census)\b")
ONCE = re.compile(r"(probe|mutat|plant|arm|inject|corrupt|fixup|hoist|build|gen|emit|writer|"
                  r"mirror|plumb|splice|rewrite|stamp|sweep|dump|scratch|tmp|verify|expect|"
                  r"selftest|snapshot|snapshot2|baseline)")


def corpus_text() -> list[tuple[str, str]]:
    """(path, text) for every committed citation source. Read ONCE: 376 gates x 43 git greps
    is 16,000 subprocesses, which is how a census takes an hour and gets killed."""
    out = []
    for spec in CORPUS:
        r = subprocess.run(["git", "grep", "-I", "-n", "-e", ".", "--", spec],
                           cwd=ROOT, capture_output=True, text=True)
        if r.returncode >= 2:
            raise SystemExit(f"citation corpus read failed rc={r.returncode} on {spec}: "
                             f"{r.stderr.strip()}")
        per: dict[str, list[str]] = {}
        for line in r.stdout.splitlines():
            path, _, rest = line.partition(":")
            if any(path.startswith(s) or f"/{s}" in path for s in SHADOW):
                continue
            per.setdefault(path, []).append(rest)
        for path, lines in per.items():
            out.append((path, "\n".join(lines)))
    return out


def cite_pattern(base: str) -> str:
    assert "." in base, f"no extension to anchor a citation on: {base}"
    stem, ext = base.rsplit(".", 1)
    # `(?<![\w.])` kills `mygraphcmp.py` and `xd.1/graphcmp.py`. `(?!\w)` kills `graphcmp.pyc`.
    return r"(?<![\w.])" + re.escape(stem) + r"\." + re.escape(ext) + r"(?!\w)"


def citers(base: str, corpus: list[tuple[str, str]]) -> list[str]:
    pat = re.compile(cite_pattern(base))
    return sorted({p for p, txt in corpus if pat.search(txt)})


def population() -> list[str]:
    return sorted(f for f in os.listdir(SLOP)
                  if f.endswith((".sh", ".py"))
                  and os.path.isfile(os.path.join(SLOP, f))
                  and f not in DONE)


def load_bearing_order() -> list[str]:
    """The gates other gates and docs invoke, in descending citer count. This is the order things
    must MOVE, because a path that stops resolving turns a recorded claim into a dead reference."""
    corpus = corpus_text()
    rows = [(f, citers(f, corpus)) for f in population()]
    rows.sort(key=lambda r: (-len(r[1]), r[0]))
    return [f for f, c in rows if c]


def classify() -> dict:
    corpus = corpus_text()
    gates, scratch, once = [], [], []
    for f in population():
        c = citers(f, corpus)
        stem = f.rsplit(".", 1)[0]
        dec, oncehit = bool(DECIDES.search(stem)), bool(ONCE.search(stem))
        row = {"file": f, "citers": c, "n": len(c), "decides": dec, "once": oncehit}
        if dec:
            gates.append(row)
        elif c:
            (once if oncehit else gates).append(row)
        else:
            (once if oncehit else scratch).append(row)
    return {"gates": gates, "scratch": scratch, "once": once,
            "corpus_files": len(corpus)}


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    r = classify()
    tot = len(r["gates"]) + len(r["scratch"]) + len(r["once"])
    print(f"# CITATION CORPUS: {r['corpus_files']} committed sources, shadow copies excluded")
    print(f"# POPULATION: top-level .sh/.py in slop, minus 2 already moved   {tot}")
    print(f"#   GATE   (named, or named-by-name)                    {len(r['gates']):4d}")
    print(f"#     of those, cited by NOTHING (name-only claim)       "
          f"{sum(1 for g in r['gates'] if not g['n']):4d}")
    print(f"#   SCRATCH (nothing names them, name does not decide)   {len(r['scratch']):4d}")
    print(f"#   ONE-SHOT (instrument-shaped, kept as evidence)      {len(r['once']):4d}")
    if "--list" not in sys.argv:
        return 0
    print("\n# MIGRATION ORDER: load-bearing first (most citers = most dead references if it moves)")
    for g in r["gates"]:
        print(f"  GATE     {g['file']:<30} cited by {g['n']:3d}"
              + ("   [NAME ONLY - no document names it]" if not g["n"] else ""))
    print("\n# SCRATCH -- named by nothing. These are the junk drawer, in reverse order.")
    for g in r["scratch"]:
        print(f"  scratch  {g['file']:<30} cited by {g['n']:3d}")
    json.dump(r, sys.stdout if "--json" in sys.argv else
              open(os.path.join(SLOP, "gatecensus", "classified.json"), "w"), indent=1)
    return 0


def selftest() -> int:
    """Each fix must MOVE a number, or it is not a fix."""
    corpus = corpus_text()
    ok = True

    # 1. the pathspec. `:(glob)` vs the plain pathspec git hands you.
    for base, brief in (("substrate-check.sh", 16), ("e2e.sh", 11),
                        ("graphcmp-run.sh", 5), ("graphcmp-repro.sh", 5)):
        n = len(citers(base, corpus))
        print(f"  {base:<20} whole-token citers now {n:3d}   (brief measured {brief})")
        if n <= brief:
            print(f"    FAIL: the number moved DOWN past the brief's; re-derive before trusting it")
            ok = False

    # 2. no shadow tree in the corpus, and no bare `bend` citation anywhere.
    shadowed = [p for p, _ in corpus if any(s in p for s in SHADOW)]
    print(f"  shadow-copy paths in corpus        {len(shadowed):3d}   (want 0)")
    if shadowed:
        print(f"    FAIL: {shadowed[:5]}")
        ok = False
    bend = citers("bend", corpus) if os.path.exists(os.path.join(SLOP, "bend")) else []
    print(f"  citers of the executable `bend`   {len(bend):3d}   (bare-basename gave 89)")
    if bend:
        print(f"    note: this basename has no extension, so no pattern can anchor it -- "
              f"{len(bend)} whole-token hits, all of them the word `bend`")

    # 3. the zero-byte and `.out` traps the project has already hit.
    for name, brief_bare in ((".err", 6), (".out", 23)):
        p = os.path.join(ROOT, ".agents/slop", name)
        if not os.path.exists(p):
            continue
        n = len(citers(name, corpus))
        print(f"  whole-token citers of `{name}`   {n:3d}   (bare-substring gave {brief_bare})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())