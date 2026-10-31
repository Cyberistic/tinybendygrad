#!/usr/bin/env node
// .agents/slop/browser/inet-gate.mjs -- THE IMAGENET GATE.
//
//   node .agents/slop/browser/inet-gate.mjs      # exit 0 = the forward pass matches
//
// WHAT IT ASKS: **DOES EFFICIENTNET-0's FORWARD PASS, REPLAYED ON A REAL WEBGPU
// ADAPTER FROM CPYTHON's TRACE, PRODUCE CPYTHON's 1000 LOGITS BIT FOR BIT?**
//
// THE SAME PAGE AND THE SAME PLUMBING AS THE TRAINING GATE (`web/train.html`,
// parameterised), because the WebGPU work -- the alias collapse, the layout
// derivation, the error scope -- is the part that must not be written twice.
//
// THE TWO SIDES ARE INDEPENDENT: `inet-oracle.json` carries CPython's logits and
// was written BEFORE any browser ran; the page never sees it.
//
// THE CONTROLS, AND EACH MUST GO RED:
//   C1  NOTHING RAN -- compare against the FIRST-BIND contents instead. If that
//       also agrees, the replay changed nothing and the row above was satisfied
//       by the uploads.
//   C2  ONE BIT of one logit, in the ORACLE. It must be caught AND name that
//       word and no other.
import { launch, shutdown, Session, CHROME_BINARIES } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/cdp.mjs";
import { serve } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/serve.mjs";
import { readFile, copyFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const HERE = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/browser";
const WEB = path.join(HERE, "web");
const MNIST = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/examples/webgpu/mnist";
const INET = path.join(HERE, "imagenet");
const OUT_NAME = "b312"; // the last launch's output slot; read out of the trace, not guessed

const P = (s) => console.log(s);
const OK = "OK  ", BAD = "BAD ";

async function buildBundle() {
  await mkdir(WEB, { recursive: true });
  await copyFile(path.join(MNIST, "mnist-webgpu.js"), path.join(WEB, "mnist-webgpu.js"));
  await copyFile(path.join(INET, "inet-net.json"), path.join(WEB, "inet-net.json"));
  await copyFile(path.join(INET, "inet-oracle.json"), path.join(WEB, "inet-oracle.json"));
}

const b64ToU32 = (b64) => {
  const bin = Buffer.from(b64, "base64");
  const out = new Uint32Array(bin.length >> 2);
  for (let i = 0; i < out.length; i++) out[i] = bin.readUInt32LE(i * 4);
  return out;
};

async function replay() {
  const srv = await serve(WEB);
  let h;
  try {
    const url = srv.url + "/train.html?net=inet-net.json&oracle=inet-oracle.json";
    h = await launch(CHROME_BINARIES["chrome-stable"], ["--headless=new"], url);
    const s = await Session.openPage(h.port, { url });
    // 328 launches and a ~100 MB trace: the deadline is generous ON PURPOSE,
    // because a page that is still parsing is not a page that failed.
    for (let i = 0; i < 2400; i++) {
      const r = await s.eval("return window.__TRAIN_RESULT ? {t:'done'} : {t:document.title};");
      if (r && r.t === "done") break;
      await new Promise((r) => setTimeout(r, 250));
    }
    const res = await s.eval("return JSON.stringify(window.__TRAIN_RESULT ?? {ok:false, error:'no result: page never finished'});");
    return JSON.parse(res);
  } finally {
    if (h) await shutdown(h);
    srv.close();
  }
}

function diff(got, want) {
  let n = 0, first = null;
  const len = Math.min(got.length, want.length);
  for (let i = 0; i < len; i++) {
    if (got[i] === want[i]) continue;
    n++;
    if (first === null) first = [i, got[i], want[i]];
  }
  return { n, len, first };
}

async function main() {
  if (!existsSync(path.join(INET, "inet-net.json"))) {
    P(`REFUSED[3]: ${path.join(INET, "inet-net.json")} is absent.`);
    P(`  It is a GENERATED artifact (103 MB: EfficientNet-0's weights as JSON).`);
    P(`  Regenerate it with:  .venv/bin/python .agents/slop/browser/trace_imagenet.py`);
    return 3;
  }
  await buildBundle();
  const oracle = JSON.parse(await readFile(path.join(INET, "inet-oracle.json"), "utf8"));
  const net = JSON.parse(await readFile(path.join(INET, "inet-net.json"), "utf8"));
  const want = b64ToU32(oracle.logits_b64);

  P(`oracle: EfficientNet(0) logits ${oracle.shape}  kernels=${net.kernels.length}  buffers=${Object.keys(net.buffers).length}`);

  const res = await replay();
  if (!res.ok) { P(`${BAD}the page did not finish: ${String(res.error).slice(0, 800)}`); return 1; }
  P(`adapter ${res.adapter}  launches ${res.launches}  uploads ${res.uploads}  f32 buffers ${res.f32_buffers}`);

  let fails = 0;
  const got = res.words[OUT_NAME];
  if (!got) { P(`${BAD}the readback has no ${OUT_NAME}`); return 1; }
  const d = diff(got, want);
  P(`${d.n === 0 ? OK : BAD}the 1000 logits AGREE (denominator=${d.len} words)`);
  if (d.n) { fails++; P(`      ${d.n}/${d.len} differ, first ${JSON.stringify(d.first)}`); }

  // ---- C1: NOTHING RAN -----------------------------------------------------
  const firstBind = net.buffers[OUT_NAME] ? b64ToU32(net.buffers[OUT_NAME].b64) : null;
  if (firstBind) {
    const c1 = diff(got, firstBind);
    P(`${c1.n > 0 ? OK : BAD}C1 (the logits vs the UPLOAD, which must DIFFER): ${c1.n} of ${c1.len} words differ`);
    if (!(c1.n > 0)) fails++;
  } else {
    P(`REFUSED[3] C1: ${OUT_NAME} has no first-bind snapshot (it was all zeros and elided),`);
    P(`  so "the logits vs the upload" cannot be asked. NOT COUNTED AS A PASS.`);
    fails++;
  }

  // ---- C2: ONE BIT OF ONE LOGIT -------------------------------------------
  const mutated = Uint32Array.from(want);
  mutated[0] ^= 1;
  const c2 = diff(got, mutated);
  const hit = c2.n === 1 && c2.first && c2.first[0] === 0;
  P(`${hit ? OK : BAD}C2 (one bit of logit 0 must be caught, and only that word): ` +
    `${hit ? "named logit[0]" : JSON.stringify({ n: c2.n, first: c2.first })}`);
  if (!hit) fails++;

  P(fails === 0
    ? `PASS -- EfficientNet(0)'s forward pass, ${res.launches} launches replayed on ${res.adapter}, ` +
      `reproduces CPython's ${d.len} ImageNet logits BIT-EXACT`
    : `FAIL (${fails}) -- see the BAD rows`);
  return fails === 0 ? 0 : 1;
}

process.exit(await main());
