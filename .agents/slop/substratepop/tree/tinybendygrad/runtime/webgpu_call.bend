# tinybendygrad/runtime/webgpu_call.bend -- THE CALL LAYER for ops_webgpu.bend.
#
# `ops_webgpu.bend` ports the STRUCTURE of the browser target and records every
# wgpu call in a trace. Its own header says every actual wgpu call is a
# `# TODO(p3) runtime/ops_webgpu.py:<line>` naming the JS import it becomes, and
# that "nothing here calls wgpu". THIS FILE IS THAT MISSING HALF: the FFI seam
# that header names and `ops_webgpu.bend` does not have.
#
# It is also what that file's own "WHAT THIS GATE STILL DOES NOT SEE" list asks
# for, in its own words:
#
#   "nothing checks that the RIGHT [usage bitmask] is passed to the RIGHT call"
#   "NOTHING checks that pass.pipeline's entryPoint is the entry point Pass.of
#    was given: THE ONLY READER WOULD BE THE FFI SEAM"
#
# ===========================================================================
# THE BOUNDARY, and why it is THIS one. Measured, not chosen by taste.
#
# `bend FILE -o FILE.mjs` emits an ES module of every NON-IO def, with
# constructors as `{$: "Name", field: value}` and `Nat` as `BigInt`. Verified by
# running it on `ops_webgpu.bend` itself: 490 exports, including `prog.call`,
# `dev.init`, `bgl.of` and `Tr.calls`, and EXCLUDING every `do IO<>` block
# (`main`, `t_call`, ... are all absent). So
#
#   bend tinybendygrad/runtime/webgpu_call.bend -o tinybendygrad/runtime/webgpu_call.mjs
#
# hands JavaScript the whole pure half and `tinybendygrad/runtime/webgpu_call.js`
# drives `navigator.gpu` from it: a GENERATED JS MODULE THE PORT'S OWN DEFS NAME,
# with the port's defs still pure and gated.
#
# The two rejected seams, and the measurement that rejects each:
#
#   - an FFI effect, `def e(..) -> IO(..): import "./e.c"; import "./e.js"`, the
#     `dtype.bend` shape. It would make `Tr.emit` answer `IO(Tr)`, so `dev.init`,
#     `prog.call` and every step def become IO-returning and THE PURE GATE THE
#     147 ROWS DEPEND ON STOPS EXISTING. It also has nowhere to put a Promise:
#     `bend guide effects` gives the JS effect side `need` and `io_park_on` on an
#     fd, and WebGPU's six `synchronous`-wrapped calls are Promises with no
#     documented park arm.
#   - "a generated JS module the TRACE names and Bend calls into" is backwards.
#     `Call` is `{k, arg}` with NO argument payload BY DESIGN -- ops_webgpu.bend
#     says so at its own `type Call` -- so a trace cannot name a descriptor.
#     Widening `Call` changes ~40 gate rows, and the trace was never the thing
#     that was missing.
#
# ===========================================================================
# WHAT IS AND IS NOT DUPLICATED. No argument is re-derived here: `bgl.of`,
# `slots`, `dev.uniform_bytes`, `alloc.size`, `copy.write_len`, `alloc.usage`,
# `dev.uniform_usage`, `copy.readable_usage`, `prog.wants_wait`, `backend_of` and
# `Tr.*` are CALLED, never reimplemented. What is written here is the step ORDER
# and which descriptor belongs to which call -- the thing the trace cannot carry.
#
# AND THAT ORDER IS PINNED, NOT ASSERTED. Every `Step` carries the trace entry
# `W.Call` it must correspond to, and `wgc_call_trace` checks the two lists
# against each other with `W.Tr.has` AT EQUAL LENGTH, which is an equality test.
# A missing step, an extra step, or a wrong tag in THIS file moves that row, and
# `wgc_call_len` is the length half of it.
#
# ONE PLACE THE TRACE IS COARSER THAN PYTHON, and it is load-bearing.
# ops_webgpu.py:95 `bg_entry` calls `dev.create_uniform(x)` (:202-205), which
# CREATES a 4-byte buffer AND writes the value into it -- two calls. The committed
# trace records ONE `CALL_CREATE OBJ_BUFFER` per uniform slot, because
# `pass.uniforms.put` emits only the create. So the write has no trace entry of
# its own and this file cannot match the trace by emitting one. `Op` therefore has
# `Uniform` -- :202-205 AS ONE UNIT, create-and-initialise -- and
# `wgc_uniform_one_step` is the row that pins the collapse. THE TRACE IS NOT
# CHANGED: those 147 rows are not mine to move.
#
# The three walls of `ops_webgpu.bend` land here as follows. WALL 2's
# `2**64-1` wait timeout (:37) is GONE, because `navigator.gpu` awaits and has
# no wait to time out; `wgc_callback_mode_gone` pins the 1 it replaced. WALL 2's
# u64 timestamp delta (:141) is the driver's, in JS doubles. WALL 3's
# `struct.pack('<f', inf)` (:204) is SOLVED here rather than deferred:
# `Uniform.is_f32` says "the driver builds this pattern in a Float32Array", and
# `wgc_infinity_is_f32` pins that the one value Bend cannot build is the one value
# the driver builds.

import Base
import ./ops_webgpu.bend as W
import ../helpers.bend as H

# ===========================================================================
# THE CONSTANTS ADDED HERE. All six are new to the port. Every one was READ out
# of `tinygrad/runtime/autogen/webgpu.py` by importing that module; the
# `file:line` is where the symbol is bound. The oracle is
# `.agents/slop/webgpu_call_oracle.py`, its captured output is
# `.agents/slop/webgpu_call_oracle_out.txt`, and NOTHING HERE IS TYPED BY HAND.
#
#   SHADER_STAGE_COMPUTE        4  autogen/webgpu.py:2601  WGPUShaderStage_Compute
#   QUERY_TYPE_TIMESTAMP        2  autogen/webgpu.py:1213  WGPUQueryType_Timestamp
#   MAP_MODE_READ               1  autogen/webgpu.py:2596  WGPUMapMode_Read
#   POWER_PREF_HIGH_PERF        2  autogen/webgpu.py:268   WGPUPowerPreference_HighPerformance
#   STYPE_SHADER_SOURCE_WGSL    2  autogen/webgpu.py:80    WGPUSType_ShaderSourceWGSL
#   CALLBACK_MODE_WAIT_ANY_ONLY 1  autogen/webgpu.py:154   WGPUCallbackMode_WaitAnyOnly
#
# `CALLBACK_MODE_WAIT_ANY_ONLY` is the flag that lets `synchronous` (:37) block;
# all six wrapped calls pass it, and NO `Op` mentions it, because there is
# nothing on the JavaScript side to pass it to.
# ===========================================================================
def SHADER_STAGE_COMPUTE() -> U32: 4
def QUERY_TYPE_TIMESTAMP() -> U32: 2
def MAP_MODE_READ() -> U32: 1
def POWER_PREF_HIGH_PERF() -> U32: 2
def STYPE_SHADER_SOURCE_WGSL() -> U32: 2
def CALLBACK_MODE_WAIT_ANY_ONLY() -> U32: 1

# ===========================================================================
# THE LITERALS ops_webgpu.py writes into descriptors. Not enums, so the citation
# is the `ops_webgpu.py` line the literal is written on and `wgc_lit_*` checks
# each against that number. `QUERY_COUNT` is deliberately NOT reused from
# `ops_webgpu.bend`: that one is the trace's own tag and this one is the
# descriptor's, so `wgc_lit_resolve_agrees` is the row that keeps the two equal.
#
#   QUERY_BUF_BYTES 16  ops_webgpu.py:115  WGPUBufferDescriptor(size=16, usage=...)
#   QUERY_COUNT     2  ops_webgpu.py:114  WGPUQuerySetDescriptor(count=2)
#   BEGIN_PASS      0  ops_webgpu.py:116  beginningOfPassWriteIndex=0
#   END_PASS        1  ops_webgpu.py:117  endOfPassWriteIndex=1
#   SUBMIT_COUNT    1  ops_webgpu.py:129  wgpuQueueSubmit(queue, 1, [cmd_buf])
#   RESOLVE_COUNT   2  ops_webgpu.py:126  ResolveQuerySet(enc, qs, 0, 2, qbuf, 0)
#
# The zero offsets -- the bind group's `offset=0` (:96), the queue write's `0`
# (:221), the resolve's source `0` and destination `0` (:126), the map's `0`
# (:18) and the buffer-to-buffer copy's two `0`s (:215) -- are literal `0` at
# their use sites, each naming its Python line, because a named `ZERO()` would be
# a constant no citation could check.
# ===========================================================================
def QUERY_BUF_BYTES() -> U32: 16
def QUERY_COUNT() -> U32: 2
def BEGIN_PASS() -> U32: 0
def END_PASS() -> U32: 1
def SUBMIT_COUNT() -> U32: 1
def RESOLVE_COUNT() -> U32: 2

# ===========================================================================
# THE OPS. One constructor per real `navigator.gpu` method, named for it. `slot`
# is the handle the driver files the RESULT under, so every later reference to a
# created object is a `U32` the driver resolves. The object KIND is not a field:
# the trace already carries it as `Call.arg`, so `Step.arg` and `Op` together say
# it once and `wgc_kind_from_arg` checks the pairing.
# ===========================================================================

# ONE bind group entry (:96) -- `(binding, buffer, offset=0, size)`. `buf` is the
# uniform THIS call creates for a `vals` slot and the caller's own for a `bufs`
# slot, which is :96's `buf = x if isinstance(x, WGPUBuffer) else
# self.dev.create_uniform(x)`; `wgc_bg_sizes` reads all three kinds off one
# fixture.
type Bind is Data:
  Bind{n: U32, buf: U32, size: U32}

# :116-117 comp_pass_desc.timestampWrites = {querySet,
  # beginningOfPassWriteIndex=0, endOfPassWriteIndex=1}. It RIDES ON THE PASS
  # DESCRIPTOR, so it is no call of its own: `wg_call_order` cannot see it and
  # neither can the trace. It is carried INSIDE `BeginPass` for exactly that
  # reason, and `wgc_timestamp_on_pass` is the row that says so.
type TimestampWrites is Data:
  TimestampWrites{qs: U32, first: U32, last: U32}

type Op is Data:
  # :11 wgpuCreateInstance(WGPUInstanceDescriptor(features=
  # WGPUInstanceFeatures(timedWaitAnyEnable=True))). No JS call -- `navigator.gpu`
  # IS the instance -- so this op exists to keep the trace entry accounted for.
  # It carries the flag it made necessary: a browser has nothing to time out, so
  # the value rides along and the driver drops it.
  Instance{timed_wait: U32}
  # :169 InstanceRequestAdapter(instance, WGPURequestAdapterOptions(powerPreference
  # =HighPerformance, backendType=backend_types.get(getenv(...), 0)))
  RequestAdapter{+power: U32, +backend: U32}
  # :172 wgpuAdapterGetFeatures(adapter_res, supported_features)
  ReadFeatures{}
  # :175 wgpuSupportedFeaturesFreeMembers(supported_features)
  FreeFeatures{}
  # :180 wgpuAdapterGetLimits(adapter_res, supported_limits)
  ReadLimits{}
  # :184 AdapterRequestDevice(adapter_res, dev_desc{requiredFeatures, requiredLimits})
  RequestDevice{+feats: List<&2, U32>}
  # :185 wgpuDeviceGetQueue(self.device_res)
  GetQueue{slot: U32}
  # :187 wgpuAdapterRelease(adapter_res)
  ReleaseAdapter{+id: U32}
  # :62, :80, :88, :101 wgpuDevicePushErrorScope(device_res, Validation)
  PushScope{+filter: U32}
  # :64, :84, :91, :102 DevicePopErrorScope(device_res)[1]
  PopScope{}
  # :63 wgpuDeviceCreateShaderModule(device_res, {code, nextInChain: WGSL})
  ShaderModule{+code: String, slot: U32}
  # :82 wgpuDeviceCreateBindGroupLayout(device_res, {entryCount, entries}). The
  # entries' `visibility` is WGPUShaderStage_Compute at EVERY entry (:75), so it
  # is one field here rather than one per entry, and `wgc_layout_visibility` pins
  # it against :75.
  BindGroupLayout{+entries: List<&2, W.Bgl>, visibility: U32, slot: U32}
  # :88 wgpuDeviceCreatePipelineLayout(device_res, {bindGroupLayoutCount=1,
  # bindGroupLayouts=[bind_layout]})
  PipelineLayout{+id: U32, slot: U32}
  # :202-205 `dev.create_uniform(val)`: ONE 4-byte UNIFORM|COPY_DST buffer AND the
  # 4-byte write into it, as ONE op, because the trace records only the create
  # (see the header). `is_f32` is WALL 3 -- false means `val` is an int and the
  # little-endian bytes are `W.dev.uniform_bytes(val)`, true means it is the
  # `float('inf')` of :97 and the driver builds an f32 pattern.
  Uniform{+slot: U32, +bytes: List<&2, U32>, is_f32: Bool}
  # :152 / :115 / :208 wgpuDeviceCreateBuffer(device_res, {size, usage}). THREE
  # different (size, usage) pairs reach this one constructor -- a storage buffer,
  # the query buffer and a readable staging buffer -- and `wgc_buffer_usage` is a
  # row about a LIST of three masks, not about one.
  CreateBuffer{+slot: U32, size: U32, usage: U32}
  # :221 wgpuQueueWriteBuffer(queue, buf, 0, <bytes>, len(src)) -- the OFFSET is
  # the literal 0 of :221 and `bytes`' LENGTH is `len(src)` of the same line, so
  # the driver writes `bytes.length` bytes and needs nothing else.
  WriteBuffer{+buf: U32, +bytes: List<&2, U32>}
  # :99 wgpuDeviceCreateBindGroup(device_res, {layout, entryCount, entries}); the
  # entries' offset is the literal 0 of :96 and lives in the driver.
  BindGroup{+layout: U32, +entries: List<&2, Bind>, slot: U32}
  # :106 DeviceCreateComputePipeline(device_res, {layout, compute:{module,
  # entryPoint}}). NOT an error scope: this one is a FUTURE (:105-107), which is
  # why `wg_call_scopes` is 3 and not 4 -- and in JS it is an ordinary await.
  ComputePipeline{+layout: U32, +module: U32, +entry: String, slot: U32}
  # :109 wgpuDeviceCreateCommandEncoder(device_res, {})
  CreateEncoder{+slot: U32}
  # :120 wgpuCommandEncoderBeginComputePass(command_encoder, comp_pass_desc). The
  # timestamp writes ride on the pass descriptor, so `ts` is where they live.
  BeginPass{+enc: U32, ts: Maybe<&2, TimestampWrites>}
  # :114 wgpuDeviceCreateQuerySet(device_res, {type=Timestamp, count=2})
  CreateQuerySet{+slot: U32, ty: U32, count: U32}
    # :121 wgpuComputePassEncoderSetPipeline(compute_pass, pipeline_result)
  SetPipeline{+pipeline: U32}
  # :122 wgpuComputePassEncoderSetBindGroup(compute_pass, 0, bind_group, 0, None)
  SetBindGroup{+group: U32, +bg: U32}
  # :123 wgpuComputePassEncoderDispatchWorkgroups(compute_pass, *global_size)
  Dispatch{+gx: U32, +gy: U32, +gz: U32}
  # :124 wgpuComputePassEncoderEnd(compute_pass)
  EndPass{}
  # :126 wgpuCommandEncoderResolveQuerySet(encoder, query_set, 0, 2, query_buf,
  # 0) -- source offset 0, destination offset 0.
  ResolveQuerySet{+enc: U32, +qs: U32, +dst: U32, count: U32}
  # :128 wgpuCommandEncoderFinish(command_encoder, {})
  Finish{+enc: U32, +slot: U32}
  # :129 wgpuQueueSubmit(queue, 1, [cmd_buf])
  Submit{+slot: U32}
  # :132-138 the seven releases, :187 the adapter's, :196-198 the buffers'.
  # `kind` is the `W.OBJ_*` the trace carries as `Call.arg`, because :132-138 is
  # seven releases whose ORDER is the whole of that block and `wg_call_released`
  # checks it there. `id` is the REAL handle, which the trace does not carry.
  Release{+id: U32, kind: U32}
  # :215 wgpuCommandEncoderCopyBufferToBuffer(encoder, buf, 0, ret, 0, size)
  CopyBuffer{+enc: U32, +src: U32, +dst: U32, size: U32}
  # :18 BufferMapAsync(buf, WGPUMapMode_Read, 0, size) -- offset the literal 0
  MapAsync{+buf: U32, mode: U32, size: U32}
  # :19 wgpuBufferGetConstMappedRange(buf, 0, size) -- offset the literal 0
  MappedRange{+buf: U32, size: U32}
  # :144 wgpuQuerySetDestroy(query_set)
  DestroyQuerySet{+qs: U32}
  # :197 wgpuBufferDestroy(buf)
  DestroyBuffer{+buf: U32}

# ONE real call: the trace entry it MUST correspond to, and the argument-carrying
# operation the driver performs. `Cs.calls` projects the (k, arg) half and
# `wgc_call_trace` compares it to `W.Tr.calls` at equal length.
type Step is Data:
  Step{k: U32, arg: U32, op: Op}

# what one phase builds: the ordered steps, the handle counter, the `if wait:`
# flag ops_webgpu.py carries in `self.wait`, and the bind group the driver sets.
# FOUR fields, because `next`, `wait` and `bg` are the only three things a step
# cannot recompute from its own arguments.
type Cs is Data:
  Cs{ops: List<&2, Step>, next: U32, wait: Bool, bg: List<&2, Bind>}

def Cs.of() -> Cs: Cs{Nil{}, 0, False{}, Nil{}}

def Cs.ops(c: Cs) -> List<&2, Step>:
  match c:
    case Cs{ops, next, wait, bg}: ops

def Cs.next(c: Cs) -> U32:
  match c:
    case Cs{ops, next, wait, bg}: next

# the handle `Cs.mint` just handed out: `Cs.next` is the NEXT slot, so the one in
# hand is one below it. One def, so no step can mint a handle and hand a
# DIFFERENT one to its op.
def Cs.last(c: Cs) -> U32: U32.sub(Cs.next(c), 1)

def Cs.wait(c: Cs) -> Bool:
  match c:
    case Cs{ops, next, wait, bg}: wait

def Cs.bg(c: Cs) -> List<&2, Bind>:
  match c:
    case Cs{ops, next, wait, bg}: bg

# THE ONE APPENDER. Steps are consed and `Cs.order` reverses once, so the step
# order IS the list order -- the same trade `bgl.flat` makes in `ops_webgpu.bend`,
# and for the same reason.
#
# **`Cs.mint` RETURNS A STATE AND THE REST OF THE STEP MUST BE BUILT FROM THAT
# ONE.** Binding the mint to a name and then writing `Cs.at(Cs.push(c), ...)` --
# threading the ORIGINAL `c` -- throws the mint away: the handle reads back
# correctly and the counter never advances.
#
# MEASURED, and it WAS INVISIBLE TO EVERY ROW ABOVE. Every handle came out
# 4294967295, which is `Cs.next(0) - 1`, so all three layouts and the pipeline
# were built against the same unbound slot and the whole gate stayed green:
# `Cs.calls` and `Cs.bg` do not read `next` at all, so a counter frozen at zero
# changes neither the trace nor the bind group. It surfaced only in the BROWSER,
# at `PipelineLayout`, with "unbound slot 4294967295" at step 15 of 57.
# `wgc_handles_distinct` is the row that would have caught it.
# THE HANDLE IN HAND: `Cs.next` is the NEXT slot to mint, so the one just minted
# is one below it, and `Cs.last` already says so for a `Cs`. This is the same
# subtraction on a bare counter, for the places that read a handle off a counter
# they did not just mint.
def Cs.hand(n: U32) -> U32: U32.sub(n, 1)

# THE BIND GROUP, as the two LISTS the gate reads: the sizes and the handles, in
# binding order. `Pass.sizes` answers the first on the trace side and these answer
# it on the seam side, which is what makes `wgc_bg_sizes` a comparison rather than
# a restatement. The handle list is the thing NO reader had: `Pass` records the
# size of each entry and not which buffer it is.
def Cs.bg_sizes.go(n: Nat, bs: List<&2, Bind>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case Bind{bn, buf, size} <> t:
          Cs.bg_sizes.go(m, t, List.append(&2, U32, acc, [size]))

def Cs.bg_sizes(+bs: List<&2, Bind>) -> List<&2, U32>:
  Cs.bg_sizes.go(List.length(&2, Bind, bs), bs, Nil{})

def Cs.bg_ids.go(n: Nat, bs: List<&2, Bind>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case Bind{bn, buf, size} <> t:
          Cs.bg_ids.go(m, t, List.append(&2, U32, acc, [bn]))

def Cs.bg_ids(+bs: List<&2, Bind>) -> List<&2, U32>:
  Cs.bg_ids.go(List.length(&2, Bind, bs), bs, Nil{})

def Cs.bg_bufs.go(n: Nat, bs: List<&2, Bind>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match bs:
        case Nil{}: acc
        case Bind{bn, buf, size} <> t: Cs.bg_bufs.go(m, t, List.append(&2, U32, acc, [buf]))

def Cs.bg_bufs(+bs: List<&2, Bind>) -> List<&2, U32>:
  Cs.bg_bufs.go(List.length(&2, Bind, bs), bs, Nil{})

def Bind.n(b: Bind) -> U32:
  match b:
    case Bind{n, buf, size}: n

def Bind.size(b: Bind) -> U32:
  match b:
    case Bind{n, buf, size}: size

# THE FIRST BIND ENTRY, or a zero one when the bind group is empty. `List.get`
# answers a `Maybe`, and a `match` may not scrutinise a computed value -- so the
# `Maybe` gets its own def, exactly as `Cs.or0` does for a `U32`.
def Cs.of_maybe(m: Maybe<&2, Bind>) -> Bind:
  match m:
    case None{}: Bind{0, 0, 0}
    case Some{b}: b

def Cs.or0_one(+bs: List<&2, Bind>) -> Bind:
  Cs.of_maybe(List.get(&2, Bind, bs, 0n))

# ONE STEP IS ONE `Cs.at`. A step that is `push, create, pop` is therefore THREE
# `Cs.at` calls and NOT a `Cs.pop(Cs.at(Cs.at(Cs.push(..), ..), ..))` nest -- the
# `Cs.pop` wrapper emits a FOURTH pop. MEASURED twice: `wgc_call_trace` stayed
# True (the extra pops are a subsequence of nothing, so the matcher cannot see a
# duplicate) and the row that DID die was `wgc_call_len`, three steps out. `Cs.pop`
# exists for the one step whose pop is not already inside a `Cs.at`.
def Cs.at(+c: Cs, k: U32, arg: U32, op: Op) -> Cs:
  match c:
    case Cs{+ops, next, wait, bg}: Cs{Step{k, arg, op} <> ops, next, wait, bg}

def Cs.mint(+c: Cs) -> Cs:
  match c:
    case Cs{ops, next, wait, bg}: Cs{ops, U32.add(next, 1), wait, bg}

def Cs.wanted(+c: Cs, w: Bool) -> Cs:
  match c:
    case Cs{ops, next, wait, bg}: Cs{ops, next, w, bg}

def Cs.bound(+c: Cs, +b: List<&2, Bind>) -> Cs:
  match c:
    case Cs{ops, next, wait, bg}: Cs{ops, next, wait, b}

# THE ORDERED STEPS and the trace projection. `wgc_call_len` compares the first
# length and `wgc_call_trace` runs the second through `W.Tr.has`, which at equal
# lengths is an equality test -- so the pair is ONE check and not two halves each
# satisfiable alone.
#
# NEITHER FOLD REVERSES, and that is not an oversight. `Cs.at` conses onto the
# FRONT, so the list reads newest-first and the walk above starts at the NEWEST --
# which means `acc` already ends in STEP ORDER and a final `List.reverse` would
# undo it. MEASURED: with the reverse in, `wgc_call_trace=False` and
# `wgc_call_mine` printed the whole call backwards, from the last release to the
# shader module's push. The two orders are mirror images of one another, which is
# exactly the kind of bug a subsequence matcher cannot see -- `W.Tr.has` answered
# False and a length check alone would have passed.
def Cs.order.go(n: Nat, ss: List<&2, Step>, acc: List<&2, Step>) -> List<&2, Step>:
  match n:
    case 0n: acc
    case 1n+m:
      match ss:
        case Nil{}: acc
        case s <> t: Cs.order.go(m, t, s <> acc)

def Cs.order(+c: Cs) -> List<&2, Step>:
  Cs.order.go(List.length(&2, Step, Cs.ops(c)), Cs.ops(c), Nil{})

def Cs.calls.go(n: Nat, ss: List<&2, Step>, acc: List<&2, W.Call>) -> List<&2, W.Call>:
  match n:
    case 0n: acc
    case 1n+m:
      match ss:
        case Nil{}: acc
        case Step{k, a, op} <> t: Cs.calls.go(m, t, W.Call{k, a} <> acc)

def Cs.calls(+c: Cs) -> List<&2, W.Call>:
  Cs.calls.go(List.length(&2, Step, Cs.ops(c)), Cs.ops(c), Nil{})

def Cs.len(c: Cs) -> U32: U32.from_nat(List.length(&2, Step, Cs.ops(c)))

# THE IDENTITY, so a length comparison reads as one comparison. `Cs.of_calls` is
# a rename and not a computation, and it exists so the row above says `Cs.len`
# equals a trace length without either side being written out twice.
def Cs.of_calls(n: U32) -> U32: n

# how many of MY steps carry this trace tag. `W.Tr.count` counts entries in a
# `Tr`, and this file has no `Tr` -- it has a `Cs` -- so the count is over the
# projected `Call`s, which is the same question asked of the same list.
def Cs.count.go(n: Nat, +k: U32, ss: List<&2, Step>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ss:
        case Nil{}: got
        case Step{kk, aa, op} <> t:
          Cs.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

# how many of MY steps are a WAIT on this particular synchronous call. The six
# `synchronous`-wrapped calls are all `CALL_WAIT` in the trace, so this is the
# only way to say WHICH one -- and :105-107 is the only FUTURE among them that
# carries no error scope.
def Cs.count_of_wait.go(n: Nat, +which: U32, ss: List<&2, Step>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match ss:
        case Nil{}: got
        case Step{k, a, op} <> t:
          Cs.count_of_wait.go(m, which, t,
            U32.add(got, Bool.to_u32(Bool.and(U32.is_eq(k, W.CALL_WAIT()),
                                              U32.is_eq(a, which)))))

def Cs.count_of_wait(+c: Cs, which: U32) -> U32:
  Cs.count_of_wait.go(List.length(&2, Step, Cs.ops(c)), which, Cs.ops(c), 0)

def Cs.count(k: U32, +c: Cs) -> U32:
  Cs.count.go(List.length(&2, Step, Cs.ops(c)), k, Cs.ops(c), 0)

# ===========================================================================
# DEVICE INIT, ops_webgpu.py:11 then :166-190, in `dev.init`'s order. `dev.init`
# pins that order on the TRACE side (`wg_init_order`); `wgc_init_trace` pins that
# the ops here agree with it, so these eight steps and those eight trace entries
# cannot come apart.
# ===========================================================================
def Cs.instance() -> Cs: Cs.at(Cs.of(), W.CALL_CREATE, W.OBJ_INSTANCE,
                               Instance{CALLBACK_MODE_WAIT_ANY_ONLY()})

# :169 InstanceRequestAdapter(instance, WGPURequestAdapterOptions(powerPreference
# =HighPerformance, backendType=backend_types.get(getenv(...), 0)))
def Cs.adapter(+c: Cs, backend_name: String) -> Cs:
  Cs.at(c, W.CALL_WAIT, W.SYNC_REQUEST_ADAPTER,
        RequestAdapter{POWER_PREF_HIGH_PERF(), W.backend_of(backend_name)})

# :172 wgpuAdapterGetFeatures(adapter_res, supported_features)
def Cs.features(+c: Cs) -> Cs: Cs.at(c, W.CALL_GET_FEATURES, 0, ReadFeatures{})

# :175 wgpuSupportedFeaturesFreeMembers(supported_features)
def Cs.features_free(+c: Cs) -> Cs: Cs.at(c, W.CALL_FREE_FEATURES, 0, FreeFeatures{})

# :180 wgpuAdapterGetLimits(adapter_res, supported_limits)
def Cs.limits(+c: Cs) -> Cs: Cs.at(c, W.CALL_GET_LIMITS, 0, ReadLimits{})

# :184 AdapterRequestDevice(adapter_res, dev_desc) -> self.device_res.
def Cs.device(+c: Cs, +feats: List<&2, U32>) -> Cs:
  Cs.at(c, W.CALL_WAIT, W.SYNC_REQUEST_DEVICE, RequestDevice{feats})

# :185 wgpuDeviceGetQueue(self.device_res)
def Cs.queue(+c: Cs) -> Cs:
  match c:
    case Cs{ops, next, wait, bg}: Cs.at(Cs{ops, next, wait, bg}, W.CALL_CREATE, W.OBJ_QUEUE,
                                       GetQueue{next})

# :187 wgpuAdapterRelease(adapter_res) -- LAST, after the device and the queue.
def Cs.adapter_release(+c: Cs, id: U32) -> Cs:
  Cs.at(c, W.CALL_RELEASE, W.OBJ_ADAPTER, ReleaseAdapter{id})

# :11 then :166-190. `Cs.adapter` mints the adapter's handle and `Cs.queue` the
# queue's, and both are read OFF the counter rather than hard-wired, so
# `wgc_init_handles` is a claim about the minting and not about two numbers.
def Cs.init(backend_name: String, +feats: List<&2, U32>) -> Cs:
  a = Cs.adapter(Cs.instance(), backend_name)
  +d = Cs.device(Cs.limits(Cs.features_free(Cs.features(a))), feats)
  Cs.adapter_release(Cs.queue(d), Cs.next(d))

# ===========================================================================
# ONE PROGRAM CALL, ops_webgpu.py:53-64 then :69-147. Every step names its Python
# line, and `wgc_call_trace` checks the WHOLE order against the trace
# `W.prog.call` produces from the same inputs -- two independent walks of the
# same Python, compared by equality.
#
# `nvals` is the COUNT and `vals` the VALUES. `ops_webgpu.bend`'s `prog.call`
# takes only the count -- its header says the call "NEEDS THE BUFFER LIST AND THE
# VAL COUNT AND NOTHING ELSE" -- and that is true of the STRUCTURE. The seam needs
# the bytes, so `vals` is an argument here and `wgc_vals_count` is the row that
# pins the two against each other.
# ===========================================================================
def Cs.push(+c: Cs) -> Cs:
  Cs.at(c, W.CALL_PUSH, W.FILTER_VALIDATION, PushScope{W.FILTER_VALIDATION()})

def Cs.pop(+c: Cs) -> Cs: Cs.at(c, W.CALL_POP, W.FILTER_VALIDATION, PopScope{})

# :62-64 -- PushErrorScope(Validation), CreateShaderModule, pop_error. The scope
# is opened and closed around ONE call, which is why neither `Pass` nor `Cs` has
# an open-scope field.
def Cs.shader(+c: Cs, code: String) -> Cs:
  +m = Cs.mint(c)
  Cs.at(Cs.at(Cs.push(m), W.CALL_CREATE, W.OBJ_SHADER_MODULE,
             ShaderModule{code, Cs.last(m)}), W.CALL_POP, W.FILTER_VALIDATION, PopScope{})

# :80-84 -- CreateBindGroupLayout(device_res, WGPUBindGroupLayoutDescriptor(
# entryCount=len(bind_entries), entries=bind_entries)), pop_error. `W.bgl.of` IS
# the derivation (:74-78) and it is CALLED, not reimplemented.
def Cs.layout(+c: Cs, +nbufs: U32, nvals: U32) -> Cs:
  +m = Cs.mint(c)
  Cs.at(Cs.at(Cs.push(m), W.CALL_CREATE, W.OBJ_BIND_GROUP_LAYOUT,
             BindGroupLayout{W.bgl.of(nbufs, nvals), SHADER_STAGE_COMPUTE(),
                            Cs.last(m)}), W.CALL_POP, W.FILTER_VALIDATION, PopScope{})

# :87-91 -- WGPUPipelineLayoutDescriptor(bindGroupLayoutCount=1,
# bindGroupLayouts=[bind_layout]), pop_error.
def Cs.playout(+c: Cs, id: U32) -> Cs:
  +m = Cs.mint(c)
  Cs.at(Cs.at(Cs.push(m), W.CALL_CREATE, W.OBJ_PIPELINE_LAYOUT,
             PipelineLayout{id, Cs.last(m)}), W.CALL_POP, W.FILTER_VALIDATION, PopScope{})

# :94-95, ONE bind group entry. The SLOT KIND decides, and there are exactly two
# shapes:
#
#   a `bufs` slot  binds the caller's own buffer and emits NOTHING -- that is
#                  `x if isinstance(x, WGPUBuffer) else self.dev.create_uniform(x)`
#   any other slot CREATES a 4-byte UNIFORM|COPY_DST buffer and writes the value,
#                  which is `dev.create_uniform` (:202-205) as ONE op, because the
#                  trace records only the create (see the header)
#
# `caller` is the caller's buffer id, used only for a `bufs` slot. `wgc_bg_sizes`
# reads all three kinds off one fixture.
def Cs.entry(+c: Cs, +n: U32, is_buf: Bool, size: U32, caller: U32, +val: U32) -> Cs:
  match is_buf:
    case True{}: Cs.bound(c, List.append(&2, Bind, Cs.bg(c), [Bind{n, caller, size}]))
    case False{}:
      +m = Cs.mint(c)
      +d = Cs.at(m, W.CALL_CREATE, W.OBJ_BUFFER,
                 Uniform{Cs.last(m), W.dev.uniform_bytes(val), U32.is_eq(n, 0)})
      Cs.bound(d, List.append(&2, Bind, Cs.bg(d), [Bind{n, Cs.last(d), size}]))

def Cs.or0(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}: 0
    case Some{v}: v

# the CALLER's own buffer id for a `bufs` slot -- the one field `Pass.sizes` does
# not carry and the one `wg_bg_sizes` reads back off the bind group.
def Cs.buf_id(m: Maybe<&2, W.Buf>) -> U32:
  match m:
    case None{}: 0
    case Some{b}: W.Buf.id(b)

# THE CALLER'S OWN BUFFER ID for a `bufs` slot -- the one field `Pass.sizes` does
# not carry. THE INDEX IS `i - 1`, not `i`: `W.slots` puts INFINITY at slot 0 and
# `bufs` at 1..len(bufs), so a `bufs` slot's position in `bs` is its binding minus
# one.
#
# `Bool.pick(c, a, b)` ANSWERS `a` WHEN `c` IS TRUE (MEASURED, not read:
# `pick(true, 111, 222)` prints 111), so the TRUE arm is the buffer id and the
# FALSE arm is the 0 that a uniform slot -- which MINTS its handle instead --
# never reads. The arms were the wrong way round at first and NO ROW IN EITHER
# FILE SAW IT: `wgc_bg_sizes` reads SIZES and a wrong buffer id does not change a
# size, and `wgc_bg_ids` as first written read the BINDINGS, not the buffers. It
# surfaced in the BROWSER, at `BindGroup`, with "Failed to convert value to
# 'GPUBuffer'" -- three of the five entries bound nothing at all. `wgc_bg_handles`
# is the row that reads the buffer ids and is what would have caught it.
def Cs.caller(i: U32, is_buf: Bool, +bs: List<&2, W.Buf>) -> U32:
  Bool.pick(U32, is_buf,
    Cs.buf_id(List.get(&2, W.Buf, bs, Nat.sub(U32.to_nat(i), 1n))), 0)

# :94-97 as a fold over `W.slots`, which is INFINITY then `bufs` then `vals`. The
# `vals` cursor drops one per non-buffer entry past the first, because a slot's
# KIND decides which of the two lists it reads -- and `W.Slot.is_buf` is the port's
# own derivation of exactly that question.
def Cs.bind.go(n: Nat, +i: U32, +ss: List<&2, W.Slot>, +bs: List<&2, W.Buf>,
               +vs: List<&2, U32>, +c: Cs) -> Cs:
  match n:
    case 0n: c
    case 1n+m:
      match ss:
        case Nil{}: c
        case W.Slot{is_buf, size} <> t:
          Cs.bind.go(m, U32.add(i, 1), t, bs,
                     Bool.pick(List<&2, U32>, Bool.or(is_buf, U32.is_eq(i, 0)), vs,
                       List.drop(&2, U32, vs, 1n)),
                     Cs.entry(c, i, is_buf, size, Cs.caller(i, is_buf, bs),
                              Cs.or0(List.get(&2, U32, vs, 0n))))

# ===========================================================================
# THE REST OF ONE PROGRAM CALL, :99-147.
# ===========================================================================
# :99-102 -- CreateBindGroup(device_res, WGPUBindGroupDescriptor(layout=
# bind_layout, entryCount=len(bindings), entries=bindings)), same push/create/pop.
# `Cs.bg` is the fold's answer and this is the only reader of it, which is what
# makes `wgc_bg_sizes` a claim about the bind group and not about a fold.
def Cs.group(+c: Cs, layout: U32) -> Cs:
  +entries = Cs.bg(c)
  +m = Cs.mint(c)
  Cs.at(Cs.at(Cs.push(m), W.CALL_CREATE, W.OBJ_BIND_GROUP,
             BindGroup{layout, entries, Cs.last(m)}), W.CALL_POP,
       W.FILTER_VALIDATION, PopScope{})

# :105-107 -- DeviceCreateComputePipeline(device_res, WGPUComputePipelineDescriptor(
# layout=pipeline_layout, compute=WGPUComputeState(module=self.prg,
# entryPoint=self.name))). NOT an error scope: this one is a FUTURE, so its status
# arrives through the callback -- which is why `wg_call_scopes` is 3 and not 4
# and why the pipeline handle is not minted by a trace entry. `Cs.last(m)` is
# `Pass.entry` made live: it is the ONLY reader of that field, which
# `ops_webgpu.bend` says it deleted for want of one.
def Cs.pipeline(+c: Cs, layout: U32, module: U32, +entry: String) -> Cs:
  +m = Cs.mint(c)
  Cs.at(m, W.CALL_WAIT, W.SYNC_CREATE_PIPELINE,
        ComputePipeline{layout, module, entry, Cs.last(m)})

# :109 -- CreateCommandEncoder(device_res, WGPUCommandEncoderDescriptor()).
def Cs.encoder(+c: Cs) -> Cs:
  +m = Cs.mint(c)
  Cs.at(m, W.CALL_CREATE, W.OBJ_COMMAND_ENCODER, CreateEncoder{Cs.last(m)})

# :112-117 -- `if wait:` the query set (type Timestamp, count 2) and a 16-byte
# QueryResolve|CopySrc buffer. THE ORDER IS THE BUFFER BEFORE THE QUERY SET,
# which is the reverse of the Python's reading order (:113 then :115) because
# `pass.query.on` nests `emit(CREATE BUFFER)` OUTSIDE `emit(CREATE QUERY_SET)` --
# and the INNER one runs first. `wg_wait_query_created` pins it on the trace side.
# :113 creates the QUERY SET and :115 the QUERY BUFFER, and the ORDER IS THE
# QUERY SET FIRST -- MEASURED against `ops_webgpu.py:113` then `:115`, and
# `wg_wait_query_created` pins the same order on the trace side. My first version
# minted the buffer first, which the subsequence matcher could not see because
# both entries are `CALL_CREATE` and differ only in the object kind.
def Cs.query.on(+c: Cs) -> Cs:
  +q = Cs.mint(c)
  +b = Cs.mint(q)
  Cs.at(Cs.at(b, W.CALL_CREATE, W.OBJ_QUERY_SET,
              CreateQuerySet{Cs.last(q), QUERY_TYPE_TIMESTAMP(), QUERY_COUNT()}),
        W.CALL_CREATE, W.OBJ_BUFFER,
        CreateBuffer{Cs.last(b), QUERY_BUF_BYTES(),
                     U32.or(W.USAGE_QUERY_RESOLVE(), W.USAGE_COPY_SRC())})

# a `match` may not scrutinise a CALL, so `if wait:` is a `.at` whose Bool is a
# PARAMETER -- the same three-`.at` shape `ops_webgpu.bend` uses at :112, :126 and
# :140, for the same reason.
def Cs.query.at(wait: Bool, +c: Cs) -> Cs:
  match wait:
    case False{}: c
    case True{}: Cs.query.on(c)

def Cs.query(+c: Cs) -> Cs: Cs.query.at(Cs.wait(c), c)

# THE THREE `if wait:` ARMS share this shape because the trace cannot carry a
# `None`: an absent timestampWrites IS `Maybe.none` here, and it is the only place
# the port models absence at all. `wgc_timestamp_on_pass` reads the answer back.
def Cs.ts.at(wait: Bool, tw: TimestampWrites) -> Maybe<&2, TimestampWrites>:
  Bool.pick(Maybe<&2, TimestampWrites>, wait, Some{tw}, None{})

# :120 -- BeginComputePass(command_encoder, comp_pass_desc). `ts` is :116-117's
# timestampWrites, which is a DESCRIPTOR FIELD and not a call: it rides here
# because `beginComputePass` is where a WebGPU caller passes it.
def Cs.begin(+c: Cs, enc: U32, qs: U32) -> Cs:
  Cs.at(c, W.CALL_BEGIN, 0,
        BeginPass{enc, Cs.ts.at(Cs.wait(c), TimestampWrites{qs, BEGIN_PASS(), END_PASS()})})

# :121-122 -- SetPipeline(compute_pass, pipeline_result) then SetBindGroup(
# compute_pass, 0, bind_group, 0, None). Group 0 is the only group and `None` for
# the dynamic-offset array means the default, which is why the group index is 0.
def Cs.set(+c: Cs, pipeline: U32, bg: U32) -> Cs:
  Cs.at(Cs.at(c, W.CALL_SET_PIPELINE, 0, SetPipeline{pipeline}),
        W.CALL_SET_BIND_GROUP, W.BIND_GROUP_INDEX(), SetBindGroup{W.BIND_GROUP_INDEX(), bg})

# :123 -- DispatchWorkgroups(compute_pass, *global_size), NOT `local_size`; and
# `pass.geometry` records the local size and never dispatches on it (see
# `ops_webgpu.bend`'s "wgsl.bend owes", item 3).
def Cs.dispatch(+c: Cs, +gx: U32, gy: U32, gz: U32) -> Cs:
  Cs.at(c, W.CALL_DISPATCH, gx, Dispatch{gx, gy, gz})

# :124 -- End(compute_pass)
def Cs.end(+c: Cs) -> Cs: Cs.at(c, W.CALL_END, 0, EndPass{})

# :126 -- `if wait:` ResolveQuerySet(command_encoder, query_set, 0, 2, query_buf, 0)
# -- AFTER the pass has ended and BEFORE the encoder is finished, which is the
# position `wg_wait_resolve_between` pins on the trace side.
def Cs.resolve.at(wait: Bool, +c: Cs, enc: U32, qs: U32, dst: U32) -> Cs:
  match wait:
    case False{}: c
    case True{}: Cs.at(c, W.CALL_RESOLVE, W.QUERY_COUNT(),
                       ResolveQuerySet{enc, qs, dst, RESOLVE_COUNT()})

def Cs.resolve(+c: Cs, enc: U32, qs: U32, dst: U32) -> Cs:
  Cs.resolve.at(Cs.wait(c), c, enc, qs, dst)

# :128-129 -- Finish(command_encoder, WGPUCommandBufferDescriptor()) then
# Submit(self.queue, 1, [cmd_buf]). FINISH FIRST, and `wgc_call_trace` is what
# would die if it were not.
def Cs.finish(+c: Cs, enc: U32) -> Cs:
  +minted = Cs.mint(c)
  Cs.at(Cs.at(minted, W.CALL_FINISH, SUBMIT_COUNT(), Finish{enc, Cs.last(minted)}),
        W.CALL_SUBMIT, SUBMIT_COUNT(), Submit{Cs.last(minted)})

# ONE release: the object KIND the trace already carries, and the REAL handle it
# acts on. The trace cannot carry the handle -- `Release{id, kind}` in `Op` is
# exactly the field the trace has no room for -- so `kind` is `Call.arg` and `id`
# is the seam's own.
type Rel is Data:
  Rel{kind: U32, id: U32}

# :132-138 -- THE SEVEN RELEASES, and the order is CREATION order, not the
# reverse: bind_layout, pipeline_layout, bind_group, compute_pipeline,
# command_encoder, compute_pass, cmd_buf. `wg_call_released` pins the SAME order
# on the trace side and `wgc_release_order` pins it here, so the two can be
# compared without either being the other's expectation.
def Cs.release.go(n: Nat, +ids: List<&2, Rel>, acc: List<&2, Step>) -> List<&2, Step>:
  match n:
    case 0n: acc
    case 1n+m:
      match ids:
        case Nil{}: acc
        case Rel{kind, id} <> t:
          Cs.release.go(m, t, Step{W.CALL_RELEASE, kind, Release{id, kind}} <> acc)

# the seven, in :132-138's order. THE ORDER IS THE CLAIM; the kinds are the
# `W.OBJ_*` the trace already carries and are therefore not this file's to pin.
def Cs.release.ids(+bgl: U32, +pl: U32, +bg: U32, +pipe: U32, +enc: U32,
                   +pass: U32, +cb: U32) -> List<&2, Rel>:
  [Rel{W.OBJ_BIND_GROUP_LAYOUT(), bgl}, Rel{W.OBJ_PIPELINE_LAYOUT(), pl},
   Rel{W.OBJ_BIND_GROUP(), bg}, Rel{W.OBJ_COMPUTE_PIPELINE(), pipe},
   Rel{W.OBJ_COMMAND_ENCODER(), enc}, Rel{W.OBJ_COMPUTE_PASS(), pass},
   Rel{W.OBJ_COMMAND_BUFFER(), cb}]

def Cs.release(+c: Cs, +ids: List<&2, Rel>) -> Cs:
  match c:
    case Cs{ops, next, wait, bg}:
      Cs{Cs.release.go(List.length(&2, Rel, ids), ids, ops), next, wait, bg}

# :206-219 `_readable_buffer`: create a staging buffer of the SAME size with
# CopyDst|MapRead, copy the whole buffer into it, submit, then release the command
# buffer and the encoder IN THAT ORDER.
def Cs.readable(+c: Cs, src: U32, +size: U32) -> Cs:
  +stage = Cs.mint(c)
  +enc = Cs.mint(stage)
  +buf = Cs.mint(enc)
  # `CopyBuffer` and `Finish` name `Cs.last(enc)`, so the encoder's handle is the
  # one `Cs.mint` handed out two steps above and NOT a second mint.
  # :215 `wgpuCommandEncoderCopyBufferToBuffer(encoder, buf, 0, ret, 0, size)` --
  # the copy IS the point of a staging buffer, and my first version omitted it.
  # MEASURED: the trace has `8:16` between the encoder's create and the finish and
  # my walk did not, which is a whole WebGPU call the port was silently not making.
  d = Cs.at(Cs.at(Cs.at(Cs.at(Cs.at(stage, W.CALL_CREATE, W.OBJ_BUFFER,
                            CreateBuffer{Cs.last(stage), size, W.copy.readable_usage()}),
                      W.CALL_CREATE, W.OBJ_COMMAND_ENCODER, CreateEncoder{Cs.last(enc)}),
                 W.CALL_COPY, size, CopyBuffer{Cs.last(enc), src, Cs.last(stage), size}),
               W.CALL_FINISH, SUBMIT_COUNT(), Finish{Cs.last(enc), Cs.last(buf)}),
             W.CALL_SUBMIT, SUBMIT_COUNT(), Submit{Cs.last(buf)})
  +e2 = Cs.mint(d)
  Cs.at(Cs.at(e2, W.CALL_RELEASE, W.OBJ_COMMAND_BUFFER,
              Release{Cs.last(buf), W.OBJ_COMMAND_BUFFER()}),
        W.CALL_RELEASE, W.OBJ_COMMAND_ENCODER,
        Release{Cs.last(enc), W.OBJ_COMMAND_ENCODER()})

# :17-19 `buf_to_mv`: map async (ONE of the six `synchronous` calls) with
# WGPUMapMode_Read, then take the const mapped range over the WHOLE buffer -- the
# range is (0, wgpuBufferGetSize(buf)), which is why the size rides on the range
# and not on the map.
def Cs.read(+c: Cs, +buf: U32, +size: U32) -> Cs:
  Cs.at(Cs.at(Cs.at(c, W.CALL_WAIT, W.SYNC_MAP_ASYNC,
                    MapAsync{buf, MAP_MODE_READ(), size}),
              W.CALL_MAP_ASYNC, W.copy.readable_usage(),
              MapAsync{buf, MAP_MODE_READ(), size}),
        W.CALL_MAPPED_RANGE, size, MappedRange{buf, size})

# :195-198 `free(buf)`: unmap ONLY if the map state is Mapped, then destroy, then
# release -- all three in that order, always. TWO defs because a `match` scrutinee
# must be a PARAMETER: the state arrives as a U32 and the comparison is a leaf.
# This is `dev.free.at`'s own shape, and `wg_free_mapped` / `wg_free_unmapped` in
# `ops_webgpu.bend` are the trace-side counterpart of these two.
def Cs.free.at(mapped: Bool, +buf: U32, +c: Cs) -> Cs:
  match mapped:
    case True{}:
      Cs.at(Cs.at(Cs.at(c, W.CALL_UNMAP, W.OBJ_BUFFER, Release{buf, W.OBJ_BUFFER()}),
                  W.CALL_DESTROY, W.OBJ_BUFFER, DestroyBuffer{buf}),
            W.CALL_RELEASE, W.OBJ_BUFFER, Release{buf, W.OBJ_BUFFER()})
    case False{}:
      Cs.at(Cs.at(c, W.CALL_DESTROY, W.OBJ_BUFFER, DestroyBuffer{buf}),
            W.CALL_RELEASE, W.OBJ_BUFFER, Release{buf, W.OBJ_BUFFER()})

# the guard, read off the map state ops_webgpu.py reports (:196
# `wgpuBufferGetMapState(buf) == WGPUBufferMapState_Mapped`). `MAP_UNMAPPED` is
# the value `ops_webgpu.bend` passes at :141-142, and `wgc_free_unmapped` is the
# row that shows the UNMAP is absent because of THAT and not by accident.
def Cs.free(+c: Cs, buf: U32, map_state: U32) -> Cs:
  Cs.free.at(U32.is_eq(map_state, W.MAP_MAPPED()), buf, c)

# :140-145 -- `if wait:` the staging read of the two timestamps, then BOTH frees,
# then QuerySetDestroy and QuerySetRelease. The delta itself is WALL 2 and belongs
# to the driver; what survives here is the CALL that produces the two u64s.
#
# THE ORDER IS THE OPPOSITE of `pass.release` and that is not a choice: :140
# `_readable_buffer` creates a command encoder and a command buffer and releases
# them in REVERSE (:216-217), while :132-138 releases the pass's own seven in
# CREATION order. `wg_wait_tail` pins the former and `wg_call_released` the
# latter, so a mutation that reverses one does not hide in the other.
# :140's four statements in order: the staging read, BOTH frees (:141 `free(
# query_buf)` then :142 `free(tmp_buf)`), then :143-144 destroy and release the
# query set. `Cs.readable` is the read and `Cs.read` the map; the frees are
# `MAP_UNMAPPED` at BOTH, because `buf_to_mv` handed back a range that the port
# never unmaps -- :196's guard is False for both, which is `wg_wait_tail`'s
# `Call{CALL_UNMAP, ...}` absence.
# :140's four statements in order: the staging read, BOTH frees (:141 `free(
# query_buf)` then :142 `free(tmp_buf)`), then :143-144 destroy and release the
# query set. `Cs.readable` is the read and `Cs.read` the map; the frees are
# `MAP_UNMAPPED` at BOTH, because `buf_to_mv` handed back a range that the port
# never unmaps -- :196's guard is False for both, which is `wg_wait_tail`'s
# `Call{CALL_UNMAP, ...}` absence.
def Cs.timing.on(+c: Cs, +qs: U32, +qbuf: U32) -> Cs:
  # THE STAGING BUFFER IS THE FIRST of `Cs.readable`'s three mints -- the buffer,
  # then the encoder, then the command buffer -- so it is `next(c)`, not
  # `next(r) - 1`. MEASURED: `next(r) - 1` is the command buffer, so `Cs.read` named
  # a handle nothing had bound and the walk stopped at step 48 of 57 with "unbound
  # slot 12". The staging buffer is the whole point of :206-219: it is what
  # `buf_to_mv` maps, and freeing it is :143's `free(tmp_buf)`.
  +r = Cs.readable(c, qbuf, QUERY_BUF_BYTES())
  +tmp = Cs.next(c)
  # :141 IS ONE EXPRESSION -- `buf_to_mv(tmp_buf := self.dev._readable_buffer
  # (query_buf)).cast("Q")` -- so the map happens INSIDE it and therefore BEFORE
  # :142's `free(query_buf)` and :143's `free(tmp_buf)`. My first version read the
  # two timestamps after both frees, which is the order a reader would guess and
  # not the order the line has.
  m = Cs.read(r, tmp, QUERY_BUF_BYTES())
  d = Cs.free(m, tmp, W.MAP_UNMAPPED())
  e = Cs.free(d, qbuf, W.MAP_UNMAPPED())
  f = Cs.at(e, W.CALL_DESTROY_QUERY_SET, W.OBJ_QUERY_SET, DestroyQuerySet{qs})
  Cs.at(f, W.CALL_RELEASE, W.OBJ_QUERY_SET, Release{qs, W.OBJ_QUERY_SET()})
def Cs.timing.at(wait: Bool, +c: Cs, +qs: U32, +qbuf: U32) -> Cs:
  match wait:
    case False{}: c
    case True{}: Cs.timing.on(c, qs, qbuf)


def Cs.timing(+c: Cs, +qs: U32, +qbuf: U32) -> Cs: Cs.timing.at(Cs.wait(c), c, qs, qbuf)

# ===========================================================================
# THE WHOLE CALL, :69-147 in `prog.call.at`'s order. The only place the order is
# spelled out, so `wgc_call_trace` has exactly one walk to blame.
# ===========================================================================
def Cs.call(+bs: List<&2, W.Buf>, +nvals: Nat, +vals: List<&2, U32>, gx: U32, gy: U32,
            gz: U32, want: Bool, +feats: List<&2, U32>, +entry: String,
            +code: String) -> Cs:
  nbufs = U32.from_nat(List.length(&2, W.Buf, bs))
  nvals_u = U32.from_nat(nvals)
  # :71 `wait = wait and TimestampQuery in self.dev.features`, then :53-64 the
  # shader module. Its handle is read off the counter AFTER the step, because
  # :62-64's push/create/pop mints nothing but the shader module itself.
  +c1 = Cs.shader(Cs.wanted(Cs.of(), W.prog.wants_wait(want, feats)), code)
  +module = Cs.last(c1)
  # :80-102 -- layout, pipeline layout, the bind group entries, the bind group.
  +c2 = Cs.layout(c1, nbufs, nvals_u)
  +bgl = Cs.last(c2)
  +c3 = Cs.playout(c2, bgl)
  +pl = Cs.last(c3)
  # the fold's fuel is `1 + len(bufs) + len(vals)` (:77's entryCount), as a Nat.
  +c4 = Cs.bind.go(Nat.add(Nat.add(1n, List.length(&2, W.Buf, bs)), nvals), 0,
                   W.slots(bs, nvals), bs, vals, c3)
  +c5 = Cs.group(c4, bgl)
  +bg = Cs.last(c5)
  # :105-107 the pipeline -- a FUTURE, so no error scope -- then :109 the encoder.
  +c6 = Cs.pipeline(c5, pl, module, entry)
  +pipe = Cs.last(c6)
  +c7 = Cs.encoder(c6)
  +enc = Cs.last(c7)
  # :112-117 `if wait:` the query set and its 16-byte resolve buffer. The two are
  # minted by `Cs.query`, so both handles are read off the counter after it.
  # `Cs.query` mints the QUERY SET and then the QUERY BUFFER, in that order
  # (:113 then :115), so both handles are read off `c8` AFTER it and NOT off `c7`:
  # `c7`'s counter is where the mint STARTED, and `Cs.next(c7) - 1` is the query
  # set only when exactly one mint happened. MEASURED: computing them from `c7`
  # gave `qs = 7` -- the encoder's own slot -- and Chrome rejected the pass with
  # "Failed to convert value to 'GPUQuerySet'".
  +c8 = Cs.query(c7)
  +qbuf = Cs.hand(Cs.next(c8))
  +qs = U32.sub(qbuf, 1)
  # :120 begin, :121-124 set, dispatch, end.
  +c9 = Cs.begin(c8, enc, qs)
  +c10 = Cs.set(c9, pipe, bg)
  +c11 = Cs.dispatch(c10, gx, gy, gz)
  +c12 = Cs.end(c11)
  # :126 `if wait:` resolve, then :128-129 finish and submit.
  +c13 = Cs.resolve(c12, enc, qs, qbuf)
  +c14 = Cs.finish(c13, enc)
  +cb = Cs.last(c14)
  # :132-138 the seven releases, in CREATION order.
  +c15 = Cs.release(c14, Cs.release.ids(bgl, pl, bg, pipe, enc, W.OBJ_QUERY_SET(), cb))
  # :140-145 `if wait:` the staging read, the map, both frees, the query set.
  Cs.timing(c15, qs, qbuf)


def METAL() -> String: "WGPUBackendType_Metal"
def BOTH() -> List<&2, U32>: [W.FEATURE_TIMESTAMP_QUERY(), W.FEATURE_SHADER_F16()]
def F16() -> List<&2, U32>: [W.FEATURE_SHADER_F16()]
def CODE() -> String: "k"

# THE ONE VAL, as a VALUES list. `BOTH` is the FEATURE list and is not this: :78's
# `len(vals)` is a count of `ProgramInfo.vals` and :95's `bg_entry(i+1, x)` binds
# each one as a uniform. `wgc_vals_count` is the row that pins the two against each
# other, and `ONE` is what the browser run hands `Cs.call`.
def ONE() -> List<&2, U32>: [7]

def bufs.go(n: Nat, +id: U32, szs: List<&2, U32>, acc: List<&2, W.Buf>) -> List<&2, W.Buf>:
  match n:
    case 0n: List.reverse(&2, W.Buf, acc)
    case 1n+m:
      match szs:
        case Nil{}: List.reverse(&2, W.Buf, acc)
        case s <> t: bufs.go(m, U32.add(id, 1), t, W.Buf{id, s} <> acc)

def bufs3() -> List<&2, W.Buf>: bufs.go(3n, 100, [64, 64, 64], Nil{})

# THE FIXTURE: 3 GLOBAL buffers of 64 bytes and ONE val, global (8,1,1), local
# (4,1,1) -- the shape `WGSLRenderer.render_kernel` was measured with, per
# `ops_webgpu.bend`'s header.
# NOTE WHAT IS ABSENT: no `local_size`. `Cs.call` has no such parameter, and that
# is the port -- ops_webgpu.py NEVER READS it (the workgroup size comes from the
# WGSL `@workgroup_size` attribute) and `ops_webgpu.bend` RECORDS it in `Pass.ls`
# without dispatching on it. `wg_call_ls_recorded` is the trace-side counterpart.
# The fixture's local size is 4 and the global size is (8,1,1); only 8 reaches a
# dispatch.
def fx(want: Bool) -> Cs: Cs.call(bufs3(), 1n, ONE(), 8, 1, 1, want, BOTH(), CODE(), "BODY")
def fx_nowait() -> Cs: fx(False{})

# THE REAL TRACE, from `W.prog.call` on the SAME inputs: two INDEPENDENT walks of
# the same Python, this file's ops and `ops_webgpu.bend`'s trace.
#
# THE FIXTURE IS `fx_life`, NOT `fx_call`, and the difference is load-bearing.
# `ops_webgpu.bend` has both: `fx_call` calls `Pass.reset` so `dev.init`'s eight
# trace entries are not in front of the call, and `fx_life` keeps them. `fx` here
# covers :53-147 -- the shader module AND the call -- and NOT :166-190, because
# `Cs.call` does not do the device init; `Cs.init` is a separate def for that, and
# `wgc_init_trace` compares it against `dev.init`. So the trace to compare against
# must drop the init while KEEPING the shader module, which is exactly what
# `Tr.reset` does -- it empties the trace and keeps everything else in the `Pass`.
# MEASURED: with `fx_life` here instead, this file's 30 steps were a SUFFIX of the
# real 38 and `wgc_call_len` was False for a reason that had nothing to do with
# the port. The eight extra entries were `0:0 1:4 20:0 21:0 22:0 1:5 0:3 2:1`.
# AND THE INIT HALF, for `wgc_init_trace`: `dev.init`'s trace on its own, with
# nothing in front of it. `Tr.reset` empties it and `Cs.init` starts from
# `Cs.of()`, so the two lists are the same eight steps from the same Python.
def fx_real_init() -> W.Dev: W.dev.init(METAL(), BOTH())

# THE PASS WITH `dev.init`'s TRACE ALREADY GONE AND THE SHADER MODULE'S STILL
# THERE. `Tr.reset` on the DEV's trace is the operation: `prog.init` copies the
# `Dev`'s trace, so emptying the `Dev` first empties the copy WITHOUT emptying
# the `Pass` -- which is what `Pass.reset` (used one step too late) got wrong.
# There is no `Tr` reader for this on the `Dev`, so the two lines are here.
def fx_real_pass(+want: Bool) -> W.Pass:
  W.prog.init(CODE(), W.Dev.at(fx_real_init(), W.Tr.reset(W.Dev.tr(fx_real_init()))))

def fx_real(+want: Bool) -> W.Pass:
  W.prog.call(bufs3(), 1, 8, 1, 1, 4, want, fx_real_pass(want))

# EVERY SLOT THE WALK MINTS, in mint order. `Cs.slots` is the reader the whole
# seam hangs on: `Op`'s `slot` field is what the driver files a result under, and
# a repeated slot is two live objects in one map entry.
#
# `Cs.mints` and `Cs.slot` have one arm per constructor that HAS a `slot`, and a
# final `case _` because `Bool.pick` evaluates both arms and so cannot skip the
# append. The two are the SAME arm list written twice, and that is deliberate: one
# answers "does this op mint?" and the other "which slot?", and a single def
# returning a `Maybe` would allocate on every op of the walk.
def Cs.mints(op: Op) -> Bool:
  match op:
    case ShaderModule{code, slot}: True{}
    case BindGroupLayout{entries, visibility, slot}: True{}
    case PipelineLayout{id, slot}: True{}
    case Uniform{slot, bytes, is_f32}: True{}
    case BindGroup{layout, entries, slot}: True{}
    case ComputePipeline{layout, module, entry, slot}: True{}
    case CreateEncoder{slot}: True{}
    case CreateQuerySet{slot, ty, count}: True{}
    case CreateBuffer{slot, size, usage}: True{}
    case Finish{enc, slot}: True{}
    case Submit{slot}: True{}
    case GetQueue{slot}: True{}
    case _: False{}

def Cs.slot(op: Op) -> U32:
  match op:
    case ShaderModule{code, slot}: slot
    case BindGroupLayout{entries, visibility, slot}: slot
    case PipelineLayout{id, slot}: slot
    case Uniform{slot, bytes, is_f32}: slot
    case BindGroup{layout, entries, slot}: slot
    case ComputePipeline{layout, module, entry, slot}: slot
    case CreateEncoder{slot}: slot
    case CreateQuerySet{slot, ty, count}: slot
    case CreateBuffer{slot, size, usage}: slot
    case Finish{enc, slot}: slot
    case Submit{slot}: slot
    case GetQueue{slot}: slot
    case _: 0

def Cs.slot_of(+op: Op, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, Cs.mints(op), List.append(&2, U32, acc, [Cs.slot(op)]), acc)

def Cs.slots.go(n: Nat, ss: List<&2, Step>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+m:
      match ss:
        case Nil{}: List.reverse(&2, U32, acc)
        case Step{k, a, op} <> t: Cs.slots.go(m, t, Cs.slot_of(op, acc))

def Cs.slots(+c: Cs) -> List<&2, U32>:
  Cs.slots.go(List.length(&2, Step, Cs.ops(c)), Cs.ops(c), Nil{})

def Cs.first_slot(+c: Cs) -> U32: Cs.or0(List.get(&2, U32, Cs.slots(c), 0n))

# THE BYTES OF THE ONE INT UNIFORM, out of the OP and not out of `dev.uniform_bytes`.
# `Cs.entry` writes `W.dev.uniform_bytes(val)` into `Uniform.bytes` for every
# non-first slot, and this is the only reader of that field -- which is why M20,
# which reintroduces the one-bit shift at the CALL SITE, moved nothing until this
# row existed. The expectation is the LITERAL :204 produces for a val of 7.
# THE FOUR BYTES, in order. `Uniform.bytes` IS `dev.uniform_bytes(val)` and is
# ALWAYS FOUR ELEMENTS, so the count is a constant here and not a fold -- which is
# also what makes this a CHECK of the byte PATTERN and not of a length.
def Cs.append4(+acc: List<&2, U32>, +bs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32,
    List.append(&2, U32,
      List.append(&2, U32, acc, [Cs.or0(List.get(&2, U32, bs, 0n))]),
      [Cs.or0(List.get(&2, U32, bs, 1n))]),
    [Cs.or0(List.get(&2, U32, bs, 2n))]),
    [Cs.or0(List.get(&2, U32, bs, 3n))])

def Cs.uniform_bytes.go(n: Nat, ss: List<&2, Step>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match ss:
        case Nil{}: acc
        case Step{k, a, Uniform{slot, bytes, is_f32}} <> t:
          Cs.uniform_bytes.go(m, t, Bool.pick(List<&2, U32>, is_f32, acc,
                                 Cs.append4(acc, bytes)))
        case Step{k, a, op} <> t: Cs.uniform_bytes.go(m, t, acc)

def Cs.uniform_bytes(+c: Cs) -> List<&2, U32>:
  Cs.uniform_bytes.go(List.length(&2, Step, Cs.ops(c)), Cs.ops(c), Nil{})

# A Bend `List<&2, U32>` as the gate's own list type, for `uniform_bytes`'s fold to
# cons into. `Cs.calls` already builds one of these for `Call`, and this is the
# `U32` counterpart -- it exists so `uniform_bytes` does not hand `List.append` a
# list of a different element type, which does not typecheck.


# 0, 1, 2, ... in mint order. THE QUESTION NO OTHER ROW ASKS: is the counter
# actually counting? A frozen counter hands out the same handle forever and every
# other row in the file stays green, because nothing else reads `next`.
def Cs.dupe_of.go(n: Nat, xs: List<&2, U32>, +seen: List<&2, U32>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case +x <> t:
          Cs.dupe_of.go(m, t, List.append(&2, U32, seen, [x]),
            Bool.pick(U32, List.contains(~U32, ~U32.is_eq, seen, x), x, got))

# 0, 1, 2, ... in mint order. THE QUESTION NO OTHER ROW ASKS: is the counter
# actually counting? A frozen counter hands out the same handle forever and every
# other row in this file stays green, because nothing else reads `next`.
# MONOTONE, NOT CONTIGUOUS: each slot is AT LEAST the one before it. THE QUESTION
# NO OTHER ROW ASKS -- is the counter actually counting? A frozen counter hands out
# the same handle forever and every other row in this file stays green, because
# nothing else reads `next`. MEASURED: with the mint bound and then discarded,
# every handle came out 4294967295 and 50 rows were green; the BROWSER caught it.
#
# MONOTONE AND NOT "EACH IS THE PREVIOUS PLUS ONE", BECAUSE REPEATS ARE CORRECT:
# `Finish`+`Submit` share the command buffer's slot, and in the wait path the
# staging buffer's encoder shares its own. MEASURED: the wait slots are
# `0,1,2,3,4,5,6,7,8,9,10,10,11,12,13,13` -- two shared pairs, each the same
# object used twice. A row demanding strict contiguity would be a row that forbids
# the port from being right, which is the same mistake as the plain-distinctness row
# it replaced.
def Cs.monotone.go(n: Nat, xs: List<&2, U32>, +last: U32, bad: Bool) -> Bool:
  match n:
    case 0n: Bool.not(bad)
    case 1n+m:
      match xs:
        case Nil{}: Bool.not(bad)
        case +x <> t: Cs.monotone.go(m, t, x, Bool.or(bad, U32.is_lt(x, last)))

def Cs.monotone(+xs: List<&2, U32>) -> Bool:
  Cs.monotone.go(List.length(&2, U32, xs), xs, 0, False{})

# THE ONE REPEATED SLOT, or 0 when there is none. `Finish` and `Submit` share the
# command buffer's slot and nothing else may: two slots in one map entry would be
# two live objects under one handle, and zero would be a buffer submitted before it
# was finished.

def Cs.dupe_of(+xs: List<&2, U32>) -> U32:
  Cs.dupe_of.go(List.length(&2, U32, xs), xs, Nil{}, 0)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

# the (k, arg) trace projection, rendered -- so a mismatch is DIAGNosable from the
# output alone rather than only as a False.
def pairs(xs: List<&2, W.Call>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case W.Call{k, a} <> t: pairs(t, String.concat([U32.show(k), ":", U32.show(a)]) <> acc)

def crow(nm: String, xs: List<&2, W.Call>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(pairs(xs, Nil{}), " ")]))

# --- 1: the constants, each against the `autogen/webgpu.py` line it came from --
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("wgc_stage_compute", SHADER_STAGE_COMPUTE())
    urow("wgc_query_type", QUERY_TYPE_TIMESTAMP())
    urow("wgc_map_mode_read", MAP_MODE_READ())
    urow("wgc_power_pref", POWER_PREF_HIGH_PERF())
    urow("wgc_stype_wgsl", STYPE_SHADER_SOURCE_WGSL())
    urow("wgc_lit_query_bytes", QUERY_BUF_BYTES())
    urow("wgc_lit_query_count", QUERY_COUNT())
    urow("wgc_lit_begin_pass", BEGIN_PASS())
    urow("wgc_lit_end_pass", END_PASS())
    urow("wgc_lit_submit", SUBMIT_COUNT())
    urow("wgc_lit_resolve", RESOLVE_COUNT())
    # WALL 2's flag, on the C side. NO `Op` mentions it -- a browser has no timed
    # wait -- and this row is the number it had.
    urow("wgc_callback_mode_gone", CALLBACK_MODE_WAIT_ANY_ONLY())

# --- 2: the init ops agree with `dev.init`'s trace --------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    +c : Cs <- IO.pure(Cs, Cs.init(METAL(), BOTH()))
    +d : W.Dev <- IO.pure(W.Dev, fx_real_init())
    row("wgc_init_trace", W.Tr.has(Cs.calls(c), W.Tr.calls(W.Dev.tr(d))))
    crow("wgc_init_calls", Cs.calls(c))
    crow("wgc_init_real", W.Tr.calls(W.Dev.tr(d)))
    row("wgc_init_len", U32.is_eq(Cs.len(c), W.seen(W.Dev.tr(d))))
    urow("wgc_init_steps", Cs.len(c))
    row("wgc_init_power", U32.is_eq(W.backend_of(METAL()), 5))
    # the two constants the RequestAdapter op carries, against the oracle's values.
    row("wgc_init_power_pref", U32.is_eq(POWER_PREF_HIGH_PERF(), 2))

# --- 3: THE CENTRAL ROW. This file's step order IS `prog.call`'s trace order --
def t_call() -> IO(Unit):
  do IO<Unit>:
    +c : Cs <- IO.pure(Cs, fx(False{}))
    +p : W.Pass <- IO.pure(W.Pass, fx_real(False{}))
    # EQUALITY, not subsequence: equal lengths plus `Tr.has` is equality, and both
    # halves are one row each so neither can be satisfied alone.
    row("wgc_call_trace", W.Tr.has(Cs.calls(c), W.Tr.calls(W.Pass.tr(p))))
    row("wgc_call_len", U32.is_eq(Cs.len(c), Cs.of_calls(W.seen(W.Pass.tr(p)))))
    crow("wgc_call_mine", Cs.calls(c))
    crow("wgc_call_real", W.Tr.calls(W.Pass.tr(p)))
    urow("wgc_call_steps", Cs.len(c))
    # FOUR error scopes, not the three `wg_call_pushes` reports. `wg_call_pushes`
    # reads `fx_call`, whose `Pass.reset` drops the shader module's -- and
    # `ops_webgpu.bend` says of :62-64 "PushErrorScope(Validation),
    # CreateShaderModule, pop_error", so the module's scope is REAL and is only
    # absent from that fixture. This file's `fx` covers :53-147, so all four are
    # here, and the two halves are equal -- which is the claim worth making: an
    # unbalanced scope is a leaked validation scope, and nothing else would say so.
    row("wgc_call_scopes", U32.is_eq(Cs.count(W.CALL_PUSH(), c), 4))
    row("wgc_call_scope_balanced", U32.is_eq(Cs.count(W.CALL_PUSH(), c),
                                             Cs.count(W.CALL_POP(), c)))
    row("wgc_call_no_pipeline_scope", U32.is_eq(Cs.count_of_wait(c, W.SYNC_CREATE_PIPELINE()), 1))

# --- 4: the wait arms, :112-145 --------------------------------------------
def t_wait() -> IO(Unit):
  do IO<Unit>:
    +c : Cs <- IO.pure(Cs, fx(True{}))
    +p : W.Pass <- IO.pure(W.Pass, fx_real(True{}))
    row("wgc_wait_trace", W.Tr.has(Cs.calls(c), W.Tr.calls(W.Pass.tr(p))))
    row("wgc_wait_len", U32.is_eq(Cs.len(c), Cs.of_calls(W.seen(W.Pass.tr(p)))))
    crow("wgc_wait_mine", Cs.calls(c))
    crow("wgc_wait_real", W.Tr.calls(W.Pass.tr(p)))
    # `wait` needs the feature (:71), so the same call with F16 only must NOT
    # create the query set -- the counterpart to `wg_wait_no_ts_creates`.
    +n : Cs <- IO.pure(Cs, Cs.call(bufs3(), 1n, ONE(), 8, 1, 1, True{}, F16(),
                                   CODE(), "BODY"))
    row("wgc_wait_no_ts", Bool.not(Cs.wait(n)))
    urow("wgc_wait_no_ts_steps", Cs.len(n))
    row("wgc_wait_no_ts_eq_nowait", U32.is_eq(Cs.len(n), Cs.len(fx_nowait())))

# --- 5: the descriptors, the thing the trace cannot carry ------------------
def t_desc() -> IO(Unit):
  do IO<Unit>:
    +c : Cs <- IO.pure(Cs, fx(False{}))
    # the three usage bitmasks, against the oracle's derivation from :152, :203
    # and :208 -- and each against the literal `wg_*_usage` already prints.
    row("wgc_usage_alloc", U32.is_eq(W.alloc.usage(), 140))
    row("wgc_usage_uniform", U32.is_eq(W.dev.uniform_usage(), 72))
    row("wgc_usage_readable", U32.is_eq(W.copy.readable_usage(), 9))
    row("wgc_usage_query", U32.is_eq(U32.or(W.USAGE_QUERY_RESOLVE(), W.USAGE_COPY_SRC()), 516))
    row("wgc_visibility", U32.is_eq(SHADER_STAGE_COMPUTE(), 4))
    row("wgc_query_type_val", U32.is_eq(QUERY_TYPE_TIMESTAMP(), 2))
    # the bind group's sizes, which is `W.slots`' answer and the seam's payload.
    lrow("wgc_bg_sizes", Cs.bg_sizes(Cs.bg(c)))
    lrow("wgc_bg_ids", Cs.bg_ids(Cs.bg(c)))
    # THE BUFFER HANDLES EACH ENTRY BINDS, and this is the row that reads what
    # `wgc_bg_sizes` cannot: a wrong buffer id leaves every SIZE correct. MEASURED:
    # `Cs.caller`'s `Bool.pick` arms were the wrong way round, so all three `bufs`
    # entries bound id 0, and the browser rejected the bind group with "Failed to
    # convert value to 'GPUBuffer'" at step 20 of 57. The expectation is the
    # LITERAL 3, 100, 101, 102 -- `bufs3` starts at 100 so a caller's id can never
    # collide with a slot the seam mints -- and it is a literal, not a call of the
    # thing under test.
    lrow("wgc_bg_handles", Cs.bg_bufs(Cs.bg(c)))
    urow("wgc_bg_n", U32.from_nat(List.length(&2, Bind, Cs.bg(c))))
    row("wgc_layout_entries", W.u32_list_eq(W.bgl.flat(W.bgl.of(3, 1), Nil{}),
                                            [0, 1, 1, 2, 2, 2, 3, 2, 4, 1]))
    row("wgc_vals_count", U32.is_eq(U32.from_nat(List.length(&2, U32, ONE())), 1))
    # EVERY SLOT THE WALK MINTS IS DISTINCT, and this row exists because a counter
    # that never advances is invisible to every other row in the file. MEASURED:
    # with `Cs.mint(c)` bound and then `Cs.at(Cs.push(c), ..)` written, every
    # handle came out 4294967295 -- `Cs.next(0) - 1` -- and 50 rows stayed green,
    # because `Cs.calls` reads the trace and `Cs.bg` reads the bind group and
    # NEITHER READS `next`. The browser was what caught it, at `PipelineLayout`.
    # So this asks the counter a question no other row asks: are the slots the walk
    # hands out pairwise different?
    # THE SLOTS THE DRIVER HANGS EVERY RESULT ON, and the claim is NOT "all
    # distinct" -- it is "distinct EXCEPT THE ONE PAIR THAT MUST SHARE".
    #
    # `Finish` (:128) and `Submit` (:129) both take the SAME command buffer, so
    # `Cs.finish` gives them one slot and `wgc_handles_shared` is the row that says
    # so. MEASURED: the first version of this row asserted plain distinctness and
    # was False, and the reason was correct code -- the slot list is
    # `0,1,2,3,4,5,6,7,8,8` and the last two are one buffer submitted after it is
    # finished. A row that says "all distinct" here would be a row that forbids the
    # port from being right.
    #
    # WHAT IT IS REALLY FOR: a counter that never advances is invisible to every
    # other row in this file, because `Cs.calls` reads the trace and `Cs.bg` reads
    # the bind group and NEITHER READS `next`. MEASURED: with the mint bound and
    # then discarded, every handle came out 4294967295 and 50 rows stayed green --
    # the browser caught it at `PipelineLayout`. `wgc_handles_contiguous` is the row
    # that asks the counter the question nothing else asks.
    row("wgc_handles_monotone", Cs.monotone(Cs.slots(fx(False{}))))
    row("wgc_handles_monotone_wait", Cs.monotone(Cs.slots(fx(True{}))))
    row("wgc_handles_shared", U32.is_eq(Cs.dupe_of(Cs.slots(fx(False{}))), 8))
    lrow("wgc_handles", Cs.slots(fx(False{})))
    lrow("wgc_handles_wait", Cs.slots(fx(True{})))
    lrow("wgc_handles_init", Cs.slots(Cs.init(METAL(), BOTH())))

def t_wall3() -> IO(Unit):
  do IO<Unit>:
    # :97 binds `float('inf')` at binding 0, and `dev.uniform_bytes` cannot build
    # an f32 pattern. So the op says `is_f32` and the driver builds it.
    +b : Bind <- IO.pure(Bind, Cs.or0_one(Cs.bg(fx(False{}))))
    row("wgc_wall3_found", U32.is_eq(Bind.n(b), 0))
    urow("wgc_wall3_size", Bind.size(b))
    row("wgc_wall3_int_bytes", W.u32_list_eq(W.dev.uniform_bytes(7), [7, 0, 0, 0]))
    # AND THE BYTES THE UNIFORM OP ACTUALLY CARRIES. M20 reintroduces the
    # one-bit shift INSIDE this file's own `Uniform` and moved no row at all,
    # because `wgc_wall3_int_bytes` calls `dev.uniform_bytes` DIRECTLY and never
    # reads what `Cs.entry` put in the op. That is the row that was missing and
    # this is it -- it reads the op, so a wrong byte pattern in the op is visible.
    lrow("wgc_uniform_bytes", Cs.uniform_bytes(fx(False{})))
    row("wgc_wall3_neg_bytes", W.u32_list_eq(W.dev.uniform_bytes(4294967295),
                                             [255, 255, 255, 255]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_init()
    +c : Unit <- t_call()
    +d : Unit <- t_wait()
    +e : Unit <- t_desc()
    +f : Unit <- t_wall3()
    IO.print("wgc-done=1")
