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
  return run_clo((_x_0) => {
  return $IO$bind$(($t_backend$()), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($t_features$()), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($t_init$()), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($t_layout$()), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($t_call$()), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($t_wait$()), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($t_refuse$()), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($t_alloc$()), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($t_sync$()), run_clo((_x_17) => {
  return (_x_18) => $IO$print$("wg-done=1", _x_18);
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $IO$bind$(_m_0, _f_0, _k_0) {
  return run_tail(_m_0, run_clo((_x_0) => {
  return run_tail(_f_0(_x_0), _k_0);
}));
}

function $t_backend$() {
  return run_clo((_x_0) => {
  return $IO$bind$(($urow$("wg_backend_webgpu", ($backend_of$("WGPUBackendType_WebGPU")))), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($urow$("wg_backend_d3d12", ($backend_of$("WGPUBackendType_D3D12")))), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($urow$("wg_backend_metal", ($backend_of$("WGPUBackendType_Metal")))), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($urow$("wg_backend_vulkan", ($backend_of$("WGPUBackendType_Vulkan")))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($urow$("wg_backend_opengles", ($backend_of$("WGPUBackendType_OpenGLES")))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($urow$("wg_backend_bare", ($backend_of$("Metal")))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($urow$("wg_backend_empty", ($backend_of$("")))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($urow$("wg_backend_unknown", ($backend_of$("nonsense")))), run_clo((_x_15) => {
  const _x_16 = ($Dev$backend$(($dev$init$(($METAL$()), ($BOTH$())))));
  return $row$("wg_backend_dev", (_x_16 === 5));
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $t_features$() {
  return run_clo((_x_0) => {
  return $IO$bind$(($row$("wg_feat_order_forward", ($u32_list_eq$(($features_of$(($BOTH$()))), {$: "Con", "head": 3, "tail": {$: "Con", "head": 8, "tail": {$: "Nil"}}})))), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($row$("wg_feat_order_reverse", ($u32_list_eq$(($features_of$(($REVERSED$()))), {$: "Con", "head": 8, "tail": {$: "Con", "head": 3, "tail": {$: "Nil"}}})))), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($row$("wg_feat_only_ts", ($u32_list_eq$(($features_of$(($TS$()))), {$: "Con", "head": 3, "tail": {$: "Nil"}})))), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($row$("wg_feat_only_f16", ($u32_list_eq$(($features_of$(($F16$()))), {$: "Con", "head": 8, "tail": {$: "Nil"}})))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($row$("wg_feat_none", ($u32_list_eq$(($features_of$(($NEITHER$()))), {$: "Nil"})))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($row$("wg_feat_drops_others", ($u32_list_eq$(($features_of$({$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 8, "tail": {$: "Con", "head": 9, "tail": {$: "Con", "head": 3, "tail": {$: "Nil"}}}}}})), {$: "Con", "head": 8, "tail": {$: "Con", "head": 3, "tail": {$: "Nil"}}})))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($row$("wg_arch_f16", ($String$eq$(($Dev$arch$(($dev$init$(($METAL$()), ($F16$()))))), "shader-f16")))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($row$("wg_arch_empty", ($String$eq$(($Dev$arch$(($dev$init$(($METAL$()), ($TS$()))))), "")))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($row$("wg_arch_missing", ($String$eq$(($Dev$arch$(($dev$init$(($METAL$()), ($NEITHER$()))))), "")))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($urow$("wg_nrequired_two", ($Dev$nrequired$(($dev$init$(($METAL$()), ($BOTH$()))))))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  return $IO$bind$(($urow$("wg_nrequired_one", ($Dev$nrequired$(($dev$init$(($METAL$()), ($F16$()))))))), run_clo((_x_21) => {
  return run_clo((_x_22) => {
  return $IO$bind$(($urow$("wg_nrequired_zero", ($Dev$nrequired$(($dev$init$(($METAL$()), ($NEITHER$()))))))), run_clo((_x_23) => {
  return $row$("wg_feat_device_kept", ($u32_list_eq$(($Dev$features$(($dev$init$(($METAL$()), ($REVERSED$()))))), {$: "Con", "head": 8, "tail": {$: "Con", "head": 3, "tail": {$: "Nil"}}})));
}), _x_22);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $t_init$() {
  return run_clo((_x_0) => {
  return $IO$bind$(run_clo((_x_1) => {
  return $IO$pure$(($dev$init$(($METAL$()), ($BOTH$()))), _x_1);
}), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$bind$(run_clo((_x_4) => {
  return $IO$pure$(($Dev$tr$(_x_2)), _x_4);
}), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($row$("wg_init_order", ($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_INSTANCE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_WAIT$()), "arg": ($SYNC_REQUEST_ADAPTER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_GET_FEATURES$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_FREE_FEATURES$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_GET_LIMITS$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_WAIT$()), "arg": ($SYNC_REQUEST_DEVICE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_QUEUE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_ADAPTER$())}, "tail": {$: "Nil"}}}}}}}}})))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($row$("wg_init_exact", ($u32_list_eq$(($created$(_x_5)), {$: "Con", "head": ($OBJ_INSTANCE$()), "tail": {$: "Con", "head": ($OBJ_QUEUE$()), "tail": {$: "Nil"}}})))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($row$("wg_init_waits", ($u32_list_eq$(($waited$(_x_5)), {$: "Con", "head": ($SYNC_REQUEST_ADAPTER$()), "tail": {$: "Con", "head": ($SYNC_REQUEST_DEVICE$()), "tail": {$: "Nil"}}})))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($row$("wg_init_released", ($u32_list_eq$(($released$(_x_5)), {$: "Con", "head": ($OBJ_ADAPTER$()), "tail": {$: "Nil"}})))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($urow$("wg_init_get_features", ($ncalls$(($CALL_GET_FEATURES$()), _x_5)))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($urow$("wg_init_free_features", ($ncalls$(($CALL_FREE_FEATURES$()), _x_5)))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($urow$("wg_init_get_limits", ($ncalls$(($CALL_GET_LIMITS$()), _x_5)))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  return $IO$bind$(($urow$("wg_init_pops", ($ncalls$(($CALL_POP$()), _x_5)))), run_clo((_x_21) => {
  return run_clo((_x_22) => {
  return $IO$bind$(($urow$("wg_init_depth", ($Tr$depth$(_x_5)))), run_clo((_x_23) => {
  return run_clo((_x_24) => {
  const _x_25 = ($Dev$instance$(_x_2));
  const _x_26 = ($Dev$adapter$(_x_2));
  const _x_27 = ($Dev$adapter$(_x_2));
  const _x_28 = ($Dev$device_res$(_x_2));
  const _x_29 = ($Dev$device_res$(_x_2));
  const _x_30 = ($Dev$queue$(_x_2));
  return $IO$bind$(($row$("wg_init_ids_ordered", ($Bool$and$((_x_25 < _x_26), ($Bool$and$((_x_27 < _x_28), (_x_29 < _x_30))))))), run_clo((_x_31) => {
  return $srow$("wg_dev_backend", ($String$concat$({$: "Con", "head": ($Dev$arch$(_x_2)), "tail": {$: "Con", "head": " ", "tail": {$: "Con", "head": ($U32$show$(($Dev$nrequired$(_x_2)))), "tail": {$: "Nil"}}}})));
}), _x_24);
});
}), _x_22);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_3);
});
}), _x_0);
});
}

function $t_layout$() {
  return run_clo((_x_0) => {
  return $IO$bind$(($row$("wg_bgl_none", ($u32_list_eq$(($bgl$flat$(($bgl$of$(0, 0)), {$: "Nil"})), {$: "Con", "head": 0, "tail": {$: "Con", "head": 1, "tail": {$: "Nil"}}})))), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($row$("wg_bgl_1_0", ($u32_list_eq$(($bgl$flat$(($bgl$of$(1, 0)), {$: "Nil"})), {$: "Con", "head": 0, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Nil"}}}}})))), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($row$("wg_bgl_3_1", ($u32_list_eq$(($bgl$flat$(($bgl$of$(3, 1)), {$: "Nil"})), {$: "Con", "head": 0, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 3, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 4, "tail": {$: "Con", "head": 1, "tail": {$: "Nil"}}}}}}}}}}})))), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($row$("wg_bgl_0_2", ($u32_list_eq$(($bgl$flat$(($bgl$of$(0, 2)), {$: "Nil"})), {$: "Con", "head": 0, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 1, "tail": {$: "Nil"}}}}}}})))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($row$("wg_bgl_5_0", ($u32_list_eq$(($bgl$flat$(($bgl$of$(5, 0)), {$: "Nil"})), {$: "Con", "head": 0, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 3, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 4, "tail": {$: "Con", "head": 2, "tail": {$: "Con", "head": 5, "tail": {$: "Con", "head": 2, "tail": {$: "Nil"}}}}}}}}}}}}})))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($urow$("wg_bgl_nentries", ($Pass$nentries$(($Pass$reset$(($pass$layout$(3, 1, ($Pass$of$("k", ($BOTH$()))))))))))), run_clo((_x_11) => {
  return $urow$("wg_bgl_nentries_0", ($Pass$nentries$(($Pass$reset$(($pass$layout$(0, 0, ($Pass$of$("k", ($BOTH$()))))))))));
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $t_call$() {
  return run_clo((_x_0) => {
  return $IO$bind$(run_clo((_x_1) => {
  return $IO$pure$(($fx_call$(($F16$()), false)), _x_1);
}), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$bind$(run_clo((_x_4) => {
  return $IO$pure$(($Pass$tr$(_x_2)), _x_4);
}), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($row$("wg_has_rejects_reverse", ($Bool$not$(($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_SUBMIT$()), "arg": 1}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_FINISH$()), "arg": 1}, "tail": {$: "Nil"}}})))))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($row$("wg_has_rejects_absent", ($Bool$not$(($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_DISPATCH$()), "arg": 999}, "tail": {$: "Nil"}})))))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($row$("wg_call_order", ($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BIND_GROUP_LAYOUT$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_PIPELINE_LAYOUT$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BIND_GROUP$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_WAIT$()), "arg": ($SYNC_CREATE_PIPELINE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_COMMAND_ENCODER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_BEGIN$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_SET_PIPELINE$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_SET_BIND_GROUP$()), "arg": ($BIND_GROUP_INDEX$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_DISPATCH$()), "arg": 8}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_END$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_FINISH$()), "arg": 1}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_SUBMIT$()), "arg": 1}, "tail": {$: "Nil"}}}}}}}}}}}}}}}}}}}}})))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($row$("wg_call_created", ($u32_list_eq$(($created$(_x_5)), {$: "Con", "head": ($OBJ_BIND_GROUP_LAYOUT$()), "tail": {$: "Con", "head": ($OBJ_PIPELINE_LAYOUT$()), "tail": {$: "Con", "head": ($OBJ_BUFFER$()), "tail": {$: "Con", "head": ($OBJ_BUFFER$()), "tail": {$: "Con", "head": ($OBJ_BIND_GROUP$()), "tail": {$: "Con", "head": ($OBJ_COMMAND_ENCODER$()), "tail": {$: "Nil"}}}}}}})))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($row$("wg_call_released", ($u32_list_eq$(($released$(_x_5)), {$: "Con", "head": ($OBJ_BIND_GROUP_LAYOUT$()), "tail": {$: "Con", "head": ($OBJ_PIPELINE_LAYOUT$()), "tail": {$: "Con", "head": ($OBJ_BIND_GROUP$()), "tail": {$: "Con", "head": ($OBJ_COMPUTE_PIPELINE$()), "tail": {$: "Con", "head": ($OBJ_COMMAND_ENCODER$()), "tail": {$: "Con", "head": ($OBJ_COMPUTE_PASS$()), "tail": {$: "Con", "head": ($OBJ_COMMAND_BUFFER$()), "tail": {$: "Nil"}}}}}}}})))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($row$("wg_call_waits", ($u32_list_eq$(($waited$(_x_5)), {$: "Con", "head": ($SYNC_CREATE_PIPELINE$()), "tail": {$: "Nil"}})))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($row$("wg_call_bindgroup0", ($u32_list_eq$(($grouped$(_x_5)), {$: "Con", "head": ($BIND_GROUP_INDEX$()), "tail": {$: "Nil"}})))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  return $IO$bind$(($row$("wg_call_dispatch_x", ($u32_list_eq$(($dispatched$(_x_5)), {$: "Con", "head": 8, "tail": {$: "Nil"}})))), run_clo((_x_21) => {
  return run_clo((_x_22) => {
  return $IO$bind$(($urow$("wg_call_dispatch_n", ($ncalls$(($CALL_DISPATCH$()), _x_5)))), run_clo((_x_23) => {
  return run_clo((_x_24) => {
  return $IO$bind$(($urow$("wg_call_pushes", ($ncalls$(($CALL_PUSH$()), _x_5)))), run_clo((_x_25) => {
  return run_clo((_x_26) => {
  return $IO$bind$(($urow$("wg_call_pops", ($ncalls$(($CALL_POP$()), _x_5)))), run_clo((_x_27) => {
  return run_clo((_x_28) => {
  return $IO$bind$(($urow$("wg_call_depth", ($Tr$depth$(_x_5)))), run_clo((_x_29) => {
  return run_clo((_x_30) => {
  return $IO$bind$(($urow$("wg_call_calls", ($seen$(_x_5)))), run_clo((_x_31) => {
  return run_clo((_x_32) => {
  return $IO$bind$(($lrow$("wg_call_sizes", ($Pass$sizes$(_x_2)))), run_clo((_x_33) => {
  return run_clo((_x_34) => {
  return $IO$bind$(($urow$("wg_call_ls_recorded", ($Pass$ls$(_x_2)))), run_clo((_x_35) => {
  return run_clo((_x_36) => {
  return $IO$bind$(($urow$("wg_call_gx", ($Pass$gx$(_x_2)))), run_clo((_x_37) => {
  return run_clo((_x_38) => {
  return $IO$bind$(($urow$("wg_call_entry_count", ($Pass$nentries$(_x_2)))), run_clo((_x_39) => {
  return run_clo((_x_40) => {
  return $IO$bind$(($urow$("wg_life_pushes", ($ncalls$(($CALL_PUSH$()), ($Pass$tr$(($fx_life$(($BOTH$()), false)))))))), run_clo((_x_41) => {
  return $urow$("wg_life_pops", ($ncalls$(($CALL_POP$()), ($Pass$tr$(($fx_life$(($BOTH$()), false)))))));
}), _x_40);
});
}), _x_38);
});
}), _x_36);
});
}), _x_34);
});
}), _x_32);
});
}), _x_30);
});
}), _x_28);
});
}), _x_26);
});
}), _x_24);
});
}), _x_22);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_3);
});
}), _x_0);
});
}

function $t_wait$() {
  return run_clo((_x_0) => {
  return $IO$bind$(run_clo((_x_1) => {
  return $IO$pure$(($fx_call$(($BOTH$()), true)), _x_1);
}), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$bind$(run_clo((_x_4) => {
  return $IO$pure$(($Pass$tr$(_x_2)), _x_4);
}), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($row$("wg_wait_flag", ($Pass$wait$(_x_2)))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($row$("wg_wait_query_created", ($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_COMMAND_ENCODER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_QUERY_SET$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_BEGIN$()), "arg": 0}, "tail": {$: "Nil"}}}}})))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($row$("wg_wait_resolve_between", ($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_END$()), "arg": 0}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RESOLVE$()), "arg": ($QUERY_COUNT$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_FINISH$()), "arg": 1}, "tail": {$: "Nil"}}}})))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($row$("wg_wait_tail", ($seq$(_x_5, {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_COMMAND_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_COMMAND_ENCODER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_COPY$()), "arg": ($QUERY_BUF_SIZE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_FINISH$()), "arg": 1}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_SUBMIT$()), "arg": 1}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_COMMAND_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_COMMAND_ENCODER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_WAIT$()), "arg": ($SYNC_MAP_ASYNC$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_MAPPED_RANGE$()), "arg": ($QUERY_BUF_SIZE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_DESTROY$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_DESTROY$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_DESTROY_QUERY_SET$()), "arg": ($OBJ_QUERY_SET$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_QUERY_SET$())}, "tail": {$: "Nil"}}}}}}}}}}}}}}}}})))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($row$("wg_wait_waits", ($u32_list_eq$(($waited$(_x_5)), {$: "Con", "head": ($SYNC_CREATE_PIPELINE$()), "tail": {$: "Con", "head": ($SYNC_MAP_ASYNC$()), "tail": {$: "Nil"}}})))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($urow$("wg_wait_destroys", ($ncalls$(($CALL_DESTROY$()), _x_5)))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($urow$("wg_wait_query_destroys", ($ncalls$(($CALL_DESTROY_QUERY_SET$()), _x_5)))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  return $IO$bind$(($urow$("wg_wait_created_n", ($ncreated$(_x_5)))), run_clo((_x_21) => {
  return run_clo((_x_22) => {
  return $IO$bind$(run_clo((_x_23) => {
  return $IO$pure$(($fx_call$(($F16$()), true)), _x_23);
}), run_clo((_x_24) => {
  return run_clo((_x_25) => {
  return $IO$bind$(run_clo((_x_26) => {
  return $IO$pure$(($Pass$tr$(_x_24)), _x_26);
}), run_clo((_x_27) => {
  return run_clo((_x_28) => {
  return $IO$bind$(($row$("wg_wait_no_ts_flag", ($Bool$not$(($Pass$wait$(_x_24)))))), run_clo((_x_29) => {
  return run_clo((_x_30) => {
  return $IO$bind$(($urow$("wg_wait_no_ts_created", ($ncreated$(_x_27)))), run_clo((_x_31) => {
  return run_clo((_x_32) => {
  return $IO$bind$(($urow$("wg_wait_no_ts_resolve", ($ncalls$(($CALL_RESOLVE$()), _x_27)))), run_clo((_x_33) => {
  return run_clo((_x_34) => {
  return $IO$bind$(($urow$("wg_wait_no_ts_qdestroy", ($ncalls$(($CALL_DESTROY_QUERY_SET$()), _x_27)))), run_clo((_x_35) => {
  return run_clo((_x_36) => {
  return $IO$bind$(($urow$("wg_wait_no_ts_map", ($ncalls$(($CALL_MAP_ASYNC$()), _x_27)))), run_clo((_x_37) => {
  return run_clo((_x_38) => {
  return $IO$bind$(run_clo((_x_39) => {
  return $IO$pure$(($fx_call$(($BOTH$()), false)), _x_39);
}), run_clo((_x_40) => {
  return run_clo((_x_41) => {
  return $IO$bind$(($row$("wg_wait_false_flag", ($Bool$not$(($Pass$wait$(_x_40)))))), run_clo((_x_42) => {
  return $urow$("wg_wait_false_query", ($ncalls$(($CALL_RESOLVE$()), ($Pass$tr$(_x_40)))));
}), _x_41);
});
}), _x_38);
});
}), _x_36);
});
}), _x_34);
});
}), _x_32);
});
}), _x_30);
});
}), _x_28);
});
}), _x_25);
});
}), _x_22);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_3);
});
}), _x_0);
});
}

function $t_refuse$() {
  return run_clo((_x_0) => {
  return $IO$bind$(run_clo((_x_1) => {
  return $IO$pure$(($fx_refuse$(1)), _x_1);
}), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  return $IO$bind$(run_clo((_x_4) => {
  return $IO$pure$(($fx_refuse$(2)), _x_4);
}), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(run_clo((_x_7) => {
  return $IO$pure$(($fx_refuse$(3)), _x_7);
}), run_clo((_x_8) => {
  return run_clo((_x_9) => {
  return $IO$bind$(run_clo((_x_10) => {
  return $IO$pure$(($fx_refuse$(4)), _x_10);
}), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($urow$("wg_refuse_shader_n", ($ncreated$(($Pass$tr$(_x_2)))))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($urow$("wg_refuse_layout_n", ($ncreated$(($Pass$tr$(_x_5)))))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($urow$("wg_refuse_playout_n", ($ncreated$(($Pass$tr$(_x_8)))))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($urow$("wg_refuse_group_n", ($ncreated$(($Pass$tr$(_x_11)))))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  return $IO$bind$(($urow$("wg_refuse_shader_calls", ($seen$(($Pass$tr$(_x_2)))))), run_clo((_x_21) => {
  return run_clo((_x_22) => {
  return $IO$bind$(($urow$("wg_refuse_layout_calls", ($seen$(($Pass$tr$(_x_5)))))), run_clo((_x_23) => {
  return run_clo((_x_24) => {
  return $IO$bind$(($urow$("wg_refuse_playout_calls", ($seen$(($Pass$tr$(_x_8)))))), run_clo((_x_25) => {
  return run_clo((_x_26) => {
  return $IO$bind$(($urow$("wg_refuse_group_calls", ($seen$(($Pass$tr$(_x_11)))))), run_clo((_x_27) => {
  return run_clo((_x_28) => {
  return $IO$bind$(($urow$("wg_refuse_shader_pops", ($ncalls$(($CALL_POP$()), ($Pass$tr$(_x_2)))))), run_clo((_x_29) => {
  return run_clo((_x_30) => {
  return $IO$bind$(($urow$("wg_refuse_layout_pops", ($ncalls$(($CALL_POP$()), ($Pass$tr$(_x_5)))))), run_clo((_x_31) => {
  return run_clo((_x_32) => {
  return $IO$bind$(($urow$("wg_refuse_playout_pops", ($ncalls$(($CALL_POP$()), ($Pass$tr$(_x_8)))))), run_clo((_x_33) => {
  return run_clo((_x_34) => {
  return $IO$bind$(($urow$("wg_refuse_layout_dispatch", ($ncalls$(($CALL_DISPATCH$()), ($Pass$tr$(_x_5)))))), run_clo((_x_35) => {
  return run_clo((_x_36) => {
  return $IO$bind$(($urow$("wg_refuse_group_dispatch", ($ncalls$(($CALL_DISPATCH$()), ($Pass$tr$(_x_11)))))), run_clo((_x_37) => {
  return run_clo((_x_38) => {
  return $IO$bind$(($urow$("wg_refuse_group_pops", ($ncalls$(($CALL_POP$()), ($Pass$tr$(_x_11)))))), run_clo((_x_39) => {
  return run_clo((_x_40) => {
  return $IO$bind$(($urow$("wg_refuse_group_depth", ($Tr$depth$(($Pass$tr$(_x_11)))))), run_clo((_x_41) => {
  return run_clo((_x_42) => {
  return $IO$bind$(($row$("wg_refuse_shader_flag", ($Tr$refused$(($Pass$tr$(_x_2)))))), run_clo((_x_43) => {
  return run_clo((_x_44) => {
  return $IO$bind$(($row$("wg_refuse_layout_order", ($seq$(($Pass$tr$(_x_5)), {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_SHADER_MODULE$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_PUSH$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BIND_GROUP_LAYOUT$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Nil"}}}}}}})))), run_clo((_x_45) => {
  return $row$("wg_refuse_group_last_pop", ($seq$(($Pass$tr$(_x_11)), {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BIND_GROUP$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Nil"}}})));
}), _x_44);
});
}), _x_42);
});
}), _x_40);
});
}), _x_38);
});
}), _x_36);
});
}), _x_34);
});
}), _x_32);
});
}), _x_30);
});
}), _x_28);
});
}), _x_26);
});
}), _x_24);
});
}), _x_22);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_9);
});
}), _x_6);
});
}), _x_3);
});
}), _x_0);
});
}

function $t_alloc$() {
  return run_clo((_x_0) => {
  return $IO$bind$(($urow$("wg_alloc_size_0", ($alloc$size$(0)))), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($urow$("wg_alloc_size_1", ($alloc$size$(1)))), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($urow$("wg_alloc_size_4", ($alloc$size$(4)))), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($urow$("wg_alloc_size_5", ($alloc$size$(5)))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($urow$("wg_alloc_size_9", ($alloc$size$(9)))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  const _x_11 = ($alloc$usage$());
  return $IO$bind$(($row$("wg_alloc_usage", (_x_11 === 140))), run_clo((_x_12) => {
  return run_clo((_x_13) => {
  const _x_14 = ($dev$uniform_usage$());
  return $IO$bind$(($row$("wg_uniform_usage", (_x_14 === 72))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  const _x_17 = ($copy$readable_usage$());
  return $IO$bind$(($row$("wg_readable_usage", (_x_17 === 9))), run_clo((_x_18) => {
  return run_clo((_x_19) => {
  const _x_20 = ($USAGE_QUERY_RESOLVE$());
  const _x_21 = ($USAGE_COPY_SRC$());
  const _x_22 = ((_x_20 | _x_21) >>> 0);
  return $IO$bind$(($row$("wg_query_usage", (_x_22 === 516))), run_clo((_x_23) => {
  return run_clo((_x_24) => {
  return $IO$bind$(run_clo((_x_25) => {
  return $IO$pure$(($alloc$of$(5, ($Tr$of$()))), _x_25);
}), run_clo((_x_26) => {
  return run_clo((_x_27) => {
  return $IO$bind$(($urow$("wg_alloc_buf_size", ($Buf$size$(($Made$buf$(_x_26)))))), run_clo((_x_28) => {
  return run_clo((_x_29) => {
  return $IO$bind$(($urow$("wg_alloc_created", ($ncalls$(($CALL_CREATE$()), ($Made$tr$(_x_26)))))), run_clo((_x_30) => {
  return run_clo((_x_31) => {
  return $IO$bind$(($urow$("wg_copyin_len_5", ($copy$write_len$(5)))), run_clo((_x_32) => {
  return run_clo((_x_33) => {
  return $IO$bind$(($urow$("wg_copyin_len_4", ($copy$write_len$(4)))), run_clo((_x_34) => {
  return run_clo((_x_35) => {
  return $IO$bind$(($urow$("wg_copyin_len_0", ($copy$write_len$(0)))), run_clo((_x_36) => {
  return run_clo((_x_37) => {
  return $IO$bind$(($urow$("wg_copyin_pad_5", ($copy$pad$(5)))), run_clo((_x_38) => {
  return run_clo((_x_39) => {
  return $IO$bind$(($urow$("wg_copyin_pad_4", ($copy$pad$(4)))), run_clo((_x_40) => {
  return run_clo((_x_41) => {
  return $IO$bind$(run_clo((_x_42) => {
  return $IO$pure$(($copy$copyin$(5, ($Tr$of$()))), _x_42);
}), run_clo((_x_43) => {
  return run_clo((_x_44) => {
  return $IO$bind$(($row$("wg_copyin_writes_padded", ($u32_list_eq$(($written$(_x_43)), {$: "Con", "head": 8, "tail": {$: "Nil"}})))), run_clo((_x_45) => {
  return run_clo((_x_46) => {
  return $IO$bind$(run_clo((_x_47) => {
  return $IO$pure$(($copy$readable$(16, ($Tr$of$()))), _x_47);
}), run_clo((_x_48) => {
  return run_clo((_x_49) => {
  return $IO$bind$(($row$("wg_readable_released", ($u32_list_eq$(($released$(($Made$tr$(_x_48)))), {$: "Con", "head": ($OBJ_COMMAND_BUFFER$()), "tail": {$: "Con", "head": ($OBJ_COMMAND_ENCODER$()), "tail": {$: "Nil"}}})))), run_clo((_x_50) => {
  return run_clo((_x_51) => {
  return $IO$bind$(($urow$("wg_readable_size", ($Buf$size$(($Made$buf$(_x_48)))))), run_clo((_x_52) => {
  return run_clo((_x_53) => {
  return $IO$bind$(run_clo((_x_54) => {
  return $IO$pure$(($dev$free$(3, ($OBJ_BUFFER$()), ($Tr$of$()))), _x_54);
}), run_clo((_x_55) => {
  return run_clo((_x_56) => {
  return $IO$bind$(($row$("wg_free_mapped", ($seq$(_x_55, {$: "Con", "head": {$: "Call", "k": ($CALL_UNMAP$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_DESTROY$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Nil"}}}})))), run_clo((_x_57) => {
  return run_clo((_x_58) => {
  return $IO$bind$(run_clo((_x_59) => {
  return $IO$pure$(($dev$free$(1, ($OBJ_BUFFER$()), ($Tr$of$()))), _x_59);
}), run_clo((_x_60) => {
  return run_clo((_x_61) => {
  return $IO$bind$(($row$("wg_free_unmapped", ($seq$(_x_60, {$: "Con", "head": {$: "Call", "k": ($CALL_DESTROY$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_RELEASE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Nil"}}})))), run_clo((_x_62) => {
  return run_clo((_x_63) => {
  return $IO$bind$(($urow$("wg_free_unmapped_unmaps", ($ncalls$(($CALL_UNMAP$()), _x_60)))), run_clo((_x_64) => {
  return run_clo((_x_65) => {
  return $IO$bind$(($row$("wg_free_bytes_0", ($u32_list_eq$(($dev$uniform_bytes$(0)), {$: "Con", "head": 0, "tail": {$: "Con", "head": 0, "tail": {$: "Con", "head": 0, "tail": {$: "Con", "head": 0, "tail": {$: "Nil"}}}}})))), run_clo((_x_66) => {
  return run_clo((_x_67) => {
  return $IO$bind$(($row$("wg_free_bytes_1", ($u32_list_eq$(($dev$uniform_bytes$(1)), {$: "Con", "head": 1, "tail": {$: "Con", "head": 0, "tail": {$: "Con", "head": 0, "tail": {$: "Con", "head": 0, "tail": {$: "Nil"}}}}})))), run_clo((_x_68) => {
  return run_clo((_x_69) => {
  return $IO$bind$(($row$("wg_free_bytes_neg", ($u32_list_eq$(($dev$uniform_bytes$(4294967295)), {$: "Con", "head": 255, "tail": {$: "Con", "head": 255, "tail": {$: "Con", "head": 255, "tail": {$: "Con", "head": 255, "tail": {$: "Nil"}}}}})))), run_clo((_x_70) => {
  return run_clo((_x_71) => {
  return $IO$bind$(run_clo((_x_72) => {
  return $IO$pure$(($dev$create_uniform$(($dev$uniform_bytes$(1)), ($Tr$of$()))), _x_72);
}), run_clo((_x_73) => {
  return run_clo((_x_74) => {
  return $IO$bind$(($row$("wg_free_uniform_created", ($seq$(($Made$tr$(_x_73)), {$: "Con", "head": {$: "Call", "k": ($CALL_CREATE$()), "arg": ($OBJ_BUFFER$())}, "tail": {$: "Con", "head": {$: "Call", "k": ($CALL_WRITE$()), "arg": 4}, "tail": {$: "Nil"}}})))), run_clo((_x_75) => {
  return $urow$("wg_free_uniform_size", ($Buf$size$(($Made$buf$(_x_73)))));
}), _x_74);
});
}), _x_71);
});
}), _x_69);
});
}), _x_67);
});
}), _x_65);
});
}), _x_63);
});
}), _x_61);
});
}), _x_58);
});
}), _x_56);
});
}), _x_53);
});
}), _x_51);
});
}), _x_49);
});
}), _x_46);
});
}), _x_44);
});
}), _x_41);
});
}), _x_39);
});
}), _x_37);
});
}), _x_35);
});
}), _x_33);
});
}), _x_31);
});
}), _x_29);
});
}), _x_27);
});
}), _x_24);
});
}), _x_19);
});
}), _x_16);
});
}), _x_13);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $t_sync$() {
  return run_clo((_x_0) => {
  return $IO$bind$(($urow$("wg_sync_ret_0", ($sync_ret$(0)))), run_clo((_x_1) => {
  return run_clo((_x_2) => {
  return $IO$bind$(($urow$("wg_sync_ret_1", ($sync_ret$(1)))), run_clo((_x_3) => {
  return run_clo((_x_4) => {
  return $IO$bind$(($urow$("wg_sync_ret_2", ($sync_ret$(2)))), run_clo((_x_5) => {
  return run_clo((_x_6) => {
  return $IO$bind$(($urow$("wg_sync_ret_3", ($sync_ret$(3)))), run_clo((_x_7) => {
  return run_clo((_x_8) => {
  return $IO$bind$(($urow$("wg_sync_emsg_1", ($sync_has_emsg$(($SYNC_MAP_ASYNC$()))))), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  return $IO$bind$(($urow$("wg_sync_emsg_2", ($sync_has_emsg$(($SYNC_POP_ERROR_SCOPE$()))))), run_clo((_x_11) => {
  return run_clo((_x_12) => {
  return $IO$bind$(($urow$("wg_sync_emsg_3", ($sync_has_emsg$(($SYNC_CREATE_PIPELINE$()))))), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$(($urow$("wg_sync_emsg_4", ($sync_has_emsg$(($SYNC_REQUEST_ADAPTER$()))))), run_clo((_x_15) => {
  return run_clo((_x_16) => {
  return $IO$bind$(($urow$("wg_sync_emsg_5", ($sync_has_emsg$(($SYNC_REQUEST_DEVICE$()))))), run_clo((_x_17) => {
  return run_clo((_x_18) => {
  return $IO$bind$(($urow$("wg_sync_emsg_6", ($sync_has_emsg$(($SYNC_WORK_DONE$()))))), run_clo((_x_19) => {
  return run_clo((_x_20) => {
  const _x_21 = ($sync_payload$(2, ($SYNC_NO_EMSG$())));
  return $IO$bind$(($urow$("wg_sync_payload_noemsg_2", (_x_21 >>> 0))), run_clo((_x_22) => {
  return run_clo((_x_23) => {
  const _x_24 = ($sync_payload$(0, ($SYNC_NO_EMSG$())));
  return $IO$bind$(($urow$("wg_sync_payload_noemsg_0", (_x_24 >>> 0))), run_clo((_x_25) => {
  return run_clo((_x_26) => {
  const _x_27 = ($sync_payload$(2, ($SYNC_HAS_EMSG$())));
  return $IO$bind$(($urow$("wg_sync_payload_emsg_2", (_x_27 >>> 0))), run_clo((_x_28) => {
  return run_clo((_x_29) => {
  return $IO$bind$(($row$("wg_sync_tail", ($String$eq$(($sync_tail$("WGPUBufferMapAsyncStatus_InstanceDropped")), "InstanceDropped")))), run_clo((_x_30) => {
  return run_clo((_x_31) => {
  return $IO$bind$(($row$("wg_sync_tail_missing", ($String$eq$(($sync_tail$("None")), "None")))), run_clo((_x_32) => {
  return run_clo((_x_33) => {
  const _x_34 = ($List$length$(($$$$047helpers$dedup_str$(($sync_name$six2$())))));
  return $IO$bind$(($urow$("wg_sync_names2", (_x_34 >>> 0))), run_clo((_x_35) => {
  return run_clo((_x_36) => {
  const _x_37 = ($List$length$(($$$$047helpers$dedup_str$(($sync_name$six3$())))));
  return $IO$bind$(($urow$("wg_sync_names3", (_x_37 >>> 0))), run_clo((_x_38) => {
  return run_clo((_x_39) => {
  return $IO$bind$(($srow$("wg_sync_name_mapasync3", ($sync_name$of$(($SYNC_MAP_ASYNC$()), 3)))), run_clo((_x_40) => {
  return run_clo((_x_41) => {
  return $IO$bind$(($srow$("wg_sync_name_pop3", ($sync_name$of$(($SYNC_POP_ERROR_SCOPE$()), 3)))), run_clo((_x_42) => {
  return run_clo((_x_43) => {
  return $IO$bind$(($srow$("wg_sync_name_pipeline3", ($sync_name$of$(($SYNC_CREATE_PIPELINE$()), 3)))), run_clo((_x_44) => {
  return run_clo((_x_45) => {
  return $IO$bind$(($srow$("wg_sync_name_adapter3", ($sync_name$of$(($SYNC_REQUEST_ADAPTER$()), 3)))), run_clo((_x_46) => {
  return run_clo((_x_47) => {
  return $IO$bind$(($srow$("wg_sync_name_device3", ($sync_name$of$(($SYNC_REQUEST_DEVICE$()), 3)))), run_clo((_x_48) => {
  return run_clo((_x_49) => {
  return $IO$bind$(($srow$("wg_sync_name_workdone3", ($sync_name$of$(($SYNC_WORK_DONE$()), 3)))), run_clo((_x_50) => {
  return run_clo((_x_51) => {
  return $IO$bind$(($srow$("wg_sync_name_success", ($sync_name$of$(($SYNC_REQUEST_ADAPTER$()), 1)))), run_clo((_x_52) => {
  return run_clo((_x_53) => {
  return $IO$bind$(($srow$("wg_sync_err_adapter", ($sync_error$(($SYNC_REQUEST_ADAPTER$()), 3, "no adapter")))), run_clo((_x_54) => {
  return run_clo((_x_55) => {
  return $IO$bind$(($srow$("wg_sync_err_empty", ($sync_error$(($SYNC_WORK_DONE$()), 3, "")))), run_clo((_x_56) => {
  return $srow$("wg_sync_err_ok", ($sync_error$(($SYNC_REQUEST_ADAPTER$()), 1, "unreachable")));
}), _x_55);
});
}), _x_53);
});
}), _x_51);
});
}), _x_49);
});
}), _x_47);
});
}), _x_45);
});
}), _x_43);
});
}), _x_41);
});
}), _x_39);
});
}), _x_36);
});
}), _x_33);
});
}), _x_31);
});
}), _x_29);
});
}), _x_26);
});
}), _x_23);
});
}), _x_20);
});
}), _x_18);
});
}), _x_16);
});
}), _x_14);
});
}), _x_12);
});
}), _x_10);
});
}), _x_8);
});
}), _x_6);
});
}), _x_4);
});
}), _x_2);
});
}), _x_0);
});
}

function $IO$print$(_text_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.print"].run, need: $0eff["IO.print"].need, args: [(_text_0)], kont: (_k_0) };
}
function $urow$(_nm_0, _v_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($U32$show$(_v_0)), "tail": {$: "Nil"}}}})), _x_0);
}

function $backend_of$(_s_0) {
  return $backend_of$go$(($List$length$(($backend_names$()))), _s_0, ($backend_names$()), 0, 0);
}

function $row$(_nm_0, _b_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($Bool$show$(_b_0)), "tail": {$: "Nil"}}}})), _x_0);
}

function $Dev$backend$(_d_0) {
  const _backend_0 = _d_0["backend"];
  return _backend_0;
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

function $METAL$() {
  return "WGPUBackendType_Metal";
}

function $BOTH$() {
  return {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Nil"}}};
}

function $u32_list_eq$(_a_0, _b_0) {
  const _x_0 = ($List$length$(_a_0));
  const _x_1 = ($List$length$(_b_0));
  const _x_2 = (_x_0 >>> 0);
  const _x_3 = (_x_1 >>> 0);
  return $Bool$and$((_x_2 === _x_3), ($$$$047helpers$u32_list_eq$(_a_0, _b_0)));
}

function $features_of$(_fs_0) {
  return $features_keep$go$(($List$length$(_fs_0)), _fs_0, {$: "Nil"});
}

function $REVERSED$() {
  return {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Nil"}}};
}

function $TS$() {
  return {$: "Con", "head": ($FEATURE_TIMESTAMP_QUERY$()), "tail": {$: "Nil"}};
}

function $F16$() {
  return {$: "Con", "head": ($FEATURE_SHADER_F16$()), "tail": {$: "Nil"}};
}

function $NEITHER$() {
  return {$: "Con", "head": 1, "tail": {$: "Con", "head": 2, "tail": {$: "Nil"}}};
}

function $String$eq$(_a_0, _b_0) {
  return $Cmp$is_eq$(($String$order$(_a_0, _b_0)));
}

function $Dev$arch$(_d_0) {
  const _arch_0 = _d_0["arch"];
  return _arch_0;
}

function $Dev$nrequired$(_d_0) {
  const _nrequired_0 = _d_0["nrequired"];
  return _nrequired_0;
}

function $Dev$features$(_d_0) {
  const _features_0 = _d_0["features"];
  return _features_0;
}

function $IO$pure$(_x_0, _k_0) {
  return run_tail(_k_0, _x_0);
}

function $Dev$tr$(_d_0) {
  const _t_0 = _d_0["t"];
  return _t_0;
}

function $seq$(_t_0, _pat_0) {
  return $Tr$has$(($Tr$calls$(_t_0)), _pat_0);
}

function $CALL_CREATE$() {
  return 0;
}

function $OBJ_INSTANCE$() {
  return 0;
}

function $CALL_WAIT$() {
  return 1;
}

function $SYNC_REQUEST_ADAPTER$() {
  return 4;
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

function $SYNC_REQUEST_DEVICE$() {
  return 5;
}

function $OBJ_QUEUE$() {
  return 3;
}

function $CALL_RELEASE$() {
  return 2;
}

function $OBJ_ADAPTER$() {
  return 1;
}

function $created$(_t_0) {
  return $Tr$args$(($CALL_CREATE$()), ($Tr$calls$(_t_0)));
}

function $waited$(_t_0) {
  return $Tr$args$(($CALL_WAIT$()), ($Tr$calls$(_t_0)));
}

function $released$(_t_0) {
  return $Tr$args$(($CALL_RELEASE$()), ($Tr$calls$(_t_0)));
}

function $ncalls$(_k_0, _t_0) {
  return $Tr$count$(_k_0, ($Tr$calls$(_t_0)));
}

function $CALL_POP$() {
  return 4;
}

function $Tr$depth$(_t_0) {
  const _depth_0 = _t_0["depth"];
  return _depth_0;
}

function $Bool$and$(_a_0, _b_0) {
  if (!_a_0) {
    return false;
  } else {
    return _b_0;
  }
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

function $srow$(_nm_0, _v_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": _v_0, "tail": {$: "Nil"}}}})), _x_0);
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

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
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

function $bgl$of$(_nbufs_0, _nvals_0) {
  const _x_0 = ((_nbufs_0 + _nvals_0) >>> 0);
  return $List$append$({$: "Con", "head": {$: "Bgl", "binding": 0, "ty": ($BIND_UNIFORM$())}, "tail": {$: "Nil"}}, ($bgl$of$go$(_x_0, 0, _nbufs_0, {$: "Nil"})));
}

function $Pass$nentries$(_p_0) {
  const _nentries_0 = _p_0["nentries"];
  return _nentries_0;
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

function $Pass$of$(_entry_0, _feats_0) {
  return {$: "Pass", "module": 0, "entry": _entry_0, "feats": _feats_0, "ls": 0, "nentries": 0, "sizes": {$: "Nil"}, "gx": 1, "gy": 1, "gz": 1, "wait": false, "t": ($Tr$of$())};
}

function $fx_call$(_feats_0, _want_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, _want_0, ($Pass$reset$(($fx_pass$(_feats_0)))));
}

function $Pass$tr$(_p_0) {
  const _t_0 = _p_0["t"];
  return _t_0;
}

function $Bool$not$(_b_0) {
  if (!_b_0) {
    return true;
  } else {
    return false;
  }
}

function $CALL_SUBMIT$() {
  return 16;
}

function $CALL_FINISH$() {
  return 15;
}

function $CALL_DISPATCH$() {
  return 12;
}

function $CALL_PUSH$() {
  return 3;
}

function $FILTER_VALIDATION$() {
  return 1;
}

function $OBJ_BIND_GROUP_LAYOUT$() {
  return 5;
}

function $OBJ_PIPELINE_LAYOUT$() {
  return 6;
}

function $OBJ_BUFFER$() {
  return 13;
}

function $OBJ_BIND_GROUP$() {
  return 7;
}

function $SYNC_CREATE_PIPELINE$() {
  return 3;
}

function $OBJ_COMMAND_ENCODER$() {
  return 9;
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

function $BIND_GROUP_INDEX$() {
  return 0;
}

function $CALL_END$() {
  return 13;
}

function $OBJ_COMPUTE_PIPELINE$() {
  return 8;
}

function $OBJ_COMPUTE_PASS$() {
  return 10;
}

function $OBJ_COMMAND_BUFFER$() {
  return 11;
}

function $grouped$(_t_0) {
  return $Tr$args$(($CALL_SET_BIND_GROUP$()), ($Tr$calls$(_t_0)));
}

function $dispatched$(_t_0) {
  return $Tr$args$(($CALL_DISPATCH$()), ($Tr$calls$(_t_0)));
}

function $seen$(_t_0) {
  const _x_0 = ($List$length$(($Tr$calls$(_t_0))));
  return (_x_0 >>> 0);
}

function $lrow$(_nm_0, _xs_0) {
  return (_x_0) => $IO$print$(($String$concat$({$: "Con", "head": _nm_0, "tail": {$: "Con", "head": "=", "tail": {$: "Con", "head": ($String$join$(($ush$(_xs_0, ",", {$: "Nil"})), ",")), "tail": {$: "Nil"}}}})), _x_0);
}

function $Pass$sizes$(_p_0) {
  const _sizes_0 = _p_0["sizes"];
  return _sizes_0;
}

function $Pass$ls$(_p_0) {
  const _ls_0 = _p_0["ls"];
  return _ls_0;
}

function $Pass$gx$(_p_0) {
  const _gx_0 = _p_0["gx"];
  return _gx_0;
}

function $fx_life$(_feats_0, _want_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, _want_0, ($fx_pass$(_feats_0)));
}

function $Pass$wait$(_p_0) {
  const _wait_0 = _p_0["wait"];
  return _wait_0;
}

function $OBJ_QUERY_SET$() {
  return 12;
}

function $CALL_RESOLVE$() {
  return 14;
}

function $QUERY_COUNT$() {
  return 2;
}

function $CALL_COPY$() {
  return 8;
}

function $QUERY_BUF_SIZE$() {
  return 16;
}

function $SYNC_MAP_ASYNC$() {
  return 1;
}

function $CALL_MAPPED_RANGE$() {
  return 6;
}

function $CALL_DESTROY$() {
  return 18;
}

function $CALL_DESTROY_QUERY_SET$() {
  return 19;
}

function $ncreated$(_t_0) {
  const _x_0 = ($List$length$(($created$(_t_0))));
  return (_x_0 >>> 0);
}

function $CALL_MAP_ASYNC$() {
  return 5;
}

function $fx_refuse$(_bad_at_0) {
  return $prog$call$(($bufs3$()), 1, 8, 1, 1, 4, false, ($fx_fail$(($BOTH$()), _bad_at_0)));
}

function $Tr$refused$(_t_0) {
  const _refused_0 = _t_0["refused"];
  return _refused_0;
}

function $OBJ_SHADER_MODULE$() {
  return 4;
}

function $alloc$size$(_nbytes_0) {
  return $$$$047helpers$round_up_u32$(_nbytes_0, 4);
}

function $alloc$usage$() {
  const _x_0 = ($USAGE_STORAGE$());
  const _x_1 = ($USAGE_COPY_DST$());
  const _x_2 = ((_x_0 | _x_1) >>> 0);
  const _x_3 = ($USAGE_COPY_SRC$());
  return ((_x_2 | _x_3) >>> 0);
}

function $dev$uniform_usage$() {
  const _x_0 = ($USAGE_UNIFORM$());
  const _x_1 = ($USAGE_COPY_DST$());
  return ((_x_0 | _x_1) >>> 0);
}

function $copy$readable_usage$() {
  const _x_0 = ($USAGE_COPY_DST$());
  const _x_1 = ($USAGE_MAP_READ$());
  return ((_x_0 | _x_1) >>> 0);
}

function $USAGE_QUERY_RESOLVE$() {
  return 512;
}

function $USAGE_COPY_SRC$() {
  return 4;
}

function $alloc$of$(_size_0, _t_0) {
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": ($alloc$size$(_size_0))}, "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))};
}

function $Tr$of$() {
  return {$: "Tr", "calls": {$: "Nil"}, "next": 0, "depth": 0, "bad_at": 0, "popn": 0, "refused": false};
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

function $written$(_t_0) {
  return $Tr$args$(($CALL_WRITE$()), ($Tr$calls$(_t_0)));
}

function $copy$readable$(_size_0, _t_0) {
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": _size_0}, "t": ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_ENCODER$()), ($Tr$emit$(($CALL_RELEASE$()), ($OBJ_COMMAND_BUFFER$()), ($Tr$emit$(($CALL_SUBMIT$()), 1, ($Tr$emit$(($CALL_FINISH$()), 1, ($Tr$emit$(($CALL_COPY$()), _size_0, ($Tr$emit$(($CALL_CREATE$()), ($OBJ_COMMAND_ENCODER$()), ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))))))))))))))};
}

function $dev$free$(_map_state_0, _id_0, _t_0) {
  const _x_0 = ($MAP_MAPPED$());
  return $dev$free$at$((_map_state_0 === _x_0), _id_0, _t_0);
}

function $CALL_UNMAP$() {
  return 17;
}

function $dev$uniform_bytes$(_v_0) {
  return $dev$uniform_bytes$go$(4, _v_0, {$: "Nil"});
}

function $dev$create_uniform$(_bytes_0, _t_0) {
  const _x_0 = ($List$length$(_bytes_0));
  return {$: "Made", "buf": {$: "Buf", "id": ($Tr$here$(_t_0)), "size": (_x_0 >>> 0)}, "t": ($copy$write$(_bytes_0, ($Tr$emit$(($CALL_CREATE$()), ($OBJ_BUFFER$()), _t_0))))};
}

function $CALL_WRITE$() {
  return 7;
}

function $sync_ret$(_n_0) {
  return TAB_0[Math.min(_n_0, 2)];
}

function $sync_has_emsg$(_which_0) {
  const _x_0 = ($SYNC_POP_ERROR_SCOPE$());
  return $Bool$pick$((_which_0 === _x_0), ($SYNC_NO_EMSG$()), ($SYNC_HAS_EMSG$()));
}

function $SYNC_POP_ERROR_SCOPE$() {
  return 2;
}

function $SYNC_WORK_DONE$() {
  return 6;
}

function $sync_payload$(_nargs_0, _has_emsg_0) {
  const _x_0 = ($SYNC_NO_EMSG$());
  return $Bool$pick$((_has_emsg_0 === _x_0), nat_chk(_nargs_0 + 1), _nargs_0);
}

function $SYNC_NO_EMSG$() {
  return 2;
}

function $SYNC_HAS_EMSG$() {
  return 1;
}

function $sync_tail$(_s_0) {
  const _x_0 = ($sync_us$(($String$to_list$(_s_0))));
  return $String$drop$(_s_0, _x_0);
}

function $List$length$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _xs_0["tail"];
    return nat_chk(($List$length$(_t_0)) + 1);
  }
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

function $sync_name$six2$() {
  return {$: "Con", "head": ($sync_tail$(($sync_name$two$(1)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(2)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(3)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(4)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(5)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$two$(6)))), "tail": {$: "Nil"}}}}}}};
}

function $sync_name$six3$() {
  return {$: "Con", "head": ($sync_tail$(($sync_name$three$(1)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(2)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(3)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(4)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(5)))), "tail": {$: "Con", "head": ($sync_tail$(($sync_name$three$(6)))), "tail": {$: "Nil"}}}}}}};
}

function $sync_name$of$(_which_0, _status_0) {
  const _x_0 = ($STATUS_SUCCESS$());
  return $Bool$pick$((_status_0 === _x_0), "Success", ($sync_name$of$err$(_which_0, _status_0)));
}

function $sync_error$(_which_0, _status_0, _emsg_0) {
  const _x_0 = ($STATUS_SUCCESS$());
  return $Bool$pick$((_status_0 === _x_0), "", ($String$concat$({$: "Con", "head": "[", "tail": {$: "Con", "head": ($sync_name$of$(_which_0, _status_0)), "tail": {$: "Con", "head": "]", "tail": {$: "Con", "head": _emsg_0, "tail": {$: "Nil"}}}}})));
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

function $backend_names$() {
  return {$: "Con", "head": "WGPUBackendType_Undefined", "tail": {$: "Con", "head": "WGPUBackendType_Null", "tail": {$: "Con", "head": "WGPUBackendType_WebGPU", "tail": {$: "Con", "head": "WGPUBackendType_D3D11", "tail": {$: "Con", "head": "WGPUBackendType_D3D12", "tail": {$: "Con", "head": "WGPUBackendType_Metal", "tail": {$: "Con", "head": "WGPUBackendType_Vulkan", "tail": {$: "Con", "head": "WGPUBackendType_OpenGL", "tail": {$: "Con", "head": "WGPUBackendType_OpenGLES", "tail": {$: "Nil"}}}}}}}}}};
}

function $Bool$show$(_b_0) {
  if (!_b_0) {
    return "False";
  } else {
    return "True";
  }
}

function $dev$request_adapter$(_d_0, _backend_name_0) {
  const _instance_0 = _d_0["instance"];
  const _t_0 = _d_0["t"];
  return {$: "Dev", "instance": _instance_0, "adapter": ($Tr$here$(_t_0)), "device_res": 0, "queue": 0, "features": {$: "Nil"}, "backend": ($backend_of$(_backend_name_0)), "nrequired": 0, "arch": "", "t": ($Tr$emit$(($CALL_WAIT$()), ($SYNC_REQUEST_ADAPTER$()), _t_0))};
}

function $dev$create_instance$() {
  return {$: "Dev", "instance": ($Tr$here$(($Tr$of$()))), "adapter": 0, "device_res": 0, "queue": 0, "features": {$: "Nil"}, "backend": 0, "nrequired": 0, "arch": "", "t": ($Tr$emit$(($CALL_CREATE$()), ($OBJ_INSTANCE$()), ($Tr$of$())))};
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

function $FEATURE_TIMESTAMP_QUERY$() {
  return 3;
}

function $FEATURE_SHADER_F16$() {
  return 8;
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

function $Tr$has$(_cs_0, _pat_0) {
  return $Tr$has$go$(($List$length$(_cs_0)), ($List$length$(_pat_0)), _cs_0, _pat_0, 0);
}

function $Tr$calls$(_t_0) {
  const _calls_0 = _t_0["calls"];
  return _calls_0;
}

function $Tr$args$(_k_0, _cs_0) {
  return $Tr$args$go$(($List$length$(_cs_0)), _k_0, _cs_0, {$: "Nil"});
}

function $Tr$count$(_k_0, _cs_0) {
  return $Tr$count$go$(($List$length$(_cs_0)), _k_0, _cs_0, 0);
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
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

function $BIND_UNIFORM$() {
  return 1;
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

function $Tr$reset$(_t_0) {
  const _bad_at_0 = _t_0["bad_at"];
  const _popn_0 = _t_0["popn"];
  return {$: "Tr", "calls": {$: "Nil"}, "next": 0, "depth": 0, "bad_at": _bad_at_0, "popn": _popn_0, "refused": false};
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

function $prog$call$(_bs_0, _nvals_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0, _p_0) {
  return $prog$call$at$(_bs_0, _nvals_0, _gx_0, _gy_0, _gz_0, _ls_0, _want_0, _p_0);
}

function $bufs3$() {
  return $bufs$go$(3, 100, {$: "Con", "head": 64, "tail": {$: "Con", "head": 64, "tail": {$: "Con", "head": 64, "tail": {$: "Nil"}}}}, {$: "Nil"});
}

function $fx_pass$(_feats_0) {
  return $prog$init$("k", ($dev$init$(($METAL$()), _feats_0)));
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

function $fx_fail$(_feats_0, _bad_at_0) {
  return $prog$init$("k", ($fx_fail$at$(($dev$init$(($METAL$()), _feats_0)), _bad_at_0)));
}

function $$$$047helpers$round_up_u32$(_num_0, _amt_0) {
  const _x_0 = ($$$$047helpers$ceildiv_u32$(_num_0, _amt_0));
  return (Math.imul(_x_0, _amt_0) >>> 0);
}

function $USAGE_STORAGE$() {
  return 128;
}

function $USAGE_COPY_DST$() {
  return 8;
}

function $USAGE_UNIFORM$() {
  return 64;
}

function $USAGE_MAP_READ$() {
  return 1;
}

function $Tr$here$(_t_0) {
  return $Tr$next$(_t_0);
}

function $dev$free$at$(_mapped_0, _id_0, _t_0) {
  if (_mapped_0) {
    return $Tr$emit$(($CALL_RELEASE$()), _id_0, ($Tr$emit$(($CALL_DESTROY$()), _id_0, ($Tr$emit$(($CALL_UNMAP$()), _id_0, _t_0)))));
  } else {
    return $Tr$emit$(($CALL_RELEASE$()), _id_0, ($Tr$emit$(($CALL_DESTROY$()), _id_0, _t_0)));
  }
}

function $MAP_MAPPED$() {
  return 3;
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

function $copy$write$(_bytes_0, _t_0) {
  const _x_0 = ($List$length$(_bytes_0));
  return $Tr$emit$(($CALL_WRITE$()), (_x_0 >>> 0), _t_0);
}

function $SYNC_NONE$() {
  return 0;
}

function $SYNC_MANY$() {
  return 2;
}

function $SYNC_ONE$() {
  return 1;
}

function $Bool$pick$(_c_0, _a_0, _b_0) {
  if (!_c_0) {
    return _b_0;
  } else {
    return _a_0;
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

function $sync_us$(_cs_0) {
  return $sync_us$at$(($List$length$(_cs_0)), _cs_0);
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

function $$$$047helpers$dedup_str$go$(_x_0, _r_0) {
  return $$$$047helpers$dedup_str$put$(($List$contains$1261$(_r_0, _x_0)), _x_0, _r_0);
}

function $sync_name$two$(_which_0) {
  return $sync_name$two$at$(_which_0);
}

function $sync_name$three$(_which_0) {
  return $sync_name$three$at$(_which_0);
}

function $STATUS_SUCCESS$() {
  return 1;
}

function $sync_name$of$err$(_which_0, _status_0) {
  return $Bool$pick$((_status_0 === 2), ($sync_name$two$(_which_0)), ($sync_name$three$(_which_0)));
}

function $backend_of$put$(_s_0, _h_0, _at_0, _got_0) {
  return $Bool$pick$(($String$eq$(_h_0, _s_0)), _at_0, _got_0);
}

function $dev$arch_of$(_fs_0) {
  return $Bool$pick$(($List$contains$1260$(_fs_0, ($FEATURE_SHADER_F16$()))), "shader-f16", "");
}

function $features_keep$put$(_x_0, _acc_0) {
  return $Bool$pick$(($keeps_feature$(_x_0)), ($List$append$(_acc_0, {$: "Con", "head": _x_0, "tail": {$: "Nil"}})), _acc_0);
}

function $Pair$snd$(_p_0) {
  const _b_0 = _p_0["snd"];
  return _b_0;
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

function $List$reverse$(_xs_0) {
  return $List$reverse$go$(_xs_0, {$: "Nil"});
}

function $bgl$entry$put$(_i_0, _nbufs_0, _acc_0) {
  return {$: "Con", "head": {$: "Bgl", "binding": ((_i_0 + 1) >>> 0), "ty": ($Bool$pick$((_i_0 >= _nbufs_0), ($BIND_UNIFORM$()), ($BIND_STORAGE$())))}, "tail": _acc_0};
}

function $Tr$pop$go$(_refused_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0) {
  return {$: "Tr", "calls": ($Bool$pick$(_refused_0, _calls_0, ($List$append$(_calls_0, {$: "Con", "head": {$: "Call", "k": ($CALL_POP$()), "arg": ($FILTER_VALIDATION$())}, "tail": {$: "Nil"}})))), "next": _next_0, "depth": ($Bool$pick$(_refused_0, _depth_0, ((_depth_0 - 1) >>> 0))), "bad_at": _bad_at_0, "popn": ($Bool$pick$(_refused_0, _popn_0, ((_popn_0 + 1) >>> 0))), "refused": ($Tr$pop$hit$(_bad_at_0, _popn_0, _refused_0))};
}

function $Tr$emit$go$(_refused_0, _k_0, _arg_0, _calls_0, _next_0, _depth_0, _bad_at_0, _popn_0) {
  return {$: "Tr", "calls": ($Bool$pick$(_refused_0, _calls_0, ($List$append$(_calls_0, {$: "Con", "head": {$: "Call", "k": _k_0, "arg": _arg_0}, "tail": {$: "Nil"}})))), "next": ($Bool$pick$(_refused_0, _next_0, ((_next_0 + 1) >>> 0))), "depth": _depth_0, "bad_at": _bad_at_0, "popn": _popn_0, "refused": _refused_0};
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

function $prog$init$(_entry_0, _d_0) {
  const _features_0 = _d_0["features"];
  const _t_0 = _d_0["t"];
  return {$: "Pass", "module": ($Tr$here$(_t_0)), "entry": _entry_0, "feats": _features_0, "ls": 0, "nentries": 0, "sizes": {$: "Nil"}, "gx": 1, "gy": 1, "gz": 1, "wait": false, "t": ($Tr$pop$(($Tr$emit$(($CALL_CREATE$()), ($OBJ_SHADER_MODULE$()), ($Tr$push$(_t_0))))))};
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

function $fx_fail$at$(_d_0, _bad_at_0) {
  return $Dev$at$(_d_0, ($Tr$fail_at$(($Dev$tr$(_d_0)), _bad_at_0)));
}

function $$$$047helpers$ceildiv_u32$(_num_0, _amt_0) {
  const _x_0 = (_amt_0 === 0 ? _num_0 : _num_0 % _amt_0);
  const _x_1 = (_amt_0 === 0 ? 0 : (_num_0 / _amt_0) >>> 0);
  const _x_2 = ($Bool$to_u32$((_x_0 !== 0)));
  return $$$$047helpers$div0$((_amt_0 === 0), ((_x_1 + _x_2) >>> 0));
}

function $Tr$next$(_t_0) {
  const _next_0 = _t_0["next"];
  return _next_0;
}

function $sync_us$at$(_n_0, _cs_0) {
  return $sync_us$go$(_n_0, 0, 0, _cs_0);
}

function $$$$047helpers$dedup_str$put$(_seen_0, _h_0, _r_0) {
  if (_seen_0) {
    return _r_0;
  } else {
    return {$: "Con", "head": _h_0, "tail": _r_0};
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

function $keeps_feature$(_f_0) {
  const _x_0 = ($FEATURE_TIMESTAMP_QUERY$());
  const _x_1 = ($FEATURE_SHADER_F16$());
  const _x_2 = (_f_0 === _x_0);
  const _x_3 = (_f_0 === _x_1);
  return (_x_2 || _x_3);
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

function $Nat$is_eq$(_a_0, _b_0) {
  return $Cmp$is_eq$(cmp_new(_a_0, _b_0));
}

function $Tr$has$step$(_m_0, _c_0, _at_0) {
  if (_m_0.$ === "None") {
    return _at_0;
  } else {
    const _want_0 = _m_0["value"];
    return $Tr$has$step$hit$(($Tr$has$step$same2$(($Call$k$(_c_0)), ($Call$k$(_want_0)), ($Call$arg$(_c_0)), ($Call$arg$(_want_0)))), _at_0);
  }
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

function $Tr$args$put$(_c_0, _k_0, _acc_0) {
  const _x_0 = ($Call$k$(_c_0));
  return $Bool$pick$((_x_0 === _k_0), ($List$append$(_acc_0, {$: "Con", "head": ($Call$arg$(_c_0)), "tail": {$: "Nil"}})), _acc_0);
}

function $Bool$to_u32$(_b_0) {
  if (!_b_0) {
    return 0;
  } else {
    return 1;
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

function $BIND_STORAGE$() {
  return 2;
}

function $Tr$pop$hit$(_bad_at_0, _popn_0, _refused_0) {
  const _x_0 = ((_popn_0 + 1) >>> 0);
  const _x_1 = (_x_0 === _bad_at_0);
  return (_refused_0 || _x_1);
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

function $pass$timing$(_p_0) {
  return $pass$timing$at$(($Pass$wait$(_p_0)), _p_0);
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

function $Tr$fail_at$(_t_0, _n_0) {
  const _calls_0 = _t_0["calls"];
  const _next_0 = _t_0["next"];
  const _depth_0 = _t_0["depth"];
  const _popn_0 = _t_0["popn"];
  const _refused_0 = _t_0["refused"];
  return {$: "Tr", "calls": _calls_0, "next": _next_0, "depth": _depth_0, "bad_at": _n_0, "popn": _popn_0, "refused": _refused_0};
}

function $$$$047helpers$div0$(_zero_0, _v_0) {
  if (_zero_0) {
    return 0;
  } else {
    return _v_0;
  }
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

function $String$cmp$rec$(_h1b_0, _h2b_0, _rr_0) {
  const _t_0 = _rr_0["fst"];
  const _t1b_0 = _t_0["fst"];
  const _t2b_0 = _t_0["snd"];
  const _r_0 = _rr_0["snd"];
  return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1b_0), "snd": (_h2b_0 + _t2b_0)}, "snd": _r_0};
}

function $Tr$has$step$hit$(_same_0, _at_0) {
  if (_same_0) {
    return nat_chk(_at_0 + 1);
  } else {
    return _at_0;
  }
}

function $Tr$has$step$same2$(_k1_0, _k2_0, _a1_0, _a2_0) {
  return $Bool$and$((_k1_0 === _k2_0), (_a1_0 === _a2_0));
}

function $Call$k$(_c_0) {
  const _k_0 = _c_0["k"];
  return _k_0;
}

function $Call$arg$(_c_0) {
  const _arg_0 = _c_0["arg"];
  return _arg_0;
}

function $prog$wants_wait$(_want_0, _feats_0) {
  return $Bool$and$(_want_0, ($List$contains$1260$(_feats_0, ($FEATURE_TIMESTAMP_QUERY$()))));
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

function $slots$(_bs_0, _nvals_0) {
  return $slots$vals$(_nvals_0, ($slots$bufs$(($List$length$(_bs_0)), _bs_0, {$: "Con", "head": {$: "Slot", "is_buf": false, "size": ($UNIFORM_SIZE$())}, "tail": {$: "Nil"}})));
}

function $pass$query$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$query$on$(_p_0);
  }
}

function $pass$resolve$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$resolve$on$(_p_0);
  }
}

function $pass$timing$at$(_wait_0, _p_0) {
  if (!_wait_0) {
    return _p_0;
  } else {
    return $pass$timing$on$(_p_0);
  }
}

function $Char$is_eq$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return (_x_0 === _x_1);
}

function $UNDER$() {
  return $Char$from_u32$(95);
}

function $SYNC_MISSING$() {
  return "None";
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

function $UNIFORM_SIZE$() {
  return 4;
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

function $Char$from_u32$(_x_0) {
  return char_new(_x_0);
}

function $copy$read_made$(_usage_0, _size_0, _m_0) {
  return {$: "Made", "buf": ($Made$buf$(_m_0)), "t": ($copy$read$(_usage_0, _size_0, ($Made$tr$(_m_0))))};
}

function $MAP_UNMAPPED$() {
  return 1;
}

function $copy$read$(_usage_0, _size_0, _t_0) {
  return $Tr$emit$(($CALL_MAPPED_RANGE$()), _size_0, ($Tr$emit$(($CALL_MAP_ASYNC$()), _usage_0, ($Tr$emit$(($CALL_WAIT$()), ($SYNC_MAP_ASYNC$()), _t_0)))));
}

const TAB_0 = [0, 1, 2];
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