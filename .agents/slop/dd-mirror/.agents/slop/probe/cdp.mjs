// A CDP runner: headless Chrome + a real navigator.gpu, driven from a page.
// Used to establish whether an adapter EXISTS on this machine, and later to run
// the real webgpu_call.js driver against it.
//
// Usage: bun .agents/slop/probe/cdp.mjs <url> <js-to-eval> [timeoutMs]
const [, , url, expr, tmo] = process.argv;
const PORT = process.env.CDP_PORT || "9222";

const deadline = Date.now() + Number(tmo || 60000);
async function targets() {
  for (;;) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/new?${encodeURIComponent(url)}`, { method: "PUT" });
      if (r.ok) return await r.json();
    } catch (e) { /* chrome not up yet */ }
    if (Date.now() > deadline) throw new Error("no devtools endpoint in time");
    await new Promise(r => setTimeout(r, 300));
  }
}

const t = await targets();
const ws = new WebSocket(t.webSocketDebuggerUrl);
let id = 0;
const waiting = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
};
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
const send = (method, params) => new Promise((res) => { const i = ++id; waiting.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });

await send("Runtime.enable", {});
const r = await send("Runtime.evaluate", {
  expression: expr, awaitPromise: true, returnByValue: true, timeout: 60000,
});
if (r.result?.exceptionDetails) {
  console.log("EXCEPTION " + JSON.stringify(r.result.exceptionDetails.exception?.description ?? r.result.exceptionDetails.text));
} else {
  console.log(typeof r.result?.result?.value === "string" ? r.result.result.value : JSON.stringify(r.result?.result?.value, null, 1));
}
ws.close();
process.exit(0);