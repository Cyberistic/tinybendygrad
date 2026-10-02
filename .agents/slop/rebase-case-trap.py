#!/usr/bin/env python3
"""Every identifier the landing batch adds or removes, and whether any PORT arms on it.

The trap this exists for: a `case`/pattern that stops matching does not FAIL, it falls
through to the next arm, which is usually a DIFFERENT answer. So the check that matters is
"does any port have this identifier in CASE POSITION", not "does any port mention it".

Two kinds of hit are reported separately, because they fail differently:
  * case-position  -- a `case X:` / `match X` arm naming the identifier: a silent fall-through
  * bare read      -- `X.something` with no case to grep for: an AttributeError at best and,
                      for a FALLBACK like `type_map.get(k, k.name)`, a silently WRONG VALUE
"""
import ast, re, subprocess as sp, sys
from pathlib import Path
REPO = Path(sys.argv[1]).resolve()
BATCH = sys.argv[2:]

HEAD = sp.check_output(["git", "rev-parse", "upstream/master"], cwd=REPO, text=True).strip()


def added_removed(path):
  """Identifiers defined/imported at HEAD but not in our copy, and vice versa."""
  ours = (REPO / path).read_text()
  head = sp.check_output(["git", "show", f"{HEAD}:{path}"], cwd=REPO, text=True)
  def names(src):
    out = set()
    try: tree = ast.parse(src)
    except SyntaxError: return out
    for n in ast.walk(tree):
      if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)): out.add(n.name)
      elif isinstance(n, ast.Assign):
        for t in n.targets:
          if isinstance(t, ast.Name): out.add(t.id)
          elif isinstance(t, ast.Attribute): out.add(t.attr)
      elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name): out.add(n.target.id)
      elif isinstance(n, ast.ImportFrom):
        for a in n.names: out.add(a.asname or a.name)
      elif isinstance(n, ast.Import):
        for a in n.names: out.add((a.asname or a.name).split(".")[0])
    return out
  a, b = names(ours), names(head)
  return sorted(b - a), sorted(a - b)


def locals_of(paths):
  """Every name BOUND inside the changed Python: assignments, params, comprehensions.

  Without this the sweep is a liar. `ast` collects assignments, so upstream's `for p in ...`
  or `amd_push(..., q, ...)` puts single letters like `p`, `q`, `s` in the identifier diff,
  and then every `match p:` in a port is reported as a case-position arm on a renamed symbol.
  The first run of this tool produced exactly that -- 20 hits, every one a Python local --
  and a sweep that cries wolf gets ignored, which is the outcome this file exists to prevent.
  A name is only a coupling candidate if it is NOT a local anywhere in the changed files.
  """
  bound = set()
  for path in paths:
    try: tree = ast.parse((REPO / path).read_text())
    except (SyntaxError, OSError): continue
    for n in ast.walk(tree):
      if isinstance(n, ast.Name) and isinstance(n.ctx, (ast.Store, ast.Del)): bound.add(n.id)
      elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
        a = n.args
        for arg in [*a.posonlyargs, *a.args, *a.kwonlyargs, a.vararg, a.kwarg]:
          if arg: bound.add(arg.arg)
      elif isinstance(n, ast.Lambda):
        a = n.args
        for arg in [*a.posonlyargs, *a.args, *a.kwonlyargs, a.vararg, a.kwarg]:
          if arg: bound.add(arg.arg)
      elif isinstance(n, (ast.comprehension,)):
        for t in ast.walk(n.target):
          if isinstance(t, ast.Name): bound.add(t.id)
      elif isinstance(n, ast.ExceptHandler) and n.name: bound.add(n.name)
  return bound


def port_for(path):
  b = REPO / "tinybendygrad" / path[len("tinygrad/"):].replace(".py", ".bend")
  return b if b.exists() else None


CASE_RE = re.compile(r"^\s*(case|match)\s+(.*)$")
print(f"HEAD {HEAD[:12]}   batch of {len(BATCH)} files\n")
bound = locals_of(BATCH)
hot = []
for f in BATCH:
  add, rem = added_removed(f)
  # a name upstream also binds locally is a local, not a moved symbol
  add = [n for n in add if n not in bound]
  rem = [n for n in rem if n not in bound]
  if not add and not rem: continue
  print(f"  {f}")
  if add: print(f"      + {', '.join(add)}")
  if rem: print(f"      - {', '.join(rem)}")
  hot += [(f, n, "ADDED") for n in add] + [(f, n, "REMOVED") for n in rem]
print(f"\n  {len(hot)} identifier events, {len(bound)} Python locals excluded\n")

# Which PORTS have any of these names in CASE position?
ports = sorted({p for p in (port_for(f) for f in BATCH) if p})
print(f"  scanning {len(ports)} ports for case-position arms\n")
hits = 0
for p in ports:
  for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
    m = CASE_RE.match(line)
    if not m: continue
    scrut = m.group(2)
    for src, name, kind in hot:
      if re.search(rf"(?<![\w.]){re.escape(name)}(?![\w])", scrut):
        print(f"    CASE-POSITION  {p.relative_to(REPO)}:{i}  [{kind} in {src}]")
        print(f"        {line.strip()[:110]}")
        hits += 1
print(f"  case-position hits: {hits}")

# And the bare reads -- no case to grep for, so grep the name and read the CONTEXT.
print("\n  bare reads / mentions in the same ports:")
for p in ports:
  for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
    st = line.strip()
    if st.startswith("#") or st.startswith("//"): continue
    if CASE_RE.match(line): continue
    for src, name, kind in hot:
      if re.search(rf"(?<![\w.]){re.escape(name)}(?![\w])", line):
        print(f"    {p.relative_to(REPO)}:{i}  [{kind} in {src}]  {st[:100]}")
        break
