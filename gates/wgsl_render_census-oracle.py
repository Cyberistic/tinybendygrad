#!/usr/bin/env python3
"""wgsl_render_census-oracle.py -- CPython's ANSWERS for the 207 rows
`tinybendygrad/renderer/wgsl.bend` prints from its own `main()`.

    .venv/bin/python gates/wgsl_render_census-oracle.py

WHAT THIS LANE IS, AND WHAT IT IS NOT.

`gates/*_graph_census*` compare an OP SEQUENCE. `gates/fold_graph_census*`
compares a VALUE. `gates/cstyle_render_census*` compares a rendered STRING for a
C renderer whose methods are reached through eight ported functions.
`gates/amd_dsl_census*` compares a TRIPLE -- `(packed word, byte image, text)` --
because that is what an expression algebra returns.

`wgsl.py` RETURNS SOMETHING ELSE AGAIN, and the printed form below is designed
from what it returns rather than borrowed from either of those. MEASURED, the
return surface of the 122-line file is heterogeneous:

    `sign_extend`   a UOp                       -- the graph half, the WALL
    `packed_field`  `(UOp, UOp, int)`           -- a TRIPLE, third element an int
    `packed_store`  a UOp                       -- the graph half, the WALL
    `packed_load`   a UOp                       -- the graph half, the WALL
    `is_packed`     `bool`
    `_packed_size`  `int`
    `is_nan`        `bool` over five INTEGERS buried in its own graph
    `packed_rmw`    a `UPat`                    -- a PREDICATE
    `wgsl_matcher`  seven `(UPat, fn)` pairs     -- seven GUARDS, seven rewrites
    `global_max` / `local_max`      `(int,int,int)`
    `barrier` / `nan`               `str`
    `supports_float4`               `bool`
    `code_for_workitem`             `dict[str, str]`
    `code_for_op`                   `dict[Op, str]`
    `type_map`                      `dict[DType, str]`
    `string_rewrite`                SEVENTEEN rules, each a `str` (and each a
                                    `None` when it does not apply)
    `render_cast` / `_render_dtype` / `render_dtype` / `render_load` / `buf_map`
    `render_kernel`                 the WHOLE WGSL MODULE, ~700 characters
    `supported_dtypes`              `set[DType]`

THE PRINTED FORM, AND WHY IT IS THIS FORM. One uniform line per row:

    name=value

where `value` is the WHOLE answer in that answer's own canonical text, with a
module's newlines spelled `\\n` (the port's `one_line`). Four decisions, each
forced by something measured:

  1. THE WHOLE STRING, NEVER A PREFIX, NEVER A LENGTH, NEVER A HASH. `ops.bend`'s
     `Rng.sig` prints a 3-op prefix and no arg and a deep node swap printed
     identically on both sides until a deeper printer was used (`gr_10`). For a
     renderer the same trap is a `render_kernel` row that prints only its first
     line, or its length: a dropped `@group(0) @binding(1)` separator is
     invisible in a length and identical in a prefix. `rk mixed` is 700
     characters on ONE line and the line carries all of them.

  2. THE TYPE IS THE CONTENT, AND IS NOT DECLARED. A reader who wants to know
     whether `nan_bs float` is an int and `rk alu` is a string can read the
     value. A separate kind column would be this file asserting the PORT's
     types, which is exactly the "oracle that reimplements the thing it checks"
     failure wearing a hat.

  3. A REFUSAL IS LOUD AND IS NAMED: `REFUSE:KeyError`, `REFUSE:IndexError`,
     `GRAPH:<the node CPython built>`. An oracle that answered `0` for a value
     CPython refuses would AGREE with a port that answers `0` for one. WGSL's
     `type_map` really does raise `KeyError` on `double`; `nan_mask double`
     really is 2^63-1 where a U32 holds 2^32-1; `packed_store`'s `wmask` really
     is a graph. All three are measurements, not crashes.

  4. A GRAPH IS NOT SILENTLY FOLDED. Where CPython returns a `UOp` and the port
     returns an `int` -- `packed_store`'s `wmask` is the whole of it -- the row
     prints CPython's OWN NODE, read back off the node CPython built, with the
     CONST arguments it wrote. That is a read of the answer, not a
     reimplementation of it, and it pins two real CPython integers per row.

THE RULE THAT SHAPED EVERY CALL BELOW: WHEREVER CPYTHON HAS A CALL, CALL IT.
The post-mortems are `gates/tn_bitwise_not-oracle.py` (seven rows, because an
oracle hand-built `cast.ne(True)` instead of calling `Tensor.bitwise_not()`) and
this file's two predecessors. So:

  * `type_map`, `barrier`, `nan`, `supports_float4`, `global_max`, `local_max`
    are read off `WGSLRenderer` ITSELF (`grep -c 'WGSLRenderer.type_map' == 0`
    here).
  * `render_cast`, `_render_dtype`, `render_dtype`, `render_load`, `buf_map`,
    `is_packed`, `_packed_size`, `render_kernel`, `supported_dtypes` are CALLED
    on a real `WGSLRenderer` instance with real `UOp`s built by `UOp`,
    `ParamArg`, `UOp.store` and `UOp.special`.
  * `pf_mask` is `packed_field(...)[2]` -- CPython's OWN third tuple element.
    `pf_elems` and `pf_width` are the two `CONST` arguments CPython wrote
    INSIDE the `shift_am` node it returned, read off that node with the graph
    shape asserted (`_shift_consts`).
  * `nan_mask` / `nan_thr` / `nan_uint` are read off `is_nan(a)`'s OWN returned
    `CMPLT(CONST(thr), AND(BITCAST(a, uint{bs}), CONST(mask)))`; `nan_e` /
    `nan_m` come from `dtypes.finfo`, which is the table `is_nan` itself calls.
  * `wmask` is read off `packed_store(s)`'s own `CAST(u32, XOR(SHL(...), ...))`.
  * the 35 `string_rewrite` rows go through
    `PatternMatcher([WGSLRenderer.string_rewrite.patterns[i]]).rewrite(u, ctx=r)`
    -- CPython's own dispatcher over CPython's own `UPat` with CPython's own
    lambda, one rule at a time. The FIXTURE (which node, and what `ctx` holds
    for its children) is the only thing chosen here, and the `atomicAnd`/
    `atomicAdd` rows are `packed_store`'s OWN returned node.

THE POPULATION IS DECLARED HERE AND THE GATE CHECKS THE TWO SIDES AGREE.
`wgsl_render_census-gate.py`'s `names_hold()` runs THIS file and runs
`wgsl.bend`, and asserts the two row-name lists are EQUAL AND IN THE SAME ORDER,
so a row present on one side only is red BEFORE any value is compared.
`fixtures_hold()` goes further: it re-reads the port's own fixture AXES out of
`wgsl.bend`'s source text (`r_pk8("uchar", S.uint8(), ...)`, `r_wm(255, 0, ...)`,
`r_cfo1(O.OpsSQRT{})`, `r_cu1("-1", 4294967295, 4294967295, ...)`,
`r_sb1("global", "data0_16", S.uint8(), S.AGlobal{}, 16, ...)`, ...) and
compares them to the axes below, name for name and in order -- so the axes
cannot drift on one side only. MEASURED, and that is not theoretical:
`gates/wgsl_render_census-mutate.py`'s P8 drifts `SR_CI` on THIS side alone and
moves ZERO rows; only the axis check catches it.
`rules_hold()` goes further still: it re-derives `string_rewrite`'s length,
that its tail IS `base_rewrite`'s own patterns, and each rule's op, from
CPython, on every run.

WHERE AN AXIS COULD NOT BE DISCOVERED, IT IS ADMITTED, and every admitted axis
says so:

    PF_DTS      the six dtypes `r_pf3` probes. ADMITTED: `elems`/`width` are
                local variables of `packed_field`, not attributes and not a
                tuple element, so no CPython call RETURNS them; what CPython
                returns is the graph they appear in.
    PK_DTS      the eight dtypes `r_pk8` probes. ADMITTED: `is_packed` and
                `buf_map` take a UOp, so the dtype axis is a choice about what
                to build, not a fact about `wgsl.py`.
    WMASK_AXIS  (mask, shift) pairs. ADMITTED: CPython's `shift_am` is SYMBOLIC,
                so the shift axis has no CPython counterpart at all.
    PS_AXIS     (name, dtype, addrspace, numel). ADMITTED, same reason.
    CFO_ARMS    the 25 ops `r_cfo1` probes. `axes_hold()` asserts that exactly
                ONE of them -- `Ops.FDIV` -- is absent from
                `WGSLRenderer.code_for_op`, which is why 24 of these rows have a
                CPython answer and one is `REFUSE:KeyError` for BOTH sides'
                reasons stated in the pins file.
    ARCHES      the two `r_sd1` arch strings. ADMITTED: `Target(arch=...)` is a
                choice about what to ask `supported_dtypes`.
    SR_CU/SR_CI `(name, hi, lo)` triples for `string_rewrite`'s two CONST rules.
                ADMITTED: a weakint CONST's value is an ARBITRAGE-PRECISION
                Python int, so "which values" is a choice; and the `hi:lo` pair
                is how `fixtures_hold` reads that choice out of `wgsl.bend`'s
                text without running anything.
    SR_BUF      `(name, buffer text, dtype, addrspace, numel)` for rule 5. The
                buffer NAMES are the port's own fixture (`data0_16`, `t0`) and
                the third is beside them; ADMITTED for the same reason
                `PK_DTS` is.
    THE `ctx` LETTERS ("S", "I", "B", "V", "G", "W", "NV", "X"). ADMITTED, and
                the admission is the whole comparison's weakest joint: `ctx[x]`
                is `self.r[key]`, the naming pass's dict, so a census cannot
                invent a kernel's variable names. What IS compared is each
                rule's SPELLING around a child, and the letters are the same on
                both sides because the port's parameter IS the letter.

`CFO_ARMS`, `PF_DTS`, `PK_DTS`, `WMASK_AXIS`, `PS_AXIS` and `ARCHES` are spelled
with the PORT'S OWN SPELLINGS (the `S.uint8()` constructor and the `"uchar"`
label), because `fixtures_hold()` compares them against that text and a
translation in the middle would be a second thing to keep right.

ONE MORE THING MEASURED BEFORE WRITING ANY OF IT, because it decided the whole
shape of the `ssimp` story and is reported rather than papered over:

    $ .venv/bin/python -c 'from tinygrad.uop.ops import UOp; from tinygrad import dtypes; \
        print(UOp.const(8).dtype, UOp.const(8).cast(dtypes.weakint) is UOp.const(8))'
    dtypes.weakint False        # two DIFFERENT consts; the identity is what matters
    ... UOp.const(8).cast(dtypes.weakint) is that SAME const -> True

`mixin/dtype.py:36` is `return self if self.dtype == to_dtype(dtype) else ...`,
so `UOp.cast` FOLDS when the dtypes agree, and a `CAST(weakint, CONST)` is
UNBUILDABLE: the only CONST is `weakint`, and casting a weakint CONST to weakint
returns the CONST. `wgsl.bend:838` builds exactly that node, and it is the ONE
`OpsCAST` site in the file that MINTS (the other two, `:334` and `:575`, are
pattern TESTS). The gate's `never_folding_cast_hold()` re-measures this on
every run so the statement cannot rot.
"""

import sys

sys.path.insert(0, __file__.rsplit("/gates/", 1)[0])

from tinygrad.dtype import AddrSpace, dtypes
from tinygrad.helpers import Target
from tinygrad.renderer.cstyle import base_rewrite
from tinygrad.renderer.wgsl import (WGSLRenderer, is_packed, packed_field,
                                    packed_store, is_nan, _packed_size)
from tinygrad.uop.ops import Ops, ParamArg, PatternMatcher, UOp

# ===========================================================================
# THE ROW PRINTERS. Each is the PORT's own renderer, written out, so a byte
# comparison compares ANSWERS rather than printers.
# ===========================================================================
def one_line(s: str) -> str:
    """`wgsl.bend:832`'s `one_line`: a module's newlines SPELLED `\\n`."""
    return s.replace("\n", "\\n")


def b(x) -> str:
    """`str(True)` is `"True"` -- `wgsl.bend:823`'s `bs`."""
    return "True" if x else "False"


ROWS = []


def row(name, value):
    """One row. `str(value)` is what makes a Bool, an int and a str share a
    line, and it is CPython's own `str`, not a re-writer."""
    ROWS.append(f"{name}={value if isinstance(value, str) else str(value)}")


def refuse(fn, *a, **kw):
    """`fn(*a)`, or `REFUSE:<ExceptionClassName>` when CPython refused.

    A REFUSAL IS A MEASUREMENT. `type_map[dtypes.double]` really does raise
    `KeyError` in `WGSLRenderer` -- `self.type_map[u.dtype]` with a `.get`
    default does not exist here -- and `'xyz'[int(x)]` really does raise
    `IndexError` at `x == 3`. Both are answers, and both are recorded as
    answers rather than crashing the lane.
    """
    try:
        return fn(*a, **kw)
    except Exception as e:                                        # noqa: BLE001
        return f"REFUSE:{type(e).__name__}"


def between(out, first, last, drop_first=False):
    """`out.split("\\n")[a:z]` -- the PORT's `Part.rest` / `Part.work` split,
    read off CPython's OWN rendered module.

    `first` and `last` are LINE PREDICATES, so this is a projection of what
    `render_kernel` returned and not a second rendering of it. `drop_first` is
    the SIGNATURE line: `render_kernel`'s `rk_sig` ends in `{\\n`, so the body
    starts on the NEXT line, while a binding line is the first line of its own
    block. A missing marker is `REFUSE:no marker`, never an empty string,
    because the empty string is what a broken extraction and a genuinely empty
    body both print.
    """
    lines = out.split("\n")
    a = next((i for i, ln in enumerate(lines) if first(ln)), None)
    z = next((i for i, ln in enumerate(lines) if last(ln)), None)
    if a is not None and drop_first:
        a += 1
    if a is None or z is None or z < a:
        return f"REFUSE:no marker (start={a}, end={z})"
    return "\n".join(lines[a:z])


# ===========================================================================
# THE AXES -- declared here and re-checked against `wgsl.bend`'s own text by
# `fixtures_hold()`. `(bend ctor, port label)` so both sides name a dtype the
# way the PORT does.
# ===========================================================================
DT = {"void": dtypes.void, "boolean": dtypes.bool, "int8": dtypes.char,
      "uint8": dtypes.uchar, "int16": dtypes.short, "uint16": dtypes.ushort,
      "int32": dtypes.int32, "uint32": dtypes.uint32, "half": dtypes.half,
      "bfloat16": dtypes.bfloat16, "single": dtypes.float, "double": dtypes.double}
CTOR = {id(v): k for k, v in DT.items()}
# BOTH SPELLINGS: `AGlobal` is the port's `S.AGlobal{}` CONSTRUCTOR (which
# `PS_AXIS` and `fixtures_hold()` speak) and `GLOBAL` is the port's ROW LABEL
# (which `r_pk8` prints). One table, two keys, no translation to keep right.
ADDRS = {"AGlobal": AddrSpace.GLOBAL, "ALocal": AddrSpace.LOCAL,
         "AReg": AddrSpace.REG, "ALU": AddrSpace.ALU,
         "GLOBAL": AddrSpace.GLOBAL, "LOCAL": AddrSpace.LOCAL,
         "REG": AddrSpace.REG}

# `r_pf3("uchar", S.uint8(), ...)`. ADMITTED -- see the module docstring.
PF_DTS = [("uchar", "uint8"), ("char", "int8"), ("ushort", "uint16"),
          ("short", "int16"), ("half", "half"), ("int32", "int32")]
# `r_pk8("uchar", S.uint8(), ...)`. ADMITTED.
PK_DTS = [("uchar", "uint8"), ("char", "int8"), ("ushort", "uint16"),
          ("short", "int16"), ("bool", "boolean"), ("half", "half"),
          ("float", "single"), ("int32", "int32")]
# `r_wm(255, 0, ...)`. ADMITTED -- CPython's `shift_am` is symbolic.
WMASK_AXIS = [(255, 0), (255, 8), (255, 16), (255, 24), (65535, 0), (65535, 16)]
# `r_ps("uchar 16", S.uint8(), S.AGlobal{}, 16, ...)`. ADMITTED.
PS_AXIS = [("uchar 16", "uint8", "AGlobal", 16), ("uchar 17", "uint8", "AGlobal", 17),
           ("ushort 16", "uint16", "AGlobal", 16), ("ushort 17", "uint16", "AGlobal", 17),
           ("half 16", "half", "AGlobal", 16), ("half 17", "half", "AGlobal", 17),
           ("float 16", "single", "AGlobal", 16), ("int32 16", "int32", "AGlobal", 16),
           ("uchar 16 REG", "uint8", "AReg", 16)]
# `r_cfo1(O.OpsSQRT{}, ...)` -- 22 arms in cstyle.py's order plus three probes.
# `axes_hold()` asserts that exactly one of the 25 is NOT in
# `WGSLRenderer.code_for_op`, and that it is `Ops.FDIV`.
CFO_ARMS = ["SQRT", "RECIPROCAL", "NEG", "EXP2", "LOG2", "SIN", "TRUNC", "AND",
            "XOR", "OR", "ADD", "SUB", "MUL", "CMOD", "CDIV", "FDIV", "CMPNE",
            "SHR", "SHL", "CMPLT", "CMPEQ", "WHERE", "LOAD", "MAX", "POW"]
# The last three are probed ONLY for the KeyError totalization -- `LOAD` is
# chosen because it has no arm and is an op a reader would expect to be absent,
# `MAX` and `POW` beside it -- so `axes_hold()` subtracts them and the claim it
# re-derives is about the TWENTY-TWO arms the port actually renders.
CFO_PROBES = ("LOAD", "MAX", "POW")
# `r_sd1("", ...)` and `r_sd1("shader-f16", ...)`. ADMITTED.
ARCHES = ["", "shader-f16"]
# `r_nan5("float", S.single(), ...)` / `r_nan_uint`.
NAN_DTS = [("float", "single"), ("half", "half"), ("bfloat16", "bfloat16"),
           ("double", "double")]
NANU_DTS = [("float", "single"), ("half", "half"), ("double", "double")]
# `r_rc1("uchar", S.uint8(), ...)`.
RC_DTS = [("uchar", "uint8"), ("ushort", "uint16"), ("char", "int8"),
          ("short", "int16"), ("int32", "int32"), ("uint32", "uint32"),
          ("float", "single"), ("half", "half")]

OPS = {o.name: o for o in Ops}


def R(target_arch=""):
    """A `WGSLRenderer` the way `CStyleLanguage`'s own methods read one: the
    class attributes plus `self.target`, and nothing else. `object.__new__`
    because `CStyleLanguage.__init__` wants a device this census must not
    open -- and because reading a class attribute off the CLASS is what
    `WGSLRenderer.type_map[...]` already does without an instance."""
    r = object.__new__(WGSLRenderer)
    r.target = Target(arch=target_arch)
    r.r = {}
    return r


def buf_of(dt, addr, numel):
    """A real buffer `UOp`: `UOp(Ops.BUFFER, arg=ParamArg(...))`. `max_numel` of
    that node is `size` and `buf_uop` of it is itself, which is what
    `is_packed`, `buf_map` and `_packed_size` read."""
    return UOp(Ops.BUFFER, arg=ParamArg(0, DT[dt], size=numel, addrspace=ADDRS[addr]))


# ===========================================================================
# GROUP T -- `type_map`. THE CLASS'S OWN DICT, READ BY ITS OWN KEY.
# ===========================================================================
def g_type_map():
    for nm, ctor in [("float", "single"), ("uchar", "uint8"), ("ushort", "uint16"),
                     ("short", "int16"), ("char", "int8"), ("int32", "int32"),
                     ("uint32", "uint32"), ("bool", "boolean"), ("half", "half")]:
        row(f"type_map {nm}", refuse(lambda: WGSLRenderer.type_map[DT[ctor]]))
    # `wgsl.py:62`'s dict has NINE entries and `render_cast`/`buf_map` index it
    # with `[]`, so `dtypes.double` RAISES. The port's `case _:` arm answers "".
    row("type_map double", refuse(lambda: WGSLRenderer.type_map[dtypes.double]))


def g_render_cast():
    for nm, ctor in RC_DTS:
        # A CAST node whose dtype is the one under test -- the shape a real
        # renderer's `render_cast(u, val)` is called with, since a real CAST
        # never has its own dtype as its src's.
        u = UOp(Ops.CAST, src=(UOp.const(1),), arg=DT[ctor])
        row(f"render_cast {nm}", refuse(lambda: R().render_cast(u, "V")))


# ===========================================================================
# GROUP C -- THE CLASS CONSTANTS.
# ===========================================================================
def g_consts():
    row("barrier", WGSLRenderer.barrier)
    row("nan", WGSLRenderer.nan)
    row("supports_float4", b(WGSLRenderer.supports_float4))
    row("global_max", ",".join(str(x) for x in WGSLRenderer.global_max))
    row("local_max", ",".join(str(x) for x in WGSLRenderer.local_max))


# ===========================================================================
# GROUP P -- `packed_field`'s THREE INTEGERS, read off CPython's OWN returned
# triple and the CONSTs CPython wrote inside its `shift_am` node.
# ===========================================================================
def _packed_fixture(ctor):
    """A `packed_field` fixture whose `shift_am` SURVIVES as a graph.

    A CONSTANT index folds the whole of `wgsl.py:12` into constants and there
    is then nothing left to read `elems` and `width` off -- which is why the
    fixture's index is a `RANGE`. `is_packed` reads `src[1].dtype`, so the
    store's VALUE must be a narrow dtype too, not a weakint CONST.
    """
    buf = buf_of(ctor, "AGlobal", 64)
    sym = UOp(Ops.RANGE, src=(UOp.const(16),), arg=(0, 1, __import__(
        "tinygrad.uop.ops", fromlist=["AxisType"]).AxisType.LOCAL))
    return UOp(Ops.INDEX, src=(buf, sym))


def _shift_consts(shift, hi_lo):
    """`(elems, width)` off `shift = MUL(FLOORMOD(CAST(i,u32), CONST(elems)),
    CONST(width))` -- the node `wgsl.py:12` BUILDS.

    `hi_lo` names the two slots so a shape change reports WHICH one moved
    instead of raising an IndexError somewhere further away. It is the only
    place this file walks a graph, and it walks the graph CPython RETURNED.
    """
    if len(hi_lo) != 2:
        return (f"REFUSE:shift is {shift.op.name}, expected MUL", 0)
    m = shift.src[0]
    if len(m.src) != 2 or m.src[1].arg is None:
        return (f"REFUSE:{m.op.name} has no CONST divisor", 0)
    return (m.src[1].arg, shift.src[1].arg)


def g_packed_field():
    for nm, ctor in PF_DTS:
        _, shift, mask = packed_field(_packed_fixture(ctor), DT[ctor])
        elems, width = _shift_consts(shift, (0, 1))
        # THE CONTROL THAT MAKES THE OTHER TWO ROWS MEAN ANYTHING. `pf_elems`
        # and `pf_width` are read off the CONSTs CPython WROTE, and a reader
        # cannot tell a correct read from a lucky one by looking at two integers
        # -- so the lane ASSERTS CPython's own mask against the expression it
        # was read with. A wrong node or a wrong slot fails HERE, loudly, rather
        # than printing two confident integers. It is an `assert` and not a row
        # because its answer is always True on a correct read and the pins file
        # has no business holding a row that cannot differ.
        assert mask == (1 << width) - 1, (nm, mask, width)
        row(f"pf_elems {nm}", elems)
        row(f"pf_width {nm}", width)
        row(f"pf_mask {nm}", mask)


def g_wmask():
    """`packed_store`'s `wmask` -- a GRAPH in CPython, an INT in the port.

    MEASURED: `wgsl.py:18` is `((mask << shift_am) ^ 0xFFFFFFFF).cast(u32)`, and
    `shift_am` is `bidx.src[1] // elems % elems * width` -- SYMBOLIC for any
    index the compiler does not know. So CPython has NO integer answer for a
    chosen shift, and a lane that printed one would be reimplementing
    `packed_store` to produce it. What IS CPython's answer is the node, so the
    row prints the two CONST arguments CPython WROTE and says the rest is a
    node. That pins `0xFFFFFFFF` and the `mask` on CPython's authority.
    """
    for mask, shift in WMASK_AXIS:
        ctor = "uint8" if mask == 255 else "uint16"
        st = _packed_fixture(ctor).store(UOp.const(7, DT[ctor]))
        got = packed_store(st)
        # got.src[1] = OR(AND(LOAD, wmask), new_v); wmask = CAST(u32, XOR(SHL(mask, sh), CONST(0xFFFFFFFF)))
        wm = got.src[1].src[0].src[1]
        x = wm.src[0] if wm.op is Ops.CAST else wm
        if x.op is not Ops.XOR or len(x.src) != 2:
            row(f"wmask {mask}_{shift}", f"REFUSE:wmask is {x.op.name}, expected XOR")
        elif x.src[1].arg is None or x.src[0].src[0].arg is None:
            row(f"wmask {mask}_{shift}",
                f"REFUSE:{x.src[0].src[0].arg!r}<<symbolic^{x.src[1].arg}")
        else:
            row(f"wmask {mask}_{shift}",
                f"GRAPH:{x.src[0].src[0].arg}<<{shift}^{x.src[1].arg}")


# ===========================================================================
# GROUP N -- `is_nan`'s FIVE INTEGERS AND ITS uint{bs}, read off CPython's OWN
# returned graph. `wgsl.py:36` returns `(...) > thr`, and `>` is CMPLT with the
# operands swapped, so the answer is `CMPLT(CONST(thr), AND(BITCAST, CONST(mask)))`.
# ===========================================================================
def _is_nan_parts(a):
    r = is_nan(a)
    if r.op is not Ops.CMPLT or len(r.src) != 2:
        return (f"REFUSE:is_nan is {r.op.name}", 0, 0, "")
    masked = r.src[1]
    if masked.op is not Ops.AND or len(masked.src) != 2:
        return (f"REFUSE:is_nan lhs is {masked.op.name}", 0, 0, "")
    bitcast = masked.src[0]
    return (r.src[0].arg, masked.src[1].arg,
            bitcast.src[0].dtype, bitcast.dtype)


def g_is_nan():
    for nm, ctor in NAN_DTS:
        thr, mask, src_dt, _ = _is_nan_parts(UOp.const(1, DT[ctor]))
        # `dtypes.finfo` IS the table `is_nan` itself calls (`wgsl.py:35`).
        exp, mant = dtypes.finfo(DT[ctor])
        row(f"nan_bs {nm}", src_dt.bitsize)
        row(f"nan_e {nm}", exp)
        row(f"nan_m {nm}", mant)
        row(f"nan_mask {nm}", mask)
        row(f"nan_thr {nm}", thr)


def g_is_nan_uint_only():
    # `nan_uint` is `getattr(dtypes, f"uint{bs}")` -- THE BITCAST'S OWN TARGET
    # dtype, which is ON THE NODE CPython RETURNED, not a table spelled here.
    for nm, ctor in NANU_DTS:
        _, _, _, cast_dt = _is_nan_parts(UOp.const(1, DT[ctor]))
        row(f"nan_uint {nm}", cast_dt.name)


# ===========================================================================
# GROUP O -- `code_for_op`. CPython's OWN dict, CPython's OWN arity.
# ===========================================================================
def g_code_for_op():
    for nm in CFO_ARMS:
        op = OPS[nm]
        arm = WGSLRenderer.code_for_op.get(op)
        if arm is None:
            row(f"code_for_op {nm}", "REFUSE:KeyError")
            continue
        # `co_argcount` is CPython TELLING us the arity, not this file
        # deciding it: `lambda a:`, `lambda a,b:`, `lambda a,b,c,dtype:`.
        row(f"code_for_op {nm}", arm(*"ABCD"[:arm.__code__.co_argcount]))


def g_workitem():
    for tag in ("g0", "g1", "g2", "l0", "l1", "l2"):
        row(f"workitem {tag}",
            refuse(WGSLRenderer.code_for_workitem[tag[0]], int(tag[1])))
    # `'xyz'[int(x)]` is an INDEX and 3 is past the end of a 3-character
    # string. The port answers "" for the whole call; CPython raises.
    row("workitem l3", refuse(WGSLRenderer.code_for_workitem["l"], 3))


def g_supported():
    for arch in ARCHES:
        row(f"supported_dtypes {arch}",
            ",".join(sorted(x.name for x in R(arch).supported_dtypes())))


def g_render_dtype():
    row("render_dtype float", refuse(lambda: R().render_dtype(dtypes.float)))
    row("_render_dtype uchar global",
        refuse(lambda: R()._render_dtype(dtypes.uint8, 1, AddrSpace.GLOBAL,
                                         True, True, (2, 3, 4))))


# ===========================================================================
# GROUP S -- `string_rewrite`, THE SEVENTEEN RULES. Every row is ONE RULE
# APPLIED TO ONE REAL `UOp`, through `PatternMatcher.rewrite` and CPython's own
# `UPat` -- the rule table is NOT reimplemented here.
#
# HOW A SINGLE RULE IS REACHED, and why that is not a reimplementation. The
# table is `WGSLRenderer.string_rewrite.patterns`, `patterns[:17]` being wgsl's
# seventeen and `patterns[17:]` being `base_rewrite`'s 33, and each row below is
# `PatternMatcher([patterns[i]]).rewrite(u, ctx=r)` -- CPython's own dispatcher
# over CPython's own pattern with CPython's own lambda. The FIXTURE (which node,
# and what `ctx` holds for its children) is the only thing chosen here, exactly
# as `CFO_ARMS` chooses an op and `RC_DTS` chooses a dtype.
#
# `ctx[x]` IS `self.r[key]` (cstyle.py:207), the naming pass's dict, so `r.r` is
# FILLED with the same one-letter text the port passes as its `String` parameter
# and the two lanes render the same substitution. Those letters are ADMITTED: a
# census cannot invent a kernel's variable names, and what is being compared is
# the rule's SPELLING around a child, not the child's own text.
#
# `None` IS SPELLED `NOMATCH` on BOTH SIDES. CPython's rule returns `None` for
# "this rule does not apply" and `PatternMatcher.rewrite` treats it as "try the
# next rule"; it is a control-flow state, not a value. `wgsl.bend` spells its own
# no-answer `NOMATCH`, and the point of naming it rather than printing `""` is
# that the empty string is the shape `type_map`'s arm used to have (FINDING 2).
# ===========================================================================
SR_RULES = WGSLRenderer.string_rewrite.patterns[:17]
SR_BASE = len(base_rewrite.patterns)

# The `ctx` letters. `S` is a bitcast/const source, `I` a rendered INDEX, `B` a
# rendered store target, `V` the alternative value, `G` the gate, `W` the wmask,
# `NV` the new value, `I0`/`I1`/`X` a plain source.
def _sr_ctx(pairs=()):
    """A `WGSLRenderer` whose `r` -- the naming pass's `self.r` dict, which is
    what `ctx[x]` reads (cstyle.py:207) -- holds `pairs`."""
    r = R()
    r.r.update(pairs)
    return r


def _wc(v):
    """A BARE CONST: `UOp.const(v)` with no dtype, and `UOp.const` folds a cast
    away at exactly bool/weakint/weakfloat (ops.py:632), so a bare CONST is
    ALWAYS weakint. That is why `c.val` in `string_rewrite`'s rules 3 and 4 is a
    weakint integer and not the target dtype's -- and why a CONST of u32 or i32
    is UNREACHABLE through `UOp.const`, which is why the rules are probed with
    `UOp(Ops.CAST, ...)` around a bare CONST (MEASURED both ways)."""
    return UOp(Ops.CONST, arg=v, src=())


def _cvar(v):
    return UOp(Ops.CAST, src=(_wc(v),), arg=dtypes.uint32)


def _cint(v):
    return UOp(Ops.CAST, src=(_wc(v),), arg=dtypes.int32)


def _i64(hi, lo):
    """The SIGNED value of the `hi:lo` pair `SR_CU`/`SR_CI` carry, which is the
    weakint CONST `c.val` the two rules read. It is derived rather than spelled
    so the axis and the fixture cannot drift apart: an axis entry is the two
    `U32` words and the node is built from those same words."""
    v = (hi << 32) | lo
    return v - (1 << 64) if hi & 0x80000000 else v


def g_string_rewrite():
    ci = UOp.const(1, dtypes.int32)
    ch = UOp.const(1, dtypes.half)
    cu = UOp.const(1, dtypes.uint32)
    alt = UOp.const(7, dtypes.uint32)
    gate = UOp.const(1, dtypes.bool)
    vf = UOp.const(5, dtypes.float)
    idx_pk = UOp(Ops.INDEX, src=(buf_of("uint8", "AGlobal", 16), _wc(1)))
    idx_pl = UOp(Ops.INDEX, src=(buf_of("single", "AGlobal", 16), _wc(1)))
    cu3 = UOp.const(3, dtypes.uint32)
    # 14 -- THE READ-MODIFY-WRITE IS CPython's OWN `packed_store` OUTPUT, so the
    # `atomicAnd`/`atomicAdd` rows are that function's answer and not a
    # hand-built approximation of it. `packed_rmw`'s `b` binder and the store's
    # `b` binder MUST BE ONE UOp: `UPat.match`'s `setdefault(self.name, uop) is
    # not uop` check rejects the store otherwise (MEASURED -- and that is why the
    # `rmw bare` row is `UOp.store(ix_n, and_n)` and not `UOp.store(idx_pk, ...)`:
    # `packed_store` rebuilds the INDEX through `bidx.src[0].index(...)`).
    rmw = packed_store(UOp.store(idx_pk, UOp.const(5, dtypes.uint8)))
    and_n = rmw.src[1].src[0]
    ix_n = and_n.src[0].src[0].src[0]
    wmask, newv = and_n.src[1], rmw.src[1].src[1]
    add = UOp(Ops.ADD, src=(_wc(1), _wc(2)), arg=Ops.ADD)
    # `(I0)+(I1)` is NOT A DIFFERENT NODE from `(I0+I1)` -- same op, same srcs,
    # same arg, and `UOp`'s interning makes them one object. So the unbalanced row
    # rides on the `ctx` SPELLING of that one node and not on a second node, and
    # `strip_parens` reads the spelling anyway (it is a `str` predicate over the
    # text, not a graph test). `index const` is a CONST index, whose `arg` is `1`
    # and so is not `Ops.ADD`, which is the rule's other branch.
    iconst = _wc(1)

    # `ctx` IS PER ROW, not one shared dict: the letters are what the row's own
    # rule reads, and sharing one dict would let a row for `INDEX` see a `B` that
    # a row for a CAST put there. Each row's bindings are exactly the nodes that
    # row's rule dereferences, which is also what makes the port's `String`
    # parameter list checkable by eye against this one.
    def r_(i, name, u, pairs=()):
        row(f"sr {name}", _sr_rewrite(i, u, _sr_ctx(pairs)))

    r_(0, "idx packed", UOp(Ops.CAST, src=(idx_pk,), arg=dtypes.uint32), {idx_pk: "B[1]"})
    r_(0, "idx plain", UOp(Ops.CAST, src=(idx_pl,), arg=dtypes.uint32), {idx_pl: "B[1]"})
    r_(1, "neg", UOp(Ops.NEG, src=(cu3,)), {cu3: "X"})
    r_(2, "cbool 1", UOp.cconst(1, dtypes.bool))
    r_(2, "cbool 0", UOp.cconst(0, dtypes.bool))
    for nm, hi, lo in SR_CU:
        r_(3, f"cuchar {nm}", _cvar(_i64(hi, lo)))
    for nm, hi, lo in SR_CI:
        r_(4, f"ci32 {nm}", _cint(_i64(hi, lo)))
    # ONE node per axis entry, bound under the SAME object the rule is given --
    # `self.r[key]` is a dict keyed by the UOp, so building the buffer twice would
    # answer `REFUSE:KeyError` for a rule that is fine.
    for nm, bn, ctor, a, k in SR_BUF:
        u = buf_of(ctor, a, k)
        row(f"sr buffer {nm}", _sr_rewrite(5, u, _sr_ctx({u: bn})))
    r_(6, "bhalf", UOp(Ops.BITCAST, src=(cu,), arg=dtypes.half), {cu: "S"})
    r_(7, "buchar", UOp(Ops.BITCAST, src=(ci,), arg=dtypes.uint8), {ci: "S"})
    r_(8, "bchar", UOp(Ops.BITCAST, src=(ci,), arg=dtypes.char), {ci: "S"})
    r_(9, "bushort", UOp(Ops.BITCAST, src=(ci,), arg=dtypes.uint16), {ci: "S"})
    r_(9, "bushort half", UOp(Ops.BITCAST, src=(ch,), arg=dtypes.uint16), {ch: "S"})
    r_(10, "bshort", UOp(Ops.BITCAST, src=(ci,), arg=dtypes.short), {ci: "S"})
    r_(10, "bshort half", UOp(Ops.BITCAST, src=(ch,), arg=dtypes.short), {ch: "S"})
    r_(11, "bany", UOp(Ops.BITCAST, src=(ch,), arg=dtypes.float), {ch: "S"})
    r_(12, "lgate packed", UOp(Ops.LOAD, src=(idx_pk, alt, gate)),
       {idx_pk: "B[1]", alt: "V", gate: "G"})
    r_(12, "lgate plain", UOp(Ops.LOAD, src=(idx_pl, alt, gate)),
       {idx_pl: "B[1]", alt: "V", gate: "G"})
    r_(13, "load packed", UOp(Ops.LOAD, src=(idx_pk,)), {idx_pk: "B[1]"})
    r_(13, "load plain", UOp(Ops.LOAD, src=(idx_pl,)), {idx_pl: "B[1]"})
    # 14 -- THREE arms, because the rule has three: with `new_v`, without it
    # (`new_v` is gone when it is 0, per wgsl.py:87), and with `is_packed` False,
    # where the rule answers `None` and the STORE falls to rule 15 instead.
    r_(14, "rmw nv", rmw, {ix_n: "B[1]", wmask: "W", newv: "NV"})
    r_(14, "rmw bare", UOp.store(ix_n, and_n), {ix_n: "B[1]", wmask: "W"})
    r_(14, "rmw plain", UOp.store(idx_pl, vf), {idx_pl: "B", vf: "V"})
    r_(15, "store", UOp.store(idx_pl, vf), {idx_pl: "B", vf: "V"})
    r_(16, "index add", UOp(Ops.INDEX, src=(idx_pl, add)), {idx_pl: "B", add: "(I0+I1)"})
    r_(16, "index const", UOp(Ops.INDEX, src=(idx_pl, iconst)), {idx_pl: "B", iconst: "I0"})
    r_(16, "index unbalanced", UOp(Ops.INDEX, src=(idx_pl, add)),
       {idx_pl: "B", add: "(I0)+(I1)"})


def _sr_rewrite(i, u, ctx):
    """`WGSLRenderer.string_rewrite`'s rule `i` applied to `u`, through CPython's
    own `PatternMatcher.rewrite`, with `None` spelled `NOMATCH`."""
    v = PatternMatcher([SR_RULES[i]]).rewrite(u, ctx=ctx)
    return "NOMATCH" if v is None else one_line(v)


def _sr_rejects(i, u):
    """THE PORT'S SIDE CANNOT CALL THIS. CPython's matcher says whether a rule's
    `UPat` accepts a node, so the NEGATIVE half of every rule is ASKED here and
    the answer is the row. The port has no `UPat` -- `wgsl.bend` carries the
    rule BODIES -- so a `srneg` row cannot be a refusal on that side, and
    `SRNEG_BODY` is what the port prints instead."""
    return len(SR_RULES[i][0].match(u, {})) == 0


def g_srneg():
    """SEVENTEEN REFUSALS, ONE PER RULE. The thirty-five `sr *` rows above are
    SPELLINGS ON CHOSEN FIXTURES: the two sides print the same string, which says
    the two BODIES agree and says nothing about whether either rule FIRES. These
    rows ask the other half -- a node each `UPat` REJECTS -- so a rule's body
    firing where CPython's pattern cannot is a reading rather than an absence.

    Every one of the seventeen is a REFUSAL BY CONSTRUCTION: `sr_` asserts the
    rejection with CPython's own `UPat.match`, so if a re-vendor widens a pattern
    the ASSERTION fails at the source and the row never silently becomes a
    positive one. The assertion is here rather than in the gate because the gate
    cannot reach `UPat` and a row whose meaning depends on an unasserted premise
    is a spelling again."""
    from tinygrad import dtypes
    from tinygrad.uop.ops import Ops, UOp
    cu3 = UOp.const(3, dtypes.uint32)
    ci = UOp.const(1, dtypes.int32)
    idx_pk = UOp(Ops.INDEX, src=(buf_of("uint8", "AGlobal", 16), _wc(1)))
    r = [
        # 0 `CAST` to `uint32` -- the same shape the positive row uses, at
        # `int32`. One dtype away, and the rule does not fire.
        (0, "cast i32", UOp(Ops.CAST, src=(idx_pk,), arg=dtypes.int32), {}),
        # 1 `NEG` of an UNSIGNED -- a float constant instead. `dtypes.uints` is
        # the rule's only dtype condition and there is nothing else to reject on.
        (1, "neg f32", UOp(Ops.NEG, src=(UOp.const(1, dtypes.float),)), {}),
        # 2 `cvar.cast(bool)` -- `bool` is the whole of the condition.
        (2, "cast i32", UOp.cconst(1, dtypes.int32), {}),
        # 3 and 4 are the SAME node at two dtypes, and they are each the other's
        # rejection: `cast(uchar|ushort|uint32)` and `cast(int32)` are disjoint.
        (3, "cast i32", UOp(Ops.CAST, src=(cu3,), arg=dtypes.int32), {}),
        (4, "cast u32", UOp(Ops.CAST, src=(cu3,), arg=dtypes.uint32), {}),
        # 5 `BUFFER` -- a bare CONST is not one.
        (5, "const", cu3, {}),
        # 6..10 the six `bitcast<>` rules, each at a dtype another one holds.
        (6, "bitcast u32", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.uint32), {}),
        (7, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
        (8, "bitcast uchar", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.uchar), {}),
        (9, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
        (10, "bitcast half", UOp(Ops.BITCAST, src=(cu3,), arg=dtypes.half), {}),
        # 11 `UPat(Ops.BITCAST, name="x")` carries NO dtype, so it matches every
        # BITCAST in the file and the rejected node has to be a different OP.
        # That is the rule's reach and it is why this row's node is a CONST.
        (11, "const", cu3, {}),
        # 12 `UPat.load(b, v, gate)` wants THREE srcs; a two-src LOAD is rule
        # 13's shape and is the node the two rules divide on.
        (12, "load 2", UOp(Ops.LOAD, src=(idx_pk,)), {idx_pk: "B[1]"}),
        # 13 `UPat.load(b)` -- the mirror: does a GATED load fall into it?
        (13, "load 3", UOp(Ops.LOAD, src=(idx_pk, cu3, UOp.const(1, dtypes.bool))),
         {idx_pk: "B[1]", cu3: "V"}),
        # 14 `UPat.any(packed_rmw, packed_rmw|nv)` -- a packed store whose value
        # is an ordinary CONST is not a read-modify-write, and this is the
        # `packed_rmw` gap the port's own header names.
        (14, "store u8", UOp.store(idx_pk, UOp.const(5, dtypes.uint8)),
         {idx_pk: "B[1]"}),
        # 15 `UPat.store(b, v)` wants TWO srcs; a GATED store is three.
        (15, "store 3", UOp.store(idx_pk, cu3, UOp.const(1, dtypes.bool)),
         {idx_pk: "B", cu3: "V"}),
        # 16 `UPat(Ops.INDEX, src=(var, var))` matches every INDEX of arity 2, so
        # the rejected node is a different OP here too.
        (16, "const", cu3, {}),
    ]
    for i, nm, u, ctx in r:
        assert _sr_rejects(i, u), (
            f"srneg rule {i} fixture {nm!r}: CPython's pattern now ACCEPTS it, so "
            f"the row is no longer a refusal -- pick another node or retire it")
        # THE RULE INDEX IS IN THE ROW NAME because several of these fixtures are
        # the same node at different rules' dtypes -- `cast i32` is rules 0, 2 and
        # 3 -- and a pins file keyed by row NAME would collapse three refusals
        # into one. A negative row that cannot be named individually is not a row.
        row(f"srneg {i} {nm}", _sr_rewrite(i, u, ctx))


# `r_cu1(...)` / `r_ci1(...)` -- rules 3 and 4's axis, as `(name, hi, lo)`. These
# are the I64 the PORT is handed: `hi` and `lo` are the two `U32` words of a
# weakint CONST's value, and the axis is declared in those words because that is
# how `fixtures_hold` can read it out of `wgsl.bend` without running anything.
SR_CU = [("255", 0, 255), ("-1", 4294967295, 4294967295), ("4294967295", 0, 4294967295),
         ("4294967296", 1, 0)]
SR_CI = [("7", 0, 7), ("-3", 4294967295, 4294967293), ("4294967295", 0, 4294967295),
         ("4294967296", 1, 0)]
# `4294967296` IS THE CASE THAT EARLIER MISSED, and it was found by a MUTATION
# rather than by reading: `sr_cuint.masked` -- the `& 0xFFFFFFFF` -- is only
# observable on a weakint CONST whose HIGH WORD is set and whose LOW WORD reads
# as non-negative. All three rows above have `hi == 0`, so dropping the mask
# entirely (`masked(v) = v`) left every one of them unchanged and the gate was
# GREEN on a mutation. `wgsl_render_census-mutate.py`'s M51 is that mutation and
# it is why this fourth row exists. `2**32 & 0xFFFFFFFF` is `0u` and
# `truncate[int32](2**32)` is `0`, so both new rows read `0`.
# `r_sb1("global", "data0_16", S.uint8(), S.AGlobal{}, 16, ...)` -- rule 5's
# `(name, buffer text, dtype, addrspace, numel)`. `data0_16` and `t0` are the
# port's own fixture buffer names and `r0` is beside them.
SR_BUF = [("global", "data0_16", "uint8", "AGlobal", 16), ("local", "t0", "single", "ALocal", 1),
          ("reg", "r0", "single", "AReg", 1)]


# ===========================================================================
# GROUP P2 -- `is_packed` / `buf_map` / `_packed_size`, on REAL buffer UOps.
# ===========================================================================
def g_packed():
    for nm, ctor in PK_DTS:
        for a in ("GLOBAL", "LOCAL", "REG"):
            u = buf_of(ctor, a, 16)
            row(f"is_packed {nm} {a}", b(is_packed(u)))
            row(f"buf_map {nm} {a}", refuse(lambda: R().buf_map(u)))


def g_packed_size():
    for nm, ctor, a, n in PS_AXIS:
        row(f"packed_size {nm}", _packed_size(buf_of(ctor, a, n)))


# ===========================================================================
# GROUP K -- `render_kernel`, THE WHOLE MODULE, ON THE PORT'S OWN FIXTURES.
#
# The kernel BODY lines and the buffer NAMES are the port's fixture and are
# ADMITTED: they are what `render_kernel` renders, and a census cannot invent a
# kernel. What is NOT admitted is anything about the ANSWER: every row below is
# a call to `WGSLRenderer.render_kernel` on real `UOp`s, or a projection of that
# call's own returned string.
# ===========================================================================
KERN_ALU = ["  var val0 = data1_4[0];", "  var val1 = data1_4[1];",
            "  var val2 = data1_4[2];", "  var val3 = data1_4[3];",
            "  var val4 = data2_4[0];", "  var val5 = data2_4[1];",
            "  var val6 = data2_4[2];", "  var val7 = data2_4[3];",
            "  data0_4[0] = (val0+val4);", "  data0_4[1] = (val1+val5);",
            "  data0_4[2] = (val2+val6);", "  data0_4[3] = (val3+val7);"]
KERN_MIXED = ["  var val0 = atomicLoad(&data0_16[0]);",
              "  var<workgroup> buf0:array<atomic<u32>,4>;",
              "  data0_16[0] = (val0+1);"]
# `rk alu` and `rk empty` hand `render_kernel` an EMPTY uops list, which is what
# `Scan{[1], False{}}` IS: no SPECIAL, no half.
BUFS_ALU = [("data0_4", buf_of("single", "AGlobal", 4)),
           ("data1_4", buf_of("single", "AGlobal", 4)),
           ("data2_4", buf_of("single", "AGlobal", 4))]
BUFS_MIXED = [("data0_16", buf_of("uint8", "AGlobal", 16)),
              ("t0", buf_of("single", "ALocal", 1))]
# TWO local axes in the order l0, l1 AND in the order l1, l0 -- the second is
# what `wgsl.bend`'s own M20 blind-spot note says the fixture is missing, and
# it is the row that proves the local-size SORT is load-bearing.
UOPS_MIXED = [UOp.special(8, "l0"), UOp.special(2, "l1"), UOp.const(0, dtypes.half)]
UOPS_MIXED_SWAPPED = [UOPS_MIXED[1], UOp.special(8, "l0"), UOPS_MIXED[2]]


# `RAW` holds the modules as `render_kernel` returned them -- WITH their
# newlines. `one_line` is the PORT's printer and escapes them for the row, so a
# projection (`rk_bindings`, `rk_body`) has to read the RAW text or it is
# splitting a one-line string on a separator that is no longer there. Keeping
# both spellings is what makes "print the WHOLE string" and "read the WHOLE
# string" the same act.
RAW = {}


def rk_raw(fn, kernel, bufs, uops):
    out = R().render_kernel(fn, kernel, [(n, (u, True)) for n, u in bufs], uops)
    RAW[fn] = out
    return out


def rk(fn, kernel, bufs, uops):
    return one_line(rk_raw(fn, kernel, bufs, uops))


def _is_alu_binding(ln):
    return ln.startswith("@group(0) @binding(1)") or \
           ln.startswith("@group(0) @binding(2)") or \
           ln.startswith("@group(0) @binding(3)")


def _is_compute(ln):
    return ln.startswith("@compute @workgroup_size(")


def _is_close(ln):
    return ln == "}"


def _is_open(ln):
    return ln.startswith("@compute @workgroup_size(") and ln.endswith(") {")


def g_render_kernel():
    alu = rk("E_4", KERN_ALU, BUFS_ALU, [])
    mixed = rk("K_mixed", KERN_MIXED, BUFS_MIXED, UOPS_MIXED)
    empty = rk("K_empty", [], [], [])
    RAW["alu"], RAW["mixed"], RAW["empty"] = RAW["E_4"], RAW["K_mixed"], RAW["K_empty"]
    # `rk_sz` and `rk_half` are `render_kernel`'s two `uops` SCANS, which
    # `render_kernel` does not expose. They are read out of its OWN output:
    # `@workgroup_size(...)` IS the local_size it computed, and `enable f16;`
    # IS the `any(uop.dtype == dtypes.fhalf)` it computed. A regex that did not
    # find the marker would answer "" and pass, so every extraction here is a
    # `REFUSE:` when the marker is absent.
    def workgroup(out):
        import re
        m = re.search(r"@workgroup_size\(([^)]*)\)", out)
        return "REFUSE:no @workgroup_size" if m is None else m.group(1)
    row("rk_sz none", workgroup(empty))
    row("rk_sz mixed", workgroup(mixed))
    row("rk_half mixed", b("enable f16;" in mixed))
    row("rk_half none", b("enable f16;" in alu))
    # THE ORDER CONTROL the port's mutation table records as MISSING (M20, "the
    # local-size sort never compares" moved 0 rows). This is not a port row --
    # `wgsl.bend` has no `uops` list whose walk order differs from its sort
    # order -- so it is NOT emitted into ROWS. It is asserted here instead and
    # reported: a uops list holding l1 BEFORE l0 must still render `(2,8)`,
    # because `render_kernel` sorts by `u.arg`.
    assert workgroup(rk("K_mixed", KERN_MIXED, BUFS_MIXED,
                        UOPS_MIXED_SWAPPED)) == "8,2", "the sort is not load-bearing"
    # `rk_bindings` and `rk_body` are the port's own two-line VIEWS of the
    # block `render_kernel` built: the binding lines joined with ";", and the
    # non-`var<workgroup>` body lines joined with ";". Both are read out of the
    # module CPython returned, so the comparison is of the BLOCK and not of a
    # second rendering of it.
    row("rk_bindings", between(RAW["alu"], _is_alu_binding, _is_compute).replace("\n", ";"))
    row("rk_body", between(RAW["alu"], _is_open, _is_close,
                           drop_first=True).replace("\n", ";"))
    row("rk alu", alu)
    row("rk mixed", mixed)
    row("rk empty", empty)


def main():
    for g in (g_type_map, g_render_cast, g_consts, g_packed_field, g_wmask,
              g_is_nan, g_is_nan_uint_only, g_code_for_op, g_workitem,
              g_supported, g_render_dtype, g_packed, g_packed_size,
              g_render_kernel, g_string_rewrite, g_srneg):
        g()
    for ln in ROWS:
        print(ln)


if __name__ == "__main__":
    sys.exit(main())