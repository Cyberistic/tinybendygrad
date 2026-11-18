#!/usr/bin/env python3
"""**MOVE **THE **TABLE **THAT **FOLLOWS **A **POINTER **LINE** -- **⇒⇒† AND **THE **POINTER
**IS **THE **FIRST **LINE**, **⇒⇒† AND **THE **TABLE **IS **THE **RUN **OF **COMMENT **LINES
**THAT **FOLLOWS **IT **AND **LOOKS **LIKE **ROWS**."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
PTR = re.compile(r"^# THE TABLE IS IN `\.agents/slop/tables/([^`]+)` -- ")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
PORT = ROOT/"tinybendygrad"
for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    i = 0
    while i < len(lines):
        m = PTR.match(lines[i]) if lines[i].startswith("#") else None
        if not m: i += 1; continue
        name = m.group(1)
        # **⇒⇒† AND **THE **TABLE's **BODY **IS **THE **RUN **AFTER **THE **POINTER**,
        # **⇒⇒† AND **IT **IS **THE **ROWS **THE **POINTER **LEFT **BEHIND**.
        j = i + 1
        while j < len(lines) and lines[j].strip().startswith("#"): j += 1
        body = lines[i+1:j]
        if not body:
            i += 1; continue
        # **⇒⇒† AND **THE **BODY **MUST **BE **ROWS**, **⇒⇒† AND **NOT **A **NEW
        # **SECTION**.
        if any(not re.match(r"^#\s+", l) and l.strip() != "#" for l in body):
            i += 1; continue
        (TABLES/name).write_text(f"<!-- FROM: tinybendygrad/{rel} -->\n# BLOCK:\n# " + "\n# ".join([l.lstrip("#").lstrip() for l in body]) + "\n# END BLOCK\n")
        lines[i+1:j] = []
        print(f"MERGED {rel}:{i+1} body of {len(body)}L -> {name}")
        i += 1
    f.write_text("\n".join(lines))
