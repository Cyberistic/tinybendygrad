#!/usr/bin/env python3
"""**THE **PARAGRAPH **CUTTER** -- **THE **APPLIER **FOR **`para-apply.py`'s **PLAN**, **⇒⇒† AND
**IT **NEVER **REWRITES **A **KEPT **LINE**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT/".agents/slop/comments/runtime-lane"))
_spec = importlib.util.spec_from_file_location("ta", ROOT/".agents/slop/comments/trim-apply.py")
ta = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ta)
_cc = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(_cc); _cc.loader.exec_module(cc)

def paragraphs(blk):
  out, cur = [], []
  for line in blk:
    if line.strip() == "#":
      if cur: out.append(cur)
      out.append([line]); cur = []
    else: cur.append(line)
  if cur: out.append(cur)
  return out

def marker(p): return any(ta.is_marker(l) for l in p if l.strip() != "#")

def first_sentence(p):
  body = [l for l in p if l.strip() != "#"]
  if not body: return len(p)
  return ta.sentence_end(body, 0)

def cut_block(blk):
  """**THE **CUT **BLOCK**, **AND **THE **NUMBER **OF **LINES **REMOVED**."""
  out = []
  for p in paragraphs(blk):
    if all(l.strip() == "#" for l in p):
      if out and out[-1].strip() == "#": continue
      out.extend(p); continue
    if marker(p): out.extend(p); continue
    n = first_sentence(p)
    out.extend(p[:n])
  # **⇒⇒† AND **THE **KEPT **SECTION **MUST **NOT **END **ON **A **LEAD-IN** -- **⇒⇒† AND
  # **A **HEADER **WITH **NO **BODY **IS **WORSE **THAN **NOTHING**.
  while out and out[-1].strip() == "#": out.pop()
  return out

only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
dry = "--dry" in sys.argv
PORT = ROOT/"tinybendygrad"
tot = 0
for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith(only): continue
    lines = f.read_text().split("\n")
    out = []
    n = 0
    i = 0
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
    if n and not dry:
        f.write_text("\n".join(out))
    if n: print(f"{n:7d}  {rel}")
    tot += n
print(f"THE LINES CUT: {tot}")
