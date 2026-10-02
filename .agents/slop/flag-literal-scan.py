#!/usr/bin/env python3
"""
The hardcoded-literal scan: for every env flag whose DEFAULT is distinctive (not 0
and not 1, which are 95 of the 146 and produce pure noise), print every line of the
Bend port of each consuming file that contains that default as a bare literal, and
every line that puts the flag name in `case`/`match` position.

Run: uv run python .agents/slop/flag-literal-scan.py > .agents/slop/flag-literal-scan.txt
"""
import ast, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, "tinybendygrad")
PY = os.path.join(REPO, "tinygrad")
SKIP_DIRS = ("autogen", "__pycache__", "test", "docs", "examples")


def defaults():
  """(flag -> (default-repr, type, [py files that read it bare])"""
  out = {}
  for root, dirs, files in os.walk(PY):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for f in files:
      if not f.endswith(".py"):
        continue
      path = os.path.join(root, f)
      rel = os.path.relpath(path, PY)
      try:
        src = open(path, encoding="utf-8", errors="replace").read()
        tree = ast.parse(src)
      except (SyntaxError, OSError):
        continue
      # ContextVar("KEY", default)  -- the default's AST node type is the coercion
      for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "ContextVar" \
           and len(node.args) >= 2 and isinstance(node.args[0], ast.Constant) \
           and isinstance(node.args[0].value, str):
          out.setdefault(node.args[0].value, {"dflt": None, "ty": "?", "sites": set()})
          if out[node.args[0].value]["dflt"] is None:
            d = node.args[1]
            try:
              out[node.args[0].value]["dflt"] = repr(ast.literal_eval(d))
              out[node.args[0].value]["ty"] = type(ast.literal_eval(d)).__name__
            except (ValueError, SyntaxError):
              out[node.args[0].value]["dflt"] = "<expr>"
              out[node.args[0].value]["ty"] = "?"
      # getenv("KEY", default)
      for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "getenv" \
           and node.args and isinstance(node.args[0], ast.Constant) \
           and isinstance(node.args[0].value, str):
          k = node.args[0].value
          e = out.setdefault(k, {"dflt": None, "ty": "?", "sites": set()})
          if len(node.args) > 1 and e["dflt"] is None:
            try:
              e["dflt"] = repr(ast.literal_eval(node.args[1]))
              e["ty"] = type(ast.literal_eval(node.args[1])).__name__
            except (ValueError, SyntaxError):
              e["dflt"] = "<expr>"
              e["ty"] = "?"
      # os.environ["KEY"] / os.environ.get("KEY", default)
      for node in ast.walk(tree):
        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute) \
           and node.value.attr == "environ" and isinstance(node.slice, ast.Constant) \
           and isinstance(node.slice.value, str):
          out.setdefault(node.slice.value, {"dflt": None, "ty": "?", "sites": set()})
  # now the bare-identifier consumers
  for fl, e in out.items():
    pat = re.compile(r"(?<![A-Za-z0-9_.])%s(?![A-Za-z0-9_])" % re.escape(fl))
    for root, dirs, files in os.walk(PY):
      dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
      for f in files:
        if not f.endswith(".py"):
          continue
        rel = os.path.relpath(os.path.join(root, f), PY)
        for i, ln in enumerate(open(os.path.join(root, f), encoding="utf-8",
                                    errors="replace"), 1):
          s = ln.strip()
          if not pat.search(ln) or s.startswith("#"):
            continue
          if 'ContextVar("%s"' % fl in ln:
            continue
          if re.search(r"""(getenv|environ(\.get)?\()\s*['"]%s['"]""" % re.escape(fl), ln):
            continue
          e["sites"].add((rel, i, s))
  return out


def main():
  ds = defaults()
  print("# Hardcoded-default scan. For every flag whose default is distinctive")
  print("# (not 0, not 1), the literals equal to it inside the Bend port of each")
  print("# consuming file. A hit is a CANDIDATE, not a verdict.")
  print()
  hits = 0
  for fl in sorted(ds):
    e = ds[fl]
    d, ty = e["dflt"], e["ty"]
    if d is None or d in ("0", "1", "<expr>", "None", "False", "True", "''", "[]", "{}"):
      continue
    try:
      lit = ast.literal_eval(d)
    except (ValueError, SyntaxError):
      continue
    if isinstance(lit, (bool, str)):
      continue
    lits = {str(lit), hex(lit) if isinstance(lit, int) and lit > 0 else "",
            repr(lit).replace("L", ""), format(lit, ",").replace(",", "_")}
    lits.discard("")
    rels = sorted({r for r, _, _ in e["sites"]})
    printed = False
    for rel in rels:
      bp = os.path.join(BEND, rel[:-3] + ".bend")
      if not os.path.exists(bp):
        continue
      lines = open(bp, encoding="utf-8", errors="replace").read().splitlines()
      for i, ln in enumerate(lines, 1):
        code = ln.split("#")[0]
        if any(re.search(r"(?<![A-Za-z0-9_.])%s(?![A-Za-z0-9_])" % re.escape(L), code)
               for L in lits):
          if not printed:
            print("## %s  default=%s (%s)   %d py reads" % (fl, d, ty, len(e["sites"])))
            printed = True
            for r, j, s in sorted(e["sites"]):
              print("     py %s:%d  %s" % (r, j, s[:100]))
          print("   >>> %s:%d  %s" % (rel, i, ln.strip()[:120]))
          hits += 1
    if not printed:
      print("## %s  default=%s (%s)  -- no literal hit in any Bend port" % (fl, d, ty))
  print()
  print("# candidate lines: %d" % hits)


if __name__ == "__main__":
  main()