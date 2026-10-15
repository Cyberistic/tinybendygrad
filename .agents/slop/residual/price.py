#!/usr/bin/env python3
"""Price a candidate change to `quoted_spans` (or `needle_kind`) by the guard bar:

    N = FAIL rows retired      M = PASS rows silenced
    M > N  =>  REFUTED and must be reverted.

The verdicts are compared by row identity (lane, file, at, subject, needle) so a
retired FAIL and a newly-FAILing PASS cannot cancel.

usage: .venv/bin/python .agents/slop/residual/price.py
"""
import importlib.util
import re
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

ORIG_SPANS = cc.quoted_spans
ORIG_KIND = cc.needle_kind


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") or c.get("num"))


def run():
  paths = cc.committed()
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    claims, _ = cc.census(paths)
    return [cc.judge(c) for c in claims]


def compare(name, base, var):
  bf = {key(c) for c in base if c.get("verdict") == cc.FAIL}
  vf = {key(c) for c in var if c.get("verdict") == cc.FAIL}
  bp = {key(c) for c in base if c.get("verdict") == cc.PASS}
  vp = {key(c) for c in var if c.get("verdict") == cc.PASS}
  retired, added = bf & vf.__class__(bf) - vf, vf - bf
  silenced, gained = bp - vp, vp - bp
  print(f"== {name}")
  print(f"   FAIL {len(bf)} -> {len(vf)}   N(retired)={len(bf - vf)}  new-FAIL={len(vf - bf)}")
  print(f"   PASS {len(bp)} -> {len(vp)}   M(silenced PASS)={len(bp - vp)}  new-PASS={len(vp - bp)}")
  verdict = "REFUTED" if len(bp - vp) > len(bf - vf) else "PASSES THE BAR"
  print(f"   M={len(bp - vp)} N={len(bf - vf)}  -> {verdict}")
  return bf - vf, bp - vp, vf - bf, vp - bp


def span_drop_apostrophe():
  """A: the `'...'` alternative is gone; only backticks and `"..."` remain."""
  def f(text):
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
    for m in re.finditer(r"\"([^\"]{4,})\"", text):
      out.append((m.start(), m.end(), m.group(1)))
    return sorted(out)
  return f


def span_guard_apostrophe():
  """B: an apostrophe opens a span only when no word character precedes it."""
  def f(text):
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
    for m in re.finditer(r"(?<![A-Za-z0-9])'([^']{4,})'|\"([^\"]{4,})\"", text):
      out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
    return sorted(out)
  return f


def kind_guard_possessive():
  """C: a needle_kind guard -- a needle opening `s ` is a possessive fragment."""
  def f(needle, gap="", line=""):
    if re.match(r"^s\s", needle):
      return "fragment"
    return ORIG_KIND(needle, gap, line)
  return f


base = run()
print(f"BASELINE: PASS={sum(c['verdict'] == 'PASS' for c in base)} "
      f"FAIL={sum(c['verdict'] == 'FAIL' for c in base)} "
      f"rows={len(base)}")
out = ROOT / ".agents/slop/residual"
for name, patch, target in (("A drop `'...'` alternative", span_drop_apostrophe, "quoted_spans"),
                            ("B apostrophe needs no word char before", span_guard_apostrophe, "quoted_spans"),
                            ("C needle_kind guard on `^s `", kind_guard_possessive, "needle_kind")):
  saved = getattr(cc, target)
  setattr(cc, target, patch())
  var = run()
  setattr(cc, target, saved)
  retired, silenced, added, gained = compare(name, base, var)
  with (out / f"price-{name[0]}.rows").open("w") as fh:
    for k in sorted(retired, key=str):
      fh.write("RETIRED\t" + "\t".join(str(x) for x in k) + "\n")
    for k in sorted(silenced, key=str):
      fh.write("SILENCED\t" + "\t".join(str(x) for x in k) + "\n")
    for k in sorted(added, key=str):
      fh.write("NEW-FAIL\t" + "\t".join(str(x) for x in k) + "\n")
    for k in sorted(gained, key=str):
      fh.write("NEW-PASS\t" + "\t".join(str(x) for x in k) + "\n")
