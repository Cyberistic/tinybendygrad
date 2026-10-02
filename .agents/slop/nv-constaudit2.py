# Audits the constants that do NOT come from nv_570 -- the sizes, the VA
# windows, the escape codes -- against the TEXT of ops_nv.py, and prints what
# CPython computes for each. The nv_570 half is nv-constaudit.py.
#   .venv/bin/python .agents/slop/nv-constaudit2.py
import sys
sys.path.insert(0, '.')
from tinygrad.helpers import round_up

# (bend NAME, the ops_nv.py line it comes from, the value that line states)
CASES = [
    ("MMIO_SZ", ":415 mmio_sz:=0x10000", 0x10000),
    ("PCI_MMIO_OFF", ":544 map_bar(bar=0, fmt='I', off=0xbb0000, size=0x10000)", 0xbb0000),
    ("PCI_ROOT", ":537 self.root, self.gpu_instance = 0xc1000000, 0", 0xc1000000),
    ("PCI_GPU_INSTANCE", ":537 self.gpu_instance = 0", 0),
    ("GPFIFO_SPAN", ":432 base=self._alloc_gpu_vaddr(0x4000000...) length=0x4000000", 0x4000000),
    ("GPFIFO_ALLOC", ":615 mem = self.iface.alloc(3<<20, ...)", 3 << 20),
    ("NOTIFIER_BYTES", ":632 notifier = Buffer(self.device, size:=48 << 20, ...)", 48 << 20),
    ("COMPUTE_ENTRIES", ":618 entries=0x10000", 0x10000),
    ("COPY_OFFSET", ":619 offset=0x100000", 0x100000),
    ("ENC_DEC_OFFSET", ":710 offset=0x200000", 0x200000),
    ("ENC_DEC_ENTRIES", ":710 entries=2048", 2048),
    ("LOW_VA_SIZE", ":349 BumpAllocator(size=0x1000000000)", 0x1000000000),
    ("LOW_VA_BASE_OSX", ":349 base=0x8000000000 if OSX", 0x8000000000),
    ("LOW_VA_BASE_LINUX", ":349 base=0x8000000000 if OSX else 0x1000000000", 0x1000000000),
    ("UVM_SIZE", ":350 BumpAllocator(size=(1 << 48) - 1)", (1 << 48) - 1),
    ("HOST_OBJ_BASE", ":351 host_object_enumerator: int = 0x1000", 0x1000),
    ("VAS_BASE", ":585 NV_VASPACE_ALLOCATION_PARAMETERS(vaBase=0x1000", 0x1000),
    ("VAS_SIZE", ":585 vaSize=0x1fffffb000000", 0x1fffffb000000),
    ("VIRT_LIMIT", ":578 NV_MEMORY_VIRTUAL_ALLOCATION_PARAMS(limit=0x1ffffffffffff)", 0x1ffffffffffff),
    ("WINDOW_SHARED", ":607 shared_mem_window = 0x729400000000", 0x729400000000),
    ("WINDOW_LOCAL", ":607 local_mem_window = 0x729300000000", 0x729300000000),
    ("GPUTT_RING_STRIDE", ":655 entries*8", 8),
    ("USERD_OFFSET_STRIDE", ":636 userdOffset=(c_uint64*8)(entries*8+offset)", 8),
    ("SMEM_CFG_DIV", ":293 min(shmem_conf * 1024 for shmem_conf in [32,64,100] ...) // 4096 + 1", 4096),
    ("SASS_FILE_SIZE", ":305 ((65536 // round_up(max(1, regs) * 32, 256)) // 4) * 4 * 32", 65536),
    ("SMEM_BANK_MULT", ":692 round_up(round_up(self.slm_per_thread * 32, 0x200) * self.max_warps_per_sm * self.num_sm_per_tpc, 0x8000)", 0x8000),
    ("LOCAL_BUF_ALIGN", ":693 Buffer(..., round_up(bytes_per_tpc*ntpc*ngpc, 0x20000)", 0x20000),
    ("COPY_STEP", ":191 range(0, sz, step:=(1 << 31))", 1 << 31),
    ("GPENTRY_SZ_SHIFT", ":123 (cmdbuf.max_numel() // 4 << 42) | (1 << 41)", 42),
    ("MAX_GRID_X", ":166 [2147483647, 65535, 65535]", 2147483647),
    ("MAX_GRID_YZ", ":166 [2147483647, 65535, 65535]", 65535),
    ("MAX_LOCAL_XY", ":167 [1024, 1024, 64]", 1024),
    ("MAX_LOCAL_Z", ":167 [1024, 1024, 64]", 64),
    ("MAX_THREADS_CAP", ":164 prod(local_size) > 1024", 1024),
    ("MIN_CBUF0_ENTRIES_BW", ":268 min_cbuf0_entries = 224", 224),
    ("MIN_CBUF0_ENTRIES_OLD", ":268 else 12", 12),
    ("CBUF0_DEFAULT_SIZE", ":233 constbufs = {0: (0, 0x160)}", 0x160),
    ("MOCK_CBUF0", ":249 cbuf0_size = 0x160 if mock else 0", 0x160),
    ("RELOC_R_CUDA_64", ":262 elif typ == 2: R_CUDA_64", 2),
    ("RELOC_LOW32", ":263 elif typ == 0x38", 0x38),
    ("RELOC_HIGH32", ":264 elif typ == 0x39", 0x39),
    ("PREFETCH_MAX", ":300 program_prefetch_size=min(prog_sz>>8, 0x1ff)", 0x1ff),
    ("MAX_SM_SMEM", ":300 max_sm_config_shared_mem_size=0x1a", 0x1a),
    ("DBG_SMS_TO_READ", ":736 numSMsToRead=100", 100),
    ("REG_CHUNK", ":819 range(0, len(ops), 124)", 124),
    ("PMAGPC_BW", ":777 PMASYS_BASE, PMAGPC_BASE, GR_GPC_BASE, GPC_BASE = (0x2b1000, 0x2b0000, 0x424000, 0x200000) if is_bw", 0x2b0000),
    ("GR_GPC_BASE_BW", ":777 ... 0x424000", 0x424000),
    ("GPC_BASE_BW", ":777 ... 0x200000", 0x200000),
    ("PMASYS_OLD", ":777 (0x24a000, 0x244000, 0x419800, 0x180000)", 0x24a000),
    ("PMAGPC_OLD", ":777 ... 0x244000", 0x244000),
    ("GR_GPC_BASE_OLD", ":777 ... 0x419800", 0x419800),
    ("GPC_BASE_OLD", ":777 ... 0x180000", 0x180000),
    ("IOWR_NR_F", ":44 (ord('F') & 0xFF) << 8", ord('F')),
    ("IOWR_SIZE_MASK", ":44 (ctypes.sizeof(args) & 0x1FFF) << 16", 0x1FFF),
    ("IOWR_DIR_SHIFT", ":44 (3 << 30)", 30),
    ("NVM_TYP_SHIFT", ":48 (typ << 28)", 28),
    ("NVM_NVALS_SHIFT", ":48 (sum(...) << 16)", 16),
    ("NVM_SUBC_SHIFT", ":48 (subc << 13)", 13),
    ("NVM_METHOD_SHIFT", ":48 (mthd >> 2)", 2),
    ("SASS_VERSION_A04", ":601 sm_version==0xa04", 0xa04),
]

print(f"{len(CASES)} non-nv_570 constants checked against ops_nv.py's text\n")
import re
src = open('tinygrad/runtime/ops_nv.py').read().split('\n')
for name, where, want in CASES:
    line = int(re.search(r'\d+', where).group())
    print(f"  {name:22} py:{where.split()[0]:6} want={want:<16} "
          f"line: {src[line-1].strip()[:78]}")

print("\n=== the derived ones, computed by CPython rather than read ===")
print("  LOW_VA_BASE_OSX + LOW_VA_SIZE (uvm base, OSX)  =", hex(0x8000000000 + 0x1000000000))
print("  LOW_VA_BASE_LINUX + LOW_VA_SIZE (uvm base)     =", hex(0x1000000000 + 0x1000000000))
print("  gpput_off COPY   = 0 + 0x10000*8 + GPPut.offset =", 0 + 0x10000 * 8 + 20)
print("  GPPut.offset (nv_570)                            =",
      __import__('tinygrad.runtime.autogen.nv_570', fromlist=['x']).AmpereAControlGPFifo.GPPut.offset)
for regs in (1, 8, 32, 40, 64, 255, 256):
    print(f"  max_threads regs={regs:<4} = ((65536 // round_up({regs}*32, 256)) // 4) * 4 * 32 = "
          f"{((65536 // round_up(max(1, regs) * 32, 256)) // 4) * 4 * 32}")
for shmem in (0, 0x400, 32 * 1024, 64 * 1024, 100 * 1024, 101 * 1024, 128 * 1024):
    cands = [c * 1024 for c in [32, 64, 100] if c * 1024 >= shmem]
    if not cands:
        print(f"  smem_cfg shmem={shmem:<8} -> min() on an EMPTY sequence: ValueError "
              f"(a LATENT raise in :293, shmem > 100KB)")
        continue
    print(f"  smem_cfg shmem={shmem:<8} = {min(cands) // 4096 + 1}")
for req in (0, 1, 32, 100, 0x400, 4096):
    if req == 0: print("  slm required=0 -> no alloc"); continue
    slm = round_up(req, 32)
    for nw, nsm, ntpc, ngpc in ((48, 4, 2, 12), (64, 4, 2, 14)):
        bpt = round_up(round_up(slm * 32, 0x200) * nw * nsm, 0x8000)
        print(f"  slm req={req:<6} slm={slm:<6} bpt={bpt:<10} total(warps{nw},tpc{ntpc},gpc{ngpc})="
              f"{round_up(bpt * ntpc * ngpc, 0x20000)}")
