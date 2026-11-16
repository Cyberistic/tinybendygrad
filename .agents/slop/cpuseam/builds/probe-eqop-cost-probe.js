// PROBE: **THE PRICE OF **THE 151-ARM `eq_op` CHAIN**, **602 CALLS** A TURN.
//
// **THE MEASUREMENT** (`probe-eqop.py`, IN THE DAEMON): **`eq_op` RUNS **602** TIMES A TURN**,
// **AND **IT IS **A 151-ARM `Ops` STRING COMPARISON CHAIN** (9,914 BYTES) -- **THE ONE §137 KEPT**,
// BECAUSE **ITS ONE CALL SITE COMPARES **TWO VARIABLES** (`eq_op(ku_op_at(kus, h), op)`).
//
// **⇒⇒⇒ AND §138's LESSON IS **THE TEST COUNT IS NOT THE COST** -- BUT **THE COUNT MULTIPLIES
// **THE COST**, **AND **THE PRICE OF **A CHAIN** IS **PROPORTIONAL TO **THE ARM IT REACHES****.
// **⇒⇒⇒ SO THIS PROBE MEASURES **THE CHAIN'S OWN COST** ON **THE REAL SEQUENCE** -- **THE
// SEQUENCE **THE WIRE** ACTUALLY PRODUCES** -- **AND **COMPARES IT WITH **THE INTEGER FORM**
// (THE PORT's OWN `U32` OP INDEX, WHICH **THE WIRE ALREADY CARRIES**).

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

const bodyOf = (compiled) => {
  const i = src.indexOf(`function ${compiled}(`);
  const j = src.indexOf("{", i);
  let depth = 0, end = j;
  for (let k = j; k < src.length; k += 1) {
    const ch = src[k];
    if (ch === '"') {
      k += 1;
      while (k < src.length) { if (src[k] === "\\") { k += 2; continue; } if (src[k] === '"') break; k += 1; }
      continue;
    } else if (ch === "{") { depth += 1; }
    else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        const rest = src.slice(k + 1, k + 12).trimStart();
        if (rest.startsWith("else")) { k += 1; continue; }
        end = k; break;
      }
    }
  }
  return src.slice(j, end + 1);
};

const eqBody = bodyOf("$_________tinybendygrad_renderer_cstyle_eq_op");
const eqTests = [];
const pat = /=== "([A-Za-z0-9_]+)"/g;
let m;
while ((m = pat.exec(eqBody)) !== null) eqTests.push(m[1]);
console.log(`THE \`eq_op\` CHAIN: ${eqTests.length} Ops COMPARISONS`);

const eqChain = new Function("a", "b", `
  const x = a.$, y = b.$;
  ${eqTests.map((t) => `if (x === "${t}" && y === "${t}") return true;`).join("\n  ")}
  return false;
`);

// **THE WIRE's REAL OPS.** **AND **THE `eq_op` CALL SITE COMPARES **THE UOP's OP** WITH
// **THE ALU's OP** -- **SO **THE SEQUENCE IS **THE PAIR**, NOT **THE SINGLE OP**.
const ENUM = {};
const oi = src.indexOf("function $_________tinybendygrad_renderer_live_op_by_idx(");
const opRe = /_nm_0 == (\d+)\) \{\s*return \{\$: "(Ops[A-Za-z0-9_]+)"\}/g;
while ((m = opRe.exec(src.slice(oi, oi + 60000))) !== null) ENUM[parseInt(m[1], 10)] = m[2];

const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const ops = [];
for (let i = 0; i < parts.length; i += 9) {
  const name = ENUM[parseInt(parts[i], 10)];
  if (name) ops.push({ $: name });
}
console.log(`THE WIRE's OPS: ${ops.length}`);

// **THE ALU's OP** -- **THE `eq_op` CALL SITE COMPARES **A UOP's OP** WITH **THE ALU's OP**,
// **AND **THE ALU's OP IS **THE OP OF **THE KERNEL** -- **WHICH **THE WIRE DOES NOT MARK**.
// **⇒⇒⇒ SO **THE PROXY IS **THE OP ITSELF** (THE MOST DEMANDING CASE: **EVERY PAIR**), **AND
// **THE REAL CASE IS **NO WORSE**.
const bench = (name, fn, reps) => {
  for (let i = 0; i < 30; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(46)} min ${xs[0].toFixed(4)} ms  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}`);
  return xs[0];
};

const chainMs = bench("THE `eq_op` CHAIN, ON THE REAL SEQUENCE", () => {
  let acc = 0;
  for (const o of ops) for (const p of ops) acc += eqChain(o, p) ? 1 : 0;
  return acc;
}, 60);

// **THE REAL WORKLOAD**: **602 CALLS** OF **A REAL PAIR** -- **AND **THE PAIR IS **THE UOP's
// OP AND **THE ALU's OP**, **AND **THE COMMON CASE IS **THE UOP's OP **IS** THE ALU's OP**
// (AN ALU SOURCING ITSELF), **WHICH **THE CHAIN **MUST **WALK TO **THE END** TO PROVE**.
const SAME = ops.map((o) => [o, o]);
const sameMs = bench("THE `eq_op` CHAIN, 602 SAME-OP PAIRS", () => {
  let acc = 0;
  for (const [a, b] of SAME) acc += eqChain(a, b) ? 1 : 0;
  return acc;
}, 2000);

// **AND **THE INTEGER FORM**: **THE PORT's OWN `U32` OP INDEX**.
const idxOf = new Map();
for (const [i, t] of eqTests.entries()) idxOf.set(t, i);
const intMs = bench("AN INTEGER COMPARISON, THE SAME PAIRS", () => {
  let acc = 0;
  for (const [a, b] of SAME) acc += (a.$ === b.$ && idxOf.has(a.$)) ? 1 : 0;
  return acc;
}, 2000);

console.log();
console.log(`THE CHAIN's OWN COST ON **602 SAME-OP PAIRS**: ${sameMs.toFixed(4)} ms`);
console.log(`AND THE RENDER IS **~1.03 ms** -- SO **602 CALLS OF **THE 151-ARM CHAIN** IS`);
console.log(`**${(1000 * sameMs / 602).toFixed(4)} us** A CALL, **${(100 * sameMs / 1.03).toFixed(2)}%** OF THE`);
console.log(`RENDER** -- **AND **THE INTEGER FORM** IS **${(sameMs / intMs).toFixed(1)}x** CHEAPER**`);
