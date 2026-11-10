# gates/ops_webgpu-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_webgpu.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_webgpu.bend as P
import ./../tinybendygrad/helpers.bend as H

# :41 -- `payload if len(payload) > 1 else payload[0] if len == 1 else None`.
def sync_ret(n: Nat) -> U32:
  match n:
    case 0n: P.SYNC_NONE()
    # `1n+p` claims every positive Nat, so the 2n+q arm must be listed first or
    # it is dead code that still typechecks (bend2-constraints.md, "Correction:
    # numeric patterns are first-match prefix matches"). measured: with the arms
    # the other way round, `wg_sync_ret_2` printed 1.
    case 2n+q: P.SYNC_MANY()
    case 1n+p: P.SYNC_ONE()

# :45-50, the only place `has_emsg` appears. 2 and 6 are the two that pass False.
def sync_has_emsg(which: U32) -> U32:
  Bool.pick(U32, U32.is_eq(which, P.SYNC_POP_ERROR_SCOPE()), P.SYNC_NO_EMSG(), P.SYNC_HAS_EMSG())

# :34 -- the payload length is always nargs + (has_emsg ? 0 : 1), because the
# False case appends `None` rather than nothing.
def sync_payload(+nargs: Nat, has_emsg: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(has_emsg, P.SYNC_NO_EMSG()), Nat.add(nargs, 1n), nargs)

# all six tails, so the gate counts the distinct ones. Counting the six full names
# instead would answer 6 both times and prove nothing, which is what the first run
# of these rows did.
def sync_name.six2() -> List<&2, String>:
  [P.sync_tail(P.sync_name.two(1)), P.sync_tail(P.sync_name.two(2)), P.sync_tail(P.sync_name.two(3)),
   P.sync_tail(P.sync_name.two(4)), P.sync_tail(P.sync_name.two(5)), P.sync_tail(P.sync_name.two(6))]

def sync_name.six3() -> List<&2, String>:
  [P.sync_tail(P.sync_name.three(1)), P.sync_tail(P.sync_name.three(2)), P.sync_tail(P.sync_name.three(3)),
   P.sync_tail(P.sync_name.three(4)), P.sync_tail(P.sync_name.three(5)), P.sync_tail(P.sync_name.three(6))]

def sync_error(+which: U32, +status: U32, emsg: String) -> String:
  Bool.pick(String, U32.is_eq(status, P.STATUS_SUCCESS()), "",
            String.concat(["[", P.sync_name.of(which, status), "]", emsg]))
def dev.create_uniform(+bytes: List<&2, U32>, +t: P.Tr) -> P.Made:
  P.Made{P.Buf{P.Tr.here(t), U32.from_nat(List.length(&2, U32, bytes))},
       P.copy.write(bytes, P.Tr.emit(P.CALL_CREATE, P.OBJ_BUFFER, t))}

def alloc.of(size: U32, +t: P.Tr) -> P.Made:
  P.Made{P.Buf{P.Tr.here(t), P.alloc.size(size)}, P.Tr.emit(P.CALL_CREATE, P.OBJ_BUFFER, t)}

def copy.pad(+nbytes: U32) -> U32: U32.sub(P.copy.write_len(nbytes), nbytes)

def copy.copyin(nbytes: U32, t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_WRITE, P.copy.write_len(nbytes), t)


# --- THE GATE ROWS ------------------------------------------------------

def METAL() -> String: "WGPUBackendType_Metal"
def TS() -> List<&2, U32>: [P.FEATURE_TIMESTAMP_QUERY()]
def F16() -> List<&2, U32>: [P.FEATURE_SHADER_F16()]
def BOTH() -> List<&2, U32>: [P.FEATURE_TIMESTAMP_QUERY(), P.FEATURE_SHADER_F16()]
def NEITHER() -> List<&2, U32>: [1, 2]
def REVERSED() -> List<&2, U32>: [P.FEATURE_SHADER_F16(), P.FEATURE_TIMESTAMP_QUERY()]

def bufs.go(n: Nat, +id: U32, szs: List<&2, U32>, acc: List<&2, P.Buf>) -> List<&2, P.Buf>:
  match n:
    case 0n: List.reverse(&2, P.Buf, acc)
    case 1n+m:
      match szs:
        case Nil{}: List.reverse(&2, P.Buf, acc)
        case s <> t: bufs.go(m, U32.add(id, 1), t, P.Buf{id, s} <> acc)

def bufs3() -> List<&2, P.Buf>: bufs.go(3n, 100, [64, 64, 64], Nil{})

def fx_pass(feats: List<&2, U32>) -> P.Pass: P.prog.init("k", P.dev.init(METAL(), feats))

# the `bad_at`-th error scope reports an error. `dev.init` opens no scope, so the
# program call's pop 1 is the shader module and the call's pops are 2, 3 and 4.
def fx_fail.at(+d: P.Dev, bad_at: U32) -> P.Dev: P.Dev.at(d, P.Tr.fail_at(P.Dev.tr(d), bad_at))

def fx_fail(feats: List<&2, U32>, bad_at: U32) -> P.Pass:
  P.prog.init("k", fx_fail.at(P.dev.init(METAL(), feats), bad_at))

# 3 bufs, 1 val, global (8,1,1), local (4,1,1), wait per the fixture.
def fx_call(feats: List<&2, U32>, want: Bool) -> P.Pass:
  P.prog.call(bufs3(), 1, 8, 1, 1, 4, want, P.Pass.reset(fx_pass(feats)))

def fx_life(feats: List<&2, U32>, want: Bool) -> P.Pass:
  P.prog.call(bufs3(), 1, 8, 1, 1, 4, want, fx_pass(feats))

# a refusal needs a call: `prog.init` alone opens exactly one scope, so with only
# the init in the fixture `bad_at` 2, 3 and 4 never fire and all four rows print
# the same number. That was the bug the first run of this gate found in itself.
def fx_refuse(bad_at: U32) -> P.Pass:
  P.prog.call(bufs3(), 1, 8, 1, 1, 4, False{}, fx_fail(BOTH(), bad_at))

def created(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_CREATE(), P.Tr.calls(t))
def released(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_RELEASE(), P.Tr.calls(t))
def waited(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_WAIT(), P.Tr.calls(t))
def dispatched(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_DISPATCH(), P.Tr.calls(t))
def grouped(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_SET_BIND_GROUP(), P.Tr.calls(t))
def written(t: P.Tr) -> List<&2, U32>: P.Tr.args(P.CALL_WRITE(), P.Tr.calls(t))
def ncalls(k: U32, t: P.Tr) -> U32: P.Tr.count(k, P.Tr.calls(t))
def ncreated(t: P.Tr) -> U32: U32.from_nat(List.length(&2, U32, created(t)))
def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

# --- 1: the backend table, :10 and :169 -------------------------------------
def t_backend() -> IO(Unit):
  do IO<Unit>:
    urow("wg_backend_webgpu", P.backend_of("WGPUBackendType_WebGPU"))
    urow("wg_backend_d3d12", P.backend_of("WGPUBackendType_D3D12"))
    urow("wg_backend_metal", P.backend_of("WGPUBackendType_Metal"))
    urow("wg_backend_vulkan", P.backend_of("WGPUBackendType_Vulkan"))
    urow("wg_backend_opengles", P.backend_of("WGPUBackendType_OpenGLES"))
    urow("wg_backend_bare", P.backend_of("Metal"))
    urow("wg_backend_empty", P.backend_of(""))
    urow("wg_backend_unknown", P.backend_of("nonsense"))
    row("wg_backend_dev", U32.is_eq(P.Dev.backend(P.dev.init(METAL(), BOTH())), 5))

# --- 2: the feature filter and the two derived values, :172-177 and :190 ------
def t_features() -> IO(Unit):
  do IO<Unit>:
    row("wg_feat_order_forward", P.u32_list_eq(P.features_of(BOTH()), [3, 8]))
    row("wg_feat_order_reverse", P.u32_list_eq(P.features_of(REVERSED()), [8, 3]))
    row("wg_feat_only_ts", P.u32_list_eq(P.features_of(TS()), [3]))
    row("wg_feat_only_f16", P.u32_list_eq(P.features_of(F16()), [8]))
    row("wg_feat_none", P.u32_list_eq(P.features_of(NEITHER()), Nil{}))
    row("wg_feat_drops_others", P.u32_list_eq(P.features_of([1, 2, 8, 9, 3]), [8, 3]))
    row("wg_arch_f16", String.eq(P.Dev.arch(P.dev.init(METAL(), F16())), "shader-f16"))
    row("wg_arch_empty", String.eq(P.Dev.arch(P.dev.init(METAL(), TS())), ""))
    row("wg_arch_missing", String.eq(P.Dev.arch(P.dev.init(METAL(), NEITHER())), ""))
    urow("wg_nrequired_two", P.Dev.nrequired(P.dev.init(METAL(), BOTH())))
    urow("wg_nrequired_one", P.Dev.nrequired(P.dev.init(METAL(), F16())))
    urow("wg_nrequired_zero", P.Dev.nrequired(P.dev.init(METAL(), NEITHER())))
    row("wg_feat_device_kept", P.u32_list_eq(P.Dev.features(P.dev.init(METAL(), REVERSED())), [8, 3]))

# --- 3: the init order, :11 then :166-187 ------------------------------------
def t_init() -> IO(Unit):
  do IO<Unit>:
    +d : P.Dev <- IO.pure(P.Dev, P.dev.init(METAL(), BOTH()))
    +t : P.Tr <- IO.pure(P.Tr, P.Dev.tr(d))
    row("wg_init_order", seq(t, [P.Call{P.CALL_CREATE, P.OBJ_INSTANCE},
      P.Call{P.CALL_WAIT, P.SYNC_REQUEST_ADAPTER}, P.Call{P.CALL_GET_FEATURES, 0},
      P.Call{P.CALL_FREE_FEATURES, 0}, P.Call{P.CALL_GET_LIMITS, 0},
      P.Call{P.CALL_WAIT, P.SYNC_REQUEST_DEVICE}, P.Call{P.CALL_CREATE, P.OBJ_QUEUE},
      P.Call{P.CALL_RELEASE, P.OBJ_ADAPTER}]))
    row("wg_init_exact", P.u32_list_eq(created(t), [P.OBJ_INSTANCE, P.OBJ_QUEUE]))
    row("wg_init_waits", P.u32_list_eq(waited(t), [P.SYNC_REQUEST_ADAPTER, P.SYNC_REQUEST_DEVICE]))
    row("wg_init_released", P.u32_list_eq(released(t), [P.OBJ_ADAPTER]))
    urow("wg_init_get_features", ncalls(P.CALL_GET_FEATURES(), t))
    urow("wg_init_free_features", ncalls(P.CALL_FREE_FEATURES(), t))
    urow("wg_init_get_limits", ncalls(P.CALL_GET_LIMITS(), t))
    urow("wg_init_pops", ncalls(P.CALL_POP(), t))
    urow("wg_init_depth", P.Tr.depth(t))
    row("wg_init_ids_ordered", Bool.and(U32.is_lt(P.Dev.instance(d), P.Dev.adapter(d)),
      Bool.and(U32.is_lt(P.Dev.adapter(d), P.Dev.device_res(d)), U32.is_lt(P.Dev.device_res(d), P.Dev.queue(d)))))
    srow("wg_dev_backend", String.concat([P.Dev.arch(d), " ", U32.show(P.Dev.nrequired(d))]))

# --- 4: the layout derivation, :74-78 ----------------------------------------
def t_layout() -> IO(Unit):
  do IO<Unit>:
    row("wg_bgl_none", P.u32_list_eq(P.bgl.flat(P.bgl.of(0, 0), Nil{}), [0, 1]))
    row("wg_bgl_1_0", P.u32_list_eq(P.bgl.flat(P.bgl.of(1, 0), Nil{}), [0, 1, 1, 2]))
    row("wg_bgl_3_1", P.u32_list_eq(P.bgl.flat(P.bgl.of(3, 1), Nil{}), [0, 1, 1, 2, 2, 2, 3, 2, 4, 1]))
    row("wg_bgl_0_2", P.u32_list_eq(P.bgl.flat(P.bgl.of(0, 2), Nil{}), [0, 1, 1, 1, 2, 1]))
    row("wg_bgl_5_0", P.u32_list_eq(P.bgl.flat(P.bgl.of(5, 0), Nil{}), [0, 1, 1, 2, 2, 2, 3, 2, 4, 2, 5, 2]))
    urow("wg_bgl_nentries", P.Pass.nentries(P.Pass.reset(P.pass.layout(3, 1, P.Pass.of("k", BOTH())))))
    urow("wg_bgl_nentries_0", P.Pass.nentries(P.Pass.reset(P.pass.layout(0, 0, P.Pass.of("k", BOTH())))))

# --- 5: one program call, :69-138 --------------------------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    +p : P.Pass <- IO.pure(P.Pass, fx_call(F16(), False{}))
    +t : P.Tr <- IO.pure(P.Tr, P.Pass.tr(p))
    # the matcher pins itself first, because five rows above depend on it being a
    # real subsequence test: a reversed pair must not match, and an entry that
    # never happened must not match.
    row("wg_has_rejects_reverse", Bool.not(seq(t, [P.Call{P.CALL_SUBMIT, 1},
      P.Call{P.CALL_FINISH, 1}])))
    row("wg_has_rejects_absent", Bool.not(seq(t, [P.Call{P.CALL_DISPATCH, 999}])))
    row("wg_call_order", seq(t, [P.Call{P.CALL_PUSH, P.FILTER_VALIDATION},
      P.Call{P.CALL_CREATE, P.OBJ_BIND_GROUP_LAYOUT}, P.Call{P.CALL_POP, P.FILTER_VALIDATION},
      P.Call{P.CALL_PUSH, P.FILTER_VALIDATION}, P.Call{P.CALL_CREATE, P.OBJ_PIPELINE_LAYOUT},
      P.Call{P.CALL_POP, P.FILTER_VALIDATION}, P.Call{P.CALL_CREATE, P.OBJ_BUFFER},
      P.Call{P.CALL_CREATE, P.OBJ_BUFFER}, P.Call{P.CALL_PUSH, P.FILTER_VALIDATION},
      P.Call{P.CALL_CREATE, P.OBJ_BIND_GROUP}, P.Call{P.CALL_POP, P.FILTER_VALIDATION},
      P.Call{P.CALL_WAIT, P.SYNC_CREATE_PIPELINE}, P.Call{P.CALL_CREATE, P.OBJ_COMMAND_ENCODER},
      P.Call{P.CALL_BEGIN, 0}, P.Call{P.CALL_SET_PIPELINE, 0},
      P.Call{P.CALL_SET_BIND_GROUP, P.BIND_GROUP_INDEX()}, P.Call{P.CALL_DISPATCH, 8},
      P.Call{P.CALL_END, 0}, P.Call{P.CALL_FINISH, 1}, P.Call{P.CALL_SUBMIT, 1}]))
    row("wg_call_created", P.u32_list_eq(created(t), [P.OBJ_BIND_GROUP_LAYOUT,
      P.OBJ_PIPELINE_LAYOUT, P.OBJ_BUFFER, P.OBJ_BUFFER, P.OBJ_BIND_GROUP,
      P.OBJ_COMMAND_ENCODER]))
    row("wg_call_released", P.u32_list_eq(released(t), [P.OBJ_BIND_GROUP_LAYOUT,
      P.OBJ_PIPELINE_LAYOUT, P.OBJ_BIND_GROUP, P.OBJ_COMPUTE_PIPELINE,
      P.OBJ_COMMAND_ENCODER, P.OBJ_COMPUTE_PASS, P.OBJ_COMMAND_BUFFER]))
    row("wg_call_waits", P.u32_list_eq(waited(t), [P.SYNC_CREATE_PIPELINE]))
    row("wg_call_bindgroup0", P.u32_list_eq(grouped(t), [P.BIND_GROUP_INDEX()]))
    row("wg_call_dispatch_x", P.u32_list_eq(dispatched(t), [8]))
    urow("wg_call_dispatch_n", ncalls(P.CALL_DISPATCH(), t))
    urow("wg_call_pushes", ncalls(P.CALL_PUSH(), t))
    urow("wg_call_pops", ncalls(P.CALL_POP(), t))
    urow("wg_call_depth", P.Tr.depth(t))
    urow("wg_call_calls", P.seen(t))
    lrow("wg_call_sizes", P.Pass.sizes(p))
    urow("wg_call_ls_recorded", P.Pass.ls(p))
    urow("wg_call_gx", P.Pass.gx(p))
    urow("wg_call_entry_count", P.Pass.nentries(p))
    urow("wg_life_pushes", ncalls(P.CALL_PUSH(), P.Pass.tr(fx_life(BOTH(), False{}))))
    urow("wg_life_pops", ncalls(P.CALL_POP(), P.Pass.tr(fx_life(BOTH(), False{}))))

# --- 6: the wait arms, :71 and :112-145 --------------------------------------
def t_wait() -> IO(Unit):
  do IO<Unit>:
    +p : P.Pass <- IO.pure(P.Pass, fx_call(BOTH(), True{}))
    +t : P.Tr <- IO.pure(P.Tr, P.Pass.tr(p))
    row("wg_wait_flag", P.Pass.wait(p))
    row("wg_wait_query_created", seq(t, [P.Call{P.CALL_CREATE, P.OBJ_COMMAND_ENCODER},
      P.Call{P.CALL_CREATE, P.OBJ_QUERY_SET}, P.Call{P.CALL_CREATE, P.OBJ_BUFFER},
      P.Call{P.CALL_BEGIN, 0}]))
    row("wg_wait_resolve_between", seq(t, [P.Call{P.CALL_END, 0},
      P.Call{P.CALL_RESOLVE, P.QUERY_COUNT()}, P.Call{P.CALL_FINISH, 1}]))
    row("wg_wait_tail", seq(t, [P.Call{P.CALL_RELEASE, P.OBJ_COMMAND_BUFFER},
      P.Call{P.CALL_CREATE, P.OBJ_BUFFER}, P.Call{P.CALL_CREATE, P.OBJ_COMMAND_ENCODER},
      P.Call{P.CALL_COPY, P.QUERY_BUF_SIZE()}, P.Call{P.CALL_FINISH, 1},
      P.Call{P.CALL_SUBMIT, 1}, P.Call{P.CALL_RELEASE, P.OBJ_COMMAND_BUFFER},
      P.Call{P.CALL_RELEASE, P.OBJ_COMMAND_ENCODER}, P.Call{P.CALL_WAIT, P.SYNC_MAP_ASYNC},
      P.Call{P.CALL_MAPPED_RANGE, P.QUERY_BUF_SIZE()}, P.Call{P.CALL_DESTROY, P.OBJ_BUFFER},
      P.Call{P.CALL_RELEASE, P.OBJ_BUFFER}, P.Call{P.CALL_DESTROY, P.OBJ_BUFFER},
      P.Call{P.CALL_RELEASE, P.OBJ_BUFFER}, P.Call{P.CALL_DESTROY_QUERY_SET, P.OBJ_QUERY_SET},
      P.Call{P.CALL_RELEASE, P.OBJ_QUERY_SET}]))
    row("wg_wait_waits", P.u32_list_eq(waited(t), [P.SYNC_CREATE_PIPELINE, P.SYNC_MAP_ASYNC]))
    urow("wg_wait_destroys", ncalls(P.CALL_DESTROY(), t))
    urow("wg_wait_query_destroys", ncalls(P.CALL_DESTROY_QUERY_SET(), t))
    urow("wg_wait_created_n", ncreated(t))
    +n : P.Pass <- IO.pure(P.Pass, fx_call(F16(), True{}))
    +nt : P.Tr <- IO.pure(P.Tr, P.Pass.tr(n))
    row("wg_wait_no_ts_flag", Bool.not(P.Pass.wait(n)))
    urow("wg_wait_no_ts_created", ncreated(nt))
    urow("wg_wait_no_ts_resolve", ncalls(P.CALL_RESOLVE(), nt))
    urow("wg_wait_no_ts_qdestroy", ncalls(P.CALL_DESTROY_QUERY_SET(), nt))
    urow("wg_wait_no_ts_map", ncalls(P.CALL_MAP_ASYNC(), nt))
    +m : P.Pass <- IO.pure(P.Pass, fx_call(BOTH(), False{}))
    row("wg_wait_false_flag", Bool.not(P.Pass.wait(m)))
    urow("wg_wait_false_query", ncalls(P.CALL_RESOLVE(), P.Pass.tr(m)))

# --- 7: the four pop_error sites, :64, :84, :91, :102 -----------------------
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +p1 : P.Pass <- IO.pure(P.Pass, fx_refuse(1))
    +p2 : P.Pass <- IO.pure(P.Pass, fx_refuse(2))
    +p3 : P.Pass <- IO.pure(P.Pass, fx_refuse(3))
    +p4 : P.Pass <- IO.pure(P.Pass, fx_refuse(4))
    # the counts include the init's two creates (instance, queue), which is why
    # the floor is 3 and not 1.
    urow("wg_refuse_shader_n", ncreated(P.Pass.tr(p1)))
    urow("wg_refuse_layout_n", ncreated(P.Pass.tr(p2)))
    urow("wg_refuse_playout_n", ncreated(P.Pass.tr(p3)))
    urow("wg_refuse_group_n", ncreated(P.Pass.tr(p4)))
    urow("wg_refuse_shader_calls", P.seen(P.Pass.tr(p1)))
    urow("wg_refuse_layout_calls", P.seen(P.Pass.tr(p2)))
    urow("wg_refuse_playout_calls", P.seen(P.Pass.tr(p3)))
    urow("wg_refuse_group_calls", P.seen(P.Pass.tr(p4)))
    urow("wg_refuse_shader_pops", ncalls(P.CALL_POP(), P.Pass.tr(p1)))
    urow("wg_refuse_layout_pops", ncalls(P.CALL_POP(), P.Pass.tr(p2)))
    urow("wg_refuse_playout_pops", ncalls(P.CALL_POP(), P.Pass.tr(p3)))
    urow("wg_refuse_layout_dispatch", ncalls(P.CALL_DISPATCH(), P.Pass.tr(p2)))
    urow("wg_refuse_group_dispatch", ncalls(P.CALL_DISPATCH(), P.Pass.tr(p4)))
    urow("wg_refuse_group_pops", ncalls(P.CALL_POP(), P.Pass.tr(p4)))
    urow("wg_refuse_group_depth", P.Tr.depth(P.Pass.tr(p4)))
    row("wg_refuse_shader_flag", P.Tr.refused(P.Pass.tr(p1)))
    row("wg_refuse_layout_order", seq(P.Pass.tr(p2), [P.Call{P.CALL_PUSH, P.FILTER_VALIDATION},
      P.Call{P.CALL_CREATE, P.OBJ_SHADER_MODULE}, P.Call{P.CALL_POP, P.FILTER_VALIDATION},
      P.Call{P.CALL_PUSH, P.FILTER_VALIDATION}, P.Call{P.CALL_CREATE, P.OBJ_BIND_GROUP_LAYOUT},
      P.Call{P.CALL_POP, P.FILTER_VALIDATION}]))
    row("wg_refuse_group_last_pop", seq(P.Pass.tr(p4), [P.Call{P.CALL_CREATE, P.OBJ_BIND_GROUP},
      P.Call{P.CALL_POP, P.FILTER_VALIDATION}]))

# --- 8: the allocator and the host transfers, :150-163, :206-221 ------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    urow("wg_alloc_size_0", P.alloc.size(0))
    urow("wg_alloc_size_1", P.alloc.size(1))
    urow("wg_alloc_size_4", P.alloc.size(4))
    urow("wg_alloc_size_5", P.alloc.size(5))
    urow("wg_alloc_size_9", P.alloc.size(9))
    row("wg_alloc_usage", U32.is_eq(P.alloc.usage(), 140))
    row("wg_uniform_usage", U32.is_eq(P.dev.uniform_usage(), 72))
    row("wg_readable_usage", U32.is_eq(P.copy.readable_usage(), 9))
    row("wg_query_usage", U32.is_eq(U32.or(P.USAGE_QUERY_RESOLVE(), P.USAGE_COPY_SRC()), 516))
    +a : P.Made <- IO.pure(P.Made, alloc.of(5, P.Tr.of()))
    urow("wg_alloc_buf_size", P.Buf.size(P.Made.buf(a)))
    urow("wg_alloc_created", ncalls(P.CALL_CREATE(), P.Made.tr(a)))
    urow("wg_copyin_len_5", P.copy.write_len(5))
    urow("wg_copyin_len_4", P.copy.write_len(4))
    urow("wg_copyin_len_0", P.copy.write_len(0))
    urow("wg_copyin_pad_5", copy.pad(5))
    urow("wg_copyin_pad_4", copy.pad(4))
    +c : P.Tr <- IO.pure(P.Tr, copy.copyin(5, P.Tr.of()))
    row("wg_copyin_writes_padded", P.u32_list_eq(written(c), [8]))
    +r : P.Made <- IO.pure(P.Made, P.copy.readable(16, P.Tr.of()))
    row("wg_readable_released", P.u32_list_eq(released(P.Made.tr(r)),
      [P.OBJ_COMMAND_BUFFER, P.OBJ_COMMAND_ENCODER]))
    urow("wg_readable_size", P.Buf.size(P.Made.buf(r)))
    +fm : P.Tr <- IO.pure(P.Tr, P.dev.free(3, P.OBJ_BUFFER, P.Tr.of()))
    row("wg_free_mapped", seq(fm, [P.Call{P.CALL_UNMAP, P.OBJ_BUFFER},
      P.Call{P.CALL_DESTROY, P.OBJ_BUFFER}, P.Call{P.CALL_RELEASE, P.OBJ_BUFFER}]))
    +fu : P.Tr <- IO.pure(P.Tr, P.dev.free(1, P.OBJ_BUFFER, P.Tr.of()))
    row("wg_free_unmapped", seq(fu, [P.Call{P.CALL_DESTROY, P.OBJ_BUFFER},
      P.Call{P.CALL_RELEASE, P.OBJ_BUFFER}]))
    urow("wg_free_unmapped_unmaps", ncalls(P.CALL_UNMAP(), fu))
    row("wg_free_bytes_0", P.u32_list_eq(P.dev.uniform_bytes(0), [0, 0, 0, 0]))
    row("wg_free_bytes_1", P.u32_list_eq(P.dev.uniform_bytes(1), [1, 0, 0, 0]))
    row("wg_free_bytes_neg", P.u32_list_eq(P.dev.uniform_bytes(4294967295), [255, 255, 255, 255]))
    # the BYTE rows above were a blind spot AND these four close it. Every one of
    # 0, 1 and 0xFFFFFFFF is a value a one-bit right shift also gets right, so the
    # wrong shift passed all three. Each literal here was read out of CPython --
    # `v.to_bytes(4, "little", signed=v < 0)`, which is :204's expression -- and not
    # computed by the thing under test.
    row("wg_free_bytes_7", P.u32_list_eq(P.dev.uniform_bytes(7), [7, 0, 0, 0]))
    row("wg_free_bytes_256", P.u32_list_eq(P.dev.uniform_bytes(256), [0, 1, 0, 0]))
    row("wg_free_bytes_65536", P.u32_list_eq(P.dev.uniform_bytes(65536), [0, 0, 1, 0]))
    row("wg_free_bytes_big", P.u32_list_eq(P.dev.uniform_bytes(2147483648), [0, 0, 0, 128]))
    +u : P.Made <- IO.pure(P.Made, dev.create_uniform(P.dev.uniform_bytes(1), P.Tr.of()))
    row("wg_free_uniform_created", seq(P.Made.tr(u), [P.Call{P.CALL_CREATE, P.OBJ_BUFFER},
      P.Call{P.CALL_WRITE, 4}]))
    urow("wg_free_uniform_size", P.Buf.size(P.Made.buf(u)))

# --- 9: `synchronous`, :23-50 -------------------------------------------------
def t_sync() -> IO(Unit):
  do IO<Unit>:
    urow("wg_sync_ret_0", sync_ret(0n))
    urow("wg_sync_ret_1", sync_ret(1n))
    urow("wg_sync_ret_2", sync_ret(2n))
    urow("wg_sync_ret_3", sync_ret(3n))
    urow("wg_sync_emsg_1", sync_has_emsg(P.SYNC_MAP_ASYNC()))
    urow("wg_sync_emsg_2", sync_has_emsg(P.SYNC_POP_ERROR_SCOPE()))
    urow("wg_sync_emsg_3", sync_has_emsg(P.SYNC_CREATE_PIPELINE()))
    urow("wg_sync_emsg_4", sync_has_emsg(P.SYNC_REQUEST_ADAPTER()))
    urow("wg_sync_emsg_5", sync_has_emsg(P.SYNC_REQUEST_DEVICE()))
    urow("wg_sync_emsg_6", sync_has_emsg(P.SYNC_WORK_DONE()))
    urow("wg_sync_payload_noemsg_2", U32.from_nat(sync_payload(2n, P.SYNC_NO_EMSG())))
    urow("wg_sync_payload_noemsg_0", U32.from_nat(sync_payload(0n, P.SYNC_NO_EMSG())))
    urow("wg_sync_payload_emsg_2", U32.from_nat(sync_payload(2n, P.SYNC_HAS_EMSG())))
    row("wg_sync_tail", String.eq(P.sync_tail("WGPUBufferMapAsyncStatus_InstanceDropped"),
      "InstanceDropped"))
    # no '_' at all, so the whole string is the "member" -- which is the shape of
    # the one status name Python does not have, and the row says so.
    row("wg_sync_tail_missing", String.eq(P.sync_tail("None"), "None"))
    urow("wg_sync_names2", U32.from_nat(List.length(&2, String, H.dedup_str(sync_name.six2()))))
    urow("wg_sync_names3", U32.from_nat(List.length(&2, String, H.dedup_str(sync_name.six3()))))
    srow("wg_sync_name_mapasync3", P.sync_name.of(P.SYNC_MAP_ASYNC(), 3))
    srow("wg_sync_name_pop3", P.sync_name.of(P.SYNC_POP_ERROR_SCOPE(), 3))
    srow("wg_sync_name_pipeline3", P.sync_name.of(P.SYNC_CREATE_PIPELINE(), 3))
    srow("wg_sync_name_adapter3", P.sync_name.of(P.SYNC_REQUEST_ADAPTER(), 3))
    srow("wg_sync_name_device3", P.sync_name.of(P.SYNC_REQUEST_DEVICE(), 3))
    srow("wg_sync_name_workdone3", P.sync_name.of(P.SYNC_WORK_DONE(), 3))
    srow("wg_sync_name_success", P.sync_name.of(P.SYNC_REQUEST_ADAPTER(), 1))
    srow("wg_sync_err_adapter", sync_error(P.SYNC_REQUEST_ADAPTER(), 3, "no adapter"))
    srow("wg_sync_err_empty", sync_error(P.SYNC_WORK_DONE(), 3, ""))
    srow("wg_sync_err_ok", sync_error(P.SYNC_REQUEST_ADAPTER(), 1, "unreachable"))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_backend()
    b : Unit <- t_features()
    +c : Unit <- t_init()
    d : Unit <- t_layout()
    e : Unit <- t_call()
    f : Unit <- t_wait()
    g : Unit <- t_refuse()
    h : Unit <- t_alloc()
    i : Unit <- t_sync()
    IO.print("wg-done=1")

# ===========================================================================
# the mutation table. Every number below is the harness's output, not an
# estimate. The harness applies one edit to a scratch copy, runs the interpreted
# lane, and diffs the row names; the useful column is "rows moved", because a
# mutation that moves nothing measures what this gate does not see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `bgl.entry.put`: `U32.is_ge(i, nbufs)` -> `U32.is_gt(i, nbufs)` | 2 | :78's `'Uniform' if i >= len(bufs)`, off by one at the boundary. Two rows and not five because `wg_bgl_none` has no boundary and `wg_bgl_1_0` does not reach `i == nbufs`. |
# | M2 | `bgl.of`: drop the binding-0 entry | 8 | the infinity entry itself. Every layout row AND `wg_bgl_nentries` AND `wg_call_entry_count` move, because the derivation is live in the port and not only in the gate. |
# | M3 | `pass.release`: swap the first two releases | 1 | :132-133's `bindLayout` before `pipelineLayout`. `wg_call_released` only -- the sequence rows do not mention the releases. |
# | M4 | `copy.readable`: swap its two releases | 2 | :216-217's `cmd_buf` before `encoder` -- the reverse of creation, against :132-138's creation order. `wg_wait_tail` moves too, so the two orders cannot be confused for one another. |
# | M5 | `pass.set`: `SetBindGroup` before `SetPipeline` | 1 | :121 before :122. `wg_call_order` and nothing ELSE -- which is why `P.Tr.has` has to be a real subsequence test for the five order rows to mean anything. |
# | M6 | `pass.geometry`: swap the dispatch's x and y slots | 3 | that :123 dispatches `global_size`, not `local_size`. `wg_call_gx`, `wg_call_dispatch_x` and (incidentally) `wg_call_order`. |
# | M7 | `copy.copyin`: write the unpadded length | 1 | that `write_buffer` receives `round_up(nbytes, 4)`. Only `wg_copyin_writes_padded` sees it: the `copy.write_len` rows pin the function, not its caller. |
# | M8 | `dev.free.at`: always unmap | 1 | :196's map-state guard. One row, and it is the count row -- the `wg_free_unmapped` sequence still holds, because a spurious unmap does not disturb unmap, destroy, release. |
# | M9 | `prog.wants_wait`: drop the TimestampQuery conjunct | 7 | :71's `wait and ... in self.dev.features`. |
# | M10 | `keeps_feature`: drop the ShaderF16 conjunct | 9 | :173-174's two-element probe list. |
# | M11 | `dev.init`: request the device before reading the limits | 1 | :180 before :184. |
# | M12 | `sync_payload`: always add the trailing element | 1 | :34's `[] if has_emsg else [None]` -- and only the True side moves, because `wg_sync_payload_emsg_2` is the only row that reads it. `wg_sync_payload_noemsg_*` are unaffected, which is the point: the two sides are separate claims. |
# | M13 | `alloc.size`: no 4-byte alignment | 4 | :152's `round_up(size, 4)`. |
# | M14 | `pass.uniforms.put`: a BUFFER slot takes 4 | 1 | :96's `size=wgpuBufferGetSize(buf)` against a uniform's own 4. |
# | M15 | `backend_of.put`: every name matches | 8 | the reverse lookup at all -- an implementation that cannot say "no name matched". |
# | M16 | `P.Tr.emit.go`: drop the `raise` guard | 10 | the raise. Every refusal row at once, and nothing else. |
# | M17 | `pass.finish`: submit before finish | 2 | :128 before :129 -- and `wg_has_rejects_reverse` as well, because the mutation makes the reversed pair actually present. That row was written to pin `P.Tr.has` and turned out to double as an order row. |
# | M18 | `pass.query`: the `if wait:` arms are swapped | 5 | :112's `if wait:`. |
# | M19 | `dev.uniform_bytes.go`: every byte is 255 | 2 | :204's little-endian byte order, for the two fixtures whose low byte is not already 255. `wg_free_bytes_neg` does not move, because its expected bytes are 255 -- that row is blind to the byte order and says so. |
# | M20 | `features_keep.put`: keep every feature | 3 | that the filter drops anything at all. It moves only the three rows with a non-probe feature in the input: with nothing to drop, a filter that drops nothing is an equivalence. |
# | M21 | a comment-only edit | 0 -- the control | a table with no row that cannot move is a table of coincidences. |
# | M22 | `sync_name.of.err`: the two and three arms are swapped | 8 | that each wrapped call carries its own status enum -- every name row, plus both distinct-counts. |
# | M23 | (not run) `P.Tr.has` with the fuel set to the pattern length | 0 -- a real blind spot, found AND fixed | see the matcher below. |
#
# M23 is the honest half of this table. Before it was fixed, `wg_call_order`,
# `wg_init_order`, `wg_wait_resolve_between`, `wg_refuse_layout_order`,
# `wg_refuse_group_last_pop`, `wg_free_mapped`, `wg_free_unmapped` and
# `wg_readable_released` were eight rows that could not fail: the matcher's fuel
# was the pattern's length, so it returned `True{}` after patlen trace entries
# without ever comparing `at`, and a reversed pattern matched. M5 and M11 are the
# two mutations that exposed it -- they moved nothing, which is the measurement.
# `wg_has_rejects_reverse` and `wg_has_rejects_absent` now pin the matcher
# itself, and every mutation above that touches an order moves its row.
#
# what this gate still does not see, and it is a short list:
#
#   1. The descriptors. `P.Tr` records the call and, for four calls, one argument.
#     Every usage bitmask, entry count, offset and buffer size is a pure function
#     with its own row -- `wg_alloc_usage`, `wg_uniform_usage`, `wg_readable_usage`,
#     `wg_query_usage`, `wg_bgl_nentries`, `wg_call_sizes` -- but nothing checks
#     that the right one is passed to the right call. Mutating
#     `copy.readable` to create its staging buffer with `P.alloc.usage()` instead of
#     `P.copy.readable_usage()` moves nothing, because both are one `call_create`
#     with the same object kind.
#   2. the descriptor-field correlations. `comp_pass_desc.timestampWrites` (:116),
#     `bindGroupLayouts=(...)` (:87), `entryCount` (:82) and `WGPUComputeState(
#     module, entryPoint)` (:106) are all fields of objects the trace does not
#     carry. In particular nothing checks that `pass.pipeline`'s `entryPoint` is
#     the entry point `P.Pass.of` was given: the only reader would be the ffi seam,
#     so the reader `P.Pass.entry` was deleted rather than left as a def nothing
#     called. The entry point is still in the `P.Pass` record, and the gate has no
#     row that reads it -- that is the gap, stated rather than papered over.
#   3. the u64 AND f32 arithmetic. Walls 2 and 3. `wg_free_bytes_*` covers the int
#     path; the timestamp delta and `struct.pack('<f', val)` are not computed at
#     all, by construction.
#   4. the limits table (:181). The port asks the adapter before it requests the
#     device and then does nothing with the answer, which is faithful and is also
#     the whole of the gap.
#   5. `pop_error`'s message. `P.Tr.pop` keeps the question and not the string, so a
#     port that picked payload[0] instead of payload[1] would be invisible here.
#     `wg_sync_payload_*` pins the arithmetic that makes [1] the message; nothing
#     pins the index.
#   6. the wgsl text. :57-59 hands `obj.lib` to the shader module. The port takes
#     `entry` from `TinyELF.name` and nothing else, because the wgsl source is
#     wgsl.bend's artefact. That half of the interface is checked on neither side.
#   7. the constants that are the port's own tags, measured, not guessed. This is
#     the `device.bend` `sig=0 4 5` shape at full size and it had ~45 rows in it.
#     Splitting the constants by WHERE they come from is what made it fixable,
#     and the split is a fact about `autogen/webgpu.py`, not a preference:
#
#       a. real wgpu values, reachable by a wrong value reaching a wrong call.
#          Nine of them -- the `WGPUBufferUsage_*` bit flags, the two
#          `WGPUFeatureName` ids, and the three `WGPUBufferMapState` members --
#          and all nine now have a literal on one side of the row that uses them:
#          `wg_alloc_usage` 140, `wg_uniform_usage` 72, `wg_readable_usage` 9,
#          `wg_query_usage` 516, `wg_feat_order_forward` [3, 8],
#          `wg_feat_only_ts` [3], `wg_feat_only_f16` [8], and `wg_free_mapped` /
#          `wg_free_unmapped` which now pass 3 and 1 to `dev.free` instead of
#          naming `map_mapped` / `map_unmapped`. Every literal was read out of
#          `tinygrad/runtime/autogen/webgpu.py` by importing that module and
#          reading its enum dicts; none was typed. Before this, `wg_feat_only_ts`
#          read `P.u32_list_eq(P.features_of(ts()), ts())` -- the fixture and the
#          expectation were the same def, so no edit to the feature id could move
#          the row.
#
#       b. port-invented tags that never reach wgpu, so a wrong value is not a
#          wrong call. `obj_*` (there is no `WGPUObjectType` in
#          `autogen/webgpu.py`; these are the trace's own object-kind ids) and
#          `call_*` (the trace's own opcodes). Their rows are still worth having
#          -- `P.u32_list_eq(created(t), [obj_instance, obj_queue])` checks which
#          objects are created and in what order, and no fixture can separate that
#          claim from the port's own tag numbering -- but they are recorded here
#          as value-blind so nobody reads them as checking the number.
#          not pinned, deliberately: `obj_instance`(0) `obj_adapter`(1)
#          `obj_queue`(3) `obj_shader_module`(4) `obj_bind_group_layout`(5)
#          `obj_pipeline_layout`(6) `obj_bind_group`(7) `obj_compute_pipeline`(8)
#          `obj_command_encoder`(9) `obj_compute_pass`(10) `obj_command_buffer`(11)
#          `obj_query_set`(12) `obj_buffer`(13), and all 23 `call_*`.
#
#       c. `sync_*` 1..6 -- the port's INDEX into the six `synchronous`-wrapped
#          calls, not a wgpu value: all six real calls pass the same
#          `WGPUCallbackMode_WaitAnyOnly` (=1). So the `wg_sync_name_*` rows are
#          blind to these numbers and check the six status-name strings instead,
#          which are literals in this file. not pinned, deliberately.
# ===========================================================================
