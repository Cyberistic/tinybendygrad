// IS THERE A DEVICE HERE THAT COMPUTES?
//
// `navigator.gpu.requestAdapter()` returning an adapter with a vendor is NOT a
// device that computes -- it is a name. So this probe goes all the way to a
// READBACK: it writes 8 known f32s to a storage buffer, runs ONE real WGSL
// compute shader that squares and adds them into a second buffer, maps that
// buffer, and prints the 8 floats it got back. `compute_back` is the number that
// matters; everything before it is a name.
//
// Three things had to be true simultaneously and all three were found by
// measurement, not by reading a spec:
//   1. a SECURE CONTEXT -- `navigator.gpu` is `undefined` on about:blank even in
//      Chrome 154, and defined on http://127.0.0.1 (cf. xd2/serve.mjs);
//   2. CHROME-STABLE, not chrome-for-testing -- every chrome-for-testing flag set
//      in xd2/gpu_probe.mjs reports `"gpu": false`;
//   3. an `http://` origin, so this file serves itself.
// The measured table of all seven (binary, flag) cases is
// `.agents/slop/xd2/gpu_probe.txt`; this file re-measures the one that works and
// then proves it computes.
//
// RUN:  node .agents/slop/e2e_gpu_probe.mjs        # writes e2e-gpu-probe.txt
// Exit: 0 = adapter + device + a verified readback. 1 = no, with the reason.

import { writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { launch, shutdown, Session, CHROME_BINARIES } from "./xd2/cdp.mjs";
import { serve } from "./xd2/serve.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

// The one flag set measured to work: chrome-stable, headless=new. `--headless=new`
// alone; `--enable-unsafe-webgpu` is NOT needed on the stable binary.
const CASES = [
  ["chrome-stable  headless=new", "chrome-stable", ["--headless=new"]],
  ["chrome-stable  headed", "chrome-stable", []],
  ["chrome-for-testing  headless=new + angle=metal", "chrome-for-testing",
    ["--headless=new", "--use-angle=metal", "--enable-unsafe-webgpu"]],
];

// 8 inputs, each squared, plus the neighbour to its right, in workgroup 0.
const N = 8;
const INPUT = [1, 2, 3, 4, 5, 6, 7, 8];
// The shader wraps: `nxt = select(0u, i + 1u, i + 1u < n)`, so the last element
// adds INPUT[0], not 0. The first version of this file expected `?? 0` here and
// disagreed with a correct device on 7 of 8 -- a hand-written expectation that
// was wrong about the thing it was checking. The wrap is now in both.
const EXPECT = INPUT.map((v, i) => v * v + INPUT[(i + 1) % N]);

const PROBE = `
  const out = { secureContext: self.isSecureContext, gpu: !!navigator.gpu };
  if (!navigator.gpu) return out;
  let a = null, adapterErr = null;
  try { a = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" }); }
  catch (e) { adapterErr = String(e); }
  if (!a) { try { a = await navigator.gpu.requestAdapter(); } catch (e) { adapterErr = String(e); } }
  if (!a) return { ...out, adapter: false, adapterErr };
  const i = a.info ?? {};
  out.adapter = true;
  out.vendor = i.vendor ?? null;
  out.architecture = i.architecture ?? null;

  let device = null, deviceErr = null;
  try { device = await a.requestDevice(); } catch (e) { deviceErr = String(e); }
  out.deviceOk = !!device;
  out.deviceErr = deviceErr;
  if (!device) return out;

  // ---- THE PART THAT IS NOT A NAME: a dispatched kernel with a readback ----
  const WGSL = \`
    @group(0) @binding(0) var<storage, read>       in_buf  : array<f32>;
    @group(0) @binding(1) var<storage, read_write> out_buf : array<f32>;
    @compute @workgroup_size(${N})
    fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
      let i = gid.x;
      let n = ${N}u;
      if (i >= n) { return; }
      let nxt = select(0u, i + 1u, i + 1u < n);
      out_buf[i] = in_buf[i] * in_buf[i] + in_buf[nxt];
    }\`;
  device.pushErrorScope("validation");
  const NBYTES = ${N} * 4;
  const src = device.createBuffer({ size: NBYTES, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(src, 0, new Float32Array(${JSON.stringify(INPUT)}));

  const shader = device.createShaderModule({ code: WGSL });
  const info = await shader.getCompilationInfo();
  out.wgslErrors = info.messages.filter((m) => m.type === "error").map((m) => m.message);

  const pipe = device.createComputePipeline({ layout: "auto", compute: { module: shader, entryPoint: "main" } });
  const dst = device.createBuffer({ size: NBYTES, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
  const read = device.createBuffer({ size: NBYTES, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });

  const bg = device.createBindGroup({ layout: pipe.getBindGroupLayout(0), entries: [
    { binding: 0, resource: { buffer: src } }, { binding: 1, resource: { buffer: dst } } ] });

  const enc = device.createCommandEncoder();
  const pass = enc.beginComputePass();
  pass.setPipeline(pipe); pass.setBindGroup(0, bg); pass.dispatchWorkgroups(1); pass.end();
  enc.copyBufferToBuffer(dst, 0, read, 0, NBYTES);
  device.queue.submit([enc.finish()]);
  await read.mapAsync(GPUMapMode.READ);
  out.compute_back = [...new Float32Array(read.getMappedRange())];
  read.unmap();

  const scoped = await device.popErrorScope();
  out.validationError = scoped ? scoped.message : null;
  return out;
`;

const root = join(HERE, "e2e-probe-root");
await mkdir(root, { recursive: true });
const { writeFile: wf } = await import("node:fs/promises");
await wf(join(root, "index.html"), `<!doctype html><meta charset=utf-8><title>e2e gpu probe</title><body>probe`);

const srv = await serve(root);
const out = [];
let anyWorked = false;

for (const [label, bin, flags] of CASES) {
  let h, text;
  try {
    h = await launch(CHROME_BINARIES[bin], flags, srv.url + "/index.html");
    const s = await Session.openPage(h.port, { url: srv.url + "/index.html" });
    const r = await s.eval(PROBE, { timeoutMs: 90000 });
    s.close();
    const got = r.compute_back ?? null;
    const want = EXPECT;
    // Bit-exact: every operand here is a small integer and every operation is a
    // single f32 multiply or add, so there is nothing for a FMA to change.
    const ok = Array.isArray(got) && got.length === want.length && got.every((v, k) => Object.is(v, want[k]));
    text = JSON.stringify({ ...r, compute_matches_expectation: ok, expected: want }, null, 2);
    if (ok) anyWorked = true;
  } catch (e) {
    text = `LAUNCH/PROBE FAILED: ${String(e).slice(0, 400)}`;
  } finally {
    if (h) await shutdown(h);
  }
  console.log(`\n### ${label}\n${text}`);
  out.push(`### ${label}\n${text}`);
}

await srv.close();
await writeFile(join(HERE, "e2e-gpu-probe.txt"), out.join("\n\n") + "\n");
console.log(`\n=== a device that computes: ${anyWorked ? "YES" : "NO"} ===`);
process.exit(anyWorked ? 0 : 1);
