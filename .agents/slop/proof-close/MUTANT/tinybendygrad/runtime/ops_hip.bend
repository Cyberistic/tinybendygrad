import Base
import ../helpers.bend as H
import ./ops_cl.bend as CL
import ./ops_cuda.bend as CU

# tinybendygrad/runtime/ops_hip.bend -- port of tinygrad/runtime/ops_hip.py.
#
# ONE `.bend` PER UPSTREAM `.py`, AT THE SAME PATH. This file was 290 lines of
# `runtime/ops_cl.bend` until the 1:1 ruling. It imports `ops_cl.bend` as `CL.`
# (the shared trace) and `ops_cuda.bend` as `CU.`, and imports neither of them
# back: bend has NO IMPORT CYCLE (MEASURED).
#
# WHY THIS FILE HOLDS THE CROSS-VENDOR GATE, and that is a MEASUREMENT and not a
# preference. `t_cross` is 22 rows that read all three vendors. A reader of
# three files must live in a file that can import all three, and the only such
# file in an acyclic three-file graph is the LAST one -- so `t_cross` and the
# three-vendor columns of `t_vend`/`t_check`/`t_err` live here. A reader asking
# "what does HIP call that CUDA spells differently" finds the whole answer in
# one file instead of three.
#
# WHAT IS HERE: `HP_*`, the HIP column of the vendor table `vend.hp`,
# `hp_unchecked` (hp:16), `hp_err_of` (hp:10), `timing.scale_hp` (hp:57's
# `ret.value * 1e-3`), `iter_sig` (TinyELF.iter_sig, device.py:365), `hp.*` and
# `HpDev`.
#
# PART 3 -- HIP. `ops_hip.py`, all 71 lines.
#
# THE MOST DIFFERENT OF THE THREE and the smallest. Where CL sets one kernel
# argument at a time by pointer and CUDA packs a blob, HIP packs a C STRUCT: hp:39
# builds `c_args` ONCE from `init_c_struct_t` and then assigns `c_args.f{i}` and
# `c_args.v{i}` on every call. The struct's field NAMES and OFFSETS are therefore
# the portable content, and they are what `Arg.off` carries -- `0` for CL,
# `i*8` for HIP, and the `round_up` walk for CUDA.
def hp_offset_sum(buf: U32, offset: U32) -> U32: U32.add(buf, offset)

# hp:57 `ret.value * 1e-3` -- the ms->s divisor, and it is a THIRD scale: the three
# vendors do not agree on a unit, and `timing_ns_scale_bits` beside
# `timing_hp_scale_bits` is the row that says so. `timing.scale` beside it is
# cl:75's nanosecond divisor and lives in `ops_cl.bend`.
def timing.scale_hp() -> F32: 0.001

# --- the HIP vendor vocabulary, read straight off ops_hip.py --------------
def vend.hp() -> List<&2, String>:
  ["", "hipSetDevice", "", "hipGetDeviceCount", "", "hipGetDeviceProperties", "", "",
   "", "hipEventCreate", "", "hipModuleLoadData", "", "", "",
   "hipModuleGetFunction", "", "hipModuleUnload", "", "hipMalloc", "", "hipFree",
   "", "", "", "hipMemcpy", "hipMemcpy", "hipDeviceSynchronize", "", "",
   "hipModuleLaunchKernel", "hipEventSynchronize", "hipEventRecord",
   "hipEventElapsedTime", "", "", "", "", "hipGetErrorString"]

def vend.hp.of(+op: U32) -> String: CL.one_s(List.get(&2, String, vend.hp(), U32.to_nat(op)))

def vend.name(+op: U32) -> String: vend.hp.of(op)

def vend.count() -> U32: CL.vend.count.at(vend.hp())

# hp:16 `hipEventCreate` is the only `hip*` call in the file with no `check`
# around it, and it is the only op the HIP column does not check.
def hp_unchecked() -> List<&2, U32>: [CL.OP_QUEUE_CREATE]

def vend.checked(+op: U32) -> Bool: Bool.not(CL.is_unchecked(hp_unchecked(), op))

def chk_count.at(n: Nat, +op: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+m: U32.add(Bool.to_u32(vend.checked(op)), chk_count.at(m, U32.add(op, 1)))

def chk_count() -> U32: chk_count.at(U32.to_nat(CL.OP_N()), 0)

# hp:10 -- the FUNCTION name is a symbol and is ported; the TEXT it returns is
# WALL 7. `hp_err_of` answers the prefix and the tail is the seam's.
def hp_err_of(status: U32) -> String: String.concat(["HIP Error ", CL.u32s(status), ", "])

def vend.line(+c: CL.Call) -> String:
  String.concat([vend.name(CL.Call.op(c)), "(", CL.Call.arg(c), ")"])

def vend.trace.put(c: CL.Call, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, [vend.line(c)])

def vend.trace.go(cs: List<&2, CL.Call>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case c <> t: vend.trace.go(t, vend.trace.put(c, acc))

def vend.trace(cs: List<&2, CL.Call>) -> String:
  String.join(vend.trace.go(cs, Nil{}), " ")


# ===========================================================================

# hp:41 `[(f'f{i}', hip.hipDeviceptr_t, i*8) for i in range(len(args))] +
# [(f'v{i}', getattr(ctypes, f"c_int{dt.bitsize}"), o) for i,(o,dt) in
# enumerate(TinyELF.iter_sig(self.signature[len(args):], len(args)*8))]`
#
# -- so the BUFFER fields are `f0` at 0, `f1` at 8, `f2` at 16 ... and the VALUE
# fields start at `len(args)*8` and are aligned by `round_up(offset,
# dt.itemsize)`. The 8 is `sizeof(hipDeviceptr_t)`.
def HP_PTR_SZ() -> U32: 8

# hp:42 `init_c_struct_t(fields[-1][2] + ctypes.sizeof(fields[-1][1]) if len(fields)
# else 0, tuple(fields))` -- the struct's SIZE is the last field's OFFSET plus its
# SIZE, and it is 0 for an empty signature. That is `fields[-1][2] + sizeof` and
# NOT `sizeof(last)` alone, which is why the LAST argument's own size is in the
# total.
def hp.cargs_size(last_off: U32, last_sz: U32, n: U32) -> U32:
  Bool.pick(U32, U32.is_zero(n), 0, U32.add(last_off, last_sz))

# device.py:365 `TinyELF.iter_sig(signature, offset)`: `yield (offset :=
# round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`. This is the walk
# hp:41 calls and it is the SAME walk `hcq2.layout_args` calls for CUDA -- so the
# two vendors agree on the alignment rule and differ only in what they do with it.
# It is not in any of the three files, so the local copy names device.py as owner.
def iter_sig.at(off: U32, isz: U32) -> U32: H.round_up_u32(off, isz)

def iter_sig.go(+iszs: List<&2, U32>, +off: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match iszs:
    case Nil{}: acc
    case z <> t:
      +a = iter_sig.at(off, z)
      iter_sig.go(t, U32.add(a, z), List.append(&2, U32, acc, [a]))

def iter_sig(+iszs: List<&2, U32>, off: U32) -> List<&2, U32>: iter_sig.go(iszs, off, Nil{})

# the ALIGNED offsets of the value fields, given the buffer count and the value
# itemsizes. `hp_offsets` is the row and it is the first place the three vendors
# visibly disagree on one signature.
def hp_val_offsets(nargs: U32, +iszs: List<&2, U32>) -> List<&2, U32>:
  iter_sig(iszs, U32.mul(nargs, HP_PTR_SZ()))

# hp:41's `f{i}` OFFSET is `i*8` with no alignment at all, so `hp_buf_offsets` is
# the other half and the two halves together are the struct.
def hp_buf_offsets.go(n: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: hp_buf_offsets.go(m, U32.add(i, 1), List.append(&2, U32, acc, [U32.mul(i, HP_PTR_SZ())]))

def hp_buf_offsets(nargs: Nat) -> List<&2, U32>: hp_buf_offsets.go(nargs, 0, Nil{})

# hp:43-44 `self.vargs = (ctypes.c_void_p * 5)(1,
# ctypes.cast(ctypes.byref(self.c_args), ctypes.c_void_p), 2,
# ctypes.cast(ctypes.pointer(ctypes.c_size_t(ctypes.sizeof(self.c_args))),
# ctypes.c_void_p), 3)` -- FIVE words: the FLAG, the struct address, 2, the struct
# SIZE, and 3. The FLAG and the SIZE are the two that are not the address, and
# `hp_vargs_words` prints all five so the row is the whole descriptor.
def HP_VARGS_WORDS() -> U32: 5
def HP_VARGS_FLAG() -> U32: 1
def HP_VARGS_KIND() -> U32: 2
def HP_VARGS_LAST() -> U32: 3

def hp.vargs_words(size: U32) -> List<&2, U32>:
  [HP_VARGS_FLAG(), 0, HP_VARGS_KIND(), size, HP_VARGS_LAST()]

# hp:42 the struct size, and the field table it comes from is `[f{i}] + [v{i}]`
# with the last field's offset and size.
def hp.last_at.go(+voffs: List<&2, U32>, at: U32) -> U32:
  match voffs:
    case Nil{}: at
    case o <> t: hp.last_at.go(t, o)

def hp.last_at(+voffs: List<&2, U32>) -> U32: hp.last_at.go(voffs, 0)

def hp.last_sz.go(+visz: List<&2, U32>, at: U32) -> U32:
  match visz:
    case Nil{}: at
    case z <> t: hp.last_sz.go(t, z)

def hp.last_sz(+visz: List<&2, U32>) -> U32: hp.last_sz.go(visz, 0)

# hp:42 -- the size is the LAST field's offset plus its size over `f{i}` fields THEN
# `v{i}` fields, so the last field is the last VALUE whenever there is one and is
# the last BUFFER otherwise, and a buffer field is 8 wide, so that arm is `nf*8`.
# `len(fields)` in the conditional is therefore `nv > 0`, not `nf`.
def hp.fields.at(nf: U32, nv: U32, +voffs: List<&2, U32>, +visz: List<&2, U32>) -> U32:
  +n = nv
  Bool.pick(U32, U32.is_zero(n), U32.mul(nf, HP_PTR_SZ()),
    hp.cargs_size(hp.last_at(voffs), hp.last_sz(visz), n))

def hp.fields(nf: Nat, +iszs: List<&2, U32>) -> U32:
  +nf = U32.from_nat(nf)
  hp.fields.at(nf, U32.from_nat(List.length(&2, U32, iszs)), hp_val_offsets(nf, iszs), iszs)

# ===========================================================================
# `HIPDevice`, hp:12-24. THREE calls in `__init__` and one of them is the only
# unchecked call in the whole file.
# ===========================================================================

# the HIP DEVICE, ops_hip.py:14-24. `didx` is hp:14's device id, `arch` hp:15's
# `gcnArchName` -- a STRING straight out of the driver, with NO derivation at all,
# unlike CL's `",".join(exts)` and CUDA's `f"sm_{a}{b}"` -- and `ev0`/`ev1` the two
# events hp:16 creates, `t` the trace.
type HpDev is Data:
  HpDev{didx: U32, arch: String, ev0: U32, ev1: U32, nevents: U32, t: CL.Tr}

def HpDev.didx(d: HpDev) -> U32:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: didx

def HpDev.arch(d: HpDev) -> String:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: arch

def HpDev.t(d: HpDev) -> CL.Tr:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: t

# hp:14 `self.device_id = int(device.split(":")[1]) if ":" in device else 0` --
# the THIRD spelling of that line, and it is the same one: `cu_didx` and
# `cl_dev_index` answer it identically and `hp_didx_*` is the row that says so.
def hp_didx(device: String) -> U32: CL.cl_dev_index(device)

# hp:15 `self.arch = init_c_var(hip.hipDeviceProp_t, lambda x:
# check(hip.hipGetDeviceProperties(x, self.device_id))).gcnArchName.decode()` --
# the `arg` is the device id and the arch is the driver's own STRING.
def hp.props(did: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_GET_DEVICE_PROPS(), U32.show(did), t)

# hp:16 `self.time_event_st, self.time_event_en = [init_c_var(hip.hipEvent_t,
# lambda x: hip.hipEventCreate(ctypes.byref(x), 0)) for _ in range(2)]` -- TWO
# events, flags 0, and NO `check`: this is the single unchecked `hip*` call in the
# three files, which is why `hp_unchecked` is exactly `[OP_QUEUE_CREATE]`.
def hp.event_create(i: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_QUEUE_CREATE(), "0", t)

# hp:23-24 `synchronize` is `check(hip.hipSetDevice(self.device_id))` then
# `check(hip.hipDeviceSynchronize())` -- TWO calls, where CL's is ONE and CUDA's
# is TWO with a different second. `hipDeviceSynchronize` takes NO argument, so its
# arg column is the constant "0" like every other zero-argument call here and NOT
# the device id -- the id is already the arg of the `hipSetDevice` in front of it.
def hp.set_device(did: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_SET_DEVICE(), U32.show(did), t)

def hp.sync(did: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_FINISH(), "0", hp.set_device(did, t))

def hp.device_sync(d: HpDev, +t: CL.Tr) -> CL.Tr: hp.sync(HpDev.didx(d), t)

# hp:20 `def count(self) -> int: return init_c_var(ctypes.c_int, lambda x:
# check(hip.hipGetDeviceCount(x))).value`
def hp.count(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_GET_DEVICE_COUNT(), "0", t)

# hp:14-18 -- the init sequence: hipGetDeviceProperties, TWO hipEventCreate, and
# nothing else. FOUR calls, and the SUPER().__init__ at :18 makes no call.
def hp.init(device: String, arch: String, +t: CL.Tr) -> HpDev:
  +did = hp_didx(device)
  +t1 = hp.props(did, t)
  +t2 = hp.event_create(0, t1)
  +t3 = hp.event_create(1, t2)
  HpDev{did, arch, CL.Tr.here(t2), CL.Tr.here(t3), 2, t3}

# ===========================================================================
# `HIPProgram`, hp:26-57. `__init__` is THREE calls and the FIRST is
# `hipSetDevice`, which CUDA also does per-entry-point and CL does NOT do at all.
# ===========================================================================

# hp:29 `check(hip.hipSetDevice(self.dev.device_id))` -- in `__init__`.
def hp.prog_init.dev(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_SET_DEVICE(), "0", t)

# hp:30-31 `self.module = init_c_var(hip.hipModule_t, lambda x:
# check(hip.hipModuleLoadData(ctypes.byref(x), obj.lib)))` then
# `self.prg = init_c_var(hip.hipFunction_t, lambda x:
# check(hip.hipModuleGetFunction(ctypes.byref(x), self.module, obj.name.encode())))
def hp.prog_init.prg(libn: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_PRG_FROM_BIN(), U32.show(libn), t)

def hp.prog_init.fn(name: String, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_KERNEL(), name, t)

# hp:33-35 `__del__` is `if hasattr(self, 'module'):
# check(hip.hipModuleUnload(self.module))` -- ONE call and ONE attribute, where
# CL's `__del__` is two calls and two attributes. `hp_prog_del_bare` is the row for
# the `hasattr` being False.
def hp.prog_del(have: Bool, +t: CL.Tr) -> CL.Tr:
  match have:
    case True{}: CL.Tr.emit(CL.OP_RELEASE_PRG(), "0", t)
    case False{}: t

# hp:38 `check(hip.hipSetDevice(self.dev.device_id))` -- on EVERY call, which is
# the opposite of CL (once, in __init__) and of CUDA (once, in the queue's
# __init__).
def hp.call_set_device(did: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_SET_DEVICE(), U32.show(did), t)

# hp:49 `if wait: check(hip.hipEventRecord(self.dev.time_event_st, None))` and
# hp:54 the same for `time_event_en`. The `arg` is WHICH event, and it is the only
# way to tell the two apart -- the CL equivalent has two different profiling PARAMS
# for the same reason.
def hp.event_record(which: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_TIME_START(), U32.show(which), t)

# hp:51 `check(hip.hipModuleLaunchKernel(self.prg, *global_size, *local_size, 0,
# None, None, self.vargs))` -- the `arg` is the VARGS STRUCT SIZE, which is the one
# traced number here that is a real byte count.
def hp.launch(cargs_size: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_LAUNCH(), U32.show(cargs_size), t)

# hp:55-56 `check(hip.hipEventSynchronize(self.dev.time_event_en))` then
# `check(hip.hipEventElapsedTime(ctypes.byref(ret), self.dev.time_event_st,
# self.dev.time_event_en))`. TWO calls where CL has THREE, and the elapsed call's
# argument is the pair of EVENTS, not a profiling param.
def hp.event_sync(which: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_WAIT_EVENT(), U32.show(which), t)

def hp.event_elapsed(st: U32, en: U32, +t: CL.Tr) -> CL.Tr:
  CL.Tr.emit(CL.OP_TIME_END(), String.concat([U32.show(st), ":", U32.show(en)]), t)

# hp:39-44 -- the ONCE-ONLY construction of `c_args` and `vargs`. It is guarded by
# `if not hasattr(self, "vargs")`, so it happens on the first call and NOT on the
# second. It MAKES NO CALL -- the struct is built by ctypes, not by the driver --
# so `hp.build.at` returns the trace UNCHANGED on both arms and the gate pins that
# with a count: `hp_call_first_n` and `hp_call_second_n` are EQUAL.
def hp.build.at(built: Bool, +t: CL.Tr) -> CL.Tr:
  match built:
    case True{}: t
    case False{}: t

def hp.record.at(+want: Bool, built: Bool, +t: CL.Tr) -> CL.Tr:
  match want:
    case False{}: hp.build.at(built, t)
    case True{}: hp.event_record(0, hp.build.at(built, t))

def hp.elapsed.at(+want: Bool, +t: CL.Tr) -> CL.Tr:
  match want:
    case False{}: t
    case True{}: hp.event_elapsed(0, 1, hp.event_sync(1, t))

# hp:49-57 -- one call, as the step list it is: set-device, then the once-only
# struct build (no call), then the `if wait:` record, then the launch, then the
# `if wait:` synchronize/elapsed pair. So a non-waiting call is TWO trace entries
# and a waiting one is FIVE.
def hp.call.at(did: U32, cargs: U32, +want: Bool, built: Bool, +t: CL.Tr) -> CL.Tr:
  +t1 = hp.call_set_device(did, t)
  +t2 = hp.record.at(want, built, t1)
  +t3 = hp.launch(cargs, t2)
  hp.elapsed.at(want, t3)

# ===========================================================================
# `HIPAllocator`, hp:59-71. Four methods, and `_offset` is the one that is WALL 6.
# ===========================================================================

# hp:61-62 `_alloc` -- `check(hip.hipSetDevice(self.dev.device_id))` then
# `check(hip.hipMalloc(ctypes.byref(x), size))`. TWO calls, where CL's is ONE and
# CUDA's is one call in each of its three branches.
def hp.alloc(did: U32, size: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_ALLOC(), U32.show(size), hp.call_set_device(did, t))

# hp:64 `_free` -- `check(hip.hipFree(storage.buf))`. ONE call and NO
# `synchronize()`, which is what makes HIP's `_free` differ from CUDA's and agree
# with CL's.
def hp.free(buf: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_FREE(), U32.show(buf), t)

# hipMemcpyKind. MEASURED out of `autogen/hip.py`'s enum: HostToDevice is 1 and
# DeviceToHost is 2, and the two are the ONLY argument HIP's `_copyin` and
# `_copyout` differ on -- the same struct, the same size, two calls.
def HIP_H2D() -> U32: 1
def HIP_D2H() -> U32: 2

# hp:65-67 `_copyin` -- `check(hip.hipSetDevice(self.dev.device_id))` then
# `check(hip.hipMemcpy(dest, mv_address(src), len(src), hip.hipMemcpyHostToDevice))`.
def hp.copyin.at(did: U32, n: U32, +t: CL.Tr) -> CL.Tr:
  CL.Tr.emit(CL.OP_COPY_IN(), U32.show(n), hp.call_set_device(did, t))

def hp.copyin(did: U32, n: U32, +t: CL.Tr) -> CL.Tr: hp.copyin.at(did, n, t)

# hp:68-70 `_copyout` -- `self.dev.synchronize()` FIRST, then
# `check(hip.hipMemcpy(mv_address(dest), src, len(dest), hip.hipMemcpyDeviceToHost))`.
# So HIP copies out DEVICE-TO-HOST after synchronising, and CL copies out after
# synchronising too: the two agree and CUDA does neither.
def hp.copyout.at(did: U32, n: U32, +t: CL.Tr) -> CL.Tr:
  CL.Tr.emit(CL.OP_COPY_OUT(), U32.show(n), hp.device_sync(HpDev{did, "", 0, 0, 2, t}, t))

def hp.copyout(did: U32, n: U32, t: CL.Tr) -> CL.Tr: hp.copyout.at(did, n, t)

# hp:67 / hp:70 -- the memcpy KIND, which is the only thing that differs between the
# two copies, and it is a two-entry table.
def hp.memcpy_kind(is_out: Bool) -> U32: Bool.pick(U32, is_out, HIP_D2H(), HIP_H2D())

# hp:71 `def _offset(self, buf, size, offset): return
# hipDeviceptr_t(buf.value + offset)` -- a POINTER-TYPED SUM, and WALL 6. The
# arithmetic is `buf + offset` and that is what `hp_offset_sum` is; the `U32` it
# returns is the VALUE the pointer holds.
# --- the HIP column of the three-vendor tables ---------------------------
def t_vend() -> IO(Unit):
  do IO<Unit>:
    CL.urow("vend_count_hip", vend.count())
    CL.srowlist("vend_names_hp", vend.hp())
    CL.urow("vend_len_hp", U32.from_nat(List.length(&2, String, vend.hp())))
    CL.srow("vend_alloc_hp", vend.name(CL.OP_ALLOC()))
    CL.srow("vend_setarg_hp", vend.name(CL.OP_SET_ARG()))
    CL.srow("vend_relkernel_hp", vend.name(CL.OP_RELEASE_KERNEL()))
    CL.srow("vend_relprg_hp", vend.name(CL.OP_RELEASE_PRG()))
    CL.srow("vend_initext_hp", vend.name(CL.OP_INIT()))
    CL.srow("vend_errstr_hp", vend.name(CL.OP_ERRSTR()))

def t_check() -> IO(Unit):
  do IO<Unit>:
    CL.urow("vend_nchecked_hp", chk_count())
    CL.urow("hp_unchecked_n", U32.from_nat(List.length(&2, U32, hp_unchecked())))
    CL.lrow("hp_unchecked_ops", hp_unchecked())
    CL.brow("chk_hp_queue", vend.checked(CL.OP_QUEUE_CREATE()))
    CL.brow("chk_hp_launch", vend.checked(CL.OP_LAUNCH()))

def t_err() -> IO(Unit):
  do IO<Unit>:
    CL.srow("hp_err_0", hp_err_of(0))
    CL.srow("hp_err_1", hp_err_of(1))
    CL.srow("hp_err_999", hp_err_of(999))

# hp:57's `ret.value * 1e-3`. It is the HIP file's own timing factor and its
# sibling `timing.scale` is cl:75's nanosecond divisor in `ops_cl.bend`, so the
# row follows the factor: the row was in `ops_cl.bend`'s `t_print` before the
# split and no longer is.
def t_hptiming() -> IO(Unit):
  do IO<Unit>:
    CL.urow("timing_hp_scale_bits", F32.bits(timing.scale_hp()))

# ===========================================================================
# PART 5 -- HIP. hp:9-71.
# ===========================================================================

def HPNAME() -> String: "gfx1100"
def HPDEV0() -> String: ""
def HPDEV2() -> String: "HIP:2"

def fx_hp() -> HpDev: hp.init(HPDEV0(), HPNAME(), CL.Tr.of())

def t_hpinit() -> IO(Unit):
  do IO<Unit>:
    CL.srow("hp_init_trace", vend.trace(CL.Tr.calls(HpDev.t(fx_hp()))))
    CL.urow("hp_init_calls", CL.Tr.n(HpDev.t(fx_hp())))
    CL.urow("hp_init_props", CL.Tr.count(CL.OP_GET_DEVICE_PROPS(), CL.Tr.calls(HpDev.t(fx_hp()))))
    CL.urow("hp_init_events", CL.Tr.count(CL.OP_QUEUE_CREATE(), CL.Tr.calls(HpDev.t(fx_hp()))))
    CL.srowlist("hp_init_event_args", CL.Tr.args(CL.OP_QUEUE_CREATE(), CL.Tr.calls(HpDev.t(fx_hp()))))
    CL.srow("hp_arch", HpDev.arch(fx_hp()))
    CL.urow("hp_nhandles", CL.Tr.next(HpDev.t(fx_hp())))
    CL.urow("hp_didx_empty", hp_didx(HPDEV0()))
    CL.urow("hp_didx_2", hp_didx(HPDEV2()))
    CL.brow("hp_didx_agrees_cl", U32.is_eq(hp_didx(HPDEV2()), CL.cl_dev_index(HPDEV2())))
    CL.srow("hp_sync_trace", vend.trace(CL.Tr.calls(hp.sync(0, CL.Tr.of()))))
    CL.srow("hp_count_trace", vend.trace(CL.Tr.calls(hp.count(CL.Tr.of()))))
    CL.srow("hp_prog_init_trace", vend.trace(CL.Tr.calls(hp.prog_init.fn("k",
      hp.prog_init.prg(128, hp.prog_init.dev(CL.Tr.of()))))))
    CL.srow("hp_prog_del_yes", vend.trace(CL.Tr.calls(hp.prog_del(True{}, CL.Tr.of()))))
    CL.srow("hp_prog_del_no", vend.trace(CL.Tr.calls(hp.prog_del(False{}, CL.Tr.of()))))
    CL.urow("hp_h2d", HIP_H2D())
    CL.urow("hp_d2h", HIP_D2H())
    CL.urow("hp_memcpy_kind_in", hp.memcpy_kind(False{}))
    CL.urow("hp_memcpy_kind_out", hp.memcpy_kind(True{}))
    CL.srow("hp_alloc_trace", vend.trace(CL.Tr.calls(hp.alloc(0, 64, CL.Tr.of()))))
    CL.srow("hp_free_trace", vend.trace(CL.Tr.calls(hp.free(7, CL.Tr.of()))))
    CL.srow("hp_copyin_trace", vend.trace(CL.Tr.calls(hp.copyin(0, 64, CL.Tr.of()))))
    CL.srow("hp_copyout_trace", vend.trace(CL.Tr.calls(hp.copyout(0, 64, CL.Tr.of()))))
    CL.urow("hp_offset_sum", hp_offset_sum(4096, 64))
    CL.urow("hp_offset_sum_0", hp_offset_sum(4096, 0))

# --- the c_args struct, hp:39-44 -- THE THIRD VENDOR'S ARGUMENT LAYOUT -----
def t_hpargs() -> IO(Unit):
  do IO<Unit>:
    CL.urow("hp_ptr_sz", HP_PTR_SZ())
    CL.lrow("hp_buf_offsets_0", hp_buf_offsets(0n))
    CL.lrow("hp_buf_offsets_1", hp_buf_offsets(1n))
    CL.lrow("hp_buf_offsets_3", hp_buf_offsets(3n))
    CL.lrow("hp_val_offsets_3_32", hp_val_offsets(3, [4, 4, 4, 4]))
    CL.lrow("hp_val_offsets_3_mixed", hp_val_offsets(3, [4, 2, 8, 1]))
    CL.lrow("hp_val_offsets_1_mixed", hp_val_offsets(1, [1, 2, 4]))
    CL.lrow("hp_val_offsets_2_odd", hp_val_offsets(2, [2, 4]))
    CL.lrow("hp_val_offsets_0", hp_val_offsets(0, [8]))
    CL.urow("hp_cargs_size_0", hp.cargs_size(0, 0, 0))
    CL.urow("hp_cargs_size_1_0_8", hp.cargs_size(0, 8, 1))
    CL.urow("hp_cargs_size_3_24_4", hp.cargs_size(24, 4, 3))
    CL.urow("hp_cargs_size_3_26_4", hp.cargs_size(26, 4, 3))
    CL.urow("hp_cargs_size_3_32_4", hp.cargs_size(32, 4, 3))
    CL.urow("hp_fields_3_4444", hp.fields(3n, [4, 4, 4, 4]))
    CL.urow("hp_fields_3_mixed", hp.fields(3n, [4, 2, 8, 1]))
    CL.urow("hp_fields_0_empty", hp.fields(0n, Nil{}))
    CL.urow("hp_fields_3_novals", hp.fields(3n, Nil{}))
    CL.urow("hp_fields_0_1val", hp.fields(0n, [4]))
    CL.urow("hp_fields_1_1val", hp.fields(1n, [1]))
    CL.urow("hp_vargs_words", HP_VARGS_WORDS())
    CL.lrow("hp_vargs_list", hp.vargs_words(32))
    CL.srow("hp_call_first_trace", vend.trace(CL.Tr.calls(hp.call.at(0, 32, False{}, False{}, CL.Tr.of()))))
    CL.srow("hp_call_wait_trace", vend.trace(CL.Tr.calls(hp.call.at(0, 32, True{}, False{}, CL.Tr.of()))))
    CL.srow("hp_call_second_trace", vend.trace(CL.Tr.calls(hp.call.at(0, 32, False{}, True{}, CL.Tr.of()))))
    CL.urow("hp_call_first_n", CL.Tr.n(hp.call.at(0, 32, False{}, False{}, CL.Tr.of())))
    CL.urow("hp_call_wait_n", CL.Tr.n(hp.call.at(0, 32, True{}, False{}, CL.Tr.of())))
    CL.urow("hp_call_second_n", CL.Tr.n(hp.call.at(0, 32, False{}, True{}, CL.Tr.of())))
    CL.urow("hp_call_built_eq", Bool.to_u32(U32.is_eq(CL.Tr.n(hp.call.at(0, 32, False{}, False{}, CL.Tr.of())),
                                                CL.Tr.n(hp.call.at(0, 32, False{}, True{}, CL.Tr.of())))))
    CL.srowlist("hp_call_elapsed_args", CL.Tr.args(CL.OP_TIME_END(), CL.Tr.calls(hp.call.at(0, 32, True{}, False{}, CL.Tr.of()))))
    CL.srowlist("hp_call_launch_args", CL.Tr.args(CL.OP_LAUNCH(), CL.Tr.calls(hp.call.at(0, 32, False{}, False{}, CL.Tr.of()))))

# --- 12: the CROSS-VENDOR COMPARISON, which is the content of this file ----
def t_cross() -> IO(Unit):
  do IO<Unit>:
    # THE SAME OPERATION, THREE SPELLINGS: alloc, free, finish, copy-in,
    # copy-out, launch, and the set-context each vendor does.
    CL.srow("x_alloc", String.join([
      CL.vend.name(CL.OP_ALLOC()), CU.vend.name(CL.OP_ALLOC()), vend.name(CL.OP_ALLOC())], "|"))
    CL.srow("x_alloc_host", String.join([
      CL.vend.name(CL.OP_ALLOC_HOST()), CU.vend.name(CL.OP_ALLOC_HOST()),
      vend.name(CL.OP_ALLOC_HOST())], "|"))
    CL.srow("x_free", String.join([
      CL.vend.name(CL.OP_FREE()), CU.vend.name(CL.OP_FREE()), vend.name(CL.OP_FREE())], "|"))
    CL.srow("x_finish", String.join([
      CL.vend.name(CL.OP_FINISH()), CU.vend.name(CL.OP_FINISH()),
      vend.name(CL.OP_FINISH())], "|"))
    CL.srow("x_copyin", String.join([
      CL.vend.name(CL.OP_COPY_IN()), CU.vend.name(CL.OP_COPY_IN()),
      vend.name(CL.OP_COPY_IN())], "|"))
    CL.srow("x_copyout", String.join([
      CL.vend.name(CL.OP_COPY_OUT()), CU.vend.name(CL.OP_COPY_OUT()),
      vend.name(CL.OP_COPY_OUT())], "|"))
    CL.srow("x_launch", String.join([
      CL.vend.name(CL.OP_LAUNCH()), CU.vend.name(CL.OP_LAUNCH()),
      vend.name(CL.OP_LAUNCH())], "|"))
    CL.srow("x_setctx", String.join([
      CL.vend.name(CL.OP_CTX_SET()), CU.vend.name(CL.OP_CTX_SET()),
      vend.name(CL.OP_SET_DEVICE())], "|"))
    CL.srow("x_wait", String.join([
      CL.vend.name(CL.OP_WAIT_EVENT()), CU.vend.name(CL.OP_WAIT_VALUE()),
      vend.name(CL.OP_WAIT_EVENT())], "|"))
    CL.srow("x_time", String.join([
      CL.vend.name(CL.OP_TIME_END()), CU.vend.name(CL.OP_TIME_END()),
      vend.name(CL.OP_TIME_END())], "|"))
    CL.srow("x_arglayout", String.join([
      CL.vend.name(CL.OP_SET_ARG()), CU.vend.name(CL.OP_SET_ARG()),
      vend.name(CL.OP_SET_ARG())], "|"))
    # THE THREE ARCH STRINGS, which are three different derivations of the same
    # `Compiled.__init__` argument.
    CL.srow("x_arch_cl", CL.Dev.arch(CL.fx_img()))
    CL.srow("x_arch_cu", CU.cu.arch_of(8, 6))
    CL.srow("x_arch_hp", HpDev.arch(fx_hp()))
    # THE THREE DEVICE-INDEX SPELLINGS, which agree.
    CL.brow("x_didx_agrees", Bool.and(U32.is_eq(CL.cl_dev_index(CL.DEV2()), CU.cu_didx(CL.DEV2())),
                                   U32.is_eq(hp_didx(CL.DEV2()), CU.cu_didx(CL.DEV2()))))
    # THE THREE `_free`s: CL waits for nothing, CUDA waits then frees, HIP frees
    # and waits for nothing. The three traces say so.
    CL.srow("x_free_cl", CL.vend.trace(CL.Tr.calls(CL.alloc.free(CL.alloc.of(64, CL.Tr.of())))))
    CL.srow("x_free_cu", CU.vend.trace(CL.Tr.calls(CU.cu.free(CU.Spec.of(False{}, False{}, 0), 7, CL.Tr.of()))))
    CL.srow("x_free_hp", vend.trace(CL.Tr.calls(hp.free(7, CL.Tr.of()))))
    # THE THREE `_copyout`s: CL enqueues then finishes, CUDA does neither, HIP
    # finishes then enqueues -- the SAME pair of calls in a DIFFERENT order.
    CL.srow("x_copyout_cl", CL.vend.trace(CL.Tr.calls(CL.copy.copyout(64, CL.Tr.of()))))
    CL.srow("x_copyout_hp", vend.trace(CL.Tr.calls(hp.copyout(0, 64, CL.Tr.of()))))
    CL.srow("x_copyin_cl", CL.vend.trace(CL.Tr.calls(CL.copy.copyin(64, CL.Tr.of()))))
    CL.srow("x_copyin_hp", vend.trace(CL.Tr.calls(hp.copyin(0, 64, CL.Tr.of()))))
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_vend()
    b : Unit <- t_check()
    c : Unit <- t_err()
    d : Unit <- t_hptiming()
    e : Unit <- t_hpinit()
    f : Unit <- t_hpargs()
    # NO trailing print: see the note in `ops_cuda.bend`'s main.
    t_cross()

# ===========================================================================
# THE SPLIT, MEASURED. 96 of the pre-split file's 445 rows are here, all of them
# byte-identical to the pre-split snapshot: the HIP column of
# `t_vend`/`t_check`/`t_err`, `t_hpinit`, `t_hpargs`, `timing_hp_scale_bits`,
# and the 22 `x_*` cross-vendor rows.
#
# MUTATIONS, over what moved into THIS file. Reproduce with
# `.agents/slop/cl_split_mutate.py`.
#
#   M5   4 lines   `vend.hp`: typo a symbol (`hipMalloc` -> `hipMallocX`).
#                Moves `vend_names_hp`, `vend_alloc_hp`, `hp_alloc_trace`,
#                `x_alloc`.
#   M6   3 lines   `hp_err_of`: change the message prefix. Moves `hp_err_0`,
#                `hp_err_1`, `hp_err_999`.
#   M7   2 lines   `vend.checked`: forget `hp_unchecked` (say `hipEventCreate`
#                IS checked). Moves `vend_nchecked_hp`, `chk_hp_queue`. NOT
#                `chk_hp_launch`: `hipModuleLaunchKernel` is checked under both
#                readings, so that row is a CONSTANT against this mutation and
#                not a witness for it.
#   M8   1 line    `timing.scale_hp`: hp:57's `1e-3` -> `1e-2`. Moves
#                `timing_hp_scale_bits` -- the one row that followed the factor
#                out of `ops_cl.bend`'s `t_print`.
#   M9   1 line    `t_cross`: swap the second and third cells of `x_launch`.
#                Moves `x_launch` and nothing else, which is what a row that
#                JOINS three spellings is supposed to do.
#   M14  5 lines   THE TRAP, the tc_ptx unit's exact bug class: rewrite a string
#                LITERAL (`hipModuleLaunchKernel` -> `T.r1_ModuleLaunchKernel`).
#                THE ROW COUNT STAYS 445 and the byte diff catches it:
#                `vend_names_hp`, `hp_call_first_trace`, `hp_call_wait_trace`,
#                `hp_call_second_trace`, `x_launch`. A harness that diffed row
#                NAMES would have reported 0.
# ===========================================================================
