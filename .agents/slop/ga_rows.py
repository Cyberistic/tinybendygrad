#!/usr/bin/env python3
"""DIAGNOSE the 149 generate.bend rows that rebase-gate.py's rows() cannot see.

`gl` prints a WHOLE generated file per row, so the text of one row contains
newlines.  rows() splits on newlines, so one gate row becomes N junk rows whose
NAMES are the first token before an `=` somewhere inside the generated Python.
This script says, per multi-line row, WHICH of two things happened:

  FRAGMENTED   the row's real name survives somewhere in the fragment set (it is
               the first line's key), and its value is TRUNCATED -- the fragments
               past line 1 are the generated file's own `NAME = value` lines.
  RENAMED      the row's name does not appear at all, so the two sides invented
               different row names for identical text.

Run:  python3 .agents/slop/ga_rows.py <port.txt> <oracle.txt>
"""
import pathlib
import re
import sys

# rows() verbatim, so this measures the SHIPPED parser and not a paraphrase.

# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows


# ga_gate.py's parser verbatim: DOTALL, keyed on the `]   py=[` shape.
ROW = re.compile(r"^(.*?) = \[(.*?)\]   py=\[(.*?)\]$", re.M | re.S)


def folded(text):
  """[(name, port, py)] for every row, SPLIT into the rows whose text is one line
  and the rows whose text SPANS lines."""
  whole, multi = [], []
  for m in ROW.finditer(text):
    nm = m.group(1).strip()
    if "\n" in nm:
      # the row's NAME is itself broken by a newline: a previous row never closed
      raise AssertionError(f"row name spans a newline: {nm!r}")
    dst = multi if "\n" in m.group(2) or "\n" in m.group(3) else whole
    dst.append((nm, m.group(2), m.group(3)))
  return whole, multi


def main(port_path, oracle_path):
  port_text = pathlib.Path(port_path).read_text()
  orc_text = pathlib.Path(oracle_path).read_text()

  p_rows, o_rows = rows(port_text), rows(orc_text)
  p_whole, p_multi = folded(port_text)
  o_whole, o_multi = folded(orc_text)

  print(f"rows() on port            : {len(p_rows)}")
  print(f"rows() on oracle          : {len(o_rows)}")
  print(f"ga_gate() on port         : {len(p_whole)} one-line + {len(p_multi)} multi-line"
        f" = {len(p_whole) + len(p_multi)} real rows")
  print(f"shared under rows()       : {len(set(p_rows) & set(o_rows))}")

  print("\n-- the real rows, by whether rows() can see them --")
  real = [nm for nm, _, _ in p_whole] + [nm for nm, _, _ in p_multi]
  seen = [nm for nm in real if nm in p_rows]
  unseen = [nm for nm in real if nm not in p_rows]
  print(f"real rows whose NAME survives rows() : {len(seen)}")
  print(f"real rows whose NAME is lost        : {len(unseen)}")
  by_name = {nm: v for nm, _, v in p_whole} | {nm: v for nm, _, v in p_multi}
  for nm in unseen:
    print(f"   {nm:<16} {by_name[nm].count(chr(10)) + 1:>4} emitted lines")

  print("\n-- cause, per lost row --")
  frag, renamed = [], []
  for nm in unseen:
    (frag if nm + " = [" in port_text else renamed).append(nm)
  print(f"FRAGMENTED (name survives as the first line's key): {len(frag)}")
  print(f"NOT IN PORT TEXT AT ALL under that spelling      : {len(renamed)}"
        + (f" -> {renamed}" if renamed else ""))

  print("\n-- the junk rows rows() invents instead --")
  real_names = set(real)
  junk = [k for k in p_rows if k not in real_names]
  # a junk name is the first token of a generated file line that carries an `=`
  print(f"rows() names that are NOT gate rows: {len(junk)}")
  for k in junk[:12]:
    print(f"   {k!r} = {p_rows[k][:60]!r}")
  if len(junk) > 12:
    print(f"   ... and {len(junk) - 12} more")
  return 0


if __name__ == "__main__":
  sys.exit(main(*sys.argv[1:3]))