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
// Program
// =======

function $f32_of_bits$(_b_0) {
  return f32_from_bits(_b_0);
}

function $parse$maybe$(_m_0) {
  if (_m_0.$ === "Some") {
    const _b_0 = _m_0["value"];
    return _b_0;
  } else {
    return 0;
  }
}

function $parse$(_s_0) {
  return $parse$maybe$(($U32$read$(_s_0)));
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

function $share_u$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": ($share_u$(_t_0))};
  }
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

function $bits_at$(_k_0, _xs_0) {
  const _x_0 = ($at_f$(_k_0, _xs_0));
  const _x_1 = ($U32$show$(f32_bits(_x_0)));
  return ("," + _x_1);
}

function $marks$(_n_0) {
  return $List$append$(($List$replicate$(_n_0, 1)), ($List$replicate$(1, 0)));
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

function $cross_entropy$(_z_0, _ls_0, _k_0) {
  const _x_0 = ($exp_sum$(_z_0));
  const _x_1 = ($at_u$(_k_0, _ls_0));
  const _x_2 = ($at_f$(_x_1, _z_0));
  const _x_3 = Math.fround(Math.log(_x_0));
  const _x_4 = Math.fround(Math.exp(_x_2));
  return Math.fround(_x_3 - _x_4);
}

function $sample$(_row_0, _ls_0, _ws_0, _li_0) {
  const _h_0 = ($rows$(($split$(($cs5$()), _ws_0, {$: "Nil"}, {$: "Nil"})), _row_0, {$: "Nil"}));
  const _z_0 = ($rows$(($split$(($cs4$()), ($skip_f$(15, _ws_0)), {$: "Nil"}, {$: "Nil"})), _h_0, {$: "Nil"}));
  return {$: "Con", "head": ($cross_entropy$(_z_0, _ls_0, _li_0)), "tail": ($List$append$(_h_0, _z_0))};
}

function $done$(_acc_0, _r_0) {
  return {$: "Con", "head": Math.fround(_acc_0 / 2), "tail": _r_0};
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

function $core_trace$(_images_0, _labels_0, _weights_0) {
  return $batch$(($share_f$(($Array$to_list$1260$(_images_0)))), 0, ($share_u$(($Array$to_list$1261$(_labels_0)))), ($share_f$(($Array$to_list$1260$(_weights_0)))), {$: "Nil"}, 0);
}

function $core_step$(_images_0, _labels_0, _weights_0) {
  return $at_f$(0, ($core_trace$(_images_0, _labels_0, _weights_0)));
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

function $U32$read$(_s_0) {
  if (_s_0 === "") {
    return {$: "None"};
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    return $U32$read$go$((_h_0 + _t_0), 0);
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

function $List$replicate$(_n_0, _x_0) {
  if (_n_0 === 0) {
    return {$: "Nil"};
  } else {
    const _p_0 = (_n_0 - 1);
    return {$: "Con", "head": _x_0, "tail": ($List$replicate$(_p_0, _x_0))};
  }
}

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
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

function $List$reverse$(_xs_0) {
  return $List$reverse$go$(_xs_0, {$: "Nil"});
}

function $Array$to_list$1260$(_a_0) {
  return $Array$to_list$go$1260$(_a_0, {$: "Nil"});
}

function $Array$to_list$1261$(_a_0) {
  return $Array$to_list$go$1261$(_a_0, {$: "Nil"});
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

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
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

function $String$split$push$(_c_0, _ps_0) {
  if (_ps_0.$ === "Nil") {
    return {$: "Con", "head": (_c_0 + ""), "tail": {$: "Nil"}};
  } else {
    const _h_0 = _ps_0["head"];
    const _t_0 = _ps_0["tail"];
    return {$: "Con", "head": (_c_0 + _h_0), "tail": _t_0};
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
export default {
  "f32_of_bits": run_lib((a0) => { const r = (run_loop($f32_of_bits$((a0)))); (a0); return r; }, 1),
  "parse.maybe": run_lib((a0) => { const r = (run_loop($parse$maybe$((a0)))); (a0); return r; }, 1),
  "parse": run_lib((a0) => { const r = (run_loop($parse$((a0)))); (a0); return r; }, 1),
  "payload": run_lib((a0) => { const r = (run_loop($payload$((a0)))); (a0); return r; }, 1),
  "skip": run_lib((a0, a1) => { const r = (run_loop($skip$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "skip_f": run_lib((a0, a1) => { const r = (run_loop($skip_f$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "put": run_lib((a0, a1, a2, a3) => { const r = (run_loop($put$($0m0(a0), (a1), (a2), (a3)))); $0m1(a0); (a1); (a2); (a3); return r; }, 4),
  "put_u": run_lib((a0, a1, a2, a3) => { const r = (run_loop($put_u$($0m0(a0), (a1), (a2), (a3)))); $0m1(a0); (a1); (a2); (a3); return r; }, 4),
  "imgs_of": run_lib((a0) => { const r = (run_loop($imgs_of$((a0)))); (a0); return r; }, 1),
  "labs_of": run_lib((a0) => { const r = (run_loop($labs_of$((a0)))); (a0); return r; }, 1),
  "ws_of": run_lib((a0) => { const r = (run_loop($ws_of$((a0)))); (a0); return r; }, 1),
  "share_f": run_lib((a0) => { const r = (run_loop($share_f$((a0)))); (a0); return r; }, 1),
  "share_u": run_lib((a0) => { const r = (run_loop($share_u$((a0)))); (a0); return r; }, 1),
  "at_f": run_lib((a0, a1) => { const r = (run_loop($at_f$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "at_u": run_lib((a0, a1) => { const r = (run_loop($at_u$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "exp_sum": run_lib((a0) => { const r = (run_loop($exp_sum$((a0)))); (a0); return r; }, 1),
  "show_f": run_lib((a0) => { const r = (run_loop($show_f$((a0)))); (a0); return r; }, 1),
  "show_u": run_lib((a0) => { const r = (run_loop($show_u$((a0)))); (a0); return r; }, 1),
  "bits_at": run_lib((a0, a1) => { const r = (run_loop($bits_at$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "marks": run_lib((a0) => { const r = $0m1(run_loop($marks$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "split": run_lib((a0, a1, a2, a3) => { const r = (run_loop($split$($0m0(a0), (a1), (a2), (a3)))); $0m1(a0); (a1); (a2); (a3); return r; }, 4),
  "cs5": run_lib(() => { const r = $0m1(run_loop($cs5$()));  return r; }, 0),
  "cs4": run_lib(() => { const r = $0m1(run_loop($cs4$()));  return r; }, 0),
  "dot": run_lib((a0, a1) => { const r = (run_loop($dot$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "rows": run_lib((a0, a1, a2) => { const r = (run_loop($rows$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "cross_entropy": run_lib((a0, a1, a2) => { const r = (run_loop($cross_entropy$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "sample": run_lib((a0, a1, a2, a3) => { const r = (run_loop($sample$((a0), (a1), (a2), nat_host(a3)))); (a0); (a1); (a2); BigInt(a3); return r; }, 4),
  "done": run_lib((a0, a1) => { const r = (run_loop($done$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "batch": run_lib((a0, a1, a2, a3, a4, a5) => { const r = (run_loop($batch$((a0), nat_host(a1), (a2), (a3), (a4), (a5)))); (a0); BigInt(a1); (a2); (a3); (a4); (a5); return r; }, 6),
  "core_trace": run_lib((a0, a1, a2) => { const r = (run_loop($core_trace$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "core_step": run_lib((a0, a1, a2) => { const r = (run_loop($core_step$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "run": run_lib((a0) => { const r = (run_loop($run$((a0)))); (a0); return r; }, 1),
};
