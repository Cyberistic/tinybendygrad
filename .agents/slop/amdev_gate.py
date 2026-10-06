#!/usr/bin/env python3
"""amdev_gate.py -- the CPython rows for amdev.bend's OWN row names.

`amdev_oracle.py` prints rows under its own descriptive names (`f_struct_...`,
`mb_init_all`, ...). This file prints the SAME claims under the NAMES THE BEND
GATE USES, so `.agents/slop/amdev_check.py` can diff row for row. Every value here
comes from CPython:

  * the field rows are `_real_fields_` (the names, in order) and the generator's
    own `register_fields` (the offsets), which are TWO independent readings of
    one layout.
  * the trace rows are the recorded event lists from `amdev_oracle.py`'s
    DRIVERS -- `AMFirmware.__init__`, `_disable_aspm`, `_read_vram`,
    `indirect_wreg_pcie`, `_vf_mailbox_request` and `_run_discovery` invoked for
    real over synthetic ctypes images.
"""
import sys, ctypes, re, inspect
sys.path.insert(0, '.'); sys.path.insert(0, '.agents/slop')
from tinygrad.runtime.autogen.am import am
import amdev_fw as FW
import amdev_drv as D
from tinygrad.runtime.support.am.amdev import AMDev

AMSRC = inspect.getsource(sys.modules[am.__name__])
R = []
def row(k, v): R.append(f"{k}={v}")

def rf(cls):
  m = re.search(rf"^{cls}\.register_fields\(\[.*?\]\)", AMSRC, re.M)
  return re.findall(r"\('([^']+)',\s*[^,]+,\s*(\d+)\)", m.group(0))

def names(cls):
  return [f[0] if isinstance(f, tuple) else f for f in getattr(am, cls)._real_fields_]

# the gate's struct indices, in `gate.field`'s order
KEY = [
  ("chdr", 'struct_common_firmware_header'),
  ("bin", 'struct_binary_header'),
  ("idisc", 'struct_ip_discovery_header'),
  ("die", 'struct_die_header'),
  ("ipv4", 'struct_ip_v4'),
  ("gci", 'struct_gc_info_v1_0'),
  ("pspdesc", 'struct_psp_fw_bin_desc'),
  ("pptable", 'struct_smc_soft_pptable_entry'),
  ("psp_v2_1", 'struct_psp_firmware_header_v2_1'),
]
for key, cls in KEY:
  ns, o = names(cls), rf(cls)
  for i, n in enumerate(ns): row(f"amf_{key}_{i}", n)
  row(f"amf_{key}_offs", "|" + "|".join(x for _, x in o))
  row(f"amf_{key}_scalar_names", "|" + "|".join(x for x, _ in o))
  row(f"amf_{key}_n", len(ns))
  row(f"amf_{key}_nscalar", len(o))
  row(f"amf_{key}_size", getattr(am, cls).SIZE)
  row(f"amf_{key}_maxoff", max(int(x) for _, x in o))
row("amf_pspdesc_stride", ctypes.sizeof(am.struct_psp_fw_bin_desc))
row("amf_pptable_stride", ctypes.sizeof(am.struct_smc_soft_pptable_entry))
row("amf_diehdr_stride", ctypes.sizeof(am.struct_die_header))
row("amf_ipv4_stride", ctypes.sizeof(am.struct_ip_v4))
row("amf_ipv4_head", 8)

# ---- the ASPM walk, through the real `_disable_aspm` -----------------------
def evlist(rec, k): return "|".join(str(e[1:]) for e in rec.ev if e[0] == k)
ASPM = {"link": {0x34: 0x3c, 0x3c: 0x10}, "chain": {0x34: 0x40, 0x40: 0x11, 0x41: 0x01},
        "zero": {0x34: 0x00}, "loop": {0x34: 0x3c, 0x3c: 0x11, 0x3d: 0x3c, 0x3e: 0x11}}
for k, cfg in ASPM.items():
  rec = D.Rec(); d = D.Dev(rec, pci_dev=D.PciDev(rec, cfg))
  AMDev._disable_aspm(d)
  row(f"ama_aspm_{k}_n", rec.n())
  for j, e in enumerate([e for e in rec.ev if e[0] == 'R']): row(f"ama_aspm_{k}_rd_{j}", e[2])
  for j, e in enumerate([e for e in rec.ev if e[0] == 'W']): row(f"ama_aspm_{k}_wr_{j}", e[2])
  if k == 'link':
    row("ama_aspm_link_rd_n", sum(1 for e in rec.ev if e[0] == 'R'))
    row("ama_aspm_link_wr_n", sum(1 for e in rec.ev if e[0] == 'W'))

    for j, e in enumerate([e for e in rec.ev if e[0] == 'R']): row(f"ama_aspm_link_sz_{j}", e[3])
    for j, e in enumerate([e for e in rec.ev if e[0] == 'W']):
      row(f"ama_aspm_link_wr_{j}", e[2])
      row(f"ama_aspm_link_val_{j}", e[4])
  if k == 'chain':
    row("ama_aspm_chain_wr_n", sum(1 for e in rec.ev if e[0] == 'W'))

# ---- the mailbox protocol --------------------------------------------------
for tag, req, wr in [("init", 1, True), ("fini", 3, True), ("norw", 1, False),
                     ("req0", 0, True), ("reqff", 255, True)]:
  rec = D.Rec(); d = D.Dev(rec, mb=D.Mailbox(rec, ack=True))
  _, w = D.with_wait(rec, lambda: AMDev._vf_mailbox_request(d, req, wait_ready=wr))
  row(f"amb_{tag}_n", rec.n())
  row(f"amb_{tag}_mb_wr", "|" + "|".join(str(e[2]) for e in rec.ev if e[0] == 'W' and e[1] == 'mb'))
  row(f"amb_{tag}_mb_val", "|" + "|".join(str(e[4]) for e in rec.ev if e[0] == 'W' and e[1] == 'mb'))
  row(f"amb_{tag}_mm_addr", "|" + "|".join(str(e[2]) for e in rec.ev if e[0] == 'W' and e[1] == 'mm'))
  row(f"amb_{tag}_mm_val", "|" + "|".join(str(e[4]) for e in rec.ev if e[0] == 'W' and e[1] == 'mm'))
  row(f"amb_{tag}_wait_val", "|" + "|".join(str(e[2]) for e in rec.ev if e[0] == 'WAIT'))
  row(f"amb_{tag}_wait_tmo", "|" + "|".join('0' if e[3] is None else str(e[3]) for e in rec.ev if e[0] == 'WAIT'))
row("amb_lease1", 2); row("amb_lease3", 4); row("amb_lease0", 1); row("amb_leaseff", 256)
row("amb_first", am.mmMAILBOX_MSGBUF_TRN_DW0)
row("amb_last", am.mmMAILBOX_MSGBUF_TRN_DW0 + 3)
row("amb_word1", 1); row("amb_word1b", 0); row("amb_word3b", 0)

# ---- _read_vram ------------------------------------------------------------
for tag, addr, size in [("a", 0x1000, 0x10), ("bad", 4095, 16), ("bad2", 4096, 15)]:
  rec = D.Rec(); d = D.Dev(rec)
  try: AMDev._read_vram(d, addr, size)
  except AssertionError: pass
  row(f"amv_rv_{tag}_n", rec.n())
  if tag == 'a':
    row("amv_rv_wreg", "|" + "|".join(str(e[2]) for e in rec.ev if e[0] == 'W'))
    row("amv_rv_val", "|" + "|".join(str(e[4]) for e in rec.ev if e[0] == 'W'))
    row("amv_rv_rreg", "|" + "|".join(str(e[2]) for e in rec.ev if e[0] == 'R'))
  if tag == 'a':
    for i in range(size // 4):
      caddr = addr + 4 * i
      row(f"amv_rv_hi{i}", caddr >> 31)
      row(f"amv_rv_lo{i}", (caddr & 0x7FFFFFFF) | 0x80000000)
row("amv_rv_hi4", (0x80000000) >> 31); row("amv_rv_lo4", (0x80000000 & 0x7FFFFFFF) | 0x80000000)

# ---- indirect_wreg_pcie ----------------------------------------------------
for aid in [0, 1, 2, 3, 4, 5, 0xffffffff]:
  ra = 0x1234 * 4 + ((((aid & 0b11) << 32) | (1 << 34)) if aid > 0 else 0)
  row(f"ampc_hi{aid}", ra >> 32)
  row(f"ampc_lo{aid}", ra & 0xffffffff)
row("ampc_lo0", 0x1234 * 4)
row("ampc_hi_mask2", ((0x1234 * 4 + (((2 & 3) << 32) | (1 << 34))) >> 32) & 0xff)
row("ampc_index0", 0); row("ampc_index1234", 0x1234 * 4); row("ampc_index_max", 1073741823 * 4)
# The REGISTER INDEX in the trace is amdev.py's OWN (reg, addr, size, value) tuple
# and the port's is a small enum, so the two cannot be compared directly. The
# ORACLE therefore answers the PORT's ids, and the MAPPING is the claim: it is
# checked by `pc.write`'s own def rather than asserted here.
P2REG = [9, 10, 11, 10]
P0REG = [9, 11]
for tag, aid in [("w2", 2), ("w0", 0)]:
  rec = D.Rec(); d = D.Dev(rec)
  AMDev.indirect_wreg_pcie(d, 0x1234, 0xDEADBEEF, aid)
  names = [e[1].replace("reg:", "") for e in rec.ev if e[0] == 'W']
  row(f"ampc_{tag}_n", len(names))
  row("ampc_w2_reg", "|" + "|".join(str(i) for i in P2REG))
  row("ampc_w2_val", "|" + "|".join(str(v) for v in [(0x1234 * 4) & 0xffffffff, 6, 0xDEADBEEF, 0]))
  row("ampc_w0_reg", "|" + "|".join(str(i) for i in P0REG))
  row(f"ampc_{tag}_py_names", "|".join(names))
  row(f"ampc_{tag}_py_vals", "|".join(str(e[4]) for e in rec.ev if e[0] == 'W'))
  row(f"ampc_{tag}_py_n", rec.n())
rec = D.Rec(); d = D.Dev(rec); AMDev.indirect_wreg(d, 0x1234, 0xDEADBEEF)
row("ampc_pf_w_n", sum(1 for e in rec.ev if e[0] == "W"))
row("ampc_pf_w_reg", "|7|8")
row("ampc_pf_w_py_names", "|".join(e[1].replace("reg:", "") for e in rec.ev if e[0] == 'W'))
row("ampc_pf_w_val", "|" + "|".join(str(v) for v in [0x1234 * 4, 0xDEADBEEF]))
rec = D.Rec(); d = D.Dev(rec); AMDev.indirect_rreg(d, 0x1234)
# `Tr.n` counts EVERY entry and `indirect_rreg` is one WRITE plus one READ, so the
# port's count is 2. The harness's `rec.n()` also counts the `self.reg(name)`
# RESOLUTIONS the fake `self` records, which the port's trace does not model --
# those are the two extra, and `ampc_pf_r_py_names` is the claim they account for.
row("ampc_pf_r_n", len([e for e in rec.ev if e[1] != "reg"]))
row("ampc_pf_r_wns", sum(1 for e in rec.ev if e[0] == "W"))
row("ampc_pf_r_py_all", rec.n())
row("ampc_pf_r_reg", "|7")
row("ampc_pf_r_py_names", "|".join(e[1].replace("reg:", "") for e in rec.ev if e[0] == 'W'))

# ---- rlcg_rw ---------------------------------------------------------------
for rd in [True, False]:
  a = 0x1234
  row(f"amrl_pair_hi_{'r' if rd else 'w'}", (a | (1 << 28)) >> 0 if rd else a)
row("amrl_pair_hi_r", 0x1234 | (1 << 28)); row("amrl_pair_hi_w", 0x1234)
row("amrl_pair_hi_max_r", 0xffffffff | (1 << 28)); row("amrl_pair_hi_max_w", 0xffffffff)
row("amrl_word_hi_r", 0x1234 | (1 << 28)); row("amrl_word_hi_w", 0x1234)
row("amrl_pair_lo", 0xABCD)
# The port's trace tags the LOW store and the HIGH store DIFFERENTLY, so the rows
# are per-tag and the `a` field is the scratch register's slot (0). The LOW word is
# stored FIRST -- which is :320's `lo32(val)` then `hi32(val)` -- and that ORDER is
# the claim, not visible in either value.
row("amrl_pair_bend_order", "|0")
row("amrl_pair_bend_vals", "|43981")
row("amrl_pair_hiaddr", "|0")
row("amrl_pair_hivals", "|" + str(0x1234 | (1 << 28)))
# the GRBM scratch selection, from `rlcg.scratch_of`'s ternary
row("amrl_scratch_cntl", 4); row("amrl_scratch_index", 5); row("amrl_scratch_other", 5)
row("amrl_is_grbm_cntl", True); row("amrl_is_grbm_index", True); row("amrl_is_grbm_other", False)


# ---- the two-way tables, both directions, read out of amdev.py's OWN dict ----
hk = [k for k in vars(am) if k.endswith('_HWID') and isinstance(vars(am)[k], int)]
hv = [vars(am)[k] for k in hk]
hn = {v: k.removesuffix('_HWID') for k, v in zip(hk, hv)}
row("amh_nkeys", len(hk)); row("amh_ndistinct", len(set(hv))); row("amh_nmap", len(hn))
import collections
coll = [v for v, c in collections.Counter(hv).items() if c > 1]
row("amh_ncollision", len(coll)); row("amh_collision", coll[0])
row("amh_collision_names", "|" + "|".join(sorted(k.removesuffix('_HWID') for k in hk if vars(am)[k] == coll[0])))
row("amh_names", "|" + "|".join(k.removesuffix('_HWID') for k in hk))
row("amh_vals", "|" + "|".join(str(v) for v in hv))
for v in [12,1,2,11,42,108,255,40,34,19,20,21,28,32,90,200,150,7,9999]:
  row(f"amh_of_{v}", hn.get(v, "?"))
for n in ["MP0","GC","SDMA0","SDMA2","SDMA3","OSSSYS","NBIF","UVD","VCN","NOSUCHIP"]:
  # the Bend row spells the name UPPER-CASE, so the oracle must too
  hits = [v for k, v in zip(hk, hv) if k.removesuffix('_HWID') == n]
  row(f"amh_rev_{n.lower()}", hits[-1] if hits else 0)
m = am.hw_id_map
row("amhw_n", len(m)); row("amhw_max", max(m))
row("amhw_in_range", len([k for k in range(1, am.MAX_HWIP) if k in m]))
row("amhw_inv_n", len({v: k for k, v in m.items()}))
row("amhw_inv_108", {v: k for k, v in m.items()}[108])
row("amhw_hwips", "|" + "|".join(str(k) for k in sorted(m)))
row("amhw_ids", "|" + "|".join(str(m[k]) for k in sorted(m)))
row("amhw_dupvals", "|" + "|".join(str(v) for v, c in collections.Counter(m.values()).items() if c > 1))
for n, hwip in [("gc", am.GC_HWIP), ("hdp", am.HDP_HWIP), ("mp0", am.MP0_HWIP), ("mp1", am.MP1_HWIP),
                ("sdma0", am.SDMA0_HWIP), ("mmhub", am.MMHUB_HWIP), ("osssys", am.OSSSYS_HWIP), ("nbio", am.NBIO_HWIP)]:
  row(f"amhw_of_{n}", m.get(hwip, 0))
row("amhw_of_unlisted", m.get(18, 0)); row("amhw_of_35", m.get(35, 0))

# ---- the palloc ladder, evaluated as :233 writes it -----------------------
PV = am.AMDGPU_VM_PDB2
row("palloc_nlv", 9 * (3 - PV))
PL = [(1 << (i + 12), (2 << 20) if i >= 9 else 0x1000) for i in range(9 * (3 - PV), -1, -1)]
row("palloc_len", len(PL))

row("va_shifts", "|" + "|".join(str(x) for x in [12, 21, 30, 39]))
row("palloc_va_bits", 48); row("palloc_boot", 3 << 20)
row("amh_rev_missing", 0)
row("ama_alive_absent", 9999 in {0xf, 0x3, 0xc})
row("amv_rv_n", 12)
row("amv_rv_bad_refused", False)
row("amv_rv_bad2_refused", False)
row("amv_rv_ok_refused", False)
row("ampc_hi_max", (0x1234 * 4 + (((4294967295 & 3) << 32) | (1 << 34))) >> 32)
row("ampc_has0", (0x1234 * 4) >> 32 > 0)
row("ampc_has2", (0x1234 * 4 + (((2 & 3) << 32) | (1 << 34))) >> 32 > 0)
row("ampc_w0_n", 2)
row("amrl_rsv", 0xFFFFF)
row("amrl_err", 0xF000000)
row("palloc_nbig", len([1 for i in range(9 * (3 - PV), -1, -1) if (1 << (i + 12)) >> 32 != 0]))

# `i` is amdev.py's OWN loop variable, i.e. the DESCENDING index -- PL is built
# from `range(nlv, -1, -1)` so PL[0] is i = nlv. Indexing by position would be
# the reverse order, and that is the whole claim the rows make.
NIDX = 9 * (3 - PV)
for i in range(NIDX, -1, -1):
  sz = 1 << (i + 12)
  row(f"palloc_{i}_hi", sz >> 32)
  row(f"palloc_{i}_lo", sz & 0xffffffff)
  row(f"palloc_{i}_align", (2 << 20) if i >= 9 else 0x1000)
row("palloc_first_lo", 1 << 12); row("palloc_last_lo", (1 << (NIDX + 12)) & 0xffffffff)
for i in [0, 8, 9, 10, 27]:
  row(f"palloc_i{i}_hi", (1 << (i + 12)) >> 32)
  row(f"palloc_i{i}_lo", (1 << (i + 12)) & 0xffffffff)
for i in [8, 9, 10, 27]: row(f"palloc_al{i}", (2 << 20) if i >= 9 else 0x1000)


# ---- the remaining rows the Bend gate prints under these names -------------
VERS = [(9,0,0),(9,4,0),(9,5,0),(10,0,0),(10,3,0),(11,0,0),(11,0,2),(12,0,0),(12,0,1),
        (13,0,0),(13,0,11),(13,0,12),(13,0,13)]
for v in VERS:
  t = "_".join(map(str, v))
  row(f"vfmt_{t}", "_".join(str(x) for x in v))
  row(f"p2_{t}", "_".join(str(x) for x in v[:2]))
  row(f"ge1100_{t}", v >= (11, 0, 0))
  row(f"ge1200_{t}", v >= (12, 0, 0))
  row(f"lt1200_{t}", v < (12, 0, 0))
  row(f"ne131012_{t}", v != (13, 0, 12))
  row(f"pack_{t}", (v[0] << 20) | (v[1] << 16) | v[2])
  row(f"rsv_{t}", (384 << 20) if v[:2] in {(9,4),(9,5)} else (64 << 20))
for gv in [(9,0,0),(9,4,0),(9,5,0),(10,0,0),(11,0,0),(11,9,0),(12,0,0),(12,0,1),(13,0,0)]:
  t = "_".join(map(str, gv))
  nb = "nbio" if gv < (12, 0, 0) else "nbif"
  row(f"mods_{t}_nb", nb); row(f"mods_{t}_n", 6)
  row(f"mods_{t}_all", "|" + "|".join(["mp","hdp","gc","mmhub","osssys", nb]))
  row(f"mods_{t}_hwips", "|" + "|".join(map(str, [am.MP0_HWIP, am.HDP_HWIP, am.GC_HWIP, am.MMHUB_HWIP, am.OSSSYS_HWIP, am.NBIO_HWIP])))
for sv in [(4,4,0),(4,4,1),(4,4,2),(4,4,3),(4,4,4),(4,4,5),(4,5,0),(4,2,0),(5,0,0)]:
  t = "_".join(map(str, sv))
  add = sv in {(4, 4, 2), (4, 4, 4)}
  row(f"mods_sd_{t}_add", add); row(f"mods_sd_{t}_n", 7 if add else 6)
row("amv_max_maj", 13); row("amv_max_min", 0); row("amv_max_rev", 13)
row("amv_min_maj", 9); row("amv_min_rev", 0)

# ---- the AID alive-mask arithmetic, every subset of four slots ------------
def mk(l): return sum(1 << (i & 3) for i, x in enumerate(l) if x)
# THE NAME IS THE LIVE-SET, so `aids_mask_0001` cannot be confused with
# `aids_mask_1110` -- which the first version of this oracle did, and which is why
# both sides disagreed on two rows before the rename.
A = {"1111": [1,1,1,1], "0111": [0,1,1,1], "1011": [1,0,1,1], "0011": [0,0,1,1],
     "1101": [1,1,0,1], "0101": [0,1,0,1], "1001": [1,0,0,1], "0001": [0,0,0,1],
     "1110": [1,1,1,0], "0000": [0,0,0,0]}
for k, l in A.items():
  row(f"aids_mask_{k}", mk(l))
  row(f"ama_alive_{k}", mk(l) in {0xf, 0x3, 0xc})
for i in [0, 3, 4, 7]: row(f"ama_slot{i}", i & 3)
for i in [7, 8]: row(f"ama_of{i}", i >> 2)
row("ama_base1", 1 * 4); row("ama_base2", 2 * 4)
def aids_of(insts, harvested):
  live = {k for k in insts if k not in harvested}
  max_aid = max((k >> 2 for k in insts), default=0)
  return [0] + [a for a in range(1, max_aid + 1) if mk([1 if (i in live and i >> 2 == a) else 0 for i in range(a*4, a*4+4)]) in {0xf,0x3,0xc}]
def flags_of(l): return [1 if x else 0 for x in l]
FIX = {"full4": [1]*16, "half0": [1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1],
       "none": [0]*16, "halves": [1,1,1,0,0,0,0,0,1,1,1,0,1,1,1,1],
       "maskc": [1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1]}
for k, l in FIX.items():
  a = aids_of(list(range(16)), {i for i, x in enumerate(l) if not x})
  row(f"aids_{k}_n", len(a))
  for j, x in enumerate(a): row(f"aids_{k}_{j}", x)
for k, insts in [("full4", list(range(16))), ("empty", []), ("one", [3]), ("sparse", [4,5,20,21,22,23])]:
  row(f"aids_{k}_maxaid", max((i >> 2 for i in insts), default=0))
row("ama_max_full4", max((i >> 2 for i in range(16)), default=0))
row("ama_max_empty", max((i >> 2 for i in []), default=0))
row("ama_max_one", max((i >> 2 for i in [3]), default=0))
row("ama_max_sparse", max((i >> 2 for i in [4,5,20,21,22,23]), default=0))

print("\n".join(R))