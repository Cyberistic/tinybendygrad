// examples/webgpu/mnist/mnist-webgpu.js -- replay a tinygrad kernel-launch trace
// on a WebGPU device.
//
// THE ABI IS NOT INVENTED HERE. It is tinygrad/runtime/ops_webgpu.py's
// WebGPUProgram.__call__ (:69-124), read off the Python and reproduced:
//
//   binding 0            var<uniform> INFINITY: f32   -- bound to +Infinity
//   bindings 1..N        var<storage,read_write>      -- in `bufs` order
//   bindings N+1..       one uniform each             -- the `vals` scalars
//   dispatch             dispatchWorkgroups(*global_size)
//
// and the WGSL itself is tinygrad's: it was produced by
// tinygrad/renderer/wgsl.py WGSLRenderer from the SAME Ops.PROGRAM the CPU
// executed. So this file only decides what the Python decides -- which buffer is
// bound where, and how big the grid is.
//
// WHAT THIS IS NOT: it is not the WebGPU device. tinybendygrad/runtime/ops_webgpu.bend
// is where the call layer is being ported, and this file is the smallest thing
// that makes the browser page real while that port is in flight. It is ~70 lines
// of buffer/bind-group/pipeline plumbing and contains no arithmetic at all: every
// number the page reports came out of a WGSL kernel tinygrad wrote.

const USAGE = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST;

/** Copy `bufs` into fresh mappable buffers and read them back as u32 words. */
async function readAll(device, encoder, bufs) {
  const names = Object.keys(bufs);
  const staged = names.map((n) => {
    const b = bufs[n];
    const rb = device.createBuffer({ size: b.size, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
    encoder.copyBufferToBuffer(b, 0, rb, 0, b.size);
    return rb;
  });
  device.queue.submit([encoder.finish()]);
  const out = {};
  for (const [i, name] of names.entries()) {
    await staged[i].mapAsync(GPUMapMode.READ);
    out[name] = new Uint32Array(staged[i].getMappedRange().slice(0));
    staged[i].unmap();
    staged[i].destroy();
  }
  return out;
}

const b64ToU32 = (b64) => {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new Uint32Array(bytes.buffer);
};

/**
 * ONE explicit bind group layout per (kernel, buffer count), spelled the way
 * tinygrad/runtime/ops_webgpu.py:74-89 spells it: binding 0 is a uniform, then
 * one storage per buffer, then one uniform per `vals` scalar.
 *
 * Two things about that are measured, and both cost a silent zero:
 *
 *  - The layout must declare EVERY binding that is offered. A layout declaring
 *    only binding 0 makes every createBindGroup carrying bindings 1..N a
 *    validation error, and WebGPU DROPS the submit without throwing: all 17
 *    launches write nothing and every buffer reads back as zeros.
 *  - `layout: "auto"` is not an alternative. It REFLECTS the shader, so a kernel
 *    that declares but never reads `var<uniform> INFINITY` gets a layout with no
 *    binding 0, and offering one is "binding index 0 not present in the bind
 *    group layout". The shader TEXT cannot decide this either: `@binding(0)` is
 *    in the text of every one of these kernels, used or not.
 *
 * The explicit layout also has to go through createPipelineLayout rather than
 * `layout: "auto"`, which is why the pipeline is built over `pipelineLayoutOf`.
 * Extra layout entries the shader does not use are legal; missing ones are not.
 */
function layoutFor(device, nStorage, nVals) {
  const entries = [{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } }];
  for (let i = 0; i < nStorage; i++) entries.push({ binding: 1 + i, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } });
  for (let i = 0; i < nVals; i++) entries.push({ binding: 1 + nStorage + i, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } });
  return device.createBindGroupLayout({ entries });
}

/**
 * Every buffer in the trace, created empty. Contents arrive per launch instead:
 * `k.in` holds CPython's bytes for exactly those buffers that no EARLIER launch
 * wrote, so the weights and the input image are supplied once and everything the
 * trace computes stays computed on the GPU rather than re-uploaded.
 */
function createBuffers(device, buffers) {
  const out = {};
  for (const [name, spec] of Object.entries(buffers)) {
    out[name] = device.createBuffer({
      label: name, size: spec.size * 4, usage: USAGE,
    });
  }
  return out;
}

/**
 * Run every launch in order and return the final logits as u32 bit patterns.
 * `outName` is the buffer the trace's last launch writes, named by the caller so
 * this file does not have to guess which binding is the result.
 *
 * `snapshot: true` additionally reads every buffer back after EVERY launch and
 * returns the per-launch states. That is how "0/10 logits right" becomes "kernel
 * 12 is the first one that differs", which is the only useful thing to look at.
 */
export async function runForward(device, net, outName, { snapshot = false } = {}) {
  const gpuBufs = createBuffers(device, net.buffers);
  // ops_webgpu.py:97 -- bg_entry(0, float('inf')).
  const infinity = device.createBuffer({ size: 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(infinity, 0, new Float32Array([Infinity]));

  // One pipeline per DISTINCT kernel, not per launch: 17 launches share 12
  // shaders, and createComputePipeline is the expensive call.
  // Pipelines are cached by the WGSL TEXT, never by the entry name.
  //
  // Measured: tinygrad's entry names are NOT unique. `E_8_4` names BOTH the
  // running_mean fill (writes 0.0) and the running_var fill (writes 1.0) -- the
  // name encodes the shape, not the constant. A cache keyed by name compiles the
  // first and dispatches it for the second, and the ladder catches it as
  // "launch 1 E_8_4: b1[0] got=1065353216 want=0" with nothing else wrong.
  const modules = new Map();
  for (const k of net.kernels) {
    if (!k.wgsl) throw new Error(`kernel ${k.entry} has no WGSL: ${k.wgslError}`);
    if (modules.has(k.wgsl)) continue;
    const mod = device.createShaderModule({ code: k.wgsl, label: `${k.entry}#${modules.size}` });
    // An invalid ShaderModule only says so at CreateComputePipeline time, and
    // then only "invalid due to a previous error". getCompilationInfo is where
    // the line and the reason actually are.
    const info = await mod.getCompilationInfo();
    const errs = info.messages.filter((m) => m.type === "error");
    if (errs.length) {
      throw new Error(`WGSL rejected for ${k.entry}: ` +
        errs.map((m) => `line ${m.lineNum}:${m.linePos} ${m.message.split("\n")[0]}`).join(" | "));
    }
    modules.set(k.wgsl, mod);
  }
  const pipelines = new Map();
  const pipelineOf = (k, nStorage, nVals) => {
    if (!pipelines.has(k.wgsl)) {
      const bgl = layoutFor(device, nStorage, nVals);
      pipelines.set(k.wgsl, device.createComputePipeline({
        label: k.entry,
        layout: device.createPipelineLayout({ bindGroupLayouts: [bgl] }),
        compute: { module: modules.get(k.wgsl), entryPoint: k.entry },
      }));
    }
    return pipelines.get(k.wgsl);
  };

  device.pushErrorScope("validation");

  const snaps = [];
  let dispatched = 0;
  for (const k of net.kernels) {
    // CPython's bytes for the buffers this launch READS that nothing has written
    // yet. Everything else the launch touches already holds what the previous
    // launches computed, so the chain really is computed on the GPU.
    for (const [name, b64] of Object.entries(k.in ?? {})) {
      device.queue.writeBuffer(gpuBufs[name], 0, b64ToU32(b64));
    }
    // ops_webgpu.py:97 -- binding 0 is the INFINITY uniform, bindings 1..N are the
    // storage buffers in `bufs` order, and the `vals` scalars follow as uniforms.
    const vals = (k.vals ?? []).map((v) => {
      const u = device.createBuffer({ size: 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      device.queue.writeBuffer(u, 0, new Uint32Array([v >>> 0]));
      return u;
    });
    const entries = [{ binding: 0, resource: { buffer: infinity } }];
    k.bufs.forEach((name, i) => entries.push({ binding: i + 1, resource: { buffer: gpuBufs[name] } }));
    vals.forEach((u, i) => entries.push({ binding: k.bufs.length + 1 + i, resource: { buffer: u } }));

    const pipeline = pipelineOf(k, k.bufs.length, vals.length);
    const bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries });
    const encoder = device.createCommandEncoder({ label: `enc${dispatched}` });
    const pass = encoder.beginComputePass({ label: `${k.entry}#${dispatched}` });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(...k.global);
    pass.end();

    if (snapshot) {
      const bufs = {};
      for (const n of k.bufs) bufs[n] = gpuBufs[n];
      snaps.push({ launch: dispatched, entry: k.entry, state: await readAll(device, encoder, bufs) });
    } else {
      device.queue.submit([encoder.finish()]);
    }
    for (const u of vals) u.destroy();
    dispatched++;
  }

  const encoder = device.createCommandEncoder({ label: "out" });
  const words = (await readAll(device, encoder, { [outName]: gpuBufs[outName] }))[outName];
  const validationError = await device.popErrorScope();
  if (validationError) throw new Error(`WebGPU validation error: ${validationError.message}`);
  return { words, launches: dispatched, snaps };
}

/** The adapter question, asked the way the page must answer it. */
export async function getDevice() {
  if (!navigator.gpu) return { ok: false, why: "navigator.gpu is undefined -- not a secure context, or no WebGPU build" };
  let adapter = null;
  try {
    adapter = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
    if (!adapter) adapter = await navigator.gpu.requestAdapter();
  } catch (e) {
    return { ok: false, why: `requestAdapter threw: ${e}` };
  }
  if (!adapter) return { ok: false, why: "requestAdapter() returned null -- no adapter, no software fallback" };
  const device = await adapter.requestDevice();
  return { ok: true, adapter, device, info: adapter.info ?? {} };
}
