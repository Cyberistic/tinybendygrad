#!/usr/bin/env python3
"""Mutate generate.bend one rule at a time and record WHICH gate rows move.

HARNESS RULES, all three learned the hard way in this repo:
  * diff whole `name=[value]` ROWS, never row NAMES.  A name-comparing harness
    reported 0 for all 30 mutations in the autogen unit and all 68 in the ops_rdma
    one: a mutation that changes a VALUE leaves the NAME identical, so a name
    comparison reports nothing happened.  `ga_gate.parse` is reused here because
    the six emitter rows carry a WHOLE FILE in one value, spanning lines, so a
    line-oriented regex finds nothing and needs DOTALL + lazy.
  * run the mutant IN THE ORIGINAL'S DIRECTORY.  A $TMPDIR copy cannot resolve
    `import Base`.
  * a mutant that fails to compile is a result, not a crash: the table records it
    rather than aborting, because "this rule is load-bearing for the type system"
    is itself the answer for some of them.
"""
import os
import patch_not_apply as PNA
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
F = ROOT / "tinybendygrad/renderer/amd/generate.bend"
BEND = ROOT / "bin/bend"
BASE_TXT = ROOT / ".agents/slop/ga-run.txt"


def parse(text):
    rows = {}
    for m in re.finditer(r"^(.*?) = \[(.*?)\]   py=\[(.*?)\]$", text, re.M | re.S):
        rows[m.group(1).strip()] = (m.group(2), m.group(3))
    return rows


def run(text):
    """Run a mutant.  Bend 2.0.34's machine stack is NOT deterministic here: the
    PRISTINE, gate-green file died with `the machine stack overflowed` on 2 of 12
    back-to-back runs and on 0 of 8 when the machine was idle, so an overflow is
    an environment artefact and never a verdict on the mutation.  RETRY it."""
    orig = F.read_text()
    try:
        F.write_text(text)
        for _ in range(8):
            r = subprocess.run([str(BEND), str(F)], capture_output=True, text=True, timeout=900)
            if "machine stack overflowed" in r.stderr:
                continue
            if r.returncode != 0 or "SOME PROOFS FAIL" in r.stdout + r.stderr:
                return None
            return parse(r.stdout)
        return "STACK"
    except subprocess.TimeoutExpired:
        return None
    finally:
        F.write_text(orig)


def moved(a, b):
    if a is None or b is None:
        return None
    return [k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]


MUTS = [
    # ---- `strip_enc`, `_norm_field`, `_map_flat` (the scalar gate rows) ----
    ("M1", "strip_enc: the ENC_ prefix is not removed",
     'strip_enc(name: String) -> String: strip_enc.sfx(enc_suffixes(), strip_prefix(name, "ENC_"))',
     'strip_enc(name: String) -> String: strip_enc.sfx(enc_suffixes(), name)',
     "the first of the two rewrites in generate.py:_strip_enc"),
    ("M2", "strip_enc: _INST_LITERAL maps to _LIT",
     'Suf{"_INST_LITERAL", "_LIT"}', 'Suf{"_INST_LIT", "_LIT"}',
     "the only suffix that REWRITES rather than deleting"),
    ("M3", "strip_enc: _VOP_DPP8 is dropped instead of _DPP8",
     'Suf{"_VOP_DPP8", "_DPP8"}', 'Suf{"_VOP_DPP8", "_DPP"}',
     "one character of a three-character suffix table"),
    ("M4", "norm_field: vsrc0 is NOT shifted to vsrc1",
     'Suf{"bound_ctrl", "bc"}', 'Suf{"bound_ctrl", "bd"}',
     "the ONLY shorten-to-one-character rename in _FIELD_RENAMES"),
    ("M5", "norm_field: simm32 is NOT renamed literal",
     'Suf{"simm32", "literal"}', 'Suf{"simm32", "simm32"}',
     "the ONLY rename that CHANGES the name's length, and it is what puts the "
     "immediate in the `literal` slot of the field ORDER"),
    ("M6", "map_flat: FLAT_GLOBAL loses its map to GLOBAL",
     'Bool.or(String.eq(enc_name, "FLAT_GLBL"), String.eq(enc_name, "FLAT_GLOBAL"))',
     'Bool.or(String.eq(enc_name, "FLAT_GLBL"), Bool.not(True{}))',
     "the first of the two special-case names in generate.py:_map_flat"),
    ("M7", "map_flat: a V-prefixed encoding loses its V",
     'def map_flat.v(enc_name: String) -> String: Bool.pick(String, String.starts_with(enc_name, "V"), "V", "")',
     'def map_flat.v(enc_name: String) -> String: ""', "the prefix that turns FLAT into VFLAT"),
    ("M8", "map_flat: SCRATCH_ loses a character",
     'String.starts_with(instr_name, "SCRATCH_")', 'String.starts_with(instr_name, "SCRATCHX")',
     "a missing character in a prefix test"),
    # ---- `field_def` (the rule table that decides a field's DSL class) ----
    ("M9", "field_def: the VGPR arm's width guard becomes 7",
     'R{2, "", 8, 0, K2_VGPR()}', 'R{2, "", 7, 0, K2_VGPR()}',
     "bits == 8 for vdst/vaddr/data; the WHOLE VGPR class is decided here"),
    ("M10", "field_def: SRsrcField's 5 becomes 6",
     'R{0, "srsrc", 5, 0, K2_SRSC()}', 'R{0, "srsrc", 6, 0, K2_SRSC()}',
     "the ONE width shared by two rules (srsrc, ssamp); the fixture has a 5-bit srsrc"),
    ("M11", "field_def: the 8-bit saddr's NULL default is lost",
     'R{0, "saddr", 8, 0, K2_SSRCN()}', 'R{0, "saddr", 8, 0, K2_SSRC()}',
     "`SSrcField(h, l, default=NULL)` vs `SSrcField(h, l)` -- the rule table has BOTH"),
    ("M12", "field_def: opsel_hi's default=3 becomes default=1",
     '"", "default=3", "default=1"]', '"", "default=1", "default=1"]',
     "the two VOP3P defaults differ and both appear in the emission"),
    ("M13", "field_def: the 9-bit SrcField arm's width guard becomes 8",
     'R{1, "src", 9, 0, K2_SRC9()}', 'R{1, "src", 8, 0, K2_SRC9()}',
     "src0/1/2/3 are the LAST arm of the ladder, the 9-bit one"),
    ("M14", "field_def: an empty arg3 leaves a trailing comma",
     'Bool.pick(String, String.is_empty(arg3(kind, base_fmt)),\n    ctor(kind) ++ "("',
     'Bool.pick(String, Bool.not(True{}),\n    ctor(kind) ++ "("',
     "the `String.concat`-drops-a-literal bug in its most literal form"),
    # ---- `write_ins` fold 1: the base classes ----
    ("M15", "base classes: the FLAT seg split is disabled",
     'Bool.pick(List<&2, String>, is_flat_split(EC.name(e), seg_hit(EC.fields(e))),',
     'Bool.pick(List<&2, String>, Bool.not(True{}),', "three classes out of one encoding"),
    ("M16", "base classes: GLOBAL's seg 2 becomes 1",
     'FV{flat_prefix(nm) ++ "GLOBAL", 2, flat_prefix(nm) ++ "GLOBALOp"}',
     'FV{flat_prefix(nm) ++ "GLOBAL", 1, flat_prefix(nm) ++ "GLOBALOp"}',
     "seg is what tells FLAT/GLOBAL/SCRATCH apart; 0/2/1 is the whole triple"),
    ("M17", "base classes: SCRATCH's seg 1 becomes 2",
     'FV{flat_prefix(nm) ++ "SCRATCH", 1, flat_prefix(nm) ++ "SCRATCHOp"}',
     'FV{flat_prefix(nm) ++ "SCRATCH", 2, flat_prefix(nm) ++ "SCRATCHOp"}',
     "the other end of the same triple"),
    ("M18", "base classes: DPP is emitted instead of skipped",
     'Bool.or(String.eq(nm, "FLAT_GLBL"), Bool.or(String.eq(nm, "DPP"), String.eq(nm, "SDWA")))',
     'Bool.or(String.eq(nm, "FLAT_GLBL"), String.eq(nm, "SDWA"))',
     "DPP/SDWA are in `encodings` but are NOT classes"),
    ("M19", "get_base_fmt: _LIT is no longer stripped",
     '"_LIT", "_DPP16"', '"_LITX", "_DPP16"',
     "VOP1_LIT's op must read VOP1Op and its class must inherit VOP1"),
    # ---- `write_ins` fold 2/3: variant and SDST classes ----
    ("M20", "SDST: VOP1's vdst field is 24,17 -> 23,17",
     'SD{"VOP1", 24, 17}', 'SD{"VOP1", 23, 17}',
     "the SDST table AND its order are one literal"),
    ("M21", "SDST: VOP3's SDST op threshold 256 becomes 255",
     'U32.is_lt(op, 256)', 'U32.is_lt(op, 255)',
     "generate.py:428 adds every VOP3 op below 256"),
    ("M22", "variant: the _MFMA suffix is lost",
     '"_SDWA_SDST", "_SDWA", "_MFMA"]', '"_SDWA_SDST", "_SDWA", "_MFM"]',
     "the LAST of the six variant suffixes; a shorter prefix still matches nothing"),
    ("M23", "variant: `op_field and is_suffix_variant` drops the suffix test",
     'is_suffix_variant(EC.name(e), ss),\n    variant_fields.go',
     'Bool.not(True{}),\n    variant_fields.go',
     "the _LIT override that lets an op the base class excluded back in"),
    # ---- `write_ins` fold 4: the instruction helpers ----
    ("M24", "helpers: ADDTID is no longer dropped from FLAT",
     'String.contains(nm, "ADDTID")', 'String.contains(nm, "ADDTIX")',
     "the ONLY dropped row in the emitter: S_ADDTID lives in FLAT, VFLAT and GLOBAL"),
    ("M25", "helpers: a variant encoding gets helpers too",
     'Bool.and(not(String.eq(EC.name(ec_get(fmt, encs)), "")), String.eq(get_base_fmt(fmt), fmt))',
     'not(String.eq(EC.name(ec_get(fmt, encs)), ""))',
     "VOP1_DPP16/VOP1_LIT/VOP3P_MFMA are in `encodings` but are VARIANTS"),
    ("M26", "helpers: the VOP3 `_E64` threshold 512 becomes 256",
     'U32.is_le(512, op)', 'U32.is_le(256, op)',
     "V_MAD_F32 (512) keeps no suffix; V_CMP_F32 (0) keeps _E64"),
    ("M27", "helpers: the `# instruction helpers` marker moves to the END",
     'List.append(&2, String, List.append(&2, String, acc, ["# instruction helpers"]),\n    helper_fmts(sort_eos(eos), encs, ss, sdst_ops(tys, eos), tys, Nil{}))',
     'List.append(&2, String, helper_fmts(sort_eos(eos), encs, ss, sdst_ops(tys, eos), tys, acc),\n    ["# instruction helpers"])',
     "generate.py:446 appends it BEFORE the loop"),
    ("M28", "helpers: a suffix-only op loses its variant class",
     'Bool.pick(String, String.eq(op_to_suffix(ss, fmt, op), ""), fmt,\n        fmt ++ op_to_suffix(ss, fmt, op))',
     'fmt', "V_MFMA_LD_SCALE_B32 must read VOP3P_MFMA, not VOP3P"),
    # ---- the other three emitters ----
    ("M29", "write_enum: HWREG/MSG become `HWREGOp`/`MSGOp` classes",
     'def class_name(+fmt: String) -> String:\n  Bool.pick(String, enum_plain_b(fmt), fmt, fmt ++ "Op")',
     'def class_name(+fmt: String) -> String:\n  fmt ++ "Op"', "HWREG and MSG are plain enums"),
    ("M30", "write_enum: the alias row is emitted for the _E32 group",
     'Bool.pick(List<&2, String>, String.is_empty(op_msuf(fmt, OP.op(o))), acc,',
     'Bool.pick(List<&2, String>, True{}, acc,', "the `V_CNPY = V_CNPY_E32` alias lines"),
    ("M31", "write_common: FMT_BITS' closing brace is dropped",
     'List.append(&2, String, head, List.append(&2, String, rows, ["}"]))',
     'List.append(&2, String, head, List.append(&2, String, rows, [""]))',
     "the generated dict must close"),
    ("M32", "write_operands: a base's `Op` suffix is lost",
     'List.append(&2, String, acc, [b ++ "Op"])', 'List.append(&2, String, acc, [b])',
     "the import list is USED BASES from `types`, not all of `enums`"),
    ("M33", "write_operands: the (name, base) `valid` filter is removed",
     'def write_operands.keep(+t: TY, vs: List<&2, VF>) -> Bool:\n  vf_hit(vs, TY.name(t), TY.base(t))',
     'def write_operands.keep(+t: TY, vs: List<&2, VF>) -> Bool:\n  True{}',
     "every (Op, Fmt) pair the XML lists, valid or not"),
    ("M34", "all_field_defs: one field definition is dropped",
     'all_defs.append(t, List.append(&2, String, acc, [x]))', 'all_defs.append(t, acc)',
     "the joined string the DSL re-export list is scanned out of"),
    # ---- `write_pcode`, the fifth emitter ----
    ("M35", "write_pcode: the sort key is (opcode, enum) instead of (enum, opcode)",
     'case PE{+en1, mn1, op1, code1} PE{+en2, mn2, op2, code2}:\n      Bool.or(String.is_lt(en1, en2), Bool.and(String.eq(en1, en2), U32.is_le(op1, op2)))',
     'case PE{+en1, mn1, +op1, code1} PE{+en2, mn2, +op2, code2}:\n      Bool.or(U32.is_lt(op1, op2), Bool.and(U32.is_eq(op1, op2), String.is_lt(en1, en2)))',
     "a TRANSPOSED tuple key: `V_MAD_F32` (512) before `V_ADD_F32` (300)"),
    ("M36", "write_pcode: the `_E64` threshold 512 becomes 256",
     'U32.is_le(512, op)', 'U32.is_le(256, op)',
     "V_ADD_F32 (300) would GAIN a suffix; V_MAD_F32 (512) keeps none"),
    ("M37", "write_pcode: the import lists EVERY enum, not the contributing ones",
     'dedup_adj(pcode_enums.go(pcode_entry(eos, ps), Nil{}))', 'pcode_enums.go(pcode_entry(eos, ps), Nil{})',
     "`sorted(set(e[0] for e in entries))` -- dedup is what removes the repeats"),
    ("M38", "write_pcode: repr loses its surrounding quotes",
     'repr_body.quote(s) ++ String.concat(repr_body.go(String.to_list(s), Nil{})) ++ repr_body.quote(s)',
     'String.concat(repr_body.go(String.to_list(s), Nil{}))',
     "{code!r} -- CPython quotes the literal, and the quote choice depends on the text"),
    ("M39", "write_pcode: the trailing comma is dropped",
     'def pcode_line(+e: PE) -> String: "  " ++ PE.en(e) ++ "." ++ PE.mn(e) ++ ": " ++ repr_str(PE.code(e)) ++ ","',
     'def pcode_line(+e: PE) -> String: "  " ++ PE.en(e) ++ "." ++ PE.mn(e) ++ ": " ++ repr_str(PE.code(e))',
     "every PCODE row is a dict item, so the comma is load-bearing"),
    ("M40", "write_pcode: the header moves AFTER the rows",
     'List.append(&2, String,\n    write_pcode.head(sort_strs(dedup_adj(pcode_enums.go(pcode_entry(eos, ps), Nil{}))), arch),\n    List.append(&2, String, pcode_lines.go(List.sort(PE, pe_le, pcode_entry(eos, ps)), Nil{}), ["}"]))',
     'List.append(&2, String,\n    List.append(&2, String, pcode_lines.go(List.sort(PE, pe_le, pcode_entry(eos, ps)), Nil{}), ["}"]),\n    write_pcode.head(sort_strs(dedup_adj(pcode_enums.go(pcode_entry(eos, ps), Nil{}))), arch))',
     "`lines = [hdr..., \"PCODE = {\"]` is built BEFORE the entries loop"),
    ("M41", "dsl_reexport: NULL is removed from _ALL_DSL only",
     '"FixedBitField", "NULL", "SBaseField"', '"FixedBitField", "SBaseField"',
     "NO-OP BY DESIGN and the table proves it: NULL is in BOTH `_ALL_DSL` and "
     "`_DSL_REGS` upstream, upstream takes `sorted(set(dsl_names + _DSL_REGS))`, "
     "so dropping it from one side cannot move a row"),
]


def main(only=None):
    global MUTS
    if only: MUTS = [m for m in MUTS if m[0] in only]
    src = F.read_text()
    base = parse(BASE_TXT.read_text())
    rows = []
    for mid, desc, find, repl, why in MUTS:
        if src.count(find) != 1:
            rows.append((mid, desc, why, PNA.not_applied(
                "anchor appears %d times" % src.count(find))))
            continue
        got = run(src.replace(find, repl, 1))
        if got == "STACK":
            rows.append((mid, desc, why, "INCONCLUSIVE: 8 machine-stack overflows"))
            continue
        if got is None:
            rows.append((mid, desc, why, "DID NOT COMPILE / PROOFS FAILED"))
            continue
        mv = moved(base, got)
        if not mv:
            rows.append((mid, desc, why, "0  <-- BLIND SPOT"))
        else:
            rows.append((mid, desc, why, "%d  %s" % (len(mv), ", ".join(mv[:6]))))
    w = max(len(r[0]) for r in rows)
    out = ["| id | ported rule | gate rows it moves |", "|---|---|---|"]
    for mid, desc, why, res in rows:
        out.append("| %s | %s | %s |" % (mid, desc, res))
        out.append("| | _why it must move:_ | %s |" % why)
    live = [r for r in rows if r[3][0].isdigit() and not r[3].startswith("0")]
    print("\n".join(out))
    print("\n%d mutations, %d move rows, %d do not" % (len(rows), len(live), len(rows) - len(live)))
    print("NOT MOVING:")
    for mid, desc, why, res in rows:
        if (mid, desc, why, res) not in live:
            print("  %s: %s  [%s]" % (mid, res, desc))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or None))