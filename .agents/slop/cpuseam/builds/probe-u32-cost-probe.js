// PROBE: **THE `u32(p)` COST -- THE PRELUDE's CHARACTER-AT-A-TIME FOLD.**
//
// THE `x` ARM DOES `u32(p)`, AND `u32` IS `$U32_read`, WHICH PER CHARACTER DOES **TWO SLICES**
// (`slice(0, char_len(s))` AND `slice(char_len(s))`) PLUS **A `char_len`** -- **THE SAME
// CHARACTER-TRIE OVERHEAD** THE TREE MEASURED FOR STRING MATCHES.
//
// **AND THE `x` PAYLOADS ARE **ALL SINGLE-CHARACTER "0"**,** SO THE FOLD RUNS ONCE PER CALL --
// BUT IT STILL PAYS **TWO SLICES** FOR **ONE CHARACTER**.
//
// THIS PROBE MEASURES: (a) THE FOLD, AS COMPILED, ON THE REAL PAYLOADS; AND (b) THE SAME
// NUMBERS PARSED BY JS's `Number`, WHICH IS **ONE CALL** AND NO SLICES.

const fs = require("fs");

const jsPath = process.argv[2];
const wirePath = process.argv[3];

const src = fs.readFileSync(jsPath, "utf8");

// THE COMPILED FOLD, TAKEN FROM THE BUILD (SO IT IS **THE PORT's OWN CODE**).
function grab(name) {
  const i = src.indexOf(`function ${name}(`);
  const j = src.indexOf("{", i);
  let depth = 0;
  for (let k = j; k < src.length; k += 1) {
    if (src[k] === "{") depth += 1;
    else if (src[k] === "}") { depth -= 1; if (depth === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`no ${name}`);
}

const charLen = src.includes("function char_len(") ? src.match(/function char_len\([^)]*\) \{[^}]*\}/)[0] : null;
const charCode = src.includes("function char_code(") ? src.match(/function char_code\([^)]*\) \{[^}]*\}/)[0] : null;

// THE RUNTIME's HELPERS, IF THEY ARE IN THE BUILD.
const helpers = [charLen, charCode].filter(Boolean).join("\n");
const FOLD = `
${helpers}
${grab("$U32_read_go")}
${grab("$U32_read")}
${grab("$Maybe_default")}
function u32(s) { return $Maybe_default($U32_read(s), 0); }
return u32;
`;
const u32 = new Function(FOLD)();

console.log(`THE COMPILED FOLD, TAKEN FROM THE BUILD (${FOLD.length} BYTES)`);

// THE REAL PAYLOADS THAT REACH `u32`: THE `x` KIND's.
const s = fs.readFileSync(wirePath, "utf8");
const parts = s.split(" ");
const xs = [];
for (let i = 0; i < parts.length; i += 9) if (parts[i + 5] === "x") xs.push(parts[i + 6]);
console.log(`THE \`x\` PAYLOADS: ${xs.length}, ALL ${JSON.stringify(xs[0])}`);

const bench = (name, fn, reps) => {
  for (let i = 0; i < 20; i += 1) fn();
  const xs2 = [];
  for (let i = 0; i < reps; i += 1) {
    const t0 = performance.now();
    fn();
    xs2.push(performance.now() - t0);
  }
  xs2.sort((a, b) => a - b);
  console.log(`${name.padEnd(40)} min ${xs2[0].toFixed(4)}  p25 ${xs2[(xs2.length / 4) | 0].toFixed(4)}  median ${xs2[xs2.length >> 1].toFixed(4)}`);
};

bench("THE FOLD (u32), ON THE 127 x PAYLOADS", () => {
  let acc = 0;
  for (const p of xs) acc += u32(p);
  return acc;
}, 2000);

bench("JS's Number(), ON THE SAME PAYLOADS", () => {
  let acc = 0;
  for (const p of xs) acc += Number(p);
  return acc;
}, 2000);

// **AND THE `i` KIND's FOUR `field(p, i)` CALLS**: THE `p` KIND DOES **FOUR** `field(p, i)`,
// AND **EACH ONE RE-SPLITS THE PAYLOAD** (`ysplit(p)` = `String.split(p, '~')`).
const ps = [];
for (let i = 0; i < parts.length; i += 9) if (parts[i + 5] === "p") ps.push(parts[i + 6]);
const is_ = [];
for (let i = 0; i < parts.length; i += 9) if (parts[i + 5] === "i") is_.push(parts[i + 6]);
console.log(`\nTHE \`p\` PAYLOADS: ${ps.length} (EACH DOES **FOUR** \`field(p, i)\` CALLS)`);
console.log(`THE \`i\` PAYLOADS: ${is_.length} (EACH DOES **TWO** \`field(p, i)\` CALLS)`);

// THE PRELUDE's `String.split`, AS COMPILED.
const splitFn = grab("$String_split_go") || "";
console.log(`\nTHE PRELUDE's \`String.split\` COMPILED: ${splitFn.length} BYTES`);
