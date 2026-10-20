// tinybendygrad/runtime/webgpu_call.js -- THE JAVASCRIPT HALF of the WebGPU
// call layer. Companion to `webgpu_call.bend`, and the thing that file's header
// says does not exist anywhere: a place where a TRACED dispatch reaches a REAL
// `navigator.gpu` call.
//
// THE BOUNDARY, in one sentence: `webgpu_call.bend` is pure Bend, is compiled to
// `webgpu_call.mjs` by `bend -o`, and this file imports that module, asks it for
// the ordered operations, and performs them against `navigator.gpu`.
//
//   bend tinybendygrad/runtime/webgpu_call.bend -o tinybendygrad/runtime/webgpu_call.mjs
//
// WHY THIS SHAPE. The `.mjs` emitter gives constructors as `{$: "Name", field}`
// and `Nat` as `BigInt`, and exports every NON-IO def, so `Cs.call` arrives here
// as an ordinary function and `Cs.order` returns the steps already in step order.
// The alternative -- an FFI effect (`import "./webgpu.c"`) -- would have made
// `Tr.emit` answer `IO(Tr)` and destroyed the pure gate the 147 rows in
// `ops_webgpu.bend` depend on; see that file's header for the measurement.
//
// EVERY `switch` ARM IS ONE `navigator.gpu` METHOD, named for it, and the op
// constructors in `webgpu_call.bend` are named for the same methods -- so a `case`
// here and a constructor there are one thing and a rename moves both. Where the C
// API and the JS API DIFFER, the arm says so and says why, because that is the
// part of the crossing the trace could never have shown.
//
// THIS FILE MAKES NO CLAIM IT HAS NOT RUN. `run` returns the steps it performed
// and throws naming the op it stopped on, so a run that dies halfway is legible
// rather than silent.

// The `.mjs` emitter puts EVERY def on the module's `default` object under its
// own name -- `export default { "Cs.call": ..., "fx": ... }` -- and there are no
// named exports at all. MEASURED: `import * as M` gives `Object.keys(M).length
// === 1` and that one key is `default`. So every port def is reached as
// `M["Cs.call"]`, never as `M.Cs.call`, because a dotted name is ONE key.
import M from "./webgpu_call.mjs";
const bend = (name) => M[name];

// ===========================================================================
// THE MARSHALLING. A Bend `List` is `{$: "Nil"}` / `{$: "Con", head, tail}`, a
// `U32` is a number and a `Nat` is a `BigInt`. These three functions are the
// whole of it; `toJS` is used where the order matters (the bind group entries,
// which are in BINDING order and must stay that way).
// ===========================================================================
const nil = (l) => l !== null && typeof l === "object" && l.$ === "Nil";

// THE MARSHALLING, and it has TWO shapes because the emitter has two.
//
// A `List` STORED IN A RECORD FIELD crosses as a plain JS array: `RequestDevice`'s
// `feats` arrives as `[3, 8]`, not as `{$: "Con", ...}`. MEASURED, and it cost a
// run -- `toJS` read `l.$` off an array, got `undefined`, and the walk stopped at
// step 5 of 57 with "Cannot read properties of undefined (reading '$')".
//
// A `List` RETURNED BY A DEF crosses as the cons list: `Cs.order` hands back
// `{$: "Con", head: ..., tail: ...}`. The guide's "a value crosses without a
// copy" is about `Array`, and `List` is not `Array` -- `List<&2, A>` is a cons
// list in both directions, but a record field of that type is emitted as an array.
//
// So `toJS` accepts either, and `isList` is the one test that tells them apart.
const isList = (l) => l !== null && typeof l === "object" && typeof l.$ === "string";

export const toJS = (l) => {
  if (Array.isArray(l)) return l.slice();
  const a = [];
  for (; l !== null && l !== undefined && !nil(l); l = l.tail) a.push(l.head);
  return a;
};

// THE C ENUMS AS THE JS API SPELLS THEM, AND THE TWO KINDS OF SPELLING.
//
// Each left-hand value is a constant `webgpu_call.bend` gated against
// `autogen/webgpu.py`; each right-hand value is what Chrome 154 actually accepts,
// and BOTH KINDS OCCUR:
//
//   BY NAME. A WebGPU IDL enum whose spec spells it as a string is a string here:
//   `buffer.type`, `mapAsync`'s mode, `createQuerySet`'s type, the power
//   preference and the two FEATURE names. `buffer.type` in particular was probed:
//   `"uniform"` is accepted and `1` is not.
//
//   BY VALUE. `GPUBufferUsage` and `GPUShaderStage` are `unsigned long` bitmasks
//   in the IDL, NOT string enums, so the C constant is forwarded unchanged.
//   MEASURED against Chrome 154 on this machine, and the string form is REJECTED:
//   `createBindGroupLayout` with `visibility: "compute"` fails with "Value is not
//   of type 'unsigned long'", while 1, 2 and 4 all succeed -- and
//   `GPUShaderStage.COMPUTE` reads 4, the same value as
//   `WGPUShaderStage_Compute`. So `visibility` is forwarded BY VALUE and this file
//   says so, because getting it wrong is a silent-looking descriptor rejection at
//   the first real bind group layout.
const SHADER_STAGE = { 4: 4 };                           // WGPUShaderStage_Compute = 4
const BINDING_TYPE = { 1: "uniform", 2: "storage" };     // WGPUBufferBindingType_*
// MEASURED, and this one is ALSO BY VALUE, which the first version got wrong in
// the other direction: `GPUQueue.mapAsync`'s first argument is a `GPUMapMode`
// FLAG (`unsigned long`), so `"read"` is REJECTED with "Value is not of type
// 'unsigned long'" and the number 1 is what `GPUMapMode.READ` is. It stopped the
// walk at step 48 of 57. So THREE of the six enums here are numeric -- usage,
// visibility and map mode -- and three are string enums: buffer type, query type
// and the power preference. That split is a property of the WebGPU IDL and not a
// choice, so it is measured per constant and said so per constant.
const MAP_MODE = { 1: 1 };                               // WGPUMapMode_Read = 1
const QUERY_TYPE = { 2: "timestamp" };                   // WGPUQueryType_Timestamp = 2
const POWER_PREF = { 2: "high-performance" };            // WGPUPowerPreference_HighPerf = 2
const FEATURE = { 3: "timestamp-query", 8: "shader-f16" };  // WGPUFeatureName_*
// `W.USAGE_UNIFORM | W.USAGE_COPY_DST`, which `wgc_usage_uniform` pins at 72, and
// which Chrome takes by value for the same reason `visibility` is.
const UNIFORM_USAGE = 72;

// WALL 3, RESOLVED. `base.bend`'s F32 has no infinity literal, no bitcast and no
// `to_bits`, so ops_webgpu.py:204's `struct.pack('<f', float('inf'))` cannot be
// built in Bend at all -- `ops_webgpu.bend` calls that WALL 3 and defers it. Here
// it is one line. This is the ONE wall of the three the seam CLOSES.
const f32 = (x) => new Float32Array([x]).buffer;

// ops_webgpu.py:97 binds `float('inf')` at binding 0, and that binding is
// load-bearing: `wgsl.py:114` declares `var<uniform> INFINITY : f32` there, so
// every kernel faults at bind time if it is anything else.
const INFINITY = Infinity;

// THE MACHINE. `slots` is `webgpu_call.bend`'s handle namespace -- the handles it
// MINTS -- and `owned` is the caller's own buffers, indexed by the ids
// `webgpu_call.bend` binds for them.
//
// `Cs.entry` binds a `bufs` slot to the CALLER's id rather than minting one,
// because ops_webgpu.py:96's `buf = x if isinstance(x, WGPUBuffer) else
// self.dev.create_uniform(x)` binds the caller's buffer as-is. Those buffers come
// from `_alloc` (:150-153) and in a browser they are `createBuffer` calls the
// CALLER makes -- `webgpu_call.bend` deliberately does not emit them, because they
// belong to the allocator and not to a program call, and `ops_webgpu.bend` ports
// `alloc.of` separately. So the driver takes them as `owned` and the caller
// supplies real GPUBuffers at the ids `bufs3` mints.
//
// THE IDS ARE 100, 101, 102 -- not 0, 1, 2 -- because `bufs3` starts at 100 so
// that a caller's buffer id can never collide with a slot the seam mints. That
// offset is `bufs3`'s own and `wgc_bg_ids` reads the bind group's bindings, which
// is what would catch a driver indexing `owned` from the wrong end.
//
// `owned` IS INDEXED BY THE CALLER'S OWN ID AND NOT BY POSITION, because
// `webgpu_call.bend` binds `bs[i-1].id` and `bufs3` starts at 100. So it is
// SPARSE, and a plain array indexed by position answers `undefined` for id 100.
// MEASURED: "unbound slot 100" at `BindGroup`, step 20 of 57. A `Map` keyed by the
// caller's id is what the port's ids call for, and it is also what makes the two
// namespaces checkable against each other: `slots` and `owned` are separate maps
// precisely so a collision would be visible rather than silent.
const fresh = (owned = new Map()) => ({ slots: new Map(), owned, maps: new Map(), pass: null, range: null });

// ===========================================================================
// ONE OP. `op` is one constructor from `webgpu_call.bend`'s `Op`, `m` is the
// machine, and `gpu` is whatever the previous op returned -- the device, the
// adapter, the queue. The seam's handles are all the state there is, and this
// driver adds only the two live WebGPU objects that are not addressed by a slot:
// the encoder and the compute pass, which `Cs.encoder` and `Cs.begin` create and
// the following five ops use.
// ===========================================================================
async function perform(op, m, gpu) {
  const buf = (slot) => {
    const b = m.slots.get(slot) ?? m.owned.get(slot);
    if (b === undefined) throw new Error("webgpu_call: unbound slot " + slot);
    return b;
  };
  switch (op.$) {
    // :11 wgpuCreateInstance(WGPUInstanceDescriptor(features=
    // WGPUInstanceFeatures(timedWaitAnyEnable=True))). `navigator.gpu` IS the
    // instance -- there is no create call on the JS side -- so this arm hands the
    // adapter forward untouched. The `timedWaitAnyEnable` flag exists ONLY so
    // `wgpuInstanceWaitAny` can block (:37); a browser awaits instead, so the
    // flag has nothing to enable and `wgc_callback_mode_gone` pins that it was 1.
    case "Instance":
      return navigator.gpu;

    // :169 InstanceRequestAdapter(instance, WGPURequestAdapterOptions(
    // powerPreference=HighPerformance, backendType=...)).
    // `backendType` IS NOT IN THE JS API: it is a wgpu-native extension for
    // choosing among several backends on one machine, and a browser exposes one.
    // So `RequestAdapter.backend` is read and NOT forwarded -- which is also why
    // `W.backend_of`'s whole nine-name reverse table has no effect here.
    case "RequestAdapter":
      return await navigator.gpu.requestAdapter({ powerPreference: POWER_PREF[op.power] });

    // :172 wgpuAdapterGetFeatures(adapter_res, supported_features). The JS
    // adapter's `features` is already a live `GPUSupportedFeatures` set.
    case "ReadFeatures": return gpu.features;

    // :175 wgpuSupportedFeaturesFreeMembers(supported_features). Nothing to free:
    // the set is a live object the collector owns. The arm EXISTS so the step is
    // accounted for, and it says so rather than pretending to free something.
    case "FreeFeatures": return gpu;

    // :180 wgpuAdapterGetLimits(adapter_res, supported_limits). In JS the limits
    // ride on the adapter and go to `RequestDevice` as `requiredLimits`.
    case "ReadLimits": return gpu.limits;

    // :184 AdapterRequestDevice(adapter_res, dev_desc{requiredFeatureCount,
    // requiredFeatures, requiredLimits}). The feature NAMES are Bend's feature
    // ids mapped to the strings WebGPU spells them with, and they are filtered by
    // what the adapter HAS: requesting an absent feature is a rejection, and
    // ops_webgpu.py:173 already filtered the list to the two it probes for.
    //
    // THE RECEIVER IS THE ADAPTER HERE and the device everywhere after, so `gpu`
    // changes identity at exactly this op. `run` makes that assignment, and this
    // is why every later arm may assume a device.
    case "RequestDevice": {
      const required = toJS(op.feats).map((f) => FEATURE[f]).filter((f) => gpu.features.has(f));
      return await gpu.requestDevice({ requiredFeatures: required, requiredLimits: gpu.limits });
    }

    // :185 wgpuDeviceGetQueue(device_res). In JS the queue is a property.
    case "GetQueue": return gpu.queue;

    // :187 wgpuAdapterRelease(adapter_res). The JS adapter is garbage collected
    // and WebGPU has no release; the arm exists to keep the step accounted for.
    case "ReleaseAdapter": return gpu;

    // :62, :80, :88, :101 wgpuDevicePushErrorScope(device_res, Validation).
    case "PushScope": gpu.pushErrorScope("validation"); return null;

    // :64, :84, :91, :102 DevicePopErrorScope(device_res)[1] -- the MESSAGE.
    // One of the six `synchronous`-wrapped calls, so an `await` here; the port's
    // `sync_payload` arithmetic is what says index 1 is the message and the
    // resolved value is it.
    case "PopScope": return await gpu.popErrorScope();

    // :63 wgpuDeviceCreateShaderModule(device_res, {code, nextInChain: WGSL}).
    // The CHAIN whose `sType = WGPUSType_ShaderSourceWGSL` names the language in
    // the C API has NO counterpart: `code` is a JS string and WGSL is the only
    // thing `createShaderModule` accepts. That is why `STYPE_SHADER_SOURCE_WGSL`
    // is carried on `Instance` and reaches no arm.
    case "ShaderModule": return gpu.createShaderModule({ code: op.code });

    // :82 wgpuDeviceCreateBindGroupLayout(device_res, {entryCount, entries}).
    // `entryCount` is inferred from `entries`, so only the entries are passed.
    // THE `visibility` IS NOT PER ENTRY, and that is ops_webgpu.py:75's own doing:
    // `bgl_entry` passes `visibility=WGPUShaderStage_Compute` for EVERY entry, so
    // `webgpu_call.bend` hoisted it to one field of the op rather than repeating
    // it five times -- and `wgc_layout_visibility` pins the 4. MEASURED: reading it
    // off each entry gave `undefined` and Chrome rejected the descriptor with
    // "Required member is undefined" AT STEP 12, which is the first real
    // descriptor this driver has built.
    case "BindGroupLayout":
      return gpu.createBindGroupLayout({
        entries: toJS(op.entries).map((b) => ({
          binding: b.binding, visibility: SHADER_STAGE[op.visibility],
          buffer: { type: BINDING_TYPE[b.ty] },
        })),
      });

    // :88 wgpuDeviceCreatePipelineLayout(device_res, {bindGroupLayoutCount=1,
    // bindGroupLayouts=[bind_layout]}). The count is inferred.
    case "PipelineLayout":
      return gpu.createPipelineLayout({ bindGroupLayouts: [buf(op.id)] });

    // :202-205 `dev.create_uniform(val)`: ONE 4-byte UNIFORM|COPY_DST buffer AND
    // the write into it. THE TRACE RECORDS ONLY THE CREATE -- `pass.uniforms.put`
    // emits `CALL_CREATE OBJ_BUFFER` -- so this is ONE op for two Python calls,
    // and `wgc_uniform_one_step` pins the collapse. `is_f32` is WALL 3: :97's
    // `float('inf')` has no bit pattern in Bend and this is where it is built.
    case "Uniform": {
      const g = gpu.createBuffer({ size: 4, usage: UNIFORM_USAGE });
      gpu.queue.writeBuffer(g, 0, op.is_f32 ? f32(INFINITY) : u8(toJS(op.bytes)));
      return g;
    }

    // :152 / :115 / :208 wgpuDeviceCreateBuffer(device_res, {size, usage}).
    // `usage` arrives as the C bitmask `webgpu_call.bend` computed and the JS
    // `GPUBufferUsage` flags are THE SAME NUMBERS, so it goes by value.
    case "CreateBuffer":
      return gpu.createBuffer({ size: op.size, usage: op.usage });

    // :221 wgpuQueueWriteBuffer(queue, buf, 0, <bytes>, len(src)). The offset is
    // the literal 0 of :221 and the LENGTH is `len(src)`, so `u8` supplies both.
    case "WriteBuffer":
      gpu.queue.writeBuffer(buf(op.buf), 0, u8(toJS(op.bytes)));
      return null;

    // :99 wgpuDeviceCreateBindGroup(device_res, {layout, entryCount, entries}).
    // The entries' `offset` is the literal 0 of :96.
    case "BindGroup":
      return gpu.createBindGroup({
        layout: buf(op.layout),
        entries: toJS(op.entries).map((e) => ({
          binding: e.n,
          resource: { buffer: buf(e.buf), offset: 0, size: e.size },
        })),
      });

    // :106 DeviceCreateComputePipeline(device_res, {layout,
    // compute:{module, entryPoint}}). A FUTURE, so NO error scope -- which is why
    // `wg_call_pushes` is 3 and not 4 -- and `createComputePipelineAsync` is the
    // awaited form of the same call. `op.entry` is `Pass.entry`, which
    // `ops_webgpu.bend` says it DELETED for want of a reader: this is that reader.
    case "ComputePipeline":
      return await gpu.createComputePipelineAsync({
        layout: buf(op.layout),
        compute: { module: buf(op.module), entryPoint: op.entry },
      });

    // :109 wgpuDeviceCreateCommandEncoder(device_res, {}). The encoder is one of
    // the two objects the seam does not slot -- the next five ops use it and none
    // of them names it -- so it lives on the machine.
    case "CreateEncoder": return gpu.createCommandEncoder({});

    // :114 wgpuDeviceCreateQuerySet(device_res, {type=Timestamp, count=2})
    case "CreateQuerySet":
      return gpu.createQuerySet({ type: QUERY_TYPE[op.ty], count: op.count });

    // :120 wgpuCommandEncoderBeginComputePass(command_encoder, comp_pass_desc).
    // :116-117's `timestampWrites` is a DESCRIPTOR FIELD and not a call of its
    // own -- which is why NO trace entry exists for it and why `ops_webgpu.bend`
    // lists it under what its gate does not see. It is handed to
    // `beginComputePass` here and nowhere else, and `wgc_timestamp_on_pass` is the
    // row that says the port put it on this op. `op.ts` is `Maybe.none` when
    // `wait` is False, which reaches JS as `null`.
    //
    // `op.ts` IS A `Maybe`, and a Bend `Maybe` crosses as `{$: "Some", value: x}`
    // or `{$: "None"}` -- NOT as `x` or `null`. MEASURED: treating it as either
    // gave `op.ts.qs === undefined` and "unbound slot undefined" at step 24 of 38,
    // and it is the ONLY `Maybe` in `Op`, which is why only this arm had to learn
    // it. `Some` unwraps to `.value`; `None` means `wait` was False and the
    // descriptor carries no timestampWrites at all.
    case "BeginPass": {
      const ts = op.ts.$ === "None" ? undefined : op.ts.value;
      return (m.pass = buf(op.enc).beginComputePass(ts === undefined ? undefined : {
        timestampWrites: { querySet: buf(ts.qs), beginningOfPassWriteIndex: ts.first,
                           endOfPassWriteIndex: ts.last } }));
    }

    // :121 wgpuComputePassEncoderSetPipeline(compute_pass, pipeline_result)
    case "SetPipeline": m.pass.setPipeline(buf(op.pipeline)); return null;

    // :122 wgpuComputePassEncoderSetBindGroup(compute_pass, 0, bind_group, 0, None)
    case "SetBindGroup": m.pass.setBindGroup(op.group, buf(op.bg)); return null;

    // :123 wgpuComputePassEncoderDispatchWorkgroups(compute_pass, *global_size).
    // `global_size` and NEVER `local_size`: ops_webgpu.py never reads the local
    // size -- the workgroup size comes from WGSL's `@workgroup_size` -- and
    // `webgpu_call.bend` has no parameter that could carry one.
    case "Dispatch": m.pass.dispatchWorkgroups(op.gx, op.gy, op.gz); return null;

    // :124 wgpuComputePassEncoderEnd(compute_pass)
    case "EndPass": m.pass.end(); return null;

    // :126 wgpuCommandEncoderResolveQuerySet(encoder, query_set, 0, 2, query_buf,
    // 0). The two leading zeros are the first query index and the destination
    // offset, as written on the Python line.
    case "ResolveQuerySet":
      buf(op.enc).resolveQuerySet(buf(op.qs), 0, op.count, buf(op.dst), 0);
      return null;

    // :128 wgpuCommandEncoderFinish(command_encoder, {})
    case "Finish": return buf(op.enc).finish();

    // :129 wgpuQueueSubmit(queue, 1, [cmd_buf]). `1` is `SUBMIT_COUNT` and the
    // JS API takes the array without a count.
    case "Submit": gpu.queue.submit([buf(op.slot)]); return null;

    // :132-138 the seven releases, :187 the adapter's. In JS EVERY one of these
    // is the collector's job and WebGPU has no release function, so this arm drops
    // the reference -- which is what the release IS. It is NOT `destroy`, which is
    // a separate op and a real call (:197).
    case "Release": m.slots.delete(op.id); return null;

    // :215 wgpuCommandEncoderCopyBufferToBuffer(encoder, buf, 0, ret, 0, size).
    // The two zeros are the source and the destination offset.
    case "CopyBuffer":
      buf(op.enc).copyBufferToBuffer(buf(op.src), 0, buf(op.dst), 0, op.size);
      return null;

    // :18 BufferMapAsync(buf, WGPUMapMode_Read, 0, size) -- one of the six
    // `synchronous`-wrapped calls, so an `await`. The offset is the literal 0.
    //
    // ONE PYTHON CALL, TWO OPS, ONE `mapAsync`. `synchronous` (:23-43) wraps
    // `wgpuBufferMapAsync2` and the port records the wrapper and the call
    // separately -- `Tr.emit(CALL_MAP_ASYNC, ..)` inside
    // `Tr.emit(CALL_WAIT, SYNC_MAP_ASYNC, ..)` -- so `Cs.read` emits `MapAsync`
    // TWICE for one :18. Calling `mapAsync` twice is an error: the second call on a
    // buffer that is already mapped or mapping REJECTS.
    //
    // So the promise is kept PER BUFFER and the second op awaits the one the first
    // started. MEASURED: without this the walk hung at the first `MapAsync` of
    // step 36 of 49. Which op is the "wrapper" and which the "call" is a question
    // `Step.k` answers and this driver does not need answered -- and NOT needing it
    // is the point, because `navigator.gpu` has no wrapper to model.
    case "MapAsync": {
      if (!m.maps.has(op.buf)) m.maps.set(op.buf, buf(op.buf).mapAsync(MAP_MODE[op.mode], 0, op.size));
      await m.maps.get(op.buf);
      return null;
    }

    // :19 wgpuBufferGetConstMappedRange(buf, 0, size). The JS spelling is
    // `getMappedRange` and it is NOT a promise.
    //
    // THE RANGE IS COPIED, NOT KEPT. :142-143 free the staging buffer right after,
    // and :197's `destroy()` DETACHES its ArrayBuffer, so a reference handed back
    // to the caller is dead by the time the walk ends -- MEASURED: reading it
    // afterwards threw "Cannot perform Construct on a detached ArrayBuffer", and
    // `RANGE 0 bytes` said why. `WebGPUProgram.__call__` at :141 reads the two
    // timestamps INSIDE the call and returns a float, so copying here is also the
    // faithful shape: what leaves `__call__` is a NUMBER, not a view.
    case "MappedRange": {
      const range = buf(op.buf).getMappedRange(0, op.size);
      m.range = range.slice(0);
      return m.range;
    }

    // :144 wgpuQuerySetDestroy(query_set). `GPUSupportedQuerySet` has no
    // `destroy`, so dropping the reference is again all there is -- and the
    // arm says so instead of calling a method that does not exist.
    case "DestroyQuerySet": return null;

    // :197 wgpuBufferDestroy(buf). THIS one is real and is NOT a release: a
    // WebGPU buffer's memory is not reclaimed until it is destroyed. There is no
    // UNMAP arm because the port emits none for these frees -- `Cs.free` passes
    // MAP_UNMAPPED at both, so :196's guard is False and `wg_wait_tail` shows no
    // `CALL_UNMAP`.
    case "DestroyBuffer": buf(op.buf).destroy(); return null;

    default: throw new Error("webgpu_call: unhandled op " + JSON.stringify(op));
  }
}

// The `U32` list `webgpu_call.bend` builds IS the byte pattern, low byte first:
// `dev.uniform_bytes` is `val.to_bytes(4, "little", signed=val < 0)` (:204).
const u8 = (bytes) => Uint8Array.from(bytes);

// ===========================================================================
// RUN. Walks the steps `Cs.order` returns -- already in step order -- and hands
// each to `perform`. It returns what was performed and throws naming the op it
// stopped on, so a partial run is legible rather than silent.
//
// THE RECEIVER CHAIN, which is the whole of what `gpu` is for, and it has THREE
// states rather than one:
//
//   `Instance`       -> `navigator.gpu`. The op exists to keep the trace entry
//                       accounted for; there is no create call in the JS API.
//   `RequestAdapter` -> the ADAPTER, whose own arms `ReadFeatures`,
//                       `FreeFeatures` and `ReadLimits` read. So `gpu` is the
//                       adapter from :169 until :184.
//   `RequestDevice`  -> the DEVICE. Every op from :185 on is made on it, which
//                       is why each of those arms may assume a device, and why
//                       this is the ONE op `run` treats specially.
//
// `GetQueue` does NOT change the receiver: in JS the queue is a property of the
// device rather than a separately-requested object. Every other op returns `null`
// or an object the SEAM slots by handle, so nothing else is threaded.
// ===========================================================================
export async function run(cs, owned = new Map()) {
  return walk([cs], owned);
}

// THE WHOLE THING, and the reason `run` takes ONE `Cs`. `webgpu_call.bend` splits
// the port the way ops_webgpu.py splits it -- `dev.init` is :166-190 and
// `prog.call` is :53-147 -- so a real run is the device init FOLLOWED BY the
// call, and the second is meaningless without the first: `fx` alone begins at
// `PushScope` (:62) and has no device to push a scope onto. MEASURED: running
// `fx` by itself stopped at step 0 of 49 with "Cannot read properties of null
// (reading 'pushErrorScope')". That is the port telling the truth about itself,
// and it is why `program` exists rather than `run` being quietly fixed to
// invent a device.
//
// `Cs.init`'s ops are NOT re-derived here: both lists come out of `Cs.order`, the
// same def the gate checks, so the driver cannot disagree with the port about
// what order the init makes its calls in.
export async function program(backend, feats, cs, owned = new Map()) {
  return walk([bend("Cs.init")(backend, feats), cs], owned);
}

async function walk(css, owned) {
  const m = fresh(owned);
  const steps = css.flatMap((c) => toJS(bend("Cs.order")(c)));
  const seen = [];
  let gpu = null;
  for (const s of steps) {
    try {
      const r = await perform(s.op, m, gpu);
      // TWO ops change the receiver, in this order: :169 hands over the ADAPTER
      // (which :172, :175 and :180 then read) and :184 hands over the DEVICE
      // (which every op from :185 on is made on). MEASURED: arming only :184 made
      // the walk stop at step 2 of 57 on `ReadFeatures`, because the adapter arms
      // had no adapter -- `gpu` was still null.
      if (s.op.$ === "RequestAdapter" || s.op.$ === "RequestDevice") gpu = r;
      // FILE THE RESULT UNDER ITS SLOT. `webgpu_call.bend` mints a `U32` per
      // created object and hands it to the driver, and this is the ONLY place that
      // does so -- an arm returning an object is not enough, because the next op
      // reaches it BY HANDLE and not by return value. MEASURED: leaving it out
      // stopped the walk at step 15 of 57 with "unbound slot 1", which is
      // `BindGroupLayout`'s: the create had happened and nothing had kept it.
      // `DestroyBuffer` on the staging buffer (:197) comes AFTER `MappedRange`,
      // so `getMappedRange`'s ArrayBuffer is still live here -- but a destroyed
      // buffer's range is not, which is why `r.range` is captured at the arm and
      // not re-read at the end. MEASURED: reading it back off the machine after
      // the walk gave `null`, because `Release` had already dropped the slot.
      if (s.op.$ === "MappedRange") m.range = r;
      if (r !== null && r !== undefined && typeof s.op.slot === "number") m.slots.set(s.op.slot, r);
      seen.push(s.op.$);
    } catch (e) {
      throw new Error(`webgpu_call: stopped at step ${seen.length}/${steps.length} (${s.op.$}): ${e.message}`);
    }
  }
  return { performed: seen, steps: steps.length, range: m.range, machine: m };
}

export { M, u8, f32, INFINITY, SHADER_STAGE, BINDING_TYPE, MAP_MODE, QUERY_TYPE,
         POWER_PREF, FEATURE, UNIFORM_USAGE, perform, fresh };
// `M` IS HERE because the pure half is the point: a caller that wants the ops and
// nothing else imports this module and reads `default.M`, and never touches
// `navigator.gpu`. `webgpu_call.bend` alone is checkable with no GPU at all.
export default { run, program, perform, walk, M };