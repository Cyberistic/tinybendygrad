// wasi_run.mjs -- run a wasm32-wasi command module and forward its output.
//   node wasi_run.mjs <module.wasm> [args...]
//
// wasm32-wasi-musl builds a WASI *command*: the module exports _start, not a
// callable library.  So this lane is exercised the way a WASI host runs a
// command, which is also how the SDK's wasm backend drives it.
import { WASI } from "node:wasi";
import { readFile } from "node:fs/promises";
import { argv, exit } from "node:process";

const [file, ...rest] = argv.slice(2);
const wasi = new WASI({
  version: "preview1",
  args: [file, ...rest],
  env: {},
  preopens: {},
  stdout: 1,
  stderr: 2,
  returnOnExit: true,
});
const { instance } = await WebAssembly.instantiate(
  await readFile(file),
  wasi.getImportObject(),
);
wasi.start(instance);
exit(wasi.exitCode);
