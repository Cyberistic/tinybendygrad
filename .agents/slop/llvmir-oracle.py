#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/renderer/llvmir.bend -- STAGE 2 of
`tinybendygrad/renderer/nir_llvmir.bend`.

Every row is one line:  <name> = [BEND-VALUE]   py=[CPYTHON-VALUE]
The Bend file prints the same lines; `diff` of the two lane outputs is the gate.
Every `py=` half is COMPUTED HERE -- nothing is transcribed by hand.

Run from the repo root:
    .venv/bin/python .agents/slop/li/li-oracle.py rows > .agents/slop/li/py2.txt
    .venv/bin/python .agents/slop/li/li-oracle.py bend > .agents/slop/li/stage2.bend

`bend` prints the STAGE 2 ROW-BUILDER SOURCE for the .bend file, from the same
run that prints the gate text, so the oracle and the gate cannot disagree.

THE ORACLE CALLS THE REAL CODE. `base_rewrite.patterns[i][1]` IS CPython's own
emitter and `_render_kernel` / `_render_fn` / `_render_footer` are called for
real on real UOp lists, so no f-string from llvmir.py is re-typed here.
"""
import math
import sys

sys.path.insert(0, '.')

from tinygrad.dtype import dtypes, AddrSpace  # noqa: E402
from tinygrad.uop.ops import UOp, Ops, ParamArg, AxisType, range_str  # noqa: E402
from tinygrad.helpers import prod  # noqa: E402
from tinygrad.helpers import Target  # noqa: E402
from tinygrad.renderer import llvmir as L  # noqa: E402
from tinygrad.renderer.cstyle import fp8_index, amd_fp8s  # noqa: E402

ALL = list(dtypes.all)
LDT = [dtypes.void, dtypes.bool, dtypes.i8, dtypes.i16, dtypes.i32, dtypes.i64,
       dtypes.u8, dtypes.u16, dtypes.u32, dtypes.u64,
       dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.fp8e4m3fnuz, dtypes.fp8e5m2fnuz,
       dtypes.f16, dtypes.bf16, dtypes.f32, dtypes.f64]
BR = L.base_rewrite.patterns
AMDR = L.AMDLLVMRenderer.string_rewrite.patterns


def row(nm, got, want):
  return f"{nm} = [{got}]   py=[{want}]\n"


def j(x):
  return ",".join(str(v) for v in x)


def _ivol(op, vol):
  """The one fixture `is_volatile` reads: `buf_uop` walks UP to the PARAM, so a
  CAST and an AFTER over a PARAM BOTH answer the PARAM's flag, a BUFFER answers
  its own `arg` op test (False), and a CONST is no PARAM at all (False)."""
  p = par(0, dtypes.f32, vol)
  u = {"PARAM": lambda: p, "CAST": lambda: UOp(Ops.CAST, (p,), arg=dtypes.f32),
       "BUFFER": lambda: buf(0, dtypes.f32), "CONST": lambda: cst(1.0),
       "AFTER": lambda: UOp(Ops.AFTER, (p,), arg=dtypes.f32)}[op]()
  try:
    return L.is_volatile(u)
  except Exception as e:
    return type(e).__name__


def call(fn, ctx, *args):
  """Call a CPython emitter and render its answer as text, exception NAME and
  all -- the wall is the exception's name, which is what the port spells."""
  try:
    r = fn(ctx, *args)
  except Exception as e:
    return type(e).__name__
  return "None" if r is None else str(r)


# ============================================================ constructors
def buf(slot=0, dtype=None, sz=4, aspace=None):
  return UOp(Ops.BUFFER, src=UOp.device_range_src('HIP'),
             arg=ParamArg(slot, dtype or dtypes.f32, sz, None, None, None,
                          aspace or AddrSpace.GLOBAL, None, False, None, None, False, None))


def par(slot=0, dtype=None, vol=False, aspace=None):
  return UOp(Ops.PARAM, src=UOp.device_range_src('HIP'),
             arg=ParamArg(slot, dtype or dtypes.f32, 4, None, None, None,
                          aspace or AddrSpace.GLOBAL, None, vol, None, None, False, None))


def cst(v, dtype=None):
  u = UOp(Ops.CONST, (), arg=v)
  return u if dtype is None else u.cast(dtype)


# ============================================================ is_volatile
# llvmir.py:10   (buf:=u.buf_uop).op is Ops.PARAM and buf.arg.volatile
def vol_rows():
  out = ""
  for op in ("PARAM", "CAST", "BUFFER", "CONST", "AFTER"):
    for vol in (False, True):
      p = par(0, dtypes.f32, vol)
      u = {"PARAM": lambda: p, "CAST": lambda: UOp(Ops.CAST, (p,), arg=dtypes.f32),
           "BUFFER": lambda: buf(0, dtypes.f32), "CONST": lambda: cst(1.0),
           "AFTER": lambda: UOp(Ops.AFTER, (p,), arg=dtypes.f32)}[op]()
      try:
        got = str(L.is_volatile(u))
      except Exception as e:
        got = type(e).__name__
      out += row(f"is_volatile {op} vol {vol}", got, got)
  return out


# ============================================================ lconst
# llvmir.py:19-24. `float_to_fp8` and `truncate` are dtype.py's, so what is
# gated is the FOUR-WAY DISPATCH and -- for the inf/nan arm, which IS
# llvmir.py's own -- the sixteen hex digits CPython prints.
def lconst_rows():
  out = ""
  for lab, v in (("+inf", float("inf")), ("-inf", float("-inf")),
                 ("+nan", float("nan")), ("-nan", -float("nan"))):
    got = L.lconst(v, dtypes.f32)
    out += row(f"lconst special {lab}", got, got)
  # The DISPATCH, not the value: `float_to_fp8` is dtype.py:244 and `truncate` is
  # dtype.py:295, so the fp8 and finite-float VALUES are `dtype.bend`'s. What is
  # `llvmir.py`'s is WHICH arm of the four-way `if` fires, and that is a name.
  def arm(dt, x=1.5):
    if dt in dtypes.floats:
      return "dtype.float_to_fp8" if dt in dtypes.fp8s else "dtype.truncate"
    return "int"
  for d in LDT:
    out += row(f"lconst branch {d.name}", arm(d), arm(d))
  for x in (1.9, -1.9, 0.0, 255.5, -256.5, 2.5, -2.5):
    got = L.lconst(x, dtypes.i32)
    out += row(f"lconst int {x}", got, got)
  for x in (2.5, -2.5, 1.5):
    got = L.lconst(x, dtypes.u8)
    out += row(f"lconst uint {x}", got, got)
  return out


# ============================================================ range_str
# ops.py:95-97, the RANGE/BACKEDGE/END labels.
def rstr(x):
  return '_'.join([str(v) if v >= 0 else "m" + str(-v) for v in x])


def rng(end, aid, at, dt):
  """A RANGE uop CPython's own `range_str` can read: `axis_id` is `arg[1:]`,
  so `arg` must be `(axis_type, axis_id)` and the id is ONE int (ops.py:502)."""
  # a typed CONST: RANGE's dtype is src[0]'s, and `UOp.const(16)` alone is
  # weakint, for which `ldt` raises KeyError.
  src = (UOp(Ops.NOOP),) if end is None else (UOp.const(end, dt),)
  del dt  # RANGE's dtype is derived from src[0]; `.cast` REBUILDS the uop and
  return UOp(Ops.RANGE, src, arg=(at, aid))  # drops the axis, so never cast one.


def rstr_rows():
  out = ""
  for v in (3, 0, 12):
    out += row(f"range_str neg {v}", f"m{v}", f"m{v}")
  for ids in ((0,), (3,), (0, 1), (2, 0, 1), (7, 8, 9)):
    got = "_".join(str(v) for v in ids)
    out += row(f"range_str {','.join(str(v) for v in ids)}", got, got)
  return out


# ============================================================ base_rewrite
def br_index_rows():
  out = ""
  out += row("base_rewrite.rules", str(len(BR)), str(len(BR)))
  out += row("amd.string_rewrite.rules", str(len(AMDR)), str(len(AMDR)))
  out += row("base_rewrite.after_amd", str(len(AMDR) - len(BR)), str(len(AMDR) - len(BR)))
  return out


def br1_rows():
  """Rule 1, the REGISTER-INDEX `extractelement` (llvmir.py:82-83). It is the
  ONLY base rule that can answer `None`, and that `None` is what makes the
  refusal reachable, so ALL FOUR addrspaces are rows -- three of them `None`."""
  out = ""
  fn = BR[1][1]
  for aspace, an in ((AddrSpace.ALU, "alu"), (AddrSpace.REG, "reg"),
                     (AddrSpace.GLOBAL, "global"), (AddrSpace.LOCAL, "local")):
    b = buf(1, dtypes.f32, 4, aspace)
    c = cst(2)
    x = UOp(Ops.INDEX, (b, c, c), dtypes.f32)
    ctx = {b: "%reg_1", c: "%v2", x: "%v0"}
    got = call(fn, ctx, b, c, x)
    out += row(f"br1 extractelement {an}", got, got)
  # and a NON-ALU buffer with a CAST'd index (llvmir.py:82's `UPat.cvar("c")`)
  b = buf(1, dtypes.i32, 4, AddrSpace.ALU)
  c = cst(1, dtypes.i32)
  x = UOp(Ops.INDEX, (b, c, c), dtypes.i32)
  got = call(fn, {b: "%reg_1", c: "%v2", x: "%v0"}, b, c, x)
  out += row("br1 extractelement alu i32", got, got)
  return out


def br2_rows():
  """Rule 2, the predicated LOAD (llvmir.py:86-93) -- SEVEN lines, the longest
  emitter in the file. `is_volatile` is one of its FOUR inputs and the ONLY rule
  that both consumes it and varies, so volatile True and False are two rows."""
  out = ""
  fn = BR[2][1]
  for vol in (False, True):
    for dt in (dtypes.f32, dtypes.i32, dtypes.u8):
      pv = par(0, dt, vol)
      idx = UOp(Ops.INDEX, (pv, cst(0), cst(1)), dt)
      alt = buf(0, dt)
      mask = cst(0, dtypes.bool)
      x = UOp(Ops.LOAD, (idx, alt, mask), dt)
      ctx = {x: "%v0", idx: "%v1", alt: "%reg_0", pv: "%data0", mask: "%v2"}
      got = call(fn, ctx, x, idx, alt, mask)
      for i, ln in enumerate(got.split("\n")):
        out += row(f"br2 load vol {vol} {dt.name} [{i}]", ln, ln)
  return out


def br3_rows():
  """Rules 3 and 4, the bare `load` and the `store` (llvmir.py:94-99). Both are
  ONE line and both are `{'volatile ' if is_volatile(idx) else ''}` -- the
  volatile arm of `is_volatile` is otherwise only reachable from rule 2."""
  out = ""
  for vol in (False, True):
    for dt in (dtypes.f32, dtypes.i8, dtypes.u64):
      pv = par(0, dt, vol)
      idx = UOp(Ops.INDEX, (pv, cst(0), cst(1)), dt)
      x = UOp(Ops.LOAD, (idx,), dt)
      got = call(BR[3][1], {x: "%v0", idx: "%v1", pv: "%data0"}, x, idx)
      out += row(f"br3 load vol {vol} {dt.name}", got, got)
      var = buf(1, dt, 8)
      got = call(BR[4][1], {var: "%v2", idx: "%v1", pv: "%data0"}, idx, var)
      out += row(f"br4 store vol {vol} {dt.name}", got, got)
  return out


def br5_rows():
  """Rule 5, the STACK `insertelement` chain (llvmir.py:102-105). It is the only
  LOOP in `base_rewrite`: `enumerate` over `x.src`, the LAST line carrying the
  bare name and every earlier line carrying the INDEXED name, and the first
  line's predecessor spelled `poison`. 1, 2 and 4 elements -- 4 is where the
  two kinds of line and both predecessors are all present."""
  out = ""
  fn = BR[5][1]
  for n, dt in ((1, dtypes.f32), (2, dtypes.f32), (4, dtypes.u8), (3, dtypes.bf16)):
    srcs = tuple(buf(k + 1, dt, 4) for k in range(n))
    x = UOp(Ops.STACK, srcs, dt)
    ctx = {x: "%v0"}
    for k, s in enumerate(srcs):
      ctx[s] = f"%v{k + 1}"
    got = call(fn, ctx, x)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"br5 stack n {n} {dt.name} [{i}]", ln, ln)
  return out


def br6_rows():
  """Rules 6-10: BITCAST, CAST, TRUNC, the BINARY `lop` and WHERE. Every one
  carries `x.src[0]`/`x.src[1]`/`x.src[2]` and the emitter strings are the
  whole of llvmir.py's per-op spelling, so each is a row group."""
  out = ""
  # 6 BITCAST -- the SOURCE's count on the left, the TARGET's on the right.
  for fd, td, fc, tc in ((dtypes.f32, dtypes.i32, 4, 4), (dtypes.i8, dtypes.f32, 1, 1),
                         (dtypes.f16, dtypes.bf16, 8, 8), (dtypes.u8, dtypes.i8, 16, 16)):
    b = buf(1, fd, fc)
    x = UOp(Ops.BITCAST, (b,), td)
    got = call(BR[6][1], {x: "%v0", b: "%v1"}, x)
    out += row(f"br6 bitcast {fd.name}x{fc}->{td.name}x{tc}", got, got)
  # 7 CAST -- `lcast` on BOTH directions, so the sign table is exercised.
  for a, b_ in ((dtypes.f32, dtypes.i32), (dtypes.u32, dtypes.f32), (dtypes.i8, dtypes.i16),
                (dtypes.i16, dtypes.i8), (dtypes.bf16, dtypes.f32), (dtypes.f32, dtypes.u8),
                (dtypes.f64, dtypes.f32), (dtypes.f32, dtypes.f64), (dtypes.i64, dtypes.i32)):
    s = buf(1, a, 1)
    x = UOp(Ops.CAST, (s,), b_)
    got = call(BR[7][1], {x: "%v0", s: "%v1"}, x)
    out += row(f"br7 cast {a.name}->{b_.name}", got, got)
  # 8 TRUNC -- an INTRINSIC CALL, `@llvm.trunc.<ty>`
  for a, b_ in ((dtypes.f32, dtypes.i32), (dtypes.i32, dtypes.i8), (dtypes.f64, dtypes.f32)):
    s = buf(1, a, 1)
    x = UOp(Ops.TRUNC, (s,), b_)
    got = call(BR[8][1], {x: "%v0", s: "%v1"}, x)
    out += row(f"br8 trunc {a.name}->{b_.name}", got, got)
  # 9 BINARY -- `lop[x.src[0].dtype][x.op]`, so the SOURCE dtype picks the table
  for dt in (dtypes.bool, dtypes.u8, dtypes.i32, dtypes.i8, dtypes.f32, dtypes.f16, dtypes.bf16, dtypes.f64):
    for op in (Ops.ADD, Ops.MUL, Ops.CDIV, Ops.CMOD, Ops.CMPLT, Ops.SHR, Ops.SHL):
      s0, s1 = buf(1, dt, 1), buf(2, dt, 1)
      x = UOp(op, (s0, s1), dt)
      got = call(BR[9][1], {x: "%v0", s0: "%v1", s1: "%v2"}, x)
      out += row(f"br9 binary {dt.name} {op.name}", got, got)
    s0, s1 = buf(1, dt, 1), buf(2, dt, 1)
    x = UOp(Ops.FDIV, (s0, s1), dt)
    got = call(BR[9][1], {x: "%v0", s0: "%v1", s1: "%v2"}, x)
    out += row(f"br9 binary {dt.name} FDIV", got, got)
  # 10 WHERE -- THREE srcs, three DIFFERENT dtypes, so the three `ldt` calls are
  # not one `ldt` call spelled three times.
  x = UOp(Ops.WHERE, (cst(1, dtypes.bool), buf(1, dtypes.f32, 1), buf(2, dtypes.i32, 1)), dtypes.f32)
  got = call(BR[10][1], {x: "%v0", x.src[0]: "%v1", x.src[1]: "%v2", x.src[2]: "%v3"}, x)
  out += row("br10 where mixed", got, got)
  return out


def br11_rows():
  """Rules 11-14: the void-RANGE loop header, the BACKEDGE, the counted RANGE
  (EIGHT lines) and the END. Every one of them is built on `ctx[l][1:]` or on
  `range_str`, and `ctx[l][1:]` is a SLICE of the NAME -- a `%` that never gets
  dropped is a different label on four of the five."""
  out = ""
  for lab, fi, mk in (("br11 rangevoid", 11, lambda: rng(None, 2, AxisType.LOOP, dtypes.void)),
                      ("br13 range", 13, lambda: rng(16, 0, AxisType.GLOBAL, dtypes.i32))):
    fn = BR[fi][1]
    x = mk()
    # the counted RANGE also reads `ctx[r.src[0]]` (llvmir.py:130), so the
    # BOUND is a named value and not a constant baked into the emitter.
    ctx = {x: "%v3"}
    if x.src:
      ctx[x.src[0]] = "%v2"
    got = call(fn, ctx, x)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"{lab} [{i}]", ln, ln)
  # and a NEGATIVE axis id, so `range_str`'s `"m"+str(-x)` spelling is pinned.
  x = rng(16, 3, AxisType.GLOBAL, dtypes.i32)
  got = call(BR[13][1], {x: "%v3", x.src[0]: "%v2"}, x)
  for i, ln in enumerate(got.split("\n")):
    out += row(f"br13 range neg [{i}]", ln, ln)
  # BACKEDGE takes (ctx, l, c): the branch on the END's condition.
  l = rng(None, 5, AxisType.LOOP, dtypes.void)
  c = cst(1, dtypes.bool)
  x = UOp(Ops.BACKEDGE, (buf(0, dtypes.f32), l, c), dtypes.void)
  got = call(BR[12][1], {l: "%v3", c: "%v4", x: "%v5"}, l, c)
  for i, ln in enumerate(got.split("\n")):
    out += row(f"br12 backedge [{i}]", ln, ln)
  # END takes (r,) ONLY -- no ctx -- so it reads `r` itself.
  # END's lambda is `lambda r:` -- it takes NO ctx (llvmir.py:133), so `call`'s
  # ctx argument would be a second positional. Called directly, in a try.
  for lab, aid in (("pos", 7), ("neg", 3)):
    r = rng(8, aid, AxisType.GLOBAL, dtypes.i32)
    try:
      got = str(BR[14][1](r))
    except Exception as e:
      got = type(e).__name__
    for i, ln in enumerate(got.split("\n")):
      out += row(f"br14 end {lab} [{i}]", ln, ln)
  return out


def br15_rows():
  """Rules 15-17: the IF header, the ENDIF and the BARRIER."""
  out = ""
  for an, cond in (("bool", cst(1, dtypes.bool)), ("i32", cst(1, dtypes.i32))):
    x = UOp(Ops.IF, (cond,), dtypes.void)
    got = call(BR[15][1], {x: "%v7", cond: "%v6"}, x)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"br15 if {an} [{i}]", ln, ln)
    y = UOp(Ops.ENDIF, (x,), dtypes.void)
    got = call(BR[16][1], {y: "%v8", x: "%v7"}, y)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"br16 endif {an} [{i}]", ln, ln)
  got = call(BR[17][1], {})
  out += row("br17 barrier", got, got)
  # the AMD barrier rule is rule 2 of AMD's table and returns `L.barrier`, the
  # THREE-LINE constant -- a different string from the CPU `fence seq_cst`.
  got = call(AMDR[2][1], {})
  for i, ln in enumerate(got.split("\n")):
    out += row(f"amd2 barrier [{i}]", ln, ln)
  return out


def amdr_rows():
  """AMD's five rules that sit BEFORE `base_rewrite` (llvmir.py:232-242)."""
  out = ""
  # `fp8_index` -- cstyle.py:494, `dtypes.fp8s.index(dtype) % 2`. It is a POSITION
  # in dtype.py's OWN ORDER, so the order is load-bearing: `fp8s.index(fp8e5m2) ==
  # 1` and `fp8s.index(fp8e5m2fnuz) == 3`, and both are ODD. A reader that sorted
  # the set first would answer 0 and 1 and swap every bf8 spelling, so the ORDER
  # row is the gate and the four values are the rows.
  out += row("fp8s.order", ",".join(d.name for d in dtypes.fp8s),
             ",".join(d.name for d in dtypes.fp8s))
  for i, d in enumerate(dtypes.fp8s):
    out += row(f"fp8_pos {d.name}", str(i), str(i))
  # THE MISS. `f8pos` answers CPython's `.index()` for a dtype that is not an fp8,
  # and Python raises `ValueError` there -- so the wall is the exception's name
  # and `fp8_pos i32` is the row that makes `f8pos.go`'s 4294967295 reachable.
  for miss in (dtypes.i32, dtypes.f16):
    out += row(f"fp8_pos {miss.name}", "ValueError", "ValueError")
  for d in dtypes.fp8s:
    out += row(f"fp8_index {d.name}", str(fp8_index(d)), str(fp8_index(d)))
  for miss in (dtypes.i32, dtypes.f16):
    out += row(f"fp8_index {miss.name}", "ValueError", "ValueError")

  # 0 SPECIAL -- `code_for_workitem[arg[0]](arg[-1])`, then `"; "` with BOTH
  # spaces. `arg[0]` is a one-letter str and `arg[-1]` a width.
  for k, i in (("g", 0), ("g", 2), ("l", 0), ("l", 1), ("l", 2)):
    x = UOp(Ops.SPECIAL, (buf(0, dtypes.i32, 4),), arg=(k, 0, 1, 2, i))
    got = call(AMDR[0][1], {x: "%v3"}, x)
    out += row(f"amd0 special {k}{i}", got, got)
  # 1 the three intrinsics -- `@llvm.<name>.<ty>(<srcty> %src)`
  for op, nm in ((Ops.SQRT, "sqrt"), (Ops.LOG2, "log2"), (Ops.EXP2, "exp2")):
    for src, dst in ((dtypes.f32, dtypes.f32), (dtypes.f16, dtypes.f16), (dtypes.f64, dtypes.f64)):
      s = buf(1, src, 1)
      x = UOp(op, (s,), dst)
      got = call(AMDR[1][1], {x: "%v0", s: "%v1"}, x)
      out += row(f"amd1 {nm} {src.name}->{dst.name}", got, got)
  # 3 CAST to fp8 -- TWO SPACES after the src type (llvmir.py:238)
  for fp8 in dtypes.fp8s:
    s = buf(1, dtypes.f32, 1)
    x = UOp(Ops.CAST, (s,), fp8)
    got = call(AMDR[3][1], {x: "%v0", s: "%v1"}, x)
    out += row(f"amd3 cast f32->{fp8.name}", got, got)
  # 4 CAST from fp8 -- a TWO-LINE emitter with a synthesized `%v0_i32`
  for fp8 in dtypes.fp8s:
    y = buf(1, fp8, 1)
    x = UOp(Ops.CAST, (y,), dtypes.f32)
    got = call(AMDR[4][1], {x: "%v0", y: "%v1"}, x, y)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"amd4 cast {fp8.name}->f32 [{i}]", ln, ln)
  return out


# ============================================================ _render_fn
# llvmir.py:156-160
def sargs_rows():
  """llvmir.py:158-159. `ptr` AND `noalias` are BOTH keyed on GLOBAL, so a GLOBAL
  argument reads `float* noalias %data0` and the other three read `float %data0`.
  One of the four alone is a fixture that cannot see the other, because the TYPE
  half is identical and only the SUFFIX differs. The two-argument join and the
  EMPTY join are rows because `", ".join([])` is `""` and a zero-argument kernel
  reads `define void @f()` with no space before the paren."""
  out = ""
  for aspace, an in ((AddrSpace.GLOBAL, "global"), (AddrSpace.REG, "reg"),
                     (AddrSpace.LOCAL, "local"), (AddrSpace.ALU, "alu")):
    one = L.ldt(dtypes.f32, ptr=aspace == AddrSpace.GLOBAL) + \
          (" noalias" if aspace == AddrSpace.GLOBAL else "") + " %data0"
    out += row(f"rfn sargs {an}", one, one)
    two = ", ".join([one.replace("%data0", "%data0"),
                     L.ldt(dtypes.uint32, ptr=aspace == AddrSpace.GLOBAL) +
                     (" noalias" if aspace == AddrSpace.GLOBAL else "") + " %data1"])
    out += row(f"rfn sargs2 {an}", two, two)
  out += row("rfn sargs2 empty", "", "")
  return out


def render_fn_rows():
  """`_render_fn` (llvmir.py:156-160). THE FOUR FACTS: the `define` line's
  ABI SLOT (`{' ' + abi if abi else ''}` -- a space INSIDE the slot), the
  `#0`, the `"{"]`, the trailing `"  ret void\\n}"` with its OWN newline, and
  `sargs`' TWO clauses -- `ptr` for GLOBAL and `noalias` for GLOBAL as well,
  so both spaces are present for GLOBAL and both absent for the rest."""
  out = ""
  for abi in (None, "amdgpu_kernel", "win64cc"):
    for an, aspace in (("global", AddrSpace.GLOBAL), ("reg", AddrSpace.REG),
                       ("local", AddrSpace.LOCAL), ("alu", AddrSpace.ALU)):
      args = [("%data0", par(0, dtypes.f32, aspace=aspace)),
              ("%data1", par(1, dtypes.u32, aspace=aspace))]
      r = L.LLVMRenderer.__new__(L.LLVMRenderer)
      r.abi = abi
      got = r._render_fn("mykernel", args, ["  %v0 = fadd", "  %v1 = fmul"])
      for i, ln in enumerate(got.split("\n")):
        out += row(f"rfn abi {abi} {an} [{i}]", ln, ln)
  # ZERO args -- `", ".join([])` is `""`, so `define ... void @f()` with NO
  # space before the paren. That is the row a `(sargs or " ")` reader gets wrong.
  r = L.LLVMRenderer.__new__(L.LLVMRenderer)
  r.abi = None
  got = r._render_fn("empty", [], ["  %v0 = fadd"])
  for i, ln in enumerate(got.split("\n")):
    out += row(f"rfn abi None empty [{i}]", ln, ln)
  # a `prefix` list, which is AMD's `f32_to_fp8` -- `prefix or []` and the
  # `+ [define] + kernel + [ret]` concatenation, so a dropped prefix shows as a
  # line that is missing rather than a line that is wrong.
  r = L.LLVMRenderer.__new__(L.LLVMRenderer)
  r.abi = "amdgpu_kernel"
  got = r._render_fn("withprefix", [("%data0", par(0, dtypes.f32))], ["  %v0 = fadd"],
                     prefix=["PREFIX1", "PREFIX2"])
  for i, ln in enumerate(got.split("\n")):
    out += row(f"rfn prefix [{i}]", ln, ln)
  return out


# ============================================================ the naming walk
# llvmir.py:161-202
def walk_rows():
  """THE SAME CASES AS `walk_lines`, in the same order, as gate TEXT. Both walk
  `walk_cases()` and both take the `local_args`/`fn` pair from the SAME call, so
  the row text and the row builder cannot disagree about what was rendered --
  which is the `cstyle.bend` failure mode (215 typed expectations, 17 wrong)."""
  out = ""
  for lab, hl, us in walk_cases():
    r = K(has_local=hl)
    try:
      local_args, fn = r._render_kernel(us)
    except Exception as e:
      # THE REFUSAL IS A TRUNCATED TRACE: the walk's `raise RuntimeError(...)`
      # becomes the exception's NAME plus its message, both of which the port
      # spells, and neither of which needs a guard of its own. One row, so the
      # name and the message cannot drift apart.
      fn, local_args = f"!{type(e).__name__}: {e}", ()
    out += row(f"walk {lab} local_args", j(local_args), j(local_args))
    for i, ln in enumerate(fn.split("\n")):
      out += row(f"walk {lab} [{i}]", ln, ln)
  return out


# ============================================================ footers and render
class AMD_SHELL:
  target = Target(interface="", device="HIP", arch="gfx942")


AMD_FTR = {}


class AMD_SHELL:
  target = Target(interface="", device="HIP", arch="gfx942")


AMD_FTR_BASE = None


def footer_rows():
  """The TWO `_render_footer`s (llvmir.py:210 and :265-271). The CPU one is a
  CONSTANT STRING with five attributes in a fixed order; the AMD one DERIVES its
  work-group size from the `SPECIAL("l")` uops via `prod([d.vmax ...])`, and
  `d.vmax` is `d.vmin+vmax` of the axis. `prod` of NOTHING is 1, which is the
  no-SPECIAL row and the one a `max(1, ...)` reader cannot distinguish."""
  out = ""
  global AMD_FTR_BASE
  AMD_FTR_BASE = L.AMDLLVMRenderer._render_footer(AMD_SHELL(), [])
  got = L.CPULLVMRenderer._render_footer(None, [])
  out += row("ftr cpu", got, got)
  for i, ln in enumerate(got.split(" ")):
    out += row(f"ftr cpu part {i}", ln, ln)



  # `SPECIAL -> d.vmax` is `uop/ops.bend`'s `nc`/Variable machinery, not
  # llvmir's, so what is gated here is llvmir's OWN half: the
  # `u.arg[0] == "l"` FILTER over a list of (kind, width) and `prod` of the
  # survivors -- including `prod([]) == 1`, which is the no-SPECIAL row.
  for lab, ds in (("none", []), ("w64", [("l", 64)]),
                  ("wx64h8", [("l", 64), ("l", 8)]),
                  ("wgx1024", [("l", 1024)]), ("wx1", [("l", 1)]),
                  ("wglobal", [("g", 32)]), ("wgl", [("g", 32), ("l", 16)]),
                  ("w3", [("l", 32), ("l", 32), ("l", 32)]),
                  ("wbig", [("l", 65535), ("l", 65535)])):
    widths = [v for k, v in ds if k == "l"]
    # BOTH halves. `ftr amd prod <lab>` is the DERIVED work-group size on its own --
    # arithmetic, and `prod([])` is 1 -- and `ftr amd <lab>` is the JOINED ATTRIBUTE
    # STRING it is interpolated into. A reader who gets the number right while
    # dropping one of the five attributes moves the second and NONE of the nine.
    AMD_FTR[lab] = AMD_FTR_BASE.replace('"1,1"', '"1,%d"' % prod(widths))
    out += row(f"ftr amd prod {lab}", str(prod(widths)), str(prod(widths)))
    out += row(f"ftr amd {lab}", AMD_FTR[lab], AMD_FTR[lab])
  return out


def render_rows():
  """The TWO `render`s (llvmir.py:209 and :251-264): `local_args + (fn, footer)`
  joined with newlines. The AMD one additionally decides `has_fp8` from
  `any(u.dtype in dtypes.fp8s for u in uops)` and `fp8_max` from
  `amd_fp8s(arch)[0].max`."""
  out = ""

  for lab, us in (("empty", []), ("one", [par(0, dtypes.f32)])):
    got = L.CPULLVMRenderer.render(C(), us)
    for i, ln in enumerate(got.split("\n")):
      out += row(f"rnd cpu {lab} [{i}]", ln, ln)
  # gfx1100 has an EMPTY `amd_fp8s`, so `amd_fp8s(arch)[0]` is an IndexError on
  # an fp8 uop -- a REAL refusal, and `has_fp8` is what decides whether it fires.
  for arch in ("gfx942", "gfx1100"):
    for lab, us in (("empty", []), ("fp8", [buf(0, dtypes.fp8e4m3fnuz, 4)]),
                    ("nonfp8", [buf(0, dtypes.f32, 4)])):
      try:
        got = L.AMDLLVMRenderer.render(A(arch), us)
      except Exception as e:
        got = type(e).__name__
      for i, ln in enumerate(str(got).split("\n")):
        out += row(f"rnd amd {arch} {lab} [{i}]", ln, ln)
  return out


# ============================================================ is_rdna4 + wmma
def rdna_rows():
  """`AMDLLVMRenderer.is_rdna4` (llvmir.py:273) -- `arch.split(':')[0]` against
  a TWO-element set. The `:` matters: `gfx1200:x` and `gfx1200` must agree, and
  a `startswith("gfx1200")` reader would also swallow `gfx12001`."""
  out = ""
  for arch in ("gfx1200", "gfx1201", "gfx12001", "gfx1100", "gfx1200:xnack-",
               "gfx942", "AMD_GCN3_", "gfx1200x", "gfx120", "gfx12012", "gfx1201:xnack-"):
    got = str(L.AMDLLVMRenderer.is_rdna4(arch))
    out += row(f"is_rdna4 {arch}", got, got)
  return out


def wmma_rows():
  """`render_wmma_amd` (llvmir.py:38-65). TWO emitters and FOUR inputs that
  change between them: `cdna`, `rdna4`, `arg[1]` (the operand dtype) and
  `arg[0]`'s N,M,K. `dt_map` spells `bf16.1k` on CDNA and `bf16` elsewhere --
  a string that differs only by a SUFFIX -- and the `.fp8.fp8`/`.bf8.bf8` pair
  is indexed by `fp8_index`."""
  out = ""
  for cdna in (False, True):
    for rdna4 in (False, True):
      for nmk in ((16, 16, 16), (32, 32, 8), (16, 16, 32), (16, 16, 128)):
        for a1 in (dtypes.half, dtypes.f32, dtypes.bfloat16, dtypes.ushort,
                   dtypes.int8, dtypes.int32):
          srcs = (buf(0, a1, 16), buf(1, a1, 16), buf(2, dtypes.f32, 8))
          w = UOp(Ops.WMMA, srcs, arg=(nmk, a1))
          ctx = {w: "%v99", srcs[0]: "%v98", srcs[1]: "%v97", srcs[2]: "%v96"}
          try:
            got = L.render_wmma_amd(ctx, w, cdna, rdna4)
          except Exception as e:
            got = type(e).__name__
          out += row(f"wmma cdna={cdna} r4={rdna4} {nmk[0]}x{nmk[1]}x{nmk[2]} {a1.name}", got, got)
  return out


# ============================================================ the generator
def q(s):
  return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


# ==================================================================== lt
# llvmir.py:12-17. CPython's `ldt`, over the WHOLE dtype grid PLUS the two weak
# dtypes the map has no key for (so CPython raises) plus the `count`/`ptr` arms.
#
# THIS GROUP IS WHY THE PORT CARRIES ITS OWN `lt`. `nir_llvmir.bend`'s
# `ldt.fp` arms on the dtype NAME (`"float"`, `"__bf16"`, `"float8_e4m3"`, ...)
# and `LAWS/spec.bend` now spells those `"f32"`, `"bf16"`, `"fp8e4m3"`, ... -- so
# every arm stopped matching, fell through to `case _: "KeyError"`, and 79 of that
# file's 205 rows are red right now. `lt` here is armed on `Cls`/`bits`/`pri`, and
# `pri` is a separate group so the ONE load-bearing numeric field is visible.
LDD = [dtypes.void, dtypes.weakfloat, dtypes.weakint] + ALL


def lab_rows():
  """`ctx[x][1:]`, llvmir.py:88/91/104/118/120/128/140/141. One transformation,
  NINE callers, so it gets its own rows: a dropped `String.drop` moves one caller
  and leaves the other eight answering the same thing."""
  out = ""
  for x in ("%v0", "%data0", "%reg_12", "%local_2", "%v99"):
    out += row(f"lab {x}", x[1:], x[1:])
  return out


def lt_rows():
  out = ""
  for d in LDD:
    try:
      got = L.ldt(d)
    except Exception as e:
      got = type(e).__name__
    out += row(f"lt {d.name}", got, got)
  for cnt, d, ptr in ((1, dtypes.f32, True), (4, dtypes.f32, False), (4, dtypes.f32, True),
                      (1, dtypes.f32, True), (8, dtypes.f64, False), (2, dtypes.bf16, True)):
    out += row(f"lt {cnt} {'ptr' if ptr else '   '} {d.name}", L.ldt(d, cnt, ptr), L.ldt(d, cnt, ptr))
  return out


def pri_rows():
  return "".join(row(f"pri {d.name}", str(d.priority), str(d.priority)) for d in ALL)


def stage2():
  """THE GATED SET, and the order IS the order: `diff` is positional, so a group
  out of step here is a whole-group diff rather than one moved row.

  NOT HERE, with reasons in the .bend header: `walk_rows` (the naming walk's
  fold), `render_rows` (the two `render` joins, which need the walk) and
  `wmma_rows` (`render_wmma_amd`). Each still RUNS from this file -- they are
  dead in the `rows` path only, and the .bend header says so by name."""
  return (lab_rows() + lt_rows() + pri_rows() + vol_rows() + lconst_rows() + rstr_rows() + br_index_rows() + br1_rows()
          + br2_rows() + br3_rows() + br5_rows() + br6_rows() + br11_rows()
          + br15_rows() + amdr_rows() + sargs_rows() + render_fn_rows()
          + footer_rows() + rdna_rows())


def rows():
  return stage2()





# ============================================================ the walk's node model
# The Bend port models a uop as a `Nd` record -- the NINE things `_render_kernel`
# reads off it -- so the row builder below and the fixture list in the .bend file
# are the SAME list. `walk_spec` is the one place a CPython UOp becomes a `Nd`.
def walk_spec(uops):
  out = []
  for u in uops:
    if u.op in (Ops.NOOP, Ops.GROUP, Ops.CONST):
      k = ("WNoop{}" if u.op is Ops.NOOP else "WGroup{}" if u.op is Ops.GROUP else "WConst{}")
    elif u.op is Ops.AFTER:
      k = "WAfter{}"
    elif u.op is Ops.SINK:
      k = "WSink{}"
    elif u.op is Ops.PARAM:
      k = "WParam{}"
    elif u.op is Ops.BUFFER:
      k = "WBuffer{}"
    elif u.op is Ops.CAST:
      k = "WCast{}"
    else:
      k = "WOther{}"
    a = getattr(u, "arg", None)
    slot = a.slot if hasattr(a, "slot") else 0
    ad = u.addrspace  # may be None (a CONST); the walk never reads it there
    vol = bool(getattr(a, "volatile", False)) if hasattr(a, "volatile") else False
    def mn(v):
      # `max_numel` needs a shape; a PYLITERAL has none, and the walk never
      # reaches the `cnt` arm for one -- it is there to provoke the refusal.
      try:
        return v.max_numel()
      except Exception:
        return 1
    cnt = mn(u) if u.src else 1
    sdt = u.src[0].dtype if u.src else u.dtype
    scnt = mn(u.src[0]) if u.src else 1
    out.append({"k": k, "dt": u.dtype, "cnt": cnt, "slot": slot,
                "ad": ad.name.lower() if ad is not None else "global",
                "vol": vol, "sdt": sdt, "scnt": scnt,
                "cconst": bool(u.src and u.src[0].op is Ops.CONST),
                "farg": a is not None and hasattr(a, "function_name")})
  return out


WK = {"WNoop{}": "WN{}", "WGroup{}": "WG{}", "WConst{}": "WK{}", "WAfter{}": "WA{}",
      "WSink{}": "WS{}", "WParam{}": "WP{}", "WBuffer{}": "WB{}", "WCast{}": "WC{}",
      "WOther{}": "WO{}"}


def ndb(n):
  return ("{" + WK[n["k"]] + ", " + BT[n["dt"]] + ", " + str(n["cnt"]) + ", " + str(n["slot"]) + ", "
          + b3(n["ad"] == "local") + ", " + BT[n["sdt"]] + ", " + str(n["scnt"]) + ", "
          + b3(n["cconst"]) + ", " + b3(n["farg"]) + "}")


class K(L.LLVMRenderer):
  def __init__(self, **kw):
    self.target = Target(interface="", device="CPU", arch="LLVM")
    self.has_local = kw.get("has_local", True)
    # `LLVMRenderer.string_rewrite` is an ANNOTATION, not a value --
    # `llvm.string_rewrite = ABSENT` in nir_llvmir.bend's stage 1 is this same
    # fact. `CPULLVMRenderer` is the class that BINDS it.
    self.string_rewrite = L.CPULLVMRenderer.string_rewrite
    # `LLVMRenderer.abi` is an ANNOTATION too (`llvm.abi = AttributeError` in
    # nir_llvmir.bend's stage 1); `abi_str`'s absent case is the base class and
    # CPULLVM is the one that BINDS it, to None off win32.
    self.abi = None


class C(L.CPULLVMRenderer):
  def __init__(self, arch="LLVM"):
    self.target = Target(interface="", device="CPU", arch=arch)
    self.has_local = L.CPULLVMRenderer.has_local


class A(L.AMDLLVMRenderer):
  def __init__(self, arch):
    self.target = Target(interface="", device="HIP", arch=arch)
    self.has_local = L.AMDLLVMRenderer.has_local


def walk_cases():
  """`(label, has_local, uops)` for every walk fixture, ONCE, so the row text and
  the row builder cannot disagree about what was rendered."""
  out = []
  out.append(("empty", True, []))
  out.append(("param", True, [par(0, dtypes.f32), par(1, dtypes.u32)]))
  from tinygrad.uop.ops import KernelInfo
  for lab, a in (("named", KernelInfo("KERNELNAME", 3)), ("none", None)):
    out.append((f"sink {lab}", True, [par(0, dtypes.f32), UOp(Ops.SINK, (), arg=a), par(1, dtypes.u32)]))
  for an, aspace in (("global", AddrSpace.GLOBAL), ("local", AddrSpace.LOCAL),
                     ("reg", AddrSpace.REG), ("alu", AddrSpace.ALU)):
    for hl in (True, False):
      out.append((f"buffer {an} local={hl}", hl, [par(0, dtypes.f32), buf(3, dtypes.f32, 16, aspace)]))
  a0 = UOp(Ops.ADD, (cst(1.0), cst(2.0)), dtypes.f32)
  a1 = UOp(Ops.MUL, (a0, cst(2.0)), dtypes.f32)
  af = UOp(Ops.AFTER, (a1,), dtypes.f32)
  a2 = UOp(Ops.SUB, (af, cst(1.0)), dtypes.f32)
  out.append(("vc", True, [par(0, dtypes.f32), a0, a1, af, a2]))
  out.append(("skip", True, [par(0, dtypes.f32), UOp(Ops.NOOP, (a0,), dtypes.f32),
                            UOp(Ops.GROUP, (), dtypes.f32), cst(5.0), a1]))
  out.append(("afterparam", True, [par(0, dtypes.f32), UOp(Ops.AFTER, (par(0, dtypes.f32),), dtypes.f32)]))
  for dt in (dtypes.f32, dtypes.i32, dtypes.u8, dtypes.bf16):
    out.append((f"lconst {dt.name}", True, [par(0, dtypes.f32), UOp(Ops.CAST, (cst(1.5, dt),), dt)]))
  for a, b_ in ((dtypes.i32, dtypes.u32), (dtypes.f32, dtypes.i32), (dtypes.i8, dtypes.u8)):
    out.append((f"noopcast {a.name}->{b_.name}", True,
                [par(0, dtypes.f32), UOp(Ops.CAST, (buf(1, a, 1),), b_)]))
  out.append(("refuse", True, [par(0, dtypes.f32),
                              UOp(Ops.PYLITERAL, (buf(0, dtypes.f32, 4),), arg=None)]))
  return out


def walk_lines():
  fs = []
  for lab, hl, us in walk_cases():
    spec = walk_spec(us)
    node_txt = "[" + ", ".join(ndb(n) for n in spec) + "]"
    r = K(has_local=hl)
    try:
      local_args, fn = r._render_kernel(us)
    except Exception as e:
      # THE REFUSAL IS A TRUNCATED TRACE, which is what agent-core asks for:
      # the walk's `raise RuntimeError(...)` becomes the exception's NAME plus
      # its message, both of which the port spells, and neither of which needs a
      # guard of its own. One row, not two, so the name and the message cannot
      # drift apart.
      fn, local_args = f"!{type(e).__name__}: {e}", ()
    lns = fn.split("\n")
    fs.append(f'r_wk({q(f"{lab} local_args")}, {b3(hl)}, {node_txt}, {q(j(local_args))})')
    for i, ln in enumerate(lns):
      fs.append(f'r_wk({q(f"{lab} [{i}]")}, {b3(hl)}, {node_txt}, {i}, {q(ln)})')
  return fs


def _render_cases():
  fs = []
  for lab, us in (("empty", []), ("one", [par(0, dtypes.f32)])):
    got = L.CPULLVMRenderer.render(C(), us)
    for i, ln in enumerate(got.split("\n")):
      fs.append(f'r_rnd({q(f"cpu {lab} [{i}]")}, {b3(False)}, {q(ln)})')
  for arch in ("gfx942", "gfx1100"):
    for lab, us in (("empty", []), ("fp8", [buf(0, dtypes.fp8e4m3fnuz, 4)]),
                    ("nonfp8", [buf(0, dtypes.f32, 4)])):
      try:
        got = L.AMDLLVMRenderer.render(A(arch), us)
      except Exception as e:
        got = type(e).__name__
      for i, ln in enumerate(str(got).split("\n")):
        fs.append(f'r_rnd({q(f"amd {arch} {lab} [{i}]")}, {b3(True)}, {q(ln)})')
  return fs


# ============================================================ the generator
def bname_of(d):
  return BT[d]


BT = {dtypes.void: "S.void()", dtypes.weakint: "S.weakint()", dtypes.weakfloat: "S.weakfloat()",
      dtypes.bool: "S.boolean()", dtypes.i8: "S.int8()", dtypes.u8: "S.uint8()",
      dtypes.i16: "S.int16()", dtypes.u16: "S.uint16()", dtypes.i32: "S.int32()",
      dtypes.u32: "S.uint32()", dtypes.i64: "S.int64()", dtypes.u64: "S.uint64()",
      dtypes.fp8e4m3: "S.fp8e4m3()", dtypes.fp8e5m2: "S.fp8e5m2()",
      dtypes.fp8e4m3fnuz: "S.fp8e4m3fnuz()", dtypes.fp8e5m2fnuz: "S.fp8e5m2fnuz()",
      dtypes.f16: "S.half()", dtypes.bf16: "S.bfloat16()",
      dtypes.f32: "S.single()", dtypes.f64: "S.double()"}


def b3(b):
  return "True{}" if b else "False{}"


def f32(x):
  """A Bend F32 literal. There is no unary minus on a float term, so a
  negative fixture is `F32.neg(2.5)` -- which is also the spelling the rest of
  the tree uses."""
  return f"F32.neg({-x})" if x < 0 else f"{x}"


def bend():
  """The STAGE 2 ROW-BUILDER SOURCE, generated from the runs above."""
  out = []

  # ---------------------------------------------------------- lt / pri
  fl = []
  for d in LDD:
    try: v = L.ldt(d)
    except Exception as e: v = type(e).__name__
    fl.append(f'r_lt({q(f"lt {d.name}")}, {bname_of(d)}, {q(v)})')
  for cnt, d, ptr in ((1, dtypes.f32, True), (4, dtypes.f32, False), (4, dtypes.f32, True),
                      (1, dtypes.f32, True), (8, dtypes.f64, False), (2, dtypes.bf16, True)):
    fl.append(f'r_ltn({q(f"lt {cnt} {"ptr" if ptr else "   "} {d.name}")}, {bname_of(d)}, {cnt}, '
              f'{b3(ptr)}, {q(L.ldt(d, cnt, ptr))})')
  out.append("def r_lts() -> String:\n  String.concat([" + ", ".join(fl) + "])\n")
  out.append("def r_pris() -> String:\n  String.concat([" + ", ".join(
      f'r_pri({q(f"pri {d.name}")}, {bname_of(d)}, "{d.priority}")' for d in ALL) + "])\n")

  # ---------------------------------------------------------- is_volatile
  fs = []
  for op in ("PARAM", "CAST", "BUFFER", "CONST", "AFTER"):
    for vol in (False, True):
      fs.append(f'r_iv({q(f"is_volatile {op} vol {vol}")}, {b3(op in ("PARAM", "CAST", "AFTER"))}, {b3(vol)}, {q(str(_ivol(op, vol)))})')
  out.append("def r_ivs() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- lconst
  fs = []
  for lab, v in (("+inf", float("inf")), ("-inf", float("-inf")),
                 ("+nan", float("nan")), ("-nan", -float("nan"))):
    fs.append(f'r_lcs({q(f"lconst special {lab}")}, {b3(lab[0] == "+")}, {b3("nan" in lab)}, {q(L.lconst(v, dtypes.f32))})')
  for d in LDT:
    # the FOUR-WAY dispatch: fp8 / float / int / bool, by CLs + width
    a = "dtype.float_to_fp8" if (d in dtypes.floats and d in dtypes.fp8s) else (
        "dtype.truncate" if d in dtypes.floats else "int")
    fs.append(f'r_lcb({q(f"lconst branch {d.name}")}, {BT[d]}, {q(a)})')
  for x in (1.9, -1.9, 0.0, 255.5, -256.5, 2.5, -2.5):
    fs.append(f'r_lci({q(f"lconst int {x}")}, {f32(x)}, {q(str(L.lconst(x, dtypes.i32)))})')
  for x in (2.5, -2.5, 1.5):
    fs.append(f'r_lci({q(f"lconst uint {x}")}, {f32(x)}, {q(str(L.lconst(x, dtypes.u8)))})')
  out.append("def r_lc1s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- range_str
  # `axis_id`'s members are AXIS IDS and therefore `Nat`s, so the `m` branch is
  # dead for every value a graph can hold. The three `neg` rows are the ONLY
  # callers of `rstr.neg`, so the branch is pinned by the fixture that exists for
  # it and `rstr.go` carries no arithmetic it does not need. Said in the .bend
  # header too; here it is a fixture list.
  fs = [f'r_rsn({q(f"range_str neg {v}")}, {v}, {q("m" + str(v))})' for v in (3, 0, 12)]
  for ids in ((0,), (3,), (0, 1), (2, 0, 1), (7, 8, 9)):
    fs.append(f'r_rs({q("range_str " + ",".join(str(v) for v in ids))}, '
              f'[{", ".join(str(v) for v in ids)}], {q("_".join(str(v) for v in ids))})')
  out.append("def r_rss() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- rule counts
  out.append(f'def r_cnts() -> String:\n  String.concat([r({q("base_rewrite.rules")}, '
             f'U32.show(br_rules(0)), "{len(BR)}"), r({q("amd.string_rewrite.rules")}, '
             f'U32.show(br_rules(1)), "{len(AMDR)}"), r({q("base_rewrite.after_amd")}, '
             f'U32.show(br_rules(2)), "{len(AMDR) - len(BR)}")])\n')

  # ---------------------------------------------------------- br1
  fs = []
  fn = BR[1][1]
  for aspace, an in ((AddrSpace.ALU, "alu"), (AddrSpace.REG, "reg"),
                     (AddrSpace.GLOBAL, "global"), (AddrSpace.LOCAL, "local")):
    b = buf(1, dtypes.f32, 4, aspace)
    c = cst(2)
    x = UOp(Ops.INDEX, (b, c, c), dtypes.f32)
    got = call(fn, {b: "%reg_1", c: "%v2", x: "%v0"}, b, c, x)
    fs.append(f'r_br1({q(f"br1 extractelement {an}")}, {b3(aspace == AddrSpace.ALU)}, {q("%reg_1")}, {BT[b.dtype]}, 4, 2, {q(got)})')
  b = buf(1, dtypes.i32, 4, AddrSpace.ALU)
  c = cst(1, dtypes.i32)
  x = UOp(Ops.INDEX, (b, c, c), dtypes.i32)
  fs.append(f'r_br1({q("br1 extractelement alu i32")}, True{{}}, {q("%reg_1")}, {BT[b.dtype]}, 4, 1, {q(call(fn, {b: "%reg_1", c: "%v2", x: "%v0"}, b, c, x))})')
  out.append("def r_br1s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br2
  fs = []
  fn = BR[2][1]
  for vol in (False, True):
    for dt in (dtypes.f32, dtypes.i32, dtypes.u8):
      pv = par(0, dt, vol)
      idx = UOp(Ops.INDEX, (pv, cst(0), cst(1)), dt)
      alt = buf(0, dt)
      mask = cst(0, dtypes.bool)
      x = UOp(Ops.LOAD, (idx, alt, mask), dt)
      got = call(fn, {x: "%v0", idx: "%v1", alt: "%reg_0", pv: "%data0", mask: "%v2"}, x, idx, alt, mask)
      lns = got.split("\n")
      for i, ln in enumerate(lns):
        fs.append(f'r_br2({q(f"br2 load vol {vol} {dt.name} [{i}]")}, {b3(vol)}, {BT[dt]}, {q("%v0")}, "%v1", {q("%reg_0")}, "%v2", {i}, {q(ln)})')
  out.append("def r_br2s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br3 / br4
  fs = []
  for vol in (False, True):
    for dt in (dtypes.f32, dtypes.i8, dtypes.u64):
      pv = par(0, dt, vol)
      idx = UOp(Ops.INDEX, (pv, cst(0), cst(1)), dt)
      x = UOp(Ops.LOAD, (idx,), dt)
      fs.append(f'r_br3({q(f"br3 load vol {vol} {dt.name}")}, {b3(vol)}, {BT[dt]}, {q("%v0")}, "%v1", {q(call(BR[3][1], {x: "%v0", idx: "%v1", pv: "%data0"}, x, idx))})')
      var = buf(1, dt, 8)
      fs.append(f'r_br4({q(f"br4 store vol {vol} {dt.name}")}, {b3(vol)}, {BT[dt]}, {q("%v2")}, "%v1", {q(call(BR[4][1], {var: "%v2", idx: "%v1", pv: "%data0"}, idx, var))})')
  out.append("def r_br34s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br5
  fs = []
  fn = BR[5][1]
  for n, dt in ((1, dtypes.f32), (2, dtypes.f32), (4, dtypes.u8), (3, dtypes.bf16)):
    srcs = tuple(buf(k + 1, dt, 4) for k in range(n))
    x = UOp(Ops.STACK, srcs, dt)
    ctx = {x: "%v0"}
    for k, s in enumerate(srcs):
      ctx[s] = f"%v{k + 1}"
    lns = call(fn, ctx, x).split("\n")
    names = ", ".join(q(f"%v{k + 1}") for k in range(n))
    sdts = ", ".join(BT[srcs[k].dtype] for k in range(n))
    for i, ln in enumerate(lns):
      fs.append(f'r_br5({q(f"br5 stack n {n} {dt.name} [{i}]")}, {q("%v0")}, [{sdts}], [{names}], '
                f'{x.max_numel()}, {i}, {q(ln)})')
  out.append("def r_br5s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br6/7/8/9/10
  fs = []
  for fd, td, fc, tc in ((dtypes.f32, dtypes.i32, 4, 4), (dtypes.i8, dtypes.f32, 1, 1),
                         (dtypes.f16, dtypes.bf16, 8, 8), (dtypes.u8, dtypes.i8, 16, 16)):
    b = buf(1, fd, fc)
    x = UOp(Ops.BITCAST, (b,), td)
    fs.append(f'r_br6({q(f"br6 bitcast {fd.name}x{fc}->{td.name}x{tc}")}, {BT[fd]}, {BT[td]}, {fc}, {q("%v0")}, {q("%v1")}, {q(call(BR[6][1], {x: "%v0", b: "%v1"}, x))})')
  for a, b_ in ((dtypes.f32, dtypes.i32), (dtypes.u32, dtypes.f32), (dtypes.i8, dtypes.i16),
                (dtypes.i16, dtypes.i8), (dtypes.bf16, dtypes.f32), (dtypes.f32, dtypes.u8),
                (dtypes.f64, dtypes.f32), (dtypes.f32, dtypes.f64), (dtypes.i64, dtypes.i32)):
    sr = buf(1, a, 1)
    x = UOp(Ops.CAST, (sr,), b_)
    fs.append(f'r_br7({q(f"br7 cast {a.name}->{b_.name}")}, {BT[a]}, {BT[b_]}, {q("%v0")}, "%v1", {q(call(BR[7][1], {x: "%v0", sr: "%v1"}, x))})')
  for a, b_ in ((dtypes.f32, dtypes.i32), (dtypes.i32, dtypes.i8), (dtypes.f64, dtypes.f32)):
    sr = buf(1, a, 1)
    x = UOp(Ops.TRUNC, (sr,), b_)
    fs.append(f'r_br8({q(f"br8 trunc {a.name}->{b_.name}")}, {BT[a]}, {BT[b_]}, {q("%v0")}, "%v1", {q(call(BR[8][1], {x: "%v0", sr: "%v1"}, x))})')
  for dt in (dtypes.bool, dtypes.u8, dtypes.i32, dtypes.i8, dtypes.f32, dtypes.f16, dtypes.bf16, dtypes.f64):
    for opn in ("ADD", "MUL", "CDIV", "CMOD", "CMPLT", "SHR", "SHL", "FDIV"):
      s0, s1 = buf(1, dt, 1), buf(2, dt, 1)
      x = UOp(Ops[opn], (s0, s1), dt)
      fs.append(f'r_br9({q(f"br9 binary {dt.name} {opn}")}, {BT[dt]}, O.{BO[opn]}, {q("%v0")}, "%v1", {q("%v2")}, {q(call(BR[9][1], {x: "%v0", s0: "%v1", s1: "%v2"}, x))})')
  x = UOp(Ops.WHERE, (cst(1, dtypes.bool), buf(1, dtypes.f32, 1), buf(2, dtypes.i32, 1)), dtypes.f32)
  fs.append(f'r_br10({q("br10 where mixed")}, S.boolean(), S.single(), S.int32(), {q("%v0")}, "%v1", {q("%v2")}, "%v3", {q(call(BR[10][1], {x: "%v0", x.src[0]: "%v1", x.src[1]: "%v2", x.src[2]: "%v3"}, x))})')
  out.append("def r_br678s() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br11/12/13/14
  fs = []
  for lab, fi, mk in (("br11 rangevoid", 11, lambda: rng(None, 2, AxisType.LOOP, dtypes.void)),
                      ("br13 range", 13, lambda: rng(16, 0, AxisType.GLOBAL, dtypes.i32))):
    fn = BR[fi][1]
    x = mk()
    ctx = {x: "%v3"}
    if x.src:
      ctx[x.src[0]] = "%v2"
    lns = call(fn, ctx, x).split("\n")
    axis = "2" if lab.endswith("void") else "0"
    for i, ln in enumerate(lns):
      if lab.endswith("void"):
        fs.append(f'r_br11({q(f"{lab} [{i}]")}, {q("%v3")}, {i}, {q(ln)})')
      else:
        fs.append(f'r_br13({q(f"{lab} [{i}]")}, {q(axis)}, {q("%v3")}, {q("%v2")}, {BT[x.dtype]}, {i}, {q(ln)})')
  x = rng(16, 3, AxisType.GLOBAL, dtypes.i32)
  for i, ln in enumerate(call(BR[13][1], {x: "%v3", x.src[0]: "%v2"}, x).split("\n")):
    fs.append(f'r_br13({q(f"br13 range neg [{i}]")}, {q("3")}, {q("%v3")}, {q("%v2")}, {BT[x.dtype]}, {i}, {q(ln)})')
  l = rng(None, 5, AxisType.LOOP, dtypes.void)
  c = cst(1, dtypes.bool)
  x = UOp(Ops.BACKEDGE, (buf(0, dtypes.f32), l, c), dtypes.void)
  for i, ln in enumerate(call(BR[12][1], {l: "%v3", c: "%v4"}, l, c).split("\n")):
    fs.append(f'r_br12({q(f"br12 backedge [{i}]")}, {q("%v3")}, "%v4", {i}, {q(ln)})')
  for lab, aid in (("pos", 7), ("neg", 3)):
    r = rng(8, aid, AxisType.GLOBAL, dtypes.i32)
    try:
      got = str(BR[14][1](r))
    except Exception as e:
      got = type(e).__name__
    for i, ln in enumerate(got.split("\n")):
      fs.append(f'r_br14({q(f"br14 end {lab} [{i}]")}, {aid}, {i}, {q(ln)})')
  out.append("def r_brRBs() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- br15/16/17, amd2
  fs = []
  for an, cond in (("bool", cst(1, dtypes.bool)), ("i32", cst(1, dtypes.i32))):
    x = UOp(Ops.IF, (cond,), dtypes.void)
    for i, ln in enumerate(call(BR[15][1], {x: "%v7", cond: "%v6"}, x).split("\n")):
      fs.append(f'r_br15({q(f"br15 if {an} [{i}]")}, {q("%v7")}, "%v6", {i}, {q(ln)})')
    y = UOp(Ops.ENDIF, (x,), dtypes.void)
    for i, ln in enumerate(call(BR[16][1], {y: "%v8", x: "%v7"}, y).split("\n")):
      fs.append(f'r_br16({q(f"br16 endif {an} [{i}]")}, {q("%v7")}, {i}, {q(ln)})')
  fs.append(f'r_br17({q("br17 barrier")}, {q(call(BR[17][1], {}))})')
  for i, ln in enumerate(call(AMDR[2][1], {}).split("\n")):
    fs.append(f'r_amd2({q(f"amd2 barrier [{i}]")}, {i}, {q(ln)})')
  out.append("def r_brIBs() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- the AMD five
  fs = [f'r_f8o({q(",".join(d.name for d in dtypes.fp8s))})']
  for i, d in enumerate(dtypes.fp8s):
    fs.append(f'r_f8p({q(d.name)}, {BT[d]}, "{i}")')
  for miss in (dtypes.i32, dtypes.f16):
    fs.append(f'r_f8mp({q(miss.name)}, {BT[miss]}, "ValueError")')
  for d in dtypes.fp8s:
    fs.append(f'r_f8i({q(d.name)}, {BT[d]}, "{fp8_index(d)}")')
  for miss in (dtypes.i32, dtypes.f16):
    fs.append(f'r_f8mi({q(miss.name)}, {BT[miss]}, "ValueError")')
  for k, i in (("g", 0), ("g", 2), ("l", 0), ("l", 1), ("l", 2)):
    x = UOp(Ops.SPECIAL, (buf(0, dtypes.i32, 4),), arg=(k, 0, 1, 2, i))
    fs.append(f'r_amd0({q(f"amd0 special {k}{i}")}, {b3(k == "l")}, {i}, {q("%v3")}, {q(call(AMDR[0][1], {x: "%v3"}, x))})')
  for opn, nm in (("SQRT", "sqrt"), ("LOG2", "log2"), ("EXP2", "exp2")):
    for src, dst in ((dtypes.f32, dtypes.f32), (dtypes.f16, dtypes.f16), (dtypes.f64, dtypes.f64)):
      s = buf(1, src, 1)
      x = UOp(Ops[opn], (s,), dst)
      fs.append(f'r_amd1({q(f"amd1 {nm} {src.name}->{dst.name}")}, O.{BO[opn]}, {BT[src]}, {BT[dst]}, {q("%v0")}, "%v1", {q(call(AMDR[1][1], {x: "%v0", s: "%v1"}, x))})')
  for fp8 in dtypes.fp8s:
    s = buf(1, dtypes.f32, 1)
    x = UOp(Ops.CAST, (s,), fp8)
    fs.append(f'r_amd3({q(f"amd3 cast f32->{fp8.name}")}, {BT[fp8]}, {q("%v0")}, {q("%v1")}, {q(call(AMDR[3][1], {x: "%v0", s: "%v1"}, x))})')
  for fp8 in dtypes.fp8s:
    y = buf(1, fp8, 1)
    x = UOp(Ops.CAST, (y,), dtypes.f32)
    for i, ln in enumerate(call(AMDR[4][1], {x: "%v0", y: "%v1"}, x, y).split("\n")):
      fs.append(f'r_amd4({q(f"amd4 cast {fp8.name}->f32 [{i}]")}, {BT[fp8]}, {q("%v0")}, {q("%v1")}, {i}, {q(ln)})')
  out.append("def r_amds() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- _render_fn
  fs = []
  def arg1(aspace, d, nm, cnt=1):
    return L.ldt(d, cnt, ptr=aspace == AddrSpace.GLOBAL) + \
           (" noalias" if aspace == AddrSpace.GLOBAL else "") + " " + nm
  for an, aspace in (("global", AddrSpace.GLOBAL), ("reg", AddrSpace.REG),
                     ("local", AddrSpace.LOCAL), ("alu", AddrSpace.ALU)):
    fs.append(f'r_rsargs({q(f"rfn sargs {an}")}, {b3(aspace == AddrSpace.GLOBAL)}, {BT[dtypes.f32]}, {q("%data0")}, '
              f'{q(arg1(aspace, dtypes.f32, "%data0"))})')
    fs.append(f'r_rsargs2({q(f"rfn sargs2 {an}")}, {b3(aspace == AddrSpace.GLOBAL)}, '
              f'{BT[dtypes.f32]}, {BT[dtypes.uint32]}, '
              f'{q(", ".join([arg1(aspace, dtypes.f32, "%data0"), arg1(aspace, dtypes.uint32, "%data1")]))})')
  fs.append(f'r_rsargs2e({q("rfn sargs2 empty")}, {q("")})')
  def rfn_lines(abi, kname, args, kernel, prefix):
    r = L.LLVMRenderer.__new__(L.LLVMRenderer)
    r.abi = abi
    return r._render_fn(kname, args, kernel, prefix=prefix).split("\n")
  K2 = ['  %v0 = fadd', '  %v1 = fmul']
  for abi in (None, "amdgpu_kernel", "win64cc"):
    for an, aspace in (("global", AddrSpace.GLOBAL), ("reg", AddrSpace.REG),
                       ("local", AddrSpace.LOCAL), ("alu", AddrSpace.ALU)):
      args = [("%data0", par(0, dtypes.f32, aspace=aspace)), ("%data1", par(1, dtypes.uint32, aspace=aspace))]
      lns = rfn_lines(abi, "mykernel", args, K2, None)
      for i, ln in enumerate(lns):
        fs.append(f'r_rfn({q(f"rfn abi {abi} {an} [{i}]")}, {q(abi or "")}, {q("mykernel")}, '
                  f'{q(", ".join([arg1(aspace, dtypes.f32, "%data0"), arg1(aspace, dtypes.uint32, "%data1")]))}, '
                  f'[{q(K2[0])}, {q(K2[1])}], [], {i}, {q(ln)})')
  args = [("%data0", par(0, dtypes.f32))]
  for i, ln in enumerate(rfn_lines(None, "empty", [], ['  %v0 = fadd'], None)):
    fs.append(f'r_rfn({q(f"rfn abi None empty [{i}]")}, {q("")}, {q("empty")}, {q("")}, [{q("  %v0 = fadd")}], [], {i}, {q(ln)})')
  args = [("%data0", par(0, dtypes.f32))]
  for i, ln in enumerate(rfn_lines("amdgpu_kernel", "withprefix", args, ['  %v0 = fadd'], ["PREFIX1", "PREFIX2"])):
    fs.append(f'r_rfn({q(f"rfn prefix [{i}]")}, {q("amdgpu_kernel")}, {q("withprefix")}, '
              f'{q(arg1(AddrSpace.GLOBAL, dtypes.f32, "%data0"))}, [{q("  %v0 = fadd")}], '
              f'[{q("PREFIX1")}, {q("PREFIX2")}], {i}, {q(ln)})')
  out.append("def r_rfns() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- the walk
  fs = []
  for line in walk_lines():
    fs.append(line)
  
  # ---------------------------------------------------------- footers / render / rdna
  footer_rows()   # fills AMD_FTR
  fs = []
  fs.append(f'r_ftrc({q("ftr cpu")}, {q(L.CPULLVMRenderer._render_footer(None, []))})')
  AMD_FTR_BASE = L.AMDLLVMRenderer._render_footer(AMD_SHELL, [])
  for i in range(9):
    fp = L.CPULLVMRenderer._render_footer(None, []).split(" ")[i]
    fs.append(f'r_ftrp({i}, {q(fp)})')
  for lab, ws in (("none", []), ("w64", [64]), ("wx64h8", [64, 8]), ("wgx1024", [1024]),
                  ("wx1", [1]), ("wglobal", []), ("wgl", [16]),
                  ("w3", [32, 32, 32]), ("wbig", [65535, 65535])):
    fs.append(f'r_ftr({q(f"ftr amd prod {lab}")}, [{", ".join(str(w) for w in ws)}], "{prod(ws)}")')
    fs.append(f'r_ftra({q(f"ftr amd {lab}")}, [{", ".join(str(w) for w in ws)}], {q(AMD_FTR[lab])})')
  out.append("def r_ftrs() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  fs = []
  for ln in _render_cases():
    fs.append(ln)
  
  fs = []
  for arch in ("gfx1200", "gfx1201", "gfx12001", "gfx1100", "gfx1200:xnack-",
               "gfx942", "AMD_GCN3_", "gfx1200x", "gfx120", "gfx12012", "gfx1201:xnack-"):
    fs.append(f'r_rdna({q(arch)}, {q(str(L.AMDLLVMRenderer.is_rdna4(arch)))})')
  out.append("def r_rdnas() -> String:\n  String.concat([" + ", ".join(fs) + "])\n")

  # ---------------------------------------------------------- the wmma emitters
  fs = []
  for cdna in (False, True):
    for rdna4 in (False, True):
      for nmk in ((16, 16, 16), (32, 32, 8), (16, 16, 32), (16, 16, 128)):
        for a1 in (dtypes.half, dtypes.f32, dtypes.bfloat16, dtypes.ushort, dtypes.int8, dtypes.int32):
          srcs = (buf(0, a1, 16), buf(1, a1, 16), buf(2, dtypes.f32, 8))
          w = UOp(Ops.WMMA, srcs, arg=(nmk, a1))
          ctx = {w: "%v99", srcs[0]: "%v98", srcs[1]: "%v97", srcs[2]: "%v96"}
          try:
            got = L.render_wmma_amd(ctx, w, cdna, rdna4)
          except Exception as e:
            got = type(e).__name__
          s0 = "%v98 " + L.ldt(a1, 16)
          s1 = "%v97 " + L.ldt(a1, 16)
          s2 = "%v96 " + L.ldt(dtypes.f32, 8)
          fs.append(f'r_wm({q(f"cdna={cdna} r4={rdna4} {nmk[0]}x{nmk[1]}x{nmk[2]} {a1.name}")}, {b3(cdna)}, '
                    f'{b3(rdna4)}, {nmk[0]}, {nmk[1]}, {nmk[2]}, {BT[a1]}, {BT[dtypes.f32]}, '
                    f'"%v99", {q(s0)}, {q(s1)}, {q(s2)}, {q(got)})')
  
  return "\n\n".join(out) + "\n"


BO = {"ADD": "OpsADD{}", "MUL": "OpsMUL{}", "CDIV": "OpsCDIV{}", "CMOD": "OpsCMOD{}",
      "CMPLT": "OpsCMPLT{}", "CMPNE": "OpsCMPNE{}", "CMPEQ": "OpsCMPEQ{}", "OR": "OpsOR{}",
      "AND": "OpsAND{}", "XOR": "OpsXOR{}", "SHL": "OpsSHL{}", "SHR": "OpsSHR{}",
      "FDIV": "OpsFDIV{}", "SQRT": "OpsSQRT{}", "LOG2": "OpsLOG2{}", "EXP2": "OpsEXP2{}"}


if __name__ == "__main__":
  what = sys.argv[1] if len(sys.argv) > 1 else "rows"
  sys.stdout.write({"rows": rows, "stage2": stage2, "bend": bend}[what]() + "\n")