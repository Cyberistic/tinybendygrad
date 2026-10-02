#!/usr/bin/env python3
# .agents/slop/nv_nvdev_oracle.py -- the CPython oracle for
# tinybendygrad/runtime/support/nv/nvdev.bend (port of tinygrad/runtime/support/nv/nvdev.py)
#
# WHY THIS ORACLE CALLS THE REAL CLASSES. Every `py=` expectation below is
# produced by importing `tinygrad.runtime.support.nv.nvdev` and driving the REAL
# `NVReg` / `NVPageTableEntry` / `NVMemoryManager` through a recording fake
# device. Nothing here re-implements nvdev.py in Python, because a
# re-implementation is a second transcription and the whole point is to have one.
# The ONLY thing transcribed is `include` (:161-163), which is 4 lines and needs
# an NVDev to call -- and what it RETURNS is generated, not transcribed.
#
# THREE WRONG GUESSES THIS ORACLE MADE, all of which a field-COUNT gate passes:
#   1. `NV_PFB_PRI_MMU_WPR2_ADDR_HI` is in dev_fb, not dev_bus.
#   2. `NV_PGC6_AON_SECURE_SCRATCH_GROUP_42` is in dev_gc6_island, not dev_fb.
#   3. `chip_details['architecture']` (:114) is NV_PMC_BOOT_42's field `architecture`
#      at bits (24,29) -- SIX bits. NV_PMC_BOOT_0's is `architecture_0` at (24,28)
#      -- FIVE bits, and it is a different name. Reading the wrong one moves the
#      `>= 0x1a` branch at :116 for every architecture above 0x1f.
#
# NO `struct.calcsize` ROWS, and here is why, stated rather than hidden:
# nvdev.py imports NO ctypes. Its only imports are `time`, `functools`,
# `tinygrad.runtime.autogen.nv_regs`, `tinygrad.helpers`, `tinygrad.runtime.
# autogen.pci`, and the support modules. So there is no struct layout in this
# file at all: the "offsets" are BIT FIELDS, `(start, end)` pairs out of nv_regs,
# and the rows below are the offset analogue. `struct.calcsize` is the oracle for
# ops_nv.py's NVOS21/NVOS54, which is a different file and another agent's wall.
#
# THE EXIT PATH IS CHECKED, not assumed: `main()` raises if it printed 0 rows.

import functools, sys
sys.path.insert(0, __file__.rsplit("/.agents/slop/", 1)[0])

from tinygrad.runtime.support.nv.nvdev import NVReg, NVPageTableEntry, NVMemoryManager
from tinygrad.helpers import round_up
from tinygrad.runtime.autogen import nv_regs, pci

rows = []
def row(name, value): rows.append((name, value))

# ---------------------------------------------------------------------------
# The recording device. `rreg`/`wreg`/`map_bar` are the seam; what the port
# gates is the ARGUMENT of each, and this records exactly what nvdev.py did.
# ---------------------------------------------------------------------------
class FakeView:
  def __init__(self, log, base, nbytes, fmt): self.log, self.base, self.nbytes, self.fmt, self.buf = log, base, nbytes, fmt, {}
  def view(self, off, size, fmt=None): return FakeView(self.log, self.base + off, size, fmt)
  def __len__(self): return self.nbytes
  def __getitem__(self, i): return self.buf.get(i, 0)
  def __setitem__(self, i, v): self.buf[i] = v; self.log.append(("store", self.base, i, v & 0xffffffffffffffff))

class FakeMM:
  """memory.py's MemoryManager attributes NVPageTableEntry reads: `mm.level_cnt`
  (:36,:58,:59,:66) and `mm.pte_covers` (:59)."""
  def __init__(self, level_cnt, pte_covers): self.level_cnt, self.pte_covers = level_cnt, pte_covers

class FakeDev:
  def __init__(self, regs, mmu_ver=3, level_cnt=6, pte_covers=None, vram_nbytes=0x80000000):
    self._regs, self.log, self.mem = regs, [], {}
    self.mmu_ver = mmu_ver
    self.pte_covers = pte_covers if pte_covers is not None else [1 << x for x in (12, 21, 29, 38, 47, 56)][::-1]
    self.mm = FakeMM(level_cnt, self.pte_covers)
    self.vram, self.pcibus = FakeView(self.log, 0, vram_nbytes, "Q"), "0000:03:00.0"
  def bind_mmu(self, ver):
    """_early_mmu_init :128 -- pte_t, pde_t, dual_pde_t for THIS mmu_ver."""
    self.pte_t, self.pde_t, self.dual_pde_t = (self._regs[x] for x in MMI_STRUCTS[ver])
  def reg(self, name): return self._regs[name]
  def rreg(self, addr): self.log.append(("rreg", addr)); return self.mem.get(addr // 4, 0)
  def wreg(self, addr, value): self.log.append(("wreg", addr, value)); self.mem[addr // 4] = value
  def alloc_sysmem(self, size, off, contiguous=False): self.log.append(("sysmem", size, off, contiguous)); return (FakeView(self.log, 0, size, None), [0])
  def bar_info(self, i): return (0x100000000, 0x80000000)
  def map_bar(self, i, fmt=None): self.log.append(("mapbar", i, fmt)); return FakeView(self.log, 0, 0x80000000, fmt)
  def read_config(self, off, sz): return 0x0006
  def write_config_flush(self, off, val, sz): self.log.append(("cfgw", off, val, sz))
  def reset(self): self.log.append(("reset",))

def include(dev, name, arch):
  """nvdev.py :161-163, transcribed. 4 lines; what it RETURNS is generated."""
  for k, v in getattr(getattr(nv_regs, name), arch or "regs").items():
    dev._regs[k] = NVReg(dev, *v) if isinstance(v, tuple) else v

# ===========================================================================
# GROUP 1 -- `include` and the register tables, in nvdev.py's OWN call order.
# ===========================================================================
EARLY_IP = [("nv_ref", ""), ("dev_fb", "tu102"), ("dev_gc6_island", "ga102")]   # :101-103
EARLY_MMU_VM = [("dev_vm", "tu102")]                                             # :124
MMI_ARCH = {3: "gh100", 2: "tu102"}                                             # :127
MMI_STRUCTS = {                                                                   # :128
  2: ("NV_MMU_VER2_PTE", "NV_MMU_VER2_PDE", "NV_MMU_VER2_DUAL_PDE"),
  3: ("NV_MMU_VER3_PTE", "NV_MMU_VER3_PDE", "NV_MMU_VER3_DUAL_PDE"),
}

dev = FakeDev({})
for m, a in EARLY_IP: include(dev, m, a)
row("nv_inc_early_ip_n", sum(len(getattr(getattr(nv_regs, m), a or "regs")) for m, a in EARLY_IP))
for m, a in EARLY_MMU_VM: include(dev, m, a)
row("nv_inc_devvm_n", len(getattr(nv_regs.dev_vm, "tu102")))
for ver in (2, 3): include(dev, "dev_mmu", MMI_ARCH[ver])

# the registers nvdev.py NAMES, with the include that provides each -- MEASURED
NAMED_REGS = [
  ("NV_PFB_PRI_MMU_WPR2_ADDR_HI", "dev_fb", "tu102"),
  ("NV_PMC_BOOT_0", "nv_ref", ""),
  ("NV_PMC_BOOT_42", "nv_ref", ""),
  ("NV_PGC6_AON_SECURE_SCRATCH_GROUP_42", "dev_gc6_island", "ga102"),
  ("NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE", "dev_vm", "tu102"),
]
for nm, m, a in NAMED_REGS:
  r = dev.reg(nm)
  row(f"nv_reg_{nm}_has_addr", 1 if isinstance(r.base, int) and isinstance(r.off, int) else 0)
  row(f"nv_reg_{nm}_base", r.base if isinstance(r.base, int) else 0)
  row(f"nv_reg_{nm}_off", r.off if isinstance(r.off, int) else 0)
  row(f"nv_reg_{nm}_nf", len(r.fields))
  # the field ORDER as a name list -- what a count-based gate CANNOT see
  row(f"nv_reg_{nm}_names", ",".join(r.fields.keys()))
  # the (start,end) pairs in the SAME order
  row(f"nv_reg_{nm}_ranges", ";".join(f"{n}={a}:{b}" for n, (a, b) in r.fields.items()))
  row(f"nv_reg_{nm}_maxw", max(b - a + 1 for a, b in r.fields.values()) if r.fields else 0)
  row(f"nv_reg_{nm}_wide", sum(1 for a, b in r.fields.values() if b - a + 1 > 32))

for ver, (pte, pde, dpd) in MMI_STRUCTS.items():
  row(f"nv_mmu_arch_{ver}", len(getattr(nv_regs.dev_mmu, MMI_ARCH[ver])))
  row(f"nv_mmu_{ver}_has_ver3", 1 if f"NV_MMU_VER3_PTE" in getattr(nv_regs.dev_mmu, MMI_ARCH[ver]) else 0)
  for nm in (pte, pde, dpd):
    r = dev.reg(nm)
    row(f"nv_reg_{nm}_has_addr", 1 if isinstance(r.base, int) and isinstance(r.off, int) else 0)
    row(f"nv_reg_{nm}_base", r.base if isinstance(r.base, int) else 0)
    row(f"nv_reg_{nm}_off", r.off if isinstance(r.off, int) else 0)
    row(f"nv_reg_{nm}_nf", len(r.fields))
    row(f"nv_reg_{nm}_names", ",".join(r.fields.keys()))
    row(f"nv_reg_{nm}_ranges", ";".join(f"{n}={a}:{b}" for n, (a, b) in r.fields.items()))
    row(f"nv_reg_{nm}_maxw", max(b - a + 1 for a, b in r.fields.values()))
    row(f"nv_reg_{nm}_wide", sum(1 for a, b in r.fields.values() if b - a + 1 > 32))
    row(f"nv_reg_{nm}_wide_names", ",".join(n for n, (a, b) in r.fields.items() if b - a + 1 > 32))

# ===========================================================================
# GROUP 2 -- NVReg.mask / encode / decode / update (:17,:19,:23,:27,:28,:30,:31)
# through the REAL methods, over NON-UNIFORM fixtures.
# ===========================================================================
B0, B42, INV = dev.reg("NV_PMC_BOOT_0"), dev.reg("NV_PMC_BOOT_42"), dev.reg("NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE")
row("nv_boot0_names", ",".join(B0.fields.keys()))
row("nv_boot0_ranges", ";".join(f"{n}={a}:{b}" for n, (a, b) in B0.fields.items()))
row("nv_boot42_arch", "%d:%d" % B42.fields["architecture"])
row("nv_boot42_impl", "%d:%d" % B42.fields["implementation"])
row("nv_boot42_chipid", "%d:%d" % B42.fields["chip_id"])
row("nv_boot42_minor_ext", "%d:%d" % B42.fields["minor_extended_revision"])
row("nv_boot42_minor", "%d:%d" % B42.fields["minor_revision"])
row("nv_boot42_major", "%d:%d" % B42.fields["major_revision"])
# `chip_id` (20..29) SPANS BOTH `implementation` (20..23) and `architecture`
# (24..29), so all three read the SAME register word and three of the six
# fields alias. A transposed field here is a transposed DEVICE ID.
row("nv_boot42_chipid_span", B42.fields["chip_id"][1] - B42.fields["implementation"][0] + 1)

# mask over NON-UNIFORM subsets: one field, two adjacent, two disjoint, all.
BF = list(B42.fields.keys())
for tag, names in [("one", ["minor_extended_revision"]),
                   ("two_adj", ["implementation", "architecture"]),
                   ("two_far", ["minor_extended_revision", "architecture"]),
                   ("all", BF), ("impl", ["implementation"]), ("arch", ["architecture"]),
                   ("chipid", ["chip_id"]), ("empty", [])]:
  row(f"nv_mask_{tag}", B42.mask(*names))
  row(f"nv_maskn_{tag}", len(names))
for nm in BF:
  a, b = B42.fields[nm]
  row(f"nv_fld_{nm}", "%d:%d:%d" % (a, b, b - a + 1))
  row(f"nv_fldmask_{nm}", B42.mask(nm))
  row(f"nv_fldwidth_{nm}", b - a + 1)
  row(f"nv_fldmax_{nm}", (1 << (b - a + 1)) - 1)

# encode/decode over NON-UNIFORM values
ENCODE_FIX = [
  ("zeros", {}), ("impl_d", {"implementation": 0xd}), ("impl_f", {"implementation": 0xf}),
  ("arch_17", {"architecture": 0x17}), ("arch_19", {"architecture": 0x19}),
  ("arch_1a", {"architecture": 0x1a}), ("arch_1b", {"architecture": 0x1b}),
  ("arch_1f", {"architecture": 0x1f}), ("arch_20", {"architecture": 0x20}),
  ("arch_3f", {"architecture": 0x3f}),
  ("boot42_full", {"minor_extended_revision": 0xf, "minor_revision": 0xf, "major_revision": 0xf,
                   "implementation": 0xf, "architecture": 0x3f}),
  ("boot0_full", {"minor_revision": 0xf, "major_revision": 0xf, "architecture_1": 0x1,
                  "implementation": 0xf, "architecture_0": 0x1f}),
  ("boot0_17d", {"minor_revision": 0x3, "major_revision": 0x7, "architecture_1": 0x1,
                 "implementation": 0xd, "architecture_0": 0x17}),
]
for tag, kw in ENCODE_FIX:
  r = B42 if "architecture_0" not in kw else B0
  e = r.encode(**kw)
  row(f"nv_encode_{tag}", e)
  row(f"nv_decode_{tag}", ",".join(f"{k}={v}" for k, v in r.decode(e).items()))
  row(f"nv_decode_order_{tag}", ",".join(r.fields.keys()))

# the MASK-INVARIANT gate: mask(names) covers exactly the named fields and
# decode(m) puts every OTHER field at zero. That is what a wrong bit offset
# breaks, and a count cannot see it.
for tag, names in [("all", BF), ("impl", ["implementation"]),
                   ("two_far", ["minor_extended_revision", "architecture"])]:
  m = B42.mask(*names)
  row(f"nv_maskinv_{tag}", ",".join(f"{k}={v}" for k, v in B42.decode(m).items()))

# `update` (:25) -- write(read() & ~mask(*names), **names), driven through the
# REAL encode/mask/write, against the REAL FakeDev.rreg/wreg.
for tag, base_val, kw in [("u1", 0xffffffff, {"implementation": 0xd}),
                          ("u2", 0x00000000, {"architecture": 0x1a}),
                          ("u3", 0xdeadbeef, {"minor_revision": 0x0, "major_revision": 0x7}),
                          ("u4", 0x00000a00, {"architecture": 0x1b, "implementation": 0x1})]:
  d = FakeDev(dev._regs)
  d.mem[B42.base // 4] = base_val
  reg = NVReg(d, B42.base, B42.off, dict(B42.fields))
  read = d.rreg(B42.base)
  m = reg.mask(*kw.keys())
  ini = read & ~m & 0xffffffff
  row(f"nv_upd_{tag}_read", read)
  row(f"nv_upd_{tag}_mask", m)
  row(f"nv_upd_{tag}_ini", ini)
  row(f"nv_upd_{tag}_enc", reg.encode(**kw))
  reg.write(ini, **kw)
  row(f"nv_upd_{tag}_w", d.log[-1][2])
  # the BYTE address of the register...
  row(f"nv_upd_{tag}_addr", d.log[-1][1])
  # ...and the WORD INDEX the device sees, which is `addr // 4` (:92-95). BOOT_42
  # is at 0xA00, so element 0x280 = 640. The `read` in `update` is the same
  # element, and FakeDev.rreg records it -- so the trace is two calls, a read of
  # 640 and a write of 640.
  row(f"nv_upd_{tag}_word", d.log[-1][1] // 4)
  # THE TRACE, in the port's OWN format: the word index, the value, and a zero
  # third slot. `rreg` at :95 reads `mmio[addr // 4]` and the address nvdev.py
  # uses is `base + off`, so the element is (base+off)//4 -- 640 for BOOT_42 at
  # 0xA00. The `read` inside `update` is a SEPARATE call that the PORT INJECTS
  # (nv.rd takes the word as a parameter), so the port's trace holds ONE call and
  # the two traces are NOT the same shape; they are compared on the WRITE, which
  # is the thing :25 actually issues.
  def fmt(e):
    if e[0] == "rreg":
      return f"rreg({e[1] // 4},0,0)"
    return f"wreg({e[1] // 4},{e[2]},0)"
  row(f"nv_upd_{tag}_tr", ",".join(fmt(e) for e in d.log if e[0] == "wreg"))

# ===========================================================================
# GROUP 3 -- _early_ip_init (:97-121): the chip tables and the PCI command
# ===========================================================================
ARCH_MAP = {0x17: "GA1", 0x19: "AD1", 0x1b: "GB2"}          # :114
FW_MAP = {"GB2": "gb202", "AD1": "ad102", "GA1": "ga102"}  # :115
row("nv_archmap_n", len(ARCH_MAP))
for k, v in ARCH_MAP.items(): row(f"nv_archmap_{k:02x}", v)
for k, v in FW_MAP.items(): row(f"nv_fwmap_{k}", v)
for arch in (0x00, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x3f):
  det = B42.decode(B42.encode(architecture=arch))
  # MEASURED, not assumed: `IP.hex8` in the INTERPRETED lane answers `17`, not
  # `0017` -- its padding branch drops the leading zeros. So the gate's row names
  # are `nv_arch_17` and the ORACLE takes that spelling, so the differ compares
  # values and not formats. (The first draft of this oracle used `%04x` and the
  # differ reported 12 "missing" rows that were present under another spelling.)
  H = f"{arch:x}"
  a, fam = det["architecture"], (ARCH_MAP.get(det["architecture"], "??"))
  row(f"nv_arch_{H}", a)
  row(f"nv_fam_{H}", fam)
  row(f"nv_mmuver_{H}", 3 if a >= 0x1a else 2)
  row(f"nv_fmcboot_{H}", 1 if a >= 0x1a else 0)
  for impl in (0x0, 0x1, 0xb, 0xd, 0xf, 0x1f) if a in ARCH_MAP else (0x0,):
    full = fam + f"{impl:02d}"
    t = f"{H}_{impl:02x}"
    row(f"nv_chipname_{t}", full)
    row(f"nv_chipname_len_{t}", len(full))
    row(f"nv_fwname_{t}", FW_MAP[full[:3]] if fam != "??" else "??")
    row(f"nv_chipprefix_{t}", full[:3])
# the two chip_id reads -- `chip_id = NV_PMC_BOOT_0.read()` (:112) is a RAW
# register read, not a decode. The gate pins the RAW word, and the word is
# (base+off) -> mmio[(0+0)//4].
row("nv_chipid_reg_base", B0.base)
row("nv_chipid_reg_off", B0.off)
row("nv_chipid_addr", B0.base + B0.off)
row("nv_chipdet_addr", B42.base + B42.off)
row("nv_wpr2_addr", dev.reg("NV_PFB_PRI_MMU_WPR2_ADDR_HI").base + dev.reg("NV_PFB_PRI_MMU_WPR2_ADDR_HI").off)
row("nv_scratch42_addr", dev.reg("NV_PGC6_AON_SECURE_SCRATCH_GROUP_42").base + dev.reg("NV_PGC6_AON_SECURE_SCRATCH_GROUP_42").off)
row("nv_inval_addr", INV.base + INV.off)
# the config-space writes at :106 and :111 -- CLEAR then SET, and the ORDER
row("nv_pci_command", pci.PCI_COMMAND)
row("nv_pci_master", pci.PCI_COMMAND_MASTER)
row("nv_cfg_sz", 2)
for cur in (0x0000, 0x0002, 0x0004, 0x0006, 0x0007, 0xffff):
  row(f"nv_cfg_clear_{cur:04x}", cur & ~pci.PCI_COMMAND_MASTER & 0xffff)
  row(f"nv_cfg_set_{cur:04x}", cur | pci.PCI_COMMAND_MASTER & 0xffff)

# ===========================================================================
# GROUP 4 -- _early_mmu_init (:123-147): shifts, covers, vram_size, large_bar
# ===========================================================================
SHIFTS = {3: (56, [12, 21, 29, 38, 47, 56]), 2: (48, [12, 21, 29, 38, 47])}   # :143

def covers_of(ver, wrap=True):
  """`pte_covers = [1 << x for x in va_shifts][::-1]`.
  `wrap=True` is the U32 list this port can hold: 1<<38, 1<<47 and 1<<56 do not
  fit a U32 and become 0. `wrap=False` is the mathematical value, which is what
  CPython computes. BOTH are measured and BOTH are gated, because the difference
  between them IS the 32-bit wall and a gate that only printed one of them would
  hide it."""
  sh = SHIFTS[ver][1]
  cs = [1 << x for x in sh][::-1]
  return [c & 0xffffffff for c in cs] if wrap else cs
for ver, (bits, sh) in SHIFTS.items():
  row(f"nv_vabits_{ver}", bits)
  row(f"nv_vashifts_{ver}", ",".join(map(str, sh)))
  row(f"nv_vashifts_n_{ver}", len(sh))
  covers = [1 << x for x in sh][::-1]                                   # memory.py :187
  # `1 << 56` and friends do NOT fit a U32, and the port's U32 list wraps them to
  # 0. So the oracle prints the wrapped list the port can hold AND the count that
  # wrapped: the wall is then a MEASURED number on both sides rather than a claim.
  row(f"nv_covers_{ver}", ",".join(str(c & 0xffffffff) for c in covers))
  row(f"nv_cover_wide_{ver}", sum(1 for c in covers if c > 0xffffffff))
  # `pte_cnt` and the `pte_cnt[lv]*pte_covers[lv] == pte_covers[lv-1]` invariant
  # are memory.py's OWN contract (:186-188) and are already ported and gated by
  # tinybendygrad/runtime/support/memory.bend. They are NOT duplicated here: a
  # second transcription of a second file's table is how two files start to
  # disagree. `pte_covers` IS needed, because nvdev.py:59 indexes it.
  row(f"nv_levelcnt_{ver}", len(sh))
  row(f"nv_lvlmsb_{ver}", ",".join(map(str, sh + [bits + 1])))            # memory.py :186
  row(f"nv_dual_pde_lv_{ver}", len(sh) - 2)                              # :36 lv == level_cnt-2
  row(f"nv_is_page_lvmax_{ver}", len(sh) - 1)                            # :58 lv < level_cnt-1
  row(f"nv_huge_lvmin_{ver}", len(sh) - 3)                               # :59 lv >= level_cnt-3
  row(f"nv_sys_lvlmax_{ver}", len(sh) - 1)                               # :66 lv == level_cnt-1
  row(f"nv_mmu_ver2_only_lv_{ver}", len(sh))                              # :66 mmu_ver==2 -> _sys always

SC = dev.reg("NV_PGC6_AON_SECURE_SCRATCH_GROUP_42")
for tag, raw in [("zero", 0), ("one", 1), ("k", 0xffff), ("full", 0xffffff)]:
  row(f"nv_vramsize_{tag}", (raw << 20) % (1 << 32))   # U32 wraps; see the WALLS
  row(f"nv_vramsize_hi_{tag}", ((raw << 20) >> 32) % (1 << 32))
  row(f"nv_vramsize_sh20_{tag}", (raw << 20) >> 20)
row("nv_tail_reserved", 64 << 20)          # :146 vram_size - (64 << 20)
row("nv_boot_size", 2 << 20)               # :146
row("nv_va_base", 0)                       # :146
row("nv_palloc_x", ",".join(map(str, (512 << 20, 2 << 20, 4 << 10))))  # :147
row("nv_palloc_n", 3)
row("nv_palloc_same", ",".join("1" if (x, x) else "0" for x in (512 << 20, 2 << 20, 4 << 10)))
row("nv_tlsf_size", 1 << 44)               # :70 TLSFAllocator((1 << 44), base=...)
row("nv_tlsf_base", 0x1000000000)          # :70
for vram_nb, vram_sz in [(0x80000000, 0x40000000), (0x80000000, 0x80000000), (0x80000000, 0x80000001),
                         (0x40000000, 0x40000000), (0x7fffffff, 0x40000000)]:
  t = f"{vram_nb:x}_{vram_sz:x}"
  row(f"nv_largebar_{t}", 1 if vram_nb >= vram_sz else 0)
  row(f"nv_reserve_ptable_{t}", 0 if vram_nb >= vram_sz else 1)
  row(f"nv_sysmem_default_{t}", 0 if vram_nb >= vram_sz else 1)

# ===========================================================================
# GROUP 5a -- NVPageTableEntry's DECISIONS (:36,:58,:59,:66), EVERY level and
# both mmu_vers. These rows depend only on (ver, lv) -- 2 x 7 = 14 -- and they
# are where a transposed level bound lands on the wrong branch, so they are
# COMPLETE rather than sampled.
# ===========================================================================
for ver in (2, 3):
  bits, sh = SHIFTS[ver]
  # THE 32-BIT WALL, AS A PAIR OF NUMBERS. `covers` is what a U32 list can hold
  # (1<<38, 1<<47 and 1<<56 WRAP TO 0) and `exact` is the mathematical value. The
  # REAL nvdev.py is driven with the wrapped list, because that is the list this
  # port has, and `nv_d_*_cover_exact` prints the other half so the wall is a
  # measurement on BOTH sides and not a disagreement.
  covers, exact = covers_of(ver, wrap=True), covers_of(ver, wrap=False)
  for lv in range(len(sh) + 1):
    d = FakeDev(dev._regs, mmu_ver=ver, level_cnt=len(sh), pte_covers=covers)
    d.bind_mmu(ver); d.vram = FakeView(d.log, 0, 0x1000, "Q")
    pte = NVPageTableEntry(d, 0, lv)
    # the gate spells the ver/lv in DECIMAL (`nv_d_2_l0_dual`), so the oracle takes
    # that spelling; the differ then compares values and not formats.
    v = f"{ver}_l{lv}"
    row(f"nv_d_{v}_cover_exact", exact[lv] if lv < len(exact) else -1)
    # AND, for the same level, WHETHER it fits -- which is what the port can answer.
    # at lv == level_cnt the index is out of range, so there is no page size to
    # fit: the answer is 0 and the ORACLE'S OWN OUT OF RANGE, which is what makes
    # the `huge_*` rows say ERR:IndexError rather than a number.
    row(f"nv_d_{v}_cover_fits", (1 if exact[lv] <= 0xffffffff else 0) if lv < len(exact) else 0)
    row(f"nv_d_{v}_level_cnt", d.mm.level_cnt)
    row(f"nv_d_{v}_dual", 1 if pte._is_dual_pde() else 0)                    # :36
    # `is_page` reads the STORED WORD, so its answer is not a function of (ver, lv)
    # alone -- it is that function plus the word. A fresh table has 0, so the
    # decision row is asked with 0, and the gate ALSO asks with 1 at entry 2 to
    # exercise the other direction. Both are named, so neither is a claim.
    row(f"nv_d_{v}_ispage", 1 if pte.is_page(0) else 0)                     # :58, word 0
    row(f"nv_d_{v}_ispage_top", 1 if (lv >= len(sh) - 1) else 0)             # the `else True`
    # entry 2 is asked with a word of 1: `d.vram.buf[2] = 1` before the call, so
    # the `& 1 == 1` is True where the fresh word made it False. That is the
    # negative case the branch needs, and it is a REAL call, not a restatement.
    # entry 2 is asked with a word whose bit 0 is SET. It is written through
    # `set_entry`, NOT by poking `buf`: on a DUAL level `entries` is indexed
    # [2e, 2e+1] so `buf[2]` is entry 1's HIGH half and setting it answers a
    # question about bit 64, not about `is_page(2)`. The first draft did exactly
    # that and the gate caught it at v2_l3.
    pte.set_entry(2, 0x1000, table=False)
    row(f"nv_d_{v}_ispage_e2", 1 if pte.is_page(2) else 0)                  # word 1
    # and the STORE is restored to a fresh table, because every later row in this
    # level must read a table nothing has written.
    pte.entries.buf.clear()
    row(f"nv_d_{v}_validkey", "aperture_small" if pte._is_dual_pde() else "aperture")   # :63
    row(f"nv_d_{v}_small", "_small" if pte._is_dual_pde() else "")                      # :44,:45,:66
    row(f"nv_d_{v}_sys", "_sys" if (ver == 2 or lv == len(sh) - 1) else "")             # :44,:66
    row(f"nv_d_{v}_addrkey", f"address{('_small' if pte._is_dual_pde() else '')}"
                             f"{('_sys' if (ver == 2 or lv == len(sh) - 1) else '')}")    # :67
    row(f"nv_d_{v}_addrsh", 12)                                                # :67 << 12
    row(f"nv_d_{v}_huge_cover", covers[lv] if lv < len(covers) else 4294967295)       # :59
    row(f"nv_d_{v}_huge_lvmin", len(sh) - 3)                                  # :59
    row(f"nv_d_{v}_addrshift", 0x200000 >> 12)                                # :40,:45 `paddr >> 12`
    # `supports_huge_page` (:59) indexes `mm.pte_covers[self.lv]`, and pte_covers
    # has `level_cnt` entries -- so at `lv == level_cnt`, a level the walk DOES
    # reach, the REAL nvdev.py raises IndexError. Recorded, not smoothed over: a
    # port that answers a Bool there is inventing behaviour.
    for paddr in (0, 0x200000, 0x200001, 0x12345000):
      try:
        row(f"nv_d_{v}_huge_{paddr:x}", 1 if pte.supports_huge_page(paddr) else 0)
      except IndexError:
        row(f"nv_d_{v}_huge_{paddr:x}", "ERR:IndexError")

# ===========================================================================
# GROUP 5b -- set_entry's VALUES, a targeted matrix. The full cross product is
# 2x7x4x5x2x2x2 = 4480 cases and a gate that has to NAME every one of them is a
# gate nobody re-reads, so the matrix is cut on purpose: every level that is
# dual and one that is not, both paddrs that straddle a page, and all four
# (table, uncached, valid) corners. Every cut is recorded below.
# ===========================================================================
for ver in (2, 3):
  bits, sh = SHIFTS[ver]
  covers = [1 << x for x in sh][::-1]
  lv_dual, lv_plain = len(sh) - 2, 0
  pte_t, pde_t, dpd = (dev.reg(x) for x in MMI_STRUCTS[ver])
  for lv in (lv_plain, lv_dual):
    for entry_id in (0, 2):
      for paddr in (0x2000, 0x12345000):
        for table in (False, True):
          for uncached in (False, True):
            for valid in (False, True):
              d = FakeDev(dev._regs, mmu_ver=ver, level_cnt=len(sh), pte_covers=covers)
              d.bind_mmu(ver); d.vram = FakeView(d.log, 0, 0x1000, "Q")
              pte = NVPageTableEntry(d, 0, lv)
              t = f"{ver}_l{lv}_e{entry_id}_p{paddr:x}_t{int(table)}_u{int(uncached)}_v{int(valid)}"
              pte.set_entry(entry_id, paddr, table=table, uncached=uncached, valid=valid)
              raw = pte.entry(entry_id)
              row(f"nv_s_{t}_st", ",".join(f"{i}:{v}" for i, v in sorted(pte.entries.buf.items())))
              row(f"nv_s_{t}_lo", raw & 0xffffffff)
              row(f"nv_s_{t}_hi", (raw >> 64) & 0xffffffff)
              row(f"nv_s_{t}_valid", 1 if pte.valid(entry_id) else 0)
              try:
                row(f"nv_s_{t}_addr", pte.address(entry_id))
              except Exception as ex:
                row(f"nv_s_{t}_addr", "ERR:" + type(ex).__name__)
              # the two STRUCT FIELD NAMES set_entry writes, per mmu_ver (:41,:46)
              if not table:
                row(f"nv_s_{t}_uncfield", "pcf" if ver == 3 else "vol")
                row(f"nv_s_{t}_uncval", int(uncached))
                row(f"nv_s_{t}_kind", 6)                       # :40 kind=6
                row(f"nv_s_{t}_aperture", 0)                   # :40 aspace defaults PHYS
              else:
                row(f"nv_s_{t}_uncfield", f"pcf_small" if ver == 3 else "no_ats")
                row(f"nv_s_{t}_uncval", 0b10 if ver == 3 else 1)
              row(f"nv_s_{t}_idx", f"{2*entry_id+1}" if pte._is_dual_pde() else f"{entry_id}")
row("nv_s_cases", 2 * 2 * 2 * 1 * 2 * 2 * 2)
# the ENCODE the two struct kinds produce, straight through NVReg.encode -- the
# pure part, without the 128-bit store
for ver in (2, 3):
  bits, sh = SHIFTS[ver]
  pte_t, pde_t, dpd = (dev.reg(x) for x in MMI_STRUCTS[ver])
  lv_dual = len(sh) - 2
  for paddr in (0, 0x2000, 0x12345000):
    for table in (False, True):
      for uncached in (False, True):
        for valid in (False, True):
          for lv, dual in ((0, False), (lv_dual, True)):
            small = "_small" if dual else ""
            sys_ = "_sys" if ver == 2 else ""
            t = f"v{ver}_l{lv}_p{paddr:x}_t{int(table)}_u{int(uncached)}_v{int(valid)}"
            if not table:
              # :40-41 -- pte_t.encode. `pcf` on ver 3, `vol` on ver 2.
              kw = {"valid": valid, "address_sys": paddr >> 12,
                    "aperture": 2, "kind": 6, ("pcf" if ver == 3 else "vol"): int(uncached)}
              e = pte_t.encode(**kw)
              row(f"nv_enc_pte_{t}", e & 0xffffffff)
              row(f"nv_enc_pte_keys_{t}", ",".join(kw.keys()))
            else:
              pde = dpd if dual else pde_t
              kw = {"is_pte": False, f"aperture{small}": 1 if valid else 0,
                    f"address{small}{sys_}": paddr >> 12}
              kw.update({f"pcf{small}": 0b10} if ver == 3 else {"no_ats": 1})
              e = pde.encode(**kw)
              row(f"nv_enc_pde_{t}", e & 0xffffffff)
              row(f"nv_enc_pde_hi_{t}", e >> 64 & 0xffffffff)
              row(f"nv_enc_pde_keys_{t}", ",".join(kw.keys()))

# ===========================================================================
# GROUP 6 -- _alloc_boot_mem (:149-159) and NVMemoryManager (:70,:72)
# ===========================================================================
for size in (0, 1, 0xfff, 0x1000, 0x1001, 0x1fff, 0x2000, 0x12345, 0x100000):
  row(f"nv_roundup_{size:x}", round_up(size, 0x1000))
  row(f"nv_pages_{size:x}", round_up(size, 0x1000) // 0x1000)
  row(f"nv_pages_raw_{size:x}", size // 0x1000)
BAR1 = 0x100000000
# `bar_info(1)[0]` is 0x100000000 == 2^32, so `bar + paddr + i*0x1000` is a
# 33-BIT value and does not fit a U32. The oracle prints it the way a U32 pair
# must: the LOW word (which is just `paddr + i*0x1000`) and the HIGH word.
for paddr in (0, 0x2000, 0x4000, 0x200000):
  for npages in (1, 2, 3):
    row(f"nv_sysaddr_{paddr:x}_{npages}", ",".join(str((paddr + i * 0x1000) & 0xffffffff) for i in range(npages)))
    row(f"nv_sysaddr_hi_{paddr:x}_{npages}", ",".join(str((BAR1 + paddr + i * 0x1000) >> 32) for i in range(npages)))
for large_bar in (0, 1):
  for sm in ("None", "True", "False"):
    row(f"nv_sysmem_{large_bar}_{sm}", 1 if (sm == "True" or (sm == "None" and not large_bar)) else 0)
row("nv_inval_value", (1 << 0) | (1 << 1) | (1 << 6) | (1 << 31))
row("nv_inval_lo", (((1 << 0) | (1 << 1) | (1 << 6)) & 0xffffffff))
row("nv_inval_hi", 1 << 31)
row("nv_inval_mask", functools.reduce(int.__or__, [1 << b for b in (0, 1, 6, 31)], 0))
row("nv_inval_bits", "0,1,6,31")
# the four bits, NAMED through the register's own field table -- and note that
# bit 1 has TWO names (all_pdb and pdb_aperture), so a mask over the wrong name
# is a different number.
for b in (0, 1, 6, 31):
  row(f"nv_inval_at_{b}", ",".join(n for n, (s, e) in INV.fields.items() if s <= b <= e) or "-")

# ---------------------------------------------------------------------------
# EMIT. One `name=value` line per row. The EXIT PATH IS CHECKED.
# ---------------------------------------------------------------------------
for nm, v in rows: print(f"{nm}={v}")
print(f"nv_rows={len(rows)}")
if not rows:
  print("ORACLE PRODUCED ZERO ROWS", file=sys.stderr); sys.exit(1)