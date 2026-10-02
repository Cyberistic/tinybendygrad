"""amdev_fw.py -- drive the REAL AMFirmware.__init__ from tinygrad/runtime/support/am/amdev.py.

No transcription. `load_fw` (:111-117) is

    blob = memoryview(bytearray(fetch_fw(...)))
    if versioned_header:
      chdr = am.struct_common_firmware_header.from_address(mv_address(blob))
      headers += (getattr(am, versioned_header + f"_v{ch.header_version_major}_{ch.header_version_minor}"),)
    return tuple([blob] + [hdr.from_address(mv_address(blob)) for hdr in headers])

so the header IS the blob. Each builder below makes ONE byte image with the real
ctypes header struct written at offset 0 -- the common header carried in the
outer struct's own first member -- and then lets `AMFirmware.__init__` read it
back out by the same code path. The class selection
`versioned_header + f"_v{major}_{minor}"` is amdev.py's own `getattr`, so the
version ladder is MEASURED rather than transcribed.
"""
import sys, ctypes
sys.path.insert(0, '.')
from tinygrad.runtime.autogen.am import am
from tinygrad.runtime.support.am.amdev import AMFirmware

BLOBSZ = 0x8000

def mk(cls, **kw):
  o = cls.from_buffer((ctypes.c_char * cls.SIZE)())
  for k, v in kw.items(): setattr(o, k, v)
  return o

def fmt_ver(v): return '_'.join(str(x) for x in v)

class Img:
  """one firmware image. The body is FILLED WITH ITS OWN OFFSET (`raw[i] = i & 0xff`)
  before the headers go down, so the offset of any `blob[off:off+size]` that
  amdev.py slices out is recoverable from the sixteen bytes at its start -- which
  is what makes the slice's POSITION, not just its length, a gateable claim."""
  def __init__(self): self.raw = bytearray(i & 0xff for i in range(BLOBSZ))
  def view(self): return (ctypes.c_char * BLOBSZ).from_buffer(self.raw)
  def put(self, obj, off=0):
    ctypes.memmove(ctypes.addressof(self.view()) + off, ctypes.byref(obj), ctypes.sizeof(obj))
    return self
  def chdr(self, outer, major, minor, ucode_off, ucode_sz):
    """fill the common header the outer struct CARRIES at offset 0.

    `hdr.from_address(blob)` reads it out of the outer struct's first member, so
    the version goes INTO the outer struct -- laying it underneath would be
    overwritten by the outer struct's own zeroed member."""
    h = outer.header
    h.ucode_array_offset_bytes = ucode_off
    h.ucode_size_bytes = ucode_sz
    h.header_version_major = major
    h.header_version_minor = minor
    h.size_bytes = 0x8000
    return outer

  # psp_<ver>_sos.bin -- :33-39
  def psp(self, major=2, minor=1, count=2, aux=1, bl_off=0x80, bl_sz=0x40, bl_type=0x12):
    o = mk(getattr(am, f"struct_psp_firmware_header_v{major}_{minor}"),
           **({'psp_fw_bin_count': count, 'psp_aux_fw_bin_index': aux} if (major, minor) == (2, 1) else
               {'psp_fw_bin_count': count}))
    self.chdr(o, major, minor, 0x100, 0x2000)
    d = o.psp_fw_bin[0]
    d.fw_type = bl_type; d.offset_bytes = bl_off; d.size_bytes = bl_sz; d.fw_version = 0x11223344
    return self.put(o)

  # smu_<ver>.bin -- :46-54.  `p2s` is one (off, sz) per soft-pptable entry that
  # carries the P2S magic id :53 tests; each lands at `pptable_entry_offset+i*stride`.
  def smu(self, minor=1, ucode_off=0x200, ucode_sz=0x900, pptable_count=0,
          pptable_entry_offset=0x4000, p2s=()):
    o = mk(getattr(am, f"struct_smc_firmware_header_v2_{minor}"),
           **({'pptable_count': pptable_count, 'pptable_entry_offset': pptable_entry_offset} if minor == 1 else {}))
    self.chdr(o.v1_0, 2, minor, ucode_off, ucode_sz)
    self.put(o)
    for i, (off, sz) in enumerate(p2s):
      self.put(mk(am.struct_smc_soft_pptable_entry, id=0x50325358, ppt_offset_bytes=off, ppt_size_bytes=sz),
               pptable_entry_offset + i * ctypes.sizeof(am.struct_smc_soft_pptable_entry))
    return self

  # sdma_<ver>.bin -- :57-64.  Same shape as gfx: v2_0's `ctx_ucode_size_bytes` and
  # v3_0's `ucode_size_bytes` are the struct's OWN members, distinct from the
  # common header's `ucode_size_bytes`.
  def sdma(self, major, minor=0, ucode_off=0x300, ucode_sz=0x700,
           ctx_ucode_sz=0x90, ctl_off=0x5000, ctl_sz=0x6000):
    o = mk(getattr(am, f"struct_sdma_firmware_header_v{major}_{minor}"))
    self.chdr(o, major, minor, ucode_off, ucode_sz)
    if major == 2:
      o.ctx_ucode_size_bytes = ctx_ucode_sz
      o.ctl_ucode_offset = ctl_off
      o.ctl_ucode_size_bytes = ctl_sz
    elif major == 3:
      o.ucode_offset_bytes = ucode_off
      o.ucode_size_bytes = ucode_sz
    return self.put(o)

  # gc_<ver>_{pfp,me,mec}.bin -- :66-82
  def gfx(self, major, minor=0, ucode_off=0x400, ucode_sz=0x1000, jt_off=0x40, jt_sz=0x20,
          data_off=0x6000, data_sz=0x300, lo=0xDEADBEEF, hi=0x1234):
    """MEASURED, twice, by letting amdev.py read this back: `ucode_off` is
    `hdr.header.ucode_array_offset_bytes` (:70, the COMMON header) but the v2_0
    code arm's size is `hdr.ucode_size_bytes` (:78) -- the struct's OWN field,
    a different member from the common header's `ucode_size_bytes`. A fixture
    that set only the common one produced a ZERO-length descriptor."""
    o = mk(getattr(am, f"struct_gfx_firmware_header_v{major}_{minor}"))
    self.chdr(o, major, minor, ucode_off, ucode_sz)
    if major == 1: o.jt_offset = jt_off; o.jt_size = jt_sz
    else:
      o.ucode_offset_bytes = ucode_off
      o.ucode_size_bytes = ucode_sz
      o.data_offset_bytes = data_off; o.data_size_bytes = data_sz
      o.ucode_start_addr_lo = lo; o.ucode_start_addr_hi = hi
    return self.put(o)

  # gc_<ver>_imu.bin -- :85-88
  def imu(self, ucode_off=0x700, iram_sz=0x800, dram_sz=0x900):
    o = mk(am.struct_imu_firmware_header_v1_0)
    self.chdr(o, 1, 0, ucode_off, 0x3000)
    o.imu_iram_ucode_size_bytes = iram_sz
    o.imu_dram_ucode_size_bytes = dram_sz
    return self.put(o)

  # gc_<ver>_rlc.bin -- :91-109.  The FOUR headers are a nesting CHAIN (v2_1 begins
  # with v2_0, v2_2 with v2_1, v2_3 with v2_2), so ONE image holding a filled v2_3
  # at offset 0 reads back as all four -- which is what `load_fw` needs, since it
  # re-derives each class from the SAME address.
  def rlc(self, minor, ucode_off=0x800, ucode_sz=0x1000):
    v23 = mk(am.struct_rlc_firmware_header_v2_3)
    v21 = v23.v2_2.v2_1
    v20 = v21.v2_0
    v21.save_restore_list_cntl_size_bytes = 0x101; v21.save_restore_list_cntl_offset_bytes = 0x102
    v21.save_restore_list_gpm_size_bytes = 0x201; v21.save_restore_list_gpm_offset_bytes = 0x202
    v21.save_restore_list_srm_size_bytes = 0x301; v21.save_restore_list_srm_offset_bytes = 0x302
    v23.v2_2.rlc_iram_ucode_size_bytes = 0x401; v23.v2_2.rlc_iram_ucode_offset_bytes = 0x402
    v23.v2_2.rlc_dram_ucode_size_bytes = 0x501; v23.v2_2.rlc_dram_ucode_offset_bytes = 0x502
    v23.rlcp_ucode_size_bytes = 0x601; v23.rlcp_ucode_offset_bytes = 0x602
    v23.rlcv_ucode_size_bytes = 0x701; v23.rlcv_ucode_offset_bytes = 0x702
    self.chdr(v20, 2, minor, ucode_off, ucode_sz)
    return self.put(v23, 0)

  def mem(self): return memoryview(self.raw)   # writable: :51 does from_buffer on a slice

class FW:
  def __init__(self, tbl): self.tbl = tbl
  def load_fw(self, fname, *headers, versioned_header=None):
    img = self.tbl[fname]
    if versioned_header is not None:
      ch = am.struct_common_firmware_header.from_address(ctypes.addressof(img.view()))
      headers = headers + (getattr(am, versioned_header + f"_v{ch.header_version_major}_{ch.header_version_minor}"),)
    return tuple([img.mem()] + [h.from_address(ctypes.addressof(img.view())) for h in headers])

class Dev:
  def __init__(self, ipver):
    self.ip_ver = ipver
    self.devfmt = "0000:00:00.0"

def run(ipver, tbl):
  dev = Dev(ipver)
  f = AMFirmware.__new__(AMFirmware)
  f.adev = dev
  fw = FW(tbl)
  f.load_fw = lambda fname, *hs, versioned_header=None: fw.load_fw(fname, *hs, versioned_header=versioned_header)
  f.__init__(dev)
  return f

class Run:
  """`run` plus the images, so a slice's POSITION is recoverable."""
  def __init__(self, ipver, tbl):
    self.f = run(ipver, tbl)
    self.tbl = tbl
  def sos(self, fw_type): return self.f.sos_fw[fw_type]
  def descs(self): return self.f.descs
  def ucode(self): return self.f.ucode_start
  def _blob_of(self, mv): return bytes(mv.obj)
  def desc_rows(self):
    out = []
    for types, mv in self.f.descs:
      whole = bytes(mv.obj)
      i = whole.find(bytes(mv[:16])) if len(mv) >= 16 else -1
      out.append((list(types), len(mv), None if i < 0 else i))
    return out

def sos_rows(fn):
  """(fw_type, size, offset) per socode, recovered the same way."""
  out = []
  for k, mv in fn.sos_fw.items():
    whole = bytes(mv.obj)
    i = whole.find(bytes(mv[:16])) if len(mv) >= 16 else -1
    out.append((k, len(mv), None if i < 0 else i))
  return sorted(out)

MP0, MP1, GC, SDMA0 = am.MP0_HWIP, am.MP1_HWIP, am.GC_HWIP, am.SDMA0_HWIP

def tbl_for(gc, sdma, mp1=(13, 0, 10), mp0=(11, 0, 0), psp_v=(2, 1), smu_v=(1,),
            sdma_v=(1, 0), gfx_v=(1, 0), rlc_minor=1, p2s=(), psp_kw=None, imu=True):
  """the whole firmware set amdev.py asks for, for ONE (gc, sdma) fixture."""
  t = {f"psp_{fmt_ver(mp0)}_sos.bin": Img().psp(*psp_v, **(psp_kw or {}))}
  t[f"smu_{fmt_ver(mp1)}.bin"] = Img().smu(*smu_v, p2s=p2s, pptable_count=len(p2s) + 1)
  t[f"sdma_{fmt_ver(sdma)}.bin"] = Img().sdma(*sdma_v)
  gcv = fmt_ver(gc)
  # :67 is `([('PFP',1),('ME',1)] if gc >= (12,0,0) else []) + [('MEC',1)]`, so MEC is
  # loaded UNCONDITIONALLY -- only PFP and ME are version-gated. Measured: a gc
  # 9.4.0 fixture still asks for gc_9_4_0_mec.bin.
  for w in (['pfp', 'me'] if gc >= (12, 0, 0) else []) + ['mec']: t[f"gc_{gcv}_{w}.bin"] = Img().gfx(*gfx_v)
  if gc >= (11, 0, 0) and imu: t[f"gc_{gcv}_imu.bin"] = Img().imu()   # :85
  t[f"gc_{gcv}_rlc.bin"] = Img().rlc(rlc_minor)                      # :91, unconditional
  return t

def ipver_for(gc, sdma, mp1=(13, 0, 10), mp0=(11, 0, 0)):
  return {MP0: mp0, MP1: mp1, GC: gc, SDMA0: sdma}