#!/usr/bin/env python3
"""**MOVE **THE **INVENTORY **TABLES **OF **THE **LANE** **TO **`.agents/slop/tables/`** **AND
**LEAVE **A **POINTER** -- **⇒⇒† AND **A **TABLE **IS **DATA**, **⇒⇒† AND **DATA **IN **A
**COMMENT **BLOCK **IS **A **FILE **IN **THE **WRONG **PLACE** (RULE 6).

**⇒⇒† AND **THE **NAMING **IS **`<path-with-slashes-as-dashes>-<line>.md`** -- **⇒⇒† AND
**THE **EXAMPLE **IN **THE **BRIEF **IS **`runtime-ops-python-17.md`**, **⇒⇒† AND **SO **THE
**`.bend` **IS **DROPPED**.

**⇒⇒† AND **THE **SAFETY **PROPERTY**: **THE **TABLE **FILE **HOLDS **THE **EXACT **TEXT
**THAT **WAS **IN **THE **SOURCE**, **⇒⇒† AND **THE **SOURCE **KEEPS **A **POINTER **THAT
**NAMES **IT**.

**⇒⇒† AND **IT **NEVER **WRITES** **UNLESS **`--apply` **IS **GIVEN**."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
# **⇒⇒† AND **THE **INVENTORY **TABLE's **HEADER**.
HEAD = re.compile(r"^#\s*(WHAT IS PORTED|WHAT IS NOT PORTED|WHAT SURVIVES)\b")
# **⇒⇒† AND **A **TABLE **ROW**: **AN **INDENTED **COMMENT **LINE**, **OR **A **LINE **THAT
# **STARTS **WITH **A **FILE's **NAME **OR **A **NUMBER**.
def is_row(l):
  if l.strip() == "#": return True
  if re.match(r"^#\s{2,}\S", l): return True
  if re.match(r"^#\s*\d+[.)]\s", l): return True
  return False

def table_extent(lines, i):
  """**THE **LAST **LINE **OF **THE **TABLE **THAT **STARTS **AT **`i`**."""
  j = i; end = i
  # **⇒⇒† AND **THE **HEADER **MAY **SPAN **LINES**, **⇒⇒† AND **IT **RUNS **TO **THE
  # **FIRST **BLANK **SEPARATOR**.
  while j < len(lines) and lines[j].strip().startswith("#") and lines[j].strip() != "#":
    end = j; j += 1
  while j < len(lines) and lines[j].strip().startswith("#"):
    s = lines[j].strip()
    if s == "#":
      k = j + 1
      while k < len(lines) and lines[k].strip() == "#": k += 1
      if k < len(lines) and is_row(lines[k]):
        end = k; j = k; continue
      break
    if not is_row(lines[j]): break
    end = j; j += 1
  return end

if __name__ == "__main__":
  only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
  apply = "--apply" in sys.argv
  PORT = ROOT/"tinybendygrad"
  for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    i = 0; moved = []
    while i < len(lines):
      if not lines[i].startswith("#") or not HEAD.match(lines[i]): i += 1; continue
      end = table_extent(lines, i)
      blk = lines[i:end+1]
      if len(blk) < 4: i += 1; continue
      name = rel.replace("/", "-").replace(".bend", "") + f"-{i+1}.md"
      (TABLES/name).write_text(f"<!-- FROM: tinybendygrad/{rel}:{i+1} -->\n# BLOCK:\n" + "\n".join(blk) + "\n# END BLOCK\n")
      text = " ".join(l.strip().lstrip("#").strip() for l in blk).strip()
      m = re.search(r"^(.*?[.!?])(\s|$)", text)
      sent = re.sub(r"\s+", " ", (m.group(1) if m else blk[0].strip())).strip()
      lines[i:end+1] = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {sent}"]
      moved.append((rel, i+1, end+1, len(blk), name))
      i += 1
    if moved and apply: f.write_text("\n".join(lines))
    for m in moved: print(f"MOVED {m[0]}:{m[1]}-{m[2]} ({m[3]}L) -> {m[4]}")
