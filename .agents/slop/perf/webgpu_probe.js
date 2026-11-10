// webgpu_probe.js -- IS THERE A WEBGPU ADAPTER IN THIS TREE? AND DOES IT RUN A SHADER?
//
//   bun .agents/slop/perf/webgpu_probe.js
//
// IT LAUNCHES ITS OWN HEADLESS CHROME on a private debugging port and profile, so it
// neither touches the browser the chrome-devtools MCP owns nor depends on that MCP being
// connected (IT TIMED OUT when asked). It then evaluates ONE script in the page:
//
//   1 `navigator.gpu` exists?
//   2 `requestAdapter()` returns a device?
//   3 compile the SAME trivial WGSL twice, run both on the same buffers, and time each.
//
// AND THE ANSWER IS RECORDED EITHER WAY. If there is no adapter, THAT is the evidence
// for stage 1 -- a refusal, not an inference. There is no path in this file from "no
// driver" to "therefore parity".
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9333;
const profile = mkdtempSync(join(tmpdir(), "wgsl-probe-"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// **A `data:` URL IS NOT A SECURE CONTEXT, SO `navigator.gpu` IS UNDEFINED THERE** --
// MEASURED, the first version of this probe answered "navigator.gpu absent" for that
// reason and not because WebGPU is missing. `http://127.0.0.1` IS a secure context, so the
// page is SERVED, not inlined.
const page = `<!doctype html><meta charset=utf8><title>wgsl</title><body>probe`;
const server = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response(page, { headers: { "content-type": "text/html" } }) });
const ORIGIN = `http://127.0.0.1:${server.port}/`;

const WGSL = `
@group(0) @binding(0) var<storage, read_write> out: array<f32>;
@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  out[i] = fma(out[i], 2.0, 1.0);
}`;

const probe = `
(async () => {
  const r = { href: location.href, secure: isSecureContext, adapter_api: !!navigator.gpu,
              adapter: false, device: false, err: null, ms: [] };
  if (!navigator.gpu) { r.err = "navigator.gpu absent"; return r; }
  let a = null;
  try { a = await navigator.gpu.requestAdapter(); } catch (e) { r.err = "requestAdapter threw: " + e.message; return r; }
  if (!a) { r.err = "requestAdapter answered null"; return r; }
  r.adapter = true;
  r.adapter_info = a.info ? { vendor: a.info.vendor, architecture: a.info.architecture, description: a.info.description } : null;
  const dev = await a.requestDevice();
  r.device = !!dev;
  const N = 1024, BYTES = N * 4;
  const buf = dev.createBuffer({ size: BYTES, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
  const read = dev.createBuffer({ size: BYTES, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
  const bgl = dev.createBindGroupLayout({ entries: [{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } }] });
  const layout = dev.createPipelineLayout({ bindGroupLayouts: [bgl] });
  const bg = dev.createBindGroup({ layout: bgl, entries: [{ binding: 0, resource: { buffer: buf } }] });
  const mods = [];
  for (const src of [${JSON.stringify(WGSL)}, ${JSON.stringify(WGSL)}]) {
    const m = dev.createShaderModule({ code: src });
    const info = await m.getCompilationInfo();
    if (info.messages.length) { r.err = "compile: " + info.messages.map(x => x.message).join("; "); return r; }
    mods.push(await dev.createComputePipelineAsync({ layout, compute: { module: m, entryPoint: "main" } }));
  }
  const zeros = new Float32Array(N);
  const times = [];
  for (const pipe of mods) {
    // warmup
    for (let k = 0; k < 3; k++) {
      dev.queue.writeBuffer(buf, 0, zeros);
      const enc = dev.createCommandEncoder();
      const p = enc.beginComputePass(); p.setPipeline(pipe); p.setBindGroup(0, bg); p.dispatchWorkgroups(N / 64); p.end();
      dev.queue.submit([enc.finish()]);
    }
    await dev.queue.onSubmittedWorkDone();
    times.push(null);
  }
  // timed: each pipeline gets the same work, alternating runs
  for (let round = 0; round < 2; round++) {
    for (let i = 0; i < 2; i++) {
      dev.queue.writeBuffer(buf, 0, zeros);
      const enc = dev.createCommandEncoder();
      const p = enc.beginComputePass(); p.setPipeline(mods[i]); p.setBindGroup(0, bg); p.dispatchWorkgroups(N / 64); p.end();
      const t0 = performance.now();
      dev.queue.submit([enc.finish()]);
      await dev.queue.onSubmittedWorkDone();
      const t1 = performance.now();
      times[i] = times[i] === null ? (t1 - t0) : Math.min(times[i], t1 - t0);
    }
  }
  // correctness: 1024 lanes, each out[i] = out[i]*2 + 1 from 0 -> 1
  const enc = dev.createCommandEncoder();
  enc.copyBufferToBuffer(buf, 0, read, 0, BYTES);
  dev.queue.submit([enc.finish()]);
  await read.mapAsync(GPUMapMode.READ);
  const got = new Float32Array(read.getMappedRange().slice(0));
  r.ms = times;
  r.sample = got[0];
  r.all_ones = got.every((v) => v === 1.0);
  read.unmap();
  return r;
})()`;

const chrome = spawn(CHROME, [
  ...(process.env.HEADFUL ? [] : ["--headless=new"]), `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--enable-unsafe-webgpu",
  "--enable-features=Vulkan,WebGPU", "--disable-gpu-sandbox",
  ORIGIN,
], { stdio: "ignore" });

let out = null;
for (let i = 0; i < 60 && out === null; i++) {
  await sleep(500);
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
    const list = await r.json();
    const t = list.find((x) => x.type === "page");
    if (!t) continue;
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    const reply = await new Promise((res) => {
      ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id === 1) res(m); };
      ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate",
        params: { expression: probe, awaitPromise: true, returnByValue: true, timeout: 120000 } }));
    });
    // **WAIT FOR THE PAGE, OR THE PROBE LIES.** MEASURED: the same file answered
    // "navigator.gpu absent" on one run and `metal-3` on the next, because the evaluate
    // sometimes ran before the tab had committed the URL -- and "no adapter" is exactly the
    // answer a wrong run would produce. A refusal that a race can fabricate is not evidence,
    // so this polls the ORIGIN first and only then asks the question.
    for (let k = 0; k < 40; k++) {
      const here = await new Promise((res) => {
        ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id === 2) res(m.result?.result?.value); };
        ws.send(JSON.stringify({ id: 2, method: "Runtime.evaluate",
          params: { expression: "JSON.stringify([location.href, typeof navigator.gpu])", returnByValue: true } }));
      });
      if (typeof here === "string" && JSON.parse(here)[0].startsWith("http://127.0.0.1")) {
        if (JSON.parse(here)[1] === "object") break;
        await sleep(250);
        continue;
      }
      await sleep(250);
    }
    ws.close();
    out = reply.result?.result?.value ?? { err: JSON.stringify(reply.result?.exceptionDetails ?? reply) };
  } catch (e) { /* not up yet */ }
}
chrome.kill("SIGKILL");
server.stop(true);
console.log(JSON.stringify(out, null, 2));
writeFileSync(join(process.cwd(), ".agents/slop/perf/webgpu-probe.json"), JSON.stringify(out, null, 2) + "\n");
