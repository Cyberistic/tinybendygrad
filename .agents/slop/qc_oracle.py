"""CPython oracle for tinybendygrad/runtime/ops_qcom.bend.

Every `py=` expectation in the gate is printed by THIS file and nothing is typed
by hand.  Usage:  .venv/bin/python .agents/slop/qc_oracle.py            (all)
                        .venv/bin/python .agents/slop/qc_oracle.py bit      (one)
"""
import sys, ast
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import mesa, kgsl

SRC = 'tinygrad/runtime/ops_qcom.py'
tree = ast.parse(open(SRC).read())


def p(*a):
    print(*a)


def bit():
    # :20 BUFTYPE_*
    p('buftype_buf=%d' % 0)
    p('buftype_tex=%d' % 1)
    p('buftype_ibo=%d' % 2)

    # :43 ctz
    for v in (1, 2, 0x40, 0x1000, 0x80000000, 0x4000, 0x3f):
        p('ctz_%08x=%d' % (v, (v & -v).bit_length() - 1))

    # :45-47 parity
    for v in (0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 0xff, 0x100, 0x3fff, 0x7f, 0x3ffff):
        p('parity_%05x=%d' % (v, parity(v)))

    # :49 pkt7_hdr / :51 pkt4_hdr
    p('CP_TYPE7_PKT=%d' % mesa.CP_TYPE7_PKT)
    p('CP_TYPE4_PKT=%d' % mesa.CP_TYPE4_PKT)
    for op, cnt in ((mesa.CP_WAIT_FOR_IDLE, 0), (mesa.CP_EVENT_WRITE, 3),
                    (mesa.CP_LOAD_STATE6_FRAG, 2), (mesa.CP_SET_MARKER, 1),
                    (mesa.CP_EXEC_CS, 4), (mesa.CP_RUN_OPENCL, 0),
                    (mesa.CP_REG_TO_MEM, 1), (mesa.CP_WAIT_REG_MEM, 5)):
        p('pkt7_%d_%d=%d' % (op, cnt, pkt7_hdr(op, cnt)))
    for reg, cnt in ((mesa.REG_A6XX_SP_CS_NDRANGE_0, 12), (mesa.REG_A6XX_SP_CS_CNTL_0, 6),
                     (mesa.REG_A6XX_SP_CS_INSTR_SIZE, 1), (mesa.REG_A6XX_TPL1_MODE_CNTL, 1),
                     (mesa.REG_A6XX_SP_UPDATE_CNTL, 2), (mesa.REG_A6XX_SP_CS_CONFIG, 1)):
        p('pkt4_%d_%d=%d' % (reg, cnt, pkt4_hdr(reg, cnt)))

    # :303 flag() over the four kgsl names ops_qcom.py uses
    for nm, val in (('KGSL_CONTEXT_PRIORITY', 8),
                    ('KGSL_CONTEXT_PREEMPT_STYLE', kgsl.KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN),
                    ('KGSL_MEMALIGN', 12),
                    ('KGSL_CACHEMODE', kgsl.KGSL_CACHEMODE_UNCACHED)):
        sh = getattr(kgsl, nm + '_SHIFT')
        mk = getattr(kgsl, nm + '_MASK')
        p('flag_%s_shift=%d' % (nm, sh))
        p('flag_%s_mask=%d' % (nm, mk))
        p('flag_%s_of_%d=%d' % (nm, val, (val << sh) & mk))


def parity(val):
    for i in range(4, 1, -1):
        val ^= val >> (1 << i)
    return (~0x6996 >> (val & 0xf)) & 1


def pkt7_hdr(opcode, cnt):
    return mesa.CP_TYPE7_PKT | cnt & 0x3FFF | parity(cnt) << 15 | (opcode & 0x7F) << 16 | parity(opcode) << 23


def pkt4_hdr(reg, cnt):
    return mesa.CP_TYPE4_PKT | cnt & 0x7F | parity(cnt) << 7 | (reg & 0x3FFFF) << 8 | parity(reg) << 27


def table():
    """The qreg table, both directions, AS THE PORT WRITES IT."""
    # NOT keyed by lineno: :111, :189, :225, :257 and :258 each carry TWO or
    # THREE qreg calls on ONE line, and keying by line silently dropped
    # a6xx_tex_const_7, cp_exec_cs_2, cp_exec_cs_3 and every second field of a
    # sampler.  MEASURED: the first run of this oracle reported NREGS=30 and
    # NFIELDS=55 where the AST walk reports 34 sites.
    sites = []
    for n in ast.walk(tree):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and isinstance(n.func.value, ast.Name) and n.func.value.id == 'qreg'):
            sites.append((n.lineno, n.func.attr, [k.arg for k in n.keywords],
                          [ast.unparse(a) for a in n.args]))
    sites.sort(key=lambda s: (s[1], s[0]))
    regs = sorted({a for _, a, _, _ in sites})
    p('NREGS=%d' % len(regs))
    for i, a in enumerate(regs):
        full = 'REG_' + a.upper()
        assert hasattr(mesa, full), full
        p('reg_%d=%s|%s' % (i, a, full))
        # REVERSE direction, ops_qcom.py:41 `name[4:].lower()`
        assert full[4:].lower() == a
    fields = []
    for lineno, attr, keys, args in sites:
        base = ('REG_' + attr.upper())[4:]
        for k in keys:
            f = k.removeprefix('_').upper()
            nm = '%s_%s' % (base, f)
            isb = hasattr(mesa, nm)
            shn = nm + '__SHIFT'
            ish = hasattr(mesa, shn)
            assert isb != ish, (nm, isb, ish)
            v = getattr(mesa, nm if isb else shn)
            fields.append((attr, f, nm if isb else shn, v, isb))
    uniq = []
    for f5 in fields:
        if f5 not in uniq:
            uniq.append(f5)
    p('NFIELDS=%d' % len(uniq))
    for i, (r, f, nm, v, isb) in enumerate(uniq):
        p('fld_%d=%s|%s|%s|%d|%d' % (i, r, f, nm, v, int(isb)))
    # the positional __val sites, which use NO field at all
    for lineno, attr, keys, args in sites:
        if args:
            p('val_%s=%s' % (attr, ','.join(args)))


def progdata():
    """ops_qcom.py:232-237 -- the six DERIVED sizes, as CPython computes them."""
    from tinygrad.helpers import round_up, next_power2
    for pvtmem, shmem, fregs, hregs, tex_cnt, ibo_cnt, samp_cnt in (
            (0, 0, 1, 1, 0, 0, 0), (256, 0, 12, 8, 0, 0, 0),
            (512, 1024, 32, 24, 1, 2, 2), (1024, 2048, 48, 40, 3, 1, 4),
            (4096, 5120, 64, 32, 5, 5, 6), (600, 300, 7, 3, 2, 3, 1)):
        per_item = round_up(pvtmem, 512) >> 9
        total = per_item * 128 * 2
        stack = round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000)
        shared = max(1, (shmem - 1) // 1024)
        maxthr = min(1024, ((384 * 32) // (max(1, (fregs + round_up(hregs, 2) // 2)) * 128)) * 128)
        ksz = round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + samp_cnt * 4, 0x100)
        p('pd_%d_%d_%d_%d_%d_%d_%d=%d|%d|%d|%d|%d|%d' % (
            pvtmem, shmem, fregs, hregs, tex_cnt, ibo_cnt, samp_cnt,
            per_item, total, stack, shared, maxthr, ksz))
        p('pd_offs_%d_%d=%d|%d|%d' % (tex_cnt, ibo_cnt, 2048, 2048 + 0x40 * tex_cnt, 2048 + 0x40 * (tex_cnt + ibo_cnt)))
        p('pd_offs_cl_%d_%d=%d|%d|%d' % (tex_cnt, ibo_cnt, 2048, 2048 + 0x40 * ibo_cnt, 2048 + 0x40 * tex_cnt + 0x40 * ibo_cnt))


def cache():
    """ops_qcom.py:287-291 -- the cache key and the image padding."""
    from tinygrad.helpers import round_up
    for name, img in (('k0', 3), ('k1', 4), ('k2', 7), ('k3', 64), ('k4', 1024), ('k5', 4095)):
        p('pad_%s=%d' % (name, round_up(img, 4)))
    # the key is (prg.src[3].arg, devs) -- a (bytes, tuple[str,...]) pair
    p('key_shape=2')
    p('devs_one=1')


def refs():
    """Every mesa/kgsl CONSTANT ops_qcom.py reads, MEASURED."""
    consts = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ('mesa', 'kgsl'):
            mod = mesa if n.value.id == 'mesa' else kgsl
            nm = n.attr
            if hasattr(mod, nm):
                v = getattr(mod, nm)
                if isinstance(v, int):
                    consts.add((n.value.id, nm, v))
    for m, nm, v in sorted(consts):
        p('c_%s_%s=%d' % (m, nm, v))
    p('NCONST=%d' % len(consts))


def vals():
    """The `qreg` VALUE for every field, and for nine whole call sites.

    The per-field rows exist because a field's own contribution is the unit a
    wrong table entry corrupts; the nine call-site rows exist because OR-ing
    several of them is where a precedence mistake would hide.
    """
    import functools
    import tinygrad.runtime.ops_qcom as Q
    X = Q._qreg_exec
    sites = []
    for n in ast.walk(tree):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and isinstance(n.func.value, ast.Name) and n.func.value.id == 'qreg'):
            sites.append((n.lineno, n.func.attr, [k.arg for k in n.keywords]))
    fields = []
    for lineno, attr, keys in sites:
        base = ('REG_' + attr.upper())[4:]
        for k in keys:
            f = k.removeprefix('_').upper()
            nm = '%s_%s' % (base, f)
            isb = hasattr(mesa, nm)
            v = getattr(mesa, nm if isb else nm + '__SHIFT')
            fields.append((attr, f, isb, v))
    uniq = []
    for f4 in fields:
        if f4 not in uniq:
            uniq.append(f4)
    # fixture value 1 for a non-bool field, and the bit itself for a bool one
    for i, (r, f, isb, v) in enumerate(uniq):
        p('fv_%d=%d' % (i, v if isb else 1 << v))
    # nine whole call sites, with values CPython substitutes for the symbols
    whole = [
        ('a6xx_sp_cs_ndrange_0', dict(kerneldim=3, localsizex=7, localsizey=15, localsizez=3)),
        ('a6xx_tex_const_0', dict(fmt=mesa.FMT6_32_32_32_32_FLOAT, swiz_x=0, swiz_y=1, swiz_z=2, swiz_w=3)),
        ('a6xx_sp_cs_config', dict(enabled=True, nsamp=2, ntex=1, nuav=3)),
        ('cp_load_state6_0', dict(state_type=mesa.ST_CONSTANTS, state_src=mesa.SS6_INDIRECT,
                                  state_block=mesa.SB6_CS_SHADER, num_unit=64)),
        ('a6xx_sp_cs_cntl_0', dict(threadsize=mesa.THREAD64, halfregfootprint=32,
                                  fullregfootprint=48, branchstack=4)),
        ('a6xx_tex_samp_0', dict(wrap_s=mesa.A6XX_TEX_CLAMP_TO_BORDER, wrap_t=mesa.A6XX_TEX_CLAMP_TO_BORDER,
                                 wrap_r=mesa.A6XX_TEX_CLAMP_TO_BORDER)),
        ('a6xx_tex_samp_1', dict(unnorm_coords=True, cubemapseamlessfiltoff=True)),
        ('cp_reg_to_mem_0', dict(reg=mesa.REG_A6XX_CP_ALWAYS_ON_COUNTER, cnt=2, _64b=True)),
        ('a6xx_sp_update_cntl', dict(cs_state=True, cs_uav=True)),
    ]
    for nm, kw in whole:
        p('rv_%s=%d' % (nm, X('REG_' + nm.upper(), **kw)))


def readlib():
    """ops_qcom.py:53 `struct.unpack("I", lib[off:off+4])[0]`."""
    import struct
    lib = struct.pack('<4I', 0xDEADBEEF, 0x00000001, 0xFFFFFFFF, 0x80000000)
    for off in (0, 4, 8, 12):
        p('rl_%d=%d' % (off, struct.unpack('I', lib[off:off + 4])[0]))
    p('rl_bytes=' + ','.join(str(b) for b in lib))


def qwords():
    """ops_qcom.py:57,59 -- itemsize // 4 per UOp and 1 per bare value."""
    from tinygrad.dtype import dtypes
    for nm, xs in (('u8_u32', [(dtypes.uint8, True), (dtypes.uint32, True)]),
                   ('u16', [(dtypes.uint16, True)]),
                   ('u64', [(dtypes.uint64, True)]),
                   ('ints', [(None, False), (None, False)]),
                   ('u32_int', [(dtypes.uint32, True), (None, False)]),
                   ('none', [])):
        p('qw_%s=%d' % (nm, sum(x.itemsize // 4 if u else 1 for x, u in xs)))


def synthetic_lib(name_len, samp_in_file, nbufs, tex, ibo, nconsts,
                  image_size=0x18, pvtmem=0x600, shmem=0x1800, fregs=33, hregs=25):
    """A stand-in for the CL shader binary `_parse_lib` walks.

    ops_qcom.py:241-283 reads a fixed set of offsets and then WALKS the kernel
    argument descriptors and the constant descriptors. A synthetic blob is the
    only way to gate the walks, and every field is put somewhere the walk must
    find it, so a port that mis-offsets by one descriptor answers differently.
    """
    import struct
    from tinygrad.helpers import round_up
    buf = bytearray(0x400)
    def put(off, val):
        buf[off:off + 4] = struct.pack('<I', val)
    put(0x34, 0x180)          # reg_desc_off
    put(0xb0, 1 if nconsts else 0)   # "do we have constants"
    put(0xac, 0x140)          # const descriptor table
    # image_offset bounds the CONSTANT walk (`cdoff + 40 <= image_offset`), so it
    # is 0x1a0: two of the three const descriptors at 0x140 fit and the third
    # does not. A blob where every constant fits would not test the bound.
    put(0xc0, 0x1a0)          # image_offset
    put(0x100, image_size)    # image_size
    put(0x110, 0x120)         # image_desc_off
    put(0x120 + 0xc4, 0x30)   # prg_offset
    put(0x120 + 0x108, 0x0a)  # branchstack (halved by the source)
    put(0x120 + 0xc8, pvtmem)
    put(0x120 + 0xd8, shmem)
    put(0x120 + 0xdc, samp_in_file)
    put(0x180 + 0x14, fregs)
    put(0x180 + 0x18, hregs)
    # the constant descriptors: 40 bytes each, (cnst, _, _, off_words, _, _, _, is32)
    for i in range(nconsts):
        c = 0x140 + 40 * i
        struct.pack_into('<I', buf, c, 0x1000 + i)
        struct.pack_into('<III', buf, c + 16, 2 + i, 0, 1)
    # the buffer descriptors: 32 bytes each, (length, _, _, offset_words, _, _, _, typ)
    bdoff = round_up(0x120 + 0x158 + name_len, 4) + 8 * samp_in_file
    assert bdoff < 0x400 - 32, bdoff
    order = ([2] * ibo) + ([1] * tex) + [0] * nbufs
    for j, typ in enumerate(order):
        o = bdoff + 32 * j
        struct.pack_into('<8I', buf, o, 64, 0, 0, 4 + j, 0, 0, 0, typ)
    # the terminating zero-length descriptor the walk breaks on
    struct.pack_into('<8I', buf, bdoff + 32 * len(order), 0, 0, 0, 0, 0, 0, 0, 0)
    return bytes(buf)


def parse_lib():
    """ops_qcom.py:239-283, run on the synthetic blob."""
    import struct
    from tinygrad.helpers import round_up, next_power2
    BUFTYPE_TEX, BUFTYPE_IBO = 1, 2
    # (name_len, samp_in_file, nbufs, tex, ibo, nconsts, image_size, pvtmem, shmem, fregs, hregs)
    cases = [(8, 0, 2, 1, 1, 0, 0x18, 0x600, 0x1800, 33, 25),
             (8, 1, 3, 2, 0, 0, 0x20, 0x200, 0x000, 1, 1),
             (16, 0, 4, 0, 3, 2, 0x04, 0x600, 0x0400, 48, 40),
             (4, 2, 5, 1, 2, 1, 0x40, 0x2000, 0x2000, 64, 32),
             (12, 1, 1, 0, 0, 3, 0x80, 0x001, 0x0800, 7, 3),
             (24, 0, 3, 3, 0, 0, 0x10, 0x00a0, 0x1001, 12, 8)]
    for k, c in enumerate(cases):
        name_len, samp, nbufs, tex, ibo, nconsts = c[:6]
        lib = synthetic_lib(*c)
        rl = lambda off: struct.unpack('I', lib[off:off + 4])[0]
        image_size = rl(0x100)
        image_offset = rl(0xc0)
        image_desc_off = rl(0x110)
        prg_offset, brnchstck = rl(image_desc_off + 0xc4), rl(image_desc_off + 0x108) // 2
        pvtmem, shmem = rl(image_desc_off + 0xc8), rl(image_desc_off + 0xd8)
        samp_cnt = samp_in_file = rl(image_desc_off + 0xdc)
        samp_cnt = samp_cnt + 1 if samp_cnt else 0
        binfos, bdoff = [], round_up(image_desc_off + 0x158 + name_len, 4) + 8 * samp_in_file
        while bdoff + 32 <= len(lib):
            length, _, _, offset_words, _, _, _, typ = struct.unpack('8I', lib[bdoff:bdoff + 32])
            if length == 0:
                break
            binfos.append((offset_words * 4, typ))
            bdoff += length
        buf_offs = [off for off, typ in binfos if typ not in {BUFTYPE_TEX, BUFTYPE_IBO}]
        tex_cnt = sum(typ is BUFTYPE_TEX for _, typ in binfos)
        ibo_cnt = sum(typ is BUFTYPE_IBO for _, typ in binfos)
        # :272 -- NOTE the order: ibo_off, tex_off, samp_off. The NIR branch at
        # :228 is tex_off, ibo_off, samp_off with the two 0x40 terms SWAPPED.
        ibo_off, tex_off, samp_off = 2048, 2048 + 0x40 * ibo_cnt, 2048 + 0x40 * tex_cnt + 0x40 * ibo_cnt
        consts_info = []
        if rl(0xb0) != 0:
            cdoff = rl(0xac)
            while cdoff + 40 <= image_offset:
                cnst = struct.unpack('I', lib[cdoff:cdoff + 4])[0]
                offset_words, _, is32 = struct.unpack('III', lib[cdoff + 16:cdoff + 28])
                sz = 2 << is32
                consts_info.append((cnst, offset_words * sz, sz))
                cdoff += 40
        reg_desc_off = rl(0x34)
        fregs, hregs = rl(reg_desc_off + 0x14), rl(reg_desc_off + 0x18)
        p('pl_%d=%s' % (k, '|'.join(str(x) for x in (
            image_size, image_offset, image_desc_off, prg_offset, brnchstck,
            pvtmem, shmem, samp_cnt, samp_in_file, tex_cnt, ibo_cnt,
            ibo_off, tex_off, samp_off, fregs, hregs, bdoff))
            + '|' + ','.join(str(x) for x in buf_offs)
            + '|' + ';'.join('%d@%d:%d' % c for c in consts_info)))
        per_item = round_up(pvtmem, 512) >> 9
        p('pd_%d=%d|%d|%d|%d|%d|%d' % (k, per_item, per_item * 128 * 2,
            round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000),
            max(1, (shmem - 1) // 1024),
            min(1024, ((384 * 32) // (max(1, (fregs + round_up(hregs, 2) // 2)) * 128)) * 128),
            round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + samp_cnt * 4, 0x100)))
        # the NIR counterpart of the same three offsets, for the ASYMMETRY row
        p('nir_%d=%d|%d|%d' % (k, 2048, 2048 + 0x40 * tex_cnt, 2048 + 0x40 * (tex_cnt + ibo_cnt)))
    # the six synthetic blobs as bend list literals
    for k, c in enumerate(cases):
        lib = synthetic_lib(*c)
        w = wrap(['%d' % b for b in lib], '  ')
        p('LIB_%d=' % k)
        for line in w.split('\n'):
            p('  ' + line)
        p('LEN_%d=%d' % (k, len(lib)))


def wrap(items, indent, width=86):
    lines, cur = [], indent
    for it in items:
        piece = it + ','
        if len(cur) + len(piece) + 1 > width:
            lines.append(cur.rstrip()); cur = indent
        cur += (' ' if cur.strip() else '') + piece
    if cur.strip():
        lines.append(cur.rstrip())
    return '\n'.join(lines)


def cachekey():
    """ops_qcom.py:285-291 -- the key, the hit, and the image padding."""
    p('key_parts=2')
    for n in (0, 1, 3, 4, 7, 16, 4095):
        from tinygrad.helpers import round_up
        p('pad_%d=%d' % (n, round_up(n, 4)))


if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if which in ('all', 'bit'):
        bit()
    if which in ('all', 'table'):
        table()
    if which in ('all', 'vals'):
        vals()
    if which in ('all', 'rl'):
        readlib()
    if which in ('all', 'qw'):
        qwords()
    if which in ('all', 'parse'):
        parse_lib()
    if which in ('all', 'ck'):
        cachekey()
    if which in ('all', 'prog'):
        progdata()
    if which in ('all', 'cache'):
        cache()
    if which in ('all', 'refs'):
        refs()