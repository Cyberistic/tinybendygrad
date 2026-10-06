// A static file server, because WebGPU needs a SECURE CONTEXT and `about:blank`
// is an opaque origin where `navigator.gpu` is undefined. 127.0.0.1 is a
// potentially-trustworthy origin, so http://127.0.0.1:PORT is enough.

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".wgsl": "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
  ".safetensors": "application/octet-stream",
  ".bin": "application/octet-stream",
};

/** Serve `root` on 127.0.0.1. Resolves with { url, close }. */
export async function serve(root, { port = 0 } = {}) {
  const base = resolve(root);
  const server = createServer(async (req, res) => {
    try {
      const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
      // normalize() collapses `..` before the prefix check, so no escape.
      const rel = normalize(path === "/" ? "/index.html" : path).replace(/^([/\\])+/, "");
      const file = join(base, rel);
      if (file !== base && !file.startsWith(base + sep)) { res.writeHead(403).end("forbidden"); return; }
      const info = await stat(file);
      if (!info.isFile()) { res.writeHead(404).end("not a file"); return; }
      const body = await readFile(file);
      res.writeHead(200, {
        "content-type": MIME[extname(file)] ?? "application/octet-stream",
        "content-length": body.length,
        "cache-control": "no-store",
        // Not required for WebGPU, but the page should not need any cross-origin grant.
        "cross-origin-opener-policy": "same-origin",
      }).end(body);
    } catch {
      res.writeHead(404, { "content-type": "text/plain" }).end("not found");
    }
  });
  await new Promise((r) => server.listen(port, "127.0.0.1", r));
  const actual = server.address().port;
  return { url: `http://127.0.0.1:${actual}`, port: actual, close: () => new Promise((r) => server.close(r)) };
}
