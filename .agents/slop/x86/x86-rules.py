#!/usr/bin/env python3
"""x86-rules.py -- THE MUTATION TABLE for `tinybendygrad/renderer/isa/x86.bend`, one
entry per PORTED RULE.

`x86-sweep.py consts` moves DATA (a table entry, a literal in a `match` arm).
This moves LOGIC -- an inverted predicate, a dropped clause, a `<` for `<=`, a `min` for a
`sub` -- because every one of the six `Enc.emit` defects this unit found was a LOGIC bug
and not a wrong constant, so a constants-only sweep would have found NONE of them and the
absence of blind constants would have read as coverage.

Each entry is `(id, find, replace)` and `find` must occur EXACTLY ONCE: a mutation applied
to the wrong site is a mutation of something else, and a table that lies about which row
it moved is worse than no table. A site that does not occur once is reported as SKIPPED
with its count, not guessed at.

    .venv/bin/python .agents/slop/x86/x86-rules.py
    .venv/bin/python .agents/slop/x86/x86-rules.py --file <scratch copy>
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import x86_sweep as S  # noqa: E402  -- the harness: run_bend, rows_moved, reference

RULES = [
  # --- STAGE 1, the register table -----------------------------------------
  ("R01 Reg.gpr size 8 -> 4",
   'Reg.of(Reg.rname(i), i, 8, Reg.s4n(i), Reg.s2n(i), Reg.s1n(i))',
   'Reg.of(Reg.rname(i), i, 4, Reg.s4n(i), Reg.s2n(i), Reg.s1n(i))'),
  ("R02 Reg.wgpr_drop drops the WRONG register (4 -> 3)",
   'def Reg.wgpr_drop(idx: U32) -> U32: Bool.pick(U32, U32.is_eq(idx, 4), 1, 0)',
   'def Reg.wgpr_drop(idx: U32) -> U32: Bool.pick(U32, U32.is_eq(idx, 3), 1, 0)'),
  ("R03 Reg.is_callee forgets r12",
   'Bool.or(U32.is_eq(ix, 12), U32.is_eq(ix, 13)),',
   'Bool.or(U32.is_eq(ix, 11), U32.is_eq(ix, 13)),'),
  ("R04 Reg.strs_lookup never finds the sub-register",
   'Reg.strs_lookup.of(Reg.gpr_find_by_name(nm), nm, sz)',
   'Reg.strs_lookup.of(None, nm, sz)'),
  ("R05 Op.base off by one (78 -> 79)",
   'def Op.base() -> U32: 78', 'def Op.base() -> U32: 79'),
  # --- STAGE 2, the op enum and the operand classes ------------------------
  ("R06 Op.rm1st_lit is always False",
   'Op.has(nm, ["MOV", "VMOVSS", "VMOVSD", "VMOVUPS", "MOVZX", "MOVSX", "MOVSXD", "VMOVD", "VMOVQ",',
   'Op.has(nm, ["MOVXX", "VMOVSS", "VMOVSD", "VMOVUPS", "MOVZX", "MOVSX", "MOVSXD", "VMOVD", "VMOVQ",'),
  ("R07 Op.xmm_ops (GPR_DEST_OPS) inverted",
   'Bool.and(Op.is_x(nm), Bool.not(Op.in_(nm, 6)))',
   'Bool.or(Op.is_x(nm), Bool.not(Op.in_(nm, 6)))'),
  # --- STAGE 3, the operand rules ------------------------------------------
  ("R08 Op.sz_arm threshold 16 -> 8",
   'Bool.pick(U32, U32.is_ge(bits, 16), 2, Bool.pick(U32, U32.is_ge(bits, 8), 1, 0))',
   'Bool.pick(U32, U32.is_ge(bits, 8), 2, Bool.pick(U32, U32.is_ge(bits, 8), 1, 0))'),
  ("R09 Op.to_int float16 -> i32",
   '    case "float16": "i16"', '    case "float16": "i32"'),
  ("R10 Op.to_int answers for a missing dtype",
   '    case _: "KeyError"', '    case _: "i32"'),
  # --- STAGE 4, the encoding table ------------------------------------------
  ("R11 Enc.demoted_opc never demotes",
   'Bool.pick(U32, Enc.demote_of(rm_sz, reg_sz, no_demote), 1, 0)',
   'Bool.pick(U32, False{}, 1, 0)'),
  ("R12 Enc.opc_arm 255 -> 254",
   'def Enc.opc_arm(+opc: U32) -> U32: Bool.pick(U32, U32.is_gt(opc, 255), 1, 0)',
   'def Enc.opc_arm(+opc: U32) -> U32: Bool.pick(U32, U32.is_gt(opc, 254), 1, 0)'),
  ("R13 Enc.disp_arm 1 -> 2",
   'def Enc.disp_arm(+disp_sz: U32) -> U32: Bool.pick(U32, U32.is_eq(disp_sz, 1), 1, 0)',
   'def Enc.disp_arm(+disp_sz: U32) -> U32: Bool.pick(U32, U32.is_eq(disp_sz, 2), 1, 0)'),
  # --- STAGE 5, the encoder -------------------------------------------------
  ("R14 Enc.rex_bit2 back to `== 1 and >= 4`",
   'U32.is_eq(sz, U32.and(U32.shrn(r, 2n), 1))',
   'Bool.and(U32.is_eq(sz, 1), Enc.ge4(r))'),
  ("R15 Enc.needs_rex drops the demote clause",
   'Bool.and(Bool.and(demote, Bool.not(has_disp)), Enc.ge4(rm))', 'False{}'),
  ("R16 Enc.needs_rex drops the W clause",
   'Bool.or(Bool.or(w, Enc.gt0(r)), Bool.or(Enc.gt0(x), Enc.gt0(b)))',
   'Bool.or(Enc.gt0(r), Bool.or(Enc.gt0(x), Enc.gt0(b)))'),
  ("R17 Enc.demote_of loses the ReadFlags exclusion",
   'Bool.and(Bool.or(U32.is_eq(rm_sz, 1), U32.is_eq(reg_sz, 1)), Bool.not(no_demote))',
   'Bool.or(U32.is_eq(rm_sz, 1), U32.is_eq(reg_sz, 1))'),
  ("R18 Enc.b1 `~r & 1` becomes `r & 1`",
   'def Enc.b1(+v: U32) -> U32: Bool.pick(U32, U32.is_lt(v, 1), 1, 0)',
   'def Enc.b1(+v: U32) -> U32: Bool.pick(U32, U32.is_gt(v, 0), 1, 0)'),
  ("R19 Enc.modrm_byte reg field masked to THREE bits",
   'Enc.modrm_byte(mod, U32.and(reg, 7)', 'Enc.modrm_byte(mod, U32.and(reg, 3)'),
  ("R20 Enc.log2b 8 -> 2 (the SIB scale)",
   '    case 8: 3', '    case 8: 1'),
  ("R21 Enc.no_index ignores the X extension bit",
   'Bool.and(U32.is_eq(idx3, 4), U32.is_zero(x))', 'U32.is_eq(idx3, 4)'),
  ("R22 Enc.want_sib allows mod == 3 (a register operand)",
   'Bool.and(Bool.not(noidx), Bool.not(U32.is_eq(mod, 3)))', 'Bool.not(noidx)'),
  ("R23 Enc.modrm_of loses the rbp/r13 clause",
   'Bool.pick(U32, Bool.or(U32.is_ne(disp_val, 0), U32.is_eq(rm, 5)),',
   'Bool.pick(U32, U32.is_ne(disp_val, 0),'),
  ("R24 Enc.tail_bytes `mod == 0` AGAIN (the inverted flag)",
   'Enc.tail_bytes.of(U32.is_lt(mod, 3), Enc.disp_bytes(disp_val, disp_sz))',
   'Enc.tail_bytes.of(U32.is_eq(mod, 0), Enc.disp_bytes(disp_val, disp_sz))'),
  ("R25 Enc.imm_int BIG endian AGAIN",
   'case 1n+p: List.append(&2, U32, [Enc.imm_byte(imm, Nat.sub(n, k))], Enc.imm_int(p, n, imm))',
   'case 1n+p: List.append(&2, U32, Enc.imm_int(p, n, imm), [Enc.imm_byte(imm, Nat.sub(n, k))])'),
  ("R26 Enc.imm_bytes kind 2 loses the nibble shift",
   'case 2: [Enc.shl(U32.and(imm, 15), 4n)]', 'case 2: [U32.and(imm, 15)]'),
  ("R27 Enc.we_of selector 2 reads xsz instead of src1sz",
   'case 2: Bool.pick(U32, U32.is_eq(src1sz, 8), 1, 0)',
   'case 2: Bool.pick(U32, U32.is_eq(xsz, 8), 1, 0)'),
  ("R28 Enc.we_of selector 1 (`we=1`) becomes a size test",
   'case 1: 1', 'case 1: Bool.pick(U32, U32.is_eq(src1sz, 8), 1, 0)'),
  ("R29 Enc.legacy_head emits the opcode AGAIN",
   'case True{}: Enc.cat(pfx, [rex])', 'case True{}: Enc.cat(pfx, [rex, Enc.opc(enc_find(nm))])'),
  ("R30 Enc.emit.tail drops the immediate bytes",
   'Enc.cat(Enc.tail_bytes(mod, has_disp, disp_val, disp_sz), Enc.imm_bytes(imm_kind, imm_n, imm))',
   'Enc.tail_bytes(mod, has_disp, disp_val, disp_sz)'),
  ("R31 Enc.emit.tail ALWAYS emits a SIB byte",
   'Enc.sib_field.of(noidx, idx3, rm3, rm_sz, Enc.want_sib(noidx, mod))',
   'Enc.sib_field.of(noidx, idx3, rm3, rm_sz, True{})'),
  ("R32 Enc.direct gives JMP a second opcode",
   '    case "JMP": [Enc.direct_op1(nm), 0, 0, 0, 0]',
   '    case "JMP": [Enc.direct_op1(nm), Enc.direct_op2(nm), 0, 0, 0, 0]'),
  ("R33 Enc.movabs REX loses the W bit",
   'Enc.cat([U32.or(72, U32.shrn(reg, 3n)), U32.add(184, U32.and(reg, 7))]',
   'Enc.cat([U32.or(64, U32.shrn(reg, 3n)), U32.add(184, U32.and(reg, 7))]'),
  # --- STAGE 7, the assembly text -------------------------------------------
  ("R34 Asm.droplast drops the FRONT instead of the back",
   'String.reverse(String.drop(String.reverse(s), 1n))', 'String.drop(s, 1n)'),
  ("R35 Asm.mnem.of drops SEVEN AND ONE (the old `drop(n, 8)`)",
   'Asm.droplast(String.drop(n, 7n)), String.drop(n, 7n))',
   'String.drop(n, 8n)), String.drop(n, 7n))'),
  ("R36 Asm.pad pads to min(7, len) AGAIN",
   'String.repeat(" ", U32.to_nat(Bool.pick(U32, U32.is_ge(w, 7), 0, U32.sub(7, w))))',
   'String.repeat(" ", U32.to_nat(Bool.pick(U32, U32.is_ge(w, 7), 0, U32.min(7, w))))'),
  ("R37 Asm.mnem forgets the lowercasing",
   'String.to_lower(Bool.pick(String, trim,', 'Bool.pick(String, trim,'),
  ("R38 AsmMem.idx_part drops the scale",
   'String.concat([" + ", AsmMem.idx(m), "*", U32.show(AsmMem.scale(m))]))',
   'String.concat([" + ", AsmMem.idx(m)]))'),
  ("R39 AsmMem.disp_part prints a zero displacement",
   'Bool.pick(String, U32.is_zero(AsmMem.disp(m)), "",', 'Bool.pick(String, False{}, "",'),
  ("R40 AsmArgs_text reverses the operands AGAIN",
   'case h <> t: List.append(&2, String, [AsmArg.text(h)], AsmArgs_text(t))',
   'case h <> t: List.append(&2, String, AsmArgs_text(t), [AsmArg.text(h)])'),
  ("R41 AsmOp.mid puts the memory BEFORE the destinations",
   'Bool.pick(List<&2, List<&2, String>>, AsmOp.has_mem(o),',
   'Bool.pick(List<&2, List<&2, String>>, Bool.not(AsmOp.has_mem(o)),'),
  ("R42 Asm.go stops skipping",
   'Bool.pick(List<&2, String>, U32.is_eq(AsmOp.kind(h), 3), acc,',
   'Bool.pick(List<&2, String>, False{}, acc,'),
  ("R43 AsmOp.line gives RET an operand column",
   '    case 1: AsmOp.head(o)', '    case 1: String.concat([AsmOp.head(o), " "])'),
  ("R44 asm_str drops the `.name:` header",
   'List.append(&2, String, [String.concat([".", fn, ":"])], AsmLines(os))', 'AsmLines(os)'),
  # --- STAGE 6, the renderer constants --------------------------------------
  ("R45 Cls.dropped forgets bf16",
   '["bf16", "fp8e4m3", "fp8e4m3fnuz", "fp8e5m2", "fp8e5m2fnuz"]',
   '["bf16X", "fp8e4m3", "fp8e4m3fnuz", "fp8e5m2", "fp8e5m2fnuz"]'),
  ("R46 Cls.keep.go keeps everything",
   'Bool.pick(List<&2, String>, Cls.dropped(h), acc, List.append(&2, String, acc, [h]))',
   'List.append(&2, String, acc, [h])'),
  ("R47 Enc.has_reg_s prints the reg when none was passed",
   '    case False{}: "-"', '    case False{}: U32.show(r)'),
  ("R48 Enc.missing counts the DIRECT entries too",
   'Bool.not(Enc.is_direct(h)))',
   'True{})'),
]


def main():
  if "--file" in sys.argv:
    S.TARGET = Path(sys.argv[sys.argv.index("--file") + 1])
  ref = S.reference()
  base = S.run_bend()
  assert base is not None, "baseline does not compile"
  assert base == ref, f"baseline differs from CPython on {len(S.rows_moved(base, ref))} rows"
  assert S.settled(base), "the substrate is moving; refusing to mutate"
  text = S.TARGET.read_text()
  results = []
  for rid, find, repl in RULES:
    n = text.count(find)
    if n != 1:
      results.append((rid, f"SKIPPED, the site occurs {n}x: {find[:60]}", [], False))
      continue
    S.TARGET.write_text(text.replace(find, repl))
    mv = S.rows_moved(base, S.run_bend())
    S.TARGET.write_text(text)
    results.append((rid, f"{find[:58]}  ->  {repl[:38]}", mv, True))
  blind = [r for r in results if not r[2]]
  print(f"=== RULES: {len(results)} mutations over {len(base)} rows; "
        f"{len(results) - len(blind)} moved rows; {len(blind)} BLIND")
  for rid, what, mv, ran in results:
    if not ran:
      print(f"  {rid}: {len(mv):4d} rows  {what}")
      continue
    fams = sorted({m.split(" ")[0].split(".")[0] for m in mv})
    print(f"  {rid}: {len(mv):4d} rows  {', '.join(fams)[:70]}")
    print(f"        {what}")
  assert not S.rows_moved(base, S.run_bend()), "a mutation leaked into the file"


if __name__ == "__main__":
  main()
