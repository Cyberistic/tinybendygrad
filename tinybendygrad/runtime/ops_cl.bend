# tinybendygrad/runtime/ops_cl.bend -- port of tinygrad/runtime/ops_cl.py (130
# lines), tinygrad/runtime/ops_cuda.py (136) and tinygrad/runtime/ops_hip.py (71)
#
# ONE DEVICE, THREE VENDOR SPELLINGS. `ops_cl.py` is the BASE CLASS for CUDA and
# HIP: `CUDADevice` and `HIPDevice` are both `Compiled`, and `Program.__call__`
# (device.py:372) is the one entry point all three share. So the three files are
# not three backends to be compared -- they are ONE backend whose every operation
# has a CL spelling, a CUDA spelling and a HIP spelling, and most of which are
# NOT the same operation under a different name. `hipMalloc` is `clCreateBuffer`
# is `cuMemAlloc_v2`; but `clSetKernelArg` has NO CUDA spelling at all (CUDA
# packs a kernargs blob) and no HIP spelling either (HIP packs a `c_args`
# struct), and `clReleaseKernel` exists in exactly ONE of the three. That table is
# the content of this file, and `vend` is it.
#
# THE SPLIT, stated once and then obeyed, and it is the rule this unit is judged
# by: a def here EITHER builds the argument of ONE device call (pure, and the
# gate checks it) OR records that call in the trace (and the gate checks the
# ORDER and the IDENTITY). There is no third kind. That is what puts the `raise`
# in the trace: `check(status)` is called after every vendor call, so a refusal
# truncates the trace and no step below needs a guard of its own.
#
# NO @extern SEAMS, and that is a DELIBERATE departure from `dtype.bend`. A
# `@extern` seam is `SOME PROOFS FAIL` plus an import closure that reaches the
# importer's every def, and it buys exactly one thing: a call that is really
# made. What survives the crossing is the STRUCTURE, and the trace IS the
# structure. So each vendor call is a `Call{op, arg}` entry and `vend.name` maps
# it back to the C symbol the seam will call. That keeps `--check-only` GREEN in
# both lanes, which is what lets the gate run at all, and it makes the seam
# greppable: the symbol name is a literal in `vend`, not an opaque body. The seam
# that finally lands replaces `Tr.emit` and nothing else.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. `cl:NN` is ops_cl.py, `cu:NN` ops_cuda.py,
# `hp:NN` ops_hip.py.
#
# ops_cl.py
#   :10-11  CC_CB / BP_CB          WALL 4  CALLBACK SIGNATURES
#   :14     OSX_TIMING_RATIO       PORTED  `timing.ratio`
#   :16     cl_errors              PORTED  `cl_err_code`, `cl_err_of`
#   :17-18  check                  PORTED  `Tr.emit` + `vend.checked`
#   :19     checked                PORTED  `Tr.checked`
#   :22-24  CLCompiler.__init__    PARTIAL `cl.key` (the md5 is WALL 5)
#   :25-37  CLCompiler.compile     PORTED  `comp.compile`
#   :40-47  CLProgram.__init__     PORTED  `prog.init`
#   :49-53  __del__                PORTED  `prog.del`
#   :55-76  __call__               PORTED  `prog.call.at`
#   :79-80  _alloc                 PORTED  `alloc.of`
#   :82-83  _free                  PORTED  `alloc.free`
#   :84-86  _copyin                PORTED  `copy.copyin`
#   :87-89  _copyout               PORTED  `copy.copyout`
#   :93-124 CLDevice.__init__      PORTED  `cl.init`
#   :121-123 the arch suffix       PORTED  `cl.arch_of`
#   :126    count                  PORTED  `cl.count`
#   :128-130 synchronize           PORTED  `cl.sync`
#
# ops_cuda.py
#   :17-18  check                  PORTED  `cu_err_of` + `vend.checked`
#   :20     as_int                 WALL 6  POINTERS
#   :22     host_stamp             WALL 6  POINTERS
#   :23     extern                 WALL 6  POINTERS
#   :30-34  CUDAQueue.__init__     PORTED  `cu.q_init`
#   :36-37  the stream property    PORTED  `cu.stream_slot`
#   :38     extern                 PORTED  `cu.extern_tag`
#   :40-47  launch                 PORTED  `cu.launch`
#   :49-52  exec                   PORTED  `cu.exec`
#   :54-55  copy                   PORTED  `cu.copy`
#   :57-58  wait                   PORTED  `cu.wait`
#   :60-61  signal                 PORTED  `cu.signal`
#   :63-64  timestamp              PORTED  `cu.timestamp`
#   :66     submit                 PORTED  `cu.submit`
#   :72-78  _alloc                 PORTED  `cu.alloc` (all THREE branches)
#   :80-82  _free                  PORTED  `cu.free`
#   :84-92  _map                   PORTED  `cu.map`
#   :93-94  _unmap                 PORTED  `cu.unmap`
#   :98-101 pm_encode              PORTED  `cu.encode_pick`
#   :104-110 __init__              PORTED  `cu.init`
#   :111-115 pm_bufferize          PORTED  `cu.bufferize_pick`
#   :117-122 handles / stamp       PORTED  `cu.handles` (the pack is WALL 6)
#   :124-130 function              PORTED  `cu.function`
#   :132    count                  PORTED  `cu.count`
#   :134-136 _wait_signal          PORTED  `cu.wait_signal`
#
# ops_hip.py
#   :9-10   check                  PARTIAL `hp_err_of` (the STRING is WALL 7)
#   :14-18  HIPDevice.__init__     PORTED  `hp.init`
#   :20     count                  PORTED  `hp.count`
#   :22-24  synchronize            PORTED  `hp.sync`
#   :27-31  HIPProgram.__init__    PORTED  `hp.prog_init`
#   :33-35  __del__                PORTED  `hp.prog_del`
#   :37-57  __call__               PORTED  `hp.call`
#   :60-62  _alloc                 PORTED  `hp.alloc`
#   :64     _free                  PORTED  `hp.free`
#   :65-67  _copyin                PORTED  `hp.copyin`
#   :68-70  _copyout               PORTED  `hp.copyout`
#   :71     _offset                WALL 6  POINTER-ARITHMETIC
#
# ===========================================================================
# THE WALLS, all of them FFI or 64-bit, and NONE of them is the interesting part.
#
# 1. `cl_mem`, `cl_program`, `cl_kernel`, `cl_context`, `CUdeviceptr` and
#    `hipDeviceptr_t` are all POINTERS. Bend has no pointer and `base.bend`
#    exports no `Word`, so every `self.dev` handle, every `BufferStorage.buf` and
#    every `cl_mem` argument becomes a `U32` HANDLE ID minted by the trace. What
#    is gated is the ORDER and the IDENTITY of the calls that produce and consume
#    them, which is the part that is not a pointer.
#    TODO(p3) runtime/ops_cl.py:80   -- clCreateBuffer's cl_mem.
#    TODO(p3) runtime/ops_cuda.py:23  -- extern()'s BufferStorage(ptr, meta).
#    TODO(p3) runtime/ops_hip.py:71   -- _offset returns a hipDeviceptr_t.
#
# 2. THE 64-BIT WALL, and it is three lines of Python.
#      cl:75  `float(end.value-start.value) * OSX_TIMING_RATIO * 1e-9`
#      hp:57  `ret.value * 1e-3`
#      cu:22  `time.perf_counter_ns()`
#    `clGetEventProfilingInfo` answers two `ctypes.c_uint64` timestamps in
#    NANOSECONDS and the delta is u64. `base.bend` exports `Word`, not
#    `Word(64n)`, so the delta is not computable here. `timing.scale` ports the
#    factors that ARE expressible -- the ns->s divisor and the `OSX_TIMING_RATIO`
#    -- and the subtraction is the seam's.
#    TODO(p3) runtime/ops_cl.py:75  -- the u64 nanosecond delta.
#    TODO(p3) runtime/ops_hip.py:57 -- the f32 millisecond elapsed.
#
# 3. `ctypes.create_string_buffer` / `ctypes.string_at` (:29-32, :105-116) are a
#    `(ptr, len)` pair the seam frees as soon as the call returns. The port keeps
#    the decoded String, because the decoded String IS what :106 stores in
#    `self.device_name` and what :100 prints.
#    TODO(p3) runtime/ops_cl.py:29  -- the build-log string buffer.
#    TODO(p3) runtime/ops_cl.py:105 -- the device-info string buffer.
#
# 4. `CC_CB` / `BP_CB` (:10-11) are `CFUNCTYPE` signatures handed as the
#    `pfn_notify` argument of `clCreateContext` and `clBuildProgram`. cl:110
#    passes a fresh `CC_CB()` and cl:27,46 pass `BP_CB()`, and a callback that
#    does nothing is indistinguishable from NULL at the trace level.
#    TODO(p3) runtime/ops_cl.py:10  -- CC_CB / BP_CB.
#
# 5. `hashlib.md5(device_name + driver_version).hexdigest()` (:118) is the
#    compiler cache key. Neither md5 nor a SHA is in Base. The port builds the
#    key's PREFIX and the two concatenated fields, which is everything about the
#    key except the digest, and the digest is the seam's.
#    TODO(p3) runtime/ops_cl.py:118 -- the md5 digest.
#
# 6. POINTER ARITHMETIC and `ctypes.byref`/`addressof`. cl:58's
#    `getattr(ctypes, f"c_int{dt.bitsize}")(vals[...])` is a VALUE boxed into a
#    1/2/4/8-byte ctypes int and passed BY REFERENCE to `clSetKernelArg`; that is
#    why the port carries `Sig.bits` as a `U32` and lets the seam do the box.
#    The ctypes TYPE NAME is portable and is ported exactly -- `ct.typename` is a
#    real table and a real gate row, and it is the one part of this that is
#    compared string-for-string against CPython.
#
# 7. `ctypes.string_at(hip.hipGetErrorString(status)).decode()` (hp:10). The
#    FUNCTION is a symbol and the port names it (`vend.hp.of(OP_ERRSTR)`); the
#    STRING it returns is data the port cannot produce, because calling it needs
#    a live HIP runtime. `hp_err_of` therefore answers the PREFIX
#    `HIP Error <status>, ` and the tail is the seam's.
#    THIS WALL USED TO BE BIGGER AND WAS WRONG ABOUT IT. It claimed that
#    `import tinygrad.runtime.autogen.hip` raises "failed to load library hip"
#    on this machine, and therefore that there was no oracle for the 1277 `hip*`
#    symbols. MEASURED, arm64 darwin: the import SUCCEEDS, all 1277 symbols
#    resolve, and `hipMemcpyHostToDevice`/`hipMemcpyDeviceToHost` answer 1 and 2
#    by `getattr` -- so `HIP_H2D` and `HIP_D2H` and every `vend.hp` cell DO have
#    an oracle and this file's constants were checked against it. Only a real
#    CALL fails, and a real call needs a device. The oracle is
#    `.agents/slop/cl_constmap.py`, which imports autogen.hip and asserts
#    `getattr` for both memcpy kinds.
#    TODO(p3) runtime/ops_hip.py:10 -- hipGetErrorString's text.
#
# WHAT IS NOT A WALL, because it is DATA and is ported:
#   `cl_errors` (:16) is a dict over the autogen module and CPython evaluates it
#   with NO GPU present -- MEASURED, and the subtlety is that it is keyed by the
#   VALUE, so 74 `CL_*` names collapse to 63 codes and the survivor of a shared
#   code is the alphabetically LAST name. See THE ERROR TABLES.
#   `cuda.enum_cudaError_enum` (cu:18) is likewise a plain dict, MEASURED, 92
#   entries, keyed int -> str, and cu:90's
#   `status == CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED` is entry 712 of it.
#
# ===========================================================================
# THE ERROR TABLES, :16 and cu:18 and hp:10, which are the three `check`s.
#
# `cl_errors = {attr: k for k in dir(cl) if k.startswith("CL_") and isinstance(
# attr:=getattr(cl, k), int) and attr <= 0}` is keyed by the ATTRIBUTE, i.e. by
# the CODE, so `cl_errors.get(status)` is code -> NAME. MEASURED on this machine:
# 74 names carry a value <= 0 and there are 63 distinct values, so 11 names are
# aliases that this comprehension THROWS AWAY, and for the four shared codes the
# survivor is the alphabetically LAST of them:
#
#   code   names in dir() order                          the survivor
#   0      CL_BUILD_SUCCESS, CL_COMPLETE, CL_DEVICE_PARTITION_BY_COUNTS_LIST_END,
#          CL_FALSE, CL_KERNEL_ARG_TYPE_NONE, CL_NONE, CL_NON_BLOCKING,
#          CL_PROGRAM_BINARY_TYPE_NONE, CL_SUCCESS       CL_SUCCESS
#   -1     CL_BUILD_NONE, CL_DEVICE_NOT_FOUND            CL_DEVICE_NOT_FOUND
#   -2     CL_BUILD_ERROR, CL_DEVICE_NOT_AVAILABLE       CL_DEVICE_NOT_AVAILABLE
#   -3     CL_BUILD_IN_PROGRESS, CL_COMPILER_NOT_AVAILABLE CL_COMPILER_NOT_AVAILABLE
#
# and the 59 codes with a single name are the other 59 entries. `cl_err_code` is
# that table's key column and `cl_err_name` its value column; the codes are
# stored as `U32` two's complement because Bend has no signed integer, so `-1` is
# `4294967295` and `cl_err_msg` has to PUT THE SIGN BACK to spell the same string
# CPython's f-string spells. `cl_err_of` is the `.get(status, 'Unknown error')`.
#
# `cuda.enum_cudaError_enum` (cu:18) is the same shape with a lower-case default,
# `'unknown'`, 92 entries, and NOT ONE negative code -- so the CUDA message needs
# no sign repair and that asymmetry between the two spellings is itself a row.
# `hipGetErrorString` is WALL 7.
#
# ===========================================================================
# WHAT device.bend AND cstyle.bend OWE THIS FILE. Named, because this file
# cannot be checked without them and does not pretend otherwise.
#
# device.bend owes:
#   1. `Buffer` is a SLOT in an arena and `nbytes` is NOT a field -- it is
#      `size * itemsize`, so the two cannot disagree. `Buf.size` here is the
#      ALLOCATED byte count and `Arg.size` is the per-argument byte count, and
#      cl:60's `pitch` multiplies a shape extent by `4 * dt.itemsize`, which is
#      the same arithmetic read at a different place.
#   2. The Allocator. `CLAllocator` is `Allocator['CLDevice']` and its four
#      methods are `_alloc`/`_free`/`_copyin`/`_copyout`. `_copyout` CALLS
#      `self.dev.synchronize()` and `_copyin` does NOT -- that asymmetry is
#      `copy.copyin` / `copy.copyout` and it is two rows in the gate.
#   3. `TinyELF.signature` is `tuple[(name, slot, DType, shape)]` and
#      `TinyELF.iter_sig` (device.py:365) is the `round_up(offset, dt.itemsize)`
#      walk. hp:41 calls it, and so does `hcq2.layout_args` for CUDA -- the SAME
#      walk in two of the three vendors. `iter_sig` is not in any of the three
#      files, so this file carries a local copy with device.py named as owner.
#   4. `Compiled.__init__` is handed `arch` at cl:124 / cu:110 / hp:18, and the
#      three arch strings are three different derivations of the same argument:
#      the OpenCL extension list (+ `IMAGE_PITCH_ALIGNMENT=`), `sm_{maj}{min}`,
#      and `gcnArchName`. `vend.arch_*` is that comparison.
#   5. `Program.__call__` is called from engine/realize.py with `bufs` resolved
#      and `vals` = `ProgramInfo.vals`. THIS FILE NEEDS THE BUFFER LIST AND THE
#      VAL COUNT AND NOTHING ELSE.
#
# cstyle.bend owes, and this is the interesting half:
#   1. `OpenCLRenderer` (cstyle.py:348) is the renderer cl:124 registers. Its
#      kernel text names the arguments `data0_4, data1_4` in BUFFER ORDER, and
#      cl:57's `for i, (_, slot, dt, shape) in enumerate(self.signature)` walks
#      the SAME order. So `clSetKernelArg(kernel, i, ...)` with `i` the ENUMERATE
#      INDEX is what binds `data0_4` -- NOT the slot. `Arg` carries both `i` and
#      `slot` and `cl_call_args_skew` is the row that pins that they differ.
#   2. `{2:cl.CL_HALF_FLOAT, 4:cl.CL_FLOAT}[dt.itemsize]` at cl:61 is keyed on
#      the ITEMSIZE and not on the dtype, so a dtype of 2 bytes is HALF and 4
#      bytes is FLOAT regardless of signedness. `img.fmt_of` is that table and it
#      is a two-entry table, which is what makes it gateable at all.
#   3. `is_image_shape(shape)` (helpers.py:37) is `shape is not None and
#      len(shape) == 3 and shape[-1] == 4` -- the LAST dim is 4, not the first.
#      `img.is_image` is that and the gate has a fixture whose image is 4 in the
#      LAST dim beside one that is 4 in the FIRST dim.
#
# ===========================================================================
# NO OpenCL, CUDA OR HIP IN THIS ENV. `Device['OPENCL']` needs a loader and no
# HIP runtime is installed here, so NOTHING below was measured against a live
# device. Every constant was READ OUT OF `tinygrad/runtime/autogen/*.py` -- and
# all THREE of those modules import on this machine, `hip` included, so all three
# are oracles (see WALL 7) -- every error-table row was MEASURED by evaluating
# the comprehension in CPython with no device present, and every other row's
# expectation is derived from the source text of the three files.
import Base
import ../helpers.bend as H

# ===========================================================================
# PART 0 -- THE VENDOR TABLE. `vend.name(vendor, op)` is one of the three
# spellings of `op`, and `""` means THIS VENDOR HAS NO SPELLING, which is itself
# a gateable fact and the reason this file is worth having.
#
# `vend.argname(op)` says what the trace's `arg` column MEANS for that op. There
# is deliberately no other per-op argument in the trace: every usage flag, offset
# and size is a pure function with its own row.
# ===========================================================================

def V_CL() -> U32: 0
def V_CUDA() -> U32: 1
def V_HIP() -> U32: 2

def OP_NONE() -> U32: 0
def OP_SET_DEVICE() -> U32: 1
def OP_GET_DEVICES() -> U32: 2
def OP_GET_DEVICE_COUNT() -> U32: 3
def OP_GET_DEVICE_INFO() -> U32: 4
def OP_GET_DEVICE_PROPS() -> U32: 5
def OP_INIT() -> U32: 6
def OP_CTX_CREATE() -> U32: 7
def OP_CTX_SET() -> U32: 8
def OP_QUEUE_CREATE() -> U32: 9
def OP_PRG_FROM_SRC() -> U32: 10
def OP_PRG_FROM_BIN() -> U32: 11
def OP_BUILD() -> U32: 12
def OP_BUILD_LOG() -> U32: 13
def OP_PRG_INFO() -> U32: 14
def OP_KERNEL() -> U32: 15
def OP_RELEASE_KERNEL() -> U32: 16
def OP_RELEASE_PRG() -> U32: 17
def OP_PLATFORMS() -> U32: 18
def OP_ALLOC() -> U32: 19
def OP_ALLOC_HOST() -> U32: 20
def OP_FREE() -> U32: 21
def OP_FREE_HOST() -> U32: 22
def OP_HOST_REGISTER() -> U32: 23
def OP_HOST_UNREGISTER() -> U32: 24
def OP_COPY_IN() -> U32: 25
def OP_COPY_OUT() -> U32: 26
def OP_FINISH() -> U32: 27
def OP_IMAGE() -> U32: 28
def OP_SET_ARG() -> U32: 29
def OP_LAUNCH() -> U32: 30
def OP_WAIT_EVENT() -> U32: 31
def OP_TIME_START() -> U32: 32
def OP_TIME_END() -> U32: 33
def OP_SIGNAL() -> U32: 34
def OP_WAIT_VALUE() -> U32: 35
def OP_HOST_FUNC() -> U32: 36
def OP_COMPUTE_CAP() -> U32: 37
def OP_ERRSTR() -> U32: 38
def OP_N() -> U32: 39

# every spelling the three files use, indexed by op. Read straight off the three
# source files; "" is MEASURED absence, not an omission in this table. The three
# lists are the SAME 39 indices and the oracle asserts the three lengths. Module
# load is `OP_PRG_FROM_BIN` = 11 in ALL THREE (`clCreateProgramWithBinary`,
# `cuModuleLoadData`, `hipModuleLoadData`); `OP_BUILD` = 12 has NO CUDA or HIP
# spelling because a module load IS their build, so 11 and 12 are where a
# transposing table is wrong and the gate prints all three lists.
def vend.cl() -> List<&2, String>:
  ["", "", "clGetDeviceIDs", "", "clGetDeviceInfo", "", "", "clCreateContext", "",
   "clCreateCommandQueue", "clCreateProgramWithSource", "clCreateProgramWithBinary",
   "clBuildProgram", "clGetProgramBuildInfo", "clGetProgramInfo", "clCreateKernel",
   "clReleaseKernel", "clReleaseProgram", "clGetPlatformIDs", "clCreateBuffer",
   "", "clReleaseMemObject", "", "", "", "clEnqueueWriteBuffer",
   "clEnqueueReadBuffer", "clFinish", "clCreateImage", "clSetKernelArg",
   "clEnqueueNDRangeKernel", "clWaitForEvents", "", "clGetEventProfilingInfo", "",
   "", "", "", ""]

def vend.cu() -> List<&2, String>:
  ["", "", "cuDeviceGet", "cuDeviceGetCount", "", "", "cuInit", "cuCtxCreate_v2",
   "cuCtxSetCurrent", "cuStreamCreate", "", "cuModuleLoadData", "", "", "",
   "cuModuleGetFunction", "", "", "", "cuMemAlloc_v2", "cuMemHostAlloc",
   "cuMemFree_v2", "cuMemFreeHost", "cuMemHostRegister_v2", "cuMemHostUnregister",
   "cuMemcpyAsync", "cuMemcpyAsync", "cuCtxSynchronize", "", "", "cuLaunchKernel",
   "", "", "", "cuStreamWriteValue64_v2", "cuStreamWaitValue64_v2",
   "cuLaunchHostFunc", "cuDeviceComputeCapability", ""]

def vend.hp() -> List<&2, String>:
  ["", "hipSetDevice", "", "hipGetDeviceCount", "", "hipGetDeviceProperties", "", "",
   "", "hipEventCreate", "", "hipModuleLoadData", "", "", "",
   "hipModuleGetFunction", "", "hipModuleUnload", "", "hipMalloc", "", "hipFree",
   "", "", "", "hipMemcpy", "hipMemcpy", "hipDeviceSynchronize", "", "",
   "hipModuleLaunchKernel", "hipEventSynchronize", "hipEventRecord",
   "hipEventElapsedTime", "", "", "", "", "hipGetErrorString"]

def vend.argname() -> List<&2, String>:
  ["", "device id", "device count", "device count", "info param", "props ptr",
   "", "context", "", "queue kind", "source", "binary", "build options",
   "build param", "program param", "kernel name", "", "", "num platforms",
   "size", "size", "", "", "size", "size", "size", "size", "queue", "queue",
   "arg index", "work dims", "event count", "", "profiling param", "signal value",
   "value", "slot", "major", "function"]

# `List.get` answers a Maybe and a `match` may not scrutinise a CALL, so every
# positional read goes through this total wrapper. "-" and 0 are what an
# out-of-range index answers, and the gate pins both.
def one_s(+m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def one_u(+m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{s}: s
    case None{}: 0

def vend.cl.of(+op: U32) -> String: one_s(List.get(&2, String, vend.cl(), U32.to_nat(op)))

def vend.cu.of(+op: U32) -> String: one_s(List.get(&2, String, vend.cu(), U32.to_nat(op)))

def vend.hp.of(+op: U32) -> String: one_s(List.get(&2, String, vend.hp(), U32.to_nat(op)))

# the three-way choice, as two Bool.picks: a `U32` ladder over tags that are not
# 0/1/n is refused outright ("a declared constructor (unknown: U32)"), and
# bend2-constraints rule 34 at line 4982 is the note on it.
def vend.name.at(is_cu: Bool, is_hp: Bool, +a: String, b: String, +c: String) -> String:
  match is_cu:
    case True{}: b
    case False{}: Bool.pick(String, is_hp, c, a)

def vend.name(+v: U32, +op: U32) -> String:
  vend.name.at(U32.is_eq(v, V_CUDA()), U32.is_eq(v, V_HIP()),
               vend.cl.of(op), vend.cu.of(op), vend.hp.of(op))

# how many of the 39 ops each vendor actually has a spelling for. This is the
# numeric form of "one device, three vendor spellings" and it is the row that
# dies if a name is misspelled or an "" is put where a symbol exists. The LIST is
# the terminator, not a `Nat` fuel: `case 1n+p` is a first-match prefix that hands
# back `p = k - 1` (MEASURED), so a fuel-driven fold works but a list-driven one
# cannot run out of fuel before the table does.
def vend.count.at(xs: List<&2, String>) -> U32:
  match xs:
    case Nil{}: 0
    case h <> t: U32.add(Bool.to_u32(Bool.not(String.eq(h, ""))), vend.count.at(t))

def vend.count(+v: U32) -> U32:
  vend.count.at(Bool.pick(List<&2, String>, U32.is_eq(v, V_CUDA()), vend.cu(),
    Bool.pick(List<&2, String>, U32.is_eq(v, V_HIP()), vend.hp(), vend.cl())))

# ===========================================================================
# THE CHECK TABLE, which is the other half of `check` and the only part of it
# that is PORTABLE. `vend.checked(v, op)` is False exactly where the call's
# status is DISCARDED, and there are three such places and they are per VENDOR:
#
#   CUDA : every call in CUDAQueue goes through `hcq2.ccall`, whose answer is
#          `UOp.custom_function(fn.__name__).call(...)` -- there is no status to
#          check, because the port has not lowered the call yet. That is SIX ops
#          and it is the largest unchecked set of the three.
#   HIP  : exactly one, `hipEventCreate` at hp:16, which is the only `hip*` call
#          in the three files with no `check` around it.
#   CL   : none AT THE OP LEVEL. Three cl* calls are unchecked at a SITE --
#          the value-returning `clGetDeviceInfo` at cl:105/107/114 whose status is
#          `(…, buf.value.decode())[1]`, the build-log reads at cl:29/30, and the
#          device PROBE at cl:98 whose status is compared against 0 instead.
#          Those are three facts with their own rows, because "cl is checked" is
#          otherwise a claim the gate cannot see.
# ===========================================================================

def cl_unchecked() -> List<&2, U32>: Nil{}

def cu_unchecked() -> List<&2, U32>:
  [OP_CTX_SET, OP_LAUNCH, OP_COPY_IN, OP_SIGNAL, OP_WAIT_VALUE, OP_HOST_FUNC]

def hp_unchecked() -> List<&2, U32>: [OP_QUEUE_CREATE]

def is_unchecked(+xs: List<&2, U32>, +op: U32) -> Bool: List.contains(~U32, ~U32.is_eq, xs, op)

# cl:98 `err = cl.clGetDeviceIDs(platform_ids[0], device_type, 0, None, num_devices)`
# -- the PROBE, whose status is compared to 0 and then forgotten. The real call
# at cl:102 IS checked.
def cl_probe_checked() -> Bool: False{}

# cl:105, :107, :114 -- `(cl.clGetDeviceInfo(...), buf.value.decode())[1]`.
# Three sites, one shape: the status is dropped on the floor.
def cl_info_checked() -> Bool: False{}

# cl:29-30 -- the build log is read twice, unchecked, and the raise at :32 is a
# `CompileError`, not a `RuntimeError` from `check`.
def cl_build_log_checked() -> Bool: False{}

def vend.checked(+v: U32, +op: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(v, V_CL()), Bool.not(is_unchecked(cl_unchecked(), op)),
    Bool.pick(Bool, U32.is_eq(v, V_CUDA()), Bool.not(is_unchecked(cu_unchecked(), op)),
      Bool.not(is_unchecked(hp_unchecked(), op))))

# how many of the 39 ops each vendor CHECKS. CL checks all 39 at the op level,
# CUDA 33 and HIP 38, and those three numbers are the compact form of the table.
# A `U32` HAS NO CONSTRUCTORS, so the walk counts in `Nat` and carries the op
# index as a `+U32` that grows from zero (bend2-constraints rule 34, line 4982).
def chk_count.at(n: Nat, +v: U32, +op: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+m: U32.add(Bool.to_u32(vend.checked(v, op)), chk_count.at(m, v, U32.add(op, 1)))

def chk_count(v: U32) -> U32: chk_count.at(U32.to_nat(OP_N()), v, 0)

# ===========================================================================
# INTEGER PRINTING. `u32s` is CPython's `str()` of an `i32`: a `U32` above
# 2^31-1 is negative and gets a minus sign and a complemented magnitude. Bend has
# no signed integer, so this is the ONE place in the file that has to put the
# sign back, and it is gated as a STRING against CPython's `str()` for a negative
# CL code AND for a positive CUDA code -- the asymmetry between the two tables is
# itself the row.
# ===========================================================================

def digits() -> List<&2, String>:
  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

def dgt(d: U32) -> String: one_s(List.get(&2, String, digits(), U32.to_nat(d)))

# the powers of ten that FIT in a U32. `U32.log2` exists but the digit count is
# not a function of it at a boundary (log2(63)=5 and log2(64)=6 straddle 2 and 3
# digits), so a log2 ladder has to be right at fourteen cut points. This list has
# nine entries and the walk below is exact.
def p10s() -> List<&2, U32>:
  [10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000]

# the first `p` with `v < p` is the digit count minus one, because a `U32` is at
# most ten digits and no tenth power fits. `Bool.pick` is STRICT so the recursive
# arm always runs; the arm that stops just discards it.
def dec_len.at(+ps: List<&2, U32>, +v: U32, +acc: U32) -> U32:
  match ps:
    case Nil{}: acc
    case p <> t: Bool.pick(U32, U32.is_lt(v, p), acc, dec_len.at(t, v, U32.add(acc, 1)))

def dec_len(v: U32) -> U32: dec_len.at(p10s(), v, 1)

def u32_dec.step(n: Nat, +v: U32, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: u32_dec.step(m, U32.div(v, 10), String.concat([dgt(U32.mod(v, 10)), acc]))

def u32_dec(+v: U32) -> String: u32_dec.step(U32.to_nat(dec_len(v)), v, "")

def u32s.at(is_neg: Bool, v: U32) -> String:
  match is_neg:
    case True{}: String.concat(["-", u32_dec(U32.sub(0, v))])
    case False{}: u32_dec(v)

# `0x80000000` is the sign bit. `U32.shrn` is LOGICAL, so this is the whole test.
def u32s(+v: U32) -> String: u32s.at(Bool.not(U32.is_zero(U32.and(v, 2147483648))), v)

# ===========================================================================
# THE ERROR TABLES. See THE ERROR TABLES in the header: the comprehension is
# keyed by the CODE, 74 names collapse to 63, and the codes are stored as `U32`
# two's complement because Bend has no signed integer.
# ===========================================================================

# MEASURED: 74 names carry a value <= 0, 63 distinct values, and the four shared
# codes keep the alphabetically LAST name (CL_SUCCESS / CL_DEVICE_NOT_FOUND /
# CL_DEVICE_NOT_AVAILABLE / CL_COMPILER_NOT_AVAILABLE).
def cl_err_code() -> List<&2, U32>:
  [0, 4294967295, 4294967294, 4294967293, 4294967292, 4294967291, 4294967290, 4294967289,
   4294967288, 4294967287, 4294967286, 4294967285, 4294967284, 4294967283, 4294967282, 4294967281,
   4294967280, 4294967279, 4294967278, 4294967277, 4294967266, 4294967265, 4294967264, 4294967263,
   4294967262, 4294967261, 4294967260, 4294967259, 4294967258, 4294967257, 4294967256, 4294967255,
   4294967254, 4294967253, 4294967252, 4294967251, 4294967250, 4294967249, 4294967248, 4294967247,
   4294967246, 4294967245, 4294967244, 4294967243, 4294967242, 4294967241, 4294967240, 4294967239,
   4294967238, 4294967237, 4294967236, 4294967235, 4294967234, 4294967233, 4294967232, 4294967231,
   4294967230, 4294967229, 4294967228, 4294967227, 4294967226, 4294967225, 4294967224]

def cl_err_name() -> List<&2, String>:
  ["CL_SUCCESS", "CL_DEVICE_NOT_FOUND", "CL_DEVICE_NOT_AVAILABLE",
   "CL_COMPILER_NOT_AVAILABLE", "CL_MEM_OBJECT_ALLOCATION_FAILURE",
   "CL_OUT_OF_RESOURCES", "CL_OUT_OF_HOST_MEMORY", "CL_PROFILING_INFO_NOT_AVAILABLE",
   "CL_MEM_COPY_OVERLAP", "CL_IMAGE_FORMAT_MISMATCH",
   "CL_IMAGE_FORMAT_NOT_SUPPORTED", "CL_BUILD_PROGRAM_FAILURE", "CL_MAP_FAILURE",
   "CL_MISALIGNED_SUB_BUFFER_OFFSET", "CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST",
   "CL_COMPILE_PROGRAM_FAILURE", "CL_LINKER_NOT_AVAILABLE",
   "CL_LINK_PROGRAM_FAILURE", "CL_DEVICE_PARTITION_FAILED",
   "CL_KERNEL_ARG_INFO_NOT_AVAILABLE", "CL_INVALID_VALUE", "CL_INVALID_DEVICE_TYPE",
   "CL_INVALID_PLATFORM", "CL_INVALID_DEVICE", "CL_INVALID_CONTEXT",
   "CL_INVALID_QUEUE_PROPERTIES", "CL_INVALID_COMMAND_QUEUE", "CL_INVALID_HOST_PTR",
   "CL_INVALID_MEM_OBJECT", "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR",
   "CL_INVALID_IMAGE_SIZE", "CL_INVALID_SAMPLER", "CL_INVALID_BINARY",
   "CL_INVALID_BUILD_OPTIONS", "CL_INVALID_PROGRAM",
   "CL_INVALID_PROGRAM_EXECUTABLE", "CL_INVALID_KERNEL_NAME",
   "CL_INVALID_KERNEL_DEFINITION", "CL_INVALID_KERNEL", "CL_INVALID_ARG_INDEX",
   "CL_INVALID_ARG_VALUE", "CL_INVALID_ARG_SIZE", "CL_INVALID_KERNEL_ARGS",
   "CL_INVALID_WORK_DIMENSION", "CL_INVALID_WORK_GROUP_SIZE",
   "CL_INVALID_WORK_ITEM_SIZE", "CL_INVALID_GLOBAL_OFFSET",
   "CL_INVALID_EVENT_WAIT_LIST", "CL_INVALID_EVENT", "CL_INVALID_OPERATION",
   "CL_INVALID_GL_OBJECT", "CL_INVALID_BUFFER_SIZE", "CL_INVALID_MIP_LEVEL",
   "CL_INVALID_GLOBAL_WORK_SIZE", "CL_INVALID_PROPERTY",
   "CL_INVALID_IMAGE_DESCRIPTOR", "CL_INVALID_COMPILER_OPTIONS",
   "CL_INVALID_LINKER_OPTIONS", "CL_INVALID_DEVICE_PARTITION_COUNT",
   "CL_INVALID_PIPE_SIZE", "CL_INVALID_DEVICE_QUEUE", "CL_INVALID_SPEC_ID",
   "CL_MAX_SIZE_RESTRICTION_EXCEEDED"]

def cl_err_n() -> U32: 63

# 74 names carry a value <= 0 and 63 of them survive the comprehension, so 11
# names are aliases it throws away. MEASURED by counting both sides in CPython.
def cl_err_names_n() -> U32: 74

def cl_err_aliases() -> U32: U32.sub(cl_err_names_n(), cl_err_n())

# code -> name, i.e. `cl_errors.get(status)`. Walks the code and the name in
# lockstep and keeps the FIRST hit, which is what a dict lookup is and is NOT
# what `List.find` is. The accumulator starts at the DEFAULT so an absent code
# answers it -- the first version started at "" and `cl_err_p999` printed
# "OpenCL Error 999: " with no default at all.
def cl_err_step(n: Nat, +status: U32, codes: List<&2, U32>, names: List<&2, String>,
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
              cl_err_step(m, status, ct, nt, Bool.or(found, h),
                          Bool.pick(String, Bool.and(Bool.not(found), h), nm, got))

def CL_UNKNOWN() -> String: "Unknown error"

def cl_err_of(+status: U32) -> String:
  cl_err_step(U32.to_nat(cl_err_n()), status, cl_err_code(), cl_err_name(), False{}, CL_UNKNOWN())

# cl:18 f"OpenCL Error {status}: {cl_errors.get(status, 'Unknown error')}". The
# f-string has a DEFAULT, so there is NO `.get(...) is not None` test to port: the
# lookup's own default IS the message's tail and the two arms of such a pick would
# be equal. MEASURED: adding the `is not None` pick back moves ZERO gate rows --
# `cl_err_p999` prints `Unknown error` either way -- so the pick was dead code and
# `cl_err_hit` is gone with it. `u32s` puts the SIGN BACK, because the table stores
# two's complement and CPython's f-string spells `-1`. That is why the row that
# pins this says so in its NAME (`cl_err_m1` prints `-1`) and the oracle prints the
# same `str()`.
def cl_err_msg(+status: U32) -> String:
  String.concat(["OpenCL Error ", u32s(status), ": ", cl_err_of(status)])

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
  String.concat(["CUDA Error ", u32s(status), ", ", cu_err_of(status)])

# cu:90's `cuda.CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED` -- entry 712, and the
# ONE code `check` is NOT called on in the whole file.
def CUDA_HOST_REGISTERED() -> U32: 712
def CUDA_SUCCESS() -> U32: 0

# cu:119's `struct.pack("4Q", ...)`, cu:109's `range(2)` and cu:120's `1e-3` are
# the three numeric constants of the CUDA file that are not ctypes types.
def cu_handle_words() -> U32: 4
def cu_handles_tail() -> U32: 0
def cu_nstreams() -> U32: 2

# hp:10 -- the FUNCTION name is a symbol and is ported; the TEXT it returns is
# WALL 7. `hp_err_of` answers the prefix and the tail is the seam's.
def hp_err_of(status: U32) -> String: String.concat(["HIP Error ", u32s(status), ", "])

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE vendor call and the ONE argument the trace records for it. `op` is the
# table index above, so `vend.name(vendor, Call.op(c))` reads the trace BACK as
# C symbols -- that is the reverse direction of the vendor table, and the gate
# prints the whole trace through it, so one misspelling moves the name rows.
#
# `arg` is a STRING and not a `U32`, which is the one design choice in this file
# that is not in the Python: cl:47's traced argument is the KERNEL NAME and every
# other traced argument is an integer, and a log that can hold both without two
# parallel types is worth the `U32.show` at each call site. It also means every
# trace row is printable, which is what the gate wants.
type Call is Data:
  Call{op: U32, arg: String}

# the machine state of the seam. `next` mints the handle ids, `bad_at` is the
# CALL ORDINAL at which `check` should report an error (0 = never), and `refused`
# is what makes a refusal a TRUNCATION rather than a flag: see THE RAISE.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, bad_at: U32, refused: Bool}

# ONE `(name, slot, dtype, shape)` of `TinyELF.signature` (device.py:361). `isimg`
# is `is_image_shape(shape)`, `bits` is `dt.bitsize` and `isz` is `dt.itemsize`;
# `h`/`w` are shape[0]/shape[1] and are only read on the image arm -- note the
# field ORDER is `h` then `w`, which is the numpy order and NOT the descriptor's.
type Sig is Data:
  Sig{slot: U32, bits: U32, isz: U32, isimg: Bool, h: U32, w: U32}

# ONE `clSetKernelArg` -- cl:63-65 -- or, in the other two vendors, ONE argument
# of the packed argument blob. `kind` is 0 for a `cl_mem`, 1 for a
# `clCreateImage` result and 2 for the boxed `c_int{bitsize}` scalar, and `off` is
# the argument's OFFSET in that vendor's packed blob (always 0 for CL, which is
# the finding: CL passes each argument by POINTER and CUDA/HIP pass them inline).
type Arg is Data:
  Arg{i: U32, slot: U32, kind: U32, size: U32, off: U32}

# ops_cl.py:110 `BufferStorage` reduced to what the three allocators and the three
# free paths read: the handle `.buf` and the byte count. `nbytes` is NOT a field
# of device.bend's Buffer either -- it is `size * itemsize`, so the two cannot
# disagree here either.
type Buf is Data:
  Buf{id: U32, size: U32}

# one created object and the trace that created it: Bend refuses to destructure a
# computed product, so the two travel together. Same idiom as `Made` in
# ops_webgpu.bend.
type Made is Data:
  Made{buf: Buf, t: Tr}

# device.py:89 `BufferSpec`, and only the three fields the three allocators read.
# `host` and `cpu` are cu:75's `options.host or options.cpu_access`, which is ONE
# test in Python and two in the record, and `ext` is `options.external_ptr`.
type Spec is Data:
  Spec{host: Bool, cpu: Bool, ext: U32}

# ---- the readers. A `Data` field is read `Type.field(value)` and EVERY reader is
# hand-written, because a locally-declared record has no generated projection at
# all (bend2-constraints rule 27, line 4450). They live here, above every user,
# so no def below needs a reader it has not got.

def Sig.of(slot: U32, bits: U32, isz: U32, isimg: Bool, h: U32, +w: U32) -> Sig:
  Sig{slot, bits, isz, isimg, h, w}

def Sig.slot(+s: Sig) -> U32:
  match s:
    case Sig{slot, bits, isz, isimg, w, h}: slot

def Sig.bits(+s: Sig) -> U32:
  match s:
    case Sig{slot, bits, isz, isimg, w, h}: bits

def Sig.isz(+s: Sig) -> U32:
  match s:
    case Sig{slot, bits, isz, isimg, w, h}: isz

def Sig.isimg(+s: Sig) -> Bool:
  match s:
    case Sig{slot, bits, isz, isimg, w, h}: isimg

# `Sig.w` is the numpy shape's LAST extent (shape[1]) and `Sig.h` its FIRST
# (shape[0]). `img_desc_w_16_8` is the row that says so: the fixture is a 16-row
# 8-column image and the descriptor's width is 8. Naming these the other way round
# is what makes `cl.pitch` look wrong when it is right -- MEASURED, and see the
# `cl.pitch` note.
def Sig.w(+s: Sig) -> U32:
  match s:
    case Sig{slot, bits, isz, isimg, h, w}: w

def Sig.h(+s: Sig) -> U32:
  match s:
    case Sig{slot, bits, isz, isimg, h, w}: h

def Arg.i(+a: Arg) -> U32:
  match a:
    case Arg{i, slot, kind, size, off}: i

def Arg.slot(+a: Arg) -> U32:
  match a:
    case Arg{i, slot, kind, size, off}: slot

def Arg.kind(+a: Arg) -> U32:
  match a:
    case Arg{i, slot, kind, size, off}: kind

def Arg.size(+a: Arg) -> U32:
  match a:
    case Arg{i, slot, kind, size, off}: size

def Arg.off(+a: Arg) -> U32:
  match a:
    case Arg{i, slot, kind, size, off}: off

def Buf.id(b: Buf) -> U32:
  match b:
    case Buf{id, size}: id

def Buf.size(b: Buf) -> U32:
  match b:
    case Buf{id, size}: size

def Made.buf(+m: Made) -> Buf:
  match m:
    case Made{buf, t}: buf

def Made.tr(+m: Made) -> Tr:
  match m:
    case Made{buf, t}: t

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

# ===========================================================================
# THE TRACE, and THE RAISE.
#
# `check(status)` (:17) is called after EVERY vendor call in all three files, and
# that is the whole of the refusal story. So `Tr.emit` records the call AND
# records a refusal when this call is the `bad_at`-th, and once `refused` is set
# it records NOTHING further. A refusal therefore shows up as a TRUNCATED trace,
# and that is why no step in this file needs a guard of its own -- exactly the
# rule ops_webgpu.bend states for its four `pop_error` sites, for 65 calls
# instead of four.
#
# The failing call IS still recorded, and that is not a special case: it sets
# `refused` in the same breath, so on entry its own `refused` is still False.
#
# `bad_at` is read AT EMIT TIME, so it must be armed BEFORE the calls happen.
# MEASURED: the first version armed a finished trace and every refusal row
# printed the full trace with `refused=False`.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, False{}}

def Tr.calls(+t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, bad_at, refused}: calls

def Tr.next(+t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, refused}: next

def Tr.refused(+t: Tr) -> Bool:
  match t:
    case Tr{calls, next, bad_at, refused}: refused

# an EMPTY trace that keeps `bad_at`, so a gate can read one program call without
# the device init in front of it and still number its calls from one.
def Tr.reset(+t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, refused}: Tr{Nil{}, 0, bad_at, refused}

def Tr.fail_at(+t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, bad_at, refused}: Tr{calls, next, n, refused}

# the handle id the NEXT emit mints. Read BEFORE the emit, so ids are monotone in
# issue order -- the same rule ops_webgpu.bend's `Tr.here` follows. It is also
# how a def reads "the id the call in front of me minted".
def Tr.here(+t: Tr) -> U32: Tr.next(t)

# how many calls are in the trace, i.e. the ORDINAL the next emit will be.
def Tr.n(+t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# the call that reports the error is the `bad_at`-th, i.e. the one whose ordinal
# is `bad_at - 1`. There is NO `is_zero(bad_at)` conjunct and it is not missing:
# the ordinals are ONE-BASED, so `bad_at = 0` -- the value `Tr.of` starts with --
# compares against `hits + 1 >= 1` and can never be equal. MEASURED: adding the
# conjunct back moves ZERO gate rows.
def Tr.hit(+bad_at: U32, hits: U32) -> Bool: U32.is_eq(U32.add(hits, 1), bad_at)

# THE CALL COUNT COMES FROM THE DESTRUCTURED LIST and not from `Tr.n(t)`, and
# that is not a style choice: `match t:` KILLS the name `t`, so the first version
# read a consumed scrutinee for the ordinal and `bad_at` never fired.
def Tr.emit.go(+refused: Bool, op: U32, arg: String, +calls: List<&2, Call>,
               +next: U32, +bad_at: U32) -> Tr:
  +hits = U32.from_nat(List.length(&2, Call, calls))
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{op, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), bad_at,
     Bool.or(refused, Tr.hit(bad_at, hits))}

def Tr.emit(op: U32, arg: String, +t: Tr) -> Tr:
  match t:
    case Tr{+calls, +next, +bad_at, +refused}:
      Tr.emit.go(refused, op, arg, calls, next, bad_at)

# cl:19 `checked(ret, status) = (check(status.value), ret)[1]` -- the status is
# checked FIRST and `ret` is the value the call returned. So the handle is minted
# on the same breath as the refusal, and a refusal means the handle was never
# assigned because Python raised before the tuple was built.
def Tr.checked(op: U32, arg: String, +t: Tr) -> Tr: Tr.emit(op, arg, t)

def Call.op(+c: Call) -> U32:
  match c:
    case Call{op, arg}: op

def Call.arg(+c: Call) -> String:
  match c:
    case Call{op, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.ops` is the op sequence in order, `Tr.args` the args of
# one op, `Tr.count` how many of one op, and `Tr.has` a real subsequence test.
# ===========================================================================

def Tr.count.go(n: Nat, +op: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{oo, aa} <> t: Tr.count.go(m, op, t, U32.add(got, Bool.to_u32(U32.is_eq(oo, op))))

def Tr.count(op: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), op, cs, 0)

def Tr.ops.go(cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case Call{oo, aa} <> t: Tr.ops.go(t, List.append(&2, U32, acc, [oo]))

def Tr.ops(+cs: List<&2, Call>) -> List<&2, U32>: Tr.ops.go(cs, Nil{})

def Tr.args.put(+c: Call, +op: U32, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(Call.op(c), op),
    List.append(&2, String, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +op: U32, cs: List<&2, Call>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{oo, aa} <> t: Tr.args.go(m, op, t, Tr.args.put(Call{oo, aa}, op, acc))

def Tr.args(op: U32, +cs: List<&2, Call>) -> List<&2, String>:
  Tr.args.go(List.length(&2, Call, cs), op, cs, Nil{})

# `Tr.has` is a real SUBSEQUENCE test: the fuel is the TRACE length and the answer
# is `at == patlen`. Getting either half wrong makes it answer True to everything,
# which is how the order rows become decorative -- so the matcher pins itself
# first, with three rows that must FAIL to match.
def Tr.has.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(+m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.hit(U32.is_eq(Call.op(c), Call.op(want)) && String.eq(Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{oo, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{oo, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)

# ONE traced call as `symbol(arg)`, and `vend.trace` joins them with ONE space.
# A `List<&2, String>` and one `String.join`, because a fold that conses onto the
# head of a `case c <> t:` walk builds the string BACKWARDS and a fold that conses
# into `String.concat` leaves a trailing space -- which is half the diff in a
# byte-compared gate (bend2-constraints rule 20 and rule 22). MEASURED: the first
# version printed every trace last-call-first.
def vend.line(+v: U32, +c: Call) -> String:
  String.concat([vend.name(v, Call.op(c)), "(", Call.arg(c), ")"])

def vend.trace.put(+v: U32, c: Call, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, [vend.line(v, c)])

def vend.trace.go(+v: U32, cs: List<&2, Call>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case c <> t: vend.trace.go(v, t, vend.trace.put(v, c, acc))

def vend.trace(+v: U32, cs: List<&2, Call>) -> String:
  String.join(vend.trace.go(v, cs, Nil{}), " ")

def str_eq.go(+a: List<&2, String>, b: List<&2, String>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case x <> t:
      match b:
        case Nil{}: False{}
        case y <> u: str_eq.go(t, u, Bool.or(bad, Bool.not(String.eq(x, y))))

def str_list_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, String, a)),
                     U32.from_nat(List.length(&2, String, b))), str_eq.go(a, b, False{}))

# ===========================================================================
# PART 1 -- OpenCL. `ops_cl.py`, all 130 lines.
# ===========================================================================

# `autogen/opencl.py`, read out. Every one of these is a value the three CL
# functions pass and none of them is derived, so they are constants and the gate
# prints all eighteen beside the module's own attributes.
def CL_SUCCESS() -> U32: 0
def CL_DEVICE_TYPE_GPU() -> U32: 4
def CL_DEVICE_TYPE_DEFAULT() -> U32: 1
def CL_MEM_READ_WRITE() -> U32: 1
def CL_MEM_OBJECT_IMAGE2D() -> U32: 4337
def CL_RGBA() -> U32: 4277
def CL_HALF_FLOAT() -> U32: 4317
def CL_FLOAT() -> U32: 4318
def CL_QUEUE_PROFILING_ENABLE() -> U32: 2
def CL_PROGRAM_BUILD_LOG() -> U32: 4483
def CL_PROGRAM_BINARY_SIZES() -> U32: 4453
def CL_PROGRAM_BINARIES() -> U32: 4454
def CL_PROFILING_COMMAND_START() -> U32: 4738
def CL_PROFILING_COMMAND_END() -> U32: 4739
def CL_DEVICE_NAME() -> U32: 4139
def CL_DRIVER_VERSION() -> U32: 4141
def CL_DEVICE_EXTENSIONS() -> U32: 4144
def CL_DEVICE_IMAGE_PITCH_ALIGNMENT() -> U32: 4170

# cl:97 `[cl.CL_DEVICE_TYPE_GPU, cl.CL_DEVICE_TYPE_DEFAULT]` -- the two candidate
# types, in the order the loop tries them, and the loop breaks at the FIRST one
# with a nonzero device count. GPU=4 first, DEFAULT=1 second.
def cl_types() -> List<&2, U32>: [CL_DEVICE_TYPE_GPU(), CL_DEVICE_TYPE_DEFAULT()]

# the sentinel `Prb.idx` carries when every candidate answered zero devices.
# cl:99's `if err == 0 and num_devices.value != 0: break` never fires, so cl:102
# built a ZERO-LENGTH `(cl_device_id * 0)()` and cl:104 would raise IndexError.
def NO_IDX() -> U32: 4294967295

# cl:95-102 -- THE PLATFORM AND DEVICE-TYPE PROBE. It is the only loop in
# `__init__` and `clGetDeviceIDs` is called ONCE PER CANDIDATE plus once for the
# real query, so the trace length is `2 + len(candidates) + 1` and the COUNT is
# the row that sees the loop at all.
#
# `nd` is the fixture's device count per candidate -- what the seam answers -- and
# a fold that cannot be told "this platform has no GPU" cannot see the `for
# device_type in [...]` at all. It is why the loop gets two fixtures.
type Prb is Data:
  Prb{idx: U32, n: U32, nd: List<&2, U32>, t: Tr}

def Prb.seed(nd: List<&2, U32>) -> Prb: Prb{NO_IDX(), 0, nd, Tr.of()}

def Prb.idx(+p: Prb) -> U32:
  match p:
    case Prb{idx, n, nd, t}: idx

def Prb.n(+p: Prb) -> U32:
  match p:
    case Prb{idx, n, nd, t}: n

def Prb.nd(+p: Prb) -> List<&2, U32>:
  match p:
    case Prb{idx, n, nd, t}: nd

def Prb.t(+p: Prb) -> Tr:
  match p:
    case Prb{idx, n, nd, t}: t

def Prb.hit(+p: Prb) -> Bool: Bool.not(U32.is_eq(Prb.idx(p), NO_IDX()))

# THE ZERO-DEVICE CANDIDATE. `hit` is "some candidate already won", so a
# candidate that answers ZERO devices must leave `idx` at NO_IDX and let the next
# one try. The first version wrote `i` unconditionally whenever `hit` was False,
# which let the GPU candidate claim the index with no devices behind it, and
# `cl_probe_idx_def` then answered 0 for BOTH fixtures -- which is exactly the
# "two rules agree so no mutation can see it" trap in its purest form: the probe
# looked right because every candidate index is 0 in the passing fixture.
def cl.probe.claim(ndev: U32, +i: U32) -> U32:
  Bool.pick(U32, Bool.not(U32.is_zero(ndev)), i, NO_IDX())

# cl:98-99 -- `err = cl.clGetDeviceIDs(platform_ids[0], device_type, 0, None,
# num_devices := c_uint32()); if err == 0 and num_devices.value != 0: break`. The
# emit is the UNCHECKED probe (cl_probe_checked) and the break keeps the FIRST
# hit, so the index is written only while `hit` is False.
def cl.probe.at(+i: U32, +ndev: U32, +p: Prb) -> Prb:
  Prb{Bool.pick(U32, Prb.hit(p), Prb.idx(p), cl.probe.claim(ndev, i)),
      Bool.pick(U32, Prb.hit(p), Prb.n(p), ndev), Prb.nd(p),
      Tr.emit(OP_GET_DEVICES(), U32.show(ndev), Prb.t(p))}

# the candidate list walks FIRST so the decrease check finds the tail before the
# growing trace, and the two lists are in lockstep.
def cl.probe.go(xs: List<&2, U32>, +nd: List<&2, U32>, +i: U32, +p: Prb) -> Prb:
  match xs:
    case Nil{}: p
    case _ <> t:
      match nd:
        case Nil{}: p
        case v <> vd: cl.probe.go(t, vd, U32.add(i, 1), cl.probe.at(i, v, p))

# cl:95 -- `check(cl.clGetPlatformIDs(0, None, num_platforms := c_uint32()))`.
def cl.platforms(n: U32, +t: Tr) -> Tr: Tr.emit(OP_PLATFORMS(), U32.show(n), t)

# cl:96 -- the second call, WITH the array. Same op and same `arg`, so the two
# are indistinguishable in the trace except by COUNT, and `cl_init_platforms` is
# that count row.
def cl.platform_ids(n: U32, +t: Tr) -> Tr: Tr.emit(OP_PLATFORMS(), U32.show(n), t)

# cl:102 `c.init_c_var((cl.cl_device_id * num_devices.value), lambda x:
# check(cl.clGetDeviceIDs(platform_ids[0], device_type, num_devices, x, None)))`
# -- the REAL device query, CHECKED, once, with the WINNING type.
def cl.device_ids(+p: Prb, +t: Tr) -> Tr: Tr.emit(OP_GET_DEVICES(), U32.show(Prb.n(p)), t)

def cl.probe_init(+p: Prb, +t: Tr) -> Prb:
  +t2 = cl.platform_ids(2, cl.platforms(2, t))
  +p2 = cl.probe.go(cl_types(), Prb.nd(p), 0, Prb{NO_IDX(), 0, Prb.nd(p), t2})
  Prb{Prb.idx(p2), Prb.n(p2), Prb.nd(p), cl.device_ids(p2, Prb.t(p2))}

# cl:97-99 -- the WINNING device type, and `one_u` answers 0 for a `None` index,
# which is NEITHER candidate: an exhausted probe leaves `Prb.idx` at NO_IDX, so
# `cl_probe_type_none` is the row that says the port answers 0 where Python would
# raise IndexError.
def cl.dev_type(+p: Prb) -> U32: one_u(List.get(&2, U32, cl_types(), U32.to_nat(Prb.idx(p))))

# ===========================================================================
# cl:120-123 -- THE ARCH STRING, which is the `Compiled.__init__` argument and
# the only derivation in `__init__` that is not a call.
#
#   arch = ",".join(self.device_exts)
#   if "cl_khr_image2d_from_buffer" in self.device_exts:
#     check(clGetDeviceInfo(..., CL_DEVICE_IMAGE_PITCH_ALIGNMENT, 4, byref(ipa), None))
#     arch += f",IMAGE_PITCH_ALIGNMENT={ipa.value}"
#
# so the suffix is there ONLY for that one extension and it is appended AFTER the
# join, which is why a device WITH the extension has one more comma-separated
# field than one without and never a leading comma.
# ===========================================================================

def cl.IMG_EXT() -> String: "cl_khr_image2d_from_buffer"
def cl.ipa_prefix() -> String: ",IMAGE_PITCH_ALIGNMENT="

# `",".join(exts)` -- `String.join` is HEAD-FIRST, so the list order is the string
# order and there is no reverse here.
def cl.ext_join(+exts: List<&2, String>) -> String: String.join(exts, ",")

# the suffix, and it is a `match` on a Bool because `if ... in ...` is a test.
def cl.arch_suffix(has_ipa: Bool, ipa: U32) -> String:
  match has_ipa:
    case True{}: String.concat([cl.ipa_prefix(), U32.show(ipa)])
    case False{}: ""

def cl.arch_of(+exts: List<&2, String>, has_ipa: Bool, ipa: U32) -> String:
  String.concat([cl.ext_join(exts), cl.arch_suffix(has_ipa, ipa)])

# cl:121 `if "cl_khr_image2d_from_buffer" in self.device_exts` -- membership on the
# list Python built with `.split()` (cl:116), so it is an EQUALITY test on one
# entry and not a substring test on the joined string.
def cl.has_img_ext(+exts: List<&2, String>) -> Bool: List.contains(~String, ~String.eq, exts, cl.IMG_EXT())

# ===========================================================================
# cl:105-123 -- THE INIT SEQUENCE, in order. Eleven calls when the extension is
# absent and twelve when it is there, and the ORDER is the whole of this def.
# ===========================================================================

# cl:105 `self.device_name = (clGetDeviceInfo(self.cl_dev, CL_DEVICE_NAME, 256,
# buf, None), buf.value.decode())[1]` -- UNCHECKED (cl_info_checked). The `arg` is
# the INFO PARAM, which is what distinguishes the five `clGetDeviceInfo` calls
# from each other in the trace.
def cl.info_name(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_INFO(), U32.show(CL_DEVICE_NAME()), t)

# cl:107 the same shape for CL_DRIVER_VERSION.
def cl.info_drv(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_INFO(), U32.show(CL_DRIVER_VERSION()), t)

# cl:110 `self.context = checked(clCreateContext(None, 1, self.cl_dev, CC_CB(),
# None, status), status)` -- CHECKED, through `checked`.
def cl.context(+t: Tr) -> Tr: Tr.checked(OP_CTX_CREATE(), "0", t)

# cl:111 `self.queue = checked(clCreateCommandQueue(self.context, self.cl_dev,
# CL_QUEUE_PROFILING_ENABLE, status), status)`. The queue FLAGS ride on the trace
# because they are the queue's only argument that is not a handle.
def cl.queue(+t: Tr) -> Tr: Tr.checked(OP_QUEUE_CREATE(), U32.show(CL_QUEUE_PROFILING_ENABLE()), t)

# cl:113 `check(clGetDeviceInfo(self.cl_dev, CL_DEVICE_EXTENSIONS, 0, None,
# byref(exts_len)))` -- the LENGTH query, and it IS checked: cl:113 wraps it in
# `check` while cl:114 does not. Two calls, one op, one info param, and only the
# COUNT separates them.
def cl.exts_len(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_INFO(), U32.show(CL_DEVICE_EXTENSIONS()), t)

# cl:114 the string query, UNCHECKED, and it carries the same info param.
def cl.exts_get(len: U32, +t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_INFO(), U32.show(CL_DEVICE_EXTENSIONS()), t)

# cl:122 `check(clGetDeviceInfo(self.cl_dev, CL_DEVICE_IMAGE_PITCH_ALIGNMENT, 4,
# byref(ipa), None))` -- CHECKED, and it only happens when the extension is there.
def cl.ipa_get(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_INFO(), U32.show(CL_DEVICE_IMAGE_PITCH_ALIGNMENT()), t)

# cl:121-123 -- `if ... in exts:` is a two-arm choice and a `match` may not
# scrutinise a call, so the flag is a parameter.
def cl.ipa_get.at(has_ipa: Bool, +t: Tr) -> Tr:
  match has_ipa:
    case True{}: cl.ipa_get(t)
    case False{}: t

# cl:104 `self.cl_dev = CLDevice.device_ids[0 if ":" not in device else
# int(device.split(":")[1])]` -- the DEVICE INDEX, not a handle. `":" in device` is
# a test on the device string and the index is every digit AFTER the colon, so the
# two halves are one flag and one fold. `cl_has_colon` is the flag on its own
# because `cl_dev_index` is 0 for both "" and "OPENCL" and the flag is what tells
# them apart.
def CL_COLON() -> Char: Char.from_u32(58)

def cl_digits.at(+hit: Bool, c: Char, +acc: U32) -> U32:
  match hit:
    case True{}: U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(c), 48))
    case False{}: acc

# the fold accumulates with the flag as it was BEFORE this character, so the ':'
# itself contributes nothing: `58 - 48` is 10 and reading it as a digit turned
# "OPENCL:0" into 100. MEASURED, and `cl_didx_0` is the row.
def cl_digits(+cs: List<&2, Char>, +hit: Bool, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case c <> t:
      +h2 = Bool.or(hit, Char.is_eq(c, CL_COLON()))
      cl_digits(t, h2, cl_digits.at(hit, c, acc))

def cl_dev_index(+device: String) -> U32: cl_digits(String.to_list(device), False{}, 0)

# `":" in device` -- one def, because `cl_dev_index` cannot be a scrutinee.
def cl_colon_at(+cs: List<&2, Char>, +hit: Bool) -> Bool:
  match cs:
    case Nil{}: hit
    case c <> t: cl_colon_at(t, Bool.or(hit, Char.is_eq(c, CL_COLON())))

def cl_has_colon(+cs: List<&2, Char>) -> Bool: cl_colon_at(cs, False{})

# cl:112 `self.pending_copyin: list[memoryview] = []` -- no call, and it is the
# only state on the device that the trace does not own.
def cl.pending_init() -> U32: 0

# cl:118 `CLCompiler(self, f"{hashlib.md5(device_name.encode() +
# driver_version.encode()).hexdigest()}")` and Compiler.__init__'s
# `f"compile_cl_{compile_key}"` (device.py:337). The PREFIX and the two
# concatenated fields are portable; the md5 is WALL 5, so the key carries the two
# fields with a `|` between them and the seam replaces the digest.
def cl.key_prefix() -> String: "compile_cl_"
def cl.key_sep() -> String: "|"

def cl.key(+name: String, +drv: String) -> String:
  String.concat([cl.key_prefix(), name, cl.key_sep(), drv])

# the OpenCL DEVICE, ops_cl.py:104-124, and only the fields ops_cl.py writes.
# `didx` is cl:104's index into `device_ids`, `ctx` and `q0` are handle ids the
# trace minted (`Tr.here` read BEFORE the emit, so the id an emit mints IS the
# `Tr.here` of the trace in front of it), `qflags` is cl:111's queue flags, `ipa`
# is cl:122's pitch alignment and `has_ipa` whether the extension was there.
type Dev is Data:
  Dev{didx: U32, ctx: U32, q0: U32, qflags: U32, name: String, drv: String,
      exts: List<&2, String>, ipa: U32, has_ipa: Bool, ckey: String,
      arch: String, pending: U32, t: Tr}

def Dev.of() -> Dev: Dev{0, 0, 0, 0, "", "", Nil{}, 0, False{}, "", "", 0, Tr.of()}

def Dev.didx(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: didx

def Dev.ctx(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: ctx

def Dev.q0(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: q0

def Dev.qflags(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: qflags

def Dev.name(d: Dev) -> String:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: name

def Dev.drv(d: Dev) -> String:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: drv

def Dev.exts(d: Dev) -> List<&2, String>:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: exts

def Dev.ipa(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: ipa

def Dev.has_ipa(d: Dev) -> Bool:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: has_ipa

def Dev.ckey(d: Dev) -> String:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: ckey

def Dev.arch(d: Dev) -> String:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: arch

def Dev.pending(d: Dev) -> U32:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: pending

def Dev.t(d: Dev) -> Tr:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}: t

# cl:93-124 -- the device. The whole call sequence is ONE def so the order is one
# term, and the two handle ids come out of `Tr.here`.
def cl.init(+p: Prb, +device: String, +name: String, +drv: String,
            +exts: List<&2, String>, +ipa: U32, t: Tr) -> Dev:
  +p2 = cl.probe_init(p, t)
  +has = cl.has_img_ext(exts)
  +t2 = cl.info_drv(cl.info_name(Prb.t(p2)))
  +t3 = cl.context(t2)
  +t4 = cl.queue(t3)
  +t5 = cl.exts_len(t4)
  +t6 = cl.exts_get(0, t5)
  Dev{cl_dev_index(device), Tr.here(t2), Tr.here(t3), CL_QUEUE_PROFILING_ENABLE(),
      name, drv, exts, ipa, has, cl.key(name, drv),
      cl.arch_of(exts, has, ipa), cl.pending_init(), cl.ipa_get.at(has, t6)}

# ===========================================================================
# cl:25-37 -- `CLCompiler.compile`. Five calls on the success path and FOUR on
# the failure path, because the two build-log reads at :29-30 sit inside
# `if build_status != 0:` and the raise at :32 stops everything else.
# ===========================================================================

# cl:26 `checked(cl.clCreateProgramWithSource(self.dev.context, 1,
# to_char_p_p([src.encode()]), None, status), status)`.
def comp.from_src(+t: Tr) -> Tr: Tr.checked(OP_PRG_FROM_SRC(), "0", t)

# cl:27 `build_status = cl.clBuildProgram(program, 1, self.dev.cl_dev, None,
# BP_CB(), None)` -- the status is COMPARED at :28, not passed to `check`, so the
# build is never a `check`-refusal and its failure is a DIFFERENT refusal.
def comp.build(+t: Tr) -> Tr: Tr.emit(OP_BUILD(), "1", t)

# cl:29-30 -- `cl.clGetProgramBuildInfo(program, self.dev.cl_dev,
# cl.CL_PROGRAM_BUILD_LOG, 0, None, log_size)` then the same with the buffer. The
# `arg` is the log LENGTH, which is 0 on the first read and the real size on the
# second, so the two ARE distinguishable in the trace and `comp_compile_badlog` is
# that row.
def comp.build_log(size: U32, +t: Tr) -> Tr: Tr.emit(OP_BUILD_LOG(), U32.show(size), t)

# cl:33 `check(clGetProgramInfo(program, CL_PROGRAM_BINARY_SIZES, ...))` and cl:34
# the same for CL_PROGRAM_BINARIES: TWO different info params on ONE op, which is
# exactly why the info param is the trace's `arg` here and for OP_GET_DEVICE_INFO.
def comp.prg_info(param: U32, +t: Tr) -> Tr: Tr.emit(OP_PRG_INFO(), U32.show(param), t)

# cl:36 `check(cl.clReleaseProgram(program))` -- the only release in the compiler.
def comp.release(+t: Tr) -> Tr: Tr.emit(OP_RELEASE_PRG(), "0", t)

# the FIVE success-path calls, in order.
def comp.compile(+t: Tr) -> Tr:
  +t1 = comp.from_src(t)
  +t2 = comp.build(t1)
  +t3 = comp.prg_info(CL_PROGRAM_BINARY_SIZES(), t2)
  +t4 = comp.prg_info(CL_PROGRAM_BINARIES(), t3)
  comp.release(t4)

# cl:28-32 -- `if build_status != 0:` then the TWO log reads and the raise. The
# raise is a `CompileError`, NOT a `check`, and this is the ONE refusal in the
# three files that the trace's `raise` does not model. Faithfulness here means the
# trace STOPS after the log reads, because after :32 nothing else in `compile`
# happens -- which is the same observable shape as a `check` refusal and is the
# reason the model covers it without a flag.
def comp.compile.bad(+t: Tr) -> Tr:
  +t1 = comp.from_src(t)
  +t2 = comp.build(t1)
  comp.build_log(0, comp.build_log(0, t2))

# the CompileError message is `f"OpenCL Compile Error\n\n{mstr.value.decode()}"`
# and the log is WALL 3, so only the PREFIX is portable.
def CL_COMPILE_ERR() -> String: "OpenCL Compile Error\n\n"

# ===========================================================================
# cl:39-53 -- `CLProgram.__init__` and `__del__`.
#
# `__init__` is FOUR calls and the order is load-bearing in a way the comment
# names: cl:46's `clBuildProgram` "# NOTE: OSX requires this", i.e. a program
# created from a BINARY must still be BUILT before `clCreateKernel`. Drop it and
# OSX rejects the kernel.
# ===========================================================================

# ONE program call's state. `unit`/`ctx` are the device's handles (prog:52 reads
# `self.dev.context` and :46 `device.cl_dev`), `prg`/`kernel` the two handles
# `__init__` mints, `sig` the TinyELF signature, `args` the per-row argument
# record, the six geometry fields the pre- and post-product sizes (cl:66
# OVERWRITES global_size with the product and still passes the LOCAL size at
# :69, so both are in hand), `want` the `wait` flag and `t` the trace.
type Prog is Data:
  Prog{vendor: U32, unit: U32, ctx: U32, prg: U32, kernel: U32, entry: String,
       sig: List<&2, Sig>, args: List<&2, Arg>, gsx: U32, gsy: U32, gsz: U32,
       lsx: U32, lsy: U32, lsz: U32, want: Bool, t: Tr}

def Prog.of(v: U32, entry: String, +sig: List<&2, Sig>) -> Prog:
  Prog{v, 0, 0, 0, 0, entry, sig, Nil{}, 1, 1, 1, 1, 1, 1, False{}, Tr.of()}

def Prog.vendor(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: vendor

def Prog.unit(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: unit

def Prog.ctx(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: ctx

def Prog.prg(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: prg

def Prog.kernel(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: kernel

def Prog.entry(+p: Prog) -> String:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: entry

def Prog.sig(+p: Prog) -> List<&2, Sig>:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: sig

def Prog.args(+p: Prog) -> List<&2, Arg>:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: args

def Prog.gsx(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: gsx

def Prog.gsy(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: gsy

def Prog.gsz(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: gsz

def Prog.lsx(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: lsx

def Prog.lsy(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: lsy

def Prog.lsz(+p: Prog) -> U32:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: lsz

def Prog.want(+p: Prog) -> Bool:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: want

def Prog.t(+p: Prog) -> Tr:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}: t

def prog.with(+p: Prog, sig: List<&2, Sig>, args: List<&2, Arg>, gsx: U32, gsy: U32,
              gsz: U32, lsx: U32, lsy: U32, lsz: U32, want: Bool, t: Tr) -> Prog:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, s0, a0, x0, y0, z0, l0, m0, n0, w0, t0}:
      Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}

def prog.with_t(+p: Prog, +t: Tr) -> Prog:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t0}:
      Prog{vendor, unit, ctx, prg, kernel, entry, sig, args, gsx, gsy, gsz, lsx, lsy, lsz, want, t}

# cl:42 `checked(cl.clCreateProgramWithBinary(device.context, 1, device.cl_dev,
# (c_size_t * 1)(len(self.lib)), to_char_p_p([self.lib], c_ubyte), binary_status,
# errcode_ret), errcode_ret)` -- the `arg` is the LIBRARY LENGTH.
def prog.from_bin(libn: U32, +t: Tr) -> Tr: Tr.checked(OP_PRG_FROM_BIN(), U32.show(libn), t)

# cl:45 `check(binary_status.value)` -- a bare `check` on a status :42 already
# wrote, and it is a SEPARATE refusal point from the one inside `checked`.
def prog.binary_check(+t: Tr) -> Tr: Tr.emit(OP_PRG_FROM_BIN(), "0", t)

# cl:46 `check(cl.clBuildProgram(self.program, 1, device.cl_dev, None, BP_CB(),
# None))` -- "# NOTE: OSX requires this".
def prog.build(+t: Tr) -> Tr: Tr.emit(OP_BUILD(), "1", t)

# cl:47 `self.kernel = checked(cl.clCreateKernel(self.program, obj.name.encode(),
# status), status)` -- the `arg` is the kernel NAME, which is the only
# user-visible string on the whole trace besides the error messages.
def prog.kernel(name: String, +t: Tr) -> Tr: Tr.checked(OP_KERNEL(), name, t)

# :40-47, in order: from-bin, the binary-status check, build, kernel.
def PROG_INIT_N() -> U32: 4

def prog.init(+d: Dev, +entry: String, libn: U32, +t: Tr, +sig: List<&2, Sig>) -> Prog:
  +t1 = prog.from_bin(libn, t)
  +t2 = prog.binary_check(t1)
  +t3 = prog.build(t2)
  +t4 = prog.kernel(entry, t3)
  Prog{V_CL(), Dev.didx(d), Dev.ctx(d), Tr.here(t1), Tr.here(t4), entry,
       sig, Nil{}, 1, 1, 1, 1, 1, 1, False{}, t4}

# cl:49-53 -- `__del__`, and the TRY/EXCEPT is the whole content of it:
#
#   try: check(cl.clReleaseKernel(self.kernel))
#   except (TypeError, AttributeError): pass
#   try: check(cl.clReleaseProgram(self.program))
#   except (TypeError, AttributeError): pass
#
# So a kernel that was never created releases NOTHING, and a program without a
# kernel still releases its program. The handle is 0 for "the attribute is
# missing", which is how `TypeError`/`AttributeError` become a `U32`.
def prog.del.prg(have_p: Bool, +t: Tr) -> Tr:
  match have_p:
    case True{}: Tr.emit(OP_RELEASE_PRG(), "0", t)
    case False{}: t

def prog.del.go(have_k: Bool, have_p: Bool, +t: Tr) -> Tr:
  match have_k:
    case True{}: prog.del.prg(have_p, Tr.emit(OP_RELEASE_KERNEL(), "0", t))
    case False{}: prog.del.prg(have_p, t)

def prog.del(+p: Prog) -> Tr:
  prog.del.go(Bool.not(U32.is_zero(Prog.kernel(p))), Bool.not(U32.is_zero(Prog.prg(p))), Prog.t(p))

# ===========================================================================
# cl:55-76 -- ONE PROGRAM CALL, as the step list it is. Every step is one line
# range of the Python and takes the `Prog` it is handed, so the order IS the
# whole of `__call__`: the arg loop (:57-65), then the geometry (:66, no call),
# then the launch (:68), then the `if wait:` block (:70-75).
#
# THE `raise` IS IN THE TRACE (see THE RAISE): `check` after every call, so once
# a refusal lands nothing further records and a refusal shows up as a TRUNCATED
# trace. `cl_refuse_*` reads that.
# ===========================================================================

# cl:58 `getattr(ctypes, f"c_int{dt.bitsize}")(vals[slot - len(bufs)])` -- the
# ctypes TYPE NAME. Portable, and the one part of WALL 6 compared
# string-for-string against CPython. Note it is `c_int` for UNSIGNED dtypes too:
# the f-string has no `u` in it. It is the f-string, so the suffix is the DECIMAL
# PRINTER and not a four-way table -- 7 is `c_int7`, not `c_int32`, and the gate
# pins that off-grid row because a table keyed on {8,16,32,64} gets it wrong.
def ct.typename(bits: U32) -> String: String.concat(["c_int", u32_dec(bits)])

# `Arg.kind`: 0 is a `cl_mem`, 1 is a `clCreateImage` result, 2 is the boxed
# `c_int{bitsize}` scalar. The three are not decoration -- they select three
# DIFFERENT `clSetKernelArg` argument types and the image one adds a
# `clCreateImage` BEFORE the set.
def KIND_MEM() -> U32: 0
def KIND_IMAGE() -> U32: 1
def KIND_SCALAR() -> U32: 2

# a `ctypes` handle is a POINTER and a pointer is eight bytes on every platform
# tinygrad supports; `ctypes.sizeof(img)` at cl:64 and `ctypes.sizeof(b)` at cl:65
# are both `PTR_SZ`. WALL 6, and the only size here that is not from a dtype.
def PTR_SZ() -> U32: 8

# `ctypes.sizeof(c_int{bits})` is bits/8, which is `dt.itemsize`.
def arg.size(kind: U32, isz: U32) -> U32:
  match kind:
    case 0: PTR_SZ()
    case 1: PTR_SZ()
    case _: isz

# cl:57-58 -- `for i, (_, slot, dt, shape) in enumerate(self.signature): b =
# bufs[slot] if slot < len(bufs) else c_int{bitsize}(vals[slot - len(bufs)])`.
# The decision is `slot < len(bufs)` and the SCALAR's index is `slot - len(bufs)`,
# so the two are one subtraction apart.
def arg.is_buf(slot: U32, +nbufs: U32) -> Bool: U32.is_lt(slot, nbufs)

def arg.val_index(slot: U32, +nbufs: U32) -> U32: U32.sub(slot, nbufs)

def arg.kind.at(isimg: Bool, +s: Sig, +nbufs: U32) -> U32:
  match isimg:
    case True{}: KIND_IMAGE()
    case False{}: Bool.pick(U32, arg.is_buf(Sig.slot(s), nbufs), KIND_MEM(), KIND_SCALAR())

# a `match` may not scrutinise a CALL, so `Sig.isimg(s)` crosses as a parameter.
def arg.kind(+s: Sig, +nbufs: U32) -> U32: arg.kind.at(Sig.isimg(s), s, nbufs)

# THE ONE ARGUMENT DERIVATION. `i` is the ENUMERATE index, which is what
# `clSetKernelArg`'s first argument is and therefore what binds `data0_4` in
# cstyle's OpenCL text; `slot` is the signature's own slot, which indexes
# `bufs`/`vals`. They are NOT the same number in general and that IS the whole
# cross-file contract with cstyle.bend. `off` is 0 for CL because every argument
# is passed BY POINTER, and it is NOT 0 for CUDA or HIP.
def arg.of(+i: U32, +s: Sig, +nbufs: U32) -> Arg:
  +k = arg.kind(s, nbufs)
  Arg{i, Sig.slot(s), k, arg.size(k, Sig.isz(s)), 0}

# cl:61 `fmt = cl.cl_image_format(cl.CL_RGBA, {2: cl.CL_HALF_FLOAT, 4:
# cl.CL_FLOAT}[dt.itemsize])` -- keyed on the ITEMSIZE and not on the dtype, so an
# int16 and a half share CL_HALF_FLOAT and only a 4-byte dtype gets CL_FLOAT. A
# 1- or 8-byte image dtype is a `KeyError` in Python and 0 here.
def img.fmt_of(isz: U32) -> U32:
  match isz:
    case 2: CL_HALF_FLOAT()
    case 4: CL_FLOAT()
    case _: 0

# cl:63 `img = checked(cl.clCreateImage(self.dev.context, CL_MEM_READ_WRITE, fmt,
# desc, None, status), status)` -- the flags argument is CL_MEM_READ_WRITE, the
# SAME constant `alloc.of` hands `clCreateBuffer`, and the `arg` is the FORMAT.
def img.create(fmt: U32, +t: Tr) -> Tr: Tr.checked(OP_IMAGE(), U32.show(fmt), t)

# cl:59-64 -- `if is_image_shape(shape):` then pitch, fmt, desc, create, set. The
# `clCreateImage` comes BEFORE the `clSetKernelArg`, so an image row contributes
# TWO trace entries and every other row contributes one.
def prog.image.at(isimg: Bool, fmt: U32, +p: Prog) -> Prog:
  match isimg:
    case True{}: prog.with_t(p, img.create(fmt, Prog.t(p)))
    case False{}: p

# cl:57-65 -- the arg loop. It RECORDS one `Arg` per signature row and emits the
# `clSetKernelArg` for each, and the arg index is the enumerate index `i`.
def prog.arg_at(+i: U32, +s: Sig, +nbufs: U32, +p: Prog) -> Prog:
  +p2 = prog.image.at(Sig.isimg(s), img.fmt_of(Sig.isz(s)), p)
  prog.with(p2, Prog.sig(p2), List.append(&2, Arg, Prog.args(p2), [arg.of(i, s, nbufs)]),
            Prog.gsx(p2), Prog.gsy(p2), Prog.gsz(p2), Prog.lsx(p2), Prog.lsy(p2),
            Prog.lsz(p2), Prog.want(p2), Tr.emit(OP_SET_ARG(), U32.show(i), Prog.t(p2)))

def prog.args.go(xs: List<&2, Sig>, +i: U32, +nbufs: U32, +p: Prog) -> Prog:
  match xs:
    case Nil{}: p
    case s <> t: prog.args.go(t, U32.add(i, 1), nbufs, prog.arg_at(i, s, nbufs, p))

# cl:60 `pitch = (round_up(shape[1], 256) if OSX else shape[1]) * 4 *
# dt.itemsize` -- the ONLY `round_up` in the three files, keyed on `OSX`, and it
# multiplies by FOUR and then by the itemsize, so it is a ROW PITCH in bytes and
# not a channel count. `shape[1]` is `Sig.w` -- the SAME number cl:62 hands the
# descriptor as its width -- so the pitch rounds `Sig.w` and NOT `Sig.h`.
# `Sig.of(0, 16, 2, True{}, 257, 4)` is a 257-row 4-wide HALF image, so its pitch
# is round_up(4, 256) * 4 * 2 = 2048 and NOT 4096. MEASURED: rounding `Sig.h`
# instead gives 4096 and moves the `img_desc_w_16_8` row too, because both read the
# same field.
def cl.PITCH_ALIGN() -> U32: 256
def IMAGE_CHANNELS() -> U32: 4

def cl.pitch.at(osx: Bool, +w: U32, isz: U32) -> U32:
  U32.mul(U32.mul(Bool.pick(U32, osx, H.round_up_u32(w, cl.PITCH_ALIGN()), w),
                  IMAGE_CHANNELS()), isz)

def cl.pitch(osx: Bool, +s: Sig) -> U32: cl.pitch.at(osx, Sig.w(s), Sig.isz(s))

# cl:62 `desc = cl.cl_image_desc(cl.CL_MEM_OBJECT_IMAGE2D, shape[1], shape[0],
# image_row_pitch=pitch, buffer=b)` -- WIDTH is shape[1] and HEIGHT is shape[0],
# i.e. the OpenCL descriptor's two extents are the Python shape's LAST TWO in the
# opposite order, because a CL image is row-pitched and a numpy shape is
# row-major. Two separate defs so the swap is gateable on its own.
def img.desc_kind() -> U32: CL_MEM_OBJECT_IMAGE2D()
def img.desc_w(+s: Sig) -> U32: Sig.w(s)
def img.desc_h(+s: Sig) -> U32: Sig.h(s)

# cl:66 `global_size = cast(tuple[int,int,int], tuple(int(g*l) for g,l in
# zip(global_size, local_size)))` -- the dispatch geometry is the PRODUCT per
# axis, and it OVERWRITES the parameter: the LOCAL size is still what cl:69 hands
# to `clEnqueueNDRangeKernel`.
def cl.geom(g: U32, l: U32) -> U32: U32.mul(g, l)

def prog.geometry(+p: Prog, +sigs: List<&2, Sig>, gx: U32, gy: U32, gz: U32,
                  +lx: U32, +ly: U32, +lz: U32, +want: Bool) -> Prog:
  match p:
    case Prog{vendor, unit, ctx, prg, kernel, entry, s0, a0, x0, y0, z0, l0, m0, n0, w0, t0}:
      Prog{vendor, unit, ctx, prg, kernel, entry, sigs, a0,
           cl.geom(gx, lx), cl.geom(gy, ly), cl.geom(gz, lz), lx, ly, lz, want, t0}

# cl:68 `check(clEnqueueNDRangeKernel(self.dev.queue, self.kernel,
# len(global_size), None, gs, ls, 0, None, event))` -- `work_dim` is
# `len(global_size)`, which is 3 at every call site because `global_size` is a
# 3-tuple by default.
def cl.launch(dims: U32, +t: Tr) -> Tr: Tr.emit(OP_LAUNCH(), U32.show(dims), t)

# cl:72 `check(clWaitForEvents(1, event))` -- ONE event, so the arg is 1.
def cl.wait_events(n: U32, +t: Tr) -> Tr: Tr.emit(OP_WAIT_EVENT(), U32.show(n), t)

# cl:73-74 -- TWO `clGetEventProfilingInfo` calls whose `arg` is the profiling
# PARAM, START then END. Two entries on one op with two different args is why the
# param is on the trace and why a count row cannot tell them apart.
def cl.profiling(param: U32, +t: Tr) -> Tr: Tr.emit(OP_TIME_END(), U32.show(param), t)

# cl:67 `event = cl.cl_event() if wait else None` -- no call, and it is what
# decides whether the `wait` block below exists at all.
def prog.time.at(+want: Bool, +p: Prog) -> Prog:
  match want:
    case False{}: p
    case True{}:
      +t1 = cl.wait_events(1, Prog.t(p))
      +t2 = cl.profiling(CL_PROFILING_COMMAND_START(), t1)
      prog.with_t(p, cl.profiling(CL_PROFILING_COMMAND_END(), t2))

def prog.launch(+want: Bool, +p: Prog) -> Prog:
  prog.time.at(want, prog.with_t(p, cl.launch(3, Prog.t(p))))

# cl:55-76 -- the step order IS the order of the Python.
def prog.call.at(+sigs: List<&2, Sig>, nbufs: U32, gx: U32, gy: U32, gz: U32,
                lx: U32, ly: U32, lz: U32, +want: Bool, +p0: Prog) -> Prog:
  +p1 = prog.args.go(sigs, 0, nbufs, p0)
  prog.launch(want, prog.geometry(p1, sigs, gx, gy, gz, lx, ly, lz, want))

# ===========================================================================
# cl:78-89 -- `CLAllocator`. Four methods, and the ASYMMETRY between them is the
# content: `_copyout` calls `self.dev.synchronize()` and `_copyin` does not, and
# `_free` calls nothing at all.
# ===========================================================================

# cl:80 `BufferStorage(checked(clCreateBuffer(self.dev.context, CL_MEM_READ_WRITE,
# size, None, status), status))` -- the `arg` is the SIZE, so `cl_alloc_args`
# reads the size straight out of the trace rather than out of the record.
def alloc.of(+size: U32, +t: Tr) -> Made:
  Made{Buf{Tr.here(t), size}, Tr.checked(OP_ALLOC(), U32.show(size), t)}

# cl:83 `check(cl.clReleaseMemObject(storage.buf))`, under `@suppress_finalizing`.
# The `arg` is the buffer HANDLE, so the trace says which buffer was freed.
def alloc.free(+m: Made) -> Tr: Tr.emit(OP_FREE(), U32.show(Buf.id(Made.buf(m))), Made.tr(m))

# cl:85-86 -- `self.dev.pending_copyin.append(src := memoryview(bytearray(src)))`
# then `check(clEnqueueWriteBuffer(self.dev.queue, dest, False, 0,
# len(src)*src.itemsize, from_mv(src), 0, None, None))`. The APPEND comes first
# and it is what the NOTE at :85 is about: "these can't be freed until the GPU
# actually executes this command". So `_copyin` grows `pending_copyin` and the
# `arg` is `len(src)*src.itemsize`.
def copy.copyin(nbytes: U32, +t: Tr) -> Tr: Tr.emit(OP_COPY_IN(), U32.show(nbytes), t)

# cl:89 `self.dev.synchronize()` -- the append that `_copyin` made is released
# here, so the COUNT of pending copies is what `synchronize` clears.
def copy.pending_clear(d: Dev) -> Dev:
  match d:
    case Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}:
      Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, 0, t}

# cl:128-130 -- `synchronize` is `check(cl.clFinish(self.queue))` followed by
# `self.pending_copyin.clear()`. TWO things, and the second is the only reason the
# first can drop the host memory.
def cl.sync(+t: Tr) -> Tr: Tr.emit(OP_FINISH(), "0", t)

# cl:87-88 -- `check(clEnqueueReadBuffer(self.dev.queue, src, False, 0,
# len(dest)*dest.itemsize, from_mv(dest), 0, None, None))` then :89's synchronize.
# So the READ is enqueued and THEN the queue is finished, and `copy.copyout` is
# the ONLY transfer that synchronises.
def copy.copyout(nbytes: U32, +t: Tr) -> Tr: cl.sync(Tr.emit(OP_COPY_OUT(), U32.show(nbytes), t))

# cl:126 `def count(self) -> int: return len(unwrap(self.device_ids))` -- no call
# at all, and that is the row: `cl_count_gpu` is the probe's `n` and the trace has
# nothing to do with it.
def cl.count(p: Prb) -> U32: Prb.n(p)

# ===========================================================================
# helpers.py:37 -- `is_image_shape(shape)` is `shape is not None and len(shape) ==
# 3 and shape[-1] == 4`. The LAST dim is 4 and not the first, so `(4, 8, 8)` is a
# plain buffer and `(8, 8, 4)` is an image. Two fixtures and the difference is
# the whole of `img.is_image`.
# ===========================================================================

def img.is_image(ndim: U32, last: U32) -> Bool:
  Bool.and(U32.is_eq(ndim, 3), U32.is_eq(last, 4))

# cl:14 `OSX_TIMING_RATIO = (125/3) if OSX else 1.0` -- "it's in like GPU clocks or
# something". An F32, and the only F32 in the three files besides hp:57's.
def timing.ratio(osx: Bool) -> F32: Bool.pick(F32, osx, 41.666666666666664, 1.0)

# cl:75 `float(end.value - start.value) * OSX_TIMING_RATIO * 1e-9` -- the ns->s
# divisor and the ratio are portable and the u64 subtraction is WALL 2.
def timing.scale(osx: Bool) -> F32: F32.mul(timing.ratio(osx), 0.000000001)

# hp:57 `ret.value * 1e-3` -- the ms->s divisor, and it is a THIRD scale: the three
# vendors do not agree on a unit, and `timing_ns_scale_bits` beside
# `timing_hp_scale_bits` is the row that says so.
def timing.scale_hp() -> F32: 0.001

# ONE `Arg` as a string: `i:slot:kind:size:off`, joined with one space. A gate with
# five Bool columns and no structural row cannot see a swapped pair, and
# `cl_call_args_skew` is the structural row that can.
def arg.str(+a: Arg) -> String:
  String.concat([U32.show(Arg.i(a)), ":", U32.show(Arg.slot(a)), ":",
                 U32.show(Arg.kind(a)), ":", U32.show(Arg.size(a)), ":",
                 U32.show(Arg.off(a))])

def arg.strs.put(+a: Arg, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, [arg.str(a)])

def arg.strs.go(xs: List<&2, Arg>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case a <> t: arg.strs.go(t, arg.strs.put(a, acc))

def arg.strs(+xs: List<&2, Arg>) -> String: String.join(arg.strs.go(xs, Nil{}), " ")# ===========================================================================
# PART 2 -- CUDA. `ops_cuda.py`, all 136 lines.
#
# THE ONLY ONE OF THE THREE THAT IS NOT A SEQUENCE OF DRIVER CALLS. `CUDAQueue`
# is a COMMAND ENCODER: its six methods do not talk to the GPU, they append to a
# command buffer and remember the LAST handle they wrote in `self.h`. The index
# arithmetic on `rt_vars` -- `index(1)` for compute and `index(2)` for a COPY
# queue, `index(3)` for the status, `signal[1:2]` for the timestamp -- is the
# portable content, and it is a table.
# ===========================================================================

# `autogen/cuda.py`, read out. These four are the ones ops_cuda.py names
# explicitly; the rest of the enum is in `cu_err_code`.
def CU_STREAM_NON_BLOCKING() -> U32: 1
def CU_STREAM_WAIT_VALUE_GEQ() -> U32: 0
def CU_STREAM_WRITE_VALUE_DEFAULT() -> U32: 0

# cu:32 `self.rt_vars = UOp.placeholder((4,), dtypes.uint64, 0, device=self.devs,
# tag="cuda")` with the comment "# [context, compute stream, copy stream, status]".
# FOUR uint64 words and the comment names all four, which is the whole of the
# layout: the port indexes them by position.
def CU_RT_VARS() -> U32: 4
def CU_IDX_CTX() -> U32: 0
def CU_IDX_COMPUTE() -> U32: 1
def CU_IDX_COPY() -> U32: 2
def CU_IDX_STATUS() -> U32: 3

# cu:33 `self.kernargs = UOp.placeholder((8,), dtypes.uint8, device=self.devs)` --
# EIGHT bytes, one word, and that is why cu:43's kernargs descriptor is five
# uint64s and not five uint32s.
def CU_KERNARGS_BYTES() -> U32: 8

# cu:109 `range(2)` -- the two streams, and it is the only `range(n)` in the file.
def cu_nstreams_() -> U32: 2

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
        arch: String, tag: U32, t: Tr}

def CuDev.of() -> CuDev: CuDev{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "", 0, Tr.of()}

def CuDev.didx(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: didx

def CuDev.ctx(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: ctx

def CuDev.maj(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: maj

def CuDev.min(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: min

def CuDev.arch(d: CuDev) -> String:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: arch

def CuDev.tag(d: CuDev) -> U32:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: tag

def CuDev.t(d: CuDev) -> Tr:
  match d:
    case CuDev{didx, ctx, maj, min, s0, s1, ncaps, cap0, cap1, cap2, cap3, arch, tag, t}: t

# cu:104 `device_id = int(device.split(":")[1]) if ":" in device else 0` -- the
# SAME `":"` split as cl:104 and with the same default, so `cl_dev_index` answers
# it for both vendors and `cu_didx_*` is the row that says the two AGREE.
def cu_didx(+device: String) -> U32: cl_dev_index(device)

# cu:106 `check(cuda.cuDeviceGet(ctypes.byref(x), device_id))`.
def CU_TAG_CUDA() -> U32: 1
def CU_TAG_STAMP() -> U32: 2
def CU_TAG_FUNC() -> U32: 3
def CU_TAG_NONE() -> U32: 0

def CU_NAME_FN() -> String: "b"
def CU_TAGWORD_FUNCTION() -> String: "function"
def CU_TAGWORD_COMPUTE() -> String: "submit_cuda_compute"
def CU_TAGWORD_COPY() -> String: "submit_cuda_copy"

# cu:99-100 `pm_encode` is TWO rules that differ ONLY in the tag string, and both
# build `encode_submit(CUDAQueue(submit))`. So the dispatch is a two-entry table
# and `cu_encode_tags` is the row that prints it.
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

def cu.init.dev(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICES(), U32.show(0), t)

# cu:107 `self.context = init_c_var(cuda.CUcontext, lambda x:
# check(cuda.cuCtxCreate_v2(ctypes.byref(x), 0, self.cu_device)))` -- the `arg` is
# the second argument, 0, which is cuCtxCreate's FLAGS.
def cu.init.ctx(+t: Tr) -> Tr: Tr.emit(OP_CTX_CREATE(), "0", t)

# cu:105 `check(cuda.cuInit(0))` -- the ONE call in the three files that is an
# initialisation of the DRIVER rather than of a device, and it has no CL or HIP
# spelling at all: `vend.init_*` is "" in all three columns.
def cu.init.drv(+t: Tr) -> Tr: Tr.emit(OP_INIT(), "0", t)

# cu:108 `check(cuda.cuDeviceComputeCapability(ctypes.byref(major),
# ctypes.byref(minor), device_id))` -- the `arg` is the DEVICE ID and the major and
# minor are what cu:110's `sm_{major}{minor}` is made of.
def cu.compute_cap(did: U32, +t: Tr) -> Tr: Tr.emit(OP_COMPUTE_CAP(), U32.show(did), t)

# cu:109 `[init_c_var(cuda.CUstream, lambda x:
# check(cuda.cuStreamCreate(ctypes.byref(x), cuda.CU_STREAM_NON_BLOCKING))) for _
# in range(2)]` -- TWO streams, flags NON_BLOCKING, and `range(2)` is the one
# `list(range(n))` over a `U32` in the three files.
def cu.stream_create(i: U32, +t: Tr) -> Tr:
  Tr.emit(OP_QUEUE_CREATE(), U32.show(CU_STREAM_NON_BLOCKING()), t)

def cu.nstreams_of(d: CuDev) -> U32: U32.add(Bool.to_u32(U32.is_zero(CU_IDX_COPY())), 1)

# cu:110 `super().__init__(device, CUDAAllocator(self), [CUDARenderer,
# PTXRenderer, NVCCRenderer], None, arch=f"sm_{major.value}{minor.value}")` -- the
# ONLY arch string in the file, and it is a `f"sm_{a}{b}"` with NO separator, which
# is why a capability of 9 and 0 is `sm_90` and not `sm_9.0`.
def cu.arch_prefix() -> String: "sm_"

def cu.arch_of(+maj: U32, +min: U32) -> String:
  String.concat([cu.arch_prefix(), U32.show(maj), U32.show(min)])

# cu:103-110 -- the init sequence, in order: cuInit, cuDeviceGet,
# cuCtxCreate_v2, cuDeviceComputeCapability, then TWO cuStreamCreate. SIX calls.
def cu.init(+device: String, +maj: U32, +min: U32, +t: Tr) -> CuDev:
  +t1 = cu.init.drv(t)
  +t2 = cu.init.dev(t1)
  +t3 = cu.init.ctx(t2)
  +t4 = cu.compute_cap(cu_didx(device), t3)
  +t5 = cu.stream_create(0, t4)
  +t6 = cu.stream_create(1, t5)
  CuDev{cu_didx(device), Tr.here(t2), maj, min, Tr.here(t4), Tr.here(t5),
        cu_handle_words(), Tr.here(t1), Tr.here(t4), Tr.here(t5), cu_handles_tail(),
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

# cu:38 `def extern(self, tag) -> UOp: return UOp.placeholder((1,),
# dtypes.uint64, 0, device=self.devs, tag=tag).getaddr(self.dev.host)` -- ONE
# uint64 placeholder per extern, and the tag is what the trace records.
def cu.extern(slot: U32, +t: Tr) -> Tr: Tr.emit(OP_HOST_FUNC(), U32.show(slot), t)

# cu:34 `self.h = ccall(cuda.cuCtxSetCurrent, self.rt_vars.index(0).load())` --
# the queue's FIRST call, and it reads rt_vars index 0, the CONTEXT.
def cu.q_init(+t: Tr) -> Tr: Tr.emit(OP_CTX_SET(), U32.show(CU_IDX_CTX()), t)

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
# self.stream, UOp.const(0, dtypes.uint64), self.kernargs.index(extra))`. The `arg`
# is the kernargs OFFSET, and it is the only traced number that is a real memory
# offset in the file.
def cu.launch(extra: U32, +t: Tr) -> Tr: Tr.emit(OP_LAUNCH(), U32.show(extra), t)

# cu:54-55 `copy` -- `ccall(cuda.cuMemcpyAsync, dst.getaddr(self.devs),
# src.getaddr(self.devs), UOp.const(sz, dtypes.uint64), self.stream)`. The `arg`
# is the BYTE COUNT and it is the only one of the six queue calls whose traced
# argument is not a slot index.
def cu.copy(sz: U32, +t: Tr) -> Tr: Tr.emit(OP_COPY_IN(), U32.show(sz), t)

# cu:57-58 `wait` -- `ccall(cuda.cuStreamWaitValue64_v2, self.stream,
# signal.getaddr(self.devs), value, cuda.CU_STREAM_WAIT_VALUE_GEQ)`.
def cu.wait(+t: Tr) -> Tr: Tr.emit(OP_WAIT_VALUE(), U32.show(CU_STREAM_WAIT_VALUE_GEQ()), t)

# cu:60-61 `signal` -- the same shape with CU_STREAM_WRITE_VALUE_DEFAULT. Both
# constants are 0, which MEASURED, so `cu_signal_arg` and `cu_wait_arg` are equal
# and the only way to tell the two calls apart in the trace is the OP.
def cu.signal(+t: Tr) -> Tr: Tr.emit(OP_SIGNAL(), U32.show(CU_STREAM_WRITE_VALUE_DEFAULT()), t)

# cu:63-64 `timestamp` -- `ccall(cuda.cuLaunchHostFunc, self.stream,
# self.extern("stamp"), signal[1:2].getaddr(self.devs))` and the comment "a slot
# is [signal][timestamp]". The `[1:2]` is a SLOT INDEX, not an offset: the
# timestamp is the second element of the signal's own vector.
def CU_SIGNAL_SLOT() -> U32: 1

def cu.timestamp(+t: Tr) -> Tr: Tr.emit(OP_HOST_FUNC(), U32.show(CU_SIGNAL_SLOT()), t)

# cu:66 `submit` -- `return self.rt_vars.after(self.h).index(3).store(
# self.h.cast(dtypes.uint64)).substitute({self.kernargs: ka})`. The `arg` is the
# STATUS slot, index 3, which is the only one of the four rt_vars indices that is
# written rather than read.
def cu.submit(+t: Tr) -> Tr: Tr.emit(OP_SIGNAL(), U32.show(CU_IDX_STATUS()), t)

# cu:49-52 `exec` -- `obj, bufs, vals = prg.to_elf(), get_call_arg_uops(call),
# get_call_var_uops(call, prg)` then the launch. `prg.arg.globals` and
# `prg.arg.vars` are the two SIZES the kernel-arg layout needs, and the address
# list is `[bufs[i].getaddr for i in prg.arg.globals] + [v.ccast(v.dtype) for v,
# var in zip(vals, prg.arg.vars)]` -- buffers THEN values, which is the same order
# as the CL signature walk.
def cu.exec(nbufs: U32, nvals: U32, +t: Tr) -> Tr:
  cu.launch(0, t)

# ===========================================================================
# `CUDAAllocator`, cu:71-95. `_alloc` has THREE branches and the third is the
# only one that is not an early return: `external_ptr`, then `host or
# cpu_access`, then device. Two of the three are `Bool.pick`s over one `Spec`.
# ===========================================================================

# cu:74 `if options.external_ptr: return BufferStorage(options.external_ptr)` --
# NO CALL AT ALL, and that is the row: the external branch traces nothing.
def cu.alloc.ext(ptr: U32, +t: Tr) -> Tr: t

# cu:75-76 `if options.host or options.cpu_access: ptr = init_c_var(
# ctypes.c_void_p, lambda x: check(cuda.cuMemHostAlloc(ctypes.byref(x), size, 0)))
# return BufferStorage(ptr, None, MMIOInterface(ptr, size))` -- the host branch,
# and it is the ONLY one of the three branches that returns an MMIOInterface.
def cu.alloc.host(size: U32, +t: Tr) -> Tr: Tr.emit(OP_ALLOC_HOST(), U32.show(size), t)

# cu:78 `return BufferStorage(init_c_var(cuda.CUdeviceptr, lambda x:
# check(cuda.cuMemAlloc_v2(ctypes.byref(x), size))).value)` -- the device branch.
def cu.alloc.dev(size: U32, +t: Tr) -> Tr: Tr.emit(OP_ALLOC(), U32.show(size), t)

# `options.host or options.cpu_access` is ONE test in Python over TWO fields, and
# the port keeps them as a `Data` record with a Bool.pick over the disjunction.
def spec.is_host(+s: Spec) -> Bool: Bool.or(Spec.host(s), Spec.cpu(s))

def cu.alloc.at(is_ext: Bool, is_host: Bool, size: U32, ptr: U32, +t: Tr) -> Tr:
  match is_ext:
    case True{}: cu.alloc.ext(ptr, t)
    case False{}:
      match is_host:
        case True{}: cu.alloc.host(size, t)
        case False{}: cu.alloc.dev(size, t)

def cu.alloc(size: U32, +s: Spec, +t: Tr) -> Tr:
  cu.alloc.at(Bool.not(U32.is_zero(Spec.ext(s))), spec.is_host(s), size, Spec.ext(s), t)

# cu:80-82 `_free` -- `self.dev.synchronize()` FIRST, then
# `check((cuda.cuMemFreeHost if options.host or options.cpu_access else
# cuda.cuMemFree_v2)(storage.buf))`. TWO calls and the ORDER is the content: the
# free waits for the device, and the CL `_free` does not wait at all.
def cu.free.at(is_host: Bool, host: U32, dev: U32, +t: Tr) -> Tr:
  match is_host:
    case True{}: Tr.emit(OP_FREE_HOST(), U32.show(host), t)
    case False{}: Tr.emit(OP_FREE(), U32.show(dev), t)

def cu.free(+s: Spec, +buf: U32, +t: Tr) -> Tr:
  cu.free.at(spec.is_host(s), buf, buf, cl.sync(t))

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
# CONSTANT CANNOT BE, so this is a HOST PARAMETER and not a port of a Python
# number. MEASURED, arm64 darwin: `mmap.PAGESIZE` is 16384, so the old comment's
# "4096 on every platform tinygrad supports" was false on the very machine this
# gate runs on. The VALUE is deliberately left at 4096 because that is what every
# platform CUDA actually runs on answers (x86-64 Linux and macOS), and 16384 would
# be wrong for all of them -- a 64K-page aarch64 Linux answers 65536. Nothing in
# this file consumes the constant: `cu.map_err.at` takes `aligned: Bool`, the
# seam's answer, and never computes the modulus. It is here so the SEAM has it,
# and `cu_page_size` prints it so the seam's reader can see which one it got.
def PAGE_SIZE() -> U32: 4096

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
def cu.map.at(registered: Bool, nbytes: U32, +t: Tr) -> Tr:
  match registered:
    case True{}: Tr.emit(OP_HOST_REGISTER(), U32.show(nbytes), t)
    case False{}: Tr.emit(OP_HOST_REGISTER(), U32.show(nbytes), t)

# cu:92 `return BufferStorage(host.addr, status == cuda.CUDA_SUCCESS)` -- the
# `meta` is "did this device register it", so it is a BOOL and not a handle.
def cu.map_ok(registered: Bool) -> Bool: Bool.not(registered)

# cu:94 `if mapping.meta: check(cuda.cuMemHostUnregister(mapping.buf))` -- the
# unmap is CONDITIONAL on meta, which is the same Bool, so an unmap of a mapping
# this device did not make traces nothing.
def cu.unmap.at(ours: Bool, buf: U32, +t: Tr) -> Tr:
  match ours:
    case True{}: Tr.emit(OP_HOST_UNREGISTER(), U32.show(buf), t)
    case False{}: t

# cu:119 `struct.pack("4Q", *[as_int(h) for h in (self.context, *self.streams)], 0)`
# -- FOUR uint64 words: the context, the TWO streams, and a trailing 0. The pack is
# WALL 6 and the COUNT is not, so `cu_handle_words` is 4 and `cu_handles_tail` is
# the trailing zero.
def cu.handles(d: CuDev) -> List<&2, U32>: [CuDev.ctx(d), 0, 0, 0]

# cu:117-122 `handles` and `stamp` are the two `cached_property` buffers, and
# cu:121-122's `stamp` is a `CUhostFn(host_stamp)` which is WALL 6. The TAG is
# what `pm_bufferize` matches on, so it is the portable half.
def cu.build.after(+t: Tr) -> Tr: Tr.emit(OP_KERNEL(), "0", t)

def cu.function(libn: U32, +t: Tr) -> Tr: cu.build.after(Tr.emit(OP_PRG_FROM_BIN(), U32.show(libn), t))

# cu:127-129 `check(cuCtxSetCurrent(self.context))`, then `cuModuleLoadData`,
# then `cuModuleGetFunction`. THREE calls, and the context-set is the one CUDA
# repeats on every entry point that touches memory.
def cu.function.ctx(+t: Tr) -> Tr: Tr.emit(OP_CTX_SET(), U32.show(0), t)

# cu:132 `def count(self) -> int: return init_c_var(ctypes.c_int, lambda x:
# check(cuda.cuDeviceGetCount(ctypes.byref(x)))).value`
def cu.count(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_COUNT(), "0", t)

# cu:134-136 `_wait_signal` -- `check(cuCtxSetCurrent(self.context))` then
# `check(cuCtxSynchronize())`, with the comment "a fault raises here". TWO calls
# and the SECOND is the one that raises, which is why the trace's truncation at
# `cuCtxSynchronize` IS the fault.
def cu.wait_signal(+t: Tr) -> Tr: cl.sync(Tr.emit(OP_CTX_SET(), "0", t))# ===========================================================================
# PART 3 -- HIP. `ops_hip.py`, all 71 lines.
#
# THE MOST DIFFERENT OF THE THREE and the smallest. Where CL sets one kernel
# argument at a time by pointer and CUDA packs a blob, HIP packs a C STRUCT: hp:39
# builds `c_args` ONCE from `init_c_struct_t` and then assigns `c_args.f{i}` and
# `c_args.v{i}` on every call. The struct's field NAMES and OFFSETS are therefore
# the portable content, and they are what `Arg.off` carries -- `0` for CL,
# `i*8` for HIP, and the `round_up` walk for CUDA.
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
  HpDev{didx: U32, arch: String, ev0: U32, ev1: U32, nevents: U32, t: Tr}

def HpDev.of() -> HpDev: HpDev{0, "", 0, 0, 2, Tr.of()}

def HpDev.didx(d: HpDev) -> U32:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: didx

def HpDev.arch(d: HpDev) -> String:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: arch

def HpDev.ev0(d: HpDev) -> U32:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: ev0

def HpDev.ev1(d: HpDev) -> U32:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: ev1

def HpDev.t(d: HpDev) -> Tr:
  match d:
    case HpDev{didx, arch, ev0, ev1, nevents, t}: t

# hp:14 `self.device_id = int(device.split(":")[1]) if ":" in device else 0` --
# the THIRD spelling of that line, and it is the same one: `cu_didx` and
# `cl_dev_index` answer it identically and `hp_didx_*` is the row that says so.
def hp_didx(device: String) -> U32: cl_dev_index(device)

# hp:15 `self.arch = init_c_var(hip.hipDeviceProp_t, lambda x:
# check(hip.hipGetDeviceProperties(x, self.device_id))).gcnArchName.decode()` --
# the `arg` is the device id and the arch is the driver's own STRING.
def hp.props(did: U32, +t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_PROPS(), U32.show(did), t)

# hp:16 `self.time_event_st, self.time_event_en = [init_c_var(hip.hipEvent_t,
# lambda x: hip.hipEventCreate(ctypes.byref(x), 0)) for _ in range(2)]` -- TWO
# events, flags 0, and NO `check`: this is the single unchecked `hip*` call in the
# three files, which is why `hp_unchecked` is exactly `[OP_QUEUE_CREATE]`.
def hp.event_create(i: U32, +t: Tr) -> Tr: Tr.emit(OP_QUEUE_CREATE(), "0", t)

# hp:23-24 `synchronize` is `check(hip.hipSetDevice(self.device_id))` then
# `check(hip.hipDeviceSynchronize())` -- TWO calls, where CL's is ONE and CUDA's
# is TWO with a different second. `hipDeviceSynchronize` takes NO argument, so its
# arg column is the constant "0" like every other zero-argument call here and NOT
# the device id -- the id is already the arg of the `hipSetDevice` in front of it.
def hp.set_device(did: U32, +t: Tr) -> Tr: Tr.emit(OP_SET_DEVICE(), U32.show(did), t)

def hp.sync(did: U32, +t: Tr) -> Tr: Tr.emit(OP_FINISH(), "0", hp.set_device(did, t))

def hp.device_sync(d: HpDev, +t: Tr) -> Tr: hp.sync(HpDev.didx(d), t)

# hp:20 `def count(self) -> int: return init_c_var(ctypes.c_int, lambda x:
# check(hip.hipGetDeviceCount(x))).value`
def hp.count(+t: Tr) -> Tr: Tr.emit(OP_GET_DEVICE_COUNT(), "0", t)

# hp:14-18 -- the init sequence: hipGetDeviceProperties, TWO hipEventCreate, and
# nothing else. FOUR calls, and the SUPER().__init__ at :18 makes no call.
def hp.init(device: String, arch: String, +t: Tr) -> HpDev:
  +did = hp_didx(device)
  +t1 = hp.props(did, t)
  +t2 = hp.event_create(0, t1)
  +t3 = hp.event_create(1, t2)
  HpDev{did, arch, Tr.here(t2), Tr.here(t3), 2, t3}

# ===========================================================================
# `HIPProgram`, hp:26-57. `__init__` is THREE calls and the FIRST is
# `hipSetDevice`, which CUDA also does per-entry-point and CL does NOT do at all.
# ===========================================================================

# hp:29 `check(hip.hipSetDevice(self.dev.device_id))` -- in `__init__`.
def hp.prog_init.dev(+t: Tr) -> Tr: Tr.emit(OP_SET_DEVICE(), "0", t)

# hp:30-31 `self.module = init_c_var(hip.hipModule_t, lambda x:
# check(hip.hipModuleLoadData(ctypes.byref(x), obj.lib)))` then
# `self.prg = init_c_var(hip.hipFunction_t, lambda x:
# check(hip.hipModuleGetFunction(ctypes.byref(x), self.module, obj.name.encode())))
def hp.prog_init.prg(libn: U32, +t: Tr) -> Tr: Tr.emit(OP_PRG_FROM_BIN(), U32.show(libn), t)

def hp.prog_init.fn(name: String, +t: Tr) -> Tr: Tr.emit(OP_KERNEL(), name, t)

# hp:33-35 `__del__` is `if hasattr(self, 'module'):
# check(hip.hipModuleUnload(self.module))` -- ONE call and ONE attribute, where
# CL's `__del__` is two calls and two attributes. `hp_prog_del_bare` is the row for
# the `hasattr` being False.
def hp.prog_del(have: Bool, +t: Tr) -> Tr:
  match have:
    case True{}: Tr.emit(OP_RELEASE_PRG(), "0", t)
    case False{}: t

# hp:38 `check(hip.hipSetDevice(self.dev.device_id))` -- on EVERY call, which is
# the opposite of CL (once, in __init__) and of CUDA (once, in the queue's
# __init__).
def hp.call_set_device(did: U32, +t: Tr) -> Tr: Tr.emit(OP_SET_DEVICE(), U32.show(did), t)

# hp:49 `if wait: check(hip.hipEventRecord(self.dev.time_event_st, None))` and
# hp:54 the same for `time_event_en`. The `arg` is WHICH event, and it is the only
# way to tell the two apart -- the CL equivalent has two different profiling PARAMS
# for the same reason.
def hp.event_record(which: U32, +t: Tr) -> Tr: Tr.emit(OP_TIME_START(), U32.show(which), t)

# hp:51 `check(hip.hipModuleLaunchKernel(self.prg, *global_size, *local_size, 0,
# None, None, self.vargs))` -- the `arg` is the VARGS STRUCT SIZE, which is the one
# traced number here that is a real byte count.
def hp.launch(cargs_size: U32, +t: Tr) -> Tr: Tr.emit(OP_LAUNCH(), U32.show(cargs_size), t)

# hp:55-56 `check(hip.hipEventSynchronize(self.dev.time_event_en))` then
# `check(hip.hipEventElapsedTime(ctypes.byref(ret), self.dev.time_event_st,
# self.dev.time_event_en))`. TWO calls where CL has THREE, and the elapsed call's
# argument is the pair of EVENTS, not a profiling param.
def hp.event_sync(which: U32, +t: Tr) -> Tr: Tr.emit(OP_WAIT_EVENT(), U32.show(which), t)

def hp.event_elapsed(st: U32, en: U32, +t: Tr) -> Tr:
  Tr.emit(OP_TIME_END(), String.concat([U32.show(st), ":", U32.show(en)]), t)

# hp:39-44 -- the ONCE-ONLY construction of `c_args` and `vargs`. It is guarded by
# `if not hasattr(self, "vargs")`, so it happens on the first call and NOT on the
# second. It MAKES NO CALL -- the struct is built by ctypes, not by the driver --
# so `hp.build.at` returns the trace UNCHANGED on both arms and the gate pins that
# with a count: `hp_call_first_n` and `hp_call_second_n` are EQUAL.
def hp.build.at(built: Bool, +t: Tr) -> Tr:
  match built:
    case True{}: t
    case False{}: t

def hp.record.at(+want: Bool, built: Bool, +t: Tr) -> Tr:
  match want:
    case False{}: hp.build.at(built, t)
    case True{}: hp.event_record(0, hp.build.at(built, t))

def hp.elapsed.at(+want: Bool, +t: Tr) -> Tr:
  match want:
    case False{}: t
    case True{}: hp.event_elapsed(0, 1, hp.event_sync(1, t))

# hp:49-57 -- one call, as the step list it is: set-device, then the once-only
# struct build (no call), then the `if wait:` record, then the launch, then the
# `if wait:` synchronize/elapsed pair. So a non-waiting call is TWO trace entries
# and a waiting one is FIVE.
def hp.call.at(did: U32, cargs: U32, +want: Bool, built: Bool, +t: Tr) -> Tr:
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
def hp.alloc(did: U32, size: U32, +t: Tr) -> Tr: Tr.emit(OP_ALLOC(), U32.show(size), hp.call_set_device(did, t))

# hp:64 `_free` -- `check(hip.hipFree(storage.buf))`. ONE call and NO
# `synchronize()`, which is what makes HIP's `_free` differ from CUDA's and agree
# with CL's.
def hp.free(buf: U32, +t: Tr) -> Tr: Tr.emit(OP_FREE(), U32.show(buf), t)

# hipMemcpyKind. MEASURED out of `autogen/hip.py`'s enum: HostToDevice is 1 and
# DeviceToHost is 2, and the two are the ONLY argument HIP's `_copyin` and
# `_copyout` differ on -- the same struct, the same size, two calls.
def HIP_H2D() -> U32: 1
def HIP_D2H() -> U32: 2

# hp:65-67 `_copyin` -- `check(hip.hipSetDevice(self.dev.device_id))` then
# `check(hip.hipMemcpy(dest, mv_address(src), len(src), hip.hipMemcpyHostToDevice))`.
def hp.copyin.at(did: U32, n: U32, +t: Tr) -> Tr:
  Tr.emit(OP_COPY_IN(), U32.show(n), hp.call_set_device(did, t))

def hp.copyin(did: U32, n: U32, +t: Tr) -> Tr: hp.copyin.at(did, n, t)

# hp:68-70 `_copyout` -- `self.dev.synchronize()` FIRST, then
# `check(hip.hipMemcpy(mv_address(dest), src, len(dest), hip.hipMemcpyDeviceToHost))`.
# So HIP copies out DEVICE-TO-HOST after synchronising, and CL copies out after
# synchronising too: the two agree and CUDA does neither.
def hp.copyout.at(did: U32, n: U32, +t: Tr) -> Tr:
  Tr.emit(OP_COPY_OUT(), U32.show(n), hp.device_sync(HpDev{did, "", 0, 0, 2, t}, t))

def hp.copyout(did: U32, n: U32, t: Tr) -> Tr: hp.copyout.at(did, n, t)

# hp:67 / hp:70 -- the memcpy KIND, which is the only thing that differs between the
# two copies, and it is a two-entry table.
def hp.memcpy_kind(is_out: Bool) -> U32: Bool.pick(U32, is_out, HIP_D2H(), HIP_H2D())

# hp:71 `def _offset(self, buf, size, offset): return
# hipDeviceptr_t(buf.value + offset)` -- a POINTER-TYPED SUM, and WALL 6. The
# arithmetic is `buf + offset` and that is what `hp_offset_sum` is; the `U32` it
# returns is the VALUE the pointer holds.
def hp_offset_sum(buf: U32, offset: U32) -> U32: U32.add(buf, offset)# ===========================================================================
# THE GATE. Every row is a claim about the TEXT of the three Python files, about
# a constant read out of `tinygrad/runtime/autogen/*.py`, or about a table those
# two things define. The row name says which Python line it is about, and where a
# row's value is a NAME it is printed as a STRING -- never as a Bool about a
# string, because `String.concat` drops a literal silently and a Bool cannot see
# that it did.
#
# THE FIXTURES.
#   `fx_gpu`    the OpenCL device with two extensions and pitch alignment 0.
#   `fx_def`    the same, with the device-type loop falling through to DEFAULT.
#   `fx_none`   the same, with the loop EXHAUSTED (every candidate zero devices).
#   `fx_img`    the same with `cl_khr_image2d_from_buffer` and alignment 128.
#   `sig3`      three GLOBAL buffers and ONE val -- the shape of a 2-input
#               1-output float kernel, which is what cstyle's OpenCL text names
#               `data0_4, data1_4`.
#   `sig_img`   the same with ONE of the buffers an image (16x8, half).
#   `sig_skew`  the same with the SLOTS not the positions, which is what separates
#               cl:57's `enumerate` index from cl:58's `slot`.
# ===========================================================================

def brow(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

def ssh(xs: List<&2, String>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ssh(t, sep, x <> acc)

def srowlist(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ssh(xs, ",", Nil{}), ",")]))

# --- 1: the vendor table, the three files' whole call vocabulary -----------
def t_vend() -> IO(Unit):
  do IO<Unit>:
    urow("vend_count_cl", vend.count(V_CL()))
    urow("vend_count_cuda", vend.count(V_CUDA()))
    urow("vend_count_hip", vend.count(V_HIP()))
    # the ABSENCES, which are the point of the table: an op only one vendor has,
    # and one that NO vendor has.
    srowlist("vend_names_cl", vend.cl())
    srowlist("vend_names_cu", vend.cu())
    srowlist("vend_names_hp", vend.hp())
    srowlist("vend_argnames", vend.argname())
    urow("vend_len_cl", U32.from_nat(List.length(&2, String, vend.cl())))
    urow("vend_len_cu", U32.from_nat(List.length(&2, String, vend.cu())))
    urow("vend_len_hp", U32.from_nat(List.length(&2, String, vend.hp())))
    urow("vend_len_argnames", U32.from_nat(List.length(&2, String, vend.argname())))
    urow("vend_op_n", OP_N())
    srow("vend_alloc_cl", vend.name(V_CL(), OP_ALLOC()))
    srow("vend_alloc_cu", vend.name(V_CUDA(), OP_ALLOC()))
    srow("vend_alloc_hp", vend.name(V_HIP(), OP_ALLOC()))
    srow("vend_setarg_cl", vend.name(V_CL(), OP_SET_ARG()))
    srow("vend_setarg_cu", vend.name(V_CUDA(), OP_SET_ARG()))
    srow("vend_setarg_hp", vend.name(V_HIP(), OP_SET_ARG()))
    srow("vend_relkernel_cl", vend.name(V_CL(), OP_RELEASE_KERNEL()))
    srow("vend_relkernel_cu", vend.name(V_CUDA(), OP_RELEASE_KERNEL()))
    srow("vend_relkernel_hp", vend.name(V_HIP(), OP_RELEASE_KERNEL()))
    srow("vend_relprg_cl", vend.name(V_CL(), OP_RELEASE_PRG()))
    srow("vend_relprg_cu", vend.name(V_CUDA(), OP_RELEASE_PRG()))
    srow("vend_relprg_hp", vend.name(V_HIP(), OP_RELEASE_PRG()))
    srow("vend_initext_cl", vend.name(V_CL(), OP_INIT()))
    srow("vend_initext_cu", vend.name(V_CUDA(), OP_INIT()))
    srow("vend_initext_hp", vend.name(V_HIP(), OP_INIT()))
    srow("vend_errstr_hp", vend.name(V_HIP(), OP_ERRSTR()))
    srow("vend_none_cl", vend.name(V_CL(), OP_NONE()))
    srow("vend_none_cu", vend.name(V_CUDA(), OP_NONE()))
    srow("vend_oob", vend.name(V_CL(), 39))

# --- 2: the check table, cu:17/34-64 and hp:16 and cl:98/105/114 ------------
def t_check() -> IO(Unit):
  do IO<Unit>:
    urow("vend_nchecked_cl", chk_count(V_CL()))
    urow("vend_nchecked_cu", chk_count(V_CUDA()))
    urow("vend_nchecked_hp", chk_count(V_HIP()))
    urow("cu_unchecked_n", U32.from_nat(List.length(&2, U32, cu_unchecked())))
    urow("hp_unchecked_n", U32.from_nat(List.length(&2, U32, hp_unchecked())))
    urow("cl_unchecked_n", U32.from_nat(List.length(&2, U32, cl_unchecked())))
    lrow("cu_unchecked_ops", cu_unchecked())
    lrow("hp_unchecked_ops", hp_unchecked())
    brow("chk_cu_launch", vend.checked(V_CUDA(), OP_LAUNCH()))
    brow("chk_cu_ctxset", vend.checked(V_CUDA(), OP_CTX_SET()))
    brow("chk_cu_alloc", vend.checked(V_CUDA(), OP_ALLOC()))
    brow("chk_hp_queue", vend.checked(V_HIP(), OP_QUEUE_CREATE()))
    brow("chk_hp_launch", vend.checked(V_HIP(), OP_LAUNCH()))
    brow("chk_cl_alloc", vend.checked(V_CL(), OP_ALLOC()))
    brow("cl_probe_checked", cl_probe_checked())
    brow("cl_info_checked", cl_info_checked())
    brow("cl_build_log_checked", cl_build_log_checked())

# --- 3: the error tables, cl:16 and cu:18 and hp:10 ------------------------
def t_err() -> IO(Unit):
  do IO<Unit>:
    urow("cl_err_n", cl_err_n())
    urow("cu_err_n", cu_err_n())
    urow("cl_err_aliases", cl_err_aliases())
    srow("cl_err_0", cl_err_msg(0))
    srow("cl_err_m1", cl_err_msg(4294967295))
    srow("cl_err_m2", cl_err_msg(4294967294))
    srow("cl_err_m3", cl_err_msg(4294967293))
    srow("cl_err_m19", cl_err_msg(4294967277))
    srow("cl_err_m30", cl_err_msg(4294967266))
    srow("cl_err_m72", cl_err_msg(4294967224))
    srow("cl_err_p999", cl_err_msg(999))
    # the four ALIASED codes -- 0, -1, -2 and -3 carry 9, 2, 2 and 2 names -- and
    # the comprehension keeps the LAST one, so these four rows are what pins WHICH
    # name survives. Without them `cl_err_step`'s "first hit wins" guard is
    # invisible: MEASURED, dropping it moved nothing until these four rows existed.
    srow("cl_err_alias_m3", cl_err_of(4294967293))
    srow("cl_err_alias_m2", cl_err_of(4294967294))
    srow("cl_err_alias_m1", cl_err_of(4294967295))
    srow("cl_err_alias_0", cl_err_of(0))
    srow("cu_err_0", cu_err_msg(0))
    srow("cu_err_1", cu_err_msg(1))
    srow("cu_err_712", cu_err_msg(712))
    srow("cu_err_777", cu_err_msg(777))
    srow("cu_err_999", cu_err_msg(999))
    srow("hp_err_0", hp_err_of(0))
    srow("hp_err_1", hp_err_of(1))
    srow("hp_err_999", hp_err_of(999))
    urow("cu_host_registered", CUDA_HOST_REGISTERED())
    urow("cu_success", CUDA_SUCCESS())

# --- 4: the integer printer, which is the only sign repair in the file -----
def t_print() -> IO(Unit):
  do IO<Unit>:
    srow("u32s_0", u32s(0))
    srow("u32s_7", u32s(7))
    srow("u32s_63", u32s(63))
    srow("u32s_100", u32s(100))
    srow("u32s_999", u32s(999))
    srow("u32s_712", u32s(712))
    srow("u32s_neg1", u32s(4294967295))
    srow("u32s_neg19", u32s(4294967277))
    urow("dec_len_0", dec_len(0))
    urow("dec_len_9", dec_len(9))
    urow("dec_len_10", dec_len(10))
    urow("dec_len_63", dec_len(63))
    urow("dec_len_64", dec_len(64))
    urow("dec_len_99", dec_len(99))
    urow("dec_len_100", dec_len(100))
    urow("dec_len_999", dec_len(999))
    urow("dec_len_1000", dec_len(1000))
    urow("dec_len_4294967295", dec_len(4294967295))
    srow("dgt_0", dgt(0))
    srow("dgt_9", dgt(9))
    # F32 constants are gated by their BIT PATTERN and not by `F32.show`: the two
    # lanes agree on `F32.bits` and on `struct.pack('<f')`, and `F32.show` prints
    # seven significant digits, which no CPython format reproduces. MEASURED on
    # both lanes against `struct.unpack('<I', struct.pack('<f', v))[0]`.
    urow("timing_ratio_off_bits", F32.bits(timing.ratio(False{})))
    urow("timing_ratio_on_bits", F32.bits(timing.ratio(True{})))
    urow("timing_ns_scale_bits", F32.bits(timing.scale(False{})))
    urow("timing_ns_scale_on_bits", F32.bits(timing.scale(True{})))
    urow("timing_hp_scale_bits", F32.bits(timing.scale_hp()))

# --- 5: the OpenCL INIT SEQUENCE, cl:93-124 --------------------------------
def EXTS_A() -> List<&2, String>: ["cl_khr_fp16", "cl_khr_int64_base_atomics"]
def EXTS_B() -> List<&2, String>: ["cl_khr_image2d_from_buffer", "cl_khr_fp16"]
def EXTS_C() -> List<&2, String>: ["cl_khr_fp16"]
def NAME() -> String: "Apple M2"
def DRV() -> String: "4.0"
def DEV0() -> String: ""
def DEV2() -> String: "OPENCL:2"
def DEV17() -> String: "OPENCL:17"

def fx_gpu() -> Dev: cl.init(Prb.seed([2, 1]), DEV0(), NAME(), DRV(), EXTS_C(), 0, Tr.of())
def fx_def() -> Dev: cl.init(Prb.seed([0, 3]), DEV0(), NAME(), DRV(), EXTS_C(), 0, Tr.of())
def fx_img() -> Dev: cl.init(Prb.seed([2, 1]), DEV0(), NAME(), DRV(), EXTS_B(), 128, Tr.of())
def fx_none() -> Dev: cl.init(Prb.seed([0, 0]), DEV0(), NAME(), DRV(), EXTS_C(), 0, Tr.of())

def t_clinit() -> IO(Unit):
  do IO<Unit>:
    srow("cl_init_trace", vend.trace(V_CL(), Tr.calls(Dev.t(fx_gpu()))))
    srow("cl_init_trace_def", vend.trace(V_CL(), Tr.calls(Dev.t(fx_def()))))
    srow("cl_init_trace_img", vend.trace(V_CL(), Tr.calls(Dev.t(fx_img()))))
    urow("cl_init_calls", Tr.n(Dev.t(fx_gpu())))
    urow("cl_init_calls_def", Tr.n(Dev.t(fx_def())))
    urow("cl_init_calls_img", Tr.n(Dev.t(fx_img())))
    urow("cl_init_platforms", Tr.count(OP_PLATFORMS(), Tr.calls(Dev.t(fx_gpu()))))
    urow("cl_init_getdevices", Tr.count(OP_GET_DEVICES(), Tr.calls(Dev.t(fx_gpu()))))
    urow("cl_init_getdevices_none", Tr.count(OP_GET_DEVICES(), Tr.calls(Dev.t(fx_none()))))
    urow("cl_init_ctx", Tr.count(OP_CTX_CREATE(), Tr.calls(Dev.t(fx_gpu()))))
    urow("cl_init_queue", Tr.count(OP_QUEUE_CREATE(), Tr.calls(Dev.t(fx_gpu()))))
    urow("cl_init_info", Tr.count(OP_GET_DEVICE_INFO(), Tr.calls(Dev.t(fx_gpu()))))
    urow("cl_init_info_img", Tr.count(OP_GET_DEVICE_INFO(), Tr.calls(Dev.t(fx_img()))))
    srowlist("cl_init_info_params", Tr.args(OP_GET_DEVICE_INFO(), Tr.calls(Dev.t(fx_img()))))
    urow("cl_probe_idx_gpu", Prb.idx(cl.probe_init(Prb.seed([2, 1]), Tr.of())))
    urow("cl_probe_idx_def", Prb.idx(cl.probe_init(Prb.seed([0, 3]), Tr.of())))
    urow("cl_probe_idx_none", Prb.idx(cl.probe_init(Prb.seed([0, 0]), Tr.of())))
    urow("cl_probe_n_gpu", Prb.n(cl.probe_init(Prb.seed([2, 1]), Tr.of())))
    urow("cl_probe_n_def", Prb.n(cl.probe_init(Prb.seed([0, 3]), Tr.of())))
    urow("cl_probe_n_none", Prb.n(cl.probe_init(Prb.seed([0, 0]), Tr.of())))
    urow("cl_probe_type_gpu", cl.dev_type(cl.probe_init(Prb.seed([2, 1]), Tr.of())))
    urow("cl_probe_type_def", cl.dev_type(cl.probe_init(Prb.seed([0, 3]), Tr.of())))
    urow("cl_probe_type_none", cl.dev_type(cl.probe_init(Prb.seed([0, 0]), Tr.of())))
    lrow("cl_types", cl_types())
    urow("cl_count_gpu", cl.count(cl.probe_init(Prb.seed([2, 1]), Tr.of())))
    urow("cl_count_none", cl.count(cl.probe_init(Prb.seed([0, 0]), Tr.of())))
    urow("cl_didx_empty", cl_dev_index(DEV0()))
    urow("cl_didx_0", cl_dev_index("OPENCL:0"))
    urow("cl_didx_2", cl_dev_index(DEV2()))
    urow("cl_didx_17", cl_dev_index(DEV17()))
    brow("cl_didx_colon", cl_has_colon(String.to_list(DEV2())))
    brow("cl_didx_nocolon", cl_has_colon(String.to_list(DEV0())))
    srow("cl_arch_none", Dev.arch(fx_gpu()))
    srow("cl_arch_img", Dev.arch(fx_img()))
    srow("cl_key", Dev.ckey(fx_gpu()))
    urow("cl_ctx_id", Dev.ctx(fx_gpu()))
    urow("cl_queue_id", Dev.q0(fx_gpu()))
    urow("cl_qflags", Dev.qflags(fx_gpu()))
    urow("cl_pending", Dev.pending(fx_gpu()))
    urow("cl_pending_after", Dev.pending(copy.pending_clear(fx_gpu())))

# --- 6: the arch string and the image tables, cl:120-123 and :60-62 --------
def t_climg() -> IO(Unit):
  do IO<Unit>:
    brow("cl_img_ext_a", cl.has_img_ext(EXTS_A()))
    brow("cl_img_ext_b", cl.has_img_ext(EXTS_B()))
    brow("cl_img_ext_c", cl.has_img_ext(EXTS_C()))
    srow("cl_arch_suffix_none", cl.arch_suffix(False{}, 128))
    srow("cl_arch_suffix_128", cl.arch_suffix(True{}, 128))
    srow("cl_ext_join_a", cl.ext_join(EXTS_A()))
    srow("cl_ext_join_b", cl.ext_join(EXTS_B()))
    urow("cl_pitch_align", cl.PITCH_ALIGN())
    urow("cl_channels", IMAGE_CHANNELS())
    urow("cl_pitch_noosx_8_8", cl.pitch(False{}, Sig.of(0, 32, 4, True{}, 8, 8)))
    urow("cl_pitch_osx_8_8", cl.pitch(True{}, Sig.of(0, 32, 4, True{}, 8, 8)))
    urow("cl_pitch_osx_1_1", cl.pitch(True{}, Sig.of(0, 16, 2, True{}, 1, 1)))
    urow("cl_pitch_osx_257_4", cl.pitch(True{}, Sig.of(0, 16, 2, True{}, 257, 4)))
    urow("cl_pitch_osx_4_257", cl.pitch(True{}, Sig.of(0, 16, 2, True{}, 4, 257)))
    urow("img_fmt_1", img.fmt_of(1))
    urow("img_fmt_2", img.fmt_of(2))
    urow("img_fmt_4", img.fmt_of(4))
    urow("img_fmt_8", img.fmt_of(8))
    urow("img_desc_kind", img.desc_kind())
    urow("img_desc_w_16_8", img.desc_w(Sig.of(0, 32, 4, True{}, 16, 8)))
    urow("img_desc_h_16_8", img.desc_h(Sig.of(0, 32, 4, True{}, 16, 8)))
    urow("img_desc_w_4_257", img.desc_w(Sig.of(0, 16, 2, True{}, 4, 257)))
    urow("img_desc_h_4_257", img.desc_h(Sig.of(0, 16, 2, True{}, 4, 257)))
    brow("img_is_image_3_4", img.is_image(3, 4))
    brow("img_is_image_3_1", img.is_image(3, 1))
    brow("img_is_image_2_4", img.is_image(2, 4))
    brow("img_is_image_4_4", img.is_image(4, 4))
    srow("ct_int8", ct.typename(8))
    srow("ct_int16", ct.typename(16))
    srow("ct_int32", ct.typename(32))
    srow("ct_int64", ct.typename(64))
    srow("ct_int7", ct.typename(7))
    urow("cl_ptr_sz", PTR_SZ())
    urow("arg_size_mem", arg.size(KIND_MEM(), 4))
    urow("arg_size_image", arg.size(KIND_IMAGE(), 4))
    urow("arg_size_scalar32", arg.size(KIND_SCALAR(), 4))
    urow("arg_size_scalar16", arg.size(KIND_SCALAR(), 2))
    urow("arg_kind_mem", arg.kind(Sig.of(0, 32, 4, False{}, 0, 0), 3))
    urow("arg_kind_scalar", arg.kind(Sig.of(3, 32, 4, False{}, 0, 0), 3))
    urow("arg_kind_image", arg.kind(Sig.of(1, 16, 2, True{}, 16, 8), 3))
    brow("arg_is_buf_0_3", arg.is_buf(0, 3))
    brow("arg_is_buf_3_3", arg.is_buf(3, 3))
    urow("arg_val_index_3_3", arg.val_index(3, 3))
    urow("arg_val_index_4_3", arg.val_index(4, 3))

def sig3() -> List<&2, Sig>:
  [Sig.of(0, 32, 4, False{}, 0, 0), Sig.of(1, 32, 4, False{}, 0, 0),
   Sig.of(2, 32, 4, False{}, 0, 0), Sig.of(3, 32, 4, False{}, 0, 0)]

def sig_img() -> List<&2, Sig>:
  [Sig.of(0, 32, 4, False{}, 0, 0), Sig.of(1, 16, 2, True{}, 16, 8),
   Sig.of(2, 32, 4, False{}, 0, 0), Sig.of(3, 32, 4, False{}, 0, 0)]

# the signature where the SLOTS are not the positions: TinyELF's slots are
# assignable (ops.py:1378 dedups them) so `slot` can skip, and that is the fixture
# that separates cl:57's `enumerate` index from cl:58's `slot`.
def sig_skew() -> List<&2, Sig>:
  [Sig.of(0, 32, 4, False{}, 0, 0), Sig.of(3, 32, 4, False{}, 0, 0),
   Sig.of(1, 32, 4, False{}, 0, 0), Sig.of(4, 32, 4, False{}, 0, 0)]

# --- 7: the compile and program-init sequences, cl:25-47 ------------------
def t_clprog() -> IO(Unit):
  do IO<Unit>:
    srow("cl_compile_trace", vend.trace(V_CL(), Tr.calls(comp.compile(Tr.of()))))
    srow("cl_compile_bad_trace", vend.trace(V_CL(), Tr.calls(comp.compile.bad(Tr.of()))))
    urow("cl_compile_calls", Tr.n(comp.compile(Tr.of())))
    urow("cl_compile_bad_calls", Tr.n(comp.compile.bad(Tr.of())))
    srowlist("cl_compile_prginfo", Tr.args(OP_PRG_INFO(), Tr.calls(comp.compile(Tr.of()))))
    srowlist("cl_compile_badlog", Tr.args(OP_BUILD_LOG(), Tr.calls(comp.compile.bad(Tr.of()))))
    srow("cl_compile_err", CL_COMPILE_ERR())
    +p : Prog <- IO.pure(Prog, prog.init(fx_gpu(), "k", 128, Tr.of(), sig3()))
    srow("cl_prog_init_trace", vend.trace(V_CL(), Tr.calls(Prog.t(p))))
    urow("cl_prog_init_calls", Tr.n(Prog.t(p)))
    urow("cl_prog_prg_id", Prog.prg(p))
    urow("cl_prog_kernel_id", Prog.kernel(p))
    urow("cl_prog_unit", Prog.unit(p))
    urow("cl_prog_ctx", Prog.ctx(p))
    srow("cl_prog_kernel_name", Prog.entry(p))
    srow("cl_prog_del_trace", vend.trace(V_CL(), Tr.calls(prog.del(p))))
    srow("cl_prog_del_nokernel", vend.trace(V_CL(), Tr.calls(prog.del(Prog.of(V_CL(), "k", Nil{})))))
    urow("cl_prog_del_full", Tr.n(prog.del(p)))
    urow("cl_prog_del_bare", Tr.n(prog.del(Prog.of(V_CL(), "k", Nil{}))))

# --- 8: ONE PROGRAM CALL, cl:55-76 -----------------------------------------
def fx_call3(want: Bool) -> Prog:
  prog.call.at(sig3(), 3, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, Tr.reset(Tr.of()), sig3()))

def fx_callimg(want: Bool) -> Prog:
  prog.call.at(sig_img(), 3, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, Tr.reset(Tr.of()), sig_img()))

def fx_callskew(want: Bool) -> Prog:
  prog.call.at(sig_skew(), 2, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, Tr.reset(Tr.of()), sig_skew()))

def t_clcall() -> IO(Unit):
  do IO<Unit>:
    +p : Prog <- IO.pure(Prog, fx_call3(False{}))
    +t : Tr <- IO.pure(Tr, Prog.t(p))
    srow("cl_call_trace", vend.trace(V_CL(), Tr.calls(t)))
    srow("cl_call_args", arg.strs(Prog.args(p)))
    srow("cl_call_trace_wait", vend.trace(V_CL(), Tr.calls(Prog.t(fx_call3(True{})))))
    srow("cl_call_args_img", arg.strs(Prog.args(fx_callimg(False{}))))
    srow("cl_call_args_skew", arg.strs(Prog.args(fx_callskew(False{}))))
    srow("cl_call_trace_img", vend.trace(V_CL(), Tr.calls(Prog.t(fx_callimg(False{})))))
    srow("cl_call_trace_skew", vend.trace(V_CL(), Tr.calls(Prog.t(fx_callskew(False{})))))
    urow("cl_call_calls", Tr.n(t))
    urow("cl_call_calls_wait", Tr.n(Prog.t(fx_call3(True{}))))
    urow("cl_call_setargs", Tr.count(OP_SET_ARG(), Tr.calls(t)))
    urow("cl_call_setargs_img", Tr.count(OP_SET_ARG(), Tr.calls(Prog.t(fx_callimg(False{})))))
    urow("cl_call_images", Tr.count(OP_IMAGE(), Tr.calls(Prog.t(fx_callimg(False{})))))
    urow("cl_call_images_3", Tr.count(OP_IMAGE(), Tr.calls(t)))
    urow("cl_call_gx", Prog.gsx(p))
    urow("cl_call_gy", Prog.gsy(p))
    urow("cl_call_gz", Prog.gsz(p))
    urow("cl_call_lsx", Prog.lsx(p))
    urow("cl_call_lsy", Prog.lsy(p))
    urow("cl_call_lsz", Prog.lsz(p))
    urow("cl_call_launch", Tr.count(OP_LAUNCH(), Tr.calls(t)))
    urow("cl_call_waitev", Tr.count(OP_WAIT_EVENT(), Tr.calls(t)))
    urow("cl_call_waitev_wait", Tr.count(OP_WAIT_EVENT(), Tr.calls(Prog.t(fx_call3(True{})))))
    urow("cl_call_time", Tr.count(OP_TIME_END(), Tr.calls(t)))
    urow("cl_call_time_wait", Tr.count(OP_TIME_END(), Tr.calls(Prog.t(fx_call3(True{})))))
    srowlist("cl_call_time_params", Tr.args(OP_TIME_END(), Tr.calls(Prog.t(fx_call3(True{})))))
    srowlist("cl_call_launch_arg", Tr.args(OP_LAUNCH(), Tr.calls(t)))
    srowlist("cl_call_setarg_args", Tr.args(OP_SET_ARG(), Tr.calls(t)))
    urow("cl_geom_8_4", cl.geom(8, 4))
    urow("cl_geom_1_1", cl.geom(1, 1))
    urow("cl_geom_0_5", cl.geom(0, 5))
    urow("cl_geom_1000_1000", cl.geom(1000, 1000))

# --- 9: the allocator, cl:78-89 and :126-130 -------------------------------
def t_clalloc() -> IO(Unit):
  do IO<Unit>:
    +a : Made <- IO.pure(Made, alloc.of(64, Tr.of()))
    srow("cl_alloc_trace", vend.trace(V_CL(), Tr.calls(Made.tr(a))))
    urow("cl_alloc_size", Buf.size(Made.buf(a)))
    urow("cl_alloc_id", Buf.id(Made.buf(a)))
    +f : Tr <- IO.pure(Tr, alloc.free(a))
    srow("cl_free_trace", vend.trace(V_CL(), Tr.calls(f)))
    srowlist("cl_free_args", Tr.args(OP_FREE(), Tr.calls(f)))
    +i : Tr <- IO.pure(Tr, copy.copyin(64, Tr.of()))
    srow("cl_copyin_trace", vend.trace(V_CL(), Tr.calls(i)))
    srowlist("cl_copyin_args", Tr.args(OP_COPY_IN(), Tr.calls(i)))
    +o : Tr <- IO.pure(Tr, copy.copyout(64, Tr.of()))
    srow("cl_copyout_trace", vend.trace(V_CL(), Tr.calls(o)))
    srowlist("cl_copyout_args", Tr.args(OP_COPY_OUT(), Tr.calls(o)))
    urow("cl_copyout_finishes", Tr.count(OP_FINISH(), Tr.calls(o)))
    urow("cl_copyin_finishes", Tr.count(OP_FINISH(), Tr.calls(i)))
    +sy : Tr <- IO.pure(Tr, cl.sync(Tr.of()))
    srow("cl_sync_trace", vend.trace(V_CL(), Tr.calls(sy)))

# --- 10: the REFUSAL paths, every `check` in the three files ---------------
# `bad_at` names the CALL ORDINAL at which `check` reports, and the trace is
# TRUNCATED from there -- which is the whole refusal model. `bad_at` is read AT
# EMIT TIME, so it must be armed BEFORE the calls happen: the first version armed
# a finished trace, all four rows printed the full nine calls and every flag was
# False. `bad_at` numbers the PROGRAM's own trace (which `Tr.reset` starts at
# zero), so 1 is `clCreateProgramWithBinary` and 5 is the first `clSetKernelArg`.
def fx_refuse.prog(bad_at: U32) -> Prog:
  prog.init(fx_gpu(), "k", 128, Tr.fail_at(Tr.reset(Tr.of()), bad_at), sig3())

def fx_refuse(bad_at: U32) -> Prog:
  prog.call.at(sig3(), 3, 8, 2, 1, 4, 1, 1, False{}, fx_refuse.prog(bad_at))

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : Prog <- IO.pure(Prog, fx_refuse(1))
    +b : Prog <- IO.pure(Prog, fx_refuse(2))
    +c : Prog <- IO.pure(Prog, fx_refuse(4))
    +d : Prog <- IO.pure(Prog, fx_refuse(5))
    +e : Prog <- IO.pure(Prog, fx_refuse(6))
    srow("cl_refuse_1_trace", vend.trace(V_CL(), Tr.calls(Prog.t(a))))
    srow("cl_refuse_2_trace", vend.trace(V_CL(), Tr.calls(Prog.t(b))))
    srow("cl_refuse_4_trace", vend.trace(V_CL(), Tr.calls(Prog.t(c))))
    srow("cl_refuse_5_trace", vend.trace(V_CL(), Tr.calls(Prog.t(d))))
    srow("cl_refuse_6_trace", vend.trace(V_CL(), Tr.calls(Prog.t(e))))
    urow("cl_refuse_1_calls", Tr.n(Prog.t(a)))
    urow("cl_refuse_2_calls", Tr.n(Prog.t(b)))
    urow("cl_refuse_4_calls", Tr.n(Prog.t(c)))
    urow("cl_refuse_5_calls", Tr.n(Prog.t(d)))
    urow("cl_refuse_6_calls", Tr.n(Prog.t(e)))
    urow("cl_refuse_5_setargs", Tr.count(OP_SET_ARG(), Tr.calls(Prog.t(d))))
    urow("cl_refuse_6_setargs", Tr.count(OP_SET_ARG(), Tr.calls(Prog.t(e))))
    urow("cl_refuse_5_launch", Tr.count(OP_LAUNCH(), Tr.calls(Prog.t(d))))
    urow("cl_refuse_6_launch", Tr.count(OP_LAUNCH(), Tr.calls(Prog.t(e))))
    urow("cl_refuse_5_args", U32.from_nat(List.length(&2, Arg, Prog.args(d))))
    urow("cl_refuse_6_args", U32.from_nat(List.length(&2, Arg, Prog.args(e))))
    urow("cl_refuse_5_calls_after_init", U32.sub(Tr.n(Prog.t(d)), PROG_INIT_N()))
    urow("cl_refuse_6_calls_after_init", U32.sub(Tr.n(Prog.t(e)), PROG_INIT_N()))
    brow("cl_refuse_1_flag", Tr.refused(Prog.t(a)))
    brow("cl_refuse_5_flag", Tr.refused(Prog.t(d)))
    brow("cl_refuse_0_flag", Tr.refused(Prog.t(fx_call3(False{}))))
    # the MATCHER pins itself first: a reversed pair must NOT match, an absent entry
    # must NOT match, and a real pair must. Five order rows are decorative
    # without these three.
    +t : Tr <- IO.pure(Tr, Prog.t(fx_call3(False{})))
    brow("cl_has_rejects_reverse", Bool.not(Tr.has(Tr.calls(t),
      [Call{OP_LAUNCH(), "3"}, Call{OP_WAIT_EVENT(), "1"}])))
    brow("cl_has_rejects_absent", Bool.not(Tr.has(Tr.calls(t), [Call{OP_LAUNCH(), "999"}])))
    brow("cl_has_rejects_arg", Bool.not(Tr.has(Tr.calls(t), [Call{OP_LAUNCH(), "4"}])))
    brow("cl_has_pair", Tr.has(Tr.calls(t), [Call{OP_SET_ARG(), "1"}, Call{OP_LAUNCH(), "3"}]))
    brow("cl_has_prefix", Tr.has(Tr.calls(t), [Call{OP_SET_ARG(), "0"}, Call{OP_SET_ARG(), "1"}]))

# ===========================================================================
# PART 4 -- CUDA. cu:17-136.
# ===========================================================================

def CUNAME() -> String: "NVIDIA GeForce RTX 4090"
def CUDEV0() -> String: ""
def CUDEV1() -> String: "CUDA:1"

def fx_cu() -> CuDev: cu.init(CUDEV1(), 8, 6, Tr.of())

def t_cuinit() -> IO(Unit):
  do IO<Unit>:
    srow("cu_init_trace", vend.trace(V_CUDA(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_calls", Tr.n(CuDev.t(fx_cu())))
    urow("cu_init_cuinit", Tr.count(OP_INIT(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_devget", Tr.count(OP_GET_DEVICES(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_ctx", Tr.count(OP_CTX_CREATE(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_cap", Tr.count(OP_COMPUTE_CAP(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_streams", Tr.count(OP_QUEUE_CREATE(), Tr.calls(CuDev.t(fx_cu()))))
    urow("cu_init_streams_n", cu_nstreams())
    srowlist("cu_init_stream_args", Tr.args(OP_QUEUE_CREATE(), Tr.calls(CuDev.t(fx_cu()))))
    srow("cu_arch_86", cu.arch_of(8, 6))
    srow("cu_arch_90", cu.arch_of(9, 0))
    srow("cu_arch_120", cu.arch_of(12, 0))
    srow("cu_arch_00", cu.arch_of(0, 0))
    urow("cu_didx_empty", cu_didx(CUDEV0()))
    urow("cu_didx_1", cu_didx(CUDEV1()))
    urow("cu_didx_17", cu_didx(DEV17()))
    brow("cu_didx_agrees_cl", U32.is_eq(cu_didx(CUDEV1()), cl_dev_index(CUDEV1())))
    urow("cu_rtvars", CU_RT_VARS())
    urow("cu_idx_ctx", CU_IDX_CTX())
    urow("cu_idx_compute", CU_IDX_COMPUTE())
    urow("cu_idx_copy", CU_IDX_COPY())
    urow("cu_idx_status", CU_IDX_STATUS())
    urow("cu_kernargs_bytes", CU_KERNARGS_BYTES())
    lrow("cu_handles", cu.handles(fx_cu()))
    urow("cu_handle_words", cu_handle_words())
    urow("cu_handles_tail", cu_handles_tail())
    urow("cu_tag_cuda", CU_TAG_CUDA())
    urow("cu_tag_stamp", CU_TAG_STAMP())
    urow("cu_tag_func", CU_TAG_FUNC())
    urow("cu_tag_none", CU_TAG_NONE())
    srowlist("cu_encode_tags", cu.encode_tags())
    urow("cu_encode_cuda", cu.encode_pick(CU_TAG_CUDA()))
    urow("cu_encode_stamp", cu.encode_pick(CU_TAG_STAMP()))
    urow("cu_encode_other", cu.encode_pick(CU_TAG_FUNC()))
    srow("cu_name_fn", CU_NAME_FN())
    srow("cu_tagword_function", CU_TAGWORD_FUNCTION())

# --- the queue, cu:28-66 ---------------------------------------------------
def t_cuqueue() -> IO(Unit):
  do IO<Unit>:
    urow("cu_stream_compute", cu.stream_slot("CUDA:0"))
    urow("cu_stream_copy", cu.stream_slot("COPY:0"))
    urow("cu_stream_queue", cu.stream_slot("QUEUE:0"))
    srow("cu_q_init_trace", vend.trace(V_CUDA(), Tr.calls(cu.q_init(Tr.of()))))
    # cu:43's `size = max([o + w.dtype.itemsize for o, w in rows], default=8) - 8`
    urow("cu_size_empty", cu.launch_size(Nil{}))
    urow("cu_size_one8", cu.launch_size([16]))
    urow("cu_size_one4", cu.launch_size([12]))
    urow("cu_size_two", cu.launch_size([12, 24]))
    urow("cu_size_three", cu.launch_size([12, 24, 40]))
    urow("cu_size_unsorted", cu.launch_size([40, 12, 24]))
    urow("cu_kernargs_base", CU_KERNARGS_BASE())
    urow("cu_desc_words", CU_DESC_WORDS())
    urow("cu_desc_bytes", CU_DESC_BYTES())
    urow("cu_desc_off", CU_DESC_OFF())
    urow("cu_extra_fresh", cu.kernarg_extra(CU_DESC_BYTES()))
    urow("cu_extra_44", cu.kernarg_extra(44))
    urow("cu_extra_84", cu.kernarg_extra(84))
    lrow("cu_desc_word_list", cu.desc_words())
    srow("cu_launch_trace", vend.trace(V_CUDA(), Tr.calls(cu.launch(44, Tr.of()))))
    srow("cu_copy_trace", vend.trace(V_CUDA(), Tr.calls(cu.copy(4096, Tr.of()))))
    srow("cu_wait_trace", vend.trace(V_CUDA(), Tr.calls(cu.wait(Tr.of()))))
    srow("cu_signal_trace", vend.trace(V_CUDA(), Tr.calls(cu.signal(Tr.of()))))
    srow("cu_timestamp_trace", vend.trace(V_CUDA(), Tr.calls(cu.timestamp(Tr.of()))))
    srow("cu_submit_trace", vend.trace(V_CUDA(), Tr.calls(cu.submit(Tr.of()))))
    srowlist("cu_wait_arg", Tr.args(OP_WAIT_VALUE(), Tr.calls(cu.wait(Tr.of()))))
    srowlist("cu_signal_arg", Tr.args(OP_SIGNAL(), Tr.calls(cu.signal(Tr.of()))))
    urow("cu_wait_geq", CU_STREAM_WAIT_VALUE_GEQ())
    urow("cu_signal_def", CU_STREAM_WRITE_VALUE_DEFAULT())
    urow("cu_wait_signal_eq", Bool.to_u32(U32.is_eq(CU_STREAM_WAIT_VALUE_GEQ(), CU_STREAM_WRITE_VALUE_DEFAULT())))
    urow("cu_signal_slot", CU_SIGNAL_SLOT())
    urow("cu_streams_nonblocking", CU_STREAM_NON_BLOCKING())
    srow("cu_exec_trace", vend.trace(V_CUDA(), Tr.calls(cu.exec(3, 1, Tr.of()))))
    srow("cu_wait_signal_trace", vend.trace(V_CUDA(), Tr.calls(cu.wait_signal(Tr.of()))))
    srow("cu_count_trace", vend.trace(V_CUDA(), Tr.calls(cu.count(Tr.of()))))
    srow("cu_function_trace", vend.trace(V_CUDA(), Tr.calls(cu.function(2048, Tr.of()))))

# --- the allocator, cu:71-95 -----------------------------------------------
def cu_alloc_trace(s: Spec, size: U32) -> Tr: cu.alloc(size, s, Tr.of())

def t_cualloc() -> IO(Unit):
  do IO<Unit>:
    srow("cu_alloc_dev", vend.trace(V_CUDA(), Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64))))
    srow("cu_alloc_host", vend.trace(V_CUDA(), Tr.calls(cu_alloc_trace(Spec.of(True{}, False{}, 0), 64))))
    srow("cu_alloc_cpu", vend.trace(V_CUDA(), Tr.calls(cu_alloc_trace(Spec.of(False{}, True{}, 0), 64))))
    srow("cu_alloc_ext", vend.trace(V_CUDA(), Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 4096), 64))))
    urow("cu_alloc_dev_n", Tr.n(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64)))
    urow("cu_alloc_ext_n", Tr.n(cu_alloc_trace(Spec.of(False{}, False{}, 4096), 64)))
    srowlist("cu_alloc_dev_args", Tr.args(OP_ALLOC(), Tr.calls(cu_alloc_trace(Spec.of(False{}, False{}, 0), 64))))
    srowlist("cu_alloc_host_args", Tr.args(OP_ALLOC_HOST(), Tr.calls(cu_alloc_trace(Spec.of(True{}, False{}, 0), 64))))
    srow("cu_free_dev", vend.trace(V_CUDA(), Tr.calls(cu.free(Spec.of(False{}, False{}, 0), 7, Tr.of()))))
    srow("cu_free_host", vend.trace(V_CUDA(), Tr.calls(cu.free(Spec.of(True{}, False{}, 0), 7, Tr.of()))))
    srow("cu_free_cpu", vend.trace(V_CUDA(), Tr.calls(cu.free(Spec.of(False{}, True{}, 0), 7, Tr.of()))))
    srow("cu_map_registered", vend.trace(V_CUDA(), Tr.calls(cu.map.at(True{}, 4096, Tr.of()))))
    srow("cu_map_new", vend.trace(V_CUDA(), Tr.calls(cu.map.at(False{}, 4096, Tr.of()))))
    brow("cu_map_ok_new", cu.map_ok(False{}))
    brow("cu_map_ok_reg", cu.map_ok(True{}))
    srow("cu_unmap_ours", vend.trace(V_CUDA(), Tr.calls(cu.unmap.at(True{}, 7, Tr.of()))))
    srow("cu_unmap_theirs", vend.trace(V_CUDA(), Tr.calls(cu.unmap.at(False{}, 7, Tr.of()))))
    urow("cu_page_size", PAGE_SIZE())
    srow("cu_map_err_other_nohost", cu.map_err(CUDEV1(), False{}, False{}, False{}))
    srow("cu_map_err_other_unaligned", cu.map_err(CUDEV1(), False{}, True{}, False{}))
    srow("cu_map_err_other_aligned", cu.map_err(CUDEV1(), False{}, True{}, True{}))
    srow("cu_map_err_cu_nohost", cu.map_err(CUDEV1(), True{}, False{}, False{}))
    srow("cu_map_err_cu_unaligned", cu.map_err(CUDEV1(), True{}, True{}, False{}))
    srow("cu_map_err_cu_aligned", cu.map_err(CUDEV1(), True{}, True{}, True{}))
    urow("cu_map_err_ctx_len", U32.from_nat(List.length(&2, String, Nil{})))
    urow("cu_map_err_len", U32.from_nat(List.length(&2, String, Nil{})))

# ===========================================================================
# PART 5 -- HIP. hp:9-71.
# ===========================================================================

def HPNAME() -> String: "gfx1100"
def HPDEV0() -> String: ""
def HPDEV2() -> String: "HIP:2"

def fx_hp() -> HpDev: hp.init(HPDEV0(), HPNAME(), Tr.of())

def t_hpinit() -> IO(Unit):
  do IO<Unit>:
    srow("hp_init_trace", vend.trace(V_HIP(), Tr.calls(HpDev.t(fx_hp()))))
    urow("hp_init_calls", Tr.n(HpDev.t(fx_hp())))
    urow("hp_init_props", Tr.count(OP_GET_DEVICE_PROPS(), Tr.calls(HpDev.t(fx_hp()))))
    urow("hp_init_events", Tr.count(OP_QUEUE_CREATE(), Tr.calls(HpDev.t(fx_hp()))))
    srowlist("hp_init_event_args", Tr.args(OP_QUEUE_CREATE(), Tr.calls(HpDev.t(fx_hp()))))
    srow("hp_arch", HpDev.arch(fx_hp()))
    urow("hp_nhandles", Tr.next(HpDev.t(fx_hp())))
    urow("hp_didx_empty", hp_didx(HPDEV0()))
    urow("hp_didx_2", hp_didx(HPDEV2()))
    brow("hp_didx_agrees_cl", U32.is_eq(hp_didx(HPDEV2()), cl_dev_index(HPDEV2())))
    srow("hp_sync_trace", vend.trace(V_HIP(), Tr.calls(hp.sync(0, Tr.of()))))
    srow("hp_count_trace", vend.trace(V_HIP(), Tr.calls(hp.count(Tr.of()))))
    srow("hp_prog_init_trace", vend.trace(V_HIP(), Tr.calls(hp.prog_init.fn("k",
      hp.prog_init.prg(128, hp.prog_init.dev(Tr.of()))))))
    srow("hp_prog_del_yes", vend.trace(V_HIP(), Tr.calls(hp.prog_del(True{}, Tr.of()))))
    srow("hp_prog_del_no", vend.trace(V_HIP(), Tr.calls(hp.prog_del(False{}, Tr.of()))))
    urow("hp_h2d", HIP_H2D())
    urow("hp_d2h", HIP_D2H())
    urow("hp_memcpy_kind_in", hp.memcpy_kind(False{}))
    urow("hp_memcpy_kind_out", hp.memcpy_kind(True{}))
    srow("hp_alloc_trace", vend.trace(V_HIP(), Tr.calls(hp.alloc(0, 64, Tr.of()))))
    srow("hp_free_trace", vend.trace(V_HIP(), Tr.calls(hp.free(7, Tr.of()))))
    srow("hp_copyin_trace", vend.trace(V_HIP(), Tr.calls(hp.copyin(0, 64, Tr.of()))))
    srow("hp_copyout_trace", vend.trace(V_HIP(), Tr.calls(hp.copyout(0, 64, Tr.of()))))
    urow("hp_offset_sum", hp_offset_sum(4096, 64))
    urow("hp_offset_sum_0", hp_offset_sum(4096, 0))

# --- the c_args struct, hp:39-44 -- THE THIRD VENDOR'S ARGUMENT LAYOUT -----
def t_hpargs() -> IO(Unit):
  do IO<Unit>:
    urow("hp_ptr_sz", HP_PTR_SZ())
    lrow("hp_buf_offsets_0", hp_buf_offsets(0n))
    lrow("hp_buf_offsets_1", hp_buf_offsets(1n))
    lrow("hp_buf_offsets_3", hp_buf_offsets(3n))
    lrow("hp_val_offsets_3_32", hp_val_offsets(3, [4, 4, 4, 4]))
    lrow("hp_val_offsets_3_mixed", hp_val_offsets(3, [4, 2, 8, 1]))
    lrow("hp_val_offsets_1_mixed", hp_val_offsets(1, [1, 2, 4]))
    lrow("hp_val_offsets_2_odd", hp_val_offsets(2, [2, 4]))
    lrow("hp_val_offsets_0", hp_val_offsets(0, [8]))
    urow("hp_cargs_size_0", hp.cargs_size(0, 0, 0))
    urow("hp_cargs_size_1_0_8", hp.cargs_size(0, 8, 1))
    urow("hp_cargs_size_3_24_4", hp.cargs_size(24, 4, 3))
    urow("hp_cargs_size_3_26_4", hp.cargs_size(26, 4, 3))
    urow("hp_cargs_size_3_32_4", hp.cargs_size(32, 4, 3))
    urow("hp_fields_3_4444", hp.fields(3n, [4, 4, 4, 4]))
    urow("hp_fields_3_mixed", hp.fields(3n, [4, 2, 8, 1]))
    urow("hp_fields_0_empty", hp.fields(0n, Nil{}))
    urow("hp_fields_3_novals", hp.fields(3n, Nil{}))
    urow("hp_fields_0_1val", hp.fields(0n, [4]))
    urow("hp_fields_1_1val", hp.fields(1n, [1]))
    urow("hp_vargs_words", HP_VARGS_WORDS())
    lrow("hp_vargs_list", hp.vargs_words(32))
    srow("hp_call_first_trace", vend.trace(V_HIP(), Tr.calls(hp.call.at(0, 32, False{}, False{}, Tr.of()))))
    srow("hp_call_wait_trace", vend.trace(V_HIP(), Tr.calls(hp.call.at(0, 32, True{}, False{}, Tr.of()))))
    srow("hp_call_second_trace", vend.trace(V_HIP(), Tr.calls(hp.call.at(0, 32, False{}, True{}, Tr.of()))))
    urow("hp_call_first_n", Tr.n(hp.call.at(0, 32, False{}, False{}, Tr.of())))
    urow("hp_call_wait_n", Tr.n(hp.call.at(0, 32, True{}, False{}, Tr.of())))
    urow("hp_call_second_n", Tr.n(hp.call.at(0, 32, False{}, True{}, Tr.of())))
    urow("hp_call_built_eq", Bool.to_u32(U32.is_eq(Tr.n(hp.call.at(0, 32, False{}, False{}, Tr.of())),
                                                Tr.n(hp.call.at(0, 32, False{}, True{}, Tr.of())))))
    srowlist("hp_call_elapsed_args", Tr.args(OP_TIME_END(), Tr.calls(hp.call.at(0, 32, True{}, False{}, Tr.of()))))
    srowlist("hp_call_launch_args", Tr.args(OP_LAUNCH(), Tr.calls(hp.call.at(0, 32, False{}, False{}, Tr.of()))))

# --- 12: the CROSS-VENDOR COMPARISON, which is the content of this file ----
def t_cross() -> IO(Unit):
  do IO<Unit>:
    # THE SAME OPERATION, THREE SPELLINGS: alloc, free, finish, copy-in,
    # copy-out, launch, and the set-context each vendor does.
    srow("x_alloc", String.join([
      vend.name(V_CL(), OP_ALLOC()), vend.name(V_CUDA(), OP_ALLOC()), vend.name(V_HIP(), OP_ALLOC())], "|"))
    srow("x_alloc_host", String.join([
      vend.name(V_CL(), OP_ALLOC_HOST()), vend.name(V_CUDA(), OP_ALLOC_HOST()),
      vend.name(V_HIP(), OP_ALLOC_HOST())], "|"))
    srow("x_free", String.join([
      vend.name(V_CL(), OP_FREE()), vend.name(V_CUDA(), OP_FREE()), vend.name(V_HIP(), OP_FREE())], "|"))
    srow("x_finish", String.join([
      vend.name(V_CL(), OP_FINISH()), vend.name(V_CUDA(), OP_FINISH()),
      vend.name(V_HIP(), OP_FINISH())], "|"))
    srow("x_copyin", String.join([
      vend.name(V_CL(), OP_COPY_IN()), vend.name(V_CUDA(), OP_COPY_IN()),
      vend.name(V_HIP(), OP_COPY_IN())], "|"))
    srow("x_copyout", String.join([
      vend.name(V_CL(), OP_COPY_OUT()), vend.name(V_CUDA(), OP_COPY_OUT()),
      vend.name(V_HIP(), OP_COPY_OUT())], "|"))
    srow("x_launch", String.join([
      vend.name(V_CL(), OP_LAUNCH()), vend.name(V_CUDA(), OP_LAUNCH()),
      vend.name(V_HIP(), OP_LAUNCH())], "|"))
    srow("x_setctx", String.join([
      vend.name(V_CL(), OP_CTX_SET()), vend.name(V_CUDA(), OP_CTX_SET()),
      vend.name(V_HIP(), OP_SET_DEVICE())], "|"))
    srow("x_wait", String.join([
      vend.name(V_CL(), OP_WAIT_EVENT()), vend.name(V_CUDA(), OP_WAIT_VALUE()),
      vend.name(V_HIP(), OP_WAIT_EVENT())], "|"))
    srow("x_time", String.join([
      vend.name(V_CL(), OP_TIME_END()), vend.name(V_CUDA(), OP_TIME_END()),
      vend.name(V_HIP(), OP_TIME_END())], "|"))
    srow("x_arglayout", String.join([
      vend.name(V_CL(), OP_SET_ARG()), vend.name(V_CUDA(), OP_SET_ARG()),
      vend.name(V_HIP(), OP_SET_ARG())], "|"))
    # THE THREE ARCH STRINGS, which are three different derivations of the same
    # `Compiled.__init__` argument.
    srow("x_arch_cl", Dev.arch(fx_img()))
    srow("x_arch_cu", cu.arch_of(8, 6))
    srow("x_arch_hp", HpDev.arch(fx_hp()))
    # THE THREE DEVICE-INDEX SPELLINGS, which agree.
    brow("x_didx_agrees", Bool.and(U32.is_eq(cl_dev_index(DEV2()), cu_didx(DEV2())),
                                   U32.is_eq(hp_didx(DEV2()), cu_didx(DEV2()))))
    # THE THREE `_free`s: CL waits for nothing, CUDA waits then frees, HIP frees
    # and waits for nothing. The three traces say so.
    srow("x_free_cl", vend.trace(V_CL(), Tr.calls(alloc.free(alloc.of(64, Tr.of())))))
    srow("x_free_cu", vend.trace(V_CUDA(), Tr.calls(cu.free(Spec.of(False{}, False{}, 0), 7, Tr.of()))))
    srow("x_free_hp", vend.trace(V_HIP(), Tr.calls(hp.free(7, Tr.of()))))
    # THE THREE `_copyout`s: CL enqueues then finishes, CUDA does neither, HIP
    # finishes then enqueues -- the SAME pair of calls in a DIFFERENT order.
    srow("x_copyout_cl", vend.trace(V_CL(), Tr.calls(copy.copyout(64, Tr.of()))))
    srow("x_copyout_hp", vend.trace(V_HIP(), Tr.calls(hp.copyout(0, 64, Tr.of()))))
    srow("x_copyin_cl", vend.trace(V_CL(), Tr.calls(copy.copyin(64, Tr.of()))))
    srow("x_copyin_hp", vend.trace(V_HIP(), Tr.calls(hp.copyin(0, 64, Tr.of()))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_vend()
    b : Unit <- t_check()
    c : Unit <- t_err()
    d : Unit <- t_print()
    e : Unit <- t_clinit()
    f : Unit <- t_climg()
    g : Unit <- t_clprog()
    h : Unit <- t_clcall()
    i : Unit <- t_clalloc()
    j : Unit <- t_refuse()
    k : Unit <- t_cuinit()
    l : Unit <- t_cuqueue()
    m : Unit <- t_cualloc()
    n : Unit <- t_hpinit()
    o : Unit <- t_hpargs()
    p : Unit <- t_cross()
    IO.print("cl-done=1")