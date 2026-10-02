// e2e.mjs -- the gate. Opens examples/webgpu/mnist/index.html in Chrome, waits
// for the page's machine-readable answer, and checks it against the CPython
// oracle ON DISK. The oracle is never taken from the page's own output: the
// harness reads oracle.json itself and diffs whole `name=value` lines.
//
// An all-equal fixture cannot detect order, so the rows here are printed with
// their INDEX, and the harness compares the whole 10-vector, not a summary.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { launch, shutdown, Session, CHROME_BINARIES } from "./cdp.mjs";
import { serve } from "./serve.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PAGE_DIR = resolve(HERE, "../../../examples/webgpu/mnist");
const BINARY = process.env.CHROME ?? "chrome-stable";
const FLAGS = ["--headless=new"];

const srv = await serve(PAGE_DIR);
const oracle = JSON.parse(await readFile(resolve(PAGE_DIR, "oracle.json"), "utf8"));
const want = [...Buffer.from(oracle.logits_b64, "base64")].reduce((a, _, i, arr) =>
  i % 4 ? a : a.concat((arr[i] | (arr[i + 1] << 8) | (arr[i + 2] << 16)) + arr[i + 3] * 0x1000000), []);

let h;
let page = { ok: false, why: "harness never got an answer" };
let console_ = [];
try {
  h = await launch(CHROME_BINARIES[BINARY], FLAGS, srv.url + "/index.html");
  const s = await Session.openPage(h.port, { url: srv.url + "/index.html" });
  s.ws.addEventListener("message", (ev) => s.dispatch(JSON.parse(ev.data)));
  page = await s.eval(`
    const deadline = Date.now() + 120000;
    while (!window.__MNIST_RESULT && Date.now() < deadline) await new Promise(r => setTimeout(r, 100));
    if (!window.__MNIST_RESULT) return { ok: false, why: "page never set __MNIST_RESULT in 120s" };
    return window.__MNIST_RESULT;
  `, { timeoutMs: 150000 });
  console_ = s.log;
  s.close();
} catch (e) {
  page = { ok: false, why: `harness: ${e}` };
} finally {
  if (h) await shutdown(h);
  await srv.close();
}

const lines = [];
const line = (name, value) => { const l = `${name}=${value}`; lines.push(l); return l; };

line("binary", BINARY);
line("oracle_note", oracle.note);
if (page.statusText) for (const l of String(page.statusText).split("\n")) line("page", l);
if (page.stack) line("page_stack", String(page.stack).split("\n")[0]);
if (page.ran) for (const l of page.ladder ?? []) line("ladder", l);
if (page.ok === false && !page.ran) {
  line("verdict", "NO_RESULT");
  line("why", page.why);
} else if (page.exact !== page.total) {
  line("verdict", "MISMATCH");
  line("max_ulp", page.maxUlp);
  line("launches", page.launches);
  page.gpuBits.forEach((g, k) => line(`logit${k}`, `${g} ${g === page.cpuBits[k] ? "exact" : "DIFF"} cpu=${page.cpuBits[k]}`));
} else {
  line("verdict", "MATCH");
  line("launches", page.launches);
  line("ms", Math.round(page.ms));
  line("exact", `${page.exact}/${page.total}`);
  page.gpuBits.forEach((g, k) => line(`logit${k}`, `${g} cpu=${page.cpuBits[k]}`));
}
// The harness's own check, independent of the page's verdict field.
const agree = page.ok === true && page.exact === page.total && page.gpuBits?.length === want.length
  && page.gpuBits.every((g, k) => g === want[k]);
line("harness_agrees_with_oracle_file", agree);

// THIRD LANE. examples/beautiful_mnist.bend gates the model's shape walk against
// CPython; the browser lane here executes it. Agreeing shapes is what ties the two
// halves of this unit together, and it is read out of the Bend program's own row
// rather than retyped. `row_round_*=False` in that file is EXPECTED: its header
// records that helpers.bend's f32_fixed truncates where CPython rounds, and the
// two rows say so on purpose. They are not this check's business.
try {
  const bend = await readFile(resolve(HERE, "bmnist-run.txt"), "utf8");
  const row = (name) => bend.split("\n").find((l) => l.startsWith(name + "="))?.slice(name.length + 1);
  line("bend_mdl_walk", row("mdl_walk"));
  line("bend_mdl_out", row("mdl_out"));
  line("bend_mdl_lin_in", row("mdl_lin_in"));
  const net = JSON.parse(await readFile(resolve(PAGE_DIR, "net.json"), "utf8"));
  const last = net.kernels.at(-1);
  const linIn = last.bufs[last.outs.length];          // the last kernel's first NON-output binding
  line("browser_linear_in_elements", net.buffers[linIn].size);
  const linWeight = Object.values(net.buffers).find((b) => b.size === 5760);
  line("browser_has_10x576_linear_weight", !!linWeight);
  line("bend_lin_in_576_vs_browser", row("mdl_lin_in") === "(1,576)" && net.buffers[linIn].size === 576);
} catch (e) {
  line("bend_cross_check", `unavailable: ${e.message}`);
}

console.log(lines.join("\n"));
if (console_.length) { console.log("--- page console ---"); console.log(console_.join("\n")); }
else console.log("--- page console: (empty) ---");
await writeFile(resolve(HERE, "e2e.txt"), lines.join("\n") + "\n");
process.exit(agree ? 0 : 1);
