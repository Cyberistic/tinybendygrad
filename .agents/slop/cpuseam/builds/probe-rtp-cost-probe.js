// PROBE: **THE PRICE OF **THE `rtp` ACCESS** -- **1,237 CALLS A TURN**, **A BLOCKED INDEXED WALK**.
//
// **⇒⇒⇒ AND §138.5's LESSON IS **THE COUNT IS NOT THE COST** -- **⇒⇒⇒ AND §138.5's SECOND
// HALF IS **THE STANDALONE COST IS NOT THE COST EITHER** -- **⇒⇒⇒ AND **THIS PROBE MEASURES
// **BOTH**: **THE CHAIN'S COST **IN ISOLATION** (A **PURE JS** WALK OF **THE SAME SHAPE**) **AND
// **THE PORT's OWN COMPILED FUNCTION**, **RUN **ON **THE SAME INPUT**.
//
// **⇒⇒⇒ AND **THE TWO NUMBERS **TOGETHER** SAY **WHETHER **THE WALK IS **THE COST** OR **THE
// CALL IS**.

const fs = require("fs");

const jsPath = process.argv[2];
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
  console.log(`${name.padEnd(48)} min ${xs[0].toFixed(4)} ms  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}`);
  return xs[0];
};

// **THE SHAPE**: **A LIST OF 779 BLOCKS**, **EACH BLOCK **16** ELEMENTS**, **AND **A WALK OF
// **THE BLOCK** **PLUS **A WALK OF **THE OFFSET INSIDE **THE BLOCK****.
const BLOCKS = 49;          // **779 / 16**
const BLOCK_SIZE = 16;
const ROWS = BLOCKS * BLOCK_SIZE;

// **THE ROWS LIST**, AS THE COMPILED FORM BUILDS IT: **A LIST OF BLOCKS**.
let blocks = { $: "Nil" };
for (let b = BLOCKS - 1; b >= 0; b -= 1) {
  let blk = { $: "Nil" };
  for (let i = BLOCK_SIZE - 1; i >= 0; i -= 1) blk = { $: "Con", head: { row: b * BLOCK_SIZE + i }, tail: blk };
  blocks = { $: "Con", head: blk, tail: blocks };
}

// **THE PORT's OWN `List.get`**, **FROM **THE BUILD** -- **AND **THE **PRELUDE's** VERSION,
// **WHICH **RECURSES**.
const listGetSrc = src.match(/function \$List_get\([^]*?\n\}/);
const List_get = new Function(`${listGetSrc[0]}\nreturn $List_get;`)();

// **THE `rtp` SHAPE**: **`d = n-1-i`**, **THEN **`bi = d/16`** AND **`off = d%16`**, **THEN
// **THE BLOCK (A `List.get` OF **bi**) **AND **THE ELEMENT (A `List.get` OF **off**)****.
const getBlock = (d) => {
  // **THE OUTER `List.get`**: **THE BLOCK INDEX**.
  let x = blocks, k = d >> 4;
  while (k > 0 && x.$ === "Con") { x = x.tail; k -= 1; }
  return x.$ === "Con" ? x.head : { $: "Nil" };
};

const walkBoth = bench("THE `rtp` WALK, 1,237 CALLS (PURE JS)", () => {
  let acc = 0;
  for (let c = 0; c < 1237; c += 1) {
    const i = c % ROWS;
    const d = (ROWS - 1 - i) >>> 0;
    const blk = getBlock(d);
    // **THE INNER `List.get`**: **THE OFFSET INSIDE **THE BLOCK**.
    let x = blk, k = d & 15;
    while (k > 0 && x.$ === "Con") { x = x.tail; k -= 1; }
    if (x.$ === "Con") acc += x.head.row;
  }
  return acc;
}, 2000);

// **AND **THE **PRELUDE's** `List.get`** (THE RECURSIVE ONE), **ON **THE SAME SHAPE**.
const preludeGet = bench("THE `rtp` WALK, 1,237 CALLS (THE PRELUDE's List.get)", () => {
  let acc = 0;
  for (let c = 0; c < 1237; c += 1) {
    const i = c % ROWS;
    const d = (ROWS - 1 - i) >>> 0;
    const blk = getBlock(d);
    const v = List_get(blk, d & 15);
    if (v.$ === "Some") acc += v.value.row;
  }
  return acc;
}, 2000);

// **AND **THE **CALL COST ALONE**: **1,237 CALLS THAT DO **NOTHING****.
const callOnly = bench("1,237 EMPTY CALLS", () => {
  let acc = 0;
  for (let c = 0; c < 1237; c += 1) acc += c;
  return acc;
}, 5000);

console.log();
console.log();
console.log("⇒⇒⇒ SO **THE WALK COSTS **~(walkBoth - callOnly) ms** AND **THE CALLS COST");
console.log("**~callOnly ms**, **AND **THE RENDER IS **1.03 ms** -- **⇒⇒⇒ AND **THE **IN-DAEMON**");
console.log("CLOCK READS **0.4787 ms** FOR **THE WHOLE rtp FUNCTION** (INCLUDING **THE **CLOCK's OWN");
console.log("OVERHEAD**)****.");
console.log("⇒⇒⇒ AND **THE **IN-DAEMON** CLOCK'S OWN OVERHEAD IS **~0.00002 ms** A CALL, **SO");
console.log("**1,237 CALLS **COST **~0.025 ms** OF **THE CLOCK** -- **⇒⇒⇒ AND **THE REMAINDER IS");
console.log("**THE FUNCTION's OWN WORK****.");
