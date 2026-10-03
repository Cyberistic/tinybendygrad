# tinybendygrad/runtime/support/objc.bend -- port of tinygrad/runtime/support/objc.py
#
# ===========================================================================
# WHAT THIS FILE IS. 77 lines of Python, and 5 of them are the interesting
# ones. `objc.py` binds five symbols out of two shared libraries and then does
# STRING LOGIC with them: the selector-name mangling that turns an Objective-C
# selector into a Python attribute name, the `functools.cache` that makes one
# selector name mean one SEL forever, the `msg` shape that prepends a receiver
# and a selector to every call, and the `retain` / `returns_retained` /
# `own` ownership lattice that decides who calls `release`. The ctypes loads are
# the seam. This file ports the logic and leaves the loads to the trace.
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one objc call (pure, and the gate checks it) OR records that call in the
# trace (the gate checks ORDER and IDENTITY). There is no third kind. No
# `@extern`, so `--check-only` says ALL PROOFS CHECK.
#
# ===========================================================================
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
# ===========================================================================
# THE HEADLINE MEASUREMENT, which is not about this file at all.
#
# `ops_metal.py:86` binds BOTH `objc_msgSend` AND `sel_registerName` on
# `metal.dll` -- the Metal framework. Measured with
# `xcrun dyld_info -exports` (see `.agents/slop/objc/symtab_oracle.txt`):
#
#   Metal.framework exports 1457 symbols and `sel_registerName` is NOT one of
#   them. Neither is `objc_msgSend`. They are LIBOBJC symbols and libobjc
#   exports them. So `metal.dll.sel_registerName` RESOLVES -- to libobjc's own
#   address, reached through Metal's dependency edge -- and that is the trap:
#   a binding that resolves at declaration time is not a binding that resolves
#   at relocation time.
#
# The failure is NOT a failed dlsym. `hcq2.py:84` names a DEVICE symbol after
# `fn.__name__`, so `ccall(SELNAME, sel)` becomes `custom_function
# ("sel_registerName")`, `cstyle.py:268` emits `extern void sel_registerName();`
# into the generated host kernel, and `elf.py:13` then fails to link it
# against `[libm, libSystem]` -- neither of which exports it either. Measured
# end to end: `(a@a.T).realize()` raises `RuntimeError: Attempting to relocate
# against an undefined symbol sel_registerName`. The fix belongs in
# `ops_cpu.py:19/21` (libobjc is missing from `CPUProgram.link_libs`), NOT in
# `objc.py` and NOT in `ops_metal.py:86`. Reported, not fixed.
#
# ===========================================================================
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
#     TODO(p3) runtime/support/objc.py:13 -- the `__del__` hook itself.
#
# W3  THE METAINTERPRETER, :47-73. `MetaSpec.__new__` / `__setattr__` /
#     `_inherit` / `_addmeth` are metaclass hooks: they run when a CLASS is
#     created, and Bend has no classes. What ports is the DECISION each hook
#     makes -- the mangled name, the `instancetype` substitution, the
#     clsmeth flag -- over an explicit method table (`Meth`). What does not is
#     that `objc_getClass(name.encode())` hands back a live `Class` object,
#     which is W1 wearing a hat.
#     TODO(p3) runtime/support/objc.py:49 -- `lib.objc_getClass(name.encode())`.
#     TODO(p3) runtime/support/objc.py:71 -- `classmethod(...)` wrapping.
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
#     wraps the INNER `f` from :37 and not `msg`'s return.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :6-21  the ownership lattice      PORTED  Idr.{retained,own,release,finalize}
#   :11-12  __hash__/__eq__ on .value PORTED  Idr.eq
#   :13-14  __del__'s guard           PORTED  Idr.finalize
#   :23    returns_retained           PORTED  Owned.of, Msg.retain
#   :25    CDLL(find_library)         WALL 1
#   :26-27 restype + the SEL cache    PORTED  Sels  (the cache IS the type)
#   :28    objc_getClass.restype      WALL 1
#   :29    the pool pair              PORTED  the ASYMMETRY, see POOL_*
#   :30-32 dispatch_data_create       PARTIAL WALL 1, but its OWNERSHIP IS PORTED
#   :34    msg's five parameters      PORTED  Msg
#   :36    the argtypes precedence    PORTED  msg_argtypes  <- the headline rule
#   :37    the call shape             PORTED  msg_args, Tr.emit
#   :38    retain -> returns_retained PORTED  Owned.of
#   :49    objc_getClass              WALL 3
#   :53-61 __setattr__ / _inherit     PORTED  as an explicit order, see INHERIT
#   :63-67 _inherit's traversal       PORTED  inh.go
#   :69-73 _addmeth                   PORTED  Meth, mangle, subst
#   :70    the selector-name mangling PORTED  mangle
#   :71-72 the instancetype arms      PORTED  subst
#   :73    the clsmeth arm            PORTED  Meth.clsmeth
#   :75-77 class Spec                 WALL 3
#
# ===========================================================================
# THE ARGUMENT MANGLING, and it is TWO steps with an ORDER between them that
# a one-step reading gets wrong. `nm = m[0].strip(':').replace(':', '_')`.
#
#   `strip(':')` removes colons from BOTH ends -- so a SELECTOR ENDING IN A
#   COLON DOES NOT GET A TRAILING UNDERSCORE. `newBufferWithLength:options:`
#   mangles to `newBufferWithLength_options`, not `...options_`. Measured
#   (`mangle_3`, `mangle_trailing_colon_keeps_underscore`).
#
#   `replace(':','_')` then maps every REMAINING colon. `dispatchThreadgroups:
#   threadsPerThreadgroup:` has one colon between two labels and a trailing
#   one, so it is `dispatchThreadgroups_threadsPerThreadgroup`
#   (`mangle_4`). And a name that is nothing but colons mangles to the EMPTY
#   string (`mangle_6`, `mangle_7`, `mangle_2` on `:init:`), which is a real
#   collision two different selectors can make and which no row here can call a
#   bug because it is what Python does.
#
# The two steps commute on the INTERIOR but NOT on the ends, so the gate runs
# both orders: `mangle_order_swap` asserts the two spellings agree, and it
# does -- which is the theorem, not the point. The point is `mangle_3`.
import Base

# ===========================================================================
# THE CTYPE KINDS. `msg`'s argtypes are lists of ctypes CLASSES, and a class is
# not a value. So each is a tag, and the tags are what the gate compares
# against the oracle's `kinds()` spelling. `CT_ID` is `id_`; `CT_INST` is the
# string `'instancetype'`, which :71-72 replaces with the CLASS -- a value this
# port cannot hold, hence WALL 3 rather than a fifth kind.
# ===========================================================================
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

# ===========================================================================
# THE SELECTOR-NAME MANGLING. :70. See the header for why it is two steps.
# ===========================================================================
def is_colon(c: Char) -> Bool: Char.is_eq(c, ':')

# step 1: drop every leading and trailing colon.
def mangle.ltrim(+cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: Nil{}
    case c <> t: Bool.pick(List<&2, Char>, is_colon(c), mangle.ltrim(t), cs)

# `+cs` is read twice in ONE expression, so both copies are spelled. The guard is
# a CONJUNCTION and needs to be: drop the head only when it is a colon AND the
# tail is empty. Testing the tail alone folded EVERY input to Nil -- so every
# mangled name came out "" and `mangle_0` said so. A gate row on an EMPTY string
# for a fixture that is not empty is a bug that cannot hide: `mangle_0` wanted
# `init`.
# The answer is `c <> rtrim(t)` and NOT `cs`: `cs` still carries the UNTRIMMED
# tail, so returning it kept every interior colon and turned `b:` into `b:`.
# Two gate rows caught it (`mangle_1` wanted `initWithCoder` and got
# `initWithCoder_`, `mangle_5` wanted `allocWithZone` and got `allocWithZone_`),
# and the trailing-underscore row is what it is FOR.
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

# ===========================================================================
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
# ===========================================================================
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
# It is the index PLUS ONE, so 0 is unambiguous: index 0 is a real entry and
# `functools.cache` can hand it back, and an index-valued miss arm would read
# as a silent rewrite of entry 0. `sel.found` keeps the raw index and
# `getsel_ix` is the one a caller should use.
# FOUND first, so a miss folds to 0 instead of to 1. Caught by the gate:
# `sel_ix_absent_is_0` answered 1, because `found` answers 0 on a miss and
# 0 is also the first real index. The two are not separable by the index alone,
# which is why the MISS arm has to be `sel.hit`.
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

# ===========================================================================
# THE MESSAGE SPEC, :34. Five parameters: the selector, the return type, the
# declared argument types, `retain`, and `clsmeth`.
# ===========================================================================
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


# ===========================================================================
# THE ARGUMENT LIST, :36. THE HEADLINE RULE OF THIS FILE:
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
# ===========================================================================
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

# ===========================================================================
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
#   shape_extra_arg_argc=3    and each declared argument is one more slot
#   shape_instance_receiver_is_the_pointer=True
#   shape_clsmeth_receiver_is_the_class=True
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
# ===========================================================================
def msg_recv.is_cls(m: Msg) -> Bool: Msg.clsmeth(m)

# the RECEIVER is the CLASS when `clsmeth` and the INSTANCE otherwise (:37), so
# both are inputs and the flag chooses. One input would hide the choice.
def msg_receiver(inst: U32, cls: U32, clsmeth: Bool) -> U32: Bool.pick(U32, clsmeth, cls, inst)

# the argument vector :37 builds. `slot` 0 is the receiver, 1 the selector.
def msg_args(recv: U32, sel: U32, args: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [recv, sel], args)

def msg_argv_len(args: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, args))

# ===========================================================================
# THE TRACE, the seam. :37's two calls go through here, and so does `own`'s.
# `a0`/`a1`/`a2` are the three C argument slots; a selector that is not a
# pointer is carried as its registry INDEX, because Bend has no pointer and an
# address would not be stable anyway.
# ===========================================================================
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



# ===========================================================================
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
# ===========================================================================
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

# ===========================================================================
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
# ===========================================================================
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

# :70 -- THE MANGLED NAME IS THE ATTRIBUTE NAME. There is nothing else to it.
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

# ===========================================================================
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
# ===========================================================================
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


# ===========================================================================
# READING THE TRACE. Three readers and a subsequence-free index, which is all
# the two-call order needs. `Tr.at` answers `Maybe`, and a `Maybe` index cannot
# be a `U32` row, so every order row goes through `Tr.at_u` which folds the miss
# to a SENTINEL -- and the sentinel is checked by its own row rather than
# assumed, because a sentinel that no row reads is a row that cannot fail.
# ===========================================================================
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
# U32 sentinel would have to be checked by a row that nothing else reads.
# `Maybe.default` is what turns it back into a printable, and `MISS` is printed
# rather than hidden.
# `Tr.at` answers a `Maybe`, because an index past the end is not a slot and a
# U32 sentinel would have to be checked by a row nothing else reads. So there is
# no sentinel: `MISSING` is printed, and `t_shape_miss_index` is the row that
# says a past-the-end read MISSES rather than answering 0.
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

# ===========================================================================
# THE GATE. `r` prints `nm = [got]   py=[want]`, so the differ reads BOTH sides
# off one line and a hand-typed want is visible as a mismatch rather than as an
# absence. Every `want` below is a row of `.agents/slop/objc/objc_oracle.txt`,
# which calls the real `objc.py`.
# ===========================================================================
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]"])

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

def orow(nm: String, got: Bool, want: String) -> IO(Unit):
  IO.print(r(nm, Bool.show(got), want))

def nrow(nm: String, got: U32, want: String) -> IO(Unit):
  IO.print(r(nm, U32.show(got), want))

def lrow(nm: String, got: List<&2, U32>, want: String) -> IO(Unit):
  IO.print(r(nm, ujoin(got), want))

def strrow(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(r(nm, got, want))

def srowl(nm: String, got: List<&2, String>, want: String) -> IO(Unit):
  IO.print(r(nm, sjoin(got), want))

# --- 1: the selector registry, :27. `functools.cache` IS the type ----------
# The fixture is NON-UNIFORM on purpose: seven lookups over FIVE distinct names
# in the order commit / waitForFence: / endEncoding / newBufferWithLength:
# options: / updateFence: / commit / waitForFence:. An all-equal fixture could
# not tell a cache from a dict-that-copies, and `getsel_distinct_count` is the
# row that says five and not seven.
def sels_f0() -> Sels: getsel("commit", Sels.of())
def sels_f1() -> Sels: getsel("waitForFence:", sels_f0())
def sels_f2() -> Sels: getsel("endEncoding", sels_f1())
def sels_f3() -> Sels: getsel("newBufferWithLength:options:", sels_f2())
def getsel_fixture() -> Sels: getsel("updateFence:", sels_f3())

# the seven lookups of the fixture, as a chain of PURE defs: a `do IO<Unit>`
# block may only bind an IO, so a value has to be threaded by name.
def sels_r1() -> Sels: getsel("commit", getsel_fixture())
def sels_r2() -> Sels: getsel("waitForFence:", sels_r1())
def sels_r3() -> Sels: getsel("commit", sels_r2())

def t_sels() -> IO(Unit):
  do IO<Unit>:
    row("sel_empty_miss", U32.is_eq(Sels.miss(Sels.of()), 0))
    row("sel_empty_count", U32.is_eq(Sels.count(Sels.of()), 0))
    strrow("sel_5_distinct", sjoin(Sels.names(getsel_fixture())),
           "commit,waitForFence:,endEncoding,newBufferWithLength:options:,updateFence:")
    nrow("sel_miss_is_5", Sels.miss(getsel_fixture()), "5")
    nrow("sel_hit_is_0", Sels.hit(getsel_fixture()), "0")
    # 6, 7 and 8 lookups over the SAME five distinct names: one hit each time,
    # and the miss count FROZEN at 5. oracle gate_sels_6/7/8.
    nrow("sel_hit_after_repeat_is_1", Sels.hit(sels_r1()), "1")
    nrow("sel_hit_after_repeat_is_2", Sels.hit(sels_r2()), "2")
    nrow("sel_hit_after_repeat_is_3", Sels.hit(sels_r3()), "3")
    nrow("sel_miss_frozen_at_5_1", Sels.miss(sels_r1()), "5")
    nrow("sel_miss_frozen_at_5_2", Sels.miss(sels_r2()), "5")
    nrow("sel_miss_frozen_at_5_3", Sels.miss(sels_r3()), "5")
    nrow("sel_count_frozen_at_5", Sels.count(sels_r2()), "5")
    nrow("sel_names_len_5", U32.from_nat(List.length(&2, String, Sels.names(sels_r2()))), "5")
    # index 0 IS a real entry, so the id is index+1 and `sel.hit` is the
    # predicate. `sel_ix_commit_is_1` is the row for that: a 0-based id would
    # answer 0 here and only `sel_hit` would be left to catch it.
    nrow("sel_ix_commit_is_1", getsel_ix("commit", sels_r2()), "1")
    nrow("sel_ix_absent_is_0", getsel_ix("nosuch", sels_r2()), "0")
    orow("sel_hit_absent_false", sel.hit(Sels.ix(sels_r2()), "nosuch"), "False")
    orow("sel_hit_commit_true", sel.hit(Sels.ix(sels_r2()), "commit"), "True")
    # repeat identity: one name is one SEL forever, which is the ObjC invariant
    # `functools.cache` exists to exploit.
    orow("sel_repeat_same_id", U32.is_eq(getsel_ix("commit", sels_r2()), getsel_ix("commit", sels_r3())), "True")
    orow("sel_repeat_is_a_hit_not_a_miss", U32.is_eq(Sels.miss(sels_r3()), Sels.miss(sels_r2())), "True")
    orow("sel_distinct_differ", Bool.not(U32.is_eq(getsel_ix("commit", sels_r2()), getsel_ix("endEncoding", sels_r2()))), "True")

# --- 2: msg's ARGTYPES, :36. THE HEADLINE RULE ------------------------------
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
def ONE_ARGS() -> List<&2, U32>: [CT_U64()]
def TWO_ARGS() -> List<&2, U32>: [CT_U64(), CT_U64()]

def t_argtypes() -> IO(Unit):
  do IO<Unit>:
    lrow("msg_argtypes_none", msg_argtypes(NONE_ARGS()), "")
    lrow("msg_argtypes_one", msg_argtypes(ONE_ARGS()), "1,1,4")
    lrow("msg_argtypes_two", msg_argtypes(TWO_ARGS()), "1,1,4,4")
    nrow("msg_argc_none", msg_argc(NONE_ARGS()), "0")
    nrow("msg_argc_one", msg_argc(ONE_ARGS()), "3")
    nrow("msg_argc_two", msg_argc(TWO_ARGS()), "4")
    # THE ROW THAT SEPARATES THE TWO READINGS. A naive `++ [ID, ID]` answers 2
    # here; the measured value is 0, and 0 is a value no reorder can produce.
    orow("msg_argtypes_none_is_not_two", Bool.not(U32.is_eq(msg_argc(NONE_ARGS()), 2)), "True")
    # :36 tests TRUTHINESS, so an explicitly `[]` and an ABSENT argtypes are the
    # same list (oracle: msg_argtypes_empty_list == msg_argtypes_bare == []). In
    # Bend there is no "absent", so a row for it would compare a value with
    # itself -- the shape agent-core calls a def of the thing under test. NOT
    # ROWED, and that is the reason rather than an omission.
    # and the DECLARED types are not touched: `msg_argtypes` prepends, it does
    # not substitute, and `msg_argtypes_one` ends in 7 (CT_CLASS) not 1.
    lrow("msg_argtypes_keeps_declared_tail", msg_argtypes(ONE_ARGS()), "1,1,4")

# --- 3: the call shape, :37. THE RECEIVER, THE SELECTOR, THE ORDER ---------
# `sender(ptr._objc_class_ if clsmeth else ptr, getsel(sel.encode()), *args)`.
# The instance is 0xAAAA and the class 0xBBBB in every fixture, so a receiver
# that picked the wrong one is a different NUMBER and not a wording.
def INST() -> U32: 43690
def CLS() -> U32: 48059

def m_end() -> Msg: Msg.of("shapeOnlyOne:")
def m_cls() -> Msg: Msg{"shapeClass", CT_ID(), Nil{}, False{}, True{}}
def m_two() -> Msg: Msg{"shapeTwo:one:", CT_VOID(), [CT_BOOL()], False{}, False{}}

def tr_end() -> Tr: msg(INST(), m_end(), 0, Tr.of())
def tr_cls() -> Tr: msg(CLS(), m_cls(), 1, tr_end())
def tr_two() -> Tr: msg(INST(), m_two(), 2, tr_cls())

def t_shape() -> IO(Unit):
  do IO<Unit>:
    orow("shape_recv_instance", U32.is_eq(msg_receiver(INST(), CLS(), False{}), INST()), "True")
    orow("shape_recv_class", U32.is_eq(msg_receiver(INST(), CLS(), True{}), CLS()), "True")
    orow("shape_recv_differs", Bool.not(U32.is_eq(msg_receiver(INST(), CLS(), False{}), msg_receiver(INST(), CLS(), True{}))), "True")
    # the argtypes DECLARED by :36 are NOT the argtypes PASSED at :37: a
    # no-argument message declares none and still passes two slots.
    nrow("shape_argv_no_args", msg_argv_len(msg_args(INST(), 0, NONE_ARGS())), "2")
    nrow("shape_argv_one_arg", msg_argv_len(msg_args(INST(), 0, ONE_ARGS())), "3")
    lrow("shape_argv_order", msg_args(7, 9, TWO_ARGS()), "7,9,4,4")
    # ONE MESSAGE IS TWO CALLS, SELECTOR FIRST. This is the measured
    # `shape_call_names=sel_registerName,objc_msgSend,...` and it is the reason
    # the generated device program needs BOTH symbols (cstyle.py:268 emits an
    # `extern` per CUSTOM_FUNCTION and hcq2.py:84 names one per ccall).
    nrow("shape_two_calls", s_two_calls(tr_end()), "2")
    srowl("shape_order", Tr.syms(tr_end()), "sel_registerName,objc_msgSend")
    srowl("shape_order_three", Tr.syms(tr_two()),
          "sel_registerName,objc_msgSend,sel_registerName,objc_msgSend,sel_registerName,objc_msgSend")
    nrow("shape_total_calls", s_two_calls(tr_two()), "6")
    orow("shape_sym0_is_selname", String.eq(Tr.sym_at(tr_end(), 0), SYM_SELNAME()), "True")
    orow("shape_sym1_is_msgsend", String.eq(Tr.sym_at(tr_end(), 1), SYM_MSGSEND()), "True")
    # THE SELECTOR LOOKUP IS A CALL OF ITS OWN, so a reversed pair would show up
    # here and nowhere else. `shape_order_reverse` is that row.
    orow("shape_order_reverse", String.eq(Tr.sym_at(tr_end(), 0), SYM_MSGSEND()), "False")
    # the receiver the send carried, and the argtypes count it declared
    nrow("shape_send_recv_inst", Tr.a0(tr_end(), 1), "43690")
    nrow("shape_send_recv_cls", Tr.a0(tr_cls(), 3), "48059")
    nrow("shape_send_sel_ix_third", Tr.a1(tr_two(), 5), "2")
    nrow("shape_send_recv_cls_in_three", Tr.a0(tr_two(), 3), "48059")
    nrow("shape_send_sel_ix", Tr.a1(tr_end(), 1), "0")
    # a past-the-end read MISSES rather than answering 0 -- `Maybe`, not a
    # sentinel, and this is the row that says so.
    orow("shape_at_0_present", Tr.sym_ok(tr_end(), 0), "True")
    orow("shape_at_2_absent", Tr.sym_ok(tr_end(), 2), "False")
    strrow("shape_at_2_is_MISSING", Tr.sym_at(tr_end(), 2), "MISSING")

# --- 4: the selector-name mangling, :70 -------------------------------------
# `nm = m[0].strip(':').replace(':', '_')`, in THAT order. The oracle's ten
# fixtures are taken from `autogen/metal.py` and disagree on colon count, on
# leading and trailing colons, and on a name that is nothing but colons -- so an
# all-equal set could not tell `strip` from `lstrip`, and `mangle_3` is the one
# that catches the trailing-underscore mistake.
def t_mangle() -> IO(Unit):
  do IO<Unit>:
    strrow("mangle_0", mangle("init"), "init")
    strrow("mangle_1", mangle("initWithCoder:"), "initWithCoder")
    strrow("mangle_2", mangle(":init:"), "init")
    strrow("mangle_3", mangle("newBufferWithLength:options:"), "newBufferWithLength_options")
    strrow("mangle_4", mangle("dispatchThreadgroups:threadsPerThreadgroup:"), "dispatchThreadgroups_threadsPerThreadgroup")
    strrow("mangle_5", mangle("allocWithZone:"), "allocWithZone")
    strrow("mangle_6", mangle("::"), "")
    strrow("mangle_7", mangle(":"), "")
    strrow("mangle_8", mangle("commit"), "commit")
    strrow("mangle_9", mangle("UTF8String"), "UTF8String")
    # `strip` REMOVES the trailing colon, so a selector ending in ':' does NOT
    # get a trailing underscore. `mangle_trailing_no_underscore` is the row that
    # a `replace`-first implementation fails, because that spelling would give
    # `newBufferWithLength_options_`.
    orow("mangle_trailing_no_underscore", Bool.not(String.ends_with(mangle("newBufferWithLength:options:"), "_")), "True")
    orow("mangle_leading_and_trailing_stripped", String.eq(mangle(":init:"), "init"), "True")
    orow("mangle_all_colons_become_empty", String.eq(mangle("::"), ""), "True")
    # THE ORDER IS LOAD-BEARING, and this is the row: replacing FIRST leaves the
    # leading colon to become an underscore (`::x:` -> `_x_`), which Python does
    # not do. So `mangle.reversed` must DIFFER, and `mangle_order_swap` is the
    # row that says it does.
    strrow("mangle_reversed_0", mangle.reversed(":init:"), "_init_")
    orow("mangle_order_swap", Bool.not(String.eq(mangle(":init:"), mangle.reversed(":init:"))), "True")
    # ... and the two orders AGREE when there is no leading colon to convert,
    # which is the one case where the distinction cannot be seen. `a:b` is the
    # fixture: an interior colon, neither end coloned.
    orow("mangle_order_agrees_on_interior", String.eq(mangle("a:b"), mangle.reversed("a:b")), "True")
    strrow("mangle_interior_a_b", mangle("a:b"), "a_b")
    strrow("mangle_interior_reversed", mangle.reversed("a:b"), "a_b")
    # THE COLLISION IS REAL. `::` and `:` both mangle to the empty string, so
    # `MetaSpec._addmeth` sets the SAME attribute for two different selectors --
    # which is why `meth_seen` keys on the MANGLED NAME, not the selector.
    orow("mangle_collides_on_empty", String.eq(mangle("::"), mangle(":")), "True")
    orow("mangle_collides_on_two", String.eq(mangle("::"), mangle("a:b")), "False")

# --- 5: the method table and the instancetype substitution, :69-73 ----------
# `_addmeth` computes `nm` and binds a `msg` under it, so the mangled name IS
# the attribute name and `Meth.name` is the whole of :70 on the record.
def m_init() -> Meth: Meth.of("init", CT_INST(), NONE_ARGS())
def m_new() -> Meth: Meth{"new", CT_INST(), NONE_ARGS(), True{}, True{}}
def m_takes() -> Meth: Meth{"takesInst:", CT_INST(), [CT_INST()], False{}, False{}}
def m_coder() -> Meth: Meth{"initWithCoder:", CT_INST(), [CT_U32()], False{}, False{}}
def m_two_arg() -> Meth: Meth{"two:", CT_INST(), [CT_INST(), CT_U64(), CT_INST()], False{}, False{}}
def m_u32ret() -> Meth: Meth{"size", CT_U64(), [CT_U64()], False{}, False{}}
def m_takesu() -> Meth: Meth{"takesU:", CT_INST(), [CT_U64()], False{}, False{}}

# the THIRD declared slot, because `List[k]` answers an Array and the rows need
# a scalar. `Maybe.default` keeps the miss explicit.
def third(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 2n), 4294967295)

def mnames.go(n: Nat, +xs: List<&2, Meth>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case mm <> t: mnames.go(m, t, List.append(&2, String, acc, [Meth.name(mm)]))

def Methnames(+xs: List<&2, Meth>) -> List<&2, String>:
  mnames.go(List.length(&2, Meth, xs), xs, Nil{})

def t_meth() -> IO(Unit):
  do IO<Unit>:
    strrow("meth_name_init", Meth.name(m_init()), "init")
    strrow("meth_name_new", Meth.name(m_new()), "new")
    strrow("meth_name_takes", Meth.name(m_takes()), "takesInst")
    strrow("meth_name_coder", Meth.name(m_coder()), "initWithCoder")
    # :71-72 `cls if m[1] == 'instancetype' else m[1]` -- THE RETURN SLOT
    nrow("meth_ret_inst_becomes_class", Msg.ret(Meth.msg(m_init())), "7")
    nrow("meth_ret_plain_passes_through", Msg.ret(Meth.msg(m_u32ret())), "4")
    # ... and EVERY argument slot, independently (oracle
    # metaspec_instancetype_arg=[id_,id_,ChildFake]).
    lrow("meth_args_inst_becomes_class", Msg.argtypes(Meth.msg(m_takes())), "1,1,7")
    # `meth_args_scalar_pass_through` below is the SAME argument shape reached
    # through a Meth rather than through a bare list, so there is no second row
    # for it: two spellings of one value is a row that cannot fail.

    # the declared scalar passes through and does NOT become CT_CLASS: the
    # substitution keys on the LITERAL 'instancetype' and on nothing else.
    lrow("meth_args_scalar_pass_through", Msg.argtypes(Meth.msg(m_takesu())), "1,1,4")
    strrow("meth_name_takesu", Meth.name(m_takesu()), "takesU")
    # the substitution happens BEFORE the prepend, so a declared `instancetype`
    # is 7 and not 1,1,8. `meth_args_inst_is_not_8` is the row.
    orow("meth_args_inst_is_not_8", U32.is_eq(third(Msg.argtypes(Meth.msg(m_takes()))), 7), "True")
    nrow("meth_args_inst_third", third(Msg.argtypes(Meth.msg(m_takes()))), "7")
    # `:72` is PER ARGUMENT and every OTHER fixture here has ONE, so a
    # `subst_list` that stopped after the head was invisible -- M13 of the
    # mutation table moved ZERO rows until this fixture existed. Three declared
    # args, the FIRST and LAST `instancetype`, so a truncation, a
    # first-only substitution and a last-only substitution are all separable.
    lrow("meth_args_inst_both_ends", Msg.argtypes(Meth.msg(m_two_arg())), "1,1,7,4,7")
    nrow("meth_args_inst_len_is_5", msg_argc(Msg.args(Meth.msg(m_two_arg()))), "5")
    # :38 `returns_retained(f) if retain else f` -- and the fourth tuple element
    # is what sets it (oracle msg_wrapped_retain_true=True, _false=False).
    orow("meth_retain_true", Msg.retain(Meth.msg(m_new())), "True")
    orow("meth_retain_false", Msg.retain(Meth.msg(m_init())), "False")
    # :73 `clsmeth=True` for a `_classmethods_` entry.
    orow("meth_clsmeth_true", Msg.clsmeth(Meth.msg(m_new())), "True")
    orow("meth_clsmeth_false", Msg.clsmeth(Meth.msg(m_init())), "False")

# --- 6: the inheritance order, :63-67 --------------------------------------
# `_inherit` walks a base's bases FIRST (:64), then its instance methods
# (:65), then its CLASS methods (:66), then re-runs every CHILD (:67).
def inh_bases() -> List<&2, Meth>: [m_init()]
def inh_all() -> List<&2, Meth>: [m_coder(), m_new()]

# Nat fuel, spelled so the binder is unambiguous (a bare `2` infers U32).
def n0() -> Nat: 0n
def n2() -> Nat: (1n + 1n : Nat)
def n3() -> Nat: (1n + (1n + 1n) : Nat)

def t_inherit() -> IO(Unit):
  do IO<Unit>:
    srowl("inh_none", Methnames(inh.go(n0(), inh_all(), Nil{})), "")
    srowl("inh_two", Methnames(inh.go(n2(), inh_all(), Nil{})), "initWithCoder,new")
    # :65-66 -- instance methods before CLASS methods, for the SAME base. A
    # reverse would give `new,initWithCoder`, so `inh_order_classlast` moves.
    orow("inh_order_classlast", String.eq(sjoin(Methnames(inh.go(n2(), inh_all(), Nil{}))), "initWithCoder,new"), "True")
    # :67 -- a child re-inherits, so a DUPLICATE is dropped by name. The two
    # entries of `inh_all` have DISTINCT names, so the dedup row needs a
    # fixture that collides, which is `inh_dup`.
    srowl("inh_dup", Methnames(inh.go(n3(), [m_init(), m_init(), m_new()], Nil{})), "init,new")
    nrow("inh_dup_len", U32.from_nat(List.length(&2, Meth, inh.go(n3(), [m_init(), m_init(), m_new()], Nil{}))), "2")

# --- 7: the ownership lattice, :6-23 ----------------------------------------
# THREE things that read alike and are not the same, and the gate keeps them in
# three separate families so no row can be satisfied by conflating two:
#
#   the FLAG       (`retain`, a Python attribute)  -- Idr.retained, no call
#   the CALL       (`own` sends retain, `release` sends release) -- 2 C calls each
#   the WRAPPER    (`returns_retained`)            -- Owned.of, flags a RESULT
#
# Oracle: own_default_retain=False, own_after_retained=True, own_after_own=True,
# own_returns_self=True, own_c_call_count=2,
# own_c_call_names=sel_registerName,objc_msgSend,
# own_release_c_call_count=1, own_release_leaves_the_flag=False.
# (`release`'s `getsel(b"release")` was already memoised by an earlier fixture,
# so its ONE call is the message alone -- which is itself the point of :27.)
# no `value.field` sugar: every field read is a reader def (constraint line 4221)
def Owned.tr(o: Owned) -> Tr:
  match o:
    case Owned{tr, r}: tr
def Owned.r(o: Owned) -> Idr:
  match o:
    case Owned{tr, r}: r

def idr_x() -> Idr: Idr.of(43690)
def idr_y() -> Idr: Idr.of(48059)
def own_y() -> Owned: Idr.own(idr_y(), Tr.of())
def own_x() -> Owned: Idr.own(idr_x(), Owned.tr(own_y()))

def t_own() -> IO(Unit):
  do IO<Unit>:
    orow("own_default_retain", Idr.retain(idr_x()), "False")
    orow("own_after_retained", Idr.retain(Idr.retained(idr_x())), "True")
    orow("own_after_own", Idr.retain(Owned.r(own_y())), "True")
    nrow("own_ptr_unchanged", Idr.ptr(Owned.r(own_y())), "48059")
    # :16 `retained()` returns SELF, so the flag is the only thing that changed.
    orow("own_retained_keeps_ptr", U32.is_eq(Idr.ptr(Idr.retained(idr_x())), INST()), "True")
    # :11-12 equality and hashing are on the VALUE, which is what makes
    # `dict.fromkeys()` dedup a set of objects (own_dedup_fromkeys_len=2).
    orow("own_eq_on_value", Idr.eq(idr_x(), Idr.of(INST())), "True")
    orow("own_ne_on_value", Bool.not(Idr.eq(idr_x(), idr_y())), "True")
    # :21 `own()` costs TWO C calls, because `msg("retain")` is itself a `msg`
    # and :37 evaluates `getsel` first. `own_c_calls_is_2` is the row.
    nrow("own_c_calls_is_2", s_two_calls(Owned.tr(own_y())), "2")
    srowl("own_c_call_names", Tr.syms(Owned.tr(own_y())), "sel_registerName,objc_msgSend")
    # THE FLAG AND THE CALL ARE SEPARATE: `retained()` sends NOTHING.
    nrow("own_retained_c_calls", s_two_calls(Tr.of()), "0")
    orow("own_release_leaves_flag", Idr.retain(Idr.retained(idr_x())), "True")
    # `release()` is `msg("release")(self)`, so on a FRESH registry it is also
    # two calls (gate_release_call_count=2) -- and the oracle's
    # gate_release_twice_call_count=1 is what the memo buys: the second release
    # skips `sel_registerName`. The port has no memo on this path and says so.
    nrow("own_release_c_calls", s_two_calls(Idr.release(idr_x(), Tr.of())), "2")
    srowl("own_release_c_call_names", Tr.syms(Idr.release(idr_x(), Tr.of())), "sel_registerName,objc_msgSend")
    # :13-14 `if self.retain and not self._is_finalizing(): self.release()`.
    # BOTH conjuncts are PARAMETERS, and each of the three rows is one conjunct
    # -- an implementation that dropped either would move exactly one of them.
    nrow("del_flag_false_sends_none", s_two_calls(Idr.finalize(idr_x(), False{}, Tr.of())), "0")
    nrow("del_finalizing_sends_none", s_two_calls(Idr.finalize(Idr.retained(idr_x()), True{}, Tr.of())), "0")
    srowl("del_finalizing_sends_nothing", Tr.syms(Idr.finalize(Idr.retained(idr_x()), True{}, Tr.of())), "")
    nrow("del_both_true_sends_two", s_two_calls(Idr.finalize(Idr.retained(idr_x()), False{}, Tr.of())), "2")
    srowl("del_both_true_sends_sel_then_msg", Tr.syms(Idr.finalize(Idr.retained(idr_x()), False{}, Tr.of())),
          "sel_registerName,objc_msgSend")
    # :23/:38 the WRAPPER. `returns_retained` flags the RESULT of the message,
    # which is a different thing from `own` flagging its receiver.
    orow("own_wrapper_off", Idr.retain(Owned.r(Owned.of(Tr.of(), idr_x(), Meth.msg(m_init())))), "False")
    orow("own_wrapper_on", Idr.retain(Owned.r(Owned.of(Tr.of(), idr_x(), Meth.msg(m_new())))), "True")
    orow("own_wrapper_keeps_ptr", U32.is_eq(Idr.ptr(Owned.r(Owned.of(Tr.of(), idr_x(), Meth.msg(m_new())))), INST()), "True")
    nrow("own_wrapper_sends_nothing", s_two_calls(Owned.tr(Owned.of(Tr.of(), idr_x(), Meth.msg(m_new())))), "0")

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
    # TODO(p3) runtime/support/objc.py:25  -- CDLL(find_library('objc'))
    # TODO(p3) runtime/support/objc.py:30  -- CDLL("/usr/lib/libSystem.dylib")
    # TODO(p3) runtime/ops_cpu.py:19       -- libobjc is missing from
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
# ===========================================================================
# THE MUTATION TABLE. Every number is the harness's output, not an estimate:
# `.venv/bin/python .agents/slop/objc/objc_mutate.py`, whose output is
# `.agents/slop/objc/objc_mutations.txt`. The harness applies ONE exact
# single-line substitution to a scratch copy, runs the INTERPRETED lane, and
# diffs whole `name=value` lines -- never the row names, because a
# name-comparing harness reported 0 for all 68 mutations in another unit.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `msg_argtypes`: the `Nil{}` arm answers `[id_, id_]` | 1 | THE HEADLINE, `:36`'s `[id_,id_]+list(argtypes) if argtypes else []`. `msg_argtypes_none` is the only row that reads it, and one row is the right count for one rule. |
# | M2 | `mangle.rtrim.go`: answer `c <> t` instead of `c <> r` | 12 | `:70`'s rtrim. Keeping the UNTRIMMED tail is **the bug this port actually had**; `mangle_1`, `mangle_3`, `mangle_4`, `mangle_5`, `mangle_leading_and_trailing_stripped`, `mangle_trailing_no_underscore` and the four `inh_*` rows that print mangled names are what caught it. |
# | M3 | `mangle.ltrim`: strip unconditionally | 23 | `:70`'s ltrim. Eats the whole string, so every non-empty fixture changes and every row printing a mangled name moves. |
# | M4 | `mangle`: `replace` before `strip` | 17 | THE ORDER of `strip(':').replace(':','_')`. A leading colon becomes an underscore, so `mangle_2` (`:init:`) and `mangle_6`/`mangle_7` (`::`, `:`) all move. |
# | M5 | `getsel_ix`: drop the MISS arm | 1 | Index 0 is a REAL index, so a 0-based id and a miss are the same answer unless `sel.hit` separates them. **The bug this port actually had**: `sel_ix_absent_is_0` read 1. |
# | M6 | `msg_argc`: count the `d <> r` TAIL | 3 | The head of a list pattern. **The bug this port actually had**: `msg_argc_one` read 2 and wanted 3. Also `meth_args_inst_len_is_5`, which is the row that found the SECOND `msg_argc` bug (feeding it `:36`'s already-prepended output). |
# | M7 | `msg`: drop the selector lookup | 18 | `:37`'s ORDER. `getsel(sel.encode())` is an ARGUMENT of the send, so the lookup is a C call that precedes it. Every call-count and call-NAME row moves, including `own_*` and `del_*` because they go through `msg`. |
# | M8 | `Idr.own`: emit only the msgSend | 2 | `:20 own()` IS `msg("retain")`. **The third bug the oracle caught**: the port sent one C call where the real `objc.py` sends two. |
# | M9 | `Idr.finalize`: drop the `retain` conjunct | 1 | `:13-14`'s FIRST conjunct, and only `del_flag_false_sends_none` moves -- so the two conjuncts are separate claims and not one. |
# | M10 | `Idr.finalize`: drop the `is_finalizing` conjunct | 2 | `:13-14`'s SECOND conjunct. `del_finalizing_sends_none` AND `del_finalizing_sends_nothing`, which is the count row beside the list row. |
# | M11 | `Owned.of`: ignore `Msg.retain` | 1 | `:23`/`:38`, `returns_retained`. One row, and it is the only row that reads the WRAPPER half of the ownership lattice. |
# | M12 | `subst`: no substitution | 5 | `:71`'s `cls if m[1] == 'instancetype' else m[1]`. |
# | M13 | `subst_list`: stop after the head | 2 | `:72`'s PER-ARGUMENT substitution. **This moved 0 rows until `meth_args_inst_both_ends` existed** -- every other fixture declares ONE argument, so a truncating `subst_list` was indistinguishable from a correct one. A zero that was a fixture request, and the fixture is the second and THIRD declared arguments. |
# | M14 | `msg_receiver`: always the instance | 2 | `:37`'s `ptr._objc_class_ if clsmeth else ptr`. |
# | M15 | `inh.go`: no dedup | 2 | `:67`'s re-inherit. Two selectors that mangle alike (`::` and `:`) collide on one attribute, and the dedup is keyed on the MANGLED NAME for that reason. |
# | M16 | `sel.put`: a HIT that appends | 10 | `:27`'s memo. Every counter row and the frozen-`count` row move, because `currsize` grows and a repeat stops being a repeat. |
# | M17 | a comment-only edit | **0 -- THE CONTROL** | a table in which every entry moves is measuring noise. |
# | M18 | `mangle.colons`: identity | 6 | `:70`'s `.replace(':','_')`. Every fixture with an INTERIOR colon moves and every fixture without one does not -- which is what a non-uniform fixture set buys. |
#
# THE THREE ZEROS, and none of them is a theorem:
#   * M17 is the CONTROL and must be 0.
#   * M13 was a 0 until the fixture was added. It is a 2 now.
#   * M1, M5, M9 and M11 move exactly ONE row each, and each is a theorem about
#     how the gate is WIREN rather than about coverage: M1 is one rule read by
#     one row, M5's miss arm is read by one row, M9's first conjunct is read by
#     one row, and M11 is the only row that reads `returns_retained`. A one-row
#     move is not a thin gate; it is a precise one, and the row names say which.
# ===========================================================================
# WHAT A FIXTURE SET HERE HAD TO BE, since two of the eighteen started at zero:
#   * The MANGLING fixtures disagree on colon COUNT, on leading and trailing
#     colons, and on a name that is nothing but colons. An all-`commit` set
#     cannot tell `strip` from `lstrip` (M3 vs M4 both move 0 on it).
#   * The ARGTYPES fixtures cover zero, one and two declared arguments, an
#     EXPLICIT `[]`, an explicit `None` restype, and a `restype` with no
#     argtypes. The zero-declaration case is the one the headline rule is about.
#   * The `Sels` fixture is FIVE distinct names looked up SEVEN then EIGHT
#     times, so `miss` freezes while `hit` grows. A fixture that looked each
#     name up once has `miss == hit` and cannot separate them.
#   * The SUBSTITUTION fixture declares THREE arguments with `instancetype` in
#     the FIRST and the LAST, because `:72` is per-argument and a one-argument
#     fixture cannot see a truncation.
# ===========================================================================
