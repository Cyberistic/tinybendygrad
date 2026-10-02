# tinybendygrad/runtime/ops_webgpu.bend -- port of tinygrad/runtime/ops_webgpu.py
#
# THE RUN SIDE OF THE BROWSER TARGET. ops_webgpu.py is wgpu-py: every call is a
# ctypes call into `tinygrad/runtime/autogen/webgpu.py`. In a browser those calls
# become JS-glue FFI, and what survives the crossing is the STRUCTURE -- device
# init, buffer upload/download, the per-call object graph, dispatch geometry,
# and the future-to-synchronous protocol. That structure is what this file
# ports. Every actual wgpu call is a `# TODO(p3) runtime/ops_webgpu.py:<line>`
# naming the JS import it becomes; nothing here calls wgpu.
#
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one wgpu call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :10  backend_types               PORTED  `backend_names`, `backend_of`
#   :11  the module-level instance    PORTED  `dev.create_instance`
#   :13  from_wgpu_str               WALL 1  STRING VIEWS
#   :14  to_wgpu_str                 WALL 1  STRING VIEWS
#   :17  buf_to_mv                   PORTED  `copy.read`
#   :23  synchronous                 PORTED  `sync_ret`, `sync_has_emsg`,
#                                             `sync_payload`, `sync_name`,
#                                             `sync_error`
#   :45  BufferMapAsync              PORTED  a WAIT, in `copy.read`
#   :46  DevicePopErrorScope         PORTED  a WAIT, in `Tr.pop`
#   :47  DeviceCreateComputePipeline PORTED  a WAIT, in `pass.pipeline`
#   :48  InstanceRequestAdapter      PORTED  a WAIT, in `dev.request_adapter`
#   :49  AdapterRequestDevice        PORTED  a WAIT, in `dev.request_device`
#   :50  QueueOnSubmittedWorkDone    DEAD   the only caller was `dev.synchronize`,
#                                             which nothing called. The status
#                                             enum is still in `sync_name`.
#   :53  WebGPUProgram.__init__      PORTED  `prog.init`
#   :67  __del__                     DEAD   `prog.del` reached nothing. This row
#                                             WAS what kept it alive: a PORTED
#                                             claim in this table is a use.
#   :71  wait                        PORTED  `prog.wants_wait`
#   :74  bgl_entry                   PORTED  `bgl.entry`
#   :77  bind_entries                PORTED  `bgl.of`  <- the layout derivation
#   :81  CreateBindGroupLayout       PORTED  `pass.layout`
#   :87  PipelineLayoutDescriptor    PORTED  `pass.playout`
#   :94  bg_entry                    PORTED  `pass.uniforms`
#   :99  CreateBindGroup             PORTED  `pass.group`
#   :105 ComputePipelineDescriptor   PORTED  `pass.pipeline`
#   :109 CreateCommandEncoder        PORTED  `pass.encoder`
#   :113 CreateQuerySet/CreateBuffer PORTED  `pass.query`
#   :120 beginComputePass            PORTED  `pass.begin`
#   :121-124 setPipeline/BindGroup/dispatch/end
#                                        PORTED  `pass.set`, `pass.dispatch`,
#                                                `pass.end`
#   :126 ResolveQuerySet             PORTED  `pass.resolve`
#   :128-129 finish/submit           PORTED  `pass.finish`
#   :132-138 the seven releases      PORTED  `pass.release`
#   :141 the timestamp arithmetic    WALL 2  THE 64-BIT WALL
#   :150 _alloc                      PORTED  `alloc.of`
#   :154 _copyin                     PORTED  `copy.copyin`
#   :159 _copyout                    DEAD   `copy.copyout` reached nothing
#   :163 _free                       DEAD   `alloc.free` died with its only
#                                             caller. `dev.free` below is the
#                                             same Python branch and IS ported.
#   :166-190 WebGpuDevice.__init__   PORTED  `dev.init`
#   :192 synchronize                 DEAD   `dev.synchronize` reached nothing
#   :195-198 free                    PORTED  `dev.free`
#   :200 pop_error                   PORTED  `Tr.pop` (see THE PAYLOAD)
#   :201-205 create_uniform           PARTIAL `dev.create_uniform`, int arm only
#   :206-219 _readable_buffer        PORTED  `copy.readable`
#   :220-221 write_buffer            PORTED  `copy.write`
#
# ===========================================================================
# THE THREE WALLS.
#
# 1. STRING VIEWS (:13-14). `ctypes.string_at(sv.data, sv.length)` and
#    `create_string_buffer(s.encode())`. A WGPUStringView is a (pointer, length)
#    pair the seam frees as soon as the callback returns -- which is why :34
#    converts INSIDE the callback. The port keeps the String and drops the pair,
#    because a String is what the entry point's NAME is (:54) and what the error
#    message is, and both are read immediately.
#    TODO(p3) runtime/ops_webgpu.py:13  -- WGPUStringView -> String.
#    TODO(p3) runtime/ops_webgpu.py:14  -- String -> WGPUStringView.
#
# 2. THE 64-BIT WALL, and it is two lines of Python.
#      :37  `wgpuInstanceWaitAny(instance, 1, WGPUFutureWaitInfo(future), 2**64-1)`
#      :141 `((timestamps:=…)[1] - timestamps[0]) / 1e9`
#    The query set answers two TIMESTAMPS in NANOSECONDS as u64 and
#    `buf_to_mv(...).cast("Q")` reads them as such. Bend has no 64-bit integer
#    (`base.bend` exports `Word`, not `Word(64n)`) and no F64, so neither the
#    unbounded wait timeout nor the delta is computable here. The seam must hand
#    over the ALREADY-SCALED seconds, because the only thing this port can do
#    with a time is print it.
#    TODO(p3) runtime/ops_webgpu.py:37  -- the 2**64-1 wait timeout.
#    TODO(p3) runtime/ops_webgpu.py:141 -- the u64 timestamp delta and its /1e9.
#
# 3. FLOAT UNIFORMS (:204). `val.to_bytes(4,'little',signed=val<0)` for an int,
#    `struct.pack('<f', val)` for a float, and :97 passes `float('inf')`.
#    `base.bend`'s F32 has no infinity literal, no bitcast and no to_bits, so the
#    f32 PATTERN cannot be built here at all. The INT arm is ported exactly
#    (`dev.uniform_bytes`); the float arm is four bytes the seam must hand over.
#    See THE INFINITY ENTRY, which is the load-bearing case.
#    TODO(p3) runtime/ops_webgpu.py:204  -- struct.pack('<f', val).
#
# CTYPES SHAPING is not a wall and is named once: the
# `(WGPUBindGroupLayoutEntry * n)(...)` array constructions at :77, :87, :97, :99,
# :129 and :215 are how Python spells "an array of n descriptors", and
# `ctypes.pointer`/`cast` at :59 and :116 spell the chained struct. The port has
# the array as a `List` and the chain as an explicit argument, which is the same
# information without the ctypes shape.
#
# ===========================================================================
# THE PAYLOAD, which is the whole async story and it is one line long.
#
# :34  status, (*payload, emsg) = s, [<args minus userdata1/2>] + ([] if has_emsg
#      else [None])
# :41  return payload if len(payload) > 1 else payload[0] if len(payload)==1 else None
#
# Two consequences this file ports and the gate pins, because both are silent:
#
#   - The callback ALWAYS appends one element. When `has_emsg` is False it
#     appends `None`, so the payload length is ALWAYS nargs + 1, never nargs.
#     That is what makes :200 `DevicePopErrorScope(self.dev.device_res)[1]` the
#     MESSAGE: the pop-error callback is (status, type, message), so the payload
#     is [type, message, None] and index 1 is the message. Four of the six
#     wrapped calls pass has_emsg=True (:45,47,48,49) and two pass False (:46,50)
#     -- `sync_has_emsg` is that table and `sync_payload` is the arithmetic.
#   - The :41 collapse therefore NEVER takes its `None` branch for these six
#     calls, because their payload is never empty. `sync_ret` ports the collapse
#     anyway, because the branch structure is the thing.
#
# THE SYNC CALLS ARE ALSO WHERE THE BROWSER DIFFERS, and the port says so:
# `wgpuInstanceWaitAny` blocks the thread. In a browser the seam returns a
# Promise and `WaitAnyOnly` has no meaning; the six `synchronous`-wrapped calls
# are the six that must become `await`. `SYNC_*` names them, and every CALL_WAIT
# entry in the trace is one of the six.
#
# ===========================================================================
# WHAT device.bend AND wgsl.bend OWE THIS FILE. Named, because this file cannot
# be checked without them and does not pretend otherwise.
#
# device.bend owes:
#   1. `Compiled.__init__` (device.py:391) is handed
#      `arch="shader-f16" * (… in features)` at :190. `dev.init` produces that
#      arch string and the feature list; whoever wires the device records it.
#   2. `Program.__call__` (device.py:372) is called from engine/realize.py:168
#      with `bufs` = `ast.arg.globals` resolved and `vals` = `ProgramInfo.vals`.
#      THIS FILE NEEDS THE BUFFER LIST AND THE VAL COUNT AND NOTHING ELSE --
#      they are what `bgl.of` turns into entries. See THE LAYOUT DERIVATION.
#   3. `BufferStorage` (device.py:110) is `_alloc`'s return (:152) and its `.buf`
#      is what `_free` (:163) and `_copyout` (:160) hand back. `Buf` is that
#      pair, and `alloc.of` is the `BufferStorage`.
#   4. `TinyELF` (device.py:355) carries `name`, which is the entry point (:54)
#      and the pipeline's `entryPoint` (:106). `prog.init` takes it as a String.
#
# wgsl.bend owes:
#   1. THE INFINITY ENTRY. `bgl.of` puts `Uniform` at binding 0 because
#      :77-78 says so, and wgsl.py:114 declares
#      `@group(0) @binding(0)  var<uniform> INFINITY : f32;`. Those two facts
#      must agree or every kernel faults at bind time. MEASURED by calling
#      `WGSLRenderer.render_kernel` in CPython -- see THE LAYOUT DERIVATION.
#   2. `WGPUBufferBindingType_Storage` for a GLOBAL buffer, because :78 keys the
#      type off the POSITION (`i < len(bufs)`) while wgsl.py:116 keys it off the
#      ADDRSPACE. They agree only because every `ProgramInfo.globals` entry is
#      GLOBAL (ops.py:1378). If wgsl.bend ever emits a non-GLOBAL global, the two
#      derivations part company.
#   3. `@workgroup_size(...)` (wgsl.py:118). `Program.__call__` takes a
#      `local_size` and ops_webgpu.py NEVER READS IT -- the workgroup size comes
#      from the WGSL attribute. `prog.call` takes `local_size`, RECORDS it in
#      `Pass.ls`, and never dispatches on it, so the gate can pin that.
#
# ===========================================================================
# THE LAYOUT DERIVATION, :74-78, which is the part of this file that is pure
# logic and therefore the part worth checking:
#
#   bgl_entry(0, 'Uniform'), *(bgl_entry(i+1, 'Uniform' if i >= len(bufs) else
#                                           'Storage')
#                              for i in range(len(bufs)+len(vals)))
#
# So: binding 0 is Uniform; bindings 1..len(bufs) are Storage; bindings
# len(bufs)+1..len(bufs)+len(vals) are Uniform. The count is 1+len(bufs)+len(vals)
# at :77, and the bind group at :97 has the same count and the same split.
# `bgl.of` is that and nothing else.
#
# THE CROSS-FILE CONTRACT, MEASURED IN CPYTHON (no GPU needed; the renderer is
# pure). `WGSLRenderer(Target('WEBGPU','WGSL','shader-f16')).render_kernel` with
# three GLOBAL buffers emits, verbatim:
#
#   fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }
#   @group(0) @binding(0)
#   var<uniform> INFINITY : f32;
#   @group(0) @binding(1)var<storage,read_write>a:array<f32>;
#   @group(0) @binding(2)var<storage,read_write>b:array<f32>;
#   @group(0) @binding(3)var<storage,read_write>c:array<i32>;
#   @compute @workgroup_size(1) fn k(@builtin(workgroup_id) gindex: vec3<u32>,
#       @builtin(local_invocation_id) lindex: vec3<u32>) {
#
# so the shader declares 1+len(bufs) bindings, in the order `bufs` was handed to
# it (cstyle.py:264 "this relies on bufs dict preserving order"), and
# `ProgramInfo.globals` (ops.py:1378, sorted+deduped by slot) is that same order.
# `pass.uniforms` binds layout entry k+1 to bufs[k]. THAT IS THE WHOLE INTERFACE
# between this file and wgsl.bend, and a divergence there is silent in both.
#
# ===========================================================================
# NO wgpu IN THIS ENV. `Device['WEBGPU']` fails with "failed to load library
# webgpu", so NOTHING here was measured against a live device. Every constant
# below was READ OUT OF `tinygrad/runtime/autogen/webgpu.py`, every status NAME
# out of the same file's enum dicts (MEASURED, see `sync_name`), and every row's
# expectation is derived from the source text or from those constants.
#
import Base
import ../helpers.bend as H

# ===========================================================================
# THE CONSTANTS. `autogen/webgpu.py` is generated ctypes bindings, so these are
# the C enum values read out of it: the bit flags at :2573-2583, and the enum
# dicts at :10 (BackendType), :135 (BufferBindingType), :268 (PowerPreference),
# :833 (FeatureName), :1545 (BufferMapState), :1550 (ErrorFilter), :1563
# (WaitStatus), :2598 (ShaderStage).
# ===========================================================================

def OBJ_INSTANCE() -> U32: 0
def OBJ_ADAPTER() -> U32: 1
def OBJ_QUEUE() -> U32: 3
def OBJ_SHADER_MODULE() -> U32: 4
def OBJ_BIND_GROUP_LAYOUT() -> U32: 5
def OBJ_PIPELINE_LAYOUT() -> U32: 6
def OBJ_BIND_GROUP() -> U32: 7
def OBJ_COMPUTE_PIPELINE() -> U32: 8
def OBJ_COMMAND_ENCODER() -> U32: 9
def OBJ_COMPUTE_PASS() -> U32: 10
def OBJ_COMMAND_BUFFER() -> U32: 11
def OBJ_QUERY_SET() -> U32: 12
def OBJ_BUFFER() -> U32: 13

def CALL_CREATE() -> U32: 0
def CALL_WAIT() -> U32: 1
def CALL_RELEASE() -> U32: 2
def CALL_PUSH() -> U32: 3
def CALL_POP() -> U32: 4
def CALL_MAP_ASYNC() -> U32: 5
def CALL_MAPPED_RANGE() -> U32: 6
def CALL_WRITE() -> U32: 7
def CALL_COPY() -> U32: 8
def CALL_BEGIN() -> U32: 9
def CALL_SET_PIPELINE() -> U32: 10
def CALL_SET_BIND_GROUP() -> U32: 11
def CALL_DISPATCH() -> U32: 12
def CALL_END() -> U32: 13
def CALL_RESOLVE() -> U32: 14
def CALL_FINISH() -> U32: 15
def CALL_SUBMIT() -> U32: 16
def CALL_UNMAP() -> U32: 17
def CALL_DESTROY() -> U32: 18
def CALL_DESTROY_QUERY_SET() -> U32: 19
def CALL_GET_FEATURES() -> U32: 20
def CALL_FREE_FEATURES() -> U32: 21
def CALL_GET_LIMITS() -> U32: 22

# the six `synchronous`-wrapped calls, :45-50.
def SYNC_MAP_ASYNC() -> U32: 1
def SYNC_POP_ERROR_SCOPE() -> U32: 2
def SYNC_CREATE_PIPELINE() -> U32: 3
def SYNC_REQUEST_ADAPTER() -> U32: 4
def SYNC_REQUEST_DEVICE() -> U32: 5
def SYNC_WORK_DONE() -> U32: 6

# has_emsg, :45-50. TRUE for 1,3,4,5; FALSE for 2,6.
def SYNC_HAS_EMSG() -> U32: 1
def SYNC_NO_EMSG() -> U32: 2

# the :41 collapse.
def SYNC_NONE() -> U32: 0
def SYNC_ONE() -> U32: 1
def SYNC_MANY() -> U32: 2

# a status the call never returned: Python's `status_enum.get(status)` is None,
# and :40's f-string writes that None as `None`. The port writes the same four
# characters, so `wg_sync_err_pop` compares equal to CPython's output.
def SYNC_MISSING() -> String: "None"

def BIND_UNIFORM() -> U32: 1
def BIND_STORAGE() -> U32: 2
def FILTER_VALIDATION() -> U32: 1
def MAP_UNMAPPED() -> U32: 1
def MAP_MAPPED() -> U32: 3
def FEATURE_TIMESTAMP_QUERY() -> U32: 3
def FEATURE_SHADER_F16() -> U32: 8
def USAGE_MAP_READ() -> U32: 1
def USAGE_COPY_SRC() -> U32: 4
def USAGE_COPY_DST() -> U32: 8
def USAGE_UNIFORM() -> U32: 64
def USAGE_STORAGE() -> U32: 128
def USAGE_QUERY_RESOLVE() -> U32: 512
def STATUS_SUCCESS() -> U32: 1
def BIND_GROUP_INDEX() -> U32: 0
def UNIFORM_SIZE() -> U32: 4
def QUERY_COUNT() -> U32: 2
def QUERY_BUF_SIZE() -> U32: 16

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE FFI call and the object it acts on. `arg` is the object kind for CREATE /
# RELEASE / DESTROY, the SYNC_* id for a WAIT, the workgroup count for a
# DISPATCH and the group index for a SET_BIND_GROUP; unused elsewhere. There is
# deliberately no field for the rest of the call's ARGUMENTS: those are what the
# defs around this record build, and the gate reads them from the record a def
# RETURNS, not from the trace.
type Call is Data:
  Call{k: U32, arg: U32}

# ops_webgpu.py:110 `BufferStorage` reduced to the two fields this file reads:
# `.buf` (:163, :96) and the size `wgpuBufferGetSize` answers (:18, :96, :207).
type Buf is Data:
  Buf{id: U32, size: U32}

# ONE bind group layout entry (:75) or bind group entry (:96). `visibility` is
# WGPUShaderStage_Compute at every entry (:75) so it is not a field.
type Bgl is Data:
  Bgl{binding: U32, ty: U32}

# what ONE bind group entry binds: either a caller's buffer or a uniform this
# call creates (:94-95, `buf = x if isinstance(x, WGPUBuffer) else
# self.dev.create_uniform(x)`). `is_buf` false means a uniform, and then `size` is
# UNIFORM_SIZE because create_uniform always makes a 4-byte buffer (:203).
type Slot is Data:
  Slot{is_buf: Bool, size: U32}

# the machine state of the FFI seam. Bend has no pointer, so `next` mints the
# handle ids: what the gate checks is that they are consumed in the right ORDER
# and the right NUMBER of times, which is the part the structure owns.
#
# `depth` is the open wgpuDevicePushErrorScope count and `bad_at` is the POP
# ordinal at which the seam should report an error (0 = never), so one fixture
# drives the `if err := self.dev.pop_error(): raise` arm at each of the four
# sites in turn. `popn` counts the pops so far and is what `bad_at` is compared
# against; it is NOT reset by `Tr.reset`, so one fixture numbering covers a whole
# program lifetime.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, depth: U32, bad_at: U32, popn: U32,
     refused: Bool}

# one created object and the trace that created it. Bend refuses to destructure a
# computed product -- `(id, t) = Tr.mint(...)` is a match on a call -- so the two
# travel together in one record. This is the port's idiom throughout: `Found` in
# ops.bend, `ShapeRes` in helpers.bend.
type Made is Data:
  Made{buf: Buf, t: Tr}

# ops_webgpu.py:165 WebGpuDevice, only the fields ops_webgpu.py itself writes.
# `instance` is module-level in Python (:11) and is carried here because Bend has
# no module-level state; there is exactly one per device either way.
type Dev is Data:
  Dev{instance: U32, adapter: U32, device_res: U32, queue: U32,
      features: List<&2, U32>, backend: U32, nrequired: U32, arch: String, t: Tr}

# ONE program call's state: the shader module (:63), the entry point (:54), the
# device's features (:71 reads `self.dev.features`), the `local_size` that
# ops_webgpu.py never reads, the layout descriptor's entryCount (:82), the bind
# group entry sizes (:96), the dispatch geometry (:123) and the trace.
type Pass is Data:
  Pass{module: U32, entry: String, feats: List<&2, U32>, ls: U32, nentries: U32,
       sizes: List<&2, U32>, gx: U32, gy: U32, gz: U32, wait: Bool, t: Tr}

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every wgpu call in this file goes through it,
# so the trace is the ordered list of JS imports the browser will make.
#
# THE RAISE. `Tr.emit`, `Tr.push` AND `Tr.pop` all record NOTHING once a pop has
# reported an error. That is the port of `if err := self.dev.pop_error(): raise`:
# everything after the raise does not happen, INCLUDING the next PushErrorScope
# and its matching pop. It is why no step below needs a guard of its own, and why
# a refusal shows up in the trace as a TRUNCATION rather than as a flag alone.
#
# The failing pop IS still recorded, and that is not a special case: it sets
# `refused` in the same breath, so on entry its own `refused` is still False.
# Guarding two of the three was the first bug this gate found in itself (four
# pops and one create survived a refusal at pop 1, which is not what Python
# does); guarding all three is the fix, and `wg_refuse_*_pops` is the row that
# pins it.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 0, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}: next

def Tr.depth(t: Tr) -> U32:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}: depth

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}: refused

# the pop ordinal the seam should fail on, so a fixture can reach each of the
# four `pop_error` sites. 0 = never, which is every successful fixture.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}:
      Tr{calls, next, depth, n, popn, refused}

# an EMPTY trace that keeps `bad_at` and `popn`, so a gate can read one program
# call without the init in front of it and still number its pops from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}:
      Tr{Nil{}, 0, 0, bad_at, popn, False{}}

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates BOTH arms, so the emitted call is a value built here and
# the guard is a parameter. This is the port's `raise`.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, depth: U32, bad_at: U32, popn: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), depth, bad_at, popn,
     refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}:
      Tr.emit.go(refused, k, arg, calls, next, depth, bad_at, popn)

# ops_webgpu.py:80 `wgpuDevicePushErrorScope(self.dev.device_res, Validation)`.
# All four sites pass Validation and all four pass the same `device_res`, so the
# trace needs neither.
def Tr.push(t: Tr) -> Tr:
  match t:
    case Tr{+calls, next, +depth, bad_at, popn, +refused}:
      Tr{Bool.pick(List<&2, Call>, refused, calls,
                   List.append(&2, Call, calls, [Call{CALL_PUSH, FILTER_VALIDATION}])),
         next, Bool.pick(U32, refused, depth, U32.add(depth, 1)), bad_at, popn, refused}

# ops_webgpu.py:64,84,91,102 `self.dev.pop_error()` = `DevicePopErrorScope(
# self.dev.device_res)[1]`. The POP ITSELF is always recorded -- it is the report
# -- and the MESSAGE is the seam's, so this keeps the question and answers it at
# pop ordinal `bad_at`. See THE PAYLOAD for why index 1 of that payload is the
# message.
def Tr.pop.hit(bad_at: U32, popn: U32, refused: Bool) -> Bool:
  Bool.or(refused, U32.is_eq(U32.add(popn, 1), bad_at))

def Tr.pop.go(+refused: Bool, +calls: List<&2, Call>, next: U32, +depth: U32,
             +bad_at: U32, +popn: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{CALL_POP, FILTER_VALIDATION}])),
     next, Bool.pick(U32, refused, depth, U32.sub(depth, 1)), bad_at,
     Bool.pick(U32, refused, popn, U32.add(popn, 1)),
     Tr.pop.hit(bad_at, popn, refused)}

def Tr.pop(t: Tr) -> Tr:
  match t:
    case Tr{+calls, next, +depth, +bad_at, +popn, +refused}:
      Tr.pop.go(refused, calls, next, depth, bad_at, popn)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in order;
# `Tr.count` is how many there are; `Tr.has` is "contains this (tag, arg)
# sequence, in order".
# ===========================================================================

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

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one
# of them would branch the walk twice over.
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

# does the trace CONTAIN this (tag, arg) sequence, in order? `at` is how much of
# the pattern is matched so far, read out of the pattern BY INDEX rather than
# carried as a second list: the head and the tail of ONE destructure share a
# binder, and a descent may not use that binder twice.
#
# BOTH fields are compared, so a pattern pins the IDENTITY of each call and not
# only its kind. That is what makes `wg_init_order` and `wg_call_order` worth
# printing: they say the instance is created, THEN the adapter is requested, THEN
# the features are read -- and which six.
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

# THE FUEL IS THE TRACE LENGTH AND THE ANSWER IS `at == patlen`. That is the whole
# matcher, and getting either half wrong makes it answer True to everything:
# with the fuel set to the PATTERN length, `case 0n:` fired after patlen trace
# entries and returned True{} without ever looking at `at`, so a reversed pattern
# matched and so did a pattern element that never occurs. MEASURED, and the row
# that caught it is `wg_has_rejects` below -- the five order rows were decorative
# until it was fixed.
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

def str_eq.go(a: List<&2, String>, b: List<&2, String>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case x <> t:
      match b:
        case Nil{}: False{}
        case y <> u: str_eq.go(t, u, Bool.or(bad, Bool.not(String.eq(x, y))))

# ===========================================================================
# ops_webgpu.py:10 -- `backend_types = {v: k for k, v in
# webgpu.enum_WGPUBackendType.items()}`, whose ONE reader is
# `backend_types.get(getenv("WEBGPU_BACKEND", ""), 0)` at :169. So the port needs
# the reverse direction, and THE KEYS ARE THE FULL C NAMES: `WEBGPU_BACKEND`
# must be `WGPUBackendType_Metal`, not `Metal`, and a name that is not in the
# table is Undefined (0), silently. docs/env_vars.md:42 has it right.
#
# The enum is 0..8 (autogen/webgpu.py:10), so the value is the INDEX. Force32 =
# 2147483647 is in the table too and is deliberately absent here: it is not a
# backend and no device would accept it.
# ===========================================================================

def backend_names() -> List<&2, String>:
  ["WGPUBackendType_Undefined", "WGPUBackendType_Null", "WGPUBackendType_WebGPU",
   "WGPUBackendType_D3D11", "WGPUBackendType_D3D12", "WGPUBackendType_Metal",
   "WGPUBackendType_Vulkan", "WGPUBackendType_OpenGL", "WGPUBackendType_OpenGLES"]

# a `got` accumulator and not a two-list walk, because the enum names are unique
# so "the last hit" is "the only hit".
def backend_of.put(s: String, h: String, at: U32, got: U32) -> U32:
  Bool.pick(U32, String.eq(h, s), at, got)

def backend_of.go(n: Nat, +s: String, ns: List<&2, String>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ns:
        case Nil{}: got
        case h <> t: backend_of.go(m, s, t, U32.add(at, 1), backend_of.put(s, h, at, got))

def backend_of(s: String) -> U32:
  backend_of.go(List.length(&2, String, backend_names()), s, backend_names(), 0, 0)

# ===========================================================================
# ops_webgpu.py:23-43 -- `synchronous`, the future-to-synchronous protocol. See
# THE PAYLOAD for why `has_emsg` changes the payload LENGTH and not its content.
#
# THE STATUS NAMES ARE MEASURED, not transcribed from a header: each of the six
# calls carries its OWN status enum, and at status 2 all six are
# `…_InstanceDropped` while at status 3 they are FOUR different things --
# ValidationError, (absent), ValidationError, Unavailable, Error, Error. So :40's
# `status_enum.get(status)` cannot be one table, and `sync_name` is six arms.
# `wg_sync_names_distinct` pins the count and `wg_sync_names2_same` pins the fact
# that status 2 is the one place they agree.
# ===========================================================================

# :41 -- `payload if len(payload) > 1 else payload[0] if len == 1 else None`.
def sync_ret(n: Nat) -> U32:
  match n:
    case 0n: SYNC_NONE()
    # `1n+p` claims EVERY positive Nat, so the 2n+q arm must be LISTED FIRST or
    # it is dead code that still typechecks (bend2-constraints.md, "Correction:
    # numeric patterns are first-match prefix matches"). MEASURED: with the arms
    # the other way round, `wg_sync_ret_2` printed 1.
    case 2n+q: SYNC_MANY()
    case 1n+p: SYNC_ONE()

# :45-50, the only place `has_emsg` appears. 2 and 6 are the two that pass False.
def sync_has_emsg(which: U32) -> U32:
  Bool.pick(U32, U32.is_eq(which, SYNC_POP_ERROR_SCOPE()), SYNC_NO_EMSG(), SYNC_HAS_EMSG())

# :34 -- the payload length is ALWAYS nargs + (has_emsg ? 0 : 1), because the
# False case appends `None` rather than nothing.
def sync_payload(+nargs: Nat, has_emsg: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(has_emsg, SYNC_NO_EMSG()), Nat.add(nargs, 1n), nargs)

def sync_name.map_async2() -> String: "WGPUBufferMapAsyncStatus_InstanceDropped"
def sync_name.pop2() -> String: "WGPUPopErrorScopeStatus_InstanceDropped"
def sync_name.pipeline2() -> String: "WGPUCreatePipelineAsyncStatus_InstanceDropped"
def sync_name.adapter2() -> String: "WGPURequestAdapterStatus_InstanceDropped"
def sync_name.device2() -> String: "WGPURequestDeviceStatus_InstanceDropped"
def sync_name.workdone2() -> String: "WGPUQueueWorkDoneStatus_InstanceDropped"

def sync_name.two.at(which: Nat) -> String:
  match which:
    case 1n: sync_name.map_async2()
    case 2n: sync_name.pop2()
    case 3n: sync_name.pipeline2()
    case 4n: sync_name.adapter2()
    case 5n: sync_name.device2()
    case _: sync_name.workdone2()

def sync_name.two(which: U32) -> String: sync_name.two.at(U32.to_nat(which))


def sync_name.map_async3() -> String: "WGPUBufferMapAsyncStatus_ValidationError"
def sync_name.pop3() -> String: SYNC_MISSING()
def sync_name.pipeline3() -> String: "WGPUCreatePipelineAsyncStatus_ValidationError"
def sync_name.adapter3() -> String: "WGPURequestAdapterStatus_Unavailable"
def sync_name.device3() -> String: "WGPURequestDeviceStatus_Error"
def sync_name.workdone3() -> String: "WGPUQueueWorkDoneStatus_Error"

def sync_name.three.at(which: Nat) -> String:
  match which:
    case 1n: sync_name.map_async3()
    case 2n: sync_name.pop3()
    case 3n: sync_name.pipeline3()
    case 4n: sync_name.adapter3()
    case 5n: sync_name.device3()
    case _: sync_name.workdone3()

def sync_name.three(which: U32) -> String: sync_name.three.at(U32.to_nat(which))

def UNDER() -> Char: Char.from_u32(95)

# ONE PAST THE LAST '_' in `cs`, or 0 if there is none. `pos` is the index and
# `at` is the answer, so this is the index of the last hit and NOT the COUNT of
# them -- the count answers 1 for every one of these names, and dropping 1
# character instead of 26 is what `DBG_tail` printed before the two counters were
# separated.
#
# `String.drop` removes the FIRST n characters (MEASURED in executor.bend: take,
# not drop, is the one that keeps a directory), so `at` counts from the front.
def sync_us.go(n: Nat, +pos: U32, +at: U32, cs: List<&2, Char>) -> U32:
  match n:
    case 0n: at
    case 1n+m:
      match cs:
        case Nil{}: at
        case h <> t: sync_us.go(m, U32.add(pos, 1),
          Bool.pick(U32, Char.is_eq(h, UNDER()), U32.add(pos, 1), at), t)

def sync_us.at(n: Nat, cs: List<&2, Char>) -> U32: sync_us.go(n, 0, 0, cs)

def sync_us(+cs: List<&2, Char>) -> U32: sync_us.at(List.length(&2, Char, cs), cs)

# the enum MEMBER name, i.e. everything after the last '_'. This is the part that
# says which STATUS the call means: the six status-2 names all end in
# `InstanceDropped` and the six status-3 names do not.
def sync_tail(+s: String) -> String: String.drop(s, U32.to_nat(sync_us(String.to_list(s))))

# all six tails, so the gate COUNTS the distinct ones. Counting the six FULL names
# instead would answer 6 both times and prove nothing, which is what the first run
# of these rows did.
def sync_name.six2() -> List<&2, String>:
  [sync_tail(sync_name.two(1)), sync_tail(sync_name.two(2)), sync_tail(sync_name.two(3)),
   sync_tail(sync_name.two(4)), sync_tail(sync_name.two(5)), sync_tail(sync_name.two(6))]

def sync_name.six3() -> List<&2, String>:
  [sync_tail(sync_name.three(1)), sync_tail(sync_name.three(2)), sync_tail(sync_name.three(3)),
   sync_tail(sync_name.three(4)), sync_tail(sync_name.three(5)), sync_tail(sync_name.three(6))]

# :40 `raise RuntimeError(f"[{status_enum.get(status)}]{emsg or ''}")`, and the
# `status != 1` guard that reaches it. Status 1 is Success and never raises, so
# :38's wait failure and :40's status failure are the two raise sites and only
# :40 is spelled out here.
def sync_name.of.err(+which: U32, status: U32) -> String:
  Bool.pick(String, U32.is_eq(status, 2), sync_name.two(which), sync_name.three(which))

def sync_name.of(+which: U32, +status: U32) -> String:
  Bool.pick(String, U32.is_eq(status, STATUS_SUCCESS()), "Success", sync_name.of.err(which, status))

def sync_error(+which: U32, +status: U32, emsg: String) -> String:
  Bool.pick(String, U32.is_eq(status, STATUS_SUCCESS()), "",
            String.concat(["[", sync_name.of(which, status), "]", emsg]))
# ===========================================================================
# ops_webgpu.py:11, :166-190 -- device init. The ORDER is the ported structure
# and it is what `dev.init` exists to pin: instance, adapter, features, limits,
# device, queue, release the adapter. Each step is one line of Python, so each
# step is one def here.
# ===========================================================================

def Dev.at(d: Dev, t: Tr) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, _}:
      Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}

def Dev.tr(d: Dev) -> Tr:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: t

def Dev.instance(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: instance

def Dev.adapter(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: adapter

def Dev.device_res(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: device_res

def Dev.queue(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: queue

def Dev.features(d: Dev) -> List<&2, U32>:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: features

def Dev.backend(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: backend

def Dev.nrequired(d: Dev) -> U32:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: nrequired

def Dev.arch(d: Dev) -> String:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, t}: arch

# :11 `webgpu.wgpuCreateInstance(webgpu.WGPUInstanceDescriptor(features=
# webgpu.WGPUInstanceFeatures(timedWaitAnyEnable=True)))`. `timedWaitAnyEnable` is
# not decoration: `synchronous` (:37) blocks in wgpuInstanceWaitAny, which is
# unimplemented without it, so all six wrapped calls depend on this one flag. The
# flag rides on the descriptor, so the trace cannot see it -- WHICH IS WHY THE
# FFI SEAM IS NOT OPTIONAL HERE AND WHY THE PORT NAMES IT INSTEAD OF DROPPING IT.
def dev.create_instance() -> Dev:
  Dev{Tr.here(Tr.of()), 0, 0, 0, Nil{}, 0, 0, "", Tr.emit(CALL_CREATE, OBJ_INSTANCE, Tr.of())}

# :168-169 InstanceRequestAdapter(instance, WGPURequestAdapterOptions(
# powerPreference=HighPerformance, backendType=backend_types.get(getenv(...), 0))).
# One of the six, so the trace entry is a WAIT and not a CREATE. `powerPreference`
# is HighPerformance at every call site (:169 is the only one), so it is a
# constant here and not a field.
def dev.request_adapter(d: Dev, backend_name: String) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, Tr.here(t), 0, 0, Nil{}, backend_of(backend_name), 0, "",
          Tr.emit(CALL_WAIT, SYNC_REQUEST_ADAPTER, t)}

# :173-174 `[feat for i in range(supported_features.featureCount)
# if (feat:=supported_features.features[i]) in [WGPUFeatureName_TimestampQuery,
# WGPUFeatureName_ShaderF16]]`. The comprehension iterates the ADAPTER's list, so
# the order is the adapter's and NOT the order of the two-element probe list.
# That is invisible for a wgpu adapter (its feature list is ascending, and
# TimestampQuery=3 sorts before ShaderF16=8) and visible for any other list, so
# the gate pins it BOTH ways: `wg_feat_order_reverse` is the row that fails if
# the port sorts by the probe list instead.
def keeps_feature(+f: U32) -> Bool:
  Bool.or(U32.is_eq(f, FEATURE_TIMESTAMP_QUERY()), U32.is_eq(f, FEATURE_SHADER_F16()))

# the comprehension is its own fold and not `List.filter`, because a closure's
# type cannot spell `+` and `keeps_feature` needs `f` twice.
def features_keep.put(+x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, keeps_feature(x), List.append(&2, U32, acc, [x]), acc)

# `features_keep.put` APPENDS, so the base cases hand `acc` straight back: the
# filter preserves the ADAPTER's order, and a `List.reverse` here reversed it for
# every list of two or more. MEASURED: `wg_feat_order_forward` was the row that
# caught it, because the one-feature fixtures are unaffected.
def features_keep.go(n: Nat, fs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case x <> t: features_keep.go(m, t, features_keep.put(x, acc))

def features_of(+fs: List<&2, U32>) -> List<&2, U32>:
  features_keep.go(List.length(&2, U32, fs), fs, Nil{})

# :172 wgpuAdapterGetFeatures, then :175 wgpuSupportedFeaturesFreeMembers. The
# filter runs BETWEEN them, in the list's own order.
def dev.get_features(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch,
          Tr.emit(CALL_GET_FEATURES, 0, t)}

def dev.features_keep(d: Dev, +fs: List<&2, U32>) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features_of(fs), backend, nrequired, arch,
          Tr.emit(CALL_FREE_FEATURES, 0, t)}

# :180-181 wgpuAdapterGetLimits then `dev_desc.requiredLimits =
# c.pointer(WGPURequiredLimits(limits=supported_limits.limits))`. The VALUES are
# the adapter's and there is no v1 spelling for a limits table; what is portable
# is that the adapter is asked BEFORE the device is requested, which is what
# `wg_init_limits_before_device` reads.
def dev.get_limits(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch,
          Tr.emit(CALL_GET_LIMITS, 0, t)}

# :176-177 `requiredFeatureCount=len(self.features)`, and :190
# `arch="shader-f16" * (WGPUFeatureName_ShaderF16 in self.features)`. Python
# string-multiplies: "" or "shader-f16", never anything else. Both are functions
# of the FILTERED list and nothing else.
def dev.arch_of(fs: List<&2, U32>) -> String:
  Bool.pick(String, List.contains(~U32, ~U32.is_eq, fs, FEATURE_SHADER_F16()),
            "shader-f16", "")

def dev.derive(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, +features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features, backend,
          U32.from_nat(List.length(&2, U32, features)), dev.arch_of(features), t}

# :184 AdapterRequestDevice(adapter_res, dev_desc) -> self.device_res.
def dev.request_device(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, Tr.here(t), 0, features, backend, nrequired, arch,
          Tr.emit(CALL_WAIT, SYNC_REQUEST_DEVICE, t)}

# :185 `self.queue = webgpu.wgpuDeviceGetQueue(self.device_res)`. Its OWN def,
# because that is what gives the queue an id of its own: `Tr.here` is read before
# the wait's emit and the wait's emit consumes it.
def dev.get_queue(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, Tr.here(t), features, backend, nrequired, arch,
          Tr.emit(CALL_CREATE, OBJ_QUEUE, t)}

# :187 `webgpu.wgpuAdapterRelease(adapter_res)` -- LAST, after the device and the
# queue are in hand. The handle is kept in `adapter`; only the reference goes.
def dev.adapter_release(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch,
          Tr.emit(CALL_RELEASE, OBJ_ADAPTER, t)}

def dev.init(backend_name: String, feats: List<&2, U32>) -> Dev:
  d1 = dev.request_adapter(dev.create_instance(), backend_name)
  d2 = dev.get_features(d1)
  d3 = dev.features_keep(d2, feats)
  d4 = dev.get_limits(d3)
  d5 = dev.derive(d4)
  d6 = dev.request_device(d5)
  d7 = dev.get_queue(d6)
  dev.adapter_release(d7)
# :195-198 -- unmap ONLY if the map state is Mapped, then destroy, then release.
# All three in that order, always. Two defs because a `match` scrutinee must be a
# PARAMETER: the state arrives as a U32 and the comparison is a leaf.
def dev.free.at(mapped: Bool, +id: U32, +t: Tr) -> Tr:
  match mapped:
    case True{}: Tr.emit(CALL_RELEASE, id, Tr.emit(CALL_DESTROY, id, Tr.emit(CALL_UNMAP, id, t)))
    case False{}: Tr.emit(CALL_RELEASE, id, Tr.emit(CALL_DESTROY, id, t))

def dev.free(map_state: U32, id: U32, t: Tr) -> Tr:
  dev.free.at(U32.is_eq(map_state, MAP_MAPPED()), id, t)

# ===========================================================================
# ops_webgpu.py:201-205 -- `create_uniform`. ONE 4-byte Uniform|CopyDst buffer,
# then a 4-byte little-endian write into it.
# ===========================================================================

def dev.uniform_usage() -> U32: U32.or(USAGE_UNIFORM(), USAGE_COPY_DST())

# `val.to_bytes(4, "little", signed=val < 0)` for an int: two's complement, low
# byte first. That is the whole int arm and it IS portable. The FLOAT arm needs
# an f32 bit pattern, which is WALL 3.
def dev.uniform_bytes.go(n: Nat, +v: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+m: dev.uniform_bytes.go(m, U32.shrn(v, 1n), U32.and(v, 255) <> acc)

def dev.uniform_bytes(v: U32) -> List<&2, U32>: dev.uniform_bytes.go(4n, v, Nil{})

def Buf.size(b: Buf) -> U32:
  match b:
    case Buf{id, size}: size

def Made.buf(m: Made) -> Buf:
  match m:
    case Made{buf, t}: buf

def Made.tr(m: Made) -> Tr:
  match m:
    case Made{buf, t}: t

# ===========================================================================
# ops_webgpu.py:220-221 -- `wgpuQueueWriteBuffer(self.queue, buf, 0, <bytes>,
# len(src))`. The length is `len` OF THE ARGUMENT, so for `_copyin` it is the
# PADDED length. That is why `bytes` is a parameter here and not a `U32`: the
# length is derived from the bytes rather than passed beside them.
# ===========================================================================

def copy.write(bytes: List<&2, U32>, t: Tr) -> Tr:
  Tr.emit(CALL_WRITE, U32.from_nat(List.length(&2, U32, bytes)), t)

def dev.create_uniform(+bytes: List<&2, U32>, +t: Tr) -> Made:
  Made{Buf{Tr.here(t), U32.from_nat(List.length(&2, U32, bytes))},
       copy.write(bytes, Tr.emit(CALL_CREATE, OBJ_BUFFER, t))}

# ===========================================================================
# ops_webgpu.py:150-163 -- the allocator.
# ===========================================================================

# :152-153 Storage|CopyDst|CopySrc. The three bits together say: a storage buffer
# the host can upload into and read back out of.
def alloc.usage() -> U32: U32.or(U32.or(USAGE_STORAGE(), USAGE_COPY_DST()), USAGE_COPY_SRC())

# :152 `size=round_up(size, 4)`, under the comment "WebGPU buffers have to be
# 4-byte aligned". That is the WHOLE of the allocator's alignment rule, and
# `round_up` is helpers.py:247 `ceildiv(x, y) * y`.
def alloc.size(nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

def alloc.of(size: U32, +t: Tr) -> Made:
  Made{Buf{Tr.here(t), alloc.size(size)}, Tr.emit(CALL_CREATE, OBJ_BUFFER, t)}

# :163 `self.dev.free(storage.buf)`
# :154-158 -- pad to a multiple of 4 with ZEROS when the length is not already
# one, then write. What falls out of that, and what the gate pins: `write_buffer`
# receives the PADDED length ALWAYS, because when nbytes % 4 == 0
# round_up(nbytes, 4) == nbytes. So a 5-byte upload reaches the device as 8 bytes
# with 3 of them zero, and `wg_copyin_writes_padded` is the row that dies if the
# port writes the unpadded length.
def copy.write_len(nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

def copy.pad(+nbytes: U32) -> U32: U32.sub(copy.write_len(nbytes), nbytes)

def copy.copyin(nbytes: U32, t: Tr) -> Tr: Tr.emit(CALL_WRITE, copy.write_len(nbytes), t)

# :206-219 -- the staging buffer every host read goes through. Create with
# CopyDst|MapRead at the SAME size, copy the whole buffer into it, submit, then
# release the command buffer and the encoder IN THAT ORDER -- the REVERSE of
# creation. Note the contrast with `pass.release`, which releases in CREATION
# order; both are pinned, so neither mutation hides in the other.
def copy.readable_usage() -> U32: U32.or(USAGE_COPY_DST(), USAGE_MAP_READ())

def copy.readable(+size: U32, +t: Tr) -> Made:
  Made{Buf{Tr.here(t), size},
       Tr.emit(CALL_RELEASE, OBJ_COMMAND_ENCODER,
         Tr.emit(CALL_RELEASE, OBJ_COMMAND_BUFFER,
           Tr.emit(CALL_SUBMIT, 1,
             Tr.emit(CALL_FINISH, 1,
               Tr.emit(CALL_COPY, size,
                 Tr.emit(CALL_CREATE, OBJ_COMMAND_ENCODER,
                   Tr.emit(CALL_CREATE, OBJ_BUFFER, t)))))))}

# :17-19 `buf_to_mv` -- map async (ONE of the six synchronous calls), then take
# the const mapped range over the WHOLE buffer. No error scope, and no size
# argument: the range is (0, wgpuBufferGetSize(buf)), which is why the size rides
# on the range call and not on the map.
def copy.read(usage: U32, +size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MAPPED_RANGE, size,
    Tr.emit(CALL_MAP_ASYNC, usage, Tr.emit(CALL_WAIT, SYNC_MAP_ASYNC, t)))

# :159-161 -- `dest[:] = buf_to_mv(tmp_buf:=self.dev._readable_buffer(src))[:nbytes]`
# then `self.dev.free(tmp_buf)`. So one create, one map and one free per copy-out,
# and the free is of the STAGING buffer, not of the source.
# the read is OF THE STAGING buffer and the free is of the SAME buffer, so the
# `Made` travels through both rather than being taken apart and put back.
def copy.read_made(usage: U32, size: U32, +m: Made) -> Made:
  Made{Made.buf(m), copy.read(usage, size, Made.tr(m))}

# ===========================================================================
# ops_webgpu.py:52-67 -- WebGPUProgram.__init__ / __del__, and the four `wait`
# arms of :112, :126 and :140 that the call steps read off `Pass.wait`.
# ===========================================================================

def Pass.of(entry: String, feats: List<&2, U32>) -> Pass:
  Pass{0, entry, feats, 0, 0, Nil{}, 1, 1, 1, False{}, Tr.of()}

def Pass.tr(p: Pass) -> Tr:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: t

def Pass.ls(p: Pass) -> U32:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: ls

def Pass.nentries(p: Pass) -> U32:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: nentries

def Pass.sizes(p: Pass) -> List<&2, U32>:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: sizes

def Pass.gx(p: Pass) -> U32:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: gx

def Pass.wait(p: Pass) -> Bool:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, t}: wait

# an EMPTY trace that keeps `bad_at` and `popn`, so a gate can read one program
# call without the init in front of it and still number its pops from one.
def Pass.reset(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, Tr.reset(t)}

# :71 `wait = wait and webgpu.WGPUFeatureName_TimestampQuery in self.dev.features`.
# The FIRST line of __call__, and the only thing that decides whether a query set
# exists at all (:112). A `wait=True` on a device without the feature is NOT an
# error: it silently measures nothing and returns None, which is what
# `wg_wait_no_ts_query` pins.
def prog.wants_wait(want: Bool, feats: List<&2, U32>) -> Bool:
  Bool.and(want, List.contains(~U32, ~U32.is_eq, feats, FEATURE_TIMESTAMP_QUERY()))

# :53-64 -- `self.dev, self.name = dev, to_wgpu_str(obj.name)`, then the WGSL
# descriptor (:57-59, a CHAINED struct whose sType is WGPUSType_ShaderSourceWGSL,
# so the shader language is named by the chain and not by the descriptor type),
# then PushErrorScope(Validation) (:62), CreateShaderModule (:63) and
# `if err := self.dev.pop_error(): raise` (:64).
def prog.init(entry: String, d: Dev) -> Pass:
  match d:
    case Dev{instance, adapter, device_res, queue, +features, backend, nrequired, arch, +t}:
      Pass{Tr.here(t), entry, features, 0, 0, Nil{}, 1, 1, 1, False{},
           Tr.pop(Tr.emit(CALL_CREATE, OBJ_SHADER_MODULE, Tr.push(t)))}
# ===========================================================================
# ops_webgpu.py:74-78 -- THE LAYOUT DERIVATION. See THE LAYOUT DERIVATION in the
# header: binding 0 Uniform, bindings 1..len(bufs) Storage, the rest Uniform, and
# `visibility` WGPUShaderStage_Compute at every entry, which is why it is not a
# field of Bgl.
# ===========================================================================

def bgl.entry.put(+i: U32, nbufs: U32, acc: List<&2, Bgl>) -> List<&2, Bgl>:
  Bgl{U32.add(i, 1),
      Bool.pick(U32, U32.is_ge(i, nbufs), BIND_UNIFORM(), BIND_STORAGE())} <> acc

def bgl.of.go(n: Nat, +i: U32, +nbufs: U32, acc: List<&2, Bgl>) -> List<&2, Bgl>:
  match n:
    case 0n: List.reverse(&2, Bgl, acc)
    case 1n+m: bgl.of.go(m, U32.add(i, 1), nbufs, bgl.entry.put(i, nbufs, acc))

# `bgl_entry(0, 'Uniform'), *(bgl_entry(i+1, ...) for i in range(len(bufs)+len(vals)))`
def bgl.of(+nbufs: U32, nvals: U32) -> List<&2, Bgl>:
  List.append(&2, Bgl, [Bgl{0, BIND_UNIFORM()}],
    bgl.of.go(U32.to_nat(U32.add(nbufs, nvals)), 0, nbufs, Nil{}))

# the gate needs the pairs, not the records: (binding, type) per entry, IN ORDER.
# `List.append` is in order and this fold does not reverse at the end, which is
# the other half of the O(n^2) trade -- see slots.vals.
def bgl.flat(xs: List<&2, Bgl>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case Bgl{b, ty} <> t: bgl.flat(t, List.append(&2, U32, List.append(&2, U32, acc, [b]), [ty]))

# :94-97 -- the bind group has the same count and the same split as the layout:
# INFINITY first (which is a uniform the call CREATES, not a constant), then the
# bufs, then the vals.
# BOTH folds APPEND and neither reverses. That is O(n^2) for a list of at most a
# few hundred entries, and it buys the thing that matters: the binding order IS
# the list order. Consing here and reversing once at the end puts the bufs in
# REVERSE order while leaving the group order right, which the gate caught as
# `wg_call_sizes=64,64,64,4` instead of `4,64,64,64,4`.
def slots.vals(n: Nat, acc: List<&2, Slot>) -> List<&2, Slot>:
  match n:
    case 0n: acc
    case 1n+m: slots.vals(m, List.append(&2, Slot, acc, [Slot{False{}, UNIFORM_SIZE()}]))

def slots.bufs(n: Nat, bs: List<&2, Buf>, acc: List<&2, Slot>) -> List<&2, Slot>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case Buf{id, sz} <> t: slots.bufs(m, t, List.append(&2, Slot, acc, [Slot{True{}, sz}]))

def slots(+bs: List<&2, Buf>, nvals: Nat) -> List<&2, Slot>:
  slots.vals(nvals, slots.bufs(List.length(&2, Buf, bs), bs, [Slot{False{}, UNIFORM_SIZE()}]))

# ===========================================================================
# ops_webgpu.py:69-147 -- ONE program call, as the step list it is. Every step is
# one line range of the Python and takes the `Pass` it is handed, so the order is
# the whole of `prog.call` and nothing else.
#
# THE `raise` IS IN THE TRACE (see THE RAISE): once a pop has reported an error
# no later step records anything, so these steps need no guard of their own and a
# refusal shows up as a TRUNCATED trace -- which is exactly what the four
# `wg_refuse_*` rows read.
# ===========================================================================

# :71, and the dispatch geometry :123 reads. `local_size` is RECORDED and never
# dispatched on: ops_webgpu.py never reads it (see wgsl.bend owes, item 3).
# the parameter is `local`, not `ls`: a pattern binder of the same name SHADOWS it
# and the Pass then keeps the 0 it was born with. MEASURED: `wg_call_ls_recorded`
# printed 0 until this was renamed.
def pass.geometry(p: Pass, gx: U32, gy: U32, gz: U32, local: U32, want: Bool) -> Pass:
  match p:
    case Pass{module, entry, +feats, ls, nentries, sizes, g0, h0, i0, wait, +t2}:
      Pass{module, entry, feats, local, nentries, sizes, gx, gy, gz,
           prog.wants_wait(want, feats), t2}

# :80-84 -- PushErrorScope(Validation), CreateBindGroupLayout(device,
# WGPUBindGroupLayoutDescriptor(entryCount=len(bind_entries), entries=...)),
# pop_error. The port stores `nentries`, which is the descriptor's field the gate
# reads, and `bgl.of` IS the entries it counts -- so the derivation is live here
# and not only in the gate.
def pass.layout(+nbufs: U32, nvals: U32, p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls,
           U32.from_nat(List.length(&2, Bgl, bgl.of(nbufs, nvals))), sizes, gx, gy, gz,
           wait, Tr.pop(Tr.emit(CALL_CREATE, OBJ_BIND_GROUP_LAYOUT, Tr.push(t)))}

# :87-91 -- WGPUPipelineLayoutDescriptor(bindGroupLayoutCount=1,
# bindGroupLayouts=[bind_layout]), then the same push/create/pop pair. bindGroupLayoutCount
# is 1 at the only call site, so it is a constant here.
def pass.playout(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.pop(Tr.emit(CALL_CREATE, OBJ_PIPELINE_LAYOUT, Tr.push(t)))}

# :94-95 -- `buf = x if isinstance(x, webgpu.WGPUBuffer) else
# self.dev.create_uniform(x)`, once per bind group entry. A uniform slot CREATES a
# 4-byte buffer and the entry takes its size; a buffer slot takes the caller's.
# The fold runs BEFORE the bind group is created, which is what puts the uniform
# creates between the pipeline layout's pop and the bind group's push.
def pass.uniforms.put(p: Pass, is_buf: Bool, sz: U32) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, +sizes, gx, gy, gz, wait, +t}:
      match is_buf:
        case True{}:
          Pass{module, entry, feats, ls, nentries, List.append(&2, U32, sizes, [sz]),
               gx, gy, gz, wait, t}
        case False{}:
          Pass{module, entry, feats, ls, nentries,
               List.append(&2, U32, sizes, [UNIFORM_SIZE()]), gx, gy, gz, wait,
               Tr.emit(CALL_CREATE, OBJ_BUFFER, t)}

def pass.uniforms.go(n: Nat, p: Pass, ss: List<&2, Slot>) -> Pass:
  match n:
    case 0n: p
    case 1n+m:
      match ss:
        case Nil{}: p
        case Slot{is_buf, size} <> t: pass.uniforms.go(m, pass.uniforms.put(p, is_buf, size), t)

def pass.uniforms(+bs: List<&2, Buf>, +nvals: Nat, p: Pass) -> Pass:
  pass.uniforms.go(Nat.add(Nat.add(1n, List.length(&2, Buf, bs)), nvals), p, slots(bs, nvals))

# :99-102 -- CreateBindGroup(device, WGPUBindGroupDescriptor(layout=bind_layout,
# entryCount=len(bindings), entries=bindings)), same push/create/pop.
def pass.group(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.pop(Tr.emit(CALL_CREATE, OBJ_BIND_GROUP, Tr.push(t)))}

# :105-107 -- DeviceCreateComputePipeline(device, WGPUComputePipelineDescriptor(
# layout=pipeline_layout, compute=WGPUComputeState(module=self.prg,
# entryPoint=self.name))). NOT an error scope: this one is a FUTURE, so its status
# arrives through the callback, which is why `wg_call_scopes` is 3 and not 4 and
# why the pipeline handle is not minted by a trace entry.
def pass.pipeline(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_WAIT, SYNC_CREATE_PIPELINE, t)}

# :109 -- CreateCommandEncoder(device, WGPUCommandEncoderDescriptor()).
def pass.encoder(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_CREATE, OBJ_COMMAND_ENCODER, t)}

# :112-117 -- `if wait:` the query set (type Timestamp, count 2) and a 16-byte
# QueryResolve|CopySrc buffer, and the pass descriptor gets timestampWrites. The
# timestamp writes ride on the DESCRIPTOR, so they are invisible to the trace --
# what the trace sees is the two creates, and that they do not happen at all when
# `wait` is False is what `wg_wait_query_created` and `wg_wait_no_ts_creates` read.
def pass.query.on(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_CREATE, OBJ_BUFFER, Tr.emit(CALL_CREATE, OBJ_QUERY_SET, t))}

# a `match` may not scrutinise a CALL, so `if wait:` is a `.at` whose Bool is a
# PARAMETER. Three `if wait:` arms, three `.at`s -- and no shared helper, because
# the three differ in what they skip and a shared one would need a tag.
def pass.query.at(wait: Bool, p: Pass) -> Pass:
  match wait:
    case False{}: p
    case True{}: pass.query.on(p)

def pass.query(+p: Pass) -> Pass: pass.query.at(Pass.wait(p), p)

# :120 -- BeginComputePass(command_encoder, comp_pass_desc).
def pass.begin(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_BEGIN, 0, t)}

# :121-122 -- SetPipeline(compute_pass, pipeline_result) then
# SetBindGroup(compute_pass, 0, bind_group, 0, None). Group 0 is the only group,
# and `None` for the dynamic-offset array means the default, which is why the
# group index rides on the trace entry as 0.
def pass.set(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_SET_BIND_GROUP, BIND_GROUP_INDEX(),
                   Tr.emit(CALL_SET_PIPELINE, 0, t))}

# :123 -- DispatchWorkgroups(compute_pass, *global_size). The X extent rides on
# the trace entry so that the gate can read the dispatch geometry; y and z are in
# the Pass beside it. NOT the local size -- see pass.geometry.
def pass.dispatch(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, +gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_DISPATCH, gx, t)}

# :124 -- End(compute_pass).
def pass.end(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_END, 0, t)}

# :126 -- `if wait:` ResolveQuerySet(command_encoder, query_set, 0, 2, query_buf, 0).
# It happens AFTER the pass has ended and BEFORE the encoder is finished, which is
# the position `wg_wait_resolve_order` pins.
def pass.resolve.on(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_RESOLVE, QUERY_COUNT(), t)}

# a `match` may not scrutinise a CALL, so `if wait:` is a `.at` whose Bool is a
# PARAMETER. Three `if wait:` arms, three `.at`s -- and no shared helper, because
# the three differ in what they skip and a shared one would need a tag.
def pass.resolve.at(wait: Bool, p: Pass) -> Pass:
  match wait:
    case False{}: p
    case True{}: pass.resolve.on(p)

def pass.resolve(+p: Pass) -> Pass: pass.resolve.at(Pass.wait(p), p)

# :128-129 -- Finish(command_encoder, WGPUCommandBufferDescriptor()) then
# Submit(self.queue, 1, [cmd_buf]).
def pass.finish(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_SUBMIT, 1, Tr.emit(CALL_FINISH, 1, t))}

# :132-138 -- THE SEVEN RELEASES, and the order is CREATION order, not the
# reverse: bind_layout, pipeline_layout, bind_group, compute_pipeline,
# command_encoder, compute_pass, cmd_buf. `wg_call_released` pins it and
# `wg_readable_released` pins the opposite order in `copy.readable`, so a mutation
# that reverses one of them does not move the other row.
def pass.release(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_RELEASE, OBJ_COMMAND_BUFFER,
             Tr.emit(CALL_RELEASE, OBJ_COMPUTE_PASS,
               Tr.emit(CALL_RELEASE, OBJ_COMMAND_ENCODER,
                 Tr.emit(CALL_RELEASE, OBJ_COMPUTE_PIPELINE,
                   Tr.emit(CALL_RELEASE, OBJ_BIND_GROUP,
                     Tr.emit(CALL_RELEASE, OBJ_PIPELINE_LAYOUT,
                       Tr.emit(CALL_RELEASE, OBJ_BIND_GROUP_LAYOUT, t)))))))}

# :140-145 -- `if wait:` the staging read of the two timestamps, then BOTH frees,
# then QuerySetDestroy and QuerySetRelease. The delta itself is WALL 2.
def pass.timing.on(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      t1 = copy.read_made(copy.readable_usage(), QUERY_BUF_SIZE(),
                          copy.readable(QUERY_BUF_SIZE(), t))
      t2 = dev.free(MAP_UNMAPPED(), OBJ_BUFFER, Made.tr(t1))
      t3 = dev.free(MAP_UNMAPPED(), OBJ_BUFFER, t2)
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_RELEASE, OBJ_QUERY_SET,
                   Tr.emit(CALL_DESTROY_QUERY_SET, OBJ_QUERY_SET, t3))}

# a `match` may not scrutinise a CALL, so `if wait:` is a `.at` whose Bool is a
# PARAMETER. Three `if wait:` arms, three `.at`s -- and no shared helper, because
# the three differ in what they skip and a shared one would need a tag.
def pass.timing.at(wait: Bool, p: Pass) -> Pass:
  match wait:
    case False{}: p
    case True{}: pass.timing.on(p)

def pass.timing(+p: Pass) -> Pass: pass.timing.at(Pass.wait(p), p)

# ===========================================================================
# ops_webgpu.py:69-70 -- `def __call__(self, *bufs, global_size=(1,1,1),
# local_size=(1,1,1), vals=(), wait=False) -> float|None`. The step order below IS
# the order of the Python, and it is the only thing this def knows.
# ===========================================================================

def prog.call.at(+bs: List<&2, Buf>, +nvals: U32, gx: U32, gy: U32, gz: U32, ls: U32,
                 want: Bool, p0: Pass) -> Pass:
  p1 = pass.geometry(p0, gx, gy, gz, ls, want)
  p2 = pass.layout(U32.from_nat(List.length(&2, Buf, bs)), nvals, p1)
  p3 = pass.playout(p2)
  p4 = pass.uniforms(bs, U32.to_nat(nvals), p3)
  p5 = pass.group(p4)
  p6 = pass.pipeline(p5)
  p7 = pass.encoder(p6)
  p8 = pass.query(p7)
  p9 = pass.begin(p8)
  pa = pass.set(p9)
  pb = pass.dispatch(pa)
  pc = pass.end(pb)
  pd = pass.resolve(pc)
  pe = pass.finish(pd)
  pf = pass.release(pe)
  pass.timing(pf)

# the traced call, with the init's trace in front of it
def prog.call(+bs: List<&2, Buf>, +nvals: U32, gx: U32, gy: U32, gz: U32, ls: U32,
              want: Bool, p: Pass) -> Pass:
  prog.call.at(bs, nvals, gx, gy, gz, ls, want, p)

# ===========================================================================
# THE GATE. Every row is a claim about `ops_webgpu.py`'s TEXT or about a constant
# read out of `autogen/webgpu.py`, and the row name says which Python line it is
# about. Numeric rows print the value, so a wrong one is diagnosable from the
# output alone.
#
# FIXTURES. One device per feature set, one program on it, one call with THREE
# 64-byte GLOBAL buffers and ONE val -- the shape of a 2-input 1-output float
# kernel, which is exactly the fixture `WGSLRenderer.render_kernel` was measured
# with. `fx_call` resets the trace so the init is not in front of it, and
# `fx_life` keeps it so the error-scope count covers a whole program lifetime.
# ===========================================================================

def METAL() -> String: "WGPUBackendType_Metal"
def TS() -> List<&2, U32>: [FEATURE_TIMESTAMP_QUERY()]
def F16() -> List<&2, U32>: [FEATURE_SHADER_F16()]
def BOTH() -> List<&2, U32>: [FEATURE_TIMESTAMP_QUERY(), FEATURE_SHADER_F16()]
def NEITHER() -> List<&2, U32>: [1, 2]
def REVERSED() -> List<&2, U32>: [FEATURE_SHADER_F16(), FEATURE_TIMESTAMP_QUERY()]

def bufs.go(n: Nat, +id: U32, szs: List<&2, U32>, acc: List<&2, Buf>) -> List<&2, Buf>:
  match n:
    case 0n: List.reverse(&2, Buf, acc)
    case 1n+m:
      match szs:
        case Nil{}: List.reverse(&2, Buf, acc)
        case s <> t: bufs.go(m, U32.add(id, 1), t, Buf{id, s} <> acc)

def bufs3() -> List<&2, Buf>: bufs.go(3n, 100, [64, 64, 64], Nil{})

def fx_pass(feats: List<&2, U32>) -> Pass: prog.init("k", dev.init(METAL(), feats))

# the `bad_at`-th error scope reports an error. `dev.init` opens NO scope, so the
# program call's pop 1 is the shader module and the call's pops are 2, 3 and 4.
def fx_fail.at(+d: Dev, bad_at: U32) -> Dev: Dev.at(d, Tr.fail_at(Dev.tr(d), bad_at))

def fx_fail(feats: List<&2, U32>, bad_at: U32) -> Pass:
  prog.init("k", fx_fail.at(dev.init(METAL(), feats), bad_at))

# 3 bufs, 1 val, global (8,1,1), local (4,1,1), wait per the fixture.
def fx_call(feats: List<&2, U32>, want: Bool) -> Pass:
  prog.call(bufs3(), 1, 8, 1, 1, 4, want, Pass.reset(fx_pass(feats)))

def fx_life(feats: List<&2, U32>, want: Bool) -> Pass:
  prog.call(bufs3(), 1, 8, 1, 1, 4, want, fx_pass(feats))

# a REFUSAL needs a CALL: `prog.init` alone opens exactly one scope, so with only
# the init in the fixture `bad_at` 2, 3 and 4 never fire and all four rows print
# the same number. That was the bug the first run of this gate found in ITSELF.
def fx_refuse(bad_at: U32) -> Pass:
  prog.call(bufs3(), 1, 8, 1, 1, 4, False{}, fx_fail(BOTH(), bad_at))

def created(t: Tr) -> List<&2, U32>: Tr.args(CALL_CREATE(), Tr.calls(t))
def released(t: Tr) -> List<&2, U32>: Tr.args(CALL_RELEASE(), Tr.calls(t))
def waited(t: Tr) -> List<&2, U32>: Tr.args(CALL_WAIT(), Tr.calls(t))
def dispatched(t: Tr) -> List<&2, U32>: Tr.args(CALL_DISPATCH(), Tr.calls(t))
def grouped(t: Tr) -> List<&2, U32>: Tr.args(CALL_SET_BIND_GROUP(), Tr.calls(t))
def written(t: Tr) -> List<&2, U32>: Tr.args(CALL_WRITE(), Tr.calls(t))
def ncalls(k: U32, t: Tr) -> U32: Tr.count(k, Tr.calls(t))
def ncreated(t: Tr) -> U32: U32.from_nat(List.length(&2, U32, created(t)))
def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

# --- 1: the backend table, :10 and :169 -------------------------------------
def t_backend() -> IO(Unit):
  do IO<Unit>:
    urow("wg_backend_webgpu", backend_of("WGPUBackendType_WebGPU"))
    urow("wg_backend_d3d12", backend_of("WGPUBackendType_D3D12"))
    urow("wg_backend_metal", backend_of("WGPUBackendType_Metal"))
    urow("wg_backend_vulkan", backend_of("WGPUBackendType_Vulkan"))
    urow("wg_backend_opengles", backend_of("WGPUBackendType_OpenGLES"))
    urow("wg_backend_bare", backend_of("Metal"))
    urow("wg_backend_empty", backend_of(""))
    urow("wg_backend_unknown", backend_of("nonsense"))
    row("wg_backend_dev", U32.is_eq(Dev.backend(dev.init(METAL(), BOTH())), 5))

# --- 2: the feature filter and the two derived values, :172-177 and :190 ------
def t_features() -> IO(Unit):
  do IO<Unit>:
    row("wg_feat_order_forward", u32_list_eq(features_of(BOTH()), [3, 8]))
    row("wg_feat_order_reverse", u32_list_eq(features_of(REVERSED()), [8, 3]))
    row("wg_feat_only_ts", u32_list_eq(features_of(TS()), [3]))
    row("wg_feat_only_f16", u32_list_eq(features_of(F16()), [8]))
    row("wg_feat_none", u32_list_eq(features_of(NEITHER()), Nil{}))
    row("wg_feat_drops_others", u32_list_eq(features_of([1, 2, 8, 9, 3]), [8, 3]))
    row("wg_arch_f16", String.eq(Dev.arch(dev.init(METAL(), F16())), "shader-f16"))
    row("wg_arch_empty", String.eq(Dev.arch(dev.init(METAL(), TS())), ""))
    row("wg_arch_missing", String.eq(Dev.arch(dev.init(METAL(), NEITHER())), ""))
    urow("wg_nrequired_two", Dev.nrequired(dev.init(METAL(), BOTH())))
    urow("wg_nrequired_one", Dev.nrequired(dev.init(METAL(), F16())))
    urow("wg_nrequired_zero", Dev.nrequired(dev.init(METAL(), NEITHER())))
    row("wg_feat_device_kept", u32_list_eq(Dev.features(dev.init(METAL(), REVERSED())), [8, 3]))

# --- 3: the init ORDER, :11 then :166-187 ------------------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    +d : Dev <- IO.pure(Dev, dev.init(METAL(), BOTH()))
    +t : Tr <- IO.pure(Tr, Dev.tr(d))
    row("wg_init_order", seq(t, [Call{CALL_CREATE, OBJ_INSTANCE},
      Call{CALL_WAIT, SYNC_REQUEST_ADAPTER}, Call{CALL_GET_FEATURES, 0},
      Call{CALL_FREE_FEATURES, 0}, Call{CALL_GET_LIMITS, 0},
      Call{CALL_WAIT, SYNC_REQUEST_DEVICE}, Call{CALL_CREATE, OBJ_QUEUE},
      Call{CALL_RELEASE, OBJ_ADAPTER}]))
    row("wg_init_exact", u32_list_eq(created(t), [OBJ_INSTANCE, OBJ_QUEUE]))
    row("wg_init_waits", u32_list_eq(waited(t), [SYNC_REQUEST_ADAPTER, SYNC_REQUEST_DEVICE]))
    row("wg_init_released", u32_list_eq(released(t), [OBJ_ADAPTER]))
    urow("wg_init_get_features", ncalls(CALL_GET_FEATURES(), t))
    urow("wg_init_free_features", ncalls(CALL_FREE_FEATURES(), t))
    urow("wg_init_get_limits", ncalls(CALL_GET_LIMITS(), t))
    urow("wg_init_pops", ncalls(CALL_POP(), t))
    urow("wg_init_depth", Tr.depth(t))
    row("wg_init_ids_ordered", Bool.and(U32.is_lt(Dev.instance(d), Dev.adapter(d)),
      Bool.and(U32.is_lt(Dev.adapter(d), Dev.device_res(d)), U32.is_lt(Dev.device_res(d), Dev.queue(d)))))
    srow("wg_dev_backend", String.concat([Dev.arch(d), " ", U32.show(Dev.nrequired(d))]))

# --- 4: the layout derivation, :74-78 ----------------------------------------
def t_layout() -> IO(Unit):
  do IO<Unit>:
    row("wg_bgl_none", u32_list_eq(bgl.flat(bgl.of(0, 0), Nil{}), [0, 1]))
    row("wg_bgl_1_0", u32_list_eq(bgl.flat(bgl.of(1, 0), Nil{}), [0, 1, 1, 2]))
    row("wg_bgl_3_1", u32_list_eq(bgl.flat(bgl.of(3, 1), Nil{}), [0, 1, 1, 2, 2, 2, 3, 2, 4, 1]))
    row("wg_bgl_0_2", u32_list_eq(bgl.flat(bgl.of(0, 2), Nil{}), [0, 1, 1, 1, 2, 1]))
    row("wg_bgl_5_0", u32_list_eq(bgl.flat(bgl.of(5, 0), Nil{}), [0, 1, 1, 2, 2, 2, 3, 2, 4, 2, 5, 2]))
    urow("wg_bgl_nentries", Pass.nentries(Pass.reset(pass.layout(3, 1, Pass.of("k", BOTH())))))
    urow("wg_bgl_nentries_0", Pass.nentries(Pass.reset(pass.layout(0, 0, Pass.of("k", BOTH())))))

# --- 5: one program call, :69-138 --------------------------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    +p : Pass <- IO.pure(Pass, fx_call(F16(), False{}))
    +t : Tr <- IO.pure(Tr, Pass.tr(p))
    # THE MATCHER PINS ITSELF FIRST, because five rows above depend on it being a
    # real subsequence test: a reversed pair must NOT match, and an entry that
    # never happened must NOT match.
    row("wg_has_rejects_reverse", Bool.not(seq(t, [Call{CALL_SUBMIT, 1},
      Call{CALL_FINISH, 1}])))
    row("wg_has_rejects_absent", Bool.not(seq(t, [Call{CALL_DISPATCH, 999}])))
    row("wg_call_order", seq(t, [Call{CALL_PUSH, FILTER_VALIDATION},
      Call{CALL_CREATE, OBJ_BIND_GROUP_LAYOUT}, Call{CALL_POP, FILTER_VALIDATION},
      Call{CALL_PUSH, FILTER_VALIDATION}, Call{CALL_CREATE, OBJ_PIPELINE_LAYOUT},
      Call{CALL_POP, FILTER_VALIDATION}, Call{CALL_CREATE, OBJ_BUFFER},
      Call{CALL_CREATE, OBJ_BUFFER}, Call{CALL_PUSH, FILTER_VALIDATION},
      Call{CALL_CREATE, OBJ_BIND_GROUP}, Call{CALL_POP, FILTER_VALIDATION},
      Call{CALL_WAIT, SYNC_CREATE_PIPELINE}, Call{CALL_CREATE, OBJ_COMMAND_ENCODER},
      Call{CALL_BEGIN, 0}, Call{CALL_SET_PIPELINE, 0},
      Call{CALL_SET_BIND_GROUP, BIND_GROUP_INDEX()}, Call{CALL_DISPATCH, 8},
      Call{CALL_END, 0}, Call{CALL_FINISH, 1}, Call{CALL_SUBMIT, 1}]))
    row("wg_call_created", u32_list_eq(created(t), [OBJ_BIND_GROUP_LAYOUT,
      OBJ_PIPELINE_LAYOUT, OBJ_BUFFER, OBJ_BUFFER, OBJ_BIND_GROUP,
      OBJ_COMMAND_ENCODER]))
    row("wg_call_released", u32_list_eq(released(t), [OBJ_BIND_GROUP_LAYOUT,
      OBJ_PIPELINE_LAYOUT, OBJ_BIND_GROUP, OBJ_COMPUTE_PIPELINE,
      OBJ_COMMAND_ENCODER, OBJ_COMPUTE_PASS, OBJ_COMMAND_BUFFER]))
    row("wg_call_waits", u32_list_eq(waited(t), [SYNC_CREATE_PIPELINE]))
    row("wg_call_bindgroup0", u32_list_eq(grouped(t), [BIND_GROUP_INDEX()]))
    row("wg_call_dispatch_x", u32_list_eq(dispatched(t), [8]))
    urow("wg_call_dispatch_n", ncalls(CALL_DISPATCH(), t))
    urow("wg_call_pushes", ncalls(CALL_PUSH(), t))
    urow("wg_call_pops", ncalls(CALL_POP(), t))
    urow("wg_call_depth", Tr.depth(t))
    urow("wg_call_calls", seen(t))
    lrow("wg_call_sizes", Pass.sizes(p))
    urow("wg_call_ls_recorded", Pass.ls(p))
    urow("wg_call_gx", Pass.gx(p))
    urow("wg_call_entry_count", Pass.nentries(p))
    urow("wg_life_pushes", ncalls(CALL_PUSH(), Pass.tr(fx_life(BOTH(), False{}))))
    urow("wg_life_pops", ncalls(CALL_POP(), Pass.tr(fx_life(BOTH(), False{}))))

# --- 6: the wait arms, :71 and :112-145 --------------------------------------
def t_wait() -> IO(Unit):
  do IO<Unit>:
    +p : Pass <- IO.pure(Pass, fx_call(BOTH(), True{}))
    +t : Tr <- IO.pure(Tr, Pass.tr(p))
    row("wg_wait_flag", Pass.wait(p))
    row("wg_wait_query_created", seq(t, [Call{CALL_CREATE, OBJ_COMMAND_ENCODER},
      Call{CALL_CREATE, OBJ_QUERY_SET}, Call{CALL_CREATE, OBJ_BUFFER},
      Call{CALL_BEGIN, 0}]))
    row("wg_wait_resolve_between", seq(t, [Call{CALL_END, 0},
      Call{CALL_RESOLVE, QUERY_COUNT()}, Call{CALL_FINISH, 1}]))
    row("wg_wait_tail", seq(t, [Call{CALL_RELEASE, OBJ_COMMAND_BUFFER},
      Call{CALL_CREATE, OBJ_BUFFER}, Call{CALL_CREATE, OBJ_COMMAND_ENCODER},
      Call{CALL_COPY, QUERY_BUF_SIZE()}, Call{CALL_FINISH, 1},
      Call{CALL_SUBMIT, 1}, Call{CALL_RELEASE, OBJ_COMMAND_BUFFER},
      Call{CALL_RELEASE, OBJ_COMMAND_ENCODER}, Call{CALL_WAIT, SYNC_MAP_ASYNC},
      Call{CALL_MAPPED_RANGE, QUERY_BUF_SIZE()}, Call{CALL_DESTROY, OBJ_BUFFER},
      Call{CALL_RELEASE, OBJ_BUFFER}, Call{CALL_DESTROY, OBJ_BUFFER},
      Call{CALL_RELEASE, OBJ_BUFFER}, Call{CALL_DESTROY_QUERY_SET, OBJ_QUERY_SET},
      Call{CALL_RELEASE, OBJ_QUERY_SET}]))
    row("wg_wait_waits", u32_list_eq(waited(t), [SYNC_CREATE_PIPELINE, SYNC_MAP_ASYNC]))
    urow("wg_wait_destroys", ncalls(CALL_DESTROY(), t))
    urow("wg_wait_query_destroys", ncalls(CALL_DESTROY_QUERY_SET(), t))
    urow("wg_wait_created_n", ncreated(t))
    +n : Pass <- IO.pure(Pass, fx_call(F16(), True{}))
    +nt : Tr <- IO.pure(Tr, Pass.tr(n))
    row("wg_wait_no_ts_flag", Bool.not(Pass.wait(n)))
    urow("wg_wait_no_ts_created", ncreated(nt))
    urow("wg_wait_no_ts_resolve", ncalls(CALL_RESOLVE(), nt))
    urow("wg_wait_no_ts_qdestroy", ncalls(CALL_DESTROY_QUERY_SET(), nt))
    urow("wg_wait_no_ts_map", ncalls(CALL_MAP_ASYNC(), nt))
    +m : Pass <- IO.pure(Pass, fx_call(BOTH(), False{}))
    row("wg_wait_false_flag", Bool.not(Pass.wait(m)))
    urow("wg_wait_false_query", ncalls(CALL_RESOLVE(), Pass.tr(m)))

# --- 7: the four pop_error sites, :64, :84, :91, :102 -----------------------
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +p1 : Pass <- IO.pure(Pass, fx_refuse(1))
    +p2 : Pass <- IO.pure(Pass, fx_refuse(2))
    +p3 : Pass <- IO.pure(Pass, fx_refuse(3))
    +p4 : Pass <- IO.pure(Pass, fx_refuse(4))
    # the counts INCLUDE the init's two creates (INSTANCE, QUEUE), which is why
    # the floor is 3 and not 1.
    urow("wg_refuse_shader_n", ncreated(Pass.tr(p1)))
    urow("wg_refuse_layout_n", ncreated(Pass.tr(p2)))
    urow("wg_refuse_playout_n", ncreated(Pass.tr(p3)))
    urow("wg_refuse_group_n", ncreated(Pass.tr(p4)))
    urow("wg_refuse_shader_calls", seen(Pass.tr(p1)))
    urow("wg_refuse_layout_calls", seen(Pass.tr(p2)))
    urow("wg_refuse_playout_calls", seen(Pass.tr(p3)))
    urow("wg_refuse_group_calls", seen(Pass.tr(p4)))
    urow("wg_refuse_shader_pops", ncalls(CALL_POP(), Pass.tr(p1)))
    urow("wg_refuse_layout_pops", ncalls(CALL_POP(), Pass.tr(p2)))
    urow("wg_refuse_playout_pops", ncalls(CALL_POP(), Pass.tr(p3)))
    urow("wg_refuse_layout_dispatch", ncalls(CALL_DISPATCH(), Pass.tr(p2)))
    urow("wg_refuse_group_dispatch", ncalls(CALL_DISPATCH(), Pass.tr(p4)))
    urow("wg_refuse_group_pops", ncalls(CALL_POP(), Pass.tr(p4)))
    urow("wg_refuse_group_depth", Tr.depth(Pass.tr(p4)))
    row("wg_refuse_shader_flag", Tr.refused(Pass.tr(p1)))
    row("wg_refuse_layout_order", seq(Pass.tr(p2), [Call{CALL_PUSH, FILTER_VALIDATION},
      Call{CALL_CREATE, OBJ_SHADER_MODULE}, Call{CALL_POP, FILTER_VALIDATION},
      Call{CALL_PUSH, FILTER_VALIDATION}, Call{CALL_CREATE, OBJ_BIND_GROUP_LAYOUT},
      Call{CALL_POP, FILTER_VALIDATION}]))
    row("wg_refuse_group_last_pop", seq(Pass.tr(p4), [Call{CALL_CREATE, OBJ_BIND_GROUP},
      Call{CALL_POP, FILTER_VALIDATION}]))

# --- 8: the allocator and the host transfers, :150-163, :206-221 ------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    urow("wg_alloc_size_0", alloc.size(0))
    urow("wg_alloc_size_1", alloc.size(1))
    urow("wg_alloc_size_4", alloc.size(4))
    urow("wg_alloc_size_5", alloc.size(5))
    urow("wg_alloc_size_9", alloc.size(9))
    row("wg_alloc_usage", U32.is_eq(alloc.usage(), 140))
    row("wg_uniform_usage", U32.is_eq(dev.uniform_usage(), 72))
    row("wg_readable_usage", U32.is_eq(copy.readable_usage(), 9))
    row("wg_query_usage", U32.is_eq(U32.or(USAGE_QUERY_RESOLVE(), USAGE_COPY_SRC()), 516))
    +a : Made <- IO.pure(Made, alloc.of(5, Tr.of()))
    urow("wg_alloc_buf_size", Buf.size(Made.buf(a)))
    urow("wg_alloc_created", ncalls(CALL_CREATE(), Made.tr(a)))
    urow("wg_copyin_len_5", copy.write_len(5))
    urow("wg_copyin_len_4", copy.write_len(4))
    urow("wg_copyin_len_0", copy.write_len(0))
    urow("wg_copyin_pad_5", copy.pad(5))
    urow("wg_copyin_pad_4", copy.pad(4))
    +c : Tr <- IO.pure(Tr, copy.copyin(5, Tr.of()))
    row("wg_copyin_writes_padded", u32_list_eq(written(c), [8]))
    +r : Made <- IO.pure(Made, copy.readable(16, Tr.of()))
    row("wg_readable_released", u32_list_eq(released(Made.tr(r)),
      [OBJ_COMMAND_BUFFER, OBJ_COMMAND_ENCODER]))
    urow("wg_readable_size", Buf.size(Made.buf(r)))
    +fm : Tr <- IO.pure(Tr, dev.free(3, OBJ_BUFFER, Tr.of()))
    row("wg_free_mapped", seq(fm, [Call{CALL_UNMAP, OBJ_BUFFER},
      Call{CALL_DESTROY, OBJ_BUFFER}, Call{CALL_RELEASE, OBJ_BUFFER}]))
    +fu : Tr <- IO.pure(Tr, dev.free(1, OBJ_BUFFER, Tr.of()))
    row("wg_free_unmapped", seq(fu, [Call{CALL_DESTROY, OBJ_BUFFER},
      Call{CALL_RELEASE, OBJ_BUFFER}]))
    urow("wg_free_unmapped_unmaps", ncalls(CALL_UNMAP(), fu))
    row("wg_free_bytes_0", u32_list_eq(dev.uniform_bytes(0), [0, 0, 0, 0]))
    row("wg_free_bytes_1", u32_list_eq(dev.uniform_bytes(1), [1, 0, 0, 0]))
    row("wg_free_bytes_neg", u32_list_eq(dev.uniform_bytes(4294967295), [255, 255, 255, 255]))
    +u : Made <- IO.pure(Made, dev.create_uniform(dev.uniform_bytes(1), Tr.of()))
    row("wg_free_uniform_created", seq(Made.tr(u), [Call{CALL_CREATE, OBJ_BUFFER},
      Call{CALL_WRITE, 4}]))
    urow("wg_free_uniform_size", Buf.size(Made.buf(u)))

# --- 9: `synchronous`, :23-50 -------------------------------------------------
def t_sync() -> IO(Unit):
  do IO<Unit>:
    urow("wg_sync_ret_0", sync_ret(0n))
    urow("wg_sync_ret_1", sync_ret(1n))
    urow("wg_sync_ret_2", sync_ret(2n))
    urow("wg_sync_ret_3", sync_ret(3n))
    urow("wg_sync_emsg_1", sync_has_emsg(SYNC_MAP_ASYNC()))
    urow("wg_sync_emsg_2", sync_has_emsg(SYNC_POP_ERROR_SCOPE()))
    urow("wg_sync_emsg_3", sync_has_emsg(SYNC_CREATE_PIPELINE()))
    urow("wg_sync_emsg_4", sync_has_emsg(SYNC_REQUEST_ADAPTER()))
    urow("wg_sync_emsg_5", sync_has_emsg(SYNC_REQUEST_DEVICE()))
    urow("wg_sync_emsg_6", sync_has_emsg(SYNC_WORK_DONE()))
    urow("wg_sync_payload_noemsg_2", U32.from_nat(sync_payload(2n, SYNC_NO_EMSG())))
    urow("wg_sync_payload_noemsg_0", U32.from_nat(sync_payload(0n, SYNC_NO_EMSG())))
    urow("wg_sync_payload_emsg_2", U32.from_nat(sync_payload(2n, SYNC_HAS_EMSG())))
    row("wg_sync_tail", String.eq(sync_tail("WGPUBufferMapAsyncStatus_InstanceDropped"),
      "InstanceDropped"))
    # no '_' at all, so the whole string is the "member" -- which is the shape of
    # the one status name Python does NOT have, and the row says so.
    row("wg_sync_tail_missing", String.eq(sync_tail("None"), "None"))
    urow("wg_sync_names2", U32.from_nat(List.length(&2, String, H.dedup_str(sync_name.six2()))))
    urow("wg_sync_names3", U32.from_nat(List.length(&2, String, H.dedup_str(sync_name.six3()))))
    srow("wg_sync_name_mapasync3", sync_name.of(SYNC_MAP_ASYNC(), 3))
    srow("wg_sync_name_pop3", sync_name.of(SYNC_POP_ERROR_SCOPE(), 3))
    srow("wg_sync_name_pipeline3", sync_name.of(SYNC_CREATE_PIPELINE(), 3))
    srow("wg_sync_name_adapter3", sync_name.of(SYNC_REQUEST_ADAPTER(), 3))
    srow("wg_sync_name_device3", sync_name.of(SYNC_REQUEST_DEVICE(), 3))
    srow("wg_sync_name_workdone3", sync_name.of(SYNC_WORK_DONE(), 3))
    srow("wg_sync_name_success", sync_name.of(SYNC_REQUEST_ADAPTER(), 1))
    srow("wg_sync_err_adapter", sync_error(SYNC_REQUEST_ADAPTER(), 3, "no adapter"))
    srow("wg_sync_err_empty", sync_error(SYNC_WORK_DONE(), 3, ""))
    srow("wg_sync_err_ok", sync_error(SYNC_REQUEST_ADAPTER(), 1, "unreachable"))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_backend()
    b : Unit <- t_features()
    +c : Unit <- t_init()
    d : Unit <- t_layout()
    e : Unit <- t_call()
    f : Unit <- t_wait()
    g : Unit <- t_refuse()
    h : Unit <- t_alloc()
    i : Unit <- t_sync()
    IO.print("wg-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number below is the harness's output, not an
# estimate. The harness applies one edit to a scratch copy, runs the INTERPRETED
# lane, and diffs the row NAMES; the useful column is "rows MOVED", because a
# mutation that moves nothing measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `bgl.entry.put`: `U32.is_ge(i, nbufs)` -> `U32.is_gt(i, nbufs)` | 2 | :78's `'Uniform' if i >= len(bufs)`, off by one at the boundary. Two rows and not five because `wg_bgl_none` has no boundary and `wg_bgl_1_0` does not reach `i == nbufs`. |
# | M2 | `bgl.of`: drop the binding-0 entry | 8 | the INFINITY entry itself. Every layout row AND `wg_bgl_nentries` AND `wg_call_entry_count` move, because the derivation is live in the port and not only in the gate. |
# | M3 | `pass.release`: swap the first TWO releases | 1 | :132-133's `bindLayout` before `pipelineLayout`. `wg_call_released` only -- the sequence rows do not mention the releases. |
# | M4 | `copy.readable`: swap its two releases | 2 | :216-217's `cmd_buf` before `encoder` -- the REVERSE of creation, against :132-138's creation order. `wg_wait_tail` moves too, so the two orders cannot be confused for one another. |
# | M5 | `pass.set`: `SetBindGroup` before `SetPipeline` | 1 | :121 before :122. `wg_call_order` and NOTHING ELSE -- which is why `Tr.has` has to be a real subsequence test for the five order rows to mean anything. |
# | M6 | `pass.geometry`: swap the dispatch's X and Y slots | 3 | that :123 dispatches `global_size`, not `local_size`. `wg_call_gx`, `wg_call_dispatch_x` and (incidentally) `wg_call_order`. |
# | M7 | `copy.copyin`: write the UNPADDED length | 1 | that `write_buffer` receives `round_up(nbytes, 4)`. Only `wg_copyin_writes_padded` sees it: the `copy.write_len` rows pin the function, not its caller. |
# | M8 | `dev.free.at`: always unmap | 1 | :196's map-state guard. One row, and it is the count row -- the `wg_free_unmapped` sequence still holds, because a spurious UNMAP does not disturb UNMAP, DESTROY, RELEASE. |
# | M9 | `prog.wants_wait`: drop the TimestampQuery conjunct | 7 | :71's `wait and ... in self.dev.features`. |
# | M10 | `keeps_feature`: drop the ShaderF16 conjunct | 9 | :173-174's two-element probe list. |
# | M11 | `dev.init`: request the device BEFORE reading the limits | 1 | :180 before :184. |
# | M12 | `sync_payload`: always add the trailing element | 1 | :34's `[] if has_emsg else [None]` -- and only the True side moves, because `wg_sync_payload_emsg_2` is the only row that reads it. `wg_sync_payload_noemsg_*` are unaffected, which is the point: the two sides are separate claims. |
# | M13 | `alloc.size`: no 4-byte alignment | 4 | :152's `round_up(size, 4)`. |
# | M14 | `pass.uniforms.put`: a BUFFER slot takes 4 | 1 | :96's `size=wgpuBufferGetSize(buf)` against a uniform's own 4. |
# | M15 | `backend_of.put`: every name matches | 8 | the reverse lookup at all -- an implementation that cannot say "no name matched". |
# | M16 | `Tr.emit.go`: drop the `raise` guard | 10 | THE RAISE. Every refusal row at once, and nothing else. |
# | M17 | `pass.finish`: SUBMIT before FINISH | 2 | :128 before :129 -- and `wg_has_rejects_reverse` as well, because the mutation makes the reversed pair actually present. That row was written to pin `Tr.has` and turned out to double as an order row. |
# | M18 | `pass.query`: the `if wait:` arms are swapped | 5 | :112's `if wait:`. |
# | M19 | `dev.uniform_bytes.go`: every byte is 255 | 2 | :204's little-endian byte order, for the two fixtures whose low byte is not already 255. `wg_free_bytes_neg` does NOT move, because its expected bytes ARE 255 -- that row is blind to the byte ORDER and says so. |
# | M20 | `features_keep.put`: keep EVERY feature | 3 | that the filter drops anything at all. It moves only the three rows with a non-probe feature in the input: with nothing to drop, a filter that drops nothing is an EQUIVALENCE. |
# | M21 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
# | M22 | `sync_name.of.err`: the two and three arms are swapped | 8 | that each wrapped call carries its OWN status enum -- every name row, plus both distinct-counts. |
# | M23 | (not run) `Tr.has` with the fuel set to the PATTERN length | 0 -- A REAL BLIND SPOT, FOUND AND FIXED | see THE MATCHER below. |
#
# M23 is the honest half of this table. Before it was fixed, `wg_call_order`,
# `wg_init_order`, `wg_wait_resolve_between`, `wg_refuse_layout_order`,
# `wg_refuse_group_last_pop`, `wg_free_mapped`, `wg_free_unmapped` and
# `wg_readable_released` were eight rows that could not fail: the matcher's fuel
# was the pattern's length, so it returned `True{}` after patlen trace entries
# without ever comparing `at`, and a reversed pattern matched. M5 and M11 are the
# two mutations that exposed it -- they moved nothing, which is the measurement.
# `wg_has_rejects_reverse` and `wg_has_rejects_absent` now pin the matcher
# itself, and every mutation above that touches an ORDER moves its row.
#
# WHAT THIS GATE STILL DOES NOT SEE, and it is a short list:
#
#   1. The DESCRIPTORS. `Tr` records the call and, for four calls, one argument.
#     Every usage bitmask, entry count, offset and buffer size is a pure function
#     with its own row -- `wg_alloc_usage`, `wg_uniform_usage`, `wg_readable_usage`,
#     `wg_query_usage`, `wg_bgl_nentries`, `wg_call_sizes` -- but nothing checks
#     that the RIGHT one is passed to the RIGHT call. Mutating
#     `copy.readable` to create its staging buffer with `alloc.usage()` instead of
#     `copy.readable_usage()` moves nothing, because both are one `CALL_CREATE`
#     with the same object kind.
#   2. THE DESCRIPTOR-FIELD CORRELATIONS. `comp_pass_desc.timestampWrites` (:116),
#     `bindGroupLayouts=(...)` (:87), `entryCount` (:82) and `WGPUComputeState(
#     module, entryPoint)` (:106) are all fields of objects the trace does not
#     carry. In particular NOTHING checks that `pass.pipeline`'s `entryPoint` is
#     the entry point `Pass.of` was given: the only reader would be the FFI seam,
#     so the reader `Pass.entry` was deleted rather than left as a def nothing
#     called. The entry point is still in the `Pass` record, and the gate has no
#     row that reads it -- that is the gap, stated rather than papered over.
#   3. THE u64 AND f32 ARITHMETIC. Walls 2 and 3. `wg_free_bytes_*` covers the int
#     path; the timestamp delta and `struct.pack('<f', val)` are not computed at
#     all, by construction.
#   4. THE LIMITS TABLE (:181). The port asks the adapter before it requests the
#     device and then does nothing with the answer, which is faithful and is also
#     the whole of the gap.
#   5. `pop_error`'s MESSAGE. `Tr.pop` keeps the question and not the string, so a
#     port that picked payload[0] instead of payload[1] would be invisible here.
#     `wg_sync_payload_*` pins the arithmetic that makes [1] the message; nothing
#     pins the index.
#   6. THE WGSL TEXT. :57-59 hands `obj.lib` to the shader module. The port takes
#     `entry` from `TinyELF.name` and nothing else, because the WGSL source is
#     wgsl.bend's artefact. That half of the interface is checked on neither side.
#   7. THE CONSTANTS THAT ARE THE PORT'S OWN TAGS, MEASURED, NOT GUESSED. This is
#     the `device.bend` `sig=0 4 5` shape at full size and it had ~45 rows in it.
#     Splitting the constants by WHERE THEY COME FROM is what made it fixable,
#     and the split is a fact about `autogen/webgpu.py`, not a preference:
#
#       a. REAL wgpu values, reachable by a wrong value reaching a wrong call.
#          Nine of them -- the `WGPUBufferUsage_*` bit flags, the two
#          `WGPUFeatureName` ids, and the three `WGPUBufferMapState` members --
#          and all NINE now have a LITERAL on one side of the row that uses them:
#          `wg_alloc_usage` 140, `wg_uniform_usage` 72, `wg_readable_usage` 9,
#          `wg_query_usage` 516, `wg_feat_order_forward` [3, 8],
#          `wg_feat_only_ts` [3], `wg_feat_only_f16` [8], and `wg_free_mapped` /
#          `wg_free_unmapped` which now pass 3 and 1 to `dev.free` instead of
#          naming `MAP_MAPPED` / `MAP_UNMAPPED`. Every literal was READ OUT of
#          `tinygrad/runtime/autogen/webgpu.py` by importing that module and
#          reading its enum dicts; none was typed. Before this, `wg_feat_only_ts`
#          read `u32_list_eq(features_of(TS()), TS())` -- the fixture and the
#          expectation were the SAME def, so no edit to the feature id could move
#          the row.
#
#       b. PORT-INVENTED TAGS that never reach wgpu, so a wrong value is not a
#          wrong call. `OBJ_*` (there is NO `WGPUObjectType` in
#          `autogen/webgpu.py`; these are the trace's own object-kind ids) and
#          `CALL_*` (the trace's own opcodes). Their rows are still worth having
#          -- `u32_list_eq(created(t), [OBJ_INSTANCE, OBJ_QUEUE])` checks WHICH
#          objects are created and IN WHAT ORDER, and no fixture can separate that
#          claim from the port's own tag numbering -- but they are recorded here
#          as value-blind so nobody reads them as checking the number.
#          NOT PINNED, DELIBERATELY: `OBJ_INSTANCE`(0) `OBJ_ADAPTER`(1)
#          `OBJ_QUEUE`(3) `OBJ_SHADER_MODULE`(4) `OBJ_BIND_GROUP_LAYOUT`(5)
#          `OBJ_PIPELINE_LAYOUT`(6) `OBJ_BIND_GROUP`(7) `OBJ_COMPUTE_PIPELINE`(8)
#          `OBJ_COMMAND_ENCODER`(9) `OBJ_COMPUTE_PASS`(10) `OBJ_COMMAND_BUFFER`(11)
#          `OBJ_QUERY_SET`(12) `OBJ_BUFFER`(13), and all 23 `CALL_*`.
#
#       c. `SYNC_*` 1..6 -- the port's INDEX into the six `synchronous`-wrapped
#          calls, not a wgpu value: all six real calls pass the SAME
#          `WGPUCallbackMode_WaitAnyOnly` (=1). So the `wg_sync_name_*` rows are
#          blind to these numbers and check the six status-name strings instead,
#          which are literals in this file. NOT PINNED, DELIBERATELY.
# ===========================================================================
