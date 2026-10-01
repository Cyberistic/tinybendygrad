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

function io_args() {
  let xs = { $: "Nil" };
  for (let i = cli_args.length; i > 0; i -= 1) {
    xs = { $: "Con", head: cli_args[i - 1], tail: xs };
  }
  return xs;
}

io_eff("IO.args", io_args);

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

for (const k of ["IO.args","IO.print"]) {
  if (!(k in $0eff)) {
    throw new Error("bend: no effect registers " + k);
  }
}

// Program
// =======

function $main$() {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $IO$args$(_x_1), run_clo((_x_2) => {
  return (_x_3) => $IO$print$(($run$(($payload$(_x_2)))), _x_3);
}), _x_0);
});
}

function $IO$bind$(_m_0, _f_0, _k_0) {
  return run_tail(_m_0, run_clo((_x_0) => {
  return run_tail(_f_0(_x_0), _k_0);
}));
}

function $IO$args$(_k_0) {
  return { $: "$FFI", run: $0eff["IO.args"].run, need: $0eff["IO.args"].need, args: [], kont: (_k_0) };
}
function $IO$print$(_text_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.print"].run, need: $0eff["IO.print"].need, args: [(_text_0)], kont: (_k_0) };
}
function $run$(_fs_0) {
  const _r_0 = ($core_trace$(($imgs_of$(_fs_0)), ($labs_of$(_fs_0)), ($ws_of$(_fs_0))));
  const _ic_0 = ($share_f$(($Array$to_list$1260$(($imgs_of$(_fs_0))))));
  const _lc_0 = ($share_u$(($Array$to_list$1261$(($labs_of$(_fs_0))))));
  const _loss_0 = ($at_f$(0, _r_0));
  const _x_0 = ($show_f$(_ic_0));
  const _x_1 = ($show_u$(_lc_0));
  const _x_2 = (_x_0 + _x_1);
  const _x_3 = ($bits_at$(7, _r_0));
  const _x_4 = (" in=" + _x_2);
  const _x_5 = ($bits_at$(6, _r_0));
  const _x_6 = (_x_3 + _x_4);
  const _x_7 = ($bits_at$(5, _r_0));
  const _x_8 = (_x_5 + _x_6);
  const _x_9 = ($bits_at$(4, _r_0));
  const _x_10 = (_x_7 + _x_8);
  const _x_11 = ($bits_at$(3, _r_0));
  const _x_12 = (_x_9 + _x_10);
  const _x_13 = ($bits_at$(2, _r_0));
  const _x_14 = (_x_11 + _x_12);
  const _x_15 = ($bits_at$(1, _r_0));
  const _x_16 = (_x_13 + _x_14);
  const _x_17 = ($bits_at$(0, _r_0));
  const _x_18 = (_x_15 + _x_16);
  const _x_19 = (_x_17 + _x_18);
  const _x_20 = f32_show(_loss_0);
  const _x_21 = (" trace=" + _x_19);
  const _x_22 = (_x_20 + _x_21);
  return ("loss=" + _x_22);
}

function $payload$(_args_0) {
  if (_args_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _t_0 = _args_0["tail"];
    if (_t_0.$ === "Con") {
      const _p_0 = _t_0["head"];
      return $String$split$(_p_0, ",");
    } else {
      return {$: "Nil"};
    }
  }
}

function $core_trace$(_images_0, _labels_0, _weights_0) {
  return $batch$(($share_f$(($Array$to_list$1260$(_images_0)))), 0, ($share_u$(($Array$to_list$1261$(_labels_0)))), ($share_f$(($Array$to_list$1260$(_weights_0)))), {$: "Nil"}, 0);
}

function $imgs_of$(_fs_0) {
  return $put$(($List$replicate$(8, 0)), ($skip$(0, _fs_0)), array_new(3, 0), 0);
}

function $labs_of$(_fs_0) {
  return $put_u$(($List$replicate$(2, 0)), ($skip$(8, _fs_0)), array_new(1, 0), 0);
}

function $ws_of$(_fs_0) {
  return $put$(($List$replicate$(32, 0)), ($skip$(10, _fs_0)), array_new(5, 0), 0);
}

function $share_f$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": ($share_f$(_t_0))};
  }
}

function $Array$to_list$1260$(_a_0) {
  return $Array$to_list$go$1260$(_a_0, {$: "Nil"});
}

function $share_u$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": ($share_u$(_t_0))};
  }
}

function $Array$to_list$1261$(_a_0) {
  return $Array$to_list$go$1261$(_a_0, {$: "Nil"});
}

function $at_f$($0, $1) {
  for (;;) {
    {
      const _k_0 = $0;
      const _xs_0 = $1;
      if (_k_0 === 0) {
        if (_xs_0.$ === "Nil") {
          return 0;
        } else {
          const _h_0 = _xs_0["head"];
          return _h_0;
        }
      } else {
        const _p_0 = (_k_0 - 1);
        if (_xs_0.$ === "Nil") {
          return 0;
        } else {
          const _t_1 = _xs_0["tail"];
          $0 = _p_0;
          $1 = _t_1;
          continue;
        }
      }
    }
  }
}

function $bits_at$(_k_0, _xs_0) {
  const _x_0 = ($at_f$(_k_0, _xs_0));
  const _x_1 = ($U32$show$(f32_bits(_x_0)));
  return ("," + _x_1);
}

function $show_f$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($show_f$(_t_0));
    const _x_1 = ($U32$show$(f32_bits(_h_0)));
    const _x_2 = ("," + _x_0);
    return (_x_1 + _x_2);
  }
}

function $show_u$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($show_u$(_t_0));
    const _x_1 = ($U32$show$(_h_0));
    const _x_2 = ("," + _x_0);
    return (_x_1 + _x_2);
  }
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

function $batch$($0, $1, $2, $3, $4, $5) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _li_0 = $1;
      const _ls_0 = $2;
      const _ws_0 = $3;
      const _r_0 = $4;
      const _acc_0 = $5;
      if (_xs_0.$ === "Nil") {
        return $done$(_acc_0, _r_0);
      } else {
        const _a_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        if (_t_0.$ === "Nil") {
          return $done$(_acc_0, _r_0);
        } else {
          const _b_0 = _t_0["head"];
          const _t_1 = _t_0["tail"];
          if (_t_1.$ === "Nil") {
            return $done$(_acc_0, _r_0);
          } else {
            const _c_0 = _t_1["head"];
            const _t_2 = _t_1["tail"];
            if (_t_2.$ === "Nil") {
              return $done$(_acc_0, _r_0);
            } else {
              const _d_0 = _t_2["head"];
              const _xs5_0 = _t_2["tail"];
              if (_ls_0.$ === "Nil") {
                return $done$(_acc_0, _r_0);
              } else {
                const __0 = _ls_0["head"];
                const _lt_0 = _ls_0["tail"];
                const _s_0 = ($sample$({$: "Con", "head": _a_0, "tail": {$: "Con", "head": _b_0, "tail": {$: "Con", "head": _c_0, "tail": {$: "Con", "head": _d_0, "tail": {$: "Nil"}}}}}, {$: "Con", "head": __0, "tail": _lt_0}, _ws_0, _li_0));
                const _x_0 = ($at_f$(0, _s_0));
                $0 = _xs5_0;
                $1 = nat_chk(_li_0 + 1);
                $2 = _lt_0;
                $3 = _ws_0;
                $4 = _s_0;
                $5 = Math.fround(_acc_0 + _x_0);
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function $put$($0, $1, $2, $3) {
  for (;;) {
    {
      const _ns_0 = $0;
      const _xs_0 = $1;
      const _a_0 = $2;
      const _i_0 = $3;
      if (_ns_0.$ === "Nil") {
        if (_xs_0.$ === "Nil") {
          return _a_0;
        } else {
          return _a_0;
        }
      } else {
        const _ns2_0 = _ns_0["tail"];
        if (_xs_0.$ === "Nil") {
          return _a_0;
        } else {
          const _h_1 = _xs_0["head"];
          const _t_1 = _xs_0["tail"];
          const _x_0 = ($f32_of_bits$(($parse$(_h_1))));
          $0 = _ns2_0;
          $1 = _t_1;
          $2 = (_a_0[_i_0 % _a_0.length] = _x_0, _a_0);
          $3 = ((_i_0 + 1) >>> 0);
          continue;
        }
      }
    }
  }
}

function $List$replicate$(_n_0, _x_0) {
  if (_n_0 === 0) {
    return {$: "Nil"};
  } else {
    const _p_0 = (_n_0 - 1);
    return {$: "Con", "head": _x_0, "tail": ($List$replicate$(_p_0, _x_0))};
  }
}

function $skip$($0, $1) {
  for (;;) {
    {
      const _n_0 = $0;
      const _xs_0 = $1;
      if (_n_0 === 0) {
        if (_xs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _h_0 = _xs_0["head"];
          const _t_0 = _xs_0["tail"];
          return {$: "Con", "head": _h_0, "tail": _t_0};
        }
      } else {
        const _p_0 = (_n_0 - 1);
        if (_xs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _t_1 = _xs_0["tail"];
          $0 = _p_0;
          $1 = _t_1;
          continue;
        }
      }
    }
  }
}

function $put_u$($0, $1, $2, $3) {
  for (;;) {
    {
      const _ns_0 = $0;
      const _xs_0 = $1;
      const _a_0 = $2;
      const _i_0 = $3;
      if (_ns_0.$ === "Nil") {
        if (_xs_0.$ === "Nil") {
          return _a_0;
        } else {
          return _a_0;
        }
      } else {
        const _ns2_0 = _ns_0["tail"];
        if (_xs_0.$ === "Nil") {
          return _a_0;
        } else {
          const _h_1 = _xs_0["head"];
          const _t_1 = _xs_0["tail"];
          const _x_0 = ($parse$(_h_1));
          $0 = _ns2_0;
          $1 = _t_1;
          $2 = (_a_0[_i_0 % _a_0.length] = _x_0, _a_0);
          $3 = ((_i_0 + 1) >>> 0);
          continue;
        }
      }
    }
  }
}

function $Array$to_list$go$1260$($0, $1) {
  for (;;) {
    {
      const _a_0 = $0;
      const _acc_0 = $1;
      if (_a_0.length === 1) {
        const _x_0 = _a_0[0];
        return {$: "Con", "head": _x_0, "tail": _acc_0};
      } else {
        const _xs_0 = _a_0.slice(0, _a_0.length >> 1);
        const _ys_0 = _a_0.slice(_a_0.length >> 1);
        $0 = _xs_0;
        $1 = ($Array$to_list$go$1260$(_ys_0, _acc_0));
        continue;
      }
    }
  }
}

function $Array$to_list$go$1261$($0, $1) {
  for (;;) {
    {
      const _a_0 = $0;
      const _acc_0 = $1;
      if (_a_0.length === 1) {
        const _x_0 = _a_0[0];
        return {$: "Con", "head": _x_0, "tail": _acc_0};
      } else {
        const _xs_0 = _a_0.slice(0, _a_0.length >> 1);
        const _ys_0 = _a_0.slice(_a_0.length >> 1);
        $0 = _xs_0;
        $1 = ($Array$to_list$go$1261$(_ys_0, _acc_0));
        continue;
      }
    }
  }
}

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
}

function $String$split$fin$(_c_0, _r_0, _cut_0) {
  if (!_cut_0) {
    return $String$split$push$(_c_0, _r_0);
  } else {
    return {$: "Con", "head": "", "tail": _r_0};
  }
}

function $Char$is_eq$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return (_x_0 === _x_1);
}

function $done$(_acc_0, _r_0) {
  return {$: "Con", "head": Math.fround(_acc_0 / 2), "tail": _r_0};
}

function $sample$(_row_0, _ls_0, _ws_0, _li_0) {
  const _h_0 = ($rows$(($split$(($cs5$()), _ws_0, {$: "Nil"}, {$: "Nil"})), _row_0, {$: "Nil"}));
  const _z_0 = ($rows$(($split$(($cs4$()), ($skip_f$(15, _ws_0)), {$: "Nil"}, {$: "Nil"})), _h_0, {$: "Nil"}));
  return {$: "Con", "head": ($cross_entropy$(_z_0, _ls_0, _li_0)), "tail": ($List$append$(_h_0, _z_0))};
}

function $f32_of_bits$(_b_0) {
  return f32_from_bits(_b_0);
}

function $parse$(_s_0) {
  return $parse$maybe$(($U32$read$(_s_0)));
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
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

function $rows$($0, $1, $2) {
  for (;;) {
    {
      const _rs_0 = $0;
      const _x_0 = $1;
      const _out_0 = $2;
      if (_rs_0.$ === "Nil") {
        return _out_0;
      } else {
        const _r_0 = _rs_0["head"];
        const _rt_0 = _rs_0["tail"];
        $0 = _rt_0;
        $1 = _x_0;
        $2 = {$: "Con", "head": ($dot$(_r_0, _x_0)), "tail": _out_0};
        continue;
      }
    }
  }
}

function $split$($0, $1, $2, $3) {
  for (;;) {
    {
      const _marks_0 = $0;
      const _w_0 = $1;
      const _cur_0 = $2;
      const _out_0 = $3;
      if (_marks_0.$ === "Nil") {
        if (_w_0.$ === "Nil") {
          return _out_0;
        } else {
          return _out_0;
        }
      } else {
        const _t_1 = _marks_0["head"];
        if (_t_1 === 0) {
          const _md_0 = _marks_0["tail"];
          if (_w_0.$ === "Nil") {
            return _out_0;
          } else {
            const _h_1 = _w_0["head"];
            const _t_2 = _w_0["tail"];
            $0 = _md_0;
            $1 = _t_2;
            $2 = {$: "Nil"};
            $3 = {$: "Con", "head": ($List$reverse$({$: "Con", "head": _h_1, "tail": _cur_0})), "tail": _out_0};
            continue;
          }
        } else {
          const _md_1 = _marks_0["tail"];
          if (_w_0.$ === "Nil") {
            return _out_0;
          } else {
            const _h_2 = _w_0["head"];
            const _t_3 = _w_0["tail"];
            $0 = _md_1;
            $1 = _t_3;
            $2 = {$: "Con", "head": _h_2, "tail": _cur_0};
            $3 = _out_0;
            continue;
          }
        }
      }
    }
  }
}

function $cs5$() {
  return $List$append$(($List$append$(($marks$(4)), ($marks$(4)))), ($marks$(4)));
}

function $cs4$() {
  return $List$append$(($List$append$(($marks$(3)), ($marks$(3)))), ($marks$(3)));
}

function $skip_f$($0, $1) {
  for (;;) {
    {
      const _n_0 = $0;
      const _xs_0 = $1;
      if (_n_0 === 0) {
        if (_xs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _h_0 = _xs_0["head"];
          const _t_0 = _xs_0["tail"];
          return {$: "Con", "head": _h_0, "tail": _t_0};
        }
      } else {
        const _p_0 = (_n_0 - 1);
        if (_xs_0.$ === "Nil") {
          return {$: "Nil"};
        } else {
          const _t_1 = _xs_0["tail"];
          $0 = _p_0;
          $1 = _t_1;
          continue;
        }
      }
    }
  }
}

function $cross_entropy$(_z_0, _ls_0, _k_0) {
  const _x_0 = ($exp_sum$(_z_0));
  const _x_1 = ($at_u$(_k_0, _ls_0));
  const _x_2 = ($at_f$(_x_1, _z_0));
  const _x_3 = Math.fround(Math.log(_x_0));
  const _x_4 = Math.fround(Math.exp(_x_2));
  return Math.fround(_x_3 - _x_4);
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

function $parse$maybe$(_m_0) {
  if (_m_0.$ === "Some") {
    const _b_0 = _m_0["value"];
    return _b_0;
  } else {
    return 0;
  }
}

function $U32$read$(_s_0) {
  if (_s_0 === "") {
    return {$: "None"};
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    return $U32$read$go$((_h_0 + _t_0), 0);
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

function $dot$(_r_0, _xs_0) {
  if (_r_0.$ === "Nil") {
    if (_xs_0.$ === "Nil") {
      return 0;
    } else {
      return 0;
    }
  } else {
    const _a_0 = _r_0["head"];
    const _t_0 = _r_0["tail"];
    if (_xs_0.$ === "Nil") {
      const _x_0 = ($dot$(_t_0, {$: "Nil"}));
      return Math.fround(_x_0 + _a_0);
    } else {
      const _b_1 = _xs_0["head"];
      const _u_1 = _xs_0["tail"];
      const _x_1 = Math.fround(_a_0 * _b_1);
      const _x_2 = ($dot$(_t_0, _u_1));
      return Math.fround(_x_1 + _x_2);
    }
  }
}

function $List$reverse$(_xs_0) {
  return $List$reverse$go$(_xs_0, {$: "Nil"});
}

function $marks$(_n_0) {
  return $List$append$(($List$replicate$(_n_0, 1)), ($List$replicate$(1, 0)));
}

function $exp_sum$(_z_0) {
  if (_z_0.$ === "Nil") {
    return 0;
  } else {
    const _v_0 = _z_0["head"];
    const _t_0 = _z_0["tail"];
    const _x_0 = Math.fround(Math.exp(_v_0));
    const _x_1 = ($exp_sum$(_t_0));
    return Math.fround(_x_0 + _x_1);
  }
}

function $at_u$($0, $1) {
  for (;;) {
    {
      const _k_0 = $0;
      const _xs_0 = $1;
      if (_k_0 === 0) {
        if (_xs_0.$ === "Nil") {
          return 0;
        } else {
          const _h_0 = _xs_0["head"];
          return _h_0;
        }
      } else {
        const _p_0 = (_k_0 - 1);
        if (_xs_0.$ === "Nil") {
          return 0;
        } else {
          const _t_1 = _xs_0["tail"];
          $0 = _p_0;
          $1 = _t_1;
          continue;
        }
      }
    }
  }
}

function $U32$read$go$($0, $1, $2) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      const _acc_0 = $1;
      if (_s_0 === "") {
        return {$: "Some", "value": _acc_0};
      } else {
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        const _x_0 = _t_0.codePointAt(0);
        const _x_1 = (Math.imul(_acc_0, 10) >>> 0);
        const _x_2 = ((_x_0 - 48) >>> 0);
        const _n_0 = ((_x_1 + _x_2) >>> 0);
        const _x_3 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $0 = _t_1;
        $1 = _n_0;
        $2 = (_x_3 === _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _t_0 = $0;
      const _n_0 = $1;
      const _ok_0 = $2;
      if (_ok_0) {
        $0 = _t_0;
        $1 = _n_0;
        $pc = 0; continue;
      } else {
        return {$: "None"};
      }
    }
  }
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

function $U32$read$if$($0, $1, $2) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _s_0 = $0;
      const _acc_0 = $1;
      if (_s_0 === "") {
        return {$: "Some", "value": _acc_0};
      } else {
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_1 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        const _x_0 = _t_0.codePointAt(0);
        const _x_1 = (Math.imul(_acc_0, 10) >>> 0);
        const _x_2 = ((_x_0 - 48) >>> 0);
        const _n_0 = ((_x_1 + _x_2) >>> 0);
        const _x_3 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $0 = _t_1;
        $1 = _n_0;
        $2 = (_x_3 === _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _t_0 = $0;
      const _n_0 = $1;
      const _ok_0 = $2;
      if (_ok_0) {
        $0 = _t_0;
        $1 = _n_0;
        $pc = 0; continue;
      } else {
        return {$: "None"};
      }
    }
  }
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