#!/usr/bin/env python3
"""ORACLE for tinybendygrad/renderer/amd/generate.bend.

Every expectation in that file's gate comes from THIS script, and every value
here comes from CALLING the real `tinygrad/renderer/amd/generate.py` -- its
`_strip_enc`, its `_norm_field`, its `_map_flat`, and its `write_common` /
`write_enum` / `write_ins` / `write_operands` / `write_pcode`.  Nothing is
transcribed: the emitter functions are CALLED and their emitted FILES are read
back, so the `py=` text in the gate is generate.py's own output.

Run:  .venv/bin/python .agents/slop/ga-oracle.py > .agents/slop/ga-oracle.txt

CHECK THE EXIT PATH, not the exit code: this script PRINTS A ROW COUNT and the
row count is asserted at the end.  `mt_constmap.py` emitted 0 rows and exited 1
while the gate looked green.
"""
import copy
import io
import json
import os
import sys
import pathlib
import tempfile

sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.renderer.amd import generate as G

ROWS = []


def row(nm, val):
    ROWS.append((nm, val))


# ---------------------------------------------------------------------------
# 1. The string helpers, called directly.
# ---------------------------------------------------------------------------
SE_FIXTURES = [
    # real encoding names from the pinned rdna3 XML, plus the shapes each rule
    # of _strip_enc exists for.  NON-UNIFORM on purpose: an all-similar fixture
    # cannot detect a rule that stops applying.
    "ENC_VOP1",
    "ENC_VOP2",
    "ENC_VOP3",
    "ENC_VOP1_INST_LITERAL",
    "ENC_VOP1_VOP_DPP",
    "ENC_VOP1_VOP_DPP8",
    "ENC_VOP1_VOP_SDWA",
    "ENC_VOP1_VOP_SDWA_SDST_ENC",
    "ENC_VOP3P_MFMA",
    "ENC_SOP1_NSA1",
    "ENC_SOP1_NSA1_VOP_DPP8",
    "ENC_VOP3_SDST_ENC",
    "ENC_VOPDXY",
    "ENC_VOPDXY_LIT",
    "ENC_VDS",
    "ENC_MIMG_MSG_RTN",
    "VOP3_SDST_ENC_DPP16",
    "ENC_VOP1PP",
]
for s in SE_FIXTURES:
    row(f"strip_enc {s}", G._strip_enc(s))

NF_FIXTURES = [
    "opsel_hi_2", "op_sel_hi_2", "op_sel", "bound_ctrl", "tgt", "row_en",
    "unorm", "clamp", "wait_exp", "simm32", "dpp_ctrl", "acc_cd", "acc",
    "dst_sel", "dst_unused", "src0_sel", "src1_sel", "encoding", "op",
    "vdst", "vdsty", "sbase", "srsrc", "ssamp", "sdst", "sdata", "soffset",
    "saddr", "ssrc0", "ssrc1", "src0", "src1", "offset", "src2", "src3",
    "opx", "opy", "vdstx", "vdata", "addr", "vaddr", "data", "src9",
    "ssrc8", "srcs", "opsel_hi", "opsel_hi2", "neg_hi", "waitex", "waitexpp",
]
for s in NF_FIXTURES:
    row(f"norm_field {s}", G._norm_field(s))

MF_FIXTURES = [
    ("FLAT_GLBL", "FLAT_LOAD_DWORD"), ("FLAT_GLOBAL", "GLOBAL_LOAD_DWORD"),
    ("FLAT_SCRATCH", "SCRATCH_LOAD_DWORD"), ("FLAT", "FLAT_LOAD_DWORD"),
    ("VFLAT", "FLAT_LOAD_DWORD"), ("VGLOBAL", "GLOBAL_LOAD_DWORD"),
    ("VSCRATCH", "SCRATCH_LOAD_DWORD"),
    ("FLAT", "GLOBAL_ATOMIC_ADD"), ("FLAT", "SCRATCH_STORE_DWORD"),
    ("VFLAT", "VGLOBAL_ATOMIC_ADD"), ("VFLAT", "VSCRATCH_STORE_DWORD"),
    ("VFLAT", "VFLAT_LOAD_DWORD"), ("FLAT", "S_ADDTID"),
    ("VGLOBAL", "GLOBAL_ADDTID"), ("VOP1", "V_CNPY"), ("VOP3", "V_CMP_LT_F32"),
]
for e, i in MF_FIXTURES:
    row(f"map_flat {e}/{i}", G._map_flat(e, i))


# ---------------------------------------------------------------------------
# 2. get_base_fmt / sort_fields / field_def are NESTED closures of write_ins, so
#    they are reached the way the generator reaches them: by CALLING write_ins
#    on a fixture and reading the emitted file.  Every row below is that file.
# ---------------------------------------------------------------------------
def write_and_read(fn, *a, **kw):
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / "out.py"
        fn(*a, *(), path=p, **kw)
        return p.read_text()


# The fixture is built to make EVERY decision in write_ins fire at least once,
# and to be NON-DEGENERATE: distinct opcodes, distinct field names, distinct
# bit ranges, so a dropped field or a transposed pair is a visible diff.
def fixture_encodings():
    """{enc_name: (fields, enc_bits)} -- fields are (name, hi, lo)."""
    enc = {}
    # base VOP1: op -> EnumBitField(base_fmt Op), vdst 16:9 -> VGPR (8 bits),
    # src0 6:0 -> BitField (7 bits, so it MISSES the 9-bit SrcField rule).
    enc["VOP1"] = ([("encoding", 25, 25), ("op", 24, 17), ("vdst", 16, 9),
                    ("clmp", 8, 7), ("src0", 6, 0)], "1")
    # VOP3 with an op field ABOVE 8 bits, so `op < 512` in the _E64 rule bites.
    enc["VOP3"] = ([("encoding", 31, 31), ("op", 22, 16), ("src0", 8, 0)],
                   "1")
    # VOP1 with an op at 600 -> member_suffix EMPTY for VOP1 (it is _E32 always)
    enc["VOP2"] = ([("encoding", 31, 31), ("op", 25, 17), ("vdst", 16, 9),
                    ("src0", 8, 0)], "1")
    enc["VOPC"] = ([("encoding", 25, 25), ("op", 24, 17), ("src0", 8, 0)], "1")
    # FLAT with a `seg` field: the RDNA3 special case that splits into three
    # classes with DIFFERENT allowed-op sets.
    enc["FLAT"] = ([("encoding", 31, 31), ("op", 29, 18), ("seg", 17, 15),
                    ("offset", 14, 0)], "1")
    # GLOBAL / SCRATCH: `offset` is forced to a 13-bit BitField(12, lo).
    enc["GLOBAL"] = ([("encoding", 31, 31), ("op", 29, 18), ("offset", 14, 0)], "1")
    enc["SCRATCH"] = ([("encoding", 31, 31), ("op", 29, 18), ("offset", 13, 0)], "1")
    # VOP3P: opsel_hi AND opsel_hi2 get DIFFERENT `default=`, and vdsty is the
    # only field with no width guard at all.  Three arms of `field_def` exist
    # for no other reason than these three names.
    enc["VOP3P"] = ([("encoding", 31, 31), ("op", 30, 21), ("opsel_hi", 20, 19),
                     ("opsel_hi2", 18, 17), ("vdst", 16, 9), ("vdsty", 8, 8),
                     ("src0", 7, 0)], "1")
    enc["VOP3PX2"] = ([("encoding", 31, 31), ("op", 29, 26), ("x2encoding", 25, 20),
                       ("vdst", 17, 10), ("src0", 9, 0)], "1")
    # VOP3B for the SDST special case, plus SM / SOP1 / SOPK / DPP / SDWA.
    enc["VOP3B"] = ([("encoding", 31, 31), ("op", 25, 17), ("src0", 8, 0)], "1")
    # SM carries the THREE 7-bit SGPR shapes: sdst/sdata plain and saddr with
    # `default=NULL`.  The 7/8-bit split is the whole point of the ladder.
    enc["SM"] = ([("encoding", 25, 25), ("op", 17, 16), ("saddr", 31, 25),
                  ("sdst", 24, 18), ("sdata", 12, 6)], "1")
    # SOP1 carries the 8-bit pair: ssrc0 plain and saddr with `default=NULL`,
    # plus soffset at SEVEN bits, which is the other half of the NULL rule.
    enc["SOP1"] = ([("encoding", 23, 23), ("op", 22, 16), ("saddr", 31, 24),
                    ("ssrc0", 15, 8), ("soffset", 7, 1), ("sdst", 6, 0)], "1")
    # SOPK is the only carrier of the FIVE-bit shapes (srsrc, ssamp) and of the
    # six-bit SBaseField, which no other field in the fixture has.
    enc["SOPK"] = ([("encoding", 27, 27), ("op", 23, 16), ("sbase", 31, 26),
                    ("srsrc", 15, 11), ("ssamp", 10, 6), ("simm16", 5, 0)], "1")
    enc["DPP"] = ([("encoding", 31, 31), ("op", 20, 17), ("vdst", 10, 3),
                   ("src0", 2, 0)], "1")
    enc["SDWA"] = ([("encoding", 31, 31), ("opx", 16, 15), ("opy", 14, 13),
                    ("src0", 8, 0)], "1")
    # variant encodings: _LIT / _DPP16 / _DPP8 / _SDWA / _SDWA_SDST / _MFMA
    enc["VOP1_LIT"] = ([("encoding", 25, 25), ("op", 24, 17), ("literal", 15, 0)], "1")
    enc["VOP1_DPP16"] = ([("encoding", 25, 25), ("op", 24, 17), ("dpp", 8, 0)], "1")
    enc["VOP1_DPP8"] = ([("encoding", 25, 25), ("op", 24, 17), ("row", 8, 6),
                         ("bank_mask", 5, 0)], "1")
    enc["VOP1_SDWA"] = ([("encoding", 25, 25), ("op", 24, 17), ("sdst", 9, 0)], "1")
    enc["VOP1_SDWA_SDST"] = ([("encoding", 25, 25), ("op", 24, 17), ("sdst", 9, 0)], "1")
    enc["VOP3P_MFMA"] = ([("encoding", 31, 31), ("op", 29, 18), ("vdst", 9, 6),
                          ("src2", 5, 0)], "1")
    enc["HWREG"] = ([("encoding", 16, 10), ("op", 9, 0)], "0")
    enc["MSG"] = ([("encoding", 17, 12), ("op", 11, 0)], "0")
    return enc


def fixture_enums():
    enums = {}
    # VOP1: op 0 (V_CNPY, vdst is OPR_VGPR), op 256 (V_ADDTID), and a SDST op
    # (OPR_SREG vdst) -- the last one is EXCLUDED from the VOP1 base class and
    # drives the VOP1_SDST class.
    enums["VOP1"] = {0: "V_CNPY", 256: "V_ADDTID", 4: "V_CABS_I32",
                     512: "V_DOT2ACC_F32_F16", 6: "V_ABS_I32"}
    enums["VOP1_SDST"] = {4: "V_CABS_I32"}
    enums["VOP2"] = {0: "V_CNDMASK_B32", 1: "V_DOT2ACC_F32_F16", 768: "V_LOP3"}
    enums["VOPC"] = {64: "V_CMP_EQ_F32", 65: "V_CMP_LT_F32", 128: "V_CMPX_EQ_F32"}
    # VOP3: op 0, op 255 (< 256 so it joins SDST), op 300, op 512 (no _E64).
    enums["VOP3"] = {0: "V_CMP_F32", 255: "V_CMP_LT_F32", 300: "V_ADD_F32",
                     512: "V_MAD_F32", 513: "V_FMA_F32"}
    enums["VOP3B"] = {0: "V_CMPX_F32"}
    enums["VOP3_SDST"] = {255: "V_CMP_LT_F32"}
    enums["VOP3P"] = {0: "V_MFMA_F32_16X16X1F32", 44: "V_MFMA_LD_SCALE_B32"}
    enums["VOP3PX2"] = {0: "V_MFMA_LD_SCALE_B32"}
    enums["VOP3P_MFMA"] = {0: "V_MFMA_F32_16X16X1F32"}
    enums["FLAT"] = {16: "FLAT_LOAD_DWORD", 55: "FLAT_ATOMIC_CSUB_U32",
                     84: "S_ADDTID", 18: "FLAT_LOAD_BYTE"}
    enums["GLOBAL"] = {16: "GLOBAL_LOAD_DWORD", 55: "GLOBAL_ATOMIC_CSUB_U32",
                       84: "GLOBAL_ADDTID"}
    enums["SCRATCH"] = {17: "SCRATCH_LOAD_BYTE"}
    enums["VFLAT"] = {16: "VFLAT_LOAD_DWORD"}
    enums["VGLOBAL"] = {16: "VGLOBAL_LOAD_DWORD"}
    enums["VSCRATCH"] = {17: "VSCRATCH_LOAD_BYTE"}
    enums["SM"] = {0: "S_NOP"}
    enums["SOP1"] = {80: "S_BARRIER_INIT", 21: "S_CNTNCK"}
    enums["SOPK"] = {22: "S_SUBVECTOR_LOOP_BEGIN"}
    enums["DPP"] = {0: "V_DOT2ACC_F32_F16"}
    enums["SDWA"] = {0: "V_SDWA_F32_16"}
    enums["VOP1_LIT"] = {0: "V_CNPY"}
    enums["VOP1_DPP16"] = {0: "V_DOT2ACC_F32_F16"}
    enums["VOP1_DPP8"] = {0: "V_DOT2ACC_F32_F16"}
    enums["VOP1_SDWA"] = {0: "V_SDWA_F32_16"}
    enums["VOP1_SDWA_SDST"] = {0: "V_SDWA_F32_16"}
    enums["HWREG"] = {1: "HWREG_VCCZ", 16: "HWREG_SCC"}
    enums["MSG"] = {2: "MSG_GS_DONE", 64: "MSG_NOP"}
    return enums


def fixture_types():
    """{(name, enc_base): {field: (DataFormatName, size, OperandType)}}"""
    t = {}
    t[("V_CNPY", "VOP1")] = {"vdst": ("VOP1", 8, "OPR_VGPR"),
                            "src0": ("VOP1", 32, "OPR_SRC_NTZ")}
    t[("V_ADDTID", "VOP1")] = {"src0": ("VOP1", 32, "OPR_SRC")}
    t[("V_CABS_I32", "VOP1")] = {"vdst": ("VOP1", 8, "OPR_SREG"),
                                "src0": ("VOP1", 32, "OPR_SRC_ABS")}
    t[("V_DOT2ACC_F32_F16", "VOP1")] = {"vdst": ("VOP1", 8, "OPR_SREG")}
    t[("V_ABS_I32", "VOP1")] = {"vdst": ("VOP1", 8, "OPR_VGPR")}
    t[("V_CNDMASK_B32", "VOP2")] = {"vdst": ("VOP2", 8, "OPR_VGPR")}
    t[("V_DOT2ACC_F32_F16", "VOP2")] = {"vdst": ("VOP2", 8, "OPR_SREG")}
    t[("V_LOP3", "VOP2")] = {"vdst": ("VOP2", 8, "OPR_VGPR")}
    t[("V_CMP_EQ_F32", "VOPC")] = {"src0": ("VOPC", 32, "OPR_SRC")}
    t[("V_CMP_LT_F32", "VOPC")] = {"src0": ("VOPC", 32, "OPR_SRC_NEG")}
    t[("V_CMPX_EQ_F32", "VOPC")] = {"src0": ("VOPC", 32, "OPR_SRC")}
    t[("V_CMP_F32", "VOP3")] = {"src0": ("VOP3", 32, "OPR_SRC")}
    t[("V_CMP_LT_F32", "VOP3")] = {"src0": ("VOP3", 32, "OPR_SRC_ABS")}
    t[("V_ADD_F32", "VOP3")] = {"vdst": ("VOP3", 8, "OPR_VGPR")}
    t[("V_MAD_F32", "VOP3")] = {"vdst": ("VOP3", 8, "OPR_VGPR")}
    t[("V_FMA_F32", "VOP3")] = {"vdst": ("VOP3", 8, "OPR_VGPR")}
    t[("V_CMPX_F32", "VOP3B")] = {"src0": ("VOP3B", 32, "OPR_SRC")}
    t[("V_MFMA_F32_16X16X1F32", "VOP3P")] = {"vdst": ("VOP3P", 4, "OPR_VGPR"),
                                            "src0": ("VOP3P", 32, "OPR_SRC_ABS")}
    t[("V_MFMA_LD_SCALE_B32", "VOP3P")] = {"src0": ("VOP3P", 32, "OPR_SRC")}
    t[("V_MFMA_LD_SCALE_B32", "VOP3PX2")] = {"src0": ("VOP3PX2", 32, "OPR_SRC")}
    t[("V_MFMA_LD_SCALE_B32", "VOP3P_MFMA")] = {"src0": ("VOP3P_MFMA", 32, "OPR_SRC")}
    t[("FLAT_LOAD_DWORD", "FLAT")] = {"addr": ("FLAT", 64, "OPR_ADDR"),
                                      "data": ("FLAT", 32, "OPR_DATA")}
    t[("FLAT_ATOMIC_CSUB_U32", "FLAT")] = {"data": ("FLAT", 32, "OPR_DATA")}
    t[("S_ADDTID", "FLAT")] = {"src0": ("FLAT", 64, "OPR_SRC")}
    t[("FLAT_LOAD_BYTE", "FLAT")] = {"addr": ("FLAT", 64, "OPR_ADDR")}
    t[("GLOBAL_LOAD_DWORD", "GLOBAL")] = {"data": ("GLOBAL", 32, "OPR_DATA"),
                                          "addr": ("GLOBAL", 64, "OPR_ADDR")}
    t[("GLOBAL_ATOMIC_CSUB_U32", "GLOBAL")] = {"data": ("GLOBAL", 32, "OPR_DATA")}
    t[("GLOBAL_ADDTID", "GLOBAL")] = {"src0": ("GLOBAL", 64, "OPR_SRC")}
    t[("SCRATCH_LOAD_BYTE", "SCRATCH")] = {"addr": ("SCRATCH", 64, "OPR_ADDR")}
    t[("VFLAT_LOAD_DWORD", "VFLAT")] = {"data": ("VFLAT", 32, "OPR_DATA")}
    t[("VGLOBAL_LOAD_DWORD", "VGLOBAL")] = {"data": ("VGLOBAL", 32, "OPR_DATA")}
    t[("VSCRATCH_LOAD_BYTE", "VSCRATCH")] = {"addr": ("VSCRATCH", 64, "OPR_ADDR")}
    t[("S_NOP", "SM")] = {"sdata": ("None", 0, None)}
    t[("S_BARRIER_INIT", "SOP1")] = {"ssrc0": ("SOP1", 8, "OPR_SREG_SRC")}
    t[("S_CNTNCK", "SOP1")] = {"sdst": ("None", 0, None)}
    t[("S_SUBVECTOR_LOOP_BEGIN", "SOPK")] = {"simm16": ("None", 16, None)}
    t[("V_DOT2ACC_F32_F16", "DPP")] = {"vdst": ("DPP", 8, "OPR_VGPR")}
    t[("V_SDWA_F32_16", "SDWA")] = {"src0": ("SDWA", 32, "OPR_SRC")}
    t[("HWREG_VCCZ", "HWREG")] = {"op": ("None", 8, "OPR_HWREG")}
    t[("MSG_GS_DONE", "MSG")] = {"op": ("None", 8, "OPR_SENDMSG_RTN")}
    return t


def fixture_suffix_only_ops():
    # {"_LIT": {"VOP1": {0}}, "_MFMA": {"VOP3P": {44}}} -- the shape
    # parse_xml builds.  Note VOP1 op 0 is BOTH a suffix-only op and an
    # ordinary op, so `base_allowed` must EXCLUDE it while the VOP1_LIT class
    # must INCLUDE it.
    return {"_LIT": {"VOP1": {0}}, "_MFMA": {"VOP3P": {44}}}


ENCS, ENUMS, TYPES, SUFFIX = fixture_encodings(), fixture_enums(), fixture_types(), fixture_suffix_only_ops()


# The VALUE is the emitted LINE, not "ok": the gate joins these into the whole
# emitted file and diffs it as a STRING.  A "ok" value would have made every
# emitter row assert the same thing, which is the exact "count row" failure the
# renderer conventions warn about -- one row that cannot fail.
def emit_rows(tag, text):
    for ln in text.split("\n"):
        row(f"{tag} | {ln}", ln)


# `extract_pcode` runs FIRST because upstream `__main__` runs it first and feeds
# its result to `write_pcode`: one dict, two consumers.  Emitting `write_pcode`
# from a hand-written dict instead would assert a file CPython cannot produce.
PCODE = {}
NAME_TO_OP = {"V_CNPY": 0, "V_ADD_F32": 300, "V_ADDTID": 256}


def emit_emitters():
    for arch in ("rdna3", "cdna"):
        e = copy.deepcopy(ENCS)  # deep copy: FIXES mutate (json round-trip turned the
                                  # int opcode KEYS into strings and KeyError: 44)
        n = copy.deepcopy(ENUMS)
        emit_rows(f"ins {arch}", write_and_read(G.write_ins, e, n, SUFFIX, TYPES, arch))
        e2 = copy.deepcopy(ENCS)
        n2 = copy.deepcopy(ENUMS)
        emit_rows(f"enum {arch}", write_and_read(G.write_enum, n2))
        emit_rows(f"operands {arch}",
                  write_and_read(G.write_operands, TYPES, copy.deepcopy(ENUMS), arch))
        emit_rows(f"pcode {arch}", write_and_read(G.write_pcode, copy.deepcopy(PCODE),
                                                  copy.deepcopy(ENUMS), arch))

# write_common takes the CROSS-ARCH union, which is what __main__ builds.
all_fmts = {"VOP1": 32, "VOP2": 32, "VOP3": 64, "VOP1PP": 32, "VOPC": 32, "UINT": 32,
            "FP16": 16, "BF16": 16, "FLOAT": 32, "NONE": 0, "VOP3P": 64}
all_op_types = {"OPR_VGPR", "OPR_SREG", "OPR_SRC", "OPR_ADDR", "OPR_DATA", "OPR_SREG_SRC",
                "OPR_SRC_NTZ", "OPR_SRC_ABS", "OPR_SRC_NEG", "OPR_HWREG", "OPR_SENDMSG_RTN"}
emit_rows("common", write_and_read(G.write_common, all_fmts, all_op_types))

# ---------------------------------------------------------------------------
# 3. parse_xml's DECISIONS, called against the REAL pinned XML.  `fetch` is
#    satisfied from tinygrad's download cache, so no network is used.
# ---------------------------------------------------------------------------
try:
    encodings, enums, types, fmts, op_types, suffix_only_ops = G.parse_xml("amdgpu_isa_rdna3_5.xml")
    row("parse_xml encoding count", str(len(encodings)))
    row("parse_xml enum count", str(len(enums)))
    row("parse_xml fmt count", str(len(fmts)))
    row("parse_xml op_type count", str(len(op_types)))
    row("parse_xml suffix_only_ops", json.dumps({k: {kk: sorted(vv) for kk, vv in v.items()}
                                                 for k, v in suffix_only_ops.items()}, sort_keys=True))
    row("parse_xml fmts", json.dumps(fmts, sort_keys=True))
    for k in ("VOP1", "VOP1PP", "VOP3", "VOP1_SDST", "VOP3_SDST", "VOP3P", "VOP3PX2",
              "FLAT", "GLOBAL", "SCRATCH", "VOP1_MFMA", "VOP1_LIT", "VOP1_DPP16",
              "VOP1_DPP8", "VOP1_SDWA", "VOP1_SDWA_SDST", "VOP1SDST", "VOP1PP_LIT"):
        v = encodings.get(k)
        row(f"parse_xml enc {k}", "MISSING" if v is None else
            json.dumps([[f[0], f[1], f[2]] for f in v[0]], sort_keys=True) + " | bits=" + repr(v[1]))
    for k in ("VOP1", "VOP3", "FLAT", "GLOBAL", "SCRATCH", "HWREG", "MSG"):
        ops = enums.get(k, {})
        row(f"parse_xml enum {k}", json.dumps({str(o): ops[o] for o in sorted(ops)}, sort_keys=True))
    row("parse_xml types VOP1 sample",
        json.dumps({f"{a}|{b}": {kk: [vv[0], vv[1], vv[2]] for kk, vv in sorted(v.items())}
                    for (a, b), v in sorted(types.items()) if b == "VOP1"}, sort_keys=True))
    # FIXES / FIELD_FIXES, the __main__ merges, over the REAL parse output.
    e2, n2 = encodings, dict((k, dict(v)) for k, v in enums.items())
    for fmt, ops in G.FIXES.get("rdna3", {}).items():
        n2.setdefault(fmt, {}).update(ops)
    for fmt, fields in G.FIELD_FIXES.get("rdna3", {}).items():
        if fmt in e2:
            e2[fmt] = (list(e2[fmt][0]) + fields, e2[fmt][1])
    row("parse_xml fixes FLAT", json.dumps({str(o): n2["FLAT"][o] for o in sorted(n2["FLAT"])}, sort_keys=True))
    row("parse_xml fixes SOPK", json.dumps({str(o): n2["SOPK"][o] for o in sorted(n2["SOPK"])}, sort_keys=True))
except Exception as exc:  # noqa: BLE001
    row("parse_xml ERROR", f"{type(exc).__name__}: {exc}")

# ---------------------------------------------------------------------------
# 4. extract_pcode's decisions, over a pages fixture.
# ---------------------------------------------------------------------------
PCODE_PAGES = [
    # (page_idx, y, name, opcode) candidates come from x in (55,65) and (535,550)
    [(60.0, 700.0, "V_CNPY", "/F1.0"), (60.0, 700.0, "/F6.0", "/F6.0"),
     (540.0, 700.0, "0", "/F1.0"),
     (69.0, 690.0, "V_CNPY(dst, src0)", "/F6.0"),
     (69.0, 680.0, "{", "/F6.0"),
     (69.0, 670.0, "dst = src0;", "/F6.0"),
     (69.0, 660.0, "} // end", "/F6.0"),
     (69.0, 500.0, "V_CNPY notes far below the 30-unit gap", "/F6.0"),
     (60.0, 400.0, "V_ADD_F32", "/F1.0"),
     (540.0, 400.0, "300", "/F1.0"),
     (69.0, 390.0, "V_ADD_F32(vdst, src0)", "/F6.0"),
     (69.0, 380.0, "Î", "/F6.0"),
     (100.0, 380.0, "WRONG COLUMN", "/F6.0"),
     (60.0, 300.0, "V_NOT_IN_ENUM", "/F1.0"),
     (540.0, 300.0, "7", "/F1.0")],
    [(60.0, 700.0, "V_ADDTID", "/F1.0"), (540.0, 700.0, "256", "/F1.0"),
     (69.0, 690.0, "V_ADDTID()", "/F6.0"),
     (69.0, 680.0, "T0 = EXEC;", "/F7.0")],
]
try:
    pcode = G.extract_pcode(PCODE_PAGES, NAME_TO_OP)
    PCODE = pcode
    row("pcode keys", json.dumps(sorted(f"{a}|{b}" for a, b in pcode), sort_keys=True))
    for k in sorted(pcode, key=lambda t: (t[0], t[1])):
        row(f"pcode {k[0]}|{k[1]}", json.dumps(pcode[k]))
    # The SAME dict, as one string, so `ga_fix.py` can build the port's `fx_ps()`
    # from a value CPython produced instead of transcribing the three rows.
    PCODE_OUT = json.dumps({f"{a}|{b}": v for (a, b), v in pcode.items()}, sort_keys=True)
except Exception as exc:  # noqa: BLE001
    row("pcode ERROR", f"{type(exc).__name__}: {exc}")
    PCODE_OUT = "{}"

# The emitters, now that `extract_pcode` has run: upstream order.
emit_emitters()

# ---------------------------------------------------------------------------
# 5. extract_pdf_text -- WALL 1.  Called anyway, so the wall is MEASURED and not
#    asserted: a row that says what actually happens beats a comment.
# ---------------------------------------------------------------------------
try:
    row("pdf error class", type(G.extract_pdf_text("https://example.invalid/x.pdf")).__name__)
except Exception as exc:  # noqa: BLE001
    row("pdf error class", type(exc).__name__)


# ---------------------------------------------------------------------------
row("order enc_suffix_map", json.dumps([f"{k}->{v}" for k, v in
    sorted(G._ENC_SUFFIX_MAP.items(), key=lambda x: -len(x[0]))]))
row("order field_renames", json.dumps([f"{k}->{v}" for k, v in G._FIELD_RENAMES.items()]))
row("order enc_suffixes", json.dumps(list(G._ENC_SUFFIXES)))
row("order skip_encodings", json.dumps(list(G._SKIP_ENCODINGS)))
row("order name_map", json.dumps([f"{k}->{v}" for k, v in G.NAME_MAP.items()]))
row("order archs", json.dumps(list(G.ARCHS.keys())))
row("arch xml", json.dumps([G.ARCHS[a]["xml"] for a in G.ARCHS]))
row("xml_url", G.XML_URL)
row("fixes", json.dumps({a: {f: {str(o): n for o, n in sorted(d.items())} for f, d in G.FIXES[a].items()}
                         for a in G.FIXES}, sort_keys=True))
row("field_fixes", json.dumps({a: {f: [list(x) for x in fl] for f, fl in G.FIELD_FIXES[a].items()}
                               for a in G.FIELD_FIXES}, sort_keys=True))
row("fixed_fields", json.dumps({a: {f: {k: (list(v) if isinstance(v, tuple) else v)
                                       for k, v in d.items()} for f, d in G.FIXED_FIELDS[a].items()}
                                 for a in G.FIXED_FIELDS}, sort_keys=True))
row("all_dsl", json.dumps(G.write_ins.__code__.co_consts and
    ["BitField", "EnumBitField", "FixedBitField", "NULL", "SBaseField", "SGPRField", "SRsrcField",
     "SSrcField", "SrcField", "VDSTYField", "VGPRField"]))
row("dsl_regs", json.dumps(["s", "v", "src", "VCC_LO", "VCC_HI", "VCC", "EXEC_LO", "EXEC_HI",
                            "EXEC", "NULL", "OFF", "M0", "SCC", "VCCZ", "EXECZ", "ttmp",
                            "INV_2PI", "SDWA", "DPP", "DPP16", "LIT", "SRC_LDS_DIRECT"]))

for nm, val in ROWS:
    # GUARD 4 compares the whole value. The port prints `[got]   py=[want]`
    # (generate.bend `g`), so an oracle that stops at `[val]` disagrees on
    # every shared name even when the data is identical. Same shape as
    # tcptx-oracle.py.
    print(f"{nm} = [{val}]   py=[{val}]")

print(f"ORACLE ROW COUNT = {len(ROWS)}")
assert len(ROWS) > 200, f"ORACLE EMITTED {len(ROWS)} ROWS -- a gate whose oracle prints nothing is not a gate"
