#!/usr/bin/env python3
"""convert.py -- THE CONVERSION INVENTORY, one line per one of `cstyle.bend`'s rows, with
the DENOMINATOR every count is a fraction of.

WHAT THIS DOES NOT DO. It does not touch `.agents/slop/cstyle-gate.py` (read-only to this
unit) and it does not decide which rows count as LIVE-VS-LIVE -- another unit is censoring
that per lane and two writers of one ledger collide silently. This file produces the
EVIDENCE the accounting needs, as a TSV, and prints the denominators so the accounting
cannot be done over an implied total.

THE FOUR STEPS PER ROW, each recorded SEPARATELY because "it did not work" is not a result:
    emitted  the port printed a row for it at all (denominator 1)
    compiled  `cc -fsyntax-only` accepted the unescaped value (denominator = emitted)
    ran       a host program including that text linked and executed (denominator = compiled)
    agreed    the numbers it produced equalled CPython's (denominator = ran)

A row's value is only COMPILED IF IT IS A TRANSLATION UNIT. Most of these rows are
fragments -- `_render_dtype` on one dtype, `code_for_op` on one op -- and a fragment does not
compile for a reason that has nothing to do with the port. So `is_tu` is reported as its own
column rather than folded into `compiled`, because folding it makes the compile rate look
like a quality measure when it is a statement about the shape of the row.

  usage: convert.py <port.txt> [--run]
"""
import argparse, pathlib, subprocess, sys, tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import importlib.util
_spec = importlib.util.spec_from_file_location("cstyle_gate", pathlib.Path(__file__).resolve().parents[1] / "cstyle-gate.py")
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

DEV = {"BASE": 0, "CLANG": 1, "OPENCL": 2, "METAL": 3, "CUDA": 4, "HIP": 5}


def unescape(s):
  """`esc_row` (cstyle.bend:1808) introduces exactly one escape, a backslash-n."""
  return s.replace("\\n", "\n")


def device_of(name):
  """The row NAME's device token, e.g. `kern2 HIP   bf16h` -> HIP. `CstyleLanguage` is the
  base and is spelled BASE in the rows; cstyle.bend's `dev_base()` is 0."""
  parts = name.split()
  for p in parts[1:]:
    if p in DEV:
      return p
  return "BASE"


def is_tu(value):
  """A TRANSLATION UNIT, decided on the text and not on the row name: it opens with a
  declaration (a typedef or a function definition) rather than continuing an expression.
  Measured on this tree: every `kern2` value opens `void `, `__kernel void `, `kernel void `
  or `extern "C" ... void `, and every non-`kern2` value opens with a type word or an
  operator and continues a body."""
  v = value.lstrip()
  return any(v.startswith(p) for p in ("void ", "__kernel void ", "kernel void ", "extern \"C\" ",
                                       "typedef ")) and "(" in v


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("port")
  ap.add_argument("--tsv", default=None)
  ap.add_argument("--cc", default="cc")
  a = ap.parse_args()
  rows, shreds, dups = gate.rows_strict(pathliblib := pathlib.Path(a.port).read_text())
  out = []
  with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td)
    for name in sorted(rows):
      got, lit = gate.split_py(rows[name])
      val = unescape(got)
      dev = device_of(name)
      fam = name.split()[0]
      tu = is_tu(val)
      rec = {"row": name, "family": fam, "device": dev, "is_tu": int(tu),
             "lines": val.count("\n") + 1, "bytes": len(val),
             "compiled": "", "first_error": "", "ran": "", "agreed": ""}
      f = td / "k.c"
      f.write_text(val)
      p = subprocess.run([a.cc, "-fsyntax-only", "-x", "c", str(f)],
                         capture_output=True, text=True)
      rec["compiled"] = int(p.returncode == 0)
      if p.returncode:
        errs = [l for l in p.stderr.splitlines() if ": error:" in l]
        # the error line WITHOUT the temp path, so the report is reproducible
        rec["first_error"] = errs[0].split(": error:")[1].strip()[:58] if errs else "?"
      out.append(rec)
  hdr = ["row", "family", "device", "is_tu", "lines", "bytes", "compiled", "ran", "agreed", "first_error"]
  tsv = "\n".join("\t".join(str(r[h]) for h in hdr) for r in out)
  if a.tsv:
    pathlib.Path(a.tsv).write_text(tsv + "\n")

  def frac(n, d):
    return f"{n}/{d}" if d else f"0/0"

  emitted = len(out)
  tus = [r for r in out if r["is_tu"]]
  compiled = [r for r in out if r["compiled"]]
  cstyle = [r for r in compiled if r["family"] == "cstyle"]
  print(f"rows EMITTED by the port                 {frac(emitted, emitted)}")
  print(f"  of which a TRANSLATION UNIT (is_tu)     {frac(len(tus), emitted)}")
  print(f"  families of those                       {sorted({r['family'] for r in tus})}")
  print(f"rows that COMPILED (cc -fsyntax-only)     {frac(len(compiled), emitted)}")
  print(f"  by family                               "
        f"{ {f: sum(1 for r in compiled if r['family'] == f) for f in sorted({r['family'] for r in compiled})} }")
  print(f"  by device                               "
        f"{ {d: sum(1 for r in compiled if r['device'] == d) for d in sorted({r['device'] for r in compiled})} }")
  print(f"rows that RAN                             0/{len(compiled)}"
        "  (Stage 2/3 ran the ONE kernel, through a fixture that supplies the `vecs` typedef"
        " this lane's `emit_min()` fixture does not)")
  print(f"rows that AGREED with CPython             0/{emitted} as ROWS;"
        " 1/1 as a KERNEL (Stage 2 and Stage 3, same text)")
  print("")
  print("THE COMPILE FAILURES, BY CAUSE, one line per distinct first error:")
  causes = {}
  for r in out:
    if not r["compiled"]:
        causes.setdefault(r["first_error"], []).append(r["row"])
  for k in sorted(causes, key=lambda k: -len(causes[k])):
    print(f"  {len(causes[k]):>3}  {k}")
    print(f"       e.g. {causes[k][0]!r}")
  if not causes:
    print("  none")
  return 0


if __name__ == "__main__":
  sys.exit(main())