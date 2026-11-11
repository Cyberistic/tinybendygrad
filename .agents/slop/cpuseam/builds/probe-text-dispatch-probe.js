// PROBE: **THE COMPILED `ku_text_go` DISPATCH, AND **WHAT EACH OP PAYS**.
//
// **WHY THIS IS **A COUNT** AND NOT A CLOCK**: THE `text` FAMILY IS **RECURSIVE** (`ku_text_go`
// CALLS `ku_text_*` WHICH CALLS `ku_text_go`), **SO CLOCKING IT **INFLATES THE MEASUREMENT**
// (MEASURED: WRAPPING ALL **46** FUNCTIONS READS THE RENDER AT **13.34 ms** AGAINST **THE TRUE
// 1.04 ms** -- **12x**). **⇒⇒⇒ AND §138's LESSON APPLIES EXACTLY**: **THE DISPATCH IS **A
// COUNT**, AND **THE COUNT COSTS NOTHING AT RUNTIME**.
//
// **AND THE DISPATCH IS **THE PORT's OWN COST**: THE COMPILED FORM IS **A CHAIN OF STRING
// COMPARISONS** ON `_op_0.$`, SO **THE COST IS THE NUMBER OF COMPARISONS AN OP PAYS** -- AND
// **THAT IS A COUNT OF THE COMPILED FORM**, WHICH IS **A FACT ABOUT THE TREE** AND NOT **A
// MEASUREMENT OF THE LOAD**.
//
// **AND THE COUNT IS **COMPUTED FROM **THE REAL WIRE**, SO IT IS **THE PORT's REAL WORK**.
//
// **THE QUESTION:** THE `ku_text_*` FAMILY IS §137's PROFILER's NAMED TOP LEAF (`ku_text`
// **1.157 ms**), AND **NO INSTRUMENT HAS EVER COUNTED ITS DISPATCH.**

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// **THE COMPILED `ku_text_go`, AND ITS CHAIN OF TESTS, IN COMPILED ORDER.
const NAME = "function $_________tinybendygrad_renderer_cstyle_ku_text_go(";
const i = src.indexOf(NAME);
if (i < 0) throw new Error("no ku_text_go");
// **AND THE FUNCTION's END IS **NOT** "THE FIRST `}` AT DEPTH 0"** -- BECAUSE **A COMPILED
// `if/else` CHAIN HAS **A `}` AT DEPTH 0** IN THE MIDDLE** (MEASURED: THE NAIVE SCAN FOUND
// **2** TESTS WHERE THE CHAIN HAS **16**). **⇒⇒⇒ SO THE SCAN **SKIPS **THE `}` THAT IS
// FOLLOWED BY `else`**, AND **IT MUST SKIP **THE STRING LITERALS** TOO** (THE PORT's OWN C
// STRINGS HAVE BRACES AND `else`s IN THEM).
const j = src.indexOf("{", i);
let depth = 0, end = j;
for (let k = j; k < src.length; k += 1) {
  const ch = src[k];
  if (ch === '"') {
    k += 1;
    while (k < src.length) {
      if (src[k] === "\\") { k += 2; continue; }
      if (src[k] === '"') break;
      k += 1;
    }
    // **AND THE CHARACTER RIGHT AFTER THE STRING MUST NOT BE SKIPPED** -- BECAUSE **IT CAN BE
    // A `}`** (A COMPILED `return {$: "Con", "head": ...}` ENDS WITH A STRING AND THEN A
    // BRACE) **AND THE `for` LOOP's `k += 1` WOULD SKIP IT**, AND **THEN THE DEPTH ACCOUNTING
    // IS OFF BY ONE AND **THE FUNCTION'S END IS FOUND EARLY** (MEASURED: THE NAIVE SCAN FOUND
    // **2** TESTS WHERE THE CHAIN HAS **16**).
    continue;
  } else if (ch === "{") {
    depth += 1;
  } else if (ch === "}") {
    depth -= 1;
    if (depth === 0) {
      const rest = src.slice(k + 1, k + 12).trimStart();
      if (rest.startsWith("else")) { k += 1; continue; }
      end = k;
      break;
    }
  }
}
const body = src.slice(j, end + 1);

// **THE TESTS**: `_op_0.$ === "OpsXXX"`. **AND THE ARM AFTER EACH TEST**, WHICH IS **THE
// `ku_text_*` FAMILY MEMBER IT CALLS** -- OR **A LITERAL**, WHICH IS **A LEAF**.
const TESTS = [];
const pat = /_op_0\.\$ === "([A-Za-z0-9_]+)"/g;
let m;
while ((m = pat.exec(body)) !== null) TESTS.push(m[1]);

console.log(`THE COMPILED \`ku_text_go\` CHAIN: **${TESTS.length} TESTS**`);
TESTS.forEach((t, i) => console.log(`  ${String(i).padStart(2)}  ${t}`));

// **AND THE WIRE's REAL OPS.** THE WIRE's OP IS **A NUMBER** (THE PORT's `op_by_idx` INDEX),
// SO THE OPS MUST BE READ FROM **THE PORT's OWN `Op` ENUM** -- **AND THE ENUM's ORDER IS THE
// PIN**, SO THE PROBE READS **THE COMPILED `op_by_idx`** RATHER THAN GUESSING.
const opFn = "function $_________tinybendygrad_renderer_live_op_by_idx(";
const oi = src.indexOf(opFn);
if (oi < 0) throw new Error("no op_by_idx");
const oj = src.indexOf("{", oi);
depth = 0;
let oe = oj;
for (let k = oj; k < src.length; k += 1) {
  if (src[k] === "{") depth += 1;
  else if (src[k] === "}") { depth -= 1; if (depth === 0) { oe = k; break; } }
}
const opBody = src.slice(oj, oe + 1);
// **THE INDEX -> THE OPS's NAME**: THE COMPILED FORM IS A CHAIN OF `case N: return OpsXXX`.
// **THE COMPILED FORM IS **AN IF-CHAIN** (`if (_nm_0 == N) { return {$: "OpsXXX"}; }`), **NOT**
// A `case` SWITCH (MEASURED) -- AND **THE MASK ARMS (`& 63`) ARE **THE COMPILER's CATCH-ALLS**
// AND ARE **NOT** ENUM MEMBERS**, SO **THE READER TAKES **ONLY **THE EXACT `== N` ARMS**.
const opRe = /_nm_0 == (\d+)\) \{\s*return \{\$: "(Ops[A-Za-z0-9_]+)"\}/g;
const ops = {};
while ((m = opRe.exec(opBody)) !== null) ops[parseInt(m[1], 10)] = m[2];
console.log(`\nTHE PORT's OWN \`Op\` ENUM, READ FROM **THE COMPILED FORM**: ${Object.keys(ops).length} MEMBERS`);

// **THE WIRE's OPS.** THE WIRE's FIRST TOKEN IS **THE OP INDEX** (MEASURED, §138: THE OP
// INDEX RIDES IN THE NUMBERS ROW).
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const counts = new Map();
for (let i = 0; i < parts.length; i += 9) {
  const idx = parseInt(parts[i], 10);
  counts.set(idx, (counts.get(idx) || 0) + 1);
}

// **WHAT EACH OP PAYS: **THE TESTS UP TO AND INCLUDING **THE ONE THAT MATCHES**.
function testsFor(opName) {
  for (let i = 0; i < TESTS.length; i += 1) {
    if (TESTS[i] === opName) return i + 1;
  }
  return TESTS.length;  // THE FALLTHROUGH.
}

console.log(`\nTHE WIRE's OPS AND **WHAT EACH PAYS**:`);
let total = 0;
let unknown = 0;
for (const [idx, n] of [...counts.entries()].sort((a, b) => b[1] - a[1])) {
  const name = ops[idx];
  if (!name) { unknown += n; continue; }
  const t = testsFor(name);
  total += n * t;
  console.log(`  ${String(name).padEnd(22)} (${String(idx).padStart(2)})  ${String(n).padStart(4)} rows  ${String(t).padStart(2)} TESTS EACH`);
}
console.log(`\nTHE **TOTAL** DISPATCH COMPARISONS A TURN: ${total} (FOR ${parts.length / 9} ROWS)`);
if (unknown) console.log(`**AND ${unknown} ROWS HAVE AN OP **NOT IN THE ENUM** -- SO THEY ARE **NOT COUNTED**.**`);
console.log(`THE AVERAGE: ${(total / (parts.length / 9)).toFixed(2)} TESTS A ROW`);
