#!/usr/bin/env node
// .agents/slop/browser/fchain-wgsl-gate.mjs -- THE FOUR PORT-RENDERED WGSL KERNELS, ON A REAL ADAPTER.
//
//   node .agents/slop/browser/fchain-wgsl-gate.mjs      # 0 = every stage bit-identical
//
// WHAT IT ASKS: **does the WGSL the PORT rendered, dispatched on WebGPU, reproduce the reference
// chain word for word?** The oracle is `fchain-harness --dump` -- the same C reference chain that
// certified the C lane -- so the two lanes are graded by ONE oracle and not two.
//
// THE PAGE NEVER SEES THE ORACLE: it reports the GPU's words and this file diffs them.
// EXITS: 0 PASS · 1 FAIL · 3 REFUSED (an artifact is missing, so nothing was measured).
import { launch, shutdown, Session, CHROME_BINARIES } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/cdp.mjs";
import { serve } from "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/.e2e-fixture/xd2/serve.mjs";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

const HERE = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/browser";
const WEB = path.join(HERE, "web");
const BUNDLE = path.join(WEB, "fchain-wgsl.json");

const P = (s) => console.log(s);
const hex = (u) => (u >>> 0).toString(16).padStart(8, "0");

function diffWords(got, want) {
  const rows = [];
  for (const [n, words] of Object.entries(want)) {
    const g = got[n];
    if (!g) { rows.push({ n, missing: true, ndiff: -1 }); continue; }
    let ndiff = 0, first = null;
    for (let i = 0; i < words.length; i++) {
      if (g[i] === words[i]) continue;
      ndiff++;
      if (first === null) first = [i, hex(g[i]), hex(words[i])];
    }
    rows.push({ n, ndiff, len: words.length, first });
  }
  return rows;
}

async function run() {
  const srv = await serve(WEB);
  let h;
  try {
    h = await launch(CHROME_BINARIES["chrome-stable"], ["--headless=new"], srv.url + "/fchain-wgsl.html");
    const s = await Session.openPage(h.port, { url: srv.url + "/fchain-wgsl.html" });
    for (let i = 0; i < 400; i++) {
      try {
        const r = await s.eval("return window.__FCHAIN_RESULT ? {t:'done'} : {t:'running'};");
        if (r && r.t === "done") break;
      } catch (e) { /* the main thread is busy; ask again */ }
      await new Promise((r) => setTimeout(r, 100));
    }
    const res = await s.eval("return JSON.stringify(window.__FCHAIN_RESULT ?? {ok:false,error:'no result: the page never finished'});");
    return JSON.parse(res);
  } finally {
    if (h) await shutdown(h);
    srv.close();
  }
}

async function main() {
  if (!existsSync(BUNDLE)) {
    P(`REFUSED[3]: ${BUNDLE} is absent. Regenerate it with:`);
    P(`  ./bin/bend .agents/slop/browser/fchainwgsl.bend > .agents/slop/browser/fchain-wgsl.rows`);
    P(`  cc -O1 -std=c11 -o /tmp/fchain .agents/slop/browser/fchain-harness.c -lm && /tmp/fchain --dump > .agents/slop/browser/fchain-ref.rows`);
    P(`  .venv/bin/python .agents/slop/browser/fchain-wgsl-gen.py`);
    return 3;
  }
  const bundle = JSON.parse(await readFile(BUNDLE, "utf8"));
  P(`bundle: modules=${bundle.modules.length} wiring=${JSON.stringify(bundle.wiring)}`);
  const res = await run();
  if (!res.ok) {
    P(`BAD  the page did not complete: ${res.error}`);
    if (res.messages) res.messages.forEach((m) => P(`     wgsl: ${m}`));
    if (res.detail) P(`     detail: ${JSON.stringify(res.detail)}`);
    P("VERDICT: A KERNEL DID NOT RUN");
    return 1;
  }
  P(`adapter: ${res.adapter}`);
  const rows = diffWords(res.stages, bundle.want);
  let ok = true;
  for (const r of rows) {
    if (r.missing) { P(`BAD  ${r.n}: the page reported nothing`); ok = false; continue; }
    const good = r.ndiff === 0;
    ok = ok && good;
    P(`${good ? "OK  " : "BAD "} ${r.n}: ${r.len - r.ndiff}/${r.len} words identical` +
      (r.first ? `  first=${r.first[0]} got=${r.first[1]} want=${r.first[2]}` : "  max-abs-diff=0.000e+00"));
  }
  P(`VERDICT: ${ok ? "ALL FOUR WGSL KERNELS AGREE" : "A WGSL KERNEL DISAGREES"}`);
  return ok ? 0 : 1;
}

process.exit(await main());
