// PROBE: **THE `eq_op` CHAIN's REAL COST, ON **THE REAL PAIRS**.
//
// **THE PAIR IS `(ku_op_at(kus, h), op)`** -- **THE UOP's OP AND **THE ALU's OP**, AND **THE ALU's
// OP IS **THE KERNEL's OP** -- **SO **FOR **A WHOLE KERNEL** IT IS **ONE VALUE**, AND **THE UOP's
// OP VARIES**.
//
// **⇒⇒⇒ AND **THE CHAIN's COST IS **THE x-POSITION** (THE UOP's OP) **PLUS **THE y-POSITION**
// (THE ALU's OP), **AND **THE COMPILED CHAIN IS **NESTED**: `if (x.$ === "OpsA") { if (y.$ ===
// "OpsA") ... } else if (x.$ === "OpsB") { ... }` -- **⇒⇒⇒ SO **THE x-TEST FOR **EVERY ARM
// BEFORE THE MATCH** IS PAID, **AND **THE y-TEST **ONLY FOR **THE MATCHED ARM****.
//
// **⇒⇒⇒ SO **THE COST OF **A PAIR** IS **THE x-POSITION + 1** (THE y-TEST) **PLUS **THE
// x-TESTS **FOR **THE ARMS **BEFORE **THE MATCH** (WHICH **ARE **THE SAME COMPARISONS**)****.

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// **THE CHAIN's x-ARM ORDER**, FROM **THE COMPILED FORM**.
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
const order = [];
for (const m of eqBody.matchAll(/if \(_x_0\.\$ === "([A-Za-z0-9_]+)"\)/g)) order.push(m[1]);
const POS = new Map(order.map((t, i) => [t, i]));
console.log(`THE eq_op CHAIN: ${order.length} x-ARMS`);

// **THE ENUM**, FROM **THE COMPILED `op_by_idx`**.
// **AND **THE ENUM IS **READ FROM **THE COMPILED `op_by_idx`** WITH **A LOOSE FORM** -- BECAUSE
// **THE COMPILED FORM's SHAPE **CHANGED** (MEASURED: **THE `case N: return OpsX` FORM IS **A
// `if (_nm_0 == N) { return {$: "OpsX"} }` FORM NOW**), **AND **A PROBE THAT ASSUMES **A
// SPELLING** IS **A PROBE THAT **SILENTLY COUNTS NOTHING****.
const ENUM = {};
// **⇒⇒⇒ AND **THE DEFINITION** IS **FOUND BY **`function ` + THE NAME****, BECAUSE
// **`indexOf(NAME)` FINDS **THE **CALL SITE** FIRST** (MEASURED: **THE FIRST READ OF **THE
// ENUM** WAS **0 MEMBERS** BECAUSE **THE SLICE STARTED AT **THE CALL**).
const oi = src.indexOf("function $_________tinybendygrad_renderer_live_op_by_idx(");
if (oi >= 0) {
  // **⇒⇒⇒ AND **THE FORM IS **`if (_nm_0 == N) { return {$: "OpsX"}; }`** -- AND **THE REGEX
  // MUST NOT USE `[^}]*`**, BECAUSE **THE `{` OF **THE BLOCK** IS **A `}`-FREE CHARACTER** AND
  // **THE PATTERN HAS TO CROSS IT** (MEASURED: **THE FIRST FORM READ **0 MEMBERS**).
  // **⇒⇒⇒ AND **THE COMPILED FORM IS **`return {$: "OpsADD"};`** -- **SO **THE PATTERN IS
  // **`$:` AND **NOT **`$":`** (MEASURED: **THE FIRST FORM READ **0 MEMBERS**, AND **THE
  // ISOLATED TEST SHOWED **`\$": "` DOES NOT MATCH** WHILE **`\$: "`** DOES).
  for (const m of src.slice(oi, oi + 60000).matchAll(/_nm_0 == (\d+)\)[\s\S]{0,60}?\$: "(Ops[A-Za-z0-9_]+)"/g)) {
    ENUM[parseInt(m[1], 10)] = m[2];
  }
}
console.log(`THE ENUM, READ FROM **THE COMPILED FORM**: ${Object.keys(ENUM).length} MEMBERS`);

// **THE WIRE's OPS.**
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const ops = [];
for (let i = 0; i < parts.length; i += 9) {
  const nm = ENUM[parseInt(parts[i], 10)];
  if (nm) ops.push(nm);
}

// **THE CHAIN, AS A FUNCTION** -- **THE COMPILED SEMANTICS**: **THE x-ARM ORDER IS **THE
// OUTER CHAIN**, AND **THE y-TEST IS **INSIDE EACH x-ARM****.
const eqChain = new Function("x", "y", `
  ${order.map((t) => `if (x === "${t}") return y === "${t}";`).join("\n  ")}
  return false;
`);

const bench = (name, fn, reps) => {
  for (let i = 0; i < 30; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(48)} min ${xs[0].toFixed(4)} ms  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}`);
  return xs[0];
};

// **THE REAL WORKLOAD**: **THE ALU's OP IS **ONE VALUE** FOR **A WHOLE KERNEL**, AND **THE UOP's
// OP IS **EACH ROW** -- **⇒⇒⇒ SO **THE PAIRS ARE **(row's op, alu op)** FOR **EACH **POSSIBLE
// ALU OP** -- **AND **THE MEASUREMENT USES **THE **MOST DEMANDING** (THE ALU OP **AT THE END
// OF **THE CHAIN**) **BECAUSE **THAT IS **THE WORST CASE** AND **A PORT'S COST IS **ITS FLOOR**.
const WORST = order[order.length - 1];
const pairs = ops.map((o) => [o, WORST]);

const chainMs = bench("THE eq_op CHAIN, THE REAL PAIRS (worst ALU op)", () => {
  let acc = 0;
  for (const [x, y] of pairs) acc += eqChain(x, y) ? 1 : 0;
  return acc;
}, 2000);

// **AND **THE COUNT OF COMPARISONS**, **FROM **THE CHAIN's STRUCTURE** (NOT FROM **A CLOCK**).
let comps = 0;
for (const [x, y] of pairs) {
  const px = POS.has(x) ? POS.get(x) : order.length;
  comps += px + 1;   // **THE x-TESTS UP TO **THE MATCH** PLUS **THE y-TEST**.
}
console.log(`\nTHE COMPARISONS FOR **${pairs.length}** PAIRS: ${comps} (${(comps / pairs.length).toFixed(1)} A PAIR)`);
console.log("AND **602** SUCH CALLS A TURN (MEASURED, probe-eqop.py) -> "
  + Math.round(602 * comps / pairs.length) + " COMPARISONS A TURN");

// **AND THE INTEGER FORM: **THE PORT's OWN `U32` OP INDEX** -- **AND **THE WIRE ALREADY CARRIES
// IT** (THE OP INDEX IS **THE FIRST NUMBER** OF **THE ROW**).
const idx = new Map(order.map((t, i) => [t, i]));
const intMs = bench("AN INTEGER COMPARISON, THE SAME PAIRS", () => {
  let acc = 0;
  for (const [x, y] of pairs) acc += (idx.get(x) === idx.get(y)) ? 1 : 0;
  return acc;
}, 2000);

console.log();
console.log(`THE CHAIN: ${chainMs.toFixed(4)} ms FOR ${pairs.length} CALLS = ${(1000 * chainMs / pairs.length).toFixed(4)} us A CALL`);
console.log(`THE INTEGER FORM: ${intMs.toFixed(4)} ms = ${(1000 * intMs / pairs.length).toFixed(4)} us A CALL`);
console.log(`**⇒⇒⇒ SO **602 CALLS A TURN: **${(602 * chainMs / pairs.length).toFixed(4)} ms** (THE CHAIN) VS **${(602 * intMs / pairs.length).toFixed(4)} ms** (THE INTEGER) -- **AND **THE RENDER IS **1.03 ms**.**`);
