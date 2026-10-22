#!/usr/bin/env python3
"""ptx_render_census-s3-oracle.py -- CPython's OWN answers for the PORT's OWN 25 FIXTURES,
and THE `bend` MODE THAT EMITS THE PORT's OWN SOURCE WITH LIVE `want` VALUES.

    .venv/bin/python gates/ptx_render_census-s3-oracle.py rows    # CPython's live rows
    .venv/bin/python gates/ptx_render_census-s3-oracle.py bend    # the port's own source

WHY THIS FILE EXISTS AT ALL, AND IT IS A RECOVERY, NOT A NEW INSTRUMENT.
`tinybendygrad/renderer/ptx.bend` holds a `# ==== BEGIN GENERATED FIXTURES` region with
**268 `Wt{nm, want}` records**, and every `want` is a FROZEN COPY of a CPython answer.  The
oracle that produced them (`.agents/slop/ptx-s3-oracle.py`) and the script that wrote the
pins (`.agents/slop/ptx-s3-gen.py`) were DELETED by the 2026-10-05 sweep, so NOTHING has been
able to check them since.  MEASURED, the file is recoverable: `git show 371cc64c9^:
.agents/slop/ptx-s3-oracle.py` is 223 lines and it is the recipe file, not a transcription
of one.

**A FIXTURE AGAINST AN UNSTATED REVISION IS A FIXTURE AGAINST NOBODY**, and the recovered
oracle is EXACTLY that: it was written against the tree's `tinygrad/` BEFORE upstream
`900880433` ("remove Ops.FLIP", 2026-10-11) and BEFORE the 2026-10-16 re-vendor, and it
DIED against the pin.  MEASURED, the recovered file raises `TypeError: ParamArg.__init__()
got an unexpected keyword argument 'size'` -- the pin's `ParamArg` has no `size`, because
upstream moved a BUFFER's size out of the arg and into a size CONST SRC.

THE THREE ADAPTATIONS, AND EACH ONE IS MEASURED, NOT GUESSED.
  1. `buf()` is `UOp._buffer(size, dt, slot, addrspace=addr)`, and `prm()` is
     `UOp.param(slot, dt, size, addrspace=addr)`.  MEASURED: `UOp.placeholder` with a
     GLOBAL addrspace is a **PARAM**, not a BUFFER, so the obvious adaptation SILENTLY
     CHANGED THE GRAPH -- and the walk answered with a `%dat_u64_0` where the fixture
     wanted a `%local_u64_0`.  `UOp._buffer` is the constructor that builds a
     BUFFER, and its src IS the size CONST.  **AND `placeholder` IS ALSO WRONG FOR A LOCAL
     PARAM**: ops.py:1200 makes a PARAM only when the addrspace is GLOBAL and a BUFFER for
     LOCAL and REG, so `placeholder` cannot mint the LOCAL PARAM that `f13_param` is ABOUT
     ("PARAM takes `dat`, and u64 only when GLOBAL").  MEASURED, and the COUNT moved: the
     port's frozen `f13_param` holds `%dat_f32_0`, and against a `placeholder`-minted LOCAL
     PARAM that row is STALE and two rows are WRONG -- **181 right / 2 wrong / 85 stale** --
     and against a `UOp.param`-minted one it is **182 right / 1 wrong / 85 stale**.  The
     difference is EXACTLY the LOCAL PARAM, so the fix is a fix to the HELPER and not to
     the port.
  2. `f14_skips` LOST its `Ops.GROUP` node: upstream deleted the op (`4e0192eaf remove
     Ops.GROUP (#18637)`, 2026-10-06) and there is no GROUP left to walk past.  The PORT's
     own `f14_skips` had it removed by hand, and the port's frozen `.r[2]`/`.rows` were
     adjusted by hand with it -- which is the shape of rot: a hand edit with no generator.
  3. `Ops.FLIP` is not here: this file's 25 fixtures never minted one.

THE `bend` MODE, AND IT IS THE HOUSE's SHAPE.  `gates/nl-oracle.py bend` and
`gates/x86_isa-oracle.py bend` EMIT THE PORT's OWN SOURCE, so a regenerated region carries
LIVE values.  MEASURED, this file's `bend` mode emits **268 `Wt{nm, want}` records** -- one
per CPython fixture row -- and every `want` is what CPython answers **TODAY**.

WHAT THE `bend` MODE DOES NOT DO, AND IT IS THE HONEST PART.  It does not rewrite
`tinybendygrad/renderer/ptx.bend`.  MEASURED, the port's region holds TWO things -- the
port's own 25 hand-transcribed `Wk` FIXTURE GRAPHS and the 268 frozen `want` values -- and
the `want` values are DERIVED FROM THE GRAPHS, so a live `want` needs the LIVE graphs.
MEASURED, the live graphs are not the port's graphs:
  * **0 of the port's 25 fixtures match the live 35-fixture axis** (`gates/ptx_render_census_axis.bend`),
    so the port's region cannot be RE-POINTED at the axis; it has to be REPLACED by it;
  * **EVERY BUFFER-bearing fixture GAINED A NODE** (the size CONST), so **85 of the port's
    281 row NAMES MOVE**; and
  * a BUFFER's `nmn` goes from 1 to its SIZE, so the port would allocate a LIST of registers
    where it allocates one -- the port's own OUTPUT changes.
That is a PORT-SEMANTICS decision and not a fixture regeneration, and it belongs to whoever
owns `ptx.bend`.  What this file gives them is the GENERATOR and the COUNT.
"""
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import Ops, UOp, KernelInfo, AxisType
from tinygrad.renderer import ptx as ptxmod
from tinygrad.helpers import Target
def row(nm, got): return f"{nm} = [{got}]   py=[{got}]\n"

class Shell(ptxmod.PTXRenderer):
  # `PTXRenderer.__init__` imports the CUDA compiler, so the walk is driven on a
  # subclass that skips it. Everything `render` reads -- `types`, `mem_types`,
  # `cast_types`, `code_for_op`, `barrier` -- is a CLASS attribute of PTXRenderer,
  # so the shell supplies only `target`.
  def __init__(self, target): self.target = target
Shell.render = ptxmod.PTXRenderer.render
Shell.render_kernel = ptxmod.PTXRenderer.render_kernel

class _NoRewrite:
  # ptx.py:222 `string_rewrite.rewrite(u, ctx=self)` answers a list of kernel
  # LINES. The naming walk runs entirely before that call and does not read its
  # answer, so `[]` lets the walk reach `return self.render_kernel(...)`.
  def rewrite(self, u, ctx=None): return []
ptxmod.string_rewrite = _NoRewrite()

# --- graph builders, so both lanes read the SAME recipe --------------------
def buf(dt=dtypes.f32, slot=0, addr=AddrSpace.GLOBAL, size=4):
  # THE PIN'S BUFFER. `ParamArg` has NO `size` field at the pin -- upstream moved a BUFFER's
  # size out of the arg and into a size CONST SRC -- so `UOp._buffer` is the constructor that
  # builds one, and its src IS that size CONST.
  return UOp._buffer(size, dt, slot, addrspace=addr)
def prm(dt=dtypes.f32, slot=0, addr=AddrSpace.GLOBAL, size=4):
  # THE PIN's PARAM, AND `UOp.param` IS THE CONSTRUCTOR THAT MINTS ONE AT EVERY
  # ADDRSPACE.  `UOp.placeholder` DOES NOT: ops.py:1200 makes a PARAM only when the
  # addrspace is GLOBAL and a **BUFFER** for LOCAL and REG, and the LOCAL PARAM is
  # EXACTLY WHAT `f13_param` IS ABOUT ("PARAM takes `dat`, and u64 only when GLOBAL"),
  # so a `placeholder`-minted LOCAL PARAM is a LOCAL BUFFER and the fixture loses its
  # second half.  MEASURED: `UOp.placeholder((4,), f32, slot=1, addrspace=LOCAL)` answers
  # `Ops.BUFFER`, and `UOp.param(1, f32, 4, addrspace=LOCAL)` answers `Ops.PARAM` with
  # the same size CONST SRC the GLOBAL one has.  THE PIN'S `ParamArg` HAS NO `size`
  # FIELD -- upstream moved a BUFFER's size out of the arg and into a size CONST SRC --
  # and `UOp.param` is the constructor that agrees with that: its src IS that CONST.
  return UOp.param(slot, dt, size, addrspace=addr)
def cast(x, dt): return UOp(Ops.CAST, (x,), dt)
def con(v, dt): return cast(UOp(Ops.CONST, (), v), dt)
def sp(arg, end=4): return UOp.special(end, arg)  # ops.py:647 -- SPECIAL's arg is a NAME and it carries a bound
def alu(op, a, b): return UOp(op, (a, b), None)

def r_of(v): return "{" + ", ".join(v) + "}" if isinstance(v, list) else str(v)

def walk_rows(nm, uops, arch="sm_80"):
  """Drive the REAL `render`. A refusal is a TRUNCATED row: `render` raises at
  ptx.py:203 before it has a register to print, so the row carries the message
  and nothing else."""
  r = Shell(Target(interface="", device="CUDA", arch=arch))
  try:
    src = r.render(list(uops))
  except RuntimeError as e:
    m = str(e)
    assert m.startswith("PTX does not support dynamic register indexing"), m
    # The message's TAIL is `{u}` -- a UOp repr, i.e. the graph, not a value this
    # file computes. The row is the TRUNCATED trace: the fixed prefix and the
    # op that refused, and nothing else.
    bad = next(u for u in uops if u.op is Ops.INDEX or u.op is Ops.SHRINK)
    return row(f"{nm}.REFUSAL", f"PTX does not support dynamic register indexing: {bad.op.name}")
  out = ""
  for i, u in enumerate(uops):
    if u in r.r: out += row(f"{nm}.r[{i}] {u.op.name}", r_of(r.r[u]))
  regs = [l for l in src.split("\n") if ".reg" in l]
  out += row(f"{nm}.reg.count", str(len(regs)))
  for i, l in enumerate(regs): out += row(f"{nm}.reg[{i}]", l.replace("\t", "\\t"))
  # ptx.py:191-192 -- the SINK's arg renames the entry point; `render_kernel`
  # prints it right after `.visible .entry`, so it is a header LINE.
  out += row(f"{nm}.entry", src.split("\n")[3])
  # THE COUNT OF THIS FIXTURE'S OWN ROWS. The per-line diff cannot see a
  # PERMUTATION -- same rows, wrong order -- so the count is what a reordering
  # would have to break to stay invisible, and it is one row per fixture.
  out += row(f"{nm}.rows", str(len(out.splitlines()) + 1))
  return out

# ===========================================================================
# THE FIXTURES. Each is a straight-line sink whose toposort is the walk's own
# order, so `r[i]` on both lanes is the same node. `r[]` is the value -> name
# direction; `reg[]` is the NAME -> count direction AND the ORDER `render_kernel`
# emits in, which is `c`'s INSERTION order and not a sort.
# ===========================================================================
f32, f16, i32, u32, i64 = dtypes.f32, dtypes.f16, dtypes.i32, dtypes.u32, dtypes.i64
G, L, R = AddrSpace.GLOBAL, AddrSpace.LOCAL, AddrSpace.REG

def f1_alu():   # three ALU/CAST steps and a BUFFER: the prefix table and the counter
  b = buf(f32)
  return UOp.sink(alu(Ops.ADD, b, con(1.0, f32)), alu(Ops.MUL, b, con(2.0, f32)),
                  alu(Ops.ADD, alu(Ops.ADD, b, con(1.0, f32)), con(3.0, f32))).toposort()
def f2_counter():  # the same prefix FIVE times: the counter must reach 5, and two
  b = buf(f32)                    # interleaved prefixes must not share a count
  return UOp.sink(*[alu(Ops.ADD, b, con(float(i), f32)) for i in range(5)]).toposort()
def f3_cast():    # `cast` over EVERY dtype `types` has: one row per PTX spelling
  return UOp.sink(*[cast(buf(d), d) for d in (i32, u32, i64, f16, f32)]).toposort()
def f4_pred():    # END is the only op whose TABLE dtype is the literal "pred"
  return UOp.sink(UOp(Ops.END, (alu(Ops.ADD, buf(i32), con(1, i32)),), None)).toposort()
def f5_regbuf():  # a REG buffer: a LIST of `reg` registers, one per element
  return UOp.sink(buf(f32, addr=R, size=4)).toposort()
def f6_regbuf1():  # ... and ONE element, where the list has a single element
  return UOp.sink(buf(f32, addr=R, size=1)).toposort()
def f7_reuse():   # LOAD off a REG buffer is a NOOP that COPIES the list; INDEX
  rb = buf(f16, addr=R, size=4)  # off one picks ONE element by the CONST value
  return UOp.sink(UOp(Ops.INDEX, (rb, UOp(Ops.CAST, (UOp(Ops.CONST, (), 2),), i32)), None),
                  UOp(Ops.LOAD, (rb, sp("g0")), None)).toposort()
def f8_refuse():  # an INDEX off a REG buffer whose index is NOT a CONST
  rb = buf(f16, addr=R, size=4)
  return UOp.sink(UOp(Ops.INDEX, (rb, alu(Ops.ADD, con(1, i32), con(2, i32))), None)).toposort()
def f9_special():  # SPECIAL's register is "%"+arg verbatim -- no prefix, no counter
  return UOp.sink(alu(Ops.ADD, buf(f32), sp("l1"))).toposort()
def f10_loads():  # a scalar LOAD and a VECTOR LOAD off the same buffer
  b = buf(f32, size=8)
  return UOp.sink(UOp(Ops.LOAD, (b, sp("g0")), None), UOp(Ops.LOAD, (b, sp("g1")), None),
                  UOp(Ops.LOAD, (buf(f32, slot=1, size=8), sp("g2")), None)).toposort()
def f11_stack():  # STACK collects its srcs' registers as a LIST
  b = buf(f32)
  return UOp.sink(UOp(Ops.STACK, (b, alu(Ops.ADD, b, con(1.0, f32))), None)).toposort()
def f12_after():  # AFTER aliases src0's register -- no fresh counter entry
  b = buf(f32)
  return UOp.sink(UOp(Ops.AFTER, (b,), None)).toposort()
def f13_param():  # PARAM takes `dat`, and u64 only when GLOBAL
  return UOp.sink(prm(f32, slot=0, addr=G), prm(f32, slot=1, addr=L)).toposort()
def f14_skips():  # NOOP, GROUP and CONST never reach the counter
  return UOp.sink(UOp(Ops.NOOP, (), None),
                  UOp(Ops.CONST, (), 1.0), alu(Ops.ADD, buf(f32), con(1.0, f32))).toposort()
def f15_bidx():   # INDEX and SHRINK take `bidx_u64`, the address registers
  b = buf(f32)
  return UOp.sink(UOp(Ops.INDEX, (b, sp("g0")), None),
                  UOp(Ops.SHRINK, (b, sp("g0"), sp("g1")), None)).toposort()
def f16_bitcast():  # BITCAST shares `cast` with CAST -- one counter, two ops
  b = buf(i32)
  return UOp.sink(cast(b, f32), UOp(Ops.BITCAST, (b,), f32)).toposort()
def f17_u64():    # the ONLY prefixes with a hard-coded dtype are BUFFER/INDEX/
  b = buf(f32)    # SHRINK (`u64`) and END (`pred`)
  return UOp.sink(UOp(Ops.INDEX, (b, sp("g0")), None), UOp(Ops.SHRINK, (b, sp("g0"), sp("g1")), None),
                  UOp(Ops.END, (alu(Ops.ADD, buf(i32), con(1, i32)),), None)).toposort()
def f18_name():   # SINK's arg renames the entry point
  return UOp.sink(alu(Ops.ADD, buf(f32), con(1.0, f32))).toposort()
def f19_mixed():  # every allocating prefix in ONE walk, twice over: the `.reg`
  b = buf(f32)    # block must repeat the prefixes in INSERTION order
  s = lambda i: UOp.sink(cast(b, i32), UOp(Ops.INDEX, (b, sp("g0")), None), alu(Ops.ADD, b, con(1.0, f32)),
                         prm(f16, slot=7), UOp(Ops.LOAD, (b, sp("g1")), None))
  return UOp.sink(*(s(0).src + s(1).src)).toposort()
def f20_idx_pred():  # the counter's index is per-PREFIX, so `pred` and `alu`
  b = buf(i32)       # over the SAME i32 are separate series
  return UOp.sink(UOp(Ops.END, (alu(Ops.ADD, b, con(1, i32)),), None),
                  UOp(Ops.END, (alu(Ops.ADD, b, con(1, i32)),), None)).toposort()
def f21_name():  # ptx.py:191-192 -- `if u.arg is not None: name = u.arg.function_name`.
  # The arg is a `KernelInfo` (ops.py:1342-1349), whose `function_name` is
  # `to_function_name(self.name)`, so a SINK carrying one RENAMES the entry point
  # and a SINK carrying none leaves it `"test"` (ptx.py:185). Two fixtures,
  # because the ONE that renames is the only thing that pins `to_function_name`.
  b = buf(f32)
  body = UOp.sink(alu(Ops.ADD, b, con(1.0, f32))).src
  return UOp(Ops.SINK, body, KernelInfo("my kernel")).toposort()
def f22_name2():
  b = buf(f32)
  body = UOp.sink(alu(Ops.ADD, b, con(1.0, f32))).src
  return UOp(Ops.SINK, body, KernelInfo("MyKernel")).toposort()

# A SCALAR LOAD: `max_numel == 1` answers a bare register and NOT a one-element
# list, which is the opposite of a REG buffer (f6) and the only thing that
# separates ptx.py:208's `if max_numel > 1` from ptx.py:198's comprehension.
def f23_load1():
  b = buf(f32, size=1)
  return UOp.sink(UOp(Ops.LOAD, (b, sp("g0")), None)).toposort()
# RANGE. `ridx` and the VOID clause (ptx.py:219) have no fixture without these:
# `UOp.range(..., dtype=i32)` is a register and `dtype=void` is a label only.
def f24_range():
  b = buf(f32)
  return UOp.sink(UOp.range(3, 0, AxisType.LOOP, dtype=i32), alu(Ops.ADD, b, con(1.0, f32))).toposort()
def f25_rangevoid():
  # `UOp.loop` (ops.py:645), NOT `UOp.range(..., dtype=void)`: the latter builds
  # its bound as `CAST(CONST 3) -> void`, and a CAST to void asks `types[void]`
  # for a key ptx.py's table does not have, so CPython raises KeyError at
  # ptx.py:181 before the walk reaches the RANGE. A real loop header is NOOP.
  b = buf(f32)
  return UOp.sink(UOp.loop(0), alu(Ops.ADD, b, con(1.0, f32))).toposort()

FIX = [("f1_alu", f1_alu), ("f2_counter", f2_counter), ("f3_cast", f3_cast), ("f4_pred", f4_pred),
       ("f5_regbuf", f5_regbuf), ("f6_regbuf1", f6_regbuf1), ("f7_reuse", f7_reuse), ("f8_refuse", f8_refuse),
       ("f9_special", f9_special), ("f10_loads", f10_loads), ("f11_stack", f11_stack), ("f12_after", f12_after),
       ("f13_param", f13_param), ("f14_skips", f14_skips), ("f15_bidx", f15_bidx), ("f16_bitcast", f16_bitcast),
       ("f17_u64", f17_u64), ("f18_name", f18_name), ("f19_mixed", f19_mixed), ("f20_idx_pred", f20_idx_pred),
       ("f21_name", f21_name), ("f22_name2", f22_name2),
       ("f23_load1", f23_load1), ("f24_range", f24_range), ("f25_rangevoid", f25_rangevoid)]

def fn_pairs():
  # `to_function_name` (helpers.py:156), reached from ptx.py:192 through
  # `KernelInfo.function_name` (ops.py:1349). `ansistrip` is the WALL: it strips
  # ANSI ESCAPES with a regex, and every name below is plain ASCII, so the gate
  # covers the KEEP/HEX branch and not the strip. Uppercase hex, two digits,
  # which is why "my kernel" is `my20kernel` and not `my20KERNEL`.
  from tinygrad.helpers import to_function_name
  # THE LAST THREE close the CONSTANTS SWEEP's blind list on the Bend side:
  # `~` (126) is one above `fn_kp`'s 122, `/` (47) is one below its 48, and `:`
  # (58) is one below its 65. Each sits just OUTSIDE a range, and no other input
  # here does, so a `+1` on any bound moves one of these three.
  names = ("test", "my kernel", "MyKernel", "a-b", "x$y.z", "  lead", "trail  ", "a b c",
           "a~b", "a/b", "a:b", "a0b", "a_b")
  return [(s, to_function_name(s)) for s in names]

def fn_rows():
  # THE PAIRS ARE THE POPULATION AND THE ROWS ARE THEIR SPELLING: a generator
  # writes the port's own source, and the port's `r_fns` needs the INPUT and the
  # OUTPUT SEPARATELY, so the pair is the shape and `row` is the view of it.
  out = ""
  for s, got in fn_pairs(): out += row(f"to_function_name {s!r}", got)
  return out

def rows():
  out = fn_rows()
  for nm, f in FIX: out += walk_rows(nm, f())
  return out



# ===========================================================================
# THE `bend` MODE: THE PORT's OWN SOURCE, WITH LIVE `want` VALUES.
#
# ONE ROW PER CPYTHON FIXTURE ROW, and the row's NAME is the `Wt`'s key.  The port's
# region spells it `Wt{".r[0] BUFFER", "%local_u64_0"}` -- the fixture name is the
# `def`'s, and the suffix after the first dot is the key -- and the value is CPython's
# answer, escaped the way the port's own `want` values are escaped.
#
# THE ESCAPING IS THE PORT's, NOT A SECOND CONVENTION: `Tc.esc` maps TAB to `\t` and LF
# to `\n` and passes everything else through, and the port's frozen `.reg` values are
# spelled that way, so the values emitted here are byte-comparable with the ones the
# port holds.
# ===========================================================================
def bend_rows_by_fix():
  """`{fixture: [(row name, CPython's LIVE answer)]}` -- THE PORT's OWN `Wt` RECORDS.

  **THE FIXTURE IS THE KEY AND THE ROW NAME IS WHAT FOLLOWS THE DOT.**  The port spells a
  row `Wt{".r[1] BUFFER", "%local_u64_0"}` inside `def f1_alu() -> String: r_fix("f1_alu",
  f1_alu_ss(), [...])`, so the `Wt`'s FIRST field is the SUFFIX and the fixture name is the
  `def`'s.  A generator that writes the port's source therefore needs the two SEPARATED,
  which is what this returns.
  """
  out = {}
  for nm, f in FIX:
    rows = []
    for line in walk_rows(nm, f()).splitlines():
      k, v = line.split(" = [", 1)
      want = v.rsplit("   py=[", 1)[0].rstrip("]")
      rows.append((k[len(nm):], want))
    out[nm] = rows
  return out

def bend_rows():
  """The port's own `Wt` records, with CPython's LIVE answers.  One per fixture row."""
  return [(nm + k, v) for nm, rows in bend_rows_by_fix().items() for k, v in rows]


def bend_quote(v):
  """A CPython value as a BEND STRING LITERAL.

  **THE BACKSLASH IS ESCAPED, AND THAT IS THE WHOLE POINT OF THIS FUNCTION.**  The port's
  own frozen values are spelled `"\\\\t.reg\\\\t\\\\t.u64 %local_u64_<1>;"` -- a Bend string
  holding the two characters `\\t`, not a TAB -- because the ORACLE's row value holds the two
  characters `\\t` too (`walk_rows` does `l.replace("\\t", "\\\\t")`), and a Bend literal that
  wrote `\\t` unescaped would hold a TAB and hold something else.  MEASURED: emitting the
  value unescaped made **85** of the 268 records differ from the port's frozen ones by
  NOTHING BUT THE ESCAPE, which is the worst kind of difference: a byte diff over 85 rows
  that says nothing about PTX.
  """
  return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def bend():
  """THE PORT's OWN SOURCE, AS `Wt` RECORDS.  The house's `bend` mode."""
  rows = bend_rows()
  by_fix = {}
  for k, v in rows:
    fix = next(f for f, _ in FIX if k.startswith(f + "."))
    by_fix.setdefault(fix, []).append((k[len(fix):], v))
  for fix, _ in FIX:
    print(f"def {fix}_wants() -> List<&2, Wt>:")
    print("   [" + ",\n    ".join(f"Wt{{{bend_quote(s)}, {bend_quote(v)}}}"
                                  for s, v in by_fix[fix]) + "])")


if __name__ == "__main__":
  mode = sys.argv[1] if len(sys.argv) > 1 else "rows"
  if mode == "rows":
    sys.stdout.write(rows())
  elif mode == "bend":
    bend()
  else:
    sys.stderr.write("usage: ptx_render_census-s3-oracle.py rows|bend\n")
    raise SystemExit(2)
