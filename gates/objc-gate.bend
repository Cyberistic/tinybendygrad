# gates/objc-gate.bend -- the gate driver for `tinybendygrad/runtime/support/objc.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/support/objc.bend as P

import ./../tinybendygrad/runtime/support/objc.bend as Q
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]"])

def rd(+nm: String, +got: String) -> String: r(nm, got, got)

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def ssh(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ssh(t, x <> acc)

def ujoin(xs: List<&2, U32>) -> String: String.join(ush(xs, Nil{}), ",")
def sjoin(xs: List<&2, String>) -> String: String.join(ssh(xs, Nil{}), ",")

def orow(nm: String, got: Bool) -> IO(Unit):
  +s = Bool.show(got)
  IO.print(rd(nm, s))

def nrow(nm: String, got: U32) -> IO(Unit):
  +s = U32.show(got)
  IO.print(rd(nm, s))

def lrow(nm: String, got: List<&2, U32>) -> IO(Unit):
  +s = ujoin(got)
  IO.print(rd(nm, s))

def strrow(nm: String, got: String) -> IO(Unit):
  IO.print(rd(nm, got))

def srowl(nm: String, got: List<&2, String>) -> IO(Unit):
  +s = sjoin(got)
  IO.print(rd(nm, s))

# --- 1: the selector registry, :27. `functools.cache` IS the type ----------
# The fixture is NON-UNIFORM on purpose: seven lookups over FIVE distinct P.names
# in the order commit / waitForFence: / endEncoding / newBufferWithLength:
# options: / updateFence: / commit / waitForFence:. An all-equal fixture could
# not tell a cache from a dict-that-copies, and `getsel_distinct_count` is the
# row that says five and not seven.
def sels_f0() -> P.Sels: P.getsel("commit", P.Sels.of())
def sels_f1() -> P.Sels: P.getsel("waitForFence:", sels_f0())
def sels_f2() -> P.Sels: P.getsel("endEncoding", sels_f1())
def sels_f3() -> P.Sels: P.getsel("newBufferWithLength:options:", sels_f2())
def getsel_fixture() -> P.Sels: P.getsel("updateFence:", sels_f3())

# the seven lookups of the fixture, as a chain of PURE defs: a `do IO<Unit>`
# block may only bind an IO, so a value has to be threaded by name.
def sels_r1() -> P.Sels: P.getsel("commit", getsel_fixture())
def sels_r2() -> P.Sels: P.getsel("waitForFence:", sels_r1())
def sels_r3() -> P.Sels: P.getsel("commit", sels_r2())

def t_sels() -> IO(Unit):
  do IO<Unit>:
    row("sel_empty_miss", U32.is_eq(P.Sels.miss(P.Sels.of()), 0))
    row("sel_empty_count", U32.is_eq(P.Sels.count(P.Sels.of()), 0))
    strrow("sel_5_distinct", sjoin(P.Sels.names(getsel_fixture())))
    nrow("sel_miss_is_5", P.Sels.miss(getsel_fixture()))
    nrow("sel_hit_is_0", P.Sels.hit(getsel_fixture()))
    # 6, 7 and 8 lookups over the SAME five distinct P.names: one hit each time,
    # and the miss count FROZEN at 5. oracle gate_sels_6/7/8.
    nrow("sel_hit_after_repeat_is_1", P.Sels.hit(sels_r1()))
    nrow("sel_hit_after_repeat_is_2", P.Sels.hit(sels_r2()))
    nrow("sel_hit_after_repeat_is_3", P.Sels.hit(sels_r3()))
    nrow("sel_miss_frozen_at_5_1", P.Sels.miss(sels_r1()))
    nrow("sel_miss_frozen_at_5_2", P.Sels.miss(sels_r2()))
    nrow("sel_miss_frozen_at_5_3", P.Sels.miss(sels_r3()))
    nrow("sel_count_frozen_at_5", P.Sels.count(sels_r2()))
    nrow("sel_names_len_5", U32.from_nat(List.length(&2, String, P.Sels.names(sels_r2()))))
    # index 0 IS a real entry, so the id is index+1 and `P.sel.hit` is the
    # predicate. `sel_ix_commit_is_1` is the row for that: a 0-based id would
    # answer 0 here and only `sel_hit` would be left to catch it.
    nrow("sel_ix_commit_is_1", P.getsel_ix("commit", sels_r2()))
    nrow("sel_ix_absent_is_0", P.getsel_ix("nosuch", sels_r2()))
    orow("sel_hit_absent_false", P.sel.hit(P.Sels.ix(sels_r2()), "nosuch"))
    orow("sel_hit_commit_true", P.sel.hit(P.Sels.ix(sels_r2()), "commit"))
    # repeat identity: one name is one SEL forever, which is the ObjC invariant
    # `functools.cache` exists to exploit.
    orow("sel_repeat_same_id", U32.is_eq(P.getsel_ix("commit", sels_r2()), P.getsel_ix("commit", sels_r3())))
    orow("sel_repeat_is_a_hit_not_a_miss", U32.is_eq(P.Sels.miss(sels_r3()), P.Sels.miss(sels_r2())))
    orow("sel_distinct_differ", Bool.not(U32.is_eq(P.getsel_ix("commit", sels_r2()), P.getsel_ix("endEncoding", sels_r2()))))

# --- 2: P.msg's ARGTYPES, :36. THE HEADLINE RULE ------------------------------
# `sender.argtypes = [id_, id_] + list(argtypes) if argtypes else []`. Python's
# conditional binds looser than `+`, so a message with NO DECLARED ARGUMENTS gets
# an EMPTY list -- not the two implicit `id_`s. Measured by the oracle:
#   msg_argtypes_bare=[]                    msg_argtypes_charp_ret=[]
#   msg_argtypes_empty_list=[]              msg_restype_none_ret=None
#   msg_argtypes_one_declared=[id_,id_,MTLResourceOptions]
#   msg_argtypes_two_declared=[id_,id_,c_ulong,c_ulong]
# `msg_argtypes_none` and `msg_argc_none` are the two rows a "prepend two"
# implementation cannot pass.
def NONE_ARGS() -> List<&2, U32>: Nil{}
def ONE_ARGS() -> List<&2, U32>: [P.CT_U64()]
def TWO_ARGS() -> List<&2, U32>: [P.CT_U64(), P.CT_U64()]

def t_argtypes() -> IO(Unit):
  do IO<Unit>:
    lrow("msg_argtypes_none", P.msg_argtypes(NONE_ARGS()))
    lrow("msg_argtypes_one", P.msg_argtypes(ONE_ARGS()))
    lrow("msg_argtypes_two", P.msg_argtypes(TWO_ARGS()))
    nrow("msg_argc_none", P.msg_argc(NONE_ARGS()))
    nrow("msg_argc_one", P.msg_argc(ONE_ARGS()))
    nrow("msg_argc_two", P.msg_argc(TWO_ARGS()))
    # the row that separates the two readings. a naive `++ [ID, ID]` answers 2
    # here; the measured value is 0, and 0 is a value no reorder can produce.
    orow("msg_argtypes_none_is_not_two", Bool.not(U32.is_eq(P.msg_argc(NONE_ARGS()), 2)))
    # :36 tests TRUTHINESS, so an explicitly `[]` and an ABSENT argtypes are the
    # same list (oracle: msg_argtypes_empty_list == msg_argtypes_bare == []). In
    # Bend there is no "absent", so a row for it would compare a value with
    # itself -- the shape agent-core calls a def of the thing under test. NOT
    # ROWED, and that is the reason rather than an omission.
    # and the DECLARED types are not touched: `P.msg_argtypes` prepends, it does
    # not substitute, and `msg_argtypes_one` ends in 7 (P.CT_CLASS) not 1.
    lrow("msg_argtypes_keeps_declared_tail", P.msg_argtypes(ONE_ARGS()))

# --- 3: the call shape, :37. the receiver, the selector, the order ---------
# `sender(ptr._objc_class_ if clsmeth else ptr, P.getsel(P.sel.encode()), *args)`.
# The instance is 0xAAAA and the class 0xBBBB in every fixture, so a receiver
# that picked the wrong one is a different NUMBER and not a wording.
def INST() -> U32: 43690
def CLS() -> U32: 48059

def m_end() -> P.Msg: P.Msg.of("shapeOnlyOne:")
def m_cls() -> P.Msg: P.Msg{"shapeClass", P.CT_ID(), Nil{}, False{}, True{}}
def m_two() -> P.Msg: P.Msg{"shapeTwo:one:", P.CT_VOID(), [P.CT_BOOL()], False{}, False{}}

def tr_end() -> P.Tr: P.msg(INST(), m_end(), 0, P.Tr.of())
def tr_cls() -> P.Tr: P.msg(CLS(), m_cls(), 1, tr_end())
def tr_two() -> P.Tr: P.msg(INST(), m_two(), 2, tr_cls())

def t_shape() -> IO(Unit):
  do IO<Unit>:
    orow("shape_recv_instance", U32.is_eq(P.msg_receiver(INST(), CLS(), False{}), INST()))
    orow("shape_recv_class", U32.is_eq(P.msg_receiver(INST(), CLS(), True{}), CLS()))
    orow("shape_recv_differs", Bool.not(U32.is_eq(P.msg_receiver(INST(), CLS(), False{}), P.msg_receiver(INST(), CLS(), True{}))))
    # the argtypes DECLARED by :36 are NOT the argtypes PASSED at :37: a
    # no-argument message declares none and still passes two slots.
    nrow("shape_argv_no_args", P.msg_argv_len(P.msg_args(INST(), 0, NONE_ARGS())))
    nrow("shape_argv_one_arg", P.msg_argv_len(P.msg_args(INST(), 0, ONE_ARGS())))
    lrow("shape_argv_order", P.msg_args(7, 9, TWO_ARGS()))
    # one message is two calls, selector first. This is the measured
    # `shape_call_names=sel_registerName,objc_msgSend,...` and it is the reason
    # the generated device program needs BOTH symbols (cstyle.py:268 emits an
    # `extern` per CUSTOM_FUNCTION and hcq2.py:84 P.names one per ccall).
    nrow("shape_two_calls", P.s_two_calls(tr_end()))
    srowl("shape_order", P.Tr.syms(tr_end()))
    srowl("shape_order_three", P.Tr.syms(tr_two()))
    nrow("shape_total_calls", P.s_two_calls(tr_two()))
    orow("shape_sym0_is_selname", String.eq(P.Tr.sym_at(tr_end(), 0), P.SYM_SELNAME()))
    orow("shape_sym1_is_msgsend", String.eq(P.Tr.sym_at(tr_end(), 1), P.SYM_MSGSEND()))
    # the selector lookup is a call of its own, so a reversed pair would show up
    # here and nowhere else. `shape_order_reverse` is that row.
    orow("shape_order_reverse", String.eq(P.Tr.sym_at(tr_end(), 0), P.SYM_MSGSEND()))
    # the receiver the send carried, and the argtypes count it declared
    nrow("shape_send_recv_inst", P.Tr.a0(tr_end(), 1))
    nrow("shape_send_recv_cls", P.Tr.a0(tr_cls(), 3))
    nrow("shape_send_sel_ix_third", P.Tr.a1(tr_two(), 5))
    nrow("shape_send_recv_cls_in_three", P.Tr.a0(tr_two(), 3))
    nrow("shape_send_sel_ix", P.Tr.a1(tr_end(), 1))
    # a past-the-end read MISSES rather than answering 0 -- `Maybe`, not a
    # sentinel, and this is the row that says so.
    orow("shape_at_0_present", P.Tr.sym_ok(tr_end(), 0))
    orow("shape_at_2_absent", P.Tr.sym_ok(tr_end(), 2))
    strrow("shape_at_2_is_MISSING", P.Tr.sym_at(tr_end(), 2))

# --- 4: the selector-name mangling, :70 -------------------------------------
# `nm = m[0].strip(':').replace(':', '_')`, in THAT order. The oracle's ten
# fixtures are taken from `autogen/metal.py` and disagree on colon count, on
# leading and trailing colons, and on a name that is nothing but colons -- so an
# all-equal set could not tell `strip` from `lstrip`, and `mangle_3` is the one
# that catches the trailing-underscore mistake.
def t_mangle() -> IO(Unit):
  do IO<Unit>:
    strrow("mangle_0", P.mangle("init"))
    strrow("mangle_1", P.mangle("initWithCoder:"))
    strrow("mangle_2", P.mangle(":init:"))
    strrow("mangle_3", P.mangle("newBufferWithLength:options:"))
    strrow("mangle_4", P.mangle("dispatchThreadgroups:threadsPerThreadgroup:"))
    strrow("mangle_5", P.mangle("allocWithZone:"))
    strrow("mangle_6", P.mangle("::"))
    strrow("mangle_7", P.mangle(":"))
    strrow("mangle_8", P.mangle("commit"))
    strrow("mangle_9", P.mangle("UTF8String"))
    # `strip` REMOVES the trailing colon, so a selector ending in ':' does NOT
    # get a trailing underscore. `mangle_trailing_no_underscore` is the row that
    # a `replace`-first implementation fails, because that spelling would give
    # `newBufferWithLength_options_`.
    orow("mangle_trailing_no_underscore", Bool.not(String.ends_with(P.mangle("newBufferWithLength:options:"), "_")))
    orow("mangle_leading_and_trailing_stripped", String.eq(P.mangle(":init:"), "init"))
    orow("mangle_all_colons_become_empty", String.eq(P.mangle("::"), ""))
    # THE ORDER IS LOAD-BEARING, and this is the row: replacing FIRST leaves the
    # leading colon to become an underscore (`::x:` -> `_x_`), which Python does
    # not do. So `P.mangle.reversed` must DIFFER, and `mangle_order_swap` is the
    # row that says it does.
    strrow("mangle_reversed_0", P.mangle.reversed(":init:"))
    orow("mangle_order_swap", Bool.not(String.eq(P.mangle(":init:"), P.mangle.reversed(":init:"))))
    # ... and the two orders AGREE when there is no leading colon to convert,
    # which is the one case where the distinction cannot be seen. `a:b` is the
    # fixture: an interior colon, neither end coloned.
    orow("mangle_order_agrees_on_interior", String.eq(P.mangle("a:b"), P.mangle.reversed("a:b")))
    strrow("mangle_interior_a_b", P.mangle("a:b"))
    strrow("mangle_interior_reversed", P.mangle.reversed("a:b"))
    # THE COLLISION IS REAL. `::` and `:` both P.mangle to the empty string, so
    # `MetaSpec._addmeth` sets the SAME attribute for two different selectors --
    # which is why `P.meth_seen` keys on the MANGLED NAME, not the selector.
    orow("mangle_collides_on_empty", String.eq(P.mangle("::"), P.mangle(":")))
    orow("mangle_collides_on_two", String.eq(P.mangle("::"), P.mangle("a:b")))

# --- 5: the method table and the instancetype substitution, :69-73 ----------
# `_addmeth` computes `nm` and binds a `P.msg` under it, so the mangled name IS
# the attribute name and `P.Meth.name` is the whole of :70 on the record.
def m_init() -> P.Meth: P.Meth.of("init", P.CT_INST(), NONE_ARGS())
def m_new() -> P.Meth: P.Meth{"new", P.CT_INST(), NONE_ARGS(), True{}, True{}}
def m_takes() -> P.Meth: P.Meth{"takesInst:", P.CT_INST(), [P.CT_INST()], False{}, False{}}
def m_coder() -> P.Meth: P.Meth{"initWithCoder:", P.CT_INST(), [P.CT_U32()], False{}, False{}}
def m_two_arg() -> P.Meth: P.Meth{"two:", P.CT_INST(), [P.CT_INST(), P.CT_U64(), P.CT_INST()], False{}, False{}}
def m_u32ret() -> P.Meth: P.Meth{"size", P.CT_U64(), [P.CT_U64()], False{}, False{}}
def m_takesu() -> P.Meth: P.Meth{"takesU:", P.CT_INST(), [P.CT_U64()], False{}, False{}}

# the THIRD declared slot, because `List[k]` answers an Array and the rows need
# a scalar. `Maybe.default` keeps the miss explicit.
def third(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 2n), 4294967295)

def mnames.go(n: Nat, +xs: List<&2, P.Meth>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case mm <> t: mnames.go(m, t, List.append(&2, String, acc, [P.Meth.name(mm)]))

def Methnames(+xs: List<&2, P.Meth>) -> List<&2, String>:
  mnames.go(List.length(&2, P.Meth, xs), xs, Nil{})

def t_meth() -> IO(Unit):
  do IO<Unit>:
    strrow("meth_name_init", P.Meth.name(m_init()))
    strrow("meth_name_new", P.Meth.name(m_new()))
    strrow("meth_name_takes", P.Meth.name(m_takes()))
    strrow("meth_name_coder", P.Meth.name(m_coder()))
    # :71-72 `cls if m[1] == 'instancetype' else m[1]` -- THE RETURN SLOT
    nrow("meth_ret_inst_becomes_class", P.Msg.ret(P.Meth.msg(m_init())))
    nrow("meth_ret_plain_passes_through", P.Msg.ret(P.Meth.msg(m_u32ret())))
    # ... and EVERY argument slot, independently (oracle
    # metaspec_instancetype_arg=[id_,id_,ChildFake]).
    lrow("meth_args_inst_becomes_class", P.Msg.argtypes(P.Meth.msg(m_takes())))
    # `meth_args_scalar_pass_through` below is the SAME argument shape reached
    # through a P.Meth rather than through a bare list, so there is no second row
    # for it: two spellings of one value is a row that cannot fail.

    # the declared scalar passes through and does NOT become P.CT_CLASS: the
    # substitution keys on the LITERAL 'instancetype' and on nothing else.
    lrow("meth_args_scalar_pass_through", P.Msg.argtypes(P.Meth.msg(m_takesu())))
    strrow("meth_name_takesu", P.Meth.name(m_takesu()))
    # the substitution happens BEFORE the prepend, so a declared `instancetype`
    # is 7 and not 1,1,8. `meth_args_inst_is_not_8` is the row.
    orow("meth_args_inst_is_not_8", U32.is_eq(third(P.Msg.argtypes(P.Meth.msg(m_takes()))), 7))
    nrow("meth_args_inst_third", third(P.Msg.argtypes(P.Meth.msg(m_takes()))))
    # `:72` is PER ARGUMENT and every OTHER fixture here has ONE, so a
    # `P.subst_list` that stopped after the head was invisible -- M13 of the
    # mutation table moved ZERO rows until this fixture existed. Three declared
    # args, the FIRST and LAST `instancetype`, so a truncation, a
    # first-only substitution and a last-only substitution are all separable.
    lrow("meth_args_inst_both_ends", P.Msg.argtypes(P.Meth.msg(m_two_arg())))
    nrow("meth_args_inst_len_is_5", P.msg_argc(P.Msg.args(P.Meth.msg(m_two_arg()))))
    # :38 `returns_retained(f) if retain else f` -- and the fourth tuple element
    # is what sets it (oracle msg_wrapped_retain_true=True, _false=False).
    orow("meth_retain_true", P.Msg.retain(P.Meth.msg(m_new())))
    orow("meth_retain_false", P.Msg.retain(P.Meth.msg(m_init())))
    # :73 `clsmeth=True` for a `_classmethods_` entry.
    orow("meth_clsmeth_true", P.Msg.clsmeth(P.Meth.msg(m_new())))
    orow("meth_clsmeth_false", P.Msg.clsmeth(P.Meth.msg(m_init())))

# --- 6: the inheritance order, :63-67 --------------------------------------
# `_inherit` walks a base's bases FIRST (:64), then its instance methods
# (:65), then its CLASS methods (:66), then re-runs every CHILD (:67).
def inh_bases() -> List<&2, P.Meth>: [m_init()]
def inh_all() -> List<&2, P.Meth>: [m_coder(), m_new()]

# Nat fuel, spelled so the binder is unambiguous (a bare `2` infers U32).
def n0() -> Nat: 0n
def n2() -> Nat: (1n + 1n : Nat)
def n3() -> Nat: (1n + (1n + 1n) : Nat)

def t_inherit() -> IO(Unit):
  do IO<Unit>:
    srowl("inh_none", Methnames(P.inh.go(n0(), inh_all(), Nil{})))
    srowl("inh_two", Methnames(P.inh.go(n2(), inh_all(), Nil{})))
    # :65-66 -- instance methods before CLASS methods, for the SAME base. A
    # reverse would give `new,initWithCoder`, so `inh_order_classlast` moves.
    orow("inh_order_classlast", String.eq(sjoin(Methnames(P.inh.go(n2(), inh_all(), Nil{}))), "initWithCoder,new"))
    # :67 -- a child re-inherits, so a DUPLICATE is dropped by name. The two
    # entries of `inh_all` have DISTINCT P.names, so the dedup row needs a
    # fixture that collides, which is `inh_dup`.
    srowl("inh_dup", Methnames(P.inh.go(n3(), [m_init(), m_init(), m_new()], Nil{})))
    nrow("inh_dup_len", U32.from_nat(List.length(&2, P.Meth, P.inh.go(n3(), [m_init(), m_init(), m_new()], Nil{}))))

# --- 7: the ownership lattice, :6-23 ----------------------------------------
# THREE things that read alike and are not the same, and the gate keeps them in
# three separate families so no row can be satisfied by conflating two:
#
#   the FLAG       (`retain`, a Python attribute)  -- P.Idr.retained, no call
#   the CALL       (`own` sends retain, `release` sends release) -- 2 C calls each
#   the WRAPPER    (`returns_retained`)            -- Q.Owned.of, flags a RESULT
#
# Oracle: own_default_retain=False, own_after_retained=True, own_after_own=True,
# own_returns_self=True, own_c_call_count=2,
# own_c_call_names=sel_registerName,objc_msgSend,
# own_release_c_call_count=1, own_release_leaves_the_flag=False.
# (`release`'s `P.getsel(b"release")` was already memoised by an earlier fixture,
# so its ONE call is the message alone -- which is itself the point of :27.)
# no `value.field` sugar: every field read is a reader def (constraint line 4221)
def Owned.tr(o: Q.Owned) -> P.Tr:
  match o:
    case Q.Owned{tr, r}: tr
def Owned.r(o: Q.Owned) -> P.Idr:
  match o:
    case Q.Owned{tr, r}: r

def idr_x() -> P.Idr: P.Idr.of(43690)
def idr_y() -> P.Idr: P.Idr.of(48059)
def own_y() -> Q.Owned: P.Idr.own(idr_y(), P.Tr.of())
def own_x() -> Q.Owned: P.Idr.own(idr_x(), Owned.tr(own_y()))

def t_own() -> IO(Unit):
  do IO<Unit>:
    orow("own_default_retain", P.Idr.retain(idr_x()))
    orow("own_after_retained", P.Idr.retain(P.Idr.retained(idr_x())))
    orow("own_after_own", P.Idr.retain(Owned.r(own_y())))
    nrow("own_ptr_unchanged", P.Idr.ptr(Owned.r(own_y())))
    # :16 `retained()` returns SELF, so the flag is the only thing that changed.
    orow("own_retained_keeps_ptr", U32.is_eq(P.Idr.ptr(P.Idr.retained(idr_x())), INST()))
    # :11-12 equality and hashing are on the VALUE, which is what makes
    # `dict.fromkeys()` dedup a set of objects (own_dedup_fromkeys_len=2).
    orow("own_eq_on_value", P.Idr.eq(idr_x(), P.Idr.of(INST())))
    orow("own_ne_on_value", Bool.not(P.Idr.eq(idr_x(), idr_y())))
    # :21 `own()` costs TWO C calls, because `P.msg("retain")` is itself a `P.msg`
    # and :37 evaluates `P.getsel` first. `own_c_calls_is_2` is the row.
    nrow("own_c_calls_is_2", P.s_two_calls(Owned.tr(own_y())))
    srowl("own_c_call_names", P.Tr.syms(Owned.tr(own_y())))
    # the flag and the call are separate: `retained()` sends nothing.
    nrow("own_retained_c_calls", P.s_two_calls(P.Tr.of()))
    orow("own_release_leaves_flag", P.Idr.retain(P.Idr.retained(idr_x())))
    # `release()` is `P.msg("release")(self)`, so on a FRESH registry it is also
    # two calls (gate_release_call_count=2) -- and the oracle's
    # gate_release_twice_call_count=1 is what the memo buys: the second release
    # skips `sel_registerName`. The port has no memo on this path and says so.
    nrow("own_release_c_calls", P.s_two_calls(P.Idr.release(idr_x(), P.Tr.of())))
    srowl("own_release_c_call_names", P.Tr.syms(P.Idr.release(idr_x(), P.Tr.of())))
    # :13-14 `if self.retain and not self._is_finalizing(): self.release()`.
    # BOTH conjuncts are PARAMETERS, and each of the three rows is one conjunct
    # -- an implementation that dropped either would move exactly one of them.
    nrow("del_flag_false_sends_none", P.s_two_calls(P.Idr.finalize(idr_x(), False{}, P.Tr.of())))
    nrow("del_finalizing_sends_none", P.s_two_calls(P.Idr.finalize(P.Idr.retained(idr_x()), True{}, P.Tr.of())))
    srowl("del_finalizing_sends_nothing", P.Tr.syms(P.Idr.finalize(P.Idr.retained(idr_x()), True{}, P.Tr.of())))
    nrow("del_both_true_sends_two", P.s_two_calls(P.Idr.finalize(P.Idr.retained(idr_x()), False{}, P.Tr.of())))
    srowl("del_both_true_sends_sel_then_msg", P.Tr.syms(P.Idr.finalize(P.Idr.retained(idr_x()), False{}, P.Tr.of())))
    # :23/:38 the WRAPPER. `returns_retained` flags the RESULT of the message,
    # which is a different thing from `own` flagging its receiver.
    orow("own_wrapper_off", P.Idr.retain(Owned.r(Q.Owned.of(P.Tr.of(), idr_x(), P.Meth.msg(m_init())))))
    orow("own_wrapper_on", P.Idr.retain(Owned.r(Q.Owned.of(P.Tr.of(), idr_x(), P.Meth.msg(m_new())))))
    orow("own_wrapper_keeps_ptr", U32.is_eq(P.Idr.ptr(Owned.r(Q.Owned.of(P.Tr.of(), idr_x(), P.Meth.msg(m_new())))), INST()))
    nrow("own_wrapper_sends_nothing", P.s_two_calls(Owned.tr(Q.Owned.of(P.Tr.of(), idr_x(), P.Meth.msg(m_new())))))

# --- 8: the symbol-binding audit, which is a DOCUMENTED NON-ROW ------------
# Nothing here is computed by this file: it is a library question, and the
# answers live in `.agents/slop/objc/symtab_oracle.txt`. They are printed as
# literals so the claim is IN THE GATE rather than only in a comment, and they
# are marked VALUE-BLIND because a gate that recomputed a dlsym would be an FFI
# seam, which is the one thing this file refuses to be.
def t_symbols() -> IO(Unit):
  do IO<Unit>:
    # MEASURED by `xcrun dyld_info -exports` on THIS host, 1457 live exports.
    srow("sym_metal_exports_selname", "0/1457")
    srow("sym_metal_exports_msgsend", "0/1457")
    srow("sym_libobjc_exports_selname", "1/437")
    srow("sym_libobjc_exports_msgsend", "1/437")
    # and yet dlsym THROUGH the Metal handle resolves both, because libobjc is a
    # dependency of Metal. A binding that resolves is not a symbol the library
    # exports, and that gap is the whole defect.
    srow("sym_metal_handle_reaches_selname", "0x1801ac730")
    srow("sym_metal_handle_reaches_msgsend", "0x1801a5800")
    srow("sym_libobjc_handle_same_address", "0x1801ac730")
    # the failure is at LINK time, against these two, which export neither.
    srow("sym_libm_exports_selname", "MISSING")
    srow("sym_libsystem_exports_selname", "MISSING")
    # TODO(p3) runtime/support/objc.py:25  symbol=lib  -- CDLL(find_library('objc'))
    # TODO(p3) runtime/support/objc.py:30  symbol=dispatch_data_create  -- CDLL("/usr/lib/libSystem.dylib")
    # TODO(p3) runtime/ops_cpu.py:18  symbol=CPUProgram       -- libobjc is missing from
    #   CPUProgram.link_libs, so elf.py:13 cannot link the `extern void
    #   sel_registerName();` that cstyle.py:268 emits for every CUSTOM_FUNCTION.
    #   REPORTED, NOT FIXED: ops_cpu.py is not this unit's file.

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_sels()
    b : Unit <- t_argtypes()
    +c : Unit <- t_shape()
    d : Unit <- t_mangle()
    e : Unit <- t_meth()
    +f : Unit <- t_inherit()
    g : Unit <- t_own()
    h : Unit <- t_symbols()
    IO.print("objc-done=1")

# THE MUTATION TABLE. Every number is the harness's output, not an estimate:
# `.venv/bin/python .agents/slop/objc/objc_mutate.py`, whose output is
# `.agents/slop/objc/objc_mutations.txt`. The harness applies ONE exact
# single-line substitution to a scratch copy, runs the INTERPRETED lane, and
# diffs whole `name=value` lines -- never the row P.names, because a
# name-comparing harness reported 0 for all 68 mutations in another unit.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `P.msg_argtypes`: the `Nil{}` arm answers `[id_, id_]` | 1 | THE HEADLINE, `:36`'s `[id_,id_]+list(argtypes) if argtypes else []`. `msg_argtypes_none` is the only row that reads it, and one row is the right count for one rule. |
# | M2 | `P.mangle.rtrim.go`: answer `c <> t` instead of `c <> r` | 12 | `:70`'s rtrim. Keeping the UNTRIMMED tail is the bug this port actually had; `mangle_1`, `mangle_3`, `mangle_4`, `mangle_5`, `mangle_leading_and_trailing_stripped`, `mangle_trailing_no_underscore` and the four `inh_*` rows that print mangled P.names are what caught it. |
# | M3 | `P.mangle.ltrim`: strip unconditionally | 23 | `:70`'s ltrim. Eats the whole string, so every non-empty fixture changes and every row printing a mangled name moves. |
# | M4 | `P.mangle`: `replace` before `strip` | 17 | THE ORDER of `strip(':').replace(':','_')`. A leading colon becomes an underscore, so `mangle_2` (`:init:`) and `mangle_6`/`mangle_7` (`::`, `:`) all move. |
# | M5 | `P.getsel_ix`: drop the MISS arm | 1 | Index 0 is a REAL index, so a 0-based id and a miss are the same answer unless `P.sel.hit` separates them. The bug this port actually had: `sel_ix_absent_is_0` read 1. |
# | M6 | `P.msg_argc`: count the `d <> r` TAIL | 3 | The head of a list pattern. The bug this port actually had: `msg_argc_one` read 2 and wanted 3. Also `meth_args_inst_len_is_5`, which is the row that found the SECOND `P.msg_argc` bug (feeding it `:36`'s already-prepended output). |
# | M7 | `P.msg`: drop the selector lookup | 18 | `:37`'s ORDER. `P.getsel(P.sel.encode())` is an ARGUMENT of the send, so the lookup is a C call that precedes it. Every call-count and call-NAME row moves, including `own_*` and `del_*` because they go through `P.msg`. |
# | M8 | `P.Idr.own`: emit only the msgSend | 2 | `:20 own()` IS `P.msg("retain")`. The third bug the oracle caught: the port sent one C call where the real `objc.py` sends two. |
# | M9 | `P.Idr.finalize`: drop the `retain` conjunct | 1 | `:13-14`'s FIRST conjunct, and only `del_flag_false_sends_none` moves -- so the two conjuncts are separate claims and not one. |
# | M10 | `P.Idr.finalize`: drop the `is_finalizing` conjunct | 2 | `:13-14`'s SECOND conjunct. `del_finalizing_sends_none` AND `del_finalizing_sends_nothing`, which is the count row beside the list row. |
# | M11 | `Q.Owned.of`: ignore `P.Msg.retain` | 1 | `:23`/`:38`, `returns_retained`. One row, and it is the only row that reads the WRAPPER half of the ownership lattice. |
# | M12 | `P.subst`: no substitution | 5 | `:71`'s `cls if m[1] == 'instancetype' else m[1]`. |
# | M13 | `P.subst_list`: stop after the head | 2 | `:72`'s PER-ARGUMENT substitution. This moved 0 rows until `meth_args_inst_both_ends` existed -- every other fixture declares ONE argument, so a truncating `P.subst_list` was indistinguishable from a correct one. A zero that was a fixture request, and the fixture is the second and THIRD declared arguments. |
# | M14 | `P.msg_receiver`: always the instance | 2 | `:37`'s `ptr._objc_class_ if clsmeth else ptr`. |
# | M15 | `P.inh.go`: no dedup | 2 | `:67`'s re-inherit. Two selectors that P.mangle alike (`::` and `:`) collide on one attribute, and the dedup is keyed on the MANGLED NAME for that reason. |
# | M16 | `P.sel.put`: a HIT that appends | 10 | `:27`'s memo. Every counter row and the frozen-`count` row move, because `currsize` grows and a repeat stops being a repeat. |
# | M17 | a comment-only edit | 0 -- THE CONTROL | a table in which every entry moves is measuring noise. |
# | M18 | `P.mangle.colons`: identity | 6 | `:70`'s `.replace(':','_')`. Every fixture with an INTERIOR colon moves and every fixture without one does not -- which is what a non-uniform fixture set buys. |
#
# THE THREE ZEROS, and none of them is a theorem:
#   * M17 is the CONTROL and must be 0.
#   * M13 was a 0 until the fixture was added. It is a 2 now.
#   * M1, M5, M9 and M11 move exactly ONE row each, and each is a theorem about
#     how the gate is WIREN rather than about coverage: M1 is one rule read by
#     one row, M5's miss arm is read by one row, M9's first conjunct is read by
#     one row, and M11 is the only row that reads `returns_retained`. A one-row
#     move is not a thin gate; it is a precise one, and the row P.names say which.

# WHAT A FIXTURE SET HERE HAD TO BE, since two of the eighteen started at zero:
#   * The MANGLING fixtures disagree on colon COUNT, on leading and trailing
#     colons, and on a name that is nothing but colons. An all-`commit` set
#     cannot tell `strip` from `lstrip` (M3 vs M4 both move 0 on it).
#   * The ARGTYPES fixtures cover zero, one and two declared arguments, an
#     EXPLICIT `[]`, an explicit `None` restype, and a `restype` with no
#     argtypes. The zero-declaration case is the one the headline rule is about.
#   * The `P.Sels` fixture is FIVE distinct P.names looked up SEVEN then EIGHT
#     times, so `miss` freezes while `hit` grows. A fixture that looked each
#     name up once has `miss == hit` and cannot separate them.
#   * The SUBSTITUTION fixture declares THREE arguments with `instancetype` in
#     the FIRST and the LAST, because `:72` is per-argument and a one-argument
#     fixture cannot see a truncation.
