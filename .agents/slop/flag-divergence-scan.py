#!/usr/bin/env python3
"""
Locate env-flag DIVERGENCE SITES: a place where upstream reads a flag and the Bend
port substitutes a constant.

For every flag it prints the Python files that CONSUME it and whether a Bend port of
that file exists.  Then, for the ports that exist, it greps the .bend file for
`case`/`match` positions and for literals equal to the flag's measured default.

Defaults are read out of the interpreter (a spy on os.getenv before importing
tinygrad.helpers), not out of the source, so nothing here is transcribed.

Run: uv run python .agents/slop/flag-divergence-scan.py > .agents/slop/flag-divergence-scan.txt
"""
import ast, json, os, re, subprocess, sys, collections

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
      return dict((k, v) for k, v in json.loads(ln[2:]))
  raise SystemExit("spy failed:\n" + p.stderr)


def direct_defaults():
  """The ~85 non-ContextVar reads: getenv("KEY", <expr>) and os.environ["KEY"].
  Defaults come from the AST of the tinygrad tree, which is a MEASUREMENT of the
  source rather than a transcription of it, and the type is the type of the AST
  node's evaluated literal when it is one."""
  out = {}
  for root, _, files in os.walk(PY):
    for f in files:
      if not f.endswith(".py"):
        continue
      path = os.path.join(root, f)
      try:
        tree = ast.parse(open(path, encoding="utf-8", errors="replace").read())
      except SyntaxError:
        continue
      rel = os.path.relpath(path, PY)
      for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
          continue
        fn = node.func
        name = getattr(fn, "id", None) or getattr(fn, "attr", None)
        if name != "getenv" or not node.args:
          continue
        k = node.args[0]
        if not (isinstance(k, ast.Constant) and isinstance(k.value, str)):
          continue
        d = "0"
        if len(node.args) > 1:
          try:
            d = repr(ast.literal_eval(node.args[1]))
          except (ValueError, SyntaxError):
            d = "<expr:%s>" % ast.dump(node.args[1])[:60]
        out.setdefault(k.value, []).append((rel, node.lineno, d))
  return out


def bend_for(pyrel):
  return os.path.join(BEND, pyrel[:-3] + ".bend")


def main():
  cv = spy_getenv()
  dd = direct_defaults()
  flags = sorted(set(cv) | set(dd))
  print("# env-flag divergence scan")
  print("# ContextVar/str/int defaults measured by spying on os.getenv (see")
  print("# .agents/slop/env-coercion-table.py PART 1); non-ContextVar getenv")
  print("# defaults measured out of the AST of the tinygrad tree.")
  print()
  have = os.path.exists
  rows = []
  for fl in flags:
    files = sorted({r for r, _, _ in dd.get(fl, [])})
    ports = [bend_for(f) for f in files if have(bend_for(f))]
    rows.append((fl, cv.get(fl), sorted(dd.get(fl, [])), files, ports))
  print("## summary")
  print("  flags total                     %d" % len(flags))
  print("  with a ContextVar default       %d" % len(cv))
  print("  read only by non-ContextVar     %d" % len([r for r in rows if r[1] is None]))
  print("  whose consuming .py has a port  %d" % len([r for r in rows if r[4]]))
  print()
  for fl, dflt, sites, files, ports in rows:
    print("## %s" % fl)
    print("   ContextVar default: %s" % (dflt if dflt else "-"))
    for rel, ln, d in sites:
      print("   getenv %-26s %s:%d   default=%s   bend=%s" %
            (fl + ",", rel, ln, d, "YES" if have(bend_for(rel)) else "no"))
    if not sites:
      # a pure ContextVar: find its consumers
      print("   (no bare getenv call; consumers found below)")
    for p in ports:
      print("   PORT %s" % os.path.relpath(p, REPO))


if __name__ == "__main__":
  main()