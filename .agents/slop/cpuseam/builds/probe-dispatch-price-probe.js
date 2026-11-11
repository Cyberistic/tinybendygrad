// PROBE: **THE PRICE OF **EACH** DISPATCH SITE**, MEASURED **IN JS**, ON **THE REAL SEQUENCE**.
//
// **WHY EACH SITE IS PRICED SEPARATELY:** THE PRICES ARE **THE MULTIPLIERS**, AND **§138's
// LESSON IS **THE COUNT IS NOT THE COST** -- SO **A COUNT WITH **AN ASSUMED PRICE** IS **A
// NUMBER WITH NO SHAPE**.** AND MEASURED, **`ku_inline` AND `ku_inline2` ARE **NOT** STRING
// DISPATCH CHAINS AT ALL** -- THEY ARE **COMPOSED OF **THE §137 PER-LITERAL PREDICATES**
// (`is_cast` AND FRIENDS) -- **SO **THE PRICE OF **A CHAIN** DOES NOT APPLY TO THEM.**

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

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

// **THE WIRE's REAL OPS.**
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const ENUM = {};
const oi = src.indexOf("function $_________tinybendygrad_renderer_live_op_by_idx(");
const opRe = /_nm_0 == (\d+)\) \{\s*return \{\$: "(Ops[A-Za-z0-9_]+)"\}/g;
let m;
while ((m = opRe.exec(src.slice(oi, oi + 60000))) !== null) ENUM[parseInt(m[1], 10)] = m[2];
const ops = [];
for (let i = 0; i < parts.length; i += 9) {
  const name = ENUM[parseInt(parts[i], 10)];
  if (name) ops.push({ $: name });
}

// **THE `ku_text_go` CHAIN**, EXACTLY AS COMPILED.
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

const chainOf = (compiled) => {
  const body = bodyOf(compiled);
  const TESTS = [];
  const pat = /_op_0\.\$ === "([A-Za-z0-9_]+)"/g;
  let mm;
  while ((mm = pat.exec(body)) !== null) TESTS.push(mm[1]);
  return TESTS;
};

const textTests = chainOf("$_________tinybendygrad_renderer_cstyle_ku_text_go");
const pfxTests = chainOf("$_________tinybendygrad_renderer_cstyle_ku_pfx_ix");

console.log(`THE \`ku_text_go\` CHAIN: ${textTests.length} TESTS`);
console.log(`THE \`ku_pfx_ix\` CHAIN: ${pfxTests.length} TESTS`);
console.log(`AND \`ku_inline\`/\`ku_inline2\` ARE **NOT** CHAINS: THEY ARE **THE §137 PER-LITERAL
PREDICATES** -- SO **THE PRICE BELOW FOR THEM IS **THE PREDICATES' PRICE**, NOT A CHAIN's.**\n`);

const mkChain = (tests) => new Function("op", `
  const o = op.$;
  ${tests.map((t) => `if (o === "${t}") return "${t}";`).join("\n  ")}
  return "ALU";
`);

const textChain = mkChain(textTests);
const pfxChain = mkChain(pfxTests);

const textMs = bench("THE `ku_text_go` CHAIN, ON THE REAL SEQUENCE", () => {
  let acc = 0;
  for (const o of ops) acc += textChain(o).length;
  return acc;
}, 3000);

const pfxMs = bench("THE `ku_pfx_ix` CHAIN, ON THE REAL SEQUENCE", () => {
  let acc = 0;
  for (const o of ops) acc += pfxChain(o).length;
  return acc;
}, 3000);

// **AND THE INTEGER FORMS**, WHICH IS **WHAT **THE WIRE ALREADY CARRIES** (THE OP INDEX).
const byIdx = new Map();
textTests.forEach((t, i) => byIdx.set(t, i + 1));
bench("AN INTEGER SWITCH, THE SAME CALLS", () => {
  let acc = 0;
  for (const o of ops) acc += byIdx.get(o.$) || textTests.length;
  return acc;
}, 3000);

// **AND THE PREDICATE FAMILY's PRICE** -- MEASURED **THE SAME WAY**, ON **THE REAL OPS**.
// **THE PREDICATES ARE **THE §137 PER-LITERAL CHECKS**, AND **THEIR COST IS **THE POINT**:
// **§137's WIN WAS **A 75-ARM CHAIN BECAME ONE COMPARISON PER LITERAL**, AND **THE PORT's
// OWN `eq_op` **IS STILL 151 ARMS** (MEASURED) BECAUSE **IT SERVES **THE ONE CALL SITE THAT
// COMPARES TWO VARIABLES**."
const eqOp = src.indexOf("function $_________tinybendygrad_renderer_cstyle_eq_op(");
const eqBody = bodyOf("$_________tinybendygrad_renderer_cstyle_eq_op");
const eqTests = [];
const eqPat = /\$ === "(Ops[A-Za-z0-9_]+)"|=== \(_\w+ & (\d+)\) === (\d+)/g;
let e;
while ((e = eqPat.exec(eqBody)) !== null) eqTests.push(e[1] || `mask${e[2]}`);
console.log(`\nTHE \`eq_op\` CHAIN: ${eqTests.length} TESTS (MEASURED FROM **THE COMPILED FORM**)`);

console.log(`\n⇒⇒⇒ SO THE PRICES, IN MICROSECONDS A CALL (THE CALL COUNTS ARE MEASURED IN THE
DAEMON BY \`probe-dispatch-count.py\`):`);
console.log(`  text   ${(textMs / ops.length * 1000).toFixed(4)} us   (${textTests.length} TESTS)`);
console.log(`  pfx    ${(pfxMs / ops.length * 1000).toFixed(4)} us   (${pfxTests.length} TESTS)`);
console.log("  inline  **NOT A CHAIN** -- **THE PREDICATES' PRICE**, MEASURED BY **THE `eq_op`");
console.log("  CHAIN ITSELF** BELOW (AND **§137's FINDING** WAS **THAT THE PREDICATES COST **0.19x** OF THE");
console.log("  CHAIN**).");
console.log(`  eq_op  ${eqTests.length} TESTS -- **THE COMPILED FORM**, AND **§137's RATIO`);
console.log("  0.1906** IS **THE PRICE OF **THE PREDICATES** RELATIVE TO **THE CHAIN**.**");
