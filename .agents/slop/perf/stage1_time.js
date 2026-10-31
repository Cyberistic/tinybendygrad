// stage1_time.js -- COMPILE AND TIME **BOTH** SHADERS IN A REAL WEBGPU DRIVER.
//
//   bun .agents/slop/perf/stage1_time.js
//
// IT READS `.agents/slop/perf/stage1/kernel.json` (written by stage1_webgpu.py: the WGSL
// CPython's `WGSLRenderer` emitted, the WGSL the PORT's own walk emitted, the exact input
// buffers, the dispatch, the expected output), serves a page from 127.0.0.1 -- a `data:` URL
// IS NOT A SECURE CONTEXT, so `navigator.gpu` is undefined there -- launches its own headless
// Chrome, and evaluates one script that compiles BOTH modules, binds the SAME buffers, runs
// each, WAITS FOR THE GPU, and reads each result back.
//
// **AND THE WAIT IS THE MEASUREMENT.** `queue.submit` returns before the work is done, so a
// timer around it measures submit latency -- that is exactly the defect stage2_metal.py had
// (0.01 ms readings). Here `await queue.onSubmittedWorkDone()` sits INSIDE the timed region,
// and each number is the minimum of N runs after 3 warmups.
//
// **AND BOTH SIDES ARE CHECKED AGAINST THE SAME EXPECTATION**, element by element, against
// the float32 result numpy computed. A timing of the wrong answer is not a timing.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

const ROOT = process.cwd();
import { readdirSync } from "node:fs";
const KS = readdirSync(join(ROOT, ".agents/slop/perf/stage1"))
  .filter((f) => f.endsWith(".json"))
  .sort().map((f) => JSON.parse(readFileSync(join(ROOT, ".agents/slop/perf/stage1", f), "utf8")));
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
  const KS = ${JSON.stringify(KS)};
  const N = ${N};
  const out = { adapter: false, device: false, err: null, kernels: [] };
  if (!navigator.gpu) { out.err = "navigator.gpu absent"; return out; }
  const a = await navigator.gpu.requestAdapter();
  if (!a) { out.err = "requestAdapter answered null"; return out; }
  out.adapter = true;
  out.arch = a.info?.architecture ?? null;
  const dev = await a.requestDevice();
  out.device = true;
  const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

  for (const K of KS) {
  const R = { name: K.name, prog: K.program, la: K.label_a, lb: K.label_b, sha: K.sha256, sha_bend: K.sha_bend, bytes: K.bytes, identical: K.identical, cause: K.cause, sides: {} };
  out.kernels.push(R);
  // binding 0 is the f32 uniform the prologue declares; 1.. are the storage buffers
  const entries = [{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } }];
  const bufs = [];
  for (let i = 0; i < K.bufs.length; i++) {
    const b = dev.createBuffer({ size: K.nbytes[i],
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
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
  const zero = new Uint8Array(K.nbytes[0]);
  const read = dev.createBuffer({ size: K.nbytes[0], usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });

  const wantA = new Float32Array(b64(K.want_a).buffer), wantB = new Float32Array(b64(K.want_b).buffer);
  // RELATIVE: a 512x512 fp32 matmul's absolute error is ~1e-3 and that is the arithmetic, not a
  // defect -- judging it at 1e-5 absolute would fail every large kernel.
  const diff = (got, want) => {
    let w = 0, m = 0;
    for (let i = 0; i < got.length; i++) { w = Math.max(w, Math.abs(got[i] - want[i])); m = Math.max(m, Math.abs(want[i])); }
    return m > 0 ? w / m : w;
  };

  // BOTH PIPELINES FIRST, THEN INTERLEAVED TIMING. The same 600 bytes measured 0.2 ms when it
  // ran first and 1.1 ms when it ran second, so a sequential per-side loop measures the ORDER
  // as much as the shader. Each round runs both sides back to back and each side keeps its min.
  const sides = [];
  for (const [label, code] of [["python", K.wgsl], ["bend", K.wgsl_bend ?? ""]]) {
    const side = { label, present: !!code, ms: null, diff: null, matched: null, ok: false, pipe: null };
    R.sides[label] = { present: side.present, ms: null, diff: null, matched: null, ok: false };
    if (!code) continue;
    const mod = dev.createShaderModule({ code });
    const info = await mod.getCompilationInfo();
    if (info.messages.length) { R.sides[label].err = info.messages.map((m) => m.lineNum + ":" + m.message).join("; "); continue; }
    try {
      side.pipe = await dev.createComputePipelineAsync({ layout, compute: { module: mod, entryPoint: K.name } });
    } catch (e) { R.sides[label].err = String(e); continue; }
    sides.push(side);
  }
  const dispatch = (pipe, mult = 1) => {
    const enc = dev.createCommandEncoder();
    const p = enc.beginComputePass();
    p.setPipeline(pipe); p.setBindGroup(0, bg);
    p.dispatchWorkgroups(K.dispatch[0] * mult, K.dispatch[1], K.dispatch[2]);
    p.end();
    return enc.finish();
  };
  for (const s of sides) for (let i = 0; i < 3; i++) {         // warmup, per side
    dev.queue.writeBuffer(bufs[0], 0, zero);
    dev.queue.submit([dispatch(s.pipe)]);
    await dev.queue.onSubmittedWorkDone();
  }
  for (let round = 0; round < N; round++) {
    for (const s of sides) {
      dev.queue.writeBuffer(bufs[0], 0, zero);
      const t0 = performance.now();
      dev.queue.submit([dispatch(s.pipe)]);
      await dev.queue.onSubmittedWorkDone();                    // INSIDE the timed region
      const ms = performance.now() - t0;
      s.ms = s.ms === null ? ms : Math.min(s.ms, ms);
    }
  }
  // **THE PLANT**: the SAME pipeline at twice the dispatch. A comparison that cannot go red is
  // not a comparison, so this measures whether the timer resolves a factor of two at this size.
  for (const s of sides) {
    let best = null;
    for (let r2 = 0; r2 < 2; r2++) {
      dev.queue.writeBuffer(bufs[0], 0, zero);
      const t0 = performance.now();
      dev.queue.submit([dispatch(s.pipe, 2)]);
      await dev.queue.onSubmittedWorkDone();
      const ms = performance.now() - t0;
      best = best === null ? ms : Math.min(best, ms);
    }
    s.ms2 = best;
  }
  for (const s of sides) {
    dev.queue.writeBuffer(bufs[0], 0, zero);
    dev.queue.submit([dispatch(s.pipe)]);
    await dev.queue.onSubmittedWorkDone();
    const enc = dev.createCommandEncoder();
    enc.copyBufferToBuffer(bufs[0], 0, read, 0, K.nbytes[0]);
    dev.queue.submit([enc.finish()]);
    await read.mapAsync(GPUMapMode.READ);
    const got = new Float32Array(read.getMappedRange().slice(0));
    read.unmap();
    const da = diff(got, wantA), db = diff(got, wantB);
    Object.assign(R.sides[s.label], {
      ms: s.ms, ms2: s.ms2, diff: Math.min(da, db),
      matched: da < 1e-5 ? "(a*b)+a" : db < 1e-5 ? "(a*b)+b" : "NEITHER",
      ok: Math.min(da, db) < 1e-5,
    });
  }
  }
  return out;
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

const fmt = (x) => (typeof x === "number" ? x.toFixed(4) : "-");
const dxp = (x) => (typeof x === "number" ? x.toExponential(2) : "-");
const rows = [
  "# stage1-webgpu.rows -- .agents/slop/perf/stage1_webgpu.py + stage1_time.js",
  `# driver: headless Chrome, adapter ${out.arch ?? "?"}, DEV=METAL NOOPT=1 uops`,
  "# python side: WGSLRenderer(Target('webgpu')).render(uops)",
  "# bend side:   wgsl_walk.bend's walk -> wgsl.bend's render_kernel",
  `# iters=${N} (min), warmups=3 per side, INTERLEAVED timed rounds, around submit+onSubmittedWorkDone`,
  "# program|kernel|sha256_python|sha256_bend|identical|bytes|python_ms_min|bend_ms_min|diff_python|diff_bend|matched_p|matched_b|ok|cause_or_err|plant_py_2x|plant_bend_2x",
];
const sha = createHash("sha256").update(JSON.stringify(out)).digest("hex").slice(0, 16);
let allOk = true;
for (const R of out.kernels ?? []) {
  const P = R.sides?.python ?? {}, B = R.sides?.bend ?? {};
  const both = P.present && B.present && P.matched && B.matched && P.matched === B.matched;
  if (!both) allOk = false;
  const why = P.err ? "python: " + P.err : B.err ? "bend: " + B.err : (R.cause || "-");
  rows.push(`${R.prog ?? "-"}|${R.name}|${R.sha}|${R.sha_bend}|${R.identical ? "yes" : "no"}|${R.bytes ?? "-"}|` +
    `${fmt(P.ms)}|${fmt(B.ms)}|${dxp(P.diff)}|${dxp(B.diff)}|${P.matched ?? "-"}|${B.matched ?? "-"}|` +
    `${both ? "yes" : "no"}|${why}|` +
    `${typeof P.ms2 === "number" && P.ms ? (P.ms2 / P.ms).toFixed(2) : "-"}|` +
    `${typeof B.ms2 === "number" && B.ms ? (B.ms2 / B.ms).toFixed(2) : "-"}`);
}
rows.push(`# probe_sha=${sha} err=${out.err ?? "-"} kernels=${(out.kernels ?? []).length} all_ok=${allOk}`);
writeFileSync(join(ROOT, ".agents/slop/perf/stage1-webgpu.rows"), rows.join("\n") + "\n");
console.log(rows.join("\n"));
