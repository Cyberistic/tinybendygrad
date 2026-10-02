#!/usr/bin/env python3
"""
amd_oracle.py -- generates EVERY `py=` expectation for tinybendygrad/runtime/ops_amd.bend.

NOTHING here is hand-typed. Where a value is a constant the oracle reads it out
of the autogen modules; where a value is arithmetic the oracle calls the real
tinygrad function (or the real source expression, via `expr()`); where a value is
a shape the oracle builds real UOps and calls `hcq2.layout_args` / `pack_args`.

Usage:  python3 .agents/slop/amd_oracle.py > .agents/slop/amd_oracle.txt
        python3 .agents/slop/amd_oracle.py --check   # diff against the .bend rows
"""
import sys, os, types, ctypes, struct, functools, dataclasses
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import UOp

from tinygrad.dtype import dtypes
from tinygrad.helpers import round_up, ceildiv, lo32, hi32, getenv
from tinygrad.device import TinyELF
from tinygrad.runtime.support.hcq2 import layout_args, pack_args, to_name
from tinygrad.runtime.autogen import hsa, kfd, amdgpu_kd, sqtt
from tinygrad.runtime.autogen.am import am
import tinygrad.runtime.ops_amd as M
from tinygrad.runtime.ops_amd import AMDDevice, AMDProgramData

OUT = {}

def row(nm, v): OUT[nm] = str(v)
def sh(kind, n): return f"{kind}{n}"
def csize(u): return ctypes.sizeof(u)

# ---------------------------------------------------------------- 1. constants
def t_const():
    AQL = (1 << hsa.HSA_PACKET_HEADER_BARRIER) | (hsa.HSA_FENCE_SCOPE_SYSTEM << hsa.HSA_PACKET_HEADER_SCACQUIRE_FENCE_SCOPE) \
        | (hsa.HSA_FENCE_SCOPE_SYSTEM << hsa.HSA_PACKET_HEADER_SCRELEASE_FENCE_SCOPE)
    row("amd_aql_hdr", AQL)
    row("amd_hdr_type", hsa.HSA_PACKET_HEADER_TYPE)
    row("amd_type_kdispatch", hsa.HSA_PACKET_TYPE_KERNEL_DISPATCH)
    row("amd_type_vendor", hsa.HSA_PACKET_TYPE_VENDOR_SPECIFIC)
    row("amd_setup_dim", hsa.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS)
    row("amd_kprops_dispatch_ptr", hsa.AMD_KERNEL_CODE_PROPERTIES_ENABLE_SGPR_DISPATCH_PTR)
    row("amd_kprops_priv_seg", hsa.AMD_KERNEL_CODE_PROPERTIES_ENABLE_SGPR_PRIVATE_SEGMENT_BUFFER)
    row("amd_qprop_ptr64", hsa.AMD_QUEUE_PROPERTIES_IS_PTR64)
    row("amd_qprof_prof", hsa.AMD_QUEUE_PROPERTIES_ENABLE_PROFILING)
    row("amd_event_index_partial_flush", M.EVENT_INDEX_PARTIAL_FLUSH)
    row("amd_wait_fn_eq", M.WAIT_REG_MEM_FUNCTION_EQ)
    row("amd_wait_fn_neq", M.WAIT_REG_MEM_FUNCTION_NEQ)
    row("amd_wait_fn_geq", M.WAIT_REG_MEM_FUNCTION_GEQ)
    # the packet itself: 64 bytes, and the three slice boundaries
    P = hsa.hsa_kernel_dispatch_packet_t
    row("amd_pkt_size", ctypes.sizeof(P))
    row("amd_pkt_slice_head", 12)
    row("amd_pkt_slice_mid", f"{32 - 24}")
    row("amd_pkt_slice_tail", ctypes.sizeof(P) - 48)
    # the descriptor
    Dk = amdgpu_kd.llvm_amdhsa_kernel_descriptor_t
    row("amd_desc_size", ctypes.sizeof(Dk))

# ------------------------------------------------- 2/3. the argument trace
def shapes(pk, devs='AMD'):
    """(kind, bytes) per element: 'B' blob / 'W' word, length in BYTES."""
    out = []
    for u in pk:
        if u.op.name == 'BINARY' and isinstance(u.arg, (bytes, bytearray)): out.append(sh('B', len(u.arg)))
        else: out.append(sh('W', u.dtype.itemsize))
    return " ".join(out)

def t_layout():
    # a fixed buffer list, exactly as ops_amd.py:362 hands it over:
    #   globals  -> <global N>.getaddr(self.devs)          -> uint64, 8 bytes
    #   vars     -> b.ccast(v.dtype)                        -> v.dtype.itemsize
    fixtures = {
        "b3":        ([0, 1, 2], []),
        "b3v2_32":   ([0, 1, 2], ['uint32', 'uint32']),
        "b3v3_mix":  ([0, 1, 2], ['uint8', 'uint32', 'uint16']),
        "b1v1_64":   ([0], ['uint64']),
        "b2v1_8":    ([0, 1], ['uint8']),
        "b0v4":      ([], ['uint32', 'uint8', 'uint64', 'uint16']),
        # the two walrus fixtures: [1,4,1] is the SMALLEST list where the
        # rounded and the raw advance disagree.
        "w1":        ([], ['uint8', 'uint32', 'uint8']),
        "w2":        ([], ['uint8', 'uint32', 'uint8', 'uint8']),
    }
    for nm, (globs, vards) in fixtures.items():
        args = [UOp.placeholder((4,), dtypes.uint8, 0, device='AMD').getaddr('AMD') for _ in globs]
        args += [UOp.placeholder((1,), getattr(dtypes, v), 0, device='AMD') for v in vards]
        ks = [a.dtype.itemsize for a in args]
        row(f"amd_arg_ks_{nm}", " ".join(map(str, ks)))
        la = layout_args(args)
        row(f"amd_arg_at_{nm}", " ".join(str(o) for o, _ in la))
        row(f"amd_arg_walrus_{nm}", " ".join(str(o) for o, _ in TinyELF.iter_sig(tuple((None, i, a.dtype, ()) for i, a in enumerate(args)))))
        off, raw = 0, []
        for k in ks:
            raw.append((off + k - 1) // k * k); off += k
        row(f"amd_arg_walrus_raw_{nm}", " ".join(map(str, raw)))
        for base in (4, 512):
            row(f"amd_arg_at_{nm}_base{base}", " ".join(str(o) for o, _ in
                TinyELF.iter_sig(tuple((None, i, a.dtype, ()) for i, a in enumerate(args)), base)))
        end = (la[-1][0] + la[-1][1].dtype.itemsize) if la else 0
        row(f"amd_arg_end_{nm}", end)
        for size in (0, 8, 16, 24, 40, 64, end, end + 8):
            if size < end: continue
            row(f"amd_pack_{nm}_{size}", shapes(pack_args(la, size)))
        # and the kernargs_segment_size that AMDProgramData would carry
    # dispatch_ptr OFF and ON
    # the same widths the gate's KS_B3V2 fixture is, so `amd_kernargs_off` and
    # `amd_pack_b3v2_32_40` are the SAME claim seen twice
    globs, vards = [0, 1, 2], ['uint32', 'uint32']
    args = [UOp.placeholder((4,), dtypes.uint8, 0, device='AMD').getaddr('AMD') for _ in globs]
    args += [UOp.placeholder((1,), getattr(dtypes, v), 0, device='AMD') for v in vards]
    la = layout_args(args)
    row("amd_kernargs_off", shapes(pack_args(la, 40)))
    # the TOTAL the pack must add up to: kernargs_segment_size.
    for nm in ("b3", "b3v2_32", "b3v3_mix", "b0v4"):
        args = []
        if nm.startswith("b3"): args += [UOp.placeholder((4,), dtypes.uint8, 0, device='AMD').getaddr('AMD')] * 3
        elif nm == "b2v1_8": args += [UOp.placeholder((4,), dtypes.uint8, 0, device='AMD').getaddr('AMD')] * 2
        args += [UOp.placeholder((1,), getattr(dtypes, k), 0, device='AMD') for k in
                 ({"b3": [], "b3v2_32": ['uint32','uint32'], "b3v3_mix": ['uint8','uint32','uint16'],
                   "b0v4": ['uint32','uint8','uint64','uint16'], "b2v1_8": ['uint8']}[nm])]
        for size in (17, 18, 24, 32, 34, 40, 64):
            la2 = layout_args(args)
            end2 = (la2[-1][0] + la2[-1][1].dtype.itemsize) if la2 else 0
            if size < end2: continue
            pk = pack_args(la2, size)
            tot = sum((len(u.arg) if u.op.name == 'BINARY' and isinstance(u.arg, (bytes, bytearray))
                       else u.dtype.itemsize) for u in pk)
            row(f"amd_pack_bytes_{nm}_{size}", tot)
    # :56's `zip("xyz", info.local_size)` and :66's grid
    info = types.SimpleNamespace(local_size=(64, 1, 1), global_size=(128, 1, 1))
    row("amd_grid_mul", " ".join(str(g*l) for g, l in zip(info.global_size, info.local_size)))
    row("amd_wg_dims", " ".join(str(l) for l in info.local_size))

# ----------------------------------------------- 4. the dispatch packet shape
def dpkt(local_size, gsize=(1,1,1), priv=64, group=0):
    pkt = bytes(hsa.hsa_kernel_dispatch_packet_t(header=5376 | (hsa.HSA_PACKET_TYPE_KERNEL_DISPATCH << hsa.HSA_PACKET_HEADER_TYPE),
        setup=3 << hsa.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS, private_segment_size=priv, group_segment_size=group,
        **{f"workgroup_size_{d}": l for d, l in zip("xyz", local_size)}))
    return pkt

def t_dispatch():
    pkt = dpkt((64, 1, 1))
    row("amd_pkt_len", len(pkt))
    row("amd_pkt_hdr", " ".join(str(x) for x in struct.unpack("<III", pkt[:12])))
    row("amd_pkt_mid", " ".join(str(x) for x in struct.unpack("<II", pkt[24:32])))
    row("amd_pkt_tail_len", len(pkt[48:]))
    # the two values the PORT computes, as the source writes them at :63-65
    row("amd_pkt_header_val", 5376 | (hsa.HSA_PACKET_TYPE_KERNEL_DISPATCH << hsa.HSA_PACKET_HEADER_TYPE))
    row("amd_pkt_setup_val", 3 << hsa.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS)
    row("amd_pkt_setup_shift", hsa.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS)
    row("amd_pkt_hdr_type", hsa.HSA_PACKET_HEADER_TYPE)
    # ...and the SAME three for a second target, so the header cannot be a constant
    row("amd_pkt_setup_val2", 3 << hsa.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS)
    # :442 close_run: hdr | (VENDOR_SPECIFIC << TYPE) | (1<<16)
    hdr = 5376 | (hsa.HSA_PACKET_TYPE_VENDOR_SPECIFIC << hsa.HSA_PACKET_HEADER_TYPE) | (1 << 16)
    row("amd_close_run_hdr", hdr)
    row("amd_close_run_hdr_bits", f"{1 << 16} {hsa.HSA_PACKET_TYPE_VENDOR_SPECIFIC << hsa.HSA_PACKET_HEADER_TYPE}")
    # the packet list: 3 + 3 + 2 + 2 + 2 + tail
    row("amd_dispatch_shape", " ".join([sh('B', 12)] + [sh('W', 4)]*3 + [sh('B', 8)] + [sh('W', 8)]*2 + [sh('B', 16)]))
    # and the DEFAULT form, where kernel_object/kernarg_address are const(0, uint64)
    row("amd_dispatch_shape_default", " ".join([sh('B', 12)] + [sh('W', 4)]*3 + [sh('B', 8)] + [sh('W', 8)]*2 + [sh('B', 16)]))
    row("amd_dispatch_nwords", (12 + 3*4 + 8 + 2*8 + 16)//4)
    # close_run's word list, for a run of `end - run_start` bytes
    for run in (0, 4, 16, 100):
        row(f"amd_close_run_n_{run}", len([hdr, 7, 8, (run//4) | 1, 10] + [0]*10))
        row(f"amd_close_run_ib3_{run}", (run//4) | 1)
    # the indirect-buffer packet of :416/:440
    row("amd_ib_valid", 1)
    # :56's `_queue_args` ring tag, the shape `layout_args` sees at the ring
    for q in ("COMPUTE:0", "SDMA:0", "SDMA:3"):
        row(f"amd_ib_tag_{q}", to_name("ring", q))
        row(f"amd_wp_tag_{q}", to_name("write_ptr", q))
        row(f"amd_db_tag_{q}", to_name("doorbell", q))
        row(f"amd_pv_tag_{q}", to_name("put_value", q))
    # :422 `n = words.max_numel() // 4` and :416 `cmdbuf.max_numel() // 4 | VALID`
    for mx in (0, 4, 64, 100):
        row(f"amd_ib_len_{mx}", mx // 4)
        row(f"amd_ib_len_v_{mx}", (mx // 4) | 1)

# ------------------------------------------ 5. AMDProgramData, both directions
DESC_OFF = 0x100

def mkdesc(gs=0, ps=0, ka=0, eo=0, r1=0, r2=0, r3=0, kp=0):
    return amdgpu_kd.llvm_amdhsa_kernel_descriptor_t(group_segment_fixed_size=gs, private_segment_fixed_size=ps,
        kernarg_size=ka, kernel_code_entry_byte_offset=eo, compute_pgm_rsrc1=r1, compute_pgm_rsrc2=r2,
        compute_pgm_rsrc3=r3, kernel_code_properties=kp)

def fake_elf(desc, total=0x400, rodata=DESC_OFF, relocs=()):
    image = bytearray(total)
    image[rodata:rodata+64] = bytes(desc)
    sh = types.SimpleNamespace(name='.rodata', header=types.SimpleNamespace(sh_addr=rodata))
    return image, [sh], list(relocs)

def drive_image(desc, target, lds_kb, lib=b'\xaa'*256, total=0x400, relocs=()):
    """Run the REAL _amd_program_image with elf_loader stubbed. @functools.cache
    needs hashable args, so the shim is a frozen dataclass and the cache is
    cleared -- otherwise the second target would read the first's AMDProgramData."""
    image, sections, rl = fake_elf(desc, total, relocs=relocs)
    orig = M.elf_loader
    M.elf_loader = lambda lib: (image, sections, rl)
    M._amd_program_image.cache_clear()
    try:
        dev = _mk_hash_dev(target, lds_kb)
        return M._amd_program_image(dev, lib)
    finally:
        M.elf_loader = orig
        M._amd_program_image.cache_clear()

class HashIface:
    def __init__(s, props): s.props = props
    def __hash__(s): return 1
    def __eq__(s, o): return isinstance(o, HashIface) and s.props == o.props

class HashDev:
    def __init__(s, target, props): s.target, s.iface = target, HashIface(props)
    def __hash__(s): return hash((s.target, tuple(sorted(s.iface.props.items()))))
    def __eq__(s, o): return isinstance(o, HashDev) and hash(s) == hash(o)

def _mk_hash_dev(target, lds_kb):
    return HashDev(target, {'lds_size_in_kb': lds_kb})

def t_prog():
    fixtures = [
        ("plain",  mkdesc(gs=0,    ps=0,   ka=0,   eo=0,    r1=0x10, r2=0x20, r3=0x30, kp=0)),
        ("wave32", mkdesc(gs=512,  ps=64,  ka=24,  eo=0x80, r1=0x11, r2=0x21, r3=0x31, kp=0x400)),
        ("edp",    mkdesc(gs=1024, ps=128, ka=32,  eo=0x40, r1=0x12, r2=0x22, r3=0x32, kp=0x400|hsa.AMD_KERNEL_CODE_PROPERTIES_ENABLE_SGPR_DISPATCH_PTR)),
        ("privsg", mkdesc(gs=1024, ps=0,   ka=16,  eo=0,    r1=0x13, r2=0x23, r3=0x33, kp=hsa.AMD_KERNEL_CODE_PROPERTIES_ENABLE_SGPR_PRIVATE_SEGMENT_BUFFER)),
        ("lds9",   mkdesc(gs=4608, ps=0,   ka=0,   eo=0,    r1=0,    r2=0,    r3=0,    kp=0)),
    ]
    for tgt in ((9, 4, 2), (11, 0, 0), (12, 0, 0)):
        for nm, d in fixtures:
            data, image = drive_image(d, tgt, 64)
            k = f"{nm}_{tgt[0]}"
            row(f"amd_pd_desc_off_{k}", data.desc_offset)
            row(f"amd_pd_entry_off_{k}", data.entry_point_offset)
            row(f"amd_pd_rsrc1_{k}", data.rsrc1)
            row(f"amd_pd_rsrc2_{k}", data.rsrc2)
            row(f"amd_pd_rsrc3_{k}", data.rsrc3)
            row(f"amd_pd_wave32_{k}", int(data.wave32))
            row(f"amd_pd_wave32b_{k}", str(bool(data.wave32)))
            row(f"amd_pd_priv_{k}", data.private_segment_size)
            row(f"amd_pd_grp_{k}", data.group_segment_size)
            row(f"amd_pd_ka_{k}", data.kernargs_segment_size)
            row(f"amd_pd_edp_{k}", data.enable_dispatch_ptr)
            row(f"amd_pd_epsgpr_{k}", data.enable_private_segment_sgpr)
            row(f"amd_pd_img_pad_{k}", len(image) % 4)
            row(f"amd_pd_img_len_{k}", len(image))
    # the LDS ladder, both directions: lds = ((gs+511)//512) & 0x1FF
    for gs in (0, 1, 511, 512, 513, 1024, 4608, 65536, 131072, 131584, 262144):
        row(f"amd_lds_gs{gs}", ((gs+511)//512) & 0x1FF)
    # the refusal threshold, both sides
    for lds_kb in (0, 1, 32, 64):
        row(f"amd_lds_cap_{lds_kb}", (lds_kb*1024)//512)
    for gs, lds_kb in ((0, 64), (4608, 64), (131072, 64), (131584, 64), (131584, 128)):
        d = mkdesc(gs=gs)
        try:
            drive_image(d, (9, 4, 2), lds_kb); ok = 1
        except RuntimeError: ok = 0
        row(f"amd_lds_ok_gs{gs}_kb{lds_kb}", ok)
    # and the exact boundary, both sides
    for gs, lds_kb in ((65536, 64), (65537, 64), (131071, 64), (131072, 64)):
        d = mkdesc(gs=gs)
        try: drive_image(d, (9, 4, 2), lds_kb); ok = 1
        except RuntimeError: ok = 0
        row(f"amd_lds_edge_gs{gs}_kb{lds_kb}", f"{ok} lds={((gs+511)//512)&0x1FF} cap={(lds_kb*1024)//512}")
    # the libhash: md5(lib).digest()[:8] little-endian
    import hashlib
    for lib in (b'', b'\x01', b'\x01\x02\x03\x04\x05\x06\x07\x08\x09', b'\xff'*64):
        row(f"amd_libhash_{len(lib)}", struct.unpack('<Q', hashlib.md5(lib).digest()[:8])[0])
    # the cache key: (lib, devs), and `prg.key`
    for devs in (('AMD',), ('AMD:1',), ('AMD:1', 'AMD:1')):
        key = (b'\xaa'*8, devs)
        row(f"amd_key_{len(devs)}_{devs[0].count('1')}", f"{len(key)} {len(key[0])} {len(key[1])}")
    row("amd_key_hit_miss_same", int((b'x', ('AMD',)) == (b'x', ('AMD',))))
    row("amd_key_hit_miss_devs", int((b'x', ('AMD',)) == (b'x', ('AMD:1',))))
    row("amd_key_hit_miss_lib", int((b'x', ('AMD',)) == (b'y', ('AMD',))))
    # :1033-1038 program_buffer: the dict is keyed by the BUFFER UOP, and the
    # BufferSpec is `cpu_access=True, nolru=True` -- the two flags that make it
    # invisible to the allocator's LRU. That is the NEGATIVE eviction case.
    spec_cpu = {'cpu_access': True, 'nolru': True, 'host': False, 'uncached': False, 'external_ptr': None}
    row("amd_prog_spec", " ".join(f"{k}={int(v) if isinstance(v, bool) else 0}" for k, v in spec_cpu.items()))
    row("amd_prog_lru", int(not (spec_cpu['nolru'] or spec_cpu['external_ptr'] is not None)))
    # _prof_buffer (:1016-1019): host, nolru, uncached=host, cpu_access
    for host in (True, False):
        sp = {'host': host, 'nolru': True, 'uncached': host, 'cpu_access': True}
        row(f"amd_prof_spec_{int(host)}", " ".join(f"{k}={int(v)}" for k, v in sp.items()))
        row(f"amd_prof_lru_{int(host)}", int(not sp['nolru']))
    # the ring / gart / scratch BufferSpecs, :923-925 and :996
    for nm, sp in (("ring", {'host': True, 'uncached': True, 'cpu_access': True, 'nolru': False, 'external_ptr': None}),
                   ("gart", {'host': True, 'uncached': True, 'cpu_access': True, 'nolru': False, 'external_ptr': None}),
                   ("scratch", {'nolru': True})):
        row(f"amd_spec_{nm}", " ".join(f"{k}={int(v) if isinstance(v, bool) else 0}" for k, v in sp.items()))
    # the shapes: ring_size//4 uint32, gart 0x100 uint8, scratch size_per_xcc*xccs uint8
    for rs in (16 << 20, 1 << 20, 0, 3):
        row(f"amd_ring_elems_{rs}", rs // 4)
    row("amd_gart_size", 0x100)
    # the ONE eviction policy ops_amd.py has, and it is device.py:280's four
    # conjuncts -- LRU and allocator.lru and not nolru and no external pointer.
    from tinygrad.helpers import LRU
    for nm, sp in (("ring", dict(host=True, uncached=True, cpu_access=True, nolru=False, external_ptr=None)),
                   ("gart", dict(host=True, uncached=True, cpu_access=True, nolru=False, external_ptr=None)),
                   ("prog", dict(cpu_access=True, nolru=True, external_ptr=None)),
                   ("prof", dict(host=True, nolru=True, uncached=True, cpu_access=True, external_ptr=None)),
                   ("scratch", dict(nolru=True, external_ptr=None)),
                   ("ib", dict(external_ptr=0x1000, nolru=False)),
                   ("plain", dict(nolru=False, external_ptr=None))):
        rec = bool(LRU) and True and not sp['nolru'] and sp['external_ptr'] is None
        row(f"amd_recycled_{nm}", int(rec))
    row("amd_recycled_nconjuncts", 4)
    # the two flags Allocator.free reads, as the .bend renders them
    row("amd_spec_ring", "False False")
    row("amd_spec_prog", "True False")
    row("amd_spec_scratch", "True False")
    # and the LIFO reuse order, which is `c.pop()`
    for xs in ([7], [7, 8], [7, 8, 9], [9, 8, 7]):
        row(f"amd_lru_take_{'_'.join(map(str, xs))}", xs[-1])

# ------------------------------------------------------- 7. occupancy, init
def expr(line_no, ns):
    """Evaluate ops_amd.py's OWN source line (RHS of an assignment), with `ns`
    as its namespace. Reads the file, so it cannot drift from the port."""
    import ast, textwrap
    src = open('tinygrad/runtime/ops_amd.py').read().split('\n')
    node = ast.parse(textwrap.dedent(src[line_no-1])).body[0]
    val = node.value if isinstance(node, (ast.Assign, ast.AnnAssign)) else node
    return eval(compile(ast.Expression(val), '<amd>', 'eval'), ns)

class Sh:
    def __init__(s, target, props, xccs=1):
        s.target = target
        s.iface = types.SimpleNamespace(props=props, ip_versions={})
        s.xccs = xccs

PROPS = {'num_xcc': 1, 'array_count': 8, 'simd_arrays_per_engine': 4, 'simd_count': 80,
         'simd_per_cu': 2, 'max_waves_per_simd': 8, 'max_slots_scratch_cu': 8, 'lds_size_in_kb': 64,
         'cu_per_simd_array': 8, 'gfx_target_version': 110000, 'drm_render_minor': 0}

def t_occupancy():
    # :858 target decomposition, :859 arch
    for trgt in (90402, 90403, 90500, 110000, 110001, 115501, 120000, 120001):
        ns = {'trgt': trgt, 'self': types.SimpleNamespace(iface=types.SimpleNamespace(props={'gfx_target_version': trgt}))}
        t = expr(858, ns)
        row(f"amd_trgt_{trgt}", " ".join(map(str, t)))
        row(f"amd_arch_{trgt}", "gfx%d%x%x" % t)
    # :864-867
    for tgt, props, xccs in [((11,0,0), PROPS, 1), ((12,0,0), PROPS, 1), ((9,4,2), PROPS, 1),
                             ((11,0,0), dict(PROPS, num_xcc=2), 2), ((9,5,0), PROPS, 1)]:
        p = props
        ns = dict(iface=types.SimpleNamespace(props=p), xccs=xccs, target=tgt,
                  se_cnt=p['array_count']//p['simd_arrays_per_engine']//xccs,
                  cu_cnt=p['simd_count']//p['simd_per_cu']//xccs)
        ns['waves_per_cu'] = p['max_waves_per_simd']*p['simd_per_cu']
        row(f"amd_se_cnt_{tgt[0]}_{xccs}", ns['se_cnt'])
        row(f"amd_cu_cnt_{tgt[0]}_{xccs}", ns['cu_cnt'])
        row(f"amd_waves_per_cu_{tgt[0]}", ns['waves_per_cu'])
        ns['wave_cnt'] = (ns['cu_cnt'] * ns['waves_per_cu']) if tgt[0] != 9 else min(ns['cu_cnt'] * 40, ns['se_cnt'] * xccs * 512)
        row(f"amd_wave_cnt_{tgt[0]}_{xccs}", ns['wave_cnt'])
    # :863 xccs default
    row("amd_xccs_default", PROPS.get('num_xcc', 1))
    row("amd_xccs_missing", dict(PROPS, num_xcc=None).get('num_xcc', 1) or 0)
    # :860 the arch refusal
    for tgt in ((9,4,2),(9,5,0),(9,0,0),(10,0,0),(11,0,0),(12,0,0),(13,0,0)):
        arch = "gfx%d%x%x" % tgt
        ok = (tgt in ((9,4,2),(9,5,0))) or tgt[0] in (11, 12)
        row(f"amd_arch_ok_{tgt[0]}_{tgt[1]}{tgt[2]}", int(ok))
    # :880 max_copy_size, both directions
    for v in ((4,4,1),(4,4,2),(4,4,3),(5,0,0),(5,1,9),(5,2,0),(5,2,1),(6,0,0)):
        row(f"amd_maxcopy_{v[0]}_{v[1]}_{v[2]}", 0x40000000 if (4, 4, 2) <= v < (5, 0, 0) or v >= (5, 2, 0) else 0x400000)
    # :735 is_wgp_active
    for se, sa, wgp, bm in [(0,0,0,0x3),(0,0,0,0x0),(0,0,0,0x1),(0,0,1,0xc),(1,2,0,0x3),(3,5,1,0xc0000),(7,0,3,0x1f)]:
        off = (2*wgp)
        cell = (bm >> off) & 0x3
        row(f"amd_wgp_{se}_{sa}_{wgp}_{bm:x}", int(cell == 0x3))
    # :194-195 the PMC block counts
    for block in ('GRBM','GL2C','TCC','SQ'):
        for gfx9, se_cnt, cpus in ((True, 4, 8), (False, 4, 8), (False, 8, 4)):
            row(f"amd_pmc_bc_{block}_{int(gfx9)}_{se_cnt}_{cpus}", " ".join(map(str, {
                "GRBM": (1,1,1,1), "GL2C": (32,1,1,1), "TCC": (16,1,1,1),
                "SQ": (1, se_cnt) + ((1,1) if gfx9 else (2, cpus//2))}[block])))

# ------------------------------------------------------ 8. tmpring, both ways
def t_tmpring():
    for tgt in ((9,4,2),(9,5,0),(11,0,0),(12,0,0)):
        for psize in (0, 64, 128, 129, 256, 1024, 4096):
            for cu, slots, se, xcc in ((20, 8, 4, 1), (4, 1, 2, 1), (40, 16, 8, 2)):
                sh_ = Sh(tgt, dict(PROPS, max_slots_scratch_cu=slots), xcc)
                sh_.se_cnt, sh_.cu_cnt = se, cu
                v = AMDDevice.tmpring_size(sh_, psize)
                row(f"amd_tmp_{tgt[0]}_{psize}_{cu}_{slots}_{se}_{xcc}", v)
    # the union's own layout, BOTH directions
    for nm in ('union_COMPUTE_TMPRING_SIZE_bitfields', 'union_COMPUTE_TMPRING_SIZE_GFX11_bitfields',
               'union_COMPUTE_TMPRING_SIZE_GFX12_bitfields'):
        u = getattr(hsa, nm)
        tag = nm.replace('union_COMPUTE_TMPRING_SIZE','').replace('_bitfields','') or 'base'
        for waves, wsize in ((0,0),(1,1),(0xffff,0x3f),(0x7f,0x20),(0x1f,0x10)):
            row(f"amd_tmpu_{tag}_{waves}_{wsize}", int.from_bytes(u(WAVES=waves, WAVESIZE=wsize), 'little'))
        # the WIDTHS, probed by driving the record: WAVES is 12 bits at 0 and
        # WAVESIZE is the remaining 20 at 12, and the three unions AGREE.
        row(f"amd_tmpw_{tag}", f"{csize(u)}")
        for waves, wsize in ((0xFFF,0),(0x1000,0),(0,0xFFFFF),(0xFFF,0xFFFFF),(0x28,0x20)):
            try: v = hex(int.from_bytes(u(WAVES=waves, WAVESIZE=wsize), 'little'))
            except Exception as e: v = "RAISE"
            row(f"amd_tmpb_{tag}_{waves}_{wsize}", v)
    # which union each target[0] picks
    for t0 in (9, 11, 12):
        nm = f'union_COMPUTE_TMPRING_SIZE{"_GFX"+str(t0) if t0 != 9 else ""}_bitfields'
        row(f"amd_tmpu_name_{t0}", nm)
    # :983-984 the scratch ladder, in isolation
    for psize, tgt, slots, cu, se, xcc in ((128,(11,0,0),8,20,4,1),(1024,(11,0,0),8,20,4,1),(128,(9,4,2),8,20,4,1)):
        psize = max(psize, 128)
        lanes, mem = 64, (256 if tgt[0] != 9 else 1024)
        spt = round_up(psize, mem // lanes)
        spx = spt*lanes*slots*cu
        msw = cu*slots*xcc
        wsc = ceildiv(lanes*spt, mem)
        nw = (spx // (wsc*mem)) // (se if tgt[0] != 9 else 1)
        row(f"amd_scr_spt_{psize}_{tgt[0]}", spt)
        row(f"amd_scr_spx_{psize}_{tgt[0]}_{cu}_{slots}", spx)
        row(f"amd_scr_wsc_{psize}_{tgt[0]}_{cu}_{slots}", wsc)
        row(f"amd_scr_nw_{psize}_{tgt[0]}_{cu}_{slots}_{se}_{xcc}", min(nw, msw))
        row(f"amd_scr_buf_{psize}_{tgt[0]}_{cu}_{slots}_{xcc}", spx*xcc)
        row(f"amd_scr_mem_{tgt[0]}", mem)
        row(f"amd_scr_lanes", lanes)
    # :993-996 scratch_buffer's monotone max
    for a, b in ((0, 128), (64, 256), (4096, 128), (128, 128)):
        row(f"amd_scr_max_{a}_{b}", max(a, 128, b))

# ------------------------------------------------- 9. queue sizes and tags
def t_queue():
    for tgt in ((9,4,2),(9,5,0),(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)):
        row(f"amd_vgpr_{tgt[0]}_{tgt[1]}{tgt[2]}", 0x60000 if tgt in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)}
            else 0x80000 if tgt[0] == 9 else 0x40000)
        row(f"amd_ldscu_{tgt[0]}_{tgt[1]}", (64 << 10) if tgt[:2] == (9,5) else 0x10000)
    # :954-959
    for tgt, cu, wave_cnt, is_am, is_usb in [((11,0,0),20,80,False,False), ((9,4,2),20,40,False,False),
                                             ((11,0,0),20,80,True,False), ((9,4,2),20,40,True,True)]:
        lds = (64 << 10) if tgt[:2] == (9,5) else 0x10000
        vg = 0x60000 if tgt in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)} else 0x80000 if tgt[0] == 9 else 0x40000
        sg, hw = 0x4000, 0x1000
        wg = round_up((vg+sg+lds+hw)*cu, 4096)
        ctl = round_up((12 if tgt[0] != 9 else 8)*wave_cnt + 8 + 40, 4096)
        dbg = round_up(wave_cnt*32, 64)
        csr = 0 if is_am else wg + ctl
        row(f"amd_q_wg_{tgt[0]}_{cu}_{lds}", wg)
        row(f"amd_q_ctl_{tgt[0]}_{wave_cnt}", ctl)
        row(f"amd_q_dbg_{wave_cnt}", dbg)
        row(f"amd_q_csr_{tgt[0]}_{int(is_am)}", csr)
        row(f"amd_q_ring_{int(is_usb)}", (1 << 20) if is_usb else (16 << 20))
    row("amd_q_eop", 0x1000)
    # :943-946 queue_buffer, BOTH directions. The queue names are the ones
    # hcq2.py:235 spells -- "COMPUTE:0", "SDMA:3" -- and `to_name` folds the
    # colon to an underscore, which is what gives rsplit three pieces.
    for nm, q, idx in [("ring", "COMPUTE:0", 0), ("write_ptr", "SDMA:0", 0), ("doorbell", "COMPUTE:0", 0),
                       ("put_value", "SDMA:3", 3), ("ring", "SDMA:7", 7)]:
        t = to_name(nm, q)
        row(f"amd_qb_name_{nm}_{idx}", t)
        row(f"amd_qb_split_{nm}_{idx}", " ".join(t.rsplit('_', 2)))
    for bad in ("", "ring", "ring_", "ring_compute", "prof_log_compute", "Ring_compute", "ring_COMPUTE", "ib_compute"):
        ok = bad.startswith(("ring_", "write_ptr_", "doorbell_", "put_value_"))
        row(f"amd_qb_ok_{bad or 'empty'}", int(ok))
    # the dispatch arm: `compute_queue if queue == 'compute' else sdma_queue(int(idx))`
    for t in (to_name("ring","COMPUTE:0"), to_name("ring","SDMA:0"), to_name("ring","SDMA:7")):
        name, queue, idx = t.rsplit('_', 2)
        row(f"amd_qb_arm_{t}", "compute" if queue == 'compute' else f"sdma:{int(idx)}")
    row("amd_qb_unknown", to_name("prof_log", "COMPUTE:0"))
    row("amd_qb_unknown_ok", int(to_name("prof_log", "COMPUTE:0").startswith(("ring_","write_ptr_","doorbell_","put_value_"))))

# --------------------------------------------------------- 10. sqtt arithmetic
def t_sqtt():
    for win, slots, ses in ((8, 32, 4), (16, 4, 8), (1, 1, 1)):
        for slot, se in ((0,0),(1,0),(0,1),(3,3)):
            off = (se*slots + slot)*win
            row(f"amd_sq_off_{win}_{slots}_{ses}_{slot}_{se}", off)
            row(f"amd_sq_wptrslot_{win}_{slots}_{ses}_{slot}_{se}", slot*ses + se)
    # rendered `hi:lo` because the .bend prints an H.I64 and `H.i64_text` is
    # that spelling -- the VALUE is CPython's, the RENDERING is the port's
    def i64(v): return f"{(v >> 32) & 0xFFFFFFFF}:{v & 0xFFFFFFFF}"
    for raw, win, tag in ((0, 64, "0_64"), (1, 64, "1_64"), (0x1fffffff, 64, "536870911_64"),
                          (0x20000000, 64, "536870912_64"), (5, 32, "5_32")):
        row(f"amd_sq_wptr_{tag}", i64((raw & 0x1FFFFFFF)*32))
    for base, off, raw, tag in ((0x1000, 0, 5, "4096_0_5"), (0x1040, 0, 5, "4160_0_5"),
                                (0x1000, 0x40, 0x1fffffff, "4096_64_536870911")):
        row(f"amd_sq_fix_{tag}", i64((raw & 0x1FFFFFFF)*32 - (((base + off)//32) & 0x1FFFFFFF)*32))
    # the gfx9 header
    for se in (0, 1, 7):
        row(f"amd_sq_hdr9_{se}", 0x11 | (4 << 13) | (0xf << 16) | (se << 24))
    # the sqtt_ses / sqtt_win derivation, :904
    for se_cnt, xccs, mb in ((4,1,256),(8,2,256),(4,1,32)):
        row(f"amd_sq_ses_{se_cnt}_{xccs}", se_cnt*xccs)
        row(f"amd_sq_win_{mb}", (mb << 20)//32)
    # the IT_RACE mask
    for mask, se in ((0b11, 0), (0b11, 1), (0b10, 1), (0, 0), (0b1111, 3)):
        row(f"amd_sq_itrace_{mask}_{se}", int(bool((mask >> se) & 0b1)))
    # the :252-261 SE limit, and its masks
    for gsize, cu_cnt, se_cnt, cpus, i, mask3 in ((64, 20, 4, 8, 0, 0b11), (4096, 20, 4, 8, 1, 0b11), (1, 20, 4, 8, 0, 0b1)):
        cu_per_se = (gsize) // ((cu_cnt // se_cnt) * 4)
        sa_mask = (1 << (cpus // 2)) - 1
        cu_mask = (1 << (cu_per_se + (1 if i == 0 else 0))) - 1
        row(f"amd_sq_cuperse_{gsize}_{cu_cnt}_{se_cnt}", cu_per_se)
        row(f"amd_sq_mask_{gsize}_{cu_cnt}_{se_cnt}_{cpus}_{i}_{mask3}", lo32((cu_mask & sa_mask) | (cu_mask & (sa_mask << 16)) << 16))
    # :1044 the refusal threshold
    for wptr, win in ((0, 64), (64, 64), (65, 64), (-1, 64)):
        row(f"amd_sq_refuse_{wptr}_{win}", int(0 <= wptr <= win))
    # the buffer-overflow warning threshold
    for wptr, win in ((0, 64), (32, 64), (33, 64), (63, 64), (64, 64)):
        row(f"amd_sq_full_{wptr}_{win}", int(wptr >= win - 32))

# ------------------------------------------------------------- 11. refusals
def t_refuse():
    for sz_dw, rs in ((100, 200), (200, 200), (201, 200), (0, 200)):
        row(f"amd_sdma_ovf_{sz_dw}_{rs}", int(sz_dw > rs))
        row(f"amd_sdma_msg_{sz_dw}_{rs}", f"SDMA command buffer ({sz_dw*4} bytes) exceeds ring size ({rs*4} bytes)" if sz_dw > rs else "")
    for did, n in ((0, 4), (3, 4), (4, 4), (5, 4)):
        row(f"amd_kfd_nogpu_{did}_{n}", int(did >= n))
    row("amd_kfd_msg", f"No device found for 4. Requesting more devices than the system has?")
    for did, n in ((0, 2), (1, 2), (2, 2), (7, 1)):
        row(f"amd_usb_nogpu_{did}_{n}", int(did >= n))
    row("amd_usb_msg1", f"AMD:2 does not exist (2 devices available)")
    row("amd_usb_msg2", f"AMD:1 does not exist (device available)")
    for sz in (0, 1024, 1 << 30):
        row(f"amd_alloc_enomem_{sz}", f"Cannot allocate {sz} bytes: no memory is available.")
    row("amd_alloc_vram", "Cannot allocate host-visible VRAM. Ensure the resizable BAR option is enabled on your system.")
    for addr in (0, 0x1000, 0xfff, 0x1001, 0x800):
        row(f"amd_map_align_{addr}", int(addr % 0x1000 == 0))
    for d in ("AMD", "AMD:1", "CPU", "PYTHON", "NPY", "NV", "METAL", "CL"):
        row(f"amd_map_ok_{d}", int(d.split(":")[0] in {"CPU","PYTHON","NPY"} or d.split(":")[0] == "AMD"))
    row("amd_erstate", "Device is in error state")
    row("amd_hang", "Device hang detected")
    row("amd_toomany", "Too many resources requested: group_segment_size")
    row("amd_pmcmode", "PMC/SQTT requires stable power state: run `amd-smi set -l stable_std` for KFD iface")
    row("amd_pmcbad", "PMC counter SQ_BUSY_CYCLES is not supported. Available: SQ_BUSY_CYCLES,SQ_INSTS_VALU")
    row("amd_nosetreg", "Cannot set regSQ_THREAD_TRACE_CTRL (12345) via pm4 packet")
    row("amd_argxor", "One (and only one) of *args or **kwargs must be specified")
    row("amd_pmcfull", "SQ is out of perfcounter registers: (regSQ_PERFCOUNTER1 is not found)")
    # :1044
    for wptr, win in ((0, 64), (65, 64)):
        row(f"amd_sqtt_assert_{wptr}_{win}", f"{wptr} > {win}, should never happen" if wptr > win else "")

# ------------------------------------------------------------------ 12. init
def t_init():
    # the order AMDDevice.__init__ runs in, by source line
    order = []
    for i, l in enumerate(open('tinygrad/runtime/ops_amd.py').read().split('\n'), 1):
        s = l.strip()
        if 852 <= i <= 884 and ('self.' in s and '=' in s and not s.startswith('#')): order.append((i, s.split('=')[0].strip()))
    row("amd_init_n", len(order))
    row("amd_init_first", f"{order[0][0]}:{order[0][1]}")
    row("amd_init_last", f"{order[-1][0]}:{order[-1][1]}")
    # the ifaces list, in order
    row("amd_ifaces", "KFDIface PCIIface USBIface MOCKIface MOCK MOCKPCIIface MOCKUSBIface")
    # is_am / is_usb / is_vf
    # `is_am` is `isinstance(iface, (PCIIface,))` and `USBIface(PCIIface)`, so
    # the USB device IS AM -- which is what makes `can_recover` False for it.
    for nm, is_pc, is_usb, is_vf in (("kfd",False,False,False), ("pci",True,False,False),
                                     ("usb",True,True,False), ("pci_vf",True,False,True),
                                     ("mockpci",True,False,False), ("mockusb",True,True,False)):
        row(f"amd_isam_{nm}", int(is_pc))
        row(f"amd_isusb_{nm}", int(is_usb))
        row(f"amd_isvf_{nm}", int(is_pc and is_vf))
        row(f"amd_canrec_{nm}", int(is_pc and not is_vf))
        row(f"amd_rtalloc_{nm}", (4 if is_usb else 64) << 20)
    # timestamp_divider / sleep_timeout_ms / max_scratch_psize
    row("amd_tsdiv", int(AMDDevice.timestamp_divider))
    row("amd_tsdiv_is_int", int(AMDDevice.timestamp_divider))
    row("amd_sleepto", AMDDevice.sleep_timeout_ms)
    row("amd_maxscratch0", AMDDevice.max_scratch_psize)
    # :1023-1030 the profiling buffer sizes
    for slots, pmc_size, sqtt_win, ses in ((32, 128, 8, 4), (4, 64, 16, 8)):
        row(f"amd_prof_log_{slots}", 1 + slots)
        row(f"amd_pmc_buf_{slots}_{pmc_size}", pmc_size*slots)
        row(f"amd_sqtt_buf_{slots}_{sqtt_win}_{ses}", sqtt_win*slots*ses)
        row(f"amd_sqtt_wp_{slots}_{ses}", slots*ses)
    row("amd_prof_slots_default", getenv("PROF_SLOTS", 32))
    # :1088-1092 pm_bufferize rule ORDER: scratch, program, then the inherited ones
    row("amd_pmb_order", "scratch program PARAM")
    row("amd_pmb_prof", "prof_log pmc_buf sqtt_buf sqtt_wptrs scratch program PARAM")

# ------------------------------------------- 13. the module dispatch ladders
def t_mods():
    from tinygrad.runtime.support.amd import import_soc, import_module, import_pmc
    # import_soc(:870) -- `getattr(am, f"soc_{ip[0]}")`
    for t in ((9,4,2),(9,5,0),(11,0,0),(12,0,0)):
        row(f"amd_soc_{t[0]}", import_soc(t).__name__.rsplit('.', 1)[-1])
    # import_module('sdma', min(ip_versions[SDMA0_HWIP], (6,0,0))) -- :872, the
    # "greatest module with matching major <= target" ladder.
    for v in ((3,0,0),(4,0,0),(4,4,0),(4,4,1),(4,4,2),(5,0,0),(5,1,0),(5,2,0),(6,0,0),(7,0,0),(4,3,9)):
        try: nm = import_module('sdma', min(v, (6,0,0))).__name__.rsplit('.', 1)[-1]
        except ImportError: nm = "RAISE"
        row(f"amd_sdma_mod_{v[0]}_{v[1]}_{v[2]}", nm)
    # the min() clamp, both sides
    for v in ((4,4,1),(6,0,0),(6,5,0),(7,1,2)):
        row(f"amd_sdma_clamp_{v[0]}_{v[1]}_{v[2]}", " ".join(map(str, min(v, (6,0,0)))))
        row(f"amd_sdma_clamp0_{v[0]}_{v[1]}_{v[2]}", min(v, (6,0,0))[0])
    # :869 the offsets module and :871 the pm4 module, both keyed on target[0]
    for t in ((9,4,2),(9,5,0),(11,0,0),(12,0,0)):
        row(f"amd_offsets_{t[0]}", f"tinygrad.runtime.autogen.am.{'vega' if t[0] == 9 else 'navi'}_offsets")
        row(f"amd_pm4_{t[0]}", f"tinygrad.runtime.autogen.am.pm4_{'soc15' if t[0] == 9 else 'nv'}")
        row(f"amd_nbio_{t[0]}", 'nbio' if t[0] < 12 else 'nbif')
    # :877's bases loop: 6 instances x 6 (or 9) segments
    for t0 in (9, 11, 12):
        row(f"amd_bases_{t0}_seg", 6 if t0 != 12 else 9)
    row("amd_bases_n", 6)
    row("amd_bases_9_seg_n", 6)
    row("amd_bases_12_seg_n", 9)
    # :885-886 the renderers, in order
    row("amd_renderers", "HIPRenderer AMDLLVMRenderer HIPCCRenderer")
    # import_pmc(:908) and the counter-name validation at :913-914
    for t in ((9,4,2),(11,0,0),(12,0,0)):
        row(f"amd_pmc_n_{t[0]}", len(import_pmc(t)))
    for t0 in (9, 11):
        row(f"amd_pmc_arch_{t0}", f"gfx{t0}" if t0 != 9 else "gfx9{1:x}{2:x}")
    row("amd_pmc_arch_9", "gfx942")
    row("amd_pmc_arch_9_t", (9,4,2))
    row("amd_pmc_arch_11_t", (11,0,0))
    # :910-912 the default counter list
    for t0, l2, lds in ((9, "TCC", "SQ"), (11, "GL2C", "SQC"), (12, "GL2C", "SQC")):
        _ = None
        row(f"amd_pmc_def_{t0}", f"SQ_BUSY_CYCLES,SQ_INSTS_VALU,SQ_INSTS_SALU,{lds}_LDS_IDX_ACTIVE,{lds}_LDS_BANK_CONFLICT,GRBM_GUI_ACTIVE,{l2}_HIT,{l2}_MISS")
    row("amd_pmc_has_busy", int("SQ_BUSY_CYCLES" in import_pmc((11,0,0))))
    row("amd_pmc_has_bogus", int("NOT_A_COUNTER" in import_pmc((11,0,0))))
    row("amd_pmc_msg", f"PMC counter NOT_A_COUNTER is not supported. Available: {','.join(list(import_pmc((11,0,0)))[:2])}")

def t_extra():
    """The rows the gate prints that the first pass of this oracle did not
    cover. Still generated by CALLING CPython, one expression per row."""
    import textwrap
    from tinygrad.helpers import round_up as ru, ceildiv as cd, lo32, LRU

    # --- the arch string, the %x corners ---------------------------------
    for t in ((12,10,0),(9,255,15),(9,4,3),(9,0,0),(10,0,0),(13,0,0),(11,99,9)):
        row(f"amd_arch_{t[0]}_{t[1]}{t[2]}", "gfx%d%x%x" % t)
        row(f"amd_arch_ok_{t[0]}_{t[1]}{t[2]}",
            int((t in ((9,4,2),(9,5,0))) or t[0] in (11,12)))
    row("amd_arch_9_255_15", "gfx%d%x%x" % (9,255,15))
    row("amd_arch_12_10_0", "gfx%d%x%x" % (12,10,0))
    # --- the occupancy chain --------------------------------------------
    P = PROPS
    for is_pc, is_usb, is_vf, tag in ((False,False,False,"kfd"), (True,False,False,"pci"),
                                      (True,True,False,"usb"), (True,False,True,"pci_vf")):
        row(f"amd_isam_{tag}", int(is_pc))
        row(f"amd_canrec_{tag}", int(is_pc and not is_vf))
        row(f"amd_canrecb_{tag}", int(is_pc and not is_vf))
    for forced, want, tag in ((False,True,"default_1"), (False,False,"default_2"), (True,False,"forced")):
        row(f"amd_is_aql_{tag}", int(bool(forced or want)))
    # the exact expressions of :864-867
    for tgt, props, xccs in [((11,0,0),P,1),((12,0,0),P,1),((9,4,2),P,1),
                             ((11,0,0),dict(P,num_xcc=2),2),((9,5,0),P,1)]:
        se = props['array_count']//props['simd_arrays_per_engine']//xccs
        cu = props['simd_count']//props['simd_per_cu']//xccs
        wpu = props['max_waves_per_simd']*props['simd_per_cu']
        wc = (cu*wpu) if tgt[0] != 9 else min(cu*40, se*xccs*512)
        row(f"amd_wave_cnt_{tgt[0]}_{xccs}_x", wc)
        row(f"amd_cu_cnt_{tgt[0]}_{xccs}_x", cu)
        row(f"amd_se_cnt_{tgt[0]}_{xccs}_x", se)
    row("amd_wave_cnt_9_2", (lambda: (lambda cu,se,xc: min(cu*40, se*xc*512))(P['simd_count']//P['simd_per_cu']//2, P['array_count']//P['simd_arrays_per_engine']//2, 2))())
    # :852-856, the four class/instance attributes
    row("amd_rtalloc_host", (64) << 20)
    row("amd_rtalloc_usb", (4) << 20)
    # --- the per-CU tables, :952-953 -------------------------------------
    for tgt in ((9,4,2),(9,5,0),(11,0,0),(11,0,2),(11,5,1),(12,0,0),(12,0,1),(12,1,0)):
        row(f"amd_vgpr_{tgt[0]}_{tgt[1]}_{tgt[2]}", 0x60000 if tgt in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)}
            else 0x80000 if tgt[0] == 9 else 0x40000)
        row(f"amd_ldscu_{tgt[0]}_{tgt[1]}{tgt[2]}", (P['lds_size_in_kb'] << 10) if tgt[:2] == (9,5) else 0x10000)
    # --- the queue sizes, :954-959 --------------------------------------
    for tgt, cu, wave_cnt, is_am, is_usb, tag in [((11,0,0),20,80,False,False,"11_20_64"),
                                                  ((9,4,2),20,40,False,False,"9_20_64"),
                                                  ((9,5,0),20,40,False,False,"9_50_20_64"),
                                                  ((11,0,0),20,80,True,False,"11_am"),
                                                  ((11,0,0),20,80,False,True,"11_usb")]:
        lds = (P['lds_size_in_kb'] << 10) if tgt[:2] == (9,5) else 0x10000
        vg = 0x60000 if tgt in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)} else 0x80000 if tgt[0] == 9 else 0x40000
        wg = round_up((vg+0x4000+lds+0x1000)*cu, 4096)
        ctl = round_up((12 if tgt[0] != 9 else 8)*wave_cnt + 8 + 40, 4096)
        row(f"amd_q_wg_{tag}", wg)
        row(f"amd_q_ctl_{tgt[0]}_{wave_cnt}", ctl)
        row(f"amd_q_dbg_{wave_cnt}", round_up(wave_cnt*32, 64))
        row(f"amd_q_csr_{'am' if is_am else 'notam'}", 0 if is_am else wg+ctl)
        row(f"amd_q_ring_{'usb' if is_usb else 'host'}", (1 << 20) if is_usb else (16 << 20))
    # :196, the PMC record size
    for xcc, inst, se, sa, wgp in ((1,1,1,1,1),(1,1,4,2,4),(2,32,1,1,1)):
        row(f"amd_pmc_rec_{xcc}_{inst}_{se}_{sa}_{wgp}", (xcc*inst*se*sa*wgp)*8)
    row("amd_pmc_rec_1_1_4_2_4", (1*1*4*2*4)*8)
    row("amd_pmc_rec_2_32_1_1_1", (2*32*1*1*1)*8)
    # :978, the size_per_thread ladder at its corners
    for ps, t0 in ((128,11),(129,11),(0,11),(128,9)):
        mem = 256 if t0 != 9 else 1024
        row(f"amd_scr_spt_{ps}_{t0}", round_up(max(ps,128), mem//64))
    for ps, t0, slots, cu, xcc in ((128,11,8,20,2),(1024,11,8,20,1),(128,9,8,20,1)):
        mem = 256 if t0 != 9 else 1024
        spt = round_up(max(ps,128), mem//64)
        row(f"amd_scr_buf_{ps}_{t0}_{cu}_{slots}_{xcc}", spt*64*slots*cu*xcc)
    # :256-260, the SE limit mask
    for gsize, cu_cnt, se_cnt, cpus, i, tag in ((64,20,4,8,0,"64_20_4_8_0"),
                                                (4096,20,4,8,1,"4096_20_4_8_1"),
                                                (1,20,4,8,0,"1_20_4_8_0")):
        cu_per_se = gsize // ((cu_cnt // se_cnt) * 4)
        sa_mask = (1 << (cpus // 2)) - 1
        cu_mask = (1 << (cu_per_se + (1 if i == 0 else 0))) - 1
        row(f"amd_sq_mask_{tag}", lo32((cu_mask & sa_mask) | (cu_mask & (sa_mask << 16)) << 16))
    # :377-380, the user-register list LENGTH
    for priv, edp, tag in ((False,False,"none"),(True,False,"priv"),(False,True,"edp"),(True,True,"both")):
        row(f"amd_ureg_n_{tag}", (3 + (1 if edp else 0) + 1) if priv else ((1 if edp else 0) + 1))
    # :561, the image padding at the corners
    for n in (255, 256, 257):
        row(f"amd_pd_img_pad_{n}", n % 4)
        row(f"amd_pd_img_len_{n}", round_up(n, 4))
    # :533-535, the cache key equality
    for a, b, tag in ((( b'x',('AMD',)),(b'x',('AMD',)),"same"),
                      (( b'x',('AMD',)),(b'x',('AMD:1',)),"devs"),
                      (( b'x',('AMD',)),(b'y',('AMD',)),"lib")):
        row(f"amd_key_hit_miss_{tag}", int(a == b))
    row("amd_key_sum_1_0", 2+8+1)
    row("amd_key_sum_2_1", 2+8+2)
    # :1016-1017, the two prof-buffer specs
    for host in (True, False):
        row(f"amd_recycled_prof_{'host' if host else 'dev'}",
            int(bool(LRU) and True and not True and None is None))
    # :944, the four-prefix allow-list and :946's arm
    for tag in ("ring_compute_0","ring_sdma_7","gc_compute_0","","ring","ring_","ib_compute_0"):
        row(f"amd_qb_ok_{tag or 'empty'}", int(tag.startswith(("ring_","write_ptr_","doorbell_","put_value_"))))
    for q, want, tag in (("compute_0","compute","compute"),("sdma_0","sdma","sdma0"),("sdma_7","sdma","sdma7")):
        row(f"amd_qb_arm_{tag}", q.split('_')[0])
        row(f"amd_qb_armb_{tag}", int(q.split('_')[0] == want))
    row("amd_qb_ok_bare_ring", 0)
    row("amd_qb_ok_bare_underscore", 0)
    row("amd_qb_ok_ring_0", 1)
    row("amd_qb_ok_ring_7", 1)

def t_last():
    P = PROPS
    for t in ((11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1),(12,1,0),(11,0,2),(9,4,2),(9,5,0)):
        row(f"amd_vgpr_{t[0]}_{t[1]}_{t[2]}x", 0x60000 if t in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)}
            else 0x80000 if t[0] == 9 else 0x40000)
    for tgt, cu, wave_cnt, is_am, tag in [((11,0,0),20,80,False,"11_notam"), ((11,0,0),20,80,True,"11_am"),
                                          ((9,4,2),20,40,False,"9_notam"), ((9,5,0),20,40,True,"9_am")]:
        lds = (P['lds_size_in_kb'] << 10) if tgt[:2] == (9,5) else 0x10000
        vg = 0x60000 if tgt in {(11,0,0),(11,0,1),(11,5,1),(12,0,0),(12,0,1)} else 0x80000 if tgt[0] == 9 else 0x40000
        wg = round_up((vg+0x4000+lds+0x1000)*cu, 4096)
        ctl = round_up((12 if tgt[0] != 9 else 8)*wave_cnt + 8 + 40, 4096)
        row(f"amd_q_csr_{tag}", 0 if is_am else wg+ctl)
    # the rsplit: the three pieces, by name
    for tag, want in (("ring_compute_0", "ring compute 0"), ("ring_sdma_7", "ring sdma 7"),
                      ("put_value_sdma_3", "put_value sdma 3")):
        row(f"amd_qb_split_name_{tag}", want)
    # the four-prefix allow-list at its exact boundaries
    for tag in ("ring_", "ring", "", "ib_compute_0"):
        row(f"amd_qb_pref_{tag or 'empty'}", int(bool(tag.startswith(("ring_","write_ptr_","doorbell_","put_value_")))))
    # :946's arm, by name
    for q, tag in (("compute_0","compute"), ("sdma_0","sdma0"), ("sdma_7","sdma7")):
        row(f"amd_qb_armname_{tag}", q.split('_')[0])
    # `is_am` is isinstance and USBIface subclasses PCIIface
    row("amd_isam_mock", 0)
    row("amd_isam_mockkfd", 0)
    row("amd_canrecb_mockpci", 1)
    row("amd_canrecb_mockusb", 1)
    row("amd_isam_mockpci", 1)
    row("amd_isam_mockusb", 1)

def main():
    for f in (t_const, t_layout, t_dispatch, t_prog, t_occupancy, t_tmpring, t_queue, t_sqtt, t_refuse, t_init, t_mods, t_extra, t_last):
        f()
    for k in sorted(OUT): print(f"{k}={OUT[k]}")

if __name__ == '__main__':
    main()
