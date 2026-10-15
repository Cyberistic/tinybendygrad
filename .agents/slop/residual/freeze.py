#!/usr/bin/env python3
"""freeze.py -- the landed guard's price on a FROZEN snapshot, so a live writer cannot
move the verdict between the two passes.  Both passes extract from ONE in-memory text
and one memoized `read()`.

usage: .venv/bin/python .agents/slop/residual/freeze.py
"""
import importlib.util
import re
import subprocess
import warnings
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

FIXED = cc.quoted_spans
PATHS = cc.committed()
SNAP = {rel: (ROOT / rel).read_text(errors="replace") for rel in PATHS}
READS: dict[str, str | None] = {}
REAL_READ = cc.read


def frozen_read(rel):
  if rel not in READS:
    READS[rel] = REAL_READ(rel)
  return READS[rel]


cc.read = frozen_read
REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
TRACKED = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.splitlines()
IDX: dict[str, list[str]] = {}
for _p in TRACKED:
  _i = _p.find("/")
  while _i != -1:
    IDX.setdefault(_p[_i:], []).append(_p)
    _i = _p.find("/", _i + 1)


def how(s):
  if REV.match(s):
    return "rev"
  if (ROOT / s).is_file():
    return "ROOT-exact"
  h = IDX.get("/" + s)
  return "absent" if h is None else ("suffix-index" if len(h) == 1 else f"AMBIG-{len(h)}")


def spans_reverted(text):
  out, i = [], 0
  while True:
    a = text.find("`", i)
    if a < 0:
      break
    b = text.find("`", a + 1)
    if b < 0:
      break
    out.append((a, b + 1, text[a + 1:b]))
    i = b + 1
  for m in re.finditer(r"\"([^\"]{4,})\"|'([^']{4,})'", text):
    out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
  return sorted(out)


def pass_():
  rows = []
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    for rel, text in SNAP.items():
      cls = cc.lane_a(rel, text) if rel.endswith(".py") else []
      cls += cc.lane_bcd(rel, cc.prose(rel, text))[0]
      rows += [cc.judge(c) for c in cls]
  return rows


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") if c.get("needle") is not None else f"#{c.get('num')}")


after = pass_()
cc.quoted_spans = spans_reverted
before = pass_()
cc.quoted_spans = FIXED
bp, ap = Counter(c["verdict"] for c in before), Counter(c["verdict"] for c in after)
print(f"FROZEN SNAPSHOT: {len(PATHS)} files, {len(before)} vs {len(after)} rows")
print(f"BEFORE  PASS={bp[cc.PASS]} FAIL={bp[cc.FAIL]} REFUSED={bp[cc.REFUSED]} SKIP={bp[cc.SKIP]}")
print(f"AFTER   PASS={ap[cc.PASS]} FAIL={ap[cc.FAIL]} REFUSED={ap[cc.REFUSED]} SKIP={ap[cc.SKIP]}")
b, a = defaultdict(Counter), defaultdict(Counter)
for c in before:
  b[key(c)][c["verdict"]] += 1
for c in after:
  a[key(c)][c["verdict"]] += 1
keys = set(b) | set(a)
for tag, ver in (("RETIRED-FAIL", cc.FAIL), ("SILENCED-PASS", cc.PASS)):
  lost = [k for k in keys if b[k][ver] > a[k][ver]]
  n = sum(b[k][ver] - a[k][ver] for k in lost)
  nn = sum(1 for k in lost if k[3] and how(k[3]) == "suffix-index")
  print(f"{tag:14s} {n:3d} rows ({nn} NEW/suffix-index)")
for k in sorted(keys, key=str):
  if b[k][cc.PASS] > a[k][cc.PASS]:
    print(f"      silenced {k[1]}:{k[2]} {k[3]} {k[4]!r} {how(k[3])}")
# THE NEEDLE CHANGES, SO A ROW CANNOT BE PAIRED BY KEY.  Pair by the ANCHOR the census
# reports (claiming file + line + subject), which is the only identity a row keeps when
# the extractor chooses a different span.
gb, ga = defaultdict(list), defaultdict(list)
for c in before:
  gb[(c["lane"], c["file"], c["at"], c["subject"])].append(c["verdict"])
for c in after:
  ga[(c["lane"], c["file"], c["at"], c["subject"])].append(c["verdict"])
trans = Counter()
for k in set(gb) | set(ga):
  if sorted(gb[k]) != sorted(ga[k]):
    trans[(tuple(sorted(gb[k])), tuple(sorted(ga[k])))] += 1
print("ANCHOR TRANSITIONS (rows whose verdict multiset moved):")
for (x, y), n in trans.most_common():
  print(f"  {n:4d}  {list(x)} -> {list(y)}")
out = Path(__file__).resolve().parent / "frozen.rows"
with out.open("w") as fh:
  for tag, ver in (("RETIRED-FAIL", cc.FAIL), ("SILENCED-PASS", cc.PASS),
                   ("RECOVERED-PASS", cc.PASS)):
    for k in sorted(keys, key=str):
      d = (b[k][ver] - a[k][ver]) if tag != "RECOVERED-PASS" else (a[k][ver] - b[k][ver])
      if d > 0:
        fh.write(f"{tag}\t" + "\t".join(str(x) for x in k) + f"\t{how(k[3])}\n")
print(f"-> {out}")
