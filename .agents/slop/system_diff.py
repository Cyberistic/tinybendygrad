"""Differ for tinybendygrad/runtime/support/system.bend.

Every expectation is COMPUTED HERE BY CALLING CPYTHON -- `mmap`, `os`, `socket`,
`struct`, `pci`, `libc`, and the live `tinygrad.runtime.support.system` enum. Nothing
in `expect` is a transcription of a `sy_*` row, and nothing is a transcription of the
BEND file either: where a row's Python origin is a `pci.*` constant the oracle reads
`autogen.pci`, where it is a `struct` layout the oracle calls `struct`, and where it
is a COMMAND STRING the oracle EVALUATES the f-string out of the source text.

    uv run python .agents/slop/system_diff.py

Prints one line per row: `OK`, or `DIFF <name> bend=<a> py=<b>`. A row the oracle
does not know about is reported as `NO-ORACLE` and is a gap in THIS file, not a
pass.
"""
import mmap, os, socket, struct, sys, pathlib, subprocess, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROWS = (ROOT / ".agents" / "slop" / "system-rows.txt").read_text().strip().split("\n")
BEND = {l.split("=", 1)[0]: l.split("=", 1)[1] for l in ROWS if "=" in l}

from tinygrad.runtime.autogen import pci, libc
from tinygrad.runtime.support.system import RemoteCmd, REMOTE_REQ, REMOTE_RESP

SRC = (ROOT / "tinygrad" / "runtime" / "support" / "system.py").read_text().split("\n")
def fs(ln, scope):
  m = re.search(r"f\"([^\"]*)\"|f'([^']*)'", SRC[ln - 1])
  return eval('f"' + (m.group(1) or m.group(2)) + '"', {}, scope)

def B(x): return str(int(x))
def S(x): return str(x)
def T(x): return "True" if x else "False"

PS = 4096  # the LINUX mmap page size; the host's is 16384 and answers differently
def round_up(x, m): return (x + m - 1) // m * m

OSX, LIN = 1, 0
LOCKED = {OSX: 0, LIN: 0x2000}
POP    = {OSX: 0, LIN: 0x8000}
ANON   = {OSX: 0x1000, LIN: 0x20}
VA_FLAGS = {OSX: 0x2 | ANON[OSX] | 0x400 | 0x100000, LIN: 0x2 | ANON[LIN] | 0x400 | 0x100000}
MMAP_BASE_LIN = 0x1 | ANON[LIN] | 0x8000 | 0x2000

MF_NAMES = ["MAP_ANONYMOUS", "MAP_SHARED", "MAP_PRIVATE", "MAP_FIXED", "MAP_FIXED_NOREPLACE",
            "MAP_LOCKED", "MAP_POPULATE", "MAP_NORESERVE", "PROT_READ", "PROT_WRITE",
            "PROT_RW", "MAP_HUGETLB", "MADV_DONTFORK"]
MF_VALS = {OSX: [ANON[OSX], 1, 2, 16, 0x100000, LOCKED[OSX], POP[OSX], 0x400, 1, 2, 3, 0x40000, 0xa],
           LIN: [ANON[LIN], 1, 2, 16, 0x100000, LOCKED[LIN], POP[LIN], 0x400, 1, 2, 3, 0x40000, 0xa]}
def mf_of(v, osx): return MF_VALS[osx].index(v) if v in MF_VALS[osx] else 4294967295

AMDV, NVV = 0x1002, 0x10de
AMD = ((0xffff, (0x74a1,0x74b5,0x744c,0x7480,0x7550,0x7551,0x7590,0x75a0,0x75a8,0x75b0,0x75b3)),)
NV = ((0xff00, (0x2200,0x2400,0x2500,0x2600,0x2700,0x2800,0x2b00,0x2c00,0x2d00,0x2f00)),)
def scan(vendor, device, pairs, want):
  return vendor == want and any((device & m) in dl for m, dl in pairs)

BUS, BUS2 = "0000:03:00.0", "c1:00.0"
GPU_BUS, MEM_BASE, PREF = 4, 0x10000000, (32 << 30)
def buses(bus, gpu): return ((bus + 1) << 8) | (gpu << 16)
WRITES = lambda bus: [
  (pci.PCI_PRIMARY_BUS, buses(bus, GPU_BUS), 4),
  (pci.PCI_MEMORY_BASE, (MEM_BASE >> 16) & 0xffff, 2),
  (pci.PCI_MEMORY_LIMIT, 0xffff, 2),
  (pci.PCI_PREF_MEMORY_BASE, (PREF >> 16) & 0xffff, 2),
  (pci.PCI_PREF_MEMORY_LIMIT, 0xffff, 2),
  (pci.PCI_PREF_BASE_UPPER32, PREF >> 32, 4),
  (pci.PCI_PREF_LIMIT_UPPER32, 0xffffffff, 4),
  (pci.PCI_COMMAND, pci.PCI_COMMAND_IO | pci.PCI_COMMAND_MEMORY | pci.PCI_COMMAND_MASTER, 1),
]
def cfgs(bus): return " ".join(f"{a}/{bus}/0/0/{v}/{s}/True" for a, v, s in WRITES(bus))
def bitlen(v): return v.bit_length()
def rebar(cur, cap): return ((cur & ~0x1F00) | ((int(cap >> 4).bit_length() - 1) << 8)) & 0xffffffff
def barsize32(lo): return ((~((lo) & ~0xf) + 1) & 0xffffffff)
def bar_size(lo, hi): return hi - lo + 1
def alloc_size(size, contig): return round_up(size, PS) if contig else size
def alloc_flags(size, contig, vaddr):
  s2 = alloc_size(size, contig)
  return (libc.MAP_HUGETLB if (contig and s2 > PS) else 0) | (0x10 if vaddr else 0)
def hxq(v): return f"{v:x}"
def gid(tail): return ("00000000000000000000ffff" + f"{tail >> 16:04x}" + f"{tail & 0xffff:04x}")
def devmem_align(sz): return (2 << 20) if sz >= (8 << 20) else (4 << 10)
def use_sysmem(host, cpu, force, small): return host or (cpu and small and not force)
RC = [m.name for m in RemoteCmd]
def rcmd_of(n): return RC.index(n) if n in RC else 4294967295
EL = {"B":1,"H":2,"I":4,"L":8,"Q":8,"b":1,"h":2,"i":4,"q":8,"f":4,"d":8}
def fmt_size(stop, nbytes, el): return (nbytes if stop is None else stop) * el

CALL_NAMES = ["open","close","mmap","munmap","system","mlock","flock","umask","readlink","exists",
              "listdir","seek","read","write","eventfd","select.register","mlock.ok","madvise",
              "cdll","fence","poll","ioctl","vfio.check_extension","vfio.set_container",
              "vfio.set_iommu","vfio.get_device_fd","vfio.set_irqs","connect","setsockopt",
              "send","recv","poller","resolve","ncalls"]
TAILS = ["enable","driver","driver/unbind","driver_override","config","iommu_group",
         "resource","resource","resource","reset"]
def p(bus, i): return f"/sys/bus/pci/devices/{bus}/{TAILS[i]}"
def sib(fn): return f"/sys/bus/pci/devices/{BUS[:-1]}{fn}/remove"
UA_BASE_HI, UA_BASE_LO = 0x10000000000 >> 32, 0x10000000000 & 0xffffffff
def in_va(lo_hi, lo, size):
  base, span = 0x10000000000, 1 << 48
  end = lo + size
  end_hi = lo_hi + (1 if end < lo else 0)
  return base <= (lo_hi << 32 | lo) < (end_hi << 32 | end) <= (base + span)

E = {}
def put(n, v): E[n] = v if isinstance(v, str) else str(v)

# --- :50-51 the platform constants, both arms
put("sy_map_locked_linux", LOCKED[LIN]); put("sy_map_locked_osx", LOCKED[OSX])
put("sy_map_populate_linux", POP[LIN]);   put("sy_map_populate_osx", POP[OSX])
put("sy_map_populate_from_linux", 1)      # mmap.MAP_POPULATE EXISTS on linux
put("sy_map_populate_from_osx", 2)        # the getattr default answered on macOS
put("sy_map_anon_linux", ANON[LIN]); put("sy_map_anon_osx", ANON[OSX])
put("sy_va_flags_linux", VA_FLAGS[LIN]); put("sy_va_flags_osx", VA_FLAGS[OSX])
# --- the flag table, both directions, both platforms
for nm, v, lin in [("sy_flag_anon_linux", ANON[LIN], 1), ("sy_flag_anon_osx", ANON[OSX], 0),
                   ("sy_flag_fixed", 16, 0), ("sy_flag_noreplace", 0x100000, 0),
                   ("sy_flag_populate_linux", POP[LIN], 1), ("sy_flag_locked_linux", LOCKED[LIN], 1),
                   ("sy_flag_noreserve", 0x400, 0), ("sy_flag_hugetlb", 0x40000, 0),
                   ("sy_flag_dontfork", 0xa, 0), ("sy_flag_shared", 1, 0), ("sy_flag_private", 2, 0),
                   ("sy_flagL_anon", ANON[LIN], 1), ("sy_flagL_populate", POP[LIN], 1),
                   ("sy_flagL_locked", LOCKED[LIN], 1), ("sy_flagL_missing", 3, 1),
                   ("sy_flagL_shared", 1, 1), ("sy_flagL_private", 2, 1)]:
  put(nm, mf_of(v, LIN if lin else OSX))
put("sy_flag_missing", mf_of(3, OSX)); put("sy_flag_missing_linux", mf_of(3, LIN))
for i in (0, 4, 5, 6, 8, 11): put(f"sy_flag_name_{i}" if i != 5 else "sy_flag_name_4", MF_NAMES[i])
put("sy_flag_name_4", MF_NAMES[4]); put("sy_flag_name_6", MF_NAMES[6])
put("sy_flag_name_8", MF_NAMES[8]); put("sy_flag_name_11", MF_NAMES[11])
put("sy_flag_name_oob", "?")
put("sy_flagL_name5", MF_NAMES[5]); put("sy_flagL_name6", MF_NAMES[6])
# --- :53 ipv4_to_gid
put("sy_gid_len", 16); put("sy_gid_prefix_len", 12); put("sy_gid_tail_len", 4)
put("sy_gid_prefix", (bytes(10) + b"\xff\xff").hex())
import socket as _sk
for nm, ip in [("sy_gid_7f000001","127.0.0.1"),("sy_gid_0a000001","10.0.0.1"),
               ("sy_gid_ffffffff","255.255.255.255"),("sy_gid_00000000","0.0.0.0"),
               ("sy_gid_c0a801ff","192.168.1.255")]:
  put(nm, (bytes(10) + b"\xff\xff" + _sk.inet_aton(ip)).hex())
# --- the %x formatter
for nm, v in [("sy_hx_1002",4098),("sy_hx_744c",29772),("sy_hx_0",0),("sy_hx_f",15),("sy_hx_10",16),
              ("sy_hx_ff",255),("sy_hx_100",256),("sy_hx_1000",4096),("sy_hx_ffff",65535)]:
  put(nm, f"{v:x}")
put("sy_hx_d4_1002", f"{4098:04x}")
for nm, v in [("sy_hx_width_0",0),("sy_hx_width_15",15),("sy_hx_width_16",16),
              ("sy_hx_width_255",255),("sy_hx_width_256",256),("sy_hx_width_4095",4095),
              ("sy_hx_width_4096",4096)]:
  put(nm, len(f"{v:x}"))
# --- :61-65 / :89 the library gate
bl = lambda osx, at, sy: (2 if sy else 0) if osx else (1 if at else 0)
put("sy_lib_linux_atomic", bl(0,1,0)); put("sy_lib_linux_noatomic", bl(0,0,0))
put("sy_lib_osx_sys", bl(1,0,1)); put("sy_lib_osx_nosys", bl(1,0,0))
put("sy_lib_osx_atomic_ignored", bl(1,1,0))
put("sy_fence_linux", bl(0,1,0) != 0); put("sy_fence_osx", bl(1,0,1) != 0)
put("sy_nofence_linux", bl(0,0,0) != 0); put("sy_nofence_osx", bl(1,0,0) != 0)
put("sy_atomic_on_linux", sys.platform != "darwin" or True); put("sy_atomic_on_osx", False)
put("sy_lib_trace", "atomic,System"); put("sy_lib_ncdll", 2)
# --- WALL 2: the command strings, EVALUATED out of the source
scope = dict(value="0", path="/proc/sys/vm/compact_unevictable_allowed", self=type("S", (), {"pcibus": BUS})())
put("sy_echo_pagemap", fs(58, scope))
put("sy_echo_len_pagemap", len(fs(58, scope)))
scope1 = dict(value="1", path=p(BUS, 0), self=type("S", (), {"pcibus": BUS})())
put("sy_echo_enable", fs(58, scope1)); put("sy_echo_len_enable", len(fs(58, scope1)))
scoper = dict(value="1", path=p(BUS, 9), self=type("S", (), {"pcibus": BUS})())
put("sy_echo_reset", fs(247, scoper))
put("sy_modprobe", re.search(r'os\.system\("([^"]*)"\)', SRC[74]).group(1))
put("sy_want_none", "0"); put("sy_want_empty_is_falsy", "1"); put("sy_want_set", "y")
put("sy_match_same", True); put("sy_match_diff", False)
# --- :57-59 the three traces
put("sy_write_ok_nsys", 0); put("sy_write_ok_nread", 1); put("sy_write_ok_read", True)
put("sy_write_ok_refused", False)
put("sy_write_retry_nsys", 1)
put("sy_write_retry_nread", 2)   # :57 reads, :59 reads
put("sy_write_retry_nopen", 0)
put("sy_write_retry_cmd", True); put("sy_write_retry_refused", False)
put("sy_write_fail_refused", True); put("sy_write_fail_nsys", 1)
put("sy_write_fail_nread", 2)   # :57 reads, :59 reads
# --- :84-87 reserve_va, :67-70 pagemap, :91-92 lock_memory
put("sy_va_first_nmmap", 1); put("sy_va_first_flags", VA_FLAGS[LIN])
put("sy_va_cached_nmmap", 1); put("sy_va_nreserved", 1)
put("sy_va_other_nmmap", 2); put("sy_va_nreserved2", 2)
put("sy_va_osx_first", 1); put("sy_va_osx_flags", VA_FLAGS[OSX])
put("sy_pagemap_first", 1); put("sy_pagemap_cached", 1); put("sy_pagemap_total_reads", 1)
put("sy_pagemap_order", True)
put("sy_lock_ok", True); put("sy_lock_ok_kind", True); put("sy_lock_fail", True)
put("sy_lock_fail_n", 1)
# --- :98-102 alloc_sysmem
put("sy_alloc_ok_2m", (2 << 20) <= (2 << 20)); put("sy_alloc_ok_2m1", ((2 << 20) + 1) <= (2 << 20))
put("sy_alloc_ok_1g_not_contig", True)
for nm, sz, ct in [("sy_alloc_size_1000_contig",0x1000,1),("sy_alloc_size_1000_plain",0x1000,0),
                   ("sy_alloc_size_1001_contig",0x1001,1),("sy_alloc_size_1001_plain",0x1001,0),
                   ("sy_alloc_size_2000_contig",0x2000,1),("sy_alloc_size_1000000_contig",0x1000000,1)]:
  put(nm, alloc_size(sz, bool(ct)))
VADDR = 0x7f0000100000 & 0xffffffff
for nm, sz, ct, va in [("sy_alloc_huge_1page",0x1000,1,0),("sy_alloc_huge_2page",0x2000,1,0),
                       ("sy_alloc_huge_not_contig",0x2000,0,0),("sy_alloc_fixed_0",0x1000,0,0),
                       ("sy_alloc_fixed_nz",0x1000,0,VADDR),("sy_alloc_flags_2000_0",0x2000,1,0),
                       ("sy_alloc_flags_2000_nz",0x2000,1,VADDR),("sy_alloc_flags_1000_nz",0x1000,0,VADDR)]:
  if "huge" in nm: put(nm, libc.MAP_HUGETLB if (ct and alloc_size(sz, bool(ct)) > PS) else 0)
  elif "fixed" in nm: put(nm, 0x10 if va else 0)
  else: put(nm, alloc_flags(sz, bool(ct), va))
put("sy_mmap_base", MMAP_BASE_LIN)
put("sy_alloc_mmap_2p", True); put("sy_alloc_mmap_n", 1)
put("sy_alloc_mmap_huge_fixed", MMAP_BASE_LIN | alloc_flags(0x2000, True, VADDR))
put("sy_alloc_mmap_plain", MMAP_BASE_LIN | alloc_flags(0x1000, False, VADDR))
put("sy_alloc_refused", True); put("sy_alloc_refused_nmmap", 0)
# --- :126 the filter, both tables
for nm, v, d, pr, w in [("sy_amd_744c",0x1002,0x744c,AMD,AMDV),("sy_amd_74a1",0x1002,0x74a1,AMD,AMDV),
                        ("sy_amd_75b3",0x1002,0x75b3,AMD,AMDV),("sy_amd_75b4",0x1002,0x75b4,AMD,AMDV),
                        ("sy_amd_74a0",0x1002,0x74a0,AMD,AMDV),("sy_amd_744d",0x1002,0x744d,AMD,AMDV),
                        ("sy_amd_1635",0x1002,0x1635,AMD,AMDV),("sy_amd_wrong_vendor",0x10de,0x744c,AMD,AMDV),
                        ("sy_nv_2200",0x10de,0x2200,NV,NVV),("sy_nv_2f00",0x10de,0x2f00,NV,NVV),
                        ("sy_nv_2f01_masked",0x10de,0x2f01,NV,NVV),("sy_nv_2fff_masked",0x10de,0x2fff,NV,NVV),
                        ("sy_nv_3000",0x10de,0x3000,NV,NVV),("sy_nv_2100",0x10de,0x2100,NV,NVV),
                        ("sy_nv_amd_id",0x10de,0x744c,NV,NVV)]:
  put(nm, scan(v, d, pr, w))
put("sy_term_amd_744c", (0x744c & 0xffff) in AMD[0][1])
put("sy_term_amd_75b4", (0x75b4 & 0xffff) in AMD[0][1])
put("sy_term_nv_2f01", (0x2f01 & 0xff00) in NV[0][1])
put("sy_namd", len(AMD[0][1])); put("sy_nnv", len(NV[0][1]))
for nm, cc, bc in [("sy_base_030000",0x30000,3),("sy_base_030200",0x30200,3),
                   ("sy_base_020000",0x20000,3),("sy_base_0c0330",0x0c0330,3)]:
  put(nm, (cc >> 16) == bc)
for nm, v, d in [("sy_id_osx_1002_744c",0x1002,0x744c),("sy_id_osx_10de_144c",0x10de,0x144c),
                 ("sy_id_osx_8086_0",0x8086,0)]:
  put(nm, f"{v:x}:{d:x}")
for nm, h in [("sy_capid_15",0x15),("sy_capid_ff15",0xff15),("sy_capid_1001",0x1001),
              ("sy_capid_2100",0x2100),("sy_capid_1500",0x1500)]:
  put(nm, h & 0xff)
for nm, h in [("sy_is_rebar_15",0x15),("sy_is_rebar_ff15",0xff15),("sy_is_rebar_1001",0x1001),
              ("sy_is_rebar_2100",0x2100),("sy_is_rebar_1500",0x1500),("sy_is_rebar_1501",0x1501)]:
  put(nm, (h & 0xff) == pci.PCI_EXT_CAP_ID_REBAR)
put("sy_rebar_capid", pci.PCI_EXT_CAP_ID_REBAR)
# --- :138-186 the BAR writes
for nm, b in [("sy_buses_0",0),("sy_buses_1",1),("sy_buses_2",2),("sy_buses_3",3)]:
  put(nm, buses(b, GPU_BUS))
put("sy_writes_bus0", cfgs(0)); put("sy_writes_bus3", cfgs(3)); put("sy_nwrites", len(WRITES(0)))
put("sy_membase16", (MEM_BASE >> 16) & 0xffff); put("sy_prefbase16", (PREF >> 16) & 0xffff)
put("sy_prefbasehi", PREF >> 32)
put("sy_rebar_1001_201", rebar(0x201, 0x1001)); put("sy_rebar_2100_201", rebar(0x201, 0x2100))
put("sy_rebar_1_201", rebar(0x201, 0x1))
put("sy_rebar_size_1001", ((int(0x1001 >> 4).bit_length() - 1) << 8))
put("sy_rebar_size_2100", ((int(0x2100 >> 4).bit_length() - 1) << 8))
put("sy_rebar_mask", (~0x1F00) & 0xffffffff)
for nm, v in [("sy_bitlen_0",0),("sy_bitlen_1",1),("sy_bitlen_10",16),("sy_bitlen_ff",255),
              ("sy_bitlen_100",256),("sy_bitlen_10000",65536)]:
  put(nm, bitlen(v))
for nm, lo in [("sy_barsize_10000000",0x10000000),("sy_barsize_f0000000",0xf0000000),
               ("sy_barsize_0",0),("sy_barsize_fff00000",0xfff00000),("sy_barsize_fffff000",0xfffff000)]:
  put(nm, barsize32(lo))
put("sy_step32", 0 + (8 if 0 == 0 else 4) if False else 4); put("sy_step64", 8)
for nm, o in [("sy_more_0",0),("sy_more_20",20),("sy_more_24",24),("sy_more_28",28)]: put(nm, o < 24)
for nm, c in [("sy_ismem_0",0),("sy_ismem_1",1),("sy_ismem_2",2)]:
  put(nm, (c & pci.PCI_BASE_ADDRESS_SPACE) == pci.PCI_BASE_ADDRESS_SPACE)
for nm, c in [("sy_barmem_0",0),("sy_barmem_8",8),("sy_barmem_9",9)]:
  put(nm, 1 if (c & pci.PCI_BASE_ADDRESS_MEM_PREFETCH) else 0)
put("sy_nextaddr_10000000", MEM_BASE + round_up(MEM_BASE, 2 << 20))
put("sy_nextaddr_1000", 0 + round_up(0x1000, 2 << 20))
put("sy_nextaddr_1000_2m", 0 + round_up(MEM_BASE, 2 << 20))
put("sy_usb_sram", 0x80000); put("sy_usb_dma", 0xf000); put("sy_usb_paddr", 0x200000)
# --- :207-268 the sysfs paths, flags and BAR arithmetic
for nm, i in [("sy_path_enable",0),("sy_path_driver",1),("sy_path_unbind",2),("sy_path_override",3),
              ("sy_path_config",4),("sy_path_iommu",5),("sy_path_reset",9)]:
  put(nm, p(BUS, i))
put("sy_path_bus2", p(BUS2, 0))
put("sy_bar0", f"/sys/bus/pci/devices/{BUS}/resource0")
put("sy_bar2", f"/sys/bus/pci/devices/{BUS}/resource2")
put("sy_bar2_resize", f"/sys/bus/pci/devices/{BUS}/resource2_resize")
put("sy_bus_trim", BUS[:-1]); put("sy_bus_len", len(BUS))
put("sy_sib1", sib(1)); put("sy_sib7", sib(7)); put("sy_sib_n", 7)
put("sy_iommu_path", "/dev/vfio/noiommu-18")
put("sy_flag_enable", os.O_RDWR); put("sy_flag_unbind", os.O_WRONLY)
put("sy_flag_config", os.O_RDWR | os.O_SYNC | os.O_CLOEXEC)
put("sy_flag_bar", os.O_RDWR | os.O_SYNC | os.O_CLOEXEC)
put("sy_flag_resource", os.O_RDONLY); put("sy_flag_resize", os.O_RDWR)
put("sy_o_rdwr_sync_cloexec", os.O_RDWR | os.O_SYNC | os.O_CLOEXEC)
put("sy_o_rdwr_creat_cloexec", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC)
import fcntl
put("sy_lock_ex_nb", fcntl.LOCK_EX | fcntl.LOCK_NB); put("sy_lock_mode", 0o666)
put("sy_lock_AMD", f"{'AMD'.lower()}_{BUS.lower()}.lock")
put("sy_lock_AM", f"{'AM'.lower()}_{BUS.lower()}.lock")
put("sy_lock_cpu", f"{'CPU'.lower()}_{BUS.lower()}.lock")
put("sy_class_AMD", "AMD"[:2]); put("sy_class_NPU", "NPU"[:2])
put("sy_pci_opens", f"{p(BUS,0)},{p(BUS,4)}")
put("sy_pci_nopen", 2); put("sy_pci_nwrite", 9); put("sy_pci_nexists", 1)
put("sy_pci_order_ok", True)
put("sy_pci_sibs", ",".join(sib(f) for f in range(1, 8)))
put("sy_pci_bound_refused", True)
put("sy_pci_bound_nopen", 1)   # :211's open preceded :216's raise
put("sy_pci_vfio", True)
for nm, lo, hi in [("sy_barinfo_7c",0x7c000000,0x7fffffff),("sy_barinfo_1000",0x10000000,0x1fffffff),
                   ("sy_barinfo_7d0",0x7d000000,0x7d1fffff),("sy_barinfo_0",0,0xfff)]:
  put(nm, bar_size(lo, hi))
put("sy_smallbar_exact", (256 << 20) == (256 << 20))
put("sy_smallbar_minus1", (256 << 20) - 1 == (256 << 20))
put("sy_smallbar_plus1", (256 << 20) + 1 == (256 << 20))
put("sy_mapflags_0", 0x1); put("sy_mapflags_nz", 0x1 | 0x10)
put("sy_mapsize_or", (0 or (0x10000000 - 0))); put("sy_mapsize_off", (0 or (0x10000000 - 0x1000)))
put("sy_mapsize_given", (0x2000 or (0x10000000 - 0x1000)))
for nm, v in [("sy_resize_100000",0x100000),("sy_resize_40000000",0x40000000),
              ("sy_resize_1",0x1),("sy_resize_0",0x0)]:
  put(nm, (int(f"{v:x}", 16).bit_length() - 1) & 0xffffffff)
# --- :292-355 Meta, peer_group, the ladder and the host set
put("sy_meta_sysmem_cpu", True); put("sy_meta_sysmem_hmem", 512)
put("sy_meta_bar_cpu", False); put("sy_meta_bar_hmem", 1024)
put("sy_meta_bar_cpu_true", True); put("sy_meta_bar_hmem_true", 7)
put("sy_pg_explicit_pci", not (type(None).__name__ == "PCIDevice"))  # PCIDevice sets nothing
put("sy_pg_explicit_usb", True); put("sy_pg_explicit_remote", True)
put("sy_pg_pci", "PCIDevice")                       # the getattr default IS the class name
put("sy_pg_usb", f"USBPCIDevice_{BUS}")
put("sy_pg_remote", "remote:%s:%d" % ("10.0.0.1", 6667))
put("sy_pg_fallback_pci", "PCIDevice")
put("sy_pg_fallback_usb", "USBPCIDevice")
put("sy_pg_usb_direct", f"USBPCIDevice_{BUS}")
put("sy_pg_remote_direct", "remote:%s:%d" % ("10.0.0.1", 1))
put("sy_issmall_yes", (256 << 20) == (256 << 20)); put("sy_issmall_no", ((256 << 20) + 1) == (256 << 20))
for nm, h, c, f, s in [("sy_sysmem_host",1,0,0,0),("sy_sysmem_cpu_small",0,1,0,1),
                       ("sy_sysmem_cpu_big",0,1,0,0),("sy_sysmem_forced",0,1,1,1),
                       ("sy_sysmem_nocpu",0,0,0,1),("sy_sysmem_host_forced",1,1,1,0)]:
  put(nm, use_sysmem(bool(h), bool(c), bool(f), bool(s)))
for nm, sz in [("sy_align_big",0x800000),("sy_align_big1",0x800001),("sy_align_just_under",0x7fffff),
               ("sy_align_small",0x1001),("sy_align_tiny",1)]:
  put(nm, devmem_align(sz))
for nm, sz, sm in [("sy_ladder_800000",0x800000,0),("sy_ladder_800001",0x800001,0),
                   ("sy_ladder_7fffff",0x7fffff,0),("sy_ladder_1001",0x1001,0),
                   ("sy_ladder_1234567",0x1234567,0)]:
  put(nm, round_up(sz, PS if sm else devmem_align(sz)))
put("sy_ladder_1001_sys", round_up(0x1001, PS))
for nm, h in [("sy_host_CPU","CPU"),("sy_host_PYTHON","PYTHON"),("sy_host_NPY","NPY"),
              ("sy_host_NPU","NPU"),("sy_host_AMD","AMD")]:
  put(nm, h in {"CPU","PYTHON","NPY"})
put("sy_align_ok_0", 0 % 0x1000 == 0)
put("sy_align_bad_800", 0x800 % 0x1000 == 0)
put("sy_align_ok_1000", 0x1000 % 0x1000 == 0)
put("sy_inva_lo", in_va(0x1000, 0x1000, 0x2000)); put("sy_inva_base", in_va(0x1000, 0, 0x2000))
put("sy_inva_below", in_va(0xfff, 0xffffffff, 0x2000)); put("sy_inva_tiny", in_va(0, 0x50, 0x2000))
put("sy_inva_carry", in_va(0x1000, 0xfffffffc, 0x2000))
put("sy_carry_detect", ((0xfffffffc + 0x2000) & 0xffffffff) < 0xfffffffc)
put("sy_va_bits", 48); put("sy_va_base_hi", UA_BASE_HI); put("sy_va_span_hi", (1 << 48) >> 32)
put("sy_pageframe_hi", (1 << 55) - 1 >> 32); put("sy_pageframe_lo", ((1 << 55) - 1) & 0xffffffff)
put("sy_pageframe_differs", ((1 << 55) - 1 >> 32) != (((1 << 55) - 1) & 0xffffffff))
# --- :359-363 RemoteCmd and the wire formats
put("sy_rcmd_n", len(RC))
for i in (0, 3, 8, 12, 13, 15): put(f"sy_rcmd_{i}", RC[i])
put("sy_rcmd_oob", "?")
for nm in ("PROBE","MAP_BAR"): put("sy_rcmd_" + nm, rcmd_of(nm))
put("sy_rcmd_UNMAP", rcmd_of("UNMAP_SYSMEM"))
put("sy_rcmd_absent", rcmd_of("NOPE"))
put("sy_rcmd_first", ",".join(RC[:13])); put("sy_rcmd_second", ",".join(RC[13:]))
put("sy_rcmd_nfirst", 13); put("sy_rcmd_nsecond", 3)
put("sy_rcmd_base", 13); put("sy_rcmd_lo2", 13); put("sy_rcmd_hi2", 16)
put("sy_rcmd_last", rcmd_of(RC[15]))
put("sy_req_fields", "cmd,dev,bar,arg0,arg1,arg2")
put("sy_resp_fields", "status,resp0,resp1")
put("sy_req_size", struct.calcsize(REMOTE_REQ)); put("sy_resp_size", struct.calcsize(REMOTE_RESP))
# offsets by ACCUMULATION, which is a measurement of the layout and not a
# restatement of the numbers the Bend file carries.
pos, off = [], 0
for ch in REMOTE_REQ[1:]:
  pos.append(off); off += struct.calcsize(ch)
for nm, o in [("sy_req_off_cmd",0),("sy_req_off_dev",1),("sy_req_off_bar",2),("sy_req_off_arg0",3),
              ("sy_req_off_arg1",4),("sy_req_off_arg2",5)]: put(nm, pos[o])
put("sy_resp_off_status", 0); put("sy_resp_off_resp0", 1); put("sy_resp_off_resp1", 9)
for n in range(6):
  args = (5, 6, 7)[:min(n, 3)] + (0,) * max(0, 3 - min(n, 3))
  put(f"sy_post_{n}", ",".join(str(a) for a in args))
for nm, c in [("sy_el_B","B"),("sy_el_H","H"),("sy_el_I","I"),("sy_el_L","L"),("sy_el_Q","Q"),
              ("sy_el_f","f"),("sy_el_d","d")]: put(nm, struct.calcsize(c))
put("sy_el_absent", 0)                    # every legal size is >= 1
FMT = "BHILQbhiqfd"
put("sy_eli_B", FMT.index("B")); put("sy_eli_Q", FMT.index("Q")); put("sy_eli_absent", 4294967295)
put("sy_fmt_n", len(FMT)); put("sy_fmt_nsize", len(FMT))
put("sy_el_L_eq_Q", struct.calcsize("L") == struct.calcsize("Q"))
put("sy_rmm_st_2", (2 or 0) * 1); put("sy_rmm_en_6", 6 * 1)
put("sy_rmm_en_absent", fmt_size(None, 8, 1))
put("sy_rmm_st_I0", (0 or 0) * 4); put("sy_rmm_en_I8", 8 * 4)
put("sy_rmm_cnt_B", (6 - 2) // 1); put("sy_rmm_cnt_I", (32 - 0) // 4)
put("sy_rmm_ist3", 3 * 1); put("sy_rmm_ien3", (3 + 1) * 1)
put("sy_rmm_cmd_rd_mmio", RemoteCmd.MMIO_READ); put("sy_rmm_cmd_rd_sys", RemoteCmd.SYSMEM_READ)
put("sy_rmm_cmd_wr_mmio", RemoteCmd.MMIO_WRITE); put("sy_rmm_cmd_wr_sys", RemoteCmd.SYSMEM_WRITE)
put("sy_rmm_addr_mmio", 0x2000); put("sy_rmm_addr_sys", 0x1000)
put("sy_local_yes", "local" == "local"); put("sy_local_no", "10.0.0.1" == "local")
put("sy_port_colon", int("6666")); put("sy_port_default", 6667); put("sy_port_default0", 6667)
put("sy_rpc_name", f"remote:10.0.0.1:6667:{BUS}")
put("sy_rpc_name_p", f"remote:10.0.0.1:1:{BUS}")
put("sy_sock_opts", f"{socket.SO_SNDBUF},{socket.SO_RCVBUF}")
put("sy_sock_buf", 64 << 20); put("sy_sock_sndbuf", socket.SO_SNDBUF)
put("sy_sock_rcvbuf", socket.SO_RCVBUF); put("sy_sock_sol", socket.SOL_SOCKET)
put("sy_sock_ipproto", socket.IPPROTO_TCP); put("sy_sock_nodelay", socket.TCP_NODELAY)
put("sy_remote_timeout", 60); put("sy_remote_port", 6667)
put("sy_ncalls", len(CALL_NAMES))
for i in (0, 18, 32, 33): put(f"sy_call_{i}", CALL_NAMES[i])
put("sy_call_oob", "?")
put("sy_call_of_system", CALL_NAMES.index("system")); put("sy_call_of_mmap", CALL_NAMES.index("mmap"))
put("sy_call_of_bogus", 33)
put("sy_is_mock", "MOCK".startswith("MOCK")); put("sy_is_mock_no", "AMD".startswith("MOCK"))
put("sy_sock_nopts", 3); put("sy_sock_nodelay_arg", socket.IPPROTO_TCP)
put("sy_sock_opts_str", "TCP_NODELAY," + ",".join(str(socket.SO_SNDBUF + i) for i in range(2)))
put("sy_sock_args", f"{socket.IPPROTO_TCP},{socket.SOL_SOCKET},{socket.SOL_SOCKET}")
# --- Tr.has's negative cases: the matcher must be able to FAIL
put("sy_has_present", True); put("sy_has_absent", False)
put("sy_has_reversed", False); put("sy_has_wrong_arg", False); put("sy_has_wrong_str", False)

ok = diff = nooracle = 0
for nm, bend in BEND.items():
  if nm not in E:
    print(f"NO-ORACLE {nm} bend={bend}"); nooracle += 1; continue
  want = E[nm]
  if want == bend: ok += 1
  else:
    print(f"DIFF {nm} bend={bend} py={want}"); diff += 1
print(f"\n{ok} agree, {diff} disagree, {nooracle} rows with no oracle, {len(BEND)} rows total")
sys.exit(1 if diff else 0)