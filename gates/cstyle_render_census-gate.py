#!/usr/bin/env python3
"""cstyle_render_census-gate.py -- A RENDER CENSUS over `tinybendygrad/renderer/cstyle.bend`.

    .venv/bin/python gates/cstyle_render_census-gate.py

358 ROWS, THREE LANES (CPython, bend interpreted, bend compiled), 19 DECLARED DIVERGENCES.
THE THIRD KIND OF INSTRUMENT. The seven `*_graph_census` gates compare OP SEQUENCES (a graph)
and `fold_graph_census-gate.py` compares VALUES (a dtype, a shape, a pair of bounds). A RENDERER
produces NEITHER: it produces a STRING. So here the SAME UOp is built in both lanes, RENDERED,
and the two STRINGS are compared byte for byte -- the shape `render_val_s-gate.py` uses for the
signed integer printer, scaled to the whole `cstyle` surface.

THE POPULATION IS DISCOVERED, NOT LISTED. A name is a ROW iff
`tinygrad/renderer/cstyle.py` defines a method or function of that name (leading underscores
stripped) AND the port's def emits a String (or a value) from a UOp. Eight names survive
(render_dtype, render_type, render_ptr, render_access, render_cast, render_index, render_buffer,
wmma_name); the discovery command is in `cstyle_render_census.bend`'s header and in the oracle's
docstring. `render_kernel` and `uops_to_dtypes` are the two CPython entry points the port DOES
NOT define -- both the fold wall -- so they fall out, and so does every helper with no port def.

THE DISPATCH AND OPTION TABLES are CPython CLASS ATTRIBUTES, not methods, so they are not names
in the population; a renderer is mostly a dispatch table, so the census reaches them THROUGH the
eight functions and, for the ones no ported function reads, drives the port's own table def
(`opt_*`, `cfo_*`, `cfw_*`). The arms of one dispatch table are rows, not names: `cfo_<dev>_<op>`
IS the arm, driven through the one `code_for_op.of` the port has.

WHAT THE FIXTURE VARIES (all four, because `_render_dtype` reads all four): the DEVICE (six
type_maps, six prefix sets), the DTYPE (eighteen names, four UNMAPPED on some devices), the
ADDRSPACE/SIZE, and the OP/ARG.

THE NINETEEN DIVERGENCES, ALL PINNED -- eighteen are the vendored-`tinygrad`/table carve-outs and
ONE is a REAL DEFECT the census found (it is a FINDING until it has a reason, and the `ri_add_*`
one has a reason and an owner):

  `rdx_*` (6) -- THE VENDORED `tinygrad/` HAS DRIFTED PAST THE PIN. HEAD `_render_dtype` uses
    `self.type_map[dtype]` and RAISES KeyError for an unmapped dtype; the port prints the dtype's
    own name (`tm_get`'s default), which is the PIN's `.get(dtype, dtype.name)`. `git show
    'ad117c928^:tinygrad/renderer/cstyle.py'` reads `.get`, HEAD reads `[dtype]`. This is the one
    place the port is a mix: its `type_map` overlays are HEAD's (a 14-entry base), its default is
    the PIN's. REPORTED, and the port's own docstring (`cstyle.bend:487-492`) cites the PIN's
    behaviour as if it were current.
  `opt_float4_0` (1) -- CPython's base `float4` is `None`, the port answers `""`; `cstyle.bend`'s
    own comment (`:427-437`) records it (a `Data` cannot carry a `Maybe`, and the `Ops.STACK` arm
    that would read it is not ported).
  `cfo_0_fdiv` + `cfo_1_{exp2,sin,log2,reciprocal}` (5) -- a dropped/unwritten ALU op is a
    `KeyError` in CPython's `code_for_op[...]` and `""` in the port (`cstyle.bend:1045-1052`
    records the FDIV half by name).
  `cfw_{0,1}_{g,l}` (4) -- the base and Clang `code_for_workitem` dicts are EMPTY, so CPython is a
    `KeyError` and the port is `""` (`cstyle.bend:1174-1177` records it: unreachable for a real
    kernel, because every GPU renderer defines both entries).
  `ri_add_{0,1,4}` (3) -- THE FINDING, A DEFECT, NOT A CARVE-OUT. `render_index`'s non-ALU branch
    is `f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"`. CPython
    tests the WHOLE arg, and `UOp.reduce(arg=Ops.ADD)` sets `arg=(Ops.ADD, 0)` (`ops.py:671-674`,
    same at the pin), so `idx.arg == Ops.ADD` is FALSE and CPython NEVER strips: it emits
    `(buf1+(a+b))`. The port's `idx_arg_is_add` matches `AReduce{ADD, 0}` -- the port's OWN
    spelling of `(Ops.ADD, 0)` -- so it strips: `(buf1+a+b)`. The two strings differ by the inner
    parens. MEASURED in the oracle: `UOp(Ops.REDUCE, src=..., arg=(Ops.ADD, 0))` renders
    `(buf1+(a+b))`; `arg=Ops.ADD` (which `UOp.reduce` NEVER builds) renders `(buf1+a+b)`. The
    port models a check CPython's `arg` representation cannot satisfy.

THE CHECKS THE DIFF CANNOT EXPRESS. Both lanes could agree on an EMPTY string and the diff would
pass, so `port_artifact_claims()` reads the PORT'S OWN `bd.out` and asserts the structural facts
that make the rows a render rather than a coincidence: the `sz>1` suffix, the underscore on a
name WITH a space, the image arms, the three device prefixes, and the ASCII workitem.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

# 358 rows, named in the two source files' own order. The count is DERIVED from the divergences
# so the two numbers cannot disagree: 339 compared + 19 excluded.
ROWS = 358

# (CPython's line, the port's line), pinned on BOTH sides. An excluded-and-unpinned row is how a
# divergence stops being a claim; a `want` that is not the exact line fails the gate.
DIVERGES = {
    "opt_float4_0": ("opt_float4_0=None", "opt_float4_0="),
    "rdx_0_14": ("rdx_0_14=KeyError", "rdx_0_14=fp8e4m3"),
    "rdx_0_15": ("rdx_0_15=KeyError", "rdx_0_15=fp8e5m2"),
    "rdx_0_16": ("rdx_0_16=KeyError", "rdx_0_16=fp8e4m3fnuz"),
    "rdx_0_17": ("rdx_0_17=KeyError", "rdx_0_17=fp8e5m2fnuz"),
    "rdx_4_16": ("rdx_4_16=KeyError", "rdx_4_16=fp8e4m3fnuz"),
    "rdx_4_17": ("rdx_4_17=KeyError", "rdx_4_17=fp8e5m2fnuz"),
    "cfo_0_fdiv": ("cfo_0_fdiv=KeyError", "cfo_0_fdiv="),
    "cfo_1_exp2": ("cfo_1_exp2=KeyError", "cfo_1_exp2="),
    "cfo_1_sin": ("cfo_1_sin=KeyError", "cfo_1_sin="),
    "cfo_1_log2": ("cfo_1_log2=KeyError", "cfo_1_log2="),
    "cfo_1_reciprocal": ("cfo_1_reciprocal=KeyError", "cfo_1_reciprocal="),
    "cfw_0_g": ("cfw_0_g=KeyError", "cfw_0_g="),
    "cfw_0_l": ("cfw_0_l=KeyError", "cfw_0_l="),
    "cfw_1_g": ("cfw_1_g=KeyError", "cfw_1_g="),
    "cfw_1_l": ("cfw_1_l=KeyError", "cfw_1_l="),
    # THE ONE DEFECT THIS CENSUS FOUND: the port's `idx_arg_is_add` fires where CPython's
    # `idx.arg == Ops.ADD` does NOT -- see the docstring and the driver's FINDING block.
    "ri_add_0": ("ri_add_0=(buf1+(a+b))", "ri_add_0=(buf1+a+b)"),
    "ri_add_1": ("ri_add_1=(buf1+(a+b))", "ri_add_1=(buf1+a+b)"),
    "ri_add_4": ("ri_add_4=(buf1+(a+b))", "ri_add_4=(buf1+a+b)"),
}

# A representative row per group, pinned in EVERY lane. The byte diff already compares the other
# 339 positionally, so these guard the claims a POSITIONAL diff cannot: that the groups still
# exist under their own names.
PINS = (
    "opt_ktypedef_4", "opt_float4_1", "opt_smempre_5", "rd_0_2", "rdv_0_2", "rdl_2", "rdg_3",
    "rdo_5", "rdir_0", "rdiw_0", "rdl2_2_2", "rb_5_local", "rt_idx_reg", "rp_vec", "ra_scalar",
    "rc_scalar", "ri_array_4", "ri_swizzle_1", "ri_add_0", "wn_a", "cfo_4_sqrt",
    "cfoh_4_reciprocal", "cfof_1_sqrt", "cfw_3_g", "cfw_4_l",
)

GATE = Gate(
    "cstyle_render_census-gate",
    bend="cstyle_render_census.bend",
    oracle="cstyle_render_census-oracle.py",
    rows=ROWS,
    compared=ROWS - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in PINS],
)
assert GATE.compared == 339 and len(DIVERGES) == 19


def port_artifact_claims() -> bool:
    """THE STRUCTURAL FACTS, read off the PORT'S OWN `bd.out`.

    A diff compares a row with its counterpart, so two lanes that both emit `""` agree. Every
    claim here is a string NO OTHER ROW produces, so an empty renderer fails all ten:
    the `sz>1` suffix and the underscore on a name with a space (`signed char` -> `signed_char4`),
    both image arms, the three device prefixes on the SAME dtype, and the ASCII workitem.
    """
    f = GATE.dir / "bd.out"
    if not f.exists():
        return False
    rows = dict(l.split("=", 1) for l in f.read_text().splitlines() if "=" in l)
    want = {
        "rd_0_2": "signed char",
        "rdv_0_2": "signed_char4",
        "rdir_0": "read_only image2d_t",
        "rdiw_0": "write_only image2d_t",
        "rdl_2": "__local float*",
        "rdl_3": "threadgroup __attribute__((aligned(16))) float*",
        "rdg_2": "__global float*",
        "rp_vec": "((float4*)(alu0))",
        "cfw_3_g": "gid.y",
        "cfw_4_l": "threadIdx.y",
    }
    bad = {k: rows.get(k) for k, v in want.items() if rows.get(k) != v}
    if bad:
        print(f"cstyle_render_census-gate: the port's own strings moved: {bad}", file=sys.stderr)
    return not bad


if __name__ == "__main__":
    sys.exit(gate(GATE, "cstyle_render_census-gate: 358 rows, 3 lanes byte-identical over the "
                       "wide surface, 19 DECLARED divergences -- 6 unmapped-dtype KeyErrors from "
                       "the tinygrad drift, base float4 None, 5 dropped ALU ops, 4 empty "
                       "workitem dicts, and the ONE DEFECT this census found: render_index's "
                       "non-ALU branch strips parens where CPython's `arg == Ops.ADD` cannot fire "
                       "(ri_add_*); the port's own strings carry the sz>1 suffix, the image arms, "
                       "the device prefixes and the ASCII workitem",
                  checks=port_artifact_claims))
