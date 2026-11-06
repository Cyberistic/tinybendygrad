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
