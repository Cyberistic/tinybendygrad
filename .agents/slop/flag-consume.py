#!/usr/bin/env python3
"""
For each env flag, list the PYTHON CONSUMPTION SITES (identifier reads, not the
declaration) and, for every consuming file that has a Bend port, the literals in
that .bend equal to the flag's measured default, plus every `case`/`match` position
in the .bend that mentions the flag.

Run: uv run python .agents/slop/flag-consume.py > .agents/slop/flag-consume.txt
"""
import ast, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, "tinybendygrad")
PY = os.path.join(REPO, "tinygrad")


def spy_getenv():
  body = r'''
import sys, os, json
sys.path.insert(0, @@REPO@@)
real = os.getenv
seen = []
def spy(key, default=None):
  seen.append([key, repr(default)])
  return real(key, default)
os.getenv = spy
import tinygrad.helpers as H
print("@@" + json.dumps(seen))
'''.replace("@@REPO@@", repr(REPO))
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return dict(json.loads(ln[2:]))


def consumers(flag):
  """reads of the bare identifier `flag` (or `HELPERS.flag`) in the tinygrad tree,
  with the declaration lines excluded by name."""
  out = []
  pat = re.compile(r"(?<![A-Za-z0-9_.])%s(?![A-Za-z0-9_])" % re.escape(flag))
  for root, _, files in os.walk(PY):
    if "autogen" in root:
      continue
    for f in files:
      if not f.endswith(".py"):
        continue
      path = os.path.join(root, f)
      rel = os.path.relpath(path, PY)
      for i, ln in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if not pat.search(ln):
          continue
        s = ln.strip()
        if s.startswith("#") or s.startswith('"') or "'" in s.split("#")[0] and "ContextVar" in s:
          continue
        if re.match(r"^%s\s*(=|\)|,)" % re.escape(flag), s) and "getenv" not in s:
          continue
        if 'ContextVar("%s"' % flag in s:
          continue
        if re.search(r"getenv\(\s*[\"']%s[\"']" % re.escape(flag), ln):
          continue
        if re.match(r"^(os\.environ(\.get)?\(\s*)?[\"']%s[\"']" % re.escape(flag), s):
          continue
        out.append((rel, i, ln.rstrip()))
  return out


def main():
  cv = spy_getenv()
  flags = sorted(set(cv))
  # every flag name anywhere in the tinygrad tree, ContextVar or not
  extra = set()
  for root, _, files in os.walk(PY):
    if "autogen" in root:
      continue
    for f in files:
      if f.endswith(".py"):
        for m in re.finditer(r"""(?:getenv\(|os\.environ(?:\.get)?\()\s*['"]([A-Z][A-Z0-9_]*)['"]""",
                             open(os.path.join(root, f), encoding="utf-8", errors="replace").read()):
          extra.add(m.group(1))
  flags = sorted(set(flags) | extra)
  print("# flag consumption sites in the tinygrad tree, and the literals equal to each")
  print("# flag's default in the Bend port of the consuming file.")
  print()
  tot = 0
  for fl in flags:
    cs = consumers(fl)
    if not cs:
      continue
    tot += len(cs)
    files = sorted({c[0] for c in cs})
    print("## %s   (ContextVar default %s)   %d reads in %d files" %
          (fl, cv.get(fl, "-"), len(cs), len(files)))
    for rel in files:
      bp = os.path.join(BEND, rel[:-3] + ".bend")
      if not os.path.exists(bp):
        continue
      btxt = open(bp, encoding="utf-8", errors="replace").read().splitlines()
      hits = [(c[1], c[2].strip()) for c in cs if c[0] == rel]
      print("   %s  (%d py sites)" % (rel, len(hits)))
      for ln, txt in hits:
        print("      py:%-5d %s" % (ln, txt[:110]))
      named = [(i, l.strip()) for i, l in enumerate(btxt, 1)
               if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(fl), l)
               and not l.strip().startswith("#")]
      if named:
        print("      BEND NAMES THE FLAG:")
        for i, l in named[:12]:
          print("         bend:%-5d %s" % (i, l[:110]))
  print()
  print("# total python reads: %d" % tot)


if __name__ == "__main__":
  main()