#!/usr/bin/env python3
"""Locate the NAMED re-derivable counts in the three surfaces, by PRECISE anchor.

The anchors are the re-derivation rules themselves (each names the instrument that
computes the value).  The population is every line in the surfaces that MATCHES an
anchor -- discovered by applying them, never listed.  Each occurrence is DATED or
LIVE by its own line (date / clock / past cue).

Anchors are `(claim, current_value, pattern)`; `current` is what
`.agents/slop/citeresolve/counts.py` computes today.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SURFACES = ("AGENTS.md", ".agents/TOOLS.md", ".agents/TODO.md")

DATE = re.compile(r"20\d\d-\d\d-\d\d")
CLOCK = re.compile(r"\b\d{1,2}:\d\d\b")
PAST = re.compile(
    r"\b(used to|before|earlier|previously|historical|no longer|had been|prior|"
    r"was \d|were \d|deleted|retired|pruned|superseded|renamed|old(?:ly)?|"
    r"read(?:s)? \d|at the parent|frozen|stale|replaced)\b", re.I)

ANCHORS = [
    ("no-txt HARD",        "0",   r"\b550\b.*\bHARD\b"),
    ("no-txt EXCUSED",     "178", r"\b139\b.*EXCUSED\b"),
    ("differ.declared()",  "175", r"len\(`?differ\.declared|differ\.declared\(\)`?`?\s*=\s*\*\*139|the \*\*139\*\* `.txt` names|139 (?:`?\.txt`?|names) (?:on disk|there)"),
    ("gates py",           "54",  r"(?:21|54)\s*`?\.py`?[^\n]*\b0\s*`?\.sh"),
    ("substrate.py",       "936", r"checks/substrate\.py.*(?:766|841|936)|(?:766|841|936)\s+lines at"),
    ("mutate harnesses",   "14",  r"(?:9 \+ 7|16|14).{0,40}survive|survive at 2026"),
    ("TOOLS paths",        "333", r"\b333\b"),
    ("TOOLS present",      "164", r"\b(?:153|160|164)\b\s*(?:are )?present|present[^\n]*\b(?:153|160|164)\b"),
    ("TOOLS gone",         "169", r"\b(?:180|173|169)\b\s*(?:are )?gone|gone[^\n]*\b(?:180|173|169)\b"),
    ("TOOLS gone slop",    "85",  r"\b(?:96|85)\b.*(?:under|of th).*slop|slop[^\n]*\b(?:96|85)\b"),
    ("gone instruments",   "6",   r"\b(?:14|16)\b[^\n]*INSTRUMENTS|INSTRUMENTS[^\n]*\b(?:14|16)\b"),
    ("port .bend",         "134", r"\b134\b|\b138\b.{0,30}\.bend|\.bend.{0,30}\b138\b"),
    ("census .bend",       "134", r"43 of (?:138|134)|(?:138|134) under 50 MB"),
    ("tracked REPORT.md",  "116", r"\b116\b"),
    ("checks sh",          "17",  r"17 `?checks/\*\.sh`?|`?checks/\*\.sh`?.{0,10}17"),
    ("corpus graphs",      "34",  r"\b(?:25|34)\b[\s-]*graph"),
    ("oracle-selfcheck",   "OK",  r"oracle-selfcheck[^\n]{0,60}"),
    ("e2e skip exit",      "4",   r"RETURNS? 4, NOT 0|exit 4"),
    ("viz README lines",   "93",  r"(?:93)\s*lines"),
    ("PCIDevice files",    "8",   r"\b8 files\b|rg -l 'PCIDevice'"),
]


def kind(line: str) -> str:
    return "DATED" if (DATE.search(line) or CLOCK.search(line) or PAST.search(line)) else "LIVE"


def main() -> int:
    print("claim\tcurrent\tsurface\tline\tkind\tsource_line")
    counts = {"LIVE": 0, "DATED": 0}
    for claim, cur, pat in ANCHORS:
        rx = re.compile(pat, re.I)
        for rel in SURFACES:
            with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if rx.search(line):
                        k = kind(line)
                        counts[k] += 1
                        print(f"{claim}\t{cur}\t{rel}\t{i}\t{k}\t{line.strip()[:180]}")
    print(f"# anchor hits: LIVE={counts['LIVE']} DATED={counts['DATED']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
