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

function io_get_env(name) {
  const value = Object.hasOwn(process.env, name) ? process.env[name] : undefined;
  return value === undefined ? io_fail(2) : io_done(value);
}

io_eff("IO.get_env", io_get_env);

})();

(() => {
// IO
// ==

function io_print(text) {
  io_out(1, io_bytes(text + "\n"));
  return { $: "Unit" };
}

io_eff("IO.print", io_print);

})();

(() => {
// File
// ====

function file_close(file) {
  const fs = require("fs");
  try {
    fs.closeSync(file);
  } catch (e) {
  }
  return { $: "Unit" };
}

io_eff("File.close", file_close);

})();

(() => {
// File
// ====

function file_read_with(file, max, offset, pack) {
  const sys = io_sys();
  const len = Math.min(max, 2147483647);
  const b = new Uint8Array(Math.max(len, 1));
  const n = Number(offset === null ? sys.read(file, sys.ptr(b), len)
    : sys.pread(file, sys.ptr(b), len, BigInt(offset)));
  return io_tup(file, n < 0 ? io_fail(sys.errno()) : io_done(pack(b, n)));
}

function file_read(file, max) {
  return file_read_with(file, max, null, io_text);
}

function file_read_bytes(file, max) {
  return file_read_with(file, max, null, io_list);
}

function file_read_at(file, offset, max) {
  return file_read_with(file, max, offset, io_list);
}

io_eff("File.read", file_read);
io_eff("File.read_bytes", file_read_bytes);
io_eff("File.read_at", file_read_at);

})();

(() => {
// File
// ====

function file_open(path, mode) {
  const name = io_bytes(path);
  if (name.includes(0)) {
    return io_fail(process.platform === "darwin" ? 92 : 84);
  }
  if (!["r", "w", "a"].includes(mode)) {
    return io_fail(22);
  }
  try {
    const fd = require("fs")
      .openSync(name.length > 0 ? Buffer.from(name) : "", mode, 0o644);
    return io_done(fd);
  } catch (e) {
    return io_fail(-e.errno);
  }
}

io_eff("File.open", file_open);

})();

for (const k of ["IO.get_env","IO.print","File.close","File.read","File.open"]) {
  if (!(k in $0eff)) {
    throw new Error("bend: no effect registers " + k);
  }
}

// Program
// =======

function $$$$047helpers$Flags$defaults$() {
  return {$: "../helpers.Flags", "no_color": false, "default_float": "float32", "default_int": "int32", "sum_dtype": "float32"};
}

function $$$$047helpers$nc_sign$(_s_0) {
  const _x_0 = ($String$starts_with$(_s_0, "+"));
  const _x_1 = ($String$starts_with$(_s_0, "-"));
  return (_x_0 || _x_1);
}

function $$$$047helpers$nc_body$(_sgn_0, _s_0) {
  if (_sgn_0) {
    return $String$to_list$(($String$drop$(_s_0, 1)));
  } else {
    return $String$to_list$(_s_0);
  }
}

function $$$$047helpers$nc_digits$(_s_0) {
  return $$$$047helpers$nc_body$(($$$$047helpers$nc_sign$(_s_0)), ($String$trim$(_s_0)));
}

function $$$$047helpers$nc_in$(_h_0) {
  const _x_0 = ($Char$to_u32$(_h_0));
  const _x_1 = ($Char$is_digit$(_h_0));
  const _x_2 = (_x_0 === 95);
  return (_x_1 || _x_2);
}

function $$$$047helpers$nc_ok$(_n_0) {
  const _ok_0 = _n_0["ok"];
  return _ok_0;
}

function $$$$047helpers$nc_nz$(_n_0) {
  const _nz_0 = _n_0["nz"];
  return _nz_0;
}

function $$$$047helpers$nc_step$(_ok_0, _isdig_0, _inclass_0, _nz_0, _h_0) {
  if (_isdig_0) {
    const _x_0 = ($Char$to_u32$(_h_0));
    const _x_1 = (_x_0 !== 48);
    return {$: "../helpers.Nc", "ok": _ok_0, "nz": (_nz_0 || _x_1)};
  } else {
    if (_inclass_0) {
      return {$: "../helpers.Nc", "ok": _ok_0, "nz": _nz_0};
    } else {
      return {$: "../helpers.Nc", "ok": false, "nz": _nz_0};
    }
  }
}

function $$$$047helpers$nc_walk$($0, $1) {
  for (;;) {
    {
      const _cs_0 = $0;
      const _n_0 = $1;
      if (_cs_0.$ === "Nil") {
        return _n_0;
      } else {
        const _h_0 = _cs_0["head"];
        const _t_0 = _cs_0["tail"];
        $0 = _t_0;
        $1 = ($$$$047helpers$nc_step$(($$$$047helpers$nc_ok$(_n_0)), ($Char$is_digit$(_h_0)), ($$$$047helpers$nc_in$(_h_0)), ($$$$047helpers$nc_nz$(_n_0)), _h_0));
        continue;
      }
    }
  }
}

function $$$$047helpers$no_color_of$go$(_n_0) {
  return $Bool$and$(($$$$047helpers$nc_ok$(_n_0)), ($$$$047helpers$nc_nz$(_n_0)));
}

function $$$$047helpers$no_color_of$(_v_0) {
  return $$$$047helpers$no_color_of$go$(($$$$047helpers$nc_walk$(($$$$047helpers$nc_digits$(_v_0)), {$: "../helpers.Nc", "ok": true, "nz": false})));
}

function $$$$047helpers$getenv_str$go$(_v_0, _d_0) {
  if (_v_0.$ === "Done") {
    const _value_0 = _v_0["value"];
    return _value_0;
  } else {
    return _d_0;
  }
}

function $$$$047helpers$getenv_str$(_k_0, _d_0) {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $IO$get_env$(_k_0, _x_1), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$pure$(($$$$047helpers$getenv_str$go$(_x_2, _d_0)), _x_3);
});
}), _x_0);
});
}

function $$$$047helpers$Flags$of$(_nc_0, _df_0, _di_0, _sd_0) {
  return {$: "../helpers.Flags", "no_color": ($$$$047helpers$no_color_of$(_nc_0)), "default_float": _df_0, "default_int": _di_0, "sum_dtype": _sd_0};
}

function $$$$047helpers$prod_u32$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 1;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($$$$047helpers$prod_u32$(_t_0));
    return (Math.imul(_h_0, _x_0) >>> 0);
  }
}

function $$$$047helpers$prod_nat$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 1;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($$$$047helpers$prod_nat$(_t_0));
    return nat_chk(_h_0 * _x_0);
  }
}

function $$$$047helpers$dedup_u32$put$(_seen_0, _h_0, _r_0) {
  if (_seen_0) {
    return _r_0;
  } else {
    return {$: "Con", "head": _h_0, "tail": _r_0};
  }
}

function $$$$047helpers$dedup_u32$go$(_x_0, _r_0) {
  return $$$$047helpers$dedup_u32$put$(($List$contains$1260$(_r_0, _x_0)), _x_0, _r_0);
}

function $$$$047helpers$dedup_u32$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $$$$047helpers$dedup_u32$go$(_h_0, ($$$$047helpers$dedup_u32$(_t_0)));
  }
}

function $$$$047helpers$dedup_str$put$(_seen_0, _h_0, _r_0) {
  if (_seen_0) {
    return _r_0;
  } else {
    return {$: "Con", "head": _h_0, "tail": _r_0};
  }
}

function $$$$047helpers$dedup_str$go$(_x_0, _r_0) {
  return $$$$047helpers$dedup_str$put$(($List$contains$1261$(_r_0, _x_0)), _x_0, _r_0);
}

function $$$$047helpers$dedup_str$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $$$$047helpers$dedup_str$go$(_h_0, ($$$$047helpers$dedup_str$(_t_0)));
  }
}

function $$$$047helpers$argfix_bad$(_sequence_with_others_0) {
  if (_sequence_with_others_0) {
    return {$: "Some", "value": 0};
  } else {
    return {$: "None"};
  }
}

function $$$$047helpers$argfix1$(_a_0) {
  return {$: "Con", "head": _a_0, "tail": {$: "Nil"}};
}

function $$$$047helpers$argfix2$(_a_0, _b_0) {
  return {$: "Con", "head": _a_0, "tail": {$: "Con", "head": _b_0, "tail": {$: "Nil"}}};
}

function $$$$047helpers$argfix_seq$(_xs_0) {
  return _xs_0;
}

function $$$$047helpers$ix_le$tie$(_same_0, _i_0, _j_0) {
  if (_same_0) {
    return (_i_0 <= _j_0);
  } else {
    return true;
  }
}

function $$$$047helpers$ix_le$cmp$(_le_0, _v_0, _w_0, _i_0, _j_0) {
  if (_le_0) {
    return $$$$047helpers$ix_le$tie$((_v_0 === _w_0), _i_0, _j_0);
  } else {
    return false;
  }
}

function $$$$047helpers$ix_le$(_a_0, _b_0) {
  const _i_0 = _a_0["i"];
  const _v_0 = _a_0["v"];
  const _j_0 = _b_0["i"];
  const _w_0 = _b_0["v"];
  return $$$$047helpers$ix_le$cmp$((_v_0 <= _w_0), _v_0, _w_0, _i_0, _j_0);
}

function $$$$047helpers$ix_of$go$(_xs_0, _i_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": {$: "../helpers.Ix", "i": _i_0, "v": _h_0}, "tail": ($$$$047helpers$ix_of$go$(_t_0, ((_i_0 + 1) >>> 0)))};
  }
}

function $$$$047helpers$ix_of$(_xs_0) {
  return $$$$047helpers$ix_of$go$(_xs_0, 0);
}

function $$$$047helpers$ix_index$(_i_0) {
  const _k_0 = _i_0["i"];
  return _k_0;
}

function $$$$047helpers$ix_map$(_l_0) {
  if (_l_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _i_0 = _l_0["head"];
    const _t_0 = _l_0["tail"];
    return {$: "Con", "head": ($$$$047helpers$ix_index$(_i_0)), "tail": ($$$$047helpers$ix_map$(_t_0))};
  }
}

function $$$$047helpers$argsort_u32$(_xs_0) {
  return $$$$047helpers$ix_map$(($List$sort$1260$(($$$$047helpers$ix_of$(_xs_0)))));
}

function $$$$047helpers$all_same_u32$go$(_xs_0, _head_0) {
  if (_xs_0.$ === "Nil") {
    return true;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $Bool$and$((_h_0 === _head_0), ($$$$047helpers$all_same_u32$go$(_t_0, _head_0)));
  }
}

function $$$$047helpers$all_same_u32$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return true;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $$$$047helpers$all_same_u32$go$(_t_0, _h_0);
  }
}

function $$$$047helpers$all_same_str$go$(_xs_0, _head_0) {
  if (_xs_0.$ === "Nil") {
    return true;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $Bool$and$(($String$eq$(_h_0, _head_0)), ($$$$047helpers$all_same_str$go$(_t_0, _head_0)));
  }
}

function $$$$047helpers$all_same_str$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return true;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $$$$047helpers$all_same_str$go$(_t_0, _h_0);
  }
}

function $$$$047helpers$u32_list_eq$(_a_0, _b_0) {
  if (_a_0.$ === "Nil") {
    if (_b_0.$ === "Nil") {
      return true;
    } else {
      return false;
    }
  } else {
    const _h_0 = _a_0["head"];
    const _t_0 = _a_0["tail"];
    if (_b_0.$ === "Con") {
      const _h2_0 = _b_0["head"];
      const _t2_0 = _b_0["tail"];
      return $Bool$and$((_h_0 === _h2_0), ($$$$047helpers$u32_list_eq$(_t_0, _t2_0)));
    } else {
      return false;
    }
  }
}

function $$$$047helpers$ShapeRes$dims$head$(_s0_0) {
  if (_s0_0.$ === "../helpers.SShape") {
    const _d_0 = _s0_0["dims"];
    return {$: "Some", "value": _d_0};
  } else if (_s0_0.$ === "../helpers.SNoShape") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $$$$047helpers$ShapeRes$dims$same$(_ref_0, _d2_0) {
  if (_ref_0.$ === "None") {
    return false;
  } else {
    const _d_0 = _ref_0["value"];
    return $Bool$not$(($$$$047helpers$u32_list_eq$(_d_0, _d2_0)));
  }
}

function $$$$047helpers$ShapeRes$dims$ref$put$(_ref_0, _d2_0) {
  if (_ref_0.$ === "None") {
    return {$: "Some", "value": _d2_0};
  } else {
    const _d_0 = _ref_0["value"];
    return {$: "Some", "value": _d_0};
  }
}

function $$$$047helpers$ShapeRes$dims$ans$(_ref_0, _n_0) {
  if (_ref_0.$ === "None") {
    return {$: "../helpers.SShape", "dims": {$: "Con", "head": _n_0, "tail": {$: "Nil"}}};
  } else {
    const _d_0 = _ref_0["value"];
    return {$: "../helpers.SShape", "dims": {$: "Con", "head": _n_0, "tail": _d_0}};
  }
}

function $$$$047helpers$ShapeRes$dims$($0, $1, $2, $3) {
  for (;;) {
    {
      const _r_0 = $0;
      const _bad_0 = $1;
      const _ref_0 = $2;
      const _n_0 = $3;
      if (_r_0.$ === "Nil") {
        if (_bad_0) {
          return {$: "../helpers.SBad", "why": "inhomogeneous shape"};
        } else {
          return $$$$047helpers$ShapeRes$dims$ans$(_ref_0, _n_0);
        }
      } else {
        const _t_0 = _r_0["head"];
        if (_t_0.$ === "../helpers.SBad") {
          const _why_0 = _t_0["why"];
          if (_bad_0) {
            return {$: "../helpers.SBad", "why": _why_0};
          } else {
            return {$: "../helpers.SBad", "why": _why_0};
          }
        } else if (_t_0.$ === "../helpers.SNoShape") {
          if (!_bad_0) {
            return {$: "../helpers.SBad", "why": "inhomogeneous shape"};
          } else {
            return {$: "../helpers.SBad", "why": "inhomogeneous shape"};
          }
        } else {
          const _d2_0 = _t_0["dims"];
          const __2 = _r_0["tail"];
          if (_bad_0) {
            return {$: "../helpers.SBad", "why": "inhomogeneous shape"};
          } else {
            $0 = __2;
            $1 = ($$$$047helpers$ShapeRes$dims$same$(_ref_0, _d2_0));
            $2 = ($$$$047helpers$ShapeRes$dims$ref$put$(_ref_0, _d2_0));
            $3 = _n_0;
            continue;
          }
        }
      }
    }
  }
}

function $$$$047helpers$ShapeRes$of$walk$(_ss_0, _n_0) {
  if (_ss_0.$ === "Nil") {
    return {$: "../helpers.SShape", "dims": {$: "Nil"}};
  } else {
    const _s0_0 = _ss_0["head"];
    const _r_0 = _ss_0["tail"];
    return $$$$047helpers$ShapeRes$dims$(_r_0, false, ($$$$047helpers$ShapeRes$dims$head$(_s0_0)), _n_0);
  }
}

function $$$$047helpers$ShapeRes$of$(_ss_0) {
  const _x_0 = ($List$length$(_ss_0));
  return $$$$047helpers$ShapeRes$of$walk$(_ss_0, (_x_0 >>> 0));
}

function $$$$047helpers$stk$init$() {
  return {$: "../helpers.Stk", "fs": {$: "Nil"}};
}

function $$$$047helpers$stk$grow$(_fv_0, _t_0, _v_0) {
  const _g_0 = {$: "../helpers.Frame", "v": ($List$append$(_fv_0, {$: "Con", "head": _v_0, "tail": {$: "Nil"}}))};
  return {$: "Con", "head": _g_0, "tail": _t_0};
}

function $$$$047helpers$stk$push$(_xs_0, _v_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Con", "head": {$: "../helpers.Frame", "v": {$: "Con", "head": _v_0, "tail": {$: "Nil"}}}, "tail": {$: "Nil"}};
  } else {
    const _t_0 = _xs_0["head"];
    const _fv_0 = _t_0["v"];
    const _t_1 = _xs_0["tail"];
    return $$$$047helpers$stk$grow$(_fv_0, _t_1, _v_0);
  }
}

function $$$$047helpers$stk$push2$(_s_0, _v_0) {
  const _fs_0 = _s_0["fs"];
  return {$: "../helpers.Stk", "fs": ($$$$047helpers$stk$push$(_fs_0, _v_0))};
}

function $$$$047helpers$stk$open$(_s_0) {
  const _fs_0 = _s_0["fs"];
  return {$: "../helpers.Stk", "fs": {$: "Con", "head": {$: "../helpers.Frame", "v": {$: "Nil"}}, "tail": _fs_0}};
}

function $$$$047helpers$stk$peek$(_s_0) {
  const _t_0 = _s_0["fs"];
  if (_t_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _t_1 = _t_0["head"];
    const _fv_0 = _t_1["v"];
    return _fv_0;
  }
}

function $$$$047helpers$stk$unpush$(_xs_0, _v_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Con", "head": {$: "../helpers.Frame", "v": {$: "Con", "head": _v_0, "tail": {$: "Nil"}}}, "tail": {$: "Nil"}};
  } else {
    const _t_0 = _xs_0["head"];
    const _gv_0 = _t_0["v"];
    const _t_1 = _xs_0["tail"];
    return $$$$047helpers$stk$grow$(_gv_0, _t_1, _v_0);
  }
}

function $$$$047helpers$st$splice$(_ss_0, _t_0) {
  if (_ss_0.$ === "Nil") {
    return _t_0;
  } else {
    const _n_0 = _ss_0["head"];
    const _r_0 = _ss_0["tail"];
    return {$: "Con", "head": {$: "../helpers.GN", "n": _n_0}, "tail": ($$$$047helpers$st$splice$(_r_0, _t_0))};
  }
}

function $$$$047helpers$st$spread$(_ss_0, _t_0) {
  if (_ss_0.$ === "Nil") {
    return _t_0;
  } else {
    const _n_0 = _ss_0["head"];
    const _r_0 = _ss_0["tail"];
    return {$: "Con", "head": _n_0, "tail": ($$$$047helpers$st$spread$(_r_0, _t_0))};
  }
}

function $$$$047helpers$get_shape$go$($0, $1, $2) {
  for (;;) {
    {
      const _k_0 = $0;
      const _ws_0 = $1;
      const _st_0 = $2;
      if (_k_0 === 0) {
        return {$: "../helpers.SBad", "why": "shape nested too deeply"};
      } else {
        const _p_0 = (_k_0 - 1);
        if (_ws_0.$ === "Nil") {
          return $$$$047helpers$ShapeRes$of$(($$$$047helpers$stk$peek$(_st_0)));
        } else {
          const _t_0 = _ws_0["head"];
          if (_t_0.$ === "../helpers.GC") {
            const _t_1 = _ws_0["tail"];
            const _t_2 = _st_0["fs"];
            if (_t_2.$ === "Nil") {
              $0 = _p_0;
              $1 = _t_1;
              $2 = {$: "../helpers.Stk", "fs": {$: "Nil"}};
              continue;
            } else {
              const _t_3 = _t_2["head"];
              const _fv_0 = _t_3["v"];
              const _rest_0 = _t_2["tail"];
              $0 = _p_0;
              $1 = _t_1;
              $2 = {$: "../helpers.Stk", "fs": ($$$$047helpers$stk$unpush$(_rest_0, ($$$$047helpers$ShapeRes$of$(_fv_0))))};
              continue;
            }
          } else {
            const _t_4 = _t_0["n"];
            if (_t_4.$ === "../helpers.Ns") {
              const _t_5 = _ws_0["tail"];
              $0 = _p_0;
              $1 = _t_5;
              $2 = ($$$$047helpers$stk$push2$(_st_0, {$: "../helpers.SNoShape"}));
              continue;
            } else {
              const _ss_0 = _t_4["ss"];
              const _t_6 = _ws_0["tail"];
              $0 = _p_0;
              $1 = ($$$$047helpers$st$splice$(_ss_0, {$: "Con", "head": {$: "../helpers.GC"}, "tail": _t_6}));
              $2 = ($$$$047helpers$stk$open$(_st_0));
              continue;
            }
          }
        }
      }
    }
  }
}

function $$$$047helpers$nest_nodes$() {
  return 1000000;
}

function $$$$047helpers$get_shape$root$(_n_0, _k_0) {
  if (_n_0.$ === "../helpers.Ns") {
    return {$: "../helpers.SNoShape"};
  } else {
    const _ss_0 = _n_0["ss"];
    return $$$$047helpers$get_shape$go$(_k_0, {$: "Con", "head": {$: "../helpers.GN", "n": {$: "../helpers.Nl", "ss": _ss_0}}, "tail": {$: "Nil"}}, ($$$$047helpers$stk$init$()));
  }
}

function $$$$047helpers$get_shape$(_n_0) {
  return $$$$047helpers$get_shape$root$(_n_0, ($$$$047helpers$nest_nodes$()));
}

function $$$$047helpers$is_image_shape$tail$(_last_0) {
  if (_last_0.$ === "Some") {
    const _x_0 = _last_0["value"];
    return (_x_0 === 4);
  } else {
    return false;
  }
}

function $$$$047helpers$is_image_shape$dims$(_three_0, _d_0) {
  if (_three_0) {
    return $$$$047helpers$is_image_shape$tail$(($List$last$(_d_0)));
  } else {
    return false;
  }
}

function $$$$047helpers$is_image_shape$rank$(_r_0) {
  if (_r_0.$ === "../helpers.SNoShape") {
    return {$: "Nil"};
  } else if (_r_0.$ === "../helpers.SBad") {
    return {$: "Nil"};
  } else {
    const _d_0 = _r_0["dims"];
    return _d_0;
  }
}

function $$$$047helpers$is_image_shape$go$(_d_0) {
  if (_d_0.$ === "Nil") {
    return false;
  } else {
    const _x_0 = ($List$length$(_d_0));
    const _x_1 = (_x_0 >>> 0);
    return $$$$047helpers$is_image_shape$dims$((_x_1 === 3), _d_0);
  }
}

function $$$$047helpers$is_image_shape$(_r_0) {
  return $$$$047helpers$is_image_shape$go$(($$$$047helpers$is_image_shape$rank$(_r_0)));
}

function $$$$047helpers$all_int_nest$(_n_0) {
  if (_n_0.$ === "../helpers.Ns") {
    return true;
  } else {
    return false;
  }
}

function $$$$047helpers$fully_flatten$go$($0, $1, $2) {
  for (;;) {
    {
      const _k_0 = $0;
      const _ws_0 = $1;
      const _acc_0 = $2;
      if (_k_0 === 0) {
        return $List$reverse$(_acc_0);
      } else {
        const _p_0 = (_k_0 - 1);
        if (_ws_0.$ === "Nil") {
          return $List$reverse$(_acc_0);
        } else {
          const _t_0 = _ws_0["head"];
          if (_t_0.$ === "../helpers.Ns") {
            const _v_0 = _t_0["v"];
            const _t_1 = _ws_0["tail"];
            $0 = _p_0;
            $1 = _t_1;
            $2 = {$: "Con", "head": {$: "../helpers.Ns", "v": _v_0}, "tail": _acc_0};
            continue;
          } else {
            const _ss_0 = _t_0["ss"];
            const _t_2 = _ws_0["tail"];
            $0 = _p_0;
            $1 = ($$$$047helpers$st$spread$(_ss_0, _t_2));
            $2 = _acc_0;
            continue;
          }
        }
      }
    }
  }
}

function $$$$047helpers$fully_flatten_nest$(_n_0) {
  if (_n_0.$ === "../helpers.Ns") {
    const _v_0 = _n_0["v"];
    return {$: "Con", "head": {$: "../helpers.Ns", "v": _v_0}, "tail": {$: "Nil"}};
  } else {
    const _ss_0 = _n_0["ss"];
    return $$$$047helpers$fully_flatten$go$(($$$$047helpers$nest_nodes$()), _ss_0, {$: "Nil"});
  }
}

function $$$$047helpers$flatten_u32$(_l_0) {
  return $List$concat$(_l_0);
}

function $$$$047helpers$f32_exp_all_ones$(_x_0) {
  const _x_1 = f32_bits(_x_0);
  const _x_2 = ((_x_1 & 2139095040) >>> 0);
  return (_x_2 === 2139095040);
}

function $$$$047helpers$f32_is_nan$(_x_0) {
  const _x_1 = f32_bits(_x_0);
  const _x_2 = ((_x_1 & 8388607) >>> 0);
  return $Bool$and$(($$$$047helpers$f32_exp_all_ones$(_x_0)), ($Bool$not$((_x_2 === 0))));
}

function $$$$047helpers$f32_is_finite$(_x_0) {
  return $Bool$not$(($$$$047helpers$f32_exp_all_ones$(_x_0)));
}

function $$$$047helpers$f32_is_neg$(_x_0) {
  const _x_1 = f32_bits(_x_0);
  return (_x_1 >= 2147483648);
}

function $$$$047helpers$f32_frac$next$(_f_0) {
  const _x_0 = Math.fround(_f_0 * 10);
  const _x_1 = (_x_0 >= 1 && _x_0 < 4294967296 ? Math.floor(_x_0) : 0);
  const _x_2 = Math.fround(_f_0 * 10);
  const _x_3 = Math.fround(_x_1);
  return Math.fround(_x_2 - _x_3);
}

function $$$$047helpers$f32_frac$digit$(_f_0) {
  const _x_0 = Math.fround(_f_0 * 10);
  const _x_1 = (_x_0 >= 1 && _x_0 < 4294967296 ? Math.floor(_x_0) : 0);
  return $Char$from_u32$(((48 + _x_1) >>> 0));
}

function $$$$047helpers$f32_frac$step$(_f_0, _acc_0) {
  const _x_0 = ($String$from_list$({$: "Con", "head": ($$$$047helpers$f32_frac$digit$(_f_0)), "tail": {$: "Nil"}}));
  return {$: "../helpers.Frac", "f": ($$$$047helpers$f32_frac$next$(_f_0)), "acc": (_acc_0 + _x_0)};
}

function $$$$047helpers$f32_frac$put$(_fr_0) {
  const _acc_0 = _fr_0["acc"];
  return _acc_0;
}

function $$$$047helpers$f32_frac$go$($0, $1) {
  for (;;) {
    {
      const _n_0 = $0;
      const _fr_0 = $1;
      if (_n_0 === 0) {
        return $$$$047helpers$f32_frac$put$(_fr_0);
      } else {
        const _p_0 = (_n_0 - 1);
        const _f_0 = _fr_0["f"];
        const _acc_0 = _fr_0["acc"];
        $0 = _p_0;
        $1 = ($$$$047helpers$f32_frac$step$(_f_0, _acc_0));
        continue;
      }
    }
  }
}

function $$$$047helpers$f32_fixed$put$(_neg_0, _s_0) {
  if (_neg_0) {
    return ("-" + _s_0);
  } else {
    return _s_0;
  }
}

function $$$$047helpers$f32_fixed$text3$(_neg_0, _ip_0, _dp_0, _frac_0) {
  const _x_0 = ($U32$show$(_ip_0));
  const _x_1 = (_x_0 + ".");
  const _x_2 = ($$$$047helpers$f32_frac$go$(_dp_0, _frac_0));
  return $$$$047helpers$f32_fixed$put$(_neg_0, (_x_1 + _x_2));
}

function $$$$047helpers$f32_fixed$text2$(_neg_0, _dp_0, _m_0, _ip_0) {
  const _x_0 = Math.fround(_ip_0);
  return $$$$047helpers$f32_fixed$text3$(_neg_0, _ip_0, _dp_0, {$: "../helpers.Frac", "f": Math.fround(_m_0 - _x_0), "acc": ""});
}

function $$$$047helpers$f32_fixed$text1$(_m_0, _dp_0, _neg_0) {
  const _x_0 = Math.fround(Math.trunc(_m_0));
  return $$$$047helpers$f32_fixed$text2$(_neg_0, _dp_0, _m_0, (_x_0 >= 1 && _x_0 < 4294967296 ? Math.floor(_x_0) : 0));
}

function $$$$047helpers$f32_fixed$text$(_x_0, _dp_0, _m_0) {
  return $$$$047helpers$f32_fixed$text1$(_m_0, _dp_0, ($$$$047helpers$f32_is_neg$(_x_0)));
}

function $$$$047helpers$f32_fixed$body$(_x_0, _dp_0) {
  return $$$$047helpers$f32_fixed$text1$(Math.fround(Math.abs(_x_0)), _dp_0, ($$$$047helpers$f32_is_neg$(_x_0)));
}

function $$$$047helpers$f32_fixed$special$inf$(_neg_0) {
  if (_neg_0) {
    return {$: "Some", "value": "-inf"};
  } else {
    return {$: "Some", "value": "inf"};
  }
}

function $$$$047helpers$f32_fixed$special$fin$(_fin_0, _neg_0) {
  if (_fin_0) {
    return {$: "None"};
  } else {
    return $$$$047helpers$f32_fixed$special$inf$(_neg_0);
  }
}

function $$$$047helpers$f32_fixed$special$(_nan_0, _fin_0, _neg_0) {
  if (_nan_0) {
    return {$: "Some", "value": "nan"};
  } else {
    return $$$$047helpers$f32_fixed$special$fin$(_fin_0, _neg_0);
  }
}

function $$$$047helpers$f32_fixed$go$(_special_0, _x_0, _dp_0) {
  if (_special_0.$ === "Some") {
    const _s_0 = _special_0["value"];
    return _s_0;
  } else {
    return $$$$047helpers$f32_fixed$body$(_x_0, _dp_0);
  }
}

function $$$$047helpers$f32_fixed$(_x_0, _dp_0) {
  return $$$$047helpers$f32_fixed$go$(($$$$047helpers$f32_fixed$special$(($$$$047helpers$f32_is_nan$(_x_0)), ($$$$047helpers$f32_is_finite$(_x_0)), ($$$$047helpers$f32_is_neg$(_x_0)))), _x_0, _dp_0);
}

function $$$$047helpers$f32_is_int_valued$(_fin_0, _x_0) {
  if (!_fin_0) {
    return false;
  } else {
    const _x_1 = Math.fround(Math.floor(_x_0));
    return (_x_1 === _x_0);
  }
}

function $$$$047helpers$f32_show$put2$(_iv_0, _x_0, _neg_0) {
  if (_iv_0) {
    const _x_1 = Math.fround(Math.abs(_x_0));
    return $$$$047helpers$f32_fixed$put$(_neg_0, ($U32$show$((_x_1 >= 1 && _x_1 < 4294967296 ? Math.floor(_x_1) : 0))));
  } else {
    return $$$$047helpers$f32_fixed$body$(_x_0, 6);
  }
}

function $$$$047helpers$f32_show$put$(_iv_0, _x_0) {
  return $$$$047helpers$f32_show$put2$(_iv_0, _x_0, ($$$$047helpers$f32_is_neg$(_x_0)));
}

function $$$$047helpers$f32_show$special$(_nan_0, _fin_0, _neg_0) {
  if (_nan_0) {
    return {$: "Some", "value": "nan"};
  } else {
    if (_fin_0) {
      return {$: "None"};
    } else {
      if (_neg_0) {
        return {$: "Some", "value": "-inf"};
      } else {
        return {$: "Some", "value": "inf"};
      }
    }
  }
}

function $$$$047helpers$f32_show$go2$(_s_0, _x_0) {
  if (_s_0.$ === "Some") {
    const _t_0 = _s_0["value"];
    return _t_0;
  } else {
    return $$$$047helpers$f32_show$put$(($$$$047helpers$f32_is_int_valued$(($$$$047helpers$f32_is_finite$(_x_0)), _x_0)), _x_0);
  }
}

function $$$$047helpers$f32_show$go$(_x_0, _s_0) {
  return $$$$047helpers$f32_show$go2$(_s_0, _x_0);
}

function $$$$047helpers$f32_show$(_x_0) {
  return $$$$047helpers$f32_show$go$(_x_0, ($$$$047helpers$f32_show$special$(($$$$047helpers$f32_is_nan$(_x_0)), ($$$$047helpers$f32_is_finite$(_x_0)), ($$$$047helpers$f32_is_neg$(_x_0)))));
}

function $$$$047helpers$pad$n$go$(_gt_0, _w_0, _n_0) {
  if (_gt_0) {
    return ((_w_0 - _n_0) >>> 0);
  } else {
    return 0;
  }
}

function $$$$047helpers$pad$n$(_w_0, _n_0) {
  return $$$$047helpers$pad$n$go$((_w_0 > _n_0), _w_0, _n_0);
}

function $$$$047helpers$pad_left$blank$(_s_0, _w_0) {
  const _x_0 = [..._s_0].length;
  const _x_1 = ($$$$047helpers$pad$n$(_w_0, (_x_0 >>> 0)));
  return $String$repeat$(" ", _x_1);
}

function $$$$047helpers$pad_left$(_s_0, _w_0) {
  const _x_0 = ($$$$047helpers$pad_left$blank$(_s_0, _w_0));
  return (_x_0 + _s_0);
}

function $$$$047helpers$pad_right$(_s_0, _w_0) {
  const _x_0 = ($$$$047helpers$pad_left$blank$(_s_0, _w_0));
  return (_s_0 + _x_0);
}

function $$$$047helpers$color_code$(_ci_0, _background_0) {
  const _x_0 = ($Bool$to_u32$(_background_0));
  const _x_1 = (Math.imul(_x_0, 10) >>> 0);
  const _x_2 = ((_x_1 + 30) >>> 0);
  return ((_x_2 + _ci_0) >>> 0);
}

function $$$$047helpers$esc$(_u_0) {
  return $String$from_list$({$: "Con", "head": ($Char$from_u32$(27)), "tail": {$: "Con", "head": ($Char$from_u32$(91)), "tail": {$: "Con", "head": ($Char$from_u32$(_u_0)), "tail": {$: "Con", "head": ($Char$from_u32$(109)), "tail": {$: "Nil"}}}}});
}

function $$$$047helpers$color_of$(_s_0) {
  if (_s_0 !== "") {
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_1 = _t_0.codePointAt(0);
    if (_t_1 == 98) {
      const _t_2 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_2 !== "") {
        const _t_3 = (_t_2.codePointAt(0) > 0xFFFF ? _t_2.slice(0, 2) : _t_2[0]);
        const _t_4 = _t_3.codePointAt(0);
        if (_t_4 == 108) {
          const _t_5 = (_t_2.codePointAt(0) > 0xFFFF ? _t_2.slice(2) : _t_2.slice(1));
          if (_t_5 !== "") {
            const _t_6 = (_t_5.codePointAt(0) > 0xFFFF ? _t_5.slice(0, 2) : _t_5[0]);
            const _t_7 = _t_6.codePointAt(0);
            if (_t_7 == 97) {
              const _t_8 = (_t_5.codePointAt(0) > 0xFFFF ? _t_5.slice(2) : _t_5.slice(1));
              if (_t_8 !== "") {
                const _t_9 = (_t_8.codePointAt(0) > 0xFFFF ? _t_8.slice(0, 2) : _t_8[0]);
                const _t_10 = _t_9.codePointAt(0);
                if (_t_10 == 99) {
                  const _t_11 = (_t_8.codePointAt(0) > 0xFFFF ? _t_8.slice(2) : _t_8.slice(1));
                  if (_t_11 !== "") {
                    const _t_12 = (_t_11.codePointAt(0) > 0xFFFF ? _t_11.slice(0, 2) : _t_11[0]);
                    const _t_13 = _t_12.codePointAt(0);
                    if (_t_13 == 107) {
                      const _t_14 = (_t_11.codePointAt(0) > 0xFFFF ? _t_11.slice(2) : _t_11.slice(1));
                      if (_t_14 === "") {
                        return {$: "Some", "value": 0};
                      } else {
                        return {$: "None"};
                      }
                    } else {
                      return {$: "None"};
                    }
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else if (_t_7 == 117) {
              const _t_15 = (_t_5.codePointAt(0) > 0xFFFF ? _t_5.slice(2) : _t_5.slice(1));
              if (_t_15 !== "") {
                const _t_16 = (_t_15.codePointAt(0) > 0xFFFF ? _t_15.slice(0, 2) : _t_15[0]);
                const _t_17 = _t_16.codePointAt(0);
                if (_t_17 == 101) {
                  const _t_18 = (_t_15.codePointAt(0) > 0xFFFF ? _t_15.slice(2) : _t_15.slice(1));
                  if (_t_18 === "") {
                    return {$: "Some", "value": 4};
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if (_t_1 == 114) {
      const _t_19 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_19 !== "") {
        const _t_20 = (_t_19.codePointAt(0) > 0xFFFF ? _t_19.slice(0, 2) : _t_19[0]);
        const _t_21 = _t_20.codePointAt(0);
        if (_t_21 == 101) {
          const _t_22 = (_t_19.codePointAt(0) > 0xFFFF ? _t_19.slice(2) : _t_19.slice(1));
          if (_t_22 !== "") {
            const _t_23 = (_t_22.codePointAt(0) > 0xFFFF ? _t_22.slice(0, 2) : _t_22[0]);
            const _t_24 = _t_23.codePointAt(0);
            if (_t_24 == 100) {
              const _t_25 = (_t_22.codePointAt(0) > 0xFFFF ? _t_22.slice(2) : _t_22.slice(1));
              if (_t_25 === "") {
                return {$: "Some", "value": 1};
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if ((_t_1 & 1) == 0) {
      return {$: "None"};
    } else if (_t_1 == 103) {
      const _t_26 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_26 !== "") {
        const _t_27 = (_t_26.codePointAt(0) > 0xFFFF ? _t_26.slice(0, 2) : _t_26[0]);
        const _t_28 = _t_27.codePointAt(0);
        if (_t_28 == 114) {
          const _t_29 = (_t_26.codePointAt(0) > 0xFFFF ? _t_26.slice(2) : _t_26.slice(1));
          if (_t_29 !== "") {
            const _t_30 = (_t_29.codePointAt(0) > 0xFFFF ? _t_29.slice(0, 2) : _t_29[0]);
            const _t_31 = _t_30.codePointAt(0);
            if (_t_31 == 101) {
              const _t_32 = (_t_29.codePointAt(0) > 0xFFFF ? _t_29.slice(2) : _t_29.slice(1));
              if (_t_32 !== "") {
                const _t_33 = (_t_32.codePointAt(0) > 0xFFFF ? _t_32.slice(0, 2) : _t_32[0]);
                const _t_34 = _t_33.codePointAt(0);
                if (_t_34 == 101) {
                  const _t_35 = (_t_32.codePointAt(0) > 0xFFFF ? _t_32.slice(2) : _t_32.slice(1));
                  if (_t_35 !== "") {
                    const _t_36 = (_t_35.codePointAt(0) > 0xFFFF ? _t_35.slice(0, 2) : _t_35[0]);
                    const _t_37 = _t_36.codePointAt(0);
                    if (_t_37 == 110) {
                      const _t_38 = (_t_35.codePointAt(0) > 0xFFFF ? _t_35.slice(2) : _t_35.slice(1));
                      if (_t_38 === "") {
                        return {$: "Some", "value": 2};
                      } else {
                        return {$: "None"};
                      }
                    } else {
                      return {$: "None"};
                    }
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if (_t_1 == 119) {
      const _t_39 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_39 !== "") {
        const _t_40 = (_t_39.codePointAt(0) > 0xFFFF ? _t_39.slice(0, 2) : _t_39[0]);
        const _t_41 = _t_40.codePointAt(0);
        if (_t_41 == 104) {
          const _t_42 = (_t_39.codePointAt(0) > 0xFFFF ? _t_39.slice(2) : _t_39.slice(1));
          if (_t_42 !== "") {
            const _t_43 = (_t_42.codePointAt(0) > 0xFFFF ? _t_42.slice(0, 2) : _t_42[0]);
            const _t_44 = _t_43.codePointAt(0);
            if (_t_44 == 105) {
              const _t_45 = (_t_42.codePointAt(0) > 0xFFFF ? _t_42.slice(2) : _t_42.slice(1));
              if (_t_45 !== "") {
                const _t_46 = (_t_45.codePointAt(0) > 0xFFFF ? _t_45.slice(0, 2) : _t_45[0]);
                const _t_47 = _t_46.codePointAt(0);
                if (_t_47 == 116) {
                  const _t_48 = (_t_45.codePointAt(0) > 0xFFFF ? _t_45.slice(2) : _t_45.slice(1));
                  if (_t_48 !== "") {
                    const _t_49 = (_t_48.codePointAt(0) > 0xFFFF ? _t_48.slice(0, 2) : _t_48[0]);
                    const _t_50 = _t_49.codePointAt(0);
                    if (_t_50 == 101) {
                      const _t_51 = (_t_48.codePointAt(0) > 0xFFFF ? _t_48.slice(2) : _t_48.slice(1));
                      if (_t_51 === "") {
                        return {$: "Some", "value": 7};
                      } else {
                        return {$: "None"};
                      }
                    } else {
                      return {$: "None"};
                    }
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if ((_t_1 & 7) == 7) {
      return {$: "None"};
    } else if (_t_1 == 99) {
      const _t_52 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_52 !== "") {
        const _t_53 = (_t_52.codePointAt(0) > 0xFFFF ? _t_52.slice(0, 2) : _t_52[0]);
        const _t_54 = _t_53.codePointAt(0);
        if (_t_54 == 121) {
          const _t_55 = (_t_52.codePointAt(0) > 0xFFFF ? _t_52.slice(2) : _t_52.slice(1));
          if (_t_55 !== "") {
            const _t_56 = (_t_55.codePointAt(0) > 0xFFFF ? _t_55.slice(0, 2) : _t_55[0]);
            const _t_57 = _t_56.codePointAt(0);
            if (_t_57 == 97) {
              const _t_58 = (_t_55.codePointAt(0) > 0xFFFF ? _t_55.slice(2) : _t_55.slice(1));
              if (_t_58 !== "") {
                const _t_59 = (_t_58.codePointAt(0) > 0xFFFF ? _t_58.slice(0, 2) : _t_58[0]);
                const _t_60 = _t_59.codePointAt(0);
                if (_t_60 == 110) {
                  const _t_61 = (_t_58.codePointAt(0) > 0xFFFF ? _t_58.slice(2) : _t_58.slice(1));
                  if (_t_61 === "") {
                    return {$: "Some", "value": 6};
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if ((_t_1 & 7) == 3) {
      return {$: "None"};
    } else if (_t_1 == 121) {
      const _t_62 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_62 !== "") {
        const _t_63 = (_t_62.codePointAt(0) > 0xFFFF ? _t_62.slice(0, 2) : _t_62[0]);
        const _t_64 = _t_63.codePointAt(0);
        if (_t_64 == 101) {
          const _t_65 = (_t_62.codePointAt(0) > 0xFFFF ? _t_62.slice(2) : _t_62.slice(1));
          if (_t_65 !== "") {
            const _t_66 = (_t_65.codePointAt(0) > 0xFFFF ? _t_65.slice(0, 2) : _t_65[0]);
            const _t_67 = _t_66.codePointAt(0);
            if (_t_67 == 108) {
              const _t_68 = (_t_65.codePointAt(0) > 0xFFFF ? _t_65.slice(2) : _t_65.slice(1));
              if (_t_68 !== "") {
                const _t_69 = (_t_68.codePointAt(0) > 0xFFFF ? _t_68.slice(0, 2) : _t_68[0]);
                const _t_70 = _t_69.codePointAt(0);
                if (_t_70 == 108) {
                  const _t_71 = (_t_68.codePointAt(0) > 0xFFFF ? _t_68.slice(2) : _t_68.slice(1));
                  if (_t_71 !== "") {
                    const _t_72 = (_t_71.codePointAt(0) > 0xFFFF ? _t_71.slice(0, 2) : _t_71[0]);
                    const _t_73 = _t_72.codePointAt(0);
                    if (_t_73 == 111) {
                      const _t_74 = (_t_71.codePointAt(0) > 0xFFFF ? _t_71.slice(2) : _t_71.slice(1));
                      if (_t_74 !== "") {
                        const _t_75 = (_t_74.codePointAt(0) > 0xFFFF ? _t_74.slice(0, 2) : _t_74[0]);
                        const _t_76 = _t_75.codePointAt(0);
                        if (_t_76 == 119) {
                          const _t_77 = (_t_74.codePointAt(0) > 0xFFFF ? _t_74.slice(2) : _t_74.slice(1));
                          if (_t_77 === "") {
                            return {$: "Some", "value": 3};
                          } else {
                            return {$: "None"};
                          }
                        } else {
                          return {$: "None"};
                        }
                      } else {
                        return {$: "None"};
                      }
                    } else {
                      return {$: "None"};
                    }
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else if ((_t_1 & 7) == 1) {
      return {$: "None"};
    } else if (_t_1 == 109) {
      const _t_78 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
      if (_t_78 !== "") {
        const _t_79 = (_t_78.codePointAt(0) > 0xFFFF ? _t_78.slice(0, 2) : _t_78[0]);
        const _t_80 = _t_79.codePointAt(0);
        if (_t_80 == 97) {
          const _t_81 = (_t_78.codePointAt(0) > 0xFFFF ? _t_78.slice(2) : _t_78.slice(1));
          if (_t_81 !== "") {
            const _t_82 = (_t_81.codePointAt(0) > 0xFFFF ? _t_81.slice(0, 2) : _t_81[0]);
            const _t_83 = _t_82.codePointAt(0);
            if (_t_83 == 103) {
              const _t_84 = (_t_81.codePointAt(0) > 0xFFFF ? _t_81.slice(2) : _t_81.slice(1));
              if (_t_84 !== "") {
                const _t_85 = (_t_84.codePointAt(0) > 0xFFFF ? _t_84.slice(0, 2) : _t_84[0]);
                const _t_86 = _t_85.codePointAt(0);
                if (_t_86 == 101) {
                  const _t_87 = (_t_84.codePointAt(0) > 0xFFFF ? _t_84.slice(2) : _t_84.slice(1));
                  if (_t_87 !== "") {
                    const _t_88 = (_t_87.codePointAt(0) > 0xFFFF ? _t_87.slice(0, 2) : _t_87[0]);
                    const _t_89 = _t_88.codePointAt(0);
                    if (_t_89 == 110) {
                      const _t_90 = (_t_87.codePointAt(0) > 0xFFFF ? _t_87.slice(2) : _t_87.slice(1));
                      if (_t_90 !== "") {
                        const _t_91 = (_t_90.codePointAt(0) > 0xFFFF ? _t_90.slice(0, 2) : _t_90[0]);
                        const _t_92 = _t_91.codePointAt(0);
                        if (_t_92 == 116) {
                          const _t_93 = (_t_90.codePointAt(0) > 0xFFFF ? _t_90.slice(2) : _t_90.slice(1));
                          if (_t_93 !== "") {
                            const _t_94 = (_t_93.codePointAt(0) > 0xFFFF ? _t_93.slice(0, 2) : _t_93[0]);
                            const _t_95 = _t_94.codePointAt(0);
                            if (_t_95 == 97) {
                              const _t_96 = (_t_93.codePointAt(0) > 0xFFFF ? _t_93.slice(2) : _t_93.slice(1));
                              if (_t_96 === "") {
                                return {$: "Some", "value": 5};
                              } else {
                                return {$: "None"};
                              }
                            } else {
                              return {$: "None"};
                            }
                          } else {
                            return {$: "None"};
                          }
                        } else {
                          return {$: "None"};
                        }
                      } else {
                        return {$: "None"};
                      }
                    } else {
                      return {$: "None"};
                    }
                  } else {
                    return {$: "None"};
                  }
                } else {
                  return {$: "None"};
                }
              } else {
                return {$: "None"};
              }
            } else {
              return {$: "None"};
            }
          } else {
            return {$: "None"};
          }
        } else {
          return {$: "None"};
        }
      } else {
        return {$: "None"};
      }
    } else {
      return {$: "None"};
    }
  } else {
    return {$: "None"};
  }
}

function $$$$047helpers$colored$put$(_color_0, _st_0, _background_0) {
  if (_color_0.$ === "None") {
    return _st_0;
  } else {
    const _ci_0 = _color_0["value"];
    const _x_0 = ($$$$047helpers$esc$(($$$$047helpers$color_code$(_ci_0, _background_0))));
    const _x_1 = (_x_0 + _st_0);
    return (_x_1 + "\u001b[0m");
  }
}

function $$$$047helpers$colored$flag$(_nc_0, _st_0, _color_0, _background_0) {
  if (_nc_0) {
    return _st_0;
  } else {
    return $$$$047helpers$colored$put$(_color_0, _st_0, _background_0);
  }
}

function $$$$047helpers$colored$go$(_f_0, _st_0, _color_0, _background_0) {
  const _nc_0 = _f_0["no_color"];
  return $$$$047helpers$colored$flag$(_nc_0, _st_0, _color_0, _background_0);
}

function $$$$047helpers$colored$(_f_0, _st_0, _color_0, _background_0) {
  return $$$$047helpers$colored$go$(_f_0, _st_0, _color_0, _background_0);
}

function $$$$047helpers$colorize_float$hi$(_gt_0) {
  if (_gt_0) {
    return {$: "Some", "value": 1};
  } else {
    return {$: "Some", "value": 3};
  }
}

function $$$$047helpers$colorize_float$pick$(_lt_0, _gt_0) {
  if (_lt_0) {
    return {$: "Some", "value": 2};
  } else {
    return $$$$047helpers$colorize_float$hi$(_gt_0);
  }
}

function $$$$047helpers$colorize_float$(_f_0, _x_0) {
  const _x_1 = ($$$$047helpers$pad_left$(($$$$047helpers$f32_fixed$(_x_0, 2)), 7));
  return $$$$047helpers$colored$(_f_0, (_x_1 + "x"), ($$$$047helpers$colorize_float$pick$((_x_0 < 0.75), (_x_0 > 1.149999976158142))), false);
}

function $$$$047helpers$time_to_str$ms$(_t_0, _w_0) {
  const _x_0 = ($$$$047helpers$pad_left$(($$$$047helpers$f32_fixed$(Math.fround(_t_0 * 1000), 2)), _w_0));
  return (_x_0 + "ms");
}

function $$$$047helpers$time_to_str$us$(_t_0, _w_0) {
  const _x_0 = ($$$$047helpers$pad_left$(($$$$047helpers$f32_fixed$(Math.fround(_t_0 * 1000000), 2)), _w_0));
  return (_x_0 + "us");
}

function $$$$047helpers$time_to_str$pick$(_gt10_0, _gt001_0, _t_0, _w_0) {
  if (_gt10_0) {
    const _x_0 = ($$$$047helpers$pad_left$(($$$$047helpers$f32_fixed$(_t_0, 2)), _w_0));
    return (_x_0 + "s ");
  } else {
    if (_gt001_0) {
      return $$$$047helpers$time_to_str$ms$(_t_0, _w_0);
    } else {
      return $$$$047helpers$time_to_str$us$(_t_0, _w_0);
    }
  }
}

function $$$$047helpers$time_to_str$(_t_0, _w_0) {
  return $$$$047helpers$time_to_str$pick$((_t_0 > 10), (_t_0 > 0.009999999776482582), _t_0, _w_0);
}

function $$$$047helpers$size_to_str$mb$(_s_0) {
  const _x_0 = Math.fround(_s_0);
  const _x_1 = ($$$$047helpers$f32_fixed$(Math.fround(_x_0 / 1048576), 2));
  return (_x_1 + " MB");
}

function $$$$047helpers$size_to_str$kb$(_s_0) {
  const _x_0 = Math.fround(_s_0);
  const _x_1 = ($$$$047helpers$f32_fixed$(Math.fround(_x_0 / 1024), 2));
  return (_x_1 + " KB");
}

function $$$$047helpers$size_to_str$pick$(_gb_0, _mb_0, _kb_0, _s_0) {
  if (_gb_0) {
    const _x_0 = Math.fround(_s_0);
    const _x_1 = ($$$$047helpers$f32_fixed$(Math.fround(_x_0 / 1073741824), 2));
    return (_x_1 + " GB");
  } else {
    if (_mb_0) {
      return $$$$047helpers$size_to_str$mb$(_s_0);
    } else {
      if (_kb_0) {
        return $$$$047helpers$size_to_str$kb$(_s_0);
      } else {
        const _x_2 = ($U32$show$(_s_0));
        return (_x_2 + " B");
      }
    }
  }
}

function $$$$047helpers$size_to_str$(_s_0) {
  return $$$$047helpers$size_to_str$pick$((_s_0 >= 1073741824), (_s_0 >= 1048576), (_s_0 >= 1024), _s_0);
}

function $$$$047helpers$ansistrip$done4$(_pend_0, _acc_0) {
  return $List$append$(($List$append$({$: "Con", "head": ($Char$from_u32$(27)), "tail": {$: "Nil"}}, {$: "Con", "head": ($Char$from_u32$(91)), "tail": {$: "Nil"}})), ($List$append$(_pend_0, _acc_0)));
}

function $$$$047helpers$ansistrip$done3$(_m_0, _acc_0, _pend_0) {
  if (_m_0 === 0) {
    return _acc_0;
  } else if (_m_0 === 1) {
    return $List$append$({$: "Con", "head": ($Char$from_u32$(27)), "tail": {$: "Nil"}}, _acc_0);
  } else {
    return $List$append$({$: "Con", "head": ($Char$from_u32$(27)), "tail": {$: "Nil"}}, _acc_0);
  }
}

function $$$$047helpers$ansistrip$done2$(_c_0, _m_0, _acc_0, _pend_0) {
  if (_m_0 === 0) {
    return $List$reverse$(_acc_0);
  } else if (_m_0 === 1) {
    return $$$$047helpers$ansistrip$done3$(1, ($List$reverse$(_acc_0)), ($List$reverse$(_pend_0)));
  } else {
    return $$$$047helpers$ansistrip$done3$(1, ($List$reverse$(_acc_0)), ($List$reverse$(_pend_0)));
  }
}

function $$$$047helpers$ansistrip$done$(_st_0) {
  const _c_0 = _st_0["c"];
  const _m_0 = _st_0["m"];
  const _acc_0 = _st_0["acc"];
  const _pend_0 = _st_0["pend"];
  return $$$$047helpers$ansistrip$done2$(_c_0, _m_0, _acc_0, _pend_0);
}

function $$$$047helpers$ansistrip$go$esc$(_h_0, _acc_0) {
  return $List$append$({$: "Con", "head": ($Char$from_u32$(27)), "tail": {$: "Nil"}}, ($List$append$({$: "Con", "head": _h_0, "tail": {$: "Nil"}}, _acc_0)));
}

function $$$$047helpers$ansistrip$go$($0, $1) {
  for (;;) {
    {
      const _cs_0 = $0;
      const _st_0 = $1;
      if (_cs_0.$ === "Nil") {
        return $$$$047helpers$ansistrip$done$(_st_0);
      } else {
        const _h_0 = _cs_0["head"];
        const _t_0 = _cs_0["tail"];
        const _t_1 = _st_0["c"];
        if (_t_1 == 27) {
          const _t_2 = _st_0["m"];
          if (_t_2 === 0) {
            const _acc_0 = _st_0["acc"];
            const _pend_0 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 1, "acc": _acc_0, "pend": _pend_0};
            continue;
          } else {
            const _q_0 = (_t_2 - 1);
            const _acc_1 = _st_0["acc"];
            const _pend_1 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": nat_chk(_q_0 + 1), "acc": _acc_1, "pend": {$: "Con", "head": _h_0, "tail": _pend_1}};
            continue;
          }
        } else if (_t_1 == 91) {
          const _t_3 = _st_0["m"];
          if (_t_3 === 0) {
            const _acc_2 = _st_0["acc"];
            const _pend_2 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 1, "acc": _acc_2, "pend": _pend_2};
            continue;
          } else {
            const _q_1 = (_t_3 - 1);
            const _acc_3 = _st_0["acc"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": nat_chk(_q_1 + 1), "acc": _acc_3, "pend": {$: "Nil"}};
            continue;
          }
        } else if (_t_1 == 75) {
          const _t_4 = _st_0["m"];
          if (_t_4 === 0) {
            const _acc_4 = _st_0["acc"];
            const _pend_4 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": _acc_4, "pend": _pend_4};
            continue;
          } else {
            const _acc_5 = _st_0["acc"];
            const _pend_5 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": _acc_5, "pend": _pend_5};
            continue;
          }
        } else if (_t_1 == 109) {
          const _t_5 = _st_0["m"];
          if (_t_5 === 0) {
            const _acc_6 = _st_0["acc"];
            const _pend_6 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": _acc_6, "pend": _pend_6};
            continue;
          } else {
            const _acc_7 = _st_0["acc"];
            const _pend_7 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": _acc_7, "pend": _pend_7};
            continue;
          }
        } else {
          const _t_6 = _st_0["m"];
          if (_t_6 === 0) {
            const _acc_8 = _st_0["acc"];
            const _pend_8 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": {$: "Con", "head": _h_0, "tail": _acc_8}, "pend": _pend_8};
            continue;
          } else {
            const _acc_9 = _st_0["acc"];
            const _pend_9 = _st_0["pend"];
            $0 = _t_0;
            $1 = {$: "../helpers.Ast", "c": ($Char$to_u32$(_h_0)), "m": 0, "acc": ($$$$047helpers$ansistrip$go$esc$(_h_0, _acc_9)), "pend": _pend_9};
            continue;
          }
        }
      }
    }
  }
}

function $$$$047helpers$ansistrip$(_s_0) {
  return $String$from_list$(($$$$047helpers$ansistrip$go$(($String$to_list$(_s_0)), {$: "../helpers.Ast", "c": 0, "m": 0, "acc": {$: "Nil"}, "pend": {$: "Nil"}})));
}

function $$$$047helpers$ansilen$(_s_0) {
  const _x_0 = ($$$$047helpers$ansistrip$(_s_0));
  return [..._x_0].length;
}

function $$$$047helpers$ansipad$(_s_0, _w_0) {
  const _x_0 = ($$$$047helpers$ansilen$(_s_0));
  const _x_1 = ($$$$047helpers$pad$n$(_w_0, (_x_0 >>> 0)));
  const _x_2 = ($String$repeat$(" ", _x_1));
  return (_s_0 + _x_2);
}

function $$$$047helpers$make_tuple_rep$go$(_n_0, _x_0) {
  if (_n_0 === 0) {
    return {$: "Nil"};
  } else {
    const _p_0 = (_n_0 - 1);
    return {$: "Con", "head": _x_0, "tail": ($$$$047helpers$make_tuple_rep$go$(_p_0, _x_0))};
  }
}

function $$$$047helpers$make_tuple_rep$(_x_0, _cnt_0) {
  return $$$$047helpers$make_tuple_rep$go$(_cnt_0, _x_0);
}

function $$$$047helpers$make_tuple_of$(_x_0) {
  return {$: "Con", "head": _x_0, "tail": {$: "Nil"}};
}

function $$$$047helpers$to_tuple_u32$(_x_0) {
  return {$: "Con", "head": _x_0, "tail": {$: "Nil"}};
}

function $$$$047helpers$to_tuple_seq$(_xs_0) {
  return _xs_0;
}

function $$$$047helpers$fg_pairs$(_p_0) {
  if (_p_0.$ === "Con") {
    const _h_0 = _p_0["head"];
    const _t_0 = _p_0["tail"];
    if (_t_0.$ === "Con") {
      const _g_0 = _t_0["head"];
      const _r_0 = _t_0["tail"];
      return {$: "Con", "head": {$: "Con", "head": _h_0, "tail": {$: "Con", "head": _g_0, "tail": {$: "Nil"}}}, "tail": ($$$$047helpers$fg_pairs$(_r_0))};
    } else {
      return {$: "Nil"};
    }
  } else {
    return {$: "Nil"};
  }
}

function $$$$047helpers$fg_skip$($0, $1) {
  for (;;) {
    {
      const _n_0 = $0;
      const _xs_0 = $1;
      if (_n_0 === 0) {
        return _xs_0;
      } else {
        const _p_0 = (_n_0 - 1);
        if (_xs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _t_0 = _xs_0["tail"];
          $0 = _p_0;
          $1 = _t_0;
          continue;
        }
      }
    }
  }
}

function $$$$047helpers$flat_to_grouped$(_padding_0) {
  return $List$reverse$(($$$$047helpers$fg_pairs$(($$$$047helpers$fg_skip$(($Nat$mod$(($List$length$(_padding_0)), 2)), _padding_0)))));
}

function $$$$047helpers$resolve_pool_pads_int$go$(_n_0, _p_0) {
  if (_n_0 === 0) {
    return {$: "Nil"};
  } else {
    const _q_0 = (_n_0 - 1);
    return {$: "Con", "head": _p_0, "tail": ($$$$047helpers$resolve_pool_pads_int$go$(_q_0, _p_0))};
  }
}

function $$$$047helpers$resolve_pool_pads_int$(_p_0, _dims_0) {
  const _x_0 = (Math.imul(2, _dims_0) >>> 0);
  return $$$$047helpers$resolve_pool_pads_int$go$(_x_0, _p_0);
}

function $$$$047helpers$pool_pads_dup$go$($0, $1) {
  for (;;) {
    {
      const _ps_0 = $0;
      const _acc_0 = $1;
      if (_ps_0.$ === "Nil") {
        return $List$reverse$(_acc_0);
      } else {
        const _h_0 = _ps_0["head"];
        const _t_0 = _ps_0["tail"];
        $0 = _t_0;
        $1 = ($List$append$(_acc_0, {$: "Con", "head": _h_0, "tail": {$: "Con", "head": _h_0, "tail": {$: "Nil"}}}));
        continue;
      }
    }
  }
}

function $$$$047helpers$pool_pads_dup$(_p_0) {
  return $$$$047helpers$pool_pads_dup$go$(_p_0, {$: "Nil"});
}

function $$$$047helpers$resolve_pool_pads$pick$(_isdims_0, _p_0) {
  if (_isdims_0) {
    return {$: "Some", "value": ($$$$047helpers$pool_pads_dup$(_p_0))};
  } else {
    return {$: "None"};
  }
}

function $$$$047helpers$resolve_pool_pads$step$(_istwodims_0, _isdims_0, _p_0, _dims_0) {
  if (_istwodims_0) {
    return {$: "Some", "value": _p_0};
  } else {
    return $$$$047helpers$resolve_pool_pads$pick$(_isdims_0, _p_0);
  }
}

function $$$$047helpers$resolve_pool_pads$n$(_two_0, _dims_0, _p_0, _dims2_0) {
  return $$$$047helpers$resolve_pool_pads$step$(_two_0, _dims_0, _p_0, _dims2_0);
}

function $$$$047helpers$resolve_pool_pads$(_p_0, _dims_0) {
  const _x_0 = ($List$length$(_p_0));
  const _x_1 = (_x_0 >>> 0);
  const _x_2 = (Math.imul(2, _dims_0) >>> 0);
  const _x_3 = ($List$length$(_p_0));
  const _x_4 = (_x_3 >>> 0);
  return $$$$047helpers$resolve_pool_pads$n$((_x_1 === _x_2), (_x_4 === _dims_0), _p_0, _dims_0);
}

function $$$$047helpers$bal$next$step$(_c_0, _d_0) {
  if (_c_0 == 40) {
    return ((_d_0 + 1) >>> 0);
  } else if ((_c_0 & 1) == 0) {
    return _d_0;
  } else if (_c_0 == 41) {
    return ((_d_0 - 1) >>> 0);
  } else {
    return _d_0;
  }
}

function $$$$047helpers$bal$next$(_h_0, _d_0) {
  return $$$$047helpers$bal$next$step$(($Char$to_u32$(_h_0)), _d_0);
}

function $$$$047helpers$bal$under$(_nd_0) {
  return (_nd_0 >= 2147483648);
}

function $$$$047helpers$bal$depth$(_st_0) {
  const _d_0 = _st_0["d"];
  return _d_0;
}

function $$$$047helpers$bal$spilled$(_st_0) {
  const _under_0 = _st_0["under"];
  return _under_0;
}

function $$$$047helpers$bal$step$(_spilled_0, _nd_0) {
  if (_spilled_0) {
    return {$: "../helpers.Depth", "d": _nd_0, "under": true};
  } else {
    return {$: "../helpers.Depth", "d": _nd_0, "under": ($$$$047helpers$bal$under$(_nd_0))};
  }
}

function $$$$047helpers$bal$end$(_st_0) {
  const _d_0 = _st_0["d"];
  const _t_0 = _st_0["under"];
  if (_t_0) {
    return false;
  } else {
    return (_d_0 === 0);
  }
}

function $$$$047helpers$bal$walk$($0, $1) {
  for (;;) {
    {
      const _cs_0 = $0;
      const _st_0 = $1;
      if (_cs_0.$ === "Nil") {
        return $$$$047helpers$bal$end$(_st_0);
      } else {
        const _h_0 = _cs_0["head"];
        const _t_0 = _cs_0["tail"];
        $0 = _t_0;
        $1 = ($$$$047helpers$bal$step$(($$$$047helpers$bal$spilled$(_st_0)), ($$$$047helpers$bal$next$(_h_0, ($$$$047helpers$bal$depth$(_st_0))))));
        continue;
      }
    }
  }
}

function $$$$047helpers$is_balanced$(_s_0) {
  return $$$$047helpers$bal$walk$(($String$to_list$(_s_0)), {$: "../helpers.Depth", "d": 0, "under": false});
}

function $$$$047helpers$strip_parens$inner$(_fst_0) {
  const _x_0 = [..._fst_0].length;
  return $String$take$(($String$drop$(_fst_0, 1)), (_x_0 < 2 ? 0 : _x_0 - 2));
}

function $$$$047helpers$is_wrapped$both$(_starts_0, _ends_0, _fst_0) {
  if (_starts_0) {
    if (_ends_0) {
      return $$$$047helpers$is_balanced$(($$$$047helpers$strip_parens$inner$(_fst_0)));
    } else {
      return false;
    }
  } else {
    return false;
  }
}

function $$$$047helpers$is_wrapped$(_fst_0) {
  return $$$$047helpers$is_wrapped$both$(($String$starts_with$(_fst_0, "(")), ($String$ends_with$(_fst_0, ")")), _fst_0);
}

function $$$$047helpers$strip_parens$go$(_wrapped_0, _fst_0) {
  if (_wrapped_0) {
    return $$$$047helpers$strip_parens$inner$(_fst_0);
  } else {
    return _fst_0;
  }
}

function $$$$047helpers$strip_parens$(_fst_0) {
  return $$$$047helpers$strip_parens$go$(($$$$047helpers$is_wrapped$(_fst_0)), _fst_0);
}

function $$$$047helpers$i32_is_neg$(_x_0) {
  return (_x_0 >= 2147483648);
}

function $$$$047helpers$i32_neg$(_x_0) {
  return ((0 - _x_0) >>> 0);
}

function $$$$047helpers$asr$(_v_0, _n_0) {
  const _m_0 = (_n_0 < 31 ? _n_0 : 31);
  const _x_0 = ($$$$047helpers$i32_neg$((31 >= 32 ? 0 : (_v_0 >>> 31) >>> 0)));
  const _x_1 = (32 < _m_0 ? 0 : 32 - _m_0);
  const _x_2 = (_m_0 >= 32 ? 0 : (_v_0 >>> _m_0) >>> 0);
  const _x_3 = (_x_1 >= 32 ? 0 : (_x_0 << _x_1) >>> 0);
  return ((_x_2 | _x_3) >>> 0);
}

function $$$$047helpers$i32_abs$(_neg_0, _x_0) {
  if (_neg_0) {
    return $$$$047helpers$i32_neg$(_x_0);
  } else {
    return _x_0;
  }
}

function $$$$047helpers$cdiv_sign$(_x_0, _y_0) {
  const _x_1 = ($$$$047helpers$i32_is_neg$(_x_0));
  const _x_2 = ($$$$047helpers$i32_is_neg$(_y_0));
  return (_x_1 !== _x_2);
}

function $$$$047helpers$floordiv_i32$exact$(_ax_0, _ay_0) {
  const _x_0 = (_ay_0 === 0 ? _ax_0 : _ax_0 % _ay_0);
  return (_x_0 === 0);
}

function $$$$047helpers$floordiv_i32$trunc$put$(_neg_0, _q_0) {
  if (_neg_0) {
    return $$$$047helpers$i32_neg$(_q_0);
  } else {
    return _q_0;
  }
}

function $$$$047helpers$floordiv_i32$trunc$exact$(_exact_0, _neg_0, _q_0) {
  if (_exact_0) {
    return $$$$047helpers$floordiv_i32$trunc$put$(_neg_0, _q_0);
  } else {
    if (_neg_0) {
      return $$$$047helpers$floordiv_i32$trunc$put$(true, ((_q_0 + 1) >>> 0));
    } else {
      return _q_0;
    }
  }
}

function $$$$047helpers$floordiv_i32$trunc$(_neg_0, _exact_0, _q_0) {
  return $$$$047helpers$floordiv_i32$trunc$exact$(_exact_0, _neg_0, _q_0);
}

function $$$$047helpers$floordiv_i32$pick$(_zero_0, _neg_0, _exact_0, _ax_0, _ay_0) {
  if (_zero_0) {
    return 0;
  } else {
    return $$$$047helpers$floordiv_i32$trunc$(_neg_0, _exact_0, (_ay_0 === 0 ? 0 : (_ax_0 / _ay_0) >>> 0));
  }
}

function $$$$047helpers$floordiv_i32$(_x_0, _y_0) {
  return $$$$047helpers$floordiv_i32$pick$((_y_0 === 0), ($$$$047helpers$cdiv_sign$(_x_0, _y_0)), ($$$$047helpers$floordiv_i32$exact$(($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_x_0)), _x_0)), ($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_y_0)), _y_0)))), ($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_x_0)), _x_0)), ($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_y_0)), _y_0)));
}

function $$$$047helpers$cdiv_i32$put$(_neg_0, _q_0) {
  if (_neg_0) {
    return $$$$047helpers$i32_neg$(_q_0);
  } else {
    return _q_0;
  }
}

function $$$$047helpers$cdiv_i32$(_zero_0, _neg_0, _q_0) {
  if (_zero_0) {
    return 0;
  } else {
    return $$$$047helpers$cdiv_i32$put$(_neg_0, _q_0);
  }
}

function $$$$047helpers$cdiv_i32_go$(_x_0, _y_0) {
  const _x_1 = ($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_x_0)), _x_0));
  const _x_2 = ($$$$047helpers$i32_abs$(($$$$047helpers$i32_is_neg$(_y_0)), _y_0));
  return $$$$047helpers$cdiv_i32$((_y_0 === 0), ($$$$047helpers$cdiv_sign$(_x_0, _y_0)), (_x_2 === 0 ? 0 : (_x_1 / _x_2) >>> 0));
}

function $$$$047helpers$cmod_i32$(_x_0, _y_0) {
  const _x_1 = ($$$$047helpers$cdiv_i32_go$(_x_0, _y_0));
  const _x_2 = (Math.imul(_x_1, _y_0) >>> 0);
  return ((_x_0 - _x_2) >>> 0);
}

function $$$$047helpers$floormod_i32$(_x_0, _y_0) {
  const _x_1 = ($$$$047helpers$floordiv_i32$(_x_0, _y_0));
  const _x_2 = (Math.imul(_x_1, _y_0) >>> 0);
  return ((_x_0 - _x_2) >>> 0);
}

function $$$$047helpers$floordiv_u32$(_x_0, _y_0) {
  return (_y_0 === 0 ? 0 : (_x_0 / _y_0) >>> 0);
}

function $$$$047helpers$floormod_u32$(_x_0, _y_0) {
  const _x_1 = (_y_0 === 0 ? 0 : (_x_0 / _y_0) >>> 0);
  const _x_2 = (Math.imul(_x_1, _y_0) >>> 0);
  return ((_x_0 - _x_2) >>> 0);
}

function $$$$047helpers$cdiv_u32$(_x_0, _y_0) {
  return (_y_0 === 0 ? 0 : (_x_0 / _y_0) >>> 0);
}

function $$$$047helpers$cmod_u32$(_x_0, _y_0) {
  const _x_1 = ($$$$047helpers$cdiv_u32$(_x_0, _y_0));
  const _x_2 = (Math.imul(_x_1, _y_0) >>> 0);
  return ((_x_0 - _x_2) >>> 0);
}

function $$$$047helpers$ceildiv_i32$(_num_0, _amt_0) {
  return $$$$047helpers$i32_neg$(($$$$047helpers$floordiv_i32$(_num_0, ($$$$047helpers$i32_neg$(_amt_0)))));
}

function $$$$047helpers$div0$(_zero_0, _v_0) {
  if (_zero_0) {
    return 0;
  } else {
    return _v_0;
  }
}

function $$$$047helpers$ceildiv_u32$(_num_0, _amt_0) {
  const _x_0 = (_amt_0 === 0 ? _num_0 : _num_0 % _amt_0);
  const _x_1 = (_amt_0 === 0 ? 0 : (_num_0 / _amt_0) >>> 0);
  const _x_2 = ($Bool$to_u32$((_x_0 !== 0)));
  return $$$$047helpers$div0$((_amt_0 === 0), ((_x_1 + _x_2) >>> 0));
}

function $$$$047helpers$round_up_i32$(_num_0, _amt_0) {
  const _x_0 = ((_num_0 + _amt_0) >>> 0);
  const _x_1 = ($$$$047helpers$floordiv_i32$(((_x_0 + 4294967295) >>> 0), _amt_0));
  return (Math.imul(_x_1, _amt_0) >>> 0);
}

function $$$$047helpers$round_down_i32$(_num_0, _amt_0) {
  return $$$$047helpers$i32_neg$(($$$$047helpers$round_up_i32$(($$$$047helpers$i32_neg$(_num_0)), _amt_0)));
}

function $$$$047helpers$round_up_u32$(_num_0, _amt_0) {
  const _x_0 = ($$$$047helpers$ceildiv_u32$(_num_0, _amt_0));
  return (Math.imul(_x_0, _amt_0) >>> 0);
}

function $$$$047helpers$round_down_u32$(_num_0, _amt_0) {
  return $$$$047helpers$i32_neg$(($$$$047helpers$round_up_u32$(($$$$047helpers$i32_neg$(_num_0)), _amt_0)));
}

function $$$$047helpers$next_power2$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _k_0 = $0;
      const _lt_0 = $1;
      const _x_0 = $2;
      const _p_0 = $3;
      if (_k_0 === 0) {
        return _p_0;
      } else {
        const _q_0 = (_k_0 - 1);
        if (_lt_0) {
          const _x_1 = ((_p_0 + _p_0) >>> 0);
          $0 = _q_0;
          $1 = (_x_1 < _x_0);
          $2 = _x_0;
          $3 = ((_p_0 + _p_0) >>> 0);
          continue;
        } else {
          return _p_0;
        }
      }
    }
  }
}

function $$$$047helpers$next_power2$(_x_0) {
  return $$$$047helpers$next_power2$go$(33, (1 < _x_0), _x_0, 1);
}

function $$$$047helpers$match_hi$(_neg_0) {
  if (_neg_0) {
    return 4294967295;
  } else {
    return 0;
  }
}

function $$$$047helpers$i64_of_i32$(_x_0) {
  return {$: "../helpers.I64", "hi": ($$$$047helpers$match_hi$(($$$$047helpers$i32_is_neg$(_x_0)))), "lo": _x_0};
}

function $$$$047helpers$i64_of_hi_lo$(_hi_0, _lo_0) {
  return {$: "../helpers.I64", "hi": _hi_0, "lo": _lo_0};
}

function $$$$047helpers$lo32$(_x_0) {
  const _lo_0 = _x_0["lo"];
  return _lo_0;
}

function $$$$047helpers$hi32$(_x_0) {
  const _hi_0 = _x_0["hi"];
  return _hi_0;
}

function $$$$047helpers$i64_cmp$lt$(_lt_0) {
  if (_lt_0) {
    return {$: "LT"};
  } else {
    return {$: "GT"};
  }
}

function $$$$047helpers$i64_cmp$mag$(_eq_0, _lt_0, _eql_0, _ltl_0) {
  if (_eq_0) {
    if (_eql_0) {
      return {$: "EQ"};
    } else {
      return $$$$047helpers$i64_cmp$lt$(_ltl_0);
    }
  } else {
    return $$$$047helpers$i64_cmp$lt$(_lt_0);
  }
}

function $$$$047helpers$i64_cmp$sgn$(_an_0, _ah_0, _al_0, _bn_0, _bh_0, _bl_0) {
  if (_an_0) {
    if (!_bn_0) {
      return {$: "LT"};
    } else {
      return $$$$047helpers$i64_cmp$mag$((_ah_0 === _bh_0), (_ah_0 < _bh_0), (_al_0 === _bl_0), (_al_0 < _bl_0));
    }
  } else {
    if (_bn_0) {
      return {$: "GT"};
    } else {
      return $$$$047helpers$i64_cmp$mag$((_ah_0 === _bh_0), (_ah_0 < _bh_0), (_al_0 === _bl_0), (_al_0 < _bl_0));
    }
  }
}

function $$$$047helpers$i64_cmp$(_a_0, _b_0) {
  return $$$$047helpers$i64_cmp$sgn$(($$$$047helpers$i32_is_neg$(($$$$047helpers$hi32$(_a_0)))), ($$$$047helpers$hi32$(_a_0)), ($$$$047helpers$lo32$(_a_0)), ($$$$047helpers$i32_is_neg$(($$$$047helpers$hi32$(_b_0)))), ($$$$047helpers$hi32$(_b_0)), ($$$$047helpers$lo32$(_b_0)));
}

function $$$$047helpers$i64_is_neg$(_x_0) {
  return $$$$047helpers$i32_is_neg$(($$$$047helpers$hi32$(_x_0)));
}

function $$$$047helpers$i64_le$(_a_0, _b_0) {
  return $Cmp$is_le$(($$$$047helpers$i64_cmp$(_a_0, _b_0)));
}

function $$$$047helpers$i64_show$(_hi_0, _lo_0) {
  return $String$concat$({$: "Con", "head": ($U32$show$(_hi_0)), "tail": {$: "Con", "head": ":", "tail": {$: "Con", "head": ($U32$show$(_lo_0)), "tail": {$: "Nil"}}}});
}

function $$$$047helpers$i64_text$(_x_0) {
  return $$$$047helpers$i64_show$(($$$$047helpers$hi32$(_x_0)), ($$$$047helpers$lo32$(_x_0)));
}

function $$$$047helpers$i64_add$(_a_0, _b_0) {
  const _x_0 = ($$$$047helpers$lo32$(_a_0));
  const _x_1 = ($$$$047helpers$lo32$(_b_0));
  const _lo_0 = ((_x_0 + _x_1) >>> 0);
  const _x_2 = ($$$$047helpers$lo32$(_a_0));
  const _carry_0 = ($Bool$pick$((_lo_0 < _x_2), 1, 0));
  const _x_3 = ($$$$047helpers$hi32$(_a_0));
  const _x_4 = ($$$$047helpers$hi32$(_b_0));
  const _x_5 = ((_x_3 + _x_4) >>> 0);
  return $$$$047helpers$i64_of_hi_lo$(((_x_5 + _carry_0) >>> 0), _lo_0);
}

function $$$$047helpers$i64_sub$(_a_0, _b_0) {
  const _x_0 = ($$$$047helpers$lo32$(_a_0));
  const _x_1 = ($$$$047helpers$lo32$(_b_0));
  const _lo_0 = ((_x_0 - _x_1) >>> 0);
  const _x_2 = ($$$$047helpers$lo32$(_a_0));
  const _x_3 = ($$$$047helpers$lo32$(_b_0));
  const _borrow_0 = ($Bool$pick$((_x_2 < _x_3), 1, 0));
  const _x_4 = ($$$$047helpers$hi32$(_a_0));
  const _x_5 = ($$$$047helpers$hi32$(_b_0));
  const _x_6 = ((_x_4 - _x_5) >>> 0);
  return $$$$047helpers$i64_of_hi_lo$(((_x_6 - _borrow_0) >>> 0), _lo_0);
}

function $$$$047helpers$data64_hi$(_r_0) {
  const _hi_0 = _r_0["fst"];
  return _hi_0;
}

function $$$$047helpers$data64_lo$(_r_0) {
  const _lo_0 = _r_0["snd"];
  return _lo_0;
}

function $$$$047helpers$data64$(_x_0) {
  const _hi_0 = _x_0["hi"];
  const _lo_0 = _x_0["lo"];
  return {$: "Tuple", "fst": _hi_0, "snd": _lo_0};
}

function $$$$047helpers$data64_le$(_x_0) {
  const _hi_0 = _x_0["hi"];
  const _lo_0 = _x_0["lo"];
  return {$: "Tuple", "fst": _lo_0, "snd": _hi_0};
}

function $$$$047helpers$to_be32$(_val_0) {
  const _x_0 = ((_val_0 & 255) >>> 0);
  const _x_1 = (8 >= 32 ? 0 : (_val_0 >>> 8) >>> 0);
  const _x_2 = ((_x_1 & 255) >>> 0);
  const _x_3 = (24 >= 32 ? 0 : (_x_0 << 24) >>> 0);
  const _x_4 = (16 >= 32 ? 0 : (_x_2 << 16) >>> 0);
  const _x_5 = (16 >= 32 ? 0 : (_val_0 >>> 16) >>> 0);
  const _x_6 = ((_x_5 & 255) >>> 0);
  const _x_7 = (24 >= 32 ? 0 : (_val_0 >>> 24) >>> 0);
  const _x_8 = (8 >= 32 ? 0 : (_x_6 << 8) >>> 0);
  const _x_9 = ((_x_7 & 255) >>> 0);
  const _x_10 = ((_x_3 | _x_4) >>> 0);
  const _x_11 = ((_x_8 | _x_9) >>> 0);
  return ((_x_10 | _x_11) >>> 0);
}

function $$$$047helpers$to_be64$(_val_0) {
  const _hi_0 = _val_0["hi"];
  const _lo_0 = _val_0["lo"];
  return {$: "../helpers.I64", "hi": ($$$$047helpers$to_be32$(_lo_0)), "lo": ($$$$047helpers$to_be32$(_hi_0))};
}

function $$$$047helpers$bit_mask$(_w_0) {
  const _x_0 = (_w_0 >= 32 ? 0 : (1 << _w_0) >>> 0);
  return ((_x_0 - 1) >>> 0);
}

function $$$$047helpers$getbits$(_value_0, _start_0, _end_0) {
  const _x_0 = (_end_0 < _start_0 ? 0 : _end_0 - _start_0);
  const _x_1 = (_start_0 >= 32 ? 0 : (_value_0 >>> _start_0) >>> 0);
  const _x_2 = ($$$$047helpers$bit_mask$(nat_chk(_x_0 + 1)));
  return ((_x_1 & _x_2) >>> 0);
}

function $$$$047helpers$i2u$(_neg_0, _bits_0, _value_0) {
  if (_neg_0) {
    const _x_0 = (_bits_0 >= 32 ? 0 : (1 << _bits_0) >>> 0);
    return ((_x_0 + _value_0) >>> 0);
  } else {
    return _value_0;
  }
}

function $$$$047helpers$kv_key$(_kv_0) {
  const _k_0 = _kv_0["k"];
  return _k_0;
}

function $$$$047helpers$kv_val$(_kv_0) {
  const _v_0 = _kv_0["v"];
  return _v_0;
}

function $$$$047helpers$kv_find$hit$(_same_0, _kv_0) {
  if (_same_0) {
    return {$: "Some", "value": ($$$$047helpers$kv_val$(_kv_0))};
  } else {
    return {$: "None"};
  }
}

function $$$$047helpers$kv_find$pick$(_found_0, _same_0, _kv_0) {
  if (_found_0.$ === "Some") {
    const _v_0 = _found_0["value"];
    return {$: "Some", "value": _v_0};
  } else {
    return $$$$047helpers$kv_find$hit$(_same_0, _kv_0);
  }
}

function $$$$047helpers$kv_find$go$($0, $1, $2) {
  for (;;) {
    {
      const _l_0 = $0;
      const _k_0 = $1;
      const _found_0 = $2;
      if (_l_0.$ === "Nil") {
        return _found_0;
      } else {
        const _kv_0 = _l_0["head"];
        const _t_0 = _l_0["tail"];
        $0 = _t_0;
        $1 = _k_0;
        $2 = ($$$$047helpers$kv_find$pick$(_found_0, ($String$eq$(($$$$047helpers$kv_key$(_kv_0)), _k_0)), _kv_0));
        continue;
      }
    }
  }
}

function $$$$047helpers$kv_find$(_l_0, _k_0) {
  return $$$$047helpers$kv_find$go$(_l_0, _k_0, {$: "None"});
}

function $$$$047helpers$kv_conflict$pick$(_found_0, _kv_0) {
  if (_found_0.$ === "None") {
    return false;
  } else {
    const _v_0 = _found_0["value"];
    const _x_0 = ($$$$047helpers$kv_val$(_kv_0));
    return (_v_0 !== _x_0);
  }
}

function $$$$047helpers$kv_conflict$(_seen_0, _kv_0) {
  return $$$$047helpers$kv_conflict$pick$(($$$$047helpers$kv_find$(_seen_0, ($$$$047helpers$kv_key$(_kv_0)))), _kv_0);
}

function $$$$047helpers$merged_seen$(_m_0) {
  const _seen_0 = _m_0["seen"];
  return _seen_0;
}

function $$$$047helpers$merged_bad$(_m_0) {
  const _bad_0 = _m_0["bad"];
  return _bad_0;
}

function $$$$047helpers$merged_of$(_bad_0, _seen_0) {
  return {$: "../helpers.Merged", "bad": _bad_0, "seen": _seen_0};
}

function $$$$047helpers$merge_dicts$add$(_conflict_0, _kv_0, _m_0) {
  if (_conflict_0) {
    return $$$$047helpers$merged_of$(true, ($$$$047helpers$merged_seen$(_m_0)));
  } else {
    return $$$$047helpers$merged_of$(($$$$047helpers$merged_bad$(_m_0)), ($List$append$(($$$$047helpers$merged_seen$(_m_0)), {$: "Con", "head": _kv_0, "tail": {$: "Nil"}})));
  }
}

function $$$$047helpers$merge_dicts$go$($0, $1) {
  for (;;) {
    {
      const _l_0 = $0;
      const _m_0 = $1;
      if (_l_0.$ === "Nil") {
        return _m_0;
      } else {
        const _kv_0 = _l_0["head"];
        const _t_0 = _l_0["tail"];
        $0 = _t_0;
        $1 = ($$$$047helpers$merge_dicts$add$(($$$$047helpers$kv_conflict$(($$$$047helpers$merged_seen$(_m_0)), _kv_0)), _kv_0, _m_0));
        continue;
      }
    }
  }
}

function $$$$047helpers$merge_dicts$pick$(_m_0) {
  const _t_0 = _m_0["bad"];
  if (_t_0) {
    return {$: "None"};
  } else {
    const _seen_1 = _m_0["seen"];
    return {$: "Some", "value": _seen_1};
  }
}

function $$$$047helpers$merge_dicts$(_ds_0) {
  if (_ds_0.$ === "Nil") {
    return {$: "Some", "value": {$: "Nil"}};
  } else {
    const _d0_0 = _ds_0["head"];
    const _r_0 = _ds_0["tail"];
    return $$$$047helpers$merge_dicts$pick$(($$$$047helpers$merge_dicts$go$(($List$concat$(_r_0)), ($$$$047helpers$merged_of$(false, _d0_0)))));
  }
}

function $$$$047helpers$part_put$(_p_0, _keep_0, _h_0) {
  const _yes_0 = _p_0["yes"];
  const _no_0 = _p_0["no"];
  if (_keep_0) {
    return {$: "../helpers.Parted", "yes": {$: "Con", "head": _h_0, "tail": _yes_0}, "no": _no_0};
  } else {
    return {$: "../helpers.Parted", "yes": _yes_0, "no": {$: "Con", "head": _h_0, "tail": _no_0}};
  }
}

function $$$$047helpers$part_test$(_sel_0, _x_0) {
  if (_sel_0 == 0) {
    return (_x_0 > 0);
  } else if ((_sel_0 & 3) == 0) {
    return true;
  } else if (_sel_0 == 2) {
    return (_x_0 === 0);
  } else if ((_sel_0 & 3) == 2) {
    return true;
  } else if (_sel_0 == 1) {
    return (_x_0 < 0);
  } else if ((_sel_0 & 3) == 1) {
    return true;
  } else if (_sel_0 == 3) {
    return $U32$is_even$(_x_0);
  } else {
    return true;
  }
}

function $$$$047helpers$part_go$($0, $1, $2) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _sel_0 = $1;
      const _p_0 = $2;
      if (_xs_0.$ === "Nil") {
        return _p_0;
      } else {
        const _h_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        $0 = _t_0;
        $1 = _sel_0;
        $2 = ($$$$047helpers$part_put$(_p_0, ($$$$047helpers$part_test$(_sel_0, _h_0)), _h_0));
        continue;
      }
    }
  }
}

function $$$$047helpers$part_out$(_p_0) {
  const _yes_0 = _p_0["yes"];
  const _no_0 = _p_0["no"];
  return {$: "Tuple", "fst": _yes_0, "snd": _no_0};
}

function $$$$047helpers$part_yes$(_r_0) {
  const _a_0 = _r_0["fst"];
  return _a_0;
}

function $$$$047helpers$part_no$(_r_0) {
  const _b_0 = _r_0["snd"];
  return _b_0;
}

function $$$$047helpers$partition$(_sel_0, _itr_0) {
  return $$$$047helpers$part_out$(($$$$047helpers$part_go$(_itr_0, _sel_0, {$: "../helpers.Parted", "yes": {$: "Nil"}, "no": {$: "Nil"}})));
}

function $$$$047helpers$unwrap_or$(_m_0, _d_0) {
  if (_m_0.$ === "Some") {
    const _v_0 = _m_0["value"];
    return _v_0;
  } else {
    return _d_0;
  }
}

function $$$$047helpers$get_single$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "None"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    if (_t_0.$ === "Nil") {
      return {$: "Some", "value": _h_0};
    } else {
      return {$: "None"};
    }
  }
}

function $$$$047helpers$Timing$report$text$(_prefix_0, _st_0, _en_0) {
  const _x_0 = (_en_0 < _st_0 ? 0 : _en_0 - _st_0);
  const _x_1 = (_x_0 >>> 0);
  const _x_2 = Math.fround(_x_1);
  const _x_3 = ($$$$047helpers$pad_left$(($$$$047helpers$f32_fixed$(Math.fround(_x_2 / 1000000), 2)), 6));
  const _x_4 = (_prefix_0 + _x_3);
  return (_x_4 + " ms");
}

function $$$$047helpers$Timing$report$go$(_enabled_0, _s_0) {
  if (_enabled_0) {
    return (_x_0) => $IO$print$(_s_0, _x_0);
  } else {
    return run_clo((_x_1) => {
  return $IO$pure$({$: "Unit"}, _x_1);
});
  }
}

function $$$$047helpers$Timing$report$(_enabled_0, _prefix_0, _st_0, _en_0) {
  return $$$$047helpers$Timing$report$go$(_enabled_0, ($$$$047helpers$Timing$report$text$(_prefix_0, _st_0, _en_0)));
}

function $$$$047helpers$lines$done$(_f_0, _value_0) {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $File$close$(_f_0, _x_1), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$pure$(($String$lines$(_value_0)), _x_3);
});
}), _x_0);
});
}

function $$$$047helpers$lines$close$(_f_0) {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $File$close$(_f_0, _x_1), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$pure$({$: "Nil"}, _x_3);
});
}), _x_0);
});
}

function $$$$047helpers$lines$split$(_r_0) {
  const _f_0 = _r_0["fst"];
  const _t_0 = _r_0["snd"];
  if (_t_0.$ === "Done") {
    const _value_0 = _t_0["value"];
    return $$$$047helpers$lines$done$(_f_0, _value_0);
  } else {
    return $$$$047helpers$lines$close$(_f_0);
  }
}

function $$$$047helpers$lines$read$(_f_0, _max_0) {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $File$read$(_f_0, _max_0, _x_1), run_clo((_x_2) => {
  return $$$$047helpers$lines$split$(_x_2);
}), _x_0);
});
}

function $$$$047helpers$lines$go$(_r_0) {
  if (_r_0.$ === "Done") {
    const _value_0 = _r_0["value"];
    return $$$$047helpers$lines$read$(_value_0, 33554432);
  } else {
    return run_clo((_x_0) => {
  return $IO$pure$({$: "Nil"}, _x_0);
});
  }
}

function $$$$047helpers$lines$(_path_0) {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $File$open$(_path_0, "r", _x_1), run_clo((_x_2) => {
  return $$$$047helpers$lines$go$(_x_2);
}), _x_0);
});
}

function $$$$047helpers$printable$go$(_got_0) {
  if (_got_0.$ === "Some") {
    const _s_0 = _got_0["value"];
    return $String$trim$(_s_0);
  } else {
    return "<missing>";
  }
}

function $$$$047helpers$printable$pick$(_line_0, _ls_0) {
  return run_clo((_x_0) => {
  return $IO$bind$(_ls_0, run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$pure$(($$$$047helpers$printable$go$(($List$get$(_x_1, (_line_0 < 1 ? 0 : _line_0 - 1))))), _x_2);
});
}), _x_0);
});
}

function $$$$047helpers$printable$(_path_0, _line_0) {
  return $$$$047helpers$printable$pick$(_line_0, ($$$$047helpers$lines$(_path_0)));
}

function $OBJ_INSTANCE$() {
  return 0;
}

function $OBJ_ADAPTER$() {
  return 1;
}

function $OBJ_QUEUE$() {
  return 3;
}

function $OBJ_SHADER_MODULE$() {
  return 4;
}

function $OBJ_BIND_GROUP_LAYOUT$() {
  return 5;
}

function $OBJ_PIPELINE_LAYOUT$() {
  return 6;
}

function $OBJ_BIND_GROUP$() {
  return 7;
}

function $OBJ_COMPUTE_PIPELINE$() {
  return 8;
}

function $OBJ_COMMAND_ENCODER$() {
  return 9;
}

function $OBJ_COMPUTE_PASS$() {
  return 10;
}

function $OBJ_COMMAND_BUFFER$() {
  return 11;
}

function $OBJ_QUERY_SET$() {
  return 12;
}

function $OBJ_BUFFER$() {
  return 13;
}

function $CALL_CREATE$() {
  return 0;
}

function $CALL_WAIT$() {
  return 1;
}

function $CALL_RELEASE$() {
  return 2;
}

function $CALL_PUSH$() {
  return 3;
}

function $CALL_POP$() {
  return 4;
}

function $CALL_MAP_ASYNC$() {
  return 5;
}

function $CALL_MAPPED_RANGE$() {
  return 6;
}

function $CALL_WRITE$() {
  return 7;
}

function $CALL_COPY$() {
  return 8;
}

function $CALL_BEGIN$() {
  return 9;
}

function $CALL_SET_PIPELINE$() {
  return 10;
}

function $CALL_SET_BIND_GROUP$() {
  return 11;
}

function $CALL_DISPATCH$() {
  return 12;
}

function $CALL_END$() {
  return 13;
}

function $CALL_RESOLVE$() {
  return 14;
}

function $CALL_FINISH$() {
  return 15;
}

function $CALL_SUBMIT$() {
  return 16;
}

function $CALL_UNMAP$() {
  return 17;
}

function $CALL_DESTROY$() {
  return 18;
}

function $CALL_DESTROY_QUERY_SET$() {
  return 19;
}

function $CALL_GET_FEATURES$() {
  return 20;
}

function $CALL_FREE_FEATURES$() {
  return 21;
}

function $CALL_GET_LIMITS$() {
  return 22;
}

function $SYNC_MAP_ASYNC$() {
  return 1;
}

function $SYNC_POP_ERROR_SCOPE$() {
  return 2;
}

function $SYNC_CREATE_PIPELINE$() {
  return 3;
}

function $SYNC_REQUEST_ADAPTER$() {
  return 4;
}

function $SYNC_REQUEST_DEVICE$() {
  return 5;
}

function $SYNC_WORK_DONE$() {
  return 6;
}

function $SYNC_HAS_EMSG$() {
  return 1;
}

function $SYNC_NO_EMSG$() {
  return 2;
}

function $SYNC_NONE$() {
  return 0;
}

function $SYNC_ONE$() {
  return 1;
}

function $SYNC_MANY$() {
  return 2;
}

function $SYNC_MISSING$() {
  return "None";
}

function $BIND_UNIFORM$() {
  return 1;
}

function $BIND_STORAGE$() {
  return 2;
}

function $FILTER_VALIDATION$() {
  return 1;
}

function $MAP_UNMAPPED$() {
  return 1;
}

function $MAP_MAPPED$() {
  return 3;
}

function $FEATURE_TIMESTAMP_QUERY$() {
  return 3;
}

function $FEATURE_SHADER_F16$() {
  return 8;
}

function $USAGE_MAP_READ$() {
  return 1;
}

function $USAGE_COPY_SRC$() {
  return 4;
}

function $USAGE_COPY_DST$() {
  return 8;
}

function $USAGE_UNIFORM$() {
  return 64;
}

function $USAGE_STORAGE$() {
  return 128;
}

function $USAGE_QUERY_RESOLVE$() {
  return 512;
}

function $STATUS_SUCCESS$() {
  return 1;
}

function $BIND_GROUP_INDEX$() {
  return 0;
}

function $UNIFORM_SIZE$() {
  return 4;
}

function $QUERY_COUNT$() {
  return 2;
}

function $QUERY_BUF_SIZE$() {
  return 16;
}

function $Tr$of$() {
  return {$: "Tr", "calls": {$: "Nil"}, "next": 0, "depth": 0, "bad_at": 0, "popn": 0, "refused": false};
}

function $Tr$calls$(_t_0) {
  const _calls_0 = _t_0["calls"];
  return _calls_0;
}

function $Tr$next$(_t_0) {
  const _next_0 = _t_0["next"];
  return _next_0;
}

function $Tr$depth$(_t_0) {
  const _depth_0 = _t_0["depth"];
  return _depth_0;
}

function $Tr$refused$(_t_0) {
  const _refused_0 = _t_0["refused"];
  return _refused_0;
}

function $Tr$fail_at$(_t_0, _n_0) {
  const _calls_0 = _t_0["calls"];
  const _next_0 = _t_0["next"];
  const _depth_0 = _t_0["depth"];
  const _popn_0 = _t_0["popn"];
  const _refused_0 = _t_0["refused"];
  return {$: "Tr", "calls": _calls_0, "next": _next_0, "depth": _depth_0, "bad_at": _n_0, "popn": _popn_0, "refused": _refused_0};
}

function $Tr$reset$(_t_0) {
  const _bad_at_0 = _t_0["bad_at"];
  const _popn_0 = _t_0["popn"];
  return {$: "Tr", "calls": {$: "Nil"}, "next": 0, "depth": 0, "bad_at": _bad_at_0, "popn": _popn_0, "refused": false};
}

function $Tr$here$(_t_0) {
  return $Tr$next$(_t_0);
}

function $Tr$emit$go$(_refused_0, _k_0, _arg_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0) {
  return {$: "Tr", "calls": ($Bool$pick$(_refused_0, _calls_0, ($List$append$(_calls_0, {$: "Con", "head": {$: "Call", "k": _k_0, "arg": _arg_0}, "tail": {$: "Nil"}})))), "next": ($Bool$pick$(_refused_0, _next_0, ((_next_0 + 1) >>> 0))), "depth": _depth_0, "bad_at": _bad_at_0, "popn": _popn_0, "refused": _refused_0};
}

function $Tr$emit$(_k_0, _arg_0, _t_0) {
  const _calls_0 = _t_0["calls"];
  const _next_0 = _t_0["next"];
  const _depth_0 = _t_0["depth"];
  const _bad_at_0 = _t_0["bad_at"];
  const _popn_0 = _t_0["popn"];
  const _refused_0 = _t_0["refused"];
  return $Tr$emit$go$(_refused_0, _k_0, _arg_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0);
}

function $Tr$push$(_t_0) {
  const _calls_0 = _t_0["calls"];
  const _next_0 = _t_0["next"];
  const _depth_0 = _t_0["depth"];
  const _bad_at_0 = _t_0["bad_at"];
  const _popn_0 = _t_0["popn"];
  const _refused_0 = _t_0["refused"];
  return {$: "Tr", "calls": ($Bool$pick$(_refused_0, _calls_0, ($List$append$(_calls_0, {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Nil"}})))), "next": _next_0, "depth": ($Bool$pick$(_refused_0, _depth_0, ((_depth_0 + 1) >>> 0))), "bad_at": _bad_at_0, "popn": _popn_0, "refused": _refused_0};
}

function $Tr$pop$hit$(_bad_at_0, _popn_0, _refused_0) {
  const _x_0 = ((_popn_0 + 1) >>> 0);
  const _x_1 = (_x_0 === _bad_at_0);
  return (_refused_0 || _x_1);
}

function $Tr$pop$go$(_refused_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0) {
  return {$: "Tr", "calls": ($Bool$pick$(_refused_0, _calls_0, ($List$append$(_calls_0, {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Nil"}})))), "next": _next_0, "depth": ($Bool$pick$(_refused_0, _depth_0, ((_depth_0 - 1) >>> 0))), "bad_at": _bad_at_0, "popn": ($Bool$pick$(_refused_0, _popn_0, ((_popn_0 + 1) >>> 0))), "refused": ($Tr$pop$hit$(_bad_at_0, _popn_0, _refused_0))};
}

function $Tr$pop$(_t_0) {
  const _calls_0 = _t_0["calls"];
  const _next_0 = _t_0["next"];
  const _depth_0 = _t_0["depth"];
  const _bad_at_0 = _t_0["bad_at"];
  const _popn_0 = _t_0["popn"];
  const _refused_0 = _t_0["refused"];
  return $Tr$pop$go$(_refused_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0);
}

function $Call$k$(_c_0) {
  const _k_0 = _c_0["k"];
  return _k_0;
}

function $Call$arg$(_c_0) {
  const _arg_0 = _c_0["arg"];
  return _arg_0;
}

function $Tr$count$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _n_0 = $0;
      const _k_0 = $1;
      const _cs_0 = $2;
      const _got_0 = $3;
      if (_n_0 === 0) {
        return _got_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_cs_0.$ === "Nil") {
          return _got_0;
        } else {
          const _t_0 = _cs_0["head"];
          const _kk_0 = _t_0["k"];
          const _t_1 = _cs_0["tail"];
          const _x_0 = ($Bool$to_u32$((_kk_0 === _k_0)));
          $0 = _m_0;
          $1 = _k_0;
          $2 = _t_1;
          $3 = ((_got_0 + _x_0) >>> 0);
          continue;
        }
      }
    }
  }
}

function $Tr$count$(_k_0, _cs_0) {
  return $Tr$count$go$(($List$length$(_cs_0)), _k_0, _cs_0, 0);
}

function $Tr$args$put$(_c_0, _k_0, _acc_0) {
  const _x_0 = ($Call$k$(_c_0));
  return $Bool$pick$((_x_0 === _k_0), ($List$append$(_acc_0, {$: "Con", "head": ($Call$arg$(_c_0)), "tail": {$: "Nil"}})), _acc_0);
}

function $Tr$args$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _n_0 = $0;
      const _k_0 = $1;
      const _cs_0 = $2;
      const _acc_0 = $3;
      if (_n_0 === 0) {
        return _acc_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_cs_0.$ === "Nil") {
          return _acc_0;
        } else {
          const _t_0 = _cs_0["head"];
          const _kk_0 = _t_0["k"];
          const _aa_0 = _t_0["arg"];
          const _t_1 = _cs_0["tail"];
          $0 = _m_0;
          $1 = _k_0;
          $2 = _t_1;
          $3 = ($Tr$args$put$({$: "Call", "k": _kk_0, "arg": _aa_0}, _k_0, _acc_0));
          continue;
        }
      }
    }
  }
}

function $Tr$args$(_k_0, _cs_0) {
  return $Tr$args$go$(($List$length$(_cs_0)), _k_0, _cs_0, {$: "Nil"});
}

function $Tr$has$step$same2$(_k1_0, _k2_0, _a1_0, _a2_0) {
  return $Bool$and$((_k1_0 === _k2_0), (_a1_0 === _a2_0));
}

function $Tr$has$step$hit$(_same_0, _at_0) {
  if (_same_0) {
    return nat_chk(_at_0 + 1);
  } else {
    return _at_0;
  }
}

function $Tr$has$step$(_m_0, _c_0, _at_0) {
  if (_m_0.$ === "None") {
    return _at_0;
  } else {
    const _want_0 = _m_0["value"];
    return $Tr$has$step$hit$(($Tr$has$step$same2$(($Call$k$(_c_0)), ($Call$k$(_want_0)), ($Call$arg$(_c_0)), ($Call$arg$(_want_0)))), _at_0);
  }
}

function $Tr$has$go$($0, $1, $2, $3, $4) {
  for (;;) {
    {
      const _n_0 = $0;
      const _patlen_0 = $1;
      const _cs_0 = $2;
      const _pat_0 = $3;
      const _at_0 = $4;
      if (_n_0 === 0) {
        return $Nat$is_eq$(_at_0, _patlen_0);
      } else {
        const _m_0 = (_n_0 - 1);
        if (_cs_0.$ === "Nil") {
          return $Nat$is_eq$(_at_0, _patlen_0);
        } else {
          const _t_0 = _cs_0["head"];
          const _kk_0 = _t_0["k"];
          const _aa_0 = _t_0["arg"];
          const _t_1 = _cs_0["tail"];
          $0 = _m_0;
          $1 = _patlen_0;
          $2 = _t_1;
          $3 = _pat_0;
          $4 = ($Tr$has$step$(($List$get$(_pat_0, _at_0)), {$: "Call", "k": _kk_0, "arg": _aa_0}, _at_0));
          continue;
        }
      }
    }
  }
}

function $Tr$has$(_cs_0, _pat_0) {
  return $Tr$has$go$(($List$length$(_cs_0)), ($List$length$(_pat_0)), _cs_0, _pat_0, 0);
}

function $u32_list_eq$(_a_0, _b_0) {
  const _x_0 = ($List$length$(_a_0));
  const _x_1 = ($List$length$(_b_0));
  const _x_2 = (_x_0 >>> 0);
  const _x_3 = (_x_1 >>> 0);
  return $Bool$and$((_x_2 === _x_3), ($$$$047helpers$u32_list_eq$(_a_0, _b_0)));
}

function $str_eq$go$($0, $1, $2) {
  for (;;) {
    {
      const _a_0 = $0;
      const _b_0 = $1;
      const _bad_0 = $2;
      if (_a_0.$ === "Nil") {
        return $Bool$not$(_bad_0);
      } else {
        const _x_0 = _a_0["head"];
        const _t_0 = _a_0["tail"];
        if (_b_0.$ === "Nil") {
          return false;
        } else {
          const _y_0 = _b_0["head"];
          const _u_0 = _b_0["tail"];
          const _x_1 = ($Bool$not$(($String$eq$(_x_0, _y_0))));
          $0 = _t_0;
          $1 = _u_0;
          $2 = (_bad_0 || _x_1);
          continue;
        }
      }
    }
  }
}

function $backend_names$() {
  return {$: "Con", "head": "WGPUBackendType_Undefined", "tail": {$: "Con", "head": "WGPUBackendType_Null", "tail": {$: "Con", "head": "WGPUBackendType_WebGPU", "tail": {$: "Con", "head": "WGPUBackendType_D3D11", "tail": {$: "Con", "head": "WGPUBackendType_D3D12", "tail": {$: "Con", "head": "WGPUBackendType_Metal", "tail": {$: "Con", "head": "WGPUBackendType_Vulkan", "tail": {$: "Con", "head": "WGPUBackendType_OpenGL", "tail": {$: "Con", "head": "WGPUBackendType_OpenGLES", "tail": {$: "Nil"}}}}}}}}}};
}

function $backend_of$put$(_s_0, _h_0, _at_0, _got_0) {
  return $Bool$pick$(($String$eq$(_h_0, _s_0)), _at_0, _got_0);
}

function $backend_of$go$($0, $1, $2, $3, $4) {
  for (;;) {
    {
      const _n_0 = $0;
      const _s_0 = $1;
      const _ns_0 = $2;
      const _at_0 = $3;
      const _got_0 = $4;
      if (_n_0 === 0) {
        return _got_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_ns_0.$ === "Nil") {
          return _got_0;
        } else {
          const _h_0 = _ns_0["head"];
          const _t_0 = _ns_0["tail"];
          $0 = _m_0;
          $1 = _s_0;
          $2 = _t_0;
          $3 = ((_at_0 + 1) >>> 0);
          $4 = ($backend_of$put$(_s_0, _h_0, _at_0, _got_0));
          continue;
        }
      }
    }
  }
}

function $backend_of$(_s_0) {
  return $backend_of$go$(($List$length$(($backend_names$()))), _s_0, ($backend_names$()), 0, 0);
}

function $sync_ret$(_n_0) {
  return TAB_0[Math.min(_n_0, 2)];
}

function $sync_has_emsg$(_which_0) {
  const _x_0 = ($SYNC_POP_ERROR_SCOPE$());
  return $Bool$pick$((_which_0 === _x_0), ($SYNC_NO_EMSG$()), ($SYNC_HAS_EMSG$()));
}

function $sync_payload$(_nargs_0, _has_emsg_0) {
  const _x_0 = ($SYNC_NO_EMSG$());
  return $Bool$pick$((_has_emsg_0 === _x_0), nat_chk(_nargs_0 + 1), _nargs_0);
}

function $sync_name$map_async2$() {
  return "WGPUBufferMapAsyncStatus_InstanceDropped";
}

function $sync_name$pop2$() {
  return "WGPUPopErrorScopeStatus_InstanceDropped";
}

function $sync_name$pipeline2$() {
  return "WGPUCreatePipelineAsyncStatus_InstanceDropped";
}

function $sync_name$adapter2$() {
  return "WGPURequestAdapterStatus_InstanceDropped";
}

function $sync_name$device2$() {
  return "WGPURequestDeviceStatus_InstanceDropped";
}

function $sync_name$workdone2$() {
  return "WGPUQueueWorkDoneStatus_InstanceDropped";
}

function $sync_name$two$at$(_which_0) {
  if (_which_0 === 0) {
    return $sync_name$workdone2$();
  } else if (_which_0 === 1) {
    return $sync_name$map_async2$();
  } else if (_which_0 === 2) {
    return $sync_name$pop2$();
  } else if (_which_0 === 3) {
    return $sync_name$pipeline2$();
  } else if (_which_0 === 4) {
    return $sync_name$adapter2$();
  } else if (_which_0 === 5) {
    return $sync_name$device2$();
  } else {
    return $sync_name$workdone2$();
  }
}

function $sync_name$two$(_which_0) {
  return $sync_name$two$at$(_which_0);
}

function $sync_name$map_async3$() {
  return "WGPUBufferMapAsyncStatus_ValidationError";
}

function $sync_name$pop3$() {
  return $SYNC_MISSING$();
}

function $sync_name$pipeline3$() {
  return "WGPUCreatePipelineAsyncStatus_ValidationError";
}

function $sync_name$adapter3$() {
  return "WGPURequestAdapterStatus_Unavailable";
}

function $sync_name$device3$() {
  return "WGPURequestDeviceStatus_Error";
}

function $sync_name$workdone3$() {
  return "WGPUQueueWorkDoneStatus_Error";
}

function $sync_name$three$at$(_which_0) {
  if (_which_0 === 0) {
    return $sync_name$workdone3$();
  } else if (_which_0 === 1) {
    return $sync_name$map_async3$();
  } else if (_which_0 === 2) {
    return $sync_name$pop3$();
  } else if (_which_0 === 3) {
    return $sync_name$pipeline3$();
  } else if (_which_0 === 4) {
    return $sync_name$adapter3$();
  } else if (_which_0 === 5) {
    return $sync_name$device3$();
  } else {
    return $sync_name$workdone3$();
  }
}

function $sync_name$three$(_which_0) {
  return $sync_name$three$at$(_which_0);
}

function $UNDER$() {
  return $Char$from_u32$(95);
}

function $sync_us$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _n_0 = $0;
      const _pos_0 = $1;
      const _at_0 = $2;
      const _cs_0 = $3;
      if (_n_0 === 0) {
        return _at_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_cs_0.$ === "Nil") {
          return _at_0;
        } else {
          const _h_0 = _cs_0["head"];
          const _t_0 = _cs_0["tail"];
          $0 = _m_0;
          $1 = ((_pos_0 + 1) >>> 0);
          $2 = ($Bool$pick$(($Char$is_eq$(_h_0, ($UNDER$()))), ((_pos_0 + 1) >>> 0), _at_0));
          $3 = _t_0;
          continue;
        }
      }
    }
  }
}

function $sync_us$at$(_n_0, _cs_0) {
  return $sync_us$go$(_n_0, 0, 0, _cs_0);
}

function $sync_us$(_cs_0) {
  return $sync_us$at$(($List$length$(_cs_0)), _cs_0);
}

function $sync_tail$(_s_0) {
  const _x_0 = ($sync_us$(($String$to_list$(_s_0))));
  return $String$drop$(_s_0, _x_0);
}

function $sync_name$six2$() {
  return {$: "Con", "head": ($sync_tail$(($sync_name$two$(1)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(2)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(3)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(4)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(5)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(6)))), "tail": {$: "Nil"}}}}}}};
}

function $sync_name$six3$() {
  return {$: "Con", "head": ($sync_tail$(($sync_name$three$(1)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(2)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(3)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(4)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(5)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(6)))), "tail": {$: "Nil"}}}}}}};
}

function $sync_name$of$err$(_which_0, _status_0) {
  return $Bool$pick$((_status_0 === 2), ($sync_name$two$(_which_0)), ($sync_name$three$(_which_0)));
}

function $sync_name$of$(_which_0, _status_0) {
  const _x_0 = ($STATUS_SUCCESS$());
  return $Bool$pick$((_status_0 === _x_0), "Success", ($sync_name$of$err$(_which_0, _status_0)));
}

function $sync_error$(_which_0, _status_0, _emsg_0) {
  const _x_0 = ($STATUS_SUCCESS$());
  return $Bool$pick$((_status_0 === _x_0), "", ($String$concat$({$: "Con", "head": "[", "tail": {$: "Con", "head": ($sync_name$of$(_which_0, _status_0)), "tail": {$: "Con", "head": "]", "tail": {$: "Con", "head": _emsg_0, "tail": {$: "Nil"}}}}})));
}

function $Dev$at$(_d_0, _t_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": _t_0};
}

function $Dev$tr$(_d_0) {
  const _t_0 = _d_0["t"];
  return _t_0;
}

function $Dev$instance$(_d_0) {
  const _instance_0 = _d_0["instance"];
  return _instance_0;
}

function $Dev$adapter$(_d_0) {
  const _adapter_0 = _d_0["adapter"];
  return _adapter_0;
}

function $Dev$device_res$(_d_0) {
  const _device_res_0 = _d_0["device_res"];
  return _device_res_0;
}

function $Dev$queue$(_d_0) {
  const _queue_0 = _d_0["queue"];
  return _queue_0;
}

function $Dev$features$(_d_0) {
  const _features_0 = _d_0["features"];
  return _features_0;
}

function $Dev$backend$(_d_0) {
  const _backend_0 = _d_0["backend"];
  return _backend_0;
}

function $Dev$nrequired$(_d_0) {
  const _nrequired_0 = _d_0["nrequired"];
  return _nrequired_0;
}

function $Dev$arch$(_d_0) {
  const _arch_0 = _d_0["arch"];
  return _arch_0;
}

function $dev$create_instance$() {
  return {$: "Dev", "instance": ($Tr$here$(($Tr$of$()))), "adapter": 0, "device_res": 0, "queue": 0, "features": {$: "Nil"}, "backend": 0, "nrequired": 0, "arch": "", "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_INSTANCE$()), ($Tr$of$())))};
}

function $dev$request_adapter$(_d_0, _backend_name_0) {
  const _instance_0 = _d_0["instance"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": ($Tr$here$(_t_0)), "device_res": 0, "queue": 0, "features": {$: "Nil"}, "backend": ($backend_of$(_backend_name_0)), "nrequired": 0, "arch": "", "t": ($Tr$emit$(($CALL_WAIT$()), ($SYNC_REQUEST_ADAPTER$()), _t_0))};
}

function $keeps_feature$(_f_0) {
  const _x_0 = ($FEATURE_TIMESTAMP_QUERY$());
  const _x_1 = ($FEATURE_SHADER_F16$());
  const _x_2 = (_f_0 === _x_0);
  const _x_3 = (_f_0 === _x_1);
  return (_x_2 || _x_3);
}

function $features_keep$put$(_x_0, _acc_0) {
  return $Bool$pick$(($keeps_feature$(_x_0)), ($List$append$(_acc_0, {$: "Con", "head": _x_0, "tail": {$: "Nil"}})), _acc_0);
}

function $features_keep$go$($0, $1, $2) {
  for (;;) {
    {
      const _n_0 = $0;
      const _fs_0 = $1;
      const _acc_0 = $2;
      if (_n_0 === 0) {
        return _acc_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_fs_0.$ === "Nil") {
          return _acc_0;
        } else {
          const _x_0 = _fs_0["head"];
          const _t_0 = _fs_0["tail"];
          $0 = _m_0;
          $1 = _t_0;
          $2 = ($features_keep$put$(_x_0, _acc_0));
          continue;
        }
      }
    }
  }
}

function $features_of$(_fs_0) {
  return $features_keep$go$(($List$length$(_fs_0)), _fs_0, {$: "Nil"});
}

function $dev$get_features$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_GET_FEATURES$()), 0, _t_0))};
}

function $dev$features_keep$(_d_0, _fs_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": ($features_of$(_fs_0)), "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_FREE_FEATURES$()), 0, _t_0))};
}

function $dev$get_limits$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_GET_LIMITS$()), 0, _t_0))};
}

function $dev$arch_of$(_fs_0) {
  return $Bool$pick$(($List$contains$1260$(_fs_0, ($FEATURE_SHADER_F16$()))), "shader-f16", "");
}

function $dev$derive$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _t_0 = _d_0["t"];
  const _x_0 = ($List$length$(_features_0));
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": _features_0, "backend": _backend_0, "nrequired": (_x_0 >>> 0), "arch": ($dev$arch_of$(_features_0)), "t": _t_0};
}

function $dev$request_device$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": ($Tr$here$(_t_0)), "queue": 0, "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_WAIT$()), ($SYNC_REQUEST_DEVICE$()), _t_0))};
}

function $dev$get_queue$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": ($Tr$here$(_t_0)), "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_QUEUE$()), _t_0))};
}

function $dev$adapter_release$(_d_0) {
  const _instance_0 = _d_0["instance"];
  const _adapter_0 = _d_0["adapter"];
  const _device_res_0 = _d_0["device_res"];
  const _queue_0 = _d_0["queue"];
  const _features_0 = _d_0["features"];
  const _backend_0 = _d_0["backend"];
  const _nrequired_0 = _d_0["nrequired"];
  const _arch_0 = _d_0["arch"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": _adapter_0, "device_res": _device_res_0, "queue": _queue_0, "features": _features_0, "backend": _backend_0, "nrequired": _nrequired_0, "arch": _arch_0, "t": ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_ADAPTER$()), _t_0))};
}

function $dev$init$(_backend_name_0, _feats_0) {
  const _d1_0 = ($dev$request_adapter$(($dev$create_instance$()), _backend_name_0));
  const _d2_0 = ($dev$get_features$(_d1_0));
  const _d3_0 = ($dev$features_keep$(_d2_0, _feats_0));
  const _d4_0 = ($dev$get_limits$(_d3_0));
  const _d5_0 = ($dev$derive$(_d4_0));
  const _d6_0 = ($dev$request_device$(_d5_0));
  const _d7_0 = ($dev$get_queue$(_d6_0));
  return $dev$adapter_release$(_d7_0);
}

function $dev$free$at$(_mapped_0, _id_0, _t_0) {
  if (_mapped_0) {
    return $Tr$emit$(($CALL_RELEASE$()), _id_0, ($Tr$emit$(($CALL_DESTROY$()), _id_0, ($Tr$emit$(($CALL_UNMAP$()), _id_0, _t_0)))));
  } else {
    return $Tr$emit$(($CALL_RELEASE$()), _id_0, ($Tr$emit$(($CALL_DESTROY$()), _id_0, _t_0)));
  }
}

function $dev$free$(_map_state_0, _id_0, _t_0) {
  const _x_0 = ($MAP_MAPPED$());
  return $dev$free$at$((_map_state_0 === _x_0), _id_0, _t_0);
}

function $dev$uniform_usage$() {
  const _x_0 = ($USAGE_UNIFORM$());
  const _x_1 = ($USAGE_COPY_DST$());
  return ((_x_0 | _x_1) >>> 0);
}

function $dev$uniform_bytes$go$($0, $1, $2) {
  for (;;) {
    {
      const _n_0 = $0;
      const _v_0 = $1;
      const _acc_0 = $2;
      if (_n_0 === 0) {
        return $List$reverse$(_acc_0);
      } else {
        const _m_0 = (_n_0 - 1);
        $0 = _m_0;
        $1 = (1 >= 32 ? 0 : (_v_0 >>> 1) >>> 0);
        $2 = {$: "Con", "head": ((_v_0 & 255) >>> 0), "tail": _acc_0};
        continue;
      }
    }
  }
}

function $dev$uniform_bytes$(_v_0) {
  return $dev$uniform_bytes$go$(4, _v_0, {$: "Nil"});
}

function $Buf$size$(_b_0) {
  const _size_0 = _b_0["size"];
  return _size_0;
}

function $Made$buf$(_m_0) {
  const _buf_0 = _m_0["buf"];
  return _buf_0;
}

function $Made$tr$(_m_0) {
  const _t_0 = _m_0["t"];
  return _t_0;
}

function $copy$write$(_bytes_0, _t_0) {
  const _x_0 = ($List$length$(_bytes_0));
  return $Tr$emit$(($CALL_WRITE$()), (_x_0 >>> 0), _t_0);
}

function $dev$create_uniform$(_bytes_0, _t_0) {
  const _x_0 = ($List$length$(_bytes_0));
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": (_x_0 >>> 0)}, "t": ($copy$write$(_bytes_0, ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))))};
}

function $alloc$usage$() {
  const _x_0 = ($USAGE_STORAGE$());
  const _x_1 = ($USAGE_COPY_DST$());
  const _x_2 = ((_x_0 | _x_1) >>> 0);
  const _x_3 = ($USAGE_COPY_SRC$());
  return ((_x_2 | _x_3) >>> 0);
}

function $alloc$size$(_nbytes_0) {
  return $$$$047helpers$round_up_u32$(_nbytes_0, 4);
}

function $alloc$of$(_size_0, _t_0) {
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": ($alloc$size$(_size_0))}, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))};
}

function $copy$write_len$(_nbytes_0) {
  return $$$$047helpers$round_up_u32$(_nbytes_0, 4);
}

function $copy$pad$(_nbytes_0) {
  const _x_0 = ($copy$write_len$(_nbytes_0));
  return ((_x_0 - _nbytes_0) >>> 0);
}

function $copy$copyin$(_nbytes_0, _t_0) {
  return $Tr$emit$(($CALL_WRITE$()), ($copy$write_len$(_nbytes_0)), _t_0);
}

function $copy$readable_usage$() {
  const _x_0 = ($USAGE_COPY_DST$());
  const _x_1 = ($USAGE_MAP_READ$());
  return ((_x_0 | _x_1) >>> 0);
}

function $copy$readable$(_size_0, _t_0) {
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": _size_0}, "t": ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_ENCODER$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_BUFFER$()), ($Tr$emit$(($CALL_SUBMIT$()), 1, ($Tr$emit$(($CALL_FINISH$()), 1, ($Tr$emit$(($CALL_COPY$()), _size_0, ($Tr$emit$(($CALL_CREATE$()), ($OBJ_COMMAND_ENCODER$()), ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))))))))))))))};
}

function $copy$read$(_usage_0, _size_0, _t_0) {
  return $Tr$emit$(($CALL_MAPPED_RANGE$()), _size_0, ($Tr$emit$(($CALL_MAP_ASYNC$()), _usage_0, ($Tr$emit$(($CALL_WAIT$()), ($SYNC_MAP_ASYNC$()), _t_0)))));
}

function $copy$read_made$(_usage_0, _size_0, _m_0) {
  return {$: "Made", "buf": ($Made$buf$(_m_0)), "t": ($copy$read$(_usage_0, _size_0, ($Made$tr$(_m_0))))};
}

function $Pass$of$(_entry_0, _feats_0) {
  return {$: "Pass", "module": 0, "entry": _entry_0, "feats": _feats_0, "ls": 0, "nentries": 0, "sizes": {$: "Nil"}, "gx": 1, "gy": 1, "gz": 1, "wait": false, "t": ($Tr$of$())};
}

function $Pass$tr$(_p_0) {
  const _t_0 = _p_0["t"];
  return _t_0;
}

function $Pass$ls$(_p_0) {
  const _ls_0 = _p_0["ls"];
  return _ls_0;
}

function $Pass$nentries$(_p_0) {
  const _nentries_0 = _p_0["nentries"];
  return _nentries_0;
}

function $Pass$sizes$(_p_0) {
  const _sizes_0 = _p_0["sizes"];
  return _sizes_0;
}

function $Pass$gx$(_p_0) {
  const _gx_0 = _p_0["gx"];
  return _gx_0;
}

function $Pass$wait$(_p_0) {
  const _wait_0 = _p_0["wait"];
  return _wait_0;
}

function $Pass$reset$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$reset$(_t_0))};
}

function $prog$wants_wait$(_want_0, _feats_0) {
  return $Bool$and$(_want_0, ($List$contains$1260$(_feats_0, ($FEATURE_TIMESTAMP_QUERY$()))));
}

function $prog$init$(_entry_0, _d_0) {
  const _features_0 = _d_0["features"];
  const _t_0 = _d_0["t"];
  return {$: "Pass", "module": ($Tr$here$(_t_0)), "entry": _entry_0, "feats": _features_0, "ls": 0, "nentries": 0, "sizes": {$: "Nil"}, "gx": 1, "gy": 1, "gz": 1, "wait": false, "t": ($Tr$pop$(($Tr$emit$(($CALL_CREATE$()), ($OBJ_SHADER_MODULE$()), ($Tr$push$(_t_0))))))};
}

function $bgl$entry$put$(_i_0, _nbufs_0, _acc_0) {
  return {$: "Con", "head": {$: "Bgl", "binding": ((_i_0 + 1) >>> 0), "ty": ($Bool$pick$((_i_0 >= _nbufs_0), ($BIND_UNIFORM$()), ($BIND_STORAGE$())))}, "tail": _acc_0};
}

function $bgl$of$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _n_0 = $0;
      const _i_0 = $1;
      const _nbufs_0 = $2;
      const _acc_0 = $3;
      if (_n_0 === 0) {
        return $List$reverse$(_acc_0);
      } else {
        const _m_0 = (_n_0 - 1);
        $0 = _m_0;
        $1 = ((_i_0 + 1) >>> 0);
        $2 = _nbufs_0;
        $3 = ($bgl$entry$put$(_i_0, _nbufs_0, _acc_0));
        continue;
      }
    }
  }
}

function $bgl$of$(_nbufs_0, _nvals_0) {
  const _x_0 = ((_nbufs_0 + _nvals_0) >>> 0);
  return $List$append$({$: "Con", "head": {$: "Bgl", "binding": 0, "ty": ($BIND_UNIFORM$())}, "tail": {$: "Nil"}}, ($bgl$of$go$(_x_0, 0, _nbufs_0, {$: "Nil"})));
}

function $bgl$flat$($0, $1) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _acc_0 = $1;
      if (_xs_0.$ === "Nil") {
        return _acc_0;
      } else {
        const _t_0 = _xs_0["head"];
        const _b_0 = _t_0["binding"];
        const _ty_0 = _t_0["ty"];
        const _t_1 = _xs_0["tail"];
        $0 = _t_1;
        $1 = ($List$append$(($List$append$(_acc_0, {$: "Con", "head": _b_0, "tail": {$: "Nil"}})), {$: "Con", "head": _ty_0, "tail": {$: "Nil"}}));
        continue;
      }
    }
  }
}

function $slots$vals$($0, $1) {
  for (;;) {
    {
      const _n_0 = $0;
      const _acc_0 = $1;
      if (_n_0 === 0) {
        return _acc_0;
      } else {
        const _m_0 = (_n_0 - 1);
        $0 = _m_0;
        $1 = ($List$append$(_acc_0, {$: "Con", "head": {$: "Slot", "is_buf": false, "size": ($UNIFORM_SIZE$())}, "tail": {$: "Nil"}}));
        continue;
      }
    }
  }
}

function $slots$bufs$($0, $1, $2) {
  for (;;) {
    {
      const _n_0 = $0;
      const _bs_0 = $1;
      const _acc_0 = $2;
      if (_n_0 === 0) {
        return _acc_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_bs_0.$ === "Nil") {
          return _acc_0;
        } else {
          const _t_0 = _bs_0["head"];
          const _sz_0 = _t_0["size"];
          const _t_1 = _bs_0["tail"];
          $0 = _m_0;
          $1 = _t_1;
          $2 = ($List$append$(_acc_0, {$: "Con", "head": {$: "Slot", "is_buf": true, "size": _sz_0}, "tail": {$: "Nil"}}));
          continue;
        }
      }
    }
  }
}

function $slots$(_bs_0, _nvals_0) {
  return $slots$vals$(_nvals_0, ($slots$bufs$(($List$length$(_bs_0)), _bs_0, {$: "Con", "head": {$: "Slot", "is_buf": false, "size": ($UNIFORM_SIZE$())}, "tail": {$: "Nil"}})));
}

function $pass$geometry$(_p_0, _gx_0, _gy_0, _gz_0, _local_0, _want_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _t2_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _local_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": ($prog$wants_wait$(_want_0, _feats_0)), "t": _t2_0};
}

function $pass$layout$(_nbufs_0, _nvals_0, _p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  const _x_0 = ($List$length$(($bgl$of$(_nbufs_0, _nvals_0))));
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": (_x_0 >>> 0), "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$pop$(($Tr$emit$(($CALL_CREATE$()), ($OBJ_BIND_GROUP_LAYOUT$()), ($Tr$push$(_t_0))))))};
}

function $pass$playout$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$pop$(($Tr$emit$(($CALL_CREATE$()), ($OBJ_PIPELINE_LAYOUT$()), ($Tr$push$(_t_0))))))};
}

function $pass$uniforms$put$(_p_0, _is_buf_0, _sz_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  if (_is_buf_0) {
    return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": ($List$append$(_sizes_0, {$: "Con", "head": _sz_0, "tail": {$: "Nil"}})), "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": _t_0};
  } else {
    return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": ($List$append$(_sizes_0, {$: "Con", "head": ($UNIFORM_SIZE$()), "tail": {$: "Nil"}})), "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))};
  }
}

function $pass$uniforms$go$($0, $1, $2) {
  for (;;) {
    {
      const _n_0 = $0;
      const _p_0 = $1;
      const _ss_0 = $2;
      if (_n_0 === 0) {
        return _p_0;
      } else {
        const _m_0 = (_n_0 - 1);
        if (_ss_0.$ === "Nil") {
          return _p_0;
        } else {
          const _t_0 = _ss_0["head"];
          const _is_buf_0 = _t_0["is_buf"];
          const _size_0 = _t_0["size"];
          const _t_1 = _ss_0["tail"];
          $0 = _m_0;
          $1 = ($pass$uniforms$put$(_p_0, _is_buf_0, _size_0));
          $2 = _t_1;
          continue;
        }
      }
    }
  }
}

function $pass$uniforms$(_bs_0, _nvals_0, _p_0) {
  const _x_0 = ($List$length$(_bs_0));
  const _x_1 = nat_chk(1 + _x_0);
  return $pass$uniforms$go$(nat_chk(_x_1 + _nvals_0), _p_0, ($slots$(_bs_0, _nvals_0)));
}

function $pass$group$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$pop$(($Tr$emit$(($CALL_CREATE$()), ($OBJ_BIND_GROUP$()), ($Tr$push$(_t_0))))))};
}

function $pass$pipeline$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_WAIT$()), ($SYNC_CREATE_PIPELINE$()), _t_0))};
}

function $pass$encoder$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_COMMAND_ENCODER$()), _t_0))};
}

function $pass$query$on$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), ($Tr$emit$(($CALL_CREATE$()), ($OBJ_QUERY_SET$()), _t_0))))};
}

function $pass$query$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$query$on$(_p_0);
  }
}

function $pass$query$(_p_0) {
  return $pass$query$at$(($Pass$wait$(_p_0)), _p_0);
}

function $pass$begin$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_BEGIN$()), 0, _t_0))};
}

function $pass$set$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_SET_BIND_GROUP$()), ($BIND_GROUP_INDEX$()), ($Tr$emit$(($CALL_SET_PIPELINE$()), 0, _t_0))))};
}

function $pass$dispatch$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_DISPATCH$()), _gx_0, _t_0))};
}

function $pass$end$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_END$()), 0, _t_0))};
}

function $pass$resolve$on$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_RESOLVE$()), ($QUERY_COUNT$()), _t_0))};
}

function $pass$resolve$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$resolve$on$(_p_0);
  }
}

function $pass$resolve$(_p_0) {
  return $pass$resolve$at$(($Pass$wait$(_p_0)), _p_0);
}

function $pass$finish$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_SUBMIT$()), 1, ($Tr$emit$(($CALL_FINISH$()), 1, _t_0))))};
}

function $pass$release$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_BUFFER$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMPUTE_PASS$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_ENCODER$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMPUTE_PIPELINE$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_BIND_GROUP$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_PIPELINE_LAYOUT$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_BIND_GROUP_LAYOUT$()), _t_0))))))))))))))};
}

function $pass$timing$on$(_p_0) {
  const _module_0 = _p_0["module"];
  const _entry_0 = _p_0["entry"];
  const _feats_0 = _p_0["feats"];
  const _ls_0 = _p_0["ls"];
  const _nentries_0 = _p_0["nentries"];
  const _sizes_0 = _p_0["sizes"];
  const _gx_0 = _p_0["gx"];
  const _gy_0 = _p_0["gy"];
  const _gz_0 = _p_0["gz"];
  const _wait_0 = _p_0["wait"];
  const _t_0 = _p_0["t"];
  const _t1_0 = ($copy$read_made$(($copy$readable_usage$()), ($QUERY_BUF_SIZE$()), ($copy$readable$(($QUERY_BUF_SIZE$()), _t_0))));
  const _t2_0 = ($dev$free$(($MAP_UNMAPPED$()), ($OBJ_BUFFER$()), ($Made$tr$(_t1_0))));
  const _t3_0 = ($dev$free$(($MAP_UNMAPPED$()), ($OBJ_BUFFER$()), _t2_0));
  return {$: "Pass", "module": _module_0, "entry": _entry_0, "feats": _feats_0, "ls": _ls_0, "nentries": _nentries_0, "sizes": _sizes_0, "gx": _gx_0, "gy": _gy_0, "gz": _gz_0, "wait": _wait_0, "t": ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_QUERY_SET$()), ($Tr$emit$(($CALL_DESTROY_QUERY_SET$()), ($OBJ_QUERY_SET$()), _t3_0))))};
}

function $pass$timing$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$timing$on$(_p_0);
  }
}

function $pass$timing$(_p_0) {
  return $pass$timing$at$(($Pass$wait$(_p_0)), _p_0);
}

function $prog$call$at$(_bs_0, _nvals_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0, _p0_0) {
  const _p1_0 = ($pass$geometry$(_p0_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0));
  const _x_0 = ($List$length$(_bs_0));
  const _p2_0 = ($pass$layout$((_x_0 >>> 0), _nvals_0, _p1_0));
  const _p3_0 = ($pass$playout$(_p2_0));
  const _p4_0 = ($pass$uniforms$(_bs_0, _nvals_0, _p3_0));
  const _p5_0 = ($pass$group$(_p4_0));
  const _p6_0 = ($pass$pipeline$(_p5_0));
  const _p7_0 = ($pass$encoder$(_p6_0));
  const _p8_0 = ($pass$query$(_p7_0));
  const _p9_0 = ($pass$begin$(_p8_0));
  const _pa_0 = ($pass$set$(_p9_0));
  const _pb_0 = ($pass$dispatch$(_pa_0));
  const _pc_0 = ($pass$end$(_pb_0));
  const _pd_0 = ($pass$resolve$(_pc_0));
  const _pe_0 = ($pass$finish$(_pd_0));
  const _pf_0 = ($pass$release$(_pe_0));
  return $pass$timing$(_pf_0);
}

function $prog$call$(_bs_0, _nvals_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0, _p_0) {
  return $prog$call$at$(_bs_0, _nvals_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0, _p_0);
}

function $METAL$() {
  return "WGPUBackendType_Metal";
}

function $TS$() {
  return {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Nil"}};
}

function $F16$() {
  return {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Nil"}};
}

function $BOTH$() {
  return {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Nil"}}};
}

function $NEITHER$() {
  return {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Nil"}}};
}

function $REVERSED$() {
  return {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Nil"}}};
}

function $bufs$go$($0, $1, $2, $3) {
  for (;;) {
    {
      const _n_0 = $0;
      const _id_0 = $1;
      const _szs_0 = $2;
      const _acc_0 = $3;
      if (_n_0 === 0) {
        return $List$reverse$(_acc_0);
      } else {
        const _m_0 = (_n_0 - 1);
        if (_szs_0.$ === "Nil") {
          return $List$reverse$(_acc_0);
        } else {
          const _s_0 = _szs_0["head"];
          const _t_0 = _szs_0["tail"];
          $0 = _m_0;
          $1 = ((_id_0 + 1) >>> 0);
          $2 = _t_0;
          $3 = {$: "Con", "head": {$: "Buf", "id": _id_0, "size": _s_0}, "tail": _acc_0};
          continue;
        }
      }
    }
  }
}

function $bufs3$() {
  return $bufs$go$(3, 100, {$: "Con", "head": 64, "tail": {$: "Con", "head": 64, "tail": {$: "Con", "head": 64, "tail": {$: "Nil"}}}}, {$: "Nil"});
}

function $fx_pass$(_feats_0) {
  return $prog$init$("k", ($dev$init$(($METAL$()), _feats_0)));
}

function $fx_fail$at$(_d_0, _bad_at_0) {
  return $Dev$at$(_d_0, ($Tr$fail_at$(($Dev$tr$(_d_0)), _bad_at_0)));
}

function $fx_fail$(_feats_0, _bad_at_0) {
  return $prog$init$("k", ($fx_fail$at$(($dev$init$(($METAL$()), _feats_0)), _bad_at_0)));
}

function $fx_call$(_feats_0, _want_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, _want_0, ($Pass$reset$(($fx_pass$(_feats_0)))));
}

function $fx_life$(_feats_0, _want_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, _want_0, ($fx_pass$(_feats_0)));
}

function $fx_refuse$(_bad_at_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, false, ($fx_fail$(($BOTH$()), _bad_at_0)));
}

function $created$(_t_0) {
  return $Tr$args$(($CALL_CREATE$()), ($Tr$calls$(_t_0)));
}

function $released$(_t_0) {
  return $Tr$args$(($CALL_RELEASE$()), ($Tr$calls$(_t_0)));
}

function $waited$(_t_0) {
  return $Tr$args$(($CALL_WAIT$()), ($Tr$calls$(_t_0)));
}

function $dispatched$(_t_0) {
  return $Tr$args$(($CALL_DISPATCH$()), ($Tr$calls$(_t_0)));
}

function $grouped$(_t_0) {
  return $Tr$args$(($CALL_SET_BIND_GROUP$()), ($Tr$calls$(_t_0)));
}

function $written$(_t_0) {
  return $Tr$args$(($CALL_WRITE$()), ($Tr$calls$(_t_0)));
}

function $ncalls$(_k_0, _t_0) {
  return $Tr$count$(_k_0, ($Tr$calls$(_t_0)));
}

function $ncreated$(_t_0) {
  const _x_0 = ($List$length$(($created$(_t_0))));
  return (_x_0 >>> 0);
}

function $seen$(_t_0) {
  const _x_0 = ($List$length$(($Tr$calls$(_t_0))));
  return (_x_0 >>> 0);
}

function $seq$(_t_0, _pat_0) {
  return $Tr$has$(($Tr$calls$(_t_0)), _pat_0);
}

function $row$(_nm_0, _b_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($Bool$show$(_b_0)), "tail": {$: "Nil"}}}})), _x_0);
}

function $urow$(_nm_0, _v_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($U32$show$(_v_0)), "tail": {$: "Nil"}}}})), _x_0);
}

function $srow$(_nm_0, _v_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": _v_0, "tail": {$: "Nil"}}}})), _x_0);
}

function $ush$($0, $1, $2) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _sep_0 = $1;
      const _acc_0 = $2;
      if (_xs_0.$ === "Nil") {
        return $List$reverse$(_acc_0);
      } else {
        const _x_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        $0 = _t_0;
        $1 = _sep_0;
        $2 = {$: "Con", "head": ($U32$show$(_x_0)), "tail": _acc_0};
        continue;
      }
    }
  }
}

function $lrow$(_nm_0, _xs_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($String$join$(($ush$(_xs_0, ",", {$: "Nil"})), ",")), "tail": {$: "Nil"}}}})), _x_0);
}

function $String$starts_with$($0, $1, $2) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      const _p_0 = $1;
      if (_s_0 === "") {
        if (_p_0 === "") {
          return true;
        } else {
          return false;
        }
      } else {
        const _h_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        if (_p_0 === "") {
          return true;
        } else {
          const _y_0 = (_p_0.codePointAt(0) > 0xFFFF ? _p_0.slice(0, 2) : _p_0[0]);
          const _yt_0 = (_p_0.codePointAt(0) > 0xFFFF ? _p_0.slice(2) : _p_0.slice(1));
          $0 = _t_1;
          $1 = _yt_0;
          $2 = ($Char$is_eq$(_h_1, _y_0));
          $pc = 1; continue;
        }
      }
    }
    case 1: {
      const _t_0 = $0;
      const _pt_0 = $1;
      const _same_0 = $2;
      if (!_same_0) {
        return false;
      } else {
        $0 = _t_0;
        $1 = _pt_0;
        $pc = 0; continue;
      }
    }
  }
}

function $String$to_list$(_s_0) {
  if (_s_0 === "") {
    return {$: "Nil"};
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    return {$: "Con", "head": _h_0, "tail": ($String$to_list$(_t_0))};
  }
}

function $String$drop$($0, $1) {
  for (;;) {
    {
      const _s_0 = $0;
      const _n_0 = $1;
      if (_s_0 === "") {
        return "";
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        if (_n_0 === 0) {
          return (_h_0 + _t_0);
        } else {
          const _p_0 = (_n_0 - 1);
          $0 = _t_0;
          $1 = _p_0;
          continue;
        }
      }
    }
  }
}

function $String$trim$(_s_0) {
  return $String$trim_end$(($String$trim_start$(_s_0)));
}

function $Char$is_digit$(_c_0) {
  const _x_0 = _c_0.codePointAt(0);
  const _x_1 = _c_0.codePointAt(0);
  return $Bool$and$((_x_0 >= 48), (_x_1 <= 57));
}

function $Char$to_u32$(_c_0) {
  return _c_0.codePointAt(0);
}

function $Bool$and$(_a_0, _b_0) {
  if (!_a_0) {
    return false;
  } else {
    return _b_0;
  }
}

function $IO$bind$(_m_0, _f_0, _k_0) {
  return run_tail(_m_0, run_clo((_x_0) => {
  return run_tail(_f_0(_x_0), _k_0);
}));
}

function $IO$get_env$(_name_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.get_env"].run, need: $0eff["IO.get_env"].need, args: [(_name_0)], kont: (_k_0) };
}
function $IO$pure$(_x_0, _k_0) {
  return run_tail(_k_0, _x_0);
}

function $List$contains$1260$(_xs_0, _x_0) {
  if (_xs_0.$ === "Nil") {
    return false;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_1 = (_h_0 === _x_0);
    const _x_2 = ($List$contains$1260$(_t_0, _x_0));
    return (_x_1 || _x_2);
  }
}

function $List$contains$1261$(_xs_0, _x_0) {
  if (_xs_0.$ === "Nil") {
    return false;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_1 = ($String$eq$(_h_0, _x_0));
    const _x_2 = ($List$contains$1261$(_t_0, _x_0));
    return (_x_1 || _x_2);
  }
}

function $List$sort$1260$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _ys_0 = {$: "Con", "head": _h_0, "tail": _t_0};
    const _n_0 = ($List$length$(_ys_0));
    return $List$sort$go$1260$(_n_0, _n_0, ($List$sort$runs$(_ys_0)));
  }
}

function $String$eq$(_a_0, _b_0) {
  return $Cmp$is_eq$(($String$order$(_a_0, _b_0)));
}

function $Bool$not$(_b_0) {
  if (!_b_0) {
    return true;
  } else {
    return false;
  }
}

function $List$length$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _xs_0["tail"];
    return nat_chk(($List$length$(_t_0)) + 1);
  }
}

function $List$append$(_xs_0, _ys_0) {
  if (_xs_0.$ === "Nil") {
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": ($List$append$(_t_0, _ys_0))};
  }
}

function $List$last$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "None"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Some", "value": ($List$last$go$(_t_0, _h_0))};
  }
}

function $List$reverse$(_xs_0) {
  return $List$reverse$go$(_xs_0, {$: "Nil"});
}

function $List$concat$(_xss_0) {
  if (_xss_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xss_0["head"];
    const _t_0 = _xss_0["tail"];
    return $List$append$(_h_0, ($List$concat$(_t_0)));
  }
}

function $Char$from_u32$(_x_0) {
  return char_new(_x_0);
}

function $String$from_list$(_cs_0) {
  if (_cs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _cs_0["head"];
    const _t_0 = _cs_0["tail"];
    return (_h_0 + ($String$from_list$(_t_0)));
  }
}

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
}

function $String$repeat$(_s_0, _n_0) {
  if (_n_0 === 0) {
    return "";
  } else {
    const _p_0 = (_n_0 - 1);
    const _x_0 = ($String$repeat$(_s_0, _p_0));
    return (_s_0 + _x_0);
  }
}

function $Bool$to_u32$(_b_0) {
  if (!_b_0) {
    return 0;
  } else {
    return 1;
  }
}

function $Nat$mod$(_a_0, _b_0) {
  return $Pair$snd$(nat_divmod(_a_0, _b_0));
}

function $String$take$(_s_0, _n_0) {
  if (_s_0 === "") {
    return "";
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    if (_n_0 === 0) {
      return "";
    } else {
      const _p_0 = (_n_0 - 1);
      return (_h_0 + ($String$take$(_t_0, _p_0)));
    }
  }
}

function $String$ends_with$(_s_0, _p_0) {
  return $String$starts_with$(($String$reverse$(_s_0)), ($String$reverse$(_p_0)));
}

function $Cmp$is_le$(_c_0) {
  if (_c_0.$ === "GT") {
    return false;
  } else {
    return true;
  }
}

function $String$concat$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($String$concat$(_t_0));
    return (_h_0 + _x_0);
  }
}

function $Bool$pick$(_c_0, _a_0, _b_0) {
  if (!_c_0) {
    return _b_0;
  } else {
    return _a_0;
  }
}

function $U32$is_even$(_a_0) {
  const _x_0 = ((_a_0 & 1) >>> 0);
  return (_x_0 === 0);
}

function $IO$print$(_text_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.print"].run, need: $0eff["IO.print"].need, args: [(_text_0)], kont: (_k_0) };
}
function $File$close$(_file_0, _k_0) {
  return { $: "$FFI", run: $0eff["File.close"].run, need: $0eff["File.close"].need, args: [(_file_0)], kont: (_k_0) };
}
function $String$lines$(_s_0) {
  return $String$split$(_s_0, "\n");
}

function $File$read$(_file_0, _max_0, _k_0) {
  return { $: "$FFI", run: $0eff["File.read"].run, need: $0eff["File.read"].need, args: [(_file_0), (_max_0)], kont: (_k_0) };
}
function $File$open$(_path_0, _mode_0, _k_0) {
  return { $: "$FFI", run: $0eff["File.open"].run, need: $0eff["File.open"].need, args: [(_path_0), (_mode_0)], kont: (_k_0) };
}
function $List$get$($0, $1) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _n_0 = $1;
      if (_xs_0.$ === "Nil") {
        return {$: "None"};
      } else {
        const _h_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        if (_n_0 === 0) {
          return {$: "Some", "value": _h_0};
        } else {
          const _p_0 = (_n_0 - 1);
          $0 = _t_0;
          $1 = _p_0;
          continue;
        }
      }
    }
  }
}

function $Nat$is_eq$(_a_0, _b_0) {
  return $Cmp$is_eq$(cmp_new(_a_0, _b_0));
}

function $Char$is_eq$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return (_x_0 === _x_1);
}

function $Bool$show$(_b_0) {
  if (!_b_0) {
    return "False";
  } else {
    return "True";
  }
}

function $String$join$(_xs_0, _sep_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return $String$join$go$(_t_0, _h_0, _sep_0);
  }
}

function $String$starts_with$if$($0, $1, $2) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      const _p_0 = $1;
      if (_s_0 === "") {
        if (_p_0 === "") {
          return true;
        } else {
          return false;
        }
      } else {
        const _h_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        if (_p_0 === "") {
          return true;
        } else {
          const _y_0 = (_p_0.codePointAt(0) > 0xFFFF ? _p_0.slice(0, 2) : _p_0[0]);
          const _yt_0 = (_p_0.codePointAt(0) > 0xFFFF ? _p_0.slice(2) : _p_0.slice(1));
          $0 = _t_1;
          $1 = _yt_0;
          $2 = ($Char$is_eq$(_h_1, _y_0));
          $pc = 1; continue;
        }
      }
    }
    case 1: {
      const _t_0 = $0;
      const _pt_0 = $1;
      const _same_0 = $2;
      if (!_same_0) {
        return false;
      } else {
        $0 = _t_0;
        $1 = _pt_0;
        $pc = 0; continue;
      }
    }
  }
}

function $String$trim_end$(_s_0) {
  return $String$reverse$(($String$trim_start$(($String$reverse$(_s_0)))));
}

function $String$trim_start$($0, $1, $2) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      if (_s_0 === "") {
        return "";
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        $0 = _t_0;
        $1 = _h_0;
        $2 = ($Char$is_space$(_h_0));
        $pc = 1; continue;
      }
    }
    case 1: {
      const _t_0 = $0;
      const _h_0 = $1;
      const _space_0 = $2;
      if (!_space_0) {
        return (_h_0 + _t_0);
      } else {
        $0 = _t_0;
        $pc = 0; continue;
      }
    }
  }
}

function $List$sort$go$1260$($0, $1, $2) {
  for (;;) {
    {
      const _fuel_0 = $0;
      const _n_0 = $1;
      const _runs_0 = $2;
      if (_fuel_0 === 0) {
        return $List$concat$(_runs_0);
      } else {
        const _f_0 = (_fuel_0 - 1);
        if (_runs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _r_0 = _runs_0["head"];
          const _t_0 = _runs_0["tail"];
          if (_t_0.$ === "Nil") {
            return _r_0;
          } else {
            const _r2_0 = _t_0["head"];
            const _rest_0 = _t_0["tail"];
            $0 = _f_0;
            $1 = _n_0;
            $2 = ($List$sort$pass$1260$(_n_0, {$: "Con", "head": _r_0, "tail": {$: "Con", "head": _r2_0, "tail": _rest_0}}));
            continue;
          }
        }
      }
    }
  }
}

function $List$sort$runs$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": {$: "Con", "head": _h_0, "tail": {$: "Nil"}}, "tail": ($List$sort$runs$(_t_0))};
  }
}

function $Cmp$is_eq$(_c_0) {
  if (_c_0.$ === "EQ") {
    return true;
  } else {
    return false;
  }
}

function $String$order$(_a_0, _b_0) {
  return $Pair$snd$(($String$cmp$(_a_0, _b_0)));
}

function $List$last$go$($0, $1) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _last_0 = $1;
      if (_xs_0.$ === "Nil") {
        return _last_0;
      } else {
        const _h_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        $0 = _t_0;
        $1 = _h_0;
        continue;
      }
    }
  }
}

function $List$reverse$go$($0, $1) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _acc_0 = $1;
      if (_xs_0.$ === "Nil") {
        return _acc_0;
      } else {
        const _h_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        $0 = _t_0;
        $1 = {$: "Con", "head": _h_0, "tail": _acc_0};
        continue;
      }
    }
  }
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
  }
}

function $Pair$snd$(_p_0) {
  const _b_0 = _p_0["snd"];
  return _b_0;
}

function $String$reverse$(_s_0) {
  return $String$reverse$go$(_s_0, "");
}

function $String$split$(_s_0, _sep_0) {
  if (_s_0 === "") {
    return {$: "Con", "head": "", "tail": {$: "Nil"}};
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    return $String$split$fin$(_h_0, ($String$split$(_t_0, _sep_0)), ($Char$is_eq$(_h_0, _sep_0)));
  }
}

function $String$join$go$(_xs_0, _h_0, _sep_0) {
  if (_xs_0.$ === "Nil") {
    return _h_0;
  } else {
    const _h2_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($String$join$go$(_t_0, _h2_0, _sep_0));
    const _x_1 = (_sep_0 + _x_0);
    return (_h_0 + _x_1);
  }
}

function $String$trim_start$if$($0, $1, $2) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      if (_s_0 === "") {
        return "";
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        $0 = _t_0;
        $1 = _h_0;
        $2 = ($Char$is_space$(_h_0));
        $pc = 1; continue;
      }
    }
    case 1: {
      const _t_0 = $0;
      const _h_0 = $1;
      const _space_0 = $2;
      if (!_space_0) {
        return (_h_0 + _t_0);
      } else {
        $0 = _t_0;
        $pc = 0; continue;
      }
    }
  }
}

function $Char$is_space$(_c_0) {
  const _x_0 = _c_0.codePointAt(0);
  const _x_1 = _c_0.codePointAt(0);
  const _x_2 = _c_0.codePointAt(0);
  const _x_3 = (_x_0 === 32);
  const _x_4 = ($Bool$and$((_x_1 >= 9), (_x_2 <= 13)));
  return (_x_3 || _x_4);
}

function $List$sort$pass$1260$(_n_0, _runs_0) {
  if (_runs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _r_0 = _runs_0["head"];
    const _t_0 = _runs_0["tail"];
    if (_t_0.$ === "Nil") {
      return {$: "Con", "head": _r_0, "tail": {$: "Nil"}};
    } else {
      const _r2_0 = _t_0["head"];
      const _rest_0 = _t_0["tail"];
      return {$: "Con", "head": ($List$merge$go$1260$(_n_0, {$: "Tuple", "fst": {$: "Nil"}, "snd": {$: "Tuple", "fst": _r_0, "snd": _r2_0}})), "tail": ($List$sort$pass$1260$(_n_0, _rest_0))};
    }
  }
}

function $String$cmp$(_a_0, _b_0) {
  if (_a_0 === "") {
    if (_b_0 === "") {
      return {$: "Tuple", "fst": {$: "Tuple", "fst": "", "snd": ""}, "snd": {$: "EQ"}};
    } else {
      const _h_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(0, 2) : _b_0[0]);
      const _t_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(2) : _b_0.slice(1));
      return {$: "Tuple", "fst": {$: "Tuple", "fst": "", "snd": (_h_0 + _t_0)}, "snd": {$: "LT"}};
    }
  } else {
    const _h_1 = (_a_0.codePointAt(0) > 0xFFFF ? _a_0.slice(0, 2) : _a_0[0]);
    const _t_1 = (_a_0.codePointAt(0) > 0xFFFF ? _a_0.slice(2) : _a_0.slice(1));
    if (_b_0 === "") {
      return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h_1 + _t_1), "snd": ""}, "snd": {$: "GT"}};
    } else {
      const _h2_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(0, 2) : _b_0[0]);
      const _t2_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(2) : _b_0.slice(1));
      return $String$cmp$fin$(_t_1, _t2_0, ($Char$cmp$(_h_1, _h2_0)));
    }
  }
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

function $String$reverse$go$($0, $1) {
  for (;;) {
    {
      const _s_0 = $0;
      const _acc_0 = $1;
      if (_s_0 === "") {
        return _acc_0;
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        $0 = _t_0;
        $1 = (_h_0 + _acc_0);
        continue;
      }
    }
  }
}

function $String$split$fin$(_c_0, _r_0, _cut_0) {
  if (!_cut_0) {
    return $String$split$push$(_c_0, _r_0);
  } else {
    return {$: "Con", "head": "", "tail": _r_0};
  }
}

function $List$merge$go$1260$($0, $1) {
  for (;;) {
    {
      const _fuel_0 = $0;
      const _st_0 = $1;
      if (_fuel_0 === 0) {
        const _acc_0 = _st_0["fst"];
        const _t_0 = _st_0["snd"];
        const _xs_0 = _t_0["fst"];
        const _ys_0 = _t_0["snd"];
        return $List$reverse$go$(_acc_0, ($List$append$(_xs_0, _ys_0)));
      } else {
        const _f_0 = (_fuel_0 - 1);
        const _acc_1 = _st_0["fst"];
        const _t_1 = _st_0["snd"];
        const _t_2 = _t_1["fst"];
        if (_t_2.$ === "Nil") {
          const _t_3 = _t_1["snd"];
          if (_t_3.$ === "Nil") {
            return $List$reverse$go$(_acc_1, {$: "Nil"});
          } else {
            const _y_0 = _t_3["head"];
            const _yt_0 = _t_3["tail"];
            return $List$reverse$go$(_acc_1, {$: "Con", "head": _y_0, "tail": _yt_0});
          }
        } else {
          const _x_0 = _t_2["head"];
          const _xt_0 = _t_2["tail"];
          const _t_4 = _t_1["snd"];
          if (_t_4.$ === "Nil") {
            return $List$reverse$go$(_acc_1, {$: "Con", "head": _x_0, "tail": _xt_0});
          } else {
            const _y_1 = _t_4["head"];
            const _yt_1 = _t_4["tail"];
            $0 = _f_0;
            $1 = ($List$merge$step$(_acc_1, _x_0, _xt_0, _y_1, _yt_1, ($$$$047helpers$ix_le$(_x_0, _y_1))));
            continue;
          }
        }
      }
    }
  }
}

function $String$cmp$fin$(_t1_0, _t2_0, _hc_0) {
  const _t_0 = _hc_0["fst"];
  const _h1b_0 = _t_0["fst"];
  const _h2b_0 = _t_0["snd"];
  const _t_1 = _hc_0["snd"];
  if (_t_1.$ === "LT") {
    return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1_0), "snd": (_h2b_0 + _t2_0)}, "snd": {$: "LT"}};
  } else if (_t_1.$ === "EQ") {
    return $String$cmp$rec$(_h1b_0, _h2b_0, ($String$cmp$(_t1_0, _t2_0)));
  } else {
    return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1_0), "snd": (_h2b_0 + _t2_0)}, "snd": {$: "GT"}};
  }
}

function $Char$cmp$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return {$: "Tuple", "fst": {$: "Tuple", "fst": _a_0, "snd": _b_0}, "snd": cmp_new(_x_0, _x_1)};
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

function $String$split$push$(_c_0, _ps_0) {
  if (_ps_0.$ === "Nil") {
    return {$: "Con", "head": (_c_0 + ""), "tail": {$: "Nil"}};
  } else {
    const _h_0 = _ps_0["head"];
    const _t_0 = _ps_0["tail"];
    return {$: "Con", "head": (_c_0 + _h_0), "tail": _t_0};
  }
}

function $List$merge$step$(_acc_0, _x_0, _xt_0, _y_0, _yt_0, _le_0) {
  if (!_le_0) {
    return {$: "Tuple", "fst": {$: "Con", "head": _y_0, "tail": _acc_0}, "snd": {$: "Tuple", "fst": {$: "Con", "head": _x_0, "tail": _xt_0}, "snd": _yt_0}};
  } else {
    return {$: "Tuple", "fst": {$: "Con", "head": _x_0, "tail": _acc_0}, "snd": {$: "Tuple", "fst": _xt_0, "snd": {$: "Con", "head": _y_0, "tail": _yt_0}}};
  }
}

function $String$cmp$rec$(_h1b_0, _h2b_0, _rr_0) {
  const _t_0 = _rr_0["fst"];
  const _t1b_0 = _t_0["fst"];
  const _t2b_0 = _t_0["snd"];
  const _r_0 = _rr_0["snd"];
  return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1b_0), "snd": (_h2b_0 + _t2b_0)}, "snd": _r_0};
}

function $0m0(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Nil": at[key] = v; return top[0];
      case "Con": at = at[key] = {...v, "head": nat_host(v["head"])}; key = "tail"; v = v[key]; continue;
      default: throw "bend: List has no tag " + v?.$ + " (its tags: Nil, Con); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m1(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Nil": at[key] = v; return top[0];
      case "Con": at = at[key] = {...v, "head": BigInt(v["head"])}; key = "tail"; v = v[key]; continue;
      default: throw "bend: List has no tag " + v?.$ + " (its tags: Nil, Con); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m2(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "../helpers.Ast": at = at[key] = {...v, "m": nat_host(v["m"])}; return top[0];
      default: throw "bend: ../helpers.Ast has no tag " + v?.$ + " (its tags: ../helpers.Ast); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m3(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "../helpers.Ast": at = at[key] = {...v, "m": BigInt(v["m"])}; return top[0];
      default: throw "bend: ../helpers.Ast has no tag " + v?.$ + " (its tags: ../helpers.Ast); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

const TAB_0 = [0, 1, 2];export default {
  "../helpers.Flags.defaults": run_lib(() => { const r = (run_loop($$$$047helpers$Flags$defaults$()));  return r; }, 0),
  "../helpers.nc_sign": run_lib((a0) => { const r = (run_loop($$$$047helpers$nc_sign$((a0)))); (a0); return r; }, 1),
  "../helpers.nc_body": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$nc_body$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.nc_digits": run_lib((a0) => { const r = (run_loop($$$$047helpers$nc_digits$((a0)))); (a0); return r; }, 1),
  "../helpers.nc_in": run_lib((a0) => { const r = (run_loop($$$$047helpers$nc_in$((a0)))); (a0); return r; }, 1),
  "../helpers.nc_ok": run_lib((a0) => { const r = (run_loop($$$$047helpers$nc_ok$((a0)))); (a0); return r; }, 1),
  "../helpers.nc_nz": run_lib((a0) => { const r = (run_loop($$$$047helpers$nc_nz$((a0)))); (a0); return r; }, 1),
  "../helpers.nc_step": run_lib((a0, a1, a2, a3, a4) => { const r = (run_loop($$$$047helpers$nc_step$((a0), (a1), (a2), (a3), (a4)))); (a0); (a1); (a2); (a3); (a4); return r; }, 5),
  "../helpers.nc_walk": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$nc_walk$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.no_color_of.go": run_lib((a0) => { const r = (run_loop($$$$047helpers$no_color_of$go$((a0)))); (a0); return r; }, 1),
  "../helpers.no_color_of": run_lib((a0) => { const r = (run_loop($$$$047helpers$no_color_of$((a0)))); (a0); return r; }, 1),
  "../helpers.getenv_str.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$getenv_str$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.getenv_str": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$getenv_str$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.Flags.of": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$Flags$of$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.prod_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$prod_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.prod_nat": run_lib((a0) => { const r = BigInt(run_loop($$$$047helpers$prod_nat$($0m0(a0)))); $0m1(a0); return r; }, 1),
  "../helpers.dedup_u32.put": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$dedup_u32$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.dedup_u32.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$dedup_u32$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.dedup_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$dedup_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.dedup_str.put": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$dedup_str$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.dedup_str.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$dedup_str$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.dedup_str": run_lib((a0) => { const r = (run_loop($$$$047helpers$dedup_str$((a0)))); (a0); return r; }, 1),
  "../helpers.argfix_bad": run_lib((a0) => { const r = (run_loop($$$$047helpers$argfix_bad$((a0)))); (a0); return r; }, 1),
  "../helpers.argfix1": run_lib((a0) => { const r = (run_loop($$$$047helpers$argfix1$((a0)))); (a0); return r; }, 1),
  "../helpers.argfix2": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$argfix2$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.argfix_seq": run_lib((a0) => { const r = (run_loop($$$$047helpers$argfix_seq$((a0)))); (a0); return r; }, 1),
  "../helpers.ix_le.tie": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$ix_le$tie$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.ix_le.cmp": run_lib((a0, a1, a2, a3, a4) => { const r = (run_loop($$$$047helpers$ix_le$cmp$((a0), (a1), (a2), (a3), (a4)))); (a0); (a1); (a2); (a3); (a4); return r; }, 5),
  "../helpers.ix_le": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ix_le$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ix_of.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ix_of$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ix_of": run_lib((a0) => { const r = (run_loop($$$$047helpers$ix_of$((a0)))); (a0); return r; }, 1),
  "../helpers.ix_index": run_lib((a0) => { const r = (run_loop($$$$047helpers$ix_index$((a0)))); (a0); return r; }, 1),
  "../helpers.ix_map": run_lib((a0) => { const r = (run_loop($$$$047helpers$ix_map$((a0)))); (a0); return r; }, 1),
  "../helpers.argsort_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$argsort_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.all_same_u32.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$all_same_u32$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.all_same_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$all_same_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.all_same_str.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$all_same_str$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.all_same_str": run_lib((a0) => { const r = (run_loop($$$$047helpers$all_same_str$((a0)))); (a0); return r; }, 1),
  "../helpers.u32_list_eq": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$u32_list_eq$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ShapeRes.dims.head": run_lib((a0) => { const r = (run_loop($$$$047helpers$ShapeRes$dims$head$((a0)))); (a0); return r; }, 1),
  "../helpers.ShapeRes.dims.same": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ShapeRes$dims$same$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ShapeRes.dims.ref.put": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ShapeRes$dims$ref$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ShapeRes.dims.ans": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ShapeRes$dims$ans$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ShapeRes.dims": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$ShapeRes$dims$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.ShapeRes.of.walk": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ShapeRes$of$walk$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ShapeRes.of": run_lib((a0) => { const r = (run_loop($$$$047helpers$ShapeRes$of$((a0)))); (a0); return r; }, 1),
  "../helpers.stk.init": run_lib(() => { const r = (run_loop($$$$047helpers$stk$init$()));  return r; }, 0),
  "../helpers.stk.grow": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$stk$grow$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.stk.push": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$stk$push$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.stk.push2": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$stk$push2$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.stk.open": run_lib((a0) => { const r = (run_loop($$$$047helpers$stk$open$((a0)))); (a0); return r; }, 1),
  "../helpers.stk.peek": run_lib((a0) => { const r = (run_loop($$$$047helpers$stk$peek$((a0)))); (a0); return r; }, 1),
  "../helpers.stk.unpush": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$stk$unpush$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.st.splice": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$st$splice$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.st.spread": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$st$spread$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.get_shape.go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$get_shape$go$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "../helpers.nest_nodes": run_lib(() => { const r = BigInt(run_loop($$$$047helpers$nest_nodes$()));  return r; }, 0),
  "../helpers.get_shape.root": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$get_shape$root$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "../helpers.get_shape": run_lib((a0) => { const r = (run_loop($$$$047helpers$get_shape$((a0)))); (a0); return r; }, 1),
  "../helpers.is_image_shape.tail": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_image_shape$tail$((a0)))); (a0); return r; }, 1),
  "../helpers.is_image_shape.dims": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$is_image_shape$dims$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.is_image_shape.rank": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_image_shape$rank$((a0)))); (a0); return r; }, 1),
  "../helpers.is_image_shape.go": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_image_shape$go$((a0)))); (a0); return r; }, 1),
  "../helpers.is_image_shape": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_image_shape$((a0)))); (a0); return r; }, 1),
  "../helpers.all_int_nest": run_lib((a0) => { const r = (run_loop($$$$047helpers$all_int_nest$((a0)))); (a0); return r; }, 1),
  "../helpers.fully_flatten.go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$fully_flatten$go$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "../helpers.fully_flatten_nest": run_lib((a0) => { const r = (run_loop($$$$047helpers$fully_flatten_nest$((a0)))); (a0); return r; }, 1),
  "../helpers.flatten_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$flatten_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_exp_all_ones": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_exp_all_ones$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_is_nan": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_is_nan$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_is_finite": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_is_finite$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_is_neg": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_is_neg$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_frac.next": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_frac$next$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_frac.digit": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_frac$digit$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_frac.step": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_frac$step$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_frac.put": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_frac$put$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_frac.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_frac$go$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "../helpers.f32_fixed.put": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_fixed$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_fixed.text3": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$f32_fixed$text3$((a0), (a1), nat_host(a2), (a3)))); (a0); (a1); BigInt(a2); (a3); return r; }, 4),
  "../helpers.f32_fixed.text2": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$f32_fixed$text2$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "../helpers.f32_fixed.text1": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_fixed$text1$((a0), nat_host(a1), (a2)))); (a0); BigInt(a1); (a2); return r; }, 3),
  "../helpers.f32_fixed.text": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_fixed$text$((a0), nat_host(a1), (a2)))); (a0); BigInt(a1); (a2); return r; }, 3),
  "../helpers.f32_fixed.body": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_fixed$body$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "../helpers.f32_fixed.special.inf": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_fixed$special$inf$((a0)))); (a0); return r; }, 1),
  "../helpers.f32_fixed.special.fin": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_fixed$special$fin$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_fixed.special": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_fixed$special$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.f32_fixed.go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_fixed$go$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "../helpers.f32_fixed": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_fixed$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "../helpers.f32_is_int_valued": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_is_int_valued$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_show.put2": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_show$put2$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.f32_show.put": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_show$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_show.special": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$f32_show$special$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.f32_show.go2": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_show$go2$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_show.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$f32_show$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.f32_show": run_lib((a0) => { const r = (run_loop($$$$047helpers$f32_show$((a0)))); (a0); return r; }, 1),
  "../helpers.pad.n.go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$pad$n$go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.pad.n": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$pad$n$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.pad_left.blank": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$pad_left$blank$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.pad_left": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$pad_left$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.pad_right": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$pad_right$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.color_code": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$color_code$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.esc": run_lib((a0) => { const r = (run_loop($$$$047helpers$esc$((a0)))); (a0); return r; }, 1),
  "../helpers.color_of": run_lib((a0) => { const r = (run_loop($$$$047helpers$color_of$((a0)))); (a0); return r; }, 1),
  "../helpers.colored.put": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$colored$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.colored.flag": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$colored$flag$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.colored.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$colored$go$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.colored": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$colored$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.colorize_float.hi": run_lib((a0) => { const r = (run_loop($$$$047helpers$colorize_float$hi$((a0)))); (a0); return r; }, 1),
  "../helpers.colorize_float.pick": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$colorize_float$pick$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.colorize_float": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$colorize_float$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.time_to_str.ms": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$time_to_str$ms$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.time_to_str.us": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$time_to_str$us$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.time_to_str.pick": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$time_to_str$pick$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.time_to_str": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$time_to_str$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.size_to_str.mb": run_lib((a0) => { const r = (run_loop($$$$047helpers$size_to_str$mb$((a0)))); (a0); return r; }, 1),
  "../helpers.size_to_str.kb": run_lib((a0) => { const r = (run_loop($$$$047helpers$size_to_str$kb$((a0)))); (a0); return r; }, 1),
  "../helpers.size_to_str.pick": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$size_to_str$pick$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.size_to_str": run_lib((a0) => { const r = (run_loop($$$$047helpers$size_to_str$((a0)))); (a0); return r; }, 1),
  "../helpers.ansistrip.done4": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ansistrip$done4$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ansistrip.done3": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$ansistrip$done3$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "../helpers.ansistrip.done2": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$ansistrip$done2$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "../helpers.ansistrip.done": run_lib((a0) => { const r = (run_loop($$$$047helpers$ansistrip$done$($0m2(a0)))); $0m3(a0); return r; }, 1),
  "../helpers.ansistrip.go.esc": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ansistrip$go$esc$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ansistrip.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ansistrip$go$((a0), $0m2(a1)))); (a0); $0m3(a1); return r; }, 2),
  "../helpers.ansistrip": run_lib((a0) => { const r = (run_loop($$$$047helpers$ansistrip$((a0)))); (a0); return r; }, 1),
  "../helpers.ansilen": run_lib((a0) => { const r = BigInt(run_loop($$$$047helpers$ansilen$((a0)))); (a0); return r; }, 1),
  "../helpers.ansipad": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ansipad$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.make_tuple_rep.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$make_tuple_rep$go$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "../helpers.make_tuple_rep": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$make_tuple_rep$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.make_tuple_of": run_lib((a0) => { const r = (run_loop($$$$047helpers$make_tuple_of$((a0)))); (a0); return r; }, 1),
  "../helpers.to_tuple_u32": run_lib((a0) => { const r = (run_loop($$$$047helpers$to_tuple_u32$((a0)))); (a0); return r; }, 1),
  "../helpers.to_tuple_seq": run_lib((a0) => { const r = (run_loop($$$$047helpers$to_tuple_seq$((a0)))); (a0); return r; }, 1),
  "../helpers.fg_pairs": run_lib((a0) => { const r = (run_loop($$$$047helpers$fg_pairs$((a0)))); (a0); return r; }, 1),
  "../helpers.fg_skip": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$fg_skip$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "../helpers.flat_to_grouped": run_lib((a0) => { const r = (run_loop($$$$047helpers$flat_to_grouped$((a0)))); (a0); return r; }, 1),
  "../helpers.resolve_pool_pads_int.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$resolve_pool_pads_int$go$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "../helpers.resolve_pool_pads_int": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$resolve_pool_pads_int$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.pool_pads_dup.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$pool_pads_dup$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.pool_pads_dup": run_lib((a0) => { const r = (run_loop($$$$047helpers$pool_pads_dup$((a0)))); (a0); return r; }, 1),
  "../helpers.resolve_pool_pads.pick": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$resolve_pool_pads$pick$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.resolve_pool_pads.step": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$resolve_pool_pads$step$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.resolve_pool_pads.n": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$resolve_pool_pads$n$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.resolve_pool_pads": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$resolve_pool_pads$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.bal.next.step": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$bal$next$step$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.bal.next": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$bal$next$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.bal.under": run_lib((a0) => { const r = (run_loop($$$$047helpers$bal$under$((a0)))); (a0); return r; }, 1),
  "../helpers.bal.depth": run_lib((a0) => { const r = (run_loop($$$$047helpers$bal$depth$((a0)))); (a0); return r; }, 1),
  "../helpers.bal.spilled": run_lib((a0) => { const r = (run_loop($$$$047helpers$bal$spilled$((a0)))); (a0); return r; }, 1),
  "../helpers.bal.step": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$bal$step$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.bal.end": run_lib((a0) => { const r = (run_loop($$$$047helpers$bal$end$((a0)))); (a0); return r; }, 1),
  "../helpers.bal.walk": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$bal$walk$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.is_balanced": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_balanced$((a0)))); (a0); return r; }, 1),
  "../helpers.strip_parens.inner": run_lib((a0) => { const r = (run_loop($$$$047helpers$strip_parens$inner$((a0)))); (a0); return r; }, 1),
  "../helpers.is_wrapped.both": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$is_wrapped$both$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.is_wrapped": run_lib((a0) => { const r = (run_loop($$$$047helpers$is_wrapped$((a0)))); (a0); return r; }, 1),
  "../helpers.strip_parens.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$strip_parens$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.strip_parens": run_lib((a0) => { const r = (run_loop($$$$047helpers$strip_parens$((a0)))); (a0); return r; }, 1),
  "../helpers.i32_is_neg": run_lib((a0) => { const r = (run_loop($$$$047helpers$i32_is_neg$((a0)))); (a0); return r; }, 1),
  "../helpers.i32_neg": run_lib((a0) => { const r = (run_loop($$$$047helpers$i32_neg$((a0)))); (a0); return r; }, 1),
  "../helpers.asr": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$asr$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "../helpers.i32_abs": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i32_abs$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cdiv_sign": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cdiv_sign$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floordiv_i32.exact": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floordiv_i32$exact$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floordiv_i32.trunc.put": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floordiv_i32$trunc$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floordiv_i32.trunc.exact": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$floordiv_i32$trunc$exact$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.floordiv_i32.trunc": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$floordiv_i32$trunc$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.floordiv_i32.pick": run_lib((a0, a1, a2, a3, a4) => { const r = (run_loop($$$$047helpers$floordiv_i32$pick$((a0), (a1), (a2), (a3), (a4)))); (a0); (a1); (a2); (a3); (a4); return r; }, 5),
  "../helpers.floordiv_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floordiv_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cdiv_i32.put": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cdiv_i32$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cdiv_i32": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$cdiv_i32$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.cdiv_i32_go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cdiv_i32_go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cmod_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cmod_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floormod_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floormod_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floordiv_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floordiv_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.floormod_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$floormod_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cdiv_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cdiv_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.cmod_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$cmod_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ceildiv_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ceildiv_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.div0": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$div0$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.ceildiv_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$ceildiv_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.round_up_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$round_up_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.round_down_i32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$round_down_i32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.round_up_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$round_up_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.round_down_u32": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$round_down_u32$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.next_power2.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$next_power2$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.next_power2": run_lib((a0) => { const r = (run_loop($$$$047helpers$next_power2$((a0)))); (a0); return r; }, 1),
  "../helpers.match_hi": run_lib((a0) => { const r = (run_loop($$$$047helpers$match_hi$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_of_i32": run_lib((a0) => { const r = (run_loop($$$$047helpers$i64_of_i32$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_of_hi_lo": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_of_hi_lo$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.lo32": run_lib((a0) => { const r = (run_loop($$$$047helpers$lo32$((a0)))); (a0); return r; }, 1),
  "../helpers.hi32": run_lib((a0) => { const r = (run_loop($$$$047helpers$hi32$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_cmp.lt": run_lib((a0) => { const r = (run_loop($$$$047helpers$i64_cmp$lt$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_cmp.mag": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$i64_cmp$mag$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "../helpers.i64_cmp.sgn": run_lib((a0, a1, a2, a3, a4, a5) => { const r = (run_loop($$$$047helpers$i64_cmp$sgn$((a0), (a1), (a2), (a3), (a4), (a5)))); (a0); (a1); (a2); (a3); (a4); (a5); return r; }, 6),
  "../helpers.i64_cmp": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_cmp$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.i64_is_neg": run_lib((a0) => { const r = (run_loop($$$$047helpers$i64_is_neg$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_le": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_le$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.i64_show": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_show$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.i64_text": run_lib((a0) => { const r = (run_loop($$$$047helpers$i64_text$((a0)))); (a0); return r; }, 1),
  "../helpers.i64_add": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_add$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.i64_sub": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$i64_sub$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.data64_hi": run_lib((a0) => { const r = (run_loop($$$$047helpers$data64_hi$((a0)))); (a0); return r; }, 1),
  "../helpers.data64_lo": run_lib((a0) => { const r = (run_loop($$$$047helpers$data64_lo$((a0)))); (a0); return r; }, 1),
  "../helpers.data64": run_lib((a0) => { const r = (run_loop($$$$047helpers$data64$((a0)))); (a0); return r; }, 1),
  "../helpers.data64_le": run_lib((a0) => { const r = (run_loop($$$$047helpers$data64_le$((a0)))); (a0); return r; }, 1),
  "../helpers.to_be32": run_lib((a0) => { const r = (run_loop($$$$047helpers$to_be32$((a0)))); (a0); return r; }, 1),
  "../helpers.to_be64": run_lib((a0) => { const r = (run_loop($$$$047helpers$to_be64$((a0)))); (a0); return r; }, 1),
  "../helpers.bit_mask": run_lib((a0) => { const r = (run_loop($$$$047helpers$bit_mask$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "../helpers.getbits": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$getbits$((a0), nat_host(a1), nat_host(a2)))); (a0); BigInt(a1); BigInt(a2); return r; }, 3),
  "../helpers.i2u": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$i2u$((a0), nat_host(a1), (a2)))); (a0); BigInt(a1); (a2); return r; }, 3),
  "../helpers.kv_key": run_lib((a0) => { const r = (run_loop($$$$047helpers$kv_key$((a0)))); (a0); return r; }, 1),
  "../helpers.kv_val": run_lib((a0) => { const r = (run_loop($$$$047helpers$kv_val$((a0)))); (a0); return r; }, 1),
  "../helpers.kv_find.hit": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$kv_find$hit$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.kv_find.pick": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$kv_find$pick$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.kv_find.go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$kv_find$go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.kv_find": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$kv_find$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.kv_conflict.pick": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$kv_conflict$pick$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.kv_conflict": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$kv_conflict$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.merged_seen": run_lib((a0) => { const r = (run_loop($$$$047helpers$merged_seen$((a0)))); (a0); return r; }, 1),
  "../helpers.merged_bad": run_lib((a0) => { const r = (run_loop($$$$047helpers$merged_bad$((a0)))); (a0); return r; }, 1),
  "../helpers.merged_of": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$merged_of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.merge_dicts.add": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$merge_dicts$add$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.merge_dicts.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$merge_dicts$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.merge_dicts.pick": run_lib((a0) => { const r = (run_loop($$$$047helpers$merge_dicts$pick$((a0)))); (a0); return r; }, 1),
  "../helpers.merge_dicts": run_lib((a0) => { const r = (run_loop($$$$047helpers$merge_dicts$((a0)))); (a0); return r; }, 1),
  "../helpers.part_put": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$part_put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.part_test": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$part_test$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.part_go": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$part_go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "../helpers.part_out": run_lib((a0) => { const r = (run_loop($$$$047helpers$part_out$((a0)))); (a0); return r; }, 1),
  "../helpers.part_yes": run_lib((a0) => { const r = (run_loop($$$$047helpers$part_yes$((a0)))); (a0); return r; }, 1),
  "../helpers.part_no": run_lib((a0) => { const r = (run_loop($$$$047helpers$part_no$((a0)))); (a0); return r; }, 1),
  "../helpers.partition": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$partition$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.unwrap_or": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$unwrap_or$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.get_single": run_lib((a0) => { const r = (run_loop($$$$047helpers$get_single$((a0)))); (a0); return r; }, 1),
  "../helpers.Timing.report.text": run_lib((a0, a1, a2) => { const r = (run_loop($$$$047helpers$Timing$report$text$((a0), nat_host(a1), nat_host(a2)))); (a0); BigInt(a1); BigInt(a2); return r; }, 3),
  "../helpers.Timing.report.go": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$Timing$report$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.Timing.report": run_lib((a0, a1, a2, a3) => { const r = (run_loop($$$$047helpers$Timing$report$((a0), (a1), nat_host(a2), nat_host(a3)))); (a0); (a1); BigInt(a2); BigInt(a3); return r; }, 4),
  "../helpers.lines.done": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$lines$done$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.lines.close": run_lib((a0) => { const r = (run_loop($$$$047helpers$lines$close$((a0)))); (a0); return r; }, 1),
  "../helpers.lines.split": run_lib((a0) => { const r = (run_loop($$$$047helpers$lines$split$((a0)))); (a0); return r; }, 1),
  "../helpers.lines.read": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$lines$read$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.lines.go": run_lib((a0) => { const r = (run_loop($$$$047helpers$lines$go$((a0)))); (a0); return r; }, 1),
  "../helpers.lines": run_lib((a0) => { const r = (run_loop($$$$047helpers$lines$((a0)))); (a0); return r; }, 1),
  "../helpers.printable.go": run_lib((a0) => { const r = (run_loop($$$$047helpers$printable$go$((a0)))); (a0); return r; }, 1),
  "../helpers.printable.pick": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$printable$pick$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "../helpers.printable": run_lib((a0, a1) => { const r = (run_loop($$$$047helpers$printable$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "OBJ_INSTANCE": run_lib(() => { const r = (run_loop($OBJ_INSTANCE$()));  return r; }, 0),
  "OBJ_ADAPTER": run_lib(() => { const r = (run_loop($OBJ_ADAPTER$()));  return r; }, 0),
  "OBJ_QUEUE": run_lib(() => { const r = (run_loop($OBJ_QUEUE$()));  return r; }, 0),
  "OBJ_SHADER_MODULE": run_lib(() => { const r = (run_loop($OBJ_SHADER_MODULE$()));  return r; }, 0),
  "OBJ_BIND_GROUP_LAYOUT": run_lib(() => { const r = (run_loop($OBJ_BIND_GROUP_LAYOUT$()));  return r; }, 0),
  "OBJ_PIPELINE_LAYOUT": run_lib(() => { const r = (run_loop($OBJ_PIPELINE_LAYOUT$()));  return r; }, 0),
  "OBJ_BIND_GROUP": run_lib(() => { const r = (run_loop($OBJ_BIND_GROUP$()));  return r; }, 0),
  "OBJ_COMPUTE_PIPELINE": run_lib(() => { const r = (run_loop($OBJ_COMPUTE_PIPELINE$()));  return r; }, 0),
  "OBJ_COMMAND_ENCODER": run_lib(() => { const r = (run_loop($OBJ_COMMAND_ENCODER$()));  return r; }, 0),
  "OBJ_COMPUTE_PASS": run_lib(() => { const r = (run_loop($OBJ_COMPUTE_PASS$()));  return r; }, 0),
  "OBJ_COMMAND_BUFFER": run_lib(() => { const r = (run_loop($OBJ_COMMAND_BUFFER$()));  return r; }, 0),
  "OBJ_QUERY_SET": run_lib(() => { const r = (run_loop($OBJ_QUERY_SET$()));  return r; }, 0),
  "OBJ_BUFFER": run_lib(() => { const r = (run_loop($OBJ_BUFFER$()));  return r; }, 0),
  "CALL_CREATE": run_lib(() => { const r = (run_loop($CALL_CREATE$()));  return r; }, 0),
  "CALL_WAIT": run_lib(() => { const r = (run_loop($CALL_WAIT$()));  return r; }, 0),
  "CALL_RELEASE": run_lib(() => { const r = (run_loop($CALL_RELEASE$()));  return r; }, 0),
  "CALL_PUSH": run_lib(() => { const r = (run_loop($CALL_PUSH$()));  return r; }, 0),
  "CALL_POP": run_lib(() => { const r = (run_loop($CALL_POP$()));  return r; }, 0),
  "CALL_MAP_ASYNC": run_lib(() => { const r = (run_loop($CALL_MAP_ASYNC$()));  return r; }, 0),
  "CALL_MAPPED_RANGE": run_lib(() => { const r = (run_loop($CALL_MAPPED_RANGE$()));  return r; }, 0),
  "CALL_WRITE": run_lib(() => { const r = (run_loop($CALL_WRITE$()));  return r; }, 0),
  "CALL_COPY": run_lib(() => { const r = (run_loop($CALL_COPY$()));  return r; }, 0),
  "CALL_BEGIN": run_lib(() => { const r = (run_loop($CALL_BEGIN$()));  return r; }, 0),
  "CALL_SET_PIPELINE": run_lib(() => { const r = (run_loop($CALL_SET_PIPELINE$()));  return r; }, 0),
  "CALL_SET_BIND_GROUP": run_lib(() => { const r = (run_loop($CALL_SET_BIND_GROUP$()));  return r; }, 0),
  "CALL_DISPATCH": run_lib(() => { const r = (run_loop($CALL_DISPATCH$()));  return r; }, 0),
  "CALL_END": run_lib(() => { const r = (run_loop($CALL_END$()));  return r; }, 0),
  "CALL_RESOLVE": run_lib(() => { const r = (run_loop($CALL_RESOLVE$()));  return r; }, 0),
  "CALL_FINISH": run_lib(() => { const r = (run_loop($CALL_FINISH$()));  return r; }, 0),
  "CALL_SUBMIT": run_lib(() => { const r = (run_loop($CALL_SUBMIT$()));  return r; }, 0),
  "CALL_UNMAP": run_lib(() => { const r = (run_loop($CALL_UNMAP$()));  return r; }, 0),
  "CALL_DESTROY": run_lib(() => { const r = (run_loop($CALL_DESTROY$()));  return r; }, 0),
  "CALL_DESTROY_QUERY_SET": run_lib(() => { const r = (run_loop($CALL_DESTROY_QUERY_SET$()));  return r; }, 0),
  "CALL_GET_FEATURES": run_lib(() => { const r = (run_loop($CALL_GET_FEATURES$()));  return r; }, 0),
  "CALL_FREE_FEATURES": run_lib(() => { const r = (run_loop($CALL_FREE_FEATURES$()));  return r; }, 0),
  "CALL_GET_LIMITS": run_lib(() => { const r = (run_loop($CALL_GET_LIMITS$()));  return r; }, 0),
  "SYNC_MAP_ASYNC": run_lib(() => { const r = (run_loop($SYNC_MAP_ASYNC$()));  return r; }, 0),
  "SYNC_POP_ERROR_SCOPE": run_lib(() => { const r = (run_loop($SYNC_POP_ERROR_SCOPE$()));  return r; }, 0),
  "SYNC_CREATE_PIPELINE": run_lib(() => { const r = (run_loop($SYNC_CREATE_PIPELINE$()));  return r; }, 0),
  "SYNC_REQUEST_ADAPTER": run_lib(() => { const r = (run_loop($SYNC_REQUEST_ADAPTER$()));  return r; }, 0),
  "SYNC_REQUEST_DEVICE": run_lib(() => { const r = (run_loop($SYNC_REQUEST_DEVICE$()));  return r; }, 0),
  "SYNC_WORK_DONE": run_lib(() => { const r = (run_loop($SYNC_WORK_DONE$()));  return r; }, 0),
  "SYNC_HAS_EMSG": run_lib(() => { const r = (run_loop($SYNC_HAS_EMSG$()));  return r; }, 0),
  "SYNC_NO_EMSG": run_lib(() => { const r = (run_loop($SYNC_NO_EMSG$()));  return r; }, 0),
  "SYNC_NONE": run_lib(() => { const r = (run_loop($SYNC_NONE$()));  return r; }, 0),
  "SYNC_ONE": run_lib(() => { const r = (run_loop($SYNC_ONE$()));  return r; }, 0),
  "SYNC_MANY": run_lib(() => { const r = (run_loop($SYNC_MANY$()));  return r; }, 0),
  "SYNC_MISSING": run_lib(() => { const r = (run_loop($SYNC_MISSING$()));  return r; }, 0),
  "BIND_UNIFORM": run_lib(() => { const r = (run_loop($BIND_UNIFORM$()));  return r; }, 0),
  "BIND_STORAGE": run_lib(() => { const r = (run_loop($BIND_STORAGE$()));  return r; }, 0),
  "FILTER_VALIDATION": run_lib(() => { const r = (run_loop($FILTER_VALIDATION$()));  return r; }, 0),
  "MAP_UNMAPPED": run_lib(() => { const r = (run_loop($MAP_UNMAPPED$()));  return r; }, 0),
  "MAP_MAPPED": run_lib(() => { const r = (run_loop($MAP_MAPPED$()));  return r; }, 0),
  "FEATURE_TIMESTAMP_QUERY": run_lib(() => { const r = (run_loop($FEATURE_TIMESTAMP_QUERY$()));  return r; }, 0),
  "FEATURE_SHADER_F16": run_lib(() => { const r = (run_loop($FEATURE_SHADER_F16$()));  return r; }, 0),
  "USAGE_MAP_READ": run_lib(() => { const r = (run_loop($USAGE_MAP_READ$()));  return r; }, 0),
  "USAGE_COPY_SRC": run_lib(() => { const r = (run_loop($USAGE_COPY_SRC$()));  return r; }, 0),
  "USAGE_COPY_DST": run_lib(() => { const r = (run_loop($USAGE_COPY_DST$()));  return r; }, 0),
  "USAGE_UNIFORM": run_lib(() => { const r = (run_loop($USAGE_UNIFORM$()));  return r; }, 0),
  "USAGE_STORAGE": run_lib(() => { const r = (run_loop($USAGE_STORAGE$()));  return r; }, 0),
  "USAGE_QUERY_RESOLVE": run_lib(() => { const r = (run_loop($USAGE_QUERY_RESOLVE$()));  return r; }, 0),
  "STATUS_SUCCESS": run_lib(() => { const r = (run_loop($STATUS_SUCCESS$()));  return r; }, 0),
  "BIND_GROUP_INDEX": run_lib(() => { const r = (run_loop($BIND_GROUP_INDEX$()));  return r; }, 0),
  "UNIFORM_SIZE": run_lib(() => { const r = (run_loop($UNIFORM_SIZE$()));  return r; }, 0),
  "QUERY_COUNT": run_lib(() => { const r = (run_loop($QUERY_COUNT$()));  return r; }, 0),
  "QUERY_BUF_SIZE": run_lib(() => { const r = (run_loop($QUERY_BUF_SIZE$()));  return r; }, 0),
  "Tr.of": run_lib(() => { const r = (run_loop($Tr$of$()));  return r; }, 0),
  "Tr.calls": run_lib((a0) => { const r = (run_loop($Tr$calls$((a0)))); (a0); return r; }, 1),
  "Tr.next": run_lib((a0) => { const r = (run_loop($Tr$next$((a0)))); (a0); return r; }, 1),
  "Tr.depth": run_lib((a0) => { const r = (run_loop($Tr$depth$((a0)))); (a0); return r; }, 1),
  "Tr.refused": run_lib((a0) => { const r = (run_loop($Tr$refused$((a0)))); (a0); return r; }, 1),
  "Tr.fail_at": run_lib((a0, a1) => { const r = (run_loop($Tr$fail_at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Tr.reset": run_lib((a0) => { const r = (run_loop($Tr$reset$((a0)))); (a0); return r; }, 1),
  "Tr.here": run_lib((a0) => { const r = (run_loop($Tr$here$((a0)))); (a0); return r; }, 1),
  "Tr.emit.go": run_lib((a0, a1, a2, a3, a4, a5, a6, a7) => { const r = (run_loop($Tr$emit$go$((a0), (a1), (a2), (a3), (a4), (a5), (a6), (a7)))); (a0); (a1); (a2); (a3); (a4); (a5); (a6); (a7); return r; }, 8),
  "Tr.emit": run_lib((a0, a1, a2) => { const r = (run_loop($Tr$emit$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Tr.push": run_lib((a0) => { const r = (run_loop($Tr$push$((a0)))); (a0); return r; }, 1),
  "Tr.pop.hit": run_lib((a0, a1, a2) => { const r = (run_loop($Tr$pop$hit$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Tr.pop.go": run_lib((a0, a1, a2, a3, a4, a5) => { const r = (run_loop($Tr$pop$go$((a0), (a1), (a2), (a3), (a4), (a5)))); (a0); (a1); (a2); (a3); (a4); (a5); return r; }, 6),
  "Tr.pop": run_lib((a0) => { const r = (run_loop($Tr$pop$((a0)))); (a0); return r; }, 1),
  "Call.k": run_lib((a0) => { const r = (run_loop($Call$k$((a0)))); (a0); return r; }, 1),
  "Call.arg": run_lib((a0) => { const r = (run_loop($Call$arg$((a0)))); (a0); return r; }, 1),
  "Tr.count.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Tr$count$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "Tr.count": run_lib((a0, a1) => { const r = (run_loop($Tr$count$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Tr.args.put": run_lib((a0, a1, a2) => { const r = (run_loop($Tr$args$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Tr.args.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Tr$args$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "Tr.args": run_lib((a0, a1) => { const r = (run_loop($Tr$args$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Tr.has.step.same2": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Tr$has$step$same2$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "Tr.has.step.hit": run_lib((a0, a1) => { const r = BigInt(run_loop($Tr$has$step$hit$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "Tr.has.step": run_lib((a0, a1, a2) => { const r = BigInt(run_loop($Tr$has$step$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "Tr.has.go": run_lib((a0, a1, a2, a3, a4) => { const r = (run_loop($Tr$has$go$(nat_host(a0), nat_host(a1), (a2), (a3), nat_host(a4)))); BigInt(a0); BigInt(a1); (a2); (a3); BigInt(a4); return r; }, 5),
  "Tr.has": run_lib((a0, a1) => { const r = (run_loop($Tr$has$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "u32_list_eq": run_lib((a0, a1) => { const r = (run_loop($u32_list_eq$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "str_eq.go": run_lib((a0, a1, a2) => { const r = (run_loop($str_eq$go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "backend_names": run_lib(() => { const r = (run_loop($backend_names$()));  return r; }, 0),
  "backend_of.put": run_lib((a0, a1, a2, a3) => { const r = (run_loop($backend_of$put$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "backend_of.go": run_lib((a0, a1, a2, a3, a4) => { const r = (run_loop($backend_of$go$(nat_host(a0), (a1), (a2), (a3), (a4)))); BigInt(a0); (a1); (a2); (a3); (a4); return r; }, 5),
  "backend_of": run_lib((a0) => { const r = (run_loop($backend_of$((a0)))); (a0); return r; }, 1),
  "sync_ret": run_lib((a0) => { const r = (run_loop($sync_ret$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "sync_has_emsg": run_lib((a0) => { const r = (run_loop($sync_has_emsg$((a0)))); (a0); return r; }, 1),
  "sync_payload": run_lib((a0, a1) => { const r = BigInt(run_loop($sync_payload$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "sync_name.map_async2": run_lib(() => { const r = (run_loop($sync_name$map_async2$()));  return r; }, 0),
  "sync_name.pop2": run_lib(() => { const r = (run_loop($sync_name$pop2$()));  return r; }, 0),
  "sync_name.pipeline2": run_lib(() => { const r = (run_loop($sync_name$pipeline2$()));  return r; }, 0),
  "sync_name.adapter2": run_lib(() => { const r = (run_loop($sync_name$adapter2$()));  return r; }, 0),
  "sync_name.device2": run_lib(() => { const r = (run_loop($sync_name$device2$()));  return r; }, 0),
  "sync_name.workdone2": run_lib(() => { const r = (run_loop($sync_name$workdone2$()));  return r; }, 0),
  "sync_name.two.at": run_lib((a0) => { const r = (run_loop($sync_name$two$at$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "sync_name.two": run_lib((a0) => { const r = (run_loop($sync_name$two$((a0)))); (a0); return r; }, 1),
  "sync_name.map_async3": run_lib(() => { const r = (run_loop($sync_name$map_async3$()));  return r; }, 0),
  "sync_name.pop3": run_lib(() => { const r = (run_loop($sync_name$pop3$()));  return r; }, 0),
  "sync_name.pipeline3": run_lib(() => { const r = (run_loop($sync_name$pipeline3$()));  return r; }, 0),
  "sync_name.adapter3": run_lib(() => { const r = (run_loop($sync_name$adapter3$()));  return r; }, 0),
  "sync_name.device3": run_lib(() => { const r = (run_loop($sync_name$device3$()));  return r; }, 0),
  "sync_name.workdone3": run_lib(() => { const r = (run_loop($sync_name$workdone3$()));  return r; }, 0),
  "sync_name.three.at": run_lib((a0) => { const r = (run_loop($sync_name$three$at$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "sync_name.three": run_lib((a0) => { const r = (run_loop($sync_name$three$((a0)))); (a0); return r; }, 1),
  "UNDER": run_lib(() => { const r = (run_loop($UNDER$()));  return r; }, 0),
  "sync_us.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($sync_us$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "sync_us.at": run_lib((a0, a1) => { const r = (run_loop($sync_us$at$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "sync_us": run_lib((a0) => { const r = (run_loop($sync_us$((a0)))); (a0); return r; }, 1),
  "sync_tail": run_lib((a0) => { const r = (run_loop($sync_tail$((a0)))); (a0); return r; }, 1),
  "sync_name.six2": run_lib(() => { const r = (run_loop($sync_name$six2$()));  return r; }, 0),
  "sync_name.six3": run_lib(() => { const r = (run_loop($sync_name$six3$()));  return r; }, 0),
  "sync_name.of.err": run_lib((a0, a1) => { const r = (run_loop($sync_name$of$err$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "sync_name.of": run_lib((a0, a1) => { const r = (run_loop($sync_name$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "sync_error": run_lib((a0, a1, a2) => { const r = (run_loop($sync_error$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Dev.at": run_lib((a0, a1) => { const r = (run_loop($Dev$at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Dev.tr": run_lib((a0) => { const r = (run_loop($Dev$tr$((a0)))); (a0); return r; }, 1),
  "Dev.instance": run_lib((a0) => { const r = (run_loop($Dev$instance$((a0)))); (a0); return r; }, 1),
  "Dev.adapter": run_lib((a0) => { const r = (run_loop($Dev$adapter$((a0)))); (a0); return r; }, 1),
  "Dev.device_res": run_lib((a0) => { const r = (run_loop($Dev$device_res$((a0)))); (a0); return r; }, 1),
  "Dev.queue": run_lib((a0) => { const r = (run_loop($Dev$queue$((a0)))); (a0); return r; }, 1),
  "Dev.features": run_lib((a0) => { const r = (run_loop($Dev$features$((a0)))); (a0); return r; }, 1),
  "Dev.backend": run_lib((a0) => { const r = (run_loop($Dev$backend$((a0)))); (a0); return r; }, 1),
  "Dev.nrequired": run_lib((a0) => { const r = (run_loop($Dev$nrequired$((a0)))); (a0); return r; }, 1),
  "Dev.arch": run_lib((a0) => { const r = (run_loop($Dev$arch$((a0)))); (a0); return r; }, 1),
  "dev.create_instance": run_lib(() => { const r = (run_loop($dev$create_instance$()));  return r; }, 0),
  "dev.request_adapter": run_lib((a0, a1) => { const r = (run_loop($dev$request_adapter$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "keeps_feature": run_lib((a0) => { const r = (run_loop($keeps_feature$((a0)))); (a0); return r; }, 1),
  "features_keep.put": run_lib((a0, a1) => { const r = (run_loop($features_keep$put$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "features_keep.go": run_lib((a0, a1, a2) => { const r = (run_loop($features_keep$go$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "features_of": run_lib((a0) => { const r = (run_loop($features_of$((a0)))); (a0); return r; }, 1),
  "dev.get_features": run_lib((a0) => { const r = (run_loop($dev$get_features$((a0)))); (a0); return r; }, 1),
  "dev.features_keep": run_lib((a0, a1) => { const r = (run_loop($dev$features_keep$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "dev.get_limits": run_lib((a0) => { const r = (run_loop($dev$get_limits$((a0)))); (a0); return r; }, 1),
  "dev.arch_of": run_lib((a0) => { const r = (run_loop($dev$arch_of$((a0)))); (a0); return r; }, 1),
  "dev.derive": run_lib((a0) => { const r = (run_loop($dev$derive$((a0)))); (a0); return r; }, 1),
  "dev.request_device": run_lib((a0) => { const r = (run_loop($dev$request_device$((a0)))); (a0); return r; }, 1),
  "dev.get_queue": run_lib((a0) => { const r = (run_loop($dev$get_queue$((a0)))); (a0); return r; }, 1),
  "dev.adapter_release": run_lib((a0) => { const r = (run_loop($dev$adapter_release$((a0)))); (a0); return r; }, 1),
  "dev.init": run_lib((a0, a1) => { const r = (run_loop($dev$init$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "dev.free.at": run_lib((a0, a1, a2) => { const r = (run_loop($dev$free$at$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "dev.free": run_lib((a0, a1, a2) => { const r = (run_loop($dev$free$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "dev.uniform_usage": run_lib(() => { const r = (run_loop($dev$uniform_usage$()));  return r; }, 0),
  "dev.uniform_bytes.go": run_lib((a0, a1, a2) => { const r = (run_loop($dev$uniform_bytes$go$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "dev.uniform_bytes": run_lib((a0) => { const r = (run_loop($dev$uniform_bytes$((a0)))); (a0); return r; }, 1),
  "Buf.size": run_lib((a0) => { const r = (run_loop($Buf$size$((a0)))); (a0); return r; }, 1),
  "Made.buf": run_lib((a0) => { const r = (run_loop($Made$buf$((a0)))); (a0); return r; }, 1),
  "Made.tr": run_lib((a0) => { const r = (run_loop($Made$tr$((a0)))); (a0); return r; }, 1),
  "copy.write": run_lib((a0, a1) => { const r = (run_loop($copy$write$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "dev.create_uniform": run_lib((a0, a1) => { const r = (run_loop($dev$create_uniform$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "alloc.usage": run_lib(() => { const r = (run_loop($alloc$usage$()));  return r; }, 0),
  "alloc.size": run_lib((a0) => { const r = (run_loop($alloc$size$((a0)))); (a0); return r; }, 1),
  "alloc.of": run_lib((a0, a1) => { const r = (run_loop($alloc$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "copy.write_len": run_lib((a0) => { const r = (run_loop($copy$write_len$((a0)))); (a0); return r; }, 1),
  "copy.pad": run_lib((a0) => { const r = (run_loop($copy$pad$((a0)))); (a0); return r; }, 1),
  "copy.copyin": run_lib((a0, a1) => { const r = (run_loop($copy$copyin$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "copy.readable_usage": run_lib(() => { const r = (run_loop($copy$readable_usage$()));  return r; }, 0),
  "copy.readable": run_lib((a0, a1) => { const r = (run_loop($copy$readable$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "copy.read": run_lib((a0, a1, a2) => { const r = (run_loop($copy$read$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "copy.read_made": run_lib((a0, a1, a2) => { const r = (run_loop($copy$read_made$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Pass.of": run_lib((a0, a1) => { const r = (run_loop($Pass$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Pass.tr": run_lib((a0) => { const r = (run_loop($Pass$tr$((a0)))); (a0); return r; }, 1),
  "Pass.ls": run_lib((a0) => { const r = (run_loop($Pass$ls$((a0)))); (a0); return r; }, 1),
  "Pass.nentries": run_lib((a0) => { const r = (run_loop($Pass$nentries$((a0)))); (a0); return r; }, 1),
  "Pass.sizes": run_lib((a0) => { const r = (run_loop($Pass$sizes$((a0)))); (a0); return r; }, 1),
  "Pass.gx": run_lib((a0) => { const r = (run_loop($Pass$gx$((a0)))); (a0); return r; }, 1),
  "Pass.wait": run_lib((a0) => { const r = (run_loop($Pass$wait$((a0)))); (a0); return r; }, 1),
  "Pass.reset": run_lib((a0) => { const r = (run_loop($Pass$reset$((a0)))); (a0); return r; }, 1),
  "prog.wants_wait": run_lib((a0, a1) => { const r = (run_loop($prog$wants_wait$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "prog.init": run_lib((a0, a1) => { const r = (run_loop($prog$init$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "bgl.entry.put": run_lib((a0, a1, a2) => { const r = (run_loop($bgl$entry$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "bgl.of.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($bgl$of$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "bgl.of": run_lib((a0, a1) => { const r = (run_loop($bgl$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "bgl.flat": run_lib((a0, a1) => { const r = (run_loop($bgl$flat$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "slots.vals": run_lib((a0, a1) => { const r = (run_loop($slots$vals$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "slots.bufs": run_lib((a0, a1, a2) => { const r = (run_loop($slots$bufs$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "slots": run_lib((a0, a1) => { const r = (run_loop($slots$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "pass.geometry": run_lib((a0, a1, a2, a3, a4, a5) => { const r = (run_loop($pass$geometry$((a0), (a1), (a2), (a3), (a4), (a5)))); (a0); (a1); (a2); (a3); (a4); (a5); return r; }, 6),
  "pass.layout": run_lib((a0, a1, a2) => { const r = (run_loop($pass$layout$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "pass.playout": run_lib((a0) => { const r = (run_loop($pass$playout$((a0)))); (a0); return r; }, 1),
  "pass.uniforms.put": run_lib((a0, a1, a2) => { const r = (run_loop($pass$uniforms$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "pass.uniforms.go": run_lib((a0, a1, a2) => { const r = (run_loop($pass$uniforms$go$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "pass.uniforms": run_lib((a0, a1, a2) => { const r = (run_loop($pass$uniforms$((a0), nat_host(a1), (a2)))); (a0); BigInt(a1); (a2); return r; }, 3),
  "pass.group": run_lib((a0) => { const r = (run_loop($pass$group$((a0)))); (a0); return r; }, 1),
  "pass.pipeline": run_lib((a0) => { const r = (run_loop($pass$pipeline$((a0)))); (a0); return r; }, 1),
  "pass.encoder": run_lib((a0) => { const r = (run_loop($pass$encoder$((a0)))); (a0); return r; }, 1),
  "pass.query.on": run_lib((a0) => { const r = (run_loop($pass$query$on$((a0)))); (a0); return r; }, 1),
  "pass.query.at": run_lib((a0, a1) => { const r = (run_loop($pass$query$at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "pass.query": run_lib((a0) => { const r = (run_loop($pass$query$((a0)))); (a0); return r; }, 1),
  "pass.begin": run_lib((a0) => { const r = (run_loop($pass$begin$((a0)))); (a0); return r; }, 1),
  "pass.set": run_lib((a0) => { const r = (run_loop($pass$set$((a0)))); (a0); return r; }, 1),
  "pass.dispatch": run_lib((a0) => { const r = (run_loop($pass$dispatch$((a0)))); (a0); return r; }, 1),
  "pass.end": run_lib((a0) => { const r = (run_loop($pass$end$((a0)))); (a0); return r; }, 1),
  "pass.resolve.on": run_lib((a0) => { const r = (run_loop($pass$resolve$on$((a0)))); (a0); return r; }, 1),
  "pass.resolve.at": run_lib((a0, a1) => { const r = (run_loop($pass$resolve$at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "pass.resolve": run_lib((a0) => { const r = (run_loop($pass$resolve$((a0)))); (a0); return r; }, 1),
  "pass.finish": run_lib((a0) => { const r = (run_loop($pass$finish$((a0)))); (a0); return r; }, 1),
  "pass.release": run_lib((a0) => { const r = (run_loop($pass$release$((a0)))); (a0); return r; }, 1),
  "pass.timing.on": run_lib((a0) => { const r = (run_loop($pass$timing$on$((a0)))); (a0); return r; }, 1),
  "pass.timing.at": run_lib((a0, a1) => { const r = (run_loop($pass$timing$at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "pass.timing": run_lib((a0) => { const r = (run_loop($pass$timing$((a0)))); (a0); return r; }, 1),
  "prog.call.at": run_lib((a0, a1, a2, a3, a4, a5, a6, a7) => { const r = (run_loop($prog$call$at$((a0), (a1), (a2), (a3), (a4), (a5), (a6), (a7)))); (a0); (a1); (a2); (a3); (a4); (a5); (a6); (a7); return r; }, 8),
  "prog.call": run_lib((a0, a1, a2, a3, a4, a5, a6, a7) => { const r = (run_loop($prog$call$((a0), (a1), (a2), (a3), (a4), (a5), (a6), (a7)))); (a0); (a1); (a2); (a3); (a4); (a5); (a6); (a7); return r; }, 8),
  "METAL": run_lib(() => { const r = (run_loop($METAL$()));  return r; }, 0),
  "TS": run_lib(() => { const r = (run_loop($TS$()));  return r; }, 0),
  "F16": run_lib(() => { const r = (run_loop($F16$()));  return r; }, 0),
  "BOTH": run_lib(() => { const r = (run_loop($BOTH$()));  return r; }, 0),
  "NEITHER": run_lib(() => { const r = (run_loop($NEITHER$()));  return r; }, 0),
  "REVERSED": run_lib(() => { const r = (run_loop($REVERSED$()));  return r; }, 0),
  "bufs.go": run_lib((a0, a1, a2, a3) => { const r = (run_loop($bufs$go$(nat_host(a0), (a1), (a2), (a3)))); BigInt(a0); (a1); (a2); (a3); return r; }, 4),
  "bufs3": run_lib(() => { const r = (run_loop($bufs3$()));  return r; }, 0),
  "fx_pass": run_lib((a0) => { const r = (run_loop($fx_pass$((a0)))); (a0); return r; }, 1),
  "fx_fail.at": run_lib((a0, a1) => { const r = (run_loop($fx_fail$at$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "fx_fail": run_lib((a0, a1) => { const r = (run_loop($fx_fail$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "fx_call": run_lib((a0, a1) => { const r = (run_loop($fx_call$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "fx_life": run_lib((a0, a1) => { const r = (run_loop($fx_life$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "fx_refuse": run_lib((a0) => { const r = (run_loop($fx_refuse$((a0)))); (a0); return r; }, 1),
  "created": run_lib((a0) => { const r = (run_loop($created$((a0)))); (a0); return r; }, 1),
  "released": run_lib((a0) => { const r = (run_loop($released$((a0)))); (a0); return r; }, 1),
  "waited": run_lib((a0) => { const r = (run_loop($waited$((a0)))); (a0); return r; }, 1),
  "dispatched": run_lib((a0) => { const r = (run_loop($dispatched$((a0)))); (a0); return r; }, 1),
  "grouped": run_lib((a0) => { const r = (run_loop($grouped$((a0)))); (a0); return r; }, 1),
  "written": run_lib((a0) => { const r = (run_loop($written$((a0)))); (a0); return r; }, 1),
  "ncalls": run_lib((a0, a1) => { const r = (run_loop($ncalls$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "ncreated": run_lib((a0) => { const r = (run_loop($ncreated$((a0)))); (a0); return r; }, 1),
  "seen": run_lib((a0) => { const r = (run_loop($seen$((a0)))); (a0); return r; }, 1),
  "seq": run_lib((a0, a1) => { const r = (run_loop($seq$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "row": run_lib((a0, a1) => { const r = (run_loop($row$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "urow": run_lib((a0, a1) => { const r = (run_loop($urow$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "srow": run_lib((a0, a1) => { const r = (run_loop($srow$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "ush": run_lib((a0, a1, a2) => { const r = (run_loop($ush$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "lrow": run_lib((a0, a1) => { const r = (run_loop($lrow$((a0), (a1)))); (a0); (a1); return r; }, 2),
};
