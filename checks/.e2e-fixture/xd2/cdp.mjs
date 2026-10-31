// Minimal Chrome DevTools Protocol client. Node >=22 (global WebSocket, no deps).
// One file, one job: drive a Chrome started with --remote-debugging-port.
//
// TWO MEASURED CONSTRAINTS shape this file, and both cost real time to find:
//
//  1. **Launch Chrome already AT the page URL.** `Page.navigate` on a directly
//     attached page target drops its reply and wedges the session: the target's
//     URL changes (visible in Target.getTargets) but every later command on that
//     socket times out. Creating the tab from the command line has no
//     cross-document transition to survive, so nothing is lost.
//
//  2. **Connect to the page target's own WebSocket** (from /json/list), not to
//     the browser socket plus Target.attachToTarget. The browser socket answers
//     Target.getTargets and then rejects `Page.enable` with -32601, because
//     sessionId routing is a second mechanism that this does not need.
//
// WebGPU additionally needs a SECURE CONTEXT: `navigator.gpu` is undefined on
// about:blank even in Chrome 154, and defined on http://127.0.0.1.

import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const CHROME_BINARIES = {
  "chrome-for-testing": "/Users/cyberistic/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  "chrome-stable": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
};

/** Launch Chrome with `url` as its first tab. Resolves once DevTools is up. */
export async function launch(binary, flags = [], url = "about:blank") {
  if (!existsSync(binary)) throw new Error(`no chrome binary at ${binary}`);
  const dir = await mkdtemp(join(tmpdir(), "cdp-"));
  const proc = spawn(binary, [
    "--remote-debugging-port=0",
    "--remote-allow-origins=*", // Node's WebSocket sends an Origin header; DevTools rejects it
    `--user-data-dir=${dir}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    ...flags,
    url,
  ], { stdio: ["ignore", "pipe", "pipe"] });
  const stderr = [];
  proc.stderr.on("data", (d) => stderr.push(String(d)));

  const portFile = join(dir, "DevToolsActivePort");
  const deadline = Date.now() + 30000;
  let port = null;
  while (Date.now() < deadline) {
    if (existsSync(portFile)) {
      const [p] = (await readFile(portFile, "utf8")).split("\n");
      if (p?.trim()) { port = Number(p.trim()); break; }
    }
    if (proc.exitCode !== null) throw new Error(`chrome exited ${proc.exitCode}: ${stderr.join("").slice(-800)}`);
    await new Promise((r) => setTimeout(r, 50));
  }
  if (!port) throw new Error(`no DevToolsActivePort in ${dir}: ${stderr.join("").slice(-800)}`);
  return { proc, port, dir };
}

/** A CDP session against one page target. */
export class Session {
  constructor(ws) { this.ws = ws; this.id = 0; this.waiting = new Map(); this.log = []; }

  /** Attach to the tab Chrome opened, and resolve once it has finished loading. */
  static async openPage(port, { url, timeoutMs = 60000 } = {}) {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const target = list.find((t) => t.type === "page" && (!url || t.url === url)) ?? list.find((t) => t.type === "page");
    if (!target) throw new Error(`no page target: ${JSON.stringify(list).slice(0, 300)}`);
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("websocket refused")); });
    const s = new Session(ws);
    ws.addEventListener("message", (ev) => s.dispatch(JSON.parse(ev.data)));
    await s.send("Page.enable");
    await s.send("Runtime.enable");
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const r = await s.send("Runtime.evaluate", { expression: "document.readyState", returnByValue: true }, 10000).catch(() => null);
      if (r?.result.value === "complete") break;
      if (Date.now() > deadline) throw new Error(`page never reached readyState=complete (at ${target.url})`);
      await new Promise((res) => setTimeout(res, 50));
    }
    return s;
  }

  /** Route a CDP frame: replies resolve their waiter. Console/exceptions are kept
   *  in `log` so a page can report progress without scraping the DOM. */
  dispatch(m) {
    if (m.id !== undefined) {
      const w = this.waiting.get(m.id);
      if (!w) return;
      this.waiting.delete(m.id);
      clearTimeout(w.timer);
      if (m.error) w.rej(new Error(`${m.error.message} (${m.error.code})`));
      else w.res(m.result);
      return;
    }
    if (m.method === "Runtime.consoleAPICalled") {
      this.log.push(m.params.args.map((a) => a.value ?? a.description ?? a.type).join(" "));
    } else if (m.method === "Runtime.exceptionThrown") {
      this.log.push(`PAGE-EXCEPTION ${m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text}`);
    }
  }

  send(method, params = {}, timeoutMs = 30000) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res, rej) => {
      const w = { res, rej };
      w.timer = setTimeout(() => { if (this.waiting.delete(id)) rej(new Error(`timeout ${method}`)); }, timeoutMs);
      this.waiting.set(id, w);
    });
  }

  /** Evaluate an async body in the page, awaiting promises, returning JSON. */
  async eval(body, { timeoutMs = 120000 } = {}) {
    const r = await this.send("Runtime.evaluate", {
      expression: `(async () => { ${body} })()`,
      awaitPromise: true, returnByValue: true, timeout: timeoutMs,
    }, timeoutMs + 5000);
    if (r.exceptionDetails) {
      return { __error: r.exceptionDetails.exception?.description ?? JSON.stringify(r.exceptionDetails) };
    }
    return r.result.value;
  }

  close() { try { this.ws.close(); } catch {} }
}

export async function shutdown(h) {
  try { h.proc.kill("SIGKILL"); } catch {}
  try { await rm(h.dir, { recursive: true, force: true }); } catch {}
}
