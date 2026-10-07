#!/usr/bin/env python3
"""scan.py -- DISCOVER the count-to-verdict sites.  Population by WALK, never by name.

SCOPE, printed by --scope and recorded in the report, because `coindependent`'s 5 and
`prune4`'s counts were both correct FOR THEIR SCOPE and meaningless without it:

    roots   checks/  gates/   (directory walk + `.py` suffix, per AGENTS.md doctrine 1)
    excl    .agents/  references/  (not gates)
    census  ONE LINE is one candidate.  A regex cannot be exhaustive; it is a NET, and
            every candidate is verified by hand before the number is quoted.

Emits `sites.tsv` and `scope.rows`.  NOT a verdict about the tree -- a net's yield.
"""
import argparse, ast, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
ROOTS = ("checks", "gates")
EXCL = (".agents", "references", "node_modules", ".git", ".venv")

# The shapes that can make a NUMBER into a VERDICT.  A count only matters here.
COUNT_FUNCS = {"len", "sum", "count", "index"}
COLLECT_FUNCS = {"rglob", "glob", "walk", "Counter", "defaultdict"}
# Verdict surfaces: text that a reader reads as an ANSWER.
VERDICT_TOKENS = (
  "verdict", "VERDICT", "PASS", "FAIL", "OK", "GREEN", "CLEAN", "clean",
  "REFUSED", "SKIP", "DEAD", "bad", "BROKEN", "AGREE", "healthy", "OK ",
)
# Destructive: a gate that WRITES a tracked artifact computed from its counts.
WRITE_CALLS = ("write_text", "write_bytes", "dump", "writelines")
WRITE_TOKENS = ("json", ".json", ".tsv", ".rows", "census", "ledger", "report", ".out")


def population():
  """The population, DECLARED BY DISCOVERY: walk, do not list."""
  out = []
  for root in ROOTS:
    for dirpath, dirnames, filenames in __import__("os").walk(REPO / root):
      dirnames[:] = [d for d in dirnames if not any(d == e for e in EXCL)]
      for fn in sorted(filenames):
        if fn.endswith(".py"):
          p = pathlib.Path(dirpath) / fn
          out.append(p)
  return sorted(out)


def verdict_code(tree):
  """Every integer the module can RETURN at top level or from main()."""
  codes = set()
  for node in ast.walk(tree):
    if isinstance(node, ast.Return) and isinstance(node.value, ast.Constant) \
       and isinstance(node.value.value, int):
      codes.add(node.value.value)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
       and node.func.attr == "exit" and node.args and isinstance(node.args[0], ast.Constant):
      codes.add(node.args[0].value)
  return sorted(codes)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--out", default=str(HERE / "sites.tsv"))
  a = ap.parse_args()
  files = population()
  rows, by_file = [], {}
  for p in files:
    try:
      src = p.read_text()
      tree = ast.parse(src)
    except (SyntaxError, UnicodeDecodeError) as e:
      rows.append((str(p.relative_to(REPO)), 0, "UNPARSED", f"{type(e).__name__}", str(e)[:60]))
      continue
    lines = src.splitlines()
    hits = []
    for i, ln in enumerate(lines, 1):
      if len(ln) > 400 or ln.lstrip().startswith("#"):
        continue
      counts = [f for f in COUNT_FUNCS if f + "(" in ln]
      colls = [f for f in COLLECT_FUNCS if f + "(" in ln or f + "[" in ln or f in ln]
      writes = [f for f in WRITE_CALLS if f + "(" in ln]
      verdicts = [t for t in VERDICT_TOKENS if t in ln]
      kinds = []
      if counts and verdicts:
        kinds.append("COUNT+VERDICT")
      if counts and (" of " in ln or " / " in ln or "/ " in ln):
        kinds.append("DENOMINATOR")
      if writes and any(t in ln for t in WRITE_TOKENS):
        kinds.append("WRITE+COUNT-ISH")
      if writes and any("len(" in lines[j] or "sum(" in lines[j]
                        for j in range(max(0, i - 6), min(len(lines), i + 6))):
        kinds.append("WRITE-AFTER-COUNT")
      if kinds:
        hits.append((i, ",".join(sorted(set(kinds))), ln.strip()[:110]))
    if hits:
      by_file[p.name] = len(hits)
      for i, k, t in hits:
        rows.append((str(p.relative_to(REPO)), i, k, "", t))
  # verdict surface per file, so "can report 0" is checkable rather than asserted
  with open(a.out, "w") as fh:
    fh.write("path\tline\tkinds\t\ttext\n")
    for r in rows:
      fh.write("\t".join(str(x) for x in r) + "\n")
  scope = HERE / "scope.rows"
  with open(scope, "w") as fh:
    fh.write(f"key\tvalue\n")
    fh.write(f"roots\t{','.join(ROOTS)}\n")
    fh.write(f"excluded\t{','.join(EXCL)}\n")
    fh.write(f"py_files_in_scope\t{len(files)}\n")
    fh.write(f"files_with_a_hit\t{len(by_file)}\n")
    fh.write(f"candidate_lines\t{sum(by_file.values())}\n")
    fh.write(f"method\tAST-parse then per-line shape match; UNPARSED counted, never dropped\n")
  print(open(scope).read(), end="")
  print("top files:")
  for n, c in sorted(by_file.items(), key=lambda kv: -kv[1])[:15]:
    print(f"  {c:4} {n}")
  print(f"\nwrote {a.out} ({len(rows)} rows incl. header)")
  return 0


if __name__ == "__main__":
  sys.exit(main())