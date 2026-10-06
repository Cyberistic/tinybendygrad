function word_to_u32(w) {
  let x = 0;
  for (let i = 0; w.$ === "WCon"; i++) {
    x |= Number(w.head) << i;
    w = w.tail;
  }
  return x >>> 0;
}

function u32_to_word(x) {
  let w = {$: "WNil"};
  for (let i = 31; i >= 0; i--) {
    w = {$: "WCon", head: ((x >>> i) & 1) === 1, tail: w};
  }
  return w;
}

function cmp_new(a, b) {
  return {$: a < b ? "LT"
    : a === b ? "EQ" : "GT"};
}

function nat_divmod(a, b) {
  return b === 0 ? {$: "Tuple", fst: 0, snd: a}
    : {$: "Tuple", fst: Math.trunc(a / b), snd: a % b};
}

function nat_chk(n) {
  if (n > 281474976710655) {
    throw "bend: a Nat past the largest immediate 2^48-1";
  }
  return n;
}

function nat_host(n) {
  const int = typeof n === "bigint" || Number.isInteger(n);
  if (int && n >= 0 && n <= 2 ** 53) {
    return Number(n);
  }
  return { [Symbol.toPrimitive]() { throw "bend: a Nat past the largest immediate 2^48-1"; } };
}

function f32_show(x) {
  if (x !== x) {
    return "nan";
  }
  if (!Number.isFinite(x) || Object.is(x, -0)) {
    return x < 0 ? "-inf"
      : x === 0 ? "-0" : "inf";
  }
  let s = "x";
  for (let p = 1; p <= 9 && f32_round(s) !== x; p += 1) {
    s = String(Number(x.toExponential(p - 1)));
  }
  return s;
}

function f32_bits(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function f32_from_bits(u) {
  return new Float32Array(new Uint32Array([u]).buffer)[0];
}

function f32_read(s) {
  const re = /^\s*[+-]?((\d+\.?\d*|\.\d+)(e[+-]?\d+)?|inf(inity)?|nan)$/i;
  const v = f32_round(s.replace(/inf\w*/i, "Infinity"));
  return re.test(s) ? {$: "Some", value: v} : {$: "None"};
}

const f32_round = function f32_round(s) {
  const d = Number(s), a = Math.abs(d), f = Math.fround(a), g = 2 * a - Math.min(f, 340282366920938500000000000000000000000);
  if (g === f || Math.fround(g) !== g || g === 1 / 0)
    return Math.sign(d) * f;
  let k = 0;
  while (a * 2 ** k % 1 !== 0)
    k += 1;
  const [, i, r, e] = /(\d*)\.?(\d*)(?:e([+-]?\d+))?$/i.exec(s), n = Number(e ?? 0) - r.length, x = BigInt(i + r) * 2n ** BigInt(k) * 10n ** BigInt(Math.max(n, 0)), y = BigInt(a * 2 ** k) * 10n ** BigInt(Math.max(-n, 0));
  return Math.sign(d) * (x === y || x > y !== g > f ? f : g);
};

function char_new(code) {
  if (code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
    throw "bend: " + code + " is not a Unicode scalar value";
  }
  return String.fromCodePoint(code);
}

// Array
// =====

function array_new(d, v) {
  if (d > 31) {
    throw "bend: an array past the deepest block class 31";
  }
  return Array(2 ** d).fill(v);
}

function array_node(a, b) {
  if (a.length !== b.length) {
    throw "bend: runtime fail-stop";
  }
  return a.concat(b);
}

function array_rmw(a, i, f) {
  const at = i % a.length;
  const old = a[at];
  a[at] = f(old);
  return {$: "Tuple", fst: a, snd: old};
}

// Run
// ===

function run_tail(f, x) {
  return {$: "$JMP", f: f.j?.f === f ? f.j : f, x: [x]};
}

function run_clo(j) {
  const f = (x) => run_loop(j(x));
  f.j = j;
  j.f = f;
  return f;
}

function run_loop(r) {
  while (r !== null && typeof r === "object" && r.$ === "$JMP") {
    r = r.f(...r.x);
  }
  return r;
}

function run_lib(f, n) {
  return (...a) => a.length < n ? run_lib((...b) => f(...a, ...b), n - a.length)
    : f(...a);
}

// Effect
// ======

const $0eff = Object.create(null);

function io_eff(k, run, need) {
  if (k in $0eff) {
    throw new Error("bend: two effects register " + k);
  }
  $0eff[k] = { run, need };
}
(() => {
// IO
// ==

function io_print(text) {
  io_out(1, io_bytes(text + "\n"));
  return { $: "Unit" };
}

io_eff("IO.print", io_print);

})();

for (const k of ["IO.print"]) {
  if (!(k in $0eff)) {
    throw new Error("bend: no effect registers " + k);
  }
}

// Program
// =======

function $main$() {
  const _v0_0 = ($tinybendygrad$047dtype$Dt$fp16$(1.5));
  return run_clo((_x_0) => {
  const _x_1 = f32_show(_v0_0);
  return $IO$bind$((_x_2) => $IO$print$(("F32ROW abi4_fp16_1p5 = " + _x_1), _x_2), run_clo((_x_3) => {
  const _v1_0 = ($tinybendygrad$047dtype$Dt$fp16$(1.100000023841858));
  return run_clo((_x_4) => {
  const _x_5 = f32_show(_v1_0);
  return $IO$bind$((_x_6) => $IO$print$(("F32ROW abi4_fp16_1p1 = " + _x_5), _x_6), run_clo((_x_7) => {
  const _v2_0 = ($tinybendygrad$047dtype$Dt$fp16$((-2.25)));
  return run_clo((_x_8) => {
  const _x_9 = f32_show(_v2_0);
  return $IO$bind$((_x_10) => $IO$print$(("F32ROW abi4_fp16_m2p25 = " + _x_9), _x_10), run_clo((_x_11) => {
  const _v3_0 = ($tinybendygrad$047dtype$Dt$fp16$(0.5));
  return run_clo((_x_12) => {
  const _x_13 = f32_show(_v3_0);
  return $IO$bind$((_x_14) => $IO$print$(("F32ROW abi4_fp16_0p5 = " + _x_13), _x_14), run_clo((_x_15) => {
  const _v4_0 = ($tinybendygrad$047dtype$Dt$fp16$(100));
  return run_clo((_x_16) => {
  const _x_17 = f32_show(_v4_0);
  return $IO$bind$((_x_18) => $IO$print$(("F32ROW abi4_fp16_100p0 = " + _x_17), _x_18), run_clo((_x_19) => {
  const _v5_0 = ($tinybendygrad$047dtype$Dt$fp16$(65504));
  return run_clo((_x_20) => {
  const _x_21 = f32_show(_v5_0);
  return $IO$bind$((_x_22) => $IO$print$(("F32ROW abi4_fp16_65504p0 = " + _x_21), _x_22), run_clo((_x_23) => {
  const _v6_0 = ($tinybendygrad$047dtype$Dt$fp16$(9.99999993922529e-9));
  return run_clo((_x_24) => {
  const _x_25 = f32_show(_v6_0);
  return $IO$bind$((_x_26) => $IO$print$(("F32ROW abi4_fp16_1em08 = " + _x_25), _x_26), run_clo((_x_27) => {
  const _v7_0 = ($tinybendygrad$047dtype$Dt$fp16$((-0)));
  return run_clo((_x_28) => {
  const _x_29 = f32_show(_v7_0);
  return $IO$bind$((_x_30) => $IO$print$(("F32ROW abi4_fp16_m0p0 = " + _x_29), _x_30), run_clo((_x_31) => {
  const _v8_0 = ($tinybendygrad$047dtype$Dt$fp16$(0));
  return run_clo((_x_32) => {
  const _x_33 = f32_show(_v8_0);
  return $IO$bind$((_x_34) => $IO$print$(("F32ROW abi4_fp16_0p0 = " + _x_33), _x_34), run_clo((_x_35) => {
  const _v9_0 = ($tinybendygrad$047dtype$Dt$fp16$(1073741824));
  return run_clo((_x_36) => {
  const _x_37 = f32_show(_v9_0);
  return $IO$bind$((_x_38) => $IO$print$(("F32ROW abi4_fp16_1073741824p0 = " + _x_37), _x_38), run_clo((_x_39) => {
  const _v10_0 = ($tinybendygrad$047dtype$Dt$fp16$(1069547520));
  return run_clo((_x_40) => {
  const _x_41 = f32_show(_v10_0);
  return $IO$bind$((_x_42) => $IO$print$(("F32ROW abi4_fp16_1069547520p0 = " + _x_41), _x_42), run_clo((_x_43) => {
  const _v11_0 = ($tinybendygrad$047dtype$Dt$fp16$(3221225472));
  return run_clo((_x_44) => {
  const _x_45 = f32_show(_v11_0);
  return $IO$bind$((_x_46) => $IO$print$(("F32ROW abi4_fp16_3221225472p0 = " + _x_45), _x_46), run_clo((_x_47) => {
  const _v12_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(0, 0));
  return run_clo((_x_48) => {
  const _x_49 = f32_show(_v12_0);
  return $IO$bind$((_x_50) => $IO$print$(("F32ROW abi4_fp8to_0_00 = " + _x_49), _x_50), run_clo((_x_51) => {
  const _v13_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(1, 0));
  return run_clo((_x_52) => {
  const _x_53 = f32_show(_v13_0);
  return $IO$bind$((_x_54) => $IO$print$(("F32ROW abi4_fp8to_0_01 = " + _x_53), _x_54), run_clo((_x_55) => {
  const _v14_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(4, 0));
  return run_clo((_x_56) => {
  const _x_57 = f32_show(_v14_0);
  return $IO$bind$((_x_58) => $IO$print$(("F32ROW abi4_fp8to_0_04 = " + _x_57), _x_58), run_clo((_x_59) => {
  const _v15_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(8, 0));
  return run_clo((_x_60) => {
  const _x_61 = f32_show(_v15_0);
  return $IO$bind$((_x_62) => $IO$print$(("F32ROW abi4_fp8to_0_08 = " + _x_61), _x_62), run_clo((_x_63) => {
  const _v16_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(60, 0));
  return run_clo((_x_64) => {
  const _x_65 = f32_show(_v16_0);
  return $IO$bind$((_x_66) => $IO$print$(("F32ROW abi4_fp8to_0_3C = " + _x_65), _x_66), run_clo((_x_67) => {
  const _v17_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(124, 0));
  return run_clo((_x_68) => {
  const _x_69 = f32_show(_v17_0);
  return $IO$bind$((_x_70) => $IO$print$(("F32ROW abi4_fp8to_0_7C = " + _x_69), _x_70), run_clo((_x_71) => {
  const _v18_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(126, 0));
  return run_clo((_x_72) => {
  const _x_73 = f32_show(_v18_0);
  return $IO$bind$((_x_74) => $IO$print$(("F32ROW abi4_fp8to_0_7E = " + _x_73), _x_74), run_clo((_x_75) => {
  const _v19_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(127, 0));
  return run_clo((_x_76) => {
  const _x_77 = f32_show(_v19_0);
  return $IO$bind$((_x_78) => $IO$print$(("F32ROW abi4_fp8to_0_7F = " + _x_77), _x_78), run_clo((_x_79) => {
  const _v20_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(128, 0));
  return run_clo((_x_80) => {
  const _x_81 = f32_show(_v20_0);
  return $IO$bind$((_x_82) => $IO$print$(("F32ROW abi4_fp8to_0_80 = " + _x_81), _x_82), run_clo((_x_83) => {
  const _v21_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(129, 0));
  return run_clo((_x_84) => {
  const _x_85 = f32_show(_v21_0);
  return $IO$bind$((_x_86) => $IO$print$(("F32ROW abi4_fp8to_0_81 = " + _x_85), _x_86), run_clo((_x_87) => {
  const _v22_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(255, 0));
  return run_clo((_x_88) => {
  const _x_89 = f32_show(_v22_0);
  return $IO$bind$((_x_90) => $IO$print$(("F32ROW abi4_fp8to_0_FF = " + _x_89), _x_90), run_clo((_x_91) => {
  const _v23_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(0, 1));
  return run_clo((_x_92) => {
  const _x_93 = f32_show(_v23_0);
  return $IO$bind$((_x_94) => $IO$print$(("F32ROW abi4_fp8to_1_00 = " + _x_93), _x_94), run_clo((_x_95) => {
  const _v24_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(1, 1));
  return run_clo((_x_96) => {
  const _x_97 = f32_show(_v24_0);
  return $IO$bind$((_x_98) => $IO$print$(("F32ROW abi4_fp8to_1_01 = " + _x_97), _x_98), run_clo((_x_99) => {
  const _v25_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(4, 1));
  return run_clo((_x_100) => {
  const _x_101 = f32_show(_v25_0);
  return $IO$bind$((_x_102) => $IO$print$(("F32ROW abi4_fp8to_1_04 = " + _x_101), _x_102), run_clo((_x_103) => {
  const _v26_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(8, 1));
  return run_clo((_x_104) => {
  const _x_105 = f32_show(_v26_0);
  return $IO$bind$((_x_106) => $IO$print$(("F32ROW abi4_fp8to_1_08 = " + _x_105), _x_106), run_clo((_x_107) => {
  const _v27_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(60, 1));
  return run_clo((_x_108) => {
  const _x_109 = f32_show(_v27_0);
  return $IO$bind$((_x_110) => $IO$print$(("F32ROW abi4_fp8to_1_3C = " + _x_109), _x_110), run_clo((_x_111) => {
  const _v28_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(124, 1));
  return run_clo((_x_112) => {
  const _x_113 = f32_show(_v28_0);
  return $IO$bind$((_x_114) => $IO$print$(("F32ROW abi4_fp8to_1_7C = " + _x_113), _x_114), run_clo((_x_115) => {
  const _v29_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(126, 1));
  return run_clo((_x_116) => {
  const _x_117 = f32_show(_v29_0);
  return $IO$bind$((_x_118) => $IO$print$(("F32ROW abi4_fp8to_1_7E = " + _x_117), _x_118), run_clo((_x_119) => {
  const _v30_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(127, 1));
  return run_clo((_x_120) => {
  const _x_121 = f32_show(_v30_0);
  return $IO$bind$((_x_122) => $IO$print$(("F32ROW abi4_fp8to_1_7F = " + _x_121), _x_122), run_clo((_x_123) => {
  const _v31_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(128, 1));
  return run_clo((_x_124) => {
  const _x_125 = f32_show(_v31_0);
  return $IO$bind$((_x_126) => $IO$print$(("F32ROW abi4_fp8to_1_80 = " + _x_125), _x_126), run_clo((_x_127) => {
  const _v32_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(129, 1));
  return run_clo((_x_128) => {
  const _x_129 = f32_show(_v32_0);
  return $IO$bind$((_x_130) => $IO$print$(("F32ROW abi4_fp8to_1_81 = " + _x_129), _x_130), run_clo((_x_131) => {
  const _v33_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(255, 1));
  return run_clo((_x_132) => {
  const _x_133 = f32_show(_v33_0);
  return $IO$bind$((_x_134) => $IO$print$(("F32ROW abi4_fp8to_1_FF = " + _x_133), _x_134), run_clo((_x_135) => {
  const _v34_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(0, 2));
  return run_clo((_x_136) => {
  const _x_137 = f32_show(_v34_0);
  return $IO$bind$((_x_138) => $IO$print$(("F32ROW abi4_fp8to_2_00 = " + _x_137), _x_138), run_clo((_x_139) => {
  const _v35_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(1, 2));
  return run_clo((_x_140) => {
  const _x_141 = f32_show(_v35_0);
  return $IO$bind$((_x_142) => $IO$print$(("F32ROW abi4_fp8to_2_01 = " + _x_141), _x_142), run_clo((_x_143) => {
  const _v36_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(4, 2));
  return run_clo((_x_144) => {
  const _x_145 = f32_show(_v36_0);
  return $IO$bind$((_x_146) => $IO$print$(("F32ROW abi4_fp8to_2_04 = " + _x_145), _x_146), run_clo((_x_147) => {
  const _v37_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(8, 2));
  return run_clo((_x_148) => {
  const _x_149 = f32_show(_v37_0);
  return $IO$bind$((_x_150) => $IO$print$(("F32ROW abi4_fp8to_2_08 = " + _x_149), _x_150), run_clo((_x_151) => {
  const _v38_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(60, 2));
  return run_clo((_x_152) => {
  const _x_153 = f32_show(_v38_0);
  return $IO$bind$((_x_154) => $IO$print$(("F32ROW abi4_fp8to_2_3C = " + _x_153), _x_154), run_clo((_x_155) => {
  const _v39_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(124, 2));
  return run_clo((_x_156) => {
  const _x_157 = f32_show(_v39_0);
  return $IO$bind$((_x_158) => $IO$print$(("F32ROW abi4_fp8to_2_7C = " + _x_157), _x_158), run_clo((_x_159) => {
  const _v40_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(126, 2));
  return run_clo((_x_160) => {
  const _x_161 = f32_show(_v40_0);
  return $IO$bind$((_x_162) => $IO$print$(("F32ROW abi4_fp8to_2_7E = " + _x_161), _x_162), run_clo((_x_163) => {
  const _v41_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(127, 2));
  return run_clo((_x_164) => {
  const _x_165 = f32_show(_v41_0);
  return $IO$bind$((_x_166) => $IO$print$(("F32ROW abi4_fp8to_2_7F = " + _x_165), _x_166), run_clo((_x_167) => {
  const _v42_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(128, 2));
  return run_clo((_x_168) => {
  const _x_169 = f32_show(_v42_0);
  return $IO$bind$((_x_170) => $IO$print$(("F32ROW abi4_fp8to_2_80 = " + _x_169), _x_170), run_clo((_x_171) => {
  const _v43_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(129, 2));
  return run_clo((_x_172) => {
  const _x_173 = f32_show(_v43_0);
  return $IO$bind$((_x_174) => $IO$print$(("F32ROW abi4_fp8to_2_81 = " + _x_173), _x_174), run_clo((_x_175) => {
  const _v44_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(255, 2));
  return run_clo((_x_176) => {
  const _x_177 = f32_show(_v44_0);
  return $IO$bind$((_x_178) => $IO$print$(("F32ROW abi4_fp8to_2_FF = " + _x_177), _x_178), run_clo((_x_179) => {
  const _v45_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(0, 3));
  return run_clo((_x_180) => {
  const _x_181 = f32_show(_v45_0);
  return $IO$bind$((_x_182) => $IO$print$(("F32ROW abi4_fp8to_3_00 = " + _x_181), _x_182), run_clo((_x_183) => {
  const _v46_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(1, 3));
  return run_clo((_x_184) => {
  const _x_185 = f32_show(_v46_0);
  return $IO$bind$((_x_186) => $IO$print$(("F32ROW abi4_fp8to_3_01 = " + _x_185), _x_186), run_clo((_x_187) => {
  const _v47_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(4, 3));
  return run_clo((_x_188) => {
  const _x_189 = f32_show(_v47_0);
  return $IO$bind$((_x_190) => $IO$print$(("F32ROW abi4_fp8to_3_04 = " + _x_189), _x_190), run_clo((_x_191) => {
  const _v48_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(8, 3));
  return run_clo((_x_192) => {
  const _x_193 = f32_show(_v48_0);
  return $IO$bind$((_x_194) => $IO$print$(("F32ROW abi4_fp8to_3_08 = " + _x_193), _x_194), run_clo((_x_195) => {
  const _v49_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(60, 3));
  return run_clo((_x_196) => {
  const _x_197 = f32_show(_v49_0);
  return $IO$bind$((_x_198) => $IO$print$(("F32ROW abi4_fp8to_3_3C = " + _x_197), _x_198), run_clo((_x_199) => {
  const _v50_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(124, 3));
  return run_clo((_x_200) => {
  const _x_201 = f32_show(_v50_0);
  return $IO$bind$((_x_202) => $IO$print$(("F32ROW abi4_fp8to_3_7C = " + _x_201), _x_202), run_clo((_x_203) => {
  const _v51_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(126, 3));
  return run_clo((_x_204) => {
  const _x_205 = f32_show(_v51_0);
  return $IO$bind$((_x_206) => $IO$print$(("F32ROW abi4_fp8to_3_7E = " + _x_205), _x_206), run_clo((_x_207) => {
  const _v52_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(127, 3));
  return run_clo((_x_208) => {
  const _x_209 = f32_show(_v52_0);
  return $IO$bind$((_x_210) => $IO$print$(("F32ROW abi4_fp8to_3_7F = " + _x_209), _x_210), run_clo((_x_211) => {
  const _v53_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(128, 3));
  return run_clo((_x_212) => {
  const _x_213 = f32_show(_v53_0);
  return $IO$bind$((_x_214) => $IO$print$(("F32ROW abi4_fp8to_3_80 = " + _x_213), _x_214), run_clo((_x_215) => {
  const _v54_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(129, 3));
  return run_clo((_x_216) => {
  const _x_217 = f32_show(_v54_0);
  return $IO$bind$((_x_218) => $IO$print$(("F32ROW abi4_fp8to_3_81 = " + _x_217), _x_218), run_clo((_x_219) => {
  const _v55_0 = ($tinybendygrad$047dtype$Dt$fp8_to$(255, 3));
  return run_clo((_x_220) => {
  const _x_221 = f32_show(_v55_0);
  return $IO$bind$((_x_222) => $IO$print$(("F32ROW abi4_fp8to_3_FF = " + _x_221), _x_222), run_clo((_x_223) => {
  const _v56_0 = ($tinybendygrad$047dtype$Dt$bf16$(1069547520));
  return run_clo((_x_224) => {
  const _x_225 = f32_show(_v56_0);
  return $IO$bind$((_x_226) => $IO$print$(("F32ROW loc_bf16_3FC00000 = " + _x_225), _x_226), run_clo((_x_227) => {
  const _v57_0 = ($tinybendygrad$047dtype$Dt$bf16$(3212836864));
  return run_clo((_x_228) => {
  const _x_229 = f32_show(_v57_0);
  return $IO$bind$((_x_230) => $IO$print$(("F32ROW loc_bf16_BF800000 = " + _x_229), _x_230), run_clo((_x_231) => {
  const _v58_0 = ($tinybendygrad$047dtype$Dt$bf16$(1));
  return run_clo((_x_232) => {
  const _x_233 = f32_show(_v58_0);
  return $IO$bind$((_x_234) => $IO$print$(("F32ROW loc_bf16_00000001 = " + _x_233), _x_234), run_clo((_x_235) => {
  const _v59_0 = ($tinybendygrad$047dtype$Dt$bf16$(2139095040));
  return run_clo((_x_236) => {
  const _x_237 = f32_show(_v59_0);
  return $IO$bind$((_x_238) => $IO$print$(("F32ROW loc_bf16_7F800000 = " + _x_237), _x_238), run_clo((_x_239) => {
  const _v60_0 = ($tinybendygrad$047dtype$Dt$bf16$(2143289344));
  return run_clo((_x_240) => {
  const _x_241 = f32_show(_v60_0);
  return $IO$bind$((_x_242) => $IO$print$(("F32ROW loc_bf16_7FC00000 = " + _x_241), _x_242), run_clo((_x_243) => {
  const _v61_0 = ($tinybendygrad$047dtype$Dt$bf16$(1199562752));
  return run_clo((_x_244) => {
  const _x_245 = f32_show(_v61_0);
  return $IO$bind$((_x_246) => $IO$print$(("F32ROW loc_bf16_477FE000 = " + _x_245), _x_246), run_clo((_x_247) => {
  const _v62_0 = ($tinybendygrad$047dtype$Dt$bf16$(1065353216));
  return run_clo((_x_248) => {
  const _x_249 = f32_show(_v62_0);
  return $IO$bind$((_x_250) => $IO$print$(("F32ROW loc_bf16_3F800000 = " + _x_249), _x_250), run_clo((_x_251) => {
  const _v63_0 = ($tinybendygrad$047dtype$Dt$bf16$(1073741824));
  return run_clo((_x_252) => {
  const _x_253 = f32_show(_v63_0);
  return $IO$bind$((_x_254) => $IO$print$(("F32ROW loc_bf16_40000000 = " + _x_253), _x_254), run_clo((_x_255) => {
  const _v64_0 = ($tinybendygrad$047dtype$Dt$bf16$(8388608));
  return run_clo((_x_256) => {
  const _x_257 = f32_show(_v64_0);
  return $IO$bind$((_x_258) => $IO$print$(("F32ROW loc_bf16_00800000 = " + _x_257), _x_258), run_clo((_x_259) => {
  const _v65_0 = ($tinybendygrad$047dtype$Dt$bf16$(2139095039));
  return run_clo((_x_260) => {
  const _x_261 = f32_show(_v65_0);
  return $IO$bind$((_x_262) => $IO$print$(("F32ROW loc_bf16_7F7FFFFF = " + _x_261), _x_262), run_clo((_x_263) => {
  const _v66_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1069547520, 0));
  return run_clo((_x_264) => {
  const _x_265 = ($U32$show$(_v66_0));
  return $IO$bind$((_x_266) => $IO$print$(("F32ROW loc_fp8from_0_3FC00000 = " + _x_265), _x_266), run_clo((_x_267) => {
  const _v67_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(3217031168, 0));
  return run_clo((_x_268) => {
  const _x_269 = ($U32$show$(_v67_0));
  return $IO$bind$((_x_270) => $IO$print$(("F32ROW loc_fp8from_0_BFC00000 = " + _x_269), _x_270), run_clo((_x_271) => {
  const _v68_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(0, 0));
  return run_clo((_x_272) => {
  const _x_273 = ($U32$show$(_v68_0));
  return $IO$bind$((_x_274) => $IO$print$(("F32ROW loc_fp8from_0_00000000 = " + _x_273), _x_274), run_clo((_x_275) => {
  const _v69_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(2147483648, 0));
  return run_clo((_x_276) => {
  const _x_277 = ($U32$show$(_v69_0));
  return $IO$bind$((_x_278) => $IO$print$(("F32ROW loc_fp8from_0_80000000 = " + _x_277), _x_278), run_clo((_x_279) => {
  const _v70_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1132462080, 0));
  return run_clo((_x_280) => {
  const _x_281 = ($U32$show$(_v70_0));
  return $IO$bind$((_x_282) => $IO$print$(("F32ROW loc_fp8from_0_43800000 = " + _x_281), _x_282), run_clo((_x_283) => {
  const _v71_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1138753536, 0));
  return run_clo((_x_284) => {
  const _x_285 = ($U32$show$(_v71_0));
  return $IO$bind$((_x_286) => $IO$print$(("F32ROW loc_fp8from_0_43E00000 = " + _x_285), _x_286), run_clo((_x_287) => {
  const _v72_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(841731191, 0));
  return run_clo((_x_288) => {
  const _x_289 = ($U32$show$(_v72_0));
  return $IO$bind$((_x_290) => $IO$print$(("F32ROW loc_fp8from_0_322BCC77 = " + _x_289), _x_290), run_clo((_x_291) => {
  const _v73_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1315859240, 0));
  return run_clo((_x_292) => {
  const _x_293 = ($U32$show$(_v73_0));
  return $IO$bind$((_x_294) => $IO$print$(("F32ROW loc_fp8from_0_4E6E6B28 = " + _x_293), _x_294), run_clo((_x_295) => {
  const _v74_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1069547520, 1));
  return run_clo((_x_296) => {
  const _x_297 = ($U32$show$(_v74_0));
  return $IO$bind$((_x_298) => $IO$print$(("F32ROW loc_fp8from_1_3FC00000 = " + _x_297), _x_298), run_clo((_x_299) => {
  const _v75_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(3217031168, 1));
  return run_clo((_x_300) => {
  const _x_301 = ($U32$show$(_v75_0));
  return $IO$bind$((_x_302) => $IO$print$(("F32ROW loc_fp8from_1_BFC00000 = " + _x_301), _x_302), run_clo((_x_303) => {
  const _v76_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(0, 1));
  return run_clo((_x_304) => {
  const _x_305 = ($U32$show$(_v76_0));
  return $IO$bind$((_x_306) => $IO$print$(("F32ROW loc_fp8from_1_00000000 = " + _x_305), _x_306), run_clo((_x_307) => {
  const _v77_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(2147483648, 1));
  return run_clo((_x_308) => {
  const _x_309 = ($U32$show$(_v77_0));
  return $IO$bind$((_x_310) => $IO$print$(("F32ROW loc_fp8from_1_80000000 = " + _x_309), _x_310), run_clo((_x_311) => {
  const _v78_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1132462080, 1));
  return run_clo((_x_312) => {
  const _x_313 = ($U32$show$(_v78_0));
  return $IO$bind$((_x_314) => $IO$print$(("F32ROW loc_fp8from_1_43800000 = " + _x_313), _x_314), run_clo((_x_315) => {
  const _v79_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1138753536, 1));
  return run_clo((_x_316) => {
  const _x_317 = ($U32$show$(_v79_0));
  return $IO$bind$((_x_318) => $IO$print$(("F32ROW loc_fp8from_1_43E00000 = " + _x_317), _x_318), run_clo((_x_319) => {
  const _v80_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(841731191, 1));
  return run_clo((_x_320) => {
  const _x_321 = ($U32$show$(_v80_0));
  return $IO$bind$((_x_322) => $IO$print$(("F32ROW loc_fp8from_1_322BCC77 = " + _x_321), _x_322), run_clo((_x_323) => {
  const _v81_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1315859240, 1));
  return run_clo((_x_324) => {
  const _x_325 = ($U32$show$(_v81_0));
  return $IO$bind$((_x_326) => $IO$print$(("F32ROW loc_fp8from_1_4E6E6B28 = " + _x_325), _x_326), run_clo((_x_327) => {
  const _v82_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1069547520, 2));
  return run_clo((_x_328) => {
  const _x_329 = ($U32$show$(_v82_0));
  return $IO$bind$((_x_330) => $IO$print$(("F32ROW loc_fp8from_2_3FC00000 = " + _x_329), _x_330), run_clo((_x_331) => {
  const _v83_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(3217031168, 2));
  return run_clo((_x_332) => {
  const _x_333 = ($U32$show$(_v83_0));
  return $IO$bind$((_x_334) => $IO$print$(("F32ROW loc_fp8from_2_BFC00000 = " + _x_333), _x_334), run_clo((_x_335) => {
  const _v84_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(0, 2));
  return run_clo((_x_336) => {
  const _x_337 = ($U32$show$(_v84_0));
  return $IO$bind$((_x_338) => $IO$print$(("F32ROW loc_fp8from_2_00000000 = " + _x_337), _x_338), run_clo((_x_339) => {
  const _v85_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(2147483648, 2));
  return run_clo((_x_340) => {
  const _x_341 = ($U32$show$(_v85_0));
  return $IO$bind$((_x_342) => $IO$print$(("F32ROW loc_fp8from_2_80000000 = " + _x_341), _x_342), run_clo((_x_343) => {
  const _v86_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1132462080, 2));
  return run_clo((_x_344) => {
  const _x_345 = ($U32$show$(_v86_0));
  return $IO$bind$((_x_346) => $IO$print$(("F32ROW loc_fp8from_2_43800000 = " + _x_345), _x_346), run_clo((_x_347) => {
  const _v87_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1138753536, 2));
  return run_clo((_x_348) => {
  const _x_349 = ($U32$show$(_v87_0));
  return $IO$bind$((_x_350) => $IO$print$(("F32ROW loc_fp8from_2_43E00000 = " + _x_349), _x_350), run_clo((_x_351) => {
  const _v88_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(841731191, 2));
  return run_clo((_x_352) => {
  const _x_353 = ($U32$show$(_v88_0));
  return $IO$bind$((_x_354) => $IO$print$(("F32ROW loc_fp8from_2_322BCC77 = " + _x_353), _x_354), run_clo((_x_355) => {
  const _v89_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1315859240, 2));
  return run_clo((_x_356) => {
  const _x_357 = ($U32$show$(_v89_0));
  return $IO$bind$((_x_358) => $IO$print$(("F32ROW loc_fp8from_2_4E6E6B28 = " + _x_357), _x_358), run_clo((_x_359) => {
  const _v90_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1069547520, 3));
  return run_clo((_x_360) => {
  const _x_361 = ($U32$show$(_v90_0));
  return $IO$bind$((_x_362) => $IO$print$(("F32ROW loc_fp8from_3_3FC00000 = " + _x_361), _x_362), run_clo((_x_363) => {
  const _v91_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(3217031168, 3));
  return run_clo((_x_364) => {
  const _x_365 = ($U32$show$(_v91_0));
  return $IO$bind$((_x_366) => $IO$print$(("F32ROW loc_fp8from_3_BFC00000 = " + _x_365), _x_366), run_clo((_x_367) => {
  const _v92_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(0, 3));
  return run_clo((_x_368) => {
  const _x_369 = ($U32$show$(_v92_0));
  return $IO$bind$((_x_370) => $IO$print$(("F32ROW loc_fp8from_3_00000000 = " + _x_369), _x_370), run_clo((_x_371) => {
  const _v93_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(2147483648, 3));
  return run_clo((_x_372) => {
  const _x_373 = ($U32$show$(_v93_0));
  return $IO$bind$((_x_374) => $IO$print$(("F32ROW loc_fp8from_3_80000000 = " + _x_373), _x_374), run_clo((_x_375) => {
  const _v94_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1132462080, 3));
  return run_clo((_x_376) => {
  const _x_377 = ($U32$show$(_v94_0));
  return $IO$bind$((_x_378) => $IO$print$(("F32ROW loc_fp8from_3_43800000 = " + _x_377), _x_378), run_clo((_x_379) => {
  const _v95_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1138753536, 3));
  return run_clo((_x_380) => {
  const _x_381 = ($U32$show$(_v95_0));
  return $IO$bind$((_x_382) => $IO$print$(("F32ROW loc_fp8from_3_43E00000 = " + _x_381), _x_382), run_clo((_x_383) => {
  const _v96_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(841731191, 3));
  return run_clo((_x_384) => {
  const _x_385 = ($U32$show$(_v96_0));
  return $IO$bind$((_x_386) => $IO$print$(("F32ROW loc_fp8from_3_322BCC77 = " + _x_385), _x_386), run_clo((_x_387) => {
  const _v97_0 = ($tinybendygrad$047dtype$Dt$fp8_from$(1315859240, 3));
  const _x_388 = ($U32$show$(_v97_0));
  return (_x_389) => $IO$print$(("F32ROW loc_fp8from_3_4E6E6B28 = " + _x_388), _x_389);
}), _x_384);
});
}), _x_380);
});
}), _x_376);
});
}), _x_372);
});
}), _x_368);
});
}), _x_364);
});
}), _x_360);
});
}), _x_356);
});
}), _x_352);
});
}), _x_348);
});
}), _x_344);
});
}), _x_340);
});
}), _x_336);
});
}), _x_332);
});
}), _x_328);
});
}), _x_324);
});
}), _x_320);
});
}), _x_316);
});
}), _x_312);
});
}), _x_308);
});
}), _x_304);
});
}), _x_300);
});
}), _x_296);
});
}), _x_292);
});
}), _x_288);
});
}), _x_284);
});
}), _x_280);
});
}), _x_276);
});
}), _x_272);
});
}), _x_268);
});
}), _x_264);
});
}), _x_260);
});
}), _x_256);
});
}), _x_252);
});
}), _x_248);
});
}), _x_244);
});
}), _x_240);
});
}), _x_236);
});
}), _x_232);
});
}), _x_228);
});
}), _x_224);
});
}), _x_220);
});
}), _x_216);
});
}), _x_212);
});
}), _x_208);
});
}), _x_204);
});
}), _x_200);
});
}), _x_196);
});
}), _x_192);
});
}), _x_188);
});
}), _x_184);
});
}), _x_180);
});
}), _x_176);
});
}), _x_172);
});
}), _x_168);
});
}), _x_164);
});
}), _x_160);
});
}), _x_156);
});
}), _x_152);
});
}), _x_148);
});
}), _x_144);
});
}), _x_140);
});
}), _x_136);
});
}), _x_132);
});
}), _x_128);
});
}), _x_124);
});
}), _x_120);
});
}), _x_116);
});
}), _x_112);
});
}), _x_108);
});
}), _x_104);
});
}), _x_100);
});
}), _x_96);
});
}), _x_92);
});
}), _x_88);
});
}), _x_84);
});
}), _x_80);
});
}), _x_76);
});
}), _x_72);
});
}), _x_68);
});
}), _x_64);
});
}), _x_60);
});
}), _x_56);
});
}), _x_52);
});
}), _x_48);
});
}), _x_44);
});
}), _x_40);
});
}), _x_36);
});
}), _x_32);
});
}), _x_28);
});
}), _x_24);
});
}), _x_20);
});
}), _x_16);
});
}), _x_12);
});
}), _x_8);
});
}), _x_4);
});
}), _x_0);
});
}

function $tinybendygrad$047dtype$Dt$fp16$(_x_0) {
  const _x_1 = f32_bits(_x_0);
  const _x_2 = (16 >= 32 ? 0 : (_x_1 >>> 16) >>> 0);
  const _x_3 = f32_bits(_x_0);
  const _x_4 = (23 >= 32 ? 0 : (_x_3 >>> 23) >>> 0);
  const _x_5 = f32_bits(_x_0);
  return $tinybendygrad$047base$F32$from_bits$(($tinybendygrad$047dtype$fp16_f32$(($tinybendygrad$047dtype$fp16_encode$(((_x_2 & 32768) >>> 0), ((_x_4 & 255) >>> 0), ((_x_5 & 8388607) >>> 0))))));
}

function $IO$bind$(_m_0, _f_0, _k_0) {
  return run_tail(_m_0, run_clo((_x_0) => {
  return run_tail(_f_0(_x_0), _k_0);
}));
}

function $IO$print$(_text_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.print"].run, need: $0eff["IO.print"].need, args: [(_text_0)], kont: (_k_0) };
}
function $tinybendygrad$047dtype$Dt$fp8_to$(_bits_0, _kind_0) {
  return $tinybendygrad$047base$F32$from_bits$(($tinybendygrad$047dtype$fp8_decode$(((_bits_0 & 255) >>> 0), _kind_0)));
}

function $tinybendygrad$047dtype$Dt$bf16$(_bits_0) {
  const _x_0 = ((_bits_0 & 2139095040) >>> 0);
  return $tinybendygrad$047base$F32$from_bits$(($Bool$pick$((_x_0 === 2139095040), _bits_0, ($tinybendygrad$047dtype$bf16$round$(_bits_0)))));
}

function $tinybendygrad$047dtype$Dt$fp8_from$(_bits_0, _kind_0) {
  return $tinybendygrad$047dtype$fp8_enc$(($tinybendygrad$047dtype$fp8_cfg$(_kind_0)), _kind_0, _bits_0);
}

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
}

function $tinybendygrad$047base$F32$from_bits$(_bits_0) {
  return f32_from_bits(_bits_0);
}

function $tinybendygrad$047dtype$fp16_f32$(_h_0) {
  const _x_0 = (10 >= 32 ? 0 : (_h_0 >>> 10) >>> 0);
  const _x_1 = ((_x_0 & 31) >>> 0);
  const _x_2 = (15 >= 32 ? 0 : (_h_0 >>> 15) >>> 0);
  const _x_3 = (10 >= 32 ? 0 : (_h_0 >>> 10) >>> 0);
  return $tinybendygrad$047dtype$fp16_f32$go$((_x_1 === 31), ((_x_2 & 1) >>> 0), ((_x_3 & 31) >>> 0), ((_h_0 & 1023) >>> 0));
}

function $tinybendygrad$047dtype$fp16_encode$(_s_0, _e_0, _m_0) {
  return $tinybendygrad$047dtype$fp16_encode$of$((_e_0 >= 255), _s_0, _e_0, _m_0);
}

function $tinybendygrad$047dtype$fp8_decode$(_x_0, _kind_0) {
  return $tinybendygrad$047dtype$fp8_decode$pre$(($tinybendygrad$047dtype$fp8_is_fnuz$(_kind_0)), ((_x_0 & 128) >>> 0), _x_0, _kind_0);
}

function $Bool$pick$(_c_0, _a_0, _b_0) {
  if (!_c_0) {
    return _b_0;
  } else {
    return _a_0;
  }
}

function $tinybendygrad$047dtype$bf16$round$(_bits_0) {
  const _x_0 = (16 >= 32 ? 0 : (_bits_0 >>> 16) >>> 0);
  const _x_1 = ((_bits_0 + 32767) >>> 0);
  const _x_2 = ((_x_0 & 1) >>> 0);
  const _x_3 = ((_x_1 + _x_2) >>> 0);
  return ((_x_3 & 4294901760) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$(_cfg_0, _kind_0, _xb_0) {
  const _x_0 = ($tinybendygrad$047dtype$fp8_enc$shr$(_xb_0, 31));
  const _sgn_0 = ($tinybendygrad$047dtype$fp8_enc$shl$(((_x_0 & 1) >>> 0), 7));
  const _exp_0 = ($tinybendygrad$047dtype$fp8_enc$exp$(_cfg_0, _xb_0));
  const _res_0 = ($tinybendygrad$047dtype$fp8_enc$res$(_cfg_0, ($tinybendygrad$047dtype$fp8_enc$absx$(_xb_0)), _exp_0, ($tinybendygrad$047dtype$fp8_enc$mant$(_cfg_0, _xb_0))));
  const _x_1 = ($tinybendygrad$047dtype$fp8_enc$exp_field$(_xb_0));
  return $Bool$pick$((_x_1 === 255), ($tinybendygrad$047dtype$fp8_enc$nonfinite$(_kind_0, _xb_0, _sgn_0)), ($tinybendygrad$047dtype$fp8_enc$put$(_kind_0, _res_0, _sgn_0)));
}

function $tinybendygrad$047dtype$fp8_cfg$(_kind_0) {
  if (_kind_0 == 0) {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 7, "sig": 4, "mant": 7, "denorm": 981467136, "ovf": 1139277824, "max_norm": 126, "min_norm": 1015021568};
  } else if ((_kind_0 & 3) == 0) {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 16, "sig": 3, "mant": 3, "denorm": 914358272, "ovf": 1198522367, "max_norm": 127, "min_norm": 939524096};
  } else if (_kind_0 == 2) {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 8, "sig": 4, "mant": 7, "denorm": 973078528, "ovf": 1131937791, "max_norm": 127, "min_norm": 1006632960};
  } else if ((_kind_0 & 3) == 2) {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 16, "sig": 3, "mant": 3, "denorm": 914358272, "ovf": 1198522367, "max_norm": 127, "min_norm": 939524096};
  } else if (_kind_0 == 1) {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 15, "sig": 3, "mant": 3, "denorm": 922746880, "ovf": 1198522367, "max_norm": 123, "min_norm": 947912704};
  } else {
    return {$: "tinybendygrad/dtype.Fp8", "bias": 16, "sig": 3, "mant": 3, "denorm": 914358272, "ovf": 1198522367, "max_norm": 127, "min_norm": 939524096};
  }
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
  }
}

function $tinybendygrad$047dtype$fp16_f32$go$(_inf_nan_0, _s_0, _e_0, _m_0) {
  if (_inf_nan_0) {
    const _x_0 = (13 >= 32 ? 0 : (_m_0 << 13) >>> 0);
    const _x_1 = (31 >= 32 ? 0 : (_s_0 << 31) >>> 0);
    const _x_2 = ($Bool$pick$((_m_0 !== 0), ((2139095040 | _x_0) >>> 0), 2139095040));
    return ((_x_1 | _x_2) >>> 0);
  } else {
    return $tinybendygrad$047dtype$fp16_f32$e$((_e_0 === 0), _s_0, _e_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp16_encode$of$(_inf_nan_0, _s_0, _e_0, _m_0) {
  if (_inf_nan_0) {
    const _x_0 = (13 >= 32 ? 0 : (_m_0 >>> 13) >>> 0);
    const _x_1 = ((512 | _x_0) >>> 0);
    const _x_2 = ($Bool$pick$((_m_0 !== 0), ((31744 | _x_1) >>> 0), 31744));
    return ((_s_0 | _x_2) >>> 0);
  } else {
    return $tinybendygrad$047dtype$fp16_encode$ovf$((_e_0 >= 143), _s_0, _e_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$pre$(_fnuz_0, _neg_zero_0, _x_0, _kind_0) {
  return $tinybendygrad$047dtype$fp8_decode$nz$(($Bool$and$(_fnuz_0, (_x_0 === 128))), _neg_zero_0, _x_0, _kind_0);
}

function $tinybendygrad$047dtype$fp8_is_fnuz$(_kind_0) {
  return (_kind_0 >= 2);
}

function $tinybendygrad$047dtype$fp8_enc$shl$(_a_0, _n_0) {
  return (_n_0 >= 32 ? 0 : (_a_0 << _n_0) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$shr$(_a_0, _n_0) {
  return (_n_0 >= 32 ? 0 : (_a_0 >>> _n_0) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$exp$(_cfg_0, _xb_0) {
  const _x_0 = ($tinybendygrad$047dtype$fp8_enc$exp_field$(_xb_0));
  const _x_1 = ((_x_0 - 127) >>> 0);
  const _x_2 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 0));
  return ((_x_1 + _x_2) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$res$(_cfg_0, _absx_0, _exp_0, _mant_0) {
  const _x_0 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 3));
  const _x_1 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 4));
  const _x_2 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 6));
  return $Bool$pick$((_absx_0 <= _x_0), 0, ($Bool$pick$((_absx_0 > _x_1), ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 5)), ($Bool$pick$((_absx_0 >= _x_2), ($tinybendygrad$047dtype$fp8_enc$norm$(_cfg_0, _absx_0, _exp_0, _mant_0)), ($tinybendygrad$047dtype$fp8_enc$sub$(_cfg_0, _absx_0, _exp_0, _mant_0)))))));
}

function $tinybendygrad$047dtype$fp8_enc$absx$(_xb_0) {
  return ((_xb_0 & 2147483647) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$mant$(_cfg_0, _xb_0) {
  const _x_0 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 1));
  const _x_1 = ($tinybendygrad$047dtype$fp8_enc$shr$(_xb_0, ((24 - _x_0) >>> 0)));
  const _x_2 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 2));
  return ((_x_1 & _x_2) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$exp_field$(_xb_0) {
  const _x_0 = ($tinybendygrad$047dtype$fp8_enc$shr$(_xb_0, 23));
  return ((_x_0 & 255) >>> 0);
}

function $tinybendygrad$047dtype$fp8_enc$nonfinite$(_kind_0, _xb_0, _sgn_0) {
  const _x_0 = ((_xb_0 & 8388607) >>> 0);
  const _x_1 = ($Bool$pick$((_x_0 === 0), 124, 127));
  return $Bool$pick$(($tinybendygrad$047dtype$fp8_enc$is_fnuz$(_kind_0)), 128, ($Bool$pick$((_kind_0 === 0), ($Bool$pick$((_sgn_0 === 0), 127, 255)), ((_x_1 | _sgn_0) >>> 0))));
}

function $tinybendygrad$047dtype$fp8_enc$put$(_kind_0, _res_0, _sgn_0) {
  return $Bool$pick$(($tinybendygrad$047dtype$fp8_enc$is_fnuz$(_kind_0)), ($Bool$pick$((_res_0 === 0), 0, ((_res_0 | _sgn_0) >>> 0))), ((_res_0 | _sgn_0) >>> 0));
}

function $U32$show$go$($0, $1, $2, $3) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

function $tinybendygrad$047dtype$fp16_f32$e$(_sub_0, _s_0, _e_0, _m_0) {
  if (_sub_0) {
    return $tinybendygrad$047dtype$fp16_f32$sub$((_m_0 === 0), _s_0, _m_0);
  } else {
    const _x_0 = ((_e_0 + 112) >>> 0);
    const _x_1 = (23 >= 32 ? 0 : (_x_0 << 23) >>> 0);
    const _x_2 = (13 >= 32 ? 0 : (_m_0 << 13) >>> 0);
    const _x_3 = (31 >= 32 ? 0 : (_s_0 << 31) >>> 0);
    const _x_4 = ((_x_1 | _x_2) >>> 0);
    return ((_x_3 | _x_4) >>> 0);
  }
}

function $tinybendygrad$047dtype$fp16_encode$ovf$(_ovf_0, _s_0, _e_0, _m_0) {
  if (_ovf_0) {
    return ((_s_0 | 31744) >>> 0);
  } else {
    return $tinybendygrad$047dtype$fp16_encode$small$((_e_0 <= 101), _s_0, _e_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$nz$(_nan_0, _neg_zero_0, _x_0, _kind_0) {
  if (_nan_0) {
    return 2143289344;
  } else {
    return $tinybendygrad$047dtype$fp8_decode$finite$(_neg_zero_0, _x_0, _kind_0);
  }
}

function $Bool$and$(_a_0, _b_0) {
  if (!_a_0) {
    return false;
  } else {
    return _b_0;
  }
}

function $tinybendygrad$047dtype$Fp8$at$(_cfg_0, _i_0) {
  const _bias_0 = _cfg_0["bias"];
  const _sig_0 = _cfg_0["sig"];
  const _mant_0 = _cfg_0["mant"];
  const _denorm_0 = _cfg_0["denorm"];
  const _ovf_0 = _cfg_0["ovf"];
  const _max_norm_0 = _cfg_0["max_norm"];
  const _min_norm_0 = _cfg_0["min_norm"];
  if (_i_0 == 0) {
    return _bias_0;
  } else if ((_i_0 & 7) == 0) {
    return _min_norm_0;
  } else if (_i_0 == 4) {
    return _ovf_0;
  } else if ((_i_0 & 7) == 4) {
    return _min_norm_0;
  } else if (_i_0 == 2) {
    return _mant_0;
  } else if ((_i_0 & 3) == 2) {
    return _min_norm_0;
  } else if (_i_0 == 1) {
    return _sig_0;
  } else if ((_i_0 & 7) == 1) {
    return _min_norm_0;
  } else if (_i_0 == 5) {
    return _max_norm_0;
  } else if ((_i_0 & 7) == 5) {
    return _min_norm_0;
  } else if (_i_0 == 3) {
    return _denorm_0;
  } else {
    return _min_norm_0;
  }
}

function $tinybendygrad$047dtype$fp8_enc$norm$(_cfg_0, _xb_0, _exp_0, _mant_0) {
  const _hu_0 = ($tinybendygrad$047dtype$fp8_enc$hu$(_cfg_0));
  const _x_0 = ($tinybendygrad$047dtype$fp8_enc$shl$(_hu_0, 1));
  const _x_1 = ((_x_0 - 1) >>> 0);
  const _x_2 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 1));
  const _x_3 = ($tinybendygrad$047dtype$fp8_enc$shl$(_exp_0, ((_x_2 - 1) >>> 0)));
  return $tinybendygrad$047dtype$fp8_enc$round$(((_xb_0 & _x_1) >>> 0), _hu_0, ((_x_3 | _mant_0) >>> 0));
}

function $tinybendygrad$047dtype$fp8_enc$sub$(_cfg_0, _xb_0, _exp_0, _mant_0) {
  const _sh_0 = ($tinybendygrad$047dtype$fp8_enc$sh$(_exp_0));
  const _half_0 = ($tinybendygrad$047dtype$fp8_enc$shl$(($tinybendygrad$047dtype$fp8_enc$hu$(_cfg_0)), _sh_0));
  const _x_0 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 1));
  const _x_1 = ($tinybendygrad$047dtype$fp8_enc$shl$(1, ((_x_0 - 1) >>> 0)));
  const _res_0 = ($tinybendygrad$047dtype$fp8_enc$shr$(((_mant_0 | _x_1) >>> 0), _sh_0));
  const _x_2 = ($tinybendygrad$047dtype$fp8_enc$shl$(_half_0, 1));
  const _x_3 = ((_xb_0 | 8388608) >>> 0);
  const _x_4 = ((_x_2 - 1) >>> 0);
  return $tinybendygrad$047dtype$fp8_enc$round$(((_x_3 & _x_4) >>> 0), _half_0, _res_0);
}

function $tinybendygrad$047dtype$fp8_enc$is_fnuz$(_kind_0) {
  return (_kind_0 >= 2);
}

function $U32$show$fin$($0, $1, $2, $3) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

function $tinybendygrad$047dtype$fp16_f32$sub$(_z_0, _s_0, _m_0) {
  if (_z_0) {
    return (31 >= 32 ? 0 : (_s_0 << 31) >>> 0);
  } else {
    return $tinybendygrad$047dtype$fp16_f32$norm$(_s_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp16_encode$small$(_sub_0, _s_0, _e_0, _m_0) {
  if (_sub_0) {
    return _s_0;
  } else {
    return $tinybendygrad$047dtype$fp16_encode$arm$((_e_0 <= 112), _s_0, _e_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$finite$(_neg_zero_0, _x_0, _kind_0) {
  const _x_1 = ((_x_0 & 127) >>> 0);
  return $tinybendygrad$047dtype$fp8_decode$zero$((_x_1 === 0), _neg_zero_0, _x_0, _kind_0);
}

function $tinybendygrad$047dtype$fp8_enc$hu$(_cfg_0) {
  const _x_0 = ($tinybendygrad$047dtype$Fp8$at$(_cfg_0, 1));
  return $tinybendygrad$047dtype$fp8_enc$shl$(1, ((23 - _x_0) >>> 0));
}

function $tinybendygrad$047dtype$fp8_enc$round$(_rb_0, _tie_0, _res_0) {
  const _x_0 = ((_res_0 & 1) >>> 0);
  const _x_1 = ($Bool$to_u32$((_x_0 === 1)));
  return $Bool$pick$((_rb_0 > _tie_0), ((_res_0 + 1) >>> 0), ($Bool$pick$((_rb_0 === _tie_0), ((_res_0 + _x_1) >>> 0), _res_0)));
}

function $tinybendygrad$047dtype$fp8_enc$sh$(_exp_0) {
  if (_exp_0 == 4294967293) {
    return 4;
  } else if ((_exp_0 & 3) == 1) {
    return 1;
  } else if (_exp_0 == 4294967295) {
    return 2;
  } else if ((_exp_0 & 3) == 3) {
    return 1;
  } else if (_exp_0 == 4294967294) {
    return 3;
  } else {
    return 1;
  }
}

function $tinybendygrad$047dtype$fp16_f32$norm$(_s_0, _m_0) {
  const _x_0 = ($U32$log2$(_m_0));
  const _x_1 = (_x_0 >>> 0);
  const _x_2 = ((31 - _x_1) >>> 0);
  const _x_3 = ((_x_2 + 103) >>> 0);
  const _x_4 = ($U32$log2$(_m_0));
  const _x_5 = (_x_4 >>> 0);
  const _x_6 = ((23 - _x_5) >>> 0);
  const _x_7 = (_x_6 >= 32 ? 0 : (_m_0 << _x_6) >>> 0);
  const _x_8 = (23 >= 32 ? 0 : (_x_3 << 23) >>> 0);
  const _x_9 = ((_x_7 & 8388607) >>> 0);
  const _x_10 = (31 >= 32 ? 0 : (_s_0 << 31) >>> 0);
  const _x_11 = ((_x_8 | _x_9) >>> 0);
  return ((_x_10 | _x_11) >>> 0);
}

function $tinybendygrad$047dtype$fp16_encode$arm$(_sub_0, _s_0, _e_0, _m_0) {
  if (_sub_0) {
    return $tinybendygrad$047dtype$fp16_encode$sub$(_s_0, _e_0, _m_0);
  } else {
    return $tinybendygrad$047dtype$fp16_encode$norm$(_s_0, _e_0, _m_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$zero$(_z_0, _neg_zero_0, _x_0, _kind_0) {
  if (_z_0) {
    return (24 >= 32 ? 0 : (_neg_zero_0 << 24) >>> 0);
  } else {
    return $tinybendygrad$047dtype$fp8_decode$exp_max$(($tinybendygrad$047dtype$fp8_is_fnuz$(_kind_0)), _x_0, _kind_0);
  }
}

function $Bool$to_u32$(_b_0) {
  if (!_b_0) {
    return 0;
  } else {
    return 1;
  }
}

function $U32$log2$(_n_0) {
  return $U32$log2$go$(5, _n_0, 0);
}

function $tinybendygrad$047dtype$fp16_encode$sub$(_s_0, _e_0, _m_0) {
  const _big_0 = ((_m_0 | 8388608) >>> 0);
  const _x_0 = ((126 - _e_0) >>> 0);
  const _sh_0 = _x_0;
  const _x_1 = (_sh_0 >= 32 ? 0 : (1 << _sh_0) >>> 0);
  const _x_2 = ((_x_1 - 1) >>> 0);
  const _x_3 = (_sh_0 >= 32 ? 0 : (1 << _sh_0) >>> 0);
  const _x_4 = ($tinybendygrad$047dtype$fp16_encode$round$((_sh_0 >= 32 ? 0 : (_big_0 >>> _sh_0) >>> 0), ((_big_0 & _x_2) >>> 0), (1 >= 32 ? 0 : (_x_3 >>> 1) >>> 0)));
  return ((_s_0 | _x_4) >>> 0);
}

function $tinybendygrad$047dtype$fp16_encode$norm$(_s_0, _e_0, _m_0) {
  const _x_0 = ((_e_0 - 112) >>> 0);
  const _x_1 = (10 >= 32 ? 0 : (_x_0 << 10) >>> 0);
  const _x_2 = (13 >= 32 ? 0 : (_m_0 >>> 13) >>> 0);
  const _x_3 = ($tinybendygrad$047dtype$fp16_encode$round$(((_x_1 + _x_2) >>> 0), ((_m_0 & 8191) >>> 0), 4096));
  return ((_s_0 | _x_3) >>> 0);
}

function $tinybendygrad$047dtype$fp8_decode$exp_max$(_fnuz_0, _x_0, _kind_0) {
  const _sig_0 = ($tinybendygrad$047dtype$fp8_sig$(_kind_0));
  const _x_1 = ((_sig_0 - 1) >>> 0);
  const _x_2 = (_x_1 >= 32 ? 0 : (_x_0 >>> _x_1) >>> 0);
  const _x_3 = ($tinybendygrad$047dtype$fp8_exp_max$(_kind_0));
  const _exp_0 = ((_x_2 & _x_3) >>> 0);
  const _x_4 = ($tinybendygrad$047dtype$fp8_exp_max$(_kind_0));
  const _x_5 = ((_x_0 & 128) >>> 0);
  const _x_6 = ($tinybendygrad$047dtype$fp8_mant_max$(_kind_0));
  return $tinybendygrad$047dtype$fp8_decode$sat$((_kind_0 === 1), ($Bool$and$(($Bool$not$(_fnuz_0)), (_exp_0 === _x_4))), (7 >= 32 ? 0 : (_x_5 >>> 7) >>> 0), _exp_0, ((_x_0 & _x_6) >>> 0), ($tinybendygrad$047dtype$fp8_bias$(_kind_0)), _sig_0, ($tinybendygrad$047dtype$fp8_mant_max$(_kind_0)));
}

function $U32$log2$go$($0, $1, $2) {
  for (;;) {
    {
      const _k_0 = $0;
      const _n_0 = $1;
      const _b_0 = $2;
      if (_k_0 === 0) {
        return _b_0;
      } else {
        const _p_0 = (_k_0 - 1);
        const _x_0 = (_p_0 >= 32 ? 0 : (1 << _p_0) >>> 0);
        const _s_0 = _x_0;
        const _x_1 = (_s_0 >= 32 ? 0 : (_n_0 >>> _s_0) >>> 0);
        const _x_2 = ($Bool$to_u32$((_x_1 !== 0)));
        const _t_0 = nat_chk(_s_0 * _x_2);
        $0 = _p_0;
        $1 = (_t_0 >= 32 ? 0 : (_n_0 >>> _t_0) >>> 0);
        $2 = nat_chk(_b_0 + _t_0);
        continue;
      }
    }
  }
}

function $tinybendygrad$047dtype$fp16_encode$round$(_half_0, _rem_0, _halfway_0) {
  const _x_0 = ((_half_0 & 1) >>> 0);
  const _x_1 = (_rem_0 > _halfway_0);
  const _x_2 = ($Bool$and$((_rem_0 === _halfway_0), (_x_0 !== 0)));
  return $Bool$pick$((_x_1 || _x_2), ((_half_0 + 1) >>> 0), _half_0);
}

function $tinybendygrad$047dtype$fp8_sig$(_kind_0) {
  return $tinybendygrad$047dtype$fp8_pick$(_kind_0, 4, 3, 4, 3);
}

function $tinybendygrad$047dtype$fp8_exp_max$(_kind_0) {
  const _x_0 = ($tinybendygrad$047dtype$fp8_sig$(_kind_0));
  const _x_1 = ((8 - _x_0) >>> 0);
  const _x_2 = (_x_1 >= 32 ? 0 : (1 << _x_1) >>> 0);
  return ((_x_2 - 1) >>> 0);
}

function $tinybendygrad$047dtype$fp8_decode$sat$(_e5m2_0, _sat_0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0, _mant_max_0) {
  return $tinybendygrad$047dtype$fp8_decode$sat2$(_sat_0, _e5m2_0, (_mant_0 !== 0), (_mant_0 === _mant_max_0), _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
}

function $Bool$not$(_b_0) {
  if (!_b_0) {
    return true;
  } else {
    return false;
  }
}

function $tinybendygrad$047dtype$fp8_mant_max$(_kind_0) {
  const _x_0 = ($tinybendygrad$047dtype$fp8_sig$(_kind_0));
  const _x_1 = ((_x_0 - 1) >>> 0);
  const _x_2 = (_x_1 >= 32 ? 0 : (1 << _x_1) >>> 0);
  return ((_x_2 - 1) >>> 0);
}

function $tinybendygrad$047dtype$fp8_bias$(_kind_0) {
  return $tinybendygrad$047dtype$fp8_pick$(_kind_0, 7, 15, 8, 16);
}

function $tinybendygrad$047dtype$fp8_pick$(_kind_0, _k0_0, _k1_0, _k2_0, _k3_0) {
  if (_kind_0 == 0) {
    return _k0_0;
  } else if ((_kind_0 & 3) == 0) {
    return _k3_0;
  } else if (_kind_0 == 2) {
    return _k2_0;
  } else if ((_kind_0 & 3) == 2) {
    return _k3_0;
  } else if (_kind_0 == 1) {
    return _k1_0;
  } else {
    return _k3_0;
  }
}

function $tinybendygrad$047dtype$fp8_decode$sat2$(_sat_0, _e5m2_0, _mant_nz_0, _mant_all_0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  if (_sat_0) {
    return $tinybendygrad$047dtype$fp8_decode$sat3$(_e5m2_0, _mant_nz_0, _mant_all_0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
  } else {
    return $tinybendygrad$047dtype$fp8_decode$value$((_exp_0 === 0), _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$sat3$(_e5m2_0, _mant_nz_0, _mant_all_0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  return $tinybendygrad$047dtype$fp8_decode$sat4$(_e5m2_0, ($Bool$pick$(_e5m2_0, _mant_nz_0, _mant_all_0)), ($Bool$and$(_e5m2_0, ($Bool$not$(_mant_nz_0)))), _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
}

function $tinybendygrad$047dtype$fp8_decode$value$(_sub_0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  if (_sub_0) {
    return $tinybendygrad$047dtype$fp8_decode$sub_pat$(_sgn_0, _mant_0, _bias_0, _sig_0);
  } else {
    return $tinybendygrad$047dtype$fp8_decode$norm_pat$(_sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$sat4$(_e5m2_0, _nan_0, _inf__0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  return $tinybendygrad$047dtype$fp8_decode$sat5$((_nan_0 || _inf__0), _e5m2_0, _nan_0, _inf__0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
}

function $tinybendygrad$047dtype$fp8_decode$sub_pat$(_sgn_0, _mant_0, _bias_0, _sig_0) {
  const _x_0 = ($U32$log2$(_mant_0));
  const _k_0 = (_x_0 >>> 0);
  const _x_1 = ((129 - _bias_0) >>> 0);
  const _x_2 = ((_x_1 - _sig_0) >>> 0);
  const _x_3 = ((_x_2 + _k_0) >>> 0);
  const _x_4 = ((23 - _k_0) >>> 0);
  const _x_5 = (_x_4 >= 32 ? 0 : (_mant_0 << _x_4) >>> 0);
  const _x_6 = (23 >= 32 ? 0 : (_x_3 << 23) >>> 0);
  const _x_7 = ((_x_5 & 8388607) >>> 0);
  const _x_8 = (31 >= 32 ? 0 : (_sgn_0 << 31) >>> 0);
  const _x_9 = ((_x_6 | _x_7) >>> 0);
  return ((_x_8 | _x_9) >>> 0);
}

function $tinybendygrad$047dtype$fp8_decode$norm_pat$(_sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  const _x_0 = ((_exp_0 + 127) >>> 0);
  const _x_1 = ((_x_0 - _bias_0) >>> 0);
  const _x_2 = ((_x_1 + 0) >>> 0);
  const _x_3 = ((24 - _sig_0) >>> 0);
  const _x_4 = (23 >= 32 ? 0 : (_x_2 << 23) >>> 0);
  const _x_5 = (_x_3 >= 32 ? 0 : (_mant_0 << _x_3) >>> 0);
  const _x_6 = (31 >= 32 ? 0 : (_sgn_0 << 31) >>> 0);
  const _x_7 = ((_x_4 | _x_5) >>> 0);
  return ((_x_6 | _x_7) >>> 0);
}

function $tinybendygrad$047dtype$fp8_decode$sat5$(_any__0, _e5m2_0, _nan_0, _inf__0, _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0) {
  if (_any__0) {
    return $tinybendygrad$047dtype$fp8_decode$inf_nan$(_e5m2_0, _nan_0, _inf__0, _sgn_0);
  } else {
    return $tinybendygrad$047dtype$fp8_decode$value$((_exp_0 === 0), _sgn_0, _exp_0, _mant_0, _bias_0, _sig_0);
  }
}

function $tinybendygrad$047dtype$fp8_decode$inf_nan$(_e5m2_0, _nan_0, _inf__0, _sgn_0) {
  return $Bool$pick$(_nan_0, ($Bool$pick$(($Bool$and$(_e5m2_0, (_sgn_0 === 1))), 4290772992, 2143289344)), ($Bool$pick$(_inf__0, ($Bool$pick$((_sgn_0 === 1), 4286578688, 2139095040)), 0)));
}

// Cli
// ===

let cli_args = [];

function cli(argv) {
  cli_args.push(argv[0]);
  for (let i = 1; i < argv.length; i += 1) {
    if (argv[i] === "--") {
      cli_args.push(...argv.slice(i + 1));
      break;
    } else if (argv[i] === "--bend-help") {
      io_out(1, io_bytes("usage: " + argv[0] + "\n"));
      process.exit(0);
    } else if (argv[i] === "--threads" || argv[i] === "--gpu") {
      i += 1;
    } else {
      cli_args.push(argv[i]);
    }
  }
}

// Show
// ====

// show_val prints a pure main's value as term_show does (see show_main);
// chain is the bracket it continues, or 0. show_chr escapes as char_show.

function show_chr(c, q) {
  const k = { 10: "n", 9: "t", 13: "r", 0: "0", 92: "\\" }[c]
    ?? (c === q.codePointAt(0) ? q : null);
  return k !== null ? "\\" + k : c < 32 || c === 127
    || (c >= 0xD800 && c <= 0xDFFF) || c > 0x10FFFF
    ? "\\u{" + c.toString(16) + "}" : String.fromCodePoint(c);
}

function show_val(D, N, d, v, chain) {
  if (D[d] === 7) {
    const fs = Object.values(typeof v === "boolean"
      ? { $: v ? "True" : "False" } : v);
    let a = d + 3;
    for (; N[D[a]] !== fs[0]; a += 4 + 2 * D[a + 2]) {}
    const o = "{[("[D[a + 3]];
    let s = o === "{" ? fs[0] + "{" : chain === o ? "" : o;
    for (const [j, f] of fs.slice(1).entries()) {
      if (o === "[" ? j === 0 && chain === o : j > 0) {
        s += ", ";
      }
      s += show_val(D, N, D[a + 5 + 2 * j], f, j === 1 && o !== "{" ? o : 0);
    }
    return o === "{" || chain !== o ? s + "}])"[D[a + 3]] : s;
  }
  return D[d] === 0 ? String(v)
    : D[d] === 1 ? f32_show(v).replace(/^-?\d+(?=e|$)/, "$&.0")
    : D[d] === 2 ? v + "n"
    : D[d] === 3 ? "'" + show_chr(v.codePointAt(0), "'") + "'"
    : D[d] === 4 ? "\"" + [...v].map((c) =>
      show_chr(c.codePointAt(0), "\"")).join("") + "\""
    : D[d] === 5 ? "{==}"
    : "[" + v.map((x) => show_val(D, N, D[d + 1], x, 0)).join(", ") + "]";
}

// Io
// ==

// Apple arm64 passes variadic fcntl flags on the stack, so io_sys
// binds fcntl there with the flags as the ninth fixed argument. A
// parked effect waits for fd (a write when out) or until at
// (performance.now()), either one undefined when unused; io_wake
// resumes k with the value of more, and undefined parks it again. The
// waits stay in deadline order, as io_park does in C.

function io_exit(main, show) {
  try {
    if (show !== null) {
      io_out(1, io_bytes(show_val(...show, 0, run_loop(main()), 0) + "\n"));
      process.exit(0);
    }
    process.exit(io_run(main));
  } catch (e) {
    io_errs(String(e));
    process.exit(1);
  }
}

function io_out(fd, data) {
  const fs = require("fs");
  let at = 0;
  while (at < data.length) {
    try {
      at += fs.writeSync(fd, data, at, data.length - at);
    } catch (e) {
      if (e.code === "EAGAIN" || e.code === "EINTR") {
        continue;
      }
      try {
        fs.writeSync(2, "bend: a short write on a standard stream\n");
      } catch (o) {
      }
      process.exit(1);
    }
  }
}

function io_errs(message) {
  io_out(2, io_bytes(message + "\n"));
}

function io_sys() {
  if (globalThis.BEND_SYS === undefined) {
    const ffi = require("bun:ffi");
    const mac = process.platform === "darwin";
    const err = mac ? "__error" : "__errno_location";
    const sel = mac ? "select$DARWIN_EXTSN" : "select";
    const T = { i: "i32", u: "u32", U: "u64", I: "i64", p: "ptr",
      c: "cstring" };
    const vari = mac && process.arch === "arm64";
    const lib = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6",
      Object.fromEntries(("socket:iii>i bind:ipu>i listen:ii>i connect:ipu>i"
        + " accept:ipp>i send:ipUi>I recv:ipUi>I read:ipU>I pread:ipUI>I"
        + " sendto:ipUipu>I recvfrom:ipUipp>I close:i>i setsockopt:iiipu>i"
        + " " + sel + ":ipppp>i"
        + (vari ? " fcntl:iiiiiiiii>i" : " fcntl:iii>i") + " getsockopt:iiipp>i"
        + " strerror:i>c " + err + ":>p").split(" ").map((s) => {
        const [name, args, ret] = s.split(/[:>]/);
        return [name, { args: [...args].map((a) => T[a]), returns: T[ret] }];
      }))).symbols;
    const fcntl = (fd, cmd, arg) => vari
      ? lib.fcntl(fd, cmd, 0, 0, 0, 0, 0, 0, arg)
      : lib.fcntl(fd, cmd, arg);
    globalThis.BEND_SYS = { ...lib, fcntl, select: lib[sel],
      ptr: ffi.ptr, mac,
      errno: () => ffi.read.i32(lib[err](), 0) };
  }
  return globalThis.BEND_SYS;
}

function io_fail(code) {
  return { $: "Fail",
    error: io_tup(code >>> 0, String(io_sys().strerror(code))) };
}

function io_done(value) {
  return { $: "Done", value };
}

function io_tup(...xs) {
  return xs.reduceRight((snd, fst) => ({ $: "Tuple", fst, snd }));
}

function io_bytes(text) {
  return new TextEncoder().encode(text);
}

function io_text(b, n) {
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(b.subarray(0, n));
}

// Bytes cross as they are (0..255), one List cell each, with no UTF-8 in
// either direction; io_unlist answers null if a value is past 255.
function io_list(b, n) {
  let xs = { $: "Nil" };
  while (n > 0) {
    xs = { $: "Con", head: b[--n], tail: xs };
  }
  return xs;
}

function io_unlist(xs) {
  const b = [];
  for (; xs.$ === "Con"; xs = xs.tail) {
    b.push(xs.head);
  }
  return b.some((x) => x > 255) ? null : Uint8Array.from(b);
}

function io_addr(host, port) {
  const part = host.split(".");
  const deci = (p) => /^(0|[1-9]\d{0,2})$/.test(p) && Number(p) < 256;
  if (port > 65535 || part.length !== 4 || !part.every(deci)) {
    return null;
  }
  const b = new Uint8Array(16);
  const head = io_sys().mac ? [16, 2] : [2, 0];
  b.set([...head, port >> 8, port & 255, ...part.map(Number)]);
  return b;
}

function io_push(fun, arg, fresh) {
  const io = globalThis.BEND_IO;
  io.runs.push({ fun, arg });
  io.live += fresh ? 1 : 0;
}

function io_wait(io) {
  const soon = io.waits[0]?.at ?? Infinity;
  const ms = soon === Infinity ? -1
    : Math.max(0, Math.ceil(soon - performance.now()));
  const fds = io.waits.filter((w) => w.fd !== undefined);
  const top = fds.reduce((m, w) => Math.max(m, w.fd), 0);
  const len = (top >> 6 << 3) + 8;
  const set = new Uint8Array(2 * len);
  const at = (w) => (w.out ? len : 0) + (w.fd >> 3);
  for (const w of fds) {
    set[at(w)] |= 1 << (w.fd & 7);
  }
  const tv = new BigInt64Array([BigInt(ms / 1000 | 0),
    BigInt(ms % 1000 * 1000)]);
  const sys = io_sys();
  if (sys.select(top + 1, sys.ptr(set), sys.ptr(set, len), null,
    ms < 0 ? null : sys.ptr(tv)) < 0) {
    if (sys.errno() !== 4) {
      throw "bend: the poller failed";
    }
    set.fill(0);
  }
  const now = performance.now();
  io.waits = io.waits.filter((w) => {
    const ready = w.at <= now || w.fd !== undefined
      && set[at(w)] & 1 << (w.fd & 7);
    if (ready) {
      io_push(io_wake, w, false);
    }
    return !ready;
  });
}

function io_wake(w) {
  const x = w.more();
  return x === undefined ? undefined : w.k(x);
}

function io_park_on(fd, out, k, more, at) {
  const ws = globalThis.BEND_IO.waits;
  const i = ws.findLastIndex((w) => (w.at ?? Infinity) <= (at ?? Infinity));
  ws.splice(i + 1, 0, { fd, out, k, more, at });
}

function io_run(m) {
  const io = { runs: [], live: 0, waits: [] };
  globalThis.BEND_IO = io;
  try {
    io_push(run_loop(m()), (x) => ({ $: "Emit", value: x }), true);
    for (;;) {
      if (io.runs.length === 0) {
        if (io.live === 0) {
          return 0;
        }
        if (io.waits.length === 0) {
          io_errs("bend: deadlock: every computation waits on a channel");
          return 1;
        }
        io_wait(io);
        continue;
      }
      const s = io.runs.shift();
      let op = s.fun(s.arg);
      while (op !== undefined) {
        if (op.$ === "Emit") {
          io.live -= 1;
          break;
        }
        if (op.$ === "Halt") {
          io_errs(op.message);
          return op.code;
        }
        const need = op.need?.() ?? {};
        if (need.time || need.read) {
          const more = () => op.run(...op.args, op.kont);
          io_park_on(need.read ? op.args[0] : undefined, false, op.kont, more,
            need.read ? undefined : performance.now() + Number(op.args[0]));
          break;
        }
        const x = op.run(...op.args, op.kont);
        if (x === undefined) {
          break;
        }
        op = op.kont(x);
      }
    }
  } catch (req) {
    if (req instanceof RangeError) {
      throw "bend: memory fault (machine stack overflow?)";
    }
    if (req?.$ !== "$FFI") {
      throw req;
    }
    io_errs("bend: runtime fail-stop");
    return 1;
  }
}

cli(process.argv.slice(1));
io_exit($main$, null);