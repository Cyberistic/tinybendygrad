#!/usr/bin/env python3
"""THE TABLE FILES' MANIFEST -- GENERATED FROM THE TABLE FILES' OWN `FROM:` LINES.

A MANIFEST THAT IS WRITTEN BY HAND IS A SECOND COPY OF THE THING IT DESCRIBES, AND
IT ROTS WITHOUT ANYONE NOTICING.  THIS ONE IS READ OUT OF THE TABLE FILES IT
NAMES, SO IT CANNOT DISAGREE WITH THEM.

THE `FROM:` LINE OF A TABLE IS ITS FIRST LINE, AND IT NAMES THE SOURCE BLOCK's
FIRST LINE.  THE MANIFEST IS SORTED BY (SOURCE, LINE), AND THE COUNT IN THE
HEADER IS COUNTED, NOT TYPED.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "MANIFEST.rows"
# **A **`.md` **TABLE **OPENS **WITH **AN **HTML **COMMENT **AND **A **`.rows` **TABLE
# **OPENS **WITH **A **`#` **COMMENT**, **AND **BOTH **NAME **THE **SOURCE.
FROM = re.compile(r"^(?:<!-- FROM: |# FROM: )(\S+)(?: -->)?$")

rows = []
for f in sorted(HERE.iterdir()):
  if not f.name.endswith(".md") and not f.name.endswith(".rows"):
    continue
  first = f.read_text().split("\n")[0]
  m = FROM.match(first)
  if not m:
    continue
  src = m.group(1)
  # **THE **LINE **IS **THE **NUMBER **AFTER **THE **COLON.
  mm = re.match(r"^(.*):(\d+)$", src)
  if not mm:
    continue
  rows.append((mm.group(1), int(mm.group(2)), f.name))

rows.sort()
sources = {r[0] for r in rows}
nrows = sum(1 for r in rows if r[2].endswith(".rows"))
nmd = sum(1 for r in rows if r[2].endswith(".md"))

out = ["# FROM: THE TABLE FILES' OWN MANIFEST, GENERATED FROM THEIR OWN `FROM:` LINES",
       "#",
       f"# {len(rows)} tables, {len(sources)} source files.",
       f"# {nrows} are `.rows` (A PIPE-ROW TABLE) AND {nmd} ARE `.md` (PROSE).",
       "# THE LINES ARE 1-BASED AND NAME THE BLOCK's **FIRST** LINE IN THE TREE.",
       "#"]
for src, ln, name in rows:
  out.append(f"{src}:{ln}\t{name}")
OUT.write_text("\n".join(out) + "\n")
print(f"THE MANIFEST WRITTEN: {len(rows)} tables, {len(sources)} source files, {nmd} .md and {nrows} .rows")
print(f"  -> {OUT.name}")
