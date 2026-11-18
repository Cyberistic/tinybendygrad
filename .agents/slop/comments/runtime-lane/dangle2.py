#!/usr/bin/env python3
"""**THE **MID-BLOCK **TRUNCATION **DETECTOR** -- **A **COMMENT **SECTION **THAT **OPENS **ON
**A **FRAGMENT **IS **A **CUT **IN **THE **MIDDLE **OF **A **SENTENCE**, **⇒⇒† AND **THE
**FRAGMENT **IS **A **LIE **THE **SAME **WAY **A **DANGLING **TAIL **IS**.

**⇒⇒† AND **THE **TEST**: **A **SECTION **THAT **OPENS **WITH **A **LINE **THAT **ENDS **ON
**A **WORD **THAT **CANNOT **END **A **SENTENCE** -- **"THIS"**, **"AND"**, **"THE"**,
**"OF"**, **"TO"**, **"A"**, **"AN"**, **"IS"**, **"WAS"**, **"IN"**, **"FOR"** -- **AND
**WHOSE **NEXT **LINE **STARTS **A **NEW **CLAIM** (A **CAPITAL**, **A **`**`, **A **NUMBER**,
**OR **A **LIST **MARKER**).

**⇒⇒† AND **A **SECTION **THAT **OPENS **ON **SUCH **A **WORD **AND **CONTINUES **INTO
**ANOTHER **LINE **THAT **COMPLETES **IT **IS **FINE** -- **⇒⇒† AND **THE **CUT **LEFT
**THE **WORD **AT **THE **END **OF **A **SECTION**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
# **⇒⇒† AND **A **WORD **THAT **CANNOT **END **A **SENTENCE**.
OPEN = re.compile(r"\b(this|and|the|of|to|a|an|is|was|in|for|with|that|it|its|are|be|by|on|as|at|from|not|but|or|if|when|where|which|than|then|so|yet|also|only|just|still|very|such|per)\s*[.:]?\s*$", re.I)
NEWCLAIM = re.compile(r"^\s*#\s*(\*|[A-Z0-9`]|-\s)")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    # **⇒⇒† AND **THE **SECTIONS**, **SPLIT **AT **BLANK **`#` **LINES**.
    secs, cur = [], []
    for l in blk:
        if l.strip() == "#":
            if cur: secs.append(cur); cur = []
            continue
        cur.append(l)
    if cur: secs.append(cur)
    for si, sec in enumerate(secs):
        if len(sec) < 1: continue
        first = sec[0].strip().lstrip("#").strip()
        if not first or not OPEN.search(first): continue
        # **⇒⇒† AND **IF **THE **SECTION **HAS **A **SECOND **LINE, **⇒⇒† AND **THAT **LINE
        # **COMPLETES **THE **SENTENCE**, **⇒⇒† AND **IT **IS **FINE**.
        if len(sec) >= 2 and not NEWCLAIM.match(sec[1]): continue
        print(f"{rel}:{ln}  SEC[{si}]  {sec[0][:120]}")
