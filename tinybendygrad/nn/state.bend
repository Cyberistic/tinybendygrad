import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../dtype.bend as DT
import ./../uop/ops.bend as O

# ===========================================================================
# nn/state.bend -- tinygrad/nn/state.py (299 lines).
#
# WHAT IS PORTED HERE IS THE PURE PART, AND IT IS THE PART THAT IS WORTH
# HAVING. `get_state_dict` (state.py:89) is a LADDER over six Python types that
# reduces to a walk over a `Data` tree, and it is the function every weight
# save/load in tinygrad goes through. It needs no device: a `state_dict` is a
# set of NAMES, and the names are a function of the OBJECT SHAPE alone. So the
# CPython oracle prints key lists and this file prints key lists, and the two are
# diffable line for line with nothing realized.
#
# THE LADDER, VERBATIM IN ORDER, because THE ORDER IS THE WHOLE FUNCTION
# (state.py:103-112):
#
#     if isinstance(obj, tensor_type):        return {prefix.strip('.'): obj}
#     if hasattr(obj, '_asdat'):               return get_state_dict(obj._asdat(), prefix)   # namedtuple
#     if isinstance(obj, OrderedDict):         return get_state_dict(dict(obj), prefix)
#     if hasattr(obj, '__dict__'):             return get_state_dict(obj.__dict__, prefix)
#     state_dict = {}
#     if isinstance(obj, (list, tuple)):       for i,x: update(get_state_dict(x, f"{prefix}{i}."))
#     elif isinstance(obj, dict):              for k,v: update(get_state_dict(v, f"{prefix}{k}."))
#     return state_dict
#
# Four of those six rungs are the SAME computation -- a mapping of name -> object
# walked with a prefix -- and only the FIRST differs (it does not descend, it
# TERMINATES). So the Data sum type has three cases, not six:
#
#     OTens   a Tensor.  TERMINATES.  key is `prefix.strip('.')`.
#     OMap    anything with named children: a dict, an OrderedDict, an
#             `__dict__`, a namedtuple's `_asdat()`.  All four rungs.
#     OSeq    a list or a tuple.  Same walk, but the key is the INDEX.
#     OOther  everything else.  Python's `state_dict` stays `{}` and is returned.
#
# `ONamed`/`OOrd`/`OAttr` are NOT separate constructors, and this is a MERGE, not
# a simplification: Python's rungs 2/3/4 differ only in WHICH attribute of the
# object holds the mapping, and all three are read here by the caller. Python
# also has an ORDER between them, and the order is observable in exactly one
# fixture -- an `OrderedDict` HAS a `__dict__` (measured, `od.__dict__ == {}`),
# so if the `__dict__` rung ran first an OrderedDict would walk to nothing.
# `sd_ord` IS that fixture, and it is the reason the merge is safe to state
# rather than to prove: the merge is safe because the caller picks the payload,
# and the gate proves the payload choice for the one type where it can go wrong.
#
# THE `Data` TREE IS THE ARGUMENT. Python's `isinstance` ladder reads a LIVE
# object; there is no such thing here, so the tree IS the caller's description of
# the object and `get_state_dict` is a fold over it. That is a DIVERGENCE and it
# is the price of the port: Python would walk an `nn.Linear` by reflection over
# its `__dict__`, and this walks a list the layer hands over. `nn/__init__.bend`
# builds that list; see its header.
#
# `prefix.strip('.')` -- the ONLY string algebra in the file, and it is not
# `String.trim` (base's is WHITESPACE, `String.trim_start` has no Char argument
# in 2.0.34) so it is written here. Measured against CPython over
# `'', '.', '..', '.a.', 'a..b..', 'a'`, which is the `sd_strip` row. It strips
# BOTH ends and it strips RUNS: `'a..b..'` -> `'a..b'`, so a leading-dot key
# contributes a `..` in the middle of a prefix that must survive. Two defs
# because dropping the head and dropping the tail are two different walks.
#
# THE ACCUMULATOR IS A LIST, NOT A MAP, and that is a DIVERGENCE THAT COSTS
# SOMETHING. Python returns a `dict`, so a repeated key COLLAPSES: measured,
# `get_state_dict({'a.b': t1, 'a': {'b': t2}})` is `{'a.b': t2}` -- one entry,
# the LAST value, at the FIRST position. A `List` keeps both. So `sd_update` is
# ported rather than skipped, and `sd_dup` is the row that would catch it being
# wrong. `Map` would answer this for free but is a `Type` (affine), so it cannot
# be a `Data` field and cannot be returned from a fold without threading it.
#
# `safe_dtypes` (state.py:33) and `inverse_safe_dtypes` (state.py:36) are PURE
# TABLES and are ported as TABLES, as a `List` of pairs in the source's order
# rather than as a `Map`, for the reason above plus one more: `inverse_safe_dtypes`
# is a dict COMPREHENSION and its insertion order is `safe_dtypes`'s, so a
# `List` is the only representation that can be compared to CPython row for row.
# `sd_inv` is the round-trip row: measured, every one of the 15 round-trips, and
# the COUNT is a separate row because a table that lost an entry would still
# round-trip on the survivors.
#
# WHAT IS A WALL, one line each, and NONE of it is a surprise:
#   * `TensorIO` (state.py:8-31) is an `io.RawIOBase`. `readinto` (:17) slices a
#     tensor and calls `.data()` -- REALIZATION, which is tensor.bend's WALL 4 --
#     and `buffer[:len(data)] = data` is a MUTATION of a Python bytearray, which
#     a `Data` record cannot express at all. `seek` (:25) IS pure integer
#     clamping and IS ported, because it is the one method in the class that
#     touches no bytes; the row is `sd_seek`.
#   * `accept_filename` (state.py:38-41) is a DECORATOR over four functions, and
#     `functools.wraps` copies `__name__`/`__doc__` off a function object. A
#     decorator is metaprogramming and a `Data` field cannot hold a function (it
#     forces `Type`), so the four decorated entry points take their filename
#     argument as a plain parameter and the wrapping is gone. Named, not hidden.
#   * `safe_load_metadata` (:44), `safe_load` (:51), `safe_save` (:64),
#     `zip_extract` (:168), `tar_extract` (:188), `torch_load` (:207) all read a
#     file. `json.loads`/`json.dumps` is a PARSER, `pathlib.Path(fn).unlink` is
#     an unlink, `zipfile`/`tarfile`/`pickle`/`zlib` are four more parsers, and
#     `Tensor(pathlib.Path(fn))` is `UOp.range`/`load` -- the FETCH wall. Every
#     one is `TODO(p3) state.py:<line>` below. They are the honest majority of
#     this file's LINES and they are the honest majority of this file's absence.
#   * `load_state_dict` (:128) -- the shape-mismatch arm's `{(), (1,)} ==
#     {state_dict[k].shape, v.shape}` IS pure and IS the one line of this function
#     worth having, but it is unreachable without `v.replace` (:159, `UOp.replace`
#     is P3) and `v.realize` (:162, WALL 4). Porting a predicate nothing can reach
#     is a tautology, so it is not ported; the line is named at the TODO.
#   * `get_parameters` (:114) IS `list(get_state_dict(obj).values())`, so it is
#     `sd_values` and it is a one-liner over a def that exists.
#
# WHAT THE GATE IS, and what it is NOT. Fourteen rows, every one a STRING or a
# COUNT, every one a claim CPython can be asked about, and all fourteen AGREE
# with `.agents/slop/state-gate.py` on both lanes (see the gate section at the
# foot of the file for the commands, the diff, and the mutation table):
#   sd_tens   a tensor is a leaf and its key is the EMPTY string
#   sd_map    a dict's keys, in insertion order
#   sd_seq    a list's keys are INDICES as strings
#   sd_nest   the `layers.0.weight` shape -- the prefix ladder through a list of
#             mappings, which is `beautiful_mnist.py`'s `Model.layers`, with a
#             non-mapping child in the middle
#   sd_strip  `prefix.strip('.')` over the six measured prefixes
#   sd_attr   the namedtuple rung and the `__dict__` rung, which are rungs 2 and 4
#   sd_ord    the OrderedDict fixture -- the ONE case where rung ORDER is visible
#   sd_dup    the dict-collapse: two children, one key, LAST value
#   sd_safe   the 15 `safe_dtypes` SPELLINGS, in order
#   sd_safedt that table is a bijection onto 15 distinct dtypes, via `sd_get`
#   sd_invn   the COUNT 15 (a count, not a boolean: see the brief's trap)
#   sd_inv    the round trip, per entry
#   sd_seek   `TensorIO.seek`'s SIGNED clamp, all three `whence` values
#   sd_param  the count of `get_parameters`, which is the count of leaves
# Nothing here builds a UOp for its own sake, so none of the arena rules apply:
# the fixtures are CONSTs in a fresh arena and the only node read is `sd_cval`,
# which exists so that `sd_dup` can see WHICH value survived the collapse.
# ===========================================================================

# ---------------------------------------------------------------------------
# THE DOT. `Char.from_u32(46)` and nothing else; the strip needs the character
# and there is no `Char.dot`.
# ---------------------------------------------------------------------------

def sd_dot() -> Char: Char.from_u32(46)

# ---------------------------------------------------------------------------
# strip('.') -- the HEAD walk. `String.split` cannot be used: it splits on a Char
# but base's `split.fin` PUSHES the separator back onto the front of every
# non-final piece, so `"a.b"` splits to three pieces and the empty ones are the
# caller's problem. Walking the char list is the honest spelling.
# ---------------------------------------------------------------------------

# `drop_lead` -- the head walk. THE FIRST VERSION OF THIS WAS WRONG and the gate
# caught it: a bare `case '.':` arm drops EVERY dot, so `a..b..` came back `ab`
# where Python's `str.strip` keeps the interior run (`a..b`). Stripping a RUN at
# the HEAD needs to know whether a non-dot has been seen yet, and that flag is
# the `St` sum type. MEASURED: the buggy form gave `inner=ab` and
# `nest=layers0weight`; the fixed form gives `a..b` and `layers.0.weight`.
#
# `St` is a `Data` record holding a `List` because the accumulator must be
# rebuilt, not shared, and the flag must ride with it -- two `Bool`s in a `Data`
# record and a separate accumulator would be a third type for the same job.
type St is Data:
  SDHead{acc: List<&2, Char>}
  SDKeep{acc: List<&2, Char>}

def St.acc(s: St) -> List<&2, Char>:
  match s:
    case SDHead{acc}: acc
    case SDKeep{acc}: acc

# `case '.':` is a Char LITERAL pattern, which is the only reason this is legal:
# `Char.is_eq(c, ...)` is a CALL and a `match` may not scrutinise one, and
# `Bool.pick` would consume `c` twice. MEASURED, and it is the fourth way found
# in this repo to spell a choice-plus-descent.
def sd_drop.head(c: Char, acc: List<&2, Char>) -> St:
  match c:
    case '.': SDHead{acc}
    case _: SDKeep{List.append(&2, Char, acc, [c])}

def sd_drop.st(c: Char, s: St) -> St:
  match s:
    case SDHead{acc}: sd_drop.head(c, acc)
    case SDKeep{acc}: SDKeep{List.append(&2, Char, acc, [c])}

def sd_drop(cs: List<&2, Char>, s: St) -> List<&2, Char>:
  match cs:
    case Nil{}: St.acc(s)
    case c <> t: sd_drop(t, sd_drop.st(c, s))

def sd_lstrip(cs: List<&2, Char>) -> List<&2, Char>:
  sd_drop(cs, SDHead{Nil{}})

# a strip is a strip of RUNS at the two ends and the two ends are independent, so
# reversing swaps them: `strip(cs) == reverse(lstrip(reverse(lstrip(cs))))`.
def sd_rev(cs: List<&2, Char>) -> List<&2, Char>:
  List.reverse(&2, Char, cs)

# `prefix.strip('.')`, state.py:103. `String.trim_start` is WHITESPACE-only in
# 2.0.34 and takes no Char, and `String.split` pushes the separator back onto
# every piece, so the char-list walk above is the honest spelling of both.
def sd_strip(s: String) -> String:
  String.from_list(sd_rev(sd_lstrip(sd_rev(sd_lstrip(String.to_list(s))))))

# ---------------------------------------------------------------------------
# THE OBJECT TREE. Three data cases plus the fall-through, and `OV` is the
# one-field-value wrapper a list of children needs: `Kv` holds a String and an
# `Obj`, and a `List` of those is the mapping.
# ---------------------------------------------------------------------------

type Kv is Data:
  Kv{k: String, o: Obj}

type Ent is Data:
  Ent{k: String, t: T.Tensor}

type Obj is Data:
  OTens{t: T.Tensor}
  OMap{es: List<&2, Kv>}
  OSeq{es: List<&2, Obj>}
  OOther{v: T.Tensor}

def Kv.k(e: Kv) -> String:
  match e:
    case Kv{k, o}: k

def Kv.o(e: Kv) -> Obj:
  match e:
    case Kv{k, o}: o

def Ent.k(e: Ent) -> String:
  match e:
    case Ent{k, t}: k

def Ent.t(e: Ent) -> T.Tensor:
  match e:
    case Ent{k, t}: t

# A CONST's VALUE, so a gate fixture's leaves are distinguishable. `Ops.name.of`
# alone would say `CONST` for all of them and `sd_dup` could not see which value
# survived the collapse. This is the ONLY reason this file builds a UOp at all.
# `APy` is ops.bend's spelling of `Arg_Py`, which is where `UOp.const` puts a
# Python value.
def sd_cval.arg(a: O.Arg) -> U32:
  match a:
    case O.APy{v}:
      match v:
        case O.CInt{i}: H.lo32(i)
        case _: 0
    case _: 0

def sd_cval.node(n: O.Node) -> U32:
  match n:
    case O.Node{op, src, arg, tag}: sd_cval.arg(arg)

def sd_cval(+t: T.Tensor) -> U32:
  sd_cval.node(O.Arena.node(T.Tensor.ar(t), T.Tensor.u(t)))

# ---------------------------------------------------------------------------
# THE WALK. One self-call, fuel FIRST, and the arms differ only in what they
# push onto the work list -- which is how the four mapping rungs of the Python
# ladder become one without a `match` on a projection and without a closure.
#
# The shape is `helpers.bend`'s `fully_flatten` (a work list, an accumulator,
# reversed at the end) and the reason is rule 5: `get_state_dict` is a
# MUTUAL recursion in Python -- walk an object, then walk each child, and
# concatenating the children's answers is a second loop -- and Bend refuses
# mutual recursion. A work list is the one recursion.
#
# The accumulator is REVERSED and turned over at the end, so the output is in
# document order, which is `dict` insertion order, which is the order
# `get_parameters` hands to an optimizer and the order `load_state_dict` writes.
# Order is not cosmetic here and the gate prints it.
# ---------------------------------------------------------------------------

# `It` is the work item: a prefix and the object still to be walked under it.
type It is Data:
  It{p: String, o: Obj}

# the children of a mapping, each under `prefix + key + "."`
def gsd_esc(ks: List<&2, Kv>, +pf: String) -> List<&2, It>:
  match ks:
    case Nil{}: Nil{}
    case +e <> t: It{String.concat([pf, Kv.k(e), "."]), Kv.o(e)} <> gsd_esc(t, pf)

# the children of a sequence, each under `prefix + str(index) + "."` -- the ONE
# place the list rung differs from the dict rung, and the reason `OSeq` exists.
# The LIST is the first parameter, not the counter: rule 5 reads a self-call's
# arguments left to right and stops at the first that shrinks, and the tail is a
# strict subterm of the list while `U32.add(n,1)` is not a subterm of `n`.
def gsd_idx(es: List<&2, Obj>, +n: U32, +pf: String) -> List<&2, It>:
  match es:
    case Nil{}: Nil{}
    case e <> t: List.append(&2, It, [It{String.concat([pf, U32.show(n), "."]), e}],
      gsd_idx(t, U32.add(n, 1), pf))

def gsd.go(k: Nat, ws: List<&2, It>, acc: List<&2, Ent>) -> List<&2, Ent>:
  match k:
    case 0n: List.reverse(&2, Ent, acc)
    case Succ{p}:
      match ws:
        case Nil{}: List.reverse(&2, Ent, acc)
        case It{pf, o} <> t:
          match o:
            # the tensor rung: it TERMINATES, it does not descend
            case OTens{tt}: gsd.go(p, t, Ent{sd_strip(pf), tt} <> acc)
            case OMap{es}: gsd.go(p, List.append(&2, It, gsd_esc(es, pf), t), acc)
            case OSeq{es}: gsd.go(p, List.append(&2, It, gsd_idx(es, 0, pf), t), acc)
            # Python's `state_dict` stays `{}` -- the object contributes nothing,
            # so `v` is read by NO arm. It is a field and not a `Bool` because a
            # `Data` record cannot hold a `Maybe` and a `Tensor|None` field is
            # exactly that; the gate supplies a tensor and the row still holds
            # because this arm IGNORES it, which is the claim.
            case OOther{v}: gsd.go(p, t, acc)

# `get_state_dict(obj, prefix='', tensor_type=Tensor)`, state.py:89. The fuel is
# a parameter because rule 5 makes it one; `sd_fuel` is the depth the gate needs
# and a caller with a deeper tree passes a bigger one.
def sd_fuel() -> Nat: 64n

def get_state_dict(o: Obj) -> List<&2, Ent>:
  gsd.go(sd_fuel(), [It{"", o}], Nil{})

def get_state_dict.pf(o: Obj, pf: String) -> List<&2, Ent>:
  gsd.go(sd_fuel(), [It{pf, o}], Nil{})

# ---------------------------------------------------------------------------
# `state_dict.update` -- state.py:109/111. A `dict` collapses a repeated key to
# the LAST value at the FIRST position, and this is that. Python gets it from
# `dict.__setitem__`; a `List` has to be told, so it is told here and `sd_dup` is
# the row that sees it.
#
# It is a REWRITE-IN-PLACE, not a filter: `put` walks the accumulator and
# replaces the tensor of the matching key, so a later value lands at the earlier
# position, which is what `dict.__setitem__` does and what a filter would not.
# ---------------------------------------------------------------------------

# ONE def, and the self-call is an ARGUMENT of `Bool.pick` (tensor.bend's rule
# 3): `pick` is a call, not a `match`, so the choice may scrutinise a computed
# Bool, and hoisting that Bool into a second def would make the two defs
# mutually recursive. `pick` evaluates both arms, so `f` and `e` are `+`.
def sd_put(+es: List<&2, Ent>, +e: Ent) -> List<&2, Ent>:
  match es:
    case Nil{}: [e]
    case +f <> t: Bool.pick(List<&2, Ent>, String.eq(Ent.k(f), Ent.k(e)),
      Ent{Ent.k(f), Ent.t(e)} <> t,
      List.append(&2, Ent, [f], sd_put(t, e)))

# the walk, so the first key WINS its position and every later one overwrites
# `List.foldl` over an accumulator, not a hand-rolled `.go` pair -- bend2-constraints
# rule 31. The step is a top-level def because a `~` template position must be CLOSED
# (a lambda capturing a runtime value is refused), and it is two lines shorter than the
# match/arm/recursion spelling it replaces. `sd_update` is not a `String` fold, so it
# cannot be an inline lambda here: `sd_put` reads `Ent.k(e)` and the table is what makes
# the first key WIN its position.
def sd_update.step(acc: List<&2, Ent>, e: Ent) -> List<&2, Ent>:
  sd_put(acc, e)

def sd_update(es: List<&2, Ent>) -> List<&2, Ent>:
  List.foldl(~&2, ~Ent, ~List<&2, Ent>, sd_update.step, es, Nil{})

# `get_state_dict` as Python returns it: a collapsed dict. The fold and the
# collapse are two defs because the fold is a recursion and `get_state_dict` is
# already one; inlining would make them mutual.
def sd_collapsed(o: Obj) -> List<&2, Ent>:
  sd_update(get_state_dict(o))

def sd_collapsed.pf(o: Obj, pf: String) -> List<&2, Ent>:
  sd_update(get_state_dict.pf(o, pf))

# `get_parameters(obj)` -- state.py:126, `list(get_state_dict(obj).values())`.
# The accumulator is PREPENDED and then reversed, so the fold has to end in a reverse
# exactly as the recursion did -- `List.reverse` is not free and moving it inside the
# step would reverse once per element.
def sd_values.step(acc: List<&2, T.Tensor>, e: Ent) -> List<&2, T.Tensor>:
  Ent.t(e) <> acc

def get_parameters(o: Obj) -> List<&2, T.Tensor>:
  List.reverse(&2, T.Tensor, List.foldl(~&2, ~Ent, ~List<&2, T.Tensor>, sd_values.step, sd_collapsed(o), Nil{}))

# ---------------------------------------------------------------------------
# safe_dtypes -- state.py:33-35, in the source's order, and `inverse_safe_dtypes`
# -- state.py:36, which is `{v:k for k,v in safe_dtypes.items()}` and so has the
# SAME order.
#
# The values are `S.Dt` and the keys are the safetensors SPELLINGS, which are not
# `str(dtype)[7:]`: `I8` is `signed char` and `BF16` is `__bf16`. The pair is
# the table, and the row prints the spelling, so the mismatch between the two
# vocabularies is visible rather than smoothed over.
# ---------------------------------------------------------------------------

type Sd is Data:
  Sd{k: String, d: S.Dt}

def Sd.k(e: Sd) -> String:
  match e:
    case Sd{k, d}: k

def Sd.d(e: Sd) -> S.Dt:
  match e:
    case Sd{k, d}: d

def safe_dtypes() -> List<&2, Sd>:
  [Sd{"BOOL", S.boolean()}, Sd{"I8", S.int8()}, Sd{"U8", S.uint8()}, Sd{"I16", S.int16()},
   Sd{"U16", S.uint16()}, Sd{"I32", S.int32()}, Sd{"U32", S.uint32()}, Sd{"I64", S.int64()},
   Sd{"U64", S.uint64()}, Sd{"F8_E4M3", S.fp8e4m3()}, Sd{"F8_E5M2", S.fp8e5m2()},
   Sd{"F16", S.half()}, Sd{"BF16", S.bfloat16()}, Sd{"F32", S.single()}, Sd{"F64", S.double()}]

# `safe_load`'s `safe_dtypes[v['dtype']]` -- state.py:61. A `Maybe` because a
# safetensors header names a dtype this table does not have, and Python's
# alternative is a `KeyError`. `Bool.pick` because a `match` may not scrutinise
# `String.eq(...)` and hoisting the Bool into a second def makes the two defs
# mutually recursive.
def sd_lookup(es: List<&2, Sd>, +nm: String) -> Maybe<&1, S.Dt>:
  match es:
    case Nil{}: None{}
    case +e <> t: Bool.pick(Maybe<&1, S.Dt>, String.eq(Sd.k(e), nm), Some{Sd.d(e)}, sd_lookup(t, nm))

def sd_get(nm: String) -> Maybe<&1, S.Dt>:
  sd_lookup(safe_dtypes(), nm)

# `inverse_safe_dtypes` -- the reverse, same order. A `Map` cannot be keyed by a
# `Dt` (base's `Map` is string-keyed only) and a `match` cannot scrutinise a
# record's field VALUE, so the reverse is a SEARCH over the same list and the
# round trip is a property of the table rather than an assertion about it.
def sd_inv(es: List<&2, Sd>, +dt: S.Dt) -> Maybe<&1, String>:
  match es:
    case Nil{}: None{}
    case +e <> t: Bool.pick(Maybe<&1, String>, O.eq_dt(Sd.d(e), dt), Some{Sd.k(e)}, sd_inv(t, dt))

def sd_name(dt: S.Dt) -> Maybe<&1, String>:
  sd_inv(safe_dtypes(), dt)

# `dtypes.weaks` is `(weakint, weakfloat)` -- dtype.py:160 -- and `safe_save`
# refuses them (state.py:73). `weakint` and `weakfloat` are not in `safe_dtypes`
# (measured: 15 entries, neither present), so the refusal is a table membership
# test and this is it.
def sd_is_weak(+dt: S.Dt) -> Bool:
  Bool.or(O.eq_dt(dt, S.weakint()), O.eq_dt(dt, S.weakfloat()))

# ---------------------------------------------------------------------------
# `TensorIO.seek` -- state.py:25.
# `self._position = min(len(self._tensor), max(0, [offset, self._position+offset,
# len(self._tensor)+offset][whence]))`
#
# `len(self._tensor)` is `t.shape[0]` (movement.py's `__len__`), which for the
# gate is the CONST's extent and is a PARAMETER here: this def takes the length
# and the offset and answers the new position, which is the whole of the method.
# `whence` is 0/1/2 and base's `List.get` is the quantifier-then-element-then-
# list form, so the three candidates are picked from a three-element list.
#
# Measured against CPython's `TensorIO.seek` on a 1-element uint8 tensor:
# `seek(0)->0 seek(1)->1 seek(-1)->0 seek(1,1)->1 seek(0,2)->1 seek(9)->1 seek(-5)->0`.
#
# TWO of those seven are the reason this def is in `H.I64` and not `U32`, and the
# gate caught it: `seek(-1)` and `seek(-5)` are NEGATIVE offsets, and `max(0, x)`
# on a `U32` wrapping `-1` to `4294967295` answers `4294967295` where Python
# answers `0`. A `U32` port of this line is a silent corruption of exactly the
# case a file reader hits on every backwards seek. The `whence=2` case is the
# other one: `len+offset` is the THIRD candidate, so an implementation that read
# `whence` as a 0/1 flag answers `0` where the answer is `1`.
# ---------------------------------------------------------------------------

def sd_i64(n: U32) -> H.I64: H.i64_of_i32(n)

# `max(0, x)` -- the clamp is SIGNED, which is the whole point of the I64 above.
def sd_seek.above(+x: H.I64, +zero: H.I64) -> H.I64:
  Bool.pick(H.I64, H.i64_is_neg(x), zero, x)

# `[offset, self._position+offset, len(self._tensor)+offset][whence]` -- base's
# `List.get` is the quantifier-then-element-then-list form, and the default is the
# `offset` arm Python's own subscript would raise on.
def sd_seek.pick.of(m: Maybe<&1, H.I64>, off: H.I64) -> H.I64:
  match m:
    case Some{x}: x
    case None{}: off

def sd_seek.pick(whence: U32, +off: H.I64, +pos: H.I64, +len_: H.I64) -> H.I64:
  sd_seek.pick.of(List.get(&1, H.I64, [off, H.i64_add(pos, off), H.i64_add(len_, off)],
    U32.to_nat(whence)), off)

# `min(len, x)` -- `above` again, with the arguments the other way round, because
# `H.i64_le` is the only comparison and `min` needs the smaller one.
def sd_seek.clamp(+len_: H.I64, +x: H.I64) -> H.I64:
  Bool.pick(H.I64, H.i64_le(x, len_), x, len_)

def sd_seek(+len_: U32, pos: U32, off: U32, whence: U32) -> H.I64:
  sd_seek.clamp(sd_i64(len_), sd_seek.above(sd_seek.pick(whence, sd_i64(off), sd_i64(pos), sd_i64(len_)),
    sd_i64(0)))

# the row compares `H.i64_text`, which prints `hi:lo` (helpers.bend's choice, and
# the reason is there), so this def exists only to give the row a `U32`-free
# comparison against a value the oracle prints as a decimal.
def sd_seek_v(len_: U32, pos: U32, off: U32, whence: U32) -> String:
  H.i64_text(sd_seek(len_, pos, off, whence))

# ---------------------------------------------------------------------------
# THE WALLS. One TODO per Python line, and no prose pretending otherwise.
# ---------------------------------------------------------------------------

# TODO(p3) state.py:8   TensorIO        -- `io.RawIOBase`; `readinto` (:17) needs
#   `.data()` (REALIZATION, tensor.bend WALL 4) and `buffer[:n] = data` mutates a
#   Python bytearray, which no `Data` record can express. `seek` is above.
# TODO(p3) state.py:38  accept_filename  -- a decorator; `functools.wraps` copies
#   attributes off a function object and a function in a `Data` field forces
#   `Type`. The four uses below take their filename as a parameter instead.
# TODO(p3) state.py:44  safe_load_metadata -- `int.from_bytes(t[0:8].data(), "little")`
#   is `.data()` (WALL 4) and `json.loads` is a PARSER.
# TODO(p3) state.py:51  safe_load        -- as above, plus `bitcast` (mixin/dtype.py)
#   and `reshape` (mixin/movement.py), and `Tensor(pathlib.Path(fn))` is `load`.
# TODO(p3) state.py:64  safe_save        -- `json.dumps` is a PARSER,
#   `pathlib.Path(fn).unlink` is an unlink, `Tensor.empty(device=f"disk:{fn}")` is
#   REALIZATION on a file device, and `t[0:8].bitcast(dtypes.int64).assign(...)` is
#   a store into a realized buffer. `round_up(len(j),8)` and the
#   `data_offsets` accumulation are the only pure lines and they are not worth a
#   file of their own.
# TODO(p3) state.py:128 load_state_dict  -- `v.replace` (:159, `UOp.replace` is P3)
#   and `v.realize` (:162, WALL 4) are both needed before the shape-mismatch
#   predicate at :156 is reachable, and `tqdm`/`Timing`/`GlobalCounters` are
#   runtime. `sorted(list(state_dict.keys() - model_state_dict.keys()))` (:149) is
#   ALSO unreachable for the same reason and is not ported on its own.
# TODO(p3) state.py:168 zip_extract      -- `zipfile.ZipFile(TensorIO(t))`: a zip
#   CENTRAL DIRECTORY parser over a tensor, and state.py:182 says so itself
#   ("we need a zlib UOp so this can be lazy").
# TODO(p3) state.py:188 tar_extract      -- `tarfile.open(fileobj=TensorIO(t))`,
#   same shape of wall.
# TODO(p3) state.py:207 torch_load       -- a `pickle.Unpickler` SUBCLASS with
#   `find_class` and `persistent_load`, plus `zipfile.is_zipfile`,
#   `tarfile.is_tarfile`, `struct.unpack` and `argsort`. A pickle VM.

# ===========================================================================
# THE GATE
# ===========================================================================

def sd_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# These two are the shape rule 31 was measured for: a CLOSED step over a String, so
# the lambda inlines and no top-level def is needed at all. The old spelling spent four
# lines and a `.go` name per fold; this spends one.
def sd_keys(es: List<&2, Ent>) -> String:
  List.foldl(~&2, ~Ent, ~String, (acc: String) => (e: Ent) => String.concat([acc, Ent.k(e), ","]), es, "")

def sd_spellings(es: List<&2, Sd>) -> String:
  List.foldl(~&2, ~Sd, ~String, (acc: String) => (e: Sd) => String.concat([acc, Sd.k(e), ","]), es, "")

def sd_strip_keys(o: Obj) -> String:
  sd_keys(sd_collapsed.pf(o, sd_strip("")))

# --- the fixtures. A tensor is a CONST in a fresh arena: a `state_dict` is a set
# of NAMES, so nothing here reads a value, and a CONST is the cheapest node that
# is a real leaf. `List.show` is not used anywhere in this repo and its `~f`
# parameter is refused by the compiler (measured), so every printer below is a
# hand-written fold, which is also the shape the rest of the tree uses.

def sd_t1() -> T.Tensor:
  T.tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})

def sd_t2() -> T.Tensor:
  T.tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})

def sd_t3() -> T.Tensor:
  T.tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})

# `t` -- a bare tensor. CPython: `list(get_state_dict(Tensor([1.0])).keys())` is
# `['']`, i.e. the key is the EMPTY STRING, which is `''.strip('.')` at :103 and
# is the one case where the leaf's own key is not a name. `sd_keys` joins with a
# trailing `","`, so the expected text is `","` and not `""` -- the ORACLE prints
# the same join, so the two are compared in the same format.
def t_tens() -> IO(Unit):
  sd_row("sd_tens", String.eq(sd_keys(sd_collapsed(OTens{sd_t1()})), ","))

# `{'w': t}` -- a dict. CPython: `['w']`.
def t_map() -> IO(Unit):
  sd_row("sd_map", String.eq(sd_keys(sd_collapsed(OMap{[Kv{"w", OTens{sd_t1()}}]})), "w,"))

# `[t, t]` -- a list. CPython: `['0', '1']`. The keys are INDICES, which is the
# one place the list rung differs from the dict rung and the reason `OSeq` exists.
def t_seq() -> IO(Unit):
  sd_row("sd_seq", String.eq(sd_keys(sd_collapsed(OSeq{[OTens{sd_t1()}, OTens{sd_t2()}]})), "0,1,"))

# `{'layers': [ {'weight': t, 'bias': t}, ... ]}` -- the `Model.layers` shape,
# which is the whole point of the function: the prefix ladder through a list of
# mappings of tensors. CPython measured on `beautiful_mnist.py`'s `Model`:
#   layers.0.weight, layers.0.bias, layers.2.weight, layers.2.bias,
#   layers.4.weight, layers.4.bias, layers.4.num_batches_tracked,
#   layers.4.running_mean, layers.4.running_var, layers.6.weight, layers.6.bias
# and the fixture below is that list with the non-parameter entries left in
# (BatchNorm carries five) and the gaps (1, 3, 5 are relu/pool) as a non-mapping
# child, so the row also pins that `OOther` contributes NOTHING -- which is
# Python's `state_dict` staying `{}` at :107 and the reason a relu in the middle
# of a layer list does not shift every key after it.
def t_nest() -> IO(Unit):
  bn : Obj = OMap{[Kv{"weight", OTens{sd_t1()}}, Kv{"bias", OTens{sd_t2()}},
    Kv{"num_batches_tracked", OTens{sd_t3()}}, Kv{"running_mean", OTens{sd_t1()}},
    Kv{"running_var", OTens{sd_t2()}}]}
  tail : Obj = OMap{[Kv{"weight", OTens{sd_t3()}}]}
  layers : Obj = OSeq{[bn, OOther{sd_t2()}, tail]}
  nested : Obj = OMap{[Kv{"layers", layers}]}
  sd_row("sd_nest", String.eq(sd_keys(sd_collapsed(nested)),
    "layers.0.weight,layers.0.bias,layers.0.num_batches_tracked,layers.0.running_mean," ++
    "layers.0.running_var,layers.2.weight,"))

# `prefix.strip('.')` over the six measured prefixes. CPython:
#   '' -> ''  '.' -> ''  '..' -> ''  '.a.' -> 'a'  'a..b..' -> 'a..b'  'a' -> 'a'
# `a..b..` is the one that matters: the interior `..` SURVIVES, so this is a
# strip of RUNS at the two ends and not a removal of every dot.
def t_strip() -> IO(Unit):
  sd_row("sd_strip", Bool.and(
    Bool.and(String.eq(sd_strip(""), ""), String.eq(sd_strip("."), "")),
    Bool.and(Bool.and(String.eq(sd_strip(".."), ""), String.eq(sd_strip(".a."), "a")),
      Bool.and(String.eq(sd_strip("a..b.."), "a..b"), String.eq(sd_strip("a"), "a")))))

# rungs 2 and 4: a namedtuple's `_asdat()` and an object's `__dict__`. Both are
# `OMap` here and both are the same computation; this row is the claim that the
# MERGE did not change the answer. CPython: a 2-field namedtuple of tensors is
# `['a', 'b']`, and `class C: self.q = t` is `['q']`.
def t_attr() -> IO(Unit):
  sd_row("sd_attr", Bool.and(
    String.eq(sd_keys(sd_collapsed(OMap{[Kv{"a", OTens{sd_t1()}}, Kv{"b", OTens{sd_t2()}}]})), "a,b,"),
    String.eq(sd_keys(sd_collapsed(OMap{[Kv{"q", OTens{sd_t1()}}]})), "q,")))

# THE ORDERING FIXTURE. An `OrderedDict` IS a dict AND it HAS a `__dict__`
# (measured: `dict(OrderedDict().__dict__) == {}`), so Python's rung 3 and rung 4
# both claim it and only the ORDER saves the answer: rung 3 first, or every
# `nn.Module`-style object built on a mapping would walk to `{}`. CPython:
# `list(get_state_dict(OrderedDict([('z',t),('a',t)])).keys())` is `['z', 'a']`.
# This row is why the four mapping rungs are MERGED rather than kept: with the
# merge there is no order left to get wrong, and this row proves the payload
# choice the merge delegates to the caller.
def t_ord() -> IO(Unit):
  sd_row("sd_ord", String.eq(
    sd_keys(sd_collapsed(OMap{[Kv{"z", OTens{sd_t1()}}, Kv{"a", OTens{sd_t2()}}]})), "z,a,"))

# THE DICT-COLLAPSE FIXTURE, and the reason `sd_update` exists at all. Python:
#   get_state_dict({'a.b': t1, 'a': {'b': t2}})  ->  {'a.b': t2}
# One key, the LAST value, at the FIRST position. A `List` without `sd_update`
# would answer two entries.
#
# The row asserts the COUNT and the VALUE separately, and the value is read with
# `sd_cval` (the CONST's payload) rather than with the arena index, because every
# fixture builds its own `Arena.empty()` so every index is 1. A `sd_put` that
# filtered instead of overwriting would pass the count and fail the value; a
# `sd_put` that appended instead would fail both. That is the whole claim.
def sd_t9() -> T.Tensor:
  T.tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(9)})

def sd_first_val(es: List<&2, Ent>) -> U32:
  match es:
    case Nil{}: 0
    case e <> _t: sd_cval(Ent.t(e))

def t_dup() -> IO(Unit):
  +collapsed : List<&2, Ent> = sd_collapsed(OMap{[Kv{"a.b", OTens{sd_t1()}},
    Kv{"a", OMap{[Kv{"b", OTens{sd_t9()}}]}}]})
  sd_row("sd_dup", Bool.and(
    Bool.and(U32.is_eq(U32.from_nat(List.length(&2, Ent, collapsed)), 1),
      String.eq(sd_keys(collapsed), "a.b,")),
    U32.is_eq(sd_first_val(collapsed), 9)))

# the 15 `safe_dtypes` SPELLINGS in the source's order. The KEYS are state.py's
# own data and they are the diff line.
#
# WHY THE DTYPES ARE NOT IN THIS ROW. `spec.bend`'s `Dt.nm` is the C spelling
# (`signed char`, `unsigned char`, `float8_e4m3`, `__bf16`) and tinygrad's
# `DType.name` is the short one (`char`, `uchar`, `fp8e4m3`, `bfloat16`); eight of
# the fifteen differ. `spec.bend` is READ-ONLY to this unit, so a joined
# `NAME:DTYPE` row would be red on both lanes for a reason that is neither side's
# bug, and hiding it inside a formatting choice is worse than naming it. The dtype
# claim is `sd_safedt` below and the name divergence is in the report.
def t_safe() -> IO(Unit):
  sd_row("sd_safe", String.eq(sd_spellings(safe_dtypes()),
    "BOOL,I8,U8,I16,U16,I32,U32,I64,U64,F8_E4M3,F8_E5M2,F16,BF16,F32,F64,"))

# the table is a BIJECTION onto 15 DISTINCT dtypes, checked through the real
# lookup path (`sd_get`, a search over the table) rather than by restating the
# table. `safe_load` does `safe_dtypes[v['dtype']]` and `safe_save` does
# `inverse_safe_dtypes[v.dtype]`, so two spellings sharing a dtype would lose a
# tensor on the round trip with no error anywhere. `sd_all_get` is "every spelling
# resolves"; `sd_distinct` is "no two share a dtype".
def sd_all_get.go(es: List<&2, Sd>) -> Bool:
  match es:
    case Nil{}: True{}
    case +e <> t: Bool.and(Maybe.is_some(&1, S.Dt, sd_get(Sd.k(e))), sd_all_get.go(t))

def sd_all_get(es: List<&2, Sd>) -> Bool:
  sd_all_get.go(es)

# pairwise distinctness, over the (i,j) prefix pairs. `H.argsort_u32` is not used:
# the table is 15 long and a fold over the tail is the whole of it.
def sd_distinct.pair(seen: List<&2, Sd>, +e: Sd) -> Bool:
  match seen:
    case Nil{}: True{}
    case +f <> u: Bool.and(Bool.not(O.eq_dt(Sd.d(f), Sd.d(e))), sd_distinct.pair(u, e))

# `es` is the FIRST parameter, not `seen`, because `seen` GROWS in the self-call
# and rule 5 reads arguments left to right and stops at the first that shrinks.
def sd_distinct.go(es: List<&2, Sd>, +seen: List<&2, Sd>) -> Bool:
  match es:
    case Nil{}: True{}
    case +e <> t: Bool.and(sd_distinct.pair(seen, e), sd_distinct.go(t, List.append(&2, Sd, seen, [e])))

def sd_distinct(es: List<&2, Sd>) -> Bool:
  sd_distinct.go(es, Nil{})

def t_safedt() -> IO(Unit):
  sd_row("sd_safedt", Bool.and(sd_all_get(safe_dtypes()), sd_distinct(safe_dtypes())))

# A COUNT and not a boolean, because a table that lost its last entry would still
# satisfy every per-entry row. CPython: `len(safe_dtypes) == 15`.
def t_invn() -> IO(Unit):
  sd_row("sd_invn", U32.is_eq(U32.from_nat(List.length(&2, Sd, safe_dtypes())), 15))

def sd_rt.hit(m: Maybe<&1, String>, k: String) -> Bool:
  match m:
    case Some{got}: String.eq(got, k)
    case None{}: False{}

def sd_rt(dt: S.Dt, k: String) -> Bool:
  sd_rt.hit(sd_name(dt), k)

def sd_inv_all(es: List<&2, Sd>) -> Bool:
  match es:
    case Nil{}: True{}
    case +e <> t: Bool.and(sd_rt(Sd.d(e), Sd.k(e)), sd_inv_all(t))

# the round trip, per entry. `safe_load` looks a spelling UP and `safe_save`
# looks a dtype UP, so a table that is not a bijection is a silent corruption in
# one direction or the other. CPython: `all(inverse[safe[k]] == k ...)` is True.
def t_inv() -> IO(Unit):
  sd_row("sd_inv", sd_inv_all(safe_dtypes()))

# `TensorIO.seek`'s clamp, all three `whence` values, on a 1-element tensor --
# measured: `seek(0)->0 seek(1)->1 seek(-1)->0 seek(1,1)->1 seek(0,2)->1 seek(9)->1
# seek(-5)->0`. The two negative offsets are passed as their two's complement
# `U32` images (`-1` is `4294967295`, `-5` is `4294967291`) because `sd_seek`'s
# parameter is a `U32` and the SIGN is applied inside it; a `U32` clamp answers
# `4294967295:4294967295` for both, which is the bug this row exists for.
# `0:0` is `H.i64_text` of zero.
def t_seek() -> IO(Unit):
  sd_row("sd_seek", Bool.and(
    Bool.and(String.eq(sd_seek_v(1, 0, 0, 0), "0:0"), String.eq(sd_seek_v(1, 0, 1, 0), "0:1")),
    Bool.and(Bool.and(String.eq(sd_seek_v(1, 0, 4294967295, 0), "0:0"),
      String.eq(sd_seek_v(1, 0, 1, 1), "0:1")),
      Bool.and(Bool.and(String.eq(sd_seek_v(1, 0, 0, 2), "0:1"),
        String.eq(sd_seek_v(1, 0, 9, 0), "0:1")),
        String.eq(sd_seek_v(1, 0, 4294967291, 0), "0:0")))))

# `len(get_parameters(model))` -- state.py:126 -- which is the count of LEAVES and
# not the count of keys before the collapse, so it is a third claim about the
# same walk and it is the one the optimizer actually consumes. CPython measured
# on `beautiful_mnist.py`'s `Model()`: 11. The fixture below is a THREE-ENTRY
# layer list with the middle one non-mapping, so it is 5 + 2 = 7 and NOT 11 --
# the row says 7 because a row must state the fixture's own count, and `sd_nest`
# is the row that pins the full model's key list.
def t_param() -> IO(Unit):
  bn : Obj = OMap{[Kv{"weight", OTens{sd_t1()}}, Kv{"bias", OTens{sd_t2()}},
    Kv{"num_batches_tracked", OTens{sd_t3()}}, Kv{"running_mean", OTens{sd_t1()}},
    Kv{"running_var", OTens{sd_t2()}}]}
  tail : Obj = OMap{[Kv{"weight", OTens{sd_t3()}}, Kv{"bias", OTens{sd_t1()}}]}
  layers : Obj = OSeq{[bn, OOther{sd_t2()}, tail]}
  sd_row("sd_param", U32.is_eq(
    U32.from_nat(List.length(&2, T.Tensor, get_parameters(OMap{[Kv{"layers", layers}]}))), 7))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_tens()
    b : Unit <- t_map()
    c : Unit <- t_seq()
    d : Unit <- t_nest()
    e : Unit <- t_strip()
    f : Unit <- t_attr()
    g : Unit <- t_ord()
    h : Unit <- t_dup()
    i : Unit <- t_safe()
    j : Unit <- t_safedt()
    k : Unit <- t_invn()
    l : Unit <- t_inv()
    m : Unit <- t_seek()
    t_param()

# ===========================================================================
# THE GATE, AS A COMMAND, AND EVERY ROW IS GREEN. Both lanes and the oracle:
#
#     .venv/bin/python .agents/slop/state-gate.py  > /tmp/py.txt
#     ./bin/bend tinybendygrad/nn/state.bend        > /tmp/bd.txt
#     ./bin/bend tinybendygrad/nn/state.bend -o /tmp/nat && /tmp/nat > /tmp/nat.txt
#     diff /tmp/bd.txt /tmp/nat.txt    # MEASURED: byte identical, all 14 rows
#     diff /tmp/py.txt /tmp/bd.txt     # MEASURED: byte identical, all 14 rows
#
# `--check-only` reports "14 defs rely on unsafe or foreign code", all fourteen in
# `dtype.bend` and all `@extern` F32 conversions that were there before this unit.
# `optim.bend` reports the identical fourteen. It is not a property of this file.
# ===========================================================================
#
# THE MUTATION TABLE, MEASURED, by `.agents/slop/state-mutate.py` (which mutates
# the file in place, restores it, and reports the rows that MOVE).
#
#     cp tinybendygrad/nn/state.bend /tmp/s.bak     # if you want to do it by hand
#     .venv/bin/python .agents/slop/state-mutate.py
#
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | the mapping child's key loses its trailing `"."` | `sd_nest` `sd_dup` | the ONE character `f"{prefix}{k}."` adds (state.py:111). `sd_tens`/`sd_map` do not move because a top-level key is `strip`ped to the same string either way -- the strip hides the bug at depth 0, which is why the fixture has a depth. |
# | M2 | the sequence child's key is `prefix ++ "."` instead of `prefix ++ str(i)` | `sd_seq` `sd_nest` `sd_param` | `str(i)` at state.py:109. This is the ONLY row family that can see `OSeq` and `OMap` differ, and M1 cannot see it. |
# | M3 | `sd_put` appends instead of overwriting | `sd_dup` | `dict.__setitem__` semantics: FIRST position, LAST value. The count assertion in `sd_dup` passes under this mutation; only the value assertion fails, which is why `sd_dup` asserts both. |
# | M4 | `sd_drop.head`'s dot arm is removed, so EVERY dot is dropped | `sd_map` `sd_seq` `sd_nest` `sd_strip` `sd_attr` `sd_ord` `sd_dup` `sd_param` (8 of 14) | the head RUN only. `layers.0.weight` loses its interior dots. **This mutation is the first version of this file's own bug** -- the shipped code had a bare `case '.':` arm with no `St`, which drops interior dots too; the gate caught it as `sd_strip=False` and `sd_nest=False` and the `St` sum type is the fix. |
# | M5 | `sd_strip` drops the `rstrip` half | `sd_map` `sd_seq` `sd_nest` `sd_strip` `sd_attr` `sd_ord` `sd_dup` | the TAIL run. Seven rows because every key in the gate ends in a dot, so the tail half is load-bearing for the whole file. |
# | M6 | `sd_seek.above` returns `x` unconditionally | `sd_seek` | the SIGNED `max(0, x)`. The two negative offsets in the row are the fixture; a `U32` clamp answers `4294967295:4294967295` for `seek(-1)`. **This is the second bug the gate caught in this file**: the first `sd_seek` was `U32` throughout and was wrong for exactly the backwards-seek case a file reader hits. |
# | M7 | the `whence == 2` candidate is `pos+off` instead of `len+off` | `sd_seek` | the THIRD element of `[offset, pos+offset, len+offset][whence]`. M6 and M7 are two rules over one row, so neither is localised: one row, two independent claims, and both are named in the row's comment. |
# | M8 | the `OOther` rung emits a key | `sd_nest` `sd_param` | Python's `state_dict` staying `{}` at state.py:107. Only the two rows with a non-mapping child move, which is the fixture's whole job: a `Tensor.relu` between two convolutions must not shift every key after it. |
# | M9 | the walk's final `List.reverse` is removed | `sd_seq` `sd_nest` `sd_attr` `sd_ord` `sd_dup` | DOCUMENT ORDER. The accumulator is built by consing, so without the reversal every multi-key row is reversed. `sd_tens`/`sd_map` are single-entry and cannot see it. |
# | M10 | a 16th, empty-spelling entry is appended to `safe_dtypes` | `sd_safe` `sd_invn` | the table's LENGTH and its spelling list. M10 is why `sd_invn` exists as a COUNT row: `sd_safe` alone would also go red, but the count is the claim that says "exactly fifteen" rather than "this particular fifteen". |
# | M11 | the leaf does not `sd_strip` its prefix | `sd_map` `sd_seq` `sd_nest` `sd_attr` `sd_ord` `sd_dup` | `prefix.strip('.')` AT THE LEAF (state.py:103), as opposed to at the point of insertion. Six rows because the strip applies to every key. |
# | M12 | a no-op edit | **NOTHING** | the control. A mutation table with no row that CANNOT move is a table of coincidences, and M12 is what makes M1-M11 mean something. |
#
# TWO MUTATIONS THAT WERE ATTEMPTED AND ARE NOT IN THE TABLE, because they are
# not expressible as a one-token edit and pretending otherwise would be a lie:
#   * swapping the `OMap` and `OSeq` ARMS. The arms are selected by the `Obj`
#     sum type, so a value has exactly one constructor and there is no order to
#     get wrong. The Python ladder's order IS observable -- `sd_ord` is the
#     fixture that proves it -- and the port has REMOVED the ambiguity rather
#     than reproduced it. That is a DIVERGENCE and it is in the header.
#   * a `tensor_type` other than `Tensor`. `get_state_dict`'s third parameter is a
#     Python TYPE, and a type in a `Data` field forces `Type`; the port's tensor
#     rung is structural. There is no row for it because there is no port for it.
#
# WHAT THE TABLE DOES NOT COVER, stated rather than left to be discovered:
#   * `TensorIO.readinto`/`read` are a WALL (see the TODO list), so the `sd_seek`
#     row pins the clamp and nothing pins that a read honours the clamp.
#   * `safe_load`/`safe_save` are WALLS, so `safe_dtypes` is gated as a TABLE and
#     not as a load. A wrong `data_offsets` computation would not move a row here.
#   * The `sd_safe` row prints the 15 SPELLINGS and not the 15 dtypes, because
#     `spec.bend`'s `Dt.nm` vocabulary and tinygrad's `DType.name` vocabulary
#     differ on eight of the fifteen and `spec.bend` is read-only to this unit.
#     The dtype claim is `sd_safedt` (a bijection, through the real lookup path).
