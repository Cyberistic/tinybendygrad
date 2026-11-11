// PROBE: **THE COMPILED `arg_of` CHAIN, AND HOW MANY TESTS EACH KIND PAYS.**
//
// THE COMPILED CHAIN HAS **BIT-MASK CATCH-ALL ARMS** (`& 15`, `& 7`, `& 3`) INTERLEAVED WITH
// THE REAL ARMS, AND THE WORK STATE SAYS "**THE `KANone` CATCH-ALL STILL PAYS ALL 17 TESTS**".
//
// THIS PROBE READS **THE COMPILED FORM** AND, FOR EACH KIND THE WIRE ACTUALLY CARRIES,
// **COUNTS THE TESTS** THE CHAIN PERFORMS BEFORE IT RETURNS. IT IS A **COUNT**, NOT A
// TIMING, BECAUSE THE COUNT IS **WHAT** THE CHAIN DOES AND A TIMING ON A LOADED MACHINE IS
// **A MEASUREMENT OF THE LOAD**.

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// THE CHAIN, AS A LIST OF (TEST, ARM-KIND) IN SOURCE ORDER.
const NAME = "function $_________tinybendygrad_renderer_live_arg_of(";
const start = src.indexOf(NAME);
if (start < 0) throw new Error("no arg_of");
const bodyStart = src.indexOf("{", start);
let depth = 0, bodyEnd = bodyStart;
for (let i = bodyStart; i < src.length; i += 1) {
  if (src[i] === "{") depth += 1;
  else if (src[i] === "}") { depth -= 1; if (depth === 0) { bodyEnd = i; break; } }
}
const body = src.slice(bodyStart, bodyEnd + 1);

// THE TESTS, IN ORDER. EACH IS "IF (TEST) { RETURN ... }" AND THE TESTS ARE:
//   · `_kind0_0 == N`            -- A REAL ARM (AN EXACT KIND CODE)
//   · `(_kind0_0 & M) == N`     -- A COMPILER-EMITTED CATCH-ALL (A FIELD-COUNT MASK)
// THE CATCH-ALLS ARE **INTERLEAVED**, AND **THE ORDER IS **THE SOURCE ORDER** (MEASURED,
// §137/§138: THE COMPILER PRESERVES THE SOURCE ORDER OF A `match` ARM LIST).
const TESTS = [];
// THE TESTS: EITHER `(_kind0_0 & M) == N` (A COMPILER-EMITTED CATCH-ALL) OR
// `_kind0_0 == N` (A REAL ARM). **THE ORDER IS **THE COMPILED ORDER**, AND THE COMPILED
// ORDER IS **THE SOURCE ORDER** (MEASURED, `PARITY.md` §137: THE COMPILER PRESERVES THE
// SOURCE ORDER OF A `match` ARM LIST).
const re = /\(\(([^)]*)\) == ([0-9]+)\)|\b(_kind0_0) == ([0-9]+)/g;
let m;
while ((m = re.exec(body)) !== null) {
  const test = m[1] !== undefined ? m[1] : m[3];
  const val = parseInt(m[2] !== undefined ? m[2] : m[4], 10);
  TESTS.push({ test, val, mask: /&/.test(test) });
}

// THE ARM AFTER EACH TEST, TO SEE WHETHER IT IS A `KANone`.
const ARMS = [];
const re2 = /(?:else )?if \([^)]*\) == [0-9]+\) \{ return ([^;]{0,80});/g;
while ((m = re2.exec(body)) !== null) ARMS.push(m[1]);

console.log(`THE COMPILED \`arg_of\` CHAIN: **${TESTS.length} TESTS**\n`);
TESTS.forEach((t, i) => {
  const arm = ARMS[i] || "";
  const kind = arm.includes("KANone") ? "KANone" : arm.slice(0, 30);
  console.log(`  ${String(i).padStart(2)}  ${t.test.padEnd(24)} -> ${kind}`);
});

// THE WIRE'S KIND POPULATION.
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const kinds = parts.filter((_, i) => i % 9 === 5);

// **THE TESTS EACH KIND PAYS**: THE CHAIN IS EVALUATED IN ORDER, SO A KIND PAYS THE TESTS
// UP TO AND INCLUDING THE ONE THAT MATCHES.
function testsFor(k0) {
  let n = 0;
  for (const t of TESTS) {
    n += 1;
    const mm = t.test.match(/^(.+?) & ([0-9]+)$/);
    if (mm) {
      if (((k0 & parseInt(mm[2], 10)) >>> 0) === t.val) return n;
    } else if (k0 === t.val) {
      return n;
    }
  }
  return n;
}

// THE KIND'S FIRST CHARACTER'S CODE.
const c0 = (t) => t.charCodeAt(0);
const pop = new Map();
for (const k of kinds) {
  const code = c0(k);
  const t = testsFor(code);
  if (!pop.has(code)) pop.set(code, { kind: k, n: 0, tests: t });
  pop.get(code).n += 1;
}

console.log(`\nTHE KIND POPULATION, AND **THE TESTS EACH PAYS**:`);
let total = 0;
for (const [code, v] of [...pop.entries()].sort((a, b) => b[1].n - a[1].n)) {
  console.log(`  kind ${String.fromCharCode(code)} (${code})  ${String(v.n).padStart(4)} rows  ${v.tests} TESTS EACH`);
  total += v.n * v.tests;
}
console.log(`\nTHE **TOTAL** COMPARISONS A TURN: ${total} (FOR ${kinds.length} ROWS)`);
console.log(`THE AVERAGE: ${(total / kinds.length).toFixed(2)} TESTS A ROW`);

// **AND THE COST OF THE MASK ARMS**: HOW MANY OF THE TESTS ARE CATCH-ALLS?
const masks = TESTS.filter((t) => t.mask).length;
console.log(`\nTHE MASK ARMS: ${masks} OF ${TESTS.length} TESTS ARE COMPILER-EMITTED CATCH-ALLS`);
console.log(`THE REAL ARMS: ${TESTS.length - masks}`);
