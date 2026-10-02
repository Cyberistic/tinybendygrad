"""amdev_drv.py -- drive amdev.py's AMDev METHODS with a fake `self`.

`AMDev.__init__` needs a real GPU, but the METHODS do not: each one reaches the
hardware through a handful of attributes (`self.pci_dev`, `self.mmio`,
`self.vf_mailbox`, `self.reg`), and every one of those can be a recorder. So
`_disable_aspm`, `_read_vram`, `indirect_wreg`, `indirect_wreg_pcie`, `rlcg_rw`,
`wreg_pair` and `_vf_mailbox_request` are invoked as amdev.py wrote them, and the
ORDER, the addresses, the values and the refusals below are amdev.py's own
output rather than a transcription of it.

`wait_cond` is the one name amdev.py imported (`from tinygrad.helpers import
... wait_cond`, :3), so it is patched in amdev's module namespace -- which is what
Python's own `from X import Y` binds.
"""
import sys, ctypes
sys.path.insert(0, '.')
from tinygrad.runtime.autogen.am import am
from tinygrad.runtime.autogen import pci
import tinygrad.runtime.support.am.amdev as M
from tinygrad.runtime.support.am.amdev import AMDev

class Reg:
  """one `self.reg(name)` target: records the writes in order, into the trace too."""
  def __init__(self, name, addr, rec=None):
    # `addr` is a LIST, because amdev.py indexes it: `.addr[inst]` at :316 and
    # `self.addr[inst]` at AMRegister.write/read. A scalar there is a TypeError.
    self.name, self.addr, self.rec = name, [addr, addr + 0x10000], rec
    self.writes = []; self.reads = 0
  def write(self, val, inst=0, direct=False, **kw):
    self.writes.append((val, inst, direct))
    if self.rec is not None: self.rec.wr("reg:" + self.name, self.addr, 4, val)
  def read(self, inst=0, direct=False, **kw):
    self.reads += 1
    if self.rec is not None: self.rec.rd("reg:" + self.name, self.addr, 4)
    return getattr(self, '_rv', 0)

class Rec:
  """the trace: `Rec.of(tag, arg)` per hardware touch, in order."""
  def __init__(self): self.ev = []
  def rd(self, tag, addr, sz): self.ev.append(("R", tag, addr, sz))
  def wr(self, tag, addr, sz, val): self.ev.append(("W", tag, addr, sz, val))
  def of(self): return "|".join(str(e) for e in self.ev)
  def n(self): return len(self.ev)

class PciDev:
  """`read_config` over a supplied byte map; `write_config_flush` records."""
  def __init__(self, rec, cfg):
    self.rec, self.cfg = rec, cfg
  def read_config(self, addr, size):
    v = 0
    for i in range(size): v |= self.cfg.get(addr + i, 0xff if self.cfg.get('_deflt', 0xff) else 0) << (8*i)
    self.rec.rd("cfg", addr, size)
    return v
  def write_config_flush(self, addr, val, size):
    self.cfg[addr] = val & 0xff
    if size > 1: self.cfg[addr+1] = (val >> 8) & 0xff
    self.rec.wr("cfg", addr, size, val)

class Mailbox:
  """`self.vf_mailbox` -- a 2-byte view. `ack` decides what bit 1 reads back."""
  def __init__(self, rec, ack=True): self.rec, self.ack, self.writes = rec, ack, []
  def __getitem__(self, i):
    self.rec.rd("mb", i, 1)
    return (2 if self.ack else 0)
  def __setitem__(self, i, v): self.writes.append((i, v)); self.rec.wr("mb", i, 1, v)

class Mmio:
  """`self.mmio` -- a U32 view whose address IS the index, as `fmt='I'` is."""
  def __init__(self, rec, n=0x4000, vals=None): self.rec, self.n, self.vals = rec, n, vals or {}
  def __len__(self): return self.n
  def __getitem__(self, i):
    self.rec.rd("mm", i, 4)
    return self.vals.get(i, M.am.IDH_READY_TO_ACCESS_GPU)
  def __setitem__(self, i, v): self.vals[i] = v; self.rec.wr("mm", i, 4, v)

class Dev:
  """a bare `self` for the AMDev methods -- no AMDev.__init__ anywhere near it."""
  def __init__(self, rec, regs=None, mmio=None, mb=None, pci_dev=None, gmc=None):
    self._rec, self.regs = rec, regs or {}
    self.mmio = mmio if mmio is not None else Mmio(rec)
    self.vf_mailbox = mb if mb is not None else Mailbox(rec)
    self.pci_dev = pci_dev
    self.gmc = gmc or {}
    self.devfmt = "0000:00:00.0"
    self.is_vf = False
    self.vf_rlc_gated = []
    self.is_err_state = False
    self.vf_access = 0
  def reg(self, name):
    self._rec.rd("reg", name, 0)
    if name not in self.regs: self.regs[name] = Reg(name, 0, self._rec)
    return self.regs[name]
  # the register ACCESS path (:301-312), recorded rather than performed.
  def rreg(self, reg, inst=0, direct=False): self._rec.rd("rreg", reg, 4); return 0
  def wreg(self, reg, val, inst=0, direct=False): self._rec.wr("wreg", reg, 4, val)
  def wreg_pair(self, base, lo, hi, val, inst=0, direct=False):
    self._rec.wr("pair", 0, 4, M.lo32(val)); self._rec.wr("pair", 1, 4, M.hi32(val))

def mkdev(**kw): return Dev(Rec(), **kw)

class NoWait:
  """a `wait_cond` that RECORDS the (mask, value, timeout, msg) and says yes."""
  def __init__(self, rec): self.rec, self.seen = rec, []
  def __call__(self, cond, value=None, timeout_ms=None, msg=None):
    # The PREDICATE IS EVALUATED. `wait_cond(lambda: self.mmio[RCV_DW0], ...)`
    # reads the register inside the lambda, so a harness that records the wait
    # without calling `cond()` misses one hardware read and the port's trace is
    # one entry longer for a reason that is not a bug.
    cond()
    self.rec.ev.append(("WAIT", msg, value, timeout_ms))
    self.seen.append((msg, value, timeout_ms))
    return True

def with_wait(rec, fn, *a, **kw):
  """run `fn` with `wait_cond` patched INTO amdev's namespace, then unpatch."""
  w = NoWait(rec)
  old = M.wait_cond
  M.wait_cond = w
  try: return fn(*a, **kw), w
  finally: M.wait_cond = old