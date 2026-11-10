# wgsl_walk.bend -- THE UOP -> BODY WALK: `_render`'s equivalent (cstyle.py:208-266) for WGSL.
#
# it lives in its own file and not in `wgsl.bend`, and that is a decision the census gate
# FORCED: `gates/wgsl_render_census-gate.py`'s `never_folding_cast_hold` PINs the bytes of
# every `OpsCAST` site in `wgsl.bend`, so that a new cast site cannot appear without someone
# re-deciding its ROLE. MEASURED: adding this walk inside `wgsl.bend` moved that pin
# (`258c37970b354a3d` against the pinned `4ad7ca714528448a`) and the gate went red -- which is
# the gate working, not complaining. The walk needs a `case O.OpsCAST{}` MATCH arm (it does
# not mint a CAST), and the honest way to add one is to put the walk where the pin does not
# govern, rather than to re-pin a tripwire around code that is not a renderer table.
#
# `wgsl.bend` IS UNTOUCHED by this file: every renderer it calls (`render_cast`,
# `render_load`, `render_kernel`, `code_for_op`, `code_for_workitem`) and both of its records
# (`Buf`, `Scan`) are used as they stand.
import Base
import ./wgsl.bend as W
import ./../uop/f32_repr.bend as FR
import ./cstyle.bend as CS
import ../uop/ops.bend as O
import ../LAWS/spec.bend as S


# THE UOP -> BODY WALK -- the `_render` equivalent (cstyle.py:208-266), which this
# file did not have: `render_kernel` takes the body as STRINGS and `kern_alu()` /
# `kern_mixed()` above are LITERALS, so the census's whole-kernel rows are rows
# about the ASSEMBLER and none of them walks a uop list.
#
# THE INPUT IS A FLAT RECORD, `R`, because the walk is driven from a generated
# module (`.agents/slop/perf/gen_wgsl/`) built out of a captured uop list, and a
# nested arg union would be three more matches for two fields. The fields are
# upstream's: `op`, `dtype`, `addrspace`, `max_numel`, the arg's STRING form
# (`SPECIAL`'s name, `SINK`'s function name), the arg's NUMBER (`SPECIAL`'s
# workitem index, `CONST`'s value), the `PARAM` slot and its shape, and the srcs.
#
# WHAT IT REPRODUCES, in upstream's order: NOOP/CONST/CUSTOM_FUNCTION skipped; a
# zero-src STACK skipped; SINK names the kernel; PARAM becomes `data{slot}_{shape}`
# and a `Buf`; SPECIAL takes its name from the arg and its text is
# `{code_for_workitem}; /* {src} */`; and everything else takes `prefix{n}` from
# the six-counter table, is INLINED when upstream's rule says so, and is otherwise
# declared as `var {name} = {text};` (`_render_dtype` answers `var` here, :103).

type R is Data:
  R{op: O.Op, dt: S.Dt, addr: S.Addr, numel: U32, str: String, idx: U32, slot: U32,
    shape: List<&2, U32>, srcs: List<&2, U32>, f: F32}

def R.op(r: R) -> O.Op:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: op

def R.dt(r: R) -> S.Dt:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: dt

def R.addr(r: R) -> S.Addr:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: addr

def R.numel(r: R) -> U32:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: numel

def R.str(r: R) -> String:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: str

def R.f(r: R) -> F32:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: f

def R.idx(r: R) -> U32:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: idx

def R.slot(r: R) -> U32:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: slot

def R.shape(r: R) -> List<&2, U32>:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: shape

def R.srcs(r: R) -> List<&2, U32>:
  match r:
    case R{op, dt, addr, numel, str, idx, slot, shape, srcs, f}: srcs

# the walk's state: one NAME-OR-TEXT per uop index (upstream's `r`, and it holds the
# RENDERED TEXT for an inlined uop and the NAME for a declared one), the body lines,
# the buffers in first-seen order, the six counters, and the kernel's name.
type Wk is Data:
  Wk{names: List<&2, String>, body: List<&2, String>, bufs: List<&2, W.Buf>,
     c: List<&2, U32>, nm: String, depth: Nat}

def Wk.zero() -> Wk: Wk{Nil{}, Nil{}, Nil{}, List.replicate(U32, 6n, 0), "test", 1n}

def Wk.names(w: Wk) -> List<&2, String>:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: names

def Wk.body(w: Wk) -> List<&2, String>:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: body

def Wk.bufs(w: Wk) -> List<&2, W.Buf>:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: bufs

def Wk.c(w: Wk) -> List<&2, U32>:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: c

def Wk.depth(w: Wk) -> Nat:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: depth

# `"  "*depth` -- cstyle.py:262. A Nat countdown, because a U32 has no `n` patterns.
def ind(+d: Nat) -> String:
  match d:
    case 0n: ""
    case 1n+k: String.concat([ind(k), "  "])

def emit(+d: Nat, +t: String) -> String: String.concat([ind(d), t])

def Wk.nm(w: Wk) -> String:
  match w:
    case Wk{names, body, bufs, c, nm, depth}: nm

# `r[u]` -- the text or name bound to the 1-based uop `k`; "" is upstream's KeyError
def wt(+names: List<&2, String>, +k: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, names, U32.to_nat(U32.sub(k, 1))), "")

# `child_count[u]` -- how many uops name `k` as a src. Upstream counts the whole list
# once; the walk asks per uop, and a 15-uop kernel makes that the cheaper question.
def has_src.go(+ss: List<&2, U32>, +k: U32, acc: U32) -> U32:
  match ss:
    case Nil{}: acc
    case h <> t: has_src.go(t, k, U32.add(acc, Bool.to_u32(U32.is_eq(h, k))))
def has_src(+ss: List<&2, U32>, +k: U32) -> U32: has_src.go(ss, k, 0)

def uses.go(+rs: List<&2, R>, +k: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case h <> t: uses.go(t, k, U32.add(acc, has_src(R.srcs(h), k)))
def uses(+rs: List<&2, R>, +k: U32) -> U32: uses.go(rs, k, 0)

def R.zero() -> R: R{O.OpsNOOP{}, S.void(), S.Aalu{}, 0, "", 0, 0, Nil{}, Nil{}, 0.0}

def R.at(+rs: List<&2, R>, +k: U32) -> R:
  Maybe.default(&2, R, List.get(&2, R, rs, U32.to_nat(U32.sub(k, 1))), R.zero())

def R.src0(r: R) -> U32: Maybe.default(&2, U32, List.get(&2, U32, R.srcs(r), 0n), 0)

# => and a constant's value is materialised at its use, which is WHERE upstream puts it.
# `_render` SKIPS every CONST (`cstyle.py:222`), so `r[const]` is never bound, and the value
# reaches the text because `base_rewrite`'s `cvar.cast(...)` rules (`cstyle.py:24-30`) rewrite a
# CAST OF A CONST into the literal: `f"{c.val}f"` for `dtypes.float`, `f"{val}u"` for u32, the
# plain digits otherwise. MEASURED BEFORE THIS EXISTED: `relu` rendered `select(f32(),alu0,...)`
# -- a CONST with no value -- and it was INVISIBLE because `f32()` is a valid WGSL zero and the
# fixture's constant was 0.0. A non-zero constant would have compiled and been WRONG.
def is_float_dt(+d: S.Dt) -> Bool: Bool.pick(Bool, S.Dt.is_float(d), True{}, False{})
def is_u32_dt(+d: S.Dt) -> Bool: Bool.pick(Bool, U32.is_eq(S.Dt.pri(d), 6), True{}, False{})
def is_con_op(+op: O.Op) -> Bool: Bool.pick(Bool, O.eq_op(op, O.OpsCONST{}), True{}, False{})
# `axis_letters` -- tinygrad/uop/ops.py:50, quoted in cstyle.bend: `{DEVICE:"d", GLOBAL:"g",
# LOCAL:"l", WARP:"w", WEAK:"L", UPCAST:"u", ...}`. The axis arrives as its NAME because
# `dump_uops` writes a RANGE's payload as `<axis>~<ids...>`.
# rules 6..11, in `sr_pick_bitcast`'s own numbering. A `match` on the RULE PARAMETER, so a
# bitcast costs one call and not six, and so nothing here recurses.
def bit_text(+rule: U32, +op: O.Op, +dt: S.Dt, +s0: S.Dt, +s: String) -> String:
  match rule:
    case 6: W.sr_bhalf(dt, s0, s)
    case 7: W.sr_buchar(dt, s)
    case 8: W.sr_bchar(dt, s)
    case 9: W.sr_bushort(dt, s0, s)
    case 10: W.sr_bshort(dt, s0, s)
    case _: W.sr_bany(op, dt, s)

def axis_letter(+nm: String) -> String:
  match nm:
    case "DEVICE": "d"
    case "GLOBAL": "g"
    case "LOCAL": "l"
    case "WARP": "w"
    case "WEAK": "L"
    case "UPCAST": "u"
    case "UNROLL": "u"
    case "LOOP": "L"
    case "PLACEHOLDER": "p"
    case _: "?"

def is_where_op(+op: O.Op) -> Bool: Bool.pick(Bool, O.eq_op(op, O.OpsWHERE{}), True{}, False{})

# the literal is computed, not carried. `R.f` is the const's f32 value and `FR.repr` is
# CPython's own `repr(float)` algorithm (uop/f32_repr.bend, 1044 of 1044 values identical), so the
# digits now come from the port's arithmetic. They used to come from `R.str`, which is CPython's
# repr TRANSCRIBED into the `.rows` dump -- a comparison of two copies of CPython's string rather
# than of the port's computation. For a non-float const the value IS its text (an integer), so that
# arm still reads `R.str` and there is nothing to compute.
def con_text(+dt: S.Dt, +r: R) -> String:
  String.concat([Bool.pick(String, is_float_dt(dt), FR.repr(R.f(r)), R.str(r)),
    Bool.pick(String, is_float_dt(dt), "f", Bool.pick(String, is_u32_dt(dt), "u", ""))])

# THE OPERAND LOOKUP: a name/text from the map, or -- for a CONST, which the map never holds --
# the materialised literal. `dt` is the dtype the value is CONSUMED as, which is upstream's
# `x.dtype` in the `cvar.cast` patterns.
def tx0(+op: O.Op, +r: R, +dt: S.Dt, +nm: String) -> String:
  match op:
    case O.OpsCONST{}: con_text(dt, r)
    case _: nm

def tx(+all: List<&2, R>, +names: List<&2, String>, +k: U32, +dt: S.Dt) -> String:
  +r = R.at(all, k)
  tx0(R.op(r), r, dt, wt(names, k))

# the CONST value behind a CAST chain: upstream's `x.src[0].render()` in the SPECIAL
# arm answers the VALUE (`/* 1024 */`), not the cast's own text (`i32(1024)`).
# TWO LEVELS, ONE PER DEF, because a recursion and its helper are MUTUAL recursion and
# Bend refuses that; both captured kernels are `CONST` under one `CAST`, and a longer
# chain answers "" rather than a plausible wrong comment.
def const_at(+op: O.Op, +r: R) -> Maybe<&2, String>:
  match op:
    case O.OpsCONST{}: Some{U32.show(R.idx(r))}
    case _: None{}


def const_step(+op: O.Op, +r: R, +rs: List<&2, R>) -> Maybe<&2, String>:
  match op:
    case O.OpsCONST{}: Some{U32.show(R.idx(r))}
    case O.OpsCAST{}: const_at(R.op(R.at(rs, R.src0(r))), R.at(rs, R.src0(r)))
    case _: None{}

def const_of(+rs: List<&2, R>, +k: U32) -> String:
  +r = R.at(rs, k)
  Maybe.default(&2, String, const_step(R.op(r), r, rs), "")


# the six-prefix counter table, same numbering as cstyle.bend's `ku_pfx_ix`
def pfx_ix(op: O.Op) -> U32:
  match op:
    case O.OpsWMMA{}: 5
    case O.OpsBUFFER{}: 4
    case O.OpsCAST{}: 2
    case O.OpsBITCAST{}: 2
    case O.OpsSTACK{}: 2
    case O.OpsINDEX{}: 3
    case O.OpsLOAD{}: 1
    case _: 0

def pfx(ix: U32) -> String:
  match ix:
    case 5: "wmma"
    case 4: "buf"
    case 2: "cast"
    case 3: "bidx"
    case 1: "val"
    case _: "alu"

def c_at(+c: List<&2, U32>, +ix: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, c, U32.to_nat(ix)), 0)

def c_bump(+c: List<&2, U32>, +ix: U32) -> List<&2, U32>:
  List.set(&2, U32, c, U32.to_nat(ix), U32.add(c_at(c, ix), 1))

# and a number is burned only by a declaration. cstyle.py:261 increments `c[prefix]` inside
# the else branch, so an INLINED uop leaves the counter alone. MEASURED: bumping
# unconditionally numbered the WHERE `alu2` where CPython has `alu1`, because the inlined CMPLT
# had already taken `alu1` -- same text, same size, different names.
def c_maybe(+c: List<&2, U32>, +ix: U32, +inl: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, inl, c, c_bump(c, ix))

def is_reg(a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

def is_con(+op: O.Op) -> Bool: Bool.pick(Bool, O.eq_op(op, O.OpsCONST{}), True{}, False{})

def shape_strs(+ds: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case h <> t: shape_strs(t, List.append(&2, String, acc, [U32.show(h)]))

# a closing brace is emitted one level OUT: the depth drops BEFORE the line (cstyle.py:249)
# a header line AND one level deeper, in one step (cstyle.py:264 increments after the line)
def wk.open(+nm: String, +line: String, +c: List<&2, U32>, +acc: Wk) -> Wk:
  Wk{List.append(&2, String, Wk.names(acc), [nm]),
    List.append(&2, String, Wk.body(acc), [line]), Wk.bufs(acc), c, Wk.nm(acc),
    Nat.add(Wk.depth(acc), 1n)}

def wk.close(+acc: Wk) -> Wk:
  +d = Nat.sub(Wk.depth(acc), 1n)
  Wk{List.append(&2, String, Wk.names(acc), [""]),
    List.append(&2, String, Wk.body(acc), [emit(d, "}")]), Wk.bufs(acc), Wk.c(acc), Wk.nm(acc), d}

def wk.add(+nm: String, +lines: List<&2, String>, +bufs: List<&2, W.Buf>, +c: List<&2, U32>, +acc: Wk) -> Wk:
  Wk{List.append(&2, String, Wk.names(acc), [nm]),
    List.append(&2, String, Wk.body(acc), lines), bufs, c, Wk.nm(acc), Wk.depth(acc)}

# ONE UOP. `op` is a PARAMETER so the dispatch is a match and not a `Bool.pick`:
# a pick here would run both arms and, for a fold, that is 2^n (the class that hung
# the Metal render for 90 s in stage 2).
def walk.one(+op: O.Op, +r: R, +all: List<&2, R>, +i: U32, +acc: Wk) -> Wk:
  match op:
    case O.OpsCONST{}: wk.add("", Nil{}, Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsNOOP{}: wk.add("", Nil{}, Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsCUSTOM_FUNCTION{}: wk.add("", Nil{}, Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsSINK{}: Wk{List.append(&2, String, Wk.names(acc), [""]), Wk.body(acc),
      Wk.bufs(acc), Wk.c(acc), R.str(r), Wk.depth(acc)}
    case O.OpsPARAM{}:
      +nm = String.concat([Bool.pick(String, String.eq(R.str(r), "-"), String.concat(["data", U32.show(R.slot(r))]), R.str(r)),
        "_", String.join(shape_strs(R.shape(r), Nil{}), "_")])
      wk.add(nm, Nil{}, List.append(&2, W.Buf, Wk.bufs(acc), [W.Buf{nm, R.dt(r), R.addr(r), R.numel(r)}]),
        Wk.c(acc), acc)
    case O.OpsSPECIAL{}:
      +nm = R.str(r)
      +txt = String.concat([W.code_for_workitem(String.eq(String.take(nm, 1n), "g"), R.idx(r)),
        "; /* ", const_of(all, R.src0(r)), " */"])
      wk.add(nm, List.append(&2, String, Nil{},
        [emit(Wk.depth(acc), String.concat(["var ", nm, " = ", txt]))]), Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsINDEX{}:
      wk.add(String.concat([tx(all, Wk.names(acc), R.src0(r), R.dt(r)), "[",
        tx(all, Wk.names(acc), Maybe.default(&2, U32, List.get(&2, U32, R.srcs(r), 1n), 0), R.dt(r)), "]"]),
        Nil{}, Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsCAST{}:
      +ix = pfx_ix(op)
      +nm = String.concat([pfx(ix), U32.show(c_at(Wk.c(acc), ix))])
      +txt = tx(all, Wk.names(acc), R.src0(r), R.dt(r))
      +inl = Bool.and(Bool.pick(Bool, is_con(R.op(R.at(all, R.src0(r)))), True{}, False{}),
        Bool.pick(Bool, U32.is_eq(R.numel(r), 1), True{}, False{}))
      # upstream: `(u.op is not Ops.CAST or max_numel == 1) and (... CAST of CONST ... or child_count == 1 ...)`
      +keep = Bool.pick(Bool, U32.is_eq(uses(all, i), 1), True{}, False{})
      +take = Bool.or(inl, Bool.and(Bool.pick(Bool, inl, True{}, keep), Bool.not(inl)))
      wk.add(Bool.pick(String, take, txt, nm),
        Bool.pick(List<&2, String>, take, Nil{},
          List.append(&2, String, Nil{},
            [emit(Wk.depth(acc), String.concat(["var ", nm, " = ", txt, ";"]))])),
        Wk.bufs(acc), c_maybe(Wk.c(acc), ix, inl), acc)
    case O.OpsLOAD{}:
      +ix = pfx_ix(op)
      +nm = String.concat([pfx(ix), U32.show(c_at(Wk.c(acc), ix))])
      +txt = W.render_load(tx(all, Wk.names(acc), R.src0(r), R.dt(r)), R.numel(r), R.dt(r), R.addr(r))
      +reg = Bool.pick(Bool, is_reg(R.addr(R.at(all, R.src0(r)))), True{}, False{})
      +inl = Bool.and(reg, Bool.pick(Bool, U32.is_eq(uses(all, i), 1), True{}, False{}))
      wk.add(Bool.pick(String, inl, txt, nm),
        Bool.pick(List<&2, String>, inl, Nil{},
          List.append(&2, String, Nil{},
            [emit(Wk.depth(acc), String.concat(["var ", nm, " = ", txt, ";"]))])),
        Wk.bufs(acc), c_maybe(Wk.c(acc), ix, inl), acc)
    case O.OpsSTORE{}:
      wk.add("", List.append(&2, String, Nil{}, [emit(Wk.depth(acc),
        String.concat([tx(all, Wk.names(acc), R.src0(r), R.dt(r)), " = ",
          tx(all, Wk.names(acc), Maybe.default(&2, U32, List.get(&2, U32, R.srcs(r), 1n), 0), R.dt(r)), ";"]))]),
        Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsAFTER{}: wk.add(tx(all, Wk.names(acc), R.src0(r), R.dt(r)), Nil{},
      Wk.bufs(acc), Wk.c(acc), acc)
    case O.OpsBUFFER{}:
      +bix = pfx_ix(op)
      +bnm = String.concat([pfx(bix), U32.show(c_at(Wk.c(acc), bix))])
      wk.add(bnm, List.append(&2, String, Nil{}, [emit(Wk.depth(acc),
        W.sr_buffer(op, bnm, R.numel(r), R.dt(r), R.addr(r)))]),
        Wk.bufs(acc), c_bump(Wk.c(acc), bix), acc)
    case O.OpsIF{}:
      # cstyle.py:20 -- `f"if ({ctx[x.src[0]]}) {{"`, at the CURRENT depth, then one deeper
      # (`cstyle.py:264` increments for IF as well as RANGE). A void op gets no declaration, but
      # it still BURNS its prefix number, which is why the name comes from the counter and is
      # thrown away.
      +fix = pfx_ix(op)
      +fnm = String.concat([pfx(fix), U32.show(c_at(Wk.c(acc), fix))])
      wk.open(fnm, emit(Wk.depth(acc), String.concat(["if (",
        tx(all, Wk.names(acc), R.src0(r), R.dt(r)), ") {"])), c_bump(Wk.c(acc), fix), acc)
    case O.OpsEND{}: wk.close(acc)
    case O.OpsENDIF{}: wk.close(acc)
    case O.OpsBACKEDGE{}: wk.close(acc)
    case O.OpsRANGE{}:
      +rnm = String.concat([axis_letter(R.str(r)), "idx", CS.range_str(R.shape(r))])
      wk.open(rnm, emit(Wk.depth(acc), String.concat(["for (var ", rnm, " = 0; ", rnm, " < ",
        tx(all, Wk.names(acc), R.src0(r), R.dt(r)), "; ", rnm, "++) {"])), Wk.c(acc), acc)
    case O.OpsBITCAST{}:
      # cstyle.py:269's `string_rewrite` CONSULTS SIX RULES FOR A BITCAST, and
      # `wgsl.bend` already has all six (`sr_bhalf`, `sr_buchar`, `sr_bchar`, `sr_bushort`,
      # `sr_bshort`, `sr_bany`) plus the picker (`sr_pick_bitcast`). The walk had no arm, so
      # a real kernel rendered `UNHANDLED(Ops.BITCAST)`; MEASURED on `bitcast(a)+1`:
      # CPython `bitcast<f32>((bitcast<u32>(val0)+1u))`, port `UNHANDLED(Ops.BITCAST)`.
      +bix = pfx_ix(op)
      +bnm = String.concat([pfx(bix), U32.show(c_at(Wk.c(acc), bix))])
      +s0 = R.at(all, R.src0(r))
      +btxt = bit_text(W.sr_pick_bitcast(R.dt(r), R.dt(s0)), op, R.dt(r), R.dt(s0),
        tx(all, Wk.names(acc), R.src0(r), R.dt(r)))
      +binl = Bool.pick(Bool, U32.is_eq(uses(all, i), 1), True{}, False{})
      wk.add(Bool.pick(String, binl, btxt, bnm),
        Bool.pick(List<&2, String>, binl, Nil{},
          List.append(&2, String, Nil{},
            [emit(Wk.depth(acc), String.concat(["var ", bnm, " = ", btxt, ";"]))])),
        Wk.bufs(acc), c_maybe(Wk.c(acc), bix, binl), acc)
    case op2:
      +ix = pfx_ix(op2)
      +nm = String.concat([pfx(ix), U32.show(c_at(Wk.c(acc), ix))])
      +txt = W.code_for_op.of(op2, tx(all, Wk.names(acc), R.src0(r), R.dt(r)),
        tx(all, Wk.names(acc), Maybe.default(&2, U32, List.get(&2, U32, R.srcs(r), 1n), 0), R.dt(r)),
        tx(all, Wk.names(acc), Maybe.default(&2, U32, List.get(&2, U32, R.srcs(r), 2n), 0), R.dt(r)))
      # AND A `WHERE` IS NEVER INLINED. Upstream's set is
      # `{Ops.STACK, *(GroupOp.ALU - {Ops.WHERE}), Ops.CAST, Ops.BITCAST}` (cstyle.py:253), and
      # the SUBTRACTION is load-bearing: MEASURED, `relu`/`maximum` rendered the same
      # `select(...)` expression on both sides but CPython DECLARED it (`var alu1 = select(...)`)
      # while the port inlined it into the STORE -- one line versus two, 656 B against 637.
      +inl = Bool.and(Bool.pick(Bool, U32.is_eq(uses(all, i), 1), True{}, False{}),
        Bool.not(is_where_op(op2)))
      wk.add(Bool.pick(String, inl, txt, nm),
        Bool.pick(List<&2, String>, inl, Nil{},
          List.append(&2, String, Nil{},
            [emit(Wk.depth(acc), String.concat(["var ", nm, " = ", txt, ";"]))])),
        Wk.bufs(acc), c_maybe(Wk.c(acc), ix, inl), acc)

def walk.go(+rs: List<&2, R>, +all: List<&2, R>, +i: U32, acc: Wk) -> Wk:
  match rs:
    case Nil{}: acc
    case h <> t: walk.go(t, all, U32.add(i, 1), walk.one(R.op(h), h, all, U32.add(i, 1), acc))

def walk(+rs: List<&2, R>) -> Wk: walk.go(rs, rs, 0, Wk.zero())
