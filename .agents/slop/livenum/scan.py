#!/usr/bin/env python3
"""Discover the LIVE-NUMBER population in the three owned surfaces.

A population by DISCOVERY, not a hand list: the rule below is the declaration,
and it is applied to every line of `AGENTS.md`, `.agents/TOOLS.md`,
`.agents/TODO.md` (read from the WORKING TREE, so the reading carries each file's
mtime, not a HEAD).

A NUMBER TOKEN is a *measure claim* if, on its line, it is bound to a unit noun
(files, lines, paths, rows, graphs, defs, dirs, ...) or an extension (`.py`,
`.sh`, `.bend`, `.txt`, `.rows`), or it is a progress fraction `n/m`, or an
`N of M` pair.  That is the whole declaration.

Each claim is DATED or LIVE by its CONTEXT WINDOW (the line plus one line either
side): DATED when the window carries a calendar date (`YYYY-MM-DD`), a clock
reading (`HH:MM`), or a past-tense cue (used to / before / earlier / previously /
historical / was NN / deleted / retired / no longer / had been / prior).  A LIVE
number is a claim about the tree AS IT IS and must re-derive; a DATED number is
EVIDENCE of what was true and MUST NOT be falsified by a later reading.

Emits TSV on stdout, counts on stderr.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SURFACES = ("AGENTS.md", ".agents/TOOLS.md", ".agents/TODO.md")

UNITS = (
    "files|lines|paths|rows|row|graphs|graph|defs|def|dirs|instances|survivors|"
    "present|gone|absent|missing|rules|arms|plants|zeros|mutations|tables|"
    "comments|chars|bytes|KB|MB|GB|us|ms|s|stages|lanes|names|tokens|probes|"
    "occs?|hits|drops|entries|keys|members|ops|markers|gates|checks|oracles|"
    "text|txt|bend|mutants|controls|hunks|wraps|graphs?"
)
EXT = r"\.(?:py|sh|bend|txt|rows|tsv|out|err|json|md|mjs|js|ts|lock)"
# a bound number: N <unit>  or  N <ext>  (unit may be separated by a short gap)
BOUND = re.compile(r"(?<![\w.])(\d{1,7})(?![\w.])\s*(?:`?)(?:" + UNITS + r"|" + EXT + r")\b", re.I)
FRAC = re.compile(r"\[[#. ]+\]\s*(\d+)/(\d+)")           # progress bar n/m
OF = re.compile(r"(?<![\w.])(\d{1,7})(?:,?\d{3})*\s+of\s+(\d{1,7})(?:,?\d{3})*\b")
DATE = re.compile(r"20\d\d-\d\d-\d\d")
CLOCK = re.compile(r"\b\d{1,2}:\d\d\b")
PAST = re.compile(
    r"\b(used to|before|earlier|previously|historical|no longer|had been|prior|"
    r"was \d|were \d|deleted|retired|pruned|superseded|renamed|old(?:ly)?|"
    r"read(?:s)? \d|at the parent|existed|appears? in (?:the )?history)\b",
    re.I,
)


def main() -> int:
    rows = []
    for rel in SURFACES:
        path = os.path.join(ROOT, rel)
        mtime = os.path.getmtime(path)
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
        for i, line in enumerate(lines, 1):
            win = "\n".join(lines[max(0, i - 2):i + 1])
            claims: list[str] = []
            for m in BOUND.finditer(line):
                claims.append(m.group(1))
            for m in FRAC.finditer(line):
                claims.append(f"{m.group(1)}/{m.group(2)}")
            for m in OF.finditer(line):
                n = m.group(1).replace(",", "")
                d = m.group(2).replace(",", "")
                claims.append(f"{n} of {d}")
            if not claims:
                continue
            kind = "DATED" if (DATE.search(win) or CLOCK.search(win) or PAST.search(win)) else "LIVE"
            for c in dict.fromkeys(claims):
                rows.append((rel, i, c, kind, line.strip()[:200]))
    print("surface\tline\tclaim\tkind\tsource_line")
    for r in rows:
        print("\t".join(str(x).replace("\t", " ") for x in r))
    from collections import Counter
    per = Counter((r[0], r[3]) for r in rows)
    print("# surfaces (line,kind counts):", file=sys.stderr)
    for rel in SURFACES:
        live = sum(1 for r in rows if r[0] == rel and r[3] == "LIVE")
        dated = sum(1 for r in rows if r[0] == rel and r[3] == "DATED")
        print(f"#   {rel}: LIVE={live} DATED={dated} total={live + dated}", file=sys.stderr)
    print(f"# TOTAL live={sum(1 for r in rows if r[3]=='LIVE')} "
          f"dated={sum(1 for r in rows if r[3]=='DATED')} claims={len(rows)}", file=sys.stderr)
    for rel in SURFACES:
        print(f"# mtime {rel} = {os.path.getmtime(os.path.join(ROOT, rel)):.0f}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
