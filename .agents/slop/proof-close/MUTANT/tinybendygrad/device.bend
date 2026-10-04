# device.bend -- tinygrad/device.py. THE DEVICE LAYER: the registry that turns
# a device STRING into a device, the Buffer that is the data handle, and
# `Compiled`, the composition of an allocator, a renderer, a compiler and a
# program. tinygrad's final output depends on which of these is underneath, so
# this is the file the WebGPU phase hangs off.
#
# ---------------------------------------------------------------------------
# WHAT IS PORTED, AND WHY IT IS THE SAME AMOUNT OF CODE.
#
# The pure half of this file is DECISION code, and decision code ports: which
# device string resolves to which class, which of two available devices is the
# default, how many bytes a buffer is, where a view's offset lands, whether a
# freed storage is recycled or dropped, what a renderer's environment variable
# is called. All of that is arithmetic on strings, integers and small records,
# and all of it is here.
#
# The impure half is the SEAM, and the seam is one line long: a Buffer's bytes
# live in device memory and every way of reaching them is a C call --
# `mmap`, `cudaMalloc`, `MTLDevice.newBuffer`, `navigator.gpu`, `pickle`.
# tinygrad reaches them with ctypes and `subprocess`; this port reaches them
# with `import "./<x>.c"`. So `allocate` / `_copyin` / `_copyout` /
# `as_memoryview` / `numpy` are WALLS, marked `# TODO(p3) device.py:<line>`,
# and everything around them -- the asserts, the offsets, the counters, the
# cache keys -- is here so the logic is already right when the C lands.
#
# BUFFERS ARE (NBYTES, CONTENT-ADDRESS) PARAMETERS. Python's `Buffer` is an
# object whose IDENTITY `_base_storage is base._storage` depends on
# (device.py:167), so a Bend `Buffer` is a slot in a `Bar` arena rather than a
# value: `Bn` carries the dtype, the size, the byte offset, the base slot and a
# content address standing in for `_storage`. That is everything the class's
# decisions read, and it is why `view` can be checked at all.
#
# ---------------------------------------------------------------------------
# ONE FIRST-WINS CLAIM, and it is an ORDER.
#
# 1. `_canonicalize` (device.py:26) collapses `cpu:0` and `CPU` onto ONE
#    registry slot, so `Device['cpu:0'] is Device['CPU']` and opening both
#    opens one device. `open_one` is that count, and nothing else notices a
#    canonicalize that forgets the `:0` strip -- it would print `open_two`.
#
# A THIRD, which is an ORDER rather than a rule: `ALL_DEVICES` (device.py:20) is
# nine names and `get_available_devices` (device.py:46) yields in that order
# and `_select_device` (device.py:58) takes `next(...)`. AMD is second and CPU
# is seventh, so with both openable the default is AMD. `first_amd` is that row
# and a last-wins fold prints CPU.
#
# ---------------------------------------------------------------------------
# `pm_bufferize` LOST ITS FIRST-WINS DISCRIMINATOR, and this records why.
#
# This header used to claim `device.py:403` has THREE rules of which "rules 2
# and 3 carry the IDENTICAL pattern `UPat(Ops.PARAM, name="b")`, so rule 3 --
# the `cfunc_buf` one -- CANNOT EVER RUN, for any input", and `pmb_cfunc` was
# the row that said so. That was TRUE at the pin and it is now GONE, for two
# separate reasons, and the second is the one that matters:
#
#   1. Upstream `bdddaad21` ("ccall by symbol", #18521) DELETED rule 3 outright.
#      `ccall` stopped needing a `Buffer` to hold a C function pointer -- it is
#      now `UOp.custom_function(fn.__name__, dtype=ret).call(...)` -- so nothing
#      in `device.py` is ever a `PARAM` tagged `"cfunc"` again. `Pn.cfunc`,
#      `pmb_cond2`, `rule2`, `rule2.go` and answer `3` had no upstream
#      counterpart left, and a row that can never move is a DEAD CLAIM rather
#      than drift, so they were DELETED here. `--check-only` was read after each.
#   2. Even before the deletion, answer `3` was UNREACHABLE IN THE PORT TOO, and
#      that is measured rather than argued: `pmb_cfunc` printed **2**, not 3.
#      Rule 2 claims the node first and `pmb.keep` is first-wins, so `Step.cand`
#      for rule 3 was computed and then DISCARDED. Nothing in the whole import
#      closure ever printed 3 -- `ops_metal.bend:2840`, the only other caller of
#      `D.param`, hard-coded the fourth argument to `False{}`.
#
# So the two rows that went are NOT a loss of coverage that could be restored:
# `pmb_cfunc` is bit-identical to `pmb_named` once the `cfunc` field is gone, and
# `pmb_cfunc_noname` is bit-identical to `pmb_none`, so keeping either would have
# been a CHANGE-DETECTOR row -- a row that passes however wrong the port is.
# `pmb_nonparam` survives, and it still has a job: it is the only fixture that
# can see rule 1's guard lose `is_param`.
#
# WHAT IS LOST AND CANNOT COME BACK: with two rules whose patterns are
# `tag="timeline"` and `tag="program", name="b"`, and a PARAM carrying ONE tag,
# NO node can be claimed twice -- so `pmb.keep`'s "accumulator already taken"
# arm is unreachable from any honest fixture, and a mutation of it now moves
# nothing. The mutation table reports that as a BLIND SPOT rather than closing it
# with a fixture that cannot exist.
#
# SEPARATELY, AND STILL OPEN: upstream also ADDED `tag="program"` to rule 1's
# pattern, which this port does not model -- `pmb_cond1` is `is_param &&
# named_b` and carries no tag. That is drift, not a dead claim, and it is named
# in the wall list below rather than folded in here.
#
# ---------------------------------------------------------------------------
# TWO MEASURED BEND CONSTRAINTS THIS FILE IS BUILT AROUND. Both cost a compile
# cycle each and neither is in bend2-constraints.md yet.
#
# A. **A LIST OF `Bool` IS NOT A USABLE TYPE.** `List<&2, Bool>` is accepted as
#    a parameter annotation and then refused by every reader of one: the cons
#    pattern `case k <> t:` reports "a match on a parameter or field (this name
#    is a def or a consumed binder)", and `List.get` / `List.length` report
#    "expected a defined name" because `Bool` does not resolve in a `Kind`
#    position. A `Bool` FIELD of a `Data` record is fine. So availability,
#    deprecation and mock-ness are a U32 BITMASK read with `U32.shrn`/
#    `U32.and` against the row's own index -- which also removes the two
#    parallel lists, and with them a zip fold.
#
# B. **A `match` on a list of a LOCALLY DECLARED one-field `Data` record is
#    refused, and the refusal is NOT reproducible from the file.** The same
#    three lines pass in a 30-line file and fail in this one, and renaming the
#    parameter, the record or the def does not always help -- a working
#    `zz1(fs: List<&2, Fl>)` sat directly above a failing
#    `zz2(oks: List<&2, Fl>)` in one file, and `oks` alone is not a keyword
#    (`KEYWORDS` in `bend2/bend.ts:1503` is def/type/law/match/case/do/return/
#    for/exs/where/is/import/Type/Data/Kind/Quant). The error message names a
#    projection, which is a lie. The fix used here is to never destructure a
#    list of a locally-declared record: the fold tables here are `DEnt` and
#    `AEnt`, both multi-field and both carrying a `U32` index, which is the
#    shape that works. REPORTED, not understood.

import Base
import ./LAWS/spec.bend as S

# ===========================================================================
# THE TWO FOLD TABLES. Both rows carry their OWN index, which is what lets a
# first-wins scan answer "which row" without an accumulator -- and an
# accumulator would have to be read twice in one expression to be passed on.
# ===========================================================================
type AEnt is Data:
  AEnt{ix: U32, nm: String}

def AEnt.ix(x: AEnt) -> U32:
  match x:
    case AEnt{ix, nm}: ix

def AEnt.nm(x: AEnt) -> String:
  match x:
    case AEnt{ix, nm}: nm

# A bitmask travelling as a `Data` record, because `U32` is affine and the fold
# below reads it once per row AND passes it on.
type Mk is Data:
  Mk{m: U32}

def Mk.m(+x: Mk) -> U32:
  match x:
    case Mk{m}: m

# `contextlib.suppress(Exception)` is the seam and a bit is the whole of it.
def bit(+m: Mk, ix: U32) -> Bool:
  U32.is_eq(U32.and(U32.shrn(Mk.m(m), U32.to_nat(U32.sub(ix, 1))), 1), 1)

# ===========================================================================
# THE STRING PRIMITIVES. Three jobs, and the middle one is the one that is easy
# to get wrong: `String.split` throws the separators away, so the tail has to
# be re-joined with them, and BOTH of its colons.
# ===========================================================================
def part.at(m: Maybe<&2, String>) -> String:
  Maybe.default(&2, String, m, "")

def part(ix: String, k: Nat) -> String:
  part.at(List.get(&2, String, String.split(ix, ':'), k))

# `ix.split(":", 1)[0]` -- `get_class`'s `x` (device.py:36), `is_disk_device`'s
# `d.split(":", 1)[0].upper()` (device.py:70) and `_renderer_name`'s
# `self.device.split(':')[0].upper()` (device.py:483).
def head(ix: String) -> String:
  part(ix, 0n)

# `device[len(d):]` -- the WHOLE rest of the string from the first colon on.
def rest_of(t: List<&2, String>) -> String:
  match t:
    case Nil{}: ""
    case h <> Nil{}: String.concat([":", h])
    case h <> u: String.concat([":", h, ":", String.join(u, ":")])

def canon.go(+s: String, xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: String.to_upper(s)
    case h <> t: String.concat([String.to_upper(h), rest_of(t)])

# `re.sub(r":0$", "", r)` strips a SUFFIX and `String.drop` takes a PREFIX, so
# the survivor is `String.take(r, len(r) - 2)`. `String.drop` here would delete
# the first two characters instead, turning "CPU" into "" and making every gate
# row that prints a device name into a lie.
def strip0.go(+r: String, k: Nat, cut: Bool) -> String:
  match cut:
    case True{}: String.take(r, k)
    case False{}: r

def strip0(+r: String) -> String:
  strip0.go(r, Nat.sub(String.length(r), 2n), String.ends_with(r, ":0"))

# `re.sub(r":0$", "", (d:=device.split(":", 1)[0].upper()) + device[len(d):])`
# -- device.py:26.
def canon(+s: String) -> String:
  strip0(canon.go(s, String.split(s, ':')))

# device.py:65-67, `canonicalize_device`. A tuple or list canonicalises
# elementwise and COLLAPSES to a bare string when the answer is one device,
# which is how a multi-device tensor becomes a single-device one.
def canon_device.device(ix: String) -> String:
  canon(ix)

# `tuple(Device.canonicalize(d) for d in device)`, hand-folded: `List.map`'s
# third argument is a FUNCTION and a named def cannot be passed as one without
# a `~` binder, which is a closure and closures are not worth one line here.
# A REBUILD, so it CONS: `List.append([h], t)` is `[h] ++ t`. Appending `[canon(h)]`
# to the recursion instead gives `xs ++ ys` and REVERSES the tuple, which is
# `multi` -- and Python's is `tuple(... for d in device)`, in order.
def canon_device.multi(ixs: List<&2, String>) -> List<&2, String>:
  match ixs:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, String, [canon(h)], canon_device.multi(t))

# device.py:70, `is_disk_device`: `any(d.split(":", 1)[0].upper() == "DISK")`
# over a tuple, so the empty tuple is False.
def is_disk(ixs: List<&2, String>) -> Bool:
  match ixs:
    case Nil{}: False{}
    case +k <> t: Bool.pick(Bool, String.eq(String.to_upper(head(k)), "DISK"), True{}, is_disk(t))

# ===========================================================================
# `ALL_DEVICES` -- device.py:20. Nine names, and THE ORDER IS THE POLICY.
# `_select_device` takes `next(get_available_devices())` and that generator
# walks this list, so index 2 beating index 7 is the default-device policy.
# ===========================================================================
def all_devices() -> List<&2, AEnt>:
  [AEnt{1, "METAL"}, AEnt{2, "AMD"}, AEnt{3, "NV"}, AEnt{4, "CUDA"},
   AEnt{5, "QCOM"}, AEnt{6, "CL"}, AEnt{7, "CPU"}, AEnt{8, "DSP"},
   AEnt{9, "WEBGPU"}]

# device.py:46-48 + :58, the scan and the `next`. FIRST-WINS over the table,
# and the empty string is the `RuntimeError("no usable devices")` Python raises
# when the generator is exhausted.
def avail(+m: Mk, es: List<&2, AEnt>) -> String:
  match es:
    case Nil{}: ""
    case +k <> t: Bool.pick(String, bit(m, AEnt.ix(k)), AEnt.nm(k), avail(m, t))

def select_device(flags: U32) -> String:
  avail(Mk{flags}, all_devices())

# ===========================================================================
# THE CLASS REGISTRY. `ALL_DEVICES` above is the ENUMERATION; this is the
# dispatch, and the two are different lists on purpose. `get_class`
# (device.py:34-37) is
#   `importlib.import_module(f'{base}.runtime.ops_{x}')` then
#   `[cls for cname, cls in getmembers(m) if cname.lower() == x + "device"][0]`
# with `x = ix.split(":")[0].lower()`, so the claim is a PREFIX claim: `webgpu:1`
# and `WEBGPU` are ONE row, and the sixteen rows below are the sixteen
# `ops_*.py` stems the same walk finds.
# TODO(p3) device.py:37  get_class -- `importlib` + `inspect.getmembers`. WALL:
#   a dynamic import and a reflection scan. The table below IS the resolved
#   lookup, first-wins on the head; a new `ops_*.py` needs one row here.
# ===========================================================================
type DEnt is Data:
  DEnt{ix: U32, head: String, cls: String}

def registry() -> List<&2, DEnt>:
  [DEnt{1, "amd", "AMDDevice"}, DEnt{2, "bend", "BendDevice"},
   DEnt{3, "cl", "CLDevice"}, DEnt{4, "cpu", "CPUDevice"},
   DEnt{5, "cuda", "CUDADevice"}, DEnt{6, "disk", "DiskDevice"},
   DEnt{7, "dsp", "DSPDevice"}, DEnt{8, "hip", "HIPDevice"},
   DEnt{9, "metal", "MetalDevice"}, DEnt{10, "npy", "NpyDevice"},
   DEnt{11, "null", "NullDevice"}, DEnt{12, "nv", "NVDevice"},
   DEnt{13, "python", "PythonDevice"}, DEnt{14, "qcom", "QCOMDevice"},
   DEnt{15, "rdma", "RDMADevice"}, DEnt{16, "webgpu", "WebGPUDevice"}]

def DEnt.ix(x: DEnt) -> U32:
  match x:
    case DEnt{ix, hd, cls}: ix

def DEnt.head(x: DEnt) -> String:
  match x:
    case DEnt{ix, hd, cls}: hd

# The first-wins scan, and 0 is Python's `ImportError` from an empty list.
def claim_row(es: List<&2, DEnt>, +h: String) -> U32:
  match es:
    case Nil{}: 0
    case +k <> t: Bool.pick(U32, String.eq(DEnt.head(k), h), DEnt.ix(k), claim_row(t, h))

# `x = ix.split(":")[0].lower()` -- the LOWER-CASE head is the claim, so
# `WEBGPU:2` and `webgpu:2` are one row and `Device['CPU']` finds `CPUDevice`.
def dcls(ix: String) -> U32:
  claim_row(registry(), String.to_lower(head(ix)))

# ===========================================================================
# THE OPENED SET. `_opened_devices` (device.py:24) is a `set[str]` that grows by
# one per `__get_canonicalized_item`, and the growth IS the point: three
# spellings of one device are ONE slot, because `canonicalize` runs first
# (device.py:30).
# TODO(p3) device.py:39  __get_canonicalized_item -- `functools.cache` and
#   `self.get_class(ix)(ix)`. WALL: constructing a device opens hardware. The
#   MEMOISATION is PORTED -- `reg_open` is the cache, keyed on the canonical
#   name, and it grows only on a miss.
# ===========================================================================
type Reg is Data:
  Reg{open: List<&2, String>}

def reg_empty() -> Reg:
  Reg{Nil{}}

# Python's `_opened_devices` is a `set[str]`, so this holds the CANONICAL NAME
# and not the registry tag -- which is what makes `open_one` the claim it is.
# `reg_open` takes the name already canonicalized, because device.py:30
# canonicalizes before it memoises and that ordering is the whole row.
def reg_has(es: List<&2, String>, +t: String) -> Bool:
  match es:
    case Nil{}: False{}
    case k <> r: Bool.pick(Bool, String.eq(k, t), True{}, reg_has(r, t))

def reg_open.go(+es: List<&2, String>, +t: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, reg_has(es, t), es, List.append(&2, String, es, [t]))

# `r.open` is a NAME lookup in Bend 2.0.34, not a projection, so every field
# read off a `Data` record parameter is a def. That is why the accessors below
# exist and why the file is not accessor soup only where a `match` is needed.
def Reg.open(+r: Reg) -> List<&2, String>:
  match r:
    case Reg{open}: open

def reg_open(r: Reg, t: String) -> Reg:
  Reg{reg_open.go(Reg.open(r), t)}

def reg_len(+r: Reg) -> U32:
  U32.from_nat(List.length(&2, String, Reg.open(r)))

# device.py:31, `assert ALLOW_DEVICE_USAGE or ix.split(":")[0] in
# ["DISK", "NPY", "PYTHON"]`. `ALLOW_DEVICE_USAGE` is an env read so it is a
# parameter; the membership is the decision.
#
# THE THREE COMMENTS HERE USED TO SAY "`__getitem__` asserts BEFORE it
# canonicalizes ... so the head is compared exactly as it arrived", AND THEY
# CITED device.py:30 as the canonicalize and :31 as the assert -- the order they
# then denied. MEASURED, `.venv/bin/python`, CALLING `Device[...]` under
# `Context(ALLOW_DEVICE_USAGE=0)`:
#     Device['PYTHON:1'] -> SUCCEEDS      Device['python:1'] -> SUCCEEDS
#     Device['METAL']    -> AssertionError
# `_canonicalize` upper-cases the stem (device.py:26), so by the time line 31
# reads `ix` the name is ALREADY `PYTHON:1`. Line 30 REBINDS `ix`; the assert
# reads the rebound value. Lower-casing here is a real port bug and `allow_py`
# is the row that caught it.
def tag_of(+h: String) -> U32:
  Bool.pick(U32, String.eq(h, "DISK"), 6,
    Bool.pick(U32, String.eq(h, "NPY"), 10, Bool.pick(U32, String.eq(h, "PYTHON"), 13, 0)))

# The assert STATEMENT, on an already-canonical name. It cannot see the rebind
# above because it is handed whatever the caller passes -- `allowed` alone is
# what let `allow_lower` read 0 for a device CPython opens.
def allowed(allow: Bool, ix: String) -> Bool:
  Bool.or(allow, U32.is_ne(tag_of(head(ix)), 0))

# device.py:29-31 as a UNIT, which is what a caller of `allowed` has. This is the
# fix for `allow_lower`, and it is one line because `canon` already exists: the
# assert's subject is `canon(ix)`, not `ix`. The PAIR `allow_py`/`allow_lower` is
# the row -- they answer the SAME number now, because both spellings reach line 31
# as `PYTHON`, and either one alone is a row that cannot see the case fold.
# `allow_disk`/`allow_npy` exist because the mutation table's `tag_of` row is a
# documented blind spot: "a case fold on a never-exercised conjunct is invisible
# however many fixtures you add for the others", and only the PYTHON branch was
# ever exercised. All four measured by CALLING CPython.
def device_usage(allow: Bool, ix: String) -> Bool:
  allowed(allow, canon(ix))

# device.py:418, `f"CPU:{self.peer_group[7:]}" if self.peer_group.startswith(
# "remote:") else HCQ_RUNTIME_DEV.value`. A PREFIX claim: a peer group is either
# a remote node's name or a local device name and the seven characters of
# "remote:" are the whole discriminator. `drop 7` is `[7:]`.
def host_name.go(+peer: String, hcq: String, remote: Bool) -> String:
  match remote:
    case True{}: String.concat(["CPU:", String.drop(peer, 7n)])
    case False{}: hcq

def host_name(+peer: String, hcq: String) -> String:
  host_name.go(peer, hcq, String.starts_with(peer, "remote:"))

# The environment variable that selects a renderer, device.py:482-483:
#   `r.__name__.upper().removesuffix("RENDERER").removeprefix(devname) or devname`
# The `or devname` is the load-bearing half: a renderer whose name IS the device
# name -- `MetalRenderer` on `METAL` -- reduces to the EMPTY string, and without
# the fallback its selector would be `""`. `rm` is that empty-string-OR.
def rm(+r: String, +d: String) -> String:
  Bool.pick(String, String.is_empty(r), d, r)

def rm_prefix.go(r: String, d: String, has: Bool) -> String:
  match has:
    case True{}: String.drop(r, String.length(d))
    case False{}: r

def rm_prefix(+r: String, +d: String) -> String:
  rm_prefix.go(r, d, String.starts_with(r, d))

def rm_suffix.go(+r: String, s: String, has: Bool) -> String:
  match has:
    case True{}: String.take(r, Nat.sub(String.length(r), String.length(s)))
    case False{}: r

def rm_suffix(+r: String, +s: String) -> String:
  rm_suffix.go(r, s, String.ends_with(r, s))

# `devname := self.device.split(':')[0].upper()` is the same `head` + `to_upper`
# `canon` starts with, taken BEFORE the strips because the fallback is the
# DEVICE's name and not the renderer's.
def rname(+rend: String, +dev: String) -> String:
  rm(rm_prefix(rm_suffix(String.to_upper(rend), "RENDERER"), String.to_upper(head(dev))),
     String.to_upper(head(dev)))

# device.py:498, `filtered = [i for i in filtered if t.interface.startswith("MOCK")
# or not i.__name__[:-5].startswith("MOCK")]` -- "never fallback to mock ifaces".
# A mock interface survives a selection ONLY when the target itself is a mock,
# so asking for the real interface on a box that only has the mock one fails
# loudly instead of silently benchmarking nothing. `[i for i in ...]` is a
# filter and the gate wants its LENGTH, which is what `select_by_name` then
# hands to `select_first_inited` -- zero survivors is the `RuntimeError`.
def iface_ok(is_mock: Bool, want_mock: Bool) -> Bool:
  Bool.or(want_mock, Bool.not(is_mock))

def ifaces() -> List<&2, AEnt>:
  [AEnt{1, "HostIface"}, AEnt{2, "MockIface"}, AEnt{3, "RealIface"},
   AEnt{4, "MockTwoIface"}]

def go_keep(w: Bool, k: Bool) -> U32:
  Bool.pick(U32, Bool.or(w, Bool.not(k)), 1, 0)

def iface_filter(+m: Mk, es: List<&2, AEnt>, +want_mock: Bool, acc: U32) -> U32:
  match es:
    case Nil{}: acc
    case k <> t: iface_filter(m, t, want_mock,
                              U32.add(acc, go_keep(want_mock, bit(m, AEnt.ix(k)))))

# device.py:415, `has_copy_queue` is `True` on the base class and the subclasses
# that answer False are the ones with no separate DMA path.
def has_copy_queue() -> Bool:
  True{}

# device.py:459-463, `return self.iface.count if hasattr(self, 'iface') else 1`.
# One device unless the interface says otherwise, and the two cases are
# different KINDS of answer -- a count and a default, not two counts.
def count(has_iface: Bool, n: U32) -> U32:
  Bool.pick(U32, has_iface, n, 1)

# device.py:55, `assert (dev:=next((d for d in self._devices if d not in
# ["DISK","NPY"] and getenv(d) == 1), None)) is None` -- the DEPRECATION assert
# and the only other read of `_devices`. `stems()` is that walk's RESULT.
# TODO(p3) device.py:23  _Device._devices -- `pathlib.Path(...).iterdir()`.
#   WALL: a directory read. The sixteen stems are spelled out, so a new
#   `ops_*.py` needs one row in `registry()` and one here.
def stems() -> List<&2, AEnt>:
  [AEnt{1, "AMD"}, AEnt{2, "BEND"}, AEnt{3, "CL"}, AEnt{4, "CPU"},
   AEnt{5, "CUDA"}, AEnt{6, "DISK"}, AEnt{7, "DSP"}, AEnt{8, "HIP"},
   AEnt{9, "METAL"}, AEnt{10, "NPY"}, AEnt{11, "NULL"}, AEnt{12, "NV"},
   AEnt{13, "PYTHON"}, AEnt{14, "QCOM"}, AEnt{15, "RDMA"}, AEnt{16, "WEBGPU"}]

def legacy_off(+h: String) -> Bool:
  Bool.or(String.eq(h, "DISK"), String.eq(h, "NPY"))

def go_dep(+m: Mk, h: String, ix: U32) -> U32:
  Bool.pick(U32, Bool.and(bit(m, ix), Bool.not(legacy_off(h))), 1, 0)

# the COUNT of stems that would trip the assert, so the gate can see a COUNT and
# not only a boolean. The mask is `getenv(stem) == 1` PER STEM, and DISK and NPY
# are the two exemptions -- so a mask with AMD set counts exactly one, and a mask
# with all sixteen set counts fourteen.
def deprecated(+m: Mk, es: List<&2, AEnt>, acc: U32) -> U32:
  match es:
    case Nil{}: acc
    case +k <> t: deprecated(m, t, U32.add(acc, go_dep(m, AEnt.nm(k), AEnt.ix(k))))

# ===========================================================================
# THE PROFILE RECORDS, device.py:74-84. Four frozen dataclasses, and the only
# fields any decision in this file reads are `ProfileGraphEntry`'s `st_id` and
# `en_id`, which `collect_prof` RENUMBERS.
# ===========================================================================
type PEnt is Data:
  PEnt{st_id: U32, en_id: U32}

# device.py:508, `replace(e, st_id=2*i, en_id=2*i+1) for i,(_, e) in
# enumerate(es)` -- a batch's timestamps are interleaved into one flat axis,
# start and end, so entry i occupies slots 2i and 2i+1.
def renum(en: U32) -> U32:
  U32.mul(U32.sub(en, 1), 2)

def renum_end(en: U32) -> U32:
  U32.add(renum(en), 1)

# device.py:507, `sigs = [buf.host.view(fmt='Q')[i]/divider for (buf,_), e in es
# for i in (e.st_id, e.en_id)]` -- the signal list is the renumbered slots in
# order, so it is twice the entry count. 16 bytes for a 2-entry batch, which is
# also `timeline_bytes` below, and the two agreeing is the point.
def sig_len(n: U32) -> U32:
  U32.mul(n, 2)

# ===========================================================================
# BUFFERS. `BufferSpec` (device.py:88) is five flags; `external_ptr: int|None`
# is flattened to a Bool because a `Data` record may not hold a `Maybe` field,
# and NOTHING here ever uses the pointer -- only its presence, in
# `Allocator.free` (device.py:280).
# ===========================================================================
type Bspec is Data:
  Bspec{uncached: Bool, cpu_access: Bool, host: Bool, nolru: Bool, ext_ptr: Bool}

def spec() -> Bspec:
  Bspec{False{}, False{}, False{}, False{}, False{}}

# The allocator's two support flags (device.py:262). `HostAllocator.__init__`
# (device.py:306) is the only caller that turns either off and it turns BOTH
# off, which is the whole of what makes a host buffer unmappable.
def supports(disk: Bool, xfer: Bool) -> List<&2, U32>:
  [Bool.to_u32(disk), Bool.to_u32(xfer)]

def host_supports() -> List<&2, U32>:
  supports(False{}, False{})

# `MultiBuffer` (device.py:97-107): `size` and `dtype` are `bufs[0]`'s, and
# `is_allocated` is `all(...)` over the per-device buffers -- False the moment
# ONE device is short, which is the only reason the class exists.
type Multi is Data:
  Multi{devs: List<&2, U32>, nbytes: U32, dt: S.Dt}

def Multi.nbytes(+x: Multi) -> U32:
  match x:
    case Multi{devs, nbytes, dt}: nbytes

def multi_nb(+m: Multi) -> U32:
  Multi.nbytes(m)

# `BufferStorage` (device.py:110): `buf`, `meta`, `host` and the `maps` dict of
# cross-device views. The dict is a WALL -- keyed by a live device object, which
# this port replaced with a tag -- and `buf` is a raw address. What IS modelled
# is the one field a decision reads, `host`, and only its presence, in
# `HostAllocator._map` (device.py:328).
# TODO(p3) device.py:110  BufferStorage.maps -- `dict[Compiled, BufferStorage]`.
#   WALL: needs the device object. `get_storage` (device.py:155) is behind it.
type Bar is Data:
  Bar{ns: List<&2, Bn>}

def bar_empty() -> Bar:
  Bar{Nil{}}

# A Buffer as (nbytes, content-address) plus the four numbers every decision in
# the class reads, and its OWN SLOT. `nbytes` is deliberately not a field: it is
# `size * itemsize`, and storing it would let the two disagree.
#
# `self_ix` is the first field because two of the readers below need the buffer's
# own index as an ANSWER -- `base_of` returns it for a root, and Python's
# `self._base if self._base is not None else self` (device.py:143) is exactly
# that. `U32` is affine, so the index could not be a second parameter beside the
# node; carrying it in the node is the same "hand something back in a record" rule
# the rest of the port uses, and it is why `Bn` is the record and not `Slot`.
type Bn is Data:
  Bn{self_ix: U32, dev: U32, size: U32, dt: S.Dt, off: U32, base: U32,
     has_base: Bool, addr: U32, spec: Bspec}

type BFound is Data:
  BFound{ar: Bar, i: U32}

def BFound.ar(+f: BFound) -> Bar:
  match f:
    case BFound{ar, i}: ar

def BFound.i(+f: BFound) -> U32:
  match f:
    case BFound{ar, i}: i

# `ar.ns` is a NAME lookup in Bend 2.0.34 and not a projection, so the arena's one
# field is a def and every `Bar` reader below goes through it.
def Bar.nodes(+ar: Bar) -> List<&2, Bn>:
  match ar:
    case Bar{ns}: ns

def bar_at.go(ns: List<&2, Bn>, n: Nat) -> Maybe<&1, Bn>:
  match ns n:
    case Nil{} _:
      None{}
    case k <> t 0n:
      Some{k}
    case k <> t 1n+p:
      bar_at.go(t, p)

# the bottom, so every reader is TOTAL -- `ops.bend`'s `Arena.node` discipline,
# and it is why no Buffer decision below threads a `Maybe`.
def bar_bot() -> Bn:
  Bn{0, 0, 0, S.uint8(), 0, 0, False{}, 0, spec()}

def bar_at(+ar: Bar, i: U32) -> Bn:
  Maybe.default(&1, Bn, bar_at.go(Bar.nodes(ar), U32.to_nat(i)), bar_bot())

def bar_next(+ar: Bar) -> U32:
  U32.from_nat(List.length(&2, Bn, Bar.nodes(ar)))

def Bn.self_ix(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: self_ix

def Bn.dev(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: dev

def Bn.size(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: size

def Bn.dt(+x: Bn) -> S.Dt:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: dt

def Bn.off(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: off

def Bn.base(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: base

def Bn.has_base(+x: Bn) -> Bool:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: has_base

def Bn.addr(+x: Bn) -> U32:
  match x:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}: addr

# device.py:153, `self.size * self.dtype.itemsize`. The one line of Buffer
# arithmetic that is not an offset, and the reason a dtype is carried at all.
def nbytes.go(+b: Bn) -> U32:
  U32.mul(Bn.size(b), S.Dt.itemsize(Bn.dt(b)))

def nbytes(+ar: Bar, i: U32) -> U32:
  nbytes.go(bar_at(ar, i))

# device.py:143, `self._base if self._base is not None else self`. Idempotent,
# because `view` stores the ROOT and device.py:131 asserts a base has no base.
def base_of.go(+b: Bn) -> U32:
  match b:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}:
      match has_base:
        case True{}: base
        case False{}: self_ix

def base_of(+ar: Bar, i: U32) -> U32:
  base_of.go(bar_at(ar, i))

# device.py:167, `self._storage is not None and (self._base is None or
# self._base_storage is self.base._storage)`. Address 0 is Python's `None`, and
# the second clause is that the view's storage IS the root's.
def is_allocated.go(+b: Bn, same: Bool) -> U32:
  Bool.to_u32(Bool.and(U32.is_ne(Bn.addr(b), 0),
    Bool.or(Bool.not(Bn.has_base(b)), same)))

def is_allocated.bar(+ar: Bar, +b: Bn) -> U32:
  is_allocated.go(b, U32.is_eq(Bn.addr(b), Bn.addr(bar_at(ar, base_of.go(b)))))

def is_allocated(+ar: Bar, i: U32) -> U32:
  is_allocated.bar(ar, bar_at(ar, i))

# device.py:122, `assert offset == 0` for a base-less buffer -- the check that
# stops a view of a view from claiming to be a root.
def bvalid_root(off: U32) -> Bool:
  U32.is_zero(off)

# device.py:131-132, the base-case asserts. The device equality is the one a
# cross-device view would trip, and it is why `view` cannot change a device.
def bvalid_base.s(+sb: Bn, +sn: Bn) -> Bool:
  Bool.and(Bool.not(Bn.has_base(sb)), U32.is_eq(Bn.dev(sn), Bn.dev(sb)))

def bvalid_base(+ar: Bar, b: U32, nb: U32) -> Bool:
  bvalid_base.s(bar_at(ar, b), bar_at(ar, nb))

# `Buffer.__init__` appends, so it returns the pair. THE ARENA RULE, and it is
# why `bnew`, `bview` and `rule1` are `Found` and not a bare index: a def that
# builds a node and returns only its index hands the caller nothing and the node
# is eliminated along with the call. `bnew.stamp` also STAMPS the slot, which is
# why a caller builds its `Bn` with a placeholder `self_ix` of 0.
# The arena is destructured OUTSIDE the `match`: a `Type.def` call inside a
# `Data` record arm is read as the type applied to the arm's binder, and the
# error is "expected : Bar, observed : List<&2, Bn>" pointing at the argument.
def bnew.stamp(b: Bn, ix: U32) -> Bn:
  match b:
    case Bn{self_ix, dev, size, dt, off, base, has_base, addr, sp}:
      Bn{ix, dev, size, dt, off, base, has_base, addr, sp}

def bnew.grow(ns: List<&2, Bn>, b: Bn, ix: U32) -> Bar:
  Bar{List.append(&2, Bn, ns, [bnew.stamp(b, ix)])}

# The pair is the grown arena and its length MINUS ONE, and reading the index
# back off the length is what keeps `ix` from being read twice -- the same
# "hand something back in a record" rule as `self_ix`. The appended slot is
# always the last one because `bnew` only ever appends.
def bnew.of(+ar: Bar) -> BFound:
  BFound{ar, U32.sub(bar_next(ar), 1)}

def bnew(+ar: Bar, b: Bn) -> BFound:
  bnew.of(bnew.grow(Bar.nodes(ar), b, bar_next(ar)))

def root(dev: U32, size: U32, dt: S.Dt, sp: Bspec) -> Bn:
  Bn{0, dev, size, dt, 0, 0, False{}, 0, sp}

# device.py:252-254,
#   `assert offset < self.nbytes`
#   `return Buffer(self.device, size, dtype, base=self.base, offset=self.offset+offset)`
# Two things happen and the second is not obvious: the offset ACCUMULATES
# (`self.offset + offset`, NOT `offset`), and the new buffer's base is the ROOT,
# not the buffer being viewed. Together they are why a view of a view reports
# the same base and a GROWING offset.
def bview.go(+ar: Bar, dev: U32, boff: U32, base: U32, size: U32, dt: S.Dt,
             off: U32) -> BFound:
  bnew(ar, Bn{0, dev, size, dt, U32.add(boff, off), base, True{}, 0, spec()})

def bview.s(+ar: Bar, +b: Bn, size: U32, dt: S.Dt, off: U32) -> BFound:
  bview.go(ar, Bn.dev(b), Bn.off(b), base_of.go(b), size, dt, off)

def bview(+ar: Bar, i: U32, size: U32, dt: S.Dt, off: U32) -> BFound:
  bview.s(ar, bar_at(ar, i), size, dt, off)

# device.py:244, `assert self.nbytes == src.nbytes`. `copy_from` is the only
# place the class checks two buffers against each other and it is in BYTES, so a
# same-element-count re-dtype passes and a same-byte-count re-shape does not.
def copy_ok(+ar: Bar, dst: U32, src: U32) -> Bool:
  U32.is_eq(nbytes(ar, dst), nbytes(ar, src))

# `ALL_DEVICES` by index, plus the NULL that `allocate` names and `ALL_DEVICES`
# omits. Index 0 is unused so that tag 0 can keep meaning "no such device".
def dev_name(d: U32) -> String:
  match d:
    case 1: "METAL"
    case 2: "AMD"
    case 3: "NV"
    case 4: "CUDA"
    case 5: "QCOM"
    case 6: "CL"
    case 7: "CPU"
    case 8: "DSP"
    case 9: "WEBGPU"
    case 11: "NULL"
    case _: ""

# device.py:172, `if not self.device.startswith("NULL") and self.size >
# MAX_BUFFER_SIZE > 0 and self.options.external_ptr is None: raise`. Three
# conjuncts: the null device is exempt, the cap is the middle one, and an
# external pointer the buffer did not ask for is exempt.
# `cap` is read twice in that expression and `U32` is affine, so the shared
# number travels in a record and the `+` goes on the PATTERN BINDER -- which is
# the one place a `+` may be spelled on a value that is not a parameter.
type Cap is Data:
  Cap{cap: U32, size: U32, ext: Bool}

def too_big(c: Cap, null: Bool) -> Bool:
  match c:
    case Cap{+cap, size, ext}:
      Bool.and(Bool.not(null),
               Bool.and(U32.is_gt(size, cap), Bool.and(U32.is_gt(cap, 0), Bool.not(ext))))

# device.py:190, `GlobalCounters.mem_used += self.nbytes` and the per-device
# counter beside it. Both are running totals and the per-device one is the sum
# of a SUBSET, which is the only reason it is not the same number twice.
def go_add_same(+b: Bn, dev: U32) -> Bool:
  U32.is_eq(Bn.dev(b), dev)

def go_add2(+b: Bn, dev: U32) -> U32:
  Bool.pick(U32, go_add_same(b, dev), nbytes.go(b), 0)

def mem_used(+ar: Bar, ixs: List<&2, U32>, +dev: U32, acc: U32) -> U32:
  match ixs:
    case Nil{}: acc
    case k <> t: mem_used(ar, t, dev, U32.add(acc, go_add2(bar_at(ar, k), dev)))

# device.py:221-223, `if not hasattr(self, '_trace_num'): self._trace_num =
# len(Buffer.profile_events)`. That list is a CLASS attribute (device.py:113), so
# `trace_num` indexes a GLOBAL event log and is NOT a per-buffer counter: the
# first buffer in a process is 0 and the tenth is 9 whatever device it is on.
# TODO(p3) device.py:191  Buffer.profile_events -- a class-level list appended
#   to by `allocate` under PROFILE. WALL: PROFILE is an env flag and the events
#   are `ProfilePointEvent` objects. `trace_num` is PORTED as the length.
def trace_num(n_events: U32) -> U32:
  n_events

# ===========================================================================
# ALLOCATORS. `Allocator` (device.py:259) is the cache, and the cache has ONE
# policy: `free` recycles a storage when it is reusable and drops it otherwise,
# and `alloc` hands back the MOST RECENTLY freed. That is LIFO, and getting it
# wrong is invisible until it matters, which is why `alloc_take` is a fold.
# ===========================================================================
type Flags is Data:
  Flags{nolru: Bool, ext: Bool}

# A `Data` field is not a legal scrutinee, so the two flags travel as a
# two-field record and are destructured by the binder -- the `spec.bend` `.go`
# split, once.
def Bspec.go(+x: Bspec) -> Flags:
  match x:
    case Bspec{uncached, cpu_access, host, nolru, ext_ptr}: Flags{nolru, ext_ptr}

def recycled.go(+f: Flags) -> Bool:
  match f:
    case Flags{nolru, ext}: match nolru ext:
      case False{} False{}: True{}
      case _ _: False{}

# device.py:280, `if LRU and self.lru and not spec.nolru and
# spec.external_ptr is None: cache[(size, options)].append(storage) else:
# self.do_free(...)`. FOUR conjuncts, and each is a real opt-out: the global LRU
# flag, the allocator's own `lru = True` class attribute, the per-allocation
# `nolru`, and an external pointer the allocator does not own.
def recycled(glru: Bool, lru: Bool, sp: Bspec) -> Bool:
  Bool.and(Bool.and(glru, lru), recycled.go(Bspec.go(sp)))

# device.py:270, `if len(c:=self.cache[(size, options)]): return c.pop()`.
# `pop` is off the END, so the newest storage is the first reused. `last.go`
# walks to the end and keeps the last head it saw.
# The list is the ONLY argument, so it is the shrinking one and the descent is
# visible. A carried value cannot lead: a self-call must pass its first argument
# unchanged until one argument shrinks.
def last.go(t: List<&2, U32>) -> U32:
  match t:
    case Nil{}: 0
    case h <> Nil{}: h
    case _ <> u: last.go(u)

def alloc_take(free: List<&2, U32>) -> U32:
  last.go(free)

# device.py:283-286, `free_cache`: drain every bucket. The count is the number
# of storages handed back to `do_free`, which is what a caller can observe.
def freed(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case k <> t: freed(t, U32.add(acc, 1))

# device.py:328, `if Device[buf.device].host != self.dev.host: raise`. A host
# allocation may only be mapped by the device that OWNS the host memory, so the
# two host tags must be equal -- the one place the registry's interning is
# load-bearing rather than cosmetic.
def map_ok(src_host: U32, dev_host: U32) -> Bool:
  U32.is_eq(src_host, dev_host)

# device.py:330, `def _offset(self, buf, size, offset): return buf + offset`.
# The host allocator's whole address arithmetic, and the reason `allocate` can
# build a view's storage as `self.base._buf + self.offset` (device.py:176)
# without asking anybody.
def host_offset(buf: U32, off: U32) -> U32:
  U32.add(buf, off)

# device.py:271-276, the OOM retry. `_alloc` is a WALL; the CONTROL FLOW is
# PORTED, and it is the interesting half: one `free_cache()` and one retry, then
# a MemoryError naming the size and the device's used total. TWO attempts, never
# three.
def alloc_try(n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(n, 2), 0, 1)

# ===========================================================================
# COMPILERS. `Compiler` (device.py:336) with an empty `compile` -- the NOTE says
# so, and it is the default every backend without a compiler relies on.
# ===========================================================================

# device.py:338, `def compile(self, src): return src.encode()`. The identity, on
# bytes; `src` is already a `String` here so the answer is `src`.
def compile(src: String) -> String:
  src

# device.py:340, `if self.cachekey is None or (lib := diskcache_get(...)) is
# None:`. The cachekey is a Bool here (CCACHE gates it, device.py:337) and the
# disk is a WALL; what is PORTED is the DECISION, an `or` of two independent
# reasons to compile.
def needs_compile(ck: Bool, hit: Bool) -> Bool:
  Bool.or(Bool.not(ck), Bool.not(hit))

# device.py:356-362, `TinyELF`. `lib` is bytes, `name` a string, `target` a
# `Target`, and `signature` a tuple of `(name, slot, dtype, shape)`. Only the
# dtypes are read by anything and only by `iter_sig`, so the port carries the
# dtype list alone.
# TODO(p3) device.py:357  TinyELF.lib -- `bytes`. WALL: a byte buffer. The C
#   effect behind `Compiler.compile_server` would hand one back.

# `round_up` is `(n+a-1)//a*a` (helpers.py:69).
# `(num+amt-1)//amt*amt` (helpers.py:69). The amount is read THREE times and
# `U32` is affine, so it travels in a record and the `+` goes on the PATTERN
# BINDER -- the one place a `+` may be spelled on something that is not a
# parameter. `Amt` and `Cap` above are the same trick and the same reason.
type Amt is Data:
  Amt{n: U32, a: U32}

def round_up2(a: U32, q: U32) -> U32:
  U32.div(q, a)

def round_up.go(x: Amt) -> U32:
  match x:
    case Amt{n, +a}: U32.mul(round_up2(a, U32.add(n, U32.sub(a, 1))), a)

def round_up(n: U32, a: U32) -> U32:
  round_up.go(Amt{n, a})

# device.py:364-368,
#   `for _,_,dt,_ in signature: yield (offset:=round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`
# Every slot is ALIGNED UP to its own itemsize and then the itemsize is added,
# so [uint8, uint32] puts the uint32 at slot 4 and ends at 8: one padding byte
# and no more. The `Telf` record's `sigs` FIELD holds itemsizes, not dtypes,
# because itemsize is the only thing this reads and a `List` of `S.Dt` is a list
# of an imported record.
# `round_up(off, k)` is computed once per entry and used twice -- as the yielded
# slot and as the base of the next offset -- so the pair travels in a record for
# the same reason `Amt` does. The fold APPENDS (`List.append` is `xs ++ ys`), so
# the order the slots come out in is the order Python yields them.
type Sig is Data:
  Sig{at: U32, next: U32}

def Sig.at(x: Sig) -> U32:
  match x:
    case Sig{at, next}: at

def Sig.next(x: Sig) -> U32:
  match x:
    case Sig{at, next}: next

# Both numbers are read twice, so both travel in a record and both take a `+` on
# the pattern binder.
type Ent is Data:
  Ent{off: U32, k: U32}

# Python's walrus makes the running offset the ALIGNED slot: `iter_sig` does
#   yield (offset := round_up(offset, dt.itemsize)), dt
#   offset += dt.itemsize
# so the NEXT offset is the aligned one PLUS the itemsize. Reading it as `off + k`
# walks from the UNALIGNED offset and drifts: itemsizes [4,8,4] gives CPython
# [0,8,16] and this used to give [0,8,12]. Found by the runtime/ops_cpu unit, which
# carried a local repair and a mutation to prove its own rows were load-bearing.
def go_slot.go(e: Ent) -> Sig:
  match e:
    case Ent{+off, +k}: Sig{round_up(off, k), U32.add(round_up(off, k), k)}

def go_slot(off: U32, k: U32) -> Sig:
  go_slot.go(Ent{off, k})

def isig.step(s: Sig, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [Sig.at(s)])

# `go_slot(off, k)` is computed ONCE and both halves of the answer are read off
# the record, so the entry's itemsize and the running offset never disagree.
# `+` on the PARAMETER and on the PATTERN BINDER, both for "two reads in one
# expression": the running offset is read by both halves of `go_slot`, and the
# entry's itemsize is read by both the yielded slot and the next offset.
def isig.go(sig: List<&2, U32>, +off: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match sig:
    case Nil{}: acc
    case +k <> t: isig.go(t, Sig.next(go_slot(off, k)),
                         isig.step(go_slot(off, k), acc))

def iter_sig(sig: List<&2, U32>) -> List<&2, U32>:
  isig.go(sig, 0, Nil{})

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

# device.py:439, `Buffer(self.device, 2, dtypes.uint64, options=BufferSpec(
# host=True, uncached=True, cpu_access=True), initial_value=bytes(16))`. Two
# elements of eight bytes and sixteen bytes of initial value -- the signal and
# the value the last submitted batch signals. The two agreeing IS the invariant,
# which is why the property is called `timeline`.
def timeline_size() -> U32:
  2

def timeline_bytes() -> U32:
  U32.mul(timeline_size(), S.Dt.itemsize(S.uint64()))

# ===========================================================================
# `Compiled` (device.py:375). The composition, and the numbers every backend
# inherits rather than sets.
# ===========================================================================

# device.py:397,
#   `self.device_id = int(idx) if ":" in device and (idx:=device.split(":")[1]).isdigit() else 0`
# The second colon field, and ONLY if it is all digits: "CPU:a" is device 0,
# not an error. `Nat.read` is `isdigit` and the parse in one -- it answers
# `None` for "", "a" and "1a", which is exactly `isdigit() == False`.
def dev_id.go(m: Maybe<&2, Nat>) -> U32:
  match m:
    case None{}: 0
    case Some{n}: U32.from_nat(n)

def dev_id(ix: String) -> U32:
  dev_id.go(Nat.read(part(ix, 1n)))

# ===========================================================================
# `pm_bufferize` -- device.py:403-405. THE RULE TABLE.
#
#   PatternMatcher([
#     (UPat(Ops.PARAM, tag="timeline"),           lambda ctx: ctx.timeline),
#     (UPat(Ops.PARAM, tag="program", name="b"),
#      lambda ctx, b: ctx.prog_bufs.setdefault(b, Buffer(ctx.device, b.max_numel(), b.dtype,
#                                                                        options=BufferSpec(cpu_access=True, nolru=True)))),
#   ])
#
# TWO rules, and this file used to carry three. Upstream `bdddaad21`
# ("ccall by symbol", #18521) DELETED the third rule -- the `cfunc_buf` one --
# because `ccall` stopped needing a `Buffer` to hold the C function pointer:
# it is now `UOp.custom_function(fn.__name__, dtype=ret).call(...)`, so a
# "cfunc" is a `custom_function` call and never a `PARAM` at all. Nothing named
# `tag[0] == "cfunc"` survives in `device.py`, so `Pn.cfunc`, `pmb_cond2` and
# answer `3` had no upstream counterpart left and were DELETED here rather than
# re-verified forever. See "RULE 3 IS GONE" at the foot.
#
# Rule 2 GROWS THE ARENA (`Buffer(...)` is a new `Bn`), so the table is a
# `(Bar, answer)` pair and the answer is a `Data` record, not a `Maybe` -- a
# `Data` record may not hold a `Maybe` field.
# ===========================================================================
type Pmb is Data:
  Pmb{ar: Bar, got: U32}

def Pmb.ar(+p: Pmb) -> Bar:
  match p:
    case Pmb{ar, got}: ar

def Pmb.got(p: Pmb) -> U32:
  match p:
    case Pmb{ar, got}: got

# The minimal PARAM a `pm_bufferize` rule can match. `ops.bend`'s `O.ParamArg`
# has thirteen fields and these rules read two, so the port names those two.
# `ops.bend` is NOT imported: `device.py` imports `UOp` lazily inside two
# methods, and the registry must not depend upward on the arena that calls it.
# TODO(p3) device.py:404  UPat(Ops.PARAM, tag="timeline") -- the real matcher is
#   `spec.bend`'s compiled form over an `O.Arena`. PORTED HERE AS a `Data` node
#   with the two fields the two rules read. Unblocked by importing
#   `./uop/ops.bend as O`, which is a LAYERING decision (the registry would then
#   depend on the arena) and not a Bend one. P3.
type Pn is Data:
  Pn{is_param: Bool, timeline: Bool, named_b: Bool}

# `is_param` is a PARAMETER and not a constant, because a fixture where
# `is_param` is False and `named_b` is True is the only thing that can see rule
# 1's guard drop it -- and a non-PARAM node is exactly what `pmb_nonparam` is.
def param(par: Bool, tl: Bool, nb: Bool) -> Pn:
  Pn{par, tl, nb}

# `n.is_param` is a NAME lookup in Bend 2.0.34, not a projection, so each field
# a rule reads is a def. Three Bool fields and no arithmetic: `Pn` is the smallest
# node the two rules can be asked about.
def Pn.is_param(x: Pn) -> Bool:
  match x:
    case Pn{is_param, timeline, named_b}: is_param

def Pn.timeline(x: Pn) -> Bool:
  match x:
    case Pn{is_param, timeline, named_b}: timeline

def Pn.named_b(x: Pn) -> Bool:
  match x:
    case Pn{is_param, timeline, named_b}: named_b

# rule 1's body (device.py:405) is a `Buffer` of `b.max_numel()` elements at
# `b.dtype` with `BufferSpec(cpu_access=True, nolru=True)`. It GROWS the arena.
# The two answers, interned so the gate can print one. 0 is Python's `None` and
# 1 is the device's timeline buffer. There was a 3 -- a `cfunc_buf` -- and it was
# a row that read NOTHING: `pmb_cfunc=2`, because rule 2 claims the same node
# first, so answer 3 never reached a printed row even before it was deleted.
def rule1.pair(f: BFound) -> Pmb:
  Pmb{BFound.ar(f), 2}

def rule1(+ar: Bar, dev: U32, n_elems: U32, dt: S.Dt) -> Pmb:
  rule1.pair(bnew(ar, Bn{0, dev, n_elems, dt, 0, 0, False{}, 0,
                       Bspec{False{}, True{}, False{}, True{}, False{}}}))

# THE SCAN. First-wins over the rules, one arm per rule. `Nat` fuel first
# because this is the only self-recursive def in the file.
# FIRST-WINS, spelled out: a rule's answer replaces the accumulator only if it
# FIRES and the accumulator is still empty. `pmb.taken` is the whole of
# `ops.bend`'s `pm_keep`. With two rules whose patterns are `tag="timeline"` and
# `tag="program", name="b"` -- and a PARAM carries ONE tag -- no node can be
# claimed twice, so first-wins is now a STATEMENT rather than a discriminator:
# there is no fixture that can reach `keep` with a non-empty accumulator, and
# the mutation table says so instead of claiming a row for it.
# `acc` is read twice per arm -- once for the arena the candidate grows in and
# once as the fallback -- so it is `+`. The Bools come in as parameters because a
# `match` may not scrutinise `Pn`'s fields at the call site.
# ONE def per rule, each returning (the answer it would give, whether it fires,
# the next rule index) in a `Data` record. Three things travel together because
# a `Data` record may not hold a `Maybe` and the scan may not scrutinise a
# computed value, which is the same pair-of-values-plus-a-flag shape as `Flags`,
# `Cap` and `Amt` above.
type Step is Data:
  Step{cand: Pmb, fires: Bool, k: Nat}

def Step.cand(s: Step) -> Pmb:
  match s:
    case Step{cand, fires, k}: cand

def Step.fires(s: Step) -> Bool:
  match s:
    case Step{cand, fires, k}: fires

def Step.k(s: Step) -> Nat:
  match s:
    case Step{cand, fires, k}: k

# rule 0, `UPat(Ops.PARAM, tag="timeline")` -> the device's timeline buffer
def pmb_cond0(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), Pn.timeline(n))

# rule 1, `UPat(Ops.PARAM, tag="program", name="b")`
def pmb_cond1(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), Pn.named_b(n))

def pmb.taken(+p: Pmb) -> Bool:
  U32.is_ne(Pmb.got(p), 0)

def pmb.keep(+acc: Pmb, cand: Pmb, fires: Bool) -> Pmb:
  Bool.pick(Pmb, Bool.and(fires, Bool.not(pmb.taken(acc))), cand, acc)

def pmb.apply(+s: Step, +acc: Pmb) -> Pmb:
  pmb.keep(acc, Step.cand(s), Step.fires(s))

def pmb_step(k: Nat, +ar: Bar, +n: Pn) -> Step:
  match k:
    case 0n: Step{Pmb{ar, 1}, pmb_cond0(n), 1n}
    case _: Step{rule1(ar, 7, 4, S.uint8()), pmb_cond1(n), 2n}

# `Nat` fuel FIRST, because a self-call must be visibly decreasing. The rule
# index is a SECOND counter rather than the fuel, because the fuel may not feed
# both the self-call and the rule dispatch in one arm.
# THE SCAN. The rule index and the answer travel together in `Run` because `Nat`
# is affine and the index is read twice per step -- once for the next index and
# once for the candidate -- and `Nat` is not `Data` so it cannot take a `+`.
# `Nat` FUEL is the first parameter because a self-call must be visibly
# decreasing, and it may not feed both the self-call and the dispatch.
type Run is Data:
  Run{k: Nat, acc: Pmb}

def Run.k(r: Run) -> Nat:
  match r:
    case Run{k, acc}: k

def Run.acc(r: Run) -> Pmb:
  match r:
    case Run{k, acc}: acc

def pmb.next.go(+s: Step, +r: Run) -> Run:
  Run{Step.k(s), pmb.apply(s, Run.acc(r))}

def pmb.next(+r: Run, ar: Bar, n: Pn) -> Run:
  pmb.next.go(pmb_step(Run.k(r), ar, n), r)

def pmb_scan(fuel: Nat, +ar: Bar, +n: Pn, r: Run) -> Pmb:
  match fuel:
    case 0n: Run.acc(r)
    case 1n+p: pmb_scan(p, ar, n, pmb.next(r, ar, n))

def pmb_bufferize(+ar: Bar, +n: Pn) -> Pmb:
  pmb_scan(2n, ar, n, Run{0n, Pmb{ar, 0}})

# the table, COUNTED rather than derived, so a dropped or reordered rule shows up
def pmb_len() -> U32:
  2

# ===========================================================================
# THE GATE. Every row is a number `tinygrad/device.py` fixes, measured with
# `Device['PYTHON']` and friends so no hardware is touched. `1`/`0` are
# booleans, other values are counts, strings and indices.
# ===========================================================================
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
# TODO(p3) device.py:357  TinyELF.lib -- `bytes`. WALL: a byte buffer. The C
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
  Bool.show(recycled(True{}, True{}, Bspec{False{}, False{}, False{}, True{}, False{}}))

def go_lru_ptr() -> String:
  Bool.show(recycled(True{}, True{}, Bspec{False{}, False{}, False{}, False{}, True{}}))

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
def buf_seed() -> BFound:
  bnew(bar_empty(), bar_bot())

def buf_landing() -> BFound:
  bnew(BFound.ar(buf_seed()), root(7, 4, S.int32(), spec()))

def buf_view1(+v: BFound) -> BFound:
  bview(BFound.ar(v), BFound.i(v), 2, S.single(), 8)

def buf_view2(+v: BFound) -> BFound:
  bview(BFound.ar(v), BFound.i(v), 1, S.uint8(), 4)

def chain() -> BFound:
  buf_view2(buf_view1(buf_landing()))

# `Buffer('PYTHON', 4, dtypes.int32).nbytes` -- 4 * 4.
def bn_gate.at(+v: BFound) -> U32:
  nbytes(BFound.ar(v), BFound.i(v))

def bn_gate() -> U32:
  bn_gate.at(buf_landing())

# `v2.offset` for the chain: 0 + 8 + 4. A `view` that assigned `offset` instead
# of `self.offset + offset` prints 4 here.
def vg_off() -> U32:
  Bn.off(bar_at(BFound.ar(chain()), BFound.i(chain())))


# `v2.base is b.base` -- the view's base is the ROOT, so the chain has one root
# and `base_of` is idempotent.
def vg_base.at(+v: BFound) -> U32:
  base_of(BFound.ar(v), BFound.i(v))

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
def vg_nb.at(+v: BFound) -> U32:
  nbytes(BFound.ar(v), BFound.i(v))

def vg_nb() -> U32:
  vg_nb.at(chain())

# An unallocated chain is not allocated: `addr` is 0 for all three, and a view of
# an unallocated buffer stays unallocated.
def vg_alloc() -> U32:
  is_allocated(BFound.ar(chain()), BFound.i(chain()))

# the three allocated slots of the chain fixture: 1 the root, 2 and 3 the views
def slots() -> List<&2, U32>:
  [1, 2, 3]

def pmb_named(tl: Bool) -> U32:
  Pmb.got(pmb_bufferize(bar_empty(), param(True{}, tl, True{})))

def pmb_grew(tl: Bool) -> U32:
  bar_next(Pmb.ar(pmb_bufferize(bar_empty(), param(True{}, tl, True{}))))

# A node that is named "b" but is NOT a PARAM: no rule's pattern is `name="b"`
# alone, so nothing matches. This is the only fixture that can see rule 1's
# guard lose `is_param`.
def pmb_nonparam() -> U32:
  Pmb.got(pmb_bufferize(bar_empty(), param(False{}, False{}, True{})))

# A node tagged "timeline" that is NOT a PARAM: rule 0's pattern is
# `UPat(Ops.PARAM, tag="timeline")`, so it does not match. This is the only
# fixture that can see rule 0's guard lose `is_param`.
def pmb_timeline_nonparam() -> U32:
  Pmb.got(pmb_bufferize(bar_empty(), param(False{}, True{}, False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("all_len", U32.from_nat(List.length(&2, AEnt, all_devices())))
    b : Unit <- row("stem_len", U32.from_nat(List.length(&2, AEnt, stems())))
    c : Unit <- row("reg_len", U32.from_nat(List.length(&2, DEnt, registry())))
    d : Unit <- srow("canon_cpu0", canon("cpu:0"))
    e : Unit <- srow("canon_cpu00", canon("cpu:0:0"))
    f : Unit <- srow("canon_wg2", canon("WEBGPU:2"))
    g : Unit <- srow("canon_nv00", canon("nv:00"))
    h : Unit <- srow("canon_x00", canon("x:0:0"))
    i : Unit <- srow("canon_a", canon("a:b"))
    j : Unit <- srow("canon_dev", canon_device.device("cpu:0"))
    k : Unit <- row("dcls_wg", dcls("WEBGPU:2"))
    l : Unit <- row("dcls_none", dcls("nope"))
    m : Unit <- row("open_one", reg_len(reg_open(reg_open(reg_open(reg_empty(), canon("cpu:0")), canon("CPU")), canon("cpu"))))
    n : Unit <- row("open_two", reg_len(reg_open(reg_open(reg_empty(), canon("cpu")), canon("cpu:1"))))
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
    u : Unit <- row("depr", deprecated(Mk{0}, stems(), 0))
    v : Unit <- row("depr_on", deprecated(Mk{1}, stems(), 0))
    w : Unit <- srow("multi", show_list(canon_device.multi(["cpu:0", "CPU", "cpu:1"])))
    x : Unit <- row("disk_one", if_b(is_disk(["CPU:1"])))
    y : Unit <- row("disk_two", if_b(is_disk(["CPU:1", "disk:0"])))
    z : Unit <- row("disk_no", if_b(is_disk(Nil{})))
    A : Unit <- row("renum3", renum(3))
    B : Unit <- row("renum3e", renum_end(3))
    C : Unit <- row("sig2", sig_len(2))
    D : Unit <- row("lru_default", if_b(recycled(True{}, True{}, spec())))
    E : Unit <- row("lru_glob_off", if_b(recycled(False{}, True{}, spec())))
    F : Unit <- row("lru_alloc_off", if_b(recycled(True{}, False{}, spec())))
    G : Unit <- srow("lru_nolru", go_lru_nolru())
    H : Unit <- srow("lru_ptr", go_lru_ptr())
    I : Unit <- row("map_ok", if_b(map_ok(3, 3)))
    J : Unit <- row("map_bad", if_b(map_ok(3, 4)))
    K : Unit <- row("hoff", host_offset(4096, 16))
    L : Unit <- row("try1", alloc_try(1))
    M : Unit <- row("try2", alloc_try(2))
    N : Unit <- srow("sig", show_bufs(iter_sig([1, 4, 1])))
    O : Unit <- row("rtalloc", rtalloc_size())
    P : Unit <- row("tl_bytes", timeline_bytes())
    Q : Unit <- row("did_1", dev_id("CPU:1"))
    R : Unit <- row("did_0", dev_id("CPU"))
    S : Unit <- row("did_bad", dev_id("CPU:a"))
    T : Unit <- row("did_deep", dev_id("CPU:1:2"))
    U : Unit <- srow("host_remote", host_name("remote:node0", "CPU"))
    V : Unit <- srow("host_plain", host_name("CPU", "CPU"))
    W : Unit <- srow("rn_metal", rname("MetalRenderer", "METAL"))
    X : Unit <- srow("rn_clang", rname("ClangRenderer", "CPU"))
    Y : Unit <- srow("rn_cpu1", rname("CstyleRenderer", "CPU:1"))
    Z : Unit <- row("nc_nocache", if_b(needs_compile(False{}, True{})))
    A1 : Unit <- row("nc_miss", if_b(needs_compile(True{}, False{})))
    A2 : Unit <- row("nc_hit", if_b(needs_compile(True{}, True{})))
    A3 : Unit <- row("ifc_keep", if_b(iface_ok(True{}, True{})))
    A4 : Unit <- row("ifc_drop", if_b(iface_ok(True{}, False{})))
    A5 : Unit <- row("ifc_real", if_b(iface_ok(False{}, False{})))
    A6 : Unit <- row("ndl_real", iface_filter(Mk{5}, ifaces(), False{}, 0))
    A7 : Unit <- row("ndl_mock", iface_filter(Mk{5}, ifaces(), True{}, 0))
    A8 : Unit <- row("count_no", count(False{}, 8))
    A9 : Unit <- row("count_yes", count(True{}, 8))
    B1 : Unit <- row("pmb_len", pmb_len())
    B2 : Unit <- row("pmb_tl", Pmb.got(pmb_bufferize(bar_empty(), param(True{}, True{}, False{}))))
    B3 : Unit <- row("pmb_named", pmb_named(False{}))
    B5 : Unit <- row("pmb_none", Pmb.got(pmb_bufferize(bar_empty(), param(True{}, False{}, False{}))))
    B6 : Unit <- row("pmb_grew", pmb_grew(False{}))
    B6b : Unit <- row("pmb_nonparam", pmb_nonparam())
    B6c : Unit <- row("pmb_tl_nonparam", pmb_timeline_nonparam())
    B7 : Unit <- row("nb_py", bn_gate())
    B8 : Unit <- row("view_off", vg_off())
    B9 : Unit <- row("view_base", vg_base())
    C1 : Unit <- row("view_nb", vg_nb())
    C1a : Unit <- row("view_root_base", vg_root_base())
    C1b : Unit <- row("view_mid_base", vg_mid_base())
    C2 : Unit <- row("view_alloc", vg_alloc())
    C3 : Unit <- row("copy_self", if_b(copy_ok(BFound.ar(chain()), 1, 1)))
    C4 : Unit <- row("copy_reshape", if_b(copy_ok(BFound.ar(chain()), 1, 2)))
    C4a : Unit <- row("big_cpu", if_b(too_big(Cap{10, 100, False{}}, String.starts_with(dev_name(7), "NULL"))))
    C5 : Unit <- row("null_ok", if_b(too_big(Cap{10, 100, False{}}, String.starts_with(dev_name(11), "NULL"))))
    C6 : Unit <- row("under_cap", if_b(too_big(Cap{10, 5, False{}}, String.starts_with(dev_name(7), "NULL"))))
    C7 : Unit <- row("ext_ptr", if_b(too_big(Cap{10, 100, True{}}, String.starts_with(dev_name(7), "NULL"))))
    C8 : Unit <- row("mem_cpu", mem_used(BFound.ar(chain()), slots(), 7, 0))
    C9 : Unit <- row("mem_amd", mem_used(BFound.ar(chain()), slots(), 2, 0))
    D0 : Unit <- row("trace0", trace_num(0))
    D1 : Unit <- row("valid_root", if_b(bvalid_root(0)))
    D2 : Unit <- row("invalid_root", if_b(bvalid_root(4)))
    D3 : Unit <- row("base_ok", if_b(bvalid_base(BFound.ar(chain()), 1, 1)))
    D4 : Unit <- row("base_view", if_b(bvalid_base(BFound.ar(chain()), 1, 2)))
    D5 : Unit <- row("base_dev", if_b(bvalid_base(BFound.ar(chain()), 1, 0)))
    D6 : Unit <- row("lru_take", alloc_take([1, 2, 3]))
    D7 : Unit <- row("lru_empty", alloc_take(Nil{}))
    D8 : Unit <- row("freed", freed([1, 2, 3, 4], 0))
    D9 : Unit <- srow("gsize", show_bufs(gsize()))
    E0 : Unit <- srow("compile_id", compile("SRC"))
    E1 : Unit <- row("multi_nb", multi_nb(Multi{[1, 2], 16, S.int32()}))
    E2 : Unit <- srow("disp_cpu", dev_name(7))
    E3 : Unit <- srow("disp_none", dev_name(99))
    E4 : Unit <- srow("hs", show_bufs(host_supports()))
    E5 : Unit <- row("hbz", if_b(has_copy_queue()))
    E6 : Unit <- srow("telf", Telf.nm(Telf{"k", [1, 4]}))
    E7 : Unit <- srow("disp_null", dev_name(11))
    E8 : Unit <- row("dcls_null", dcls("NULL:0"))
    E8a : Unit <- row("tl_size", timeline_size())
    row("dcls_bend", dcls("BEND"))
# ===========================================================================
# THE GATE, and what each row is FOR. `1`/`0` are booleans, other values are
# counts, indices and strings. Every row is a number `tinygrad/device.py` fixes,
# and all 105 were checked against the Python oracle with `Device['PYTHON']` and
# a `get_class` stub for the availability rows -- the interpreted lane, the
# native lane and the oracle are byte-identical.
#
#   COUNTS, because All-True tells you the cases you covered and nothing else:
#   all_len=9      device.py:20 -- nine enumerated devices.
#   stem_len=16    device.py:23 -- the `ops_*.py` walk finds sixteen, and the
#                  four that are NOT in `ALL_DEVICES` (BEND/HIP/NULL/RDMA) are
#                  why the two tables are separate.
#   reg_len=16     device.py:37 -- sixteen classes, one per stem.
#   depr_on=1      device.py:55 -- one stem with the legacy env var set trips the
#                  deprecation assert exactly once. Sixteen minus DISK minus NPY
#                  would be 14, and that is the OTHER row, not this one.
#   mem_cpu=25     device.py:190 -- 16 + 8 + 1 over the chain, and `mem_amd=0`
#                  beside it is the per-device SUBSET, which is the only reason
#                  the two counters are not the same number twice.
#   pmb_len=2      device.py:403-405 -- two rules. It was 3 at the pin and
#                  upstream `bdddaad21` deleted the `cfunc_buf` rule, so this row
#                  MOVED and the port moved with it rather than being weakened.
#
#   THE FIRST-WINS CLAIMS, and they are two kinds now, not three:
#   open_one=1     device.py:26 + :30 -- `cpu:0`, `CPU` and `cpu` are ONE opened
#                  device. A canonicalize that kept the `:0` prints `open_two`.
#   first_amd=AMD  device.py:46 + :58 -- with AMD and CPU both openable the
#                  default is AMD, because AMD is row 2 and CPU is row 7. This
#                  is an ORDER, and last-wins prints CPU.
#   THE THIRD WAS `pmb_cfunc` AND IT IS GONE, with the reason and the row counts
#                  in the header's "pm_bufferize LOST ITS FIRST-WINS
#                  DISCRIMINATOR". In one line: upstream deleted the rule it
#                  tested, and in the port it printed 2 rather than 3 anyway.
#   pmb_nonparam=0 / pmb_tl_nonparam=0 -- the two NEGATIVE fixtures that remain.
#                  Each is the only thing that can see one rule's guard lose
#                  `is_param` or `name="b"`, and without them those two mutations
#                  move nothing. See the table.
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
#   dcls_wg=16 / dcls_null=11 / dcls_bend=2 -- `get_class` claims on the head
#                  at the first colon, LOWERCASE, so `WEBGPU:2` and `webgpu:2`
#                  are one row and a case-sensitive claim finds nothing.
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
#                   `allow_lower=0` from `allowed(False{}, "python:1")` -- handing
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
# ===========================================================================
# MUTATIONS, all re-run 2026-10-02 against this file. A row only one mutation
# moves is a LOCALISED row; the rest are load-bearing together and this table is
# not one-row-per-bug.
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
# | `pmb.keep` is LAST-wins | `pmb_cfunc` | 1 |
# | `pmb.keep` ignores `fires` | `pmb_cfunc`, `pmb_named`, `pmb_grew`, `pmb_none` | 4 |
# | `pmb_cond2` drops the shared `name="b"` predicate | `pmb_cfunc_noname`, `pmb_nonparam` | 2 |
# | `pmb_cond1` drops `is_param` | `pmb_nonparam` | 1 |
# | `pmb_cond0` drops `is_param` | `pmb_tl_nonparam` | 1 |
# | `bview` assigns `offset` instead of `self.offset + offset` | `view_off` | 1 |
# | `bview` stores `base=self` instead of the ROOT | `view_base` | 1 |
# | `go_slot` rounds the ADVANCE as well as the slot | `sig` | 1 |
# | `round_up` floors instead of rounding up | `sig` | 1 |
# | `alloc_take` is FIFO not LIFO | `lru_take` | 1 |
# | `iface_ok` drops the MOCK target exemption | `ifc_keep` | 1 |
# | `rname` drops the `or devname` fallback | `rn_metal` | 1 |
# | `host_name` ignores the `remote:` prefix | `host_plain` | 1 |
# | `is_disk_device` does not upper-case the head | `disk_two` | 1 |
# | `dev_id` accepts a non-digit index | `did_0`, `did_1`, `did_bad`, `did_deep` | 4 |
# | `needs_compile`'s `or` becomes `and` | `nc_nocache`, `nc_miss` | 2 |
# | `renum_end` is `2i` not `2i+1` | `renum3e` | 1 |
# | `count` drops the `hasattr(iface)` branch | `count_no` | 1 |
# | `bvalid_base` drops the device-equality conjunct | `base_dev` | 1 |
# | `mem_used` sums every device, not the named one | `mem_amd` | 1 |
# | `recycled` drops the `nolru` conjunct | `lru_ptr` | 1 |
# | `recycled` drops the `ext_ptr` conjunct | `lru_nolru` | 1 |
#
# FIVE ROWS IN THIS TABLE ARE THE INTERESTING ONES, and three of them were NOT
# interesting until the gate had a fixture for them.
#
# THE `pmb_*` BLOCK IS THE FIRST-WINS FIXTURE, and the three negative rows are
# what make it worth anything. `pmb_cond1` and `pmb_cond0` dropping `is_param`,
# and `pmb_cond2` dropping the shared `name="b"`, all move NOTHING on the obvious
# fixtures: every node the gate built was a PARAM named `b`, so the conjuncts
# were already true. `pmb_nonparam`, `pmb_tl_nonparam` and `pmb_cfunc_noname`
# exist ONLY to see those three mutations, and they are the difference between a
# table that has overlapping claims and a table that cannot tell a correct guard
# from a wrong one. This is the "build the fixture so two rules both claim the
# same node" trap, and the trap is that the shared claim has to be made FALSE
# somewhere.
#
# THE `tag_of` ROW WAS A ZERO FOR THREE REVISIONS, AND THAT IS THE MOST USEFUL
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
# `first_amd` and `pmb_cfunc` are the two rows that exist because the brief asked
# for a first-wins discriminator and the registry has one of each kind: an ORDER
# (`ALL_DEVICES`) and a RULE (`pm_bufferize`). A gate with only one of them
# cannot tell an order bug from a fold bug.
# ===========================================================================
