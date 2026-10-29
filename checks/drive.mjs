// drive.mjs -- drive the LIVE tinybendygrad/runtime/dtype.js under plain node.
//
// WHY A DIRECT DRIVER AND NOT A .bend SEAM. `Dt.fp8_to` is PURE in dtype.bend
// (:916 `def Dt.fp8_to(bits: U32, +kind: U32) -> F32`), so it imports no .js seam
// and `dtype.js:151 fp8_decode` is UNREACHED from any .bend. And the seam that
// does exist, `dtype_fp8_to`, ends in `of32(...)`, which hands the pattern to
// JavaScript -- so the one row this unit must gate (e4m3's unsigned NaN) is a
// float that cannot tell 0x7FC00000 from 0xFFC00000. Reaching `fp8_decode`'s own
// return value is the only way to see the pattern, which is why the gate is a
// direct driver and not a seam. Same shape as .agents/slop/fp8fix/build.py,
// which compiles the live dtype.c instead of going through dtype.bend.
//
// WHAT IS APPENDED, AND WHY THAT IS HONEST. `fp8_decode` is module-local, so the
// driver appends EXACTLY one line -- an export list -- to the live file's bytes
// and md5s the result. `gate.py` asserts the appended text equals `APPEND`, and
// the printed `SRC_MD5` pair lets the log prove which bytes ran.
//
// `CID(k)` compiles to the string `k` in the JS backend (comp.ts:2866), so the
// shim is the identity and the keys are the names in dtype.js's own io_eff calls.
//
// USAGE: node drive.mjs <dtype.js> <workdir>   reading <workdir>/work.json.

import {createHash} from "node:crypto";
import {mkdirSync, readFileSync, writeFileSync} from "node:fs";
import {argv} from "node:process";
import {pathToFileURL} from "node:url";

const APPEND = "\nexport {fp8_encode, fp8_decode, FP8_CFG, of32, bits32};\n";

const [src, work] = argv.slice(2);
const bytes = readFileSync(src, "utf8");
mkdirSync(work, {recursive: true});
const probe = `${work}/dtype.probe.mjs`;
writeFileSync(probe, bytes + APPEND);

const EFFECTS = {};
// `Dt` is a module-local `let` in the generated JS; here it is the namespace
// object the ten `io_eff` lines index. `CID(k)` compiles to the string `k` in
// the JS backend (comp.ts:2866), so the identity shim makes each CID its own
// fully-qualified name and the registration keys are readable.
const CIDS = ["bf16", "fp16", "fp8_from", "fp8_to", "i64_trunc", "i64_floor_div",
  "i64_floor_mod", "i64_cdiv", "i64_cmod", "i64_ceildiv"];
globalThis.Dt = Object.fromEntries(CIDS.map((n) => [n, `Dt.${n}`]));
globalThis.CID = (k) => k;
globalThis.io_eff = (k, run) => {
  if (EFFECTS[k] !== undefined) throw new Error("two effects register " + k);
  EFFECTS[k] = run;
};
const {fp8_encode, fp8_decode} = await import(pathToFileURL(probe).href);

const md5 = (s) => createHash("md5").update(s).digest("hex");
const out = [`SRC_MD5 ${md5(bytes)}`,
  `APPEND ${JSON.stringify(APPEND)}`,
  // A census with a zero denominator has found nothing to look at: this line
  // says the ten registrations in dtype.js really ran, and names them.
  `REGISTERED ${Object.keys(EFFECTS).sort().join(" ")}`];

// Each family answers in its own unit -- `fp8_encode` a CODE, `fp8_decode` an
// f32 PATTERN -- so each is printed at its own width. One width for both would
// make every row a string mismatch and the count mean nothing.
for (const [fam, x, kind, name] of JSON.parse(readFileSync(`${work}/work.json`, "utf8"))) {
  const v = fam === "E" ? fp8_encode(x, kind) : fp8_decode(x, kind);
  out.push(`JROW ${name} = ${(v >>> 0).toString(16).padStart(fam === "E" ? 2 : 8, "0")}`);
}
process.stdout.write(out.join("\n") + "\n");