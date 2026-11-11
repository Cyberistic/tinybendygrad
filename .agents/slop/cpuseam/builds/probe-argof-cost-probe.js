// PROBE: **HOW MUCH DOES THE `arg_of` CHAIN'S TEST COUNT COST?**
//
// THE CHAIN IS **17 TESTS** (9 REAL ARMS AND **8 COMPILER-EMITTED BIT-MASK CATCH-ALLS**),
// AND **THE `x` KIND PAYS 16 OF THEM** FOR 127 ROWS. **IS THAT WORTH ANYTHING?**
//
// THE QUESTION MATTERS BECAUSE §137's REORDER EXPERIMENT FAILED, AND THE WORK STATE'S
// EXPLANATION WAS "**THE `KANone` CATCH-ALL STILL PAYS ALL 17 TESTS**" -- WHICH WAS **A
// READING OF THE **OLD** CHAIN**. ON THE **CURRENT** CHAIN, `KANone` PAYS **5**.
//
// THIS PROBE MEASURES **THE CHAIN'S OWN COST** IN JS, **ON THE REAL KIND SEQUENCE**, AND
// COMPARES IT WITH **A DIRECT MAP LOOKUP** (THE OBVIOUSLY-OPTIMAL SHAPE).

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");
const NAME = "function $_________tinybendygrad_renderer_live_arg_of(";
const start = src.indexOf(NAME);
const bodyStart = src.indexOf("{", start);
let depth = 0, bodyEnd = bodyStart;
for (let i = bodyStart; i < src.length; i += 1) {
  if (src[i] === "{") depth += 1;
  else if (src[i] === "}") { depth -= 1; if (depth === 0) { bodyEnd = i; break; } }
}
const body = src.slice(bodyStart, bodyEnd + 1);

// THE TESTS, IN COMPILED ORDER, AS JS EXPRESSIONS THAT EVALUATE TO A BOOLEAN.
const order = [];
const PAT = /(?:else\s+if|^\s*if)\s*\(([^)]*(?:\)[^)]*)*?)\)\s*\{/g;
let m;
while ((m = PAT.exec(body)) !== null) {
  const t = m[1].trim();
  const mm = /^\((_kind0_0) & (\d+)\) == (\d+)$/.exec(t);
  if (mm) order.push({ expr: `((k & ${mm[2]}) === ${mm[3]})`, mask: true, val: parseInt(mm[3], 10) });
  else {
    const mm2 = /^_kind0_0 == (\d+)$/.exec(t);
    if (mm2) order.push({ expr: `(k === ${mm2[1]})`, mask: false, val: parseInt(mm2[1], 10) });
  }
}
console.log(`THE CHAIN: ${order.length} TESTS`);

// THE WIRE'S REAL KIND SEQUENCE.
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const kinds = [];
for (let i = 0; i < parts.length; i += 9) kinds.push(parts[i + 5].charCodeAt(0));

// **THE CHAIN, AS A FUNCTION**: THE FIRST MATCHING ARM WINS, AND THE MASKS AND THE REAL
// ARMS ARE IN COMPILED ORDER.
function makeChain() {
  const src2 = order.map((t, i) =>
    `  if (${t.expr}) return ${t.mask ? '"MASK"' : '"REAL"'};`).join("\n");
  return new Function("k", `${src2}\n  return "DEFAULT";`);
}
const chain = makeChain();

// **THE COUNT**, AND **THE MAP LOOKUP**.
const counts = new Map();
let totalTests = 0;
for (const k of kinds) {
  let n = 0;
  for (const t of order) {
    n += 1;
    const v = t.mask ? ((k & parseInt(t.expr.match(/& (\d+)/)[1], 10)) === t.val) : (k === t.val);
    if (v) break;
  }
  totalTests += n;
  counts.set(k, (counts.get(k) || 0) + 1);
}
console.log(`THE TOTAL TESTS A TURN: ${totalTests} (FOR ${kinds.length} ROWS)`);
console.log(`THE AVERAGE: ${(totalTests / kinds.length).toFixed(2)}`);

const bench = (name, fn, reps) => {
  for (let i = 0; i < 20; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(40)} min ${xs[0].toFixed(4)}  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}  median ${xs[xs.length >> 1].toFixed(4)}`);
};

bench("THE CHAIN, ON THE REAL SEQUENCE", () => {
  let acc = 0;
  for (const k of kinds) acc += chain(k).length;
  return acc;
}, 2000);

bench("A DIRECT MAP LOOKUP", () => {
  const m = new Map();
  let acc = 0;
  for (const k of kinds) acc += (m.get(k) || 0);
  return acc;
}, 2000);

// **THE WHOLE ARG OF's COST, FOR SCALE**: THE CHAIN'S SHARE OF THE 0.232 ms.
const chainMs = (() => {
  for (let i = 0; i < 20; i += 1) { let a = 0; for (const k of kinds) a += chain(k).length; }
  const xs = [];
  for (let i = 0; i < 2000; i += 1) {
    const t0 = performance.now();
    let a = 0; for (const k of kinds) a += chain(k).length;
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  return xs[0];
})();
console.log(`\nTHE CHAIN'S OWN COST: ${chainMs.toFixed(4)} ms A TURN`);
console.log("AND THE MEASURED `arg_of` PHASE IS **0.2320 ms** -- SO THE CHAIN IS");
console.log(`**${(100 * chainMs / 0.2320).toFixed(1)}%** OF IT, AND **${(100 * chainMs / 1.0137).toFixed(1)}%** OF THE DECODE.`);
