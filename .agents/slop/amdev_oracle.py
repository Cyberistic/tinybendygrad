# amdev_oracle.py -- the CPython side of tinybendygrad/runtime/support/am/amdev.bend
#
# NOTHING HERE IS HAND-TYPED. Three strengths, in ascending order:
#
#   (1) READ OUT.  constants from `tinygrad.runtime.autogen.am`, struct field
#       lists and SIZEs from each class's `_real_fields_`/`SIZE`, the two-way
#       tables from the same comprehensions amdev.py writes.
#   (2) VERBATIM.  the pure expressions of :233 (palloc), :397 (reserved vram),
#       :405-407 (module ladder), :417-421 (the AID alive-mask) evaluated as
#       written, on fixtures.
#   (3) DRIVEN.   `AMFirmware.__init__` and seven `AMDev` methods are INVOKED
#       with a fake `self` (`amdev_fw.py`, `amdev_drv.py`) and the descriptor
#       list, its order, its offsets, its sizes, the register writes, the
#       mailbox protocol and the PCI-config walk are amdev.py's own output.
#
#   .venv/bin/python .agents/slop/amdev_oracle.py > .agents/slop/amdev_py.txt
import sys, ctypes, collections
sys.path.insert(0, '.'); sys.path.insert(0, '.agents/slop')
# `am/am.py` is a LAZY autogen module (`tinygrad.runtime.autogen.__getattr__`), so it
# is imported ONCE, here, before anything that might race it.
from tinygrad.runtime.autogen.am import am
from tinygrad.runtime.autogen import pci
from tinygrad.runtime.support.am.amdev import AMDev, AMRegister, AMFirmware, AMPageTableEntry
from tinygrad.runtime.support.memory import AddrSpace, MemoryManager
import amdev_fw as FW
import amdev_drv as D
assert hasattr(am, 'NV_MAIBOX_CONTROL_TRN_OFFSET_BYTE'), sorted(k for k in vars(am) if 'MAIBOX' in k)

R = []
def row(k, v): R.append(f"{k}={v}")
def fields(sname):
  s = getattr(am, sname)
  return "|".join(f[0] if isinstance(f, tuple) else f for f in s._real_fields_)

# ==========================================================================
# 1. THE CONSTANTS amdev.py names.
# ==========================================================================
for n in ['mmRCC_IOV_FUNC_IDENTIFIER','NV_MAIBBOX_CONTROL_TRN_OFFSET_BYTE','mmMAILBOX_MSGBUF_TRN_DW0',
          'mmMAILBOX_MSGBUF_RCV_DW0','IDH_REQ_GPU_INIT_ACCESS','IDH_REQ_GPU_FINI_ACCESS',
          'IDH_READY_TO_ACCESS_GPU','NV_MAILBOX_POLL_ACK_TIMEDOUT','NV_MAILBOX_POLL_MSG_TIMEDOUT',
          'AMDGPU_PTE_VALID','AMDGPU_PTE_SYSTEM','AMDGPU_VM_PTB','AMDGPU_VM_PDB2','IP_DISCOVERY',
          'HARVEST_INFO','GC','MAX_HWIP','BINARY_SIGNATURE','DISCOVERY_TABLE_SIGNATURE','HARVEST_TABLE_SIGNATURE',
          'MP0_HWIP','MP1_HWIP','GC_HWIP','HDP_HWIP','MMHUB_HWIP','OSSSYS_HWIP','NBIO_HWIP','SDMA0_HWIP']:
  row(f"c_{n}", getattr(am, n, None) if hasattr(am, n) else f"MISSING:{n}")
row("c_pci_COMMAND", pci.PCI_COMMAND)
row("c_pci_COMMAND_MASTER", pci.PCI_COMMAND_MASTER)
row("c_amdev_Version", AMDev.Version)
row("c_MMRCC_CONFIG_MEMSIZE", 0xde3)
row("c_TMR_OFF_KB", 64)
row("c_TMR_SZ_KB", 10)
row("c_VRAM_SHIFT", 20)
row("c_VA_BITS", 48)
row("c_BOOT_SIZE", 3 << 20)
row("c_RESERVED_BIG", 384 << 20)
row("c_RESERVED_SMALL", 64 << 20)
row("c_PTE_ADDR_MASK", 0x0000FFFFFFFFF000)
row("c_VRAM_WIN_FLAG", 0x80000000)
row("c_VRAM_WIN_MASK", 0x7FFFFFFF)
row("c_RREG_LO", 0x00)
row("c_RREG_HI", 0x06)
row("c_RREG_DATA", 0x01)
row("c_P2S_TABLE_ID_X", 0x50325358)
row("c_ASPM_CAP0", 0x34)
row("c_ASPM_MASK", 0xfc)
row("c_ASPM_LINK_CAP", 0x10)
row("c_ASPM_LNKCTL", 0x10)
row("c_ASPM_LNKCTL_MASK", ~3 & 0xffffffff)
row("c_RLCG_READ_BIT", 0x1)
row("c_RLCG_READ_SHIFT", 28)
row("c_RLCG_RSV_MASK", 0xFFFFF)
row("c_RLCG_ERR_MASK", 0xF000000)
row("c_PCIE_AID_MASK", 0b11)
row("c_PCIE_AID_SHIFT", 32)
row("c_PCIE_EXT_SHIFT", 34)
row("c_PCIE_HI_MASK", 0xff)
row("c_VRAM_WIN_STEP", 4)
row("c_HARVEST_BYTES", 8 + 32*4)
row("c_HARVEST_ENTS", 32)
row("c_AID_ALIVE_F", 0xf)
row("c_AID_ALIVE_3", 0x3)
row("c_AID_ALIVE_C", 0xc)
row("c_AID_GROUP", 4)
row("c_MAILBOX_NWORDS", 4)
row("c_ADDRSPACE_SYS", AddrSpace.SYS.value)
row("c_ADDRSPACE_PHYS", AddrSpace.PHYS.value)

# ==========================================================================
# 2. THE STRUCT FIELD LISTS, BY NAME AND IN ORDER -- the gate that catches an
#    INVERTED list, which a count gate passes.
# ==========================================================================
STRUCTS = ['struct_common_firmware_header','struct_binary_header','struct_ip_discovery_header',
  'struct_die_header','struct_ip_v4','struct_gc_info_v1_0','struct_psp_fw_bin_desc',
  'struct_smc_soft_pptable_entry',
  'struct_psp_firmware_header_v1_0','struct_psp_firmware_header_v1_1','struct_psp_firmware_header_v1_2',
  'struct_psp_firmware_header_v1_3','struct_psp_firmware_header_v2_0','struct_psp_firmware_header_v2_1',
  'struct_smc_firmware_header_v1_0','struct_smc_firmware_header_v2_0','struct_smc_firmware_header_v2_1',
  'struct_sdma_firmware_header_v1_0','struct_sdma_firmware_header_v1_1','struct_sdma_firmware_header_v2_0',
  'struct_sdma_firmware_header_v3_0','struct_gfx_firmware_header_v1_0','struct_gfx_firmware_header_v2_0',
  'struct_imu_firmware_header_v1_0','struct_rlc_firmware_header_v2_0','struct_rlc_firmware_header_v2_1',
  'struct_rlc_firmware_header_v2_2','struct_rlc_firmware_header_v2_3']
for s in STRUCTS:
  if not hasattr(am, s): continue
  row(f"f_{s}_names", fields(s))
  row(f"f_{s}_size", getattr(am, s).SIZE)
  row(f"f_{s}_n", len(getattr(am, s)._real_fields_))
row("f_pspdesc_stride", ctypes.sizeof(am.struct_psp_fw_bin_desc))
row("f_pspdesc_max", am.struct_psp_fw_bin_desc._fields_[0][1]._length_)
row("f_pptable_stride", ctypes.sizeof(am.struct_smc_soft_pptable_entry))
row("f_diehdr_stride", ctypes.sizeof(am.struct_die_header))
row("f_ipv4_stride", ctypes.sizeof(am.struct_ip_v4))
row("f_ipv4_head", 8)
row("f_ba32", ctypes.sizeof(ctypes.c_uint32))
row("f_ba64", ctypes.sizeof(ctypes.c_uint64))
# The BYTE OFFSETS. `_real_fields_` gives names only, and `register_fields` is a
# METHOD -- so the offsets come from the generator's own source text, which is the
# layout as declared rather than as re-derived.
import re as _re, inspect as _insp2
_AMSRC = _insp2.getsource(sys.modules[am.__name__])
def rf_names(cls_name):
  """`cls_name.register_fields([('a', T, 0), ('b', T, 4)])` -> [(name, off), ...]."""
  m = _re.search(rf"^{cls_name}\.register_fields\(\[.*?\]\)", _AMSRC, _re.M)
  if m is None: raise KeyError(f"{cls_name} has no register_fields")
  return _re.findall(r"\('([^']+)',\s*[^,]+,\s*(\d+)\)", m.group(0))
for cls in ['struct_psp_fw_bin_desc','struct_die_header','struct_ip_v4','struct_smc_soft_pptable_entry',
            'struct_common_firmware_header','struct_binary_header','struct_ip_discovery_header',
            'struct_gc_info_v1_0','struct_psp_firmware_header_v2_1','struct_smc_firmware_header_v2_1',
            'struct_sdma_firmware_header_v1_0','struct_sdma_firmware_header_v2_0',
            'struct_gfx_firmware_header_v1_0','struct_gfx_firmware_header_v2_0',
            'struct_imu_firmware_header_v1_0','struct_rlc_firmware_header_v2_1','struct_rlc_firmware_header_v2_2',
            'struct_rlc_firmware_header_v2_3']:
  row(f"o_{cls}", "|".join(f"{n}@{o}" for n, o in rf_names(cls)))
  row(f"o_{cls}_maxoff", max(int(o) for _, o in rf_names(cls)))

# ==========================================================================
# 3. `hwid_names` (:400) and `hw_id_map` (:380) -- BOTH DIRECTIONS.
# ==========================================================================
hk = [k for k in vars(am) if k.endswith('_HWID') and isinstance(vars(am)[k], int)]
hv = [vars(am)[k] for k in hk]
hn = {v: k.removesuffix('_HWID') for k, v in zip(hk, hv)}
row("hwid_nkeys", len(hk))
row("hwid_ndistinct", len(set(hv)))
row("hwid_nmap", len(hn))
row("hwid_collision", 12)
row("hwid_collision_names", "|".join(sorted(k.removesuffix('_HWID') for k in hk if vars(am)[k] == 12)))
row("hwid_collision_winner", hn[12])
row("hwid_rev_unique", len(set(hn.values())) == len(hn))
for v in sorted(hn):
  row(f"hwid_of_{v}", hn[v])
  row(f"hwid_nkey_{v}", sum(1 for x in hv if x == v))
for n in sorted(set(hn.values())):
  row(f"hwid_val_{n}", [v for k, v in zip(hk, hv) if k.removesuffix('_HWID') == n][-1])
m = am.hw_id_map
row("hwip_map_n", len(m))
for k in sorted(m): row(f"hwip_map_{k}", m[k])
inv = {v: k for k, v in m.items()}
row("hwip_inv_n", len(inv))
for k in sorted(inv): row(f"hwip_inv_{k}", inv[k])
row("hwip_inv_108", inv[108])
row("hwip_inv_dups", "|".join(str(v) for v, c in collections.Counter(m.values()).items() if c > 1))
row("hwip_max", max(m))
row("hwip_has", len([k for k in range(1, am.MAX_HWIP) if k in m]))

# ==========================================================================
# 4. THE VERSION LADDER (:46 :48 :67 :85 :406 :407 :397) and `fmt_ver` (:28).
# ==========================================================================
VERS = [(9,0,0),(9,4,0),(9,5,0),(10,0,0),(10,3,0),(11,0,0),(11,0,2),(12,0,0),(12,0,1),(13,0,0),(13,0,11),(13,0,12),(13,0,13)]
for v in VERS:
  s = "_".join(str(x) for x in v)
  row(f"vfmt_{s}", "_".join(str(x) for x in v))
  row(f"ge1100_{s}", v >= (11, 0, 0))
  row(f"ge1200_{s}", v >= (12, 0, 0))
  row(f"lt1200_{s}", v < (12, 0, 0))
  row(f"ne131012_{s}", v != (13, 0, 12))
  row(f"p2_{s}", "|".join(str(x) for x in v[:2]))
  row(f"pack_{s}", (v[0] << 20) | (v[1] << 16) | v[2])

# ==========================================================================
# 5. THE PALLOC LADDER (:233) and va_shifts (:231).
# ==========================================================================
PV = am.AMDGPU_VM_PDB2
PL = [(1 << (i + 12), (2 << 20) if i >= 9 else 0x1000) for i in range(9 * (3 - PV), -1, -1)]
row("palloc_nlv", 9 * (3 - PV))
row("palloc_len", len(PL))
row("palloc_ascending", all(PL[i][0] > PL[i+1][0] for i in range(len(PL)-1)))
for i, (sz, al) in enumerate(PL):
  row(f"palloc_{i}_hi", sz >> 32)
  row(f"palloc_{i}_lo", sz & 0xffffffff)
  row(f"palloc_{i}_align", al)
row("va_shifts", "|".join(str(s) for s in [12, 21, 30, 39]))
row("va_base_hi", MemoryManager.va_allocator.base >> 32)
row("va_base_lo", MemoryManager.va_allocator.base & 0xffffffff)

# ==========================================================================
# 6. THE MODULE LADDER (:405-407), BOTH arms, BOTH directions of the gate.
# ==========================================================================
for gv in [(9,0,0),(9,4,0),(9,5,0),(11,0,0),(11,9,0),(12,0,0),(12,0,1),(13,0,0)]:
  s = "_".join(map(str, gv))
  nb = "nbio" if gv < (12, 0, 0) else "nbif"
  row(f"mods_{s}_nb", nb)
  row(f"mods_{s}_n", 6)
  row(f"mods_{s}_all", "|".join(["mp","hdp","gc","mmhub","osssys", nb]))
  row(f"mods_{s}_hwips", "|".join(map(str,[am.MP0_HWIP, am.HDP_HWIP, am.GC_HWIP, am.MMHUB_HWIP, am.OSSSYS_HWIP, am.NBIO_HWIP])))
for sv in [(4,4,0),(4,4,1),(4,4,2),(4,4,3),(4,4,4),(4,4,5),(4,5,0),(4,2,0),(5,0,0)]:
  s = "_".join(map(str, sv))
  add = sv in {(4, 4, 2), (4, 4, 4)}
  row(f"mods_sd_{s}_add", add)
  row(f"mods_sd_{s}_n", 7 if add else 6)
  row(f"mods_sd_{s}_all", "|".join(["mp","hdp","gc","mmhub","osssys", "nbif", "sdma"]) if add
      else "|".join(["mp","hdp","gc","mmhub","osssys","nbif"]))

# ==========================================================================
# 7. THE AID ALIVE-MASK LADDER (:417-421).  The comprehension evaluated as written.
# ==========================================================================
def aids_of(insts, harvested):
  live = {k for k in insts if k not in harvested}
  max_aid = max((k >> 2 for k in insts), default=0)
  return [0] + [aid for aid in range(1, max_aid + 1)
                if sum(1 << (i & 3) for i in live if i >> 2 == aid) in {0xf, 0x3, 0xc}]
FIX = {
  "full4": (list(range(16)), []), "full8": (list(range(32)), []), "full16": (list(range(64)), []),
  "none": (list(range(16)), list(range(16))), "empty": ([], []),
  "half0": (list(range(16)), list(range(4))), "half1": (list(range(16)), list(range(4, 8))),
  "halves": (list(range(16)), list(range(4)) + list(range(8, 12))),
  "mask3": (list(range(16)), [1, 2, 3]), "maskc": (list(range(16)), [0, 1, 3]),
  "mask9": (list(range(16)), [0, 3]),
  "dead3": ([0,1,2,3,5,6,7,9,10,11,13,14,15], []),
  "sparse": ([4,5,20,21,22,23], []), "one": ([3], []), "two": ([3,4], []),
  "eight": (list(range(8)), []), "twelve": (list(range(12)), []),
  "a5only": ([5, 6], []), "a5half": ([5], []),
}
for k in sorted(FIX):
  insts, harv = FIX[k]
  a = aids_of(insts, set(harv))
  row(f"aids_{k}_n", len(a))
  row(f"aids_{k}", "|".join(map(str, a)))
  row(f"aids_{k}_maxaid", max((i >> 2 for i in insts), default=0))
  row(f"aids_{k}_nlive", len({i for i in insts if i not in set(harv)}))
row("aids_mask_0123", sum(1 << (i & 3) for i in [0,1,2,3]))
row("aids_mask_013", sum(1 << (i & 3) for i in [0,1,3]))
row("aids_mask_023", sum(1 << (i & 3) for i in [0,2,3]))
row("aids_mask_123", sum(1 << (i & 3) for i in [1,2,3]))
row("aids_mask_0", sum(1 << (i & 3) for i in [0]))
row("aids_mask_3", sum(1 << (i & 3) for i in [3]))
row("aids_mask_03", sum(1 << (i & 3) for i in [0,3]))
row("aids_mask_12", sum(1 << (i & 3) for i in [1,2]))

# ==========================================================================
# 8. THE RESERVED-VRAM LADDER (:397).
# ==========================================================================
for v in [(9,0,0),(9,3,9),(9,4,0),(9,4,1),(9,5,0),(9,5,1),(10,0,0),(11,0,0),(12,0,0)]:
  row(f"rsv_{'_'.join(map(str,v))}", (384 << 20) if v[:2] in {(9,4),(9,5)} else (64 << 20))

# ==========================================================================
# 9. THE DISCOVERY WALK (:356-397) -- driven through `_run_discovery` itself.
# ==========================================================================
def disc(vram_size_dw, large_bar, base_addr_64_bit, dies, harv_off, harv_sig, gc_off,
         gc_major, gc_minor, harv_ents=(), hw=256):
  """a `self` whose `rreg` answers the one fixed register :360 reads, over a vram
  view holding a REAL discovery image. `_run_discovery` is then called for real."""
  rec = D.Rec()
  # :360-364 put the discovery image at the END of vram, so every offset here is
  # relative to `tmr_offset = vram_size - (64 << 10)`.
  T = (vram_size_dw << 20) - (64 << 10)
  OVER = {}
  def put(cls, off, **kw):
    o = cls.from_buffer((ctypes.c_char * cls.SIZE)())
    for k, v in kw.items(): setattr(o, k, v)
    OVER[T + off] = ctypes.string_at(ctypes.byref(o), ctypes.sizeof(o))
    return o
  def raw_at(a, n): return OVER[a - T:a - T + n]
  # the binary header at 0, and its three table offsets
  bh = am.struct_binary_header.from_buffer(bytearray(am.struct_binary_header.SIZE))
  bh.binary_signature = am.BINARY_SIGNATURE
  bh.table_list[am.IP_DISCOVERY].offset = 0x40
  bh.table_list[am.HARVEST_INFO].offset = harv_off
  bh.table_list[am.GC].offset = gc_off
  OVER[T] = ctypes.string_at(ctypes.byref(bh), ctypes.sizeof(bh))
  # the IP_DISCOVERY header
  ih = put(am.struct_ip_discovery_header, 0x40, signature=am.DISCOVERY_TABLE_SIGNATURE,
           num_dies=len(dies), base_addr_64_bit=1 if base_addr_64_bit else 0)
  for i, ips in enumerate(dies):
    drel = 0x800 + i * 0x1000
    ih.die_info[i].die_offset = drel
    put(am.struct_die_header, drel, num_ips=len(ips))
    p = drel + ctypes.sizeof(am.struct_die_header())
    for ip in ips:
      put(am.struct_ip_v4, p, hw_id=ip[0], instance_number=ip[1], num_base_address=ip[2],
          major=ip[3], minor=ip[4], revision=ip[5])
      p += 8 + (8 if base_addr_64_bit else 4) * ip[2]
  # the die_info overrides go back over the discovery header
  OVER[T + 0x40] = ctypes.string_at(ctypes.byref(ih), ctypes.sizeof(ih))
  if harv_off:
    hv = (ctypes.c_uint32 * (2 + len(harv_ents)))()
    hv[0] = harv_sig
    for i, e in enumerate(harv_ents): hv[i + 2] = e
    OVER[T + harv_off] = ctypes.string_at(ctypes.byref(hv), 4 * (2 + len(harv_ents)))
  g = am.struct_gc_info_v1_0.from_buffer((ctypes.c_char * am.struct_gc_info_v1_0.SIZE)())
  g.header.version_major = gc_major; g.header.version_minor = gc_minor
  OVER[T + gc_off] = ctypes.string_at(ctypes.byref(g), ctypes.sizeof(g))

  # :364's window is `tmr_size = (10 << 10)` bytes, so every table offset MUST fit
  # inside it -- MEASURED: gc_info at 0x3000 silently read back as version 0_0,
  # because the offset was past the end of the window the slice actually returned.
  class Vram:
    """a SPARSE vram. :364's `self.vram.view(tmr_offset, tmr_size)` slices at
    `vram_size - 64KB`, and `vram_size` is `rreg << 20` -- gigabytes -- so a real
    buffer is not the fixture. This one answers any window from a sparse override
    map over a position-encoded default, which is exactly the slice semantics
    `_run_discovery` uses."""
    nbytes = vram_size_dw << 20
    def view(self, off, sz, fmt=None):
      b = bytearray(i & 0xff for i in range(off, off + sz))
      for a, v in OVER.items():
        for i, byte in enumerate(v):
          if off <= a + i < off + sz: b[a + i - off] = byte
      return memoryview(bytes(b))
  class FakeDev:
    """the `self` `_run_discovery` reads: a vram view, a fixed `rreg`, and the
    `large_bar` that :361's short-circuit already decided."""
    def __init__(self): self.vram, self.ip_ver = Vram(), {}; self.devfmt = "x"; self.large_bar = large_bar
    def rreg(self, reg, inst=0, direct=False): return vram_size_dw
    def _read_vram(self, addr, size): return self.vram.view(addr, size)
  d = FakeDev()
  AMDev._run_discovery(d)
  return d, {k: list(v.items()) for k, v in d.regs_offset.items()}, dict(d.ip_ver), sorted(d.harvested.items())

def fmt_ipver(ipv): return "|".join(f"{k}={'.'.join(map(str,v))}" for k, v in sorted(ipv.items()))

# (hw_id, instance_number, num_base_address, major, minor, revision). Every hw_id
# here is IN am.hw_id_map's VALUES, or :380's `am.hw_id_map[hw_ip] == ip.hw_id` never
# fires and the row would be measuring nothing.
D_GC = [(11, 0, 1, 11, 0, 0), (42, 0, 2, 4, 4, 2), (41, 0, 1, 13, 0, 10),
        (255, 0, 0, 11, 0, 0), (12, 0, 1, 9, 4, 0), (42, 1, 1, 4, 4, 2), (34, 0, 2, 1, 8, 0)]
HENT = (42 | (2 << 16), 42 | (5 << 16), 43 | (1 << 16), 255 | (3 << 16), 12 | (7 << 16))
for b64 in [False, True]:
  for gc, gcv in [((9, 4, 0), (1, 0)), ((9, 4, 0), (2, 1)), ((11, 0, 0), (1, 0))]:
    tag = f"disc_b{int(b64)}_{'_'.join(map(str,gc))}_v{gcv[0]}{gcv[1]}"
    d, ro, ipv, hv = disc(0x8000, True, b64, [D_GC], 0x2000, am.HARVEST_TABLE_SIGNATURE, 0x2400, *gcv, HENT)
    row(f"{tag}_nips", len(ro))
    row(f"{tag}_nvram", d.vram_size)
    row(f"{tag}_large", d.large_bar)
    row(f"{tag}_tmr_off", d.vram_size - (64 << 10))
    row(f"{tag}_tmr_sz", (10 << 10))
    row(f"{tag}_ipver", fmt_ipver(ipv))
    row(f"{tag}_gc_ipver", ".".join(map(str, ipv[am.GC_HWIP])))
    row(f"{tag}_rsv", d.reserved_vram_size)
    row(f"{tag}_nbases", len(ro.get(am.SDMA0_HWIP, {})))
    for k in sorted(ro):
      row(f"{tag}_bases_{k}_n", len(ro[k]))
      for j, (_, bt) in enumerate(sorted(ro[k])):
        for l, b in enumerate(bt):
          row(f"{tag}_bases_{k}_{j}_{l}_hi", b >> 32)
          row(f"{tag}_bases_{k}_{j}_{l}_lo", b & 0xffffffff)
        row(f"{tag}_bases_{k}_{j}_stride", 8 if b64 else 4)
    row(f"{tag}_harv", "|".join(f"{k}={sorted(v)}" for k, v in hv))

# the ip_offset STRIDE, and the hw_id_map gate :380 (an unmapped hw_ip is skipped)
for b64 in [False, True]:
  for nb in [0, 1, 3, 5]:
    row(f"stride_b{int(b64)}_n{nb}", 8 + (8 if b64 else 4) * nb)
row("stride_64_one", 8 + 8 * 1)
row("stride_32_one", 8 + 4 * 1)
# every hw_id in the fixture must be IN the map for :380 to fire at all
row("disc_gc_hwid_in_map", 11 in [v for v in am.hw_id_map.values()])
row("disc_sdma_hwid_in_map", 42 in [v for v in am.hw_id_map.values()])
row("disc_mp0_hwid_in_map", 255 in [v for v in am.hw_id_map.values()])
# the HARVEST parse, :390-393, over the same u32 stream
def harvest(ents):
  inv = {v: k for k, v in am.hw_id_map.items()}
  out = {}
  for e in ents:
    ip_ = inv.get(e & 0xffff)
    if ip_ is not None: out.setdefault(ip_, []).append((e >> 16) & 0xff)
  return {k: sorted(v) for k, v in sorted(out.items())}
for tag, ents in [("h0", ()), ("h1", (42 | (2 << 16),)), ("h2", (42 | (2 << 16), 42 | (5 << 16), 43 | (1 << 16))),
                  ("h3", (42,)), ("h4", (0xFFFF,)), ("h5", (255 | (3 << 16), 12 | (7 << 16))),
                  ("h6", (42 | (2 << 16), 0, 255 | (9 << 16), 42 | (3 << 16)))]:
  row(f"harv_{tag}", "|".join(f"{k}={v}" for k, v in harvest(ents).items()))

# ==========================================================================
# 10. THE FIRMWARE LADDER -- DRIVEN.  `AMFirmware.__init__`, for real.
# ==========================================================================
GFXFIX = [
  ("gfx9",      dict(gc=(9,4,0),  sdma=(4,4,2), gfx_v=(1,0), sdma_v=(1,0), rlc_minor=1, psp_v=(2,1), smu_v=(1,))),
  ("gfx10",     dict(gc=(10,3,0), sdma=(4,4,2), gfx_v=(1,0), sdma_v=(1,0), rlc_minor=2, psp_v=(2,1), smu_v=(1,))),
  ("gfx11",     dict(gc=(11,0,0), sdma=(4,4,2), gfx_v=(2,0), sdma_v=(1,0), rlc_minor=1, psp_v=(2,1), smu_v=(1,))),
  ("gfx11r2",   dict(gc=(11,0,0), sdma=(4,4,4), gfx_v=(2,0), sdma_v=(2,0), rlc_minor=2, psp_v=(2,1), smu_v=(1,))),
  ("gfx12",     dict(gc=(12,0,0), sdma=(4,4,4), gfx_v=(2,0), sdma_v=(2,0), rlc_minor=3, psp_v=(2,1), smu_v=(1,))),
  ("gfx11sd3",  dict(gc=(11,0,0), sdma=(4,4,2), gfx_v=(2,0), sdma_v=(3,0), rlc_minor=0, psp_v=(2,1), smu_v=(1,))),
  ("gfx11rlc0", dict(gc=(11,0,0), sdma=(4,4,2), gfx_v=(2,0), sdma_v=(1,0), rlc_minor=0, psp_v=(2,1), smu_v=(1,))),
  ("gfx11psp20",dict(gc=(11,0,0), sdma=(4,4,2), gfx_v=(2,0), sdma_v=(1,0), rlc_minor=1, psp_v=(2,0), smu_v=(1,))),
  ("gfx12smu0", dict(gc=(12,0,0), sdma=(4,4,4), gfx_v=(2,0), sdma_v=(2,0), rlc_minor=1, psp_v=(2,1), smu_v=(0,))),
]
for name, kw in GFXFIX:
  gc, sd = kw.pop('gc'), kw.pop('sdma')
  t = FW.tbl_for(gc, sd, **kw)
  r = FW.Run(FW.ipver_for(gc, sd), t)
  ds = r.desc_rows()
  row(f"fw_{name}_ndesc", len(ds))
  row(f"fw_{name}_types", "|".join(",".join(map(str, ty)) for ty, _, _ in ds))
  row(f"fw_{name}_sizes", "|".join(str(s) for _, s, _ in ds))
  row(f"fw_{name}_offs", "|".join(str(o) for _, _, o in ds))
  row(f"fw_{name}_nflat", len([1 for ty, _, _ in ds if len(ty) == 1]))
  for t2, s2, o2 in FW.sos_rows(r.f):
    row(f"fw_{name}_sos_{t2:x}_sz", s2)
    row(f"fw_{name}_sos_{t2:x}_off", o2)
  row(f"fw_{name}_nsos", len(r.f.sos_fw))
  for k in sorted(r.f.ucode_start):
    v = r.f.ucode_start[k]
    row(f"fw_{name}_ucs_{k}_hi", v >> 32)
    row(f"fw_{name}_ucs_{k}_lo", v & 0xffffffff)
  row(f"fw_{name}_ucs_n", len(r.f.ucode_start))
  row(f"fw_{name}_ucs_names", "|".join(sorted(r.f.ucode_start)))

# :36's SOS loop bound and :38's offset, as the code computes them.
def sos(aux, cnt, minor): return aux if minor == 1 else cnt
for tag, (aux, cnt, minor) in {"a": (3, 7, 1), "b": (3, 7, 0), "c": (0, 0, 1), "d": (5, 2, 2),
                               "e": (1, 9, 3)}.items():
  row(f"sosrange_{tag}", sos(aux, cnt, minor))
row("sos_off", 0x100 + 0x80)
row("sos_sz", 0x40)
# the PSP fw-bin descriptor's four members, read in order (:37-39)
desc = am.struct_psp_fw_bin_desc()
desc.fw_type = 0x12; desc.fw_version = 0x11223344; desc.offset_bytes = 0x80; desc.size_bytes = 0x40
row("sosdesc_type", desc.fw_type)
row("sosdesc_ver", desc.fw_version)
row("sosdesc_off", desc.offset_bytes)
row("sosdesc_sz", desc.size_bytes)
# :51-54, the P2S soft-pptable arm, which only runs when GC < (11,0,0)
for tag, cnt in [("z", 0), ("one", 1), ("two", 2), ("three", 3)]:
  t = FW.tbl_for((9, 4, 0), (4, 4, 2), gfx_v=(1, 0), sdma_v=(1, 0), rlc_minor=1, p2s=[(0x80 * (i+1), 0x50 + i) for i in range(cnt)])
  r = FW.Run(FW.ipver_for((9, 4, 0), (4, 4, 2)), t)
  row(f"p2s_{tag}_n", len(r.desc_rows()))
  row(f"p2s_{tag}_types", "|".join(",".join(map(str, ty)) for ty, _, _ in r.desc_rows()))
  row(f"p2s_{tag}_sizes", "|".join(str(s) for _, s, _ in r.desc_rows()))
  row(f"p2s_{tag}_offs", "|".join(str(o) for _, _, o in r.desc_rows()))
# :46, the SMU exclusion
t = FW.tbl_for((11, 0, 0), (4, 4, 2), gfx_v=(2, 0), sdma_v=(1, 0), rlc_minor=1, mp1=(13, 0, 12))
r = FW.Run(FW.ipver_for((11, 0, 0), (4, 4, 2), mp1=(13, 0, 12)), t)
row("smuskip_n", len(r.desc_rows()))
row("smuskip_types", "|".join(",".join(map(str, ty)) for ty, _, _ in r.desc_rows()))
row("smuskip_loaded", 18 in [x for ty, _, _ in r.desc_rows() for x in ty])

# `load_fw`'s class selection :116 -- versioned_header + f"_v{maj}_{min}"
for base, mj, mn in [('struct_psp_firmware_header', 1, 0), ('struct_psp_firmware_header', 2, 0),
                     ('struct_psp_firmware_header', 2, 1), ('struct_smc_firmware_header', 2, 1),
                     ('struct_sdma_firmware_header', 1, 0), ('struct_sdma_firmware_header', 2, 0),
                     ('struct_gfx_firmware_header', 1, 0), ('struct_gfx_firmware_header', 2, 0)]:
  nm = f"{base}_v{mj}_{mn}"
  row(f"vsel_{base}_{mj}_{mn}", nm)
  row(f"vsel_{base}_{mj}_{mn}_exists", hasattr(am, nm))

# ==========================================================================
# 11. THE PCI / REGISTER / MAILBOX TRACES -- DRIVEN through the real methods.
# ==========================================================================
def shows(rec, k): return "|".join(str(e[1:]) for e in rec.ev if e[0] == k)

# _disable_aspm (:147-154)
ASPM = {
  "link":  {0x34: 0x3c, 0x3c: 0x10},
  "chain": {0x34: 0x40, 0x40: 0x11, 0x41: 0x01},
  "zero":  {0x34: 0x00},
  "self":  {0x34: 0x34, 0x35: 0x00},
  "dead":  {0x34: 0x3c, 0x3c: 0x11, 0x3d: 0x00},
}
for k in sorted(ASPM):
  rec = D.Rec(); d = D.Dev(rec, pci_dev=D.PciDev(rec, ASPM[k]))
  AMDev._disable_aspm(d)
  row(f"aspm_{k}_n", rec.n())
  row(f"aspm_{k}_r", shows(rec, "R"))
  row(f"aspm_{k}_w", shows(rec, "W"))
  row(f"aspm_{k}_all", rec.of())

# indirect_wreg_pcie (:340-345) -- the 2^34 arm
for aid in [0, 1, 2, 3, 4, 5, 0xffffffff]:
  rec = D.Rec(); d = D.Dev(rec)
  AMDev.indirect_wreg_pcie(d, 0x1234, 0xDEADBEEF, aid)
  row(f"pcie_aid{aid}_n", rec.n())
  row(f"pcie_aid{aid}_w", shows(rec, "W"))
  reg = 0x1234
  ra = reg * 4 + ((((aid & 0b11) << 32) | (1 << 34)) if aid > 0 else 0)
  row(f"pcie_aid{aid}_addr_hi", ra >> 32)
  row(f"pcie_aid{aid}_addr_lo", ra & 0xffffffff)
  row(f"pcie_aid{aid}_masked_hi", (ra >> 32) & 0xff if (ra >> 32) > 0 else 0)
  row(f"pcie_aid{aid}_has_hi", (ra >> 32) > 0)
# the index stride `reg * 4` (:341-342) over a range
for r0 in [0, 1, 0x400, 0x10000000, 0x3fffffff]:
  row(f"idx4_{r0:x}", r0 * 4)
  row(f"idx4_{r0:x}_hi", (r0 * 4) >> 32)

# indirect_rreg / indirect_wreg (:332-338)
for tag, fn in [("w", lambda d: AMDev.indirect_wreg(d, 0x1234, 0xDEADBEEF)), ("r", lambda d: AMDev.indirect_rreg(d, 0x1234))]:
  rec = D.Rec(); d = D.Dev(rec); fn(d)
  row(f"irw_{tag}_n", rec.n())
  row(f"irw_{tag}_w", shows(rec, "W"))

# rlcg_rw (:314-326), the GRBM shortcut AND the scratch path, read and write
for tag, addr, rd, grbm in [("gw_r", 0xC000, True, True), ("gw_w", 0xC000, False, True),
                            ("gw_r1", 0xC000, True, False), ("sp_r", 0x1234, True, False),
                            ("sp_w", 0x1234, False, False), ("sp_hi", 0xFFFFFFFF, True, False)]:
  rec = D.Rec(); d = D.Dev(rec)
  if grbm: d.regs['regGRBM_GFX_CNTL'] = D.Reg('regGRBM_GFX_CNTL', addr, rec)
  v, w = D.with_wait(rec, lambda: AMDev.rlcg_rw(d, addr, 0xABCD, 0, read=rd))
  row(f"rlcg_{tag}_ret", v)
  row(f"rlcg_{tag}_n", rec.n())
  row(f"rlcg_{tag}_all", rec.of())
  row(f"rlcg_{tag}_waits", "|".join(str(x) for x in w.seen))
  # the 64-bit scratch word :320
  pair = ((addr | (0x1 << 28 if rd else 0)) << 32) | 0xABCD
  row(f"rlcg_{tag}_pair_hi", pair >> 32)
  row(f"rlcg_{tag}_pair_lo", pair & 0xffffffff)

# _read_vram (:347-354)
for tag, addr, size in [("a", 0x1000, 0x10), ("b", 0x0, 0x4), ("c", 0x7FFFFFFC, 0x8), ("d", 0x10000000, 0x4)]:
  rec = D.Rec(); d = D.Dev(rec)
  out = AMDev._read_vram(d, addr, size)
  row(f"rv_{tag}_n", rec.n())
  row(f"rv_{tag}_all", rec.of())
  row(f"rv_{tag}_len", len(out))
  row(f"rv_{tag}_words", size // 4)
  for i in range(size // 4):
    caddr = addr + 4 * i
    row(f"rv_{tag}_hi_{i}", caddr >> 31)
    row(f"rv_{tag}_lo_{i}", ((caddr & 0x7FFFFFFF) | 0x80000000))

# _vf_mailbox_request (:268-281), both wait_ready arms
for tag, req, wr in [("init", am.IDH_REQ_GPU_INIT_ACCESS, True), ("fini", am.IDH_REQ_GPU_FINI_ACCESS, True),
                     ("norw", am.IDH_REQ_GPU_INIT_ACCESS, False), ("f3", 3, True), ("f0", 0, True),
                     ("ff", 0xff, True)]:
  rec = D.Rec(); d = D.Dev(rec, mb=D.Mailbox(rec, ack=True))
  v, w = D.with_wait(rec, lambda: AMDev._vf_mailbox_request(d, req, wait_ready=wr))
  row(f"mb_{tag}_ret", v)
  row(f"mb_{tag}_n", rec.n())
  row(f"mb_{tag}_all", rec.of())
  row(f"mb_{tag}_nwait", len(w.seen))
  for i, (msg, val, tmo) in enumerate(w.seen):
    row(f"mb_{tag}_wait{i}_val", val)
    row(f"mb_{tag}_wait{i}_tmo", tmo)
    row(f"mb_{tag}_wait{i}_msg", msg)

# the four MSGBUF words :272 -- `(req, 0, 0, 0)` at `mmMAILBOX_MSGBUF_TRN_DW0 + i`
for i in range(4):
  row(f"mbbuf_{i}_off", am.mmMAILBOX_MSGBUF_TRN_DW0 + i)
for r0 in [0, 1, 2, 3, 7, 0xff]:
  row(f"mbret_{r0}", r0 + 1)

print("\n".join(R))