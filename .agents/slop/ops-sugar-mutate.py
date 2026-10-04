#!/usr/bin/env python3
"""Mutation table for the sugar constructors of `tinybendygrad/uop/ops.bend`.

    .venv/bin/python .agents/slop/ops-sugar-mutate.py

Each mutation is a ONE-STRING edit to the port that should be a no-op if the gate is
measuring the def it claims to measure, and a ROW MOVER if the def is load-bearing. A
mutation that moves no row is a hole: either the def is not what the row reads, or
the row is not sensitive to the thing it names.

THE CLAIMS BEING TESTED, one per def, and each is a GUARD claim rather than an
arithmetic one -- these are constructors, so what can be wrong is which arm runs,
not what an arm computes:

  body                 the op test, and the `case _` arm
  is_inline_call       each of its four conjuncts, separately
  has_unbound_outputs  the `src[1:]` slice, the ALLOC test, `bind_on_realize`, the
                       `unsharded_base` peel and the op test
  index                the STACK/CONST guard, its answer (`self.src[val]`), the
                       three list shapes, and SELF-FIRST
  store                the optional gate, and SELF-FIRST
  ins                  the `self.src` and `self.tag` defaults
  wmma                 the arg's four fields, and the src order
  reduce               the `(rop, 0)` normalisation
  cconst               the CAST, its dtype, and the ARENA it is interned into
  invalid/is_invalid   the `CInvalid` payload
  ufix                 the `CU` arm minting nothing

Read fresh, write a single targeted `str.replace`, and never rewrite the file from a
stale read -- ops.bend is SHARED with another agent working on a different line
range, and a whole-file rewrite silently drops their concurrent edits.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
EXPECTED_ROWS = 41

# (label, the exact string to replace, its replacement, the rows that MUST move)
MUTATIONS = [
  # --- `body`: the op test and the catch-all.
  ("body_drops_call",
   """  match op:
    case OpsCALL{}: Some{src0}
    case _: None{}""",
   """  match op:
    case OpsADD{}: Some{src0}
    case _: None{}""", ["sg_body_call", "sg_body_add"]),
  ("body_always_some",
   "UOp.body.of(Arena.op(ar, self), Arena.src0(ar, self))",
   "UOp.body.of(OpsCALL{}, Arena.src0(ar, self))", ["sg_body_add"]),
  # --- `is_inline_call`: FOUR conjuncts, four mutations, four rows.
  ("inline_drops_op",
   "    Bool.and(eq_op(Arena.op(ar, self), OpsCALL{}), eq_op(Arena.op(ar, b), OpsSINK{})),",
   "    eq_op(Arena.op(ar, b), OpsSINK{}),", ["sg_inline_aft"]),
  ("inline_drops_sink",
   "    Bool.and(eq_op(Arena.op(ar, self), OpsCALL{}), eq_op(Arena.op(ar, b), OpsSINK{})),",
   "    eq_op(Arena.op(ar, self), OpsCALL{}),", ["sg_inline_body"]),
  ("inline_drops_anon",
   """  match barg:
    case ANone{}: UOp.is_inline_call.pre(arg)
    case _: Some{False{}}""",
   """  match barg:
    case _: UOp.is_inline_call.pre(arg)""", ["sg_inline_kernel"]),
  ("inline_drops_pre",
   "    case ACall{ci}: Some{Bool.not(CallInfo.precompile(ci))}",
   "    case ACall{ci}: Some{True{}}", ["sg_inline_pre"]),
  ("inline_cfun_is_false",
   "    case ACall{ci}: Some{Bool.not(CallInfo.precompile(ci))}\n    case _: None{}",
   "    case ACall{ci}: Some{Bool.not(CallInfo.precompile(ci))}\n    case _: Some{False{}}",
   ["sg_inline_cfun"]),
  # --- `has_unbound_outputs`: FIVE facts, and the slice is the one that is easy.
  ("huo_drops_slice",
   "UOp.has_unbound_outputs.of(Arena.op(ar, self), fuel, ar, Arena.src_from(ar, self, 1))",
   "UOp.has_unbound_outputs.of(Arena.op(ar, self), fuel, ar, Arena.srcs(ar, self))",
   ["sg_huo_src0"]),
  ("huo_drops_op",
   """  match op:
    case OpsCALL{}: UOp.huo.go(fuel, ar, xs, False{})
    case _: False{}""",
   """  match op:
    case _: UOp.huo.go(fuel, ar, xs, False{})""", ["sg_huo_noncall"]),
  ("huo_drops_alloc",
   "  Bool.and(eq_op(Arena.op(ar, b), OpsALLOC{}), UOp.huo.bor(Arena.arg(ar, b)))",
   "  UOp.huo.bor(Arena.arg(ar, b))", ["sg_huo_buffer"]),
  ("huo_drops_bind",
   "    case AParam{pa}: Bool.not(ParamArg.bind_on_realize(pa))",
   "    case AParam{pa}: True{}", ["sg_huo_bind"]),
  ("huo_drops_peel",
   "  +b = UOp.unsharded_base(fuel, ar, x)",
   "  +b = x", ["sg_huo_unshard"]),
  # --- `index`: the guard, its answer, and the three list shapes.
  ("index_drops_stack",
   "  Bool.and(eq_op(Arena.op(ar, self), OpsSTACK{}), UOp.index.isconst(ar, k))",
   "  UOp.index.isconst(ar, k)", ["sg_index_one"]),
  ("index_drops_isconst",
   "  Bool.and(eq_op(Arena.op(ar, self), OpsSTACK{}), UOp.index.isconst(ar, k))",
   "  eq_op(Arena.op(ar, self), OpsSTACK{})", ["sg_index_nc"]),
  ("index_wrong_slot",
   "    case APy{CInt{i}}: H.lo32(i)\n    case _: 0",
   "    case APy{CInt{i}}: 0\n    case _: 0", ["sg_index_hit1"]),
  ("index_drops_src0",
   """  match srcs:
    case Nil{}: UOp.new(ar, OpsINDEX{}, [self], ANone{}, TNone{})
    case h <> t: UOp.index.rest(ar, self, h, t)""",
   """  match srcs:
    case Nil{}: UOp.new(ar, OpsINDEX{}, Nil{}, ANone{}, TNone{})
    case h <> t: UOp.index.rest(ar, self, h, t)""", ["sg_index_plain"]),
  # `self.src[new_srcs[0].val]` is `Arena.src(ar, self, val)` -- the SELF is the
  # node being indexed, so putting the other operand first answers the CONST's own
  # src list, which is empty, and the answer becomes the bottom.
  # The fast path must MINT NOTHING and hand back the CALLER's arena. Making it mint
  # is the whole of the mint-on-the-fast-path bug, and `hit0`/`hit1` are the only two
  # rows that can see it because they are index EQUALITY.
  #
  # NOT MUTATION-TESTED, and named rather than faked: the OTHER half of
  # `UOp.index.slot` -- that the answer is `self.src[val]` and not `k.src[val]` --
  # needs `k` read twice, so expressing it would add a `+` to a `U32` the def does
  # not otherwise need. A `+` bought for a mutation is a reference count leaked for
  # a test, and `index_wrong_slot` already covers the slot's other half (the value,
  # not the node).
  ("index_fast_path_mints",
   "    case True{}: Found{ar, UOp.index.slot(ar, self, k)}",
   "    case True{}: UOp.new(ar, OpsINDEX{}, [self, k], ANone{}, TNone{})",
   ["sg_index_hit1", "sg_index_hit0"]),
  # --- `store`: the gate, and the order.
  ("store_drops_gate",
   """  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val]""",
   """  match gate:
    case _: [self, val]""", ["sg_store_gate"]),
  ("store_always_gate",
   """  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val]""",
   """  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val, self]""", ["sg_store_nogate"]),
  ("store_swaps_self",
   """  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val]""",
   """  match gate:
    case Some{g}: [val, self, g]
    case None{}: [val, self]""", ["sg_store_nogate", "sg_store_gate"]),
  # --- `ins`: the two arena-read defaults. `self.src` first, because SELF-FIRST is
  # the bug class this file has already paid for twice.
  ("ins_drops_tag",
   "UOp.new(ar, OpsINS{}, Arena.srcs(ar, self), AInk{nm, dt}, Arena.tag(ar, self))",
   "UOp.new(ar, OpsINS{}, Arena.srcs(ar, self), AInk{nm, dt}, TNone{})", ["sg_ins_tag"]),
  ("ins_drops_srcs",
   "UOp.new(ar, OpsINS{}, Arena.srcs(ar, self), AInk{nm, dt}, Arena.tag(ar, self))",
   "UOp.new(ar, OpsINS{}, Nil{}, AInk{nm, dt}, Arena.tag(ar, self))",
   ["sg_ins_tag", "sg_ins_none"]),
  # --- `wmma`: the arg's fields, and the src order.
  ("wmma_drops_threads",
   "  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, threads, tc}, TNone{})",
   "  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, 0, tc}, TNone{})", ["sg_wmma"]),
  ("wmma_drops_dt",
   "  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, threads, tc}, TNone{})",
   "  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, S.void(), threads, tc}, TNone{})",
   ["sg_wmma"]),
  ("wmma_swaps_acc",
   "  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, threads, tc}, TNone{})",
   "  UOp.new(ar, OpsWMMA{}, [acc, b, a], AWmma{dims, dt, threads, tc}, TNone{})", ["sg_wmma"]),
  # --- `reduce`: the `(rop, 0)` NORMALISATION. A def that always built `AReduce`
  # answers the `None` row with a reduce arg, which is the row that exists for it.
  ("reduce_always_arg",
   """  match rop:
    case Some{r}: AReduce{r, 0}
    case None{}: ANone{}""",
   """  match rop:
    case Some{r}: AReduce{r, 0}
    case None{}: AReduce{OpsNOOP{}, 0}""", ["sg_reduce_none"]),
  ("reduce_drops_axes",
   "    case Some{r}: AReduce{r, 0}", "    case Some{r}: AReduce{r, 1}", ["sg_reduce_some"]),
  ("reduce_drops_self",
   "  UOp.new(ar, OpsREDUCE{}, List.append(&2, U32, [self], srcs), UOp.reduce.arg(rop), TNone{})",
   "  UOp.new(ar, OpsREDUCE{}, srcs, UOp.reduce.arg(rop), TNone{})", ["sg_reduce_some", "sg_reduce_none"]),
  # --- `cconst`: the CAST, its dtype, and the ARENA it is interned into.
  # The last of the three is the "constructor that mints into an arena the caller
  # then discards" trap: interning the CAST into `ar` instead of `Found.ar(c)`
  # leaves it out of the arena `sg.minted` reads, and the bottom is a NOOP, so the
  # row prints `Ops.NOOP` rather than nothing.
  ("cconst_drops_dtype",
   "  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})",
   "  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{S.void()}, TNone{})",
   ["sg_cconst_i32", "sg_cconst_f32"]),
  ("cconst_stale_arena",
   "  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})",
   "  UOp.new(ar, OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})",
   ["sg_cconst_i32", "sg_cconst_f32"]),
  ("cconst_drops_const",
   "  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})",
   "  UOp.new(Found.ar(c), OpsCAST{}, Nil{}, ADt{dt}, TNone{})", ["sg_cconst_i32", "sg_cconst_f32"]),
  # --- `invalid` / `is_invalid`: the `CInvalid` PAYLOAD. Replacing it with a
  # `CInt` moves `sg_invalid` and `sg_isinv_ci` together, which is the pair.
  ("invalid_is_cint",
   "  UOp.const(ar, CInvalid{})", "  UOp.const(ar, CInt{H.i64_of_i32(0)})", ["sg_invalid", "sg_isinv_ci"]),
  ("is_invalid_drops_cinvalid",
   "    case OpsCONST{} APy{CInvalid{}}: True{}",
   "    case OpsCONST{} APy{CInvalid{}}: False{}", ["sg_isinv_ci"]),
  # --- `ufix`: the `CU` arm must MINT NOTHING. A def that rebuilt the node would
  # answer `sg_ufix_miss` with a fresh index, which is the row that exists for it.
  # A rebuilt CONST has the same OP NAME as the original, so `sg_ufix_uop` CANNOT
  # move and `sg_ufix_miss` must: that row is index equality, and a def that minted on
  # the `CU` arm answers a fresh index. The two rows measure different things and one
  # of them is blind to this mutation, which is the honest shape of the pair.
  ("ufix_mints_on_cu",
   """  match hit:
    case Some{u}: Found{ar, u}
    case None{}: UOp.const(ar, v)""",
   """  match hit:
    case Some{u}: UOp.const(ar, clike.val(CU{u}))
    case None{}: UOp.const(ar, v)""", ["sg_ufix_miss"]),
  ("ufix_drops_cv",
   "    case CU{u}: Some{u}\n    case CV{v}: None{}",
   "    case CU{u}: Some{u}\n    case CV{v}: Some{0}", ["sg_ufix_lit"]),
]


def rows_moved(before: dict, after: dict) -> list:
  return sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))


def read_rows() -> dict:
  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)], capture_output=True, text=True, cwd=REPO)
  rows = {}
  for line in out.stdout.split("\n"):
    if line.startswith("sg_") and "=" in line:
      k, v = line.split("=", 1)
      rows[k] = v
  return rows


def main() -> int:
  if not OPS.exists():
    print("ops.bend is gone", file=sys.stderr)
    return 1
  base = read_rows()
  if len(base) != EXPECTED_ROWS:
    print(f"ops-sugar-mutate: the unmutated file answers {len(base)} rows, not {EXPECTED_ROWS} -- "
          f"run ops-sugar-gate.sh first and fix that before measuring anything", file=sys.stderr)
    return 1
  print(f"{'mutation':28} {'rows that moved':52} verdict")
  bad = 0
  for label, old, new, must in MUTATIONS:
    text = OPS.read_text()
    if text.count(old) != 1:
      print(f"{label:28} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':52} NOT MEASURED")
      bad += 1
      continue
    OPS.write_text(text.replace(old, new, 1))
    try:
      got = read_rows()
      moved = rows_moved(base, got)
    finally:
      OPS.write_text(text)
    if len(got) != len(base):
      print(f"{label:28} {'RUN BROKE (' + str(len(got)) + ' of ' + str(len(base)) + ' rows)':52} NOT A ROW MOVE")
      bad += 1
      continue
    ok = all(m in moved for m in must)
    if not ok:
      bad += 1
    print(f"{label:28} {','.join(moved) or '-':52} {'ok' if ok else 'MISSING ' + ','.join(must)}")
  print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations moved the rows they name")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
