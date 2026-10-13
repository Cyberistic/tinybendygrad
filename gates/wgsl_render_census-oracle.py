#!/usr/bin/env python3
"""wgsl_render_census-oracle.py -- CPython's ANSWERS for the 172 rows
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
    `string_rewrite`                sixteen rules, each a `str`
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

THE POPULATION IS DECLARED HERE AND THE GATE CHECKS THE TWO SIDES AGREE.
`wgsl_render_census-gate.py`'s `names_hold()` runs THIS file and runs
`wgsl.bend`, and asserts the two row-name lists are EQUAL AND IN THE SAME ORDER,
so a row present on one side only is red BEFORE any value is compared.
`fixtures_hold()` goes further: it re-reads the port's own fixture AXES out of
`wgsl.bend`'s source text (`r_pk8("uchar", S.uint8(), ...)`, `r_wm(255, 0, ...)`,
`r_cfo1(O.OpsSQRT{})`, ...) and compares them to the axes below, name for name
and in order -- so the axes cannot drift on one side only.

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
from tinygrad.renderer.wgsl import (WGSLRenderer, is_packed, packed_field,
                                    packed_store, is_nan, _packed_size)
from tinygrad.uop.ops import Ops, ParamArg, UOp

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
              g_render_kernel):
        g()
    for ln in ROWS:
        print(ln)


if __name__ == "__main__":
    sys.exit(main())