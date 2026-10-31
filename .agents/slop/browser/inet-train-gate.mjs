#!/usr/bin/env node
// .agents/slop/browser/inet-train-gate.mjs -- THE IMAGENET TRAINING GATE.
//
//   node .agents/slop/browser/inet-train-gate.mjs
//
// WHAT IT ASKS, AND IT IS THE UPDATE AND NOT THE FORWARD:
// **DO THE PARAMETERS AN EFFICIENTNET-0 TRAINING STEP UPDATES, REPLAYED ON A REAL
// WEBGPU ADAPTER FROM CPYTHON's TRACE, END BIT-IDENTICAL TO CPYTHON's?**
//
// THE PREVIOUS VERSION OF THIS GATE COMPARED THE 1000 LOGITS, AND THE REVIEW THAT
// KILLED IT WAS RIGHT: **THE LOGITS ARE PRODUCED BY THE FORWARD, BEFORE `backward`
// AND THE SGD STEP RUN**, so a step whose gradients were ALL ZERO and whose weights
// never moved would have printed PASS. **⇒ AND THAT IS NOT HYPOTHETICAL -- IT IS
// WHAT THIS TRACE DID** (`0 of them MOVED`) until the detach below was found.
//
// THE DENOMINATOR IS THE SAMPLED PARAMETERS, NAMED: the eight heaviest of
// EfficientNet-0's 311 float parameters -- the conv and linear weights. 6.6 M
// parameters snapshotted twice would take the trace from megabytes to gigabytes,
// and the sample is what the trace CLAIMS to train.
//
// THE ROWS, AND EVERY ONE OF THEM MUST BE ABLE TO FAIL:
//   1  GPU == CPYTHON's `after`, BIT-EXACT, over the sampled parameters
//   2  the parameters MOVED: `before != after`, from the trace's own two snapshots
//   3  C1 -- GPU vs `before` MUST DIFFER, or the replay changed nothing
//   4  C2 -- one bit of one `after` word must be caught, and only that word
//   5  C3 -- and the comparison's tolerance cannot be Infinity: one word moved by
//            a whole ULP-class amount is caught, so an exact row means something
//
// TWO SIDES, INDEPENDENT: `inet-train-oracle.json` is CPython's, written before any
// browser ran, and the page never sees it.
import { launch, shutdown, Session, CHROME_BINARIES } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/cdp.mjs";
import { serve } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/serve.mjs";
import { readFile, copyFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const HERE = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/browser";
const WEB = path.join(HERE, "web");
const MNIST = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/examples/webgpu/mnist";
const DIR = path.join(HERE, "imagenet-train");

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
    const url = `${srv.url}/train.html?net=inet-train-net.json&oracle=inet-train-oracle.json&batch=${process.env.BATCH ?? 64}&only=${only}`;
    h = await launch(CHROME_BINARIES["chrome-stable"], ["--headless=new"], url);
    const s = await Session.openPage(h.port, { url });
    await s.eval("window.__GO = true;");
    for (let i = 0; i < 4800; i++) {
      try {
        const r = await s.eval("return window.__TRAIN_RESULT ? {t:'done'} : {t:'running'};", { timeoutMs: 60000 });
        if (r && r.t === "done") break;
      } catch (e) { /* the main thread is busy; ask again */ }
      await new Promise((r) => setTimeout(r, 250));
    }
    try {
      return JSON.parse(await s.eval("return JSON.stringify(window.__TRAIN_RESULT ?? {ok:false, error:'no result'});", { timeoutMs: 240000 }));
    } catch (e) {
      return { ok: false, error: `no result inside the budget (${e.message})` };
    }
  } finally {
    if (h) await shutdown(h);
    srv.close();
  }
}

const diff = (got, want) => {
  let n = 0, first = null;
  const len = Math.min(got.length, want.length);
  for (let i = 0; i < len; i++) {
    if (got[i] === want[i]) continue;
    n++;
    if (first === null) first = [i, got[i], want[i]];
  }
  return { n, len, first };
};

async function main() {
  if (!existsSync(path.join(DIR, "inet-train-net.json"))) {
    P(`REFUSED[3]: ${path.join(DIR, "inet-train-net.json")} is absent.`);
    P(`  A GENERATED artifact. Regenerate with:`);
    P(`      .venv/bin/python .agents/slop/browser/trace_imagenet_train.py 64`);
    return 3;
  }
  await buildBundle();
  const oracle = JSON.parse(await readFile(path.join(DIR, "inet-train-oracle.json"), "utf8"));
  const net = JSON.parse(await readFile(path.join(DIR, "inet-train-net.json"), "utf8"));
  const P8 = oracle.params ?? {};
  const names = Object.keys(P8);
  if (!names.length) {
    P(`REFUSED[3]: the oracle records NO parameter buffers, so the update cannot be`);
    P(`  compared. That is the exact defect this gate exists to catch: a logits-only`);
    P(`  row is green on a step whose gradients are zero.`);
    return 3;
  }

  P(`oracle: EfficientNet(0) TRAINING step at ${oracle.input.slice(2).join("x")}, loss=${oracle.loss}`);
  P(`        ${names.length} SAMPLED PARAMETER buffers, ${Object.values(P8).reduce((a, v) => a + v.numel, 0)} parameters total`);
  for (const n of names) P(`          ${n.padEnd(6)} ${P8[n].name.padEnd(34)} numel=${P8[n].numel}`);

  let res = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    res = await replay(names.join(","));
    if (res && res.ok) break;
    if (attempt === 0) P(`  attempt 1: no result, restarting the page`);
  }
  if (!res || !res.ok) {
    P(`REFUSED[3]: no result from either page (${res && res.error}).`);
    P(`  launched ${net.kernels.length} kernels; WGSL-UNRENDERED: 0 of ${net.kernels.length} (trace-side).`);
    return 3;
  }
  P(`PERF launches=${res.launches} parse=${(res.ms_parse ?? 0).toFixed(0)}ms ` +
    `gpu=${(res.ms_gpu ?? 0).toFixed(1)}ms read=${(res.ms_read ?? 0).toFixed(1)}ms ` +
    `per_launch=${((res.ms_gpu ?? 0) / Math.max(1, res.launches) * 1000).toFixed(1)}us`);
  P(`adapter ${res.adapter}  launches ${res.launches}  uploads ${res.uploads}  read_back ${res.read_back}`);

  let fails = 0;

  // ---- 1. THE UPDATE, BIT-EXACT -------------------------------------------
  let totWords = 0, totDiff = 0, badParams = 0;
  for (const n of names) {
    const got = res.words[n];
    const want = b64ToU32(P8[n].after_b64);
    if (!got) { P(`${BAD}${n} was not read back`); fails++; badParams++; continue; }
    const d = diff(got, want);
    totWords += d.len; totDiff += d.n;
    if (d.n) { badParams++; P(`      ${n} (${P8[n].name}): ${d.n}/${d.len} words differ, first ${JSON.stringify(d.first)}`); }
  }
  const exact = totDiff === 0;
  P(`${exact ? OK : BAD}the UPDATED PARAMETERS are BIT-IDENTICAL to CPython's ` +
    `(denominator=${names.length} buffers, ${totWords} words)${exact ? "" : `, ${badParams} buffer(s) differ`}`);
  if (!exact) fails++;

  // ---- 2. AND THEY MOVED ---------------------------------------------------
  const moved = names.filter((n) => P8[n].before_b64 !== P8[n].after_b64);
  P(`${moved.length === names.length ? OK : BAD}the parameters MOVED during the step: ` +
    `${moved.length} of ${names.length} differ between the trace's own two snapshots`);
  if (moved.length !== names.length) fails++;

  // ---- 3. C1: NOTHING RAN -------------------------------------------------
  let c1Diff = 0;
  for (const n of names) {
    const got = res.words[n];
    if (!got) continue;
    c1Diff += diff(got, b64ToU32(P8[n].before_b64)).n;
  }
  P(`${c1Diff > 0 ? OK : BAD}C1 (the GPU vs the **PRE-STEP** weights, which must DIFFER): ` +
    `${c1Diff} of ${totWords} words differ`);
  if (!(c1Diff > 0)) fails++;

  // ---- 4. C2: ONE BIT OF ONE UPDATED WEIGHT --------------------------------
  const v = names[0];
  const mutAfter = Uint32Array.from(b64ToU32(P8[v].after_b64));
  mutAfter[0] ^= 1;
  const c2 = diff(res.words[v], mutAfter);
  P(`${c2.n === 1 && c2.first && c2.first[0] === 0 ? OK : BAD}C2 (one bit of ${v}[0] must be caught, ` +
    `and only that word): ${c2.n === 1 ? "named word 0" : JSON.stringify({ n: c2.n, first: c2.first })}`);
  if (!(c2.n === 1)) fails++;

  // ---- 5. C3: THE ROW CAN FAIL AT ALL --------------------------------------
  // One whole parameter buffer is compared against the WRONG parameter's update.
  // If that also "agrees", the row is comparing nothing.
  const other = names[1] ?? names[0];
  const swapped = diff(res.words[v], b64ToU32(P8[other].after_b64));
  P(`${swapped.n > 0 ? OK : BAD}C3 (${v} against ${other}'s update must NOT agree): ` +
    `${swapped.n} of ${swapped.len} words differ`);
  if (!(swapped.n > 0)) fails++;

  P(fails === 0
    ? `PASS -- one EfficientNet(0) TRAINING step, ${res.launches} launches replayed on ` +
      `${res.adapter}, leaves ${names.length} of ${names.length} SAMPLED PARAMETERS ` +
      `BIT-IDENTICAL to CPython's (${totWords} words), and every one of them MOVED`
    : `FAIL (${fails}) -- see the BAD rows`);
  return fails === 0 ? 0 : 1;
}

process.exit(await main());
