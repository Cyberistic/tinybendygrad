# gates/webgpu_call-gate.bend -- the gate driver for `tinybendygrad/runtime/webgpu_call.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/webgpu_call.bend as P

import ./../tinybendygrad/runtime/ops_webgpu.bend as W
import ./../tinybendygrad/helpers.bend as H
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

# the (k, arg) trace projection, rendered -- so a mismatch is DIAGNosable from the
# output alone rather than only as a False.
def pairs(xs: List<&2, W.Call>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case W.Call{k, a} <> t: pairs(t, String.concat([U32.show(k), ":", U32.show(a)]) <> acc)

def crow(nm: String, xs: List<&2, W.Call>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(pairs(xs, Nil{}), " ")]))

# --- 1: the constants, each against the `autogen/webgpu.py` line it came from --
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("wgc_stage_compute", P.SHADER_STAGE_COMPUTE())
    urow("wgc_query_type", P.QUERY_TYPE_TIMESTAMP())
    urow("wgc_map_mode_read", P.MAP_MODE_READ())
    urow("wgc_power_pref", P.POWER_PREF_HIGH_PERF())
    urow("wgc_stype_wgsl", P.STYPE_SHADER_SOURCE_WGSL())
    urow("wgc_lit_query_bytes", P.QUERY_BUF_BYTES())
    urow("wgc_lit_query_count", P.QUERY_COUNT())
    urow("wgc_lit_begin_pass", P.BEGIN_PASS())
    urow("wgc_lit_end_pass", P.END_PASS())
    urow("wgc_lit_submit", P.SUBMIT_COUNT())
    urow("wgc_lit_resolve", P.RESOLVE_COUNT())
    # WALL 2's flag, on the C side. NO `P.Op` mentions it -- a browser has no timed
    # wait -- and this row is the number it had.
    urow("wgc_callback_mode_gone", P.CALLBACK_MODE_WAIT_ANY_ONLY())

# --- 2: the init ops agree with `dev.init`'s trace --------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    +c : P.Cs <- IO.pure(P.Cs, P.Cs.init(P.METAL(), P.BOTH()))
    +d : W.Dev <- IO.pure(W.Dev, P.fx_real_init())
    row("wgc_init_trace", W.Tr.has(P.Cs.calls(c), W.Tr.calls(W.Dev.tr(d))))
    crow("wgc_init_calls", P.Cs.calls(c))
    crow("wgc_init_real", W.Tr.calls(W.Dev.tr(d)))
    row("wgc_init_len", U32.is_eq(P.Cs.len(c), W.seen(W.Dev.tr(d))))
    urow("wgc_init_steps", P.Cs.len(c))
    row("wgc_init_power", U32.is_eq(W.backend_of(P.METAL()), 5))
    # the two constants the RequestAdapter op carries, against the oracle's values.
    row("wgc_init_power_pref", U32.is_eq(P.POWER_PREF_HIGH_PERF(), 2))

# --- 3: THE CENTRAL ROW. This file's step order IS `prog.call`'s trace order --
def t_call() -> IO(Unit):
  do IO<Unit>:
    +c : P.Cs <- IO.pure(P.Cs, P.fx(False{}))
    +p : W.Pass <- IO.pure(W.Pass, P.fx_real(False{}))
    # EQUALITY, not subsequence: equal lengths plus `Tr.has` is equality, and both
    # halves are one row each so neither can be satisfied alone.
    row("wgc_call_trace", W.Tr.has(P.Cs.calls(c), W.Tr.calls(W.Pass.tr(p))))
    row("wgc_call_len", U32.is_eq(P.Cs.len(c), P.Cs.of_calls(W.seen(W.Pass.tr(p)))))
    crow("wgc_call_mine", P.Cs.calls(c))
    crow("wgc_call_real", W.Tr.calls(W.Pass.tr(p)))
    urow("wgc_call_steps", P.Cs.len(c))
    # FOUR error scopes, not the three `wg_call_pushes` reports. `wg_call_pushes`
    # reads `fx_call`, whose `Pass.reset` drops the shader module's -- and
    # `ops_webgpu.bend` says of :62-64 "PushErrorScope(Validation),
    # CreateShaderModule, pop_error", so the module's scope is REAL and is only
    # absent from that fixture. This file's `P.fx` covers :53-147, so all four are
    # here, and the two halves are equal -- which is the claim worth making: an
    # unbalanced scope is a leaked validation scope, and nothing else would say so.
    row("wgc_call_scopes", U32.is_eq(P.Cs.count(W.CALL_PUSH(), c), 4))
    row("wgc_call_scope_balanced", U32.is_eq(P.Cs.count(W.CALL_PUSH(), c),
                                             P.Cs.count(W.CALL_POP(), c)))
    row("wgc_call_no_pipeline_scope", U32.is_eq(P.Cs.count_of_wait(c, W.SYNC_CREATE_PIPELINE()), 1))

# --- 4: the wait arms, :112-145 --------------------------------------------
def t_wait() -> IO(Unit):
  do IO<Unit>:
    +c : P.Cs <- IO.pure(P.Cs, P.fx(True{}))
    +p : W.Pass <- IO.pure(W.Pass, P.fx_real(True{}))
    row("wgc_wait_trace", W.Tr.has(P.Cs.calls(c), W.Tr.calls(W.Pass.tr(p))))
    row("wgc_wait_len", U32.is_eq(P.Cs.len(c), P.Cs.of_calls(W.seen(W.Pass.tr(p)))))
    crow("wgc_wait_mine", P.Cs.calls(c))
    crow("wgc_wait_real", W.Tr.calls(W.Pass.tr(p)))
    # `wait` needs the feature (:71), so the same call with P.F16 only must NOT
    # create the query set -- the counterpart to `wg_wait_no_ts_creates`.
    +n : P.Cs <- IO.pure(P.Cs, P.Cs.call(P.bufs3(), 1n, P.ONE(), 8, 1, 1, True{}, P.F16(),
                                   P.CODE(), "BODY"))
    row("wgc_wait_no_ts", Bool.not(P.Cs.wait(n)))
    urow("wgc_wait_no_ts_steps", P.Cs.len(n))
    row("wgc_wait_no_ts_eq_nowait", U32.is_eq(P.Cs.len(n), P.Cs.len(P.fx_nowait())))

# --- 5: the descriptors, the thing the trace cannot carry ------------------
def t_desc() -> IO(Unit):
  do IO<Unit>:
    +c : P.Cs <- IO.pure(P.Cs, P.fx(False{}))
    # the three usage bitmasks, against the oracle's derivation from :152, :203
    # and :208 -- and each against the literal `wg_*_usage` already prints.
    row("wgc_usage_alloc", U32.is_eq(W.alloc.usage(), 140))
    row("wgc_usage_uniform", U32.is_eq(W.dev.uniform_usage(), 72))
    row("wgc_usage_readable", U32.is_eq(W.copy.readable_usage(), 9))
    row("wgc_usage_query", U32.is_eq(U32.or(W.USAGE_QUERY_RESOLVE(), W.USAGE_COPY_SRC()), 516))
    row("wgc_visibility", U32.is_eq(P.SHADER_STAGE_COMPUTE(), 4))
    row("wgc_query_type_val", U32.is_eq(P.QUERY_TYPE_TIMESTAMP(), 2))
    # the bind group's sizes, which is `W.slots`' answer and the seam's payload.
    lrow("wgc_bg_sizes", P.Cs.bg_sizes(P.Cs.bg(c)))
    lrow("wgc_bg_ids", P.Cs.bg_ids(P.Cs.bg(c)))
    # THE BUFFER HANDLES EACH ENTRY BINDS, and this is the row that reads what
    # `wgc_bg_sizes` cannot: a wrong buffer id leaves every SIZE correct. MEASURED:
    # `P.Cs.caller`'s `Bool.pick` arms were the wrong way round, so all three `P.bufs`
    # entries bound id 0, and the browser rejected the bind group with "Failed to
    # convert value to 'GPUBuffer'" at step 20 of 57. The expectation is the
    # LITERAL 3, 100, 101, 102 -- `P.bufs3` starts at 100 so a caller's id can never
    # collide with a slot the seam mints -- and it is a literal, not a call of the
    # thing under test.
    lrow("wgc_bg_handles", P.Cs.bg_bufs(P.Cs.bg(c)))
    urow("wgc_bg_n", U32.from_nat(List.length(&2, P.Bind, P.Cs.bg(c))))
    row("wgc_layout_entries", W.u32_list_eq(W.bgl.flat(W.bgl.of(3, 1), Nil{}),
                                            [0, 1, 1, 2, 2, 2, 3, 2, 4, 1]))
    row("wgc_vals_count", U32.is_eq(U32.from_nat(List.length(&2, U32, P.ONE())), 1))
    # every slot the walk mints is distinct, and this row exists because a counter
    # that never advances is invisible to every other row in the file. MEASURED:
    # with `P.Cs.mint(c)` bound and then `P.Cs.at(P.Cs.push(c), ..)` written, every
    # handle came out 4294967295 -- `P.Cs.next(0) - 1` -- and 50 rows stayed green,
    # because `P.Cs.calls` reads the trace and `P.Cs.bg` reads the bind group and
    # NEITHER READS `next`. The browser was what caught it, at `PipelineLayout`.
    # So this asks the counter a question no other row asks: are the slots the walk
    # hands out pairwise different?
    # the slots the driver hangs every result on, and the claim is not "all
    # distinct" -- it is "distinct except the one pair that must share".
    #
    # `Finish` (:128) and `Submit` (:129) both take the SAME command buffer, so
    # `P.Cs.finish` gives them one slot and `wgc_handles_shared` is the row that says
    # so. MEASURED: the first version of this row asserted plain distinctness and
    # was False, and the reason was correct code -- the slot list is
    # `0,1,2,3,4,5,6,7,8,8` and the last two are one buffer submitted after it is
    # finished. A row that says "all distinct" here would be a row that forbids the
    # port from being right.
    #
    # WHAT IT IS REALLY FOR: a counter that never advances is invisible to every
    # other row in this file, because `P.Cs.calls` reads the trace and `P.Cs.bg` reads
    # the bind group and NEITHER READS `next`. MEASURED: with the mint bound and
    # then discarded, every handle came out 4294967295 and 50 rows stayed green --
    # the browser caught it at `PipelineLayout`. `wgc_handles_contiguous` is the row
    # that asks the counter the question nothing else asks.
    row("wgc_handles_monotone", P.Cs.monotone(P.Cs.slots(P.fx(False{}))))
    row("wgc_handles_monotone_wait", P.Cs.monotone(P.Cs.slots(P.fx(True{}))))
    row("wgc_handles_shared", U32.is_eq(P.Cs.dupe_of(P.Cs.slots(P.fx(False{}))), 8))
    lrow("wgc_handles", P.Cs.slots(P.fx(False{})))
    lrow("wgc_handles_wait", P.Cs.slots(P.fx(True{})))
    lrow("wgc_handles_init", P.Cs.slots(P.Cs.init(P.METAL(), P.BOTH())))

def t_wall3() -> IO(Unit):
  do IO<Unit>:
    # :97 binds `float('inf')` at binding 0, and `dev.uniform_bytes` cannot build
    # an f32 pattern. So the op says `is_f32` and the driver builds it.
    +b : P.Bind <- IO.pure(P.Bind, P.Cs.or0_one(P.Cs.bg(P.fx(False{}))))
    row("wgc_wall3_found", U32.is_eq(P.Bind.n(b), 0))
    urow("wgc_wall3_size", P.Bind.size(b))
    row("wgc_wall3_int_bytes", W.u32_list_eq(W.dev.uniform_bytes(7), [7, 0, 0, 0]))
    # and the bytes the uniform op actually carries. M20 reintroduces the
    # one-bit shift INSIDE this file's own `Uniform` and moved no row at all,
    # because `wgc_wall3_int_bytes` calls `dev.uniform_bytes` DIRECTLY and never
    # reads what `P.Cs.entry` put in the op. That is the row that was missing and
    # this is it -- it reads the op, so a wrong byte pattern in the op is visible.
    lrow("wgc_uniform_bytes", P.Cs.uniform_bytes(P.fx(False{})))
    row("wgc_wall3_neg_bytes", W.u32_list_eq(W.dev.uniform_bytes(4294967295),
                                             [255, 255, 255, 255]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_init()
    +c : Unit <- t_call()
    +d : Unit <- t_wait()
    +e : Unit <- t_desc()
    +f : Unit <- t_wall3()
    IO.print("wgc-done=1")
