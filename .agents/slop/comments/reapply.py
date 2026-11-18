#!/usr/bin/env python3
"""**THE **RE-APPLY** -- **THE **BASE's **MARKERS **PUT **BACK **INTO **THE **HEAD's **BLOCKS**, **⇒⇒† AND
**IT **REFUSES **IF **A **CODE **LINE **WOULD **MOVE**.

**⇒⇒† AND **WHY**: **THE **GOAL **IS **A **DIFF **THAT **CONTAINS **NO **NON-COMMENT **LINE**, **⇒⇒† AND
**A **BLANK **LINE **IS **NOT **A **COMMENT**, **⇒⇒† AND **SO **THE **HEAD's **BLOCK **BOUNDARIES **MUST
**STAY**, **⇒⇒† AND **THE **ONLY **WAY **TO **PUT **THOSE **BOUNDARIES **BACK **IS **TO **EDIT **THE
**HEAD's **FILE **IN **PLACE**.

**⇒⇒† AND **WHY **THE **MARKERS **HAVE **TO **COME **BACK**: **MEASURED, **THE **HEAD's **CUT **DROPPED
**656 **CITATIONS **AND **129 **MEASUREMENTS **AND **117 **DIFFERENCE-MARKER **LINES** **AGAINST **THE
**BASE**, **⇒⇒† AND **THE **RULE's **OWN **WORDS **ARE **THAT **THE **DIFFERENCE **/ **WEIRD **/ **MEASURED
**SET **IS **KEPT **WHOLE**, **⇒⇒† AND **AND **A **CUT **THAT **DROPS **THE **EVIDENCE **IS **NOT **A
**CUT**.

**⇒⇒† AND **THE **MECHANISM**: **FOR **EVERY **HEAD **BLOCK**, **FIND **THE **BASE **BLOCK **IT **CAME
**FROM** (**BY **THE **FIRST **LINE**, **⇒⇒† AND **THE **ORDER**), **⇒⇒† AND **TAKE **THE **RULE's **CUT
**OF **THAT **BASE **BLOCK**, **⇒⇒† AND **AND **UNION **IT **WITH **THE **HEAD's **OWN **LINES**, **⇒⇒† AND
**AND **THE **RESULT **IS **THE **HEAD's **BLOCK **PLUS **THE **MISSING **MARKERS**, **⇒⇒† AND **AND **THE
**BLOCK **BOUNDARIES **DO **NOT **MOVE**, **⇒⇒† AND **AND **THE **DIFF **IS **COMMENTS **ONLY**.
"""

import importlib.util
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("go", HERE / "gen-ops.py")
go = importlib.util.module_from_spec(spec)
spec.loader.exec_module(go)

FILES = ["__init__", "divandmod", "f32_repr", "fold", "movement", "ops",
         "render", "spec", "symbolic", "upat", "validate", "weak"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "5de8a84f8"


def code_of(lines):
  return [l for l in lines
          if not l.strip().startswith("#") and l.strip() != ""]


def blocks_of(lines):
  out = []
  i = 0
  while i < len(lines):
    if lines[i].strip().startswith("#"):
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"):
        j += 1
      out.append((i, j))
      i = j
    else:
      i += 1
  return out


def key_of(block):
  """**THE **JOIN **KEY**: **THE **BLOCK's **FIRST **LINE**, **WITHOUT **THE **`#`**."""
  return block[0].strip().lstrip("#").strip()


def match_blocks(base_lines, head_lines):
  """**THE **CORRESPONDENCE**, **⇒⇒† AND **EVERY **HEAD **BLOCK **GETS **THE **BASE **BLOCK **IT **CAME
  **FROM**, **⇒⇒† AND **AND **THE **JOIN **IS **A **SEQUENCE **ALIGNMENT**, **⇒⇒† AND **AND **NOT **A
  **GREEDY **BEST-OVERLAP**, **⇒⇒† AND **THE **REASON **IS **MEASURED**: **THE **HEAD **DROPS **BLOCKS**,
  **⇒⇒† AND **AND **A **GREEDY **MATCH **TAKES **THE **WRONG **BASE **BLOCK **WHEN **A **BLOCK **WAS
  **DROPPED**, **⇒⇒† AND **AND **AN **ALIGNMENT **THAT **ALLOWS **A **GAP **GETS **IT **RIGHT**.

  **⇒⇒† AND **THE **ALIGNMENT **IS **OVER **THE **BLOCK's **LINE **SETS**: **TWO **BLOCKS **MATCH **WHEN
  **THE **SHARED **LINES **ARE **THE **MOST **THEY **SHARE**, **⇒⇒† AND **AND **THE **SHARED **LINE **COUNT
  **IS **THE **SCORE**."""
  import difflib
  base_blocks = [(i, j, base_lines[i:j]) for i, j in blocks_of(base_lines)]
  head_blocks = [(i, j, head_lines[i:j]) for i, j in blocks_of(head_lines)]
  base_sets = [frozenset(l.strip() for l in bb) for _i, _j, bb in base_blocks]
  head_sets = [frozenset(l.strip() for l in hb) for _i, _j, hb in head_blocks]
  matches = [None] * len(head_blocks)
  sm = difflib.SequenceMatcher(None, base_sets, head_sets, autojunk=False)
  for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == "equal":
      for k in range(j2 - j1):
        matches[j1 + k] = base_blocks[i1 + k]
    elif tag == "replace":
      # **⇒⇒† AND **THE **REPLACE **IS **A **ONE-TO-ONE **MATCH **OF **THE **TWO **RUNS**, **⇒⇒† AND **AND
      # **THE **PAIRING **IS **BY **THE **SHARED **LINE **COUNT**.
      pairs = []
      for hk in range(j1, j2):
        best = None
        best_n = 0
        for bk in range(i1, i2):
          n = len(base_sets[bk] & head_sets[hk])
          if n > best_n:
            best_n = n
            best = bk
        pairs.append((hk, best, best_n))
      for hk, bk, n in pairs:
        if bk is not None and n > 0:
          matches[hk] = base_blocks[bk]
  return matches


def rebuild(base_lines, head_lines):
  """**THE **REBUILD**, **⇒⇒† AND **EVERY **HEAD **BLOCK **BECOMES **THE **RULE's **CUT **OF **THE
  **BASE **BLOCK **IT **CAME **FROM**, **⇒⇒† AND **AND **A **BLOCK **THE **RULE **DROPS **WHOLE **KEEPS
  **ITS **FIRST **LINE**, **⇒⇒† AND **AND **THE **REASON **IS **MEASURED**: **THE **HEAD's **BLOCK
  **BOUNDARIES **MUST **NOT **MOVE** (**A **BLANK **LINE **IS **NOT **A **COMMENT**), **⇒⇒† AND **AND **A
  **BLOCK **THAT **KEPT **NONE **MUST **STILL **KEEP **A **LINE** **OR **THE **BLANK **LINES **AROUND **IT
  **MERGE**.

  **⇒⇒† AND **AND **A **BASE **BLOCK **THE **HEAD **DROPPED **WHOLE **IS **PUT **BACK**, **⇒⇒† AND **AND
  **ONLY **THE **LINES **THE **RULE **KEEPS**, **⇒⇒† AND **THE **REASON **IS **MEASURED**: **THE **HEAD's
  **CUT **DROPPED **281 **CITATIONS **AND **32 **MEASUREMENTS **AGAINST **THE **BASE**, **⇒⇒† AND **AND **A
  **CUT **THAT **DROPS **THE **EVIDENCE **IS **NOT **A **CUT**, **⇒⇒† AND **AND **THE **PUT-BACK **IS **AN
  **INSERTION **OF **COMMENT **LINES **AND **SO **THE **DIFF **IS **COMMENTS **ONLY**."""
  matches = match_blocks(base_lines, head_lines)
  head_blocks = blocks_of(head_lines)
  matched = {best[0] for best in matches if best is not None}
  # **⇒⇒† AND **THE **ORPHANS**: **THE **BASE **BLOCKs **THE **HEAD **DROPPED **WHOLE**, **⇒⇒† AND **AND
  # **THE **LINES **THE **RULE **KEEPS **OF **EACH**, **⇒⇒† AND **AND **THEY **GO **BACK **AT **THE **BASE's
  # **POSITION**, **⇒⇒† AND **AND **THE **POSITION **IS **MAPPED **ONTO **THE **HEAD **BY **THE **MATCHED
  # **BLOCKs**.
  orphans = {}
  for bi, bj in blocks_of(base_lines):
    if bi not in matched:
      kept = go.block_keep(base_lines[bi:bj], first=(bi == 0))
      if kept:
        orphans[bi] = kept
  # **⇒⇒† AND **THE **MAP**: **THE **BASE's **LINE **NUMBER **AND **THE **HEAD's **LINE **NUMBER **OF **EVERY
  # **MATCHED **BLOCK**, **⇒⇒† AND **AND **THE **MAP **BETWEEN **TWO **ANCHORS **IS **LINEAR**.
  anchors = sorted((best[0], head_blocks[b][0]) for b, best in enumerate(matches) if best is not None)
  def head_of(base_line):
    if not anchors or base_line <= anchors[0][0]:
      return 0
    prev = anchors[0]
    for a in anchors[1:]:
      if base_line < a[0]:
        span = a[0] - prev[0]
        off = (base_line - prev[0]) * (a[1] - prev[1]) / span if span else 0
        return prev[1] + int(off)
      prev = a
    return anchors[-1][1]
  # **⇒⇒† AND **THE **OUT **IS **BUILT **HEAD **LINE **BY **HEAD **LINE**, **⇒⇒† AND **AND **THE **ORPHANS
  # **GO **IN **AT **THE **HEAD **LINE **THEY **MAP **TO**, **⇒⇒† AND **AND **THEY **GO **BEFORE **THE
  # **BLOCK **AT **THAT **LINE**.
  insert_at = {}
  for bi, kept in orphans.items():
    insert_at.setdefault(head_of(bi), []).extend(kept)
  out = []
  i = 0
  b = 0
  while i < len(head_lines):
    if head_lines[i].strip().startswith("#"):
      j = i
      while j < len(head_lines) and head_lines[j].strip().startswith("#"):
        j += 1
      block = head_lines[i:j]
      best = matches[b]
      b += 1
      out.extend(insert_at.pop(i, []))
      if best is not None:
        _bi, _bj, base_block = best
        kept = go.block_keep(base_block, first=(best[0] == 0))
        out.extend(kept)
      else:
        out.extend(block)
      i = j
    else:
      out.extend(insert_at.pop(i, []))
      out.append(head_lines[i])
      i += 1
  for rest in insert_at.values():
    out.extend(rest)
  return out


def main() -> int:
  for n in FILES:
    rel = f"tinybendygrad/uop/{n}.bend"
    base = subprocess.run(["git", "show", f"{BASE}:{rel}"], capture_output=True, text=True, check=True).stdout
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], capture_output=True, text=True, check=True).stdout
    cur = (ROOT / rel).read_text()
    new = rebuild(base.split("\n"), head.split("\n"))
    if code_of(new) != code_of(cur.split("\n")):
      print(f"REFUSED: {rel} -- THE CODE WOULD MOVE", file=sys.stderr)
      return 1
    (ROOT / rel).write_text("\n".join(new))
    bl = sum(1 for l in base.split("\n") if l.strip().startswith("#"))
    hl = sum(1 for l in head.split("\n") if l.strip().startswith("#"))
    nl = sum(1 for l in new if l.strip().startswith("#"))
    print(f"{rel:34s} base {bl:6d}  head {hl:6d}  -> {nl:6d} comment lines")
  return 0


if __name__ == "__main__":
  sys.exit(main())
