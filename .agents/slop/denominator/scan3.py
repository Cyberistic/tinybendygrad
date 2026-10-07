#!/usr/bin/env python3
"""scan3.py -- WHICH CANDIDATES CAN ACTUALLY REACH AN EMPTY POPULATION *TODAY*.

`scan2.py`'s guard classifier was wrong twice -- it cleared `checks/dup-census.py` once and
`checks/dup-gate.py` once, in opposite directions, and **a classifier that cannot classify the
two cases this report is built from is not a census.**  So the tranche is not chosen by a
regex at all.

IT IS CHOSEN BY THE TREE.  For every candidate module, take the ARGUMENT of each population
constructor (`glob`/`rglob`/`walk`) as a literal, resolve it against the repo, and MEASURE how
many entries it yields.  A module whose population source is ABSENT or yields 0 is a gate that
CAN go vacuously green the moment it is next run -- and that is the tranche, chosen by the
state of the tree rather than by a judgement about code.

Emits `reach.tsv`.  A non-literal glob is reported as UNRESOLVED and never silently counted.
"""
import ast, os, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
ROOTS = ("checks", "gates")
EXCL = (".agents", "references", "node_modules", ".git", ".venv", "__pycache__")
POP_CALLS = {"glob", "rglob", "walk", "listdir", "iterdir"}


def population():
  for root in ROOTS:
    for dirpath, dirnames, filenames in os.walk(REPO / root):
      dirnames[:] = [d for d in dirnames if d not in EXCL]
      for fn in sorted(filenames):
        if fn.endswith(".py"):
          yield pathlib.Path(dirpath) / fn


def pop_sources(tree, src):
  """(line, literal-or-None, pattern) for every population constructor call."""
  out = []
  for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
       and node.func.attr in POP_CALLS:
      pat = None
      if node.args:
        a = node.args[0]
        if isinstance(a, ast.Constant) and isinstance(a.value, str):
          pat = a.value
        elif isinstance(a, ast.BinOp) and isinstance(a.op, ast.Div):
          pat = "".join(x.value for x in (a.left, a.right) if isinstance(x, ast.Constant))
      out.append((node.lineno, pat, node.func.attr))
      if node.func.attr == "glob" and node.args and isinstance(node.args[0], ast.Call):
        out.append((node.lineno, pat, "glob(inner)"))
  return out


def resolve(pat, modpath):
  """Entries under the literal, resolved against the module's own directory then the repo."""
  base = (modpath.parent / pat).resolve()
  if base.exists():
    return str(base.relative_to(REPO)) if REPO in base.parents or base == REPO else str(base), True
  alt = (REPO / pat).resolve()
  if alt.exists():
    return str(alt.relative_to(REPO)), True
  return None, False


def count(pat, modpath):
  """How many entries the literal actually yields.  globs get an expansion, others a listing."""
  for base in ((modpath.parent / pat).resolve(), (REPO / pat).resolve()):
    if not base.exists():
      continue
    if any(c in pat for c in "*?["):
      hits = [q for q in base.parent.glob(pat) if q.exists()] if base.parent.exists() else []
      return len(hits), True
    if base.is_dir():
      return sum(1 for _ in base.iterdir()), True
    return 1, True
  return 0, False


def main():
  cands = {r.split("\t")[0] for r in
           (HERE / "sites.tsv").read_text().splitlines()[1:] if r.strip()}
  rows = []
  for p in sorted(population()):
    rel = str(p.relative_to(REPO))
    if rel not in cands:
      continue
    src = p.read_text(errors="replace")
    try:
      tree = ast.parse(src)
    except SyntaxError:
      rows.append((rel, "-", "UNPARSED", "-", "-"))
      continue
    srcs = pop_sources(tree, src)
    if not srcs:
      rows.append((rel, "-", "NO-LITERAL-POP", "-", "-"))
      continue
    seen, empties = set(), []
    for ln, pat, kind in srcs:
      if pat is None:
        seen.add("UNRESOLVED")
        continue
      n, exists = count(pat, p)
      key = f"{pat}"
      if key in seen:
        continue
      seen.add(key)
      empties.append((ln, pat, n, exists))
    if not empties:
      rows.append((rel, "-", "ALL-UNRESOLVED", "-", "-"))
      continue
    reachable = any(n == 0 for _, _, n, _ in empties)
    missing = [pat for _, pat, n, ex in empties if not ex]
    empty = [pat for _, pat, n, ex in empties if ex and n == 0]
    rows.append((rel,
                 "REACHABLE" if reachable else ("MISSING" if missing else "populated"),
                 "; ".join(f"{pat}={n}" for _, pat, n, _ in empties[:3]),
                 ", ".join(missing[:2]), ", ".join(empty[:2])))
  out = HERE / "reach.tsv"
  with open(out, "w") as fh:
    fh.write("path\tstate\tpopulations\tmissing\tEMPTY\n")
    for r in rows:
      fh.write("\t".join(r) + "\n")
  reach = [r for r in rows if r[1] in ("REACHABLE", "MISSING")]
  print(f"SCOPE: candidates from sites.tsv ({len(cands)}), measured against the tree as it is now")
  print(f"  REACHABLE-OR-MISSING (a vacuous green is ONE RUN away): {len(reach)}")
  print(f"  populated / unresolved                      : {len(rows) - len(reach)}")
  for r in reach:
    print(f"    {r[0]:<32} {r[1]:<10} {r[2][:70]}")
  print(f"\nwrote {out.relative_to(REPO)} ({len(rows)} rows)")
  return 0


if __name__ == "__main__":
  sys.exit(main())