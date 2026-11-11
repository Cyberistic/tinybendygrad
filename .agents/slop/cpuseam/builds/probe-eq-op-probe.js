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
  return {$: a < b ? "LT" : a === b ? "EQ" : "GT"};
}

function tup_new(a, b) {
  return {$: "Tuple", fst: a, snd: b};
}

function nat_divmod(a, b) {
  return tup_new(b && Math.trunc(a / b), b ? a % b : a);
}

function nat_chk(n) {
  if (n > 281474976710655) {
    throw "bend: a Nat past the largest immediate 2^48-1";
  }
  return n;
}

function nat_in(n) {
  if (!Number.isInteger(n) || n < 0 || n > 2 ** 53) {
    throw "bend: expected a Nat host number: an integer from 0 to 2^53";
  }
  return n;
}

function f32_show(x) {
  let s = "nan";
  for (let p = 1; x === x && p <= 9 && f32_round(s) !== x; p += 1) {
    s = String(Number(x.toExponential(p - 1)));
  }
  return (Object.is(x, -0) ? "-0" : s).replace("Infinity", "inf");
}

function f32_bits(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function f32_from_bits(u) {
  return new Float32Array(new Uint32Array([u]).buffer)[0];
}

function f32_read(s) {
  const re = /^[\t\n\v\f\r ]*[+-]?((\d+(?:\.\d*)?|\.\d+)(e[+-]?\d+)?|inf(inity)?|nan)$/i;
  return re.test(s) ? {$: "Some", value: f32_round(
    s.replace(/inf\w*/i, "Infinity"))} : {$: "None"};
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

const char_new = function char_new(c) {
  return c < 55296 || c >= 57344 && c <= 1114111 ? String.fromCodePoint(c) : String.fromCharCode(56320, c >>> 22, c >>> 11 & 2047, c & 2047);
};

function char_len(s, at = 0) {
  return s[at] === "\uDC00" ? 4 : s.codePointAt(at) > 0xFFFF ? 2 : 1;
}

function char_code(s) {
  return s.length < 4 ? s.codePointAt(0)
    : (s.charCodeAt(1) << 22 | s.charCodeAt(2) << 11 | s.charCodeAt(3)) >>> 0;
}

function string_contains(s, p) {
  // A match starts at a Char, not inside a packed U32 code.
  for (let at = 0; at <= s.length; at += char_len(s, at)) {
    if (s.startsWith(p, at)) {
      return true;
    }
  }
  return false;
}

function str_out(s) {
  return s.replace(/\uDC00[^]{3}/gu, "\uFFFD");
}

function str_in(s) {
  return s.replace(/\p{Cs}/gu, "\uFFFD");
}

// Array
// =====

function array_new(d, v, lgs) {
  if (d > 31 - lgs) {
    throw "bend: an array past the deepest block class 31 (depth + log2 words per cell)";
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
  const old = a[i %= a.length];
  a[i] = f(old);
  return tup_new(a, old);
}

// Run
// ===

function run_tail(f, x) {
  return {$: "$JMP", f: f.j?.f === f ? f.j : f, x};
}

function run_clo(j) {
  const f = (x) => run_loop(j(x));
  f.j = j;
  j.f = f;
  return f;
}

function run_loop(r) {
  while (r !== null && typeof r === "object" && r.$ === "$JMP") {
    r = r.f(r.x);
  }
  return r;
}

function run_lib(f, n) {
  return (...a) => a.length < n ? run_lib((...b) => f(...a, ...b), n - a.length)
    : run_loop(f(...a));
}

// Effect
// ======

const $0eff = Object.create(null);
const io_file_append = new Set();

function io_eff(k, run) {
  if (arguments.length > 2) {
    throw new Error("bend: " + k + " takes no need: an effect that waits parks itself");
  }
  if (k in $0eff) {
    throw new Error("bend: two effects register " + k);
  }
  $0eff[k] = run;
}
(() => {
// IO
// ==

function io_print(text) {
  io_std(io_bytes(text + "\n"));
  return { $: "Unit" };
}

io_eff("IO.print", io_print);

})();

// Program
// =======

function $main() {
  const _ops1_0 = {$: "Con", "head": {$: "OpsCAST"}, "tail": {$: "Con", "head": {$: "OpsINDEX"}, "tail": {$: "Con", "head": {$: "OpsADD"}, "tail": {$: "Con", "head": {$: "OpsMUL"}, "tail": {$: "Con", "head": {$: "OpsLOAD"}, "tail": {$: "Con", "head": {$: "OpsSTORE"}, "tail": {$: "Con", "head": {$: "OpsCONST"}, "tail": {$: "Con", "head": {$: "OpsRANGE"}, "tail": {$: "Con", "head": {$: "OpsWHERE"}, "tail": {$: "Con", "head": {$: "OpsXOR"}, "tail": {$: "Con", "head": {$: "OpsOR"}, "tail": {$: "Nil"}}}}}}}}}}}};
  const _ops2_0 = {$: "Con", "head": {$: "OpsCAST"}, "tail": {$: "Con", "head": {$: "OpsINDEX"}, "tail": {$: "Con", "head": {$: "OpsADD"}, "tail": {$: "Con", "head": {$: "OpsMUL"}, "tail": {$: "Con", "head": {$: "OpsLOAD"}, "tail": {$: "Con", "head": {$: "OpsSTORE"}, "tail": {$: "Con", "head": {$: "OpsCONST"}, "tail": {$: "Con", "head": {$: "OpsRANGE"}, "tail": {$: "Con", "head": {$: "OpsWHERE"}, "tail": {$: "Con", "head": {$: "OpsXOR"}, "tail": {$: "Con", "head": {$: "OpsOR"}, "tail": {$: "Nil"}}}}}}}}}}}};
  const _big1_0 = $$rep(_ops1_0, 64);
  const _big2_0 = $$rep(_ops2_0, 64);
  const _same_0 = $$agree($$old_all(_big1_0), $$new_all(_big2_0));
  return (_x_0) => $IO_print($$String_concat({$: "Con", "head": "same ", "tail": {$: "Con", "head": $$probe_b_b(_same_0), "tail": {$: "Con", "head": "\n", "tail": {$: "Nil"}}}}), _x_0);
}

function $rep(_xs_0, _n_0) {
  return $rep_go(_xs_0, $$List_replicate(_n_0, {$: "OpsSPECIAL"}));
}

function $agree(_a_0, _b_0) {
  if (_a_0) {
    if (_b_0) {
      return true;
    } else {
      return false;
    }
  } else {
    if (_b_0) {
      return false;
    } else {
      return true;
    }
  }
}

function $old_all(_xs_0) {
  return $old_all_go(_xs_0);
}

function $new_all(_xs_0) {
  return $new_all_go(_xs_0);
}

function $IO_print(_text_0, _k_0) {
  return { $: "IO.print", args: [str_out(_text_0)], kont: (x) => _k_0(x) };
}

function $String_concat(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = $$String_concat(_t_0);
    return (_h_0 + _x_0);
  }
}

function $probe_b_b(_x_0) {
  if (_x_0) {
    return "T";
  } else {
    return "F";
  }
}

function $rep_go($0, $1) {
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
        $1 = $$List_append(_acc_0, {$: "Con", "head": _h_0, "tail": {$: "Nil"}});
        continue;
      }
    }
  }
}

function $List_replicate(_n_0, _x_0) {
  if (_n_0 == 0) {
    return {$: "Nil"};
  } else {
    const _p_0 = (_n_0 - 1);
    return {$: "Con", "head": _x_0, "tail": $$List_replicate(_p_0, _x_0)};
  }
}

function $old_all_go(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return false;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = $$old_work(_h_0);
    const _x_1 = $$old_all_go(_t_0);
    return (_x_0 || _x_1);
  }
}

function $new_all_go(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return false;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = $$new_work(_h_0);
    const _x_1 = $$new_all_go(_t_0);
    return (_x_0 || _x_1);
  }
}

function $List_append(_xs_0, _ys_0) {
  if (_xs_0.$ === "Nil") {
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": $$List_append(_t_0, _ys_0)};
  }
}

function $old_work(_op_0) {
  const _x_0 = $$eq_op(_op_0, {$: "OpsCAST"});
  const _x_1 = $$eq_op(_op_0, {$: "OpsINDEX"});
  const _x_2 = $$eq_op(_op_0, {$: "OpsADD"});
  const _x_3 = $$eq_op(_op_0, {$: "OpsMUL"});
  const _x_4 = $$eq_op(_op_0, {$: "OpsLOAD"});
  const _x_5 = $$eq_op(_op_0, {$: "OpsSTORE"});
  const _x_6 = $$eq_op(_op_0, {$: "OpsCONST"});
  const _x_7 = $$eq_op(_op_0, {$: "OpsRANGE"});
  const _x_8 = $$eq_op(_op_0, {$: "OpsWHERE"});
  const _x_9 = $$eq_op(_op_0, {$: "OpsXOR"});
  const _x_10 = (_x_6 || _x_7);
  const _x_11 = (_x_8 || _x_9);
  const _x_12 = (_x_4 || _x_5);
  const _x_13 = (_x_10 || _x_11);
  const _x_14 = (_x_2 || _x_3);
  const _x_15 = (_x_12 || _x_13);
  const _x_16 = (_x_0 || _x_1);
  const _x_17 = (_x_14 || _x_15);
  return (_x_16 || _x_17);
}

function $new_work(_op_0) {
  const _x_0 = $$is_cast(_op_0);
  const _x_1 = $$is_index(_op_0);
  const _x_2 = $$is_add(_op_0);
  const _x_3 = $$is_mul(_op_0);
  const _x_4 = $$is_load(_op_0);
  const _x_5 = $$is_store(_op_0);
  const _x_6 = $$is_const(_op_0);
  const _x_7 = $$is_range(_op_0);
  const _x_8 = $$is_where(_op_0);
  const _x_9 = $$is_xor(_op_0);
  const _x_10 = (_x_6 || _x_7);
  const _x_11 = (_x_8 || _x_9);
  const _x_12 = (_x_4 || _x_5);
  const _x_13 = (_x_10 || _x_11);
  const _x_14 = (_x_2 || _x_3);
  const _x_15 = (_x_12 || _x_13);
  const _x_16 = (_x_0 || _x_1);
  const _x_17 = (_x_14 || _x_15);
  return (_x_16 || _x_17);
}

function $eq_op(_x_0, _y_0) {
  if (_x_0.$ === "OpsSPECIAL") {
    if (_y_0.$ === "OpsSPECIAL") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsBUFFER") {
    if (_y_0.$ === "OpsBUFFER") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsALLOC") {
    if (_y_0.$ === "OpsALLOC") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsNOOP") {
    if (_y_0.$ === "OpsNOOP") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsREWRITE_ERROR") {
    if (_y_0.$ === "OpsREWRITE_ERROR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsPARAM") {
    if (_y_0.$ === "OpsPARAM") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsREFPARAM") {
    if (_y_0.$ === "OpsREFPARAM") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCALL") {
    if (_y_0.$ === "OpsCALL") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsPROGRAM") {
    if (_y_0.$ === "OpsPROGRAM") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsLINEAR") {
    if (_y_0.$ === "OpsLINEAR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSOURCE") {
    if (_y_0.$ === "OpsSOURCE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsBINARY") {
    if (_y_0.$ === "OpsBINARY") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSINK") {
    if (_y_0.$ === "OpsSINK") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsAFTER") {
    if (_y_0.$ === "OpsAFTER") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSTACK") {
    if (_y_0.$ === "OpsSTACK") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsGETADDR") {
    if (_y_0.$ === "OpsGETADDR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsINDEX") {
    if (_y_0.$ === "OpsINDEX") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSHRINK") {
    if (_y_0.$ === "OpsSHRINK") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsLOAD") {
    if (_y_0.$ === "OpsLOAD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSTORE") {
    if (_y_0.$ === "OpsSTORE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsWMMA") {
    if (_y_0.$ === "OpsWMMA") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCAST") {
    if (_y_0.$ === "OpsCAST") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsBITCAST") {
    if (_y_0.$ === "OpsBITCAST") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsEXP2") {
    if (_y_0.$ === "OpsEXP2") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsLOG2") {
    if (_y_0.$ === "OpsLOG2") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSIN") {
    if (_y_0.$ === "OpsSIN") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSQRT") {
    if (_y_0.$ === "OpsSQRT") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsRECIP") {
    if (_y_0.$ === "OpsRECIP") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsNEG") {
    if (_y_0.$ === "OpsNEG") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsTRUNC") {
    if (_y_0.$ === "OpsTRUNC") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsADD") {
    if (_y_0.$ === "OpsADD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMUL") {
    if (_y_0.$ === "OpsMUL") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSHL") {
    if (_y_0.$ === "OpsSHL") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSHR") {
    if (_y_0.$ === "OpsSHR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsTRUNCDIV") {
    if (_y_0.$ === "OpsTRUNCDIV") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMAX") {
    if (_y_0.$ === "OpsMAX") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsTRUNCMOD") {
    if (_y_0.$ === "OpsTRUNCMOD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCMPLT") {
    if (_y_0.$ === "OpsCMPLT") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCMPNE") {
    if (_y_0.$ === "OpsCMPNE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCMPEQ") {
    if (_y_0.$ === "OpsCMPLT") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsXOR") {
    if (_y_0.$ === "OpsXOR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsOR") {
    if (_y_0.$ === "OpsOR") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsAND") {
    if (_y_0.$ === "OpsAND") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsTHREEFRY") {
    if (_y_0.$ === "OpsTHREEFRY") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSUB") {
    if (_y_0.$ === "OpsSUB") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsFDIV") {
    if (_y_0.$ === "OpsFDIV") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsPOW") {
    if (_y_0.$ === "OpsPOW") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsDIV") {
    if (_y_0.$ === "OpsDIV") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMOD") {
    if (_y_0.$ === "OpsMOD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsWHERE") {
    if (_y_0.$ === "OpsWHERE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMULACC") {
    if (_y_0.$ === "OpsMULACC") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsBARRIER") {
    if (_y_0.$ === "OpsBARRIER") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsRANGE") {
    if (_y_0.$ === "OpsRANGE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsIF") {
    if (_y_0.$ === "OpsIF") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsEND") {
    if (_y_0.$ === "OpsEND") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsENDIF") {
    if (_y_0.$ === "OpsENDIF") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsBACKEDGE") {
    if (_y_0.$ === "OpsBACKEDGE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCONST") {
    if (_y_0.$ === "OpsCONST") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCUSTOM") {
    if (_y_0.$ === "OpsCUSTOM") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCUSTOMI") {
    if (_y_0.$ === "OpsCUSTOMI") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsINS") {
    if (_y_0.$ === "OpsINS") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCONTIGUOUS_BACKWARD") {
    if (_y_0.$ === "OpsCONTIGUOUS_BACKWARD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsDETACH") {
    if (_y_0.$ === "OpsDETACH") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsSTAGE") {
    if (_y_0.$ === "OpsSTAGE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCOPY") {
    if (_y_0.$ === "OpsCOPY") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMSELECT") {
    if (_y_0.$ === "OpsMSELECT") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsMSTACK") {
    if (_y_0.$ === "OpsMSTACK") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsCUSTOM_FUNCTION") {
    if (_y_0.$ === "OpsCUSTOM_FUNCTION") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsRESHAPE") {
    if (_y_0.$ === "OpsRESHAPE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsPERMUTE") {
    if (_y_0.$ === "OpsPERMUTE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsEXPAND") {
    if (_y_0.$ === "OpsEXPAND") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsPAD") {
    if (_y_0.$ === "OpsPAD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsUNSHARD") {
    if (_y_0.$ === "OpsUNSHARD") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsREDUCE") {
    if (_y_0.$ === "OpsREDUCE") {
      return true;
    } else {
      return false;
    }
  } else if (_x_0.$ === "OpsALLREDUCE") {
    if (_y_0.$ === "OpsALLREDUCE") {
      return true;
    } else {
      return false;
    }
  } else {
    if (_y_0.$ === "OpsPYLITERAL") {
      return true;
    } else {
      return false;
    }
  }
}

function $is_cast(_x_0) {
  if (_x_0.$ === "OpsCAST") {
    return true;
  } else {
    return false;
  }
}

function $is_index(_x_0) {
  if (_x_0.$ === "OpsINDEX") {
    return true;
  } else {
    return false;
  }
}

function $is_add(_x_0) {
  if (_x_0.$ === "OpsADD") {
    return true;
  } else {
    return false;
  }
}

function $is_mul(_x_0) {
  if (_x_0.$ === "OpsMUL") {
    return true;
  } else {
    return false;
  }
}

function $is_load(_x_0) {
  if (_x_0.$ === "OpsLOAD") {
    return true;
  } else {
    return false;
  }
}

function $is_store(_x_0) {
  if (_x_0.$ === "OpsSTORE") {
    return true;
  } else {
    return false;
  }
}

function $is_const(_x_0) {
  if (_x_0.$ === "OpsCONST") {
    return true;
  } else {
    return false;
  }
}

function $is_range(_x_0) {
  if (_x_0.$ === "OpsRANGE") {
    return true;
  } else {
    return false;
  }
}

function $is_where(_x_0) {
  if (_x_0.$ === "OpsWHERE") {
    return true;
  } else {
    return false;
  }
}

function $is_xor(_x_0) {
  if (_x_0.$ === "OpsXOR") {
    return true;
  } else {
    return false;
  }
}

const $$rep = $rep;
const $$old_all = $old_all;
const $$new_all = $new_all;
const $$agree = $agree;
const $$probe_b_b = $probe_b_b;
const $$String_concat = $String_concat;
const $$List_replicate = $List_replicate;
const $$List_append = $List_append;
const $$old_work = $old_work;
const $$old_all_go = $old_all_go;
const $$new_work = $new_work;
const $$new_all_go = $new_all_go;
const $$eq_op = $eq_op;
const $$is_cast = $is_cast;
const $$is_index = $is_index;
const $$is_add = $is_add;
const $$is_mul = $is_mul;
const $$is_load = $is_load;
const $$is_store = $is_store;
const $$is_const = $is_const;
const $$is_range = $is_range;
const $$is_where = $is_where;
const $$is_xor = $is_xor;
// Cli
// ===

let cli_args = [];

function cli(argv) {
  let rts = false;
  cli_args.push(argv[0]);
  for (let i = 1; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--RTS") {
      cli_args.push(...argv.slice(i + 1));
      break;
    } else if (a === "+RTS" || a === "-RTS") {
      rts = a === "+RTS";
    } else if (!rts) {
      cli_args.push(a);
    } else if (a === "--help" || a === "--gpu-build") {
      io_out(1, io_bytes(a === "--help" ? "usage: " + argv[0] + "\n" : ""));
      process.exit(0);
    } else {
      const re = a === "--threads" ? /^0*[1-9]\d*$/ : a === "--gpu"
        ? /^(on|off|(\d*(?:\.\d*)?)([GM])B)$/ : undefined;
      const m  = re?.exec(argv[++i]);
      if (!m || m[3]
        && !(m[2] * 2 ** (m[3] === "G" ? 30 : 20) >= 16384)) {
        io_errs("bend: " + (re === undefined ? "unknown runtime option " + a
          : a === "--gpu" ? "expected on, off or a size like 4GB after --gpu"
          : "expected a thread count of 1 or more after --threads"));
        process.exit(1);
      }
    }
  }
}

// Io
// ==

// Apple arm64 passes variadic fcntl flags on the stack, so io_sys passes
// them as the ninth argument. A parked effect waits for fd (a write when
// out) and/or until at; once due, io_wait calls more and resumes k with its
// value, or parks it again on undefined. Waits stay in deadline order.

function io_exit(main) {
  try {
    process.exit(io_run(main));
  } catch (e) {
    io_errs(String(e));
    process.exit(1);
  }
}

function io_out(fd, data) {
  const fs = require("fs");
  for (let at = 0; at < data.length;) {
    try {
      const n = fs.writeSync(fd, data.subarray(at));
      if (n === 0) {
        throw "no progress";
      }
      at += n;
    } catch (e) {
      if (e.code === "EAGAIN" || e.code === "EINTR") {
        continue;
      }
      // Bun ignores SIGPIPE until a listener comes and goes.
      if (e.code === "EPIPE") {
        process.on("SIGPIPE", () => {}).removeAllListeners("SIGPIPE")
          .kill(process.pid, "SIGPIPE");
      }
      try {
        fs.writeSync(2, "bend: a short write on a standard stream\n");
      } catch (o) {
      }
      process.exit(1);
    }
  }
}

// Non-TTY stdout flushes before waits, errors, exits, or at 64 KiB.

let io_held = null;

function io_std(data) {
  io_held ??= !require("tty").isatty(1) && [];
  if (!io_held) {
    return io_out(1, data);
  }
  io_held.push(data);
  io_held.n = (io_held.n ?? 0) + data.length;
  if (io_held.n >= 65536) {
    io_sync();
  }
}

function io_sync() {
  if (io_held?.length > 0) {
    io_held.n = 0;
    io_out(1, Buffer.concat(io_held.splice(0)));
  }
}

function io_errs(message) {
  io_sync();
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
        + " accept:ipp>i send:ipUi>I recv:ipUi>I read:ipU>I"
        + " sendto:ipUipu>I recvfrom:ipUipp>I close:i>i setsockopt:iiipu>i"
        + " " + sel + ":ipppp>i"
        + " fcntl:iii" + (vari ? "iiiiii" : "") + ">i getsockopt:iiipp>i"
        + " strerror:i>c " + err + ":>p").split(" ").map((s) => {
        const [name, args, ret] = s.split(/[:>]/);
        return [name, { args: [...args].map((a) => T[a]), returns: T[ret] }];
      }))).symbols;
    const fcntl = vari ? (fd, cmd, arg) => lib.fcntl(fd, cmd, 0, 0, 0, 0, 0,
      0, arg) : lib.fcntl;
    globalThis.BEND_SYS = { ...lib, fcntl, select: lib[sel],
      ptr: ffi.ptr, mac,
      errno: () => ffi.read.i32(lib[err](), 0) };
  }
  return globalThis.BEND_SYS;
}

// Without bun:ffi, errors use bare errno.
function io_fail(code, ...rest) {
  let text = "errno " + code;
  try {
    text = String(io_sys().strerror(code));
  } catch (_) {
  }
  return { $: "Fail", error: io_tup(io_tup(code >>> 0, text), ...rest) };
}

function io_done(value) {
  return { $: "Done", value };
}

function io_until(ms) {
  return performance.now() + Number(ms);
}

function io_late(at) {
  return at !== undefined && performance.now() >= at;
}

function io_ready(at, r) {
  return at === undefined ? r : { $: "Ready", value: r };
}

function io_tup(...xs) {
  return xs.reduceRight((b, a) => tup_new(a, b));
}

const io_enc = new TextEncoder();

function io_bytes(text) {
  return io_enc.encode(str_out(text));
}

function io_text(b, n) {
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(b.subarray(0, n));
}

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
  b.set([...io_sys().mac ? [16, 2] : [2, 0], port >> 8, port & 255,
    ...part.map(Number)]);
  return b;
}

let io_active;

function io_push(fun, arg, fresh, io = io_active) {
  io.runs.push({ fun, arg });
  io.live += fresh ? 1 : 0;
}

function io_wait(io, block) {
  const soon = io.waits[0]?.at ?? Infinity;
  const ms = !block ? 0 : soon === Infinity ? -1
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
  io_sync();
  const sys = fds.length > 0 ? io_sys() : null;
  // Timers need no FFI.
  if (!sys && ms !== 0) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0,
      ms < 0 ? Infinity : ms);
  }
  if (sys?.select(top + 1, sys.ptr(set), sys.ptr(set, len), null,
    ms < 0 ? null : sys.ptr(tv)) < 0) {
    if (sys.errno() !== 4) {
      throw "bend: the poller failed";
    }
    set.fill(0);
  }
  const now = performance.now();
  const due = (w) => w.at <= now || w.fd !== undefined
    && set[at(w)] & 1 << (w.fd & 7);
  const todo = io.waits;
  io.waits = todo.filter((w) => !due(w));
  for (const w of todo.filter(due)) {
    const x = w.more();
    if (x !== undefined) {
      io_push(w.k, x, false, io);
    }
  }
}

function io_park_on(fd, out, k, more, at = Infinity) {
  const ws = io_active.waits;
  const t = { fd, out, k, more, at };
  ws.splice(ws.findLastIndex((w) => w.at <= at) + 1, 0, t);
  return t;
}

function io_run(m) {
  const io = { runs: [], live: 0, waits: [] };
  const parent = io_active;
  io_active = io;
  try {
    io_push(run_loop(m()), (x) => ({ $: "Emit", value: x }), true);
    let look = 0;
    for (let n = 0;; n += 1) {
      if (io.runs.length === 0) {
        if (io.live === 0) {
          return 0;
        }
        if (io.waits.length === 0) {
          io_errs("bend: deadlock: every computation waits on a channel");
          return 1;
        }
        io_wait(io, true);
        continue;
      }
      if ((n & 63) === 0 && io.waits.length > 0) {
        const now = performance.now();
        if (now >= look || io.waits[0].at <= now) {
          look = now + 10;
          io_wait(io, false);
        }
      }
      const s = io.runs.shift();
      let op = s.fun(s.arg);
      for (let left = 64; op !== undefined; left -= 1) {
        if (op.$ === "Emit") {
          io.live -= 1;
          break;
        }
        if (op.$ === "Halt" || op.$ === "Exit") {
          if (op.$ === "Halt") io_errs(op.message);
          if (op.code > 255) {
            io_errs("bend: exit code must be in 0..255");
            return 1;
          }
          return op.code;
        }
        const run = $0eff[op.$];
        if (run === undefined) {
          throw "bend: no effect registers " + op.$;
        }
        const x = run(...op.args, op.kont);
        if (x === undefined) {
          break;
        }
        if (left === 1) {
          io_push(op.kont, x, false, io);
          break;
        }
        op = op.kont(x);
      }
    }
  } catch (e) {
    throw e instanceof RangeError ? "bend: memory fault (machine stack overflow?)" : e;
  } finally {
    io_sync();
    io.done = true;
    io_active = parent;
  }
}

cli(process.argv.slice(1));
io_exit($main);