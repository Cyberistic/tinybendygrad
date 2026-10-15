#!/usr/bin/env python3
"""resid.py -- price the RESIDUAL guards against the guard bar, on the NEW population.

    N = FAIL rows retired     M = PASS rows silenced
    M > N  =>  REFUTED and must be reverted.

NEW = a FAIL whose subject is not a file at `ROOT/<subject>`, i.e. the
suffix-index half that `adfee1a5028e` made measurable (derived from the
pre-patch `read()` read off git, not from a list).

usage: .venv/bin/python .agents/slop/residual/resid.py
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

ORIG_SPANS, ORIG_KIND = cc.quoted_spans, cc.needle_kind
REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
TRACKED = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.splitlines()
IDX: dict[str, list[str]] = {}
for _p in TRACKED:
  _i = _p.find("/")
  while _i != -1:
    IDX.setdefault(_p[_i:], []).append(_p)
    _i = _p.find("/", _i + 1)


def how(subj: str) -> str:
  if REV.match(subj):
    return "rev"
  if (ROOT / subj).is_file():
    return "ROOT-exact"
  hit = IDX.get("/" + subj)
  if hit is None:
    return "absent"
  return "suffix-index" if len(hit) == 1 else f"AMBIGUOUS-{len(hit)}"


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") if c.get("needle") is not None else f"#{c.get('num')}")


def vmap(rows):
  d = defaultdict(Counter)
  for c in rows:
    d[key(c)][c.get("verdict")] += 1
  return d


PATHS = cc.committed()


def run():
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    return [cc.judge(c) for c in cc.census(PATHS)[0]]


def tally(base, var, label):
  b, v = vmap(base), vmap(var)
  keys = set(b) | set(v)
  retired = sum(max(0, b[k][cc.FAIL] - v[k][cc.FAIL]) for k in keys)
  silenced = sum(max(0, b[k][cc.PASS] - v[k][cc.PASS]) for k in keys)
  bnew = sum(max(0, b[k][cc.FAIL] - v[k][cc.FAIL]) for k in keys
             if k[3] and how(k[3]) == "suffix-index")
  bnewp = sum(max(0, b[k][cc.PASS] - v[k][cc.PASS]) for k in keys
              if k[3] and how(k[3]) == "suffix-index")
  fp = sum(b[k][cc.FAIL] for k in keys)
  pp = sum(b[k][cc.PASS] for k in keys)
  vf = sum(v[k][cc.FAIL] for k in keys)
  vp = sum(v[k][cc.PASS] for k in keys)
  print(f"{label:34s} FAIL {fp:4d}->{vf:4d}  N={retired:3d} | PASS {pp:4d}->{vp:4d}  "
        f"M={silenced:3d} | NEW-only N={bnew:3d} M={bnewp:3d} | "
        f"{'REFUTED' if silenced > retired else 'PASSES'}")
  return b, v


# ---------------------------------------------------------------- variants
def spans_A():
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
    for m in re.finditer(r'"([^"]{4,})"', text):
      out.append((m.start(), m.end(), m.group(1)))
    return sorted(out)
  return f


def spans_D():
  """An apostrophe opens a span only after whitespace."""
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
    for m in re.finditer(r"(?<=\s)'([^']{4,})'|\"([^\"]{4,})\"", text):
      out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
    return sorted(out)
  return f


def spans_E():
  """An apostrophe opens a span only when no word char or backtick precedes it."""
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
    for m in re.finditer(r"(?<![\w`])'([^']{4,})'|\"([^\"]{4,})\"", text):
      out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
    return sorted(out)
  return f


def kind_pre_guard1():
  def f(needle, gap="", line=""):
    if needle != needle.strip() or needle[:1] in "),;:]}" or needle[-1:] in "([{.,;:":
      return "fragment"
    return ORIG_KIND(needle, gap, line)
  return f


CELL = re.compile(r"[A-Za-z]+(?:-[A-Za-z]+)*")


def kind_cell_hyphen():
  def f(needle, gap="", line=""):
    k = ORIG_KIND(needle, gap, line)
    t = needle.strip("*… ")
    if (k == "text" and line.lstrip().startswith("|") and CELL.fullmatch(t)
        and not any(ch.isdigit() for ch in t)):
      return "cell-label"
    return k
  return f


base = run()
tf = Counter(c["verdict"] for c in base)
new_fail = sum(1 for c in base if c.get("verdict") == cc.FAIL
               and how(c.get("subject", "")) == "suffix-index")
print(f"BASELINE @ {subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()[:12]}: "
      f"rows={len(base)} PASS={tf[cc.PASS]} FAIL={tf[cc.FAIL]} REFUSED={tf[cc.REFUSED]} "
      f"SKIP={tf[cc.SKIP]} | NEW-FAIL={new_fail}")
print()
print("--- needle_kind variants (one census, re-judge)")
for label, patch in (("pre-guard-1 (no \\n rule)", kind_pre_guard1),
                     ("cell-label accepts hyphen", kind_cell_hyphen)):
  cc.needle_kind = patch()
  var = run()
  cc.needle_kind = ORIG_KIND
  tally(base, var, label)

print()
print("--- quoted_spans variants (re-extract; the extractor feeds lane C)")
for label, patch in (("A drop '...' alternative", spans_A),
                     ("D apostrophe after whitespace", spans_D),
                     ("E apostrophe not after word/`", spans_E)):
  cc.quoted_spans = patch()
  var = run()
  cc.quoted_spans = ORIG_SPANS
  b, v = tally(base, var, label)
  out = ROOT / f".agents/slop/residual/price-{label[0]}.rows"
  with out.open("w") as fh:
    for k in sorted(set(b) | set(v), key=str):
      for verdict, n in (v[k] - b[k]).items():
        fh.write(f"GAINED-{verdict}\t" + "\t".join(str(x) for x in k) + f"\t{n}\n")
      for verdict, n in (b[k] - v[k]).items():
        fh.write(f"LOST-{verdict}\t" + "\t".join(str(x) for x in k) + f"\t{n}\n")
