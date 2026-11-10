#!/usr/bin/env python3
"""DO THE LEDGER's **TWO** BAR TABLES DISAGREE, AND WHERE?

THE CLASS. `.agents/TODO.md` PRINTS ITS CATEGORY LIST **TWICE**:
  - **THE HEAD TABLE**, at the top, in a fenced block: `name  [###....] 3/10  prose`.
  - **THE SUMMARY TABLE**, at the bottom: `• name — ████████░░ 39/49  80%`.

⇒ **TWO PRINTS OF ONE LIST ARE TWO SOURCES OF TRUTH, AND A DOCUMENT THAT SAYS TWO THINGS
ABOUT ONE FACT IS A DEFECT.** The two tables spell the SAME categories DIFFERENTLY (the head
table's names are the SECTION titles, lower-cased and shortened; the summary table's are the
section titles too, but truncated with an ellipsis), so a census that compares them by
STRING EQUALITY reads **ZERO** disagreements on a file that HAS them.

⇒ **⇒ SO THE MATCH IS BY **SECTION**, NOT BY NAME: a bar belongs to the section it names, and
the two bars for one section are the two rows that name it. **A BAR WITH NO SECTION IS A BAR
FOR A CATEGORY WHOSE ITEMS LIVE IN THE HEAD BLOCK's PROSE, AND IT IS NOT A DISAGREEMENT.**

⇒ **AND THE MATCH MUST BE UNIQUE.** The tree has several sections whose titles are the same
or nearly the same, and a census that picks the first match compares two different rows.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/twotables.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LEDGER = ROOT / ".agents/TODO.md"

HEAD = re.compile(r"^(\S+)\s+(\[[#\.]+\])\s+(\d+)/(\d+)\s{0,3}")
SUM = re.compile(r"^•\s+(.*?)\s*[—–-]\s*([█░#\.]+)\s+(\d+)/(\d+)\s+(\d+)%")


def norm(s):
    s = re.sub(r"^\[x\]\s*", "", s)
    s = re.sub(r"\*\*", "", s)
    s = re.sub(r"\.\.\.$", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s.lower())
    return " ".join(s.split())


def main():
    lines = LEDGER.read_text().split("\n")
    head, summ = [], []
    for i, line in enumerate(lines):
        m = HEAD.match(line)
        if m:
            head.append((i, norm(m.group(1)), int(m.group(3)), int(m.group(4)), line))
        m = SUM.match(line)
        if m:
            summ.append((i, norm(m.group(1)), int(m.group(3)), int(m.group(4)), line))

    # ---- the sections ----------------------------------------------------------------------
    sections = []
    for i, line in enumerate(lines):
        h = re.match(r"^(#{1,6})\s+(.*)$", line)
        if not h:
            continue
        sections.append((i, norm(h.group(2)), h.group(2)))
    by_line = {s[0]: s for s in sections}

    def match(bar_name):
        """The ONE section a bar names, or None.

        ⇒ **THE SHORTEST MATCHING TITLE WINS, NOT THE LONGEST.** A section title is
        `NAME — a long explanation of it`, and the bar's name is the `NAME` PART, so
        `section.startswith(bar_name)` is the test. **⇒ AND WHEN TWO SECTIONS SHARE A
        LEADING NAME, THE SHORTEST TITLE IS THE CATEGORY AND THE LONGER ONE IS A
        SUB-SECTION** -- `Lane liveness` (11 items) and `Lane liveness — ...` (a different
        heading) are different sections, and picking the LONGEST sent the first version of
        this file to a section with no items in it.
        """
        if not bar_name:
            return None
        hits = [s for s in sections
                if s[1].startswith(bar_name) or bar_name.startswith(s[1][:max(12, len(s[1]) - 4)])]
        if not hits:
            return None
        return min(hits, key=lambda s: len(s[1]))

    head_by_sec = {}
    for i, name, d, dd, raw in head:
        s = match(name)
        if s is None:
            continue
        head_by_sec.setdefault(s[0], []).append((d, dd, i, raw))
    summ_by_sec = {}
    for i, name, d, dd, raw in summ:
        s = match(name)
        if s is None:
            continue
        summ_by_sec.setdefault(s[0], []).append((d, dd, i, raw))

    both = set(head_by_sec) & set(summ_by_sec)
    disagree = 0
    for sec in sorted(both):
        h = head_by_sec[sec][0]
        s = summ_by_sec[sec][0]
        if (h[0], h[1]) != (s[0], s[1]):
            disagree += 1
            print(f"DISAGREE  {by_line[sec][2][:56]}")
            print(f"          head    L{h[2]+1}: {h[0]}/{h[1]}")
            print(f"          summary L{s[2]+1}: {s[0]}/{s[1]}")
    print()
    print(f"head bars {len(head)} · summary bars {len(summ)}")
    print(f"sections named by BOTH tables: {len(both)}")
    print(f"THE TWO TABLES DISAGREE: {disagree}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
