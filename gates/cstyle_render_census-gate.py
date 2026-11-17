#!/usr/bin/env python3
"""cstyle_render_census-gate.py -- A RENDER CENSUS over `tinybendygrad/renderer/cstyle.bend`.

    .venv/bin/python gates/cstyle_render_census-gate.py

361 ROWS, THREE LANES (CPython, bend interpreted, bend compiled), 15 DECLARED DIVERGENCES.
THE THIRD KIND OF INSTRUMENT. The seven `*_graph_census` gates compare OP SEQUENCES (a graph)
and `fold_graph_census-gate.py` compares VALUES (a dtype, a shape, a pair of bounds). A RENDERER
produces NEITHER: it produces a STRING. So here the SAME UOp is built in both lanes, RENDERED,
and the two STRINGS are compared byte for byte -- the shape `render_val_s-gate.py` uses for the
signed integer printer, scaled to the whole `cstyle` surface.

425 ROWS NOW, AND THE 64 THAT LANDED ARE THE `rvp_*` ONES -- `render_vector_prefix`,
THE FUNCTION WHOSE WHOLE BODY IS AN `aligned(...)` NUMBER. THEY EXIST BECAUSE
THE CENSUS'S OWN POPULATION RULE HAD SAID, IN THIS FILE'S HEADER, THAT
`render_vector_prefix` HAS "NO PORT DEF" -- AND **THAT WAS FALSE**:
`tinybendygrad/renderer/cstyle.bend:3089` DEFINES IT. SO THE `aligned(...)`
NUMBER HAD **NO ROW ANYWHERE**, AND THE PORT's `ku_align` WAS WRONG: A
CONSTANT `4` OFF-CPU WHERE UPSTREAM ANSWERS `2**int(math.log2(dt.itemsize *
count))` (SO A `float4` GOT `aligned(4)` WHERE UPSTREAM EMITS `aligned(16)`),
AND `4` FOR A `bool` VECTOR WHERE UPSTREAM EMITS `aligned(1)`. IT WAS ALSO
INVISIBLE TO THE CORPUS: THE `aligned(...)` CLAUSE APPEARS IN **NONE** OF THE
CORPUS's 38 OUTPUTS (MEASURED: `grep -rho "aligned([0-9]*)" runs/graphcmp/D/`
IS EMPTY), SO NO GRAPH's OUTPUT MOVED WHEN IT WAS FIXED. THE `rvp_*` ROWS
VARY ALL THREE OF UPSTREAM's ARMS -- THE `target.device == "CPU"` FLAG, THE
`dtypes.is_bool` ARM, AND THE PRODUCT `dt.itemsize * count` -- AND THE COUNTS
3, 5 AND 6 ARE CHOSEN BECAUSE THEIR PRODUCTS (12, 20, 24) ARE NOT POWERS OF
TWO: A `log2` WITHOUT A FLOOR ANSWERS 16, 32 AND 32 WHERE UPSTREAM ANSWERS 8,
16 AND 16.

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

THE FIFTEEN DIVERGENCES, ALL PINNED -- six are the vendored-`tinygrad` drift and nine are
BENT-IS-TOTAL refusals, and the ONE REAL DEFECT this census found (`ri_add_*`) is fixed with its
pin dropped:

  `rdx_*` (6) -- THE VENDORED `tinygrad/` HAS DRIFTED PAST THE PIN AND THE PORT IS RIGHT. HEAD
    `_render_dtype` uses `self.type_map[dtype]` and RAISES KeyError for an unmapped dtype; the
    port prints the dtype's own name (`tm_get`'s default), which is the PIN's
    `.get(dtype, dtype.name)`. MEASURED BOTH WAYS: `tinygrad/renderer/cstyle.py:190-191` reads
    `self.type_map[dtype]`, `git show 'ad117c928^:tinygrad/renderer/cstyle.py'` reads
    `self.type_map.get(dtype, dtype.name)`. `AGENTS.md`: `ad117c928^` IS the pin and
    `ad117c928` is THIS PROJECT's own re-vendor, so a divergence here is the port being right
    and the tree drifting. NOT FIXED AND NOT TO BE FIXED. Only the oracle's refusal MARKER moved
    (`KeyError` -> `REFUSE:KeyError`); every `rdx_*` PORT column is byte-identical to what it
    was.
  `cfo_0_fdiv` + `cfo_1_{exp2,sin,log2,reciprocal}` (5) -- a dropped ALU op is a `KeyError` in
    CPython's `code_for_op[...]` (MEASURED: `args=(Ops.FDIV,)` and `(Ops.EXP2,)` etc., and
    `Ops.FDIV not in CStyleLanguage.code_for_op` while the four deleted ones are `in base` and
    `not in clang`). Bend is total and cannot raise, so the port answers
    `UNHANDLED(Ops.X)` -- the spelling `wgsl.bend:480` already uses for the SAME KeyError on
    the SAME twenty inherited arms, because `wgsl.bend:71-72` says those arms move HERE. It
    USED TO answer `""`, which is the shape this file's own header calls dangerous: the ALU
    rule wraps the answer in `f"..."`, so an empty one deletes the operand.
  `cfw_{0,1}_{g,l}` (4) -- the base and Clang `code_for_workitem` dicts are EMPTY (MEASURED, both
    are `{}`), so CPython raises `KeyError('g')` / `KeyError('l')`. The port answers
    `UNHANDLED(code_for_workitem[g])`, NAMING THE MISSING KEY -- which is CPython's own
    `KeyError` argument. `""` was worse twice over: it emitted a bare `;` from
    `f"{...}; /* ... */"`, AND `cfw_0_g` was byte-identical to `cfw_0_l`, so the `k` argument
    could not move the row.
  `ri_add_{0,1,4}` (3) -- WAS THE ONE FINDING, AND IT IS FIXED. `render_index`'s non-ALU branch is
    `f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"`, and the
    port's `idx_arg_is_add` matched `AReduce{ADD, 0}` -- its OWN spelling of `(Ops.ADD, 0)`, the
    shape `UOp.reduce` builds -- so it STRIPPED where CPython did not: `(buf1+a+b)` against
    CPython's `(buf1+(a+b))`.
    THE FIRST READING OF THIS SAID "CPython NEVER STRIPS", AND THAT IS TOO STRONG. MEASURED:
    `UOp(Ops.REDUCE, arg=(Ops.ADD, 0)).arg == Ops.ADD` is FALSE (a TUPLE never equals an enum)
    BUT `UOp(Ops.REDUCE, arg=Ops.ADD).arg is Ops.ADD` is TRUE -- so the test IS live, it fires
    when the arg IS the enum, which `UOp.reduce` does not build and a caller CAN. The arena's
    closed `Arg` spells "the arg IS an op" as `AOpLit`, so `idx_arg_is_add` now matches THAT arm
    and the two lanes agree on all three rows. `cstyle.bend` records both measurements.

THE CHECKS THE DIFF CANNOT EXPRESS. Both lanes could agree on an EMPTY string and the diff would
pass, so `port_artifact_claims()` reads the PORT'S OWN `bd.out` and asserts the structural facts
that make the rows a render rather than a coincidence: the `sz>1` suffix, the underscore on a
name WITH a space, the image arms, the three device prefixes, and the ASCII workitem.

THE CHECKS THE MUTATIONS ASKED FOR, AND THE ONE THAT ANSWERED NOTHING. This gate HAD no mutation
harness, which is why a whole session could read it green and never learn that its central finding
left a branch uncovered. `gates/cstyle_render_census-mutate.py` now carries ELEVEN, one per
claim. TEN move rows. THE ELEVENTH DID NOT, and it is the reason three rows exist:

  M8 -- `render_index` never strips parens -- moved 0 of 358 rows. The census drove ONE shape of
    the index arg, `arg=(Ops.ADD, 0)`, and on that node CPython's `idx.arg == Ops.ADD` is FALSE
    (`(Ops.ADD, 0) == Ops.ADD` compares a tuple to an enum) AND the port's `idx_arg_is_add` is
    FALSE (`AReduce{ADD,0}` is not `AOpLit`). Both lanes took the do-NOT-strip arm, agreed, and
    `H.strip_parens` had no row anywhere -- on the very branch the `ri_add_*` finding was about.
    The fix was to match `AOpLit`; the fix made the branch UNREACHED rather than unreachable.
    `ri_lit_*` (3 rows) drives `AOpLit{OpsADD{}}`, the shape `upat.py:26`'s
    `UOp(Ops.PYLITERAL, arg=self.op[0])` builds and the only one CPython strips on. `ri_add_*`
    `(buf1+(a+b))` and `ri_lit_*` `(buf1+a+b)` now differ by exactly the strip, and M8 moves 3.

That is `amd_dsl_census`'s `String.eq("vdst","vdst")` class wearing a row named after the defect
it used to prove: `ri_add_*` looks like a paren-stripping test -- the fixture is an ADD, the value
is `(a+b)` -- and tested nothing of the kind. A row is not a test because its NAME says what it
checks.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, oracle_drift

# 425 rows, named in the two source files' own order. The count is DERIVED from the divergences
# so the two numbers cannot disagree: 410 compared + 15 excluded. It was 358 until `ri_lit_*`
# (3 rows) landed -- see `M8` in `cstyle_render_census-mutate.py`, the mutation that moved zero
# rows and named the branch with no row on it -- and 361 until the `rvp_*` rows landed (64).
ROWS = 425

# THE ORACLE'S INPUTS, PINNED. A pin in a comment is a pin that cannot fail, and
# this gate's OWN SUBJECT is a COMPARISON AGAINST UPSTREAM -- so the bytes of
# the upstream it compares against are a PIN, and they are READ BY THIS GATE'S
# OWN CODE (`oracle_drift` below) on every run.
#
# WHY IT IS HERE AND NOT OPTIONAL. `gates/edge-runner.py`'s candidate rule is
# "a member that holds a CAN-FAIL PIN its own code reads" (and
# `gates/pincensus-pop.py`'s `rule_a` finds a pin site by its NAME matching
# `PIN_NAME` AND ITS RIGHT-HAND SIDE CARRYING A HEX LITERAL). THIS GATE HAD NO
# SUCH CONSTANT -- its `PINS` is a tuple of ROW NAMES, which is a different
# thing -- SO IT WAS **NOT A CANDIDATE** AND THE EDGE NEVER RAN IT.
# MEASURED: `gates/edge-runner.py --plan` printed 28 candidates and this gate
# was NOT AMONG THEM, while `gates/wgsl_render_census-gate.py` WAS (its
# `DRIFT_PIN` is exactly this shape). THIS IS THE REACHABILITY THE TASK ASKS
# FOR, AND IT WAS NOT THERE.
#
# THE FIVE FILES ARE THE ONES THE ORACLE IMPORTS OR READS: `cstyle.py` (the
# renderer whose methods are called), `ops.py` (the `Ops` enum), `dtype.py`
# (`dtypes`), `helpers.py` (`Target`, which `render_vector_prefix` READS FOR
# ITS `device` FIELD), and `uop/__init__.py` (which re-exports `Ops` -- and
# WHICH IS WHERE `class Ops` LIVES, SO A GREP OF `ops.py` FINDS NO `class Ops`
# AND UNDERCOUNTS THE ENUM BY HALF).
DRIFT_PIN = {
  "tinygrad/renderer/cstyle.py":
    "957f2bad6fd1bc3c17a1cad8d58d56cb9ec8cf8bdf5fa819aca74111f902126d",
  "tinygrad/uop/ops.py":
    "743ee07146d77b8d6e03fb819a63d4fe7c48a1f74ab2af2d9080460f59a285ed",
  "tinygrad/dtype.py":
    "d37944d2e66107023cc955dce457db9f256ca3cacb441bf5442c881ffa35bd60",
  "tinygrad/helpers.py":
    "417c5664548b0e89cc7b3441694314b62c05d73cd32a7a827380244499b34550",
  "tinygrad/uop/__init__.py":
    "d4029b973dfce976cccce6030a6673c647f1ed91ab142a2d0c99e5cb2fbc6bcb",
}

# (CPython's line, the port's line), pinned on BOTH sides. An excluded-and-unpinned row is how a
# divergence stops being a claim; a `want` that is not the exact line fails the gate.
#
# `opt_float4_0` WAS here and is not any more. CPython's base `float4` is `None` -- an ABSENT
# VALUE, not a refusal -- and the port answered `""`, which `dsl.bend:2041-2044` already ruled
# out for exactly this case ("an empty string is NOT the same answer, so the port prints
# `None`"). `float4.of` answers `"None"` and the row AGREES.
#
# AND `cfo_1_reciprocal`'s PORT-SIDE PIN SAID `UNHANDLED(Ops.RECIPROCAL)`, WHICH IS THE
# PRE-RENAME SPELLING AND DID NOT EXIST AT THE PIN `f5ac54685074` -- UPSTREAM RENAMED IT IN
# `1427aac3b` ("FLOORDIV/FLOORMOD -> DIV/MOD (#19047)", 2026-10-27) (`Ops.RECIPROCAL` ->
# `Ops.RECIP`), AND THE PORT's OWN `Op` ENUM SPELLS IT `OpsRECIP`.  SO THE PIN WAS
# STALE AND THE GATE WENT RED WITH A PRECISE MESSAGE ("bd's cfo_1_reciprocal is not
# 'cfo_1_reciprocal=UNHANDLED(Ops.RECIPROCAL)'") -- AND THE DIVERGENCE ITSELF IS
# UNCHANGED: THE PORT STILL REFUSES THIS ROW (`UNHANDLED(Ops.RECIP)`), SO THE PIN IS REPOINTED
# AND NOT WEAKENED, AND THE ROW STILL DIVERGES.
DIVERGES = {
    "rdx_0_14": ("rdx_0_14=REFUSE:KeyError", "rdx_0_14=fp8e4m3"),
    "rdx_0_15": ("rdx_0_15=REFUSE:KeyError", "rdx_0_15=fp8e5m2"),
    "rdx_0_16": ("rdx_0_16=REFUSE:KeyError", "rdx_0_16=fp8e4m3fnuz"),
    "rdx_0_17": ("rdx_0_17=REFUSE:KeyError", "rdx_0_17=fp8e5m2fnuz"),
    "rdx_4_16": ("rdx_4_16=REFUSE:KeyError", "rdx_4_16=fp8e4m3fnuz"),
    "rdx_4_17": ("rdx_4_17=REFUSE:KeyError", "rdx_4_17=fp8e5m2fnuz"),
    "cfo_0_fdiv": ("cfo_0_fdiv=REFUSE:KeyError", "cfo_0_fdiv=UNHANDLED(Ops.FDIV)"),
    "cfo_1_exp2": ("cfo_1_exp2=REFUSE:KeyError", "cfo_1_exp2=UNHANDLED(Ops.EXP2)"),
    "cfo_1_sin": ("cfo_1_sin=REFUSE:KeyError", "cfo_1_sin=UNHANDLED(Ops.SIN)"),
    "cfo_1_log2": ("cfo_1_log2=REFUSE:KeyError", "cfo_1_log2=UNHANDLED(Ops.LOG2)"),
    "cfo_1_reciprocal": ("cfo_1_reciprocal=REFUSE:KeyError",
                         "cfo_1_reciprocal=UNHANDLED(Ops.RECIP)"),
    "cfw_0_g": ("cfw_0_g=REFUSE:KeyError", "cfw_0_g=UNHANDLED(code_for_workitem[g])"),
    "cfw_0_l": ("cfw_0_l=REFUSE:KeyError", "cfw_0_l=UNHANDLED(code_for_workitem[l])"),
    "cfw_1_g": ("cfw_1_g=REFUSE:KeyError", "cfw_1_g=UNHANDLED(code_for_workitem[g])"),
    "cfw_1_l": ("cfw_1_l=REFUSE:KeyError", "cfw_1_l=UNHANDLED(code_for_workitem[l])"),
}

# A representative row per group, pinned in EVERY lane. The byte diff already compares the other
# 339 positionally, so these guard the claims a POSITIONAL diff cannot: that the groups still
# exist under their own names.
PINS = (
    "opt_ktypedef_4", "opt_float4_1", "opt_smempre_5", "rd_0_2", "rdv_0_2", "rdl_2", "rdg_3",
    "rdo_5", "rdir_0", "rdiw_0", "rdl2_2_2", "rb_5_local", "rt_idx_reg", "rp_vec", "ra_scalar",
    "rc_scalar", "ri_array_4", "ri_swizzle_1", "ri_add_0", "ri_lit_0", "wn_a", "cfo_4_sqrt",
    "cfoh_4_reciprocal", "cfof_1_sqrt", "cfw_3_g", "cfw_4_l",
    # THE `render_vector_prefix` ROWS, AND THE FOUR THAT CARRY THE THREE ARMS
    # BETWEEN THEM. `rvp_gpu_12_4` IS A `float4` (THE `float4` LOAD THE
    # ATTRIBUTE EXISTS FOR), `rvp_gpu_12_3` IS THE NON-POWER-OF-TWO PRODUCT
    # (12 BYTES -> 8, NOT 16), `rvp_gpu_1_4` IS THE `bool` ARM (1, NOT 4),
    # AND `rvp_cpu_12_4` IS THE CPU ARM (4, NOT 16).
    "rvp_gpu_12_4", "rvp_gpu_12_3", "rvp_gpu_1_4", "rvp_cpu_12_4",
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
assert GATE.compared == 410 and len(DIVERGES) == 15


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
        # THE `aligned(...)` NUMBERS, READ OFF THE PORT's OWN STRINGS. A DIFF
        # COMPARES A ROW WITH ITS COUNTERPART, SO TWO LANES THAT BOTH EMIT THE
        # SAME WRONG NUMBER AGREE -- AND THE WHOLE POINT OF THE `rvp_*` ROWS
        # IS THAT THE PORT's ANSWER IS NOW THE UPSTREAM ONE, WHICH A DIFF
        # ALREADY SEES. THESE FOUR ARE THE STRUCTURAL CLAIM: THE ATTRIBUTE IS
        # PRESENT, IT IS IN THE `aligned(...)` SLOT, AND ITS NUMBER IS THE
        # WHOLE-VECTOR ONE ON THE GPU AND THE ELEMENT ONE ON THE CPU.
        "rvp_gpu_12_4": "typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));",
        "rvp_gpu_12_3": "typedef float float3 __attribute__((aligned(8),ext_vector_type(3)));",
        "rvp_gpu_1_4": "typedef _Bool _Bool4 __attribute__((aligned(1),ext_vector_type(4)));",
        "rvp_cpu_12_4": "typedef float float4 __attribute__((aligned(4),ext_vector_type(4)));",
    }
    bad = {k: rows.get(k) for k, v in want.items() if rows.get(k) != v}
    if bad:
        print(f"cstyle_render_census-gate: the port's own strings moved: {bad}", file=sys.stderr)
    return not bad


def oracle_inputs_intact() -> bool:
    """THE ORACLE'S INPUTS AGAINST `DRIFT_PIN`, re-measured on EVERY run.

    `gates/gatekit.py:oracle_drift` asks the question and this gate decides what
    an answer means. THE QUESTION IS NOT "is this gate well-formed": it is "is
    the UPSTREAM this gate compares against still the upstream these rows were
    taken against", and only `main()` knows whether a drifted input is fatal
    for THIS gate. It is: a `render_vector_prefix` whose `alignment` line has
    MOVED is a DIFFERENT ORACLE, and every `rvp_*` row would be comparing the
    port against a function that no longer exists.
    """
    bad = oracle_drift(DRIFT_PIN)
    if bad:
        print(f"cstyle_render_census-gate: the ORACLE's INPUTS drifted: {bad}", file=sys.stderr)
        return False
    return True


if __name__ == "__main__":
    sys.exit(gate(GATE, "cstyle_render_census-gate: 425 rows, 3 lanes byte-identical over the "
                       "wide surface, 15 DECLARED divergences -- 6 unmapped-dtype refusals "
                       "from the tinygrad drift where THE PORT IS RIGHT, and 9 refusals Bend "
                       "cannot raise (5 dropped ALU ops, 4 empty workitem dicts) which the port "
                       "now spells UNHANDLED(...) instead of the empty string; base float4 None "
                       "AGREES and its pin is dropped; the ONE DEFECT it found (render_index's "
                       "non-ALU branch stripping parens on an AReduce where CPython strips "
                       "only on a literal-op "
                       "arg) IS FIXED; the port's own strings carry the sz>1 suffix, the image arms, "
                       "the device prefixes and the ASCII workitem; AND THE 64 `rvp_*` ROWS "
                       "COMPARE THE PORT's `render_vector_prefix` AGAINST CPython's REAL ONE, "
                       "OVER ALL THREE OF ITS ARMS -- THE CPU FLAG, THE `is_bool` ARM (1, NOT 4) "
                       "AND THE `aligned(...)` NUMBER, INCLUDING THE NON-POWER-OF-TWO PRODUCTS "
                       "(12 BYTES -> 8, 20 -> 16, 24 -> 16) THAT A `log2` WITHOUT A FLOOR "
                       "ANSWERS WRONG",
                  checks=lambda: port_artifact_claims() and oracle_inputs_intact()))
