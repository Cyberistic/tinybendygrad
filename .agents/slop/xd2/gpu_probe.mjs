// IS THERE A BROWSER WITH A WEBGPU ADAPTER ON THIS MACHINE?
//
// Both halves must hold, and only the second is obvious: `navigator.gpu` must
// EXIST (needs a secure context -- it is undefined on about:blank even in
// Chrome 154) and `requestAdapter()` must return a non-null adapter whose
// `requestDevice()` resolves.
//
// One JSON block per (binary, flag-set), so the answer is a table and not a
// rumour. gpu_probe.txt is the artifact.

import { writeFile, mkdir } from "node:fs/promises";
import { launch, shutdown, Session, CHROME_BINARIES } from "./cdp.mjs";
import { serve } from "./serve.mjs";

const PROBE = `
  const out = { url: location.href, secureContext: self.isSecureContext, gpu: !!navigator.gpu };
  if (!navigator.gpu) return out;
  let a = null, adapterErr = null;
  try { a = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" }); } catch (e) { adapterErr = String(e); }
  if (!a) { try { a = await navigator.gpu.requestAdapter(); } catch (e) { adapterErr = String(e); } }
  if (!a) return { ...out, adapter: false, adapterErr };
  const i = a.info ?? {};
  let device = null, deviceErr = null;
  try { device = await a.requestDevice(); } catch (e) { deviceErr = String(e); }
  return {
    ...out, adapter: true,
    vendor: i.vendor ?? null, architecture: i.architecture ?? null,
    device: i.device ?? null, description: i.description ?? null,
    features: [...a.features].sort(),
    maxComputeWorkgroupSizeX: a.limits.maxComputeWorkgroupSizeX,
    maxComputeInvocationsPerWorkgroup: a.limits.maxComputeInvocationsPerWorkgroup,
    maxStorageBufferBindingSize: a.limits.maxStorageBufferBindingSize,
    maxBufferSize: a.limits.maxBufferSize,
    deviceOk: !!device, deviceErr,
  };
`;

const CASES = [
  ["chrome-for-testing  headless=new", "chrome-for-testing", ["--headless=new"]],
  ["chrome-for-testing  headless=new + unsafe-swiftshader", "chrome-for-testing", ["--headless=new", "--enable-unsafe-swiftshader"]],
  ["chrome-for-testing  headless=new + unsafe-webgpu", "chrome-for-testing", ["--headless=new", "--enable-unsafe-webgpu"]],
  ["chrome-for-testing  headless=new + angle=metal", "chrome-for-testing", ["--headless=new", "--use-angle=metal", "--enable-unsafe-webgpu"]],
  ["chrome-for-testing  headed", "chrome-for-testing", []],
  ["chrome-stable 154  headless=new", "chrome-stable", ["--headless=new"]],
  ["chrome-stable 154  headed", "chrome-stable", []],
];

const root = new URL("./probe-root", import.meta.url).pathname;
await mkdir(root, { recursive: true });
await writeFile(root + "/index.html", `<!doctype html><meta charset=utf-8><title>gpu probe</title><body>probe`);
const srv = await serve(root);

const lines = [];
for (const [label, bin, flags] of CASES) {
  let h;
  let text;
  try {
    h = await launch(CHROME_BINARIES[bin], flags, srv.url + "/index.html");
    const s = await Session.openPage(h.port, { url: srv.url + "/index.html" });
    const r = await s.eval(PROBE, { timeoutMs: 90000 });
    s.close();
    text = JSON.stringify(r, null, 2);
    console.log(`\n### ${label}\n${text}`);
  } catch (e) {
    text = `LAUNCH/PROBE FAILED: ${String(e).slice(0, 300)}`;
    console.log(`\n### ${label}\n${text}`);
  } finally {
    if (h) await shutdown(h);
  }
  lines.push(`### ${label}\n${text}`);
  await writeFile(new URL("./gpu_probe.txt", import.meta.url).pathname, lines.join("\n\n"));
}
await srv.close();
