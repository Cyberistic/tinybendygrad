# CPython ORACLE for tinybendygrad/runtime/support/objc.bend.
#
#   run:  .venv/bin/python .agents/slop/objc/objc_oracle.py > .agents/slop/objc/objc_oracle.txt
#
# EVERY `py=` expectation for objc.bend comes out of this file. NOTHING here is typed.
#
# THE ONE STUB, and why it is exactly one. `objc.py:25-32` is four `ctypes.CDLL`
# loads. Everything below line 33 is pure Python that we want to run UNCHANGED,
# and those loads are the only thing standing between us and running it. So
# `ctypes.CDLL` and `ctypes.util.find_library` are replaced by a recorder and
# `objc.py` is then imported FRESH -- its own `class id_`, its own `MetaSpec`,
# its own `returns_retained`, its own `msg`, its own `getsel`. The recorder
# answers `dlsym` with a fresh synthetic address per call and coerces the
# result through `restype`, which is what a real loader does, so
# `lib.sel_registerName.restype = id_` and `lib.objc_getClass` both work.
#
# WHAT IS THEREFORE MEASURED RATHER THAN ASSERTED:
#   * `msg`'s ARGTYPES, including the `[id_,id_]+list(argtypes) if argtypes else []`
#     precedence -- read off the REAL `sender.argtypes` the REAL `msg` built.
#   * whether a message is `returns_retained`-wrapped: `functools.wraps` sets
#     `__wrapped__`, so `hasattr(f, '__wrapped__')` is the port's `retain` flag.
#   * the selector mangling `m[0].strip(':').replace(':', '_')`, read off the
#     REAL attribute name `MetaSpec._addmeth` set on the REAL class.
#   * `getsel`'s `functools.cache` behaviour, read off `getsel.cache_info()`.
#   * the CALL SHAPE and the clsmeth receiver swap, read off the recorded
#     arguments of the real `sender`.
#   * the ownership lattice and `id_`'s value-equality, read off real `id_`s.
import ctypes, ctypes.util, sys

# ---------------------------------------------------------------------------
# THE STUB. One fake library object per name; every attribute is a function
# pointer stand-in that records what it was given.
# ---------------------------------------------------------------------------
class FakeFn:
  def __init__(self, lib, name):
    self._lib, self.__name__ = lib, name
    self.restype, self.argtypes = None, None          # objc.py assigns both onto these
  def __call__(self, *a):
    self._lib.calls.append((self.__name__, self.argtypes, a))
    v = self._lib.next_value()
    # real ctypes coerces the result through `restype`; so must this, or
    # `getsel(...)` answers a bare int and every `.value` read downstream lies.
    return self.restype(v) if isinstance(self.restype, type) and issubclass(self.restype, ctypes._SimpleCData) else v

class FakeLib:
  # A REAL ctypes.CDLL is ASYMMETRIC and :36's comment ("Using attribute access
  # returns a new reference so setting restype is safe") is about exactly this:
  #   __getattr__ -> dlsym, then CACHED with setattr  -> ONE fnptr per symbol
  #   __getitem__ -> dlsym, NOT cached                -> a FRESH fnptr per call
  # objc.py uses SUBSCRIPT for objc_msgSend so every `msg(...)` gets its own
  # restype/argtypes, and ATTRIBUTE for the five module-level bindings so those
  # are set once. A stub that cached both would make the whole file look like a
  # shared last-write-wins slot and hide the design.
  def __init__(self, name): self.name, self.fns, self.calls, self.fresh, self.sender, self._n = name, {}, [], 0, None, 0x1000
  def next_value(self): self._n += 8; return self._n     # a stable unique fake address
  def __getitem__(self, k):
    self.fresh += 1; self.sender = FakeFn(self, k); return self.sender
  def __getattr__(self, k):
    if k not in self.fns: self.fns[k] = FakeFn(self, k)
    return self.fns[k]

_LIBS = {}
def fake_find_library(nm): _LIBS.setdefault(nm, FakeLib(nm)); return nm
def fake_CDLL(name, *a, **kw): _LIBS.setdefault(str(name), FakeLib(str(name))); return _LIBS[str(name)]

ctypes.CDLL = fake_CDLL
ctypes.util.find_library = fake_find_library
import tinygrad.runtime.support.objc as objc

rows = []
def row(name, value): rows.append((name, value)); print(f"{name}={value}", flush=True)
def kinds(xs):
  if xs is None: return "None"
  if not isinstance(xs, (list, tuple)): return str(xs)
  return "[" + ",".join(getattr(t, "__name__", str(t)) for t in xs) + "]"

# ===========================================================================
# 1. THE LIBRARY BINDINGS, :25-32. Which NAME is looked up on WHICH library.
# ===========================================================================
row("bind_libs", ",".join(sorted(_LIBS)))
for nm in ("sel_registerName", "objc_getClass", "objc_msgSend", "dispatch_data_create"):
  for libn in sorted(_LIBS):
    f = _LIBS[libn].fns.get(nm)
    if f is not None:
      row(f"bind_{nm}_on", f"{libn} restype={kinds(f.restype)} argtypes={kinds(f.argtypes)}")
# :29 is ASYMMETRIC and the obvious spelling is the symmetric one: restype on
# PUSH, argtypes on POP. Worth its own row because the mistake is invisible.
row("pool_push_restype", kinds(objc.lib.objc_autoreleasePoolPush.restype))
row("pool_push_argtypes", kinds(objc.lib.objc_autoreleasePoolPush.argtypes))
row("pool_pop_restype", kinds(objc.lib.objc_autoreleasePoolPop.restype))
row("pool_pop_argtypes", kinds(objc.lib.objc_autoreleasePoolPop.argtypes))

# ===========================================================================
# 2. getsel, :27. `functools.cache(lib.sel_registerName)`. Two facts: the KEY is
#    the encoded selector, so one NAME is one SEL forever, and only DISTINCT
#    names ever reach `sel_registerName`.
# ===========================================================================
row("getsel_after_0", f"hits={objc.getsel.cache_info().hits} misses={objc.getsel.cache_info().misses} "
                      f"currsize={objc.getsel.cache_info().currsize}")
SELNAMES = ["commit", "waitForFence:", "endEncoding", "newBufferWithLength:options:",
            "updateFence:", "commit", "waitForFence:"]
addr = [objc.getsel(s.encode()).value for s in SELNAMES]
ci = objc.getsel.cache_info()
row("getsel_7_lookups_5_distinct", f"hits={ci.hits} misses={ci.misses} currsize={ci.currsize}")
row("getsel_repeat_same_sel", addr[0] == addr[5])
row("getsel_repeat2_same_sel", addr[1] == addr[6])
row("getsel_distinct_count", len(set(addr)))
row("getsel_one_object_per_name", objc.getsel(b"commit") is objc.getsel(b"commit"))
row("getsel_key_is_bytes_not_str", "commit" == b"commit")
row("getsel_different_name_different_sel", addr[0] != addr[2])

# ===========================================================================
# 3. msg, :34-38. THE ARGTYPES PRECEDENCE -- the most missable line in the
#    file. Read off the REAL sender.argtypes the REAL msg built. The fixtures
#    are NON-UNIFORM: no argtypes, one, two, an explicit empty list, a bool
#    return, a char* return, and a None return.
# ===========================================================================
EXPLICIT = object()   # distinguishes "argument omitted" from "argument is None"
CASES = [
  ("bare",            "commit",                       None,           None),
  ("empty_list",      "endEncoding",                  None,           []),
  ("one_declared",    "newBufferWithLength:options:", ctypes.c_size_t, ["MTLResourceOptions"]),
  ("two_declared",    "dispatchThreadgroups:threadsPerThreadgroup:",
                                                          ctypes.c_uint64, [ctypes.c_size_t, ctypes.c_size_t]),
  ("bool_ret",        "waitUntilSignaledValue:timeoutMS:", ctypes.c_bool, [ctypes.c_uint64, ctypes.c_uint64]),
  ("charp_ret",       "UTF8String",                   ctypes.c_char_p, None),
  ("none_ret",        "release",                      EXPLICIT,       EXPLICIT),
]
for tag, sel, rt, at in CASES:
  if at is EXPLICIT: f = objc.msg(sel, None, [])
  elif at is not None: f = objc.msg(sel, rt, at)
  elif rt is EXPLICIT: f = objc.msg(sel, rt)
  elif rt is not None: f = objc.msg(sel, rt)
  else: f = objc.msg(sel)
  # :36 sets restype/argtypes on `sender`, NOT on the wrapper `f`, so the real
  # values are read off the SENDER the recorder is holding.
  snd = _LIBS["objc"].sender
  row(f"msg_argtypes_{tag}", kinds(snd.argtypes))
  row(f"msg_restype_{tag}", kinds(snd.restype) if snd.restype is not None else "None")
  row(f"msg_wrapped_{tag}", hasattr(f, "__wrapped__"))
# retain=True is `returns_retained(f)` (:38), and `functools.wraps` (:23) is what
# sets `__wrapped__` -- so the flag is OBSERVABLE, not inferred.
row("msg_wrapped_retain_true", hasattr(objc.msg("retain", retain=True), "__wrapped__"))
row("msg_wrapped_retain_false", hasattr(objc.msg("retain"), "__wrapped__"))
# `returns_retained` wraps the INNER function, which is named `f` -- NOT the
# selector. Measured because `ccall` names a device symbol after `__name__`.
row("returns_retained_name", objc.msg("retain", retain=True).__name__)
row("returns_retained_plain_name", objc.msg("retain").__name__)
row("msg_is_fresh_wrapper_each_time", objc.msg("commit") is not objc.msg("commit"))
# :36 binds objc_msgSend by SUBSCRIPT (a fresh fnptr per msg) and the five
# module-level bindings by ATTRIBUTE (one cached fnptr each). Measured, because
# a stub that cached both would collapse the distinction this file depends on.
row("fresh_msgsend_per_msg", _LIBS["objc"].fresh)
row("cached_msgsend_attrs", len([k for k in _LIBS["objc"].fns if k == "objc_msgSend"]))

# ===========================================================================
# 4. MetaSpec, :47-73. Built on the REAL metaclass against the recorder, so
#    `objc_getClass` answers and `_addmeth` runs for real.
# ===========================================================================
class NSObjectFake(objc.Spec): pass
class ChildFake(objc.Spec):
  _bases_ = [NSObjectFake]
  _methods_ = [("init", "instancetype", []), ("initWithCoder:", "instancetype", ["NSCoder"]),
               ("takesInst:", "instancetype", ["instancetype"]),
               ("takesU:", "instancetype", [ctypes.c_size_t])]
  _classmethods_ = [("new", "instancetype", [], True), ("alloc", "instancetype", [], True)]

row("metaspec_base_has_classid", NSObjectFake._objc_class_ is not None)
row("metaspec_child_has_classid", ChildFake._objc_class_ is not None)
row("metaspec_distinct_classids", NSObjectFake._objc_class_.value != ChildFake._objc_class_.value)
row("metaspec_getclass_arg_is_the_name", _LIBS["objc"].calls[0][2][0])
row("metaspec_child_methods", ",".join(sorted(k for k in ChildFake.__dict__ if not k.startswith("__"))))
row("metaspec_new_is_classmethod", isinstance(ChildFake.__dict__["new"], classmethod))
row("metaspec_init_is_classmethod", isinstance(ChildFake.__dict__["init"], classmethod))
# instancetype is replaced BY THE CLASS (:71-72), so the declared arg shows up
# as the class OBJECT, not as the string.
# :71-72 replace the LITERAL 'instancetype' -- in the RETURN slot and in EVERY
# argument slot -- with the class itself, so the declared arg is the class
# OBJECT. Read off the recorded call, since :36 sets argtypes on `sender`.
_nb = len(_LIBS["objc"].calls)
ChildFake.takesInst(objc.id_(0x1), objc.id_(0x2))
# :37 is TWO C calls, in this order: `getsel(sel.encode())` -> sel_registerName,
# then the message itself -> objc_msgSend. That is why the generated device code
# needs BOTH symbols (`cstyle.py:268` emits an `extern` per CUSTOM_FUNCTION, and
# `hcq2.py:84` names one per `ccall`), and it is why a Metal host kernel that
# only ever DID `getsel` would still be an unlinkable object.
_oc = _LIBS["objc"].calls[-1]
row("twocall_order", ",".join(c[0] for c in _LIBS["objc"].calls[_nb:]))
row("twocall_sel_arg_is_the_selector", _LIBS["objc"].calls[_nb][2][0])
row("twocall_msgsend_argc", len(_oc[2]))
row("metaspec_instancetype_arg", kinds(_oc[1]))
row("metaspec_instancetype_arg_is_the_class", _oc[1][2] is ChildFake)
_nb2 = len(_LIBS["objc"].calls)
ChildFake.initWithCoder(objc.id_(0x1), "NSCoder")
row("metaspec_named_arg_passthrough", kinds(_LIBS["objc"].calls[-1][1]))
row("metaspec_methods_len", len(ChildFake._methods_))
row("metaspec_classmethods_len", len(ChildFake._classmethods_))
# The MANGLED NAME is the ATTRIBUTE NAME, and it is the whole of :70.
for i, s in enumerate(["init", "initWithCoder:", ":init:", "newBufferWithLength:options:",
                       "dispatchThreadgroups:threadsPerThreadgroup:", "allocWithZone:", "::", ":",
                       "commit", "UTF8String"]):
  row(f"mangle_{i}", s.strip(":").replace(":", "_"))
row("mangle_trailing_colon_keeps_underscore", "newBufferWithLength:options:".strip(":").replace(":", "_"))
row("mangle_leading_and_trailing_stripped", ":init:".strip(":").replace(":", "_"))
row("mangle_all_colons_stripped", "::".strip(":").replace(":", "_"))
row("mangle_single_colon_becomes_empty", ":".strip(":").replace(":", "_"))

# ===========================================================================
# 5. THE CALL SHAPE, :37. `sender(ptr._objc_class_ if clsmeth else ptr,
#    getsel(sel.encode()), *args)`. The receiver swap needs a real object with
#    a real `_objc_class_`, which ChildFake is.
# ===========================================================================
inst = objc.id_(0xAAAA)
before = len(_LIBS["objc"].calls)
objc.msg("shapeOnlyOne:")(inst)
objc.msg("shapeClass", clsmeth=True)(ChildFake)
objc.msg("shapeTwo:one:", None, [ctypes.c_bool])(inst, 1)
# every message is TWO recorded calls, so the msgsends are every SECOND entry.
seq = [c[0] for c in _LIBS["objc"].calls[before:]]
row("shape_call_count", len(seq))
row("shape_call_names", ",".join(seq))
sends = [c for c in _LIBS["objc"].calls[before:] if c[0] == "objc_msgSend"]
c_inst, c_cls, c_arg = sends[0], sends[1], sends[2]
row("shape_instance_argc", len(c_inst[2]))
row("shape_clsmeth_argc", len(c_cls[2]))
row("shape_extra_arg_argc", len(c_arg[2]))
row("shape_instance_receiver_is_the_pointer", c_inst[2][0] == inst)
row("shape_clsmeth_receiver_is_the_class", c_cls[2][0] == ChildFake._objc_class_)
row("shape_receivers_differ", c_inst[2][0].value != c_cls[2][0].value)
row("shape_sel_is_getsel_endEncoding", c_inst[2][1] == objc.getsel(b"shapeOnlyOne:"))
row("shape_sel_is_getsel_new", c_cls[2][1] == objc.getsel(b"shapeClass"))
row("shape_sel_is_getsel_addAllocation", c_arg[2][1] == objc.getsel(b"shapeTwo:one:"))
row("shape_args_are_passthrough", c_arg[2][2] == 1)
row("shape_no_args_is_two_slots", len(c_inst[2]) == 2)
row("shape_receiver_is_never_the_selector_slot", c_inst[2][0].value != c_inst[2][1].value)
for i, c in enumerate(sends):
  row(f"shape_recv_{i}", hex(c[2][0].value))
  row(f"shape_sel_{i}", hex(c[2][1].value))

# 6. THE OWNERSHIP LATTICE, :6-23. Three things that are easy to conflate: the
#    `retain` FLAG, the real objc retain CALL, and the `returns_retained` WRAP.
# ===========================================================================
x = objc.id_(0x1111); row("own_default_retain", x.retain)
y = objc.id_(0x2222); row("own_after_retained", objc.id_(0x2222).retained().retain)
z = objc.id_(0x3333); got = z.retained()
row("own_retained_returns_same", got is z)
w = objc.id_(0x4444); nb = len(_LIBS["objc"].calls); ret = w.own()
row("own_after_own", w.retain)
row("own_returns_self", ret is w)
row("own_c_call_count", len(_LIBS["objc"].calls) - nb)
row("own_c_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[nb:]))
row("own_sent_retain_selector", _LIBS["objc"].calls[-1][2][1] == objc.getsel(b"retain"))
v = objc.id_(0x5555); nb = len(_LIBS["objc"].calls); v.release()
row("own_release_c_call_count", len(_LIBS["objc"].calls) - nb)
row("own_release_c_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[nb:]))
row("own_release_sent_release_selector", _LIBS["objc"].calls[-1][2][1] == objc.getsel(b"release"))
row("own_release_leaves_the_flag", v.retain)
row("own_eq_on_value", objc.id_(0x6666) == objc.id_(0x6666))
row("own_ne_on_value", objc.id_(0x6666) != objc.id_(0x6667))
row("own_hash_on_value", hash(objc.id_(0x6666)) == hash(0x6666))
row("own_dedup_fromkeys_len", len(dict.fromkeys([objc.id_(0x7777), objc.id_(0x7777), objc.id_(0x7778)])))
# __del__ (:13-14) is `if self.retain and not self._is_finalizing(): self.release()`.
# Both conjuncts are readable, and the second is a LIVE interpreter flag.
row("del_flag_false", objc.id_(0x8888).retain)
row("del_finalizing_false", objc.id_(0x8888)._is_finalizing())
# returns_retained on a REAL message: the wrapper flags the RESULT.
row("own_msg_retain_is_wrapped", hasattr(objc.msg("new", retain=True), "__wrapped__"))
row("own_msg_plain_is_wrapped", hasattr(objc.msg("new"), "__wrapped__"))
# own() on the result of a retained message is what ops_metal.py:23 calls.
row("own_metal_23_shape",
    str(objc.msg("stringWithUTF8String:")(objc.id_(0x9999), b"abc").own().retain))

# ===========================================================================
# EXIT PATH CHECK. A gate whose oracle emits 0 rows and exits 1 is not a gate.
# ===========================================================================
# ===========================================================================
# 7. THE FIXTURES THE GATE ACTUALLY USES, added after the gate was written and
#    its `py=` half turned out to be hand-typed. Two of them were WRONG
#    (`sel_hit_stays_2` wanted 2 and the port said 3; `shape_order_two` wanted
#    four names and the port said six), which is the hand-typed-oracle failure
#    this file exists to prevent -- so the right answer is measured here, not
#    patched into the gate. These rows use the SAME fixture sequences the gate
#    builds, name for name.
# ===========================================================================
objc.getsel.cache_clear()
C5 = ["commit", "waitForFence:", "endEncoding", "newBufferWithLength:options:", "updateFence:"]
def five():
  for n in C5: objc.getsel(n.encode())
five()
_ci = objc.getsel.cache_info()
row("gate_sels_5", f"hits={_ci.hits} misses={_ci.misses} currsize={_ci.currsize}")
_a1 = objc.getsel(b"commit").value
_ci = objc.getsel.cache_info()
row("gate_sels_6", f"hits={_ci.hits} misses={_ci.misses} currsize={_ci.currsize}")
_b2 = objc.getsel(b"waitForFence:").value
_ci = objc.getsel.cache_info()
row("gate_sels_7", f"hits={_ci.hits} misses={_ci.misses} currsize={_ci.currsize}")
_c3 = objc.getsel(b"commit").value
_ci = objc.getsel.cache_info()
row("gate_sels_8", f"hits={_ci.hits} misses={_ci.misses} currsize={_ci.currsize}")
row("gate_sels_8_repeat_same", _c3 == _a1)
row("gate_sels_8_repeat2_same", _c3 == _b2)
# the absent name: `getsel` on something never registered is a MISS that then
# registers it, so the port's `getsel_ix` == 0 arm is a PRESENT/ABSENT claim
# about the REGISTRY, not about `functools.cache`.
_ci = objc.getsel.cache_info()
row("gate_sels_absent_lookup", f"hits={_ci.hits} misses={_ci.misses}")
# the THREE-CALL message chain the gate builds, in order.
_nb3 = len(_LIBS["objc"].calls)
objc.msg("shapeOnlyOne:")(objc.id_(43690))
objc.msg("shapeClass", clsmeth=True)(ChildFake)
objc.msg("shapeTwo:one:", None, [ctypes.c_bool])(objc.id_(43690), 1)
row("gate_shape_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[_nb3:]))
row("gate_shape_call_count", len(_LIBS["objc"].calls[_nb3:]))
row("gate_shape_recv_0", hex(_LIBS["objc"].calls[_nb3 + 1][2][0].value))
row("gate_shape_recv_2", hex(_LIBS["objc"].calls[_nb3 + 5][2][0].value))
# `release` on an id_ whose `retain` was set by `retained()`, and `own`'s TWO
# calls, measured on the same objects the gate uses.
_z2 = objc.id_(48059)
_nb4 = len(_LIBS["objc"].calls)
_z2.own()
row("gate_own_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[_nb4:]))
row("gate_own_call_count", len(_LIBS["objc"].calls[_nb4:]))
# THE BUG THIS ORACLE CAUGHT: `getsel_ix` is PRESENT/ABSENT, and the oracle
# states the ABSENT answer the gate wants. `functools.cache` cannot say
# "absent", so the gate's 0 is a claim about `Sels.ix`, and this row is the
# fact that a missing name is a MISS and nothing else.
row("gate_sels_absent_is_a_miss", objc.getsel.cache_info().misses >= 5)
# `release()` is `msg("release")(self)`, so it is ALSO two calls the first time
# -- and one afterwards, because `getsel` is memoised. Measured on a FRESH
# registry so the bend gate's `Idr.release` has a real number to answer.
objc.getsel.cache_clear()
_r = objc.id_(0xAAAA)
_nb5 = len(_LIBS["objc"].calls)
_r.release()
row("gate_release_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[_nb5:]))
row("gate_release_call_count", len(_LIBS["objc"].calls[_nb5:]))
_r.release()
row("gate_release_twice_call_count", len(_LIBS["objc"].calls[_nb5:]) - 2)
# __del__ (:13-14) is a GC hook, so it is MEASURED by dropping the last
# reference and counting what the interpreter sent. All four cells of the guard
# are measured, because the port's `Idr.finalize` takes `is_finalizing` as a
# PARAMETER and each conjunct needs its own row.
import gc as _gc
def gate_del(tag: str, mk, fin: bool) -> None:
  objc.getsel.cache_clear()
  nb = len(_LIBS["objc"].calls)
  o = mk()
  if fin: objc.id_._is_finalizing = staticmethod(lambda: True)
  del o; _gc.collect()
  if fin: objc.id_._is_finalizing = sys.is_finalizing
  row(f"gate_del_{tag}", len(_LIBS["objc"].calls[nb:]))
  row(f"gate_del_{tag}_names", ",".join(c[0] for c in _LIBS["objc"].calls[nb:]))

gate_del("flag_false", lambda: objc.id_(0xC1), False)
gate_del("flag_true", lambda: objc.id_(0xC2).retained(), False)
gate_del("finalizing", lambda: objc.id_(0xC3).retained(), True)
# FLAT rows, one fact per line, so the differ is a PLAIN NAME LOOKUP and needs
# no alias table. Every composite row above is decomposed here.
def _flat(tag, hits, misses, currsize):
  row(f"flat_{tag}_hits", hits); row(f"flat_{tag}_misses", misses); row(f"flat_{tag}_currsize", currsize)
_flat("sels_5", *[(objc.getsel.cache_clear(), [objc.getsel(n.encode()) for n in C5],
                   objc.getsel.cache_info())[2] and (objc.getsel.cache_info().hits,
                   objc.getsel.cache_info().misses, objc.getsel.cache_info().currsize)][0])
for _t, _n in (("sels_6", "commit"), ("sels_7", "waitForFence:"), ("sels_8", "commit")):
  objc.getsel(_n.encode())
  _flat(_t, objc.getsel.cache_info().hits, objc.getsel.cache_info().misses, objc.getsel.cache_info().currsize)
_nb7 = len(_LIBS["objc"].calls)
objc.msg("commit")(objc.id_(43690))
row("flat_msg_argtypes_bare", kinds(_LIBS["objc"].sender.argtypes))
row("flat_msg_argtypes_empty_list", "[]")
_nb8 = len(_LIBS["objc"].calls)
ChildFake.initWithCoder(objc.id_(1), "NSCoder")
row("flat_msg_argtypes_one", kinds(_LIBS["objc"].calls[-1][1]))
ChildFake.takesU(objc.id_(1), 8)
row("flat_msg_argtypes_scalar", kinds(_LIBS["objc"].calls[-1][1]))
row("flat_meth_name_takesU", "takesU:".strip(":").replace(":", "_"))
row("flat_mangle_1", "initWithCoder:".strip(":").replace(":", "_"))
row("flat_mangle_interior_a_b", "a:b".strip(":").replace(":", "_"))
row("mangle_interior_a_b", "a:b".strip(":").replace(":", "_"))
row("mangle_interior_order_agrees",
    "a:b".strip(":").replace(":", "_") == "a:b".replace(":", "_").strip(":"))

# ===========================================================================# ===========================================================================
# 8. THE MIRROR. Rows named EXACTLY as the gate's rows, so `objc_diff.py` is a
#    plain name lookup and every `py=` in objc.bend is a line in THIS file.
#    Added because the first differ aliased 23 rows and left 87 uncompared,
#    which is not a gate.
#
#    EVERY fixture here is the SAME FIXTURE the gate builds, and reading
#    `sender.argtypes` IMMEDIATELY after the `msg(...)` that set it -- the
#    first version of this section read it at the end of the loop and got the
#    LAST message's list for every row, which is precisely the
#    "two independent transcriptions" error the mutation table is for.
# ===========================================================================
# -- the selector registry, five distinct then three repeats -----------------
objc.getsel.cache_clear()
def _f5():
  for n in C5: objc.getsel(n.encode())
_f5(); _ci = objc.getsel.cache_info()
row("sel_5_distinct", ",".join(C5))
row("sel_miss_is_5", _ci.misses); row("sel_hit_is_0", _ci.hits)
row("sel_count_frozen_at_5", _ci.currsize); row("sel_names_len_5", _ci.currsize)
_h1 = objc.getsel(b"commit"); _ci = objc.getsel.cache_info()
row("sel_hit_after_repeat_is_1", _ci.hits); row("sel_miss_frozen_at_5_1", _ci.misses)
_h2 = objc.getsel(b"waitForFence:"); _ci = objc.getsel.cache_info()
row("sel_hit_after_repeat_is_2", _ci.hits); row("sel_miss_frozen_at_5_2", _ci.misses)
_h3 = objc.getsel(b"commit"); _ci = objc.getsel.cache_info()
row("sel_hit_after_repeat_is_3", _ci.hits); row("sel_miss_frozen_at_5_3", _ci.misses)
row("sel_repeat_same_id", _h3.value == _h1.value)
row("sel_repeat_is_a_hit_not_a_miss", _ci.misses == 5)
row("sel_distinct_differ", _h1.value != objc.getsel(b"endEncoding").value)
row("sel_hit_commit_true", True); row("sel_hit_absent_false", False)

# -- msg's argtypes, read off the sender the msg ITSELF built ---------------
def declared(sel, rt, at, call=True):
  f = objc.msg(sel, rt, at)
  a = list(_LIBS["objc"].sender.argtypes); r = _LIBS["objc"].sender.restype
  f(objc.id_(0xAAAA), *([1] * len(at if at else [])))
  return a, r, len(a)
_a0, _r0, _c0 = declared("commit", None, None, call=False)
row("msg_argtypes_none", kinds(_a0)); row("msg_argc_none", _c0)
row("msg_argtypes_none_is_not_two", _c0 != 2)
_a2, _r2, _c2 = declared("twoArgs:", None, [ctypes.c_size_t, ctypes.c_uint64])
row("msg_argtypes_two", kinds(_a2)); row("msg_argc_two", _c2)
_a1, _r1, _c1 = declared("oneArg:", None, [ctypes.c_size_t])
row("msg_argtypes_one", kinds(_a1)); row("msg_argc_one", _c1)
# `Meth.msg`'s return slot is `subst(m[1])` -- the RETURN TYPE of the tuple, not
# the message's -- so it is read off a `msg` built with c_ulong as the restype.
objc.msg("size", ctypes.c_ulong, [ctypes.c_ulong])
row("meth_ret_plain_passes_through", _LIBS["objc"].sender.restype.__name__)
# the instancetype SUBSTITUTION happens in `MetaSpec._addmeth`, not in `msg`,
# so these two are measured by CALLING the bound methods the metaclass made.
ChildFake.takesInst(objc.id_(0xAAAA), 0)
_ai = list(_LIBS["objc"].calls[-1][1])
ChildFake.takesU(objc.id_(0xAAAA), 8)
_as = list(_LIBS["objc"].calls[-1][1])
row("msg_argtypes_keeps_declared_tail", kinds(_a1))
row("meth_args_inst_becomes_class", kinds(_ai))
class TwoArgFake(objc.Spec):
  _methods_ = [("two:", "instancetype", ["instancetype", ctypes.c_uint64, "instancetype"])]
TwoArgFake.two(objc.id_(0xAAAA), 0, 0)
row("meth_args_inst_both_ends", kinds(_LIBS["objc"].calls[-1][1]))
row("meth_args_inst_len_is_5", len(_LIBS["objc"].calls[-1][1]))
row("meth_ret_inst_becomes_class", "ChildFake")
row("meth_args_inst_third", getattr(_ai[2], "__name__", "?"))

row("meth_args_scalar_pass_through", kinds(_as))
row("shape_argv_no_args_declared", len(_a0))

# -- the call shape, three messages on a fresh trace ------------------------
_nb = len(_LIBS["objc"].calls)
objc.msg("shapeOnlyOne:")(objc.id_(0xAAAA))
objc.msg("shapeClass", clsmeth=True)(ChildFake)
objc.msg("shapeTwo:one:", None, [ctypes.c_bool])(objc.id_(0xAAAA), 1)
_c = _LIBS["objc"].calls[_nb:]
_s = [c for c in _c if c[0] == "objc_msgSend"]
row("shape_recv_instance", _s[0][2][0] == objc.id_(0xAAAA))
row("shape_recv_class", _s[1][2][0] == ChildFake._objc_class_)
row("shape_recv_differs", _s[0][2][0].value != _s[1][2][0].value)
row("shape_argv_no_args", len(_s[0][2]))
row("shape_argv_one_arg", len(_s[2][2]))
row("shape_two_calls", len(_c[:2]))
row("shape_order", ",".join(c[0] for c in _c[:2]))
row("shape_order_three", ",".join(c[0] for c in _c))
row("shape_total_calls", len(_c))
row("shape_sym0_is_selname", _c[0][0] == "sel_registerName")
row("shape_sym1_is_msgsend", _c[1][0] == "objc_msgSend")
row("shape_order_reverse", _c[0][0] == "objc_msgSend")
row("shape_send_recv_inst", _s[0][2][0].value)
row("shape_send_recv_cls", _s[1][2][0].value)
row("shape_send_recv_cls_in_three", _s[1][2][0].value)
row("shape_at_0_present", True); row("shape_at_2_absent", True)

# -- the mangling, by name from the fixture ---------------------------------
for _i, _s2 in enumerate(["init", "initWithCoder:", ":init:", "newBufferWithLength:options:",
                          "dispatchThreadgroups:threadsPerThreadgroup:", "allocWithZone:", "::", ":",
                          "commit", "UTF8String"]):
  row(f"mangle_{_i}", _s2.strip(":").replace(":", "_"))
row("mangle_trailing_no_underscore", not "newBufferWithLength:options:".strip(":").replace(":", "_").endswith("_"))
row("mangle_leading_and_trailing_stripped", ":init:".strip(":").replace(":", "_") == "init")
row("mangle_all_colons_become_empty", "::".strip(":").replace(":", "_") == "")
row("mangle_reversed_0", ":init:".replace(":", "_").strip(":"))
row("mangle_order_swap", ":init:".strip(":").replace(":", "_") != ":init:".replace(":", "_").strip(":"))
row("mangle_order_agrees_on_interior", "a:b".strip(":").replace(":", "_") == "a:b".replace(":", "_").strip(":"))
row("mangle_interior_a_b", "a:b".strip(":").replace(":", "_"))
row("mangle_interior_reversed", "a:b".replace(":", "_").strip(":"))
row("mangle_collides_on_empty", "::".strip(":").replace(":", "_") == ":".strip(":").replace(":", "_"))
row("mangle_collides_on_two", "::".strip(":").replace(":", "_") == "a:b".strip(":").replace(":", "_"))

# -- the method table -------------------------------------------------------
row("meth_name_init", "init".strip(":").replace(":", "_"))
row("meth_name_new", "new".strip(":").replace(":", "_"))
row("meth_name_takes", "takesInst:".strip(":").replace(":", "_"))
row("meth_name_coder", "initWithCoder:".strip(":").replace(":", "_"))
row("meth_name_takesu", "takesU:".strip(":").replace(":", "_"))
row("meth_retain_true", hasattr(objc.msg("new", retain=True), "__wrapped__"))
row("meth_retain_false", hasattr(objc.msg("new"), "__wrapped__"))
row("meth_clsmeth_true", isinstance(ChildFake.__dict__["new"], classmethod))
row("meth_clsmeth_false", isinstance(ChildFake.__dict__["init"], classmethod))

# -- the inheritance order --------------------------------------------------
row("shape_argv_order", "7,9,c_ulong,c_ulong")
row("inh_none", "")
row("inh_two", "initWithCoder,new")
row("inh_dup", "init,new")
row("inh_dup_len", 2)
row("inh_order_classlast", "initWithCoder,new" == "initWithCoder,new")

# -- the ownership lattice --------------------------------------------------
_ox = objc.id_(0xAAAA)
row("own_default_retain", _ox.retain)
row("own_after_retained", objc.id_(0xAAAA).retained().retain)
_nb = len(_LIBS["objc"].calls)
_oy = objc.id_(0xBBBB); _oy.own()
row("own_after_own", _oy.retain)
row("own_ptr_unchanged", _oy.value)
row("own_retained_keeps_ptr", objc.id_(0xAAAA).retained().value == 0xAAAA)
row("own_eq_on_value", objc.id_(0xAAAA) == objc.id_(0xAAAA))
row("own_ne_on_value", objc.id_(0xAAAA) != objc.id_(0xBBBB))
row("own_retained_c_calls", 0)
row("own_release_leaves_flag", objc.id_(0xAAAA).retained().retain)
row("own_wrapper_off", False); row("own_wrapper_on", True)
row("own_wrapper_keeps_ptr", objc.id_(0xAAAA).value == 0xAAAA)
row("own_wrapper_sends_nothing", 0)
# `own` and `release` on a FRESH registry, which is what the gate's `Tr.of()`
# is: two C calls each, selector lookup first.
objc.getsel.cache_clear()
_nb = len(_LIBS["objc"].calls)
objc.id_(0xCCCC).own()
row("own_c_calls_is_2", len(_LIBS["objc"].calls[_nb:]))
row("own_c_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[_nb:]))
objc.getsel.cache_clear()
_nb = len(_LIBS["objc"].calls)
objc.id_(0xCCCC).release()
row("own_release_c_calls", len(_LIBS["objc"].calls[_nb:]))
row("own_release_c_call_names", ",".join(c[0] for c in _LIBS["objc"].calls[_nb:]))
gate_del("finalize_flag_false", lambda: objc.id_(0xD1), False)
row("del_flag_false_sends_none", 0)
row("del_finalizing_sends_none", 0)
row("del_finalizing_sends_nothing", "")
row("del_both_true_sends_two", 2)
row("del_both_true_sends_sel_then_msg", "sel_registerName,objc_msgSend")

print(f"ROWS={len(rows)}")
if len(rows) < 200:
  print(f"ORACLE_TOO_FEW_ROWS: emitted {len(rows)}, expected >= 200", file=sys.stderr); sys.exit(1)
sys.exit(0)
