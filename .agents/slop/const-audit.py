#!/usr/bin/env python3
"""SMOKE-TEST a ported table against its generated header. Not an oracle.

WHY. runtime/ops_nv.bend shipped 606 green gate rows with 33 of 219 constants WRONG:
a gate tests graphs, the constants answer to a C header nobody read, so no number of
rows finds this. The fix is to diff against the authority. But note WHAT the 33/219
audit actually was: a hand-built 219-entry name map, because the port invents names
and the header's namespace differs. A name-matching script catches only the slice that
happens to line up, so this is a cheap smoke test -- its COVERAGE number is the point,
not its verdict.

It matches a port name to a header name two ways: exact, and by stripping a prefix
from a fixed list (the ports rename, e.g. CLASS_BLACKWELL_COMPUTE_A vs the headers
BLACKWELL_COMPUTE_A). It refuses to call a name WRONG when the two sides are plainly
different concepts (a small port index vs a real ioctl code), and it reports every
number so a human can judge coverage.

  usage: python3 .agents/slop/const-audit.py <file.bend> <authority.py> [...]
"""
import ast, re, sys
from pathlib import Path

BEND_CONST = re.compile(r"^def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*(-?\d+)\s*$")
# Prefixes the ports add to disambiguate within a file. Extend per-file, never guess silently.
PREFIXES = ("CLASS_", "NV01_", "NV20_", "UVM_", "FERMI_", "KEPLER_", "AMPERE_", "CUDA_", "CL_", "HIP_")


def bend_consts(path):
  out = {}
  for line in Path(path).read_text().splitlines():
    m = BEND_CONST.match(line)
    if m: out[m.group(1)] = int(m.group(2))
  return out


def py_consts(*paths):
  """name -> int, for module-level `NAME = <int literal>`. A name bound twice to
  DIFFERENT values is dropped: it is ambiguous, not auditable."""
  out, bad = {}, set()
  for p in paths:
    try: tree = ast.parse(Path(p).read_text())
    except (OSError, SyntaxError) as e:
      print(f"  !! {p}: {e}", file=sys.stderr); continue
    for node in tree.body:
      if not isinstance(node, ast.Assign): continue
      if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name): continue
      try: v = ast.literal_eval(node.value)
      except (ValueError, SyntaxError): continue
      if not isinstance(v, int) or isinstance(v, bool): continue
      n = node.targets[0].id
      if n in out and out[n] != v: out.pop(n); bad.add(n)
      elif n not in bad: out[n] = v
  return out


def main():
  if len(sys.argv) < 3:
    print(__doc__); return 2
  bend, auths = sys.argv[1], sys.argv[2:]
  port, auth = bend_consts(bend), py_consts(*auths)
  exact = {n: n for n in port if n in auth}
  suff = {}
  for n in port:
    if n in exact: continue
    for pfx in PREFIXES:
      if n.startswith(pfx) and n[len(pfx):] in auth: suff[n] = n[len(pfx):]; break
  shared = {**exact, **suff}
  wrong = [(n, port[n], auth[m]) for n, m in shared.items() if port[n] != auth[m]]
  # A port value that is a tiny index against a real ioctl code is a NAME COLLISION
  # across two namespaces, not a wrong constant. Report it, do not call it a bug.
  collide = [(n, port[n], auth[m]) for n, m in shared.items() if port[n] != auth[m] and port[n] < 64]
  real = [w for w in wrong if w not in collide]
  print(f"{Path(bend).name}: {len(port)} consts | COVERED {len(shared)} "
        f"({len(exact)} exact + {len(suff)} by prefix) | likely-WRONG {len(real)} | "
        f"name-collisions {len(collide)} | UNCOVERED {len(port) - len(shared)}")
  for n, p, a in real: print(f"  WRONG {n}: port {p} ({p:#x}) authority {a} ({a:#x})")
  for n, p, a in collide: print(f"  COLLIDE {n}: port {p} vs authority {a} ({a:#x}) -- likely different concept, judge by hand")
  if len(port) - len(shared) > len(shared):
    print(f"  NOTE: {len(port) - len(shared)} consts UNCOVERED -- a name-matching script cannot")
    print("        reach them. This is a SMOKE TEST; a real audit needs a hand-built map.")
  return 0


if __name__ == "__main__": sys.exit(main())
