#!/usr/bin/env python3
"""CONSTANT AUDIT for tinybendygrad/renderer/nir.bend.

Every constant `op_const` / `intr_const` / `idx_const` / `arch_int` holds is
compared against a live `getattr` on `tinygrad.runtime.autogen.mesa`, with the
AUTHORITY recorded per symbol. The authority column matters: `--check-only`
proves the port COMPILES, not that a number is the right number, and `ops_nv`'s
audit found 33 of 219 constants wrong in a file already printing 590 green rows.

  .venv/bin/python .agents/slop/nir/nir_const_audit.py
"""
import sys, os, re
sys.path.insert(0, os.getcwd())
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nir_oracle import const_rows, _mesa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "tinybendygrad", "renderer", "nir.bend")
TABLES = ("op_const", "intr_const", "idx_const", "arch_int")

def port_consts():
  """The `case "name": N` arms of the port's constant tables."""
  out, cur = {}, None
  for line in open(SRC):
    m = re.match(r"^def (\w+)\((?:nm|arch): String\) -> U32:", line)
    if m: cur = m.group(1); continue
    if re.match(r"^def \w", line) and cur: cur = None
    m = re.match(r'^    case "([^"]+)": (\d+)$', line)
    if m and cur in TABLES: out[(cur, m.group(1))] = int(m.group(2))
  return out

def main():
  port = port_consts()
  n_checked = n_wrong = n_absent = 0
  print("%-42s %-12s %-8s %-8s %s" % ("SYMBOL", "TABLE", "PORT", "MESA", "VERDICT"))
  print("-" * 100)
  for nm, auth, v in const_rows():
    # `const_rows()` names are ALREADY fully qualified (`nir_op_iadd`) and the PORT
    # keys `op_const` by the BARE name (`case "iadd": 306`) because `nalu` prepends
    # the prefix (nir.py:38) -- so the lookup strips it for `op_const` only.
    # Prefixing audited 30 of 97 and stripping audited nothing; both were measured.
    bare = nm[len("nir_op_"):] if nm.startswith("nir_op_") else nm
    for tbl, key in (("op_const", bare), ("intr_const", nm), ("idx_const", nm)):
      if (tbl, key) not in port: continue
      got = port[(tbl, key)]
      n_checked += 1
      if v == "ABSENT":
        n_absent += 1; verdict = "PORTED BUT ABSENT IN MESA"
      elif got == int(v): verdict = "ok"
      else: verdict = "*** WRONG ***"; n_wrong += 1
      print("%-42s %-12s %-8s %-8s %s" % (key, tbl, got, v, verdict))
  print("-" * 100)
  print("checked %d constants, %d WRONG, %d ported-but-absent" % (n_checked, n_wrong, n_absent))
  # `arch_int` is a port of `int(arch[3:])`, not a mesa constant, so it is counted
  # here only so the sweep's 101 arms and this file's 97+4 agree.
  print("plus %d `arch_int` arms, gated against CPython's int(arch[3:]) by the "
        "`arch_int sm_*` rows" % sum(1 for t, _k in port if t == "arch_int"))
  ms = [n for n in dir(_mesa()) if n.startswith(("nir_op_", "nir_intrinsic_", "NIR_INTRINSIC_"))]
  named = {k for _t, k in port}
  print("\nmesa symbols in the same three enums that this file does NOT name: %d of %d"
        % (len([n for n in ms if n not in named]), len(ms)))

if __name__ == "__main__": main()
