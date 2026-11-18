#!/usr/bin/env python3
"""**MOVE **THE **REMAINDER **OF **AN **INVENTORY **TABLE**, **⇒⇒† AND **THE **TABLE's **ROWS
**MAY **NOT **ALL **BE **INDENTED**, **⇒⇒† AND **SO **THE **EXTENT **RUNS **TO **THE
**NEXT **BLANK **SEPARATOR **THAT **IS **FOLLOWED **BY **A **NON-ROW **COMMENT **LINE**."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
ROW = re.compile(r"^\s*#\s+(\S|$)")
HEAD = re.compile(r"^#\s*(WHAT IS PORTED|WHAT IS NOT PORTED|WHAT SURVIVES|WHAT IS HERE|THE PORTED)\b")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
PORT = ROOT/"tinybendygrad"
for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    i = 0
    while i < len(lines):
        if not lines[i].startswith("#") or not HEAD.match(lines[i]): i += 1; continue
        j = i; end = i
        while j < len(lines) and lines[j].strip().startswith("#"):
            if j > i and lines[j].strip() == "#":
                # **⇒⇒† AND **A **BLANK **SEPARATOR **THAT **IS **FOLLOWED **BY **A **ROW
                # **CONTINUES **THE **TABLE**.
                k = j + 1
                while k < len(lines) and lines[k].strip() == "#": k += 1
                if k < len(lines) and ROW.match(lines[k]):
                    end = k; j = k; continue
                break
            end = j; j += 1
        blk = lines[i:end+1]
        if len(blk) < 3: i += 1; continue
        name = rel.replace("/", "-") + f"-{i+1}.md"
        (TABLES/name).write_text(f"<!-- FROM: tinybendygrad/{rel}:{i+1} -->\n# BLOCK:\n" + "\n".join(blk) + "\n# END BLOCK\n")
        text = " ".join(l.strip().lstrip("#").strip() for l in blk).strip()
        m = re.search(r"^(.*?[.!?])(\s|$)", text)
        sent = re.sub(r"\s+", " ", (m.group(1) if m else blk[0].strip())).strip()
        lines[i:end+1] = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {sent}"]
        print(f"MOVED {rel}:{i+1}-{end+1} ({len(blk)}L) -> {name}")
        i += 1
    f.write_text("\n".join(lines))
