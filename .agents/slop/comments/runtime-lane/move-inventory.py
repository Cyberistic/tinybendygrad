#!/usr/bin/env python3
"""**MOVE **EVERY **"WHAT **IS **PORTED" **INVENTORY **TABLE **OF **THE **LANE** **TO
**`.agents/slop/tables/`** **AND **LEAVE **A **POINTER** -- **⇒⇒† AND **A **TABLE **IS
**DATA**, **⇒⇒† AND **DATA **IN **A **COMMENT **BLOCK **IS **A **FILE **IN **THE **WRONG
**PLACE** (RULE 6).

**⇒⇒† AND **THE **EXTENT**: **THE **TABLE **RUNS **FROM **THE **HEADER **TO **THE **FIRST
**COMMENT **LINE **THAT **IS **NOT **INDENTED **AND **NOT **A **BLANK **SEPARATOR**."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
HEAD = re.compile(r"^#\s*WHAT IS PORTED, DEF BY DEF\b")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
PORT = ROOT/"tinybendygrad"
for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    i = 0
    while i < len(lines):
        if not lines[i].startswith("#") or not HEAD.match(lines[i]):
            i += 1; continue
        # **⇒⇒† AND **THE **EXTENT**.
        j = i
        end = i
        while j < len(lines) and lines[j].strip().startswith("#"):
            s = lines[j].strip()
            if j > i and s != "#" and not re.match(r"^#\s{2,}\S", lines[j]):
                break
            end = j
            j += 1
        blk = lines[i:end+1]
        name = rel.replace("/", "-") + f"-{i+1}.md"
        (TABLES/name).write_text(f"<!-- FROM: tinybendygrad/{rel}:{i+1} -->\n# BLOCK:\n" + "\n".join(blk) + "\n# END BLOCK\n")
        text = " ".join(l.strip().lstrip("#").strip() for l in blk).strip()
        m = re.search(r"^(.*?[.!?])(\s|$)", text)
        sent = re.sub(r"\s+", " ", (m.group(1) if m else blk[0].strip())).strip()
        lines[i:end+1] = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {sent}"]
        print(f"MOVED {rel}:{i+1}-{end+1} ({len(blk)}L) -> {name}")
        i += 1
    f.write_text("\n".join(lines))
