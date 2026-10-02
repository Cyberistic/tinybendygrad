#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/renderer/nir_llvmir.bend (STAGE 1).

Each entry is a (name, old, new) edit that must appear EXACTLY ONCE in the
source. The harness applies it to a scratch copy IN THE SAME DIRECTORY (the file
imports ./__init__.bend and ./../uop/ops.bend by relative path), runs the
interpreted lane, and diffs against the unmutated lane. What moves is the
measurement; what does NOT move is the more useful half -- it names what this
gate is blind to.

    python3 .agents/slop/nl/nl-mutate.py            # run all
    python3 .agents/slop/nl/nl-mutate.py M7 M12     # run some
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
REL = "tinybendygrad/renderer/nir_llvmir.bend"
BEND = os.path.join(ROOT, "bin", "bend")

MUTATIONS = [
  # ---------------------------------------------------------------- ldt
  ("M1",
   'def ldt.ints(bits: U32) -> String: String.concat(["i", U32.show(bits)])',
   'def ldt.ints(bits: U32) -> String: String.concat(["i", U32.show(U32.div(bits, 8))])',
   "the integer arm is `\"i\" + str(bits)`, NOT `\"i\" + str(bits // 8)`. This\n"
   "   mutation is the bug the FIRST version of this file actually had: eight\n"
   "   `ldt` rows answered i1/i2/i4/i8, which is a plausible and self-consistent\n"
   "   table. It is in the table because the failure mode is the whole argument\n"
   "   for a string diff against a generated oracle."),
  ("M2",
   '    case "half"           : "half"',
   '    case "half"           : "bfloat"',
   "`__bf16` is the ONLY dtype the map calls `bfloat`. Swapping it onto `half`\n"
   "   moves the half rows and the ptr-half row but leaves the bf16 rows, so it\n"
   "   is caught only because both are in the table."),
  ("M3",
   "def ldt.v(+d: S.Dt, +count: U32) -> String:\n"
   '  Bool.pick(String, U32.is_gt(count, 1), String.concat(["<", U32.show(count), " x ", ldt.of(d), ">"]), ldt.of(d))',
   "def ldt.v(+d: S.Dt, +count: U32) -> String:\n"
   '  Bool.pick(String, U32.is_ge(count, 1), String.concat(["<", U32.show(count), " x ", ldt.of(d), ">"]), ldt.of(d))',
   "the `count > 1` arm. `ldt 0 float` and `ldt 1 float` are the two fixtures\n"
   "   that separate `>` from `>=`, and CPython answers the bare name for both."),
  ("M4",
   "def NI() -> String: \"NotImplementedError\"",
   "def NI() -> String: \"NotImplementedError\"  # CONTROL: comment only",
   "CONTROL 1: a comment-only edit, which must move NOTHING."),
  ("M5",
   '      Bool.pick(String, U32.is_gt(S.Dt.itemsize(ot), S.Dt.itemsize(it)), "fpext", "fptrunc"),',
   '      Bool.pick(String, U32.is_gt(S.Dt.itemsize(ot), S.Dt.itemsize(it)), "fptrunc", "fpext"),',
   "`fpext` is the WIDENING arm, so it is the `>` arm. Swapping the two moves\n"
   "   every float-to-float cell whose widths differ -- which is `half->float`,\n"
   "   `__bf16->float` and `float->double`, three cells in each of the two grid\n"
   "   directions."),
  ("M6",
   '        Bool.pick(String, U32.is_lt(S.Dt.itemsize(ot), S.Dt.itemsize(it)), "trunc", "zext"), NI())),',
   '        Bool.pick(String, U32.is_lt(S.Dt.itemsize(ot), S.Dt.itemsize(it)), "trunc", "sext"), NI())),',
   "the unsigned/bool -> int narrow arm is `zext`, and the signed -> int one is\n"
   "   `sext`. They differ only for the NINE integer dtypes, so this moves the\n"
   "   unsigned half of the grid and nothing else -- which is what makes the\n"
   "   `lcast.b` direction worth having at all."),
  ("M7",
   '      Bool.pick(String, S.Dt.is_int(ot), Bool.pick(String, S.Dt.is_unsigned(ot), "fptoui", "fptosi"), NI())),',
   '      Bool.pick(String, S.Dt.is_int(ot), "fptosi", NI())),',
   "float -> int ignores `is_unsigned`. The unsigned targets are the four fp8\n"
   "   widths and the four uint widths."),
  ("M8",
   'def NI() -> String: "NotImplementedError"',
   'def NI() -> String: "NoCast"',
   "the WALL MARKER. `lcast.a void` and `lcast.b void` are the two rows that\n"
   "   make it reachable; `lcast.b bool` is the row that makes the FALL-THROUGH\n"
   "   reachable, because `float -> bool` is the only pair where clause 1 is\n"
   "   entered and answers nothing."),

  # ---------------------------------------------------------------- lop
  ("M9",
   'def ldt.flags() -> String: " nsz arcp contract afn"',
   'def ldt.flags() -> String: "nsz arcp contract afn"',
   "the LEADING SPACE of `flags`. It is a row of its own (`lop.flags`) for\n"
   "   exactly this reason, and five of the six float table entries are built from\n"
   "   it -- so this moves the flags row and every `lop.float*` row that spells\n"
   "   `fcmp`."),
  ("M10",
   '    case O.OpsCMPLT{}: "icmp slt"',
   '    case O.OpsCMPLT{}: "icmp ult"',
   "`signed_lop`'s CMPLT is `icmp slt` and only that one cell differs from the\n"
   "   unsigned table -- so it moves ONE cell of `lop.signed` plus the four\n"
   "   `lop signed char|short|int|long` rows and four `lop.op CMPLT` cells."),
  ("M11",
   '    case O.OpsFDIV{} : String.concat(["fdiv", ldt.flags()])',
   '    case O.OpsFDIV{} : String.concat(["fadd", ldt.flags()])',
   "`float_lop`'s SIX keys are the ones `lop[dt]` has for a FLOAT, and `FDIV` is\n"
   "   the only one of the thirteen that an integer dtype does NOT have -- so\n"
   "   this is the value AND the key set in one edit."),
  ("M12",
   "   O.OpsOR{}, O.OpsAND{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}]",
   "   O.OpsOR{}, O.OpsAND{}, O.OpsXOR{}, O.OpsSHL{}]",
   "`lops.uf()` is `unsigned_lop`'s own TWELVE keys and `lop[dt]` for an integer\n"
   "   is exactly that list, in that order. Dropping SHR moves the two `.len`\n"
   "   rows, all NINE integer dtype rows and `lop.op SHR`."),
  ("M13",
   "def lop.has_f(+op: O.Op) -> Bool: List.contains(~O.Op, O.eq_op, lops.sf(), op)",
   "def lop.has_f(+op: O.Op) -> Bool: True{}",
   "the float-table membership test. This is the predicate that decides WHICH\n"
   "   dtypes an op row walks, so it moves all thirteen `lop.op` rows -- and only\n"
   "   those, because the per-dtype rows do not go through it."),
  ("M14",
   "def lop.dts_of(+op: O.Op) -> List<&2, S.Dt>: lop.dts.go(R.dtypes_all(), op, Nil{})",
   "def lop.dts_of(+op: O.Op) -> List<&2, S.Dt>: lop.dts.go(lop.keys(), op, Nil{})",
   "the op rows are ordered by `dtypes.all`, NOT by `lop`'s key order, because\n"
   "   CPython's oracle walks `ALL`. Swapping the source of the list moves all\n"
   "   thirteen op rows and NOTHING else -- which is the point: it is a pure\n"
   "   ORDER mutation, invisible to any row that is not positional."),
  ("M15",
   "def cfo_base() -> List<&2, O.Op>: List.append(&2, O.Op, lops.uf(), [O.OpsFDIV{}])",
   "def cfo_base() -> List<&2, O.Op>: lops.uf()",
   "`code_for_op`'s keys are the UNION of the three tables, and FDIV is in the\n"
   "   union only through `float_lop`. Dropping it moves the two sorted\n"
   "   `code_for_op` strings and BOTH `.len` rows."),
  ("M16",
   "def cfo_amd() -> List<&2, O.Op>: List.append(&2, O.Op, cfo_base(), intrs())",
   "def cfo_amd() -> List<&2, O.Op>: List.append(&2, O.Op, cfo_base(), [O.OpsSQRT{}])",
   "AMD ADDS the three `llvm_intrinsics` ops, so its `code_for_op` has SIXTEEN\n"
   "   keys where the base has THIRTEEN. Keeping one of the three moves only the\n"
   "   amd rows."),
  ("M17",
   "  Llvm{True{}, 1, True{}, True{}, \"\", [2147483647, 65535, 65535], [2415919103, 2415919103, 2415919103],\n"
   "       True{}, [4294967295, 4294967295, 4294967295], 65536}",
   "  Llvm{True{}, 1, True{}, True{}, \"\", [2147483647, 65535, 65535], [2415919103, 2415919103, 2415919103],\n"
   "       True{}, [4294967295, 4294967295, 4294967295], 32768}",
   "AMD's `shared_max` is HIPRenderer's 65536 and the base's is 32768. This\n"
   "   moves ONE row, which is the thinnest localisation in the table -- and it\n"
   "   is there because `amd.smax` is a FIELD and not a literal."),
  ("M18",
   "  Llvm{True{}, 0, False{}, True{}, \"\", [1, 0, 0], [2415919103, 2415919103, 2415919103], False{}, Nil{}, 32768}",
   "  Llvm{True{}, 0, True{}, True{}, \"\", [1, 0, 0], [2415919103, 2415919103, 2415919103], False{}, Nil{}, 32768}",
   "CPULLVM's `has_local = False` is the ONLY class-attribute flip in the three\n"
   "   renderers, and it is what decides `alloca` versus a global in `_render_kernel`."),
  ("M19",
   '  Bool.pick(String, has, Bool.pick(String, U32.is_eq(tag, 1), "amdgpu_kernel", "None"), "AttributeError")',
   '  Bool.pick(String, has, Bool.pick(String, U32.is_eq(tag, 1), "amdgpu_kernel", "None"), "None")',
   "`LLVMRenderer.abi` is an ANNOTATION with no value, so `getattr` raises. A\n"
   "   `Data` field cannot be absent, so `has_abi` IS the absent case and the\n"
   "   marker is the exception's NAME. Answering `None` here is the mistake a\n"
   "   reader makes when it forgets the base class is abstract in that field."),

  # ---------------------------------------------------------------- naming
  ("M20",
   '  String.concat(["%", Bool.pick(String, is_local, "local", "reg"), "_", U32.show(slot)])',
   '  String.concat(["%", Bool.pick(String, is_local, "reg", "local"), "_", U32.show(slot)])',
   "the ONLY addrspace the name spells is LOCAL; GLOBAL, REG and ALU all read\n"
   "   `reg`, so THREE of the four rows are a CONSTANT COLUMN. Inverting the\n"
   "   test moves all four -- every name flips -- which is measured rather than\n"
   "   assumed and is the difference between this and `reduce.bend`'s rule-4\n"
   "   shape, where a constant column let a mutation move NOTHING."),
  ("M21",
   '  String.concat(["tail call i32 @llvm.amdgcn.", Bool.pick(String, is_l, "workitem", "workgroup"), ".id.",',
   '  String.concat(["tail call i32 @llvm.amdgcn.", Bool.pick(String, is_l, "workgroup", "workitem"), ".id.",',
   "`code_for_workitem`'s two entries differ ONLY in workgroup/workitem, and the\n"
   "   gate runs both at three widths -- so all six rows move."),
  ("M22",
   '  Bool.pick(String, U32.is_eq(x, 0), "x", Bool.pick(String, U32.is_eq(x, 1), "y", "z"))',
   '  Bool.pick(String, U32.is_eq(x, 0), "x", Bool.pick(String, U32.is_eq(x, 1), "x", "z"))',
   "`chr(120 + int(x))` is x, y, z for widths 0, 1, 2. Collapsing 1 onto 0\n"
   "   moves FOUR of the six rows -- a width map is a per-cell table and this is\n"
   "   the mutation that shows the gate is not reading one fixture."),
  ("M23",
   '  [String.concat(["fence syncscope(\\"workgroup\\") release"]),\n'
   '   "tail call void @llvm.amdgcn.s.barrier()",\n'
   '   "fence syncscope(\\"workgroup\\") acquire", ""]',
   '  ["fence syncscope(workgroup) release",\n'
   '   "tail call void @llvm.amdgcn.s.barrier()",\n'
   '   "fence syncscope(workgroup) acquire", ""]',
   "the TWO QUOTES round `workgroup`. `syncscope(workgroup)` is a different\n"
   "   LLVM attribute and a perfectly plausible string, which is why\n"
   "   `barrier[0]` and `barrier[2]` are rows and not a count."),
  ("M24",
   '   "fence syncscope(\\"workgroup\\") acquire", ""]',
   '   "fence syncscope(\\"workgroup\\") acquire"]',
   "the EMPTY TAIL. `barrier` ends in a newline, so `split` yields four pieces\n"
   "   and `barrier.lines` is 4. Dropping it moves the count row AND `barrier[3]`,\n"
   "   which is the only way a dropped TRAILING element is visible at all."),
  ("M25",
   '  String.concat(["  ", xn, " = getelementptr inbounds ", ldt.t(d, cnt, False{}), ", ", ldt.t(d, cnt, True{}), " ",\n'
   '    s0, ", ", ldt.t(d1, 1, False{}), " ", s1])',
   '  String.concat(["  ", xn, " = getelementptr inbounds ", ldt.t(d, 1, False{}), ", ", ldt.t(d, 1, True{}), " ",\n'
   '    s0, ", ", ldt.t(d1, 1, False{}), " ", s1])',
   "the element type and the pointer type take the BUFFER'S COUNT. Hard-wiring\n"
   "   1 moves only the two vector fixtures and leaves the two scalar ones green\n"
   "   -- which is why `gep %v0 floatx4 long` and `gep %v9 __bf16x8` exist."),
  ("M26",
   '  String.concat(["  ", xn, " = getelementptr inbounds ",',
   '  String.concat(["  ", xn, " = getelementptr ",',
   "`inbounds` is a one-word literal in a template, and `String.concat` drops a\n"
   "   literal SILENTLY -- which is the failure this whole file is gated against.\n"
   "   It moves four rows and nothing else."),
  ("M27",
   '    sp4(), nl(), "  br label %select_clip", nl(),',
   '    nl(), "  br label %select_clip", nl(),',
   "the FOUR TRAILING SPACES after `float -{fp8_max})` in llvmir.py:258. The\n"
   "   oracle prints CPython's bytes and `diff` is byte-exact, so the spaces are\n"
   "   in the expectation and dropping them is one moved row -- the mutation a\n"
   "   human reading both lanes side by side would call green."),
  ("M28",
   "      Bool.pick(String, Bool.and(drop, fp8_is_sp(h)), String.concat([acc, rest]),",
   "      Bool.pick(String, False{}, String.concat([acc, rest]),",
   "the separator's SECOND CHARACTER. Not consuming the space indents every\n"
   "   label body THREE spaces where CPython indents two. This is a bug the file\n"
   "   ACTUALLY HAD and it moves eight of the twenty-eight prefix lines."),
  ("M29",
   "def fp8_split2(+cs: List<&2, Char>, drop: Bool, +acc: String) -> String:",
   "def fp8_split2(+cs: List<&2, Char>, drop: Bool, +acc: String) -> String:  # CONTROL: comment only",
   "CONTROL 2. M30 is the accumulator mutation and it is severe enough that the\n"
   "   control beside it is what makes the other numbers mean something."),

  # ---------------------------------------------------------------- supported_dtypes
  ("M30",
   "  Bool.or(Bool.or(Bool.and(O.eq_dt(d, S.bfloat16()), Bool.not(x86)),\n"
   "                  Bool.and(O.eq_dt(d, S.half()), Bool.not(osx))), is_fp8(d))",
   "  Bool.or(Bool.or(Bool.and(O.eq_dt(d, S.bfloat16()), Bool.not(x86)),\n"
   "                  Bool.and(O.eq_dt(d, S.half()), Bool.not(osx))), False{})",
   "the `d not in dtypes.fp8s` conjunct. `sd cpullvm` is the ONLY renderer in\n"
   "   this stage that drops every fp8 dtype, so this moves the eight cpullvm\n"
   "   rows and no amd row -- which is the difference between the two filters\n"
   "   made visible."),
  ("M31",
   "  Bool.or(Bool.or(Bool.and(O.eq_dt(d, S.bfloat16()), Bool.not(x86)),\n"
   "                  Bool.and(O.eq_dt(d, S.half()), Bool.not(osx))), is_fp8(d))",
   "  Bool.or(Bool.and(O.eq_dt(d, S.half()), Bool.not(osx)), is_fp8(d))",
   "the `bfloat16` clause. It is the one conjunct that needs the ARCH, so it is\n"
   "   the one that separates `sd cpullvm riscv64` from `sd cpullvm x86_64`."),
  ("M32",
   "def sd.drop_amd(+d: S.Dt, fnuz: Bool) -> Bool:\n"
   "  Bool.and(is_fp8(d), Bool.not(Bool.and(fnuz, is_fnuz(d))))",
   "def sd.drop_amd(+d: S.Dt, fnuz: Bool) -> Bool:\n"
   "  Bool.and(is_fp8(d), Bool.not(fnuz))",
   "`d not in fp8s or d in amd_fp8s(arch)`. `amd_fp8s('gfx942')` is the FNUZ\n"
   "   PAIR and not all four, so dropping the `is_fnuz` conjunct keeps\n"
   "   `float8_e4m3` and `float8_e5m2`. One row moves: `sd amd gfx942`."),
  ("M33",
   "def is_fp8(+d: S.Dt) -> Bool: List.contains(~S.Dt, O.eq_dt, fp8s(), d)",
   "def is_fp8(+d: S.Dt) -> Bool: List.contains(~S.Dt, O.eq_dt, fnuzs(), d)",
   "the fp8 SET. `fp8s()` is four dtypes and `fnuzs()` two, so this moves only\n"
   "   the cpullvm rows -- the two rows whose kept set grows by two dtypes."),
  ("M34",
   "def dts.uf() -> List<&2, S.Dt>: [S.boolean(), S.uint8(), S.uint16(), S.uint32(), S.uint64()]",
   "def dts.uf() -> List<&2, S.Dt>: [S.uint8(), S.uint16(), S.uint32(), S.uint64(), S.boolean()]",
   "`lop`'s key order starts with `bool` because the dict literal is\n"
   "   `(dtypes.bool,)+dtypes.uints`. Moving it to the end moves `lop.keys` --\n"
   "   and `code_for_op`'s sorted join is NOT moved, which is the point: that one\n"
   "   is sorted and this one is not, and both are rows."),

  # ---------------------------------------------------------------- the sort
  ("M35",
   "        List.append(&2, String, [h], osort.ins(x, t)))",
   "        t)",
   "the insertion sort's ELSE arm. Dropping the head on the else arm is the\n"
   "   first bug this sort had: `llvm.code_for_op` came back as\n"
   "   `ADD,MUL,ADD,OR,ADD,...` -- a thirteen-slot list with duplicates. The\n"
   "   `.len` row stays GREEN, which is the count-row note in its sharpest form."),
  ("M36",
   "def unames_s(+ds: List<&2, S.Dt>) -> String: String.join(osort.ss(unames.go(ds, Nil{}), Nil{}), \",\")",
   "def unames_s(+ds: List<&2, S.Dt>) -> String: String.join(unames.go(ds, Nil{}), \",\")",
   "CPython's `supported_dtypes` returns a SET, so the oracle SORTS and the port\n"
   "   must too. Not sorting moves all NINE `sd` rows and NO `lop` row -- the two\n"
   "   spellings of a dtype list that differ only in their order, which is why\n"
   "   they are two defs."),

  # ---------------------------------------------------------------- the grid
  ("M37",
   "def CA() -> List<&2, S.Dt>:\n"
   "  [S.void(), S.half(), S.bfloat16(), S.single(), S.double(), S.boolean(),\n"
   "   S.int8(), S.int16(), S.int32(), S.int64(), S.uint8(), S.uint16(), S.uint32(), S.uint64()]",
   "def CA() -> List<&2, S.Dt>:\n"
   "  [S.half(), S.bfloat16(), S.single(), S.double(), S.boolean(), S.void(),\n"
   "   S.int8(), S.int16(), S.int32(), S.int64(), S.uint8(), S.uint16(), S.uint32(), S.uint64()]",
   "the lcast GRID's order, which is dtype.py's declaration order for the\n"
   "   fourteen and `void` first. Moving `void` is a pure ORDER edit: it moves\n"
   "   BOTH directions of the grid -- twenty-eight rows -- and changes no cell.\n"
   "   It is here because `diff` is positional and an order bug is otherwise\n"
   "   invisible."),
  ("M38",
   "def fp8_prefix(has_fp8: Bool, +mx: String) -> List<&2, String>:\n"
   "  Bool.pick(List<&2, String>, has_fp8, fp8_lines(fp8_raw(mx)), Nil{})",
   "def fp8_prefix(has_fp8: Bool, +mx: String) -> List<&2, String>:\n"
   "  Bool.pick(List<&2, String>, True{}, fp8_lines(fp8_raw(mx)), Nil{})",
   "`has_fp8` is `any(u.dtype in dtypes.fp8s for u in uops)` (llvmir.py:252). A\n"
   "   reader that always answers True moves `fp8 prefix none` and NOTHING else\n"
   "   -- and that single row is the only thing that can see it. `fp8 prefix\n"
   "   lines` and the twenty-eight line rows are blind to it by construction."),
  ("M39",
   '  Bool.pick(List<&2, S.Dt>, lop.has(op, d), List.append(&2, S.Dt, [d], rest), rest)\n\ndef lop.dts_of',
   '  Bool.pick(List<&2, S.Dt>, lop.has(op, d), List.append(&2, S.Dt, [d], rest), rest)  # CONTROL\n\ndef lop.dts_of',
   "CONTROL 3: a trailing comment on the `lop.dts.go` arm, which must move\n"
   "   NOTHING. Together with M4 and M29 that is three controls."),
]


def run_gate(src_path):
  """Run the interpreted lane. Returns (ok, stdout+stderr)."""
  r = subprocess.run([BEND, src_path], cwd=ROOT, capture_output=True, text=True, timeout=900)
  return (r.returncode == 0 and "PROOFS FAIL" not in r.stdout), r.stdout + r.stderr


def main():
  want = [a for a in sys.argv[1:] if not a.startswith("--")]
  short = "--short" in sys.argv
  with open(os.path.join(ROOT, REL)) as f:
    base = f.read()

  ok, baseline = run_gate(os.path.join(ROOT, REL))
  if not ok:
    print("BASELINE DOES NOT RUN:\n" + baseline[:2000])
    return 1
  base_lines = baseline.splitlines()

  results = []
  for mid, old, new, what in MUTATIONS:
    if mid and want and mid not in want:
      continue
    n = base.count(old)
    if n != 1:
      results.append((mid, None, "EDIT MATCHES %d TIMES -- fix the mutation" % n, what))
      continue
    scratch_dir = os.path.join(ROOT, os.path.dirname(REL))
    with tempfile.NamedTemporaryFile("w", suffix=".bend", dir=scratch_dir, delete=False) as tf:
      tf.write(base.replace(old, new))
      tmp = tf.name
    try:
      ok, out = run_gate(tmp)
    except subprocess.TimeoutExpired:
      results.append((mid, None, "TIMEOUT", what))
      continue
    finally:
      os.unlink(tmp)
    if not ok:
      first = [x for x in out.splitlines() if x.startswith("- ")][:1]
      results.append((mid, None, "FAIL compile (%s)" % (first[0][2:][:60] if first else "?"), what))
      continue
    mut = out.splitlines()
    moved = [i for i, (a, b) in enumerate(zip(base_lines, mut)) if a != b]
    names = []
    for i in moved[:6]:
      names.append(base_lines[i].split("=")[0].strip())
    more = " ..." if len(moved) > 6 else ""
    label = ", ".join(names) or "(none)"
    results.append((mid, moved, "%d row(s): %s%s%s" % (len(moved), label, more,
                                                       "  %+d lines" % (len(mut) - len(base_lines)) if len(mut) != len(base_lines) else ""), what))

  width = max(len(r[0]) for r in results) + 2
  for mid, moved, summary, what in results:
    print("%-*s %s" % (width, mid, summary))
    if not short:
      for ln in what.splitlines():
        print("%-*s   %s" % (width, "", ln))
  return 0


if __name__ == "__main__":
  sys.exit(main())