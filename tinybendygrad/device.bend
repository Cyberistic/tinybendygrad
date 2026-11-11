# device.bend -- tinygrad/device.py. THE DEVICE LAYER: the registry that turns
# a device STRING into a device, the Buffer that is the data handle, and
# `Compiled`, the composition of an allocator, a renderer, a compiler and a
# program. tinygrad's final output depends on which of these is underneath, so
# this is the file the WebGPU phase hangs off.
#

# what is ported, and why it is the same amount of code.
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
# buffers are (nbytes, content-address) parameters. Python's `Buffer` is an
# object whose IDENTITY `_base_storage is base._storage` depends on
# (device.py:111), so a Bend `Buffer` is a slot in a `Bar` arena rather than a
# value: `Bn` carries the dtype, the size, the byte offset, the base slot and a
# content address standing in for `_storage`. That is everything the class's
# decisions read, and it is why `view` can be checked at all.
#

# ONE FIRST-WINS CLAIM, and it is an ORDER.
#
# 1. `_canonicalize` (device.py:28 symbol=_canonicalize) collapses `cpu:0` and `CPU` onto ONE
#    registry slot, so `Device['cpu:0'] is Device['CPU']` and opening both
#    opens one device. `open_one` is that count, and nothing else notices a
#    canonicalize that forgets the "zero" suffix strip -- it would print
#    `open_two`.  (the port's own row names `open_one` and `open_two` are NOT
#    in upstream)
#
# 2. and it is an order rather than a rule: `ALL_DEVICES` (device.py:18) is
#    nine names and `get_available_devices` (device.py:48 symbol=get_available_devices) yields in that order
#    and `_select_device` (device.py:56 symbol=_select_device) takes `next(...)`. AMD is second and CPU
#    is seventh, so with both openable the default is AMD. `first_amd` is that row
#    and a last-wins fold prints CPU.
#

# THE LINK, and it is what REPLACED the rule table at the pin. That table is
# GONE, from upstream and from this port.
#
# Upstream's `tinygrad/device.py` carries TWO members this file did not have:
#
#   device.py:377   link_bufs:dict[str, Any] = {}
#   device.py:411   def link_buffer(self, b:UOp) -> Buffer|None: return None
#
# `link_bufs` is a CLASS attribute -- ONE dict for every device, mutated IN
# PLACE by `Compiled.link_bufs |= {...}` at backend-import time -- and
# `link_buffer` is a PER-DEVICE METHOD whose base-class answer is `None`.
# Their only consumer is `tinygrad/runtime/support/hcq2.py:488-490`, in
# `bufferize_buf`, and it answers ONE question: which PHYSICAL buffer does
# this logical ALLOC belong to?
#
# THERE IS NO `Compiled.tag()`. `rg -n 'def tag|\.tag\(' tinygrad/` at the pin
# answers one line -- `tinygrad/uop/ops.py:269: def tagstr(self)` -- and
# `tag` is a FIELD of `UOp.arg` that the MATCHER patterns read
# (`UPat(Ops.PARAM, tag="timeline")`). It is not a method and it is not on
# `Compiled`.
#
# and neither `link_buffer` nor `link_bufs` mutates a kernel's BUFFER list.
# `link_buffer` is a PURE QUERY -- a UOp in, a Buffer or None out -- and
# `link_bufs` is a dict that `|=` mutates. What CHANGES is the ALLOC's
# BINDING, and `bufferize_buf` builds a NEW UOp (`UOp.from_buffer(...)`).
#
# the `pm_bufferize` rule table is gone from this port, and upstream is why.
#
# At the PREVIOUS vendoring `tinygrad/device.py:375` read
#   `pm_bufferize:Any = None # one for all devices: each adds the rules of the
#    placeholders it owns, its tags start with its name`
# and the rules were a `PatternMatcher` a backend PREPENDED to -- two rules,
# `UPat(Ops.PARAM, tag="timeline")` and `UPat(Ops.PARAM, tag="program",
# name="b")`. AT THE PIN THAT CLASS ATTRIBUTE IS GONE: the grep
# `rg -n pm_bufferize tinygrad/` answers NOTHING, and
# `device.py:374-377` carries `pm_encode`,
# `pm_lower`, `pm_link` and `link_bufs`, with `link_buffer` a per-device
# method at `device.py:411`.
#
# WHAT REPLACED IT: `Compiled.link_bufs` (a NAME -> owner registry), the
# per-device `Compiled.link_buffer`, and their ONE consumer, `bufferize_buf` in
# `tinygrad/runtime/support/hcq2.py:481-495`. THAT IS PORTED AND LIVE: the
# registry, the resolution and `to_name` are the twenty-six `lk_*`/`tn_*` rows
# below, and `bufferize_buf` is `tinybendygrad/runtime/support/hcq2.bend`,
# sixty-two rows against CPython's own function.
#
# the seven rows that went with the table, and what covers each of them now:
#   pmb_len=2       the table's rule COUNT. Nothing covers it and nothing
#                   should: there is no attribute to count.
#   pmb_tl=1        a PARAM tagged "timeline" -> the device's timeline buffer.
#                   Now `hcq2.py:477` registers `{"timeline": ...}` in
#                   `link_bufs`, and the `lk_lvl_*`/`lk_kind_*`/`lk_buf_*` rows
#                   plus `bufferize_buf`'s sixty-two are the measurement.
#   pmb_named=2     a PARAM named "b" -> a NEW program Buffer. Now the
#                   unlinked-alloc branch of `bufferize_buf`, which is
#                   `lk_lvl_none=4` and `lk_lvl_wrongdev=4` here.
#   pmb_none=0      a PARAM that matches no rule. Now the same branch.
#   pmb_grew=1      the arena grew by one slot. Now `bufferize_buf`'s
#                   allocation, measured by `lk_plain_bytes`/`lk_hook_bytes`.
#   pmb_nonparam=0      a NON-PARAM does not match rule 1.
#   pmb_tl_nonparam=0   a NON-PARAM does not match rule 0.
#                   the last two are covered by nothing, and nothing should be:
#                   the `is_param` conjunct they exercise was a guard in the
#                   DELETED table's patterns. Upstream's replacement has no such
#                   guard -- `bufferize_buf` is called on a PARAM by
#                   construction and asks about a NAME.
#
# two measured facts that survived the table, because they are why the port was
# ALREADY drifting before this removal:
#   1. Upstream `bdddaad21` ("ccall by symbol", #18521) DELETED the table's
#      THIRD rule -- the `cfunc_buf` one -- because `ccall` stopped needing a
#      `Buffer` to hold a C function pointer. Nothing in `device.py` is a PARAM
#      tagged `"cfunc"` any more.
#   2. The port's own `pmb_cfunc` row printed 2, not 3: rule 2 claims the
#      node first and the scan is first-wins, so the third rule's answer never
#      reached a printed row even BEFORE upstream deleted it.
# So the table was a corpse that was already a corpse upstream, and this removal
# deletes it on both sides at once.
#

# two measured BEND constraints this file is built around. Both cost a compile
# cycle each and neither is in bend2-constraints.md yet.
#
# A. A LIST OF `Bool` IS AWKWARD TO READ, NOT UNUSABLE. `List<&2, Bool>` is
#    accepted as a parameter annotation and `List.length(&2, Bool, xs)` COMPILES
#    AND RUNS (MEASURED 2026-10-07: `U32.from_nat(List.length(&2, Bool, xs))`
#    returns a value; an earlier note here claimed it was "refused by every
#    reader", which the measurement did NOT reproduce and which `flipthird` had
#    already contradicted). What IS real: element access is the cost.
#    `List.get(&2, Bool, xs, 0n)` has type `Maybe<&2, Bool>`, so every read is a
#    peel, and a cons pattern `case k <> t:` over the list names a consumed
#    binder. A `Bool` FIELD of a `Data` record is fine (e.g. `CBool{b: Bool}`).
#    So availability, deprecation and mock-ness are a U32 BITMASK read with
#    `U32.shrn`/
#    `U32.and` against the row's own index -- which also removes the two
#    parallel lists, and with them a zip fold.
#
# B. A `match` on a list of a LOCALLY DECLARED one-field `Data` record is
#    refused, and the refusal is NOT reproducible from the file. The same
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

# THE TWO FOLD TABLES. Both rows carry their OWN index, which is what lets a
# first-wins scan answer "which row" without an accumulator -- and an
# accumulator would have to be read twice in one expression to be passed on.

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

# THE STRING PRIMITIVES. Three jobs, and the middle one is the one that is easy
# to get wrong: `String.split` throws the separators away, so the tail has to
# be re-joined with them, and BOTH of its colons.

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

# device.py:70-72, `is_disk_device`: `any(d.split(":", 1)[0].upper() in
# ("DISK", "NVME") for d in to_tuple(device)` over a tuple, so the empty tuple
# is False.
#
# THE `"NVME"` ARM IS THE ONE THIS DEF WAS MISSING, AND THE COMMENT ABOVE IT
# MISQUOTED UPSTREAM WHILE IT DID. MEASURED 2026-11-10, CPython's OWN
# `is_disk_device`:
#   is_disk_device(("DISK:0",)) -> True
#   is_disk_device(("NVME:0",)) -> True    <-- THE PORT ANSWERED False
#   is_disk_device(("nvme:0",)) -> True    <-- UPPER-CASED, SO ALSO True
# UPSTREAM'S SPELLING IS `in ("DISK", "NVME")` -- TWO NAMES -- AND THE PORT
# HAD ONE. `NVME` IS NOT A HYPOTHETICAL NAME: `tinygrad/runtime/ops_nvme.py`
# EXISTS AT THE PIN AND DEFINES `NVMEDevice`, AND THE PORT PORTS THAT FILE AS
# `tinybendygrad/runtime/ops_nvme.bend` -- SO THE PORT HAS THE DEVICE AND
# `is_disk` DID NOT RECOGNISE IT. `uop/spec.py:178` READS
# `not is_disk_device(copy.arg)` AND `uop/ops.py:724` READS
# `is_disk_device(device)`, SO A WRONG ANSWER HERE IS A WRONG SPEC AND A WRONG
# `on_disk`.
def is_disk_head(+h: String) -> Bool:
  Bool.or(String.eq(h, "DISK"), String.eq(h, "NVME"))

def is_disk(ixs: List<&2, String>) -> Bool:
  match ixs:
    case Nil{}: False{}
    case +k <> t: Bool.pick(Bool, is_disk_head(String.to_upper(head(k))), True{}, is_disk(t))

# `ALL_DEVICES` -- device.py:20. Nine names, and THE ORDER IS THE POLICY.
# `_select_device` takes `next(get_available_devices())` and that generator
# walks this list, so index 2 beating index 7 is the default-device policy.

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

# THE CLASS REGISTRY. `ALL_DEVICES` above is the ENUMERATION; this is the
# dispatch, and the two are different lists on purpose. `get_class`
# (device.py:34-37) is
#   `importlib.import_module(f'{base}.runtime.ops_{x}')` then
#   `[cls for cname, cls in getmembers(m) if cname.lower() == x + "device"][0]`
# with `x = ix.split(":")[0].lower()`, so the claim is a PREFIX claim: `webgpu:1`
# and `WEBGPU` are ONE row, and the seventeen rows below are the sixteen
# `ops_*.py` stems the same walk finds PLUS THE PORT's OWN `ops_bend.bend`.
# TODO(p3) device.py:37  get_class -- `importlib` + `inspect.getmembers`. WALL:
#   a dynamic import and a reflection scan. The table below IS the resolved
#   lookup, first-wins on the head; a new `ops_*.py` needs one row here.
#
# THE `nvme` ROW IS THE ONE THIS TABLE WAS MISSING, AND THE COUNT DID NOT SEE IT.
# MEASURED 2026-11-10, UPSTREAM'S OWN WALK OVER `tinygrad/runtime/`:
#   `ops_*.py` stems -> AMD CL CPU CUDA DISK DSP HIP METAL NPY NULL NV NVME
#   PYTHON QCOM RDMA WEBGPU -- SIXTEEN, AND `NVME` IS ONE OF THEM -- and
#   `importlib.import_module('tinygrad.runtime.ops_nvme')` ANSWERS
#   `NVMEDevice`, so upstream's `get_class('nvme')` SUCCEEDS and
#   `Device['NVME:0']` OPENS. The port's table had SIXTEEN rows too, and
#   `stem_len=16` / `reg_len=16` READ CORRECTLY, so NO ROW COULD SEE THE
#   MISSING ONE: the port had SPENT `NVME`'s SLOT ON `BEND`, THE PORT's OWN
#   DEVICE, WHICH UPSTREAM DOES NOT HAVE AT ANY REVISION. THE PORT'S `BEND`
#   ROW IS RIGHT AND ITS `NVME` ROW WAS ABSENT, AND A COUNT IS NOT A TABLE.
#
# THE INDICES ARE STABLE. `tag_of` (device.py:31's allow-list) HARD-CODES 6 for
# DISK, 10 for NPY and 13 for PYTHON, AND `DEnt.ix` IS THE ROW's OWN INDEX,
# SO `nvme` IS ADDED AT 17 -- THE END -- AND EVERY EXISTING INDEX IS
# UNTOUCHED. THE TABLE IS ALPHABETICAL UP TO `webgpu` AND `nvme` IS THE ONE
# ROW THAT IS NOT, AND THAT IS THE PRICE OF A STABLE INDEX -- THE WALK IS
# NOT ORDERED AT ALL (`iterdir` IS NOT SORTED), SO THE TABLE's ORDER IS THE
# PORT's OWN, AND THE INDEX IS WHAT THE OTHER ROWS READ.

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
   DEnt{15, "rdma", "RDMADevice"}, DEnt{16, "webgpu", "WebGPUDevice"},
   DEnt{17, "nvme", "NVMEDevice"}]

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

# THE OPENED SET. `_opened_devices` (device.py:24) is a `set[str]` that grows by
# one per `__get_canonicalized_item`, and the growth IS the point: three
# spellings of one device are ONE slot, because `canonicalize` runs first
# (device.py:30).
# TODO(p3) device.py:41  __get_canonicalized_item -- `functools.cache` and
#   `self.get_class(ix)(ix)`. WALL: constructing a device opens hardware. The
#   MEMOISATION is PORTED -- `reg_open` is the cache, keyed on the canonical
#   name, and it grows only on a miss.

type Reg is Data:
  Reg{open: List<&2, String>}

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

# device.py:31, `assert ALLOW_DEVICE_USAGE or ix.split(":")[0] in
# ["DISK", "NPY", "PYTHON"]`. `ALLOW_DEVICE_USAGE` is an env read so it is a
# parameter; the membership is the decision.
#
# the three comments here used to say "`__getitem__` asserts before it
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

def go_keep(w: Bool, k: Bool) -> U32:
  Bool.pick(U32, Bool.or(w, Bool.not(k)), 1, 0)

def iface_filter(+m: Mk, es: List<&2, AEnt>, +want_mock: Bool, acc: U32) -> U32:
  match es:
    case Nil{}: acc
    case k <> t: iface_filter(m, t, want_mock,
                              U32.add(acc, go_keep(want_mock, bit(m, AEnt.ix(k)))))

# device.py:55, `assert (dev:=next((d for d in self._devices if d not in
# ["DISK","NPY"] and getenv(d) == 1), None)) is None` -- the DEPRECATION assert
# and the only other read of `_devices`. `stems()` is that walk's RESULT.
# TODO(p3) device.py:23  symbol=_Device  -- `_Device._devices`, set in `_Device.__init__`: `pathlib.Path(...).iterdir()`.
#   WALL: a directory read. The seventeen stems are spelled out, so a new
#   `ops_*.py` needs one row in `registry()` and one here.
#
# `NVME` IS THE ROW THIS TABLE WAS MISSING, AND `stem_len` COULD NOT SEE IT.
# MEASURED 2026-11-10, UPSTREAM'S OWN WALK OVER `tinygrad/runtime/`:
#   `[x.stem[len("ops_"):].upper() for x in ...iterdir() if x.stem.startswith("ops_")]`
# -> AMD CL CPU CUDA DISK DSP HIP METAL NPY NULL NV NVME PYTHON QCOM RDMA
#   WEBGPU -- SIXTEEN, AND `NVME` IS ONE OF THEM. The port's table had SIXTEEN
#   ROWS TOO, WITH `BEND` WHERE `NVME` BELONGS, SO `stem_len=16` READ
#   CORRECTLY AND NO ROW COULD SEE THE MISSING ONE. `BEND` IS THE PORT's OWN
#   DEVICE AND IT STAYS -- IT IS THE SEVENTEENTH ROW -- BUT `NVME` IS
#   UPSTREAM'S SIXTEENTH AND IT WAS ABSENT.
#
# THE INDICES ARE THE BITMASK SLOTS: `go_dep` READS `bit(m, AEnt.ix(k))`, SO
# `NVME` IS ADDED AT 17 -- THE END -- AND NO EXISTING SLOT MOVES.
def stems() -> List<&2, AEnt>:
  [AEnt{1, "AMD"}, AEnt{2, "BEND"}, AEnt{3, "CL"}, AEnt{4, "CPU"},
   AEnt{5, "CUDA"}, AEnt{6, "DISK"}, AEnt{7, "DSP"}, AEnt{8, "HIP"},
   AEnt{9, "METAL"}, AEnt{10, "NPY"}, AEnt{11, "NULL"}, AEnt{12, "NV"},
   AEnt{13, "NVME"}, AEnt{14, "PYTHON"}, AEnt{15, "QCOM"}, AEnt{16, "RDMA"},
   AEnt{17, "WEBGPU"}]

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

# THE PROFILE RECORDS, device.py:74-84. Four frozen dataclasses, and the only
# fields any decision in this file reads are `ProfileGraphEntry`'s `st_id` and
# `en_id`, which `collect_prof` RENUMBERS.

type PEnt is Data:
  PEnt{st_id: U32, en_id: U32}

# device.py:508, `replace(e, st_id=2*i, en_id=2*i+1) for i,(_, e) in
# enumerate(es)` -- a batch's timestamps are interleaved into one flat axis,
# start and end, so entry i occupies slots 2i and 2i+1.
def renum(en: U32) -> U32:
  U32.mul(U32.sub(en, 1), 2)

# BUFFERS. `BufferSpec` (device.py:88) is five flags; `external_ptr: int|None`
# is flattened to a Bool because a `Data` record may not hold a `Maybe` field,
# and NOTHING here ever uses the pointer -- only its presence, in
# `Allocator.free` (device.py:280).

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

# device.py:167, `self._storage is not None and (self._base is None or
# self._base_storage is self.base._storage)`. Address 0 is Python's `None`, and
# the second clause is that the view's storage IS the root's.
def is_allocated.go(+b: Bn, same: Bool) -> U32:
  Bool.to_u32(Bool.and(U32.is_ne(Bn.addr(b), 0),
    Bool.or(Bool.not(Bn.has_base(b)), same)))

def is_allocated.bar(+ar: Bar, +b: Bn) -> U32:
  is_allocated.go(b, U32.is_eq(Bn.addr(b), Bn.addr(bar_at(ar, base_of.go(b)))))

# device.py:131-132, the base-case asserts. The device equality is the one a
# cross-device view would trip, and it is why `view` cannot change a device.
def bvalid_base.s(+sb: Bn, +sn: Bn) -> Bool:
  Bool.and(Bool.not(Bn.has_base(sb)), U32.is_eq(Bn.dev(sn), Bn.dev(sb)))

# `Buffer.__init__` appends, so it returns the pair. THE ARENA RULE, and it is
# why `bnew` and `bview` are `Found` and not a bare index: a def that
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

# device.py:189, `GlobalCounters.mem_used += self.nbytes` and the per-device
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

# ALLOCATORS. `Allocator` (device.py:259) is the cache, and the cache has ONE
# policy: `free` recycles a storage when it is reusable and drops it otherwise,
# and `alloc` hands back the MOST RECENTLY freed. That is LIFO, and getting it
# wrong is invisible until it matters, which is why `alloc_take` is a fold.

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

# COMPILERS. `Compiler` (device.py:336) with an empty `compile` -- the NOTE says
# so, and it is the default every backend without a compiler relies on.

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
# TODO(p3) device.py:344  TinyELF.lib -- `bytes`. WALL: a byte buffer. The C
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

# device.py:439, `Buffer(self.device, 2, dtypes.uint64, options=BufferSpec(
# host=True, uncached=True, cpu_access=True), initial_value=bytes(16))`. Two
# elements of eight bytes and sixteen bytes of initial value -- the signal and
# the value the last submitted batch signals. The two agreeing IS the invariant,
# which is why the property is called `timeline`.
def timeline_size() -> U32:
  2

def timeline_bytes() -> U32:
  U32.mul(timeline_size(), S.Dt.itemsize(S.uint64()))

# `Compiled` (device.py:375). The composition, and the numbers every backend
# inherits rather than sets.

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

# `Compiled.link_bufs` (device.py:377) and `Compiled.link_buffer` (device.py:411).
# THE LINK: which PHYSICAL buffer a logical ALLOC belongs to.
#
# what upstream has and what the port had. At the pin (`tinygrad/` is upstream
# 5c2bf39d6c4b) `tinygrad/device.py` carries TWO members and the port carried
# NEITHER:
#
#   device.py:377   link_bufs:dict[str, Any] = {}
#   device.py:411   def link_buffer(self, b:UOp) -> Buffer|None: return None
#
# `link_bufs` is a CLASS attribute: ONE dict for every device, mutated IN PLACE
# by `Compiled.link_bufs |= {...}` at backend-import time. `link_buffer` is a
# PER-DEVICE METHOD whose base-class answer is `None` -- "this device has no
# opinion".
#
# the prior reading was wrong in three ways, and all three are measured:
#
#   1. THERE IS NO `Compiled.tag()`. `rg -n 'def tag|\.tag\(' tinygrad/` at the
#      pin answers ONE line -- `tinygrad/uop/ops.py:269: def tagstr(self)` --
#      and `tag` itself is a FIELD of `UOp.arg` that the MATCHER patterns read
#      (`UPat(Ops.PARAM, tag="timeline")`). It is not a method, and it is not
#      on `Compiled`.
#   2. `link_buffer` AND `link_bufs` ARE NOT CALLED BY `device.py` AT ALL. Their
#      only consumer is `tinygrad/runtime/support/hcq2.py:488-490`, inside
#      `bufferize_buf`.
#   3. neither mutates a kernel's BUFFER list. `link_buffer` is a pure query --
#      a UOp in, a Buffer or None out. `link_bufs` is a dict that `|=` mutates.
#      What CHANGES is the ALLOC's BINDING, and `bufferize_buf` builds a NEW
#      UOp (`UOp.from_buffer(...)`); it does not mutate an existing one.
#
# and the port was porting a function upstream deleted. The `pm_bufferize`
# rule table was upstream's PRE-restructure shape: at the previous
# vendoring `tinygrad/device.py:375` read
#   `pm_bufferize:Any = None # one for all devices: each adds the rules of the
#    placeholders it owns, its tags start with its name`
# and the rules were a `PatternMatcher` that a backend PREPENDED to. At the pin
# that class attribute is GONE and `link_bufs`/`link_buffer` are what is there.
# the table is gone from this port too, so this section is the whole of the
# mechanism: there is no corpse left to carry, and no table below.

# `to_name` (tinygrad/helpers.py:21) -- `"_".join(parts).replace(":", "_").lower()`.
# The fold runs on the JOINED string, not on each part, so a part that is
# already lower-case does not make the whole fold lower-case.
#
# base.bend exports NEITHER `replace` NOR `map`, so this is the character walk,
# and it is `ops_rdma.bend`'s `tname` (:726-740) under another name. THE TWO
# MUST AGREE: the device-scoped registry key is a STRING, so a fold that
# differed by one case would leave every device-scoped entry unfindable while
# every row stayed green.
# TODO(p3) helpers.bend  `to_name` -- upstream keeps it in helpers.py:21, and
#   `ops_rdma.bend` already has the same fold. It belongs in ONE place, and
#   that place is not this file; the hoist is a two-line edit for whoever is
#   allowed to change a second file.
def COLON_C() -> Char: Char.from_u32(58)
def UNDER_C() -> Char: Char.from_u32(95)

def tn.put(+h: Char, +acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, acc, [Bool.pick(Char, Char.is_eq(h, COLON_C()), UNDER_C(), h)])

def tn.go(n: Nat, cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case h <> t: tn.go(m, t, tn.put(h, acc))

def tn(+s: String) -> String:
  String.to_lower(String.from_list(tn.go(List.length(&2, Char, String.to_list(s)), String.to_list(s), Nil{})))

def to_name(parts: List<&2, String>) -> String:
  tn(String.join(parts, "_"))

# ONE registry entry. `kind` is upstream's `isinstance(owned, Buffer)`
# discriminator: 0 is a Buffer, 1 is a CALLABLE that upstream CALLS with the
# alloc (`owned(b)`). `buf` is the ARENA SLOT the entry yields.
type Lk is Data:
  Lk{name: String, kind: U32, buf: U32}

# `dict.get(key)` -- and a dict holds ONE value per key, so a name registered
# TWICE is the LAST registration that wins: `dict.update` OVERWRITES and does
# not append. A first-wins scan finds the OLDER entry and is wrong.
type LkHit is Data:
  LkHit{found: Bool, kind: U32, buf: U32}

# The TWO hits, one per key. A record because a `Data` record may not hold a
# `Maybe` field, and the scan may not scrutinise a computed value.
type LkTwo is Data:
  LkTwo{h1: LkHit, h2: LkHit}

# `Compiled.link_bufs |= {...}` -- `|=` on a dict is `update`: it ADDS a key,
# or OVERWRITES the value under a key that is already there. It mutates the
# CLASS attribute IN PLACE, so the registry is ONE value every device reads,
# and that is why the duplicate rule ("the LAST registration wins") lives in
# the scan and not here.
def link_add(+regs: List<&2, Lk>, +name: String, kind: U32, buf: U32) -> List<&2, Lk>:
  List.append(&2, Lk, regs, [Lk{name, kind, buf}])

# The DEVICE's `link_buffer` answer. `has=False` is the BASE class's answer --
# `def link_buffer(self, b:UOp) -> Buffer|None: return None` (device.py:411) --
# and `has=True` is a backend that owns a buffer for this alloc
# (`ops_null.py:77`, `ops_cl.py:123`, `ops_metal.py:238`).
type Hook is Data:
  Hook{has: Bool, buf: U32}

def link_buffer_base() -> Hook:
  Hook{False{}, 0}

# THE ANSWER. `level` is upstream's four-way:
#   0  the alloc has NO name -> `UOp.new_buffer(...)`: a FRESH buffer, not one
#      that was linked
#   1  the registry, PLAIN name
#   2  the registry, DEVICE-SCOPED name
#   3  the device's `link_buffer`
#   4  nothing: allocate
# `kind` is upstream's `isinstance(owned, Buffer)`: 0 a Buffer, 1 a CALLABLE
# that was called with the alloc, 2 neither.
type LkRes is Data:
  LkRes{level: U32, kind: U32, buf: U32}

def LkRes.level(x: LkRes) -> U32:
  match x:
    case LkRes{level, kind, buf}: level

def LkRes.kind(x: LkRes) -> U32:
  match x:
    case LkRes{level, kind, buf}: kind

def LkRes.buf(x: LkRes) -> U32:
  match x:
    case LkRes{level, kind, buf}: buf

# THE RESOLUTION, upstream's `bufferize_buf` (hcq2.py:483-494) first four lines:
#   if b.arg.name is None: return UOp.new_buffer(b.device, b.max_numel(), b.dtype)
#   owned = Compiled.link_bufs.get(b.arg.name,
#                                  Compiled.link_bufs.get(to_name(b.device, b.arg.name)))
#   if owned is not None: r = owned if isinstance(owned, Buffer) else owned(b)
#   elif (r:=dev.link_buffer(b)) is not None: pass
#   else: ... allocate ...
# The PLAIN name is asked FIRST and the DEVICE-SCOPED name only if it missed,
# and the Buffer-vs-CALLABLE dispatch happens AFTER the two-key lookup -- so a
# callable under the plain name and a Buffer under the device-scoped name are
# BOTH "the registry answered", and the plain one still wins.
#
# the order of the defs is the order of the lookup: the device's own answer
# first (it is the LAST thing asked), then the device-scoped hit, then the
# plain hit, then the scan that produces both hits, then the entry point.

def link_hook(hook: Hook) -> LkRes:
  match hook:
    case Hook{has, buf}:
      match has:
        case True{}: LkRes{3, 2, buf}
        case False{}: LkRes{4, 2, 0}

# The DEVICE-SCOPED hit, which is the registry's second key.
def link_dev(level: U32, h: LkHit, hook: Hook) -> LkRes:
  match h:
    case LkHit{found, kind, buf}:
      match found:
        case True{}: LkRes{U32.add(level, 1), kind, buf}
        case False{}: link_hook(hook)

# The PLAIN hit, which is the registry's FIRST key.
def link_plain(level: U32, h1: LkHit, h2: LkHit, hook: Hook) -> LkRes:
  match h1:
    case LkHit{found, kind, buf}:
      match found:
        case True{}: LkRes{level, kind, buf}
        case False{}: link_dev(level, h2, hook)

def link_two(level: U32, two: LkTwo, hook: Hook) -> LkRes:
  match two:
    case LkTwo{h1, h2}: link_plain(level, h1, h2, hook)

# BOTH registry keys in ONE pass, because the registry is CONSUMED by a scan
# and cannot be scanned twice. `k1` is the PLAIN name and `k2` the
# DEVICE-SCOPED one; both are `+` so they may be READ on every step, and the
# entry's name is `+` for the same reason.
#
# The accumulator is OVERWRITTEN by every match, so the LAST registration of a
# name wins -- which is `dict.update`, and NOT a first-wins scan.
def link_scan.go(es: List<&2, Lk>, +k1: String, +k2: String, a1: LkHit, a2: LkHit) -> LkTwo:
  match es:
    case Nil{}: LkTwo{a1, a2}
    case e <> t:
      match e:
        case Lk{+name, +kind, +buf}:
          link_scan.go(t, k1, k2,
                       Bool.pick(LkHit, String.eq(name, k1), LkHit{True{}, kind, buf}, a1),
                       Bool.pick(LkHit, String.eq(name, k2), LkHit{True{}, kind, buf}, a2))

def link_scan(es: List<&2, Lk>, +k1: String, +k2: String) -> LkTwo:
  link_scan.go(es, k1, k2, LkHit{False{}, 2, 0}, LkHit{False{}, 2, 0})

def link_resolve(regs: List<&2, Lk>, name: Maybe<&2, String>, dev: String, hook: Hook) -> LkRes:
  match name:
    case None{}: LkRes{0, 2, 0}
    case Some{+n}: link_two(1, link_scan(regs, n, to_name([dev, n])), hook)

def lk_ar16(+ar: Bar) -> Bar:
  BFound.ar(bnew(ar, root(7, 16, S.uint8(), spec())))

# The ARENA the link rows measure. Slot 0 is the bottom, 1..6 are the
# registry's sentinels at 64 bytes each and 7 is the device hook's buffer at
# 16 bytes -- the ORACLE's byte counts, because upstream's registry entries
# are Buffers of their OWN size and the link NEVER resizes one to the alloc's.
def lk_ar64.go(n: Nat, +ar: Bar) -> Bar:
  match n:
    case 0n: ar
    case 1n+m: lk_ar64.go(m, BFound.ar(bnew(ar, root(7, 64, S.uint8(), spec()))))

def lk_arena() -> Bar:
  lk_ar16(lk_ar64.go(6n, BFound.ar(bnew(bar_empty(), bar_bot()))))
