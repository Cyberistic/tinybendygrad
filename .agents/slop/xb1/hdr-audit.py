#!/usr/bin/env python3
"""xb1/hdr-audit.py -- every BACKTICK-QUOTED symbol in a .bend file's header ported
list must resolve to a real `def` in that file.

Written because the fallback has already bitten this project: hcq2.bend's header
claims `:455-477 bufferize_cmdbuf PORTED pad128, rt_patch, dword_at` and NOT ONE of
those three names is a def in the file -- it is the `ops_webgpu` case in miniature,
where the header claim is the only thing keeping the claim alive.

A hit is NOT automatically a bug: a row may legitimately name an UPSTREAM python
symbol, a `Tr` tag, a bend builtin, or a def in a sibling. This prints the hits so a
human can classify them, and it prints the exact line so the claim can be fixed where
it lives rather than here.
"""
import pathlib, re, sys

SLOP = pathlib.Path(__file__).resolve().parent


def defs(src):
  return set(re.findall(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(", src, re.M)) | \
         set(re.findall(r"^type ([A-Za-z_][A-Za-z0-9_.]*) is", src, re.M))


for path in sys.argv[1:]:
  p = pathlib.Path(path)
  src = p.read_text()
  have = defs(src)
  # also every def in files it imports, and base.bend's own names
  for m in re.finditer(r'^import "?([\w./-]+\.bend)"? as (\w+)', src, re.M):
    sib = (p.parent / m.group(1)).resolve()
    if sib.exists():
      have |= {f"{m.group(2)}.{d}" for d in defs(sib.read_text())} | defs(sib.read_text())
  print(f"\n=== {path}  ({len(have)} defs reachable)")
  for i, line in enumerate(src.splitlines(), 1):
    if not line.lstrip().startswith("#"):
      continue
    for sym in re.findall(r"`([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)`", line):
      if sym in have:
        continue
      if re.match(r"^(hcq2|device|ops_\w+|nn|render|postrange|heuristic|ops)\.py", sym):
        continue
      if "." in sym or sym[:1].isupper():
        continue  # a sibling/module-qualified name, or a type: classified by reading
      print(f"  {i}: UNRESOLVED `{sym}`   | {line.strip()[:96]}")