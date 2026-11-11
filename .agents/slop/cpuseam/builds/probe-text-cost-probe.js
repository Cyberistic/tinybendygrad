// PROBE: **HOW MUCH DOES THE `ku_text_go` DISPATCH COST, IN JS?**
//
// **THE CHAIN IS **16 STRING COMPARISONS** ON `_op_0.$`, AND **432 OF 782 ROWS (55%) FALL
// THROUGH** TO THE `else` -- **10,088 COMPARISONS A TURN**, MEASURED ON **THE REAL WIRE**.
//
// **⇒⇒⇒ AND §138's LESSON IS **THE TEST**:** THE `arg_of` CHAIN WAS **17 TESTS** AND IT COST
// **0.0020 ms** OF A **0.2320 ms** PHASE -- **0.9%** -- **SO A DISPATCH IS **NOT** NECESSARILY
// THE COST**, AND **THE COUNT IS NOT THE VERDICT**.
//
// **⇒⇒⇒ SO THIS PROBE MEASURES **THE CHAIN'S OWN COST**, ON **THE REAL KIND SEQUENCE**, AND
// COMPARES IT WITH **A DIRECT LOOKUP** (THE OBVIOUSLY-OPTIMAL SHAPE) -- **AND WITH **THE
// WHOLE RENDER**, **SO THE ANSWER IS **A SHARE** AND NOT **A NUMBER**.

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// **THE COMPILED CHAIN, EXACTLY.**
const NAME = "function $_________tinybendygrad_renderer_cstyle_ku_text_go(";
const i = src.indexOf(NAME);
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
const body = src.slice(j, end + 1);

// **THE TESTS, IN COMPILED ORDER.**
const TESTS = [];
const pat = /_op_0\.\$ === "([A-Za-z0-9_]+)"/g;
let m;
while ((m = pat.exec(body)) !== null) TESTS.push(m[1]);

// **THE CHAIN, AS A FUNCTION** -- THE COMPILED FORM'S EXACT SEMANTICS: THE FIRST MATCH WINS,
// AND **THE `else` IS THE LAST ARM**.
const chain = new Function("op", `
  const o = op.$;
  ${TESTS.map((t) => `if (o === "${t}") return "${t}";`).join("\n  ")}
  return "ALU";
`);

// **THE WIRE's REAL OPS.**
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
// **THE OP INDEX -> THE OPS's NAME**, READ FROM **THE COMPILED `op_by_idx`** (NOT GUESSED).
const ENUM = {};
const oi = src.indexOf("function $_________tinybendygrad_renderer_live_op_by_idx(");
const opRe = /_nm_0 == (\d+)\) \{\s*return \{\$: "(Ops[A-Za-z0-9_]+)"\}/g;
while ((m = opRe.exec(src.slice(oi, oi + 60000))) !== null) ENUM[parseInt(m[1], 10)] = m[2];
const ops = [];
for (let i = 0; i < parts.length; i += 9) {
  const name = ENUM[parseInt(parts[i], 10)];
  if (name) ops.push({ $: name });
}

console.log(`THE CHAIN: ${TESTS.length} TESTS, AND ${ops.length} ROWS WITH A KNOWN OP`);

const bench = (name, fn, reps) => {
  for (let i = 0; i < 30; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(44)} min ${xs[0].toFixed(4)}  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}  median ${xs[xs.length >> 1].toFixed(4)}`);
  return xs[0];
};

const chainMs = bench("THE CHAIN, ON THE REAL SEQUENCE", () => {
  let acc = 0;
  for (const o of ops) acc += chain(o).length;
  return acc;
}, 3000);

bench("A MAP LOOKUP (THE OPTIMAL SHAPE)", () => {
  const m = new Map();
  let acc = 0;
  for (const o of ops) acc += (m.get(o.$) || 0);
  return acc;
}, 3000);

// **AND THE SWITCH FORM** -- WHAT A `match` ON AN **INTEGER** WOULD COMPILE TO.
const byIdx = new Map();
for (const t of TESTS) byIdx.set(t, TESTS.indexOf(t) + 1);
bench("AN INTEGER SWITCH (THE `match` ON A `U32` FORM)", () => {
  let acc = 0;
  for (const o of ops) acc += byIdx.get(o.$) || TESTS.length;
  return acc;
}, 3000);

console.log(`\nTHE CHAIN's OWN COST: ${chainMs.toFixed(4)} ms A TURN`);
console.log(`AND **THE TRUE RENDER IS **1.03 ms** (MEASURED, THE PAIRED INSTRUMENT, THE MINIMUM)`);
console.log(`**⇒⇒⇒ SO THE DISPATCH IS **${(100 * chainMs / 1.03).toFixed(2)}%** OF THE RENDER.`);
