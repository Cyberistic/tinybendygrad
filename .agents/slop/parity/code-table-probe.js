#!/usr/bin/env node
// code-table-probe.js -- THE PORT's NUMERIC CODE TABLES AGAINST THE STRING TABLES THEY REPLACE.
//
// WHY IT EXISTS. `tinybendygrad/renderer/live.bend`'s `dt_of` / `addr_of` / `arg_of` MATCH ON CHAR
// CODES, BECAUSE A `match` ON A STRING IN Bend IS A CHARACTER TRIE (THE GENERATED CODE SLICES THE FIRST
// CHARACTER AND SLICES THE REST TO TEST THE LENGTH -- TWO SLICES AND TWO `char_len` PER CALL) AND A
// `match` ON A `U32` IS AN INTEGER COMPARE. **=> AND A COMPUTED ARM KEY IS REFUSED** ("expected : a
// pattern"), SO THE TABLE CANNOT DERIVE ITS OWN KEYS, WHICH MAKES THE NUMERIC KEYS **A SECOND SOURCE OF
// TRUTH**.
//
// **=> SO THE SECOND SOURCE IS CHECKED BY A PROBE, NOT BY READING.** THIS CALLS THE COMPILED
// `dt_of` / `addr_of` / `arg_of` OVER EVERY CODE AND COMPARES EACH ANSWER AGAINST THE PORT's OWN STRING
// TABLE. **=> AND A PROBE THAT COMPARES A TABLE WITH ITSELF PROVES NOTHING**, SO THE TWO ARE SEPARATE:
// THE STRING TABLE BELOW IS RE-TYPED, NOT READ OUT OF THE PORT.
//
//     .venv/bin/python .agents/slop/parity/code-table-probe.py
//
// IT BUILDS THE LIVE RENDERER ITSELF (ONE `bin/bend` PROCESS) AND EXITS NON-ZERO ON ANY MISMATCH.

// THE COMPILED RENDERER COMES IN BY PATH, BECAUSE `bun` AND `node` BOTH LOAD A `.js` FILE AS ESM WHEN
// THE TREE's `package.json` SAYS SO, AND SPAWNING `bin/bend` FROM HERE HITS THAT LOADER. SO THE
// DRIVER BUILDS IT AND PASSES THE PATH.
const fs = require("node:fs");
const src = fs.readFileSync(process.argv[2], "utf8");

// THE COMPILED FILE IS NOT LOADED AS A MODULE: IT IS THE PORT's OWN JS, WITH `require` CALLS, AND
// BOTH `bun` AND `node` LOAD A `.js` FILE AS ESM WHEN THE TREE's `package.json` SAYS SO. **=> SO THE
// PROBE EXTRACTS THE FIVE TABLES AND EVALUATES THEM**, WHICH IS ALSO WHAT MAKES THE PROBE A PROBE: IT
// RUNS THE PORT's OWN COMPILED CODE AND NOT A COPY OF IT.
function grab(name) {
  let at = src.indexOf("function " + name + "(");
  if (at < 0) {
    const c = src.indexOf("\nconst " + name + " =");
    if (c < 0) return null;
    return src.slice(c + 1, src.indexOf("\n", c + 1));
  }
  // **=> AND A `const` ALIAS WITH THE SAME NAME IS A SEPARATE DEFINITION AND IS GRABBED TOO.** MEASURED:
  // THE COMPILER EMITS BOTH `function $_________tinybendygrad_helpers_i64_of_hi_lo(` AND
  // `const $$_________tinybendygrad_helpers_i64_of_hi_lo = $_________...;` -- SO THE ALIAS IS A
  // DISTINCT NAME AND IS ITS OWN PIECE.
  let i = src.indexOf("{", at), depth = 0, k = i;
  for (;;) {
    if (src[k] === "{") depth += 1;
    else if (src[k] === "}") { depth -= 1; if (depth === 0) break; }
    k += 1;
  }
  return src.slice(at, k + 1);
}

// THE COMPILED PORT's TABLES. THE NAMES ARE THE COMPILER's, AND A MISSING ONE IS A FINDING.
const NAMES = ["$_________tinybendygrad_renderer_live_dt_of",
               "$_________tinybendygrad_renderer_live_addr_of",
               "$_________tinybendygrad_renderer_live_arg_of",
               "$_________tinybendygrad_renderer_live_arg_of_range",
               "$_________tinybendygrad_renderer_live_arg_of_wmma"];
for (const n of NAMES) {
  if (!src.includes("function " + n + "(")) {
    console.log("MISSING " + n + " -- the compiled renderer has no such table");
    process.exit(1);
  }
}
// **=> AND THE TABLES' DEPENDENCIES ARE EVALUATED TOO.** `dt_of` CALLS `LAWS/spec.bend`'s
// CONSTRUCTORS AND `arg_of` CALLS `arg_of.range` / `arg_of.wmma`, SO THE WHOLE CLOSURE IS EVALUATED:
// EVERY FUNCTION DEFINITION IN THE COMPILED FILE, IN FILE ORDER. **=> AND THE COMPILED FILE IS NOT
// LOADED AS A MODULE** -- IT IS THE PORT's OWN JS, WITH `require` CALLS, AND BOTH `bun` AND `node` LOAD
// A `.js` FILE AS ESM WHEN THE TREE's `package.json` SAYS SO.
// **=> AND THE CLOSURE IS 45 FUNCTIONS, NOT THE WHOLE FILE.** EVALUATING EVERY DEFINITION HANGS,
// BECAUSE THE COMPILED FILE's LAST FUNCTIONS ARE THE CLI AND THE I/O. **=> SO THE CLOSURE IS COMPUTED**
// (THE TABLES, PLUS EVERY FUNCTION THEY NAME, TRANSITIVELY) AND EVALUATED **IN FILE ORDER**, WHICH IS
// THE ORDER THE COMPILER EMITTED THEM IN AND SO THE ORDER THEY RESOLVE IN.
const need = new Set();
const frontier = NAMES.slice();
while (frontier.length) {
  const n = frontier.pop();
  if (need.has(n)) continue;
  const body = grab(n);
  if (body === null) continue;
  need.add(n);
  // **=> AND A `$` IN AN IDENTIFIER IS DOUBLED AT A CALL SITE.** MEASURED: THE DEFINITION IS
  // `function $_________tinybendygrad_helpers_i64_of_hi_lo(` AND THE CALL SITE READS
  // `$$_________tinybendygrad_helpers_i64_of_hi_lo(` -- SO A CALL SITE'S `$$` IS ONE `$`.
  for (const m of body.matchAll(/(\$+[A-Za-z0-9_]+)\(/g)) {
    frontier.push(m[1]);
    // **AND THE ALIAS IS ITS OWN NAME, SO IT IS IN THE CLOSURE UNDER THE `$$` SPELLING** -- WHICH
    // IS WHAT THE SCAN SEES AT A CALL SITE.
    // **=> AND A CALL SITE'S `$$` IS THE ESCAPED FORM OF A `$`-PREFIXED NAME, AND THE FILE DEFINES
    // THE ALIAS UNDER THE DOUBLED SPELLING.** MEASURED: THE DEFINITION IS
    // `function $_________tinybendygrad_helpers_i64_of_hi_lo(` AND THE ALIAS IS
    // `const $$_________tinybendygrad_helpers_i64_of_hi_lo = ...`, AND THE CALL SITE USES THE ALIAS.
    // **SO BOTH SPELLINGS ARE IN THE CLOSURE.**
    if (m[1].startsWith("$$")) frontier.push("$" + m[1].slice(2));
    else frontier.push("$" + m[1]);
  }
  // **AND THE RUNTIME HELPERS ARE PLAIN JS NAMES** (`char_len`, `char_code`, `u32_to_word`,
  // `word_to_u32`), NOT `$`-PREFIXED, SO THE SCAN TAKES THEM TOO.
  for (const m of body.matchAll(/\b([a-z][A-Za-z0-9_]*)\(/g)) {
    frontier.push(m[1]);
  }
}
// **=> AND THE CLOSURE IS EVALUATED IN ONE PIECE, BECAUSE A SEPARATE EVAL HAS ITS OWN SCOPE.** THE
// COMPILER'S ALIASES ARE `const` (MEASURED:
// `const $$_________tinybendygrad_helpers_i64_of_hi_lo = $_________tinybendygrad_helpers_i64_of_hi_lo;`
// -- **THE `$$` IS THE ESCAPED FORM OF A `$`-PREFIXED NAME** -- AND A `const` EVALUATED ALONE IS NOT
// VISIBLE TO THE NEXT EVAL. **=> SO THE CLOSURE IS CONCATENATED, IN FILE ORDER, AND EVALUATED ONCE.**
let piece = "";
let defined = 0;
// **=> AND THE NAME IS TAKEN AS IT APPEARS, `$$` AND ALL.** THE COMPILER'S ALIASES ARE NAMED WITH A
// DOUBLED `$`, AND A REGEX THAT CAPTURES `[A-Za-z0-9_$]+` GETS THE WHOLE NAME -- SO THE ONLY THING
// THAT MATTERS IS THAT THE CLOSURE'S NAMES ARE THE FILE'S NAMES. **AND THE FIRST DEFINITION HAS NO
// LEADING NEWLINE** (MEASURED: THE COMPILED FILE BEGINS `function word_to_u32(w) {`), SO THE PATTERN
// IS `(?:^|\n)`.
for (const m of src.matchAll(/(?:^|\n)(?:function|const) ([A-Za-z0-9_$]*)[ (=]/g)) {
  if (!need.has(m[1])) continue;
  const body = grab(m[1]);
  if (body === null) continue;
  piece += "\n" + body;
  defined += 1;
}
// eslint-disable-next-line no-eval
(0, eval)(piece);
for (const n of NAMES) {
  if (typeof eval(n) !== "function") {
    console.log("MISSING " + n + " -- the compiled renderer has no such table (" + defined + " evaluated)");
    process.exit(1);
  }
}

// THE STRING TABLE, RE-TYPED -- THE PORT's OWN, BEFORE THE CHANGE. THE DTYPE's ANSWER IS THE SPEC's
// DTYPE NAME, THE ADDRSPACE's IS ITS CONSTRUCTOR, AND THE ARG KIND'S IS ITS PAYLOAD'S CONSTRUCTOR.
const DT_STR = {
  "1": "f32", "2": "i32", "3": "u32", "4": "i64", "5": "u64", "6": "u8", "7": "i8",
  "8": "u16", "9": "i16", "b": "bool", "v": "void", "w": "weakint", "W": "weakfloat",
  "h": "f16", "B": "bf16", "d": "f64",
};
const ADDR_STR = { "g": "AGlobal", "l": "ALocal", "r": "AReg" };
const ARG_STR = {
  "i": "CInt", "f": "CFloat", "t": "CBool", "p": "PARAM", "x": "INDEX",
  "s": "SINK", "q": "SPECIAL",
  "RW": "AXIS_WEAK", "RG": "AXIS_GLOBAL", "RL": "AXIS_LOCAL", "RD": "AXIS_DEVICE",
  "RU": "AXIS_UPCAST", "RR": "AXIS_WARP", "RO": "AXIS_LOOP", "RP": "AXIS_PLACEHOLDER",
  "M1": "f32", "M2": "f16", "M3": "bf16",
};

function dtName(d) {
  // THE PORT's `S.Dt` CARRIES ITS OWN NAME IN `nm` (`LAWS/spec.bend`'s `Dt{pri, bits, cls, nm}`).
  return d && d.nm !== undefined ? d.nm : JSON.stringify(d);
}
function kindOf(tag) {
  switch (tag) {
    case "KAConst": return "CONST";
    case "KAParam": return "PARAM";
    case "KAIndex": return "INDEX";
    case "KASink": return "SINK";
    case "KASpecial": return "SPECIAL";
    case "KARange": return "RANGE";
    case "KAWmma": return "WMMA";
    case "KANone": return "NONE";
    default: return "?" + tag;
  }
}

let bad = 0, n = 0;
const DT = eval(NAMES[0]);
const ADDR = eval(NAMES[1]);
const ARG = eval(NAMES[2]);

// THE DTYPE CODES.
for (const [code, want] of Object.entries(DT_STR)) {
  const got = dtName(DT(code.charCodeAt(0)));
  n += 1;
  if (got !== want) {
    bad += 1;
    console.log("DT MISMATCH " + JSON.stringify(code) + " -> " + got + " want " + want);
  }
}
// THE ADDRSPACE CODES.
for (const [code, want] of Object.entries(ADDR_STR)) {
  const got = ADDR(code.charCodeAt(0));
  n += 1;
  if (got.$ !== want) {
    bad += 1;
    console.log("ADDR MISMATCH " + JSON.stringify(code) + " -> " + got.$ + " want " + want);
  }
}
// THE ARG KINDS: THE FIRST CHARACTER SEPARATES THE GROUPS AND THE SECOND PICKS INSIDE ONE.
for (const [code, want] of Object.entries(ARG_STR)) {
  const c0 = code.charCodeAt(0);
  const c1 = code.length > 1 ? code.charCodeAt(1) : 0;
  const got = ARG(c0, c1, "0");
  const k = kindOf(got && got.$);
  let ok;
  if (want.startsWith("AXIS_")) {
    ok = k === "RANGE" && JSON.stringify(got).indexOf(want) >= 0;
  } else if (want === "f32" || want === "f16" || want === "bf16") {
    ok = k === "WMMA" && JSON.stringify(got).indexOf('"' + want + '"') >= 0;
  } else if (want === "CInt" || want === "CFloat" || want === "CBool") {
    ok = k === "CONST" && JSON.stringify(got).indexOf('"' + want + '"') >= 0;
  } else {
    ok = k === want;
  }
  n += 1;
  if (!ok) {
    bad += 1;
    console.log("ARG MISMATCH " + JSON.stringify(code) + " -> " + k + " " + JSON.stringify(got));
  }
}
console.log("PROBE: " + n + " codes checked, " + bad + " mismatches");
process.exit(bad ? 1 : 0);
