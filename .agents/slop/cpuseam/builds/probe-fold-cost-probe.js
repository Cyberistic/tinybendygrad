// PROBE: **THE PRICE OF **THE RENDER's HOT FOLDS**: `List_append` (17,825 CALLS A TURN) AND
// `String_concat` (13,389).
//
// **WHY:** THE RENDER's HOT COUNT (MEASURED, `probe-hot-count.py`, IN THE DAEMON) IS:
//   `List_append` 17,825   `String_concat` 13,389   `KU_op` 6,188   `St_r` 4,355
// **⇒⇒⇒ AND BOTH FOLDS ARE **RECURSIVE, ONE ELEMENT AT A TIME** -- **THE SAME SHAPE AS THE
// PRELUDE's `String.split` THAT THE TREE ALREADY MOVED TO JS** (§125: THE SPLIT WAS **92.6%
// OF A TURN**).
//
// **⇒⇒⇒ AND `List_append(xs, ys)` **COPIES `xs`** -- SO **ITS COST IS **PROPORTIONAL TO THE
// LENGTH OF `xs`**, NOT TO **THE NUMBER OF CALLS**. **⇒⇒⇒ SO **THE COUNT ALONE IS **NOT
// ENOUGH** -- **THE TOTAL ELEMENTS COPIED** IS **THE NUMBER THAT MATTERS**, AND **THAT IS
// COUNTABLE** (AND **COUNTING IT IS **FREE**).

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// **AND THE TIMER's RESOLUTION IS **COARSE** FOR **A SINGLE CALL** -- MEASURED: A LIST OF
// **1** READS **0.0000 ms** -- **SO EACH MEASUREMENT RUNS **N CALLS** INSIDE **ONE** TIMED
// ITERATION** AND **DIVIDES**, WHICH IS **THE SAME MEASUREMENT** AT **A COARSER SCALE**.
const bench = (name, fn, reps, batch) => {
  const N = batch || 1;
  // **AND THE RESULT MUST BE **USED**, OR **THE JIT DELETES **THE CALLS****.
  let sink = 0;
  const one = () => { for (let i = 0; i < N; i += 1) { const r = fn(); sink += (typeof r === "string") ? r.length : (r && r.$ === "Con") ? 1 : 0; } };
  globalThis.__sink = () => sink;
  for (let i = 0; i < 30; i += 1) one();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    one();
    xs.push((performance.now() - t0) / N);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(48)} min ${(xs[0] * 1000).toFixed(4)} us  p25 ${(xs[(xs.length / 4) | 0] * 1000).toFixed(4)} us`);
  return xs[0];
};

// **THE COMPILED `List_append` AND `String_concat`**, TAKEN **FROM THE BUILD**.
const mk = (name) => {
  const i = src.indexOf(`function ${name}(`);
  const j = src.indexOf("{", i);
  let depth = 0, end = j;
  for (let k = j; k < src.length; k += 1) {
    if (src[k] === "{") depth += 1;
    else if (src[k] === "}") { depth -= 1; if (depth === 0) { end = k; break; } }
  }
  // **AND THE COMPILED BODY IS **RECURSIVE** AND CALLS **THE GLOBAL `$$Name`** -- SO **THE
  // EVALUATED SCOPE MUST **BIND `$$Name` TO **THE FUNCTION ITSELF****, OR **THE RECURSION
  // THROWS `ReferenceError`**.
  const body = src.slice(i, end + 1);
  const inner = name;                    // E.G. `$List_append`.
  const global = name.replace(/^\$/, "$$");  // E.G. `$$List_append`.
  const scope = {};
  scope[global] = new Function(`${global}`, `${body}\nreturn ${inner};`).bind(scope);
  return scope[global];
};

const List_append = mk("$List_append");
const String_concat = mk("$String_concat");

// **THE LIST-SHAPED WORKLOADS THE RENDER ACTUALLY DOES.** **THE ROWS ARE **THE RENDER's OWN
// OUTPUT LISTS**, AND **THE SIZES ARE **THE PORT's OWN** (THE WIRE CARRIES 782 ROWS; THE
// RENDER BUILDS PER-KERNEL ROW LISTS).
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const rows = parts.length / 9;

// **THE `List.append` COST FOR **A LIST OF EVERY LENGTH THE RENDER USES.**
// **AND THE SUM, WHICH IS **THE TOTAL ELEMENTS COPIED** -- **THE NUMBER THAT MATTERS.**
console.log(`THE WIRE CARRIES ${rows} ROWS. THE List.append COST IS **PROPORTIONAL TO THE`);
console.log("LENGTH OF **THE FIRST ARGUMENT** -- SO **THE QUESTION IS **THE DISTRIBUTION OF **THOSE");
console.log("LENGTHS**, NOT **THE NUMBER OF CALLS**.\n");

const lens = [1, 2, 4, 8, 16, 32, 64, 128, 256];
console.log(`THE \`List_append\` COST, **PER CALL**, **BY THE FIRST ARGUMENT's LENGTH**:`);
for (const L of lens) {
  let xs = { $: "Nil" };
  for (let i = 0; i < L; i += 1) xs = { $: "Con", head: i, tail: xs };
  const ys = { $: "Nil" };
  const ms = bench(`  A LIST OF ${String(L).padStart(3)}`, () => List_append(xs, ys), 500, Math.max(1, Math.floor(2000 / L)));
  console.log(`      -> ${(ms * 1000).toFixed(4)} us A CALL, ${(ms * 1000 / L).toFixed(4)} us AN ELEMENT`);
}

// **AND THE STRING CONCAT, **THE SAME WAY** -- **A LIST OF STRINGS** IS CONCATENATED.
console.log(`\nAND THE \`String_concat\` COST, **PER CALL**, **BY THE LIST's LENGTH**:`);
for (const L of [1, 4, 16, 64]) {
  let xs = { $: "Nil" };
  for (let i = 0; i < L; i += 1) xs = { $: "Con", head: "abcdefgh", tail: xs };
  const ms = bench(`  A LIST OF ${String(L).padStart(3)} STRINGS`, () => String_concat(xs), 500, Math.max(1, Math.floor(2000 / L)));
  console.log(`      -> ${(ms * 1000).toFixed(4)} us A CALL`);
}
