#!/usr/bin/env python
"""DISCOVER the caches, not name them.

Two independent populations, because a cache is a wrong-shaped thing to find and one
instrument naming them by hand would be the same class again:

  (c) WRITE SITES -- AST over every `.py` in the four trees plus shell redirects, taking the
      target DIRECTORY out of the expression that BUILDS THE PATH.  For a method call
      `recv.write_text(content)` the target is the RECEIVER, not the content; for `open(path,
      "w")` it is the first argument.  (Getting that backwards was this file's own first
      measurement, and it reported the CONTENT of 166 sites as if it were their path.)
  (b) DIRECTORY WALK -- occupancy of the directory each keyed site names.

A keyed site (f-string, `+`, `/`, a variable) is a CACHE CANDIDATE: the path varies, so the
directory holds a population and can go stale.  A literal-path site is an ARTIFACT: one file,
one run, no population."""
import ast, os, pathlib, re, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[3]
TREES = ("checks", "gates", "oracles", "runs")
WRITE = ("write_text", "write_bytes", "writelines")


def lit(node):
  return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def unparse(node):
  try:
    return ast.unparse(node)
  except Exception:
    return "<unparseable>"


def py_sites():
  out = []
  for tree in TREES:
    for p in sorted((ROOT / tree).rglob("*.py")):
      try:
        t = ast.parse(p.read_text())
      except SyntaxError:
        continue
      for n in ast.walk(t):
        if not isinstance(n, ast.Call):
          continue
        f = n.func
        attr = f.attr if isinstance(f, ast.Attribute) else ""
        mode = lit(n.args[1]) if (attr == "open" and len(n.args) > 1) else None
        if attr in WRITE and isinstance(f, ast.Attribute):
          target = unparse(f.value)          # the RECEIVER is the path; args[0] is the content
        elif attr == "open" and mode and "w" in mode and n.args:
          target = unparse(n.args[0])
        else:
          continue
        out.append((tree, str(p.relative_to(ROOT)), n.lineno, attr, target, lit(n.args[0] if n.args else None) is not None and attr != "open"))
  return out


SH = re.compile(r"(?<![0-9<>])>>?\s*(?:\"([^\"]+)\"|'([^']+)'|([A-Za-z_][\w./{}$-]*))")


def sh_sites():
  out = []
  for tree in TREES:
    for p in sorted((ROOT / tree).rglob("*.sh")):
      for i, ln in enumerate(p.read_text().splitlines(), 1):
        if ln.lstrip().startswith("#"):
          continue
        m = SH.search(ln)
        if m:
          tgt = next(g for g in m.groups() if g)
          out.append((tree, str(p.relative_to(ROOT)), i, "redirect", tgt,
                      not ("{" in tgt or "$" in tgt or "*" in tgt)))
  return out


def target_dir(tree, expr):
  """The DIRECTORY a target expression names, or None.  Only a name that looks like a path is
  accepted: a bare `text` is a variable, not a directory, and guessing would invent one."""
  m = re.search(r"['\"]([^'\"]*?/?)['\"]", expr)
  if m and ("/" in m.group(1) or m.group(1)):
    rel = m.group(1)
  else:
    m2 = re.match(r"^([A-Za-z_][\w.]*)", expr)
    if not m2:
      return None
    return ("UNRESOLVED:" + m2.group(1))
  return rel if rel.startswith(("checks/", "gates/", "oracles/", "runs/", ".agents/")) else f"{tree}/{rel}"


def main():
  sites = py_sites() + sh_sites()
  keyed = [s for s in sites if not s[5]]
  print(f"WRITE SITES over {len(TREES)} trees ({', '.join(TREES)}), AST + shell redirects")
  print(f"  write sites total                     : {len(sites)}")
  print(f"  LITERAL path  -> an ARTIFACT, no pop. : {len(sites) - len(keyed)}")
  print(f"  KEYED path    -> CACHE CANDIDATE       : {len(keyed)}")
  print()
  dirs = collections.Counter()
  print(f"{'site':<46} {'target expr':<44} {'dir':<30} files topshape")
  for tree, path, ln, callee, tgt, _ in sorted(keyed, key=lambda s: (s[1], s[2])):
    d = target_dir(tree, tgt)
    if d is None or d.startswith("UNRESOLVED"):
      print(f"  {path}:{ln:<5} {tgt:<44} {d or '?':<30}   -- no path in the expression, skipped")
      continue
    p = ROOT / d.rstrip("/")
    try:
      names = [q.name for q in p.iterdir() if q.is_file()]
    except OSError:
      names = []
    shapes = collections.Counter(re.sub(r"[A-Za-z0-9_.]*\d[A-Za-z0-9_.]*", "*", n) for n in names)
    top = shapes.most_common(1)[0][1] if shapes else 0
    dirs[d] += 1
    print(f"  {path+':'+str(ln):<46} {tgt[:42]:<44} {d:<30} {len(names):<5} {top}")
  print()
  print(f"DISTINCT DIRECTORIES written by keyed sites: {len(dirs)}")
  for d, n in sorted(dirs.items(), key=lambda kv: -kv[1]):
    print(f"  {n:>3} sites -> {d}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
