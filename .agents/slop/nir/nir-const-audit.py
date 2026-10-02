#!/usr/bin/env python3
"""CONSTANT AUDIT for tinybendygrad/renderer/nir.bend.

Every constant `op_const` / `intr_const` / `idx_const` holds is compared against
a live `getattr` on `tinygrad.runtime.autogen.mesa`, with the authority recorded
per symbol. The authority column matters: `--check-only` proves the port
COMPILES, not that a number is the right number, and `ops_nv`'s audit found 33
of 219 constants wrong in a file already printing 590 green rows.

  .venv/bin/python .agents/slop/nir/nir-const-audit.py
"""
import sys, os, re, subprocess
sys.path.insert(0, os.getcwd())
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nir_oracle import const_rows, _mesa

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "tinybendygrad", "renderer", "nir.bend")

def port_consts():
  """The `case "name": N` arms of the port's three constant tables."""
  out, cur = {}, None
  for line in open(SRC):
    m = re.match(r"^def (\w+)\(nm: String\) -> U32:", line)
    if m: cur = m.group(1); continue
    if re.match(r"^def \w", line) and cur: cur = None
    m = re.match(r'^    case "([^"]+)": (\d+)$', line)
    if m and cur in ("op_const", "intr_const", "idx_const"):
      out[(cur, m.group(1))] = int(m.group(2))
  return out

def main():
  port = port_consts()
  live = {nm: v for nm, _auth, v in const_rows()}
  n_checked = n_wrong = n_absent_in_port = 0
  print("%-42s %-14s %-10s %-10s %s" % ("SYMBOL", "AUTHORITY", "PORT", "MESA", "VERDICT"))
  print("-" * 104)
  for nm, auth, v in const_rows():
    # `const_rows()` names are ALREADY fully qualified (`nir_op_iadd`), and the
    # PORT keys `op_const` by the BARE name (`case "iadd": 306`) because `nalu`
    # prepends the prefix (nir.py:38). So the lookup strips it for `op_const`
    # only -- prefixing audited 30 of 97 and stripping audited nothing.
    bare = nm[len("nir_op_"):] if nm.startswith("nir_op_") else nm
    for tbl, key in (("op_const", bare), ("intr_const", nm), ("idx_const", nm)):
      if (tbl, key) in port:
        got, want = port[(tbl, key)], v
        n_checked += 1
        if v == "ABSENT":
          n_absent_in_port += 1
          verdict = "PORTED BUT ABSENT IN MESA"
        elif got == int(v): verdict = "ok"
        else:
          verdict = "*** WRONG ***"; n_wrong += 1
        print("%-42s %-14s %-10s %-10s %s" % (key, tbl, got, v, verdict))
  print("-" * 104)
  print("checked %d constants, %d WRONG, %d ported-but-absent" % (n_checked, n_wrong, n_absent_in_port))
  # and the reverse: symbols mesa has that the port never names
  named = {k for _t, k in port}
  unused = [nm for nm in _dir_syms() if nm not in named]
  print("\nmesa symbols this file's tables do NOT name: %d of %d (the enum is "
        "much larger than the file's slice of it)" % (len(unused), len(_dir_syms())))

def _dir_syms():
  return [n for n in dir(_mesa()) if n.startswith(("nir_op_", "nir_intrinsic_", "NIR_INTRINSIC_"))]

if __name__ == "__main__": main()
