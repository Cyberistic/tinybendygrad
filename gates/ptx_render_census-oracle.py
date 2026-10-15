#!/usr/bin/env python3
"""ptx_render_census-oracle.py -- CPython's OWN answers for every row
`gates/ptx_render_census.bend` prints from `tinybendygrad/renderer/ptx.bend`.

    .venv/bin/python gates/ptx_render_census-oracle.py

WHAT THIS LANE IS, AND WHY IT CALLS AND DOES NOT CALL.
======================================================
`gates/*_graph_census*` compare an OP SEQUENCE. `gates/fold_graph_census*` compare a
VALUE. `gates/cstyle_render_census*` compare a rendered STRING for a C renderer.
`gates/wgsl_render_census*` compare a rendered WGSL MODULE. `gates/amd_dsl_census*`
compare a TRIPLE.

`ptx.py` RETURNS A STRING TOO, but a DIFFERENT ONE, and the difference is the design of
this file. `PTXRenderer.render` returns ONE `str`: a whole PTX MODULE, whose newlines are
real newlines, whose body is produced by TWENTY-THREE `string_rewrite` rules NONE of
which is ported. So the module is NOT a thing the two lanes can both print, and pretending
otherwise would produce a row that compares a header against a header and calls the
kernel correct. The printed form here is therefore:

  * ONE `name=value` row per ANSWER both lanes can produce, value in canonical text with
    `\n` spelled `\\n`. Never a prefix, never a length, never a hash --
    `ops.bend`'s `Rng.sig` printed a 3-op prefix and a deep node swap was invisible.

  * ONE `<fixture>.mod` row per fixture carrying CPython's WHOLE return value, and it is a
    DECLARED DIVERGENCE, not a comparison. The port answers
    `ABSENT:string_rewrite(23) not ported` -- a LOUD refusal, because an oracle that
    answered `""` would AGREE with a port that answers `""`. The pin holds CPython's own
    module text, so the moment the port grows one the pin fails and the row leaves
    DIVERGES. That is the whole-module form `wgsl` used for `render_kernel`, applied to a
    function whose body really is missing rather than merely large.

THE RULE THAT SHAPED EVERY CALL BELOW: WHEREVER CPYTHON HAS A CALL, CALL IT.
`gates/tn_bitwise_not-oracle.py` lost seven rows by hand-building `cast.ne(True)` instead
of calling `Tensor.bitwise_not()`. So:

  * the walk rows are read off `PTXRenderer.render`'s OWN `self.r`, after a REAL
    `render()` call on a REAL `UOp` graph. Nothing here re-derives a register name.
  * the `.reg` declaration lines are read off the RETURNED MODULE, which is where
    `render_kernel` puts `c.items()`.
  * `types`/`mem_types`/`cast_types` are read off `PTXRenderer` ITSELF.
  * `fmt` has no name to call -- it is a CLOSURE inside `render_kernel` -- so `fmt_*` is
    `render_kernel`'s own output: `render_kernel([line], ...)` and the line read back out
    of the module. CPython's `fmt` is applied, not reimplemented.
  * `to_function_name` is `KernelInfo(name).function_name`, CPython's own property.

WHAT THE FIXTURE IS, AND THE ONE CHOICE MADE HERE. A fixture is a real CPython kernel
graph; the BEND lane's fixture is the same graph written as a list of `Wk` records. The
ONLY thing chosen on this side is that graph. It is self-checking: `render()` visits
exactly the nodes the `Wk` list names, so a transcription that mistook an op for another
misaligns the `.r<i>` indices and the gate goes red on the ROW COUNT before any value is
read. `--dump-fixtures` prints the CPython step list for every fixture, which is the
axis the Bend lane must be transcribed FROM.
"""
import inspect
import sys

from tinygrad.dtype import dtypes
from tinygrad.helpers import Target, to_function_name
from tinygrad.uop.ops import UOp, Ops, KernelInfo
from tinygrad.uop.spec import AddrSpace
from tinygrad.renderer.ptx import PTXRenderer

R = PTXRenderer(Target(arch="sm_89"))

F32, I32, U32, I64, F16, BOOL = dtypes.float32, dtypes.int32, dtypes.uint32, dtypes.int64, dtypes.half, dtypes.bool
ROWS = []


def row(nm, v):
    ROWS.append(f"{nm}={v}")


def C(v, dt=None):
    return UOp.const(v, dt)


def CAST(a, dt):
    return UOp(Ops.CAST, src=(a,), arg=dt)


def CCONST(v, dt):
    """`UOp.cconst` -- a CONST forced through a CAST, and the ONLY shape ptx.py:202 accepts.

    ptx.py:202 tests `u.src[1].op is Ops.CAST and u.src[1].src[0].op is Ops.CONST`.
    `UOp.const(2, dtypes.int32)` is `CONST weakint` then `CAST i32`, so CASTing THAT
    gives `CAST(CAST(CONST))` and the subscript guard is FALSE -- which is how the first
    draft of `f05_regbuf4` hit ptx.py:203's raise on a fixture that was SUPPOSED to take
    the accept arm. MEASURED, and it is why `CCONST` exists rather than `CAST(C(...))`.
    """
    return UOp.cconst(v, dt)


def BITCAST(a, dt):
    return UOp(Ops.BITCAST, src=(a,), arg=dt)


def SP(n, name):
    """A SPECIAL whose RANGE has a STRONG dtype.

    `UOp.special(64, "g0")` builds `SPECIAL(RANGE weakint)`, and ptx.py's walk visits that
    RANGE, so `ssa("ridx", u)` asks `self.types[dtypes.weakint]` for a key the table does
    NOT have and CPython raises `KeyError: dtypes.weakint` (MEASURED -- and that refusal
    is kept as its own fixture, `f31_weakint`, because it is the port's headline finding).
    Every OTHER fixture wants the walk to get PAST the RANGE, so it spells it strongly.
    """
    return UOp(Ops.SPECIAL, src=(UOp.range(n, 0, dtype=dtypes.int32),), arg=name)


# --------------------------------------------------------------------------
# THE FIXTURES. Real graphs: every node here is reachable from the SINK, which is
# what `UOp.toposort()` walks, which is what `render` is handed.
# --------------------------------------------------------------------------
def F01_alu():
    a, b = CAST(C(3.0), F32), CAST(C(4.0), F32)
    return UOp(Ops.ADD, src=(a, b))


def F02_counter():
    acc = CAST(C(1.0), F32)
    for i in range(2, 7):
        acc = UOp(Ops.ADD, src=(acc, CAST(C(float(i)), F32)))
    return acc


def F03_cast5():
    outs = [CAST(C(i + 0.5), dt) for i, dt in enumerate((I32, U32, I64, F16, F32))]
    return UOp.stack(*outs)


def F04_end():
    # ptx.py:126 -- `UPat(Ops.END, src=(UPat(), UPat(Ops.RANGE, name="r")))`: src[1] must
    # be a RANGE. A NOOP there matches no rule and `render` raises ptx.py:224. MEASURED:
    # `UOp(Ops.END, src=(alu, UOp(Ops.NOOP)))` answers
    # "failed to render Ops.END with dtypes.f32 srcs [dtypes.f32, dtypes.void]".
    return UOp(Ops.END, src=(F01_alu(), UOp.range(8, 0, dtype=dtypes.int32)))


def F05_regbuf4():
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.REG)
    return UOp(Ops.INDEX, src=(buf, CCONST(2, I32)))


def F06_regbuf1():
    buf = UOp.placeholder((1,), F32, slot=0, addrspace=AddrSpace.REG)
    return UOp(Ops.INDEX, src=(buf, CCONST(0, I32)))


def F07_reuse():
    # ptx.py:200 -- LOAD whose src[0] is ALU (a SPECIAL) is a COPY, not a memory read.
    return SP(4, "g0").load()


def F08_refuse():
    # ptx.py:202-203 -- INDEX into a REG register by something that is not a CONST of a
    # CAST. ptx.py RAISES; this is the ONE refusal the walk has.
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.REG)
    dyn = CCONST(0, I32) + CCONST(1, I32)
    return UOp(Ops.INDEX, src=(buf, dyn))


def F09_special():
    return UOp(Ops.ADD, src=(CAST(C(1.0), F32), SP(4, "g0")))


def F09b_launch():
    # ptx.py:166-167 -- `local_dims` are the SPECIALs whose arg[0] is "l", and
    # `.maxntid` is the PRODUCT of their vmax. A fixture with an "l" is the only thing
    # that can see `launch_bounds` at all.
    return UOp(Ops.ADD, src=(SP(8, "l0"), SP(16, "l1")))


def F10_loads():
    outs = [SP(64, f"g{i}").load() for i in range(3)]
    return UOp.stack(*outs)


def F11_stack():
    return UOp.stack(CAST(C(1.0), F32), F01_alu())


def F12_after():
    return F01_alu().after(F01_alu())


def F13_param():
    g = UOp.placeholder((16,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    l = UOp.placeholder((16,), F32, slot=1, addrspace=AddrSpace.LOCAL)
    return UOp.stack(g, l)


def F14_skips():
    # ptx.py:187 skips NOOP, GROUP and CONST. `UOp.stack` refuses a NOOP (it has no
    # shape), so the skips come in through the ops that CONSUME them: GROUP's own srcs,
    # and a CONST that is a SINK's direct child. MEASURED: the first draft's
    # `UOp.stack(UOp(Ops.NOOP), ...)` answers "shape requested, but Ops.NOOP doesn't
    # have a shape" -- the ORACLE's own bug, found by reading the message.
    grp = UOp(Ops.GROUP, src=(UOp(Ops.NOOP), UOp(Ops.NOOP)))
    return (grp, C(7.0), F01_alu())


def F15_bidx():
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    return UOp(Ops.SHRINK, src=(buf, SP(64, "g0")), arg=(0,))


def F16_bitcast():
    return BITCAST(CAST(C(3.0), F32), F32)


def F17_u64():
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    ix = UOp(Ops.INDEX, src=(buf, SP(64, "g0")), arg=(0,))
    sh = UOp(Ops.SHRINK, src=(ix, SP(64, "g1")), arg=(0,))
    return UOp(Ops.END, src=(UOp(Ops.ADD, src=(sh, sh)), UOp.range(8, 0, dtype=dtypes.int32)))


def F19_mixed():
    # No `UOp.stack` across two shapes: MEASURED, `UOp.stack(CAST(ix.load(), I32), p)`
    # answers "all shapes must match for stack, got [(), (16,)]". Every operand is
    # `.index(0)`-ed down to a scalar instead.
    # SCALAR placeholders, shape (). MEASURED: with shape (16,) the `.index(0)` builds
    # `INDEX(BUFFER, LOAD(...))` and ptx.py:203's CONST-of-CAST subscript guard is FALSE,
    # so ptx.py RAISES "dynamic register indexing" -- the oracle's own fixture bug, found
    # by reading the message rather than by trusting it.
    # The INDEX form, `UOp(Ops.INDEX, src=(buf, SPECIAL), arg=(0,))`, NOT `.index()`:
    # MEASURED that `.index(0)` builds `INDEX(BUFFER, LOAD(...))` and ptx.py:203's
    # CONST-of-CAST subscript guard is FALSE, so ptx.py RAISES "dynamic register
    # indexing". And NOT a bare `buf.load()` either -- MEASURED that ptx.py's two LOAD
    # rules BOTH require `src[0]` to be an INDEX or a SHRINK, so an un-indexed PARAM load
    # answers "failed to render Ops.LOAD". Both were the oracle's own fixture bugs.
    # NOTHING REDUCES A LOAD TO A SCALAR. MEASURED, three ways, all of them the oracle's
    # own bug rather than the port's: `.index(0)` builds `INDEX(LOAD(...), ...)`, whose
    # subscript is a CONST rather than a CONST-of-a-CAST, so ptx.py:203 raises "dynamic
    # register indexing"; a bare `buf.load()` has no INDEX for ptx.py's LOAD rules to
    # match, so ptx.py:224 raises "failed to render Ops.LOAD"; and `UOp.placeholder((),..)`
    # has no axis to subscript. A SHAPE-(4,) buffer indexed once and loaded is the shape a
    # real kernel has, and it is the shape that gives the LIST form of ptx.py:208.
    p = UOp.placeholder((4,), F16, slot=0, addrspace=AddrSpace.GLOBAL)
    buf = UOp.placeholder((4,), F32, slot=1, addrspace=AddrSpace.GLOBAL)
    pl = UOp(Ops.INDEX, src=(p, SP(64, "g2")), arg=(0,)).load()
    bl = UOp(Ops.INDEX, src=(buf, SP(64, "g0")), arg=(0,)).load()
    return UOp.stack(CAST(bl, I32), CAST(pl, F32))


def F23_load1():
    # `max_numel == 1` is the ONLY thing that separates ptx.py:208's comprehension from a
    # bare string, so the buffer has ONE element.
    buf = UOp.placeholder((1,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    return UOp(Ops.INDEX, src=(buf, SP(64, "g0")), arg=(0,)).load()


def F24_range():
    # ptx.py:216 -- RANGE gets prefix "ridx". A NON-void one allocates a register.
    return UOp.stack(UOp.range(4, 0, dtype=dtypes.int32), F01_alu())


def F25_rangevoid():
    # ptx.py:219 -- `if u.op is Ops.RANGE and u.dtype == dtypes.void: prefix = None`.
    # `UOp.loop` is the only constructor that gives a RANGE a VOID dtype: its src is a
    # NOOP, and a NOOP's dtype is void. The SINK takes a second child because a loop's
    # shape is (4,) and `UOp.stack` needs matching shapes.
    return (UOp.loop(0), UOp.range(4, 0, dtype=dtypes.int32))


def F26_store():
    # ptx.py:99-105 -- the STORE rules, the ONLY place `.vN` and the register LIST appear.
    # ptx.py:102 -- the STORE's src[0] must be an INDEX or a SHRINK. `buf.store(...)`
    # gives `STORE(BUFFER, val)` and no rule matches; MEASURED, ptx.py answers
    # "failed to render Ops.STORE with dtypes.void srcs [dtypes.f32, dtypes.f32,
    # dtypes.i32]". The STORE goes on the INDEX.
    buf = UOp.placeholder((16,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    ix = UOp(Ops.INDEX, src=(buf, SP(64, "g0")), arg=(0,))
    return ix.store(UOp.stack(*[CAST(C(float(i)), F32) for i in range(4)]))


def F27_loadbool():
    # ptx_matcher rule 5 (ptx.py:49-51) -- a bool LOAD through a uint8 view. This is a
    # GRAPH REWRITE, so the graph `render` receives is the REWRITTEN one, and the bool
    # buffer's `mem_types` entry (`u8`, not `pred`) is what the row turns on.
    buf = UOp.placeholder((1,), BOOL, slot=0, addrspace=AddrSpace.GLOBAL)
    return UOp(Ops.INDEX, src=(buf, SP(64, "g0")), arg=(0,)).load()


def F31_weakint():
    # THE HEADLINE REFUSAL. `UOp.range(4, 0)` DEFAULTS to `dtype=dtypes.weakint`, the
    # walk allocates `ridx` for it (ptx.py:216), and ptx.py:181 asks
    # `self.types[dtypes.weakint]` for a key the twelve-entry table does not have.
    # MEASURED: `KeyError: dtypes.weakint`. NOT via `UOp.special` -- MEASURED that
    # `sint_to_uop(64)` is a `CONST dtypes.weakint` and CONSTs are skipped at ptx.py:187,
    # so `UOp.special(64, "g0")` renders FINE and the first draft of this fixture was a
    # fixture that tested nothing.
    return UOp.range(4, 0)


def F32_weakfloat():
    # THE OTHER HEADLINE. An ADD over two weakfloat CONSTs is a real node with dtype
    # `dtypes.weakfloat` and it is NOT a CONST, so ptx.py:187 does not skip it;
    # ptx.py:181 raises `KeyError: dtypes.weakfloat`. The port answers `"pred"` for
    # weakint and `""` for weakfloat -- the first is a WRONG TYPE, the second is NO TYPE.
    return UOp(Ops.ADD, src=(UOp.const(3.0), UOp.const(4.0)))


def F33_bf16cast():
    # ptx.py:231 excludes bfloat16 from `supported_dtypes` and `cast_types` has no
    # bfloat16 key, so a CAST to bf16 raises at ptx.py:181 as well.
    return UOp.const(3.0).cast(dtypes.bfloat16)


def F35_loadvec():
    # THE FIXTURE `f10_loads` AND EVERY EARLIER DRAFT OF THIS CENSUS WERE MISSING, and
    # `ptx_render_census-mutate.py`'s M1 found it: M1 -- "`pf.of`'s LOAD list flag becomes
    # always false" -- moved ZERO of 515 rows. CAUSE, MEASURED: an INDEX carrying a
    # CONCRETE `arg=(0,)` is a SHRINK, so `UOp(Ops.INDEX, src=(buf, SP), arg=(0,)).load()`
    # has `max_numel == 1` and ptx.py:208's comprehension is never reached. Every LOAD in
    # the axis was a scalar, so `Pf.lst` had no observable effect. Dropping `arg` makes the
    # INDEX a RESHAPE and the LOAD a four-element vector, which is the shape `f10_loads`
    # already used on the port side. A mutation that moves zero rows is the census naming
    # its own hole, and this one was a hole in the FIXTURE.
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.GLOBAL)
    return buf.load()


def F36_regbuf_store():
    # A STORE into a REG-space INDEX, which is ptx.py:99-101's arm whose predicate is
    # `loc.addrspace == AddrSpace.REG` -- the ONLY store rule that emits no `.vN` and no
    # memory space, and the only one that is a plain `mov`.
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.REG)
    return UOp(Ops.INDEX, src=(buf, CCONST(1, I32))).store(CAST(C(1.0), F32))


def F38_regload():
    # THE FIXTURE `ptx_render_census-mutate.py`'s M9 WAS MISSING, and M9's own recorded
    # reason for moving zero rows was WRONG. M9 makes an on-REG/ALU LOAD take ptx.py:204's
    # SUBSCRIPT arm instead of its COPY arm, and it moved zero of 557 rows; the census's own
    # note blamed finding 2 -- "it moves nothing BECAUSE the alias arm already returns the
    # wrong register" -- which was true only while `rg_at(w, 0)` answered `NONE`. Now that
    # the arm is FIXED the blame is gone and M9 is still zero, for the real reason, and this
    # fixture is the one that names it:
    #
    #   EVERY on-ALU LOAD in the axis has `src[0]` = a SPECIAL, and a SPECIAL's register is
    #   a SCALAR STRING, so subscript 0 returns it unchanged. `r[u.src[0]]` and
    #   `r[u.src[0]][0]` are the SAME STRING for every LOAD the axis has.
    #
    # A REG-space BUFFER's register is a LIST of four, so a LOAD of one is the shape where
    # the two arms genuinely disagree -- `r1` is all four registers here and `%reg_f32_0`
    # under M9. MEASURED: this graph renders, `R.render` does not refuse it.
    buf = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.REG)
    return buf.load()


def F37_twobufs():
    # THE FIXTURE EVERY EARLIER FIXTURE OF THIS CENSUS WAS MISSING, and the census's own
    # alias finding named it: ptx.py:204 reads `r[u.src[0]][u.src[1].src[0].val]`, and every
    # other INDEX/SHRINK on a REG src in this axis has its `src[0]` at STEP ZERO -- because a
    # REG `placeholder` has no srcs, so toposort always emits it first. `u.src[0]` NOT at
    # index 0 is ORDINARY (it is what `f10_loads`' three LOADs and `f12_after`'s AFTER
    # already are), and only f12/f10 said so.
    #
    # MEASURED, and this is why two buffers rather than one cleverer graph: `r[4][1]` is
    # `%reg_f32_5` and `r[0][1]` is `%reg_f32_1`, so the two candidate readers of ptx.py:204
    # ANSWER DIFFERENTLY and the row is a real discriminator rather than a coincidence.
    # MEASURED toposort, the whole axis of the defect: `INDEX(b, 1)` carries `refs=[4, 6]`.
    a = UOp.placeholder((4,), F32, slot=0, addrspace=AddrSpace.REG)
    b = UOp.placeholder((4,), F32, slot=1, addrspace=AddrSpace.REG)
    return UOp.stack(UOp(Ops.INDEX, src=(a, CCONST(2, I32))),
                     UOp(Ops.INDEX, src=(b, CCONST(1, I32))))


def F34_boolalu():
    # ptx.py:24-28 -- ADD/MUL/XOR/AND/OR BRANCH on `dt == dtypes.bool` and pick `or`/
    # `and`/`and.pred`/`xor.pred`/`or.pred`. A bool ALU node is the only thing that can
    # see that branch, and `supported_dtypes` KEEPS bool, so it is a legal dtype.
    t, f = UOp.const(True, dtypes.bool), UOp.const(False, dtypes.bool)
    return UOp.stack(UOp(Ops.OR, src=(t, f)), UOp(Ops.AND, src=(t, f)))


# (name, graph builder, SINK function_name or None for "test")
FIXTURES = [
    ("f01_alu", F01_alu, None),
    ("f02_counter", F02_counter, None),
    ("f03_cast5", F03_cast5, None),
    ("f04_end", F04_end, None),
    ("f05_regbuf4", F05_regbuf4, None),
    ("f06_regbuf1", F06_regbuf1, None),
    ("f07_reuse", F07_reuse, None),
    ("f08_refuse", F08_refuse, None),
    ("f09_special", F09_special, None),
    ("f09b_launch", F09b_launch, None),
    ("f10_loads", F10_loads, None),
    ("f11_stack", F11_stack, None),
    ("f12_after", F12_after, None),
    ("f13_param", F13_param, None),
    ("f14_skips", F14_skips, None),
    ("f15_bidx", F15_bidx, None),
    ("f16_bitcast", F16_bitcast, None),
    ("f17_u64", F17_u64, None),
    ("f19_mixed", F19_mixed, None),
    ("f23_load1", F23_load1, None),
    ("f24_range", F24_range, None),
    ("f25_rangevoid", F25_rangevoid, None),
    ("f26_store", F26_store, None),
    ("f27_loadbool", F27_loadbool, None),
    ("f28_name", F01_alu, "my kernel"),
    ("f29_name2", F01_alu, "MyKernel"),
    ("f30_noparam", F13_param, "a-b_c.d"),
    ("f31_weakint", F31_weakint, None),
    ("f32_weakfloat", F32_weakfloat, None),
    ("f33_bf16cast", F33_bf16cast, None),
    ("f34_boolalu", F34_boolalu, None),
    ("f35_loadvec", F35_loadvec, None),
    ("f36_regstore", F36_regbuf_store, None),
    ("f37_twobufs", F37_twobufs, None),
    ("f38_regload", F38_regload, None),
]

# `Ops.WMMA` and the `Ops.IF`/`Ops.ENDIF`/`Ops.RANGE`/`Ops.BACKEDGE` loop trio need
# fragment registers and a RangeDef that this census does not fabricate. They are named in
# the report as the census's own wall, not silently dropped.


def one_line(s):
    """A MODULE or a list of LINES as ONE row value: real newlines spelled `\\n`.

    Never a prefix and never a length. `wgsl_render_census`'s `rk mixed` row is 700
    characters on one line for the same reason.
    """
    # EXACTLY `tc_ptx.bend`'s `esc`, and that is not a coincidence: `esc1` maps TAB to
    # `\t` and LF to `\n` and passes every other character through, so the two lanes
    # SPELL a value the same way without agreeing on a convention. A BACKSLASH is NOT
    # escaped by either side, and MEASURED: no row value contains one -- the only
    # backslashes in `ptx.py`'s output are in `bar.sync\t0;`, where the tab is already a
    # TAB in CPython and becomes the two characters `\t` in both lanes.
    return s.replace("\n", "\\n").replace("\t", "\\t")


def run_fixture(name, build, fname):
    """`render` on a real graph, and CPython's OWN walk output read back off it."""
    try:
        root = build()
    except Exception as e:  # a fixture that cannot be BUILT is a refusal, and is loud
        row(f"{name}.mod", f"REFUSE:build:{type(e).__name__}")
        return
    sink = UOp(Ops.SINK, src=root if isinstance(root, tuple) else (root,),
               arg=KernelInfo(fname if fname is not None else "test"))
    uops = list(sink.toposort())
    mod = None
    try:
        mod = R.render(uops)
    except Exception as e:
        # ptx.py:181's KeyError, ptx.py:203's raise and ptx.py:224's all land here, and
        # all THREE ARE NAMED rather than collapsed into one word -- because an oracle
        # answering `""` for a refusal would AGREE with a port answering `""`.
        #
        # AND THE WALK ROWS ARE STILL EMITTED, which is the correction. ptx.py:208
        # assigns `r[u]` BEFORE ptx.py:222 can raise, so a refusal at 222 leaves the
        # register map COMPLETE and only the MODULE missing; ptx.py:181 and ptx.py:203
        # stop the walk earlier and leave it short. The first draft returned on the
        # exception and threw away the very rows that pin ptx.py:208 -- which is why
        # `ptx_render_census-mutate.py`'s M1 moved zero of 515 rows.
        mod = f"REFUSE:{type(e).__name__}"
    refused = isinstance(mod, str) and mod.startswith("REFUSE:")
    if refused:
        # `.reg`/`.entry` live in the MODULE, and there is no module. `render_kernel` was
        # never called, so there is nothing to read them off -- NOT a choice, a fact about
        # `render`. The census's own `refuses` flag says the same thing and `axis_hold()`
        # checks the two agree.
        for i, u in enumerate(uops):
            v = R.r.get(u)
            row(f"{name}.r{i}", "NONE" if v is None else
                (one_line(v) if isinstance(v, str) else one_line("{" + ", ".join(v) + "}")))
        row(f"{name}.mod", mod)
        return
    # THE WALK: `self.r` IS ptx.py:176's dict, read after the walk that filled it.
    #
    # ONE ROW PER STEP, NOT ONE PER ALLOCATION. A step ptx.py:187/191 SKIPS gets `NONE`,
    # and so does a step the walk reached and allocated nothing for. MEASURED, and this is
    # the population rule that makes the two lanes comparable by construction: with one row
    # per ALLOCATION the port's answer to a step is "no row", and an absent row cannot be
    # diffed against a present one -- `gates/cstyle_render_census-gate.py` records that
    # shape as a population that drifted by 10 rows the moment a fixture changed shape.
    # A `NONE` in the middle of a run is a CLAIM: this step allocated nothing.
    for i, u in enumerate(uops):
        v = R.r.get(u)
        if v is None:
            row(f"{name}.r{i}", "NONE")
        elif isinstance(v, str):
            row(f"{name}.r{i}", one_line(v))
        else:
            row(f"{name}.r{i}", one_line("{" + ", ".join(v) + "}"))
    # THE `.reg` BLOCK: ptx.py:165 prints `f".reg .{ty} %{key}<{cnt}>;"` for `c.items()`.
    lines = mod.split("\n")
    decls = [l for l in lines if l.lstrip("\t").startswith(".reg")]
    row(f"{name}.regn", len(decls))
    for i, d in enumerate(decls):
        row(f"{name}.reg{i}", one_line(d))
    entry = [l for l in lines if l.startswith(".visible .entry")]
    row(f"{name}.entry", one_line(entry[0]) if entry else "NONE")
    # THE WHOLE RETURN VALUE, and it is the LAST row of the fixture on both sides.
    row(f"{name}.mod", one_line(mod))


def main():
    # ---- 1. to_function_name, reached through CPython's OWN property -------------
    # AXIS ADMITTED: which strings to ask is a choice. The axis is the port's own 13
    # names (so the two sides name the same fixtures) plus the four BOUNDARY strings the
    # port's own sweep says were missing: `126`/`47`/`58` sit just outside a range, and
    # `48`/`95` are the digit and underscore LOW bounds. A compare written as
    # `or(ge,le)` matches every char; these five are what separates that from the truth.
    FN_AXIS = ["test", "my kernel", "MyKernel", "a-b", "x$y.z", "  lead", "trail  ", "a b c",
               "a~b", "a/b", "a:b", "a0b", "a_b", "~", "/", "Z", "_", " ", "0", "`"]
    for i, s in enumerate(FN_AXIS):
        row(f"tfn_{i}", one_line(KernelInfo(s).function_name))

    # ---- 2. THE THREE DTYPE TABLES, read off the CLASS -------------------------
    # `void` is in `S.Dt` and in no table, so all three REFUSE. A refusal is spelled.
    DTS = [dtypes.void, dtypes.bool, dtypes.int8, dtypes.uint8, dtypes.int16, dtypes.uint16,
           dtypes.int32, dtypes.uint32, dtypes.int64, dtypes.uint64, dtypes.half,
           dtypes.bfloat16, dtypes.float32, dtypes.float64, dtypes.fp8e4m3, dtypes.fp8e5m2,
           dtypes.fp8e4m3fnuz, dtypes.fp8e5m2fnuz]
    for i, d in enumerate(DTS):
        for tag, tbl in (("tyo", PTXRenderer.types), ("mto", PTXRenderer.mem_types),
                         ("cto", PTXRenderer.cast_types)):
            row(f"{tag}_{i}", tbl.get(d, f"REFUSE:KeyError({d.name})"))

    # ---- 3. `fmt`, READ OFF `render_kernel`'s OWN OUTPUT ------------------------
    # `fmt` is a closure and has no name to call. Every line of `kernel` goes through it,
    # so `render_kernel([line], ...)` and reading the body back IS CPython's `fmt`. The
    # axis is ptx.py's OWN mnemonics, because `fmt`'s rule is
    # `len(line.split(" ")[0]) > 7` and the mnemonics are where the boundary lives:
    # `mov.b32` is 7 (two tabs) and `selp.f32` is 8 (one tab).
    # EVERY ENTRY BUT ONE CARRIES A SPACE, and that is a CORRECTION rather than a style.
    # ptx.py:164 is `line.replace(" ", TAB if len(line.split(" ")[0]) > 7 else TABTAB, 1)`,
    # so a bare mnemonic has nothing to replace and the SEVEN-CHARACTER RULE NEVER FIRES.
    # MEASURED: the first draft's axis was bare mnemonics and all twenty-one rows agreed
    # on `\tmov.b32` -- twenty-one agreeing rows agreeing on a branch neither lane took.
    # `gates/ptx_render_census-gate.py`'s `claims_hold()` caught it, because its expected
    # value said two tabs. The pairs that straddle the boundary are `add.f32` (7, two
    # tabs) against `selp.f32` (8, one), and `rem.u32` (7) against `setp.eq.s32` (10).
    FMT_AXIS = ["mov.b32 %d, %a;", "selp.f32 %d, %b, %c, %a;", "add.f32 %d, %a, %b;",
                "and.pred %d, %a, %b;", "or.pred %d, %a, %b;", "xor.pred %d, %a, %b;",
                "mad.lo.s64 %d, %a, %b, %c;", "mul.lo.s16 %d, %a, %b;", "div.s32 %d, %a, %b;",
                "rem.u32 %d, %a, %b;", "setp.eq.s32 %d, %a, %b;", "setp.neu.f32 %d, %a, %b;",
                "max.s32 %d, %a, %b;", "cvt.rzi.s32.s32 %d, %a;", "rcp.approx.f32 %d, %a;",
                "shl.b32 %d, %a, %b;", "shr.u32 %d, %a, %b;", "bar.sync\t0;", "$RAW",
                "fma.rn.f32 %d, %a, %b, %c;",
                "mma.sync.aligned.m8n8k4.row.col.f32.tf32.tf32.f32 {{{d0}, {d1}}}, "
                "{{{a0}, {a1}}}, {{{b0}, {b1}}}, {{{c0}, {c1}}};"]
    for i, line in enumerate(FMT_AXIS):
        m = R.render_kernel([line], "fmt", [], [], [])
        body = m.split("\n{\n", 1)[1].rsplit("\n\tret;", 1)[0].split("\n")
        row(f"fmt_{i}", one_line(body[0]))

    # ---- 4. `kernel_prefix` and the fixed limits --------------------------------
    K = PTXRenderer.kernel_prefix.format(launch_bounds=128)
    for i, l in enumerate(K.split("\n")):
        row(f"kpf_{i}", one_line(l))
    # `,`-JOINED and not Python's tuple REPR: `T.ushow` in `tc.bend` is the port's own
    # printer for a `List<U32>` and it spells `a,b,c`. MEASURED both ways -- the tuple
    # `repr` and `T.ushow` differ by the parentheses, which is a byte diff over three rows
    # and nothing else.
    row("gmax", ",".join(str(v) for v in PTXRenderer.global_max))
    row("lmax", ",".join(str(v) for v in PTXRenderer.local_max))
    row("smax", PTXRenderer.shared_max)
    row("suffix", PTXRenderer.suffix)
    row("barrier", one_line(PTXRenderer.barrier))
    # `supported_dtypes`, `asm_for_op`, `supports_half` and `doesnt_support_half` are NOT
    # ROWS HERE, AND THE REASON IS SCOPE, NOT OMISSION. They live in
    # `tinybendygrad/renderer/tc_ptx.bend`, which has its OWN gate and its OWN mutation
    # harness (`.agents/slop/tcptx-mutate.py`). `ptx.bend` CONSUMES five helpers out of
    # that file -- `types_of`, `mem_types_of`, `cast_types_of`, `fmt`, `px_pline`, `esc`,
    # `hex1` -- and those five ARE the `tyo_/mto_/cto_/fmt_/kpf_` rows below, because a
    # census that skipped the SEAM would be a census of a file that is not used.

    # ---- 5. THE WALK -------------------------------------------------------------
    for name, build, fname in FIXTURES:
        run_fixture(name, build, fname)

    sys.stdout.write("\n".join(ROWS) + "\n")
    return 0


if __name__ == "__main__":
    if "--dump-fixtures" in sys.argv:
        for name, build, _ in FIXTURES:
            root = build()
            sink = UOp(Ops.SINK, src=root if isinstance(root, tuple) else (root,),
                       arg=KernelInfo("test"))
            uops = list(sink.toposort())
            print(f"## {name}  ({len(uops)} steps)")
            for i, u in enumerate(uops):
                n = 1
                try:
                    n = u.max_numel()
                except Exception:
                    pass
                print(f"   {i:2d} {u.op.name:<9} {str(u.dtype):<22} {str(u.addrspace):<18} nmn={n}")
        sys.exit(0)
    sys.exit(main())