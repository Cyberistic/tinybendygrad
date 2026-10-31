// stage1_time.js -- RUN THE WGSL tinygrad EMITTED, IN A REAL WEBGPU DRIVER, AND TIME IT.
//
//   bun .agents/slop/perf/stage1_time.js
//
// IT READS `.agents/slop/perf/stage1/kernel.json` (written by stage1_webgpu.py: the WGSL
// text, the exact input buffers, the dispatch, the expected output), serves a page from
// 127.0.0.1 -- a `data:` URL IS NOT A SECURE CONTEXT, so `navigator.gpu` is undefined there
// -- launches its own headless Chrome, and evaluates one script that compiles the shader,
// binds the buffers, dispatches it, WAITS FOR THE GPU, and reads the result back.
//
// **AND THE WAIT IS THE MEASUREMENT.** `queue.submit` returns before the work is done, so a
// timer around it measures submit latency -- that is exactly the defect stage2_metal.py had
// (0.01 ms readings). Here `await queue.onSubmittedWorkDone()` sits INSIDE the timed region,
// and the reported number is the minimum of N runs after warmups.
//
// ⇒ AND THE CORRECTNESS CHECK IS THE POINT OF USING THE REAL BUFFERS: the shader's output is
// compared, element by element, against the float32 result numpy computed. A timing of the
// wrong answer is not a timing.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

const ROOT = process.cwd();
const K = JSON.parse(readFileSync(join(ROOT, ".agents/slop/perf/stage1/kernel.json"), "utf8"));
const N = Number(process.env.STAGE1_ITERS || 3);
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9334;
const profile = mkdtempSync(join(tmpdir(), "wgsl-stage1-"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const page = `<!doctype html><meta charset=utf8><title>stage1</title><body>stage1`;
const server = Bun.serve({ port: 0, hostname: "127.0.0.1",
  fetch: () => new Response(page, { headers: { "content-type": "text/html" } }) });
const ORIGIN = `http://127.0.0.1:${server.port}/`;

const script = `
(async () => {
  const K = ${JSON.stringify(K)};
  const N = ${N};
  const r = { adapter: false, device: false, sha256: null, err: null, ms: [], max_abs_diff: null, ok: false };
  if (!navigator.gpu) { r.err = "navigator.gpu absent"; return r; }
  const a = await navigator.gpu.requestAdapter();
  if (!a) { r.err = "requestAdapter answered null"; return r; }
  r.adapter = true;
  r.arch = a.info?.architecture ?? null;
  const dev = await a.requestDevice();
  r.device = true;
  const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

  const mod = dev.createShaderModule({ code: K.wgsl });
  const info = await mod.getCompilationInfo();
  if (info.messages.length) { r.err = "compile: " + info.messages.map((m) => m.lineNum + ":" + m.message).join("; "); return r; }
  r.sha256 = null;

  // binding 0 is the f32 uniform the prologue declares; 1.. are the storage buffers
  const entries = [{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } }];
  const bufs = [];
  for (let i = 0; i < K.bufs.length; i++) {
    const b = dev.createBuffer({ size: K.nbytes[i], usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
    dev.queue.writeBuffer(b, 0, b64(K.bufs[i]));
    bufs.push(b);
    entries.push({ binding: i + 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } });
  }
  const uni = dev.createBuffer({ size: 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  dev.queue.writeBuffer(uni, 0, new Float32Array([Infinity]));

  const bgl = dev.createBindGroupLayout({ entries });
  const layout = dev.createPipelineLayout({ bindGroupLayouts: [bgl] });
  const bg = dev.createBindGroup({ layout: bgl,
    entries: [{ binding: 0, resource: { buffer: uni } },
              ...bufs.map((b, i) => ({ binding: i + 1, resource: { buffer: b } }))] });
  const pipe = await dev.createComputePipelineAsync({ layout, compute: { module: mod, entryPoint: K.name } });

  const read = dev.createBuffer({ size: K.nbytes[0], usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
  const dispatch = () => {
    const enc = dev.createCommandEncoder();
    const p = enc.beginComputePass();
    p.setPipeline(pipe); p.setBindGroup(0, bg);
    p.dispatchWorkgroups(K.dispatch[0], K.dispatch[1], K.dispatch[2]);
    p.end();
    return enc.finish();
  };
  const zero = new Uint8Array(K.nbytes[0]);
  for (let i = 0; i < 3; i++) {           // warmup: compile + first runs
    dev.queue.writeBuffer(bufs[0], 0, zero);
    dev.queue.submit([dispatch()]);
    await dev.queue.onSubmittedWorkDone();
  }
  const ms = [];
  for (let i = 0; i < N; i++) {
    dev.queue.writeBuffer(bufs[0], 0, zero);
    const t0 = performance.now();
    dev.queue.submit([dispatch()]);
    await dev.queue.onSubmittedWorkDone();   // INSIDE the timed region
    ms.push(performance.now() - t0);
  }
  // read the output of the LAST run and compare against numpy
  const enc = dev.createCommandEncoder();
  enc.copyBufferToBuffer(bufs[0], 0, read, 0, K.nbytes[0]);
  dev.queue.submit([enc.finish()]);
  await read.mapAsync(GPUMapMode.READ);
  const got = new Float32Array(read.getMappedRange().slice(0));
  const diff = (b) => {
    const want = new Float32Array(b64(b).buffer);
    let w = 0;
    for (let i = 0; i < got.length; i++) w = Math.max(w, Math.abs(got[i] - want[i]));
    return w;
  };
  r.diff_ab_plus_a = diff(K.want_a);
  r.diff_ab_plus_b = diff(K.want_b);
  r.ms = ms.sort((x, y) => x - y);
  r.max_abs_diff = Math.min(r.diff_ab_plus_a, r.diff_ab_plus_b);
  r.matched = r.diff_ab_plus_a < 1e-5 ? "(a*b)+a" : r.diff_ab_plus_b < 1e-5 ? "(a*b)+b" : "NEITHER";
  r.ok = r.matched !== "NEITHER";
  r.sha256 = K.sha256;
  read.unmap();
  return r;
})()`;

const chrome = spawn(CHROME, [
  "--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--enable-unsafe-webgpu",
  "--enable-features=Vulkan,WebGPU", "--disable-gpu-sandbox", ORIGIN,
], { stdio: "ignore" });

let out = null;
for (let i = 0; i < 60 && out === null; i++) {
  await sleep(500);
  try {
    const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
    const t = list.find((x) => x.type === "page");
    if (!t) continue;
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    // WAIT FOR THE PAGE: a race here once made the same probe answer "navigator.gpu absent".
    for (let k = 0; k < 40; k++) {
      const here = await new Promise((res) => {
        ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id === 2) res(m.result?.result?.value); };
        ws.send(JSON.stringify({ id: 2, method: "Runtime.evaluate",
          params: { expression: "JSON.stringify([location.href, typeof navigator.gpu])", returnByValue: true } }));
      });
      if (typeof here === "string") {
        const [href, gpu] = JSON.parse(here);
        if (href.startsWith("http://127.0.0.1") && gpu === "object") break;
      }
      await sleep(250);
    }
    const reply = await new Promise((res) => {
      ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id === 1) res(m); };
      ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate",
        params: { expression: script, awaitPromise: true, returnByValue: true, timeout: 180000 } }));
    });
    ws.close();
    out = reply.result?.result?.value ?? { err: JSON.stringify(reply.result?.exceptionDetails ?? reply).slice(0, 600) };
  } catch { /* not up yet */ }
}
if (out === null) out = { err: "no reply from the page within the wait" };
chrome.kill("SIGKILL");
server.stop(true);

const sha = createHash("sha256").update(JSON.stringify(out)).digest("hex").slice(0, 16);
const rows = [
  "# stage1-webgpu.rows -- .agents/slop/perf/stage1_time.js + stage1_webgpu.py",
  `# driver: headless Chrome, adapter ${out?.arch ?? "?"}, DEV=METAL NOOPT=1 uops rendered by WGSLRenderer`,
  `# iters=${N} (min), warmups=3, timed around submit+onSubmittedWorkDone`,
  `# bend_side=absent  (wgsl.bend has NO uop->text walk: its render_kernel takes BODY STRINGS)`,
  "# kernel|sha256_python|sha256_bend|identical|bytes|python_ms_min|max_abs_diff|matched|ok",
  `${K.name}|${out?.sha256 ?? "-"}|-|python-only|${K.bytes}|${(out?.ms?.[0] ?? NaN).toFixed(4)}|` +
    `${(out?.max_abs_diff ?? NaN).toExponential(2)}|${out?.matched ?? "-"}|${out?.ok ? "yes" : "no"}`,
  `# probe_sha=${sha} err=${out?.err ?? "-"}`,
];
writeFileSync(join(ROOT, ".agents/slop/perf/stage1-webgpu.rows"), rows.join("\n") + "\n");
console.log(rows.join("\n"));
