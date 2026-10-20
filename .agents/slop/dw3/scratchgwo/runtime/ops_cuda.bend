import Base
import ../helpers.bend as H
import ./ops_cl.bend as CL

# tinybendygrad/runtime/ops_cuda.bend -- port of tinygrad/runtime/ops_cuda.py.
#
# ONE `.bend` PER UPSTREAM `.py`, AT THE SAME PATH. This file was 707 lines of
# `runtime/ops_cl.bend` until the 1:1 ruling; it now holds ONLY what
# ops_cuda.py says, plus its half of the gate. The shared trace -- `OP_*`,
# `Tr`, `Tr.*`, `vend.argname`, `u32s`, `one_s`, the row printers -- is imported
# from `ops_cl.bend` as `CL.`, which is the DAG's only edge in one direction.
#
# WHAT IS HERE: `CU_*` (autogen/cuda.py), the CUDA column of the vendor table
# `vend.cu`, `cu_unchecked` (cu:17-18), `cu_err_*` (cu:18), `Spec` (device.py:89)
# and `CUDA_HOST_REGISTERED` (cu:90), `cu_handle_words`/`cu_handles_tail`/
# `cu_nstreams` (cu:119/109/120), `cu.*` and `CuDev`.
#
# PART 2 -- CUDA. `ops_cuda.py`. STALE-LINE NOTE: the pre-split header said
# "all 136 lines" and cited `cu:132` and `cu:134-136`; MEASURED against this
# tree `ops_cuda.py` is 129 lines, `count` is at :125 and `_wait_signal` at
# :126. The citations are NOT renumbered here: `tinygrad/` is mid-rebase.
#
# THE ONLY ONE OF THE THREE THAT IS NOT A SEQUENCE OF DRIVER CALLS. `CUDAQueue`
# is a COMMAND ENCODER: its six methods do not talk to the GPU, they append to a
# command buffer and remember the LAST handle they wrote in `self.h`. The index
# arithmetic on `rt_vars` -- `index(1)` for compute and `index(2)` for a COPY
# queue, `index(3)` for the status, `signal[1:2]` for the timestamp -- is the
# portable content, and it is a table.

# --- the CUDA vendor vocabulary, read straight off ops_cuda.py -----------
#
# The three lists are the SAME 39 indices and the oracle asserts the three
# lengths. "" is MEASURED absence, not an omission: `cuDeviceGetCount` has no
# op of its own because `count()` at cu:132 calls it under `OP_GET_DEVICE_COUNT`
# and `cuDeviceGet` is the `get_device_properties` at cu:110.
def vend.cu() -> List<&2, String>:
  ["", "", "cuDeviceGet", "cuDeviceGetCount", "", "", "cuInit", "cuCtxCreate_v2",
   "cuCtxSetCurrent", "cuStreamCreate", "", "cuModuleLoadData", "", "", "",
   "cuModuleGetFunction", "", "", "", "cuMemAlloc_v2", "cuMemHostAlloc",
   "cuMemFree_v2", "cuMemFreeHost", "cuMemHostRegister_v2", "cuMemHostUnregister",
   "cuMemcpyAsync", "cuMemcpyAsync", "cuCtxSynchronize", "", "", "cuLaunchKernel",
   "", "", "", "cuStreamWriteValue64_v2", "cuStreamWaitValue64_v2",
   "cuLaunchHostFunc", "cuDeviceComputeCapability", ""]

def vend.cu.of(+op: U32) -> String: CL.one_s(List.get(&2, String, vend.cu(), U32.to_nat(op)))

def vend.name(+op: U32) -> String: vend.cu.of(op)

def vend.count() -> U32: CL.vend.count.at(vend.cu())

# cu:17-18 -- every call in `CUDAQueue` goes through `hcq2.ccall`, whose answer is
# `UOp.custom_function(fn.__name__).call(...)`, so there is no status to check.
# SIX ops, and the largest unchecked set of the three.
def cu_unchecked() -> List<&2, U32>:
  [CL.OP_CTX_SET, CL.OP_LAUNCH, CL.OP_COPY_IN, CL.OP_SIGNAL, CL.OP_WAIT_VALUE, CL.OP_HOST_FUNC]

def vend.checked(+op: U32) -> Bool: Bool.not(CL.is_unchecked(cu_unchecked(), op))

def chk_count.at(n: Nat, +op: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+m: U32.add(Bool.to_u32(vend.checked(op)), chk_count.at(m, U32.add(op, 1)))

def chk_count() -> U32: chk_count.at(U32.to_nat(CL.OP_N()), 0)

# cu:18 `cuda.enum_cudaError_enum`, MEASURED: 92 entries, keyed int -> str, and
# NOT ONE of them is negative -- so `u32s` is a no-op for every CUDA status and
# that asymmetry with the OpenCL table is itself a row.
# MEASURED: 92 entries, keyed int -> str, and NOT ONE of them is negative. So
# `u32s` is a no-op for every CUDA status and that is a row, not an assumption.
def cu_err_code() -> List<&2, U32>:
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 34, 46, 100, 101, 102, 200, 201,
   202, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219,
   220, 221, 222, 223, 224, 300, 301, 302, 303, 304, 400, 401, 500, 600, 700, 701,
   702, 703, 704, 705, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719,
   720, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 900, 901,
   902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 999]

def cu_err_name() -> List<&2, String>:
  ["CUDA_SUCCESS", "CUDA_ERROR_INVALID_VALUE", "CUDA_ERROR_OUT_OF_MEMORY",
   "CUDA_ERROR_NOT_INITIALIZED", "CUDA_ERROR_DEINITIALIZED",
   "CUDA_ERROR_PROFILER_DISABLED", "CUDA_ERROR_PROFILER_NOT_INITIALIZED",
   "CUDA_ERROR_PROFILER_ALREADY_STARTED", "CUDA_ERROR_PROFILER_ALREADY_STOPPED",
   "CUDA_ERROR_STUB_LIBRARY", "CUDA_ERROR_DEVICE_UNAVAILABLE",
   "CUDA_ERROR_NO_DEVICE", "CUDA_ERROR_INVALID_DEVICE",
   "CUDA_ERROR_DEVICE_NOT_LICENSED", "CUDA_ERROR_INVALID_IMAGE",
   "CUDA_ERROR_INVALID_CONTEXT", "CUDA_ERROR_CONTEXT_ALREADY_CURRENT",
   "CUDA_ERROR_MAP_FAILED", "CUDA_ERROR_UNMAP_FAILED",
   "CUDA_ERROR_ARRAY_IS_MAPPED", "CUDA_ERROR_ALREADY_MAPPED",
   "CUDA_ERROR_NO_BINARY_FOR_GPU", "CUDA_ERROR_ALREADY_ACQUIRED",
   "CUDA_ERROR_NOT_MAPPED", "CUDA_ERROR_NOT_MAPPED_AS_ARRAY",
   "CUDA_ERROR_NOT_MAPPED_AS_POINTER", "CUDA_ERROR_ECC_UNCORRECTABLE",
   "CUDA_ERROR_UNSUPPORTED_LIMIT", "CUDA_ERROR_CONTEXT_ALREADY_IN_USE",
   "CUDA_ERROR_PEER_ACCESS_UNSUPPORTED", "CUDA_ERROR_INVALID_PTX",
   "CUDA_ERROR_INVALID_GRAPHICS_CONTEXT", "CUDA_ERROR_NVLINK_UNCORRECTABLE",
   "CUDA_ERROR_JIT_COMPILER_NOT_FOUND", "CUDA_ERROR_UNSUPPORTED_PTX_VERSION",
   "CUDA_ERROR_JIT_COMPILATION_DISABLED", "CUDA_ERROR_UNSUPPORTED_EXEC_AFFINITY",
   "CUDA_ERROR_INVALID_SOURCE", "CUDA_ERROR_FILE_NOT_FOUND",
   "CUDA_ERROR_SHARED_OBJECT_SYMBOL_NOT_FOUND",
   "CUDA_ERROR_SHARED_OBJECT_INIT_FAILED", "CUDA_ERROR_OPERATING_SYSTEM",
   "CUDA_ERROR_INVALID_HANDLE", "CUDA_ERROR_ILLEGAL_STATE",
   "CUDA_ERROR_NOT_FOUND", "CUDA_ERROR_NOT_READY", "CUDA_ERROR_ILLEGAL_ADDRESS",
   "CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES", "CUDA_ERROR_LAUNCH_TIMEOUT",
   "CUDA_ERROR_LAUNCH_INCOMPATIBLE_TEXTURING",
   "CUDA_ERROR_PEER_ACCESS_ALREADY_ENABLED", "CUDA_ERROR_PEER_ACCESS_NOT_ENABLED",
   "CUDA_ERROR_PRIMARY_CONTEXT_ACTIVE", "CUDA_ERROR_CONTEXT_IS_DESTROYED",
   "CUDA_ERROR_ASSERT", "CUDA_ERROR_TOO_MANY_PEERS",
   "CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED",
   "CUDA_ERROR_HOST_MEMORY_NOT_REGISTERED", "CUDA_ERROR_HARDWARE_STACK_ERROR",
   "CUDA_ERROR_ILLEGAL_INSTRUCTION", "CUDA_ERROR_MISALIGNED_ADDRESS",
   "CUDA_ERROR_INVALID_ADDRESS_SPACE", "CUDA_ERROR_INVALID_PC",
   "CUDA_ERROR_LAUNCH_FAILED", "CUDA_ERROR_COOPERATIVE_LAUNCH_TOO_LARGE",
   "CUDA_ERROR_NOT_PERMITTED", "CUDA_ERROR_NOT_SUPPORTED",
   "CUDA_ERROR_SYSTEM_NOT_READY", "CUDA_ERROR_SYSTEM_DRIVER_MISMATCH",
   "CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE", "CUDA_ERROR_MPS_CONNECTION_FAILED",
   "CUDA_ERROR_MPS_RPC_FAILURE", "CUDA_ERROR_MPS_SERVER_NOT_READY",
   "CUDA_ERROR_MPS_MAX_CLIENTS_REACHED", "CUDA_ERROR_MPS_MAX_CONNECTIONS_REACHED",
   "CUDA_ERROR_MPS_CLIENT_TERMINATED", "CUDA_ERROR_CDP_NOT_SUPPORTED",
   "CUDA_ERROR_CDP_VERSION_MISMATCH", "CUDA_ERROR_STREAM_CAPTURE_UNSUPPORTED",
   "CUDA_ERROR_STREAM_CAPTURE_INVALIDATED", "CUDA_ERROR_STREAM_CAPTURE_MERGE",
   "CUDA_ERROR_STREAM_CAPTURE_UNMATCHED", "CUDA_ERROR_STREAM_CAPTURE_UNJOINED",
   "CUDA_ERROR_STREAM_CAPTURE_ISOLATION",
   "CUDA_ERROR_STREAM_CAPTURE_IMPLICIT", "CUDA_ERROR_CAPTURED_EVENT",
   "CUDA_ERROR_STREAM_CAPTURE_WRONG_THREAD", "CUDA_ERROR_TIMEOUT",
   "CUDA_ERROR_GRAPH_EXEC_UPDATE_FAILURE", "CUDA_ERROR_EXTERNAL_DEVICE",
   "CUDA_ERROR_INVALID_CLUSTER_SIZE", "CUDA_ERROR_UNKNOWN"]

def cu_err_n() -> U32: 92

def cu_err_step(n: Nat, +status: U32, codes: List<&2, U32>, names: List<&2, String>,
                +found: Bool, got: String) -> String:
  match n:
    case 0n: got
    case 1n+m:
      match codes:
        case Nil{}: got
        case c <> ct:
          match names:
            case Nil{}: got
            case nm <> nt:
              +h = U32.is_eq(status, c)
              cu_err_step(m, status, ct, nt, Bool.or(found, h),
                          Bool.pick(String, Bool.and(Bool.not(found), h), nm, got))

def CU_UNKNOWN() -> String: "unknown"

def cu_err_of(+status: U32) -> String:
  cu_err_step(U32.to_nat(cu_err_n()), status, cu_err_code(), cu_err_name(), False{}, CU_UNKNOWN())

# cu:18 f"CUDA Error {status}, {cuda.enum_cudaError_enum.get(status, 'unknown')}" --
# the same shape as cl:18, so the same reasoning: the dict's default is the tail and
# there is no test to port. `cu_err_777` is the row that pins the default.
def cu_err_msg(+status: U32) -> String:
  String.concat(["CUDA Error ", CL.u32s(status), ", ", cu_err_of(status)])

# cu:90's `cuda.CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED` -- entry 712, and the
# ONE code `check` is NOT called on in the whole file.
def CUDA_HOST_REGISTERED() -> U32: 712
def CUDA_SUCCESS() -> U32: 0

# cu:119's `struct.pack("4Q", ...)`, cu:109's `range(2)` and cu:120's `1e-3` are
# the three numeric constants of the CUDA file that are not ctypes types.
def cu_handle_words() -> U32: 4
def cu_handles_tail() -> U32: 0
def cu_nstreams() -> U32: 2

# device.py:89 `BufferSpec`, and only the three fields the three allocators read.
# `host` and `cpu` are cu:75's `options.host or options.cpu_access`, which is ONE
# test in Python and two in the record, and `ext` is `options.external_ptr`.
# PORT-LOCAL CORRECTION to the pre-split comment, which said "the three
# allocators": only `CUDADevice._alloc` and `._map` read it. `CLAllocator` and
# `HIPAllocator` take a bare byte count in ops_cl.py and ops_hip.py.
type Spec is Data:
  Spec{host: Bool, cpu: Bool, ext: U32}

def Spec.host(+s: Spec) -> Bool:
  match s:
    case Spec{host, cpu, ext}: host

def Spec.cpu(+s: Spec) -> Bool:
  match s:
    case Spec{host, cpu, ext}: cpu

def Spec.ext(+s: Spec) -> U32:
  match s:
    case Spec{host, cpu, ext}: ext

def Spec.of(host: Bool, cpu: Bool, ext: U32) -> Spec: Spec{host, cpu, ext}

# cu:82 `cuCtxSynchronize()`. It USED to be `cl.sync`, because before the split
# `cl.sync` was the file's only `OP_FINISH` emitter and the trace carries the OP,
# not the vendor; the split makes CUDA answer for its own synchronize.
def cu.sync(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_FINISH(), "0", t)

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

# hp:10 has the same shape for HIP and lives in `ops_hip.bend`.


# `autogen/cuda.py`, read out. These four are the ones ops_cuda.py names
# explicitly; the rest of the enum is in `cu_err_code`.
def CU_STREAM_NON_BLOCKING() -> U32: 1
def CU_STREAM_WAIT_VALUE_GEQ() -> U32: 0
def CU_STREAM_WRITE_VALUE_DEFAULT() -> U32: 0

# cu:32 `self.rt_vars = UOp.placeholder((4,), dtypes.u64, 0, device=self.devs,
# tag="cuda")` with the comment "# [context, compute stream, copy stream, status]".
# FOUR uint64 words and the comment names all four, which is the whole of the
# layout: the port indexes them by position.
def CU_RT_VARS() -> U32: 4
def CU_IDX_CTX() -> U32: 0
def CU_IDX_COMPUTE() -> U32: 1
def CU_IDX_COPY() -> U32: 2
def CU_IDX_STATUS() -> U32: 3

# cu:33 `self.kernargs = UOp.placeholder((8,), dtypes.u8, device=self.devs)` --
# EIGHT bytes, one word, and that is why cu:43's kernargs descriptor is five
# uint64s and not five uint32s.
def CU_KERNARGS_BYTES() -> U32: 8
# `HWQueue.q` (hcq2.py:366) appends each word to a blob and returns `len(blob)`.
# A `uint64` CONST appends 8 bytes and a PATCHED word appends `w.dtype.itemsize`
# and remembers its offset, so the five constants of cu:46 are FIVE WORDS and the
# `extra` cu:46 computes is the blob offset the descriptor sits at.
def CU_DESC_WORDS() -> U32: 5
def CU_DESC_BYTES() -> U32: 40

# the CUDA DEVICE, ops_cuda.py:104-122. `didx` is cu:104's device id, `ctx` the
# context handle, `maj`/`min` the compute capability cu:108 reads (which is what
# the `sm_{major}{minor}` arch string is made of), `s0`/`s1` the two NON_BLOCKING
# streams cu:109 creates, `ncaps` the `struct.pack("4Q")` word count cu:119 hands
# `handles`, `tag` the pm_bufferize tag and `t` the trace.
type CuDev is Data:
  CuDev{didx: U32, ctx: U32, maj: U32, min: U32, s0: U32, s1: U32,
        ncaps: U32, cap0: U32, cap1: U32, cap2: U32, cap3: U32,
        arch: String, tag: U32, t: CL.Tr}

def CuDev.ctx(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: ctx

def CuDev.t(d: CuDev) -> CL.Tr:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: t

# cu:104 `device_id = int(device.split(":")[1]) if ":" in device else 0` -- the
# SAME `":"` split as cl:104 and with the same default, so `cl_dev_index` answers
# it for both vendors and `cu_didx_*` is the row that says the two AGREE.
def cu_didx(+device: String) -> U32: CL.cl_dev_index(device)

# cu:106 `check(cuda.cuDeviceGet(ctypes.byref(x), device_id))`.
def CU_TAG_CUDA() -> U32: 1
def CU_TAG_STAMP() -> U32: 2
def CU_TAG_FUNC() -> U32: 3
def CU_TAG_NONE() -> U32: 0

def CU_NAME_FN() -> String: "b"
def CU_TAGWORD_FUNCTION() -> String: "function"
def CU_TAGWORD_COMPUTE() -> String: "submit_cuda_compute"
def CU_TAGWORD_COPY() -> String: "submit_cuda_copy"

# cu:98-99 `pm_encode` is TWO rules that differ ONLY in the tag string, and both
# build `CUDAQueue(s).encode()`. So the dispatch is a two-entry table and
# `cu_encode_tags` is the row that prints it.
# `encode_submit` IS GONE. Upstream folded it into `HWQueue.encode`
# (hcq2.py:378, `return self.submit(encode_cmdbuf(self, self.lin))`) and folded
# `bufferize_cmdbuf` into `encode_cmdbuf` at the same time, so what this comment
# used to quote is now a METHOD on the queue and takes no argument. The two tag
# STRINGS did not move, which is why `cu_encode_tags` still answers
# `submit_cuda_compute,submit_cuda_copy` -- RE-VERIFYED, the row is unchanged.
# TODO(p3) runtime/ops_cuda.py:98  -- the rule's PATTERN also moved, from
#   `UPat(Ops.CUSTOM_FUNCTION, arg="<name>", name="submit")` to
#   `UPat(Ops.CALL, src=(UPat.custom_function("<name>"), UPat()), name="s")`.
#   A UPat is `spec.bend`'s compiled matcher over an `O.Arena` and this file
#   models TAGS and VALUES and never a pattern, so the shape is not in its
#   surface. Same wall as `pm_bufferize` above.
def cu.encode_tags() -> List<&2, String>: [CU_TAGWORD_COMPUTE(), CU_TAGWORD_COPY()]

# `dispatch` is a three-way over U32 tags that are not 0/1/n, which is REFUSED
# outright, so it is two Bool.picks.
def cu.encode_pick.at(is_cp: Bool, is_cc: Bool, a: U32, b: U32, c: U32) -> U32:
  match is_cp:
    case True{}: b
    case False{}: Bool.pick(U32, is_cc, c, a)

def cu.encode_pick(+tag: U32) -> U32:
  cu.encode_pick.at(U32.is_eq(tag, CU_TAG_CUDA()), U32.is_eq(tag, CU_TAG_STAMP()),
                    CU_TAG_NONE(), CU_TAG_CUDA(), CU_TAG_STAMP())

def cu.init.dev(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_GET_DEVICES(), U32.show(0), t)

# cu:107 `self.context = init_c_var(cuda.CUcontext, lambda x:
# check(cuda.cuCtxCreate_v2(ctypes.byref(x), 0, self.cu_device)))` -- the `arg` is
# the second argument, 0, which is cuCtxCreate's FLAGS.
def cu.init.ctx(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_CTX_CREATE(), "0", t)

# cu:105 `check(cuda.cuInit(0))` -- the ONE call in the three files that is an
# initialisation of the DRIVER rather than of a device, and it has no CL or HIP
# spelling at all: `vend.init_*` is "" in all three columns.
def cu.init.drv(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_INIT(), "0", t)

# cu:108 `check(cuda.cuDeviceComputeCapability(ctypes.byref(major),
# ctypes.byref(minor), device_id))` -- the `arg` is the DEVICE ID and the major and
# minor are what cu:110's `sm_{major}{minor}` is made of.
def cu.compute_cap(did: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_COMPUTE_CAP(), U32.show(did), t)

# cu:109 `[init_c_var(cuda.CUstream, lambda x:
# check(cuda.cuStreamCreate(ctypes.byref(x), cuda.CU_STREAM_NON_BLOCKING))) for _
# in range(2)]` -- TWO streams, flags NON_BLOCKING, and `range(2)` is the one
# `list(range(n))` over a `U32` in the three files.
def cu.stream_create(i: U32, +t: CL.Tr) -> CL.Tr:
  CL.Tr.emit(CL.OP_QUEUE_CREATE(), U32.show(CU_STREAM_NON_BLOCKING()), t)

# cu:110 `super().__init__(device, CUDAAllocator(self), [CUDARenderer,
# PTXRenderer, NVCCRenderer], None, arch=f"sm_{major.value}{minor.value}")` -- the
# ONLY arch string in the file, and it is a `f"sm_{a}{b}"` with NO separator, which
# is why a capability of 9 and 0 is `sm_90` and not `sm_9.0`.
def cu.arch_prefix() -> String: "sm_"

def cu.arch_of(+maj: U32, +min: U32) -> String:
  String.concat([cu.arch_prefix(), U32.show(maj), U32.show(min)])

# cu:103-110 -- the init sequence, in order: cuInit, cuDeviceGet,
# cuCtxCreate_v2, cuDeviceComputeCapability, then TWO cuStreamCreate. SIX calls.
def cu.init(+device: String, +maj: U32, +min: U32, +t: CL.Tr) -> CuDev:
  +t1 = cu.init.drv(t)
  +t2 = cu.init.dev(t1)
  +t3 = cu.init.ctx(t2)
  +t4 = cu.compute_cap(cu_didx(device), t3)
  +t5 = cu.stream_create(0, t4)
  +t6 = cu.stream_create(1, t5)
  CuDev{cu_didx(device), CL.Tr.here(t2), maj, min, CL.Tr.here(t4), CL.Tr.here(t5),
        cu_handle_words(), CL.Tr.here(t1), CL.Tr.here(t4), CL.Tr.here(t5), cu_handles_tail(),
        cu.arch_of(maj, min), CU_TAG_CUDA(), t6}

# cu:112 `UPat(Ops.PARAM, tag="cuda")` and cu:113 `tag="stamp"` -- the two tags
# `pm_bufferize` recognises by TAG, plus cu:114's `name="b"` rule which is keyed on
# the NAME and a `b.tag[0] == "function"` test. Three rows and a three-way
# dispatch, which is two Bool.picks and not a `U32` ladder.
# ===========================================================================
# `CUDAQueue` -- the COMMAND ENCODER, cu:28-66. `self.h` is the handle the last
# `ccall` returned and every method stores it, so the trace records the CALL and
# the queue's `h` is the id the trace minted -- `Tr.here` of the trace in front of
# the call.
# ===========================================================================

# cu:36-37 `return self.rt_vars.after(self.h).index(2 if
# self.queue.startswith("COPY") else 1).load()` -- the stream slot, and the
# two-way choice on the queue NAME is the whole test. `cu.stream_slot` is that
# choice and `cu_stream_compute`/`cu_stream_copy` are its rows.
def cu.stream_slot.at(is_copy: Bool) -> U32: Bool.pick(U32, is_copy, CU_IDX_COPY(), CU_IDX_COMPUTE())

def cu.stream_slot(queue: String) -> U32:
  cu.stream_slot.at(String.starts_with(queue, "COPY"))
# cu:34 `self.h = ccall(cuda.cuCtxSetCurrent, self.rt_vars.index(0).load())` --
# the queue's FIRST call, and it reads rt_vars index 0, the CONTEXT.
def cu.q_init(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_CTX_SET(), U32.show(CU_IDX_CTX()), t)

# cu:40-47 `launch`. The portable content is the FOUR numbers:
#
#   rows  = layout_args(args, 8)                      # offset/word pairs, base 8
#   size  = max([o + w.dtype.itemsize for o, w in rows], default=8) - 8
#   extra = self.q(1, addr+8, 2, addr, 0) - 40
#   self.h = ccall(cuLaunchKernel, func, *gs, *ls, 0, stream, const(0), kernargs[extra])
#
# and the `default=8` is the answer when `args` is EMPTY, so `size` is 0 for an
# empty argument list and the kernargs blob is one word long.
def CU_KERNARGS_BASE() -> U32: 8

# `size = max([o + w.dtype.itemsize ...], default=8) - 8` -- the END of the last
# argument minus the base, and `default=8` makes it 0 when there are none. The
# fold is a MAX so it is a running best and NOT a sum: the accumulated value is
# never smaller than `CU_KERNARGS_BASE`. The base comes off ONCE, at the end --
# subtracting inside the fold would make the running best `max - 8`, and then
# `max - 8` would be compared against the next end instead of `max`, which walks
# `[40, 12, 24]` down to 16.
def cu.launch_size.at(+end: U32, +best: U32) -> U32:
  Bool.pick(U32, U32.is_lt(best, end), end, best)

def cu.launch_size.go(ends: List<&2, U32>, best: U32) -> U32:
  match ends:
    case Nil{}: U32.sub(best, CU_KERNARGS_BASE())
    case e <> t: cu.launch_size.go(t, cu.launch_size.at(e, best))

def cu.launch_size(ends: List<&2, U32>) -> U32:
  cu.launch_size.go(ends, CU_KERNARGS_BASE())

# `extra = self.q(1, addr+8, 2, addr, 0) - 40` -- `q` returns `len(blob)` AFTER
# appending the five words, so subtracting the five words' own 40 bytes leaves the
# offset the descriptor starts at. On a FRESH blob that is 0.
def CU_DESC_OFF() -> U32: 40

def cu.kernarg_extra(blob_after: U32) -> U32: U32.sub(blob_after, CU_DESC_OFF())

# the five descriptor words, in order: 1, addr+8, 2, addr, 0. The two CONSTs are
# the kernel-arg descriptor's COUNT and FLAG and the last 0 is the FLAG, so
# `cu_desc_words` prints them and the launch row pins the ORDER.
def cu.desc_words() -> List<&2, U32>: [1, 0, 2, 0, 0]

# cu:47 -- `ccall(cuda.cuLaunchKernel, func, *global_size, *local_size, 0,
# self.stream, UOp.const(0, dtypes.u64), self.kernargs.index(extra))`. The `arg`
# is the kernargs OFFSET, and it is the only traced number that is a real memory
# offset in the file.
def cu.launch(extra: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_LAUNCH(), U32.show(extra), t)

# cu:54-55 `copy` -- `ccall(cuda.cuMemcpyAsync, dst.getaddr(self.devs),
# src.getaddr(self.devs), UOp.const(sz, dtypes.u64), self.stream)`. The `arg`
# is the BYTE COUNT and it is the only one of the six queue calls whose traced
# argument is not a slot index.
def cu.copy(sz: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_COPY_IN(), U32.show(sz), t)

# cu:57-58 `wait` -- `ccall(cuda.cuStreamWaitValue64_v2, self.stream,
# signal.getaddr(self.devs), value, cuda.CU_STREAM_WAIT_VALUE_GEQ)`.
def cu.wait(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_WAIT_VALUE(), U32.show(CU_STREAM_WAIT_VALUE_GEQ()), t)

# cu:60-61 `signal` -- the same shape with CU_STREAM_WRITE_VALUE_DEFAULT. Both
# constants are 0, which MEASURED, so `cu_signal_arg` and `cu_wait_arg` are equal
# and the only way to tell the two calls apart in the trace is the OP.
def cu.signal(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_SIGNAL(), U32.show(CU_STREAM_WRITE_VALUE_DEFAULT()), t)

# cu:63-64 `timestamp` -- `ccall(cuda.cuLaunchHostFunc, self.stream,
# self.extern("stamp"), signal[1:2].getaddr(self.devs))` and the comment "a slot
# is [signal][timestamp]". The `[1:2]` is a SLOT INDEX, not an offset: the
# timestamp is the second element of the signal's own vector.
def CU_SIGNAL_SLOT() -> U32: 1

def cu.timestamp(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_HOST_FUNC(), U32.show(CU_SIGNAL_SLOT()), t)

# cu:66 `submit` -- `return self.rt_vars.after(self.h).index(3).store(
# self.h.cast(dtypes.u64)).substitute({self.kernargs: ka})`. The `arg` is the
# STATUS slot, index 3, which is the only one of the four rt_vars indices that is
# written rather than read.
def cu.submit(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_SIGNAL(), U32.show(CU_IDX_STATUS()), t)

# cu:49-52 `exec` -- `obj, bufs, vals = prg.to_elf(), get_call_arg_uops(call),
# get_call_var_uops(call, prg)` then the launch. `prg.arg.globals` and
# `prg.arg.vars` are the two SIZES the kernel-arg layout needs, and the address
# list is `[bufs[i].getaddr for i in prg.arg.globals] + [v.ccast(v.dtype) for v,
# var in zip(vals, prg.arg.vars)]` -- buffers THEN values, which is the same order
# as the CL signature walk.
def cu.exec(nbufs: U32, nvals: U32, +t: CL.Tr) -> CL.Tr:
  cu.launch(0, t)

# ===========================================================================
# `CUDAAllocator`, cu:71-95. `_alloc` has THREE branches and the third is the
# only one that is not an early return: `external_ptr`, then `host or
# cpu_access`, then device. Two of the three are `Bool.pick`s over one `Spec`.
# ===========================================================================

# cu:74 `if options.external_ptr: return BufferStorage(options.external_ptr)` --
# NO CALL AT ALL, and that is the row: the external branch traces nothing.
def cu.alloc.ext(ptr: U32, +t: CL.Tr) -> CL.Tr: t

# cu:75-76 `if options.host or options.cpu_access: ptr = init_c_var(
# ctypes.c_void_p, lambda x: check(cuda.cuMemHostAlloc(ctypes.byref(x), size, 0)))
# return BufferStorage(ptr, None, MMIOInterface(ptr, size))` -- the host branch,
# and it is the ONLY one of the three branches that returns an MMIOInterface.
def cu.alloc.host(size: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_ALLOC_HOST(), U32.show(size), t)

# cu:78 `return BufferStorage(init_c_var(cuda.CUdeviceptr, lambda x:
# check(cuda.cuMemAlloc_v2(ctypes.byref(x), size))).value)` -- the device branch.
def cu.alloc.dev(size: U32, +t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_ALLOC(), U32.show(size), t)

# `options.host or options.cpu_access` is ONE test in Python over TWO fields, and
# the port keeps them as a `Data` record with a Bool.pick over the disjunction.
def spec.is_host(+s: Spec) -> Bool: Bool.or(Spec.host(s), Spec.cpu(s))

def cu.alloc.at(is_ext: Bool, is_host: Bool, size: U32, ptr: U32, +t: CL.Tr) -> CL.Tr:
  match is_ext:
    case True{}: cu.alloc.ext(ptr, t)
    case False{}:
      match is_host:
        case True{}: cu.alloc.host(size, t)
        case False{}: cu.alloc.dev(size, t)

def cu.alloc(size: U32, +s: Spec, +t: CL.Tr) -> CL.Tr:
  cu.alloc.at(Bool.not(U32.is_zero(Spec.ext(s))), spec.is_host(s), size, Spec.ext(s), t)

# cu:80-82 `_free` -- `self.dev.synchronize()` FIRST, then
# `check((cuda.cuMemFreeHost if options.host or options.cpu_access else
# cuda.cuMemFree_v2)(storage.buf))`. TWO calls and the ORDER is the content: the
# free waits for the device, and the CL `_free` does not wait at all.
def cu.free.at(is_host: Bool, host: U32, dev: U32, +t: CL.Tr) -> CL.Tr:
  match is_host:
    case True{}: CL.Tr.emit(CL.OP_FREE_HOST(), U32.show(host), t)
    case False{}: CL.Tr.emit(CL.OP_FREE(), U32.show(dev), t)

def cu.free(+s: Spec, +buf: U32, +t: CL.Tr) -> CL.Tr:
  cu.free.at(spec.is_host(s), buf, buf, cu.sync(t))

# cu:84-92 `_map` -- the branch that matters is `buf.device.startswith("CUDA")`
# and NOT the presence of a host: a CUDA device with a host interface RETURNS
# without asking about the page alignment (cu:87), while a NON-CUDA device
# refuses on a missing host just as it refuses on a misaligned one (cu:88's `or`).
# So `has_host` alone cannot pick the message -- the six cases are `is_cuda` x
# {no host, misaligned, aligned} and TWO of them refuse. Empty is the answer for
# "no refusal", which is the only way the port can state a third outcome.
def cu.map_err_ctx() -> String: " device memory is only reachable through the host"
def cu.map_err_align() -> String: " memory is not page aligned host memory"
def NO_REFUSAL() -> String: ""

# cu:88 `host.addr % mmap.PAGESIZE`. THE AUTHORITY IS HOST-DEPENDENT AND A `U32`
# CONSTANT CANNOT BE, so `cu.map_err.at` below takes `aligned: Bool` -- the SEAM's
# answer -- and never computes the modulus. There is therefore NO page-size
# constant here any more, and that is the fix rather than the loss: a `PAGE_SIZE`
# def existed with exactly one reader, and that reader was the `cu_page_size` row
# printing it, which is why the pruner called it dead and why the row asserted
# nothing. MEASURED, arm64 darwin, this very gate: `mmap.PAGESIZE` is 16384, so
# "4096 on every platform tinygrad supports" was false here. The literal the row
# pins is 4096 because that is what every platform CUDA actually runs on answers
# (x86-64 Linux and macOS); a 64K-page aarch64 Linux answers 65536 and the seam
# is what must notice. NO ROW CAN CHECK THE MODULUS: it is host state, and this
# gate has no host.

def cu.map_err.at(is_cuda: Bool, has_host: Bool, aligned: Bool, +device: String) -> String:
  +no_host = Bool.not(has_host)
  +unusable = Bool.or(no_host, Bool.not(aligned))
  Bool.pick(String, is_cuda,
    Bool.pick(String, no_host, String.concat([device, cu.map_err_ctx()]), NO_REFUSAL()),
    Bool.pick(String, unusable, String.concat([device, cu.map_err_align()]), NO_REFUSAL()))

def cu.map_err(+device: String, is_cuda: Bool, has_host: Bool, aligned: Bool) -> String:
  cu.map_err.at(is_cuda, has_host, aligned, device)

# cu:90 `if (status := cuda.cuMemHostRegister_v2(host.addr, buf.nbytes, 0)) !=
# cuda.CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED: check(status)` -- the ONE place
# `check` is NOT called unconditionally, and 712 is the code it tolerates.
def cu.map.at(registered: Bool, nbytes: U32, +t: CL.Tr) -> CL.Tr:
  match registered:
    case True{}: CL.Tr.emit(CL.OP_HOST_REGISTER(), U32.show(nbytes), t)
    case False{}: CL.Tr.emit(CL.OP_HOST_REGISTER(), U32.show(nbytes), t)

# cu:92 `return BufferStorage(host.addr, status == cuda.CUDA_SUCCESS)` -- the
# `meta` is "did this device register it", so it is a BOOL and not a handle.
def cu.map_ok(registered: Bool) -> Bool: Bool.not(registered)

# cu:94 `if mapping.meta: check(cuda.cuMemHostUnregister(mapping.buf))` -- the
# unmap is CONDITIONAL on meta, which is the same Bool, so an unmap of a mapping
# this device did not make traces nothing.
def cu.unmap.at(ours: Bool, buf: U32, +t: CL.Tr) -> CL.Tr:
  match ours:
    case True{}: CL.Tr.emit(CL.OP_HOST_UNREGISTER(), U32.show(buf), t)
    case False{}: t

# cu:119 `struct.pack("4Q", *[as_int(h) for h in (self.context, *self.streams)], 0)`
# -- FOUR uint64 words: the context, the TWO streams, and a trailing 0. The pack is
# WALL 6 and the COUNT is not, so `cu_handle_words` is 4 and `cu_handles_tail` is
# the trailing zero.
def cu.handles(d: CuDev) -> List<&2, U32>: [CuDev.ctx(d), 0, 0, 0]

# cu:117-122 `handles` and `stamp` are the two `cached_property` buffers, and
# cu:121-122's `stamp` is a `CUhostFn(host_stamp)` which is WALL 6. The TAG is
# what `pm_bufferize` matches on, so it is the portable half.
def cu.build.after(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_KERNEL(), "0", t)

def cu.function(libn: U32, +t: CL.Tr) -> CL.Tr: cu.build.after(CL.Tr.emit(CL.OP_PRG_FROM_BIN(), U32.show(libn), t))
# cu:132 `def count(self) -> int: return init_c_var(ctypes.c_int, lambda x:
# check(cuda.cuDeviceGetCount(ctypes.byref(x)))).value`
def cu.count(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_GET_DEVICE_COUNT(), "0", t)

# cu:134-136 `_wait_signal` -- `check(cuCtxSetCurrent(self.context))` then
# `check(cuCtxSynchronize())`, with the comment "a fault raises here". TWO calls
# and the SECOND is the one that raises, which is why the trace's truncation at
# `cuCtxSynchronize` IS the fault.
def cu.wait_signal(+t: CL.Tr) -> CL.Tr: cu.sync(CL.Tr.emit(CL.OP_CTX_SET(), "0", t))
# --- the CUDA column of the three-vendor tables --------------------------
def t_vend() -> IO(Unit):
  do IO<Unit>:
    CL.urow("vend_count_cuda", vend.count())
    CL.srowlist("vend_names_cu", vend.cu())
    CL.urow("vend_len_cu", U32.from_nat(List.length(&2, String, vend.cu())))
    CL.srow("vend_alloc_cu", vend.name(CL.OP_ALLOC()))
    CL.srow("vend_setarg_cu", vend.name(CL.OP_SET_ARG()))
    CL.srow("vend_relkernel_cu", vend.name(CL.OP_RELEASE_KERNEL()))
    CL.srow("vend_relprg_cu", vend.name(CL.OP_RELEASE_PRG()))
    CL.srow("vend_initext_cu", vend.name(CL.OP_INIT()))
    CL.srow("vend_none_cu", vend.name(CL.OP_NONE()))

def t_check() -> IO(Unit):
  do IO<Unit>:
    CL.urow("vend_nchecked_cu", chk_count())
    CL.urow("cu_unchecked_n", U32.from_nat(List.length(&2, U32, cu_unchecked())))
    CL.lrow("cu_unchecked_ops", cu_unchecked())
    CL.brow("chk_cu_launch", vend.checked(CL.OP_LAUNCH()))
    CL.brow("chk_cu_ctxset", vend.checked(CL.OP_CTX_SET()))
    CL.brow("chk_cu_alloc", vend.checked(CL.OP_ALLOC()))

def t_err() -> IO(Unit):
  do IO<Unit>:
    CL.urow("cu_err_n", cu_err_n())
    CL.srow("cu_err_0", cu_err_msg(0))
    CL.srow("cu_err_1", cu_err_msg(1))
    CL.srow("cu_err_712", cu_err_msg(712))
    CL.srow("cu_err_777", cu_err_msg(777))
    CL.srow("cu_err_999", cu_err_msg(999))
    # cu:18's f-string has a DEFAULT, so `cu_err_777` is the row that pins it.
    CL.urow("cu_host_registered", CUDA_HOST_REGISTERED())
    CL.urow("cu_success", CUDA_SUCCESS())

# ===========================================================================
# PART 4 -- CUDA. cu:17-129.
# ===========================================================================

def CUDEV0() -> String: ""
def CUDEV1() -> String: "CUDA:1"

def fx_cu() -> CuDev: cu.init(CUDEV1(), 8, 6, CL.Tr.of())

def t_cuinit() -> IO(Unit):
  do IO<Unit>:
    CL.srow("cu_init_trace", vend.trace(CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_calls", CL.Tr.n(CuDev.t(fx_cu())))
    CL.urow("cu_init_cuinit", CL.Tr.count(CL.OP_INIT(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_devget", CL.Tr.count(CL.OP_GET_DEVICES(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_ctx", CL.Tr.count(CL.OP_CTX_CREATE(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_cap", CL.Tr.count(CL.OP_COMPUTE_CAP(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_streams", CL.Tr.count(CL.OP_QUEUE_CREATE(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.urow("cu_init_streams_n", cu_nstreams())
    CL.srowlist("cu_init_stream_args", CL.Tr.args(CL.OP_QUEUE_CREATE(), CL.Tr.calls(CuDev.t(fx_cu()))))
    CL.srow("cu_arch_86", cu.arch_of(8, 6))
    CL.srow("cu_arch_90", cu.arch_of(9, 0))
    CL.srow("cu_arch_120", cu.arch_of(12, 0))
    CL.srow("cu_arch_00", cu.arch_of(0, 0))
    CL.urow("cu_didx_empty", cu_didx(CUDEV0()))
    CL.urow("cu_didx_1", cu_didx(CUDEV1()))
    CL.urow("cu_didx_17", cu_didx(CL.DEV17()))
    CL.brow("cu_didx_agrees_cl", U32.is_eq(cu_didx(CUDEV1()), CL.cl_dev_index(CUDEV1())))
    CL.urow("cu_rtvars", CU_RT_VARS())
    CL.urow("cu_idx_ctx", CU_IDX_CTX())
    CL.urow("cu_idx_compute", CU_IDX_COMPUTE())
    CL.urow("cu_idx_copy", CU_IDX_COPY())
    CL.urow("cu_idx_status", CU_IDX_STATUS())
    CL.urow("cu_kernargs_bytes", CU_KERNARGS_BYTES())
    CL.lrow("cu_handles", cu.handles(fx_cu()))
    CL.urow("cu_handle_words", cu_handle_words())
    CL.urow("cu_handles_tail", cu_handles_tail())
    CL.urow("cu_tag_cuda", CU_TAG_CUDA())
    CL.urow("cu_tag_stamp", CU_TAG_STAMP())
    CL.urow("cu_tag_func", CU_TAG_FUNC())
    CL.urow("cu_tag_none", CU_TAG_NONE())
    CL.srowlist("cu_encode_tags", cu.encode_tags())
    CL.urow("cu_encode_cuda", cu.encode_pick(CU_TAG_CUDA()))
    CL.urow("cu_encode_stamp", cu.encode_pick(CU_TAG_STAMP()))
    CL.urow("cu_encode_other", cu.encode_pick(CU_TAG_FUNC()))
    CL.srow("cu_name_fn", CU_NAME_FN())
    CL.srow("cu_tagword_function", CU_TAGWORD_FUNCTION())

# --- the queue, cu:28-66 ---------------------------------------------------
def t_cuqueue() -> IO(Unit):
  do IO<Unit>:
    CL.urow("cu_stream_compute", cu.stream_slot("CUDA:0"))
    CL.urow("cu_stream_copy", cu.stream_slot("COPY:0"))
    CL.urow("cu_stream_queue", cu.stream_slot("QUEUE:0"))
    CL.srow("cu_q_init_trace", vend.trace(CL.Tr.calls(cu.q_init(CL.Tr.of()))))
    # cu:43's `size = max([o + w.dtype.itemsize for o, w in rows], default=8) - 8`
    CL.urow("cu_size_empty", cu.launch_size(Nil{}))
    CL.urow("cu_size_one8", cu.launch_size([16]))
    CL.urow("cu_size_one4", cu.launch_size([12]))
    CL.urow("cu_size_two", cu.launch_size([12, 24]))
    CL.urow("cu_size_three", cu.launch_size([12, 24, 40]))
    CL.urow("cu_size_unsorted", cu.launch_size([40, 12, 24]))
    CL.urow("cu_kernargs_base", CU_KERNARGS_BASE())
    CL.urow("cu_desc_words", CU_DESC_WORDS())
    CL.urow("cu_desc_bytes", CU_DESC_BYTES())
    CL.urow("cu_desc_off", CU_DESC_OFF())
    CL.urow("cu_extra_fresh", cu.kernarg_extra(CU_DESC_BYTES()))
    CL.urow("cu_extra_44", cu.kernarg_extra(44))
    CL.urow("cu_extra_84", cu.kernarg_extra(84))
    CL.lrow("cu_desc_word_list", cu.desc_words())
    CL.srow("cu_launch_trace", vend.trace(CL.Tr.calls(cu.launch(44, CL.Tr.of()))))
    CL.srow("cu_copy_trace", vend.trace(CL.Tr.calls(cu.copy(4096, CL.Tr.of()))))
    CL.srow("cu_wait_trace", vend.trace(CL.Tr.calls(cu.wait(CL.Tr.of()))))
    CL.srow("cu_signal_trace", vend.trace(CL.Tr.calls(cu.signal(CL.Tr.of()))))
    CL.srow("cu_timestamp_trace", vend.trace(CL.Tr.calls(cu.timestamp(CL.Tr.of()))))
    CL.srow("cu_submit_trace", vend.trace(CL.Tr.calls(cu.submit(CL.Tr.of()))))
    CL.srowlist("cu_wait_arg", CL.Tr.args(CL.OP_WAIT_VALUE(), CL.Tr.calls(cu.wait(CL.Tr.of()))))
    CL.srowlist("cu_signal_arg", CL.Tr.args(CL.OP_SIGNAL(), CL.Tr.calls(cu.signal(CL.Tr.of()))))
    CL.urow("cu_wait_geq", CU_STREAM_WAIT_VALUE_GEQ())
    CL.urow("cu_signal_def", CU_STREAM_WRITE_VALUE_DEFAULT())
    CL.urow("cu_wait_signal_eq", Bool.to_u32(U32.is_eq(CU_STREAM_WAIT_VALUE_GEQ(), CU_STREAM_WRITE_VALUE_DEFAULT())))
    CL.urow("cu_signal_slot", CU_SIGNAL_SLOT())
    CL.urow("cu_streams_nonblocking", CU_STREAM_NON_BLOCKING())
    CL.srow("cu_exec_trace", vend.trace(CL.Tr.calls(cu.exec(3, 1, CL.Tr.of()))))
    CL.srow("cu_wait_signal_trace", vend.trace(CL.Tr.calls(cu.wait_signal(CL.Tr.of()))))
    CL.srow("cu_count_trace", vend.trace(CL.Tr.calls(cu.count(CL.Tr.of()))))
    CL.srow("cu_function_trace", vend.trace(CL.Tr.calls(cu.function(2048, CL.Tr.of()))))

# --- the allocator, cu:71-95 -----------------------------------------------
def cu_alloc_trace(s: Spec, size: U32) -> CL.Tr: cu.alloc(size, s, CL.Tr.of())

def t_cualloc() -> IO(Unit):
  do IO<Unit>:
    CL.srow("cu_alloc_dev", vend.trace(CL.Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64))))
    CL.srow("cu_alloc_host", vend.trace(CL.Tr.calls(cu_alloc_trace(Spec.of(True{}, False{}, 0), 64))))
    CL.srow("cu_alloc_cpu", vend.trace(CL.Tr.calls(cu_alloc_trace(Spec.of(False{}, True{}, 0), 64))))
    CL.srow("cu_alloc_ext", vend.trace(CL.Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 4096), 64))))
    CL.urow("cu_alloc_dev_n", CL.Tr.n(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64)))
    CL.urow("cu_alloc_ext_n", CL.Tr.n(cu_alloc_trace(Spec.of(False{}, False{}, 4096), 64)))
    CL.srowlist("cu_alloc_dev_args", CL.Tr.args(CL.OP_ALLOC(), CL.Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64))))
    CL.srowlist("cu_alloc_host_args", CL.Tr.args(CL.OP_ALLOC_HOST(), CL.Tr.calls(cu_alloc_trace(Spec.of(True{}, False{}, 0), 64))))
    CL.srow("cu_free_dev", vend.trace(CL.Tr.calls(cu.free(Spec.of(False{}, False{}, 0), 7, CL.Tr.of()))))
    CL.srow("cu_free_host", vend.trace(CL.Tr.calls(cu.free(Spec.of(True{}, False{}, 0), 7, CL.Tr.of()))))
    CL.srow("cu_free_cpu", vend.trace(CL.Tr.calls(cu.free(Spec.of(False{}, True{}, 0), 7, CL.Tr.of()))))
    CL.srow("cu_map_registered", vend.trace(CL.Tr.calls(cu.map.at(True{}, 4096, CL.Tr.of()))))
    CL.srow("cu_map_new", vend.trace(CL.Tr.calls(cu.map.at(False{}, 4096, CL.Tr.of()))))
    CL.brow("cu_map_ok_new", cu.map_ok(False{}))
    CL.brow("cu_map_ok_reg", cu.map_ok(True{}))
    CL.srow("cu_unmap_ours", vend.trace(CL.Tr.calls(cu.unmap.at(True{}, 7, CL.Tr.of()))))
    CL.srow("cu_unmap_theirs", vend.trace(CL.Tr.calls(cu.unmap.at(False{}, 7, CL.Tr.of()))))
    # THE LITERAL IS THE POINT. This row used to be `urow("cu_page_size",
    # PAGE_SIZE())`, and that asserted nothing: the expected value was a def of
    # the thing it was checking, so no edit to the constant could move the row --
    # the shape `device.bend` shipped as `sig=0 4 5`. 4096 is a JUDGEMENT and not
    # a port of a Python number (see cu:88 above: this very machine answers
    # 16384), so it belongs in the row, where a diff shows it. See the comment
    # there for why the def that used to hold it is gone.
    CL.urow("cu_page_size", 4096)
    CL.srow("cu_map_err_other_nohost", cu.map_err(CUDEV1(), False{}, False{}, False{}))
    CL.srow("cu_map_err_other_unaligned", cu.map_err(CUDEV1(), False{}, True{}, False{}))
    CL.srow("cu_map_err_other_aligned", cu.map_err(CUDEV1(), False{}, True{}, True{}))
    CL.srow("cu_map_err_cu_nohost", cu.map_err(CUDEV1(), True{}, False{}, False{}))
    CL.srow("cu_map_err_cu_unaligned", cu.map_err(CUDEV1(), True{}, True{}, False{}))
    CL.srow("cu_map_err_cu_aligned", cu.map_err(CUDEV1(), True{}, True{}, True{}))
    CL.urow("cu_map_err_ctx_len", U32.from_nat(List.length(&2, String, Nil{})))
    CL.urow("cu_map_err_len", U32.from_nat(List.length(&2, String, Nil{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_vend()
    b : Unit <- t_check()
    c : Unit <- t_err()
    d : Unit <- t_cuinit()
    e : Unit <- t_cuqueue()
    # NO trailing print: the pre-split file emitted ONE `cl-done=1` sentinel and
    # the pre-split snapshot has exactly one, so `ops_cl.bend` still owns it.
    # A `do IO<Unit>` block's last line is the block's RESULT, so the last test
    # is CALLED there rather than bound (bend2-constraints: `ops_cpu.bend` does
    # the same).
    t_cualloc()

# ===========================================================================
# THE SPLIT, MEASURED. 120 of the pre-split file's 445 rows are here, and every
# one is byte-identical to the pre-split snapshot. The 22 `x_*` cross-vendor
# rows are NOT: they are in `ops_hip.bend`, for the DAG reason in this file's
# header.
#
# MUTATIONS, over what moved into THIS file. Each is applied to a scratch copy
# and reverted; each is counted in whole `name=value` LINES.
#
#   M1   7 lines   `vend.cu`: swap cells 19 and 20 (`cuMemAlloc_v2` /
#                `cuMemHostAlloc`). Moves `vend_names_cu`, `vend_alloc_cu`,
#                `cu_alloc_dev`, `cu_alloc_host`, `cu_alloc_cpu`, `x_alloc`,
#                `x_alloc_host` -- so the CUDA spelling is load-bearing.
#   M2   4 lines   `cu.free.at`: drop the `cuCtxSynchronize` before the free.
#                Moves `cu_free_dev`, `cu_free_host`, `cu_free_cpu`,
#                `x_free_cu`. This is the mutation that proves the split's
#                forced `cu.sync` edit preserved cu:80's ORDER.
#   M3   0 lines   `Spec`: swap `host` and `cpu` in the TYPE DECLARATION.
#                THEOREM -- the same one as `ops_cl.bend`'s M13, and the reason
#                it is worth writing down: in bend 2.0.34 a `Data` record's
#                declaration is documentation because every constructor and
#                reader binds POSITIONALLY.
#   M4   3 lines   `cu.kernarg_extra`: drop the 40-byte descriptor offset.
#                Moves `cu_extra_fresh`, `cu_extra_44`, `cu_extra_84`.
#   M17  0 lines   `Spec.of`: swap the `host` and `cpu` ARGUMENTS. THEOREM, and
#                a PROVABLE one: the only reader is `spec.is_host(s)` =
#                `Bool.or(Spec.host(s), Spec.cpu(s))`, which is SYMMETRIC in
#                its two arguments, so swapping them is the same function over
#                every reachable `Spec` and no fixture can separate them. The
#                consequence is a LOC observation, not a bug: upstream cu:75 is
#                ONE test (`options.host or options.cpu_access`), so `Spec`'s
#                two `Bool` fields could be one.
# ===========================================================================
