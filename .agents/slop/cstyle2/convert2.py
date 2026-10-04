#!/usr/bin/env python3
"""convert2.py -- CONVERT text rows into C, then gate every conversion THREE ways.

THREE OBLIGATIONS, AND THE POINT IS THAT THEY ARE SEPARABLE. `cc` accepting a file, the
binary running, and the numbers matching tinygrad are three different facts. So each
converted row carries three independent columns and nothing here folds them.

WHAT A CONVERSION IS. The row's OWN value is never edited. A translation unit is built
AROUND it, supplying only declarations that upstream's own machinery supplies in the same
situation, and every added line is recorded in the row's `added` column. Two of them:

  kern2  the one vector prefix upstream's `_render_defines` emits, captured LIVE from
         `ClangRenderer.render_vector_prefix` by preamble-oracle.py.
  cfo    the variables the row's own value names. The arity comes from the value, not from
         an op table: `cc` gets the last word on whether that arity is expressible.

THE DRIVER IS NOT SOMETHING THE PORT CAN INFLUENCE. It re-declares the entry point FROM THE
ROW'S OWN SIGNATURE (parameters copied out of the row's text with the names replaced), sizes
the buffers from the highest lane index the row's own body touches, reads and writes raw
bytes, pre-fills the output with a sentinel no lane of the program can produce, and prints
only bit patterns.

THE FLAGS ARE TINYGRAD'S, not mine: `ClangCompiler.compile`'s
(`runtime/support/compiler_cpu.py:14-17`) minus `-nostdlib`, which only matters for a kernel
destined for `mmap` + `dllopen` rather than for a host program. `-ffreestanding` is what
makes `sqrt(X)` resolve, because `CStyleLanguage` emits it with no `#include`.

  usage: convert2.py <port.txt> --preamble <file> [--tsv out.tsv] [--cc cc]
"""
import argparse
import importlib.util
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("cstyle_gate", HERE.parent / "cstyle-gate.py")
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

DIALECT = {"BASE": ["-x", "c"], "CLANG": ["-x", "c"], "OPENCL": ["-x", "cl"],
           "HIP": ["-x", "c++"]}
NO_FRONTEND = {"METAL": "no `-x metal` in Apple clang", "CUDA": "no CUDA installation"}
# tinygrad's own flags, `compiler_cpu.py:14-17`.
CCFLAGS = ["-O2", "-fPIC", "-ffreestanding", "-fno-math-errno", "-fno-ident"]

# The row's own DTYPE TAG, never a table of ops.
DTYPE = {"f32": "float", "f64": "double", "f16": "half"}


def unescape(s):
  return s.replace("\\n", "\n")


def device_of(name):
  for p in name.split()[1:]:
    if p in DIALECT or p in NO_FRONTEND:
      return p
  return "BASE"


# --------------------------------------------------------------------- the `cfo` harness
def cfo_harness(row, value):
  dt = row.split()[-1]
  if dt not in DTYPE:
    return None, f"no host C type for the row's dtype tag {dt!r}"
  ctype = DTYPE[dt]
  used = [v for v in ("X", "Y", "Z") if v in value]
  if not used:
    return None, "the value names no input variable"
  # ONE type, then the names. (An earlier version put the type on every declarator, which
  # `cc` caught: `expected identifier or '('`. A harness bug found by the compiler it runs.)
  decl = f"{ctype} " + ", ".join(f"{v} = IN_{v}" for v in used)
  # `math.h` because the BASE renderer's tables emit BARE `sqrt(X)`/`sin(X)`, and no real
  # device ever compiles them: ClangRenderer replaces them with `__builtin_*`
  # (`cstyle.py:293-294`), so `render_kernel` emits no include for them and the declaration
  # has to come from the harness. Recorded in `added` so the liberty is visible.
  src = ('#include <stdio.h>\n#include <stdint.h>\n#include <string.h>\n#include <math.h>\n'
         + ("#define half _Float16\n" if ctype == "half" else "")
         + 'int main(void) {\n'
         '  const float IN_X = 1.5f, IN_Y = 3.25f, IN_Z = 0.75f;\n  ' + decl + ';\n'
         f'  volatile {ctype} R = ({ctype})({value});\n'
         f'  unsigned char b[sizeof R];\n'
         f'  memcpy(b, (const void *)&R, sizeof R);\n'
         f'  for (size_t i = 0; i < sizeof R; i++) printf("%02x", b[i]);\n'
         '  printf("\\n");\n  return 0;\n}\n')
  return src, (f"#include <math.h>; one {ctype} per identifier the value names "
               f"({', '.join(used)})"
               + ("; `#define half _Float16`, which the port's own HIP kern2 rows carry"
                  if ctype == "half" else ""))


# --------------------------------------------------------------------- the `kern2` driver
SIG = re.compile(r"E_4\s*\((.*?)\)\s*\{", re.S)
LANE = re.compile(r"val0\[(\d+)\]")


def split_top(s, sep=","):
  """Split on `sep` at paren/bracket depth 0, so a parameter default cannot split a row."""
  out, depth, cur = [], 0, ""
  for ch in s:
    if ch in "([":
      depth += 1
    elif ch in ")]":
      depth -= 1
    if ch == sep and depth == 0:
      out.append(cur)
      cur = ""
    else:
      cur += ch
  if cur.strip():
    out.append(cur)
  return [x.strip() for x in out if x.strip()]


def kern_driver(value):
  """A `main` derived from the ROW'S OWN TEXT: the parameter list with the names replaced,
  the buffer SIZE from the row's own body, one float per non-pointer parameter, a sentinel
  the program cannot produce, and bit patterns out. Nothing here is per-row knowledge.

  THE BUFFERS ARE `aligned_alloc`'d, NOT STACK ARRAYS, and that is load-bearing. With
  `float buf[N]` this driver got `3fc00000` back -- the INPUT's own bits, i.e. the kernel's
  16-byte store had VANISHED. `buf` is 4-byte aligned and the body stores through a
  `float4*`, so the store is UB; and nothing in the TU says the callee's store reaches the
  later read of `buf[0]`, so clang may answer that read from the register the initialiser
  left there. An allocation the compiler cannot reason about removes the whole class."""
  m = SIG.search(value)
  if not m:
    return None, "the row's text has no `E_4(...) {` definition"
  params = split_top(m.group(1))
  decls, args, ptrs, scalars = [], [], [], []
  for i, p in enumerate(params):
    ptr = "*" in p
    decls.append(re.sub(r"([A-Za-z_]\w*)\s*((?:\[[^\]]*\])?)\s*$",
                        lambda mm: f"a{i}{mm.group(2)}", p))
    (ptrs if ptr else scalars).append(i)
    args.append(f"buf{i}" if ptr else f"IN[{len(scalars)-1}]")
  if not ptrs:
    # No pointer parameter means no buffer to print, so there is nothing a host program
    # could observe. Reported, not crashed on: the `kern2 ... alu` rows are this case, and
    # they are also the rows whose body reads a buffer its own signature does not declare.
    return None, "no pointer parameter, so the kernel has nothing a host can observe"
  lanes = max([int(x) for x in LANE.findall(value)], default=0) + 1
  # A `float4` access spans 4 floats whatever the body's lane indices say, so a buffer is at
  # least that wide; `lanes` is how many of them the program has an opinion about.
  width = max(lanes, 4)
  body = ["#include <stdio.h>", "#include <stdlib.h>", "#include <string.h>",
          f"void E_4({', '.join(decls)});",
          "#define W " + str(width),
          "#define LANES " + str(lanes),
          "int main(void) {",
          "  static const float IN[3] = {1.5f, 3.25f, 0.75f};"]
  for i in ptrs:
    # `aligned_alloc` requires the SIZE to be a multiple of the ALIGNMENT (C11 7.22.3.1);
    # `4*W` is 16 and the alignment is 64, so the first version asked for an
    # illegal size, got NULL back, and every kernel row died on SIGSEGV (rc=-11).
    body.append(f"  float *buf{i} = aligned_alloc(64, ((4 * W + 63) / 64) * 64);\n  if (!buf{i}) return 9;")
  body.append("  for (int i = 0; i < W; i++) { "
              + " ".join(f"buf{i}[i] = -12345.0f;" for i in ptrs) + " }")
  body.append("  for (int i = 0; i < W; i++) { "
              + " ".join(f"buf{i}[i] = IN[i % 3];" for i in ptrs) + " }")
  body.append("  unsigned char b[4];")
  body.append(f"  E_4({', '.join(args)});")
  # ONLY the FIRST pointer buffer is printed. An earlier version printed every pointer and
  # so emitted two lines per row -- the second being the INPUT buffer's untouched value,
  # which reads like a second output lane and is not one.
  body.append(f"  for (int i = 0; i < LANES; i++) {{ memcpy(b, (const void *)&buf{ptrs[0]}[i], 4);"
              ' printf("%02x%02x%02x%02x\\n", b[0], b[1], b[2], b[3]); }')
  body += ["  return 0;", "}"]
  note = (f"{len(params)} parameter(s) copied from the row's own signature, {lanes} lane(s) "
          f"from the highest val0[k] its body reads, {width}-float aligned buffers")
  return "\n".join(body) + "\n", note


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("port")
  ap.add_argument("--preamble", required=True)
  ap.add_argument("--tsv")
  ap.add_argument("--cc", default="cc")
  ap.add_argument("--decl-from", default=None,
                  help="supply the declarations from ANOTHER ROW OF THE SAME RUN. Used for "
                       "the HIP `cfo` rows, whose values call `__ocml_*`: the port renders "
                       "those declarations in its own `hipocml` row, so the port's own "
                       "output is the preamble for the port's own output.")
  a = ap.parse_args()
  preamble = pathlib.Path(a.preamble).read_text().rstrip("\n")
  rows, _s, dups = gate.rows_strict(pathlib.Path(a.port).read_text())
  assert not dups, dups
  decl_from = ""
  if a.decl_from:
    assert a.decl_from in rows, f"no row named {a.decl_from!r} to take declarations from"
    decl_from = unescape(gate.split_py(rows[a.decl_from])[0]).rstrip("\n")
  recs = []
  with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td)
    for name in sorted(rows):
      got, _lit = gate.split_py(rows[name])
      val = unescape(got)
      fam, dev = name.split()[0], device_of(name)
      rec = {"row": name, "family": fam, "device": dev, "added": "", "gate1_cc": "",
             "gate2_run": "", "gate3_agree": "", "bits": "", "note": ""}
      recs.append(rec)
      if dev in NO_FRONTEND:
        rec["note"] = NO_FRONTEND[dev]
        continue
      flags = DIALECT[dev]
      if fam == "kern2":
        kern, note = kern_driver(val)
        if kern is None:
          rec["note"] = note
          continue
        src = preamble + "\n" + val + "\n" + kern
        rec["added"] = "the one vector prefix upstream's _render_defines emits; " + note
      elif fam == "cfo" and val.strip():
        h = cfo_harness(name, val)
        if h[0] is None:
          rec["note"] = h[1]
          continue
        src, rec["added"] = h[0], h[1]
        if "__ocml_" in val and decl_from:
          src = decl_from + "\n" + src
          rec["added"] += "; plus the `__ocml_*` declarations from this run's `hipocml` row"
      else:
        rec["note"] = "not a family this conversion wraps; see measure.py's cause table"
        continue
      f = td / "k.c"
      f.write_text(src)
      p = subprocess.run([a.cc, *flags, *CCFLAGS, "-fsyntax-only", str(f)],
                         capture_output=True, text=True)
      rec["gate1_cc"] = int(p.returncode == 0)
      if p.returncode:
        errs = [l for l in p.stderr.splitlines() if ": error:" in l]
        rec["note"] = errs[0].split(": error:")[1].strip()[:64] if errs else "?"
        continue
      exe = td / "k.out"
      q = subprocess.run([a.cc, *flags, *CCFLAGS, "-o", str(exe), str(f)],
                         capture_output=True, text=True)
      if q.returncode:
        rec["gate2_run"] = 0
        errs = [l for l in q.stderr.splitlines() if ": error:" in l]
        rec["note"] = "LINK: " + (errs[0].split(": error:")[1].strip()[:56] if errs else "?")
        continue
      r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=20)
      if r.returncode != 0 or not r.stdout.strip():
        rec["gate2_run"] = 0
        rec["note"] = f"RUN rc={r.returncode} stdout={r.stdout.strip()[:40]!r}"
        continue
      rec["gate2_run"] = 1
      rec["bits"] = " ".join(r.stdout.split())

  if a.tsv:
    hdr = ["row", "family", "device", "added", "gate1_cc", "gate2_run", "gate3_agree",
           "bits", "note"]
    pathlib.Path(a.tsv).write_text(
      "\t".join(hdr) + "\n" + "\n".join("\t".join(str(r[h]) for h in hdr) for r in recs) + "\n")

  n = len(recs)
  for k, lab in (("gate1_cc", "GATE 1  cc accepted the built translation unit"),
                 ("gate2_run", "GATE 2  it linked and ran"),
                 ("gate3_agree", "GATE 3  its output equalled tinygrad's")):
    print(f"  {lab:<48} {sum(1 for r in recs if r[k] == 1)}/{n}")
  print()
  print("EVERY ROW THAT CROSSED GATE 1, BY NAME")
  for r in recs:
    if r["gate1_cc"] == 1 or (r["note"] and r["family"] in ("kern2", "cfo")):
      print(f"  {r['row']!r:<32} cc={r['gate1_cc']!s:<5} run={r['gate2_run']!s:<5} "
            f"agree={r['gate3_agree']!s:<5} {r['bits'][:40]:<40} {r['note'][:46]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())