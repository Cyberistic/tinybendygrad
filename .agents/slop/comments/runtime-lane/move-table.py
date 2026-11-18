#!/usr/bin/env python3
"""**MOVE **ONE **COMMENT **BLOCK **TO **`.agents/slop/tables/`** AND **LEAVE **A
**POINTER** -- **⇒⇒† AND **A **TABLE **IS **DATA**, **⇒⇒† AND **DATA **IN **A **COMMENT
**BLOCK **IS **A **FILE **IN **THE **WRONG **PLACE** (RULE 6).

**⇒⇒† AND **THE **NAMING **IS **`<path-with-slashes-as-dashes>-<line>.md`**, **⇒⇒† AND **THE
**POINTER **IS **ONE **LINE** THAT **NAMES **THE **TABLE **AND **KEEPS **THE **FIRST
**SENTENCE**."""
import pathlib, sys, re
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
rel = sys.argv[1]; line = int(sys.argv[2])
path = ROOT/"tinybendygrad"/rel
lines = path.read_text().split("\n")
i = line - 1
j = i
while j < len(lines) and lines[j].strip().startswith("#"): j += 1
blk = lines[i:j]
name = rel.replace("/", "-") + f"-{line}.md"
out = TABLES/name
body = "\n".join(blk)
out.write_text(f"<!-- FROM: tinybendygrad/{rel}:{line} -->\n# BLOCK:\n{body}\n# END BLOCK\n")
# **⇒⇒† AND **THE **POINTER**: **THE **FIRST **SENTENCE **OF **THE **BLOCK**, **PLUS **THE
# **TABLE's **PATH**.
first = blk[0].strip()
# **⇒⇒† AND **THE **FIRST **SENTENCE**, **⇒⇒† AND **NOT **THE **FIRST **LINE**, **⇒⇒† AND
# **BECAUSE **THE **FIRST **LINE **IS **OFTEN **THE **MIDDLE **OF **ONE**.
text = " ".join(l.strip().lstrip("#").strip() for l in blk).strip()
m = re.search(r"^(.*?[.!?])(\s|$)", text)
sent = m.group(1) if m else text.split("\n")[0]
sent = re.sub(r"\s+", " ", sent).strip()
new = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {sent}"]
lines[i:j] = new
path.write_text("\n".join(lines))
print(f"MOVED {rel}:{line} ({len(blk)}L) -> {name}")
