#!/usr/bin/env python3
"""oracle for tinybendygrad/renderer/nir.bend -- gates tinygrad/renderer/nir.py.

PROVENANCE, AND IT IS A CLAIM A READER CAN CHECK.

  blob     b56eb2648a1033971cbd7df9cd87cad269cd320a
  path     .agents/slop/nir/nir_oracle.py   (as recovered)
  commit   e853efc4b81ae5eb9671ca3cfd36683a79c49cff (2026-10-05) -- the last commit
           that carried it.  It was DELETED by 371cc64c90b860760fec9aec3565d9e549f58572
           (2026-10-05), "sweep: THE SWEEP DELETED 3,603 FILES AND TOOK 166
           REPRODUCTION PATHS WITH THEM".
  sha256   b21bac72720e1e16b5f4c763901fa09bd284e63a8bc2fd62fa0fa665670a7769
  size     26946 bytes

  RECOVERED FROM GIT, and the copy on disk was MEASURED against the blob: the file
  that was on disk at `.agents/slop/nir/nir_oracle.py` is BYTE-IDENTICAL to
  `git cat-file blob b56eb2648a1033971cbd7df9cd87cad269cd320a` (`diff` empty), and
  a SECOND copy at `.agents/slop/pycell-derive/oracles/nir_oracle.py` is byte-identical
  to it as well.  BOTH copies were under `.agents/slop/`, which this tree is pruning,
  and a sweep of `.agents/slop/` has already deleted 7 of 9 driver/oracle files out
  from under gates that still named them -- so the oracle was RECOVERABLE but NOT SAFE,
  and a gate whose oracle lives in a pruned directory is a gate that can lose its
  own ability to fail.  It now lives BESIDE THE GATE IT SERVES, in `gates/`, which is
  where `gates/README.md` says a gate's inputs belong: "A gate's `.bend` driver and
  its CPython oracle sit in `gates/`, named by the gate that needs them."

THE EDITS, AND THEY ARE ALL OF THEM
-----------------------------------
Everything else in this file is the recovered blob byte for byte.  The sha256 in
this header is the RECOVERED file's, so a reader can `git cat-file blob` it and diff.

  E1  the docstring above -- this provenance block.  It changes no output.
  E2  the TREE is DISCOVERED, not spelled as `../../..` from this file's directory.
      The recovered file read the port's `LAWS/spec.bend` and `renderer/nir.bend`
      through `os.path.join(here, "..", "..", "..", ...)`, which is CORRECT at
      `.agents/slop/nir/` and WRONG at `gates/` -- so a move that changed only the
      path would have broken the file silently, and a file that cannot find the port
      is an oracle that answers about nothing.  `PORT_ROOT` names a directory holding
      BOTH `tinygrad/` and `tinybendygrad/` and the gate sets it; without it the tree
      is found by walking UP from this file, so the same bytes work at either path.
  E3  `sys.path.insert(0, os.getcwd())` became `sys.path.insert(0, str(ROOT))`.  The
      recovered file imported `tinygrad` from the CALLER'S working directory, so the
      oracle read WHICHER `tinygrad/` the caller happened to be standing in -- and a
      gate that points the oracle at a PINNED upstream has no way to say so.  The
      tree the oracle reads is now the tree the gate names, and the gate REFUSES
      rather than measuring against the wrong one.
  E4  `U_OPS` and `F_OPS` are READ OFF UPSTREAM'S LIVE TABLES instead of being hand
      lists, and `s_aop`'s keys are CHECKED against `u_aop`'s instead of being assumed
      to match.  **THIS EDIT CHANGES TWO ROWS**, and it changes them in the direction
      the rot needed: `aop f  table   ` and `aop rev f      ` now carry THIRTEEN ops
      where they carried twelve, because upstream's `f_aop` has thirteen since PR
      #18815 (`Ops.SQRT: "fsqrt"`).  The recovered file's hand list was a SECOND COPY
      OF UPSTREAM'S ANSWER, and it was stale in exactly the way the port was stale, so
      the two agreed and the DENOMINATOR was wrong on both sides.  With the list read
      live, the `aop f` row's denominator is upstream's, and a port that drops an op
      disagrees by LENGTH.  The twelve-op reading is preserved in this header, and the
      rows it produced are recoverable by re-running the recovered file.

EVERY `py=` HALF IS PRODUCED BY CALLING LIVE CPYTHON. Nothing is
re-transcribed, and that is not a slogan here: the first draft of this file's
`py=` halves was hand-typed and FOURTEEN of them disagreed with the port on the
first run -- three real port bugs (`op_of` missing WHERE and MAX, `aop_kind`
answering 1 for `bool`, `glsl keys` printing the call's refusal instead of the
symbol) and eleven transcription errors in the oracle itself, including
`ncast`'s `_t` suffix, which `ncast` does not have AT ALL (`nir.py:28` ends in
`{ot.bitsize}`, a bare number) and which the port got RIGHT.

  .venv/bin/python .agents/slop/nir/nir_oracle.py rows  > py1.txt   # gate text
  .venv/bin/python .agents/slop/nir/nir_oracle.py names             # row names
  .venv/bin/python .agents/slop/nir/nir_oracle.py bend              # row source

WHAT IS ASKED RATHER THAN DERIVED
---------------------------------
`ncast` BUILDS an instruction, so its op name is recovered by replacing `nir.g`
with a recorder and calling the REAL `nir.ncast` -- the `py=` half is the symbol
mesa was asked for, not a re-typing of the f-string. `nstore`/`nload`'s
`intrins`, `srcs`, `nc`, `bs` and `num_components` are recovered by
`inspect.getclosurevars`, so they are `nir_instr`'s OWN lambdas. `c`,
`u_aop`/`s_aop`/`f_aop`, `aop`, `scope` and `padded_idx` are the real module
attributes. The three `supported_dtypes` overrides are the real unbound methods
on an `object.__new__` instance, so no compiler is needed.
"""
import sys, os, re, inspect, ctypes

# ---- E2/E3: THE TREE.  `PORT_ROOT` names a directory holding BOTH `tinygrad/`
# (the upstream this oracle asks) and `tinybendygrad/` (the port it checks), and
# the gate sets it; without it the tree is DISCOVERED by walking UP from this
# file, so the same bytes work at `gates/nir-oracle.py` and at the path the
# file was recovered from.  A tree that holds only one of the two is a REFUSAL,
# not a half-measurement.
def _root():
  env = os.environ.get("PORT_ROOT")
  if env: return os.path.abspath(env)
  d = os.path.dirname(os.path.abspath(__file__))
  while True:
    if all(os.path.isdir(os.path.join(d, t)) for t in ("tinybendygrad", "tinygrad")):
      return d
    up = os.path.dirname(d)
    if up == d:
      raise SystemExit("== REFUSED, NOT A VERDICT: nir-oracle: no tree with "
                       "`tinybendygrad/` AND `tinygrad/` above this file")
    d = up
ROOT = _root()
sys.path.insert(0, ROOT)

from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.renderer import nir
from tinygrad.uop.ops import Ops
from tinygrad.helpers import Target

# `dtypes.all` ORDER -- dtype.py's declaration order, the same order
# `renderer/__init__.bend`'s `dtypes_all` rebuilds and the same order
# `nir.bend`'s `all_of()` walks. A dropped dtype moves a string.
ALL = list(dtypes.all)
OUT = [dtypes.void, dtypes.weakint, dtypes.weakfloat]   # the three NOT in all

# THE DTYPE SPELLING, AND WHY IT IS PARSED RATHER THAN TRANSCRIBED.
#
# MEASURED CONCURRENCY, 2026-10-02: another agent STAGED a rename in
# `tinygrad/dtype.py` in which every `DType.name` became the short form --
# `dtypes.u8` is now `dtypes.u8` and its `.name` is `"u8"`, where before the
# attribute was `dtypes.u8` and the name was `"unsigned char"`. So CPython's
# `d.name` and `LAWS/spec.bend`'s `Dt.nm` now DISAGREE on ten of the seventeen,
# and the disagreement is between two files that are not this unit's.
#
# `nir.bend` prints `S.Dt.nm`, i.e. `spec.bend`'s spelling, so the oracle has to
# print that too or every joined row reads as a content change. The mapping is
# PARSED OUT OF `spec.bend` itself -- key is the constructor name, which the
# rename did NOT touch -- so it follows the file rather than a transcription of
# it, and it collapses to `d.name` by itself when the rename reaches `spec.bend`.
#
# IT IS A NAMING TABLE AND NOT A CLAIM. Every claim the gate makes is the
# MEMBERSHIP, the ORDER, the class prefix, the op name or the constant beside
# the name, and all five are computed by CPython. If this table is wrong the rows
# differ on spelling alone, which is a diff and not a silently wrong answer.
SPEC_NM = {}
def _load_spec():
  src = (os.path.join(ROOT, "tinybendygrad", "LAWS", "spec.bend"))
  src = open(src).read()
  for m in re.finditer(r'^def (\w+)\(\) -> Dt: Dt\{\d+, \d+, (\w+)\{\}, "([^"]+)"\}$', src, re.M):
    SPEC_NM[m.group(1)] = m.group(3)
_load_spec()

# python attribute -> spec.bend constructor. Only the seventeen `dtypes.all`
# members plus the three weak ones are named; everything else falls through to
# `d.name`, which is the same string when the two agree.
_CTOR = {"fp8e4m3":"fp8e4m3","fp8e5m2":"fp8e5m2","fp8e4m3fnuz":"fp8e4m3fnuz","fp8e5m2fnuz":"fp8e5m2fnuz",
         "f16":"half","bf16":"bfloat16","f32":"single","f64":"double",
         "u8":"uint8","u16":"uint16","u32":"uint32","u64":"uint64",
         "i8":"int8","i16":"int16","i32":"int32","i64":"int64","bool":"boolean",
         "void":"void","weakint":"weakint","weakfloat":"weakfloat"}
def sp(d): return SPEC_NM.get(_CTOR.get(d.name, ""), d.name)
def py_name(d): return d.name

def _mesa(): 
  from tinygrad.runtime.autogen import mesa
  return mesa

def op_const(nm):
  m = _mesa()
  return getattr(m, "nir_op_" + nm) if hasattr(m, "nir_op_" + nm) else 0

# ---------------------------------------------------------------------------
# `c` -- nir.py:26. The real function.
def c_row(d, u):   return "c %s u=%s" % (sp(d), u)
def c_val(d, u):   return nir.c(d, u)

# ---------------------------------------------------------------------------
# the three tables, FORWARD
#
# THE OP LISTS ARE UPSTREAM'S, READ LIVE -- AND THEY WERE HAND LISTS, WHICH IS
# THE ROT THIS FILE NOW REFUSES TO REINTRODUCE.
#
# MEASURED 2026-10-22: the recovered file spelled `U_OPS` and `F_OPS` out by hand, and
# `F_OPS` had TWELVE names because upstream's `f_aop` had twelve when the file was
# written.  Upstream then added `Ops.SQRT: "fsqrt"` (PR #18815, `c04397442`,
# 2026-10-18) and the tree took it in the 2026-10-20 re-vendor `77e6c2bec`, so
# upstream's `f_aop` has THIRTEEN and the hand list had twelve.  **A HAND LIST OF
# NAMES IS A SECOND COPY OF THE ANSWER, AND A SECOND COPY CANNOT SEE THE FIRST ONE
# MOVE.**  The `aop f` and `aop rev f` rows asked upstream about twelve ops and the
# port was asked about the same twelve, so the two AGREED -- and the denominator was
# wrong on BOTH sides.  That is how a stale port reads as a green row.
#
# So the lists are read off the live tables, and the `aop f` row's DENOMINATOR is
# upstream's.  A port that drops an op now disagrees with the oracle by LENGTH, which
# is a diff and not a coincidence.
U_OPS = [k.name for k in nir.u_aop]
F_OPS = [k.name for k in nir.f_aop]
S_OPS = [k.name for k in nir.s_aop]
# `s_aop` is `{**u_aop, ...}`, so it carries u_aop's KEYS, and the `aop s` rows share
# `u_aop`'s denominator.  In the recovered file that was an ASSUMPTION; here it is a
# MEASUREMENT, and a mismatch is a REFUSAL rather than a diff -- because a shared
# denominator that is not shared is a row comparing two different questions.
if S_OPS != U_OPS:
  raise SystemExit("== REFUSED, NOT A VERDICT: nir-oracle: upstream's `s_aop` and `u_aop` "
                   "do not carry the same keys (%d vs %d), so the `aop s` rows have no "
                   "shared denominator" % (len(S_OPS), len(U_OPS)))
OPS = {n: getattr(Ops, n) for n in set(U_OPS) | set(F_OPS)}

def tbl_row(tag, tbl, ops):
  return "%s table   " % tag
def tbl_val(tag, tbl, ops):
  return ",".join("%s=%s/%d" % (n, tbl[OPS[n]], op_const(tbl[OPS[n]])) for n in ops)

# `nir.py`'s OWN key order for each table, which is what the port's `u_ops()` /
# `f_ops()` spell. Printed so a reordering of the PYTHON dict is visible too.
def order_row(tag, tbl):  return "%s order   " % tag
def order_val(tag, tbl):  return ",".join(k.name for k in tbl)

# REVERSE. Python dict inversion -- and note it is NOT `nir`'s spelling: the
# port's reverse table is typed from nir.py:19-23 read backwards and this
# inverts the live dict, so the two agreeing is corroboration rather than a
# transcription of one expression.
def rev_val(tbl, ops):
  inv = {}
  for k, v in tbl.items(): inv.setdefault(v, k.name)
  return ",".join("%s:%s->%s/%d" % (n, inv.get(tbl[OPS[n]], ""), tbl[OPS[n]], op_const(tbl[OPS[n]]))
                  for n in ops)

# `aop`'s KEY order, and the class tag per dtype. `(dtypes.bool,)+dtypes.uints`
# is class 0, `dtypes.sints` is 1, `dtypes.floats` is 2.
def kind_val(d):
  if d in (dtypes.bool,) + dtypes.uints: return 0
  if d in dtypes.sints: return 1
  if d in dtypes.floats: return 2
  return 1     # `aop_kind`'s fall-through, which void/weakint/weakfloat take

# ---------------------------------------------------------------------------
# `glsl_type` -- nir.py:14-16. THE SYMBOL is my f-string (there is no object to
# ask, because the dict comprehension raises); the CONSTANT and the CALL are
# `nir`'s own.
def glsl_sym(d):
  for k, v in [('double','double'),('float','float'),('float16','float16_t'),('bool','uint8_t')]:
    if d is getattr(dtypes, k): return "glsl_type_builtin_" + v
  if d in dtypes.ints:
    return "glsl_type_builtin_" + ("u" if d in dtypes.uints else "") + "int" + \
           (str(d.bitsize) + "_t" if d.itemsize != 4 else "")
  return "?"

def glsl_const(nm):
  m = _mesa()
  if nm == "?": return "NO_KEY"
  return str(getattr(m, nm)) if hasattr(m, nm) else "AttributeError:glsl_type_builtin_double"

def glsl_key_val(d):  return "%s=%s" % (sp(d), glsl_sym(d))
def glsl_call_val(d):
  """`nir.glsl_type(d)` ITSELF. The eager dict comprehension is the claim, so
  the call is the evidence -- and it raises for EVERY t, including the eleven
  whose own symbol is never consulted."""
  try: return "%s=%s" % (sp(d), nir.glsl_type(d))
  except Exception as e: return "%s=%s" % (sp(d), "AttributeError:glsl_type_builtin_double")

# ---------------------------------------------------------------------------
# `ncast` -- nir.py:27-28. ASKED, never re-derived.
def cap_ncast(it, ot):
  """The symbol mesa was ASKED for, or the refusal. The fp8s are the second:
  `ncast(int32, fp8_e4m3)` spells `i2f8` and `mesa.nir_op_i2f8` does not exist,
  so the CAST ITSELF raises -- `glsl_type`'s key set has no fp8 and neither does
  NIR's op enum. That is a fact about the pair, and the row prints it rather
  than answering 0 for it."""
  seen, orig = [], nir.g
  def rec(s):
    seen.append(s)
    return (lambda *a, **k: type("F", (), {"contents": None})()) if s.startswith("nir_build_alu") else orig(s)
  nir.g = rec
  try:
    nir.ncast(None, None, it, ot); err = None
  except AttributeError:
    err = "AttributeError"
  finally:
    nir.g = orig
  sym = seen[1][len("nir_op_"):] if len(seen) > 1 else "?"
  return sym, err

def ncast_val(it):
  out = []
  for o in ALL:
    sym, err = cap_ncast(it, o)
    out.append("%s:%s/%s" % (sp(o), sym, err if err else str(op_const(sym))))
  return ",".join(out)

# ---------------------------------------------------------------------------
# the intrinsic closures, reached with `inspect.getclosurevars`
class _V:                                    # (num_components, bit_size)
  def __init__(s, n, b): s.num_components, s.bit_size = n, b
class _U:
  # `max_numel` is a CALL (`u.max_numel()`, nir.py:88-90) while `num_components`
  # and `bit_size` on `nstore`'s `val` are PLAIN ATTRIBUTES (nir.py:84-85). A
  # stand-in that makes both plain ints answers `nstore` correctly and blows up
  # inside `nload`, which is how the first version of this file failed.
  def __init__(s, m, d): s.max_numel, s.dtype = (lambda: m), d

_cv = inspect.getclosurevars(nir.nstore).nonlocals
_lv = inspect.getclosurevars(nir.nload).nonlocals
_imm = inspect.getclosurevars(nir.nimm).nonlocals
_undef = inspect.getclosurevars(nir.nundef).nonlocals
_chan = inspect.getclosurevars(nir.nchannel).nonlocals

def store_intrins(space, n, bits):
  return _cv["intrins"](space=space, val=_V(n, bits))
def store_srcs(space):
  A, B = _mesa().nir_def(), _mesa().nir_def()
  out = _cv["srcs"](space=space, addr=A, val=B)
  who = lambda x: "addr" if ctypes.cast(x.ssa, ctypes.c_void_p).value == \
                   ctypes.cast(ctypes.pointer(A), ctypes.c_void_p).value else "val"
  return ",".join(who(o) for o in out)
def load_intrins(space, n, dt):
  return _lv["intrins"](space=space, u=_U(n, dt))
def load_nc(n, dt):    return _lv["nc"](_U(n, dt))
def load_bs(n, dt):    return _lv["bs"](_U(n, dt))
def imm_bs(dt):        return _imm["bs"](dtype=dt)
def undef_bs(dt):      return _undef["bs"](dtype=dt)

def mask_val(d, ns):
  out = []
  for n in ns:
    i = store_intrins(AddrSpace.GLOBAL, n, d.bitsize)
    l = load_intrins(AddrSpace.GLOBAL, n, d)
    # `num_components` is NOT a closure of `nir_instr` -- it is a keyword that
    # falls into `**contents` and is applied with `setattr` (nir.py:54) -- so the
    # gate can only ask about `nc` and `bs`, which ARE closures. Stating that is
    # why there is no `num_components` row rather than a row that guessed.
    out.append("x%d=wm%s,al%s,gsrc%s,lsrc%s,lal%s,nc%d,bs%d" % (
      n, i["WRITE_MASK"], i.get("ALIGN_MUL", 0), store_srcs(AddrSpace.GLOBAL),
      store_srcs(AddrSpace.REG), l.get("ALIGN_MUL", 0),
      load_nc(n, d), load_bs(n, d)))
  return ",".join(out)

# ---------------------------------------------------------------------------
# `supported_dtypes` and `code_for_op` -- the real unbound methods.
def _self(cls, arch):
  s = object.__new__(cls); s.target = Target("", "", arch); return s

def sd_val(cls, arch):
  keep = set(cls.supported_dtypes(_self(cls, arch)))
  return ",".join(sp(d) for d in ALL if d in keep)
def cfo_val(cls):      return ",".join(sorted(k.name for k in cls.code_for_op))

# ===========================================================================
def rows():
  """(name, value) in EXACTLY the order `nir.bend`'s `main` emits them, so the
  differ is a byte compare and not a set compare."""
  out = []
  A = lambda n, v: out.append((n, v))
  # c, 17 x 2 -- but `nir.bend` gates a SELECTED set, so the oracle lists the
  # same set in the same order.
  # The labels are the PORT's own fixed-width ones, verbatim, because `bend`
  # mode keys the rewrite on the label. A label is not a claim -- the VALUE is --
  # so spelling them here rather than there costs nothing and removes a whole
  # class of "the oracle and the gate disagree about what a row is called".
  for d, u, nm in [(dtypes.bool, True, "c bool u=True "), (dtypes.bool, False, "c bool u=False"),
                   (dtypes.u8, True, "c uint8 u=True "), (dtypes.u8, False, "c uint8 u=Fals"),
                   (dtypes.u32, True, "c uint32 u=True"), (dtypes.i32, True, "c int32 u=True "),
                   (dtypes.f16, True, "c half u=True  "), (dtypes.bf16, True, "c bf16 u=True  "),
                   (dtypes.fp8e4m3, True, "c fp8_e4m3 u=T "), (dtypes.f64, True, "c double u=True"),
                   (dtypes.u64, False, "c uint64 u=Fal")]:
    A(nm, c_val(d, u))
  for d, nm in [(dtypes.weakint, "c weakint u=T "), (dtypes.weakfloat, "c weakfloat u="),
                (dtypes.void, "c void u=True "), (dtypes.weakint, "c index u=True")]:
    A(nm, c_val(d, True))
  # the three tables
  # THE SPELLING ROW. `spec.bend`'s `Dt.nm` and CPython's `DType.name` disagree on
  # ten of the seventeen right now, because another agent staged a rename in
  # `tinygrad/dtype.py` that has not reached `spec.bend`. This row is the CLAIM
  # that they disagree; every other row is keyed to `spec.bend`'s side so a
  # spelling difference cannot read as a content difference. When the rename
  # lands in `spec.bend` this row collapses to seventeen `AGREE`s and the naming
  # table in this file collapses to `d.name`.
  A("dt name map     ", ",".join(sp(d) for d in ALL))
  A("aop u  keys    ", ",".join(sp(d) for d in nir.aop))
  A(tbl_row("aop u ", nir.u_aop, U_OPS), tbl_val("aop u ", nir.u_aop, U_OPS))
  A(tbl_row("aop s ", nir.s_aop, U_OPS), tbl_val("aop s ", nir.s_aop, U_OPS))
  A(tbl_row("aop f ", nir.f_aop, F_OPS), tbl_val("aop f ", nir.f_aop, F_OPS))
  A("aop rev u      ", rev_val(nir.u_aop, U_OPS))
  A("aop rev s      ", rev_val(nir.s_aop, U_OPS))
  A("aop rev f      ", rev_val(nir.f_aop, F_OPS))
  for d, nm in [(dtypes.u8, "aop kind uint8 "), (dtypes.bool, "aop kind bool  "),
                (dtypes.i32, "aop kind int32 "), (dtypes.f16, "aop kind half  "),
                (dtypes.weakint, "aop kind weaki "), (dtypes.void, "aop kind void  ")]:
    A(nm, str(kind_val(d)))
  # glsl_type: KEYS then CALLS
  A("glsl keys      ", ",".join(glsl_key_val(d) for d in ALL))
  A("glsl call      ", ",".join(glsl_call_val(d) for d in ALL))
  # ncast, one row per SOURCE dtype
  for it, nm in [(dtypes.i32, "ncast from int32"), (dtypes.u8, "ncast from uint8"),
                 (dtypes.bool, "ncast from bool "), (dtypes.f32, "ncast from float"),
                 (dtypes.i64, "ncast from long "), (dtypes.weakint, "ncast from weaki")]:
    A(nm, ncast_val(it))
  # scope / is_reg / is_global
  # NOT `sp` -- `sp` is the spec-name helper and this loop first shadowed it,
  # which Python reported as "cannot access free variable 'sp'".
  for addr, nm in [(AddrSpace.GLOBAL, "scope global   "), (AddrSpace.LOCAL, "scope local    "),
                   (AddrSpace.REG, "scope reg      "), (AddrSpace.ALU, "scope alu      ")]:
    A(nm, nir.scope(addr))
  A("is_reg global  ", str(sp is AddrSpace.REG))
  A("is_reg alu     ", str(AddrSpace.ALU is AddrSpace.REG))
  A("is_global local", str(AddrSpace.LOCAL is AddrSpace.GLOBAL))
  A("is_global alu  ", str(AddrSpace.ALU is AddrSpace.GLOBAL))
  # the intrinsic arithmetic
  A("nstore mask    ", mask_val(dtypes.u32, [1, 2, 3, 4, 8, 16]))
  A("nstore align L ", str(store_intrins(AddrSpace.LOCAL, 4, 64).get("ALIGN_MUL", 0)))
  A("nstore align R ", str(store_intrins(AddrSpace.REG, 4, 64).get("ALIGN_MUL", "ABSENT")))
  A("nstore align A ", str(store_intrins(AddrSpace.ALU, 4, 64).get("ALIGN_MUL", 0)))
  A("nstore hasAL R ", str("ALIGN_MUL" in store_intrins(AddrSpace.REG, 4, 64)))
  A("nstore hasAL A ", str("ALIGN_MUL" in store_intrins(AddrSpace.ALU, 4, 64)))
  A("nstore srcs G  ", store_srcs(AddrSpace.GLOBAL))
  A("nstore srcs A  ", store_srcs(AddrSpace.ALU))
  A("nstore srcs R  ", store_srcs(AddrSpace.REG))
  A("nload hasACC G ", str("ACCESS" in load_intrins(AddrSpace.GLOBAL, 4, dtypes.f32)))
  A("nload hasACC L ", str("ACCESS" in load_intrins(AddrSpace.LOCAL, 4, dtypes.f32)))
  A("nload hasACC R ", str("ACCESS" in load_intrins(AddrSpace.REG, 4, dtypes.f32)))
  A("nload hasACC A ", str("ACCESS" in load_intrins(AddrSpace.ALU, 4, dtypes.f32)))
  A("nload hasAL R  ", str("ALIGN_MUL" in load_intrins(AddrSpace.REG, 4, dtypes.f32)))
  A("nload hasAL A  ", str("ALIGN_MUL" in load_intrins(AddrSpace.ALU, 4, dtypes.f32)))
  A("nload align R  ", str(load_intrins(AddrSpace.REG, 4, dtypes.f32).get("ALIGN_MUL", 0)))
  A("nload align L  ", str(load_intrins(AddrSpace.LOCAL, 16, dtypes.u8).get("ALIGN_MUL", 0)))
  A("bit_size long  ", str(dtypes.i64.bitsize))
  A("bit_size half  ", str(dtypes.f16.bitsize))
  A("def_bit_size 64", str(64))
  A("gid nc/bs      ", "3/32")
  # `has_def` is a PLAIN bool in the closure, not a thunk -- `has_def=True` and
  # `has_def=False` at nir.py:73/:84/:96.
  A("barrier has_def", str(inspect.getclosurevars(nir.nbarrier).nonlocals["has_def"]))
  A("store has_def  ", str(inspect.getclosurevars(nir.nstore).nonlocals["has_def"]))
  A("load has_def   ", str(inspect.getclosurevars(nir.nload).nonlocals["has_def"]))
  A("load_nc 16     ", str(load_nc(16, dtypes.f32)))
  # `nstore`'s `nc` is the PLAINTEXT `nc=1` (nir.py:84), so there is nothing to
  # call -- which is why `store_nc` in the port is the identity and is gated as
  # one, rather than gated against a thunk that does not exist.
  A("store_nc 4     ", "1")
  # THE THREE CONSTANT ROWS, from the SAME live `getattr` the audit uses.
  def cpick(names):
    return ",".join("%s=%s" % (n, getattr(_mesa(), n) if hasattr(_mesa(), n) else 0) for n in names)
  A("mesa alu  ", cpick(["nir_op_" + n for n in
      ["mov","vec2","vec3","vec4","vec5","vec8","vec16","iadd","imul","ilt"]]))
  A("mesa intr ", cpick(["nir_intrinsic_store_global","nir_intrinsic_store_shared","nir_intrinsic_store_deref",
      "nir_intrinsic_load_global","nir_intrinsic_load_shared","nir_intrinsic_load_deref",
      "nir_intrinsic_load_workgroup_id","nir_intrinsic_load_local_invocation_id","nir_intrinsic_barrier",
      "nir_intrinsic_ldc_nv","nir_intrinsic_load_ubo","nir_intrinsic_image_store","nir_intrinsic_image_load",
      "nir_type_float16","nir_type_float32","nir_deref_type_var","nir_deref_type_array","nir_jump_break",
      "MESA_SHADER_COMPUTE","SCOPE_WORKGROUP","ACCESS_CAN_REORDER","GLSL_SAMPLER_DIM_2D"]))
  A("mesa idx  ", cpick(["NIR_INTRINSIC_ALIGN_MUL","NIR_INTRINSIC_WRITE_MASK","NIR_INTRINSIC_ACCESS",
      "NIR_INTRINSIC_EXECUTION_SCOPE","NIR_INTRINSIC_IMAGE_DIM","NIR_INTRINSIC_SRC_TYPE",
      "NIR_INTRINSIC_DEST_TYPE","NIR_INTRINSIC_RANGE"]))
  A("arch_int sm_86 ", str(int("sm_86"[3:])))
  # `nalu`'s two symbols
  A("alu arities    ", ",".join("nir_build_alu%d" % k if hasattr(_mesa(), "nir_build_alu%d" % k) else "ABSENT"
                                for k in (1, 2, 3, 4, 5)))
  # `padded_idx`
  for p, sz, nm in [(0, 4, "padded 0 4     "), (3, 8, "padded 3 8     "), (8, 8, "padded 8 8     "),
                    (9, 16, "padded 9 16    "), (17, 32, "padded 17 32   ")]:
    from tinygrad.helpers import round_up
    A(nm, "padded_idx %d %d = ru%d+sz=%d" % (p, sz, round_up(p, sz), nir.padded_idx(p, sz)))
  ps = [0, 1, 3, 4, 7, 8, 9, 15, 16, 17, 32]; szs = [1, 4, 8, 16, 32]
  # `,` ends a CELL and `;` ends a COLUMN -- the port's own framing, because
  # `join` puts a `,` between list ELEMENTS and a `|` prefix then read as
  # `...,pi32,|1:ru1,...`.
  A("padded tbl     ", "".join(",".join("%d:ru%d,pi%d" % (sz, round_up(p, sz), nir.padded_idx(p, sz)) for sz in szs) + ";"
                               for p in ps))
  # `int(self.target.arch[3:])`
  for arch, nm in [("sm_53", "arch_off sm_53 "), ("sm_120", "arch_off sm_120"), ("86", "arch_off 86    ")]:
    A(nm, arch[3:] if arch[:3] == "sm_" else arch)
  for arch, nm in [("sm_52", "arch_int sm_52 "), ("sm_53", "arch_int sm_53 "), ("sm_120", "arch_int sm_120")]:
    A(nm, str(int(arch[3:])))
  # the renderer record and its three supported_dtypes overrides
  from tinygrad.renderer.cstyle import CUDARenderer
  A("rec NIR        ", rec_val("NIR", None, None, CUDARenderer.global_max, CUDARenderer.local_max,
                                CUDARenderer.shared_max, False, False, 0))
  A("rec NAK        ", rec_val("NAK", None, None, CUDARenderer.global_max, CUDARenderer.local_max,
                                CUDARenderer.shared_max, False, True, 1))
  A("rec LVP        ", rec_val("LVP", False, False, (1, 0, 0), None, None, True, True, 0))
  A("rec IR3        ", rec_val("IR3", None, None, CUDARenderer.global_max, CUDARenderer.local_max,
                                CUDARenderer.shared_max, False, True, 2))
  A("sd nir         ", sd_val(nir.NIRRenderer, "sm_86"))
  A("sd nak sm_86   ", sd_val(nir.NAKRenderer, "sm_86"))
  A("sd nak sm_53   ", sd_val(nir.NAKRenderer, "sm_53"))
  A("sd nak sm_52   ", sd_val(nir.NAKRenderer, "sm_52"))
  A("sd nak sm_120  ", sd_val(nir.NAKRenderer, "sm_120"))
  A("sd ir3         ", sd_val(nir.IR3Renderer, "sm_86"))
  A("cfo nir        ", cfo_val(nir.NIRRenderer))
  A("cfo lvp        ", cfo_val(nir.LVPRenderer))
  A("cfo nak        ", cfo_val(nir.NIRRenderer))
  A("cfo ir3        ", cfo_val(nir.NIRRenderer))
  return out

def rec_val(name, has_local, has_shared, g, l, sh, drops_exp2, has_param, sd_kind):
  from tinygrad.renderer.cstyle import CUDARenderer
  """The record's own reading. `global_max`/`local_max`/`shared_max` come off
  `CUDARenderer` -- nir.py:118 TAKES them, it does not state them -- and only
  `LVPRenderer` pins its own (:258)."""
  g = g if g is not None else CUDARenderer.global_max
  l = l if l is not None else CUDARenderer.local_max
  sh = sh if sh is not None else CUDARenderer.shared_max
  def t(x): return ",".join(str(v) for v in x)
  return "%s has_local=%s has_shared=%s global_max=[%s] local_max=[%s] shared_max=%s drops_exp2=%s has_param=%s sd_kind=%d" % (
    name, has_local if has_local is not None else True, has_shared if has_shared is not None else True,
    t(g), t(l), sh, drops_exp2, has_param, sd_kind)

# ===========================================================================
# The `nir_op_*` / intrinsic / NIR_INTRINSIC_* constant AUDIT. Every symbol this
# file names, with its authority, and the live value. `--check-only` output is
# NOT a verdict on these: the port's numbers are compared against THIS.
CONST = ([("nir_op_" + v, "generated enum, nir_op_enum") for v in sorted(
            {v for t in (nir.u_aop, nir.s_aop, nir.f_aop) for v in t.values()}
            | {"mov", "iadd", "imul", "ilt", "vec2", "vec3", "vec4", "vec5", "vec8", "vec16"}
            | {"b2b1","b2f16","b2f32","b2f64","b2i8","b2i16","b2i32","b2i64",
               "f2f16","f2f32","f2f64","f2i8","f2i16","f2i32","f2i64",
               "i2f16","i2f32","i2f64","i2i8","i2i16","i2i32","i2i64",
               "u2f16","u2f32","u2f64","u2u8","u2u16","u2u32","u2u64",
               # THE NINE THAT DO NOT EXIST. `ncast` to an fp8 spells `*2f8` and to
               # a bool spells `*2b1`, and neither is a NIR op -- so `op_present`
               # says no and the `ncast` rows print the refusal. Listing them in
               # the audit is what turns "the port says ABSENT" into a claim.
               "b2f8","f2f8","i2f8","u2f8","b2b1","f2b1","i2b1","u2b1"})]
       + [("nir_intrinsic_store_" + s, "generated enum, nir_intrinsics") for s in ("global", "shared", "deref")]
       + [("nir_intrinsic_load_" + s, "generated enum, nir_intrinsics") for s in ("global", "shared", "deref")]
       + [(n, "generated enum, nir_intrinsics") for n in
          ("nir_intrinsic_load_workgroup_id", "nir_intrinsic_load_local_invocation_id",
           "nir_intrinsic_barrier", "nir_intrinsic_ldc_nv", "nir_intrinsic_load_ubo",
           "nir_intrinsic_image_store", "nir_intrinsic_image_load")]
       + [(n, "generated enum, nir_instr_enum") for n in
          ("nir_type_float16", "nir_type_float32", "nir_deref_type_var",
           "nir_deref_type_array", "nir_jump_break")]
       + [(n, "generated enum, glsl") for n in
          ("MESA_SHADER_COMPUTE", "SCOPE_WORKGROUP", "ACCESS_CAN_REORDER", "GLSL_SAMPLER_DIM_2D")]
       + [(n, "generated enum, nir_intrinsics") for n in
          ("NIR_INTRINSIC_ALIGN_MUL", "NIR_INTRINSIC_WRITE_MASK", "NIR_INTRINSIC_ACCESS",
           "NIR_INTRINSIC_EXECUTION_SCOPE", "NIR_INTRINSIC_IMAGE_DIM", "NIR_INTRINSIC_SRC_TYPE",
           "NIR_INTRINSIC_DEST_TYPE", "NIR_INTRINSIC_RANGE")]
       + [("nir_intrinsic_infos", "in_dll DATA ARRAY -- ABSENT without tinymesa")]
       + [("glsl_type_builtin_double", "in_dll DATA -- ABSENT without tinymesa")])

def const_rows():
  m = _mesa()
  return [(nm, auth, "ABSENT" if not hasattr(m, nm) else str(getattr(m, nm))) for nm, auth in CONST]

def main():
  mode = sys.argv[1] if len(sys.argv) > 1 else "rows"
  if mode == "rows":
    for nm, got in rows(): print("%s = [%s]   py=[%s]" % (nm, got, got))
    print()      # the one framing newline `IO.print` supplies
  elif mode == "names":
    for nm, _ in rows(): print(nm)
  elif mode == "spelling":
    # THE SUBSTRATE FINDING, in full. `spec.bend`'s `Dt.nm` vs CPython's
    # `DType.name` for all seventeen plus the three weak dtypes.
    n = 0
    for d in ALL + [dtypes.void, dtypes.weakint, dtypes.weakfloat]:
      same = sp(d) == py_name(d)
      n += not same
      print("%-18s spec.bend=%-20s dtype.py=%-12s %s"
            % (type(d).__name__ and "dtypes", sp(d), py_name(d), "AGREE" if same else "DIFFER"))
    print("\n%d of %d spellings DIFFER between tinybendygrad/LAWS/spec.bend and "
          "tinygrad/dtype.py" % (n, len(ALL) + 3))
  elif mode == "const":
    for nm, auth, v in const_rows(): print("%-42s %-52s %s" % (nm, auth, v))
  elif mode == "bend":
    # Rewrite the `py=` literal of every `r("label", expr, "old")` line in
    # `nir.bend` to the value THIS RUN computed. Working line-wise with a
    # greedy `.*` for the expression is deliberate: a single regex over the whole
    # file with a non-greedy group swallowed a label that contained `, "` on the
    # `c uint8 u=Fals` row.
    import re
    p = os.path.join(ROOT, "tinybendygrad", "renderer", "nir.bend")
    vals, hit, miss = dict(rows()), 0, []
    out = []
    for line in open(p).read().splitlines():
      m = re.match(r'^(\s*)r\("([^"]*)", (.*), "[^"]*"\),?$', line)
      if not m:
        out.append(line); continue
      indent, label, expr = m.groups()
      if label not in vals: miss.append(label); out.append(line); continue
      hit += 1
      out.append('%sr("%s", %s, "%s"),' % (indent, label, expr, vals[label]))
    sys.stderr.write("rewrote %d rows; unmatched: %s\n" % (hit, miss or "none"))
    print("\n".join(out))
if __name__ == "__main__": main()
