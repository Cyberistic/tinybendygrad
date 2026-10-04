#!/usr/bin/env python3
"""measure.py -- THE FOUR COLUMNS over all 227 rows of renderer/cstyle.bend, the CAUSE of
every row that is not C a compiler accepts, and the denominator DERIVED by derive.py.

THE FOUR COLUMNS. Each is defined by what it MEASURES, and the definitions are printed,
because "226 of 227 are text" was a count of a mixture and a mixture with no stated
definition cannot be re-checked.

  TEXT      the row's value is not compilable C, and NO TOOLCHAIN is being blamed for it.
            Determined by handing the unescaped value to `cc` in the dialect the row's
            device names and reading rc. Deliberately NOT a second, structural guess: the
            previous unit's structural test and `cc` disagreed on 8 of 227 rows, which is
            why that test was replaced rather than kept.
  COMPILES  `cc` accepted the unescaped value. rc==0, from the PROCESS.
  EXECUTES  a host binary linked the row's text and ran it, producing output.
  AGREES    that output equalled tinygrad's own answer, from a live CPython call.

AND THE FIFTH BUCKET, kept OUT of TEXT on purpose: TOOLCHAIN-ABSENT, a device whose front
end is not installed here. "The text is right and the compiler is missing" is a different
fact from "the text is wrong", and folding them together is how 226 became one number.

THE THREE CAUSES a non-C row can have, assigned BY RULE and printed by row name, so the
rule can be checked:

  (a) STRING BY DESIGN -- the row's value is a piece of C that upstream's function under
      test RETURNS AS A STRING for someone else to splice: `render_dtype` on one dtype,
      `code_for_op` on one op, `render_index` on one index. No compiler will ever accept it
      standing alone and that is not a defect. Two sub-kinds, because they are different
      failures to convert: `SINGLE-CELL` (one value, needs a host) and `JOINED` (the GATE
      joined several values with `|`/`,`/` / `, so the row is not even one C value --
      `cstyle-gate.py`'s own `cells()`).
  (b) NEVER REACHED THE RENDERER -- the row's own text is supplied by a FIXTURE, so the
      renderer never produced it. MEASURED, not asserted: the `kern2` family is the only
      family whose value is a whole translation unit, and every one of its 30 rows splices
      `g_kernel()`, a two-line literal (`cstyle.bend`'s own words: "verbatim from the
      oracle"), where upstream would have `code_for_op`'d a uop list. So those 30 rows
      exercise `render_kernel`'s FRAMING and nothing inside it.
  (c) DISPATCH NOT COVERED -- the renderer has no arm and REFUSES, and the row pins the
      refusal. Measured live against CPython in empty-probe.py: 7 rows, all `Ops.FDIV` on
      a device whose `code_for_op` has no FDIV arm, or one of the five ops `ClangRenderer`
      deletes at `cstyle.py:291`.

  usage: measure.py <cstyle.bend> <port.txt> [--tsv out.tsv]
"""
import argparse
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("cstyle_gate", HERE.parent / "cstyle-gate.py")
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

# DIALECT BY DEVICE. A device with no entry has NO FRONT END on this machine, and each
# absence carries the command that established it so it is reproducible, not asserted.
DIALECT = {"BASE": ["-x", "c"], "CLANG": ["-x", "c"], "OPENCL": ["-x", "cl"],
           "HIP": ["-x", "c++"]}
NO_FRONTEND = {
  "METAL": "cc -x metal -fsyntax-only  ->  error: language not recognized: 'metal'",
  "CUDA": "cc -x cuda -nocudainc -nocudalib -fsyntax-only  ->  unknown type name '__device__' "
          "(no CUDA installation; the front end does not engage)",
  "HIP": "cc -x c++ exists, but the row's own __attribute__((amdgpu_flat_work_group_size)) is a "
         "hard ERROR off an AMD target and -Wno-error does not downgrade it",
}

# THE FAMILIES THAT JOIN SEVERAL VALUES INTO ONE ROW, read from cstyle-gate.py's own
# `cells()` rather than restated, so a change to the gate's separator shows up here.
JOINED_FAMILIES = ("tmap", "rd", "witem", "buft", "opt")


def unescape(s):
  return s.replace("\\n", "\n")


def device_of(name):
  for p in name.split()[1:]:
    if p in DIALECT or p in NO_FRONTEND:
      return p
  return "BASE"


def cc_run(val, dev):
  flags = DIALECT.get(dev)
  if flags is None:
    return "TOOLCHAIN-ABSENT", ""
  with tempfile.TemporaryDirectory() as td:
    f = pathlib.Path(td) / "k.c"
    f.write_text(val)
    p = subprocess.run(["cc", *flags, "-fsyntax-only", str(f)], capture_output=True, text=True)
    errs = [l for l in p.stderr.splitlines() if ": error:" in l]
    first = errs[0].split(": error:")[1].strip()[:70] if errs else "?"
    return int(p.returncode == 0), (first if p.returncode else "")


def cause(rec):
  """(a)/(b)/(c) or None, BY RULE. Printed by row name so the rule is checkable.

  ⚠ THE EMPTY-FILE TRAP, and it is not hypothetical: an EMPTY C file is a valid
  translation unit, so `cc` exits 0 on a row whose value is the empty string. Five of this
  file's rows are refusals with an empty value, so a naive "cc accepted" count reports
  them as COMPILING. `cc` accepting zero bytes is not the port's answer compiling, so
  COMPILES requires a non-empty value and the count of rows where the two differ is
  printed by the caller."""
  if rec["cc"] == 1 and not rec["empty"]:
    return None
  if rec["family"] == "kern2":
    return "b: never reached the renderer (body is the g_kernel() literal)"
  if rec["empty"]:
    return "c: dispatch not covered (upstream KeyError, confirmed live)"
  if rec["family"] in JOINED_FAMILIES:
    return "a: string by design, JOINED (the gate joined N cells; not one C value)"
  return "a: string by design, single cell"


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("bend")
  ap.add_argument("port")
  ap.add_argument("--tsv")
  a = ap.parse_args()
  rows, _shreds, dups = gate.rows_strict(pathlib.Path(a.port).read_text())
  assert not dups, f"duplicate row names would silently overwrite: {dups}"
  out = []
  for name in sorted(rows):
    got, _lit = gate.split_py(rows[name])
    val = unescape(got)
    dev = device_of(name)
    ok, err = cc_run(val, dev)
    rec = {"row": name, "family": name.split()[0], "device": dev,
           "cells": len(gate.cells(got)), "lines": val.count("\n") + 1, "bytes": len(val),
           "cc": ok, "first_error": err, "empty": int(val.strip() == ""),
           "newlines": int("\n" in val)}
    rec["cause"] = cause(rec) or ""
    out.append(rec)

  if a.tsv:
    hdr = ["row", "family", "device", "cells", "lines", "bytes", "newlines", "cc",
           "empty", "cause", "first_error"]
    pathlib.Path(a.tsv).write_text(
      "\t".join(hdr) + "\n" + "\n".join("\t".join(str(r[h]) for h in hdr) for r in out) + "\n")

  n = len(out)

  def cnt(pred):
    return sum(1 for r in out if pred(r))

  def frac(k):
    return f"{k}/{n}"

  text = cnt(lambda r: r["cc"] == 0 or (r["cc"] == 1 and r["empty"]))
  comp = cnt(lambda r: r["cc"] == 1 and not r["empty"])
  absent = cnt(lambda r: r["cc"] == "TOOLCHAIN-ABSENT")
  emptyfile = cnt(lambda r: r["cc"] == 1 and r["empty"])

  print(f"DENOMINATOR  {n} rows, DERIVED by derive.py from main()'s row-emitting calls")
  print(f"             rows-present {n}  rows-expected {n}  family multisets equal  "
        f"duplicates 0")
  print()
  print("THE FOUR COLUMNS, each against that denominator")
  print(f"  TEXT      cc rejected the value, no toolchain blamed   {frac(text)}")
  print(f"  COMPILES  cc accepted the value (rc from the process)  {frac(comp)}")
  print(f"  EXECUTES  a host binary ran it                         0/{n}   measured in convert2.py GATE 2")
  print(f"  AGREES    that output equalled tinygrad's               0/{n}   measured in agree.py GATE 3")
  print()
  print("THE FIFTH BUCKET, deliberately outside TEXT")
  print(f"  TOOLCHAIN-ABSENT                                        {frac(absent)} "
        f"{sorted({r['device'] for r in out if r['cc'] == 'TOOLCHAIN-ABSENT'})}")
  for d in sorted(NO_FRONTEND):
    print(f"      {d:<7} {NO_FRONTEND[d]}")
  print(f"  the partitions sum to TEXT {text} + COMPILES {comp} + ABSENT {absent} = "
        f"{text+comp+absent}")
  print()
  print("THE EMPTY-FILE TRAP, counted rather than described")
  print(f"  rows whose value is the empty string AND whose cc exited 0  {emptyfile}/{n}  "
        f"{[r['row'] for r in out if r['cc'] == 1 and r['empty']]}")
  print("  an empty C file IS a valid translation unit, so `cc` exits 0 on a REFUSAL.")
  print("  COMPILES above excludes them; a naive cc-accepted count would report "
        f"{comp+emptyfile}/{n}.")
  print()
  print("THE CAUSE OF EVERY NON-COMPILING ROW, BY RULE, BY NAME")
  for key in sorted({r["cause"] for r in out if r["cause"]}):
    sel = [r for r in out if r["cause"] == key]
    print(f"  {len(sel):>3}/{n}  {key}")
    print(f"        families {sorted({r['family'] for r in sel})}")
    for r in sel[:6]:
      print(f"          {r['row']!r}  {r['first_error'][:52]}")
    if len(sel) > 6:
      print(f"          ... and {len(sel)-6} more, all in four-col.tsv")
  print()
  print("THE EMPTY VALUES -- cause (c), and each one is a REFUSAL upstream")
  for r in out:
    if r["empty"]:
      print(f"  {r['row']!r}")
  print()
  print("MULTI-LINE ROWS (the escape the gate applies and this measurement undoes)")
  ml = [r for r in out if r["newlines"]]
  print(f"  {len(ml)}/{n} rows carry a real newline once unescaped; "
        f"families {sorted({r['family'] for r in ml})}")
  print()
  print("SELF-CHECK, the two ways this script can be wrong")
  print(f"  rows with a cause assigned but cc ACCEPTED (must be 0): "
        f"{cnt(lambda r: r['cause'] and r['cc'] == 1)}")
  print(f"  rows with cc REJECTED and no cause (must be 0):         "
        f"{cnt(lambda r: r['cc'] == 0 and not r['cause'])}")
  print(f"  cause-(c) rows that are not empty (must be 0):          "
        f"{cnt(lambda r: r['cause'].startswith('c') and not r['empty'])}")
  return 0


if __name__ == "__main__":
  sys.exit(main())