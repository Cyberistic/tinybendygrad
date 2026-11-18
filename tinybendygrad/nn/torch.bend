# tinybendygrad/nn/torch.bend -- port of tinygrad/nn/torch.py
#
# `nn/torch.py` IS FOUR LINES AND NONE OF THEM IS A TENSOR.
#
#     1  # type: ignore
#     2  import sys, pathlib
#     3  sys.path.append(pathlib.Path(__file__).parent.parent.as_posix())
#     4  try: import extra.torch_backend.backend  # noqa: F401
#     5  except ImportError as e: raise ImportError("...") from e
#
# The brief asked whether this is "an upstream-backed wrapper" and demanded an
# honest answer either way. it is upstream-backed and the backend is present:
# `extra/torch_backend/backend.py` is in this checkout, so the file is not a
# re-export of anything and it is not a stub -- it is a GATE. MEASURED, by
# importing it:
#
#     >>> import tinygrad.nn.torch
#     ImportError: torch frontend not in release
#     To fix, install tinygrad from a git checkout with pip install -e .
#
# So the four lines are a PATH DERIVATION, a sys.path MUTATION, a guarded import
# and a refusal that KEEPS ITS CAUSE (`from e`). Those four things are the port.
#
# WHAT IS PORTED, DEF BY DEF.
#
#   :2  `import sys, pathlib`              PORTED as the two things it names:
#                                                 `sys.path` is a LIST, `pathlib`
#                                                 is WALL 1.
#   :3  `sys.path.append(...)`             PORTED  `shim.append`  ONE append, LAST
#   :3  `Path(__file__)`                   WALL 1   the file's own name
#   :3  `.parent.parent`                   PORTED  `drop2`  two components
#   :3  `.as_posix()`                      PORTED  `as_posix`  backslash -> slash
#   :4  `try:` / `import extra...backend`  WALL 2   the import itself; the CALL
#                                                 and its position are ported
#   :5  `except ImportError as e:`         PORTED  `shim.import`'s `ok` argument
#   :5  `raise ImportError(MSG) from e`    PORTED  `Tr.raise` -- the message, the
#                                                 `from e` chain, and the fact that
#                                                 NOTHING AFTER IT HAPPENS
#
# THE THREE WALLS, and they are all `pathlib` / `sys` / the import machinery.
#
# 1. PATHLIB (device.py has the same wall, ops_*.py files take it for granted).
#    `Path` NORMALISES. Three measured cases where a string operation and
#    `Path` disagree, all of which `drop2` does NOT reproduce:
#      'a//b/c.py'  ->  Path.parent = 'a/b'    (the empty component is collapsed)
#      'x/y/'       ->  Path.parent = 'x'     (a trailing separator is ignored)
#      'a/./b/c.py' ->  Path.parent = 'a/b'    ('.' is a component, not nothing)
#    `__file__` is already normalised -- CPython hands the interpreter a
#    normalised path -- so the port takes a NORMALISED path and says so, and
#    these three are the counterexamples that make the claim falsifiable.
#    TODO(p3) nn/torch.py:3  `pathlib.Path` -- normalisation of '.', '..', '//'
#      and trailing separators. WALL: a path library, not a string operation.
# 2. SYS (device.bend has the same wall in `_opened_devices`). `sys.path` is
#    module-level mutable state and Bend has no module state, so it travels in
#    `Imp.path` -- which is the only difference, and exactly `device.bend`'s
#    `Reg` for `_opened_devices`.
#    TODO(p3) nn/torch.py:3  `sys.path` -- module-level list mutation.
# 3. THE IMPORT (WALL 2). `import extra.torch_backend.backend` binds names in
#    `sys.modules` and can fail with any `ImportError` subclass. What is PORTED
#    is everything that is not the import: that it is ONE call, that it happens
#    AFTER the path append, that its failure is the sole trigger for the raise,
#    and the raise's own text and cause.
#    TODO(p3) nn/torch.py:4  the import -- `import extra.torch_backend.backend` binds
#      names in `sys.modules`, and the module search is the wall.
#
# THE SPLIT, stated once and then obeyed. A def here EITHER derives the argument
# of one of the three calls (pure, and the gate checks it) OR records that call
# in the trace (and the gate checks the ORDER). There is no third kind.
#
# THE RAISE IS IN THE TRACE, and that is the port of `raise`. Once the import
# has failed, `Tr.raise.at` sets `refused`, and `Tr.emit` records NOTHING for
# any later call -- so a refusal appears in the trace as a TRUNCATION rather
# than as a flag alone, which is why no step below needs a guard of its own.
# There is only one step after the import in this file, so the truncation is
# measured by the COUNT and by the absence of a third entry, not by a later
# call being suppressed. that is the honest limit of the claim; see
# `torch_refuse_n`.

import Base
import ../helpers.bend as H

# THE CONSTANTS. Every literal in the file, and the four measured values that
# come out of importing it in CPython.

def PARENT_DEPTH() -> U32: 2
def MSG_NEWLINE_AT() -> U32: 29
def MSG_LINES() -> U32: 2
def MODULE_NAME() -> String: "extra.torch_backend.backend"
def MSG_HEAD() -> String: "torch frontend not in release"
def MSG_TAIL() -> String: "To fix, install tinygrad from a git checkout with pip install -e ."

# the three calls, in the order Python makes them.
def CALL_PATH_APPEND() -> U32: 0
def CALL_IMPORT() -> U32: 1
def CALL_RAISE() -> U32: 2

# `raise ... from e` -- the cause is KEPT, so the trace entry's argument is 1.
def FROM_E() -> U32: 1

def SLASH() -> String: "/"
def ROOT_SLASH() -> String: "/"
def DOT() -> String: "."
def SLASH_C() -> Char: Char.from_u32(47)
def BSLASH_C() -> Char: Char.from_u32(92)
def LFU() -> Char: Char.from_u32(10)

# the message, with the newline `"\n"` between its two halves. `String.concat`
# and not one literal, because base.bend has no `\n` escape.
def NL() -> String: String.from_list([LFU()])

def MSG() -> String: String.concat([MSG_HEAD(), NL(), MSG_TAIL()])

def MSG_LINES_GOT() -> U32: U32.from_nat(List.length(&2, String, String.split(MSG(), LFU())))

# THE TYPES.

type Call is Data:
  Call{k: U32, arg: U32}

# the machine state of the seam. `refused` is nn/torch.py's `raise`: everything
# after it does not happen. There is no `next` because nothing here MINTS a
# handle -- `sys.path` grows and `sys.modules` binds names, and neither is a
# number this file can invent.
type Tr is Data:
  Tr{calls: List<&2, Call>, refused: Bool}

# `sys.path` (WALL 2) and the trace. One record and not two, because the append
# is the only thing that writes the path and it writes the trace in the same
# breath -- `device.bend`'s `Reg` and its opened set, which is the same idea.
type Imp is Data:
  Imp{path: List<&2, String>, t: Tr}

# THE TRACE.

def Tr.of() -> Tr: Tr{Nil{}, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, refused}: calls

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, refused}: refused

def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])), refused}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, refused}: Tr.emit.go(refused, k, arg, calls)

# nn/torch.py:4-5 as ONE def. `ok` is the import's answer -- the seam's, and
# the ONLY thing the guard reads -- and the raise is recorded on entry to a
# still-unrefused trace, exactly like ops_webgpu's failing pop. The failing
# import IS still in the trace, because the raise reports IT and not itself.
#
# Two `Bool.pick`s and no nested `match`, because a `match` may not follow a
# `Data` match's binder (bend2-constraints.md, position 2158) and `Bool.pick` is
# strict, so both arms are TOTAL values built here. `calls` is read four times,
# which is why the binder takes `+`.
def Tr.raise.at(+ok: Bool, t: Tr) -> Tr:
  match t:
    case Tr{+calls, +refused}:
      Tr{Bool.pick(List<&2, Call>, ok, calls,
                   Bool.pick(List<&2, Call>, refused, calls,
                             List.append(&2, Call, calls, [Call{CALL_RAISE(), FROM_E()}]))),
         Bool.pick(Bool, ok, refused, True{})}

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# READING THE TRACE. Same three readers as ops_webgpu, and the same fuel bug they
# were written around: the fuel is the TRACE's length and the answer is
# `at == patlen`, so a reversed pattern does NOT match.

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

# nn/torch.py:3 -- `.parent.parent`, and it is TWO components, not one. The port
# deletes the last two components and the two separators in front of them, which
# is what makes the answer `/abs/tinygrad` and not `abs/tinygrad`: the leading
# separator is part of `s` and a prefix is kept.
#
# `prev` is `len(component) + 1` for the LAST component consumed and `acc` is
# that same quantity for the SECOND-last, added up. So after the whole walk `acc`
# is exactly `(len(second) + 1) + (len(last) + 1)` -- the two components AND the
# two separators, which is why `String.take` keeps a leading `/`. A fold and not
# two `List.get`s because a `Maybe` read is once-only and `n < 2` would need a
# `Nat` subtraction that underflows rather than a None.
type Ac is Data:
  Ac{acc: U32, prev: U32}

def Ac.acc(a: Ac) -> U32:
  match a:
    case Ac{acc, prev}: acc

def ac.step(+x: String, a: Ac) -> Ac:
  match a:
    case Ac{acc, prev}:
      Ac{U32.add(prev, U32.add(1, U32.from_nat(String.length(x)))), U32.add(1, U32.from_nat(String.length(x)))}

def ac.go(n: Nat, xs: List<&2, String>, a: Ac) -> Ac:
  match n:
    case 0n: a
    case 1n+m:
      match xs:
        case Nil{}: a
        case h <> t: ac.go(m, t, ac.step(h, a))

def tail2.at(n: Nat, xs: List<&2, String>) -> U32: Ac.acc(ac.go(n, xs, Ac{0, 0}))

def tail2.at2(+s: String) -> U32:
  tail2.at(List.length(&2, String, String.split(s, SLASH_C())), String.split(s, SLASH_C()))

# pathlib answers `'.'` when there is nothing left and `'/'` when the path was
# rooted and there is nothing left -- and "nothing left" means TWO OR FEWER
# COMPONENTS, not one, because `Path('nn/torch.py').parent` is `'nn'` and
# `.parent` of THAT is `'.'`. MEASURED, all four of these:
#   'torch.py' -> '.'   'nn/torch.py' -> '.'   '/torch.py' -> '/'
#   'tinygrad/nn/torch.py' -> 'tinygrad'
def drop2.at(n: Nat, rooted: Bool, tail: U32, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+m:
      Bool.pick(String, U32.is_le(U32.from_nat(m), 1),
        Bool.pick(String, rooted, ROOT_SLASH(), DOT()),
        String.take(s, Nat.sub(String.length(s), U32.to_nat(tail))))

def drop2(+s: String) -> String:
  drop2.at(List.length(&2, String, String.split(s, SLASH_C())), String.starts_with(s, SLASH()),
           tail2.at2(s), s)

# nn/torch.py:3 `-- `PurePath.as_posix()`. A char fold and not a `String.replace`,
# because base.bend exports no `replace`. It is a no-op on POSIX and a rewrite
# on Windows, and the fixture set pins BOTH, because a fold that mapped every
# character to `'/'` would pass the POSIX rows and fail the Windows one.
def posix.put(+h: Char, +acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, acc, [Bool.pick(Char, Char.is_eq(h, BSLASH_C()), SLASH_C(), h)])

def posix.go(n: Nat, cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case h <> t: posix.go(m, t, posix.put(h, acc))

def as_posix(+s: String) -> String:
  String.from_list(posix.go(List.length(&2, Char, String.to_list(s)), String.to_list(s), Nil{}))

# nn/torch.py:2-5, the whole of it, as three steps.

def Imp.of() -> Imp: Imp{Nil{}, Tr.of()}

def Imp.path(x: Imp) -> List<&2, String>:
  match x:
    case Imp{path, t}: path

def Imp.tr(x: Imp) -> Tr:
  match x:
    case Imp{path, t}: t

def root_of(f: String) -> String: as_posix(drop2(f))

# :3 -- ONE `sys.path.append`, LAST, with no dedup and no prepend. The argument
# is derived BEFORE the call is recorded, because that is Python's own order and
# because a `Bool.pick` arm that builds a structure has to bind it first
# (bend2-constraints.md, position 4930).
def shim.append(f: String, imp: Imp) -> Imp:
  match imp:
    case Imp{path, t}: Imp{List.append(&2, String, path, [root_of(f)]), Tr.emit(CALL_PATH_APPEND(), 0, t)}

# :4-5 -- the import and the refusal. ONE def, because `try:`/`except` is one
# statement pair and splitting it would let the gate pass a version that imports
# without ever being able to refuse.
def shim.import(ok: Bool, imp: Imp) -> Imp:
  match imp:
    case Imp{path, t}: Imp{path, Tr.raise.at(ok, Tr.emit(CALL_IMPORT(), 0, t))}

def shim.run(f: String, ok: Bool) -> Imp: shim.import(ok, shim.append(f, Imp.of()))

# THE GATE. Every row is a claim about nn/torch.py's TEXT or about a value
# MEASURED by importing `tinygrad.nn.torch` in CPython. `1`/`0` are booleans,
# other values are counts, indices and strings.
# THE GATE MOVED TO `gates/torch-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Every expectation in the driver is generated by calling CPython, so no row
# there is typed by hand.
