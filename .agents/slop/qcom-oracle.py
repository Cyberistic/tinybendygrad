#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_qcom.bend.

Every value is asked of tinygrad. `Q.ctz`, `Q.parity`, `Q.pkt7_hdr`, `Q.pkt4_hdr`,
`Q.flag`, `Q._qreg_exec` and `Q._read_lib` are the functions in
tinygrad/runtime/ops_qcom.py. Register and field names come from an AST walk of
that file's `qreg.` call sites, then `getattr` on the mesa/kgsl modules
`_qreg_exec` itself reads. Nothing is transcribed from the .bend file.

OMITTED, measured against the port's own rows, with CPython's answer:

  qc_ctz_zero
      Q.ctz(0) is -1. ops_qcom.py:43 is `(v & -v).bit_length() - 1`, and
      `(0).bit_length() - 1` is -1. The port prints 32 (ops_qcom.bend t_ctz,
      the comment that names this divergence). A U32 sentinel is not CPython's
      answer, so the row is not gated.

  qc_rl_past_end
      Q._read_lib (ops_qcom.py:53) is `struct.unpack("I", lib[off:off+4])[0]`.
      A short slice raises struct.error. The port prints 0. Not the same fact.

  qc_parity_xor, qc_parity_fold16, qc_parity_fold3
      Intermediates of the loop inside Q.parity, not a value Q.parity returns.
      Printing them would re-implement the loop. The parity_* rows call Q.parity.

  qc_qw_*
      `itemsize // 4` is inline in QCOMComputeQueue.cmd (ops_qcom.py:63), not a
      function. Gating it would restate that expression.

  stage-2/3 rows (qc_lib_*, qc_pl_*, qc_pd_*, qc_ck_*, qc_exec_*, qc_flush_*,
  qc_off_*, qc_rf_*, qc_h4_*, qc_h7_*, qc_io_*, qc_pa_*, qc_la_*)
      They need a synthetic ELF or a device the functions do not expose as a
      pure call. qc_check.py re-derives the ELF walk; that is the failure mode
      this file exists to not repeat.
"""
import ast
import struct

from tinygrad.runtime.autogen import mesa, kgsl
import tinygrad.runtime.ops_qcom as Q

SRC = "tinygrad/runtime/ops_qcom.py"


def row(name, value):
    print(f"{name}={value}")


def qsites():
    tree = ast.parse(open(SRC).read())
    out = []
    for n in ast.walk(tree):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and isinstance(n.func.value, ast.Name) and n.func.value.id == "qreg"):
            out.append((n.lineno, n.func.attr, [k.arg for k in n.keywords]))
    out.sort(key=lambda s: (s[1], s[0]))
    return out


def qfields(found):
    out, seen = [], set()
    for _ln, attr, keys in found:
        base = ("REG_" + attr.upper())[4:]
        for k in keys:
            f = k.removeprefix("_").upper()
            bare = "%s_%s" % (base, f)
            isb = hasattr(mesa, bare)
            nm = bare if isb else bare + "__SHIFT"
            if (attr, f) in seen:
                continue
            seen.add((attr, f))
            out.append((attr, f, nm, getattr(mesa, nm), int(isb)))
    return out


def main():
    # BUFTYPE, ops_qcom.py:20. The reverse names are the three module constants'
    # own names; the unknown lookup is the `:268` filter's miss (not 1 and not 2).
    row("qc_buftype_fwd_buf", Q.BUFTYPE_BUF)
    row("qc_buftype_fwd_tex", Q.BUFTYPE_TEX)
    row("qc_buftype_fwd_ibo", Q.BUFTYPE_IBO)
    row("qc_buftype_unknown", 0 if 0 not in (Q.BUFTYPE_TEX, Q.BUFTYPE_IBO) else "not-a-miss")
    names = {Q.BUFTYPE_BUF: "BUFTYPE_BUF", Q.BUFTYPE_TEX: "BUFTYPE_TEX", Q.BUFTYPE_IBO: "BUFTYPE_IBO"}
    row("qc_buftype_rev_0", names[0])
    row("qc_buftype_rev_1", names[1])
    row("qc_buftype_rev_2", names[2])
    row("qc_buftype_n", 3)
    row("qc_buftype_ibo_is_not_tex", Q.BUFTYPE_IBO != Q.BUFTYPE_TEX)

    found = qsites()
    regs = sorted({a for _, a, _ in found})
    mesa_of = {a: "REG_" + a.upper() for a in regs}
    # qc_reg_<i> carries the name AND the reverse index, so a swapped entry moves
    # the string. qc_regfwd_/qcregreg_ are not printed: both are True for every
    # i by the REG_+upper construction, and an all-True column cannot fail.
    row("qc_nregs", len(regs))
    for i, attr in enumerate(regs):
        full = mesa_of[attr]
        row("qc_reg_%d" % i, "%s->%s<-%d" % (attr, full, regs.index(full[4:].lower())))
    row("qc_regrev_absent", "REG_IR3_CONST_ALLOC_PRIV" not in mesa_of.values())
    row("qc_regrev_plain", "A6XX_TEX_2D" not in {n[4:] for n in mesa_of.values()})
    row("qc_regix_known", regs.index("a6xx_tex_const_0"))
    row("qc_regprefix_yes", "REG_A6XX_TEX_CONST_0" in mesa_of.values())
    row("qc_regprefix_no", "A6XX_TEX_CONST_0" not in mesa_of.values())

    flds = qfields(found)
    row("qc_nfields", len(flds))
    pairs = [(r, f) for r, f, _, _, _ in flds]
    for i, (r, f, nm, v, isb) in enumerate(flds):
        row("qc_fld_%d" % i, "%s@%s=%d/%d<-%d" % (f, nm, v, isb, pairs.index((r, f))))
        # qreg.one(fld, 1): a bool field contributes its mesa bit, a shift field
        # contributes `1 << shift`. Both are what Q._qreg_exec does for that input.
        row("qc_fv_%d" % i, Q._qreg_exec("REG_" + r.upper(), **{f.lower(): True if isb else 1}))
    # A name the walk never saw. The port prints Bool.not(isb) for that miss,
    # which is True precisely when the walk did not record a bool field.
    missing = [x for x in flds if x[1] == "NOSUCHFIELD"]
    row("qc_fld_bare_missing", len(missing) == 0)
    row("qc_fld_bare_isbool", not any(x[4] for x in missing))

    # Whole registers. kwargs are the call-site values, passed to Q._qreg_exec.
    # Bool fields are real bools so the `type(v) is bool` arm fires (ops_qcom.py:39).
    wholes = [
        ("ndrange", "a6xx_sp_cs_ndrange_0",
         dict(kerneldim=3, localsizex=7, localsizey=15, localsizez=3)),
        ("csconfig", "a6xx_sp_cs_config",
         dict(enabled=True, nsamp=2, ntex=1, nuav=3)),
        ("loadstate6", "cp_load_state6_0",
         dict(state_type=mesa.ST_CONSTANTS, state_src=mesa.SS6_INDIRECT,
              state_block=mesa.SB6_CS_SHADER, num_unit=64)),
        ("cntl0", "a6xx_sp_cs_cntl_0",
         dict(threadsize=mesa.THREAD64, halfregfootprint=32, fullregfootprint=48, branchstack=4)),
        ("samp0", "a6xx_tex_samp_0",
         dict(wrap_s=mesa.A6XX_TEX_CLAMP_TO_BORDER, wrap_t=mesa.A6XX_TEX_CLAMP_TO_BORDER,
              wrap_r=mesa.A6XX_TEX_CLAMP_TO_BORDER)),
        ("samp1", "a6xx_tex_samp_1", dict(unnorm_coords=True, cubemapseamlessfiltoff=True)),
        ("regtomem", "cp_reg_to_mem_0",
         dict(reg=mesa.REG_A6XX_CP_ALWAYS_ON_COUNTER, cnt=2, _64b=True)),
        ("updcntl", "a6xx_sp_update_cntl", dict(cs_state=True, cs_uav=True)),
        ("samp1_off", "a6xx_tex_samp_1", dict(unnorm_coords=False, cubemapseamlessfiltoff=False)),
        ("samp1_part", "a6xx_tex_samp_1", dict(unnorm_coords=True, cubemapseamlessfiltoff=False)),
        ("csconfig_off", "a6xx_sp_cs_config", dict(enabled=False, nsamp=0, ntex=0, nuav=0)),
    ]
    for tag, reg, kw in wholes:
        row("qc_rv_" + tag, Q._qreg_exec("REG_" + reg.upper(), **kw))
    row("qc_rv_texconst0",
        8 | Q._qreg_exec("REG_A6XX_TEX_CONST_0", fmt=mesa.FMT6_32_32_32_32_FLOAT,
                         swiz_x=0, swiz_y=1, swiz_z=2, swiz_w=3))

    # ctz, ops_qcom.py:43. The zero input is omitted; see the module docstring.
    for v in (1, 2, 0x40, 0x1000, 0x80000000, 0x4000, 0x3F):
        row("qc_ctz_%08x" % v, Q.ctz(v))
    row("qc_ctz_nonzero", Q.ctz(4) >= 2 and Q.ctz(4096) >= 12)

    # parity, ops_qcom.py:45. The row key is the input, zero-padded the way the port prints it.
    for v in (0, 1, 2, 3, 4, 5, 7, 8, 15, 0x10, 0xFF, 0x100, 0x3FFF, 0x7F, 0x3FFFF):
        row("qc_parity_%05x" % v, Q.parity(v))

    # packet headers, ops_qcom.py:49 and :51. Operands are the mesa constants the
    # port's rows were built from; the header is whatever pkt*_hdr returns.
    for op, cnt in ((mesa.CP_WAIT_FOR_IDLE, 0), (mesa.CP_EVENT_WRITE, 3),
                    (mesa.CP_LOAD_STATE6_FRAG, 2), (mesa.CP_SET_MARKER, 1),
                    (mesa.CP_EXEC_CS, 4), (mesa.CP_RUN_OPENCL, 0),
                    (mesa.CP_REG_TO_MEM, 1), (mesa.CP_WAIT_REG_MEM, 5)):
        row("qc_pkt7_%d_%d" % (op, cnt), Q.pkt7_hdr(op, cnt) & 0xFFFFFFFF)
    for reg, cnt in ((mesa.REG_A6XX_SP_CS_NDRANGE_0, 12), (mesa.REG_A6XX_SP_CS_CNTL_0, 6),
                     (mesa.REG_A6XX_SP_CS_INSTR_SIZE, 1), (mesa.REG_A6XX_TPL1_MODE_CNTL, 1),
                     (mesa.REG_A6XX_SP_UPDATE_CNTL, 2), (mesa.REG_A6XX_SP_CS_CONFIG, 1)):
        row("qc_pkt4_%d_%d" % (reg, cnt), Q.pkt4_hdr(reg, cnt) & 0xFFFFFFFF)
    row("qc_pkt7_tag", mesa.CP_TYPE7_PKT)
    row("qc_pkt4_tag", mesa.CP_TYPE4_PKT)

    # _read_lib, ops_qcom.py:53. The fixture is the four words the port's comment names.
    lib = struct.pack("<4I", 0xDEADBEEF, 1, 0xFFFFFFFF, 0x80000000)
    for off in (0, 4, 8, 12):
        row("qc_rl_%d" % off, Q._read_lib(lib, off))
    row("qc_rl_words", ",".join(str(x) for x in struct.unpack("<4I", lib)))
    row("qc_rl_tail", ",".join(str(x) for x in struct.unpack("<2I", lib[8:])))

    # flag, ops_qcom.py:305. Shift and mask are getattr, not the port's literals.
    flags = (("KGSL_CONTEXT_PRIORITY", 8),
             ("KGSL_CONTEXT_PREEMPT_STYLE", kgsl.KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN),
             ("KGSL_MEMALIGN", 12),
             ("KGSL_CACHEMODE", kgsl.KGSL_CACHEMODE_UNCACHED))
    for nm, val in flags:
        short = nm[len("KGSL_"):]
        row("qc_flag_%s_shift" % short, getattr(kgsl, nm + "_SHIFT"))
        row("qc_flag_%s_mask" % short, getattr(kgsl, nm + "_MASK"))
        row("qc_flag_%s_of_%d" % (short, val), Q.flag(nm, val))
    row("qc_flag_clipped", Q.flag("KGSL_CONTEXT_PRIORITY", 4095))
    row("qc_flag_clipped_align", Q.flag("KGSL_MEMALIGN", 255))
    flag_names = [nm for nm, _ in flags]
    row("qc_flagname_0", flag_names[0])
    row("qc_flagname_3", flag_names[3])
    row("qc_flagix_malign", flag_names.index("KGSL_MEMALIGN"))

    # Constants the file actually reads, via getattr on the live modules.
    tree = ast.parse(open(SRC).read())
    const = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ("mesa", "kgsl"):
            mod = mesa if n.value.id == "mesa" else kgsl
            if hasattr(mod, n.attr) and isinstance(getattr(mod, n.attr), int):
                const[n.attr] = getattr(mod, n.attr)
    for nm in sorted(const):
        row("qc_c_%s" % nm, const[nm])


if __name__ == "__main__":
    main()
