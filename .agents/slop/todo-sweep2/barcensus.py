#!/usr/bin/env python3
"""FIND EVERY CATEGORY WHOSE BAR DISAGREES WITH ITS OWN ITEMS.

THE CLASS. A ledger's bar (`[###....] 3/10`) is a COUNT, and a count that is WRONG is a
number that cannot go red: it says 3 of 10 when every item is ticked, so a reader who trusts
the bar reads an unfinished category, and a reader who reads the items reads a finished one.
**⇒ "A DOCUMENT MUST NOT SAY TWO THINGS ABOUT ONE FACT" -- AND HERE THE TWO THINGS ARE THE
BAR AND THE ITEMS, IN THE SAME FILE, FOR THE SAME CATEGORY.**

⇒ **THE POPULATION IS DISCOVERED, NEVER NAMED.** A category is a `##`/`###` section, and a
  category's ITEMS are the `- [ ]` / `- [x]` lines inside it.

⇒ **AND THERE ARE **TWO** BAR TABLES, AND THAT IS ITSELF PART OF THE DEFECT.**
  - **THE HEAD TABLE**, at the top of the file, in a fenced block: `name  [###....] 3/10  prose`.
  - **THE SUMMARY TABLE**, at the bottom: `• name — [###....] 3/10  76%`.
  **⇒ THEY ARE THE SAME CATEGORY LIST PRINTED TWICE, AND THEY CAN DISAGREE.** A CENSUS THAT
  READS ONE OF THEM HAS NOT READ THE LEDGER.

⇒ **⇒ SO THE CENSUS READS **BOTH**, AND A CATEGORY IS "CONTRADICTED" WHEN **EITHER** BAR
  DISAGREES WITH THE SECTION's OWN ITEMS.** The head table's bar is matched by NAME; the
  summary table's bar is matched by the SAME NAME. **A NAME THAT MATCHES NO SECTION IS
  REPORTED AS `NO SECTION` AND NOT AS A DEFECT** -- because a bar for a category whose items
  live in the head block's prose has no section to disagree with.

⇒ **WHAT IS REPORTED.**
  - `BAR STALE`     -- a bar says < 100% and EVERY item is ticked. **THE BAR CANNOT GO RED.**
  - `BAR AHEAD`     -- a bar says 100% and SOME item is open. **⇒ THE LEDGER PROMISES A
                       COMPLETION THAT IS NOT THERE, WHICH IS THE WORSE HALF.**
  - `THE TWO TABLES DISAGREE` -- the head table and the summary table print different
                       fractions for the SAME category. **⇒ THE LEDGER SAYS TWO THINGS.**

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/barcensus.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LEDGER = ROOT / ".agents/TODO.md"

# THE HEAD TABLE: `name  [###....] 3/10  prose`, INSIDE the fenced block at the top.
HEAD_BAR = re.compile(r"^(\S+)\s+(\[[#\.]+\])\s+(\d+)/(\d+)\s{0,3}")
# THE SUMMARY TABLE: `• name — ████████░░ 39/49  80%`.
# **⇒ NOTE THE DIFFERENCE FROM THE HEAD TABLE: THE HEAD TABLE WRAPS ITS BAR IN BRACKETS
# (`[###....] 3/10`) AND THE SUMMARY TABLE DOES **NOT** (`████░░░░ 39/49  80%`).** A census
# that reads both with ONE regex reads exactly one of them, and reports the other as
# ABSENT -- which is how the first version of this file matched **ZERO** summary rows and
# called a file with 188 bars consistent.
SUM_BAR = re.compile(r"^•\s+(.*?)\s*[—–-]\s*([█░#\.]+)\s+(\d+)/(\d+)\s+(\d+)%")


def norm(s):
    s = re.sub(r"^\[x\]\s*", "", s)
    s = re.sub(r"\*\*", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s.lower())
    return " ".join(s.split())


def main():
    lines = LEDGER.read_text().split("\n")

    head = []
    summ = []
    for i, line in enumerate(lines):
        m = HEAD_BAR.match(line)
        if m:
            head.append((i, norm(m.group(1)), int(m.group(3)), int(m.group(4))))
        m = SUM_BAR.match(line)
        if m:
            summ.append((i, norm(m.group(1)), int(m.group(3)), int(m.group(4))))

    # ---- the sections ---------------------------------------------------------------------
    sections = []
    for i, line in enumerate(lines):
        h = re.match(r"^(#{1,6})\s+(.*)$", line)
        if not h:
            continue
        lvl = len(h.group(1))
        j = i + 1
        opens = done = partial = 0
        while j < len(lines):
            h2 = re.match(r"^(#{1,6})\s+", lines[j])
            if h2 and len(h2.group(1)) <= lvl:
                break
            # **⇒ AN ITEM MAY BE INDENTED.** The tree's items are `- [x]` at column 0 in most
            # sections and `  - [x]` under a sub-heading in others, and the FIRST version of
            # this census matched column 0 ONLY -- **⇒ so it read a section with nine items
            # as a section with ZERO, and called its bar STALE.** A census that counts a
            # population it can only see when it happens to be flush left is a census of
            # the wrong population.
            #
            # **⇒ AND THERE IS A **THIRD** STATE, `- [~]`, AND IT IS NOT A TICK AND NOT AN
            # OPEN ITEM.** The ledger's own summary table writes it as `(+1 [~])` beside a
            # fraction -- **⇒ SO THE DENOMINATOR COUNTS A `[~]` AS NOT-DONE, AND A CENSUS
            # THAT COUNTS ONLY `[ ]` AND `[x]` READS A SECTION WITH A PARTIAL ITEM AS A
            # FINISHED ONE.** THE FIRST VERSION OF THIS CENSUS DID EXACTLY THAT AND REPORTED
            # TWO SECTIONS AS STALE THAT ARE NOT.
            if re.match(r"^\s*- \[ \] ", lines[j]):
                opens += 1
            elif re.match(r"^\s*- \[~\] ", lines[j]):
                partial += 1
            elif re.match(r"^\s*- \[x\] ", lines[j]):
                done += 1
            j += 1
        sections.append((i, lvl, norm(h.group(2)), h.group(2), opens, done, partial))

    # ---- match a bar to a section ----------------------------------------------------------
    # BY NAME, AND THE NAME MUST BE A PREFIX OF THE SECTION's TITLE IN THE BAR's OWN DIRECTION:
    # the bar's name is a TRUNCATED title, so the bar's name must be a PREFIX of the section's
    # normalised title. A section whose title CONTAINS the bar's name as a SUBSTRING is a
    # DIFFERENT section (the tree has "PROBES" and "PROBES — the pinned..."), so a SUBSTRING
    # match is allowed ONLY when it is the LONGEST possible match.
    def find_section(bname):
        """The ONE section a bar names, or None.

        ⇒ **A NAME THAT MATCHES MORE THAN ONE SECTION IS NOT A MATCH.** The tree has three
        sections called `**NOT COMMITTED.**` and two called `Progress: [#########.] 9/10`,
        and a bar for one of them is a bar for a DIFFERENT one. A census that picks the
        first match reports a disagreement that is not there -- **⇒ AND THE FIRST VERSION OF
        THIS FILE DID EXACTLY THAT, AND REPORTED THREE `BAR AHEAD` ROWS THAT WERE ALL THE
        SAME AMBIGUITY.** So the match must be UNIQUE, and an ambiguous name is reported as
        AMBIGUOUS, not as a defect.
        """
        hits = []
        for s in sections:
            if s[3] == 0 and s[4] == 0 and s[5] == 0:
                continue
            n = s[2]
            if not bname:
                continue
            if n.startswith(bname):
                hits.append((len(bname), s))
            elif len(n) > 12 and bname.startswith(n[:max(12, len(n) - 4)]):
                hits.append((len(n), s))
        if not hits:
            return None, "NO SECTION"
        best = max(hits, key=lambda x: x[0])[1]
        # A TIE IS AN AMBIGUITY: two sections match the bar's name equally well.
        tied = [h for h in hits if h[0] == max(x[0] for x in hits)]
        if len({id(h[1]) for h in tied}) > 1:
            return None, f"AMBIGUOUS ({len({id(h[1]) for h in tied})} sections)"
        return best, "OK"

    stale = ahead = nosec = ambig = 0
    disagree = 0
    for label, bars in (("HEAD", head), ("SUMMARY", summ)):
        for i, bname, d, dd in bars:
            s, why = find_section(bname)
            if s is None:
                if why.startswith("AMBIGUOUS"):
                    ambig += 1
                else:
                    nosec += 1
                continue
            _, _, _, title, opens, done, partial = s
            if dd == 0:
                continue
            if d >= dd and opens:
                ahead += 1
                print(f"BAR AHEAD   [{label}] bar says {d}/{dd} but {opens} item(s) are OPEN"
                      f"  -- {title[:58]}")
            elif d < dd and opens == 0 and partial == 0:
                stale += 1
                print(f"BAR STALE   [{label}] bar says {d}/{dd} but ALL {done} item(s) are TICKED"
                      f"  -- {title[:58]}")

    # ---- the two tables against each other --------------------------------------------------
    by_name = {}
    for i, bname, d, dd in head:
        by_name.setdefault(bname, []).append((d, dd))
    for i, bname, d, dd in summ:
        for hd, hdd in by_name.get(bname, []):
            if (hd, hdd) != (d, dd):
                disagree += 1
                print(f"TABLES DISAGREE  {bname}: head {hd}/{hdd} vs summary {d}/{dd}")

    print()
    print(f"head bars {len(head)} · summary bars {len(summ)} · sections with items "
          f"{sum(1 for s in sections if s[4] + s[5] + s[6])}")
    print(f"BAR STALE (the bar cannot go red) : {stale}")
    print(f"BAR AHEAD (the bar promises more) : {ahead}")
    print(f"THE TWO TABLES DISAGREE            : {disagree}")
    print(f"bars with NO section to check      : {nosec}")
    print(f"bars whose NAME IS AMBIGUOUS       : {ambig}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
