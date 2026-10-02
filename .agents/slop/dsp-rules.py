#!/usr/bin/env python3
"""dsp-rules.py -- the MUTATION TABLE for the re-armed dtype ladders of
`tinybendygrad/runtime/ops_dsp.bend`, over the lane that is NOW COMPARED.

WHY IT CAN ANSWER AT ALL. Before this unit the gate printed `nm=value` and carried the
expectation in a `# py=` comment, so nothing compared and `dsp_gate_check.py` called
itself "AUTHORITY: NONE". Every mutation below therefore had a reference to disagree
with. Now the lane is `nm = [port]   py=[CPython]` and the reference is
`.agents/slop/dsp_py.txt`, so a mutation that moves a row is a row the diff CATCHES.

Each entry is `(id, find, replace)` and `find` must occur EXACTLY ONCE: a mutation
applied to the wrong site measures something else, and a table that lies about which row
it moved is worse than no table. A site that is not unique is reported SKIPPED.

    .venv/bin/python .agents/slop/dsp-rules.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "tinybendygrad/runtime/ops_dsp.bend"
BEND = ROOT / "bin/bend"
PY = ROOT / ".venv/bin/python"

# The 793abbb REGRESSION first: put the three ladders back on dtype NAMES, which is the
# bug that shipped 512 green rows.
RULES = [
  # D01 is THE regression: it destructures to `nm` and matches the NAME, which is exactly
  # the pre-793abbb shape and -- unlike `match cls:` against a string literal -- COMPILES,
  # so the table reports the ROWS it moved instead of a parse error.
  ("D01 dt_fmt RE-ARMED ON THE NAME (the 793abbb regression, verbatim)",
   '      match cls:\n'
   '        case S.CBool{}  : "?"\n'
   '        case S.CSint{}  : dt_fmt.si(bits)\n'
   '        case S.CUint{}  : dt_fmt.su(bits)\n'
   '        case S.CFloat{} : dt_fmt.sf(bits, pri)\n'
   '        case _: dt_fmt_none()',
   '      match nm:\n'
   '        case "bool": "?"\n'
   '        case "i8": "b"\n'
   '        case "i16": "h"\n'
   '        case "i32": "i"\n'
   '        case "f32": "f"\n'
   '        case "f64": "d"'),
  ("D01b dt_supported keyed on PRI 12 (f16's, not bf16's)",
   '        case S.CFloat{}: Bool.and(U32.is_eq(bits, 16), U32.is_eq(pri, 13))',
   '        case S.CFloat{}: Bool.and(U32.is_eq(bits, 16), U32.is_eq(pri, 12))'),
  ("D02 dt_fmt.sf drops the `pri` guard (bf16 gets f16's fmt)",
   '    case 16: Bool.pick(String, U32.is_eq(pri, 12), "e", dt_fmt_none())',
   '    case 16: "e"'),
  ("D03 dt_fmt.sf forgets the 64-bit arm",
   '    case 64: Bool.pick(String, U32.is_eq(pri, 15), "d", dt_fmt_none())', '    case _: dt_fmt_none()'),
  ("D04 dt_cname.sf drops the `pri` guard (bf16 gets f16's C type)",
   '    case 16: Bool.pick(String, U32.is_eq(pri, 12), "__fp16", "__bf16")', '    case 16: "__fp16"'),
  ("D05 dt_cname.sf: an fp8 stops raising (KeyError -> a name)",
   "        case _: \"KeyError\"\n", "        case _: \"fp8\"\n"),
  ("D06 dt_itemsize_dt is a name table again (every answer wrong)",
   '    case S.Dt{pri, bits, cls, nm}: U32.div(U32.add(bits, 7), 8)',
   '    case S.Dt{pri, bits, cls, nm}: 100'),
  ("D07 dt_itemsize_dt rounds DOWN (i16 becomes 1)",
   'U32.div(U32.add(bits, 7), 8)', 'U32.div(bits, 8)'),
  ("D08 dt_is_fp8_dt drops the `cls` arm (i8/u8 are fp8s too)",
   """        case S.CFloat{}: U32.is_eq(bits, 8)
        case _: False{}""", """        case _: U32.is_eq(bits, 8)"""),
  ("D09 dt_is_bf16_dt forgets `pri` (i16 is dropped too)",
   '        case S.CFloat{}: Bool.and(U32.is_eq(bits, 16), U32.is_eq(pri, 13))',
   '        case S.CFloat{}: U32.is_eq(bits, 16)'),
  ("D10 dt_supported keeps the bf16",
   'Bool.and(base, Bool.and(Bool.not(dt_is_fp8_dt(d)), Bool.not(dt_is_bf16_dt(d))))',
   'Bool.and(base, Bool.not(dt_is_fp8_dt(d)))'),
  ("D11 supported_12.at index 9: half -> bfloat16 (bf16 is NOT supported)",
   '    case 9n: S.half()', '    case 9n: S.bfloat16()'),
  ("D11b supported_12.at index 11: double -> f16",
   '    case _: S.double()', '    case _: S.half()'),
  ("D12 INSN_CNT_WORD back to 0x6a520000",
   'def INSN_CNT_WORD() -> U32: 1779810304', 'def INSN_CNT_WORD() -> U32: 1784217600'),
  ("D13 ION_SYSTEM_HEAP_ID: the port says 0, `qcom_dsp` says 25",
   'def ION_SYSTEM_HEAP_ID() -> Nat: 0n', 'def ION_SYSTEM_HEAP_ID() -> Nat: 25n'),
  ("D13b SC_OPEN 0x0BE00000 -> 0x13050100 (the port's constant)",
   'def SC_OPEN() -> U32: 199229440', 'def SC_OPEN() -> U32: 319095040'),
  ("D13c SC_SEEK 0x09010000 -> 0x9010000 (they are equal; a NO-OP mutation)",
   'def SC_SEEK() -> U32: 151004672', 'def SC_SEEK() -> U32: 151060480'),
  ("D13d SC_STAT 0x01F02000 -> 0x1F020100 (the port's constant)",
   'def SC_STAT() -> U32: 31195136', 'def SC_STAT() -> U32: 520225024'),
  ("D14 link_line grows a second dot -- THE PORT'S OWN BUG",
   'String.concat([".", n, " : ALIGN(4096) { *(.", n, ") }"])',
   'String.concat([".", n, " : ALIGN(4096) { *.(", n, ") }"])'),
  ("D19 rpc.unknown_err prints the sc in DECIMAL",
   'f"RuntimeError: Unknown op: sc={n}"', 'f"RuntimeError: Unknown op: sc={x}"'),
]


def reference():
  r = subprocess.run([str(PY), str(ROOT / ".agents/slop/dsp_oracle2.py"), "rows"],
                     capture_output=True, text=True, check=True)
  return r.stdout.split("\n")


def run():
  r = subprocess.run([str(BEND), str(TARGET)], capture_output=True, text=True)
  return None if r.returncode != 0 else r.stdout.split("\n")


def moved(base, after):
  if after is None:
    return ["<FILE DID NOT COMPILE>"]
  if len(base) != len(after):
    return [f"<ROW COUNT {len(base)} -> {len(after)}>"]
  return [b for b, a in zip(base, after) if b != a]


def main():
  ref = reference()
  base = run()
  assert base is not None, "baseline does not compile"
  text = TARGET.read_text()
  # the SUBSTRING half of the gate: compare only ` = [...]` rows, because one row prints a
  # fifteen-line link script. A whole-line diff is still what counts; this is the count.
  agree = sum(1 for b, r in zip(base, ref) if b == r)
  print(f"=== BASELINE: {len(base)} lines, {agree} agree with CPython, "
        f"{len(base) - agree - 1} disagree")
  results = []
  for rid, find, repl in RULES:
    n = text.count(find)
    if n != 1:
      results.append((rid, f"SKIPPED, the site occurs {n}x", []))
      continue
    TARGET.write_text(text.replace(find, repl))
    mv = moved(base, run())
    TARGET.write_text(text)
    results.append((rid, f"{find.strip()[:52]!r}", mv))
  blind = [r for r in results if not r[2]]
  print(f"=== RULES: {len(results)} mutations, {len(results) - len(blind)} moved rows, "
        f"{len(blind)} BLIND")
  for rid, what, mv in results:
    names = sorted({m.split(" = [")[0] for m in mv})
    print(f"  {rid}: {len(mv):3d} rows  {', '.join(names)[:76]}")
    if not mv:
      print(f"        {what}")
  assert not moved(base, run()), "a mutation leaked into the file"
  return 0


if __name__ == "__main__":
  raise SystemExit(main())