// wire.js -- THE WIRE SPLIT, AS AN EFFECT.
//
// WHY THIS EXISTS. `live.bend`'s decoder splits the wire with `String.split`, and the PRELUDE's split is
// ONE RECURSION PER CHARACTER: two `slice`s and a token concatenation per character (`String.split.push`
// is `_c_0 + _h_0`). MEASURED (`PARITY.md` §125): on a 15,346-character wire that is **5.16 ms of a
// 5.58 ms daemon turn -- 92.6%** -- and everything else in the turn is 0.42 ms.
//
// THE SAME ALGORITHM IN JS COSTS 0.12 ms, because `String.prototype.split` is native and ONE call.
// MEASURED on the same wire: the prelude's algorithm in JS 0.72 ms, `s.split(" ")` plus building the list
// 0.12 ms (best of 20), and the per-turn median 0.136 ms.
//
// SO THE PORT CALLS THE NATIVE ONE THROUGH THE MECHANISM IT ALREADY SHIPS: `Sz.read_dir` (`sz.bend` +
// `sz.js`) is the same shape of effect -- a foreign call the checker reads and never checks -- and this
// file is the same shape of answer.
//
// THE SHAPE OF THE ANSWER, AND IT IS THE PORT'S OWN:
//
//   * `io_args` (base.bend) returns the LIST ITSELF and the runtime unwraps it; a `Done` box made the
//     decoder read `undefined.$` and throw. So this returns the list, not a box.
//   * `sz.js`'s `sz_read_dir` builds `{ $: CID(Con), head: <a JS string>, tail: xs }` and the runtime's
//     `String` IS a JS string (`str_out` is `s.replace(...)`), so the heads need no conversion.
//
// AND `CID(Con)`/`CID(Nil)` ARE REWRITTEN BY THE COMPILER to the plain tags "Con"/"Nil" in the JS lane
// (`comp.ts`'s `c_ids` -> `js_tag`), which is why the tags below are written as the strings the runtime
// uses.

function wire_split(s) {
  const parts = s.split(" ");
  let xs = { $: "Nil" };
  for (let i = parts.length; i > 0; i -= 1) xs = { $: "Con", head: parts[i - 1], tail: xs };
  return xs;
}

io_eff(CID(Wire.split), wire_split);

// THE WIRE'S TWO LISTS, IN TWO EFFECTS.
//
// WHY TWO: BEND'S LIST IS MONOMORPHIC, SO A ROW CANNOT HOLD BOTH STRINGS AND NUMBERS, AND A ROW CANNOT BE
// A PAIR OF LISTS OF DIFFERENT KINDS. ONE LIST PER KIND, THEN THE PORT WALKS THEM IN STEP.
//
// WHY THE NUMBERS AT ALL: the port's `U32.read` is the PRELUDE's character-at-a-time fold, and at runtime a
// string is a JS string, so the compiler emits `slice(0, char_len(s))` AND `slice(char_len(s))` PER CHARACTER.
// MEASURED (`PARITY.md` §131): the wire's 2,814 numbers cost 21,294 `char_len` calls and ~42,000 string
// allocations a render, where the SAME ALGORITHM IN JS IS 0.015-0.025 ms -- forty times faster.
// THE WIRE ROW IS NINE TOKENS: [op, dt, addr, shape, numel, kind, payload, srcs, cc] -- WHICH IS
// `ku_ws.of`'s (a, b, c, d, e, f, g, h, i) READ IN ORDER. THE FIVE THAT ARE NOT NUMBERS ARE op, dt,
// addr, kind, payload; THE REST ARE numel, cc, shape[] AND srcs[].
function wire_strings(s) {
  const parts = s.split(" ");
  let rows = { $: "Nil" };
  for (let i = parts.length - 9; i >= 0; i -= 9) {
    const strs = { $: "Con", head: parts[i], tail: { $: "Con", head: parts[i + 1], tail: { $: "Con", head: parts[i + 2],
      tail: { $: "Con", head: parts[i + 5], tail: { $: "Con", head: parts[i + 6], tail: { $: "Nil" } } } } } };
    rows = { $: "Con", head: strs, tail: rows };
  }
  return rows;
}

io_eff(CID(Wire.strings), wire_strings);

// THE NUMBERS, PER UOP: [numel, cc, shapeCount, srcsCount, shape..., srcs...]. THE PORT'S `ku_row.of`
// TAKES numel, cc, THEN THE TWO COUNTS, THEN THE REST -- AND `take`/`skip` SPLIT THE REST AT THE SHAPE
// COUNT. EVERY NUMBER ON THE WIRE IS AN INTEGER, SO `Number` IS EXACT.
//
// **THE LIST IS BUILT BACKWARDS-TO-FORWARDS, AND THAT IS THE WHOLE TRICK.** Prepending puts the element
// at the HEAD, so the LAST thing prepended is the FIRST thing read. The list must read
// [numel, cc, sc, gc, shape..., srcs...], so the prepending order is srcs, then shape, then the four
// scalars -- and the scalars are prepended innermost-first.
function wire_numbers(s) {
  const parts = s.split(" ");
  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));
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
    rows = { $: "Con", head: nums, tail: rows };
  }
  return rows;
}

io_eff(CID(Wire.numbers), wire_numbers);
