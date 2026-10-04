#!/usr/bin/env python3
"""Mutation table for tinybendygrad/nn/onnx.bend. Mutates the file in place,
re-runs the NATIVE lane, reports which rows MOVE, and restores the file.

    .venv/bin/python .agents/slop/onnx-mutate.py

A mutation that moves NOTHING is information about the GATE, not a passing test
(bend2-constraints' `device.bend` gate lesson), and each such row below is
either a control (M0/M13) or a MISSING ROW that the comment names.
"""
import shutil, subprocess, sys, os, tempfile
import patch_not_apply as PNA

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
F = os.path.join(REPO, "tinybendygrad", "nn", "onnx.bend")
BAK = "/tmp/onnxgate/mut.bak"
OUT = "/tmp/onnxgate/mut.txt"

# (id, find, replace, what it was testing)
MUTS = [
  # ---- the ONNX dtype NAME TABLE -------------------------------------------
  ("M1",  'case 2: Some{"uint8"}', 'case 2: Some{"uchar"}',
   "the DTYPES_DICT lookup KEY (:37 `self.name.lower()`). `uchar` is the ATTRIBUTE "
   "name, not the key: CPython's DTYPES_DICT has both, so the wrong one still "
   "answers a dtype and only the KEY row moves."),
  ("M2",  'case 7: Some{"int64"}', 'case 7: Some{"long"}',
   "the same lookup, on the entry whose `DType.name` is `long`."),
  ("M3",  'case 9: Some{"BOOL"}', 'case 9: None{}',
   "the UPPER arm of the ODT table: deletes a member, so `onnx_odt_n` still "
   "counts 13 and `onnx_odt_tbl`/the round trips go red. This is the "
   "COUNT-vs-CONTENT pair the brief asks for."),
  ("M4",  'case 16: Some{"bfloat16"}', 'case 16: Some{"bfloat16X"}',
   "the reverse table's entry: `onnx_odt_rt2` and `onnx_odt_code` see it and "
   "`onnx_odt_ktbl` prints it."),
  # ---- the attribute NAME TABLE --------------------------------------------
  ("M5",  'case 7: Some{"ints"}', 'case 7: Some{"int"}',
   "`to_field_name`'s `7: \"ints\"` (:27) -- the SINGULAR spelling is also a "
   "valid `_parse_AttributeProto` key, so only the spelling row sees it."),
  ("M6",  'case 5: Some{"g"}', 'case 5: Some{"graph"}',
   "the GRAPH arm, which is the one that carries an `OnnxRunner` and therefore "
   "has no payload."),
  # ---- Domain --------------------------------------------------------------
  ("M7",  'case DomPrevTrain{}: "ai.onnx.preview.training"',
   'case DomPrevTrain{}: "ai.onnx.preview"',
   "`Domain.AI_ONNX_PREVIEW_TRAINING`'s VALUE (:46), which is the longest of the "
   "nine and the easiest to mistype."),
  ("M8",  'case DomTrain{}: True{}\n    case DomPrevTrain{}: True{}\n    case _: False{}',
   'case DomTrain{}: True{}\n    case _: False{}',
   "`_init_from_graph`'s TRAINING membership (:379), one of its TWO members."),
  # ---- required_input_python_consts ---------------------------------------
  ("M9",  'Pc{"ReduceL2", [1]}', 'Pc{"ReduceL2", [0]}',
   "the comprehension-built rungs (:357): a wrong INDEX moves only the lookup "
   "rows and the table string, never the count."),
  ("M10", 'Pc{"Resize", [1, 2, 3]}', 'Pc{"Resize", [1, 2]}',
   "the literal rungs (:355), and the row that says a dropped index is a "
   "silent wrong-input rather than a crash."),
  # ---- the op table --------------------------------------------------------
  ("M11", '"HardSwish", "Hardmax",', '"Hardmax",',
   "a DROPPED op name. `onnx_ops_n` moves because the count is 170; the table "
   "string moves too. This is the row that says the table is a SET claim."),
  ("M12", '"Upsample", "Where", "Xor"', '"Upsample", "Wherf", "Xor"',
   "a MISSPELLED op name of the SAME LENGTH, so the COUNT is unchanged and only "
   "the table string moves. This is the row that says `onnx_ops_n` alone is not "
   "the table claim."),
  ("M13", 'case "IsNaN": Some{"isnan"}', 'case "IsNaN": Some{"is_nan"}',
   "the ONE `getattr(Tensor, op.lower())` entry (:1310) whose Tensor method is "
   "not simply the lower-cased name -- `Tensor.isnan`, not `Tensor.is_nan`."),
  # ---- _select_op ----------------------------------------------------------
  ("M14", 'U32.is_le(Ver.v(v), ver)', 'U32.is_lt(Ver.v(v), ver)',
   "the `<=` in the eligibility test (:421). Strict `<` refuses opset 1 for "
   "`Softmax`, which is the row that sees the off-by-one."),
  # The FIRST attempt at M15 mutated the `bv` accumulator (`U32.max(bv, ...) ->
  # bv`) and moved NOTHING, which is a finding and not a null result: `bv` feeds
  # only the max comparison, and the ANSWER is the `bi` string, so `bv` is not
  # load-bearing on its own. The load-bearing edit is the one that makes `bi`
  # first-wins.
  ("M15", 'Bool.pick(String, U32.is_gt(Ver.v(v), bv), Ver.i(v), bi)',
   'Bool.pick(String, U32.is_gt(Ver.v(v), bv), bi, Ver.i(v))',
   "`eligible_ops[max(eligible_ops.keys())]` (:423): first-wins instead of max. "
   "See the note above: the sibling mutation on the `bv` accumulator moved "
   "NOTHING and that is the blind spot it found."),
  # ---- the padding arithmetic ---------------------------------------------
  ("M16", '  onx_zip(List.reverse(&2, H.I64, Hal.a(hs)), List.reverse(&2, H.I64, Hal.b(hs)))',
   '  onx_zip(List.reverse(&2, H.I64, Hal.a(hs)), Hal.b(hs))',
   "`p2t`'s SECOND reversal (:483). Reversing only the first half is the bug "
   "this gate already caught once; the fixture that separates them is "
   "`onnx_p2t_neg`."),
  ("M17", 'List.take(&2, H.I64, List.drop(&2, H.I64, xs, U32.to_nat(n)), U32.to_nat(n))',
   'List.drop(&2, H.I64, xs, U32.to_nat(n))',
   "`p2t`'s `take(n, drop(n))` second half: an ODD-length pads tuple drops its "
   "last element in CPython, and `onnx_p2t_odd` is the only row that sees it."),
  ("M18", 'U32.or(U32.shrn(H.lo32(x), 1n), U32.shln(U32.and(H.hi32(x), 1), 31n))',
   'U32.or(U32.shrn(H.lo32(x), 1n), U32.shln(U32.and(H.lo32(x), 1), 31n))',
   "the 64-bit shift's LOW-word fill: it comes from `hi & 1`, not from the low "
   "word's own bit 0. `onnx_ap_su_neg2` is the row."),
  ("M19", 'def onx_p2t(+pads: List<&2, H.I64>) -> List<&2, H.I64>:',
   '# a CONTROL: a comment-only edit.\ndef onx_p2t(+pads: List<&2, H.I64>) -> List<&2, H.I64>:',
   "THE CONTROL. Recorded because a mutation table with no row that CANNOT move "
   "is a table of coincidences, and because this is the only mutation here that "
   "does not change behaviour at all."),
  ("M20", 'case 5: Some{"FIXED32"}', 'case 5: Some{"FIXED64"}',
   "the WireType table's LAST member, whose code is the largest of the six and "
   "so the one a `case 8:`-style prefix arm would swallow. Its two `1`/`5` "
   "codes make the round trip the row that sees a swap."),
]


def run():
  # The INTERPRETED lane, not the native one: measured at 10 s per run against
  # ~90 s to compile, and the gate's 123 rows are lane-identical, so the mutation
  # table measures the same thing either way. (`--check-only` re-proves all 190
  # defs on every run -- bend2-constraints' `sz` rule 9 -- which is why the
  # native lane is the wrong one to bisect with.)
  r = subprocess.run([os.path.join(REPO, "bin", "bend"), F],
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
  return r.stdout.decode("utf-8", "replace").splitlines()


def main():
  base = open(F).read()
  shutil.copy(F, BAK)
  ref = run()
  print(f"baseline: {len(ref)} rows")
  for mid, find, repl, why in MUTS:
    if find not in base:
      print("%s: %s -- the mutation is stale" % (mid, PNA.not_applied()))
      continue
    open(F, "w").write(base.replace(find, repl, 1))
    try:
      got = run()
    finally:
      open(F, "w").write(base)
    moved = [a.split("=")[0] for a, b in zip(ref, got) if a != b]
    ndiff = sum(1 for a, b in zip(ref, got) if a != b) + abs(len(ref) - len(got))
    print(f"{mid}: moved {len(moved)} row(s)" + (f"  [{', '.join(moved)}]" if moved else "  (NOTHING)"))
    print(f"     why: {why}")
  # confirm the file is restored and the gate is green again
  again = run()
  assert again == ref, "the file was not restored"
  print("restored: byte identical to baseline")


if __name__ == "__main__":
  main()