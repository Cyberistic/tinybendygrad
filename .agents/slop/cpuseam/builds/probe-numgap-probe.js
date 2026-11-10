// PROBE: **WHERE** THE `numbers` 0.49 ms GOES.
//
// THE IN-DAEMON CLOCK SAYS `wire_numbers`' REST IS 0.49 ms A TURN. THE PURE JS SAYS 0.187 ms.
// **SO ~0.30 ms IS SPENT IN THE BEND SIDE**, CONSUMING THE 782 ROWS AND THEIR 1,273 NUMBERS.
//
// THIS PROBE MEASURES THE CONSUMPTION'S SHAPE IN JS, AS THE **MIRROR** OF WHAT THE BEND
// SIDE DOES: READ EVERY ROW, READ ITS NINE HEADERS, AND WALK THE REST.

const fs = require("fs");

const s = fs.readFileSync(process.argv[2], "utf8");

// THE JS EFFECT'S BODY, VERBATIM FROM `tinybendygrad/renderer/wire.js`.
function wire_numbers(s) {
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
}

const bench = (name, fn, reps) => {
  for (let i = 0; i < 5; i += 1) fn();
  const xs = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs.push(performance.now() - t0);
  }
  xs.sort((a, b) => a - b);
  console.log(`${name.padEnd(38)} min ${xs[0].toFixed(4)}  p25 ${xs[(xs.length / 4) | 0].toFixed(4)}  median ${xs[xs.length >> 1].toFixed(4)}`);
};

bench("T1: wire_numbers (JS body only)", () => wire_numbers(s), 200);

// **THE CONSUMPTION's SHAPE**: EVERY ROW, EVERY NUMBER.
bench("T2: walk every row and number", () => {
  const rows = wire_numbers(s);
  let acc = 0;
  let r = rows;
  while (r.$ !== "Nil") {
    let n = r.head;
    while (n.$ !== "Nil") { acc += n.head; n = n.tail; }
    r = r.tail;
  }
  return acc;
}, 200);

// **THE COUNT**.
{
  const rows = wire_numbers(s);
  let nrows = 0, nnums = 0;
  let r = rows;
  while (r.$ !== "Nil") {
    nrows += 1;
    let n = r.head;
    while (n.$ !== "Nil") { nnums += 1; n = n.tail; }
    r = r.tail;
  }
  console.log(`\nTHE LIST: ${nrows} ROWS, ${nnums} NUMBERS, ${(nnums / nrows).toFixed(2)} A ROW`);
}
