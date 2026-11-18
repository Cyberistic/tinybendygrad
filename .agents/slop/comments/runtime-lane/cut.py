#!/usr/bin/env python3
"""**THE **LANE **CUTTER** -- **THE **PARAGRAPH-LEVEL **CUT **OF **THE **`runtime/` **LANE**.

**⇒⇒† AND **THE **RULE** (THE **TREE's **OWN, `AGENTS.md:16`): **A **COMMENT **EARNS **ITS
**PLACE **IN **ONE **OF **FOUR **WAYS** -- **DIFFERENCE** (**AN **UPSTREAM **CITATION**),
**WEIRD** (**A **WALL **OR **A **REFUSAL**), **MEASURED** (**A **NUMBER**), **AND **THE
**FILE **HEADER** (**WHAT **THE **FILE **IS**). **⇒⇒† AND **EVERYTHING **ELSE **IS
**NARRATION**.

**⇒⇒† AND **THE **CUT **IS **AT **PARAGRAPH **GRANULARITY**, **⇒⇒† AND **A **PARAGRAPH
**THAT **CARRIES **A **KEEP **MARKER **IS **KEPT **WHOLE**, **⇒⇒† AND **A **PARAGRAPH **THAT
**DOES **NOT **IS **CUT **TO **ITS **FIRST **SENTENCE**, **⇒⇒† AND **AND **IF **THE **FIRST
**SENTENCE **IS **THE **WHOLE **PARAGRAPH**, **⇒⇒† AND **THE **PARAGRAPH **GOES**.

**⇒⇒† AND **THE **SAFETY **PROPERTY**: **A **KEPT **PARAGRAPH **IS **A **PREFIX **OF **THE
**ORIGINAL**, **⇒⇒† AND **SO **NO **KEPT **LINE **IS **REWRITTEN**, **⇒⇒† AND **ONLY **WHOLE
**COMMENT **LINES **ARE **DELETED**.

**⇒⇒† AND **THE **LIST **RULE**: **A **LIST **IS **KEPT **WHOLE **IF **ANY **OF **ITS **ITEMS
**CARRIES **A **KEEP **MARKER**, **⇒⇒† AND **BECAUSE **THE **ITEMS **OF **A **LIST **ARE **THE
**CLAIMS **OF **ONE **LIST**, **⇒⇒† AND **CUTTING **ITEM **3 **OF **6 **LEAVES **A **LIST
**THAT **LIES **BY **OMISSION**.

**⇒⇒† AND **IT **NEVER **WRITES** **UNLESS **`--apply` **IS **GIVEN**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
_spec = importlib.util.spec_from_file_location("ta", ROOT/".agents/slop/comments/trim-apply.py")
ta = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ta)
_cc = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(_cc); _cc.loader.exec_module(cc)

CITE = ta.CITE
MEAS = ta.MEASURED
WALL = re.compile(r"\b(WALL\b|BLOCKED|REFUSED|REFUSES|CANNOT|CAN NOT|MUST BE|MUST ONLY|IS NOT A|ARE NOT)\b")
DIFF = ta.DIFFERENCE
# **⇒⇒† AND **A **LIST **ITEM**.
ITEM = re.compile(r"^\s*#\s*(?:[-*+]\s+|\d+[.)]\s+)")
# **⇒⇒† AND **THE **FILE **HEADER's **FIRST **LINE **IS **THE **FILE's **NAME**.
def keep_marker(p):
  t = " ".join(p)
  return bool(CITE.search(t) or MEAS.search(t) or WALL.search(t) or DIFF.search(t))

def paragraphs(blk):
  out, cur = [], []
  for line in blk:
    if line.strip() == "#":
      if cur: out.append(cur)
      out.append([line]); cur = []
    else: cur.append(line)
  if cur: out.append(cur)
  return out

def is_list(p):
  return any(ITEM.match(l) for l in p)

def cut_block(blk):
  out = []
  for p in paragraphs(blk):
    if all(l.strip() == "#" for l in p):
      if out and out[-1].strip() == "#": continue
      out.extend(p); continue
    if keep_marker(p): out.extend(p); continue
    if is_list(p):
      # **⇒⇒† AND **A **LIST **WITH **NO **MARKER **AT **ALL **IS **CUT **TO **ITS **FIRST
      # **ITEM**, **⇒⇒† AND **A **LIST **THAT **HAS **A **MARKER **IN **ONE **ITEM **IS **KEPT
      # **WHOLE** -- **⇒⇒† AND **THE **LIST **RULE **IS **ABOVE**.
      out.extend(p[:1]); continue
    body = [l for l in p if l.strip() != "#"]
    n = ta.sentence_end(body, 0) if body else len(p)
    out.extend(p[:n])
  while out and out[-1].strip() == "#": out.pop()
  return out

if __name__ == "__main__":
  only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
  apply = "--apply" in sys.argv
  PORT = ROOT/"tinybendygrad"
  tot = 0
  for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    out = []; n = 0; i = 0
    while i < len(lines):
      if not lines[i].strip().startswith("#"):
        out.append(lines[i]); i += 1; continue
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"): j += 1
      blk = lines[i:j]
      if len(blk) > 6:
        new = cut_block(blk)
        n += len(blk) - len(new)
        out.extend(new)
      else:
        out.extend(blk)
      i = j
    if n and apply: f.write_text("\n".join(out))
    if n: print(f"{n:7d}  {rel}")
    tot += n
  print(f"THE LINES CUT: {tot}")
