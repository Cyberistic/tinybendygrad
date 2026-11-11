# tinybendygrad/runtime/ops_npy.bend -- port of tinygrad/runtime/ops_npy.py
#
# FOUR LINES:
#
#     1  from tinygrad.device import Compiled, HostAllocator
#     2
#     3  class NpyDevice(Compiled):
#     4    def __init__(self, device:str): super().__init__(device, HostAllocator(self), [], None)
#
# So the class INHERITS EVERYTHING and overrides ONE METHOD, and the whole
# content of the port is FOUR ARGUMENTS and what each of them becomes:
#
#     device   -> self.device                                  device.py:396
#     HostAllocator(self) -> self.allocator                    device.py:396
#     []       -> self.renderers                               device.py:396
#     None     -> self.runtime_t                               device.py:396
#
# THE ARGUMENT NOBODY EXPECTS. `renderers or [Renderer]` at tinygrad/device.py:382 symbol=__init__ is an
# `or`, and `[]` is FALSY, so `NpyDevice` is NOT the renderer-less device its
# source line suggests -- it is handed `[Renderer]`, the same default every
# `Compiled` without a renderer gets. MEASURED: `[r.__name__ for r in
# NpyDevice('NPY').renderers]` is `['Renderer']` and `renderers[0] is Renderer`.
# That is the headline row of this file and it is one token of Python.
#
# the second thing the four lines say, by what they do not contain:
# `RDMADevice.__init__` (ops_rdma.py:70) calls `self._select_iface(device)`.
# `NpyDevice.__init__` does not. So:
#   * `self.iface` is never set, and `peer_group` (tinygrad/device.py:384 symbol=__init__) falls all the
#     way through `getattr(getattr(self,'iface',None),'peer_group', …)` to
#     `device.split(":")[0]` -- the head, "NPY".
#   * `device_id` comes from `Compiled.__init__` (tinygrad/device.py:383 symbol=__init__) and NOT from
#     `_select_iface` (tinygrad/device.py:469 symbol=_select_iface), which sets it FIRST and then asserts on
#     the deprecated `NPY_IFACE` env var. Two lines of Python set the same
#     field and only one of them can run here.
#   * `self.host` is device.py:418, `host_name(peer_group, HCQ_RUNTIME_DEV)`,
#     which for a local peer group is the string "CPU".
#   * `arch` is None, so `_select_renderer` (tinygrad/device.py:462 symbol=_select_renderer) passes NO `arch`
#     kwarg at all: `({"arch": self.arch} if self.arch else {})`.
#   * `NpyDevice.ifaces` is `[]`, inherited from `Compiled` (tinygrad/device.py:363 symbol=ifaces).
#

# THE PORTABLE END-TO-END DEVICE. The brief asked for a judgement here and the
# answer is yes, with one correction to the premise.
#
# `ops_npy.py` does not touch numpy: `NpyDevice`'s storage is `mmap` and its
# surface is `HostAllocator`'s, so "the whole surface is numpy files" is not
# quite it -- the whole surface is the HOST allocator. What is true, and what
# matters, is the conclusion: this is the only device in tinygrad whose ENTIRE
# contract is `mmap` + a memoryview + the default renderer. No driver, no FFI,
# no queue, no shader, no PCIe. So it is the one device where the contract can
# be checked by RUNNING it, and this file's gate is built out of numbers read
# off a real `NpyDevice('NPY')` that allocated, was written into, was read back
# and was freed (MEASURED; `.agents/slop/oracle_npy_torch.py` is the script).
# Every device below it in the tree -- disk, python, cpu -- inherits something
# from it, and it is the only one that needs no `import "./x.c"`.
#

# WHAT IS PORTED, DEF BY DEF. The first block is `ops_npy.py` and the second is
# `HostAllocator` (tinygrad/device.py:293 symbol=HostAllocator), which is the surface those four lines
# expose and which nothing else in `runtime/` re-implements.
#
# ops_npy.py
#   :3  `class NpyDevice(Compiled)`   PORTED  `Npy` -- four fields and the trace
#   :4  the four arguments            PORTED  `Npy.of` and the five constant defs
#   :4  `[]` becoming `[Renderer]`    PORTED  `RENDERER_EFFECTIVE` -- upstream's `HostAllocator` sits beside the `[]`
#                                        and upstream's `Compiled.__init__`
#                                        (tinygrad/device.py:382
#                                        symbol=Compiled.__init__) makes it
#                                        `[Renderer]`
#   --  the missing `_select_iface`   PORTED  `Npy.peer`, `Npy.did`, `Npy.host`
#
# device.py, `HostAllocator`
#   :305 `super().__init__(dev, False, False)`  PORTED  `npy.supports`
#   :307 `mmap.mmap(-1, size, ACCESS_WRITE)`    PORTED  `npy.mmap`
#   :308 `BufferStorage(view.addr, meta, view)` PORTED  `npy.alloc` (THREE args)
#   :310-312 `_free`'s remote branch    PORTED  `npy.free` -- and NPY never takes it
#   :315 `_copyin`                      PORTED  `npy.copyin`  synchronize FIRST
#   :316 the `_view(...)[:] = ...`      PORTED  `npy.copyin`  the SOURCE's length
#   :317 `_copyout`                     PORTED  `npy.copyout`
#   :328-329 `_map`'s host guard        PORTED  `npy.map.at`   the REFUSAL
#   :329 `BufferStorage(buf.host.addr)` PORTED  `npy.map`     ONE argument
#   :330 `_offset`                      PORTED  `npy.offset`   `buf + offset`
#

# THE THREE WALLS.
#
# 1. MMAP (tinygrad/device.py:297 symbol=_alloc). `mmap.mmap(-1, size, access=ACCESS_WRITE)` is a
#    syscall and this file reaches host memory the way `device.bend` reaches
#    it -- by NAMING the call in a trace. `mmap`/`munmap`/`memcpy` and
#    `to_mv` (tinygrad/helpers.py:575 symbol=to_mv, `ctypes.from_address`) are FFI seams.
#    TODO(p3) device.py:297  symbol=_alloc  mmap.mmap -- the mapping syscall.
#    TODO(p3) helpers.py:575  symbol=to_mv  to_mv -- `memoryview((ctypes.c_uint8*sz).from_address(ptr))`.
# 2. `cpu_profile` (device.py:315,:317). A `with` around the copy that writes a
#    profile event and re-reads `DEBUG`. It wraps the copy, it does not change
#    it, and the three calls inside it are what the gate pins.
#    TODO(p3) device.py:310  symbol=_copyin  cpu_profile -- the `with` and its profile event.
# 3. `Device[buf.device]` (tinygrad/device.py:315 symbol=_map). Opening a device by string is a
#    registry lookup and a hardware open. `device.bend` OWES this file the
#    already-opened set, so the port compares host NAMES rather than
#    interning a device object -- and the host names are interned into two tags
#    so `device.bend`'s `map_ok` can be used as it is written.
#    TODO(p3) device.py:315  `Device[buf.device]` -- the registry open.
#

# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE host call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind, and there is
# no `import "./x.c"` in this file: the syscall trace IS the record of the
# call, so a foreign effect would be a second way of saying the same thing.
# `ops_webgpu.bend` needed one because its calls are ctypes STRUCTS; these are
# `(size, addr)` pairs.
#
# THE RAISES ARE IN THE TRACE, both of them, and they are the device's two
# refusals: `Allocator.alloc`'s `assert size > 0` (tinygrad/device.py:257-258 symbol=alloc) and
# `HostAllocator._map`'s host guard (tinygrad/device.py:314-315 symbol=_map). A refusal records itself
# and truncates: `Tr.emit` records NOTHING once `refused` is set, so
# `alloc(0)` shows as `[REFUSE]` and never reaches `mmap`, which is what
# `npy_alloc0_n` and `npy_alloc0_no_mmap` read.

import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S


# THE CONSTANTS. Every literal in the source and the four that come out of
# running `NpyDevice('NPY')`.


# the six host calls, in the order `HostAllocator` can make them.
def CALL_SYNC() -> U32: 0
def CALL_MMAP() -> U32: 1
def CALL_MVIEW() -> U32: 2
def CALL_MVWRITE() -> U32: 3
def CALL_MUNMAP() -> U32: 4
def CALL_REFUSE() -> U32: 5

# which of the two refusals. `npy_refuse_n` counts them.
def REFUSE_ALLOC() -> U32: 0
def REFUSE_MAP() -> U32: 1

# the FOUR arguments of super().__init__, interned so the gate can print them.
# `ALLOC_HOST` is the allocator `HostAllocator(self)` names -- 1 and not 0 so
# that "no allocator" is distinguishable from "the host allocator".
def ALLOC_HOST() -> U32: 1
def RUNTIME_NONE() -> U32: 0
# `[]` as it is WRITTEN, and `[Renderer]` as it is USED. device.py:396 is
# `renderers or [Renderer]` and `[]` is falsy.
def RENDERERS_PASSED() -> U32: 0
def RENDERERS_EFFECTIVE() -> U32: 1
# `self.arch` is None, and device.py:483 asks `if self.arch` -- so NO arch kwarg
# reaches `DEV.target`.
def ARCH_KWARG() -> U32: 0

# `Compiled.host` (device.py:418) is "CPU" for any local peer group. Two tags
# so the map guard has a second value to refuse on; `device.bend`'s `map_ok`
# compares U32s and this is where the U32s come from.
def HOST_CPU() -> U32: 1
def HOST_OTHER() -> U32: 2

def hcq() -> String: "CPU"

# the two refusal messages, `f"…{size}"` and `f"…{self.dev.device}"`.
def MSG_ALLOC_HEAD() -> String: "alloc size must be positive, getting "
def MSG_MAP_HEAD() -> String: "host memory is not on the node of "

def FMT_B() -> U32: 1


# THE TYPES.


# ONE host call and the ONE number it is given. `arg` is the size for MMAP,
# MVIEW and MVWRITE and 0 for SYNC, MUNMAP and REFUSE, where the refused
# quantity rides on `Tr.refused` instead -- the same decision
# ops_webgpu.bend makes about its four argumentless calls.
type Call is Data:
  Call{k: U32, arg: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, refused: Bool}

# `NpyDevice.__init__`'s four arguments, the three fields `Compiled.__init__`
# derives from the device string, and the trace. `alloc` and `runtime` are the
# interned arguments; `did`, `peer` and `host` are what device.py:397-398 and
# :418 write.
type Npy is Data:
  Npy{dev: String, alloc: U32, runtime: U32, nrender: U32, sup_disk: Bool,
      sup_xfer: Bool, did: U32, peer: String, host: String, t: Tr}


# THE TRACE.

def Tr.of() -> Tr: Tr{Nil{}, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, refused}: calls

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, refused}: refused

def Tr.ncalls(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])), refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, refused}: Tr.emit.go(refused, k, arg, calls)

# a refusal is recorded and is also the thing that truncates. `calls` and
# `refused` are both read twice and both take `+`, and the `+refused` on the
# parameter is what makes the entry survive on a trace that is already
# refused -- which is the case ops_webgpu.bend found in itself and this file
# does not have, because no refusal in `HostAllocator` is ever nested inside
# another. `npy_refuse_nested` says so rather than leaving it to be assumed.
def Tr.refuse.at(which: U32, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +refused}:
      Tr{Bool.pick(List<&2, Call>, refused, calls,
                   List.append(&2, Call, calls, [Call{CALL_REFUSE(), which}])), True{}}

def Tr.refuse(which: U32, t: Tr) -> Tr: Tr.refuse.at(which, t)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg


# READING THE TRACE. Same three readers as ops_webgpu.bend and torch.bend, and
# the same fuel bug they were written around: the fuel is the TRACE's length and
# the answer is `at == patlen`, so a reversed pattern does NOT match.

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def ustr(xs: List<&2, U32>) -> String: String.join(ush(xs, ",", Nil{}), ",")

# two TRACES compared elementwise, (kind, arg) at a time -- `u32_list_eq` cannot
# take a `List<&2, Call>` and the shape of the claim is "the same calls in the
# same order", which is per-element.
def call_eq.go(a: List<&2, Call>, b: List<&2, Call>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case +x <> t:
      match b:
        case Nil{}: False{}
        case +y <> u: call_eq.go(t, u, Bool.or(bad, Bool.not(Tr.has.step.same2(Call.k(x), Call.k(y), Call.arg(x), Call.arg(y)))))

def call_list_eq(+a: List<&2, Call>, +b: List<&2, Call>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, Call, a)),
                     U32.from_nat(List.length(&2, Call, b))), call_eq.go(a, b, False{}))


# THE CONSTRUCTOR. ops_npy.py:4 as one def, and the five rows it answers.
#
# `device_id` is `D.dev_id` (device.py:397) and NOT `_select_iface`'s parse
# (device.py:494) -- `NpyDevice.__init__` never calls `_select_iface`, which is
# the whole of what makes `NPY_IFACE` a dead env var here.
def Npy.of(+dev: String) -> Npy:
  Npy{dev, ALLOC_HOST(), RUNTIME_NONE(), RENDERERS_EFFECTIVE(), False{}, False{},
      D.dev_id(dev), D.head(dev), D.host_name(D.head(dev), hcq()), Tr.of()}

def Npy.dev(x: Npy) -> String:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: dev

def Npy.alloc(x: Npy) -> U32:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: alloc

def Npy.runtime(x: Npy) -> U32:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: runtime

def Npy.nrender(x: Npy) -> U32:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: nrender

def Npy.sup_disk(x: Npy) -> Bool:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: sup_disk

def Npy.sup_xfer(x: Npy) -> Bool:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: sup_xfer

def Npy.did(x: Npy) -> U32:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: did

def Npy.peer(x: Npy) -> String:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: peer

def Npy.host(x: Npy) -> String:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: host

def Npy.tr(x: Npy) -> Tr:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}: t

def Npy.at(x: Npy, t: Tr) -> Npy:
  match x:
    case Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, _}:
      Npy{dev, alloc, runtime, nrender, sup_disk, sup_xfer, did, peer, host, t}


# THE ALLOCATOR SURFACE. Every def here is one line of `HostAllocator`, and
# every one of them either builds one host call's argument or records it.


# device.py:305 `super().__init__(dev, supports_copy_from_disk=False,
# supports_transfer=False)` -- BOTH flags off, and they are the only allocator
# in the tree that turns both off, which is what makes a host buffer
# un-transferable. `device.bend` already carries the pair as `host_supports`,
# so the port READS it: two spellings of one fact are a bug waiting to happen.
def npy.supports() -> List<&2, U32>: D.host_supports()

# device.py:316,:324,:329 `self._view(addr, n)`, i.e.
# `MMIOInterface(addr, n, fmt='B')` -> `to_mv(addr, n)`. `fmt='B'` at every
# site and it is not decoration: `_copyin`'s `src.cast('B')` needs a
# byte-typed destination.
def npy.mview(size: U32, t: Tr) -> Tr: Tr.emit(CALL_MVIEW(), size, t)

# device.py:307 `mmap.mmap(-1, size, access=mmap.ACCESS_WRITE)`. THE RAW SIZE.
# There is no `round_up` anywhere in `HostAllocator`, which is the whole
# difference from `BNXTAllocator._alloc` (ops_rdma.py:40) and the reason the
# two allocators' traces are not interchangeable: `npy_alloc_raw` pins that a
# 5-byte allocation asks mmap for FIVE bytes.
def npy.mmap(size: U32, t: Tr) -> Tr: Tr.emit(CALL_MMAP(), size, t)

# device.py:325 `self.dev.synchronize()` -- FIRST in BOTH directions, before
# the view and before the write. The order is load-bearing and the gate reads
# it in `npy_copyin_sync_first` and `npy_copyout_sync_first`.
def npy.sync(t: Tr) -> Tr: Tr.emit(CALL_SYNC(), 0, t)

# device.py:315-316 `self.dev.synchronize()` then
# `self._view(dest, src.nbytes)[:] = src.cast('B')`. The LENGTH IS THE
# SOURCE'S (`src.nbytes`), never the destination buffer's -- which is why a
# short upload copies short and a LONGER one raises from the memoryview slice
# assignment instead of clamping. `npy_copyin_len` is that argument.
def npy.copyin(+len: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MVWRITE(), len, npy.mview(len, npy.sync(t)))

# device.py:324-318 `_copyout` is the same three calls in the same order with
# `dest.nbytes` -- the DESTINATION's length this time, because there the
# memoryview being assigned is `dest`. Two defs for two Python defs even though
# the trace is identical; `npy_copyout_order` and `npy_copyin_order` are the
# same list and `npy_copyin_is_copyout` is the row that says so.
def npy.copyout(+len: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MVWRITE(), len, npy.mview(len, npy.sync(t)))

# device.py:270 `assert size > 0, f"alloc size must be positive, getting
# {size}"` -- the ONE refusal on the allocation path, and it lives in
# `Allocator.alloc` rather than in `HostAllocator`, so it is `Compiled`'s rule
# that NPY inherits. `size` is read twice and `Bool.pick` is strict, so both
# arms are built and the `U32` lives in a record: the same `Amt`/`Cap` trick
# `device.bend` uses for `round_up` and `too_big`.
type Sz is Data:
  Sz{size: U32, msg: String}

def npy.alloc_msg(size: U32) -> String: String.concat([MSG_ALLOC_HEAD(), U32.show(size)])

def Sz.size(s: Sz) -> U32:
  match s:
    case Sz{size, msg}: size

# device.py:311 `return BufferStorage(view.addr, meta, view)` -- THREE
# arguments, so the storage carries the address, the mmap AND the memoryview.
# `npy_map_args` is the contrast: `_map` returns a ONE-argument BufferStorage.
def npy.alloc.go(+s: Sz, t: Tr) -> Tr: npy.mview(Sz.size(s), npy.mmap(Sz.size(s), t))

def npy.alloc.at(+size: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, U32.is_gt(size, 0), npy.alloc.go(Sz{size, npy.alloc_msg(size)}, t),
            Tr.refuse(REFUSE_ALLOC(), t))

def npy.alloc(size: U32, t: Tr) -> Tr: npy.alloc.at(size, t)

# device.py:310-312 `_free` -- `if (remote:=getattr(self.dev,"remote",None)) is
# not None: self.dev.synchronize(); remote.free_sysmem(storage.host)`. `NPY`
# has NO `remote` attribute, so BOTH branches are skipped and the memory is
# never handed back: the mmap lives as long as the `BufferStorage.meta`
# reference is. `npy_free_n = 0` is the row that says so, and `npy_free_remote_n
# = 1` is the row that says the OTHER arm exists -- a free that always munmaps
# moves exactly one of the two.
def npy.free.at(+remote: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, remote, Tr.emit(CALL_MUNMAP(), 0, t), t)

def npy.free(remote: Bool, t: Tr) -> Tr: npy.free.at(remote, t)

# device.py:328-329 `_map` -- `if Device[buf.device].host != self.dev.host:
# raise RuntimeError(f"host memory is not on the node of {self.dev.device}")`
# then `return BufferStorage(buf.host.addr)`. TWO CLAIMS, and the second is
# the interesting one: ONE argument, so the mapped storage has NO `meta` and NO
# `host`. That is measured -- `HostAllocator._map(Buffer('NPY',12,uint8))`
# answers `BufferStorage(0x…, None, None)` -- and it is why `_map` cannot be
# written as a re-`alloc`. `npy_map_args = 1` is that argument count and
# `npy_map_n = 0` is that `_map` makes NO host call at all.
def MSG_MAP(dev: String) -> String: String.concat([MSG_MAP_HEAD(), dev])

def npy.map.at(+same: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, same, t, Tr.refuse(REFUSE_MAP(), t))

# `device.bend`'s `map_ok` IS the guard at device.py:328 (`host != host`), so
# the port calls it rather than restating the comparison.
def npy.map(src_host: U32, dev_host: U32, t: Tr) -> Tr:
  npy.map.at(D.map_ok(src_host, dev_host), t)

# the ARGUMENT COUNT of the BufferStorage `_map` returns, as a number the gate
# can compare against `_alloc`'s three. Not a trace entry: it is a claim about
# a Python call's shape, and it is the one row that cannot be checked by any
# mutation of the trace.
def ALLOC_STORAGE_ARGS() -> U32: 3
def MAP_STORAGE_ARGS() -> U32: 1

# device.py:330 `def _offset(self, buf, size, offset): return buf + offset` --
# the host allocator's WHOLE address arithmetic, and it is `device.bend`'s
# `host_offset`. So a view on NPY HAS an offset, which is the opposite of
# `BNXTAllocator._offset` (ops_rdma.py:52), where it returns `buf` unchanged.
def npy.offset(buf: U32, off: U32) -> U32: D.host_offset(buf, off)

# `HostAllocator._view(addr, size)` views EXACTLY `size` bytes -- not a page. That
# is the whole difference from `BNXTAllocator._alloc` (ops_rdma.py:27,40), whose
# virtual address covers `round_up(mem.nbytes, 0x1000)`, and it is why the two
# allocators' traces are not interchangeable. MEASURED: a 12-byte allocation
# answers `st.host.nbytes == 12`. `npy_alloc_view_exact` and
# `npy_alloc_not_page` are the two halves and a `round_up` that crept into this
# allocator moves the second one and not the first.
def npy.view_bytes(size: U32) -> U32: size

def page_bytes(size: U32) -> U32: H.round_up_u32(size, 4096)


# THE GATE MOVED TO `gates/ops_npy-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the driver
# defines nothing this file needs -- the line `gates/README.md:173` draws.
#
# What they claim is upstream's answer, not a formula: `ops_npy.py`'s text,
# `HostAllocator` as `device.py` writes it, and numbers a real `NpyDevice('NPY')`
# printed. Those 83 rows survive as `oracles/tinybendygrad_runtime_ops_npy.bend.rows`
# and the driver's output is byte-identical to them, sorted.
