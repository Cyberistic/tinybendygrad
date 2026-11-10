// PROBE: THE JS HALF OF THE DECODE, PART BY PART. THE INPUT IS THE TREE's OWN WIRE.
//
// THE QUESTION: `wire_numbers` COSTS 0.49 ms A TURN. WHAT IN IT? THE PER-ROW WORK IS
// (a) THE `s.split(" ")` OVER 18 KB, (b) THE PER-ROW `list()` CALLS -- TWO PER ROW, EACH
// `t.split("~").map(Number)`, AND (c) THE LIST OBJECT ALLOCATION (ONE `{ $: "Con", head, tail }`
// PER NUMBER, PLUS ONE PER ROW).
//
// AND THE MEASUREMENT IS **THE SAME LOOP, THREE TIMES**, ON THE **SAME** INPUT, SO THE
// DIFFERENCES ARE THE PARTS AND NOT THE LOAD.

const fs = require("fs");
const s = fs.readFileSync(process.argv[2], "utf8");

function bench(name, fn, reps) {
  // THE WARM-UP, THEN THE MEASURED REPS.
  for (let i = 0; i < 5; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(34)} min ${xs[0].toFixed(4)}  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}  median ${xs[xs.length >> 1].toFixed(4)}`);
}

// (0) THE SPLIT ALONE.
bench("split(' ') only", () => s.split(" "), 200);

// (1) THE SPLIT PLUS THE PER-ROW `list()` CALLS, NO OBJECT ALLOCATION.
bench("split + list() calls", () => {
  const parts = s.split(" ");
  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));
  let acc = 0;
  for (let i = parts.length - 9; i >= 0; i -= 9) {
    const shape = list(parts[i + 3]);
    const srcs = list(parts[i + 7]);
    acc += shape.length + srcs.length;
  }
  return acc;
}, 200);

// (2) THE FULL `wire_numbers`, VERBATIM FROM `tinybendygrad/renderer/wire.js`.
bench("wire_numbers (verbatim)", () => {
  const parts = s.split(" ");
  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));
  const c0 = (t) => t.charCodeAt(0);
  const c1 = (t) => (t.length > 1 ? t.charCodeAt(1) : 0);
  let rows = { $: "Nil" };
  for (let i = parts.length - 9; i >= 0; i -= 9) {
    const shape = list(parts[i + 3]);
    const srcs = list(parts[i + 7]);
    let nums = { $: "Nil" };
    for (let k = 0; k < srcs.length; k += 1) nums = { $: "Con", head: srcs[srcs.length - 1 - k], tail: nums };
    for (let k = 0; k < shape.length; k += 1) nums = { $: "Con", head: shape[shape.length - 1 - k], tail: nums };
    nums = { $: "Con", head: srcs.length, tail: nums };
    nums = { $: "Con", head: shape.length, tail: nums };
    nums = { $: "Con", head: Number(parts[i + 8]), tail: nums };
    nums = { $: "Con", head: Number(parts[i + 4]), tail: nums };
    nums = { $: "Con", head: c1(parts[i + 5]), tail: nums };
    nums = { $: "Con", head: c0(parts[i + 5]), tail: nums };
    nums = { $: "Con", head: c0(parts[i + 2]), tail: nums };
    nums = { $: "Con", head: c0(parts[i + 1]), tail: nums };
    nums = { $: "Con", head: Number(parts[i]), tail: nums };
    rows = { $: "Con", head: nums, tail: rows };
  }
  return rows;
}, 200);

// (3) THE SAME, BUT **THE ROW OBJECTS ARE PRE-BUILT AND THE LIST IS A FLAT ARRAY** -- THE
//     QUESTION IS HOW MUCH OF THE COST IS THE `{ $: "Con", head, tail }` ALLOCATION.
bench("wire_numbers -> flat arrays", () => {
  const parts = s.split(" ");
  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));
  const c0 = (t) => t.charCodeAt(0);
  const c1 = (t) => (t.length > 1 ? t.charCodeAt(1) : 0);
  const rows = [];
  for (let i = parts.length - 9; i >= 0; i -= 9) {
    const shape = list(parts[i + 3]);
    const srcs = list(parts[i + 7]);
    const nums = [];
    for (let k = srcs.length - 1; k >= 0; k -= 1) nums.push(srcs[k]);
    for (let k = shape.length - 1; k >= 0; k -= 1) nums.push(shape[k]);
    nums.push(srcs.length, shape.length, Number(parts[i + 8]), Number(parts[i + 4]),
              c1(parts[i + 5]), c0(parts[i + 5]), c0(parts[i + 2]), c0(parts[i + 1]), Number(parts[i]));
    rows.push(nums);
  }
  return rows;
}, 200);

// (4) **THE `~`-SPLIT ONLY**, WITH NO OTHER WORK: THE 600 `~`-LISTS.
bench("600 '~' splits + map(Number)", () => {
  const parts = s.split(" ");
  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));
  let acc = 0;
  for (let i = parts.length - 9; i >= 0; i -= 9) {
    acc += list(parts[i + 3]).length + list(parts[i + 7]).length;
  }
  return acc;
}, 200);
