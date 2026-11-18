# tinybendygrad/runtime/support/objc.bend -- port of tinygrad/runtime/support/objc.py
#
# WHAT THIS FILE IS. 77 lines of Python, and 5 of them are the interesting
# ones. `objc.py` binds five symbols out of two shared libraries and then does
# STRING LOGIC with them: the selector-name mangling that turns an Objective-C
# selector into a Python attribute name, the `functools.cache` that makes one
# selector name mean one SEL forever, the `msg` shape that prepends a receiver
# and a selector to every call, and the `retain` / `returns_retained` /
# `own` ownership lattice that decides who calls `release`. The ctypes loads are
# the seam. This file ports the logic and leaves the loads to the trace.
#

#

# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one objc call (pure, and the gate checks it) OR records that call in the
# trace (the gate checks ORDER and IDENTITY). There is no third kind. No
# `@extern`, so `--check-only` says ALL PROOFS CHECK.
#

# THE ORACLE. Every `py=` expectation below is a row of
# `.agents/slop/objc/objc_oracle.txt`, produced by CALLING the real `objc.py`
# with exactly one thing stubbed: the four `ctypes.CDLL` loads at :25-32.
# Nothing is hand-transcribed. The stub is not cosmetic -- it reproduces
# ctypes' ASYMMETRY, because :36's own comment is about it:
#
#   lib["objc_msgSend"]   SUBSCRIPT -> a FRESH fnptr per msg, so setting
#                                 restype on it is safe (:36's comment)
#   lib.sel_registerName ATTRIBUTE -> one CACHED fnptr, set once (:26)
#
# A stub that cached both would turn the whole file into a shared last-write-wins
# slot and hide the design. The oracle measures both directions
# (`fresh_msgsend_per_msg` 13, `cached_msgsend_attrs` 0).
#

# THE HEADLINE MEASUREMENT, which is not about this file at all.
#
# `ops_metal.py:86` binds BOTH `objc_msgSend` AND `sel_registerName` on
# `metal.dll` -- the Metal framework. Measured with
# `xcrun dyld_info -exports` (see `.agents/slop/objc/symtab_oracle.txt`):
#
#   Metal.framework exports 1457 symbols and `sel_registerName` is NOT one of
#
# The failure is NOT a failed dlsym. `hcq2.py:84` names a DEVICE symbol after
# `fn.__name__`, so `ccall(SELNAME, sel)` becomes `custom_function
# ("sel_registerName"), `tinygrad/renderer/cstyle.py:271` emits `extern void sel_registerName();`
# into the generated host kernel, and `elf.py:13` then fails to link it
# against `[libm, libSystem]` -- neither of which exports it either. Measured
# end to end: `(a@a.T).realize()` raises `RuntimeError: Attempting to relocate
# against an undefined symbol sel_registerName`. The fix belongs in
# `tinygrad/runtime/ops_cpu.py:18-19 symbol=CPUProgram` (upstream's `rt_lib` -- libobjc is missing from `CPUProgram.link_libs`), NOT in
# `objc.py` and NOT in `tinygrad/runtime/ops_metal.py:86` (upstream's `objc_msgSend` binding). Reported, not fixed.
#
# WALLS, and they are four narrow ones.
#
# W1  THE LIBRARY LOADS, :25-32. Four `ctypes.CDLL`s and a
#     `ctypes.util.find_library`. Bend can open neither. Every symbol is
#     therefore a NAME the trace carries and never an address.
#     TODO(p3) runtime/support/objc.py:25 -- `CDLL(find_library('objc'))`.
#     TODO(p3) runtime/support/objc.py:30 -- `CDLL("/usr/lib/libSystem.dylib")`.
#     NOTE, measured, and worth knowing before anyone "fixes" it: that second
#     path resolves for a BARE `ctypes.CDLL` (the dyld shared cache has it) and
#     does NOT for `support/c.py`'s `DLL`, whose `findlib` gates on
#     `pathlib.Path(p).is_file()` (`c.py:102-103`) and silently skips it. So
#     routing objc.py's libSystem load through `DLL` would BREAK a binding that
#     works today. `symtab_oracle.py` measures both.
#
# W2  `class id_(ctypes.c_void_p)`, :6-21. The POINTER is a `c_void_p` and
#     `id_` adds hashing, value-equality and `__del__`. What ports is the
#     ownership lattice, as a value transformation over a `U32` address; what
#     does not is that the address is opaque and that `__del__` is GC-TIMED.
#     `Idr.finalize` takes `is_finalizing` as a PARAMETER, which is the whole
#     of `__del__`'s guard (:13-14) and makes it testable at all.
#     TODO(p3) runtime/support/objc.py:13  symbol=__del__ -- the `__del__` hook itself.
#
# W3  THE METAINTERPRETER, :47-73. `MetaSpec.__new__` / `__setattr__` /
#     `_inherit` / `_addmeth` are metaclass hooks: they run when a CLASS is
#     created, and Bend has no classes. What ports is the DECISION each hook
#     makes -- the mangled name, the `instancetype` substitution, the
#     clsmeth flag -- over an explicit method table (`Meth`). What does not is
#     that `objc_getClass(name.encode())` hands back a live `Class` object,
#     which is W1 wearing a hat.
#     TODO(p3) runtime/support/objc.py:49 -- `lib.objc_getClass(name.encode())`.
#     TODO(p3) runtime/support/objc.py:71  symbol=_addmeth -- `classmethod(...)` wrapping.
#
# W4  THE CALLABLES. `msg` returns a closure over `sender` and `sel`, and
#     `returns_retained` returns a closure over `f`; Bend has no first-class
#     functions (a fold over a function parameter is impossible). So a `Msg` is
#     a VALUE here and `returns_retained` is a post-processor on its result
#     (`Owned.of`). Nothing is lost: `functools.wraps` preserves `__name__`,
#     and `hasattr(f, '__wrapped__')` is exactly the port's `retain` flag --
#     both MEASURED, not assumed.
#     `returns_retained_name=f` is the sharp version of that: the wrapped
#     function is named `f`, NOT the selector, because `returns_retained(f)`
#     wraps the INNER `f` from tinygrad/runtime/support/objc.py:37 -- upstream's `sender` -- and not `msg`'s return.
#
# THE TABLE IS IN `.agents/slop/tables/runtime-support-objc-88.md` -- WHAT IS PORTED, DEF BY DEF.
#
# THE ARGUMENT MANGLING, and it is TWO steps with an ORDER between them that
# a one-step reading gets wrong. `nm = m[0].strip(':').replace(':', '_')`.
#
#   `strip(':')` removes colons from BOTH ends -- so a SELECTOR ENDING IN A
#   colon does not get a trailing underscore. `newBufferWithLength:options:`
#   mangles to `newBufferWithLength_options`, not `...options_`. Measured
#   (`mangle_3`, `mangle_trailing_colon_keeps_underscore`).
#
#   `replace(':','_')` then maps every REMAINING colon. `dispatchThreadgroups:
#
# The two steps commute on the INTERIOR but NOT on the ends, so the gate runs
# both orders: `mangle_order_swap` asserts the two spellings agree, and it
# does -- which is the theorem, not the point. The point is `mangle_3`.
import Base

# THE CTYPE KINDS. `msg`'s argtypes are lists of ctypes CLASSES, and a class is
# not a value. So each is a tag, and the tags are what the gate compares
# against the oracle's `kinds()` spelling. `CT_ID` is `id_`; `CT_INST` is the
# string `'instancetype'`, which :71-72 replaces with the CLASS -- a value this
# port cannot hold, hence WALL 3 rather than a fifth kind.

def CT_VOID() -> U32: 0
def CT_ID() -> U32: 1
def CT_I32() -> U32: 2
def CT_U32() -> U32: 3
def CT_U64() -> U32: 4
def CT_BOOL() -> U32: 5
def CT_CHARP() -> U32: 6
def CT_CLASS() -> U32: 7
def CT_INST() -> U32: 8

def POOL_PUSH() -> String: "objc_autoreleasePoolPush"
def POOL_POP() -> String: "objc_autoreleasePoolPop"
def SYM_MSGSEND() -> String: "objc_msgSend"
def SYM_SELNAME() -> String: "sel_registerName"
def SYM_GETCLASS() -> String: "objc_getClass"
def SYM_DDCREATE() -> String: "dispatch_data_create"

# THE SELECTOR-NAME MANGLING. :70. See the header for why it is two steps.

def is_colon(c: Char) -> Bool: Char.is_eq(c, ':')

# step 1: drop every leading and trailing colon.
def mangle.ltrim(+cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: Nil{}
    case c <> t: Bool.pick(List<&2, Char>, is_colon(c), mangle.ltrim(t), cs)

# `+cs` is read twice in ONE expression, so both copies are spelled. The guard is
def mangle.rtrim.go(+c: Char, +t: List<&2, Char>, +r: List<&2, Char>) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Bool.and(is_colon(c), List.is_empty(&2, Char, t)), Nil{}, c <> r)

def mangle.rtrim(cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: Nil{}
    case +c <> +t: mangle.rtrim.go(c, t, mangle.rtrim(t))

# step 2: every colon that survives becomes an underscore.
def mangle.colons(+cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: Nil{}
    case c <> t: Bool.pick(Char, is_colon(c), '_', c) <> mangle.colons(t)

def mangle(s: String) -> String:
  String.from_list(mangle.colons(mangle.rtrim(mangle.ltrim(String.to_list(s)))))

# THE ORDER MATTERS, and this is the whole point of splitting :70 in two:
# `.replace(':','_')` FIRST leaves a leading colon to become an underscore
# (`::x:` -> `_x_`), which Python does not do. `mangle_reversed` is the wrong
# spelling and `mangle_order_swap` is the row that says they differ.
def mangle.reversed(s: String) -> String:
  String.from_list(mangle.rtrim(mangle.ltrim(mangle.colons(String.to_list(s)))))

# THE SELECTOR REGISTRY, :27. `getsel = functools.cache(lib.sel_registerName)`
# is a MEMO, so it is a TYPE here rather than a function, and the type carries
# the two counters `functools.cache` exposes: one MISS per DISTINCT name, ever,
# and one HIT per repeat. That is the load-bearing property -- ObjC interns
# selector names, so one name is one SEL forever, and the memo is what makes
# the second message of a name free.
#
# The SEL "value" is this port's own INDEX into `ix`, not an address: Bend has
# no pointer and an address is not stable across runs. So the numbers are
# PORT TAGS, and what the gate checks is the STRUCTURE -- the miss count, the
# hit count, the hit/miss ratio, the repeat identity and the distinct count.

type SelRow is Data:
  SelRow{name: String, ix: U32}

type Sels is Data:
  Sels{ix: List<&2, SelRow>, next: U32, miss: U32, hit: U32}

# `sel.found` answers the index of `s`, or 0 when absent. 0 is also the FIRST
# real index, so `hit` disambiguates and the caller never reads `found` alone.
def sel.found(+xs: List<&2, SelRow>, +s: String, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case SelRow{n, j} <> t: Bool.pick(U32, String.eq(n, s), i, sel.found(t, s, U32.add(i, 1)))

# "is `s` present?", which is NOT `getsel_ix == 0` -- see getsel_ix.
def sel.hit(+xs: List<&2, SelRow>, +s: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case SelRow{n, _} <> t: Bool.or(String.eq(n, s), sel.hit(t, s))

# a lookup that either HITS (records nothing) or MISSES (appends one row and
# bumps `next`). `sel.hit` is the PREDICATE, not the index, because index 0 is
# a real index: an index-valued miss arm is a silent rewrite of entry 0.
def sel.put(+xs: List<&2, SelRow>, +s: String, +next: U32, +miss: U32, +hit: U32) -> Sels:
  Bool.pick(Sels, sel.hit(xs, s),
            Sels{xs, next, miss, U32.add(hit, 1)},
            Sels{List.append(&2, SelRow, xs, [SelRow{s, next}]), U32.add(next, 1),
                 U32.add(miss, 1), hit})

def Sels.of() -> Sels: Sels{Nil{}, 0, 0, 0}

def Sels.ix(t: Sels) -> List<&2, SelRow>:
  match t:
    case Sels{ix, next, miss, hit}: ix
def Sels.next(t: Sels) -> U32:
  match t:
    case Sels{ix, next, miss, hit}: next
def Sels.miss(t: Sels) -> U32:
  match t:
    case Sels{ix, next, miss, hit}: miss
def Sels.hit(t: Sels) -> U32:
  match t:
    case Sels{ix, next, miss, hit}: hit

def Sels.count(t: Sels) -> U32: Sels.next(t)

# `getsel(s)`. The Python takes BYTES and so does the real thing; Bend has no
# bytes, so it takes the name. The encoding is the name's own encoding and
# nothing else -- `sel.registerName` wants no NUL on Darwin -- and
# `getsel_twocall` is the row that says the lookup is a call of its own.
def getsel(s: String, +t: Sels) -> Sels: sel.put(Sels.ix(t), s, Sels.next(t), Sels.miss(t), Sels.hit(t))

# the SEL id, which is this port's own REGISTRY INDEX (see the Sels header).
def getsel_ix(+s: String, +t: Sels) -> U32:
  Bool.pick(U32, sel.hit(Sels.ix(t), s), U32.add(sel.found(Sels.ix(t), s, 0), 1), 0)

def names.go(n: Nat, +xs: List<&2, SelRow>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case SelRow{nm, ix} <> t: names.go(m, t, List.append(&2, String, acc, [nm]))

def Sels.names(+t: Sels) -> List<&2, String>:
  names.go(List.length(&2, SelRow, Sels.ix(t)), Sels.ix(t), Nil{})

# THE MESSAGE SPEC, :34. Five parameters: the selector, the return type, the
# declared argument types, `retain`, and `clsmeth`.
# `args` is the DECLARED argument list -- `m[2]`, after `subst_list` -- and
# `Msg.argtypes` is what `:36` assigns to `sender`, which is NOT the same list:
# `msg_argc` counts the DECLARED args and adds two for the receiver and the
# selector, so feeding it `:36`'s output double-counts them. That was a real bug
# (`meth_args_inst_len_is_5` read 7 and wanted 5) and it is why the two are
# separate readers rather than one.
type Msg is Data:
  Msg{sel: String, ret: U32, args: List<&2, U32>, retain: Bool, clsmeth: Bool}

def Msg.of(sel: String) -> Msg: Msg{sel, CT_ID(), Nil{}, False{}, False{}}
def Msg.sel(m: Msg) -> String:
  match m:
    case Msg{sel, ret, args, retain, clsmeth}: sel
def Msg.ret(m: Msg) -> U32:
  match m:
    case Msg{sel, ret, args, retain, clsmeth}: ret
def Msg.args(m: Msg) -> List<&2, U32>:
  match m:
    case Msg{sel, ret, args, retain, clsmeth}: args
def Msg.retain(m: Msg) -> Bool:
  match m:
    case Msg{sel, ret, args, retain, clsmeth}: retain
def Msg.clsmeth(m: Msg) -> Bool:
  match m:
    case Msg{sel, ret, args, retain, clsmeth}: clsmeth

# the argument list, :36. the headline rule of this file:
#
#   sender.restype, sender.argtypes = restype, [id_, id_]+list(argtypes) if argtypes else []
#
# Python's conditional binds LOOSER than `+`, so this parses as
#
#   (  [id_, id_] + list(argtypes)  )  if  argtypes  else  []
#
# and the consequence is that a message with NO DECLARED ARGUMENTS gets an
# EMPTY argtypes list -- not the two implicit `id_`s. The receiver and the
# selector are passed positionally, and ctypes is told nothing about them.
#
# MEASURED, and it is the opposite of the natural reading:
#   msg_argtypes_bare=[]            no argtypes        -> []
#   msg_argtypes_charp_ret=[]       restype only       -> []
#   msg_argtypes_one_declared=[id_,id_,MTLResourceOptions]
#   msg_argtypes_two_declared=[id_,id_,c_ulong,c_ulong]
#   msg_argtypes_empty_list=[]      an explicit `[]` is indistinguishable
#   msg_restype_none_ret=None       an explicit `None` restype means VOID
#
# So `msg_argtypes` is not "prepend two". It is "prepend two IF anything was
# declared, otherwise nothing", and `msg_argtypes_none` is the row that can
# tell the two apart from a wrong implementation.

def msg_argtypes(declared: List<&2, U32>) -> List<&2, U32>:
  match declared:
    case Nil{}: Nil{}
    case d <> r: List.append(&2, U32, [CT_ID(), CT_ID()], declared)

# `:36` -- what the sender is told. `[]` when nothing was declared.
def Msg.argtypes(m: Msg) -> List<&2, U32>: msg_argtypes(Msg.args(m))

def msg_argc(declared: List<&2, U32>) -> U32:
  match declared:
    case Nil{}: 0
    # the WHOLE list, not the `d <> r` tail -- using the tail answers n and not
    # n+2. Caught by `msg_argc_one` (2, wanted 3).
    case d <> r: U32.add(2, U32.from_nat(List.length(&2, U32, declared)))

# THE CALL SHAPE, :37.
#
#   f(ptr, *args) = sender(ptr._objc_class_ if clsmeth else ptr,
#                          getsel(sel.encode()), *args)
#
# Two things happen and neither is a parameter of `msg`: the RECEIVER is the
# class when `clsmeth` and the instance otherwise, and the SECOND argument is
# ALWAYS the selector, looked up by name. Measured (`shape_recv_*`, and
# `shape_receivers_differ`):
#
#   shape_instance_argc=2     a no-argument message passes receiver + selector
#
# And the ORDER, :37 is TWO C calls and the first one is not the message:
#
#   shape_call_names=sel_registerName,objc_msgSend,sel_registerName,objc_msgSend
#   own_c_call_names=sel_registerName,objc_msgSend
#
# `getsel(sel.encode())` is evaluated as an ARGUMENT, so it runs first, and
# that is why `hcq2.py:84` produces a `custom_function` for BOTH symbols and
# `cstyle.py:268` emits an `extern` for each. A device program that sent
# `objc_msgSend` but not `sel_registerName` would not even build.

def msg_recv.is_cls(m: Msg) -> Bool: Msg.clsmeth(m)

# the RECEIVER is the CLASS when `clsmeth` and the INSTANCE otherwise (:37), so
# both are inputs and the flag chooses. One input would hide the choice.
def msg_receiver(inst: U32, cls: U32, clsmeth: Bool) -> U32: Bool.pick(U32, clsmeth, cls, inst)

# the argument vector :37 builds. `slot` 0 is the receiver, 1 the selector.
def msg_args(recv: U32, sel: U32, args: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [recv, sel], args)

def msg_argv_len(args: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, args))

# THE TRACE, the seam. :37's two calls go through here, and so does `own`'s.
# `a0`/`a1`/`a2` are the three C argument slots; a selector that is not a
# pointer is carried as its registry INDEX, because Bend has no pointer and an
# address would not be stable anyway.

type Call is Data:
  Call{sym: String, a0: U32, a1: U32, a2: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32}

def Tr.of() -> Tr: Tr{Nil{}, 0}
def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next}: calls
def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next}: next

def Tr.emit(sym: String, a0: U32, a1: U32, a2: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next}: Tr{List.append(&2, Call, calls, [Call{sym, a0, a1, a2}]), U32.add(next, 1)}

# ONE MESSAGE, :37 in full. `getsel(sel.encode())` is an ARGUMENT of the send,
# so it is emitted FIRST -- `s_two_calls_order` is the row, and it is the reason
# the generated device code needs BOTH symbols. `sel_ix` is the registry index
# the send carries; `nargs` is `msg_argc`, NOT `msg_argv_len`, because a
# message with no DECLARED args declares none (:36) even though the call still
# passes a receiver and a selector.
def Tr.sel(name: String, t: Tr) -> Tr: Tr.emit(SYM_SELNAME(), 0, 0, 0, t)

def Tr.send(recv: U32, sel_ix: U32, nargs: U32, t: Tr) -> Tr:
  Tr.emit(SYM_MSGSEND(), recv, sel_ix, nargs, t)

# `msg(...)(ptr, *args)` end to end: lookup, then send, in that order.
def msg(recv: U32, +m: Msg, sel_ix: U32, t: Tr) -> Tr:
  Tr.send(recv, sel_ix, msg_argc(Msg.args(m)), Tr.sel(Msg.sel(m), t))

def s_two_calls(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# THE OWNERSHIP LATTICE, :6-23. THREE things that read alike and are not the
# same, and conflating any two of them is the classic bug in this layer:
#
#   1. the `retain` FLAG   -- a Python attribute (:9), set by `retained()`,
#                             read by `__del__`. Nothing about the refcount.
#   2. the real objc CALL -- `own()` sends `retain` (:20) and `release()` sends
#                             `release` (:15). These are MESSAGES.
#   3. the WRAPPER        -- `returns_retained` (:23) is a decorator that sets
#                             the flag on a RESULT, and it is what `msg(retain=
#                             True)` returns (:38).
#
# MEASURED: `own()` sends exactly TWO C calls (`sel_registerName` then
# `objc_msgSend`) because `msg("retain")` is itself a `msg` call, and it sets
# the flag via `retained()`. `release()` also sends two. Neither CLEARS the
# flag -- `own_release_leaves_the_flag=False` says the flag is FALSE after a
# release on a never-owned object, and nothing anywhere sets it back to False.
# There is no `unown()` in this file, which is itself the ownership story:
# a retained id_ is released exactly once, by `__del__`.

type Idr is Data:
  Idr{ptr: U32, retain: Bool}

def Idr.of(p: U32) -> Idr: Idr{p, False{}}
def Idr.ptr(r: Idr) -> U32:
  match r:
    case Idr{ptr, retain}: ptr
def Idr.retain(r: Idr) -> Bool:
  match r:
    case Idr{ptr, retain}: retain

# :12 `__eq__` -- equality is on the VALUE, never on identity. This is what
# makes `dict.fromkeys()` dedup a set of objects (:11's comment) and what makes
# a selector comparable to anything else holding the same address.
def Idr.eq(a: Idr, b: Idr) -> Bool: U32.is_eq(Idr.ptr(a), Idr.ptr(b))

# :16 `retained()` -- set the flag, return SELF. No call is sent.
def Idr.retained(r: Idr) -> Idr: Idr{Idr.ptr(r), True{}}

# :21 `own()` -- `msg("retain")(self)` then `retained()`. The message is the
# seam (`Owned.tr`); the flag is pure. The answer carries both because `own()`
# both sends a call and returns a value, and a def that only did the first
# would be a leak.
type Owned is Data:
  Owned{tr: Tr, r: Idr}

# `own()` IS `msg("retain")(self)`, so it goes through `msg` and therefore sends
# the SELECTOR LOOKUP too: two C calls, not one. Measured
# (gate_own_call_names=sel_registerName,objc_msgSend, gate_own_call_count=2).
# An earlier version emitted only the msgSend and `own_c_call_names` caught it.
def Idr.own(+r: Idr, t: Tr) -> Owned: Owned{msg(Idr.ptr(r), Msg.of("retain"), 0, t), Idr.retained(r)}

# :15 `release()` -- one message, and it does NOT touch the flag.
def Idr.release(+r: Idr, t: Tr) -> Tr: msg(Idr.ptr(r), Msg.of("release"), 0, t)

# :13-14 `__del__`: `if self.retain and not self._is_finalizing(): self.release()`.
# Both conjuncts are PARAMETERS, which is the only reason this is testable: the
# GC hook itself is WALL 2 and the DECISION is what ports.
def Idr.finalize(+r: Idr, is_finalizing: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, Bool.and(Idr.retain(r), Bool.not(is_finalizing)), Idr.release(r, t), t)

# :23 `returns_retained(f)` -- flag the RESULT. `Msg.retain` (:38) selects it.
def Owned.of(tr: Tr, +r: Idr, m: Msg) -> Owned: Owned{tr, Bool.pick(Idr, Msg.retain(m), Idr.retained(r), r)}

# THE METHOD TABLE, :69-73. `MetaSpec._addmeth` turns one autogen tuple
# `(selector, restype, [argtypes], *kwargs)` into a bound `msg`. The tuple is
# the port's `Meth`; the kwargs beyond the first three become `retain` and
# `clsmeth`, which is why a fourth element (`True`) appears in `autogen/*.py`'s
# `_methods_` lists at all.
#
# `m[1] == 'instancetype'` -> the class itself, and EVERY `a == 'instancetype'`
# in `m[2]` -> the class too. Measured (`metaspec_instancetype_arg=
# [id_,id_,ChildFake]`, `metaspec_instancetype_arg_is_the_class=True`), and the
# class is a live Python CLASS here, which is WALL 3; the port substitutes
# `CT_CLASS` for it, which is a TAG, so `msg_argtypes_none` cannot tell a
# faithful `CT_CLASS` from a wrong one. Said here rather than hidden.

type Meth is Data:
  Meth{sel: String, ret: U32, args: List<&2, U32>, retain: Bool, clsmeth: Bool}

def Meth.of(sel: String, ret: U32, args: List<&2, U32>) -> Meth: Meth{sel, ret, args, False{}, False{}}
def Meth.sel(m: Meth) -> String:
  match m:
    case Meth{sel, ret, args, retain, clsmeth}: sel
def Meth.ret(m: Meth) -> U32:
  match m:
    case Meth{sel, ret, args, retain, clsmeth}: ret
def Meth.args(m: Meth) -> List<&2, U32>:
  match m:
    case Meth{sel, ret, args, retain, clsmeth}: args
def Meth.retain(m: Meth) -> Bool:
  match m:
    case Meth{sel, ret, args, retain, clsmeth}: retain
def Meth.clsmeth(m: Meth) -> Bool:
  match m:
    case Meth{sel, ret, args, retain, clsmeth}: clsmeth

# :70 -- the mangled name is the attribute name. There is nothing else to it.
def Meth.name(+m: Meth) -> String: mangle(Meth.sel(m))

# :71-72 -- the instancetype substitution. The return slot and EVERY argument
# slot, independently, and a NON-matching entry passes through untouched
# (`metaspec_named_arg_passthrough=[id_,id_,NSCoder]`).
def subst(+t: U32) -> U32: Bool.pick(U32, U32.is_eq(t, CT_INST()), CT_CLASS(), t)

def subst_list(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case t <> r: subst(t) <> subst_list(r)

# :71 `cls if m[1] == 'instancetype' else m[1]`, `*m[3:]` for the rest.
def Meth.msg(+m: Meth) -> Msg:
  Msg{Meth.sel(m), subst(Meth.ret(m)), subst_list(Meth.args(m)),
       Meth.retain(m), Meth.clsmeth(m)}

# THE INHERITANCE ORDER, :53-61 and :63-67. `MetaSpec` re-runs `_addmeth` in
# three situations, and the ORDER of :65-67 is what `inh.go` walks:
#
#   a DIRECT base's own methods, then its CLASS methods       (:65-66)
#   a base's bases first -- `_inherit` recurses BEFORE adding (:63-64)
#   and then every CHILD re-inherits from this class           (:67)
#
# :67 is the part that is easy to lose: a subclass registered on a base AFTER
# the base was populated still gets the base's methods, because setting
# `_methods_` on the base walks `cls._children_`. A port that only walked
# bases would produce a DIFFERENT method set for a diamond, and there is no
# fixture here that could tell the two apart -- `inh_diamond` records that as
# a blind spot instead of pretending to close it.
# "has this method already been added?", keyed on the MANGLED NAME -- which is
# the attribute name, so two selectors that mangle alike are ONE attribute and
# the second `setattr` wins. That collision is real (`::` and `:` both mangle
# to the empty string) and it is why the key is the name and not the selector.
def meth_seen(+out: List<&2, Meth>, +nm: String) -> Bool:
  match out:
    case Nil{}: False{}
    case Meth{sel, ret, args, retain, clsmeth} <> t:
      Bool.or(String.eq(Meth.name(Meth{sel, ret, args, retain, clsmeth}), nm), meth_seen(t, nm))

def inh.go(n: Nat, +ms: List<&2, Meth>, +out: List<&2, Meth>) -> List<&2, Meth>:
  match n:
    case 0n: out
    case 1n+m:
      match ms:
        case Nil{}: out
        case Meth{sel, ret, args, retain, clsmeth} <> t:
          inh.go(m, t, Bool.pick(List<&2, Meth>,
                                 meth_seen(out, mangle(sel)),
                                 out, List.append(&2, Meth, out, [Meth{sel, ret, args, retain, clsmeth}])))

# READING THE TRACE. Three readers and a subsequence-free index, which is all

def Call.sym(c: Call) -> String:
  match c:
    case Call{sym, a0, a1, a2}: sym
def Call.a0(c: Call) -> U32:
  match c:
    case Call{sym, a0, a1, a2}: a0
def Call.a1(c: Call) -> U32:
  match c:
    case Call{sym, a0, a1, a2}: a1
def Call.a2(c: Call) -> U32:
  match c:
    case Call{sym, a0, a1, a2}: a2

# `Tr.at` answers a `Maybe`, because an index past the end is not a slot and a
def Tr.at(t: Tr, k: U32) -> Maybe<&2, Call>:
  List.get(&2, Call, Tr.calls(t), U32.to_nat(k))

def Tr.a0(+t: Tr, k: U32) -> U32:
  Maybe.default(&2, U32, Maybe.map(&2, Call, U32, Call.a0, Tr.at(t, k)), 4294967295)

def Tr.a1(+t: Tr, k: U32) -> U32:
  Maybe.default(&2, U32, Maybe.map(&2, Call, U32, Call.a1, Tr.at(t, k)), 4294967295)

def Tr.sym_at(+t: Tr, k: U32) -> String:
  Maybe.default(&2, String, Maybe.map(&2, Call, String, Call.sym, Tr.at(t, k)), "MISSING")

def Tr.sym_ok(+t: Tr, k: U32) -> Bool:
  Maybe.is_some(&2, Call, Tr.at(t, k))

def syms.go(n: Nat, +cs: List<&2, Call>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case c <> t: syms.go(m, t, List.append(&2, String, acc, [Call.sym(c)]))

def Tr.syms(+t: Tr) -> List<&2, String>: syms.go(U32.to_nat(Tr.next(t)), Tr.calls(t), Nil{})

# THE GATE. `r` prints `nm = [got]   py=[want]`, so the differ reads BOTH sides
# off one line and a hand-typed want is visible as a mismatch rather than as an
# absence.
#
# the derived row.  The `py=` half is the port's own value, read through the same
#
# the teeth MOVE, and WHERE they MOVE is the point.  a derived row's two halves
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its 123 rows are compared against `gates/objc-oracle.py` by
# `gates/lanewitness-gate.py`, which runs this DRIVER for the lane -- so the
# comparison follows the rows, and the oracle stays where it is.
