/**
 * bench.ts -- run the same payload through both backends and print a table.
 *
 * Two things are measured, and the second is the point:
 *
 *   - agreement: both backends must answer the same eight f32 bits, or the
 *     run fails and says which lane moved;
 *   - cost: min-of-5 wall time per backend, because a min is the only number
 *     that is not really a measurement of the scheduler.
 *
 * `min of 5` is the contract, so that is what is printed, along with the
 * machine load the numbers were taken at -- a timing without load is a
 * rumour.  Node is the harness; a browser is a manual step, and the SDK's
 * dispatch is identical there because it is the same module.
 *
 *     node --experimental-strip-types langs/sdk/bench.ts
 */
import { execFileSync, execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { BendLibrarySDK, PAYLOAD, type Answer } from "./bend_sdk.ts";
import { WALL } from "./bend_wasm.ts";

/** The contract: five runs, keep the fastest. */
const RUNS = 5;

const here = path.dirname(fileURLToPath(import.meta.url));
const langs = path.resolve(here, "..");
const vector = path.resolve(langs, "vectors", "payload.rows");

/** The payload, as the 42 numbers every lane speaks. */
function readPayload(): number[] {
  return fs.readFileSync(vector, "utf8").trim().split(",").map(Number);
}

/** How loaded the machine is, so a timing can be read in context. */
function loadAverage(): string {
  try {
    return execSync("sysctl -n vm.loadavg", { encoding: "utf8" }).trim();
  } catch {
    return execSync("cat /proc/loadavg", { encoding: "utf8" })
      .split(" ")
      .slice(0, 3)
      .join(" ");
  }
}

function cpuModel(): string {
  try {
    return execSync("sysctl -n machdep.cpu.brand_string", { encoding: "utf8" }).trim();
  } catch {
    return "unknown CPU";
  }
}

/** Milliseconds, to three places, which is well past timer resolution here. */
function ms(value: number): string {
  return value.toFixed(3).padStart(9);
}

/** Run one backend `RUNS` times and keep the fastest. */
function timeBackend(sdk: BendLibrarySDK, data: readonly number[]): {
  best: number;
  answer: Answer;
} {
  let best = Number.POSITIVE_INFINITY;
  let answer: Answer | undefined;
  for (let i = 0; i < RUNS; i += 1) {
    const t0 = performance.now();
    const got = sdk.executeTask(data);
    const dt = performance.now() - t0;
    if (answer === undefined) answer = got;
    else if (answer.join(",") !== got.join(",")) {
      throw new Error(`${sdk.backendName} run ${i} disagreed with its own run 0`);
    }
    if (dt < best) best = dt;
  }
  if (answer === undefined) throw new Error("no runs");
  return { best, answer };
}

/** One lane that is a separate process, timed the same way. */
function timeProcess(bin: string, args: readonly string[]): number | undefined {
  if (!fs.existsSync(bin)) return undefined;
  let best = Number.POSITIVE_INFINITY;
  for (let i = 0; i < RUNS; i += 1) {
    const t0 = performance.now();
    execFileSync(bin, args as string[], { encoding: "utf8" });
    const dt = performance.now() - t0;
    if (dt < best) best = dt;
  }
  return best;
}

const data = readPayload();
if (data.length !== PAYLOAD) {
  throw new Error(`payload.rows holds ${data.length} numbers, wanted ${PAYLOAD}`);
}

console.log("Bend core_step benchmark");
console.log(`  payload   ${vector}`);
console.log(`  cpu       ${cpuModel()}`);
console.log(`  loadavg   ${loadAverage()}  (1m 5m 15m)`);
console.log(`  node      ${process.version}`);
console.log(`  runs      min of ${RUNS}, per backend, same payload`);
console.log("");

// The JS backend is always available, so it is the floor the table is read
// against; the wasm backend is attempted by the same init() a consumer uses.
const rows: { name: string; best: number; answer: Answer; note: string }[] = [];

const jsSdk = await BendLibrarySDK.init({ forceJS: true });
const jsRun = timeBackend(jsSdk, data);
rows.push({
  name: "sdk/js forced",
  best: jsRun.best,
  answer: jsRun.answer,
  note: jsSdk.wasmReason ?? "",
});

const autoSdk = await BendLibrarySDK.init();
const autoRun = timeBackend(autoSdk, data);
rows.push({
  name: `sdk/${autoSdk.backendName} auto`,
  best: autoRun.best,
  answer: autoRun.answer,
  note: autoSdk.wasmReason ?? "",
});

console.log("  backend           min ms   answer bits");
console.log("  " + "-".repeat(78));
for (const r of rows) {
  console.log(`  ${r.name.padEnd(17)} ${ms(r.best)}   ${r.answer.join(",")}`);
}
console.log("");

// Agreement is a gate, not a remark.
const reference = rows[0];
for (const r of rows.slice(1)) {
  if (r.answer.join(",") !== reference.answer.join(",")) {
    console.error(`FAIL ${r.name} disagrees with ${reference.name}`);
    console.error(`  ${reference.name}: ${reference.answer.join(",")}`);
    console.error(`  ${r.name}: ${r.answer.join(",")}`);
    process.exit(1);
  }
}
console.log(`AGREE   ${rows.length} backends, ${reference.answer.length} f32, bit identical`);
console.log(`LOSS    ${jsSdk.loss(reference.answer)}  (f32 ${reference.answer[0]})`);
if (autoSdk.fellBack) {
  console.log(`FELL BACK to ${autoSdk.backendName}: ${autoSdk.wasmReason ?? "unknown"}`);
  console.log(`WASM LANE: ${WALL}`);
}

// The native binary and the C build are timed here too, even though they are
// not SDK backends: a table with only two JS rows says nothing about cost, and
// process startup is included so the numbers are comparable rather than
// flattering.  Both are whole-process timings, which is why they are larger.
console.log("");
console.log("  non-SDK lanes, whole process including startup");
console.log("  " + "-".repeat(78));
for (const bin of ["core_native", "core_c"]) {
  const t = timeProcess(path.join(langs, "out", bin), [vector.trim()]);
  console.log(
    t === undefined
      ? `  ${bin.padEnd(17)}       n/a   not built; run langs/verify.sh first`
      : `  ${bin.padEnd(17)} ${ms(t)}   (process start, run, exit)`,
  );
}
