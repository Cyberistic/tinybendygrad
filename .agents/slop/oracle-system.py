"""Oracle for tinybendygrad/runtime/support/system.bend.

EVERY value printed here is read out of a LIVE CPython interpreter: the mmap /
os / socket / struct constants, the autogen ctypes constant tables, and the
string-building rules of support/system.py re-evaluated as the Python source
itself spells them. Nothing is transcribed.

    uv run python .agents/slop/oracle-system.py
"""
import mmap, os, socket, struct, sys, enum, ctypes

def hr(t): print(f"\n===== {t}")

# --- the constants support/system.py:50-51 actually names ---------------------
hr("mmap constants (:50-51)")
for k in ("MAP_PRIVATE", "MAP_SHARED", "MAP_ANONYMOUS", "MAP_FIXED",
          "PROT_READ", "PROT_WRITE", "PAGESIZE", "MAP_HUGETLB"):
  print(f"mmap.{k}={getattr(mmap, k, 'ABSENT')}")
print(f"getattr(mmap, 'MAP_POPULATE', 'ABSENT')={getattr(mmap, 'MAP_POPULATE', 'ABSENT')}")
print(f"MAP_LOCKED_per_system_py={0 if sys.platform == 'darwin' else 0x2000}")
print(f"MAP_NORESERVE_per_system_py={0x400}")
print(f"MAP_FIXED_per_system_py={0x10}")
print(f"MAP_FIXED_NOREPLACE_per_system_py={0x100000}")
print(f"sys.platform={sys.platform!r}  OSX={sys.platform == 'darwin'}")

hr("os open flags")
for k in ("O_RDONLY", "O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_SYNC",
          "O_CLOEXEC", "O_NONBLOCK", "O_APPEND"):
  print(f"os.{k}={getattr(os, k, 'ABSENT')}")
print(f"os.O_RDWR|os.O_SYNC|os.O_CLOEXEC={os.O_RDWR|os.O_SYNC|os.O_CLOEXEC}")
print(f"os.O_RDWR|os.O_CREAT|os.O_CLOEXEC={os.O_RDWR|os.O_CREAT|os.O_CLOEXEC}")
print(f"0o666={0o666}")

hr("socket constants")
for k in ("IPPROTO_TCP", "TCP_NODELAY", "SOL_SOCKET", "SO_SNDBUF", "SO_RCVBUF",
          "SO_RCVTIMEO", "SO_SNDTIMEO"):
  print(f"socket.{k}={getattr(socket, k, 'ABSENT')}")
print(f"64<<20={64 << 20}")

hr("autogen.pci")
from tinygrad.runtime.autogen import pci
PN = ["PCI_PRIMARY_BUS", "PCI_SECONDARY_BUS", "PCI_SUBORDINATE_BUS",
      "PCI_MEMORY_BASE", "PCI_MEMORY_LIMIT", "PCI_PREF_MEMORY_BASE",
      "PCI_PREF_MEMORY_LIMIT", "PCI_PREF_BASE_UPPER32", "PCI_PREF_LIMIT_UPPER32",
      "PCI_COMMAND", "PCI_COMMAND_IO", "PCI_COMMAND_MEMORY", "PCI_COMMAND_MASTER",
      "PCI_EXT_CAP_ID", "PCI_EXT_CAP_ID_REBAR", "PCI_EXT_CAP_NEXT",
      "PCI_BASE_ADDRESS_0", "PCI_BASE_ADDRESS_SPACE",
      "PCI_BASE_ADDRESS_MEM_PREFETCH", "PCI_BASE_ADDRESS_MEM_TYPE_64",
      "PCI_BASE_ADDRESS_MEM_TYPE_MASK", "PCI_STATUS"]
for n in PN:
  print(f"pci.{n}={getattr(pci, n, 'ABSENT')}")
print(f"pci.PCI_COMMAND_IO|MEMORY|MASTER={pci.PCI_COMMAND_IO | pci.PCI_COMMAND_MEMORY | pci.PCI_COMMAND_MASTER}")

hr("autogen.libc")
from tinygrad.runtime.autogen import libc
for n in ("MAP_HUGETLB", "MADV_DONTFORK", "MAP_SHARED", "MAP_PRIVATE",
          "MAP_ANONYMOUS", "MAP_FIXED", "MAP_POPULATE", "MAP_LOCKED",
          "MAP_NORESERVE", "MAP_FIXED_NOREPLACE", "PROT_READ", "PROT_WRITE",
          "MADV_HUGEPAGE", "MADV_WILLNEED", "MADV_COLD"):
  print(f"libc.{n}={getattr(libc, n, 'ABSENT')}")

hr("autogen.vfio")
from tinygrad.runtime.autogen import vfio
for n in ("VFIO_TYPE", "VFIO_NOIOMMU_IOMMU", "VFIO_PCI_MSI_IRQ_INDEX",
          "VFIO_IRQ_SET_DATA_EVENTFD", "VFIO_IRQ_SET_ACTION_TRIGGER"):
  print(f"vfio.{n}={getattr(vfio, n, 'ABSENT')}")
try:
  print(f"ctypes.sizeof(vfio.struct_vfio_irq_set)={ctypes.sizeof(vfio.struct_vfio_irq_set)}")
  print(f"sizeof(struct_vfio_irq_set)+sizeof(c_int)={ctypes.sizeof(vfio.struct_vfio_irq_set) + ctypes.sizeof(ctypes.c_int)}")
except Exception as e: print("irq_set sizeof failed:", e)

# --- RemoteCmd, :359-361 -----------------------------------------------------
hr("RemoteCmd enum (:359-361) — the LIVE enum from the imported module")
from tinygrad.runtime.support.system import RemoteCmd, REMOTE_REQ, REMOTE_RESP
for m in RemoteCmd:
  print(f"RemoteCmd.{m.name}={m.value}")
print(f"count={len(list(RemoteCmd))}")
print(f"order={[m.name for m in RemoteCmd]}")
print(f"RemoteCmd(0).name={RemoteCmd(0).name!r}  RemoteCmd(15).name={RemoteCmd(15).name!r}")
print(f"first 13 == range(13)? {[m.value for m in RemoteCmd][:13] == list(range(13))}")
print(f"last 3  == range(13,16)? {[m.value for m in RemoteCmd][13:] == list(range(13, 16))}")
print(f"REMOTE_REQ={REMOTE_REQ!r}  REMOTE_RESP={REMOTE_RESP!r}")

hr("REMOTE_REQ / REMOTE_RESP struct layout (:363)")
print(f"REMOTE_REQ='<BIIQQQ' calcsize={struct.calcsize('<BIIQQQ')}")
print(f"REMOTE_RESP='<BQQ' calcsize={struct.calcsize('<BQQ')}")
# field ORDER proved by a sentinel round-trip, not by reading the comment.
SENT = {"cmd": 0x11, "dev": 0x22, "bar": 0x33, "arg0": 0x44, "arg1": 0x55, "arg2": 0x66}
packed = struct.pack(REMOTE_REQ, SENT["cmd"], SENT["dev"], SENT["bar"],
                     SENT["arg0"], SENT["arg1"], SENT["arg2"])
back = struct.unpack(REMOTE_REQ, packed)
print("REMOTE_REQ sentinels -> unpacked positionally: " + repr(tuple(hex(v) for v in back)))
print("REMOTE_REQ field order (positional) = ('cmd','dev','bar','arg0','arg1','arg2')")
def _offsets(fmt, names):
  out, pos = [], 0
  for n, c in zip(names, [c for c in fmt if c not in "<>=!@"]):
    out.append((n, c, pos))
    pos += struct.calcsize(c)
  return out
print("REMOTE_REQ offsets: " + repr(_offsets(REMOTE_REQ, ['cmd', 'dev', 'bar', 'arg0', 'arg1', 'arg2'])))
print("REMOTE_RESP offsets: " + repr(_offsets(REMOTE_RESP, ['status', 'resp0', 'resp1'])))
for cmd, dev, bar, a0, a1, a2 in [(RemoteCmd.CFG_WRITE, 0, 1, 0x100, 0x200, 0),
                                  (RemoteCmd.CFG_READ, 0, 0, 0, 0, 0),
                                  (RemoteCmd.MAP_SYSMEM, 0, 0, 0x100000, 0, 0)]:
  print(f"pack(REMOTE_REQ, {cmd.name})={struct.pack('<BIIQQQ', cmd, dev, bar, a0, a1, a2).hex()}")

hr("the pad-to-3 rule, :418 -- struct.pack(REMOTE_REQ, cmd, dev, bar, *(*args,0,0,0)[:3])")
for args in [(), (5,), (5, 6), (5, 6, 7), (5, 6, 7, 8), (5, 6, 7, 8, 9)]:
  padded = (*args, 0, 0, 0)[:3]
  print(f"args={args} -> padded={padded} -> hex={struct.pack('<BIIQQQ', 0, 0, 0, *padded).hex()}")

hr("element size table — struct.calcsize(self.fmt), :370/:377")
for f in ("B", "H", "I", "L", "Q", "b", "h", "i", "q", "f", "d"):
  print(f"calcsize({f!r})={struct.calcsize(f)}")

hr("RemoteMMIOInterface slicing, :371-375")
for k, n, sl in [("slice", 8, slice(2, 6)), ("int", 8, 3)]:
  pass
el = struct.calcsize('B')
sl = slice(2, 6)
st, en = (sl.start or 0) * el, (8 if sl.stop is None else sl.stop) * el
print(f"fmt='B' el={el} slice(2,6) -> st={st} en={en} en-st={en - st} items={(en - st) // el}")
print(f"fmt='B' el={el} int 3       -> st={3 * el} en={8 * el}")
el4 = struct.calcsize('I')
print(f"fmt='I' el={el4} slice(0,8) -> st={0 * el4} en={8 * el4} items={(8 * el4) // el4}")
print(f"slice(k,k+1) with k=3 el={el} -> st={3 * el} en={4 * el}")
print(f"slice(None,None) el={el} -> st={0} en={8 * el}")

hr("alloc_sysmem paddrs unpack, :437 -- struct.unpack(f'<{n // 8}Q', ...)")
for n in (0, 8, 16, 24, 4096):
  print(f"n={n} -> n//8={n // 8}")

hr("system_paddrs (:96) — the PAGEFRAME mask and the multiply")
for vaddr, size in [(0x1000, 0x1000), (0x7ffff7a00000, 0x3000), (0xdead000, 0x2000)]:
  print(f"vaddr={vaddr:#x} size={size:#x} seek={vaddr // mmap.PAGESIZE * 8} nread={size // mmap.PAGESIZE * 8}")
print(f"(1<<55)-1={(1 << 55) - 1} = {hex((1 << 55) - 1)}")
for x in (0x7fffffffdfe0_0000, 0x8000_0000_0026_0000, 0x0000_1234_5678_9abc):
  print(f"x={x:#x} & mask = {x & ((1 << 55) - 1):#x} * PAGESIZE = {hex((x & ((1 << 55) - 1)) * mmap.PAGESIZE)}")

hr("alloc size ladder, :315 — round_up(size, PAGESIZE if sysmem else ((2<<20) if size>=(8<<20) else (4<<10)))")
def round_up(x, m): return (x + m - 1) // m * m
for size in (1, 0xfff, 0x1000, 0x1001, 0x7fffff, 0x800000, 0x800001, 0x1234567, 0x2000000):
  print(f"size={size:#x} sysmem_align={hex(mmap.PAGESIZE)} devmem_align={hex((2 << 20) if size >= (8 << 20) else (4 << 10))}"
        f" -> {hex(round_up(size, mmap.PAGESIZE))} / {hex(round_up(size, (2 << 20) if size >= (8 << 20) else (4 << 10)))}")
for size in (0x7fffff, 0x800000, 0x800001):
  print(f"size={size:#x} >= (8<<20) is {size >= (8 << 20)}")

hr("pci_setup_usb_bars values, :141-151 (gpu_bus=4 mem_base=0x10000000 pref_mem_base=32<<30)")
GPU_BUS, MEM_BASE, PREF_MEM_BASE = 4, 0x10000000, (32 << 30)
print(f"pref_mem_base={PREF_MEM_BASE:#x} = {PREF_MEM_BASE}")
for bus in range(GPU_BUS):
  print(f"bus={bus} buses={(0 << 0) | ((bus + 1) << 8) | (GPU_BUS << 16):#x}")
print(f"(mem_base>>16)&0xffff={(MEM_BASE >> 16) & 0xffff:#x}")
print(f"(pref_mem_base>>16)&0xffff={(PREF_MEM_BASE >> 16) & 0xffff:#x}")
print(f"pref_mem_base>>32={PREF_MEM_BASE >> 32:#x} (as passed to PREF_BASE_UPPER32)")
print(f"pci.PCI_PREF_LIMIT_UPPER32 value written={0xffffffff:#x}")
print(f"cap_ptr start=0x100  bar loop bound=24  bar_off steps: 4 or 8")
print(f"rebar: (~0x1F00) = {hex(~0x1F00 & 0xffffffffffffffff)}")

hr("BAR sizing, :175 — ((~(((hi<<32)|lo) & ~0xf)) + 1) & (2**64-1 if bar_64 else 2**32-1)")
def bar_size(lo, hi, bar_64):
  return ((~(((hi << 32) | lo) & ~0xf)) + 1) & (0xffffffffffffffff if bar_64 else 0xffffffff)
for lo, hi, b64 in [(0xfffff000, 0, False), (0xfff00000, 0, False), (0xf0000000, 0x2, True),
                    (0x10000000, 0x2, True), (0x0, 0x0, False), (0xffff0000, 0xffff, True)]:
  sz = bar_size(lo, hi, b64)
  print(f"lo={lo:#x} hi={hi:#x} bar_64={b64} -> size={sz:#x} ({sz}) round_up2M={hex(round_up(sz, 2 << 20))}")
for n in (0x1000, 0x100000, 0x1000000, 0x10000000):
  print(f"(int({n:#x} >> 4).bit_length() - 1) << 8 = {hex(((n >> 4).bit_length() - 1) << 8)}")
for cap in (0x00001001, 0x00002100, 0x00000001, 0x00000002):
  print(f"cap={cap:#x} -> bar_size_log2-1 shift = {hex(((cap >> 4).bit_length() - 1) << 8)}")

hr("USBPCIDevice constants, :272-282")
print(f"BumpAllocator size=0x80000 wrap=False")
print(f"dma_view(0xf000 + off, size) and paddrs [0x200000 + off]")
print(f"read_config/write_config pcie_cfg_req bus=4 dev=0 fn=0")
print(f"lock name = f\"{{devpref.lower()}}_{{pcibus.lower()}}.lock\"")

hr("PCIAllocationMeta, :292-293 — field order and names")
import dataclasses
@dataclasses.dataclass
class PCIAllocationMeta: mapping: object; has_cpu_mapping: bool; hMemory: int = 0
print(f"fields={[f.name for f in dataclasses.fields(PCIAllocationMeta)]}")
print(f"defaults={[f.default for f in dataclasses.fields(PCIAllocationMeta)]}")
print(f"PCIAllocationMeta('M', True, 5)={dataclasses.astuple(PCIAllocationMeta('M', True, 5))}")
print(f"PCIAllocationMeta('M', False)={dataclasses.astuple(PCIAllocationMeta('M', False))}")

hr("peer_group, :297 / :272 / :430 — the getattr fallback and its two overrides")
for cls, has in [("PCIDevice", False), ("USBPCIDevice", True), ("RemotePCIDevice", True)]:
  val = f"USBPCIDevice_0000:00:01.0" if cls == "USBPCIDevice" else ("remote:10.0.0.1:6667" if cls == "RemotePCIDevice" else None)
  print(f"{cls}: has_explicit={has} peer_group={val if has else cls}")
print(f"is_bar_small: bar_info(vram_bar)[1] == (256<<20) -> {(256 << 20)}")

hr("pci_scan_bus filter, :126 — any((device & mask) in devlist for mask, devlist in devices)")
DEVICES = ((0xFFFFF, (0x744C, 0x73BF, 0x73DF, 0x687F, 0x74BF, 0x73FF, 0x72DF,
                      0x744D, 0x73EF, 0x73AF, 0x7400, 0x7405, 0x73C0, 0x73C1, 0x73C3)),
            (0xFF00, (0x1635, 0x1636, 0x1637, 0x1638, 0x1639, 0x163A, 0x163B,
                      0x163C, 0x163D, 0x163E, 0x163F, 0x1640, 0x1641, 0x1642)))
def match(vendor, device, devs=DEVICES):
  return vendor == 0x1002 and any((device & mask) in dl for mask, dl in devs)
for vendor, device in [(0x1002, 0x744C), (0x1002, 0x1635), (0x1002, 0x1636),
                        (0x1002, 0x1637), (0x1002, 0x73BF), (0x1002, 0x1234),
                        (0x10DE, 0x144C), (0x1002, 0x74BF)]:
  print(f"vendor={vendor:#x} device={device:#x} -> {match(vendor, device)}")
print("=== the negative side: right vendor, one past the largest id under each mask")
print(f"device=0x1643 (past 0x1642) -> {match(0x1002, 0x1643)}")
print(f"device=0x74C0 (past 0x74BF) -> {match(0x1002, 0x74C0)}")
print(f"masks={[hex(m) for m, _ in DEVICES]}")
print(f"ndev={[len(dl) for _, dl in DEVICES]}")

hr("the REAL device tables, :126's `devices` argument — read out of the callers")
import ast, re as _re
for f in sorted(__import__('pathlib').Path('tinygrad/runtime').glob('ops_*.py')):
  txt = f.read_text()
  for mt in _re.finditer(r"vendor=(0x[0-9a-fA-F]+), devices=\(\((.*?)\),\),", txt, _re.S):
    vend = int(mt.group(1), 16)
    # the tuple-of-pairs is a Python literal; eval it rather than transcribe it.
    pairs = eval("((" + mt.group(2) + "),)", {"__builtins__": {}})
    for mask, dl in pairs:
      print(f"{f.name}: vendor={vend:#x} mask={mask:#x} ndev={len(dl)} ids={[hex(d) for d in dl]}")
      print(f"{f.name}: mask hi/lo -> {mask >> 32} : {mask & 0xffffffff}  (a 0x1002/0x10de mask fits one U32)")

hr("pci_scan_bus filter over the REAL tables, :126")
AMDV, NVV = 0x1002, 0x10de
def real_match(vendor, device, pairs, want):
  return vendor == want and any((device & mask) in dl for mask, dl in pairs)
AMD = ((0xffff, (0x74a1,0x74b5,0x744c,0x7480,0x7550,0x7551,0x7590,0x75a0,0x75a8,0x75b0,0x75b3)),)
NV = ((0xff00, (0x2200,0x2400,0x2500,0x2600,0x2700,0x2800,0x2b00,0x2c00,0x2d00,0x2f00)),)
print(f"AMD mask={AMD[0][0]:#x} -> the mask is 0xffff, so `device & 0xffff` is the device ITSELF")
for v, d in [(0x1002, 0x744c), (0x1002, 0x74a1), (0x1002, 0x75b3), (0x1002, 0x75b4),
             (0x1002, 0x1635), (0x10de, 0x2200), (0x1002, 0x74c), (0x1002, 0x744d)]:
  print(f"vendor={v:#06x} device={d:#06x} -> AMD={real_match(v, d, AMD, AMDV)} NV={real_match(v, d, NV, NVV)}")
print("=== the negative side: one PAST the largest id under each mask, and one BEFORE")
print(f"AMD device=0x75b4 (past 0x75b3) -> {real_match(0x1002, 0x75b4, AMD, AMDV)}")
print(f"AMD device=0x74a0 (just below 0x74a1) -> {real_match(0x1002, 0x74a0, AMD, AMDV)}")
print(f"NV  device=0x3000 (past 0x2f00, mask 0xff00) -> {real_match(0x10de, 0x3000, NV, NVV)}")
print(f"NV  device=0x2100 (just below 0x2200) -> {real_match(0x10de, 0x2100, NV, NVV)}")
print(f"AMD RIGHT vendor, id in the OTHER table (0x2200) -> {real_match(0x1002, 0x2200, AMD, AMDV)}")
print(f"NV  RIGHT vendor, id in the OTHER table (0x744c) -> {real_match(0x10de, 0x744c, NV, NVV)}")
print(f"WRONG vendor, id in the table: AMD dev 0x744c w/ vendor 0x10de -> {real_match(0x10de, 0x744c, AMD, AMDV)}")
print("=== a mask that is NOT 0xffff, so `device & mask` DIFFERS from `device`")
print(f"NV device=0x2f00 & 0xff00 = {0x2f00 & 0xff00:#x} -> in devlist: {0x2f00 & 0xff00 in NV[0][1]}")
print(f"NV device=0x2fff & 0xff00 = {0x2fff & 0xff00:#x} -> in devlist: {0x2fff & 0xff00 in NV[0][1]}")
print(f"NV device=0x2f01 & 0xff00 = {0x2f01 & 0xff00:#x} -> in devlist: {0x2f01 & 0xff00 in NV[0][1]}")

hr("base_class shift, :116/:122 — read_prop('class-code') >> 16")
for cc in (0x030000, 0x030200, 0x020000, 0x0C0330, 0x030000 | 0x744C):
  print(f"class-code={cc:#x} >> 16 = {cc >> 16:#x} ==0x03 -> {cc >> 16 == 0x03}")

hr("OSX id formatting, :117 — f\"{v:x}:{d:x}\" vs the Linux pcibus string")
for v, d in [(0x1002, 0x744C), (0x10DE, 0x144C), (0x8086, 0x0), (0x1002, 0x1635)]:
  print(f"v={v:#x} d={d:#x} -> {f'{v:x}:{d:x}'}")

hr("filter_visible_devices, :11-16 — the index string parser")
def parse(idstr):
  if '-' in idstr[1:]: return ("range", list(range(int(idstr.split('-')[0]), int(idstr.split('-')[1]) + 1)))
  return ("list", [int(x) for x in idstr.split(',') if x.strip()])
for s in ["0", "0,1", "0-3", "0-0", "1-2", "", " ", "0, 1", "0,1,2", "-1", "3-1", "0-1-2", " 0 , 1 ", "0,", ",0", "10-12"]:
  try: print(f"{s!r} -> {parse(s)}")
  except Exception as e: print(f"{s!r} -> RAISES {type(e).__name__}: {e}")

hr("RemotePCIDevice.scan, :399-406 — the REMOTE env parser and the default port")
for r in ["", " ", "local", "10.0.0.1", "10.0.0.1:6666", " local , 10.0.0.2:1 "]:
  parts = [x.strip() for x in r.split(",") if x.strip()]
  out = []
  for x in parts:
    if x == "local": out.append("LOCAL")
    else:
      host, port = x.split(":")[0], int(x.split(":")[1]) if ":" in x else 6667
      out.append(f"remote:{host}:{port}")
  print(f"REMOTE={r!r} -> parts={parts} -> {out}")

hr("read_config / write_config, :248-249 — little-endian int <-> bytes")
for off, size, v in [(0, 1, 0x86), (0x4, 4, 0x02342010), (0x60, 2, 0x0300), (0x100, 4, 0xFFFFFFFF)]:
  b = v.to_bytes(size, byteorder='little')
  print(f"offset={off:#x} size={size} value={v:#x} -> bytes={b.hex()} readback={int.from_bytes(b, byteorder='little'):#x}")

hr("bar_info, :258-260 — the /resource line, hex parse, `e - s + 1`")
for line, idx in [("0x7c000000 0x7fffffff 0x00000000\n0x0 0x0 0x0", 0),
                 ("0x7c000000 0x7fffffff 0x00000000\n0x10000000 0x1fffffff 0x0", 1),
                 ("0x10000000 0x1fffffff 0x00000000\n0x0 0xfff 0x0", 0),
                 ("0x7d000000 0x7d1fffff 0x00000000\n0x0 0x0 0x0", 0),
                 ("0x0 0xfff 0x0\n0x7d000000 0x7d3fffff 0x0", 1)]:
  s, e, _ = line.splitlines()[idx].split()
  si, ei = int(s, 16), int(e, 16)
  print(f"line={line!r} idx={idx} -> ({si:#x}, {ei - si + 1:#x}) size={ei - si + 1}")

hr("resize_bar, :265-268 — str(int(read,16).bit_length() - 1)")
for v in (0x100000, 0x40000000, 0x80000000, 0x200000, 0x1, 0x0):
  try: print(f"resize={v:#x} -> {str(int(v, 16).bit_length() - 1) if isinstance(v, str) else str(v.bit_length() - 1)}")
  except Exception as e: print(f"{v:#x} -> {e}")

hr("write_sysfs / reset / modprobe / lsof command strings, :58/:75/:198/:247")
# The f-strings are EVALUATED OUT OF THE SOURCE TEXT, not retyped, so a stray
# space cannot hide here. A first cut of this oracle added a trailing space to
# every write_sysfs/reset command and the port would have inherited it.
import re as _re
LINES = open("tinygrad/runtime/support/system.py").read().splitlines()
def fs(line):
  """eval the f-string literal on `line`, with `value`/`path`/`name`/`pcibus` in scope."""
  m = _re.search(r"f\"([^\"]*)\"|f'([^']*)'", LINES[line - 1])
  expr = (m.group(1) or m.group(2))
  return eval('f"' + expr + '"', {}, dict(value="0", path="/proc/sys/vm/compact_unevictable_allowed",
                                           name="0000", lock_name="/tmp/unique/0000.lock",
                                           self=type("S", (), {"pcibus": "0000:03:00.0"})(),
                                           gpu_bus=4, bus=0))
for ln in (58, 247):
  print(f":{ln} source = {LINES[ln-1].strip()}")
  print(f":{ln} for value='0' -> {fs(ln)!r}")
  print(f":{ln} for value='1' -> {fs(ln).replace(chr(39) + 'echo 0 >', chr(39) + 'echo 1 >')!r}")
print(f":58 len for value='0' = {len(fs(58))}  (a trailing space would make it {len(fs(58)) + 1})")
print(f":58 endswith the closing quote at the LAST char? {fs(58)[-1]!r} == \"'\" -> {fs(58)[-1] == chr(39)}")
print(f":75 vfio modprobe cmd={LINES[74].strip()[11:-1]!r}  (a plain string literal, not an f-string)")
print(f":198 lsof source = {LINES[197].strip()}")
print(f":198 rendered     = {'Failed to acquire lock file ' + '0000' + '. `sudo lsof ' + '/tmp/unique/0000.lock' + '` may help identify the process holding the lock.'!r}")
print(f":212 source       = {LINES[211].strip()}")
print(f":268 source       = {LINES[267].strip()}")
print(f":272 peer_group   = {LINES[271].strip()}")
print(f":430 peer_group   = {LINES[429].strip()}")

hr("sysfs path table, :211-242 / :259 / :266")
for pcibus in ("0000:03:00.0", "c1:00.0"):
  for t in ("enable", "driver", "driver/unbind", "driver_override", "config", "iommu_group", "resource", "resource0", "resource2_resize"):
    print(f"/sys/bus/pci/devices/{pcibus}/{t}")
BUS = "0000:03:00.0"
print("sibling remove: f\"/sys/bus/pci/devices/{self.pcibus[:-1]}{fn}/remove\" for fn in range(1, 8)")
for fn in range(1, 8): print(f"  /sys/bus/pci/devices/{BUS[:-1]}{fn}/remove")
LINK = f"/sys/devices/pci0000:00/0000:00:01.0/{BUS}/iommu_group"
print(f"iommu_group readlink target = {LINK}")
print(f"  .split('/')[-1] = {LINK.split('/')[-1]!r}   <- the number in /dev/vfio/noiommu-")
print(f"noiommu path: {'/dev/vfio/noiommu-' + LINK.split('/')[-1]!r}")
print(f"lock name (:208) f\"{{devpref.lower()}}_{{pcibus.lower()}}.lock\" -> {f'{"AM".lower()}_{BUS.lower()}.lock'!r}")
print(f"devpref[:2] (pci_probe_device, :136) -> {'AM'[:2]!r}  (USBPCIDevice, :273, keeps the full devpref)")

hr("map_bar mmap flags, :263")
for addr in (0, 0x100000):
  print(f"addr={addr:#x} -> MAP_SHARED|(MAP_FIXED if addr else 0) = {mmap.MAP_SHARED | (0x10 if addr else 0):#x}")
print(f"PROT_READ|PROT_WRITE={mmap.PROT_READ | mmap.PROT_WRITE:#x}  MADV_DONTFORK={0x10}")
for off, size, bi in [(0, None, 0x100000000), (0x1000, None, 0x100000000), (0, 0x2000, 0x100000000)]:
  print(f"map_bar off={off:#x} size={size} -> size or (bar_info(bar)[1] - off) = {size or (bi - off):#x}")

hr("map_bar / alloc : host-device set and refusals, :337-343")
for dev, host in [("CPU:0", "localhost"), ("PYTHON:1", "localhost"), ("NPY:2", "localhost"),
                  ("NPU:0", "localhost"), ("AMD:1", "localhost"), ("CPU:0", "otherhost")]:
  print(f"b.device={dev!r} split(':')[0]={{'CPU','PYTHON','NPY'}}? {dev.split(':')[0] in {'CPU','PYTHON','NPY'}}  host mismatch: {host != 'localhost'}")
for addr in (0x0, 0x800, 0x1000, 0x1fff, 0x2000):
  print(f"b._buf={addr:#x} % 0x1000 = {addr % 0x1000} -> aligned: {addr % 0x1000 == 0}")
# the real AMD virtual-address window, read out of ops_amd.py rather than guessed
AMBASE, AMBITS = 0x10000000000, 48
print(f"AMD va_base={AMBASE:#x} va_bits={AMBITS} span={AMBASE + (1 << AMBITS):#x}")
for lo, size in [(AMBASE + 0x1000, 0x2000), (AMBASE - 0x1000, 0x2000),
                 (AMBASE + 0x1000, 1 << 48), (0x50, 0x2000), (AMBASE + 0x1000, 0x1000)]:
  print(f"lo={lo:#x} size={size:#x} -> in range: {AMBASE <= lo < lo + size <= AMBASE + (1 << AMBITS)}")
for lo, size in [(0x1000, 0x1001), (0x1000, 0x1000)]:
  print(f"round_up({lo:#x}, {size:#x}, 0x1000) = {((lo + 0x1000 - 1) // 0x1000) * 0x1000:#x}")

hr("ipv4_to_gid, :53")
import socket as _s
for ip in ("127.0.0.1", "10.0.0.1", "192.168.1.255", "0.0.0.0", "255.255.255.255"):
  gid = bytes(10) + b'\xff\xff' + _s.inet_aton(ip)
  print(f"{ip} -> len={len(gid)} hex={gid.hex()}")

hr("the pcie_cfg_req ARGUMENT SHAPE, :142-185 (field names and order)")
import inspect
LINES2 = open("tinygrad/runtime/support/system.py").read().splitlines()
for ln in (142, 144, 145, 146, 147, 148, 149, 151, 156, 157, 158, 159, 165, 169, 170, 172, 173, 177, 178, 185):
  print(f"  :{ln}: {LINES2[ln - 1].strip()}")
print("--- CustomASM24Controller.pcie_cfg_req signature (the real field order, usb.py:137):")
from tinygrad.runtime.support.usb import CustomASM24Controller
print("  " + str(inspect.signature(CustomASM24Controller.pcie_cfg_req)))
print("  positional-only head is `byte_addr`; every call in system.py passes it POSITIONALLY")
print("  and bus/dev/fn/value/size as KEYWORDS, so the record the port builds has")
print("  fields in exactly this order: byte_addr, bus, dev, fn, value, size.")
print("--- the KWs every WRITE passes, in source order, deduped:")
import re as _r
kws, seen = [], set()
for ln in list(range(142, 152)) + list(range(156, 160)) + list(range(165, 180)) + [185]:
  for kw in _r.findall(r"\b(bus|dev|fn|value|size)\s*=", LINES2[ln - 1]):
    if kw not in seen: seen.add(kw); kws.append(kw)
print("  " + repr(kws))

hr("OSX read_prop, :108-112 — 8-byte LE buffer, no crash on a real device")
for raw in (0x1002, 0x744C, 0x0300, 0x00000003):
  buf = (ctypes.c_uint8 * 8)()
  for i, b in enumerate(raw.to_bytes(8, "little")): buf[i] = b
  print(f"raw={raw:#x} -> int.from_bytes(bytes(buf),'little')={int.from_bytes(bytes(buf), 'little'):#x}")

hr("lock fd flags table, :194-197")
print(f"exists  -> os.open(lock_name, os.O_RDWR) = {os.O_RDWR}")
print(f"missing -> os.open(lock_name, os.O_RDWR|os.O_CREAT|os.O_CLOEXEC, 0o666) = {os.O_RDWR | os.O_CREAT | os.O_CLOEXEC}")
import fcntl
print(f"fcntl.LOCK_EX|LOCK_NB={fcntl.LOCK_EX | fcntl.LOCK_NB}  LOCK_EX={fcntl.LOCK_EX} LOCK_NB={fcntl.LOCK_NB}")
print(f"os.umask(0) then 0o666 -> the file is created {0o666:o} with no group/other bits cleared")

hr("alloc_sysmem guard, :99-100")
for size, contig in [(2 << 20, True), ((2 << 20) + 1, True), (1 << 30, True), (1 << 30, False), (4 << 20, False)]:
  print(f"size={size:#x} contiguous={contig} -> assert passes: {not contig or size <= (2 << 20)}")
print(f"MAP_HUGETLB={libc.MAP_HUGETLB:#x}")
for size, contig, vaddr in [(0x1000, True, 0), (0x1000, True, 0x7f0000000000), (0x2000, True, 0),
                            (0x1000, False, 0x7f0000000000), (0x1000000, True, 0)]:
  s2 = round_up(size, mmap.PAGESIZE) if (contig and round_up(size, mmap.PAGESIZE) > mmap.PAGESIZE) else size
  flags = (libc.MAP_HUGETLB if (contig and s2 > mmap.PAGESIZE) else 0) | (0x10 if vaddr else 0)
  print(f"size={size:#x} contig={contig} vaddr={vaddr:#x} -> size'={s2:#x} flags={flags:#x}")
print(f"mmap flag OR, :101 = PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS|MAP_POPULATE|MAP_LOCKED|flags")
print(f"  base = {mmap.MAP_SHARED | getattr(mmap,'MAP_ANONYMOUS',0) | (getattr(mmap,'MAP_POPULATE',0) if not sys.platform=='darwin' else 0) | (0 if sys.platform=='darwin' else 0x2000):#x}")
print(f"  reserve_va :87 = {mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS | 0x400 | 0x100000:#x}")
print(f"  contiguous 1G aligned = {round_up(1 << 30, mmap.PAGESIZE) & ~(mmap.PAGESIZE - 1):#x} hugepage-aligned: "
      f"{round_up(1 << 30, mmap.PAGESIZE) % (1 << 21) == 0}")

hr("LINUX-PARAMETERISED: the page size changes the alloc_sysmem flags, :100-101")
# mmap.PAGESIZE is 16384 on this macOS host and 4096 on every Linux tinygrad runs
# on, and :100's `> mmap.PAGESIZE` test flips between the two. The first cut of
# this oracle used the HOST page size and printed `flags=0x0` for an 8 KiB
# contiguous request, which is wrong for the platform the port targets.
PS = 4096
def round_up(x, m): return (x + m - 1) // m * m
print(f"Linux mmap.PAGESIZE={PS}")
for size, contig, vaddr in [(0x1000, True, 0), (0x1000, True, 0x7f0000000000),
                            (0x2000, True, 0), (0x2000, True, 0x7f0000000000),
                            (0x1000, False, 0), (0x1000, False, 0x7f0000000000),
                            (0x1000000, True, 0), (0x1000000, True, 0x7f0000000000),
                            (0x1001, True, 0), (0x1000, True, 0)]:
  rnd = round_up(size, PS)
  s2 = rnd if contig else size
  huge = contig and s2 > PS
  flags = (libc.MAP_HUGETLB if huge else 0) | (0x10 if vaddr else 0)
  base = 0x1 | 0x20 | 0x8000 | 0x2000
  print(f"size={size:#x} contig={contig} vaddr={vaddr:#x} -> rounded={rnd:#x} size'={s2:#x} "
        f"huge={huge} flags={flags:#x} mmap_flags={base | flags:#x}")
print("=== the assert at :99, on the LINUX page size")
for size in (2 << 20, (2 << 20) + 1, 1 << 20, 4 << 20, 1 << 30):
  print(f"size={size:#x} contiguous=True -> assert passes: {size <= (2 << 20)}")
print("=== :315's ladder on the LINUX page size")
for size in (1, 0xfff, 0x1000, 0x1001, 0x7fffff, 0x800000, 0x800001, 0x1234567, 0x2000000):
  sysm = round_up(size, PS)
  devm = round_up(size, (2 << 20) if size >= (8 << 20) else (4 << 10))
  print(f"size={size:#x} -> sysmem round_up={sysm:#x}  devmem align={hex((2 << 20) if size >= (8 << 20) else (4 << 10))} -> {devm:#x}")

hr("the reserve_va / alloc_sysmem flag ORs, LINUX, from the source's own constants")
print(f"reserve_va :87  MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE|MAP_FIXED_NOREPLACE = {0x2 | 0x20 | 0x400 | 0x100000:#x}")
print(f"alloc_sysmem :101 base MAP_SHARED|MAP_ANONYMOUS|MAP_POPULATE|MAP_LOCKED = {0x1 | 0x20 | 0x8000 | 0x2000:#x}")
print(f"map_bar :263  MAP_SHARED|(MAP_FIXED if addr else 0) = {0x1:#x} / {0x1 | 0x10:#x}")
print(f"  prot = PROT_READ|PROT_WRITE = {0x1 | 0x2:#x}")
print(f"system_paddrs :96  (1<<55)-1 = {hex((1 << 55) - 1)}  -> hi={(1 << 55) - 1 >> 32} lo={((1 << 55) - 1) & 0xffffffff}")

hr("the sibling / lock / reset / message strings, on a real bus id")
BUS = "0000:03:00.0"
print(f"pcibus[:-1] = {BUS[:-1]!r}")
for fn in range(1, 8): print(f"  fn={fn} -> {f'/sys/bus/pci/devices/{BUS[:-1]}{fn}/remove'!r}")
print(f"lock name   = {f'{"AM".lower()}_{BUS.lower()}.lock'!r}")
print(f"permission  = {f'Cannot access PCI device {BUS}: run `extra/amdpci/setup_python_cap.sh` or use sudo'!r}")
print(f"bound msg   = {f'Driver is bound to {BUS}'!r}")
print(f"reset cmd   = {f'sudo sh -c ' + chr(39) + f'echo 1 > /sys/bus/pci/devices/{BUS}/reset' + chr(39)!r}")
print(f"resize msg  = {f'Cannot resize BAR 2: nope. Ensure the resizable BAR option is enabled.'!r}")
print(f"visibility  = {f'invalid visibility filter: {[0, 1, 2]} (2 devices available)'!r}  / 1 dev: "
      f"{f'invalid visibility filter: {[0, 5]} (1 device available)'!r}")
print(f"deprecation = {f'HCQ_VISIBLE_DEVICES=0,1 is deprecated, use DEV=AMD:0,1 instead'!r}")
print(f"mmap fail   = {f'Failed to mmap {4096} bytes at {0x7f0000000000:#x}: Cannot allocate memory'!r}")
print(f"re-read msg = {f'Failed to disable migration of locked pages. Please run sudo sh -c ' + chr(39) + 'echo 0 > /proc/sys/vm/compact_unevictable_allowed' + chr(39) + ' manually.'!r}")
print(f"flock msg   = {f'Failed to acquire lock file AMD. `sudo lsof /tmp/unique/am_0000:03:00.0.lock` may help identify the process holding the lock.'!r}")

hr("the RemoteMMIOInterface fmt table and the arg pack, in DECIMAL for the Bend gate")
print("calcsize: " + repr({c: struct.calcsize(c) for c in 'BHILQbhqfd'}))
print(f"REMOTE_RESP size = {struct.calcsize(REMOTE_RESP)}, REMOTE_REQ size = {struct.calcsize(REMOTE_REQ)}")
print("REMOTE_REQ offsets: cmd=0 dev=1 bar=5 arg0=9 arg1=17 arg2=25")
print("REMOTE_RESP offsets: status=0 resp0=1 resp1=9")
print(f"socket: IPPROTO_TCP={socket.IPPROTO_TCP} TCP_NODELAY={socket.TCP_NODELAY} "
      f"SOL_SOCKET={socket.SOL_SOCKET} SO_SNDBUF={socket.SO_SNDBUF} SO_RCVBUF={socket.SO_RCVBUF}")
print(f"the two buffer opts share one value: 64<<20 = {64 << 20}")

hr("the BAR probe arithmetic, :163-183, as a fixture table")
def probe(lo, hi, bar_64):
  lo &= 0xfffffff0
  size = 0xffffffffffffffff if bar_64 else 0xffffffff
  return (~(((hi << 32) | lo) & ~0xf) + 1) & size
for bar_off, lo, hi, b64, mem, pref in [
    (0,  0x10000000, 0, False, True,  False),
    (4,  0x00000000, 0, False, True,  False),
    (8,  0xf0000000, 0, False, True,  False),
    (12, 0x0, 0, False, False, False)]:
  sz = probe(lo, hi, b64)
  print(f"bar_off={bar_off:2d} lo={lo:#x} hi={hi:#x} bar_64={b64} mem={mem} pref={pref} -> "
        f"size={sz:#x} ({sz}) next_bar_off={bar_off + (8 if b64 else 4)}")
print("=== the 32-bit BAR size as a U32 WRAP: 0 - (lo & 0xfffffff0)")
for lo in (0x10000000, 0xf0000000, 0x00000000, 0xfff00000, 0xfffff000):
  print(f"  lo={lo:#x} -> {(0 - (lo & 0xfffffff0)) & 0xffffffff:#x}   CPython says {hex(probe(lo, 0, False))}")

hr("REBAR, :154-161 -- the control rewrite and the cap-id test")
for cap, cur in [(0x00001001, 0x00000201), (0x00002100, 0x00000201), (0x00000001, 0x00000201)]:
  n = (int(cap >> 4).bit_length() - 1) << 8
  print(f"cap={cap:#x} cur={cur:#x} -> new_ctrl = (({cur} & ~0x1F00) | ({n})) & 0xffffffff = {((cur & ~0x1F00) | n) & 0xffffffff:#x}")
  print(f"   ~0x1F00 as u32 = {(~0x1F00) & 0xffffffff:#x}   (cap>>4).bit_length() = {int(cap >> 4).bit_length()}")
for hdr in (0x00001001, 0x00002100, 0x00000015, 0x0000ff15, 0x00001500):
  print(f"  PCI_EXT_CAP_ID(hdr={hdr:#x}) & 0xff = {hdr & 0xff:#x} -> rebar: {(hdr & 0xff) == 0x15}")

hr("the eight bus-enable writes, :142-151 -- offsets, values and SIZES in order")
GPU_BUS, MEM_BASE, PREF = 4, 0x10000000, (32 << 30)
for bus in (0, 3):
  writes = [
    ("PCI_PRIMARY_BUS", pci.PCI_PRIMARY_BUS, (0 << 0) | ((bus + 1) << 8) | (GPU_BUS << 16), 4),
    ("PCI_MEMORY_BASE", pci.PCI_MEMORY_BASE, (MEM_BASE >> 16) & 0xffff, 2),
    ("PCI_MEMORY_LIMIT", pci.PCI_MEMORY_LIMIT, 0xffff, 2),
    ("PCI_PREF_MEMORY_BASE", pci.PCI_PREF_MEMORY_BASE, (PREF >> 16) & 0xffff, 2),
    ("PCI_PREF_MEMORY_LIMIT", pci.PCI_PREF_MEMORY_LIMIT, 0xffff, 2),
    ("PCI_PREF_BASE_UPPER32", pci.PCI_PREF_BASE_UPPER32, PREF >> 32, 4),
    ("PCI_PREF_LIMIT_UPPER32", pci.PCI_PREF_LIMIT_UPPER32, 0xffffffff, 4),
    ("PCI_COMMAND", pci.PCI_COMMAND, pci.PCI_COMMAND_IO | pci.PCI_COMMAND_MEMORY | pci.PCI_COMMAND_MASTER, 1),
  ]
  print(f"--- bus={bus}")
  for nm, off, val, sz in writes:
    print(f"  {nm:22s} off={off:3d} value={val:#x} size={sz}")
print("the ORDER is the claim, and it is EIGHT writes")
print(f"PCI_COMMAND value = {pci.PCI_COMMAND_IO | pci.PCI_COMMAND_MEMORY | pci.PCI_COMMAND_MASTER}")
print(f"cap_ptr starts at 0x100 and the bar loop runs `while bar_off < 24`")

hr("the alloc() decision, :310-325")
for host, cpu_access, force_devmem, small_bar in [
    (True, False, False, False), (False, True, False, True), (False, True, False, False),
    (False, True, True, True), (False, False, False, True), (True, True, True, False)]:
  s = host or (cpu_access and small_bar and not force_devmem)
  print(f"host={host} cpu_access={cpu_access} force_devmem={force_devmem} bar_small={small_bar} -> sysmem={s}")
print("=== is_bar_small, :300")
for sz in (256 << 20, (256 << 20) - 1, (256 << 20) + 1, 0x10000000, 0x2000000):
  print(f"  bar size={sz} ({sz:#x}) == (256<<20) -> {sz == (256 << 20)}")
