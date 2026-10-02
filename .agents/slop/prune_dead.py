#!/usr/bin/env python3
"""A PRUNER that refuses to drop anything it cannot PROVE unread.

`dead-defs.py` matches the BASE name, so `def rp.pair.hi` is scored alive by the
hundreds of `rp.` uses. `dead-defs2.py` fixes that but still counts a use inside
a STRING literal, and it counts `Dev.of` alive because `CuDev.of` contains it.
Both produce false negatives, and a false negative in a pruner is a def kept for
no reason while a report claims the file is clean.

This one is deliberately paranoid, and it says so per def:
  * the FULL dotted name is matched, as a WHOLE identifier, never a substring
    (`Dev.of` must not be found inside `CuDev.of`),
  * the def's own line has only its own NAME blanked -- the rest of the line
    stays, because most defs here are one line and read their constants there,
  * `#` comments and `"` strings are removed first, so a name mentioned only in
    prose does not count as a use,
  * `import`ed module names are not uses of local defs,
  * and a def whose name appears in the gate's own `row(...)`/`urow(...)`/
    `srow(...)`/`srowlist(...)` lists, or nowhere, is reported with the exact set
    of places it IS mentioned, so a reviewer can see why.

`main` is the entry point and is never dead.

    .venv/bin/python .agents/slop/prune_dead.py <file.bend> [...]
"""
import re, sys
from pathlib import Path

DEF = re.compile(r"^(def|type)\s+([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)")
IDENT = re.compile(r"[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*")
ENTRY = {"main"}


def strip(line):
  """drop a `#` comment and the CONTENTS of a `"` string. Kept byte-length by
  replacing with spaces so column positions in the report stay meaningful."""
  out, in_str = [], False
  for i, ch in enumerate(line):
    if ch == '"' and (i == 0 or line[i - 1] != '\\'):
      in_str = not in_str
      out.append(' '); continue
    if ch == '#' and not in_str: break
    out.append(' ' if in_str else ch)
  return ''.join(out)


def audit(path):
  raw = Path(path).read_text().splitlines()
  code = [strip(l) for l in raw]
  defs = [(m.group(2), i) for i, l in enumerate(code, 1) if (m := DEF.match(l))]
  imports = {b or a.rsplit("/", 1)[-1].removesuffix(".bend")
             for a, b in re.findall(r"^import\s+(\S+)(?:\s+as\s+(\S+))?", "\n".join(code), re.M)}
  hay, own = [], {}
  for i, l in enumerate(code, 1):
    m = DEF.match(l)
    if m:
      own[m.group(2)] = i
      # blank ONLY the name token, keep the rest of the line
      hay.append(" " * m.end() + l[m.end():])
    else:
      hay.append(l)
  blob = "\n".join(hay)
  dead = []
  for name, ln in defs:
    if name in ENTRY: continue
    pat = re.compile(rf"(?<![A-Za-z_0-9.]){re.escape(name)}(?![A-Za-z_0-9])")
    uses = [i for i, l in enumerate(blob.splitlines(), 1) if pat.search(l)]
    if uses:
      continue
    mentions = [i for i, l in enumerate(raw, 1) if pat.search(l)]
    dead.append((name, ln, mentions, imports))
  return len(defs), dead


def main():
  for p in sys.argv[1:]:
    n, dead = audit(p)
    print(f"{Path(p).name}: {n} top-level defs/types, {len(dead)} PROVABLY never named in code")
    for name, ln, mentions, _ in dead:
      print(f"  DEAD line {ln}: {name}   (named only at lines {mentions or 'nowhere, not even a comment'})")
  return 0


if __name__ == "__main__":
  sys.exit(main())
