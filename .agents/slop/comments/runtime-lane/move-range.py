#!/usr/bin/env python3
"""**MOVE **A **RANGE **OF **COMMENT **LINES **TO **`.agents/slop/tables/`** AND **LEAVE **A
**POINTER** -- **⇒⇒† AND **THE **RANGE **IS **GIVEN **AS **`<file> <from> <to>`** **IN **THE
**FILE's **1-BASED **LINE **NUMBERS**, **⇒⇒† AND **THE **RANGE **MUST **BE **A **RUN **OF
**`#` **LINES**."""
import pathlib, sys, re
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
rel, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
path = ROOT/"tinybendygrad"/rel
lines = path.read_text().split("\n")
i, j = a-1, b
blk = lines[i:j]
for l in blk:
    if l.strip() and not l.strip().startswith("#"):
        raise SystemExit(f"NOT A COMMENT RUN: {l!r}")
name = rel.replace("/", "-") + f"-{a}.md"
(TABLES/name).write_text(f"<!-- FROM: tinybendygrad/{rel}:{a} -->\n# BLOCK:\n" + "\n".join(blk) + "\n# END BLOCK\n")
text = " ".join(l.strip().lstrip("#").strip() for l in blk).strip()
m = re.search(r"^(.*?[.!?])(\s|$)", text)
sent = re.sub(r"\s+", " ", (m.group(1) if m else blk[0].strip())).strip()
# **⇒⇒† AND **A **TABLE **BLOCK **HAS **NO **SENTENCE** -- **⇒⇒† AND **THE **POINTER
# **NAMES **THE **TABLE **BY **ITS **HEADER** **AND **STOPS **THERE**.
if all(re.match(r"^#\s{2,}", l) or l.strip() == "#" for l in blk[1:]):
    sent = "THE PORTED/WALLS TABLE."
lines[i:j] = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {sent}"]
path.write_text("\n".join(lines))
print(f"MOVED {rel}:{a}-{b} ({len(blk)}L) -> {name}")
