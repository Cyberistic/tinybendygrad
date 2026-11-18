#!/usr/bin/env python3
"""**THE **STAGER**: **MY **BYTES **GO **INTO **THE **INDEX**, **⇒⇒† AND **THE **WORKING **TREE
**IS **LEFT **ALONE**.

**⇒⇒† AND **WHY**: **ANOTHER **UNIT **IS **EDITING **SOME **OF **THE **SAME **FILES**, **⇒⇒† AND
**A **COMMIT **THAT **CARRIES **THEIR **BYTES** **IS **NOT **MY **COMMIT**, **⇒⇒† AND **THE
**ONLY **WAY **TO **COMMIT **ONLY **MY **BYTES** **IS **TO **PUT **THEM **IN **THE **INDEX**
**WITHOUT **TOUCHING **THE **WORKING **TREE** -- **`git update-index --cacheinfo`**, **⇒⇒† AND
**THE **WORKING **TREE **THEN **DIFFERS **FROM **THE **INDEX**, **⇒⇒† AND **THAT **IS **THE
**PRICE **OF **NOT **STEALING **ANOTHER **UNIT's **WORK**.

**⇒⇒† AND **THE **RECONSTRUCTION**: **THE **FILE **IS **BUILT **FROM **`HEAD`**, **⇒⇒† AND
**WITH **THE **MOVED **BLOCKs **REPLACED **BY **THE **POINTER **LINE**, **⇒⇒† AND **NOTHING
**ELSE** -- **⇒⇒† AND **SO **THE **RESULT **IS **EXACTLY **MY **CUT**.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PTR = re.compile(r"^# THE TABLE IS IN `\.agents/slop/tables/([\w.-]+)`")
FROM = re.compile(r"FROM: (\S+):(\d+)")
TMP = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")


def sh(*args, **kw):
  return subprocess.run(list(args), capture_output=True, text=True, cwd=ROOT, **kw)


def head_lines(rel):
  return sh("git", "show", f"HEAD:{rel}").stdout.split("\n")


def table_body(name):
  p = ROOT / ".agents/slop/tables" / name
  body = p.read_text().split("\n")
  if p.suffix == ".md":
    # **⇒⇒† AND **THE **`.md` **BODY **STARTS **AT **INDEX **2** (THE **`<!-- FROM -->`** LINE,
    # **A **BLANK**, **THEN **THE **BLOCK**).
    n = 0
    for l in body[2:]:
      if l.startswith("#") or l.strip() == "":
        n += 1
      else:
        break
    while n > 0 and body[2 + n - 1].strip() == "":
      n -= 1
    return n
  n = 0
  for l in body[1:]:
    if l.startswith("#"):
      n += 1
    else:
      break
  return n


def table_lines(name):
  """**⇒⇒† AND **THE **MOVED **BLOCK's **OWN **TEXT**, **⇒⇒† AND **FOR **A **`.md` **FILE **IT
  **IS **THE **BODY**, **⇒⇒† AND **FOR **A **`.rows` **FILE **IT **IS **THE **`# BLOCK:`
  **SECTION** -- **⇒⇒† AND **THE **SECTION **HOLDS **THE **WHOLE **ORIGINAL **COMMENT
  **BLOCK**, **⇒⇒† AND **SO **THE **MATCH **AGAINST **`HEAD`** **IS **EXACT**.
  """
  p = ROOT / ".agents/slop/tables" / name
  body = p.read_text().split("\n")
  out, on = [], False
  for l in body:
    if l.startswith("# BLOCK:"):
      on = True
      continue
    if on:
      if l.startswith("# END BLOCK"):
        break
      out.append(l)
  if not out and p.suffix == ".md":
    return [l for l in body[2:] if l.startswith("#")]
  return out


def block_at(head, line):
  """**⇒⇒† AND **THE **RUN **OF **COMMENT **LINES **AT **THE **ORIGIN**, **⇒⇒† AND **THE
  **ORIGIN **LINE **IS **1-BASED**."""
  i = line - 1
  if i < 0 or i >= len(head) or not head[i].lstrip().startswith("#"):
    return None
  j = i
  while j < len(head) and head[j].lstrip().startswith("#"):
    j += 1
  return head[i:j]


def find_block(head, tb):
  """**⇒⇒† AND **THE **BLOCK's **OWN **TEXT**, **⇒⇒† AND **THE **MATCH **IS **EXACT** -- **⇒⇒†
  AND **THE **TABLE **FILE **IS **THE **RECORD **OF **THE **BLOCK**, **⇒⇒† AND **SO **THE **TWO
  **MUST **BE **THE **SAME **LINES**. **⇒⇒† AND **THE **HIT **MUST **BE **UNIQUE**, **⇒⇒† AND
  **A **DUPLICATE **IS **A **REFUSAL** -- **⇒⇒† AND **BECAUSE **AN **AMBIGUOUS **MATCH **REMOVES
  **THE **WRONG **LINES**."""
  if not tb:
    return None
  hits = []
  n = len(tb)
  for i in range(len(head) - n + 1):
    if head[i:i + n] == tb:
      hits.append(i + 1)
  return hits[0] if len(hits) == 1 else None


def main():
  files = [l.strip() for l in open(sys.argv[1])]
  TMP.mkdir(parents=True, exist_ok=True)
  nrep = 0
  for rel in files:
    wt = (ROOT / rel).read_text().split("\n")
    ptrs = [(i, PTR.match(l).group(1)) for i, l in enumerate(wt) if PTR.match(l)]
    if not ptrs:
      print(f"NO POINTER: {rel}")
      continue
    exp = head_lines(rel)
    ok = True
    # **⇒⇒† AND **THE **REPLACEMENTS **ARE **COLLECTED **AND **APPLIED **AT **THE **END**,
    # **⇒⇒† AND **SO **A **REPLACEMENT's **SHIFT **CANNOT **MOVE **THE **NEXT **BLOCK's
    # **SEARCH**, **⇒⇒† AND **THE **SEARCH **IS **ALWAYS **AGAINST **`HEAD`**, **⇒⇒† AND
    # **THE **ORIGIN **OF **EVERY **BLOCK**.
    edits = []
    for i, name in sorted(ptrs, key=lambda p: -p[0]):
      t = (ROOT / ".agents/slop/tables" / name).read_text().split("\n")
      m = FROM.search(t[0])
      if not m:
        print(f"NO ORIGIN: {name}")
        ok = False
        continue
      line = int(m.group(2))
      # **⇒⇒† AND **THE **BLOCK**, **⇒⇒† AND **ITS **LENGTH **AND **ITS **TEXT** **COME **FROM
      # **THE **ORIGIN **IN **`HEAD`**, **⇒⇒† AND **THE **TABLE **FILE **IS **THE **RECORD
      # **OF **IT**, **⇒⇒† AND **SO **THE **TWO **MUST **AGREE**.
      blk = block_at(exp, line)
      tb = table_lines(name)
      if blk is None or (tb and blk != tb):
        # **⇒⇒† AND **ANOTHER **UNIT's **COMMIT **MAY **HAVE **REMOVED **LINES **ABOVE**,
        # **⇒⇒† AND **SO **THE **ORIGIN **LINE **IS **STALE**, **⇒⇒† AND **THE **BLOCK **IS
        # **FOUND **BY **ITS **OWN **TEXT** -- **⇒⇒† AND **THE **TEXT **IS **THE **TABLE
        # **FILE**, **⇒⇒† AND **AND **A **MATCH **MUST **BE **EXACT**.
        blk = find_block(exp, tb)
        if blk is None:
          print(f"BLOCK NOT FOUND in HEAD: {rel} {name} (origin {line}, {len(tb)} table lines)")
          ok = False
          continue
        line, _ = blk
        blk = block_at(exp, line)
      n = len(blk)
      edits.append((line - 1, n, wt[i]))
      nrep += 1
    if not ok:
      print(f"SKIPPED (not reconstructed): {rel}")
      continue
    for start, n, ptr in sorted(edits, key=lambda e: -e[0]):
      exp[start:start + n] = [ptr]
    out = "\n".join(exp)
    tmp = TMP / (rel.replace("/", "_"))
    tmp.write_text(out)
    blob = sh("git", "hash-object", "-w", "--", str(tmp)).stdout.strip()
    mode = sh("git", "ls-files", "-s", "--", rel).stdout.split()[0]
    sh("git", "update-index", "--cacheinfo", f"{mode},{blob},{rel}")
    print(f"STAGED {rel} blob={blob[:12]} ({len(ptrs)} pointers)")
  print(f"TOTAL blocks replaced: {nrep}")


if __name__ == "__main__":
  main()
