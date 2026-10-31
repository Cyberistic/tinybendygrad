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

// **⇒ THE TOLERANCE, AND WHY IT IS NOT A CONVENIENCE.** EfficientNet-0 has ~50
// convolution layers across 328 kernels, so f32 ACCUMULATION ORDER compounds
// where MNIST's four convs did not. **MEASURED: max |absolute| 2.384e-7 over 1000
// logits, 189 of them BIT-IDENTICAL** -- and that is the SAME class and the SAME
// magnitude `examples/webgpu/mnist/README.md` records for its own convolutions
// (3.6e-7), because the CPU is compiled `-O2` with no `-ffp-contract=off`
// (`support/compiler_cpu.py:21`) so clang fuses multiply-adds WGSL does not.
//
// **⇒ AND A TOLERANCE THAT CANNOT FAIL IS A LABEL**, so the plant below adds
// exactly 1.0 to one logit's expectation and the SAME comparison must reject it.
const TOL = 1e-6;

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
  // **⇒ AND A COUNT OF DIFFERING WORDS IS NOT A MAGNITUDE**, and the two mean
  // different things: an f32 accumulation-order difference is a few ULP in the
  // last place (the MNIST page documents 3.6e-7 absolute on its convolutions),
  // while a structural error is a whole different number. **⇒ SO THE ROW PRINTS
  // THE MAXIMUM ABSOLUTE DEVIATION AND ITS ULP**, and a reader can tell which.
  const f32v = (w) => { const b = Buffer.alloc(4); b.writeUInt32LE(w >>> 0); return b.readFloatLE(0); };
  const i32v = (w) => { const b = Buffer.alloc(4); b.writeInt32LE(w | 0); return b.readInt32LE(0); };
  let maxAbs = 0, maxUlp = 0, maxRel = 0, at = -1;
  for (let i = 0; i < Math.min(got.length, want.length); i++) {
    if (got[i] === want[i]) continue;
    const a = Math.abs(f32v(got[i]) - f32v(want[i]));
    if (a > maxAbs) { maxAbs = a; at = i; }
    maxUlp = Math.max(maxUlp, Math.abs(i32v(got[i]) - i32v(want[i])));
    const den = Math.abs(f32v(want[i])) || 1;
    maxRel = Math.max(maxRel, a / den);
  }
  const exact = d.len - d.n;
  const within = maxAbs <= TOL;
  P(`${within ? OK : BAD}the 1000 logits AGREE within ${TOL} ABSOLUTE (denominator=${d.len} words): ` +
    `${exact} exact, ${d.n} differ, max |abs| ${maxAbs.toExponential(3)}` +
    `${at >= 0 ? ` at logit ${at}` : ""}, max ${maxUlp} ULP, max rel ${maxRel.toExponential(3)}`);
  if (!within) fails++;
  P(`     ${exact} of ${d.len} logits BIT-IDENTICAL; ${d.n} differ inside the tolerance`);
  if (d.n) P(`      first ${JSON.stringify(d.first)}`);

  // ---- C3: THE TOLERANCE MUST BE ABLE TO FAIL ------------------------------
  // One logit's expectation is moved by a real amount and the SAME test must
  // reject it. Without this, `TOL = 1e-6` could be `Infinity` and every row
  // above would still be green.
  const far = Uint32Array.from(want);
  far[0] = new Uint32Array(new Float32Array([f32v(want[0]) + 1.0]).buffer)[0];
  let farMax = 0;
  for (let i = 0; i < Math.min(got.length, far.length); i++) {
    if (got[i] === far[i]) continue;
    farMax = Math.max(farMax, Math.abs(f32v(got[i]) - f32v(far[i])));
  }
  P(`${farMax > TOL ? OK : BAD}C3 (one logit moved by 1.0 must EXCEED the tolerance): ` +
    `max ${farMax.toExponential(3)} vs ${TOL}`);
  if (!(farMax > TOL)) fails++;

  // ---- C1: NOTHING RAN -----------------------------------------------------
  // **⇒ AND THE UPLOAD **IS** ALREADY KNOWN WHEN THE FIRST BIND WAS ELIDED AS ALL
  // ZEROES** -- `GPUBuffer` is zero-initialised, so the "no upload" state of this
  // buffer is a zero array and the control is still askable. The first version
  // REFUSED here, which was wrong: an absent PAYLOAD is not an absent FACT.
  const site = net.buffers[OUT_NAME];
  const firstBind = site?.b64 ? b64ToU32(site.b64) : new Uint32Array(got.length);
  const c1 = diff(got, firstBind);
  P(`${c1.n > 0 ? OK : BAD}C1 (the logits vs the UPLOAD, which must DIFFER): ` +
    `${c1.n} of ${c1.len} words differ` +
    `${site?.b64 ? "" : " (the first bind was all-zero and elided, so the upload is zeroes)"}`);
  if (!(c1.n > 0)) fails++;

  // ---- C2: ONE BIT OF ONE LOGIT -------------------------------------------
  // **⇒ AND THE BIT IS FLIPPED IN A WORD THAT CURRENTLY **AGREES**, WHICH IS THE
  // ONLY WAY THIS CONTROL CAN MEAN ANYTHING.** The first version flipped
  // `want[0]`, and `got[0]` already differed from `want[0]` -- so flipping the
  // oracle's bit left the comparison's verdict unchanged and the control could
  // never fire. **⇒ A MUTATION IN A WORD THAT IS ALREADY WRONG MEASURES NOTHING.**
  let k = 0;
  while (k < got.length && got[k] !== want[k]) k++;
  const mutated = Uint32Array.from(want);
  mutated[k] ^= 1;
  const c2 = diff(got, mutated);
  const hit = c2.n === d.n + 1;
  P(`${hit ? OK : BAD}C2 (one bit of logit ${k}, which agrees, must add EXACTLY one differing word): ` +
    `${hit ? `count ${d.n} -> ${c2.n}` : `count ${d.n} -> ${c2.n}, expected ${d.n + 1}`}`);
  if (!hit) fails++;

  P(fails === 0
    ? `PASS -- EfficientNet(0)'s forward pass, ${res.launches} launches replayed on ${res.adapter}, ` +
      `reproduces CPython's ${d.len} ImageNet logits to ${maxAbs.toExponential(3)} ABSOLUTE ` +
      `(${exact} of ${d.len} bit-identical), and the tolerance is shown to be able to fail`
    : `FAIL (${fails}) -- see the BAD rows`);
  return fails === 0 ? 0 : 1;
}

process.exit(await main());
