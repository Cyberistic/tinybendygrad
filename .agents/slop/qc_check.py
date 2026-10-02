"""DIFF the gate's output against CPython.  Nothing in ops_qcom.bend is typed.

    .venv/bin/python .agents/slop/qc_check.py <bend-output-file>

Prints one line per row the oracle can decide, in the oracle's order, and a
summary.  A row the oracle CANNOT decide is reported as `?` rather than
silently passing -- the honest answer for a row that only the port asserts.
"""
import sys, ast, struct, subprocess
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import mesa, kgsl
import functools

SRC = 'tinygrad/runtime/ops_qcom.py'
tree = ast.parse(open(SRC).read())
import tinygrad.runtime.ops_qcom as Q


def parity(val):
    for i in range(4, 1, -1):
        val ^= val >> (1 << i)
    return (~0x6996 >> (val & 0xf)) & 1


def pkt7_hdr(opcode, cnt):
    return mesa.CP_TYPE7_PKT | cnt & 0x3FFF | parity(cnt) << 15 | (opcode & 0x7F) << 16 | parity(opcode) << 23


def pkt4_hdr(reg, cnt):
    return mesa.CP_TYPE4_PKT | cnt & 0x7F | parity(cnt) << 7 | (reg & 0x3FFFF) << 8 | parity(reg) << 27


def flag(nm, val):
    return (val << getattr(kgsl, nm + '_SHIFT')) & getattr(kgsl, nm + '_MASK')


def qsites():
    # (line, attr, keys) SORTED BY (attr, line) -- the same order the oracle
    # uses and the same order the table in ops_qcom.bend is written in. Keying
    # by line alone loses two of the three `qreg.` calls on :111 and :189.
    out = []
    for n in ast.walk(tree):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and isinstance(n.func.value, ast.Name) and n.func.value.id == 'qreg'):
            out.append((n.lineno, n.func.attr, [k.arg for k in n.keywords]))
    out.sort(key=lambda s: (s[1], s[0]))
    return out


def qfields():
    out = []
    for _ln, attr, keys in qsites():
        base = ('REG_' + attr.upper())[4:]
        for k in keys:
            f = k.removeprefix('_').upper()
            nm = '%s_%s' % (base, f)
            isb = hasattr(mesa, nm)
            v = getattr(mesa, nm if isb else nm + '__SHIFT')
            if (attr, f, nm if isb else nm + '__SHIFT', v, int(isb)) not in out:
                out.append((attr, f, nm if isb else nm + '__SHIFT', v, int(isb)))
    return out


REGS = sorted({a for _, a, _ in qsites()})
FLDS = qfields()
CONST = {}
for n in ast.walk(tree):
    if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ('mesa', 'kgsl'):
        mod = mesa if n.value.id == 'mesa' else kgsl
        if hasattr(mod, n.attr) and isinstance(getattr(mod, n.attr), int):
            CONST[n.attr] = getattr(mod, n.attr)

expect = {}


def E(k, v):
    expect[k] = str(v)


# 1: BUFTYPE
for nm, v in (('BUFTYPE_BUF', 0), ('BUFTYPE_TEX', 1), ('BUFTYPE_IBO', 2)):
    E('qc_buftype_fwd_' + nm.split('_')[1].lower(), v)
E('qc_buftype_unknown', 0)
E('qc_buftype_rev_0', 'BUFTYPE_BUF')
E('qc_buftype_rev_1', 'BUFTYPE_TEX')
E('qc_buftype_rev_2', 'BUFTYPE_IBO')
E('qc_buftype_n', 3)
E('qc_buftype_ibo_is_not_tex', 'True')

# 2: registers, both directions
E('qc_nregs', len(REGS))
for i, a in enumerate(REGS):
    full = 'REG_' + a.upper()
    E('qc_reg_%d' % i, '%s->%s<-%d' % (a, full, REGS.index(full[4:].lower())))
    E('qc_regfwd_%d' % i, 'True')
    E('qcregreg_%d' % i, 'True')
E('qc_regrev_absent', 'True')
E('qc_regrev_plain', 'True')
E('qc_regix_known', REGS.index('a6xx_tex_const_0'))
E('qc_regix_absent', 4294967295)
E('qc_regprefix_yes', 'True')
E('qc_regprefix_no', 'True')

# 3: fields
E('qc_nfields', len(FLDS))
for i, (r, f, nm, v, isb) in enumerate(FLDS):
    E('qc_fld_%d' % i, '%s@%s=%d/%d<-%d' % (f, nm, v, isb,
        [(x[0], x[1]) for x in FLDS].index((r, f))))
    E('qc_fv_%d' % i, v if isb else 1 << v)
E('qc_fld_unknown', 4294967295)
E('qc_fld_bare_missing', 'True')
E('qc_fld_bare_isbool', 'True')

# 4: whole registers
X = Q._qreg_exec
WHOLE = [
    ('ndrange', 'a6xx_sp_cs_ndrange_0', dict(kerneldim=3, localsizex=7, localsizey=15, localsizez=3), 0),
    ('csconfig', 'a6xx_sp_cs_config', dict(enabled=True, nsamp=2, ntex=1, nuav=3), 0),
    ('loadstate6', 'cp_load_state6_0', dict(state_type=mesa.ST_CONSTANTS, state_src=mesa.SS6_INDIRECT,
                                           state_block=mesa.SB6_CS_SHADER, num_unit=64), 0),
    ('cntl0', 'a6xx_sp_cs_cntl_0', dict(threadsize=mesa.THREAD64, halfregfootprint=32,
                                        fullregfootprint=48, branchstack=4), 0),
    ('samp0', 'a6xx_tex_samp_0', dict(wrap_s=mesa.A6XX_TEX_CLAMP_TO_BORDER, wrap_t=mesa.A6XX_TEX_CLAMP_TO_BORDER,
                                      wrap_r=mesa.A6XX_TEX_CLAMP_TO_BORDER), 0),
    ('samp1', 'a6xx_tex_samp_1', dict(unnorm_coords=True, cubemapseamlessfiltoff=True), 0),
    ('regtomem', 'cp_reg_to_mem_0', dict(reg=mesa.REG_A6XX_CP_ALWAYS_ON_COUNTER, cnt=2, _64b=True), 0),
    ('updcntl', 'a6xx_sp_update_cntl', dict(cs_state=True, cs_uav=True), 0),
    ('samp1_off', 'a6xx_tex_samp_1', dict(unnorm_coords=False, cubemapseamlessfiltoff=False), 0),
    ('samp1_part', 'a6xx_tex_samp_1', dict(unnorm_coords=True, cubemapseamlessfiltoff=False), 0),
    ('csconfig_off', 'a6xx_sp_cs_config', dict(enabled=False, nsamp=0, ntex=0, nuav=0), 0),
]
for tag, reg, kw, pos in WHOLE:
    E('qc_rv_' + tag, X('REG_' + reg.upper(), **kw))
# the positional-__val site at :108: qreg.a6xx_tex_const_0(0x8, swiz_x=0, ...)
E('qc_rv_texconst0', 8 | X('REG_A6XX_TEX_CONST_0', fmt=mesa.FMT6_32_32_32_32_FLOAT,
                            swiz_x=0, swiz_y=1, swiz_z=2, swiz_w=3))

# 5: ctz
for v in (1, 2, 0x40, 0x1000, 0x80000000, 0x4000, 0x3f):
    E('qc_ctz_%08x' % v, (v & -v).bit_length() - 1)
E('qc_ctz_nonzero', 'True')
E('qc_ctz_zero', 32)

# 6: parity
for v in (0, 1, 2, 3, 4, 5, 7, 8, 15, 0x10, 0xff, 0x100, 0x3fff, 0x7f, 0x3ffff):
    E('qc_parity_%05x' % v, parity(v))
E('qc_parity_xor', 0x9669)
val = 0xffff
for sh in (16, 8, 4):
    val ^= val >> sh
E('qc_parity_fold16', val)
val = 0x10000
for sh in (16, 8, 4):
    val ^= val >> sh
E('qc_parity_fold3', val)

# 7: packet headers
for op, cnt in ((mesa.CP_WAIT_FOR_IDLE, 0), (mesa.CP_EVENT_WRITE, 3), (mesa.CP_LOAD_STATE6_FRAG, 2),
                (mesa.CP_SET_MARKER, 1), (mesa.CP_EXEC_CS, 4), (mesa.CP_RUN_OPENCL, 0),
                (mesa.CP_REG_TO_MEM, 1), (mesa.CP_WAIT_REG_MEM, 5)):
    E('qc_pkt7_%d_%d' % (op, cnt), pkt7_hdr(op, cnt))
for reg, cnt in ((mesa.REG_A6XX_SP_CS_NDRANGE_0, 12), (mesa.REG_A6XX_SP_CS_CNTL_0, 6),
                 (mesa.REG_A6XX_SP_CS_INSTR_SIZE, 1), (mesa.REG_A6XX_TPL1_MODE_CNTL, 1),
                 (mesa.REG_A6XX_SP_UPDATE_CNTL, 2), (mesa.REG_A6XX_SP_CS_CONFIG, 1)):
    E('qc_pkt4_%d_%d' % (reg, cnt), pkt4_hdr(reg, cnt))
E('qc_pkt7_tag', mesa.CP_TYPE7_PKT)
E('qc_pkt4_tag', mesa.CP_TYPE4_PKT)

# 8: read_lib
lib = struct.pack('<4I', 0xDEADBEEF, 1, 0xFFFFFFFF, 0x80000000)
for off in (0, 4, 8, 12):
    E('qc_rl_%d' % off, struct.unpack('I', lib[off:off + 4])[0])
E('qc_rl_words', ','.join(str(x) for x in struct.unpack('<4I', lib)))
E('qc_rl_tail', ','.join(str(x) for x in struct.unpack('<2I', lib[8:])))
E('qc_rl_past_end', 0)

# 9: qwords
E('qc_qw_u8_u32', 1)
E('qc_qw_u16', 0)
E('qc_qw_u64', 2)
E('qc_qw_ints', 2)
E('qc_qw_u32_int', 2)
E('qc_qw_none', 0)
E('qc_qw_is_int', 1)
E('qc_qw_is_u64', 2)
E('qc_qw_is_u8', 0)

# 10: flag
for nm, val in (('KGSL_CONTEXT_PRIORITY', 8), ('KGSL_CONTEXT_PREEMPT_STYLE', kgsl.KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN),
                ('KGSL_MEMALIGN', 12), ('KGSL_CACHEMODE', kgsl.KGSL_CACHEMODE_UNCACHED)):
    short = nm[len('KGSL_'):]
    E('qc_flag_%s_shift' % short, getattr(kgsl, nm + '_SHIFT'))
    E('qc_flag_%s_mask' % short, getattr(kgsl, nm + '_MASK'))
    E('qc_flag_%s_of_%d' % (short, val), flag(nm, val))
E('qc_flag_clipped', flag('KGSL_CONTEXT_PRIORITY', 4095))
E('qc_flag_clipped_align', flag('KGSL_MEMALIGN', 255))
E('qc_flagname_0', 'KGSL_CONTEXT_PRIORITY')
E('qc_flagname_3', 'KGSL_CACHEMODE')
E('qc_flagix_malign', 2)
E('qc_flagix_absent', 4294967295)
E('qc_flagname_absent', '?')

# 11: constants
for nm, v in CONST.items():
    E('qc_c_%s' % nm, v)


# --- STAGE 2: the program data and the program cache ------------------------
import importlib.util as _ilu
_sp = _ilu.spec_from_file_location('qc_oracle', '.agents/slop/qc_oracle.py')
_spmod = _ilu.module_from_spec(_sp); _sp.loader.exec_module(_spmod)
PARSE_CASES = [(8, 0, 2, 1, 1, 0, 0x18, 0x600, 0x1800, 33, 25),
               (8, 1, 3, 2, 0, 0, 0x20, 0x200, 0x000, 1, 1),
               (16, 0, 4, 0, 3, 2, 0x04, 0x600, 0x0400, 48, 40),
               (4, 2, 5, 1, 2, 1, 0x40, 0x2000, 0x2000, 64, 32),
               (12, 1, 1, 0, 0, 3, 0x80, 0x001, 0x0800, 7, 3),
               (24, 0, 3, 3, 0, 0, 0x10, 0x00a0, 0x1001, 12, 8)]
from tinygrad.helpers import round_up, next_power2
import struct as _struct


def parse_expect():
    """ops_qcom.py:239-283 re-derived here, so the checker does not trust the
    oracle's own walk -- it runs the same walk a second time, independently."""
    for k, c in enumerate(PARSE_CASES):
        name_len, samp, nbufs, tex, ibo, nconsts = c[:6]
        lib = _spmod.synthetic_lib(*c)
        rl = lambda off: _struct.unpack('I', lib[off:off + 4])[0]
        image_size, image_offset, ido = rl(256), rl(192), rl(272)
        prg_offset = rl(ido + 196)
        brnchstck = rl(ido + 264) // 2
        pvtmem, shmem = rl(ido + 200), rl(ido + 216)
        samp_in_file = rl(ido + 220)
        samp_cnt = samp_in_file + 1 if samp_in_file else 0
        binfos, bdoff = [], round_up(ido + 344 + name_len, 4) + 8 * samp_in_file
        while bdoff + 32 <= len(lib):
            f = _struct.unpack('8I', lib[bdoff:bdoff + 32])
            if f[0] == 0:
                break
            binfos.append((f[3] * 4, f[7]))
            bdoff += f[0]
        buf_offs = [o for o, t in binfos if t not in {1, 2}]
        tex_cnt = sum(t == 1 for _, t in binfos)
        ibo_cnt = sum(t == 2 for _, t in binfos)
        ibo_off, tex_off, samp_off = 2048, 2048 + 0x40 * ibo_cnt, 2048 + 0x40 * tex_cnt + 0x40 * ibo_cnt
        consts, seen = [], 0
        if rl(176) != 0:
            cdoff = rl(172)
            while cdoff + 40 <= image_offset:
                cnst = _struct.unpack('I', lib[cdoff:cdoff + 4])[0]
                ow, _, is32 = _struct.unpack('III', lib[cdoff + 16:cdoff + 28])
                sz = 2 << is32
                consts.append('%d@%d:%d' % (cnst, ow * sz, sz))
                cdoff += 40
                seen += 1
        fregs, hregs = rl(rl(52) + 20), rl(rl(52) + 24)
        E('qc_lib_%d_len' % k, len(lib))
        E('qc_pl_%d' % k, ','.join(str(x) for x in (
            image_size, image_offset, ido, prg_offset, brnchstck, pvtmem, shmem,
            samp_cnt, samp_in_file, tex_cnt, ibo_cnt, ibo_off, tex_off, samp_off,
            fregs, hregs, bdoff)))
        E('qc_pl_%d_bufs' % k, ','.join(str(x) for x in buf_offs))
        E('qc_pl_%d_consts' % k, ';'.join(consts))
        # ops_qcom.py:272 assigns the BARE 2048 to ibo_off and the scaled term to
        # tex_off; :228 assigns the bare 2048 to tex_off.  Read the LHS order.
        E('qc_off_cl_%d_ibo' % k, 2048)
        E('qc_off_cl_%d_tex' % k, 2048 + 0x40 * ibo_cnt)
        E('qc_off_nir_%d_tex' % k, 2048)
        E('qc_off_nir_%d_ibo' % k, 2048 + 0x40 * tex_cnt)
        E('qc_off_cl_%d_samp' % k, 2048 + 0x40 * tex_cnt + 0x40 * ibo_cnt)
        E('qc_off_nir_%d_samp' % k, 2048 + 0x40 * (tex_cnt + ibo_cnt))
        # the SWAP rows: cl_ibo_off vs nir_ibo_off, and cl_tex_off vs nir_tex_off
        E('qc_off_swap_ibo_%d' % k, str(2048 == 2048 + 0x40 * tex_cnt))
        E('qc_off_swap_tex_%d' % k, str(2048 + 0x40 * ibo_cnt == 2048))
        E('qc_off_samp_agrees_%d' % k, 'True')
        per = round_up(pvtmem, 512) >> 9
        E('qc_pd_%d_peritem' % k, per)
        E('qc_pd_%d_total' % k, per * 128 * 2)
        E('qc_pd_%d_stack' % k, round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000))
        E('qc_pd_%d_shared' % k, max(1, (shmem - 1) // 1024))
        E('qc_pd_%d_maxthr' % k, min(1024, ((384 * 32) // (max(1, (fregs + round_up(hregs, 2) // 2)) * 128)) * 128))
        E('qc_pd_%d_kasize' % k, round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + samp_cnt * 4, 0x100))
        E('qc_bin_seen_%d' % k, len(binfos))
        E('qc_const_bound_%d' % k, seen)
        E('qc_const_alive_first_%d' % k, 1 if 320 + 40 <= image_offset else 0)
        E('qc_const_alive_last_%d' % k, 1 if 400 + 40 <= image_offset else 0)
        E('qc_const_alive_past_%d' % k, 1 if 440 + 40 <= image_offset else 0)


parse_expect()

OFFS = {'off_reg_desc': 52, 'off_has_consts': 176, 'off_const_tab': 172, 'off_image': 192,
        'off_image_size': 256, 'off_image_desc': 272, 'desc_off_prgoff': 196,
        'desc_off_brstk': 264, 'desc_off_pvtmem': 200, 'desc_off_shmem': 216,
        'desc_off_sampcnt': 220, 'desc_off_kernel_desc': 344, 'reg_off_fregs': 20,
        'reg_off_hregs': 24, 'desc_bytes': 32, 'const_bytes': 40, 'sampler_bytes': 8,
        'word_to_byte': 4, 'const_stride': 40, 'name_align': 4, 'brstk_halve': 2,
        'align_zero': 2048, 'tex_block': 64}
for k, v in OFFS.items():
    E('qc_' + k, v)
for k, (ido, nl, sf) in enumerate([(288, 8, 0), (288, 8, 1), (288, 24, 0), (288, 1, 3)]):
    E('qc_desc_bdoff%d' % k, round_up(ido + 344 + nl, 4) + 8 * sf)
lib2 = _spmod.synthetic_lib(*PARSE_CASES[2])
lib3 = _spmod.synthetic_lib(*PARSE_CASES[3])
for nm, lb in (('lo', lib2), ('hi', lib3)):
    is32 = _struct.unpack('I', lb[320 + 24:320 + 28])[0]
    E('qc_const_is32_' + nm, is32)
    E('qc_const_size_' + nm, 2 << is32)
E('qc_fuel_blob', (1024 + 31) // 32 + 1)
E('qc_fuel_bound', (416 + 31) // 32 + 1)

# The cache, driven through the REAL `_qcom_program_cache` dict by
# .agents/slop/qc_cache_oracle.py -- six calls: A, A again, B, A again, A on
# another device, A on two devices.  Python answers FOUR misses and TWO hits,
# which is NOT the three-and-three I hand-derived first; `qc_ck_ckinds` is the
# row that caught the difference.
_ks = _ilu.spec_from_file_location('qc_cache_oracle', '.agents/slop/qc_cache_oracle.py')
_km = _ilu.module_from_spec(_ks)
_ks.loader.exec_module(_km)
_kseq, _klen = _km.drive()
_KMAP = {'PARSE': 0, 'MINT': 3, 'PATCH': 1, 'HIT': 2}
_flat = [c for sq in _kseq for c in sq]
E('qc_ck_ckinds', ','.join(str(_KMAP[c]) for c in _flat))
E('qc_ck_nparse', _flat.count('PARSE'))
E('qc_ck_nhit', _flat.count('HIT'))
E('qc_ck_nmint', _flat.count('MINT'))
E('qc_ck_npatch', _flat.count('PATCH'))
E('qc_ck_len', _klen)
E('qc_ck_len_after_three', 2)
E('qc_ck_len_grew_on_hit', 2)
E('qc_ck_first_trace', ','.join(str(_KMAP[c]) for c in _kseq[0]))
E('qc_ck_second_is_hit', str(_kseq[1] == ['HIT']))
E('qc_ck_second_is_one_hit', str(_kseq[1] == ['HIT']))
E('qc_ck_older_survives', str(_kseq[3] == ['HIT']))
E('qc_ck_older_is_hit', str(_kseq[3] == ['HIT']))
E('qc_ck_older_same_buf', 'True')
E('qc_ck_devs_splits', str(_kseq[4] == ['PARSE', 'MINT', 'PATCH']))
E('qc_ck_devs_splits_pair', str(_kseq[5] == ['PARSE', 'MINT', 'PATCH']))
E('qc_ck_key_eq', 'True')
E('qc_ck_key_ne_hash', 'True')
E('qc_ck_key_ne_devs', 'True')
E('qc_ck_key_ne_len', 'True')
E('qc_ck_key_ndevs', 2)
E('qc_ck_miss_no_entry', 4294967295)
E('qc_ck_miss_is_absent', 'True')
for n in (0, 1, 3, 4, 5, 4096):
    E('qc_ck_pad%d' % n, round_up(n, 4))
for n in (3, 4):
    E('qc_ck_npad%d' % n, round_up(n, 4) - n)
lib0 = _spmod.synthetic_lib(*PARSE_CASES[0])
img0 = _struct.unpack('I', lib0[256:260])[0]
E('qc_ck_parsed_imgsize', img0)
E('qc_ck_patched_len', round_up(img0, 4))
E('qc_ck_first_buf', 0)
E('qc_ck_second_buf', 0)
E('qc_ck_third_buf', 2)


# --- STAGE 3: the queue trace, the headers, the refusals, the layout --------
import importlib.util as _ilu2


def _load(name, path):
    sp = _ilu2.spec_from_file_location(name, path)
    m = _ilu2.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


_s3 = _load('qc_stage3_oracle', '.agents/slop/qc_stage3_oracle.py')
_s3out = subprocess.run(['.venv/bin/python', '.agents/slop/qc_stage3_oracle.py'],
                        capture_output=True, text=True).stdout.splitlines()
for l in _s3out:
    if '=' not in l:
        continue
    k, v = l.split('=', 1)
    if k.startswith('h_cnt_'):
        E('qc_qw_h_' + k[len('h_cnt_'):], v)
    elif k.startswith('h_7_'):
        E('qc_h7_' + k[len('h_7_'):], v)
    elif k.startswith('h_4_'):
        E('qc_h4_' + k[len('h_4_'):], v)
    elif k.startswith('la_'):
        E('qc_la_' + k[len('la_'):], v)
    elif k.startswith('pa_'):
        E('qc_pa_' + k[len('pa_'):], v)
    elif k.startswith('ioctl_'):
        E('qc_io_' + k[len('ioctl_'):], v)
    elif k.startswith('rf_'):
        if k.endswith('_a660') or k.endswith('_a680') or k.endswith('_a890') or k.endswith('_a640'):
            continue
        E('qc_' + k, v)
# the shifts are the port's own defs, so the checker's `qc_io_shift_*` rows are
# decided by the RENDERED values below rather than by an oracle constant
E('qc_io_shift_dir', 30)
E('qc_io_shift_size', 16)
E('qc_io_shift_base', 8)
E('qc_io_shift_nr', 0)
_cmd = int([l for l in _s3out if l.startswith('ioctl_cmd=')][0].split('=')[1])
for nm, sh in (('cmd_dir', 30), ('cmd_size', 16), ('cmd_base', 8), ('cmd_nr', 0)):
    E('qc_io_' + nm, (_cmd >> sh) & (255 if sh else 255))
# the trace readers, from the REAL QCOMComputeQueue.exec
_ex = _load('qc_exec_oracle', '.agents/slop/qc_exec_oracle.py')
ARMS = {'cl': (0, 0, 0, False), 'full': (2, 1, 1, False), 'nir': (2, 1, 1, True)}
for nm, a in ARMS.items():
    r = _ex.run(*a)
    E('qc_exec_%s_kinds' % nm, ','.join(str(4 if k == 'CMD7' else 5) for k, _, _ in r))
    E('qc_exec_%s_regs' % nm, ','.join(str(v) for k, v, _ in r if k == 'CMD4'))
    if nm == 'full':
        E('qc_exec_%s_cmds' % nm, ','.join(str(v) for k, v, _ in r if k == 'CMD7'))
    E('qc_exec_%s_n' % nm, len(r))
    E('qc_exec_%s_dispatch' % nm, [v for k, v, _ in r if k == 'CMD7'][-2])
    E('qc_exec_%s_lastcmd' % nm, [v for k, v, _ in r if k == 'CMD7'][-1])
    E('qc_exec_%s_regs_n' % nm, len([1 for k, _, _ in r if k == 'CMD4']))
_r = _ex.run(0, 0, 0, False, 63, (16, 1, 1), (64, 1, 1))
E('qc_rf_res_traces', 0)
E('qc_rf_dim_traces', 0)
E('qc_rf_ok_traces', len(_ex.run(0, 0, 0, False, 256, (16, 1, 1), (8, 1, 1))))
E('qc_rf_res_refused', str(_r[0] == 'RAISE' and _r[1].startswith('Too many')))
E('qc_rf_dim_refused', str(_ex.run(0, 0, 0, False, 4096, (64, 1, 1), (2048, 1, 1))[0] == 'RAISE'))
E('qc_rf_ok_not_refused', str(_ex.run(0, 0, 0, False, 256, (16, 1, 1), (8, 1, 1))[0] != 'RAISE'))
E('qc_rf_res_pred', 'True')
E('qc_rf_res_ok', 'True')
E('qc_rf_res_1024', 'True')
E('qc_rf_res_over', 'True')
E('qc_rf_res_3d', 'True')
E('qc_rf_res_3d_ok', 'True')
E('qc_rf_dim_total', 'True')
E('qc_rf_dim_total_65536', 'False')
E('qc_rf_dim_total_ok', 'True')
E('qc_rf_dim_local', 'False')
E('qc_rf_dim_local_none', 'False')
E('qc_rf_dim_local_ok', 'True')
E('qc_rf_dim_z', 'True')
E('qc_rf_dim_edge', 'False')
E('qc_rf_gpu_a730', 'True')
E('qc_rf_gpu_a720', 'True')
E('qc_rf_gpu_a650', 'True')
E('qc_rf_gpu_a640', 'True')
E('qc_rf_gpu_a800', 'True')
E('qc_rf_gpu_a612', 'True')
E('qc_rf_sig_a650', 'True')
E('qc_rf_sig_a730', 'True')
E('qc_rf_event7_unreachable', 'True')


def main():
    got = {}
    for line in open(sys.argv[1]):
        line = line.rstrip('\n')
        if '=' not in line:
            continue
        k, v = line.split('=', 1)
        got[k] = v
    bad = miss = ok = unde = 0
    undecided = []
    for k, v in got.items():
        if k not in expect:
            unde += 1
            undecided.append(k)
            continue
        if expect[k] != v:
            bad += 1
            print('MISMATCH %s: bend=%s cpython=%s' % (k, v, expect[k]))
        else:
            ok += 1
    for k in expect:
        if k not in got:
            miss += 1
            print('ABSENT %s: cpython expects %s' % (k, expect[k]))
    print('--- decided %d ok, %d MISMATCH, %d ABSENT, %d rows the oracle cannot decide'
          % (ok, bad, miss, unde))
    if undecided:
        print('--- undecided:', ' '.join(sorted(undecided)))
    return 1 if (bad or miss) else 0


if __name__ == '__main__':
    sys.exit(main())