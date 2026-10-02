#!/usr/bin/env python
"""Rewrite `uop/spec.bend`'s spec.py line citations FROM CPython's AST.

Every `# 161` on a `PMEntry` row and every `# spec.py:161` above a `te_N` def is a claim
about which line of `tinygrad/uop/spec.py` that rule came from. Nine of them were three
too high, because the port carried a duplicate rule and every citation after it drifted;
a comment that is off by three looks exactly like a correct one.

So the numbers here are READ, not typed: `ast` gives the `lineno` of each element of the
`PatternMatcher([...])` list literal in spec.py, which is the line the rule is written on.

  usage: python .agents/slop/spec-citations.py [--check]

`--check` reports drift without writing. Exit 0 when every citation agrees, 1 otherwise.
"""
import ast
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
PY = REPO / "tinygrad/uop/spec.py"
BEND = REPO / "tinybendygrad/uop/spec.bend"

# (bend table def, spec.py's name for the same table, Bend def-name prefix)
TABLES = [("tensor_own", "spec_tensor", "te"), ("program_own", "spec_program", "pr"),
          ("hcq_own", "spec_hcq", "hq")]


def spec_py_lines(table):
  """`lineno` of each rule in spec.py's `spec_tensor` / `spec_program` / ... literal."""
  tree = ast.parse(PY.read_text())
  for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == table:
      call = node.value
      if isinstance(call, ast.BinOp):        # `PatternMatcher([...]) + spec_shared`
        call = call.left
      return [elt.lineno for elt in call.args[0].elts]
  raise LookupError(table)


def bend_rows(fn):
  """The `O.PMEntry{n, ...}   # NNN` rows of `def fn()`, in order."""
  lines = BEND.read_text().splitlines()
  i = next(k for k, l in enumerate(lines) if l.startswith(f"def {fn}("))
  out = []
  for k in range(i + 1, len(lines)):
    m = re.match(r"(\s*O\.PMEntry\{(\d+),.*?)\s*#\s*(\d+)\s*$", lines[k])
    if m:
      out.append((k, int(m.group(2)), int(m.group(3))))
    elif out:
      break
  return out


def main():
  check = "--check" in sys.argv
  lines = BEND.read_text().splitlines(keepends=True)
  drift = 0

  for fn, py_table, prefix in TABLES:
    want = spec_py_lines(py_table)
    rows = bend_rows(fn)
    if len(rows) != len(want):
      print(f"  {fn}: port has {len(rows)} rows, spec.py has {len(want)} -- "
            f"refusing to realign by index")
      drift += 1
      continue
    for (k, tag, cited), correct in zip(rows, want):
      if cited != correct:
        drift += 1
        print(f"  {fn} tag {tag}: cites {cited}, spec.py says {correct}")
        lines[k] = re.sub(r"#\s*\d+\s*$", f"# {correct}", lines[k].rstrip("\n")) + "\n"
    print(f"  {fn}: {len(rows)} citations checked against {py_table}")

  # the `# spec.py:NNN` header comment above each def, matched by the rule it precedes
  for fn, py_table, prefix in TABLES:
    want = spec_py_lines(py_table)
    for k, l in enumerate(lines):
      m = re.match(r"# spec\.py:(\d+) \(", l)
      if not m:
        continue
      # `def te_1.facts(` is a HELPER of te_1, not te_1 itself -- match the verdict defs,
      # which are the ones whose parameter list is `(+fx: F.Folded, +self: U32)`.
      nxt = next((n for n in range(k + 1, min(k + 8, len(lines)))
                  if re.match(rf"def {prefix}_\d+\(\+fx: F\.Folded, \+self: U32\)", lines[n])), None)
      if nxt is None:
        continue
      tag = int(re.match(rf"def {prefix}_(\d+)\(", lines[nxt]).group(1))
      if tag >= len(want):
        continue
      if int(m.group(1)) != want[tag]:
        drift += 1
        print(f"  header above {prefix}_{tag}: cites {m.group(1)}, spec.py says {want[tag]}")
        lines[k] = l.replace(f"# spec.py:{m.group(1)} ", f"# spec.py:{want[tag]} ", 1)

  if check:
    print(f"  {drift} citations drifted")
    return 1 if drift else 0
  BEND.write_text("".join(lines))
  print(f"  rewrote {drift} citations")
  return 0


if __name__ == "__main__":
  sys.exit(main())