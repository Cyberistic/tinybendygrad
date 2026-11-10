# gates/device-gate.bend -- THE GATE DRIVER for `tinybendygrad/device.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/device.bend as P
import ./../tinybendygrad/LAWS/spec.bend as S

# device.py:65-67, `canonicalize_device`. A tuple or list canonicalises
# elementwise and COLLAPSES to a bare string when the answer is one device,
# which is how a multi-device tensor becomes a single-device one.
def canon_device.device(ix: String) -> String:
  P.canon(ix)

def select_device(flags: U32) -> String:
  P.avail(P.Mk{flags}, P.all_devices())

def reg_empty() -> P.Reg:
  P.Reg{Nil{}}

def reg_open(r: P.Reg, t: String) -> P.Reg:
  P.Reg{P.reg_open.go(P.Reg.open(r), t)}

def reg_len(+r: P.Reg) -> U32:
  U32.from_nat(List.length(&2, String, P.Reg.open(r)))

# device.py:29-31 as a UNIT, which is what a caller of `allowed` has. This is the
# fix for `allow_lower`, and it is one line because `canon` already exists: the
# assert's subject is `P.canon(ix)`, not `ix`. The PAIR `allow_py`/`allow_lower` is
# the row -- they answer the SAME number now, because both spellings reach line 31
# as `PYTHON`, and either one alone is a row that cannot see the case fold.
# `allow_disk`/`allow_npy` exist because the mutation table's `tag_of` row is a
# documented blind spot: "a case fold on a never-exercised conjunct is invisible
# however many fixtures you add for the others", and only the PYTHON branch was
# ever exercised. All four measured by CALLING CPython.
def device_usage(allow: Bool, ix: String) -> Bool:
  P.allowed(allow, P.canon(ix))

# `devname := self.device.split(':')[0].upper()` is the same `head` + `to_upper`
# `canon` starts with, taken BEFORE the strips because the fallback is the
# DEVICE's name and not the renderer's.
def rname(+rend: String, +dev: String) -> String:
  P.rm(P.rm_prefix(P.rm_suffix(String.to_upper(rend), "RENDERER"), String.to_upper(P.head(dev))),
     String.to_upper(P.head(dev)))

# device.py:498, `filtered = [i for i in filtered if t.interface.startswith("MOCK")
# or not i.__name__[:-5].startswith("MOCK")]` -- "never fallback to mock ifaces".
# A mock interface survives a selection ONLY when the target itself is a mock,
# so asking for the real interface on a box that only has the mock one fails
# loudly instead of silently benchmarking nothing. `[i for i in ...]` is a
# filter and the gate wants its LENGTH, which is what `select_by_name` then
# hands to `select_first_inited` -- zero survivors is the `RuntimeError`.
def iface_ok(is_mock: Bool, want_mock: Bool) -> Bool:
  Bool.or(want_mock, Bool.not(is_mock))

def ifaces() -> List<&2, P.AEnt>:
  [P.AEnt{1, "HostIface"}, P.AEnt{2, "MockIface"}, P.AEnt{3, "RealIface"},
   P.AEnt{4, "MockTwoIface"}]

# device.py:406, `has_copy_queue` is `True` on the base class and the subclasses
# that answer False are the ones with no separate DMA path.
def has_copy_queue() -> Bool:
  True{}

# device.py:458-463, `return self.iface.count if hasattr(self, 'iface') else 1`.
# One device unless the interface says otherwise, and the two cases are
# different KINDS of answer -- a count and a default, not two counts.
def count(has_iface: Bool, n: U32) -> U32:
  Bool.pick(U32, has_iface, n, 1)

def renum_end(en: U32) -> U32:
  U32.add(P.renum(en), 1)

# device.py:507, `sigs = [buf.host.view(fmt='Q')[i]/divider for (buf,_), e in es
# for i in (e.st_id, e.en_id)]` -- the signal list is the renumbered slots in
# order, so it is twice the entry count. 16 bytes for a 2-entry batch, which is
# also `timeline_bytes` below, and the two agreeing is the point.
def sig_len(n: U32) -> U32:
  U32.mul(n, 2)

def multi_nb(+m: P.Multi) -> U32:
  P.Multi.nbytes(m)

def base_of(+ar: P.Bar, i: U32) -> U32:
  P.base_of.go(P.bar_at(ar, i))

def is_allocated(+ar: P.Bar, i: U32) -> U32:
  P.is_allocated.bar(ar, P.bar_at(ar, i))

# device.py:123, `assert offset == 0` for a base-less buffer -- the check that
# stops a view of a view from claiming to be a root.
def bvalid_root(off: U32) -> Bool:
  U32.is_zero(off)

def bvalid_base(+ar: P.Bar, b: U32, nb: U32) -> Bool:
  P.bvalid_base.s(P.bar_at(ar, b), P.bar_at(ar, nb))

# device.py:244, `assert self.nbytes == src.nbytes`. `copy_from` is the only
# place the class checks two buffers against each other and it is in BYTES, so a
# same-element-count re-dtype passes and a same-byte-count re-shape does not.
def copy_ok(+ar: P.Bar, dst: U32, src: U32) -> Bool:
  U32.is_eq(P.nbytes(ar, dst), P.nbytes(ar, src))

def too_big(c: P.Cap, null: Bool) -> Bool:
  match c:
    case P.Cap{+cap, size, ext}:
      Bool.and(Bool.not(null),
               Bool.and(U32.is_gt(size, cap), Bool.and(U32.is_gt(cap, 0), Bool.not(ext))))

# device.py:221-223, `if not hasattr(self, '_trace_num'): self._trace_num =
# len(Buffer.profile_events)`. That list is a CLASS attribute (device.py:113), so
# `trace_num` indexes a GLOBAL event log and is NOT a per-buffer counter: the
# first buffer in a process is 0 and the tenth is 9 whatever device it is on.
# TODO(p3) device.py:112  Buffer.profile_events -- a class-level list appended
#   to by `allocate` under PROFILE. WALL: PROFILE is an env flag and the events
#   are `ProfilePointEvent` objects. `trace_num` is PORTED as the length.
def trace_num(n_events: U32) -> U32:
  n_events

# ===========================================================================
# `Program` (device.py:370) is two `pass` bodies and one signature, and the
# signature is the contract every backend implements: buffers, a 3-vector
# global and local size defaulting to (1,1,1), an extra `vals` tuple, and a
# `wait` flag. A default global size of ONE is not a placeholder, it is what
# makes a one-element kernel launchable with no launch metadata.
# ===========================================================================
def gsize() -> List<&2, U32>:
  [1, 1, 1]

# device.py:383, `rtalloc_size: int = 64<<20` -- the bump-allocator pool every
# per-linear buffer is carved out of. 64 MiB, and `rt_buffer` asks for exactly
# this size, so the number appears twice in the class and must be one number.
def rtalloc_size() -> U32:
  67108864


# --- THE GATE ROWS ------------------------------------------------------
# THE GATE. Every row is a number `tinygrad/device.py` fixes, measured with
# `Device['PYTHON']` and friends so no hardware is touched. `1`/`0` are
# booleans, other values are counts, strings and indices.
#
# The rows, their fixtures and the `main` that prints them are the INSTRUMENT
# and they live in `gates/device-gate.bend` -- `gates/README.md:173` says a
# gate's `.bend` driver sits in `gates/`, named by the gate that needs it.
def if_b.go(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def if_b(b: Bool) -> U32:
  if_b.go(b)

def show_list(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def go_show(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: go_show(t, String.concat([acc, U32.show(h), " "]))

def show_bufs(xs: List<&2, U32>) -> String:
  go_show(xs, "")

# `TinyELF`, device.py:355-367. `lib` is bytes, `name` a string, `target` a
# `Target` and `signature` a tuple of `(name, slot, dtype, shape)`. Only the
# dtypes are read by anything and only by `iter_sig`, so the port carries the
# ITEMSIZES -- all `iter_sig` reads, and it keeps the list's element type a
# `U32` rather than an imported record.
# TODO(p3) device.py:344  TinyELF.lib -- `bytes`. WALL: a byte buffer. The C
#   effect behind `Compiler.compile_server` (device.py:349) would hand one back.
#
# The `type` sits IMMEDIATELY above its first reader on purpose. Declared 500
# lines lower it compiles; declared here and read from the gate section it fails
# with "a declared constructor (unknown: Telf)" pointing at the CONSTRUCTOR
# rather than at the cause. See the header, constraint B.
type Telf is Data:
  Telf{nm: String, sigs: List<&2, U32>}

# The binder is `got` and not `nm`: a binder that SHADOWS a def in the record's
# own namespace makes the constructor unresolvable, and the error names the
# constructor rather than the shadowing binder.
def Telf.nm(+x: Telf) -> String:
  match x:
    case Telf{got, sigs}: got

def go_lru_nolru() -> String:
  Bool.show(P.recycled(True{}, True{}, P.Bspec{False{}, False{}, False{}, True{}, False{}}))

def go_lru_ptr() -> String:
  Bool.show(P.recycled(True{}, True{}, P.Bspec{False{}, False{}, False{}, False{}, True{}}))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# ---- the BUFFER fixture: `Buffer('PYTHON', 4, dtypes.int32)` and the two views
# Python builds on it, which is the whole of the view-arithmetic gate. The arena
# is threaded so a row can read offsets AFTER a growth.
#
# Slot 0 is a seeded bottom, so the root is slot 1 and the two views are 2 and 3.
# That is not tidiness: `view_base` is the row that says a view's base is the ROOT
# and not the buffer it was taken of, and with the root at slot 0 both the right
# answer (0) and the wrong one (1) are small numbers. At slot 1 they are 1 and 2.
def buf_seed() -> P.BFound:
  P.bnew(P.bar_empty(), P.bar_bot())

def buf_landing() -> P.BFound:
  P.bnew(P.BFound.ar(buf_seed()), P.root(7, 4, S.int32(), P.spec()))

def buf_view1(+v: P.BFound) -> P.BFound:
  P.bview(P.BFound.ar(v), P.BFound.i(v), 2, S.single(), 8)

def buf_view2(+v: P.BFound) -> P.BFound:
  P.bview(P.BFound.ar(v), P.BFound.i(v), 1, S.uint8(), 4)

def chain() -> P.BFound:
  buf_view2(buf_view1(buf_landing()))

# `Buffer('PYTHON', 4, dtypes.int32).nbytes` -- 4 * 4.
def bn_gate.at(+v: P.BFound) -> U32:
  P.nbytes(P.BFound.ar(v), P.BFound.i(v))

def bn_gate() -> U32:
  bn_gate.at(buf_landing())

# `v2.offset` for the chain: 0 + 8 + 4. A `view` that assigned `offset` instead
# of `self.offset + offset` prints 4 here.
def vg_off() -> U32:
  P.Bn.off(P.bar_at(P.BFound.ar(chain()), P.BFound.i(chain())))


# `v2.base is b.base` -- the view's base is the ROOT, so the chain has one root
# and `base_of` is idempotent.
def vg_base.at(+v: P.BFound) -> U32:
  base_of(P.BFound.ar(v), P.BFound.i(v))

def vg_base() -> U32:
  vg_base.at(chain())

# `b.base is b`, i.e. the ROOT reports ITSELF -- 1, with the root at slot 1 -- and
# `v.base is b.base`: the middle view also reports the ROOT's slot, not its
# parent's. A `view` that stored `base=self` puts 2 in `view_mid_base`.
def vg_root_base() -> U32:
  vg_base.at(buf_landing())

def vg_mid_base() -> U32:
  vg_base.at(buf_view1(buf_landing()))

# `v2.nbytes` -- 1 * 1, the re-dtype, and it is the byte count `copy_from` checks
# and NOT the element count.
def vg_nb.at(+v: P.BFound) -> U32:
  P.nbytes(P.BFound.ar(v), P.BFound.i(v))

def vg_nb() -> U32:
  vg_nb.at(chain())

# An unallocated chain is not allocated: `addr` is 0 for all three, and a view of
# an unallocated buffer stays unallocated.
def vg_alloc() -> U32:
  is_allocated(P.BFound.ar(chain()), P.BFound.i(chain()))

# the three allocated slots of the chain fixture: 1 the root, 2 and 3 the views
def slots() -> List<&2, U32>:
  [1, 2, 3]

# ===========================================================================
# THE LINK FIXTURES. The names are the ORACLE's names and the slots are the
# ORACLE's sentinels, so a row and an oracle row are compared BY THE NUMBER.
#
# The registry the rows resolve against, one per case, because upstream's
# `Compiled.link_bufs` is a CLASS attribute that every case CLEARS before it
# installs its own entries.
# ===========================================================================
def lk_reg_plain() -> List<&2, P.Lk>:
  [P.Lk{"mine", 0, 1}]

def lk_reg_dev() -> List<&2, P.Lk>:
  [P.Lk{"python_mine", 0, 2}]

def lk_reg_both() -> List<&2, P.Lk>:
  P.link_add(lk_reg_dev(), "mine", 0, 1)

def lk_reg_call() -> List<&2, P.Lk>:
  [P.Lk{"call", 1, 3}]

def lk_reg_devcall() -> List<&2, P.Lk>:
  [P.Lk{"python_call", 1, 4}]

def lk_reg_dup() -> List<&2, P.Lk>:
  P.link_add([P.Lk{"dup", 0, 5}], "dup", 0, 6)

def lk_reg_none() -> List<&2, P.Lk>:
  Nil{}

# THE EIGHT RESOLUTIONS, one per oracle case.
def lk_r_plain() -> P.LkRes:
  P.link_resolve(lk_reg_plain(), Some{"mine"}, "PYTHON", P.link_buffer_base())

def lk_r_dev() -> P.LkRes:
  P.link_resolve(lk_reg_dev(), Some{"mine"}, "PYTHON", P.link_buffer_base())

def lk_r_both() -> P.LkRes:
  P.link_resolve(lk_reg_both(), Some{"mine"}, "PYTHON", P.link_buffer_base())

def lk_r_call() -> P.LkRes:
  P.link_resolve(lk_reg_call(), Some{"call"}, "PYTHON", P.link_buffer_base())

def lk_r_devcall() -> P.LkRes:
  P.link_resolve(lk_reg_devcall(), Some{"call"}, "PYTHON", P.link_buffer_base())

def lk_r_dup() -> P.LkRes:
  P.link_resolve(lk_reg_dup(), Some{"dup"}, "PYTHON", P.link_buffer_base())

def lk_r_none() -> P.LkRes:
  P.link_resolve(lk_reg_none(), Some{"mine"}, "PYTHON", P.link_buffer_base())

def lk_r_unnamed() -> P.LkRes:
  P.link_resolve(lk_reg_plain(), None{}, "PYTHON", P.link_buffer_base())

# The device's OWN answer, asked only after both registry keys missed.
def lk_r_hook() -> P.LkRes:
  P.link_resolve(lk_reg_none(), Some{"mine"}, "NULL", P.Hook{True{}, 7})

# THE WRONG DEVICE. The device-scoped key is a FOLD of the device string, so
# an entry registered for PYTHON is invisible to an alloc on METAL:0.
def lk_r_wrongdev() -> P.LkRes:
  P.link_resolve(lk_reg_dev(), Some{"mine"}, "METAL:0", P.link_buffer_base())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("all_len", U32.from_nat(List.length(&2, P.AEnt, P.all_devices())))
    b : Unit <- row("stem_len", U32.from_nat(List.length(&2, P.AEnt, P.stems())))
    c : Unit <- row("reg_len", U32.from_nat(List.length(&2, P.DEnt, P.registry())))
    d : Unit <- srow("canon_cpu0", P.canon("cpu:0"))
    e : Unit <- srow("canon_cpu00", P.canon("cpu:0:0"))
    f : Unit <- srow("canon_wg2", P.canon("WEBGPU:2"))
    g : Unit <- srow("canon_nv00", P.canon("nv:00"))
    h : Unit <- srow("canon_x00", P.canon("x:0:0"))
    i : Unit <- srow("canon_a", P.canon("a:b"))
    j : Unit <- srow("canon_dev", canon_device.device("cpu:0"))
    k : Unit <- row("dcls_wg", P.dcls("WEBGPU:2"))
    l : Unit <- row("dcls_none", P.dcls("nope"))
    k2 : Unit <- row("dcls_nvme", P.dcls("NVME:0"))
    k3 : Unit <- row("dcls_nvme_lower", P.dcls("nvme:0"))
    m : Unit <- row("open_one", reg_len(reg_open(reg_open(reg_open(reg_empty(), P.canon("cpu:0")), P.canon("CPU")), P.canon("cpu"))))
    n : Unit <- row("open_two", reg_len(reg_open(reg_open(reg_empty(), P.canon("cpu")), P.canon("cpu:1"))))
    o : Unit <- row("allow_py", if_b(device_usage(False{}, "PYTHON:1")))
    o2 : Unit <- row("allow_lower", if_b(device_usage(False{}, "python:1")))
    o3 : Unit <- row("allow_metal", if_b(device_usage(False{}, "METAL")))
    o4 : Unit <- row("allow_on", if_b(device_usage(True{}, "METAL")))
    o5 : Unit <- row("allow_cpu", if_b(device_usage(False{}, "CPU:1")))
    o6 : Unit <- row("allow_disk", if_b(device_usage(False{}, "disk:1")))
    o7 : Unit <- row("allow_npy", if_b(device_usage(False{}, "npy:1")))
    o8 : Unit <- row("allow_cpu_l", if_b(device_usage(False{}, "cpu:1")))
    o9 : Unit <- row("allow_mixed", if_b(device_usage(False{}, "PyThOn:0")))
    r : Unit <- srow("first_amd", select_device(130))
    s : Unit <- srow("first_wg", select_device(256))
    t : Unit <- srow("first_none", select_device(0))
    u : Unit <- row("depr", P.deprecated(P.Mk{0}, P.stems(), 0))
    v : Unit <- row("depr_on", P.deprecated(P.Mk{1}, P.stems(), 0))
    w : Unit <- srow("multi", show_list(P.canon_device.multi(["cpu:0", "CPU", "cpu:1"])))
    x : Unit <- row("disk_one", if_b(P.is_disk(["CPU:1"])))
    y : Unit <- row("disk_two", if_b(P.is_disk(["CPU:1", "disk:0"])))
    z : Unit <- row("disk_no", if_b(P.is_disk(Nil{})))
    z1 : Unit <- row("disk_nvme", if_b(P.is_disk(["NVME:0"])))
    z2 : Unit <- row("disk_nvme_lower", if_b(P.is_disk(["nvme:0"])))
    z3 : Unit <- row("disk_nvme_mixed", if_b(P.is_disk(["CPU:1", "NVME:0"])))
    A : Unit <- row("renum3", P.renum(3))
    B : Unit <- row("renum3e", renum_end(3))
    C : Unit <- row("sig2", sig_len(2))
    D : Unit <- row("lru_default", if_b(P.recycled(True{}, True{}, P.spec())))
    E : Unit <- row("lru_glob_off", if_b(P.recycled(False{}, True{}, P.spec())))
    F : Unit <- row("lru_alloc_off", if_b(P.recycled(True{}, False{}, P.spec())))
    G : Unit <- srow("lru_nolru", go_lru_nolru())
    H : Unit <- srow("lru_ptr", go_lru_ptr())
    I : Unit <- row("map_ok", if_b(P.map_ok(3, 3)))
    J : Unit <- row("map_bad", if_b(P.map_ok(3, 4)))
    K : Unit <- row("hoff", P.host_offset(4096, 16))
    L : Unit <- row("try1", P.alloc_try(1))
    M : Unit <- row("try2", P.alloc_try(2))
    N : Unit <- srow("sig", show_bufs(P.iter_sig([1, 4, 1])))
    O : Unit <- row("rtalloc", rtalloc_size())
    P : Unit <- row("tl_bytes", P.timeline_bytes())
    Q : Unit <- row("did_1", P.dev_id("CPU:1"))
    R : Unit <- row("did_0", P.dev_id("CPU"))
    S : Unit <- row("did_bad", P.dev_id("CPU:a"))
    T : Unit <- row("did_deep", P.dev_id("CPU:1:2"))
    U : Unit <- srow("host_remote", P.host_name("remote:node0", "CPU"))
    V : Unit <- srow("host_plain", P.host_name("CPU", "CPU"))
    W : Unit <- srow("rn_metal", rname("MetalRenderer", "METAL"))
    X : Unit <- srow("rn_clang", rname("ClangRenderer", "CPU"))
    Y : Unit <- srow("rn_cpu1", rname("CstyleRenderer", "CPU:1"))
    Z : Unit <- row("nc_nocache", if_b(P.needs_compile(False{}, True{})))
    A1 : Unit <- row("nc_miss", if_b(P.needs_compile(True{}, False{})))
    A2 : Unit <- row("nc_hit", if_b(P.needs_compile(True{}, True{})))
    A3 : Unit <- row("ifc_keep", if_b(iface_ok(True{}, True{})))
    A4 : Unit <- row("ifc_drop", if_b(iface_ok(True{}, False{})))
    A5 : Unit <- row("ifc_real", if_b(iface_ok(False{}, False{})))
    A6 : Unit <- row("ndl_real", P.iface_filter(P.Mk{5}, ifaces(), False{}, 0))
    A7 : Unit <- row("ndl_mock", P.iface_filter(P.Mk{5}, ifaces(), True{}, 0))
    A8 : Unit <- row("count_no", count(False{}, 8))
    A9 : Unit <- row("count_yes", count(True{}, 8))
    B7 : Unit <- row("nb_py", bn_gate())
    B8 : Unit <- row("view_off", vg_off())
    B9 : Unit <- row("view_base", vg_base())
    C1 : Unit <- row("view_nb", vg_nb())
    C1a : Unit <- row("view_root_base", vg_root_base())
    C1b : Unit <- row("view_mid_base", vg_mid_base())
    C2 : Unit <- row("view_alloc", vg_alloc())
    C3 : Unit <- row("copy_self", if_b(copy_ok(P.BFound.ar(chain()), 1, 1)))
    C4 : Unit <- row("copy_reshape", if_b(copy_ok(P.BFound.ar(chain()), 1, 2)))
    C4a : Unit <- row("big_cpu", if_b(too_big(P.Cap{10, 100, False{}}, String.starts_with(P.dev_name(7), "NULL"))))
    C5 : Unit <- row("null_ok", if_b(too_big(P.Cap{10, 100, False{}}, String.starts_with(P.dev_name(11), "NULL"))))
    C6 : Unit <- row("under_cap", if_b(too_big(P.Cap{10, 5, False{}}, String.starts_with(P.dev_name(7), "NULL"))))
    C7 : Unit <- row("ext_ptr", if_b(too_big(P.Cap{10, 100, True{}}, String.starts_with(P.dev_name(7), "NULL"))))
    C8 : Unit <- row("mem_cpu", P.mem_used(P.BFound.ar(chain()), slots(), 7, 0))
    C9 : Unit <- row("mem_amd", P.mem_used(P.BFound.ar(chain()), slots(), 2, 0))
    D0 : Unit <- row("trace0", trace_num(0))
    D1 : Unit <- row("valid_root", if_b(bvalid_root(0)))
    D2 : Unit <- row("invalid_root", if_b(bvalid_root(4)))
    D3 : Unit <- row("base_ok", if_b(bvalid_base(P.BFound.ar(chain()), 1, 1)))
    D4 : Unit <- row("base_view", if_b(bvalid_base(P.BFound.ar(chain()), 1, 2)))
    D5 : Unit <- row("base_dev", if_b(bvalid_base(P.BFound.ar(chain()), 1, 0)))
    D6 : Unit <- row("lru_take", P.alloc_take([1, 2, 3]))
    D7 : Unit <- row("lru_empty", P.alloc_take(Nil{}))
    D8 : Unit <- row("freed", P.freed([1, 2, 3, 4], 0))
    D9 : Unit <- srow("gsize", show_bufs(gsize()))
    E0 : Unit <- srow("compile_id", P.compile("SRC"))
    E1 : Unit <- row("multi_nb", multi_nb(P.Multi{[1, 2], 16, S.int32()}))
    E2 : Unit <- srow("disp_cpu", P.dev_name(7))
    E3 : Unit <- srow("disp_none", P.dev_name(99))
    E4 : Unit <- srow("hs", show_bufs(P.host_supports()))
    E5 : Unit <- row("hbz", if_b(has_copy_queue()))
    E6 : Unit <- srow("telf", Telf.nm(Telf{"k", [1, 4]}))
    E7 : Unit <- srow("disp_null", P.dev_name(11))
    E8 : Unit <- row("dcls_null", P.dcls("NULL:0"))
    E8a : Unit <- row("tl_size", P.timeline_size())
    F1 : Unit <- srow("tn_plain", P.to_name(["PYTHON", "timeline"]))
    F2 : Unit <- srow("tn_colon", P.to_name(["METAL:0", "handles"]))
    F3 : Unit <- srow("tn_lower", P.to_name(["AMD", "Scratch"]))
    F4 : Unit <- row("lk_lvl_plain", P.LkRes.level(lk_r_plain()))
    F5 : Unit <- row("lk_kind_plain", P.LkRes.kind(lk_r_plain()))
    F6 : Unit <- row("lk_buf_plain", P.LkRes.buf(lk_r_plain()))
    F7 : Unit <- row("lk_lvl_dev", P.LkRes.level(lk_r_dev()))
    F8 : Unit <- row("lk_kind_dev", P.LkRes.kind(lk_r_dev()))
    F9 : Unit <- row("lk_buf_dev", P.LkRes.buf(lk_r_dev()))
    G1 : Unit <- row("lk_lvl_both", P.LkRes.level(lk_r_both()))
    G2 : Unit <- row("lk_buf_both", P.LkRes.buf(lk_r_both()))
    G3 : Unit <- row("lk_lvl_call", P.LkRes.level(lk_r_call()))
    G4 : Unit <- row("lk_kind_call", P.LkRes.kind(lk_r_call()))
    G5 : Unit <- row("lk_buf_call", P.LkRes.buf(lk_r_call()))
    G6 : Unit <- row("lk_lvl_devcall", P.LkRes.level(lk_r_devcall()))
    G7 : Unit <- row("lk_kind_devcall", P.LkRes.kind(lk_r_devcall()))
    G8 : Unit <- row("lk_buf_devcall", P.LkRes.buf(lk_r_devcall()))
    H1 : Unit <- row("lk_lvl_dup", P.LkRes.level(lk_r_dup()))
    H2 : Unit <- row("lk_buf_dup", P.LkRes.buf(lk_r_dup()))
    H3 : Unit <- row("lk_lvl_none", P.LkRes.level(lk_r_none()))
    H4 : Unit <- row("lk_lvl_unnamed", P.LkRes.level(lk_r_unnamed()))
    H5 : Unit <- row("lk_lvl_hook", P.LkRes.level(lk_r_hook()))
    H6 : Unit <- row("lk_buf_hook", P.LkRes.buf(lk_r_hook()))
    H7 : Unit <- row("lk_lvl_wrongdev", P.LkRes.level(lk_r_wrongdev()))
    H8 : Unit <- row("lk_plain_bytes", P.nbytes(P.lk_arena(), 1))
    H9 : Unit <- row("lk_hook_bytes", P.nbytes(P.lk_arena(), 7))
    row("dcls_bend", P.dcls("BEND"))
# ===========================================================================
# THE GATE, and what each row is FOR. `1`/`0` are booleans, other values are
# counts, indices and strings. Every row is a number `tinygrad/device.py` fixes,
# and all 105 were checked against the Python oracle with `Device['PYTHON']` and
# a `get_class` stub for the availability rows -- the interpreted lane, the
# native lane and the oracle are byte-identical.
#
#   COUNTS, because All-True tells you the cases you covered and nothing else:
#   all_len=9      device.py:20 -- nine enumerated devices.
#   stem_len=17    device.py:23 -- the `ops_*.py` walk finds SIXTEEN and the
#                  PORT's OWN `ops_bend.bend` is a SEVENTEENTH, and the five that
#                  are NOT in `ALL_DEVICES` (BEND/HIP/NULL/RDMA/NVME) are why the
#                  two tables are separate.
#   reg_len=17     device.py:37 -- seventeen classes, one per stem.
#   depr_on=1      device.py:55 -- one stem with the legacy env var set trips the
#                  deprecation assert exactly once. Seventeen minus DISK minus
#                  NPY would be 15, and that is the OTHER row, not this one.
#   mem_cpu=25     device.py:190 -- 16 + 8 + 1 over the chain, and `mem_amd=0`
#                  beside it is the per-device SUBSET, which is the only reason
#                  the two counters are not the same number twice.
#
#   `NVME` IS THE ROW THE TABLES WERE MISSING, AND THE COUNTS COULD NOT SEE IT.
#   MEASURED 2026-11-10, UPSTREAM'S OWN WALK OVER `tinygrad/runtime/`:
#     `[x.stem[len("ops_"):].upper() for x in ...iterdir() if x.stem.startswith("ops_")]`
#     -> AMD CL CPU CUDA DISK DSP HIP METAL NPY NULL NV NVME PYTHON QCOM RDMA
#     WEBGPU -- SIXTEEN, `NVME` AMONG THEM, AND `ops_nvme.py` DEFINES
#     `NVMEDevice`, SO UPSTREAM'S `get_class('nvme')` SUCCEEDS. THE PORT HAD
#     SIXTEEN ROWS TOO, WITH `BEND` WHERE `NVME` BELONGS, SO `stem_len` AND
#     `reg_len` BOTH READ **16** AND **NO COUNT COULD SEE THE MISSING ONE** --
#     A COUNT IS NOT A TABLE. THE FIX IS TWO ROWS AND A COUNT:
#     `dcls_nvme=17` AND `dcls_nvme_lower=17` SAY THE CLAIM RESOLVES, AND
#     `disk_nvme=1` / `disk_nvme_lower=1` / `disk_nvme_mixed=1` SAY
#     `is_disk_device` ANSWERS True FOR AN NVME DEVICE, WHICH IT DID NOT --
#     UPSTREAM'S SPELLING IS `in ("DISK", "NVME")` AND THE PORT HAD ONE NAME.
#     CPython's OWN `is_disk_device(("NVME:0",))` ANSWERS True.
#
#   THE FIRST-WINS CLAIMS, and they are two kinds now, not three:
#   open_one=1     device.py:26 + :30 -- `cpu:0`, `CPU` and `cpu` are ONE opened
#                  device. A canonicalize that kept the `:0` prints `open_two`.
#   first_amd=AMD  device.py:46 + :58 -- with AMD and CPU both openable the
#                  default is AMD, because AMD is row 2 and CPU is row 7. This
#                  is an ORDER, and last-wins prints CPU.
#   THE OTHER KIND WAS A RULE -- upstream's `Compiled.pm_bufferize` -- and it is
#                  GONE from upstream AND from this port. The seven rows that
#                  exercised it went with it, and the header records what each
#                  of the seven measured and what covers it now.
#
#   THE VIEW ARITHMETIC, device.py:252:
#   nb_py=16        4 elements of int32.
#   view_off=12     offsets ACCUMULATE: 0 + 8 + 4. A `view` that assigned
#                   `offset` prints 4.
#   view_base=1     the innermost view's base is the ROOT (slot 1), not its
#                   parent. A `view` that stored `base=self` prints 2.
#   view_mid_base=1 the middle view also reports the root. Python's own
#                   `v2.base is b.base` cannot say WHICH slot, so the port pins
#                   the slot number and the gate's fixture seeds a bottom at 0.
#   view_nb=1       the re-dtype's BYTE count, and `copy_reshape=0` is the same
#                   number read through `copy_from`'s assert.
#   view_alloc=0    a view of an unallocated buffer is unallocated.
#
#   THE PREFIX CLAIMS, which is what `device string prefixes` means here:
#   dcls_wg=16 / dcls_null=11 / dcls_bend=2 / dcls_nvme=17 / dcls_nvme_lower=17
#                  -- `get_class` claims on the head at the first colon,
#                  LOWERCASE, so `WEBGPU:2` and `webgpu:2` are one row and a
#                  case-sensitive claim finds nothing. `dcls_nvme` IS **17**
#                  BECAUSE THE `nvme` ROW IS THE **LAST** ONE: THE OTHER
#                  INDICES ARE READ BY `tag_of` (6 DISK, 10 NPY, 13 PYTHON) AND
#                  BY `go_dep`'s BITMASK SLOTS, SO A ROW INSERTED IN THE MIDDLE
#                  WOULD MOVE THEM. `gates/devtag-gate.py` READS THOSE THREE
#                  TAGS OUT OF `tag_of` AND IS THE WITNESS THAT THEY DID NOT
#                  MOVE.
#   rn_metal=METAL  `_renderer_name`'s `or devname`: `MetalRenderer` on `METAL`
#                   reduces to the EMPTY string and the fallback is what makes
#                   the selector `METAL` instead of `""`.
#   host_remote=CPU:node0 / host_plain=CPU -- the `remote:` prefix is the whole
#                   discriminator for a peer group.
#   allow_py=1 / allow_lower=1  `["DISK","NPY","PYTHON"]` is UPPER case, but
#                   device.py:30 REBINDS `ix = self.canonicalize(ix)` and :31 then
#                   reads the REBOUND value, so by the time the assert runs the
#                   name is already `PYTHON:1`. Both spellings PASS with
#                   `ALLOW_DEVICE_USAGE=0` and CPython agrees: measured by
#                   CALLING `Device[...]` under `Context(ALLOW_DEVICE_USAGE=0)`,
#                   `Device['python:1']` SUCCEEDS. These two rows used to read
#                   `allow_lower=0` from `P.allowed(False{}, "python:1")` -- handing
#                   the assert a name CPython never shows it -- which is how
#                   `device.bend` came to be the one gate left UNWIRED. `allowed`
#                   is still the port of the assert STATEMENT; `device_usage` is
#                   the port of `__getitem__`'s TWO lines and is what the rows read.
#   allow_disk=1 / allow_npy=1  the other two branches of the allow-list, and
#                   they exist because `tag_of`'s only fixture was PYTHON: see the
#                   `tag_of` row in the mutation table, which was a measured ZERO.
#                   `allow_metal=0`, `allow_on=1`, `allow_cpu=0`, `allow_cpu_l=0`
#                   and `allow_mixed=1` (`PyThOn:0`) are the other corners.
#   disk_two=1      `is_disk_device` UPPER-cases, so `disk:0` in a tuple counts.
#   disk_nvme=1 / disk_nvme_lower=1 / disk_nvme_mixed=1
#                  -- upstream's `is_disk_device` is
#                  `any(d.split(":", 1)[0].upper() in ("DISK", "NVME") for d in to_tuple(device))`
#                  and **TWO** names are in that tuple. The port had ONE, and
#                  `NVME` is not hypothetical: `tinygrad/runtime/ops_nvme.py`
#                  exists at the pin, defines `NVMEDevice`, and the port ports
#                  that file as `tinybendygrad/runtime/ops_nvme.bend`. MEASURED
#                  2026-11-10, CPython's own `is_disk_device(("NVME:0",))`
#                  answers **True** and the port answered **False**. The two
#                  spellings and the mixed tuple are three rows because a
#                  single one of them cannot see BOTH a dropped name and a
#                  dropped case fold.
#   sig=0 4 8       `iter_sig` yields the ROUNDED slot and advances the running
#                   offset FROM THAT SLOT, because device.py:366s walrus assigns the
#                   rounded value. This row used to read `0 4 5` and its comment
#                   claimed the advance was by the RAW itemsize, with `0 4 8` named as
#                   if it were a variation -- a gate built to ENCODE THE BUG. Found by
#                   the runtime/ops_cpu unit, which carried a local repair for it.
#   multi=CPU,CPU,CPU:1  `canonicalize_device` is a REBUILD and CONS. Appending
#                   reverses the tuple.
#   lru_* / ext_ptr  `Allocator.free`'s FOUR conjuncts, one row each. The global
#                   LRU flag, the allocator's own `lru`, `nolru` and
#                   `external_ptr` are four independent opt-outs and three of
#                   the four rows exist only to see one of them dropped.
#   ndl_real=2 / ndl_mock=4 -- "never fallback to mock ifaces": two mock
#                   interfaces out of four, and asking for a real interface
#                   leaves the two real ones.
#
#   THE LINK, device.py:377 + :411 and hcq2.py:488-490. Twenty-six rows, and
#   every one of them was compared against CPython on the SAME input: the
#   oracle drives upstream's OWN `bufferize_buf` with a real `Ops.ALLOC` UOp
#   and OBSERVES the level from the sentinel Buffer that came back. The
#   comparison is `.agents/slop/linkbuf/compare.sh`, and it reads
#   `shared=26 agree=26 differ=0`.
#
#   tn_plain / tn_colon / tn_lower  `to_name` (helpers.py:21), the fold that
#                   makes the device-scoped registry key: the parts joined with
#                   `_`, the colons folded to `_`, and the WHOLE string
#                   lower-cased. `P.to_name("AMD", "Scratch")` is `amd_scratch`,
#                   so a registry key that is not lower-case is not a key.
#   lk_lvl_*      the LEVEL, which is upstream's own four-way: 0 the alloc has
#                   NO name and gets a FRESH buffer, 1 the registry under the
#                   PLAIN name, 2 the registry under the DEVICE-SCOPED name, 3
#                   the device's own `link_buffer`, 4 nothing and the buffer is
#                   allocated. The PLAIN name is asked FIRST, so `lk_lvl_both=1`
#                   is the row that says the two keys are not interchangeable.
#   lk_kind_*     upstream's `isinstance(owned, Buffer)`: 0 the registry entry
#                   IS a Buffer, 1 it is a CALLABLE that upstream CALLS with the
#                   alloc (`owned(b)`). `lk_kind_call=1` is the only row that
#                   sees the dispatch, and it is the row a port that ignored
#                   `isinstance` would get wrong.
#   lk_buf_*      WHICH buffer won, as the fixture's slot. The fixture's slots
#                   are the ORACLE's sentinel ids, so the number is comparable:
#                   1 the plain entry, 2 the device-scoped entry, 3 the plain
#                   CALLABLE, 4 the device-scoped callable, 5 and 6 the two
#                   registrations of one name, 7 the device's own buffer.
#   lk_lvl_dup=1 / lk_buf_dup=6    the DUPLICATE. Upstream's `dict.update`
#                   OVERWRITES, so the LAST registration of a name wins. The
#                   row is 6, not 5, and that is the whole point of it.
#   lk_lvl_unnamed=0  an alloc with NO name is NOT a miss: upstream returns
#                   `UOp.new_buffer(...)`, a FRESH buffer that was not linked,
#                   and the registry is never consulted. 0 is that; 4 would be
#                   a port that read the empty name as a key.
#   lk_lvl_hook=3 / lk_hook_bytes=16  the device's OWN answer, asked only
#                   after BOTH registry keys missed. The byte count is the
#                   hook's buffer, and upstream's `ops_null.py:77` sizes it
#                   FROM THE ALLOC.
#   lk_lvl_wrongdev=4  the device-scoped key is a FOLD OF THE DEVICE, so an
#                   entry registered for PYTHON is invisible to an alloc on
#                   METAL:0. This is the row that says the registry is ONE
#                   global dict keyed by a device-scoped name, and not a dict
#                   per device.
#   lk_plain_bytes=64  a linked buffer's size is the REGISTRY'S size, not the
#                   alloc's: upstream never resizes one to fit.
#
#   THE PLANT -- the four ways this could be wrong, and the MUTATION that is
#   the plant for each. All eight mutations are MEASURED, by
#   `.agents/slop/linkbuf/mutate.py`, which edits the file, compiles the
#   mutant in a SCRATCH directory (so the substrate digest does not move) and
#   diffs the rows.
#
#   A BUFFER ADDED TWICE  `link_add` PREPENDS instead of appending, so the
#                   scan finds the OLDER of two registrations. `lk_buf_dup` 6
#                   -> 5. Upstream's `dict.update` overwrites, so the newer
#                   one wins, and a first-wins scan is a different thing.
#   A BUFFER ADDED TO THE WRONG LIST  the two hits are SWAPPED at `link_two`,
#                   so the plain key's hit is read as the device-scoped one.
#                   Six rows move, and `lk_lvl_wrongdev` is the one that says
#                   the wrong list makes one device's entry visible to another.
#   a list mutated in place when the caller expected a COPY  the port
#                   CANNOT EXPRESS THIS ONE, and it says so: upstream's
#                   `Compiled.link_bufs |= {...}` mutates a CLASS attribute in
#                   place, and a Bend list is a VALUE, so `link_add` returns a
#                   NEW list and there is no in-place mutation to port. What
#                   survives the encoding is that the registry is ONE value
#                   handed to the resolution, and the two mutations that break
#                   it are the two keys SWAPPED (six rows) and the
#                   device-scoped key forgetting the device (six rows). The
#                   difference is invisible to every row here because upstream
#                   only ever mutates the registry at import time, before any
#                   resolution.
#   A NULL BUFFER  two plants: an unnamed alloc treated as a MISS
#                   (`lk_lvl_unnamed` 0 -> 4) and the base class's `None`
#                   answer treated as a buffer (`lk_lvl_none` 4 -> 3, and
#                   `lk_lvl_wrongdev` with it).
# ===========================================================================
# MUTATIONS, all re-run 2026-10-02 against this file. A row only one mutation
# moves is a LOCALISED row; the rest are load-bearing together and this table is
# not one-row-per-bug.
#
# THE THREE `NVME` ROWS ARE **MEASURED 2026-11-10** AND NOT ASSERTED, BY
# `.agents/slop/helpers-device-shrink/nvme-mutate.py` -- WHICH STAGES THE
# MUTANT **OUTSIDE `tinybendygrad/`** SO A MUTATION NEVER MOVES THE SUBSTRATE
# DIGEST's POPULATION, AND WHICH READS THE ROWS OUT OF A LIVE RUN. AND THE
# MEASUREMENT CORRECTED THE TABLE ONCE: THE CLAIM WAS THAT `stems` LOSING THE
# `NVME` ROW MOVES `stem_len` **AND** `dcls_nvme` **AND** `dcls_nvme_lower`,
# AND IT MOVES **`stem_len` ALONE** -- BECAUSE `dcls` READS `registry()` AND
# NOT `stems()`, SO THE TWO TABLES ARE **SEPARATE CLAIMS** AND A ROW THAT
# COVERS ONE DOES NOT COVER THE OTHER. A TABLE ROW NOBODY MEASURED IS A LABEL.
#
# | mutation | rows moved | how many |
# | --- | --- | --- |
# | `strip0` uses `String.drop` (a PREFIX) not `String.take` (a SUFFIX) | `canon_cpu0`, `canon_cpu00`, `canon_x00`, `canon_dev`, `multi`, `open_one` | 6 |
# | `canon.go` drops the tail's first colon | `canon_a`, `canon_cpu00`, `canon_nv00`, `canon_wg2`, `canon_x00`, `multi`, `open_two` | 7 |
# | `strip0` never strips (any string ends in something) | `canon_a`, `canon_nv00`, `canon_wg2`, `multi`, `open_one` | 5 |
# | `rest_of` drops the tail's second colon | `canon_cpu00`, `canon_x00` | 2 |
# | `avail` is LAST-wins | `first_amd`, `first_wg` | 2 |
# | `dcls` matches the head case-sensitively | `dcls_wg`, `dcls_null`, `dcls_bend` | 3 |
# | `registry` loses the NULL row | `reg_len`, `dcls_null` | 2 |
# | `all_devices` renames WEBGPU | `first_wg` | 1 |
# | `canon_device.multi` appends (reverses) | `multi` | 1 |
# | `tag_of` lower-cases the allow-list | `allow_disk` | 1 |
# | `device_usage` does NOT canonicalize | `allow_lower`, `allow_disk`, `allow_npy`, `allow_mixed` | 4 |
# | `tag_of` never matches NPY | `allow_npy` | 1 |
# | `tag_of` never matches DISK | `allow_disk` | 1 |
# | `tag_of` never matches PYTHON | `allow_py`, `allow_lower`, `allow_mixed` | 3 |
# | `bview` assigns `offset` instead of `self.offset + offset` | `view_off` | 1 |
# | `bview` stores `base=self` instead of the ROOT | `view_base` | 1 |
# | `go_slot` rounds the ADVANCE as well as the slot | `sig` | 1 |
# | `round_up` floors instead of rounding up | `sig` | 1 |
# | `alloc_take` is FIFO not LIFO | `lru_take` | 1 |
# | `iface_ok` drops the MOCK target exemption | `ifc_keep` | 1 |
# | `rname` drops the `or devname` fallback | `rn_metal` | 1 |
# | `host_name` ignores the `remote:` prefix | `host_plain` | 1 |
# | `is_disk_device` does not upper-case the head | `disk_two` | 1 |
# | `is_disk_device` drops the `"NVME"` arm of `("DISK", "NVME")` | `disk_nvme`, `disk_nvme_lower`, `disk_nvme_mixed` | 3 |
# | `registry` loses the `nvme` row | `reg_len`, `dcls_nvme`, `dcls_nvme_lower` | 3 |
# | `stems` loses the `NVME` row | `stem_len` | 1 |
# | `dev_id` accepts a non-digit index | `did_0`, `did_1`, `did_bad`, `did_deep` | 4 |
# | `needs_compile`'s `or` becomes `and` | `nc_nocache`, `nc_miss` | 2 |
# | `renum_end` is `2i` not `2i+1` | `renum3e` | 1 |
# | `count` drops the `hasattr(iface)` branch | `count_no` | 1 |
# | `bvalid_base` drops the device-equality conjunct | `base_dev` | 1 |
# | `mem_used` sums every device, not the named one | `mem_amd` | 1 |
# | `recycled` drops the `nolru` conjunct | `lru_ptr` | 1 |
# | `recycled` drops the `ext_ptr` conjunct | `lru_nolru` | 1 |
#
# THE LINK'S OWN MUTATIONS, measured 2026-10-22 by
# `.agents/slop/linkbuf/mutate.py`. Each one is a textual edit of THIS file,
# compiled and RUN in a scratch directory -- so the substrate digest does not
# move while a mutant is measured -- and the rows are diffed against the
# baseline. The harness is the tree's rule: "IF YOU MUST TEST A SYSTEM IN
# isolation, first write all the ways it could fail, then write the code."
#
# | mutation | rows moved | how many |
# | --- | --- | --- |
# | `link_add` PREPENDS (a buffer added twice: the OLDER wins) | `lk_buf_dup` | 1 |
# | the two hits are SWAPPED (a buffer added to the wrong list) | `lk_buf_both`, `lk_lvl_call`, `lk_lvl_dev`, `lk_lvl_devcall`, `lk_lvl_dup`, `lk_lvl_plain` | 6 |
# | the two registry keys are SWAPPED (a copy instead of a shared list) | `lk_buf_both`, `lk_lvl_call`, `lk_lvl_dev`, `lk_lvl_devcall`, `lk_lvl_dup`, `lk_lvl_plain` | 6 |
# | an unnamed alloc is a MISS (a null buffer) | `lk_lvl_unnamed` | 1 |
# | the base class's `None` answer becomes a buffer (a null buffer) | `lk_lvl_none`, `lk_lvl_wrongdev` | 2 |
# | `to_name` does not lower-case | `lk_buf_dev`, `lk_buf_devcall`, `lk_kind_dev`, `lk_kind_devcall`, `lk_lvl_dev`, `lk_lvl_devcall`, `tn_colon`, `tn_lower`, `tn_plain` | 9 |
# | `to_name` does not fold the colon | `tn_colon` | 1 |
# | the device-scoped key forgets the device | `lk_buf_dev`, `lk_buf_devcall`, `lk_kind_dev`, `lk_kind_devcall`, `lk_lvl_dev`, `lk_lvl_devcall` | 6 |
#
# every one of the eight moves at least one row, and that is the property the
# table is for: a mutation that moves nothing is a DEAD row, and a dead row is
# a label. The FIRST-WINS one (`link_add` PREPENDS) moves exactly ONE row, and
# that one row -- `lk_buf_dup` -- is the whole claim that upstream's
# `dict.update` overwrites and does not append.
#
# five rows in this table are the interesting ones, and three of them were not
# interesting until the gate had a fixture for them.
#
# the `pmb_*` block was the first-wins fixture, and it is gone with the table it
# exercised. What it taught this gate is still here: a mutation that moves
# NOTHING is a statement about the GATE and not about the code, and the only
# honest response to one is to go and build the fixture or fix the mutation it
# is asking for. The LINK's own table below is the same discipline -- EIGHT
# mutations, and every one of them moves at least one row.
#
# the `tag_of` row was a zero for three revisions, and that is the most useful
# THING THIS GATE TAUGHT ME. `tag_of` lower-casing the allow-list moved NOTHING,
# twice, for two DIFFERENT reasons, and both had to be found before the row moved
# at all. (1) Every fixture passed a lower-case spelling, so the conjunct was
# vacuously true either way -- the fix was a second FIXTURE, `allow_lower`, the
# spelling that must NOT be allowed. (2) With that fixture in place the mutation
# STILL moved nothing, because the mutation I was writing touched the `DISK`
# branch and the two rows exercise the `PYTHON` one: a case fold on a
# never-exercised conjunct is invisible however many fixtures you add for the
# others. A mutation that moves nothing is information about the GATE and not
# about the code, and the only honest response to it -- twice -- is to go and
# build the fixture or fix the mutation it is asking for.
#
# RE-MEASURED 2026-10-03, and the lesson finished paying: with `allow_disk` and
# `allow_npy` added (the other two allow-list branches) that mutation now moves
# `allow_disk`, M4 and M5 each move their own branch, and M1 -- deleting the one
# line that is the `allow_lower` fix -- moves four rows. Table above, produced by
# `.agents/slop/dev-mutate.py`, which diffs whole `name=value` lines, mutates a
# scratch COPY, and ABORTS on a zero-row run rather than reporting a false zero.
#
# THE `strip0` ROW IS THE BIGGEST, and it is the one that would have shipped.
# `re.sub(r":0$", "", s)` strips a SUFFIX and `String.drop` takes a PREFIX, so
# the obvious transcription deletes the first two characters of every canonical
# device name: "CPU" becomes "", "CPU:0" becomes "P:0". Six rows move, including
# `open_one` -- and the reason `open_one` moves is that `reg_open` is keyed on
# the canonical NAME, so a canonicalize that mangles the name mangles the memo.
# That coupling is the reason this file keys the opened set on the string rather
# than on the registry tag, and it was worth the extra field.
#
# `first_amd` is the first-wins discriminator this gate still has, and it is an
# ORDER (`ALL_DEVICES`). The OTHER kind -- a RULE (`Compiled.pm_bufferize`) --
# is gone from upstream AND from this port, so the gate holds one kind of
# discriminator and says so rather than implying a second.
# ===========================================================================
