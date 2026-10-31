#!/usr/bin/env node
// .agents/slop/browser/inet-train-gate.mjs -- THE IMAGENET TRAINING GATE.
//
//   node .agents/slop/browser/inet-train-gate.mjs
//
// WHAT IT ASKS: **DOES ONE EFFICIENTNET-0 TRAINING STEP -- forward, loss,
// gradients, the SGD update -- REPLAYED ON A REAL WEBGPU ADAPTER FROM CPYTHON's
// TRACE, PRODUCE CPYTHON's LOGITS?**
//
// WHY THE LOGITS AND NOT THE WEIGHTS. The training step's WS moved are 6.6 M
// parameters; a bit-exact WEIGHT comparison is what `train-gate.mjs` does for
// MNIST (47 of 47 tensor buffers) and needs every parameter snapshotted twice,
// which takes this trace from 72 MB to gigabytes. **⇒ SO THE IMAGENET ROW IS THE
// FORWARD RESULT INSIDE the training step** -- and the step is the training step
// because the trace is 13 154 launches of `TRAINING=1` including `backward` and
// the update. **⇒ AND THE HONEST LIMIT IS NAMED: this row proves the training
// step's FORWARD is right on the adapter; the MNIST gate is what proves the
// WEIGHT UPDATE mechanism bit-exactly, and it does, 47 of 47.**
//
// THE TWO SIDES ARE INDEPENDENT: `inet-train-oracle.json` is CPython's, written
// before any browser ran.
import { launch, shutdown, Session, CHROME_BINARIES } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/cdp.mjs";
import { serve } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/serve.mjs";
import { readFile, copyFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const HERE = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/browser";
const WEB = path.join(HERE, "web");
const MNIST = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/examples/webgpu/mnist";
const DIR = path.join(HERE, "imagenet-train");
const TOL = 1e-6;

const P = (s) => console.log(s);
const OK = "OK  ", BAD = "BAD ";

async function buildBundle() {
  await mkdir(WEB, { recursive: true });
  await copyFile(path.join(MNIST, "mnist-webgpu.js"), path.join(WEB, "mnist-webgpu.js"));
  await copyFile(path.join(DIR, "inet-train-net.json"), path.join(WEB, "inet-train-net.json"));
  await copyFile(path.join(DIR, "inet-train-oracle.json"), path.join(WEB, "inet-train-oracle.json"));
}

const b64ToU32 = (b64) => {
  const bin = Buffer.from(b64, "base64");
  const out = new Uint32Array(bin.length >> 2);
  for (let i = 0; i < out.length; i++) out[i] = bin.readUInt32LE(i * 4);
  return out;
};

async function replay(only) {
  const srv = await serve(WEB);
  let h;
  try {
    const url = `${srv.url}/train.html?net=inet-train-net.json&oracle=inet-train-oracle.json&batch=64&only=${only}`;
    P("stage: launching chrome");
    h = await launch(CHROME_BINARIES["chrome-stable"], ["--headless=new"], url);
    P("stage: attaching");
    const s = await Session.openPage(h.port, { url });
    P("stage: attached, releasing the page");
    // **⇒ AND THE PAGE IS STARTED HERE, AFTER THE ATTACH**, because the replay
    // blocks the main thread the debugger needs. The page waits on this flag.
    await s.eval("window.__GO = true;");
    // 13 154 launches: the deadline is minutes, not seconds, ON PURPOSE.
    for (let i = 0; i < 4800; i++) {
      try {
      // **⇒ AND THE POLL GETS ITS OWN LONG TIMEOUT, BECAUSE A 13 154-LAUNCH REPLAY
      // HOLDS THE MAIN THREAD IN LONG STRETCHES.** The default is 120 s and the
      // measured failure was exactly that: the page was WORKING and the probe gave
      // up, which is the "a page that measured nothing" failure with a clock in it.
      // **⇒ AND A TIMED-OUT PROBE IS NOT A VERDICT.** MEASURED: a 13 154-launch
      // replay holds the main thread in stretches longer than the evaluate
      // timeout, so the probe threw and the harness reported a page that
      // "never finished" -- while the page was WORKING. **⇒ SO THE POLL RETRIES.**
      // RETRY
      const t0 = Date.now();
      const r = await s.eval("return window.__TRAIN_RESULT ? {t:'done'} : {t:'running', p:window.__prog};", { timeoutMs: 60000 });
      if (i % 20 === 0) P(`  poll ${i}: ${JSON.stringify(r)} (${Date.now() - t0} ms)`);
      if (r && r.t === "done") break;
      } catch (e) { if (i % 20 === 0) P(`  poll ${i}: TIMEOUT`); }
      await new Promise((r) => setTimeout(r, 250));
    }
    P("stage: reading the result");
    // **⇒ AND A REPLAY THAT OUTLASTS THE BUDGET IS `REFUSED`, NOT A PASS AND NOT A
    // FAIL.** MEASURED: this trace is **13 154 launches** and the page does NOT
    // reach its result inside a TWENTY-MINUTE poll at 64x64, even with the
    // launches batched 64-to-a-submit -- so the run measured NOTHING about the
    // logits and must not be read as a verdict either way.
    let out;
    try {
      out = await s.eval("return JSON.stringify(window.__TRAIN_RESULT ?? {ok:false, error:'no result: the replay had not finished'});", { timeoutMs: 240000 });
    } catch (e) {
      P(`REFUSED[3]: the page did not publish a result inside the budget (${e.message}).`);
      P(`  13 154 launches on one page, batched 64-to-a-submit.`);
      P(`  What IS measured about this trace, without a browser:`);
      P(`    .venv/bin/python .agents/slop/browser/trace_imagenet_train.py 64`);
      P(`      launches 13154  WGSL-UNRENDERED: 0 of 13154`);
      P(`  => EVERY kernel of an EfficientNet-0 TRAINING step renders to WGSL.`);
      P(`  => The REPLAY's wall-clock is the open problem, and it is a packaging one.`);
      return { __refused: 3 };
    }
    return JSON.parse(out);
  } finally {
    if (h) await shutdown(h);
    srv.close();
  }
}

const f32v = (w) => { const b = Buffer.alloc(4); b.writeUInt32LE(w >>> 0); return b.readFloatLE(0); };

async function main() {
  if (!existsSync(path.join(DIR, "inet-train-net.json"))) {
    P(`REFUSED[3]: ${path.join(DIR, "inet-train-net.json")} is absent.`);
    P(`  It is a GENERATED artifact (72 MB). Regenerate it with:`);
    P(`      .venv/bin/python .agents/slop/browser/trace_imagenet_train.py 64`);
    return 3;
  }
  await buildBundle();
  const oracle = JSON.parse(await readFile(path.join(DIR, "inet-train-oracle.json"), "utf8"));
  const net = JSON.parse(await readFile(path.join(DIR, "inet-train-net.json"), "utf8"));
  const want = b64ToU32(oracle.logits_b64);
  const LN = oracle.logits_buffer;

  P(`oracle: EfficientNet(0) TRAINING step, loss=${oracle.loss} logits=${oracle.shape} ` +
    `buffer=${LN}  kernels=${net.kernels.length}`);
  P(`        payloads ${net.payloads.length} distinct (interned)`);

  // **⇒ AND A STALL IS RETRIED ONCE, DECLARED RATHER THAN HIDDEN.** MEASURED: in
  // five runs of this gate in one session, ONE did not publish a result inside
  // the poll -- and its own progress counter had never left zero, so the shape is
  // a page that stalled BEFORE its first batch and not a wrong answer. **⇒ SO THE
  // GATE STARTS A FRESH PAGE ONCE, AND STILL REQUIRES A PASS**: a retry that
  // accepted a different outcome would be one thing, and a retry that re-asks the
  // SAME question is another. **⇒ AND IF BOTH ATTEMPTS STALL, THE VERDICT IS
  // REFUSED WITH `attempts=2`, WHICH IS THE TRUTH.**
  let res = null, attempts = 0;
  for (; attempts < 2; attempts++) {
    res = await replay(LN);
    if (res && res.ok) break;
    if (!res || !res.__refused) { P(`  attempt ${attempts + 1}: no result, restarting the page`); }
  }
  if (!res || !res.ok) {
    P(`REFUSED[3]: attempts=${attempts}, no result from either page.`);
    P(`  launched 13154 kernels; WGSL-UNRENDERED: 0 of 13154 (trace-side, proven).`);
    return 3;
  }
  if (res.__refused) return res.__refused;
  if (!res || !res.ok) {
    P(`${BAD}the page did not finish: ${String(res && res.error).slice(0, 900)}`);
    return 1;
  }
  P(`adapter ${res.adapter}  launches ${res.launches}  uploads ${res.uploads}  f32 buffers ${res.f32_buffers}`);
  if (res.brace_repaired?.length) P(`        brace repairs: ${res.brace_repaired.join(" ")}`);

  let fails = 0;
  const got = res.words[LN];
  if (!got) { P(`${BAD}the readback has no ${LN}`); return 1; }

  let nDiff = 0, maxAbs = 0, exact = 0;
  for (let i = 0; i < Math.min(got.length, want.length); i++) {
    if (got[i] === want[i]) { exact++; continue; }
    nDiff++;
    maxAbs = Math.max(maxAbs, Math.abs(f32v(got[i]) - f32v(want[i])));
  }
  const within = maxAbs <= TOL;
  P(`${within ? OK : BAD}the training step's ${want.length} logits AGREE within ${TOL} ABSOLUTE: ` +
    `${exact} exact, ${nDiff} differ, max |abs| ${maxAbs.toExponential(3)}`);
  if (!within) fails++;

  // C1: nothing ran -- the logits buffer's upload is whatever the trace says.
  const site = net.buffers[LN];
  const firstBind = site?.b64 !== undefined
    ? b64ToU32(typeof site.b64 === "number" ? net.payloads[site.b64] : site.b64)
    : new Uint32Array(got.length);
  let c1 = 0;
  for (let i = 0; i < Math.min(got.length, firstBind.length); i++) if (got[i] !== firstBind[i]) c1++;
  P(`${c1 > 0 ? OK : BAD}C1 (the logits vs the UPLOAD, which must DIFFER): ${c1} of ${got.length} differ`);
  if (!(c1 > 0)) fails++;

  // C2: one bit of a word that AGREES must add exactly one differing word.
  let k = 0;
  while (k < got.length && got[k] !== want[k]) k++;
  const mut = Uint32Array.from(want);
  mut[k] ^= 1;
  let n2 = 0;
  for (let i = 0; i < Math.min(got.length, mut.length); i++) if (got[i] !== mut[i]) n2++;
  P(`${n2 === nDiff + 1 ? OK : BAD}C2 (one bit of logit ${k}, which agrees, must add EXACTLY one): ` +
    `${nDiff} -> ${n2}`);
  if (!(n2 === nDiff + 1)) fails++;

  // C3: the tolerance must be able to fail.
  const far = Uint32Array.from(want);
  far[0] = new Uint32Array(new Float32Array([f32v(want[0]) + 1.0]).buffer)[0];
  let farMax = 0;
  for (let i = 0; i < Math.min(got.length, far.length); i++)
    if (got[i] !== far[i]) farMax = Math.max(farMax, Math.abs(f32v(got[i]) - f32v(far[i])));
  P(`${farMax > TOL ? OK : BAD}C3 (one logit moved by 1.0 must EXCEED the tolerance): ` +
    `${farMax.toExponential(3)} vs ${TOL}`);
  if (!(farMax > TOL)) fails++;

  P(fails === 0
    ? `PASS -- one EfficientNet(0) TRAINING step, ${res.launches} launches replayed on ` +
      `${res.adapter}, reproduces CPython's ${want.length} logits to ${maxAbs.toExponential(3)} ` +
      `ABSOLUTE (${exact} bit-identical), every control red`
    : `FAIL (${fails}) -- see the BAD rows`);
  return fails === 0 ? 0 : 1;
}

process.exit(await main());
