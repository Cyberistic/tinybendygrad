# tinybendygrad/runtime/ops_webgpu.bend -- port of tinygrad/runtime/ops_webgpu.py
#
# the run side of the browser target. ops_webgpu.py is wgpu-py: every call is a
# ctypes call into `tinygrad/runtime/autogen/webgpu.py`. In a browser those calls
# become js-glue ffi, and what survives the crossing is the structure -- device
# init, buffer upload/download, the per-call object graph, dispatch geometry,
# and the future-to-synchronous protocol. That structure is what this file
# ports. Every actual wgpu call is a `# TODO(p3) runtime/ops_webgpu.py:<line>`
# naming the js import it becomes; nothing here calls wgpu.
#
# the split, stated once and then obeyed. a def here either builds the argument
# of one wgpu call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the order). There is no third kind.
#

# what is ported, DEF by DEF.
#
#   :11  `backend_types`            ported  the port's own backend_names/backend_of
#   tinygrad/runtime/ops_webgpu.py:12 `instance`      ported  `dev.create_instance` symbol=instance
#   :13  from_wgpu_str               wall 1  string views
#   :14  to_wgpu_str                 wall 1  string views
#   :17  buf_to_mv                   ported  `copy.read`
#   :24  `synchronous`                 ported  the port's own sync_ret/sync_has_emsg,
#                                             sync_payload/sync_name/sync_error
#   :45  BufferMapAsync              ported  a wait, in `copy.read`
#   :46  DevicePopErrorScope         ported  a wait, in `Tr.pop`
#   :47  DeviceCreateComputePipeline ported  a wait, in `pass.pipeline`
#   tinygrad/runtime/ops_webgpu.py:49 `InstanceRequestAdapter` ported  a wait, in `dev.request_adapter` symbol=InstanceRequestAdapter
#   tinygrad/runtime/ops_webgpu.py:50 `AdapterRequestDevice` ported  a wait, in `dev.request_device` symbol=AdapterRequestDevice
#   :50  QueueOnSubmittedWorkDone    dead   the only caller was `dev.synchronize`,
#                                             which nothing called. The status
#                                             enum is still in `sync_name`.
#   :53  WebGPUProgram.__init__      ported  `prog.init`
#   :67  __del__                     dead   `prog.del` reached nothing. This row
#                                             was what kept it alive: a ported
#                                             claim in this table is a use.
#   :71  the `wait` flag                 ported  the port's own prog.wants_wait
#   :74  bgl_entry                   ported  `bgl.entry`
#   :77  bind_entries                ported  `bgl.of`  <- the layout derivation
#   :81  CreateBindGroupLayout       ported  `pass.layout`
#   :87  PipelineLayoutDescriptor    ported  `pass.playout`
#   :94  bg_entry                    ported  `pass.uniforms`
#   :99  CreateBindGroup             ported  `pass.group`
#   :105 ComputePipelineDescriptor   ported  `pass.pipeline`
#   :109 CreateCommandEncoder        ported  `pass.encoder`
#   :113 CreateQuerySet/CreateBuffer ported  `pass.query`
#   :120 beginComputePass            ported  `pass.begin`
#   :121-124 setPipeline/BindGroup/dispatch/end
#                                        ported  `pass.set`, `pass.dispatch`,
#                                                `pass.end`
#   :126 ResolveQuerySet             ported  `pass.resolve`
#   :128-129 finish/submit           ported  `pass.finish`
#   :132-138 the seven releases      ported  `pass.release`
#   :141 the timestamp arithmetic    wall 2  the 64-bit wall
#   :150 _alloc                      ported  `alloc.of`
#   :154 _copyin                     ported  `copy.copyin`
#   :159 _copyout                    dead   `copy.copyout` reached nothing
#   :163 _free                       dead   `alloc.free` died with its only
#                                             caller. `dev.free` below is the
#                                             same Python branch and is ported.
#   :166-190 WebGpuDevice.__init__   ported  `dev.init`
#   :192 synchronize                 dead   `dev.synchronize` reached nothing
#   :195-198 free                    ported  `dev.free`
#   :200 pop_error                   ported  `Tr.pop` (see the payload)
#   :201-205 create_uniform           partial `dev.create_uniform`, int arm only
#   :206-219 _readable_buffer        ported  `copy.readable`
#   :220-221 write_buffer            ported  `copy.write`
#

# the three walls.
#
# 1. string views (:13-14). `ctypes.string_at(sv.data, sv.length)` and
#    `create_string_buffer(s.encode())`. a WGPUStringView is a (pointer, length)
#    pair the seam frees as soon as the callback returns -- which is why :34
#    converts inside the callback. The port keeps the String and drops the pair,
#    because a String is what the entry point's name is (:54) and what the error
#    message is, and both are read immediately.
#    TODO(p3) runtime/ops_webgpu.py:14  symbol=from_wgpu_str  -- WGPUStringView -> String.
#    TODO(p3) runtime/ops_webgpu.py:15  symbol=to_wgpu_str  -- String -> WGPUStringView.
#
# 2. the 64-bit wall, and it is two lines of Python.
#      :37  `wgpuInstanceWaitAny(instance, 1, WGPUFutureWaitInfo(future), 2**64-1)`
#      tinygrad/runtime/ops_webgpu.py:142 `((timestamps:=…)[1] - timestamps[0]) / 1e9` symbol=__call__
#    The query set answers two timestamps in nanoseconds as u64 and
#    `buf_to_mv(...).cast("q")` reads them as such. Bend has no 64-bit integer
#    (`base.bend` exports `Word`, not `Word(64n)`) and no F64, so neither the
#    unbounded wait timeout nor the delta is computable here. The seam must hand
#    over the already-scaled seconds, because the only thing this port can do
#    with a time is print it.
#    TODO(p3) runtime/ops_webgpu.py:38  symbol=wrapper  -- the 2**64-1 wait timeout.
#    TODO(p3) runtime/ops_webgpu.py:142  symbol=__call__ -- the u64 timestamp delta and its /1e9.
#
# 3. FLOAT uniforms (tinygrad/runtime/ops_webgpu.py:202 symbol=create_uniform). `val.to_bytes(4,'little',signed=val<0)` for an int,
#    `struct.pack('<f', val)` for a float, and :97 passes `float('inf')`.
#    `base.bend`'s F32 has no infinity literal, no bitcast and no to_bits, so the
#    f32 pattern cannot be built here at all. The INT arm is ported exactly
#    (`dev.uniform_bytes`); the float arm is four bytes the seam must hand over.
#    See the infinity entry, which is the load-bearing case.
#    TODO(p3) runtime/ops_webgpu.py:205  symbol=create_uniform  -- struct.pack('<f', val).
#
# ctypes shaping is not a wall and is named once: the
#   `(WGPUBindGroupLayoutEntry * n)(...)` array constructions at tinygrad/runtime/ops_webgpu.py:77 -- the only one
#   of that type at this pin -- and the `WGPUBindGroupEntry * n` one at tinygrad/runtime/ops_webgpu.py:97 are how Python spells "an array of n descriptors", and
# `ctypes.pointer`/`cast` at :59 and :116 spell the chained struct. The port has
# the array as a `List` and the chain as an explicit argument, which is the same
# information without the ctypes shape.
#

# the payload, which is the whole async story and it is one line long.
#
# :34  status, (*payload, emsg) = s, [<args minus userdata1/2>] + ([] if has_emsg
#      else [None])
# :41  return payload if len(payload) > 1 else payload[0] if len(payload)==1 else None
#
# Two consequences this file ports and the gate pins, because both are silent:
#
#   - The callback always appends one element. When `has_emsg` is False it
#     appends `None`, so the payload length is always nargs + 1, never nargs.
#     That is what makes :200 `DevicePopErrorScope(self.dev.device_res)[1]` the
#     message: the pop-error callback is (status, type, message), so the payload
#     is [type, message, None] and index 1 is the message. Four of the six
#     wrapped calls pass has_emsg=True (:45,47,48,49) and two pass False (:46,50)
#     -- `sync_has_emsg` is that table and `sync_payload` is the arithmetic.
#   - The tinygrad/runtime/ops_webgpu.py:42 collapse therefore never takes its `None` branch for these six
#     calls, because their payload is never empty. `sync_ret` ports the collapse
#     anyway, because the branch structure is the thing.
#
# the sync calls are also WHERE the browser differs, and the port says so:
# `wgpuInstanceWaitAny` blocks the thread. In a browser the seam returns a
# Promise and `WaitAnyOnly` has no meaning; the six `synchronous`-wrapped calls
# are the six that must become `await`. `sync_*` names them, and every call_wait
# entry in the trace is one of the six.
#

# what device.bend AND wgsl.bend owe this file. Named, because this file cannot
# be checked without them and does not pretend otherwise.
#
# device.bend owes:
#   1. `Compiled.__init__` (tinygrad/device.py:379 symbol=__init__) is handed
#      `arch="shader-f16" * (… in features)` at :190. `dev.init` produces that
#      arch string and the feature list; whoever wires the device records it.
#   2. `Program.__call__` (tinygrad/device.py:360 symbol=__call__) is called from
#      tinygrad/engine/realize.py:167 -- the `ets.append(rt(*args, ...))` line -- with `bufs` = `ast.arg.globals` resolved
#      this file needs the BUFFER list AND the val count AND nothing ELSE --
#      they are what `bgl.of` turns into entries. See the layout derivation.
#   3. `BufferStorage` (tinygrad/device.py:109 symbol=BufferStorage) is `_alloc`'s return (tinygrad/runtime/ops_webgpu.py:151 symbol=_alloc) and its `.buf`
#      is what `_copyout` (tinygrad/runtime/ops_webgpu.py:160 symbol=_copyout) and `_free`
#      (tinygrad/runtime/ops_webgpu.py:164 symbol=_free) hand back. `Buf` is that pair, and `alloc.of` is the `BufferStorage`.
#   4. `TinyELF` (tinygrad/device.py:343-345 symbol=TinyELF) carries `name`, which is the entry point (:54)
#      and the pipeline's `entryPoint` (:106). `prog.init` takes it as a String.
#
# wgsl.bend owes:
#   1. the infinity entry. `bgl.of` puts `Uniform` at binding 0 because
#      :77-78 says so, and wgsl.py:114 declares
#      `@group(0) @binding(0)  var<uniform> infinity : f32;`. Those two facts
#      must agree or every kernel faults at bind time. measured by calling
#      `WGSLRenderer.render_kernel` in CPython -- see the layout derivation.
#   2. `WGPUBufferBindingType_Storage` for a global buffer: at this pin upstream's tinygrad/runtime/ops_webgpu.py:78 -- its `AddrSpace` --
#      keys the type off the addrspace (`'Uniform' if a is AddrSpace.alu else 'Storage'`), and
#      tinygrad/renderer/wgsl.py:116 keys it off the addrspace too. They agree because both key off the
#      addrspace, not because every `ProgramInfo.globals` entry is
#      global (tinygrad/uop/ops.py:1347 symbol=globals).
#   3. `@workgroup_size(...)` (wgsl.py:118). `Program.__call__` takes a
#      `local_size` and ops_webgpu.py never reads it -- the workgroup size comes
#      from the wgsl attribute. `prog.call` takes `local_size`, records it in
#      `Pass.ls`, and never dispatches on it, so the gate can pin that.
#

# the layout derivation, :74-78, which is the part of this file that is pure
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
# the cross-file contract, measured in CPYTHON (no gpu needed; the renderer is
# pure). `WGSLRenderer(Target('WEBGPU','wgsl','shader-f16')).render_kernel` with
# three global buffers emits, verbatim:
#
#   fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }
#   @group(0) @binding(0)
#   var<uniform> infinity : f32;
#   @group(0) @binding(1)var<storage,read_write>a:array<f32>;
#   @group(0) @binding(2)var<storage,read_write>b:array<f32>;
#   @group(0) @binding(3)var<storage,read_write>c:array<i32>;
#   @compute @workgroup_size(1) fn k(@builtin(workgroup_id) gindex: vec3<u32>,
#       @builtin(local_invocation_id) lindex: vec3<u32>) {
#
# so the shader declares 1+len(bufs) bindings, in the order `bufs` was handed to
# it (cstyle.py:264 "this relies on bufs dict preserving order"), and
# `ProgramInfo.globals` (tinygrad/uop/ops.py:1347 symbol=globals, sorted+deduped by slot) is that same order.
# `pass.uniforms` binds layout entry k+1 to bufs[k]. that is the whole interface
# between this file and wgsl.bend, and a divergence there is silent in both.
#

# no wgpu in this env. `Device['WEBGPU']` fails with "failed to load library
# webgpu", so nothing here was measured against a live device. Every constant
# below was read out of `tinygrad/runtime/autogen/webgpu.py`, every status name
# out of the same file's enum dicts (measured, see `sync_name`), and every row's
# expectation is derived from the source text or from those constants.
#
import Base
import ../helpers.bend as H

# the constants. `autogen/webgpu.py` is generated ctypes bindings, so these are
# the c enum values read out of it: the bit flags at :2573-2583, and the enum
# dicts at :10 (BackendType), :135 (BufferBindingType), :268 (PowerPreference),
# :833 (FeatureName), :1545 (BufferMapState), :1550 (ErrorFilter), :1563
# (WaitStatus), :2598 (ShaderStage).

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

# the types.

# one ffi call and the object it acts on. `arg` is the object kind for create /
# release / destroy, the sync_* id for a wait, the workgroup count for a
# dispatch and the group index for a set_bind_group; unused elsewhere. There is
# deliberately no field for the rest of the call's arguments: those are what the
# defs around this record build, and the gate reads them from the record a def
# returns, not from the trace.
type Call is Data:
  Call{k: U32, arg: U32}

# ops_webgpu.py:163 `BufferStorage` reduced to the two fields this file reads:
# `.buf` (:163, :96) and the size `wgpuBufferGetSize` answers (:18, :96, :207).
type Buf is Data:
  Buf{id: U32, size: U32}

# one bind group layout entry (:75) or bind group entry (:96). `visibility` is
# WGPUShaderStage_Compute at every entry (:75) so it is not a field.
type Bgl is Data:
  Bgl{binding: U32, ty: U32}

# what one bind group entry binds: either a caller's buffer or a uniform this
# call creates (:94-95, `buf = x if isinstance(x, WGPUBuffer) else
# self.dev.create_uniform(x)`). `is_buf` false means a uniform, and then `size` is
# uniform_size because create_uniform always makes a 4-byte buffer (:203).
type Slot is Data:
  Slot{is_buf: Bool, size: U32}

# the machine state of the ffi seam. Bend has no pointer, so `next` mints the
# handle ids: what the gate checks is that they are consumed in the right order
# and the right number of times, which is the part the structure owns.
#
# `depth` is the open wgpuDevicePushErrorScope count and `bad_at` is the pop
# ordinal at which the seam should report an error (0 = never), so one fixture
# drives the `if err := self.dev.pop_error(): raise` arm at each of the four
# sites in turn. `popn` counts the pops so far and is what `bad_at` is compared
# against; it is not reset by `Tr.reset`, so one fixture numbering covers a whole
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

# one program call's state: the shader module (:63), the entry point (:54), the
# device's features (:71 reads `self.dev.features`), the `local_size` that
# ops_webgpu.py never reads, the layout descriptor's entryCount (:82), the bind
# group entry sizes (:96), the dispatch geometry (:123) and the trace.
type Pass is Data:
  Pass{module: U32, entry: String, feats: List<&2, U32>, ls: U32, nentries: U32,
       sizes: List<&2, U32>, gx: U32, gy: U32, gz: U32, wait: Bool, t: Tr}

# the trace. `Tr.emit` is the seam: every wgpu call in this file goes through it,
# so the trace is the ordered list of js imports the browser will make.
#
# the raise. `Tr.emit`, `Tr.push` AND `Tr.pop` all record nothing once a pop has
# reported an error. That is the port of `if err := self.dev.pop_error(): raise`:
# everything after the raise does not happen, including the next PushErrorScope
# and its matching pop. It is why no step below needs a guard of its own, and why
# a refusal shows up in the trace as a truncation rather than as a flag alone.
#
# The failing pop is still recorded, and that is not a special case: it sets
# `refused` in the same breath, so on entry its own `refused` is still False.
# Guarding two of the three was the first bug this gate found in itself (four
# pops and one create survived a refusal at pop 1, which is not what Python
# does); guarding all three is the fix, and `wg_refuse_*_pops` is the row that
# pins it.

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

# an empty trace that keeps `bad_at` and `popn`, so a gate can read one program
# call without the init in front of it and still number its pops from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, depth, bad_at, popn, refused}:
      Tr{Nil{}, 0, 0, bad_at, popn, False{}}

# the id the next emit mints, i.e. what the seam's call returns. Read before the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates both arms, so the emitted call is a value built here and
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
# self.dev.device_res)[1]`. The pop itself is always recorded -- it is the report
# -- and the message is the seam's, so this keeps the question and answers it at
# pop ordinal `bad_at`. See the payload for why index 1 of that payload is the
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

# reading the trace. `Tr.args` is the args of every entry with tag `k`, in order;
# `Tr.count` is how many there are; `Tr.has` is "contains this (tag, arg)
# sequence, in order".

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

# a leaf, because `Bool.pick` evaluates both arms and a recursive call inside one
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

# does the trace contain this (tag, arg) sequence, in order? `at` is how much of
# the pattern is matched so far, read out of the pattern by INDEX rather than
# carried as a second list: the head and the tail of one destructure share a
# binder, and a descent may not use that binder twice.
#
# both fields are compared, so a pattern pins the identity of each call and not
# only its kind. That is what makes `wg_init_order` and `wg_call_order` worth
# printing: they say the instance is created, then the adapter is requested, then
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

# the fuel is the trace length AND the answer is `at == patlen`. That is the whole
# matcher, and getting either half wrong makes it answer True to everything:
# with the fuel set to the pattern length, `case 0n:` fired after patlen trace
# entries and returned True{} without ever looking at `at`, so a reversed pattern
# matched and so did a pattern element that never occurs. measured, and the row
# that caught it is `wg_has_rejects` below -- the five order rows were decorative
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

# ops_webgpu.py:10 -- `backend_types = {v: k for k, v in
# webgpu.enum_WGPUBackendType.items()}`, whose one reader is
# `backend_types.get(getenv("webgpu_backend", ""), 0)` at :169. So the port needs
# the reverse direction, and the keys are the full c names: `webgpu_backend`
# must be `WGPUBackendType_Metal`, not `Metal`, and a name that is not in the
# table is Undefined (0), silently. docs/env_vars.md:42 has it right.
#
# The enum is 0..8 (autogen/webgpu.py:10), so the value is the INDEX. Force32 =
# 2147483647 is in the table too and is deliberately absent here: it is not a
# backend and no device would accept it.

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

# ops_webgpu.py:23-43 -- `synchronous`, the future-to-synchronous protocol. See
# the payload for why `has_emsg` changes the payload length and not its content.
#
# the status names are measured, not transcribed from a header: each of the six
# calls carries its own status enum, and at status 2 all six are
# `…_InstanceDropped` while at status 3 they are four different things --
# ValidationError, (absent), ValidationError, Unavailable, Error, Error. So :40's
# `status_enum.get(status)` cannot be one table, and `sync_name` is six arms.
# `wg_sync_names_distinct` pins the count and `wg_sync_names2_same` pins the fact
# that status 2 is the one place they agree.

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

# one past the last '_' in `cs`, or 0 if there is none. `pos` is the index and
# `at` is the answer, so this is the index of the last hit and not the count of
# them -- the count answers 1 for every one of these names, and dropping 1
# character instead of 26 is what `DBG_tail` printed before the two counters were
# separated.
#
# `String.drop` removes the first n characters (measured in ops_python.bend:2317 symbol=Prog.write.slash:
# take, not drop, is the one that keeps a directory), so `at` counts from the
# front.
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

# the enum member name, i.e. everything after the last '_'. This is the part that
# says which status the call means: the six status-2 names all end in
# `InstanceDropped` and the six status-3 names do not.
def sync_tail(+s: String) -> String: String.drop(s, U32.to_nat(sync_us(String.to_list(s))))

# :40 `raise RuntimeError(f"[{status_enum.get(status)}]{emsg or ''}")`, and the
# `status != 1` guard that reaches it. Status 1 is Success and never raises, so
# :38's wait failure and :40's status failure are the two raise sites and only
# :40 is spelled out here.
def sync_name.of.err(+which: U32, status: U32) -> String:
  Bool.pick(String, U32.is_eq(status, 2), sync_name.two(which), sync_name.three(which))

def sync_name.of(+which: U32, +status: U32) -> String:
  Bool.pick(String, U32.is_eq(status, STATUS_SUCCESS()), "Success", sync_name.of.err(which, status))

# ops_webgpu.py:11, :166-190 -- device init. The order is the ported structure
# and it is what `dev.init` exists to pin: instance, adapter, features, limits,
# device, queue, release the adapter. Each step is one line of Python, so each
# step is one def here.

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
# flag rides on the descriptor, so the trace cannot see it -- which is why the
# ffi seam is not optional here AND why the port names it instead of dropping it.
def dev.create_instance() -> Dev:
  Dev{Tr.here(Tr.of()), 0, 0, 0, Nil{}, 0, 0, "", Tr.emit(CALL_CREATE, OBJ_INSTANCE, Tr.of())}

# :168-169 InstanceRequestAdapter(instance, WGPURequestAdapterOptions(
# powerPreference=HighPerformance, backendType=backend_types.get(getenv(...), 0))).
# One of the six, so the trace entry is a wait and not a create. `powerPreference`
# is HighPerformance at every call site (:169 is the only one), so it is a
# constant here and not a field.
def dev.request_adapter(d: Dev, backend_name: String) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, Tr.here(t), 0, 0, Nil{}, backend_of(backend_name), 0, "",
          Tr.emit(CALL_WAIT, SYNC_REQUEST_ADAPTER, t)}

# :173-174 `[feat for i in range(supported_features.featureCount)
# if (feat:=supported_features.features[i]) in [WGPUFeatureName_TimestampQuery,
# WGPUFeatureName_ShaderF16]]`. The comprehension iterates the adapter's list, so
# the order is the adapter's and not the order of the two-element probe list.
# That is invisible for a wgpu adapter (its feature list is ascending, and
# TimestampQuery=3 sorts before ShaderF16=8) and visible for any other list, so
# the gate pins it both ways: `wg_feat_order_reverse` is the row that fails if
# the port sorts by the probe list instead.
def keeps_feature(+f: U32) -> Bool:
  Bool.or(U32.is_eq(f, FEATURE_TIMESTAMP_QUERY()), U32.is_eq(f, FEATURE_SHADER_F16()))

# the comprehension is its own fold and not `List.filter`, because a closure's
# type cannot spell `+` and `keeps_feature` needs `f` twice.
def features_keep.put(+x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, keeps_feature(x), List.append(&2, U32, acc, [x]), acc)

# `features_keep.put` appends, so the base cases hand `acc` straight back: the
# filter preserves the adapter's order, and a `List.reverse` here reversed it for
# every list of two or more. measured: `wg_feat_order_forward` was the row that
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
# filter runs between them, in the list's own order.
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
# c.pointer(WGPURequiredLimits(limits=supported_limits.limits))`. The values are
# the adapter's and there is no v1 spelling for a limits table; what is portable
# is that the adapter is asked before the device is requested, which is what
# `wg_init_limits_before_device` reads.
def dev.get_limits(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch,
          Tr.emit(CALL_GET_LIMITS, 0, t)}

# :176-177 `requiredFeatureCount=len(self.features)`, and :190
# `arch="shader-f16" * (WGPUFeatureName_ShaderF16 in self.features)`. Python
# string-multiplies: "" or "shader-f16", never anything else. Both are functions
# of the filtered list and nothing else.
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

# :185 `self.queue = webgpu.wgpuDeviceGetQueue(self.device_res)`. Its own def,
# because that is what gives the queue an id of its own: `Tr.here` is read before
# the wait's emit and the wait's emit consumes it.
def dev.get_queue(d: Dev) -> Dev:
  match d:
    case Dev{instance, adapter, device_res, queue, features, backend, nrequired, arch, +t}:
      Dev{instance, adapter, device_res, Tr.here(t), features, backend, nrequired, arch,
          Tr.emit(CALL_CREATE, OBJ_QUEUE, t)}

# :187 `webgpu.wgpuAdapterRelease(adapter_res)` -- last, after the device and the
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
# :195-198 -- unmap only if the map state is Mapped, then destroy, then release.
# All three in that order, always. Two defs because a `match` scrutinee must be a
# parameter: the state arrives as a U32 and the comparison is a leaf.
def dev.free.at(mapped: Bool, +id: U32, +t: Tr) -> Tr:
  match mapped:
    case True{}: Tr.emit(CALL_RELEASE, id, Tr.emit(CALL_DESTROY, id, Tr.emit(CALL_UNMAP, id, t)))
    case False{}: Tr.emit(CALL_RELEASE, id, Tr.emit(CALL_DESTROY, id, t))

def dev.free(map_state: U32, id: U32, t: Tr) -> Tr:
  dev.free.at(U32.is_eq(map_state, MAP_MAPPED()), id, t)

# ops_webgpu.py:201-205 -- `create_uniform`. one 4-byte Uniform|CopyDst buffer,
# then a 4-byte little-endian write into it.

def dev.uniform_usage() -> U32: U32.or(USAGE_UNIFORM(), USAGE_COPY_DST())

# `val.to_bytes(4, "little", signed=val < 0)` for an int: two's complement, low
# byte first. That is the whole int arm and it is portable. The FLOAT arm needs
# an f32 bit pattern, which is wall 3.
# `U32.shrn(v, 1n)` shifts by one bit, not by one byte. `shrn` composes the
# one-bit `U32.shr` n times, so the amount must be the bit count -- 8 -- and not a
# byte count. `U32.shr` is also the one-bit shift, so `shrn(v, 8n)` is the byte
# shift and has no shorter name.
#
# measured, AND no row in this file could see it. With `1n` the value was divided by
# two per byte, so 7 came out `7,3,1,0` instead of CPython's `7,0,0,0` -- but the
# three byte rows were 0, 1 and 0xFFFFFFFF, and a one-bit shift gets all three right
# (0 shifts to 0, 1 to 0 after one step, 0xFFFFFFFF has no zero byte). The fourth
# byte of 7 is the first value that separates them, and it took a fixture from the
# ffi seam in `runtime/webgpu_call.bend` to supply it: that file's
# `wgc_wall3_int_bytes` row is about a `vals` entry of 7 and was `False` against a
# correct expectation. The four rows below are the fixtures that close it.
def dev.uniform_bytes.go(n: Nat, +v: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+m: dev.uniform_bytes.go(m, U32.shrn(v, 8n), U32.and(v, 255) <> acc)

def dev.uniform_bytes(v: U32) -> List<&2, U32>: dev.uniform_bytes.go(4n, v, Nil{})

def Buf.size(b: Buf) -> U32:
  match b:
    case Buf{id, size}: size

# the other field, and the one the ffi seam needs: `runtime/webgpu_call.bend`'s
# `Cs.entry` binds the caller's own buffer for a `bufs` slot (:96's `x if
# isinstance(x, WGPUBuffer) else self.dev.create_uniform(x)`), which is this id.
# `wgc_bg_handles` there is the row that reads it back. It was added with the seam
# and is the only reader this file has of it.
def Buf.id(b: Buf) -> U32:
  match b:
    case Buf{id, size}: id

def Made.buf(m: Made) -> Buf:
  match m:
    case Made{buf, t}: buf

def Made.tr(m: Made) -> Tr:
  match m:
    case Made{buf, t}: t

# ops_webgpu.py:220-221 -- `wgpuQueueWriteBuffer(self.queue, buf, 0, <bytes>,
# len(src))`. The length is `len` of the argument, so for `_copyin` it is the
# padded length. That is why `bytes` is a parameter here and not a `U32`: the
# length is derived from the bytes rather than passed beside them.

def copy.write(bytes: List<&2, U32>, t: Tr) -> Tr:
  Tr.emit(CALL_WRITE, U32.from_nat(List.length(&2, U32, bytes)), t)

# ops_webgpu.py:150-163 -- the allocator.

# :152-153 Storage|CopyDst|CopySrc. The three bits together say: a storage buffer
# the host can upload into and read back out of.
def alloc.usage() -> U32: U32.or(U32.or(USAGE_STORAGE(), USAGE_COPY_DST()), USAGE_COPY_SRC())

# :152 `size=round_up(size, 4)`, under the comment "WebGPU buffers have to be
# 4-byte aligned". That is the whole of the allocator's alignment rule, and
# `round_up` is helpers.py:247 `ceildiv(x, y) * y`.
def alloc.size(nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

# :163 `self.dev.free(storage.buf)`
# :154-158 -- pad to a multiple of 4 with zeros when the length is not already
# one, then write. What falls out of that, and what the gate pins: `write_buffer`
# receives the padded length always, because when nbytes % 4 == 0
# round_up(nbytes, 4) == nbytes. So a 5-byte upload reaches the device as 8 bytes
# with 3 of them zero, and `wg_copyin_writes_padded` is the row that dies if the
# port writes the unpadded length.
def copy.write_len(nbytes: U32) -> U32: H.round_up_u32(nbytes, 4)

# :206-219 -- the staging buffer every host read goes through. Create with
# CopyDst|MapRead at the same size, copy the whole buffer into it, submit, then
# release the command buffer and the encoder in that order -- the reverse of
# creation. Note the contrast with `pass.release`, which releases in creation
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

# :17-19 `buf_to_mv` -- map async (one of the six synchronous calls), then take
# the const mapped range over the whole buffer. No error scope, and no size
# argument: the range is (0, wgpuBufferGetSize(buf)), which is why the size rides
# on the range call and not on the map.
def copy.read(usage: U32, +size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MAPPED_RANGE, size,
    Tr.emit(CALL_MAP_ASYNC, usage, Tr.emit(CALL_WAIT, SYNC_MAP_ASYNC, t)))

# :159-161 -- `dest[:] = buf_to_mv(tmp_buf:=self.dev._readable_buffer(src))[:nbytes]`
# then `self.dev.free(tmp_buf)`. So one create, one map and one free per copy-out,
# and the free is of the staging buffer, not of the source.
# the read is of the staging buffer and the free is of the same buffer, so the
# `Made` travels through both rather than being taken apart and put back.
def copy.read_made(usage: U32, size: U32, +m: Made) -> Made:
  Made{Made.buf(m), copy.read(usage, size, Made.tr(m))}

# ops_webgpu.py:52-67 -- WebGPUProgram.__init__ / __del__, and the four `wait`
# arms of :112, :126 and :140 that the call steps read off `Pass.wait`.

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

# an empty trace that keeps `bad_at` and `popn`, so a gate can read one program
# call without the init in front of it and still number its pops from one.
def Pass.reset(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, Tr.reset(t)}

# :71 `wait = wait and webgpu.WGPUFeatureName_TimestampQuery in self.dev.features`.
# The first line of __call__, and the only thing that decides whether a query set
# exists at all (:112). a `wait=True` on a device without the feature is not an
# error: it silently measures nothing and returns None, which is what
# `wg_wait_no_ts_query` pins.
def prog.wants_wait(want: Bool, feats: List<&2, U32>) -> Bool:
  Bool.and(want, List.contains(~U32, ~U32.is_eq, feats, FEATURE_TIMESTAMP_QUERY()))

# :53-64 -- `self.dev, self.name = dev, to_wgpu_str(obj.name)`, then the wgsl
# descriptor (:57-59, a chained struct whose sType is WGPUSType_ShaderSourceWGSL,
# so the shader language is named by the chain and not by the descriptor type),
# then PushErrorScope(Validation) (:62), CreateShaderModule (:63) and
# `if err := self.dev.pop_error(): raise` (:64).
def prog.init(entry: String, d: Dev) -> Pass:
  match d:
    case Dev{instance, adapter, device_res, queue, +features, backend, nrequired, arch, +t}:
      Pass{Tr.here(t), entry, features, 0, 0, Nil{}, 1, 1, 1, False{},
           Tr.pop(Tr.emit(CALL_CREATE, OBJ_SHADER_MODULE, Tr.push(t)))}

# ops_webgpu.py:74-78 -- the layout derivation. See the layout derivation in the
# header: binding 0 Uniform, bindings 1..len(bufs) Storage, the rest Uniform, and
# `visibility` WGPUShaderStage_Compute at every entry, which is why it is not a
# field of Bgl.

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

# the gate needs the pairs, not the records: (binding, type) per entry, in order.
# `List.append` is in order and this fold does not reverse at the end, which is
# the other half of the o(n^2) trade -- see slots.vals.
def bgl.flat(xs: List<&2, Bgl>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case Bgl{b, ty} <> t: bgl.flat(t, List.append(&2, U32, List.append(&2, U32, acc, [b]), [ty]))

# :94-97 -- the bind group has the same count and the same split as the layout:
# infinity first (which is a uniform the call creates, not a constant), then the
# bufs, then the vals.
# both folds append and neither reverses. That is o(n^2) for a list of at most a
# few hundred entries, and it buys the thing that matters: the binding order is
# the list order. Consing here and reversing once at the end puts the bufs in
# reverse order while leaving the group order right, which the gate caught as
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

# ops_webgpu.py:69-147 -- one program call, as the step list it is. Every step is
# one line range of the Python and takes the `Pass` it is handed, so the order is
# the whole of `prog.call` and nothing else.
#
# the `raise` is in the trace (see the raise): once a pop has reported an error
# no later step records anything, so these steps need no guard of their own and a
# refusal shows up as a truncated trace -- which is exactly what the four
# `wg_refuse_*` rows read.

# :71, and the dispatch geometry :123 reads. `local_size` is recorded and never
# dispatched on: ops_webgpu.py never reads it (see wgsl.bend owes, item 3).
# the parameter is `local`, not `ls`: a pattern binder of the same name shadows it
# and the Pass then keeps the 0 it was born with. measured: `wg_call_ls_recorded`
# printed 0 until this was renamed.
def pass.geometry(p: Pass, gx: U32, gy: U32, gz: U32, local: U32, want: Bool) -> Pass:
  match p:
    case Pass{module, entry, +feats, ls, nentries, sizes, g0, h0, i0, wait, +t2}:
      Pass{module, entry, feats, local, nentries, sizes, gx, gy, gz,
           prog.wants_wait(want, feats), t2}

# :80-84 -- PushErrorScope(Validation), CreateBindGroupLayout(device,
# WGPUBindGroupLayoutDescriptor(entryCount=len(bind_entries), entries=...)),
# pop_error. The port stores `nentries`, which is the descriptor's field the gate
# reads, and `bgl.of` is the entries it counts -- so the derivation is live here
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
# self.dev.create_uniform(x)`, once per bind group entry. a uniform slot creates a
# 4-byte buffer and the entry takes its size; a buffer slot takes the caller's.
# The fold runs before the bind group is created, which is what puts the uniform
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
# entryPoint=self.name))). not an error scope: this one is a future, so its status
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
# timestamp writes ride on the descriptor, so they are invisible to the trace --
# what the trace sees is the two creates, and that they do not happen at all when
# `wait` is False is what `wg_wait_query_created` and `wg_wait_no_ts_creates` read.
def pass.query.on(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_CREATE, OBJ_BUFFER, Tr.emit(CALL_CREATE, OBJ_QUERY_SET, t))}

# a `match` may not scrutinise a call, so `if wait:` is a `.at` whose Bool is a
# parameter. Three `if wait:` arms, three `.at`s -- and no shared helper, because
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

# :123 -- DispatchWorkgroups(compute_pass, *global_size). The x extent rides on
# the trace entry so that the gate can read the dispatch geometry; y and z are in
# the Pass beside it. not the local size -- see pass.geometry.
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
# It happens after the pass has ended and before the encoder is finished, which is
# the position `wg_wait_resolve_order` pins.
def pass.resolve.on(p: Pass) -> Pass:
  match p:
    case Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait, +t}:
      Pass{module, entry, feats, ls, nentries, sizes, gx, gy, gz, wait,
           Tr.emit(CALL_RESOLVE, QUERY_COUNT(), t)}

# a `match` may not scrutinise a call, so `if wait:` is a `.at` whose Bool is a
# parameter. Three `if wait:` arms, three `.at`s -- and no shared helper, because
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

# :132-138 -- the seven releases, and the order is creation order, not the
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

# :140-145 -- `if wait:` the staging read of the two timestamps, then both frees,
# then QuerySetDestroy and QuerySetRelease. The delta itself is wall 2.
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

# a `match` may not scrutinise a call, so `if wait:` is a `.at` whose Bool is a
# parameter. Three `if wait:` arms, three `.at`s -- and no shared helper, because
# the three differ in what they skip and a shared one would need a tag.
def pass.timing.at(wait: Bool, p: Pass) -> Pass:
  match wait:
    case False{}: p
    case True{}: pass.timing.on(p)

def pass.timing(+p: Pass) -> Pass: pass.timing.at(Pass.wait(p), p)

# ops_webgpu.py:69-70 -- `def __call__(self, *bufs, global_size=(1,1,1),
# local_size=(1,1,1), vals=(), wait=False) -> float|None`. The step order below is
# the order of the Python, and it is the only thing this def knows.

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

# the gate. Every row is a claim about `ops_webgpu.py`'s text or about a constant
# read out of `autogen/webgpu.py`, and the row name says which Python line it is
# about. Numeric rows print the value, so a wrong one is diagnosable from the
# output alone.
#
# fixtures. One device per feature set, one program on it, one call with three
# 64-byte global buffers and one val -- the shape of a 2-input 1-output float
# kernel, which is exactly the fixture `WGSLRenderer.render_kernel` was measured
# with. `fx_call` resets the trace so the init is not in front of it, and
# `fx_life` keeps it so the error-scope count covers a whole program lifetime.

def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
