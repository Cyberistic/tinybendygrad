"""STAGE 3 oracles: the cmd/reg headers, the cache-flush trace, the exec
register sequence, the submit ioctl word, and the KERNEL ARGUMENT LAYOUT.

The last one is the contract five other units are porting, so it gets its own
`layout` section driven through the REAL `layout_args`/`pack_args`.
"""
import sys, struct
sys.path.insert(0, '.')


def p(*a):
    print(*a)


def hdr():
    import tinygrad.runtime.ops_qcom as Q
    p7, p4, par = Q.pkt7_hdr, Q.pkt4_hdr, Q.parity
    # the word count, :57/:59 -- one UOp's words are itemsize//4, a bare int is 1
    for nm, xs in (('u32', [(4, True)]), ('u16', [(2, True)]), ('u8', [(1, True)]),
                   ('u64', [(8, True)]), ('two_u32', [(4, True), (4, True)]),
                   ('int', [(0, False)]), ('u32_int', [(4, True), (0, False)]),
                   ('none', []), ('u16u8', [(2, True), (1, True)])):
        n = sum(sz // 4 if u else 1 for sz, u in xs)
        p('h_cnt_%s=%d' % (nm, n))
    # the header of every `cmd`/`reg` ops_qcom.py actually issues, with its count
    from tinygrad.runtime.autogen import mesa
    for nm, op, cnt in (('setmarker', mesa.CP_SET_MARKER, 1),
                        ('waitidle', mesa.CP_WAIT_FOR_IDLE, 0),
                        ('eventwrite', mesa.CP_EVENT_WRITE, 3),
                        ('loadconst', mesa.CP_LOAD_STATE6_FRAG, 2),
                        ('exec', mesa.CP_EXEC_CS, 4),
                        ('runcl', mesa.CP_RUN_OPENCL, 0),
                        ('eventinv', mesa.CP_EVENT_WRITE, 1),
                        ('memwrites', mesa.CP_WAIT_MEM_WRITES, 0),
                        ('regtomem', mesa.CP_REG_TO_MEM, 1),
                        ('waitregmem', mesa.CP_WAIT_REG_MEM, 5)):
        p('h_7_%s=%d' % (nm, p7(op, cnt)))
    for nm, r, cnt in (('updatecntl', mesa.REG_A6XX_SP_UPDATE_CNTL, 2),
                       ('cs_tsize', mesa.REG_A6XX_SP_CS_TSIZE, 1),
                       ('cs_usize', mesa.REG_A6XX_SP_CS_USIZE, 1),
                       ('mode_cntl', mesa.REG_A6XX_SP_MODE_CNTL, 1),
                       ('perfctr', mesa.REG_A6XX_SP_PERFCTR_SHADER_MASK, 1),
                       ('tpl1', mesa.REG_A6XX_TPL1_MODE_CNTL, 1),
                       ('dbgeco', mesa.REG_A6XX_TPL1_DBG_ECO_CNTL, 1),
                       ('ndrange', mesa.REG_A6XX_SP_CS_NDRANGE_0, 12),
                       ('cntl0', mesa.REG_A6XX_SP_CS_CNTL_0, 6),
                       ('cntl1', mesa.REG_A6XX_SP_CS_CNTL_1, 3),
                       ('regprogid', mesa.REG_A6XX_SP_REG_PROG_ID_0, 5),
                       ('pvtmemstk', mesa.REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET, 1),
                       ('instrsize', mesa.REG_A6XX_SP_CS_INSTR_SIZE, 1),
                       ('sampbase', mesa.REG_A6XX_SP_CS_SAMPLER_BASE, 1),
                       ('texmembase', mesa.REG_A6XX_SP_CS_TEXMEMOBJ_BASE, 1),
                       ('uavbase', mesa.REG_A6XX_SP_CS_UAV_BASE, 1),
                       ('csconfig', mesa.REG_A6XX_SP_CS_CONFIG, 1),
                       ('constcfg0', mesa.REG_A6XX_SP_CS_CONST_CONFIG_0, 2)):
        p('h_4_%s=%d' % (nm, p4(r, cnt)))


def layout():
    """hcq2.py:74-83 -- `layout_args` and `pack_args`, the REAL ones."""
    from tinygrad.runtime.support.hcq2 import layout_args, pack_args
    from tinygrad.uop.ops import UOp
    from tinygrad.dtype import dtypes
    for nm, xs in (('empty', []), ('one', [4]), ('three', [4, 4, 4]),
                   ('six', [4] * 6), ('mix', [4, 2, 4])):
        args = layout_args([UOp.const(x, dtypes.uint32) for x in xs], 2048)
        p('la_%s=%s' % (nm, ','.join(str(o) for o, _ in args)))
    # `pack_args`: sorted by offset, one BINARY pad per GAP, then a final pad.
    for nm, pairs, size in (('tight', [(2048, 4), (2052, 4)], 2560),
                            ('gap', [(2048, 4), (2064, 4)], 2560),
                            ('big_gap', [(0, 4), (64, 4)], 128),
                            ('unsorted', [(2064, 4), (2048, 4)], 2560),
                            ('huge_tail', [(2048, 4)], 4096)):
        words = pack_args([(o, UOp.const(o, dtypes.uint32)) for o, _ in pairs], size)
        pads = [len(w.arg) for w in words if isinstance(w.arg, bytes)]
        p('pa_%s=%s' % (nm, ','.join(str(x) for x in pads)))


def submit():
    """ops_qcom.py:202-203 -- the ioctl command word."""
    from tinygrad.runtime.autogen import kgsl
    import ctypes
    idir, base, nr, struct_t = kgsl.IOCTL_KGSL_GPU_COMMAND.args
    sz = ctypes.sizeof(struct_t)
    p('ioctl_dir=%d' % idir)
    p('ioctl_base=%d' % base)
    p('ioctl_nr=%d' % nr)
    p('ioctl_size=%d' % sz)
    p('ioctl_cmd=%d' % ((idir << 30) | (sz << 16) | (base << 8) | nr))


def refusals():
    """ops_qcom.py:118-120 and :332 and :79 -- the four raises."""
    from math import ceil

    def bad_resources(mt, ls):
        from tinygrad.helpers import prod
        return mt < prod(ls)

    def bad_dims(gs, ls):
        z = [65536, 65536, 65536]
        y = [1024, 1024, 1024]
        return any(g * l > mx for g, l, mx in zip(gs, ls, z)) and any(l > mx for l, mx in zip(ls, y))
    for nm, mt, ls in (('fit', 256, [64, 1, 1]), ('tight', 64, [64, 1, 1]),
                       ('over', 63, [64, 1, 1]), ('over1', 1024, [1025, 1, 1]),
                       ('three', 1024, [64, 64, 64])):
        p('rf_res_%s=%d' % (nm, 1 if bad_resources(mt, ls) else 0))
        p('rf_res_%s=%d' % (nm, 1 if bad_resources(mt, ls) else 0))
    for nm, gs, ls in (('small', [16, 1, 1], [8, 1, 1]),
                       ('huge_ls', [64, 1, 1], [2048, 1, 1]),
                       ('huge_ls_y', [64, 1, 1], [8, 2048, 1]),
                       ('huge_ls_z', [64, 1, 1], [8, 1, 2048]),
                       ('over_total', [65536, 1, 1], [2, 1, 1]),
                       ('over_total2', [1, 65536, 1], [1, 2, 1]),
                       ('ok_big', [65535, 1, 1], [1, 1, 1])):
        p('rf_dim_%s=%d' % (nm, 1 if bad_dims(gs, ls) else 0))
    # :332 `if self.gpu_id[:2] >= (7, 3): raise`
    for nm, gid in (('a730', (7, 3, 0)), ('a650', (6, 5, 0)), ('a640', (6, 4, 0)),
                    ('a660', (6, 6, 0)), ('a680', (6, 8, 0)), ('a890', (8, 9, 0))):
        p('rf_gpu_%s=%d' % (nm, 1 if gid[:2] >= (7, 3) else 0))
    # :74 `if self.dev.gpu_id[:2] < (7, 3)` -- the SIGNAL guard, which is the
    # complement for every gpu the device accepts and the ONLY supported one.
    for nm, gid in (('a730', (7, 3, 0)), ('a650', (6, 5, 0)), ('a640', (6, 4, 0))):
        p('rf_sig_%s=%d' % (nm, 1 if gid[:2] < (7, 3) else 0))
    # :122 cast_int(x, ceil) -- the global/local multiply
    for nm, g, l in (('even', 64, 4), ('odd', 65, 4), ('odd2', 7, 3), ('one', 1, 1)):
        p('rf_mp_%s=%d' % (nm, ceil(g * l) if isinstance(g * l, float) else int(g * l)))
        p('rf_ceil_%s=%d' % (nm, ceil(g)))


def arch():
    """ops_qcom.py:338 -- `("a%d%d%d" + IMAGE_SUFFIX) % gpu_id`."""
    for nm, gid, img in (('650', (6, 5, 0), 0), ('640', (6, 4, 0), 0),
                         ('660', (6, 6, 0), 0), ('680', (6, 8, 0), 0),
                         ('650i', (6, 5, 0), 1), ('640i', (6, 4, 1), 1),
                         ('612', (6, 1, 2), 0), ('630', (6, 3, 0), 1)):
        p('arch_%s=a%d%d%d%s' % (nm, gid[0], gid[1], gid[2],
                                 ',IMAGE_PITCH_ALIGNMENT=64' if img else ''))


def flags():
    """ops_qcom.py:317-319 -- the context flags, OR-ed in Python's order."""
    import tinygrad.runtime.ops_qcom as Q
    from tinygrad.runtime.autogen import kgsl
    def flag(nm, val):
        return (val << getattr(kgsl, nm + '_SHIFT')) & getattr(kgsl, nm + '_MASK')
    for prio in (8, 0, 1, 15, 16, 255, 4095):
        f = (kgsl.KGSL_CONTEXT_PREAMBLE | kgsl.KGSL_CONTEXT_PWR_CONSTRAINT
             | kgsl.KGSL_CONTEXT_NO_FAULT_TOLERANCE | kgsl.KGSL_CONTEXT_NO_GMEM_ALLOC
             | flag('KGSL_CONTEXT_PRIORITY', prio)
             | flag('KGSL_CONTEXT_PREEMPT_STYLE', kgsl.KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN))
        p('fl_prio_%d=%d' % (prio, f))
    # :355-356 the allocator flags
    for nm, unc in (('plain', 0), ('unc', 1)):
        f = flag('KGSL_MEMALIGN', 12) | kgsl.KGSL_MEMFLAGS_USE_CPU_MAP
        if unc:
            f |= flag('KGSL_CACHEMODE', kgsl.KGSL_CACHEMODE_UNCACHED)
        p('al_%s=%d' % (nm, f))
    p('al_align_hint=%d' % (1 << 12))
    # :365 the external-pointer page alignment
    for ptr, size in ((0x1234, 100), (0x1000, 100), (0xfff, 4096), (0x40, 64)):
        p('al_aligned_%x_%d=%d|%d' % (ptr, size, ptr & ~0xfff,
                                      ((size + (ptr & 0xfff) + 0xfff) // 0x1000) * 0x1000))


if __name__ == '__main__':
    w = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if w in ('all', 'hdr'):
        hdr()
    if w in ('all', 'layout'):
        layout()
    if w in ('all', 'submit'):
        submit()
    if w in ('all', 'rf'):
        refusals()
    if w in ('all', 'arch'):
        arch()
    if w in ('all', 'fl'):
        flags()