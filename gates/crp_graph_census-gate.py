#!/usr/bin/env python3
"""crp_graph_census-gate.py -- A PROMOTATION CENSUS over `tinybendygrad/mixin/creation.bend`,
and the first gate that layer's DTYPE PROMOTION has ever had.

    .venv/bin/python gates/crp_graph_census-gate.py
    .venv/bin/python gates/crp_graph_census-gate.py --refresh

207 ROWS, THREE LANES, 206 EXACT MATCHES AND 1 DECLARED DIVERGENCE -- W3's MISSING
`vmin`/`vmax`, WHICH IS A CONSEQUENCE RATHER THAN A DEFECT. **THE NINETEEN `iv_` ROWS THIS
GATE FOUND ARE FIXED AND GONE**; see THE 19 PINS THAT ARE NOT HERE, below. **THE SIBLING
`cr_graph_census` ALREADY EXISTS AND IS GREEN**
(MEASURED rc=0, 28 rows), which is not what this unit's brief said. What the sibling prints
is `O.Rng.sig`: the node COUNT, the ROOT op, the ROOT's src COUNT and the ROOT's src op
SEQUENCE. `realize_graph_census-oracle.py:38-44` names that instrument's own failure -- "a
3-op PREFIX and no ARG, and `gr_10` printed identically on both sides until a deep printer
was used" -- and `creation.bend`'s own header says the same of ITS gate: "THE FLOAT ARM IS
THE SILENT ONE: there both consts cast, so the COUNT agrees and only the CONST's ARG
differs, which `Rng.sig` did not print before this session." So this gate prints the whole
CONE, and inside it the CONST's VALUE and the ALLOC's `ParamArg`.

WHAT THE DEEP FORM BOUGHT, MEASURED AND NOT ARGUED. Thirty of the 207 rows moved when the
float arm started printing `H.f32_show` instead of a bit pattern, and EVERY ONE OF THEM WAS
THE ORACLE'S OR THE FIXTURE'S, NOT THE PORT'S: `H.f32_show(0.0)` is `"0"` where Python's
`repr(0.0)` is `"0.0"`. Twenty rows' worth of that would have been pins-file noise about
`helpers.bend`. The remaining two fixture defects are named at the foot. The two real
divergences below were INVISIBLE TO THE SIBLING'S SIGNATURE ENTIRELY -- `Rng.sig` prints
`CONST/0` for a constant whatever it holds and prints no `ParamArg` at all -- so neither
could ever have been reported by a prefix.

THE POPULATIONS ARE DISCOVERED, ON BOTH SIDES, AND NINE CHECKS COMPARE THEM EVERY RUN.
    methods_hold    the TEN `cr_*` defs that mirror a `creation.py` METHOD. Discovered by
                    intersecting `creation.bend`'s `def cr_*` names with `creation.py`'s
                    `def <n>(self|cls`, both by `re` -- NEITHER LIST TYPED -- and the
                    METHOD SET is compared with the driver's own family table, so a method
                    nothing has a row for is named rather than quietly absent.
                    `cpy_only_methods()` prints `creation.py`'s methods the port does NOT
                    have, which is W2's `_multi_like` and nothing else today.
    dtypes_hold     the TWENTY dtypes, from `spec.bend`'s twenty `def <n>() -> Dt: Dt{...}`
                    constructors, cross-checked against `dir(dtypes)`'s `DType`s, against
                    CPython's `priority`/`bitsize`, field by field, and against the row
                    names both lanes printed. It also asserts that the ONE field the two
                    files disagree on is still `{void.priority}` and no more.
    receiver_hold   `rx(dt).dtype == dt` for all twenty dtypes, AND that a BUFFERED
                    `Tensor.zeros(dt)` does NOT have it -- so the receiver fixture is
                    load-bearing rather than decorative.
    frompy_hold     every constructor of the port's `type Const` is REACHED by a row, read
                    off the lane's own output: `CInvalid` by an `iv_` row, `CBool` by a
                    bool-dtype row, `CFloat` by a float-dtype row, `CInt` by an int-dtype
                    row. Four `O.Const` arms, four witnesses.
    opscast_hold     THE (b) TRIAGE AS A GATE. `grep -c OpsCAST creation.bend` is 1, it is
                    inside `cr_cast`, and `cr_cast` HAS a fold arm -- and the nineteen `iv_`
                    rows say what that fold gets wrong. A tree-wide grep is NOT the answer,
                    because most of its hits are pattern-matcher arms; this file has one.
    drift_hold      SEVEN vendored files, THREE blobs each, plus -- for the TWO THAT HAVE
                    DRIFTED since `ad117c928^` -- the BODY of every def the rows read,
                    compared between the pin and HEAD. See THE VENDORED answer below.
    classes_hold    each declared divergence still IS its class. A `PROMOTION FOLD` row must
                    be CPython's row with exactly one `CAST/1` deleted, REBUILT and
                    compared (a subsequence test is not the claim); a `W3 BOUNDS` row must
                    be CPython's row with one `ParamArg` field changed AND its `eb_` PAIR
                    must now AGREE, because the pair is what names the cause.
    fold_axis_hold  the fold SET is MEASURED, not assumed: over the `f_` family exactly
                    three of twenty dtypes carry no `CAST/1` and they are `bool`, `weakint`
                    and `weakfloat` -- `ops.py:634`'s own comment, read back off a lane.
    no_noop_bottom   `NOOP` is `Arena.bottom()`, so a `NOOP` in any cone is an out-of-range
                    index read. Read off the port lanes' own output.

THE VENDORED ANSWER, AND IT IS NOT "NOTHING DRIFTED". `git rev-parse --short=8` on all
three revisions, per file:

    tinygrad/mixin/creation.py   HEAD=73f51afa  ad117c928=73f51afa  PIN=73f51afa  UNCHANGED
    tinygrad/dtype.py            HEAD=f40089a1  ad117c928=f40089a1  PIN=f40089a1  UNCHANGED
    tinygrad/mixin/dtype.py      HEAD=688a612a  ad117c928=688a612a  PIN=688a612a  UNCHANGED
    tinygrad/mixin/movement.py   HEAD=35ebe0eb  ad117c928=35ebe0eb  PIN=35ebe0eb  UNCHANGED
    tinygrad/tensor.py           HEAD=4f7d22e7  ad117c928=4f7d22e7  PIN=4f7d22e7  UNCHANGED
    tinygrad/helpers.py          HEAD=563d1602  ad117c928=deb96849  PIN=deb96849  **DRIFTED**
    tinygrad/uop/ops.py          HEAD=2c686da7  ad117c928=6f7b9996  PIN=3ffac84b  **DRIFTED**

SO TWO FILES HAVE DRIFTED SINCE THE PIN `ad117c928^`, and `AGENTS.md` says the PIN is the
truthful oracle for a drifted file -- which would mean these rows were measured against the
wrong tree. THEY WERE NOT, AND THE MEASUREMENT IS IN `drift_hold()` AND IS ABOUT BODIES:

  * `helpers.py` moved by ONE INSERTION, `def to_name(*parts)`, and nothing in
    `creation.py`'s ten methods reads it. `argfix` (helpers.py:24) and `prod` are
    byte-identical: `git diff 'ad117c928^' HEAD -- tinygrad/helpers.py` is 1 file changed,
    1 insertion(+), 0 deletions(-), and the hunk is that one def.
  * `ops.py` moved by 61 insertions and 69 deletions, in `UOp.loop`, `UOp.param_like`,
    `UOp.custom_function`, `UOp.call`, `CallInfo.__reduce__` and the deletion of
    `contiguous_bitcast_index`. NONE OF THOSE IS READ BY THESE 207 ROWS. The two that are
    -- `UOp.const` (ops.py:629-637, which owns the fold) and `UOp.toposort` (ops.py:588) --
    are extracted from the pin and from HEAD and compared BYTE FOR BYTE, and they are
    identical. `drift_hold()` re-extracts and re-compares on every run, so the claim stays
    re-decidable instead of being a sentence somebody wrote once.

THE 19 PINS THAT ARE NOT HERE, AND THE ONE THAT IS. `creation.bend` IS CHANGED BY THIS
REVISION, and the change is the finding.

  0 PROMOTION FOLD -- `iv_void iv_weakint iv_i8 iv_u8 iv_i16 iv_u16 iv_i32 iv_u32 iv_i64
  iv_u64 iv_weakfloat iv_fp8e4m3 iv_fp8e4m3fnuz iv_fp8e5m2 iv_fp8e5m2fnuz iv_f16 iv_bf16
  iv_f32 iv_f64` were CPython's row with EXACTLY ONE `CAST/1` INSERTED -- verified by
  rebuilding, not by a subsequence test -- while `iv_bool`, the twentieth dtype, AGREED.
  `cr_const_of` folded on `from_py(v) == dt`, and `ops.py:630` has ALREADY REPLACED `dt`
  with `from_py(b)` whenever `b is Invalid`, so the test was `bool == dt`: true at `bool`
  and false at the other nineteen. It now folds on `de = cr_cast_dt(is_cinvalid(v), dt)`,
  which is `ops.py:630`'s `dtype` AFTER that replacement, and all twenty `iv_` rows match
  CPython byte for byte. THE MUTATION READING, BOTH WAYS: WITH THESE NINETEEN PINS STILL IN
  PLACE AND THE FIX IN, THE GATE IS RED -- `bd's iv_void is not 'iv_void=...CAST/1...' --
  if the divergence is fixed, drop it from DIVERGES`; WITH THEM DROPPED IT IS GREEN.

  1 W3 BOUNDS -- `el_weakint`. The port's ALLOC is `i64` and CPython's is `i32`, a buffer
  twice the width. Its PAIR `eb_weakint` -- the same call with `vmin`/`vmax` handed in --
  AGREES, which is what makes this one row a measurement rather than a shrug: the missing
  bounds are named as the cause and `D.commit_dtype` is cleared.

EXIT STATUS: 0 all three lanes identical after the pins and every check holds · 1 a lane
took the wrong row count, the oracle failed, the native compile failed, the lanes disagree,
a pin moved, or a check failed · 3 a precondition was absent (the pins file, the output
directory, the substrate, or the oracle) · 5 a lane ran and emitted nothing.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, REFUSED, gate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "crp_graph_census-pins.rows"
ART = HERE / "artifacts" / "crp_graph_census-gate"
DRIVER = HERE / "crp_graph_census.bend"
ORACLE = HERE / "crp_graph_census-oracle.py"
PORT = ROOT / "tinybendygrad" / "mixin" / "creation.bend"
CPY = ROOT / "tinygrad" / "mixin" / "creation.py"
SPEC = ROOT / "tinybendygrad" / "LAWS" / "spec.bend"
OPS = ROOT / "tinybendygrad" / "uop" / "ops.bend"
PIN = "ad117c928^"          # the pin AGENTS.md names for a drifted file

# THE SEVEN VENDORED FILES THESE ROWS READ, and the BLOB each must keep. A gate that pinned
# only its subject would let `ops.py` move and report the port's stale numbers as a verdict.
VENDORED = ("tinygrad/mixin/creation.py", "tinygrad/uop/ops.py", "tinygrad/dtype.py",
            "tinygrad/helpers.py", "tinygrad/mixin/dtype.py", "tinygrad/mixin/movement.py",
            "tinygrad/tensor.py")
# THE TWO THAT HAVE ACTUALLY MOVED SINCE THE PIN, and the BODY of each def the rows read.
# `drift_hold()` extracts these from the PIN and from HEAD and compares them byte for byte,
# so "the drift does not touch what these rows read" is a re-derived claim and not a note.
DRIFTED = {
    "tinygrad/uop/ops.py": [
        (r"^  def const\(b:ConstLike.*?(?=^  # cast, except for CONST)", "UOp.const"),
        (r"^  def toposort\(self, gate.*?(?=^  def topovisit)", "UOp.toposort"),
    ],
    "tinygrad/helpers.py": [
        (r"^def argfix\(\*x\):.*?(?=^def |\Z)", "argfix"),
        (r"^def prod\(.*?(?=^def |\Z)", "prod"),
    ],
}

# THE ROW POPULATION IS NOT HERE. It is discovered from the driver, the dtype table and
# CPython's own module, and `names_hold()` compares it with what BOTH lanes printed. This
# constant exists only so `gatekit` knows how many rows to demand before it has read any.
FAMS = 9                     # the `fam.of` arms in the driver, re-derived by `names_hold`
SHFAMS = 5                   # the `sh.of` arms
SHAPES = 4                   # the `shp()` list elements, re-derived from the driver file
TAIL = 7                     # the six `in_*` rows and `ctl_2`


def report(name, bad):
    for b in bad:
        print(f"  {name}: {b}", file=sys.stderr)
    if not bad:
        print(f"  {name}: OK")
    return not bad


def _lines(s):
    return [l for l in s.splitlines() if l.strip()]


# ===========================================================================
# THE POPULATION. Re-derived from BOTH sides on every run, never a list here.
# ===========================================================================
SPEC_DT = re.compile(r"^def ([a-z_0-9]+)\(\) -> Dt: Dt\{([0-9]+), ([0-9]+),", re.M)
ALIAS = {"void": "void", "weakint": "weakint", "boolean": "bool", "int8": "i8", "uint8": "u8",
         "int16": "i16", "uint16": "u16", "int32": "i32", "uint32": "u32", "int64": "i64",
         "uint64": "u64", "weakfloat": "weakfloat", "fp8e4m3": "fp8e4m3",
         "fp8e4m3fnuz": "fp8e4m3fnuz", "fp8e5m2": "fp8e5m2", "fp8e5m2fnuz": "fp8e5m2fnuz",
         "half": "f16", "bfloat16": "bf16", "single": "f32", "double": "f64"}
CPY_METHOD = re.compile(r"^ *def ([a-z_0-9]+)\((?:self|cls)[,)]", re.M)
PORT_DEF = re.compile(r"^def ([a-z_0-9]+)\(", re.M)


def spec_dtypes():
    """`spec.bend`'s dtype constructors, IN FILE ORDER, as `(bend name, pri, bits)`."""
    return [(nm, int(pri), int(bits)) for nm, pri, bits in SPEC_DT.findall(SPEC.read_text())]


def methods():
    """`cr_<n>` is a census METHOD iff `creation.bend` declares `def cr_<n>` AND
    `creation.py` declares `<n>(self` / `<n>(cls`. Two `re` walks over two files and an
    intersection -- neither list typed, and the empty answer is a red run, not a lane."""
    port = {n[3:] for n in PORT_DEF.findall(PORT.read_text()) if n.startswith("cr_")}
    cpy = set(CPY_METHOD.findall(CPY.read_text()))
    return sorted(port & cpy)


def cpy_only_methods():
    """`creation.py`'s methods the port does NOT have, NAMED. `_multi_like` is W2 (the
    multi-device arm) and `const` is a `raise NotImplementedError`; a method list that
    silently dropped them would look the same as a port that simply lacks them."""
    port = {n[3:] for n in PORT_DEF.findall(PORT.read_text()) if n.startswith("cr_")}
    return sorted(set(CPY_METHOD.findall(CPY.read_text())) - port)


def driver_fams():
    r"""THE DRIVER'S OWN FAMILY TABLE, in its own order: `fam.of`'s and `sh.of`'s arms,
    parsed out of `crp_graph_census.bend`. A family the gate cannot find there is a family
    whose ROWS it would never notice losing.

    THE `case _` ARM IS PART OF THE TABLE AND NOT A GAP IN IT. `fam.of` numbers `zl` 0
    through `z` 7 and answers everything else with `eb`, so a regex reading only the
    numbered arms found EIGHT families and demanded 183 rows against lanes that printed
    207. The `_` arm's id is therefore the COUNT of the numbered ones, which is also what
    `fam.one` dispatches on -- the two are the same number and the gate must not invent a
    second one."""
    src = DRIVER.read_text()

    def arms(head):
        body = re.search(rf"^def {head}\.of\(.*?\n(.*?)(?=^def )", src, re.M | re.S)
        if not body:
            return []
        got = [(int(i), p) for i, p in re.findall(r'case (\d+)n: "(\w+)"', body.group(1))]
        tail = re.findall(r'case _:\s+"(\w+)"', body.group(1))
        return got + [(len(got), p) for p in tail]

    return arms("fam"), arms("sh")


def driver_shapes():
    """HOW MANY SHAPES `shp()` LISTS, read out of the driver's own definition. A count in
    this file that nobody checks against `shp()` is a second number that can disagree with
    the first, which is `ops_python_census-gate.py`'s `compared is not len(port_only)`."""
    m = re.search(r"^def shp\(\) -> List<&2, List<&2, U32>>: (\[.*\])", DRIVER.read_text(), re.M)
    if not m:
        return 0
    depth, n = 0, 0
    for ch in m.group(1):
        if ch == "[":
            depth += 1
            n += 1 if depth == 2 else 0
        elif ch == "]":
            depth -= 1
    return n


def expected_rows():
    """THE ROW NAME LIST, BUILT FROM DISCOVERY, IN ORDER. Family prefixes from the driver,
    dtypes from `spec.bend`, shapes from `shp()`, and the tail from the driver's own prints.
    `names_hold()` compares this with BOTH lanes."""
    fams, shfams = driver_fams()
    dts = [ALIAS.get(n, n) for n, _, _ in spec_dtypes()]
    out = [f"{p}_{d}" for _, p in fams for d in dts]
    out += [f"{p}_{i}" for _, p in shfams for i in range(driver_shapes())]
    src = DRIVER.read_text()
    out += sorted(re.findall(r'IO\.print\(String\.concat\(\["(in_\w+)="', src))
    out += [f"ctl_{n}" for n in re.findall(r'sh\.one\(\d+n, "ctl", (\d+)n', src)]
    return out


def lane_rows(name):
    f = ART / name
    if not f.is_file():
        return None
    return {l.split("=", 1)[0]: l.split("=", 1)[1] for l in _lines(f.read_text())}


def names_hold() -> bool:
    """THE TWO LANES CARRY THE DISCOVERED POPULATION, IN THE DISCOVERED ORDER, ONCE EACH.

    This is `rng_graph_census`'s "every one of the 726 pairs is emitted, refusals included,
    so the two lanes carry the same row count by construction", made re-decidable: the
    population is rebuilt from four sources and compared against what both lanes PRINTED, so
    a family the driver stops walking, a dtype `spec.bend` gains or a shape `shp()` loses is
    a red run rather than a shorter lane. The oracle's first draft missed `re.MULTILINE` on
    its own dtype regex, discovered an EMPTY population, printed 27 of 207 rows and exited
    0 -- this is the check that would have said so, and `gatekit`'s row count is the
    backstop behind it."""
    want = expected_rows()
    bad = []
    if len(want) != len(set(want)):
        bad.append(f"the discovered population has {len(want) - len(set(want))} duplicate names")
    fams, shfams = driver_fams()
    if len(fams) != FAMS:
        bad.append(f"the driver's `fam.of` has {len(fams)} arms, the header says {FAMS}")
    if len(shfams) != SHFAMS:
        bad.append(f"the driver's `sh.of` has {len(shfams)} arms, the header says {SHFAMS}")
    if driver_shapes() != SHAPES:
        bad.append(f"`shp()` lists {driver_shapes()} shapes, the header says {SHAPES}")
    tail = len(want) - len(fams) * len(spec_dtypes()) - len(shfams) * driver_shapes()
    if tail != TAIL:
        bad.append(f"the discovered tail is {tail} rows, the header says {TAIL}")
    for lane, f in (("bd", "bd.out"), ("bn", "bn.out"), ("py", "py.rows")):
        got = list(_lane_order(f))
        if got != want:
            missing = sorted(set(want) - set(got))[:4]
            extra = sorted(set(got) - set(want))[:4]
            bad.append(f"{lane} printed {len(got)} rows, the discovery says {len(want)}"
                       + (f"; missing {missing}" if missing else "")
                       + (f"; extra {extra}" if extra else ""))
    return report("names_hold", bad)


def _lane_order(f):
    p = ART / f
    if not p.is_file():
        return []
    return [l.split("=", 1)[0] for l in _lines(p.read_text()) if "=" in l]


# THE TEN DISCOVERED METHODS AND WHERE EACH ONE IS ROWED. A method with no family is not
# necessarily a gap -- `full` is reached through `iv_` and `fs_` because those ARE `cr_full`
# with two different values -- so this is a MAP and not a coverage count, and a method added
# to `creation.bend` with no entry here is a red run rather than an unmentioned omission.
METHOD_ROWS = {
    "const_like": "cl", "empty": "ne", "empty_like": "el", "full": "f", "full_like": "fl",
    "invalids": "iv", "ones": "o", "ones_like": "ol", "zeros": "z", "zeros_like": "zl",
}


def methods_hold() -> bool:
    """THE METHOD POPULATION, DISCOVERED FROM BOTH FILES AND COMPARED WITH THE DRIVER.

    `cr_<n>` is a census METHOD iff `creation.bend` declares `def cr_<n>` AND `creation.py`
    declares `<n>(self` / `<n>(cls`. MEASURED: `creation.bend` has 41 distinct `cr_*` def
    prefixes and 10 of them mirror a method; the other 31 are the plumbing (`cr_cast`,
    `cr_from_py`, `cr_bounds`, `cr_mop`, `cr_after`, `cr_alloc`, ...) and this census's own
    printers. `creation.py` has 11 methods and the eleventh is `_multi_like`, which is W2 --
    the multi-device arm `cr_full_like` cannot reach -- so it is PRINTED here rather than
    left to look like agreement.

    `creation.py:12`'s `const` is a `raise NotImplementedError` and is a `@staticmethod`, so
    it matches neither regex; it is in `MISSING` for that reason and the reason is here."""
    m = methods()
    unported = cpy_only_methods()
    fams = [p for _, p in driver_fams()[0]] + [p for _, p in driver_fams()[1]]
    bad = []
    if not m:
        bad.append("no `cr_*` def mirrors a creation.py method -- the discovery is EMPTY, "
                   "which is not a measurement")
    if len(m) != len(set(m)):
        bad.append("the discovered method set has duplicates")
    for x in m:
        if x not in METHOD_ROWS:
            bad.append(f"{x} mirrors a creation.py method and METHOD_ROWS has no row family "
                       f"for it -- add the family or say why it needs none")
    for x, fam in METHOD_ROWS.items():
        if x in m and fam not in fams:
            bad.append(f"{x} is declared rowed in family {fam!r}, which the driver has no "
                       f"arm for (it has {fams})")
    for x in unported:
        if x not in MISSING:
            bad.append(f"creation.py's {x} has no def in creation.bend and is not declared "
                       f"unported (MISSING={sorted(MISSING)})")
    print(f"  methods_hold: {len(m)} methods {m}; creation.py's own unported: {unported}")
    return report("methods_hold", bad)


# `creation.py`'s methods with NO def here, and WHY. A list of two is not a population --
# it is a CLAIM -- so it is compared against the discovered set on every run, which is what
# turns it into a check.
MISSING = {"_multi_like": "W2, the multi-device arm (creation.py:16-20); `cr_full_like` "
                          "is single-device and the tuple arm is a TODO(p3) at "
                          "creation.bend:414",
           "const": "a `raise NotImplementedError` (creation.py:12), a @staticmethod, and so "
                    "neither regex matches it; it has no def and no graph"}


def dtypes_hold() -> bool:
    """THE DTYPE TABLE ITSELF, CROSS-CHECKED FIELD BY FIELD. `spec.bend` is the port's
    table, `dir(dtypes)` is CPython's, and the two are DIFFERENT FILES with a shared
    vocabulary -- so the check is not "both have twenty entries", it is "entry i of one has
    the same priority and the same bitsize as entry i of the other"."""
    bad = []
    spec = spec_dtypes()
    if not spec:
        bad.append("spec.bend has no `def <n>() -> Dt: Dt{` constructor")
        return report("dtypes_hold", bad)
    sys.path.insert(0, str(ROOT))
    from tinygrad import dtypes
    from tinygrad.dtype import DType
    cpy = {}
    for n in dir(dtypes):
        try:
            v = getattr(dtypes, n)
        except Exception:                                            # noqa: BLE001
            continue
        if isinstance(v, DType):
            cpy[v.name] = v
    if set(cpy) != {ALIAS.get(n, n) for n, _, _ in spec}:
        bad.append(f"spec.bend's dtypes are {sorted(ALIAS.get(n, n) for n, _, _ in spec)}, "
                   f"dir(dtypes) has {sorted(cpy)}")
    off = []
    for nm, pri, bits in spec:
        d = cpy.get(ALIAS.get(nm, nm))
        if d is None:
            continue
        if d.bitsize != bits:
            off.append(f"{nm}.bitsize dtypes={d.bitsize} spec={bits}")
        if d.priority != pri and nm not in PRI_OFF:
            off.append(f"{nm}.priority dtypes={d.priority} spec={pri}")
        elif d.priority != pri:
            off.append(f"{nm}.priority dtypes={d.priority} spec={pri} [DECLARED]")
    if sorted(off) != [f"void.priority dtypes={cpy['void'].priority} spec=0 [DECLARED]"]:
        bad.append(f"the dtype fields that disagree are {off}, expected only void.priority")
    return report("dtypes_hold", bad)


PRI_OFF = {"void"}


def receiver_hold() -> bool:
    """THE RECEIVER FIXTURE IS LOAD-BEARING, MEASURED BOTH WAYS.

    `Tensor.zeros(shape, dtype=dt)` is NOT a tensor of dtype `dt`: `full` builds its buffer
    with `commit_dtype()` (creation.py:86), so at `weakint` it is an **i32** tensor. The
    oracle's receiver is `buffer=False` for that reason, and this check re-derives both
    halves so a future change to either is a red run rather than a set of rows that quietly
    stop testing the dtype their names claim. `decomp_graph_census` lived a whole session
    on a fixture that was wrong in exactly this way."""
    sys.path.insert(0, str(ROOT))
    from tinygrad import dtypes
    from tinygrad.dtype import DType
    bad, checked = [], 0
    # `dir(dtypes)` carries FORTY-FIVE names for TWENTY dtypes -- `float`, `double`, `half`,
    # `int`, `long`, `bool`, `uchar` and the rest are ALIASES of the same twenty objects --
    # so the population is the DISTINCT set keyed by `DType.name`, which is what
    # `dtypes_()` in the oracle returns and what `dtypes_hold` compares.
    seen = {}
    for n in dir(dtypes):
        try:
            dt = getattr(dtypes, n)
        except Exception:                                            # noqa: BLE001
            continue
        if isinstance(dt, DType):
            seen.setdefault(dt.name, dt)
    for dt in seen.values():
        checked += 1
        if Tensor0(dt).dtype is not dt:
            bad.append(f"{dt.name}: buffer=False receiver has dtype {Tensor0(dt).dtype.name}")
        if dt is dtypes.weakint and Tensor0(dt, buffered=True).dtype is dt:
            bad.append("a BUFFERED weakint receiver now IS weakint -- the fixture's reason "
                       "for buffer=False has gone and the choice must be re-argued")
    if checked != 20:
        bad.append(f"dir(dtypes) yielded {checked} DTypes, expected 20")
    return report("receiver_hold", bad)


def Tensor0(dt, buffered=False):
    """THE RECEIVER, AS `crp_graph_census-oracle.py` BUILDS IT. Reached through the oracle
    as a MODULE rather than re-spelled here, so the two cannot disagree about what the
    fixture is -- `amd_dsl_census-gate.py`'s `fixtures_hold` for the same reason."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("_crp_oracle", str(ORACLE))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    from tinygrad.tensor import Tensor
    kw = {} if buffered else {"buffer": False}
    return Tensor.zeros(m.SHAPE, dtype=dt, device=m.DEV, **kw)


def frompy_hold() -> bool:
    """EVERY CONSTRUCTOR OF THE PORT'S `O.Const` IS REACHED BY A ROW, AND THE WITNESS IS
    THE LANE'S OWN OUTPUT.

    `ops.bend`'s `type Const is Data:` has FOUR constructors, and `creation.bend`'s
    `cr_from_py` has one arm each for three of them plus a `_`. A census that reached only
    two of them would still print two hundred agreeing rows. So the arms are parsed out of
    `ops.bend` and each one is looked for in a NAMED row's printed value -- `CInvalid` by an
    `iv_` row, `CBool` by the bool-dtype row, `CFloat` by a float-dtype row, `CInt` by an
    int-dtype row. This is the VALUE AXIS made re-decidable rather than a claim about it."""
    arms = re.findall(r"^  (C\w+)\{", re.search(r"^type Const is Data:\n(.*?)(?=^type )",
                                               OPS.read_text(), re.M | re.S).group(1), re.M)
    bd, py = lane_rows("bd.out"), lane_rows("py.rows")
    if bd is None or py is None:
        return report("frompy_hold", ["the promoted lanes are not there"])
    dts = [ALIAS.get(n, n) for n, _, _ in spec_dtypes()]
    witness = {"CInvalid": ("iv_bool", "CONST/0[Invalid:"), "CBool": ("cl_bool", "CONST/0[True:"),
               "CFloat": ("cl_f32", "CONST/0[bits="), "CInt": ("cl_i32", "CONST/0[1:")}
    bad = []
    if sorted(arms) != sorted(witness):
        bad.append(f"O.Const declares {sorted(arms)}, this check witnesses {sorted(witness)}")
    for arm, (row, needle) in witness.items():
        if arm not in arms:
            continue
        for lane, got in (("bd", bd), ("py", py)):
            if needle not in got.get(row, ""):
                bad.append(f"{lane}'s {row} does not hold {arm} ({needle!r} absent)")
    return report("frompy_hold", bad)


def opscast_hold() -> bool:
    """THE (b) TRIAGE, AS A GATE. `grep -c OpsCAST tinybendygrad/mixin/creation.bend` is
    ONE, and this file's brief warned that a tree-wide grep is NOT the answer because most
    of its hits are pattern-matcher arms where an identity fold would be WRONG. MEASURED:
    the one hit is `cr_cast` (creation.bend:217), `DTypeMixin.cast` (dtype.py:36), and
    `cr_cast` DOES fold -- it has a `same` arm. What this check adds is the OTHER half of
    the triage: the fold's ANSWER, which `classes_hold` and `fold_axis_hold` read off the
    lanes. A second `OpsCAST` in this file would be a site nobody triaged, so it is a red
    run rather than a silent addition."""
    src = PORT.read_text()
    hits = [i + 1 for i, l in enumerate(src.splitlines()) if "OpsCAST" in l]
    bad = []
    if len(hits) != 1:
        bad.append(f"creation.bend has {len(hits)} OpsCAST sites at {hits}, expected 1 -- a "
                   f"new one is untriaged")
    else:
        body = re.search(r"^def cr_cast\(.*?(?=^def )", src, re.M | re.S)
        if not body or "OpsCAST" not in body.group(0):
            bad.append(f"the OpsCAST at :{hits[0]} is no longer inside `cr_cast`")
        elif not re.search(r"case True\{\}: t", body.group(0)):
            bad.append("`cr_cast` has no fold arm -- it ALWAYS MINTS, which is class (b) "
                       "unfolds and every `iv_` row would be a finding of a new kind")
    # AND THE FOLD TEST IS `from_py(v) == de` WHERE `de` IS ops.py:630's `dtype` AFTER ITS
    # `b is Invalid` REPLACEMENT. BOTH HALVES ARE CHECKED and the reason is this file's own
    # history: the nineteen rows it reported were a fold on `from_py(v) == dt` -- on the
    # dtype ops.py:630 had already thrown away -- so a check that looked for the `md_dt_eq`
    # alone would have passed on the broken predicate and on the fixed one alike.
    for want, why in (("+de = cr_cast_dt(F.is_cinvalid.val(v), dt)",
                       "ops.py:630's `b is Invalid` dtype REPLACEMENT"),
                      ("cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
                       "the fold test on the dtype the CONST HAS")):
        if want not in src:
            bad.append(f"`cr_const_of` no longer reads {want!r} -- {why} has moved")
    return report("opscast_hold", bad)


def _blob(rev, rel):
    r = subprocess.run(["git", "rev-parse", "--short=8", f"{rev}:{rel}"],
                       capture_output=True, text=True, cwd=str(ROOT))
    return r.stdout.strip() if r.returncode == 0 else f"rc={r.returncode}"


def _at(rev, rel, pat):
    r = subprocess.run(["git", "show", f"{rev}:{rel}"], capture_output=True, text=True,
                       cwd=str(ROOT))
    m = re.search(pat, r.stdout, re.M | re.S) if r.returncode == 0 else None
    return m.group(0) if m else None


def drift_hold() -> bool:
    """SEVEN FILES, THREE BLOBS EACH, AND -- FOR THE TWO THAT HAVE MOVED -- THE BODY OF
    EVERY DEF THE ROWS READ.

    `AGENTS.md` says the PIN is the truthful oracle for a drifted file. TWO files HAVE
    drifted since `ad117c928^` (`helpers.py` 1 insertion, `ops.py` 61+/69-), so a gate
    that only compared blobs would have to declare its own 207 rows untrustworthy. What
    makes them trustworthy is a BODY comparison: `UOp.const`, `UOp.toposort`, `argfix` and
    `prod` are extracted from the pin and from HEAD and compared byte for byte, and they
    are identical. That is re-extracted here on every run, so the claim is a reading rather
    than a sentence somebody wrote once."""
    bad = []
    for rel in VENDORED:
        head, vend, pin = _blob("HEAD", rel), _blob("ad117c928", rel), _blob(PIN, rel)
        if not head.startswith(("rc=", "")):
            bad.append(f"{rel}: HEAD did not resolve")
            continue
        if head == vend == pin:
            continue
        for pat, nm in DRIFTED.get(rel, []):
            a, b = _at(PIN, rel, pat), _at("HEAD", rel, pat)
            if a is None or b is None:
                bad.append(f"{rel} HAS DRIFTED and {nm} could not be read from "
                           f"{'the pin' if a is None else 'HEAD'}")
            elif a != b:
                bad.append(f"{rel} HAS DRIFTED and {nm} CHANGED between {PIN} and HEAD -- "
                           f"the PIN is the truthful oracle for it and these rows were "
                           f"measured against HEAD")
    unlisted = [rel for rel in VENDORED if rel not in DRIFTED
                and not (_blob("HEAD", rel) == _blob(PIN, rel))]
    for rel in unlisted:
        bad.append(f"{rel} HAS DRIFTED and is NOT in DRIFTED -- either add it with the defs "
                   f"the rows read, or say why its drift cannot reach them")
    return report("drift_hold", bad)


# ---------------------------------------------------------------------- the classes
# A declared divergence must still BE its class, in the terms the class is defined by.
def inserted(cpy, port):
    """WHAT THE PORT ADDS TO CPYTHON, or `None` when that is not the relation.

    THE WALK IS OVER THE **PORT'S** LIST, AND THAT IS NOT COSMETIC.
    `decomp_graph_census-gate.py`'s `deleted()` walks CPython's list and can only ever find
    DELETIONS -- its `i` advances unconditionally, so a token CPython does NOT have stalls
    `j` for the rest of the cone and the function answers `None`. MEASURED here: the first
    draft of this check reused it, and all NINETEEN `iv_` rows answered `None` and would
    have reported "the finding is fixed" for every one of them. A port that MINTS A NODE is
    the common direction -- the defect class is named after the minting -- so this walks
    the other list.

    A GREEDY WALK IS NOT THE CLAIM EITHER. "The port's tokens appear in CPython's, in
    order" is true of far more than "the port adds one node", so this REBUILDS the matched
    list and compares it to `cpy` in full: the answer is a witness that the port's row IS
    CPython's row with exactly those tokens inserted, and nothing else moved."""
    ct, pt = cpy.split(","), port.split(",")
    out, extra, i, j = [], [], 0, 0
    while j < len(pt):
        if i < len(ct) and pt[j] == ct[i]:
            out.append(pt[j])
            i += 1
        else:
            extra.append(pt[j])
        j += 1
    return extra if i == len(ct) and out == ct else None


def classes_hold() -> bool:
    """EVERY CLASS'S MEASURED CLAIM, CHECKED ON THE LANES THIS RUN JUST PROMOTED.

    The pins already make a moved row RED; this says WHY each row is allowed to differ, in
    the terms the class is defined by, so a divergence that keeps its text cannot silently
    change what it IS. A gate that only pins differences has forgotten what it is pinning.
    `el_weakint` gets the stronger half: its `eb_` PAIR must now AGREE, because the pair is
    what names the missing bounds as the cause rather than leaving it a guess.

    THE `PROMOTION-FOLD` BRANCH IS KEPT AFTER THE CLASS WAS CLEARED, and `--refresh` can no
    longer produce that name. A pins row that still carries it -- hand-edited, or restored
    from an older revision -- is then checked as ITS class and REDS rather than passing
    unexamined, which is the whole reason this loop re-derives instead of reading the column."""
    cpy, port = lane_rows("py.rows"), lane_rows("bd.out")
    if cpy is None or port is None:
        return report("classes_hold", ["the promoted lanes are not there"])
    bad = []
    for row, (cls, _v) in DIVERGES.items():
        pv, bv = cpy.get(row), port.get(row)
        if cls == "PROMOTION-FOLD":
            extra = inserted(pv, bv) if pv and bv else None
            if extra != ["CAST/1"]:
                bad.append(f"{row} is not CPython's row with exactly one CAST/1 INSERTED "
                           f"({extra}) -- the finding is fixed or the fixture moved; drop "
                           f"the pin, do not leave it here")
        elif cls == "W3-BOUNDS":
            if pv is None or bv is None or pv.replace("ALLOC/0[i32", "ALLOC/0[i64") != bv:
                bad.append(f"{row} is not CPython's row with the ALLOC's i32 -> i64")
            if cpy.get("eb_weakint") != port.get("eb_weakint"):
                bad.append("eb_weakint no longer AGREES -- the pair that names the missing "
                           "vmin/vmax as the cause has been lost, so el_weakint is a shrug")
        else:
            bad.append(f"{row} has no class")
    return report("classes_hold", bad)


def fold_axis_hold() -> bool:
    """THE FOLD SET, MEASURED OFF CPYTHON'S OWN LANE AND NOT READ OFF A COMMENT.

    `ops.py:634` says the `.cast` "folds away at exactly the dtypes a CONST derives
    (bool/weakint/weakfloat)". Over the `f_` family -- `Tensor.full(shape, dt.const(1),
    dtype=dt)` -- the claim is decidable: the root's cone holds a `CAST/1` at every CONCRETE
    dtype and none at those three. MEASURED: 3 of 20 rows carry no `CAST/1` and their
    dtypes are exactly `bool`, `weakint`, `weakfloat`; the other 17 carry exactly one. If
    `UOp.const` changes, this goes red, which is the point of writing the comment down as a
    measurement rather than as prose."""
    py = lane_rows("py.rows")
    if py is None:
        return report("fold_axis_hold", ["the promoted lanes are not there"])
    dts = [ALIAS.get(n, n) for n, _, _ in spec_dtypes()]
    bare = [d for d in dts if "CAST/1" not in py.get(f"f_{d}", "")]
    casty = [d for d in dts if "CAST/1" in py.get(f"f_{d}", "")]
    bad = []
    if sorted(bare) != ["bool", "weakfloat", "weakint"]:
        bad.append(f"CPython folds at {sorted(bare)}, expected ['bool', 'weakfloat', "
                   f"'weakint'] -- ops.py:634's own list, read off a lane")
    if sorted(casty) != sorted(set(dts) - {"bool", "weakfloat", "weakint"}):
        bad.append(f"the casting dtypes are {sorted(casty)}")
    for d in casty:
        if py[f"f_{d}"].count("CAST/1") != 1:
            bad.append(f"f_{d} carries {py[f'f_{d}'].count('CAST/1')} CAST/1, expected 1")
    return report("fold_axis_hold", bad)


def no_noop_bottom() -> bool:
    """`NOOP` IS `Arena.bottom()` -- what `Arena.node` answers for an index the arena does
    not hold -- so a `NOOP` in any cone is an out-of-range index read and always a defect.
    Read off BOTH PORT LANES' own output, because the two defects it catches are the two
    this layer has already had: a stale arena, where the answer is read off the arena
    HANDED IN rather than the one the answer came back in (nine fixes tree-wide), and a
    hash-consed self-loop, which prints a plausible graph. CPython has no `NOOP` to disagree
    with, so this is the only assertion that can see either here."""
    for lane in ("bd.out", "bn.out"):
        f = ART / lane
        if not f.is_file():
            return report("no_noop_bottom", [f"{lane} is not there"])
        for l in _lines(f.read_text()):
            if "=" in l and "NOOP" in l.split("=", 1)[1]:
                print(f"  no_noop_bottom: {lane}: {l.split('=', 1)[0]} reads the BOTTOM",
                      file=sys.stderr)
                return False
    return report("no_noop_bottom", [])


# ===========================================================================
# THE DIVERGENCE POPULATION -- declared in a file beside the gate, PINNED on both sides,
# written by `--refresh` and by nothing else.
# ===========================================================================
def _pins():
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live "
                      f"in git, beside the gate, not in `gates/artifacts/` (which "
                      f"`gatekit` empties). Run --refresh.")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 4:
            return None, f"{PINS.name}: a line is not row<TAB>class<TAB>oracle<TAB>port: {ln!r}"
        row, cls, py_v, port_v = parts
        pins[row] = (cls, (f"{row}={py_v}", f"{row}={port_v}"))
    return pins, ""


DIVERGES, WHY = _pins()

# A divergence needs a CLASS before it can be pinned, or the pins file grows a difference
# nobody has explained. `--refresh` REFUSES to pin a row that lands in none of these.
CLASSES = [
    ("UNEXPLAINED", r"^.*$",
     "NO CLASS. A row that differs and matches none of these is a real divergence with no "
     "reason attached; `--refresh` refuses to pin it rather than record a difference nobody "
     "has looked at."),
    ("W3-BOUNDS", r"^el_weakint$",
     "creation.bend's W3, with a consequence rather than a refusal. `commit_dtype` "
     "(dtype.py:16) reads `self._uop.vmin`/`vmax`, which Python can compute and this port "
     "cannot, so `cr_empty_like` takes them as `Maybe`s. With `None{}` for both the ladder "
     "lands on i64; with `Some{0}` -- which is what `UOp._min_max`'s CONST arm (ops.py:1160) "
     "returns for the receiver's `0` -- it lands on i32 and AGREES. The `eb_` family is the "
     "second half of the pair and `classes_hold` refuses the pin without it."),
]
# `PROMOTION-FOLD` WAS HERE AND ITS NINETEEN ROWS ARE GONE. `cr_const_of` folded on
# `from_py(v) == dt` -- the CALLER's dtype, the one `ops.py:630` has already REPLACED with
# `from_py(b)` when `b is Invalid` -- so for `Invalid` the test was `bool == dt`, true at one
# dtype of twenty, and the port minted a `CAST/1` at the other nineteen. `cr_const_of` now
# folds on the dtype the CONST HAS (see `opscast_hold`, which checks both halves of the new
# predicate) and all twenty `iv_` rows agree with CPython. THE CLASS IS NOT RE-DECLARED HERE:
# a `iv_` row that diverges again lands in no class, and `--refresh` REFUSES to pin it, which
# is the reading that a cleared defect coming back is a NEW finding rather than a stale pin.


def _header(n_div, n_same, rows):
    return "\n".join([
        "# crp_graph_census-pins.rows -- GENERATED by `crp_graph_census-gate.py --refresh`,",
        "# which is its ONLY writer. One TAB-separated QUAD per declared divergence:",
        "# `<row>\\t<class>\\t<CPython's value>\\t<the port's value>`.",
        "#",
        f"# {n_div} DIVERGENCES of {rows} ROWS, {n_same} OF WHICH AGREE EXACTLY. Git-resident",
        "# and beside the gate because `AGENTS.md`'s rule is that a gate's required inputs",
        "# live in git and not in `gates/artifacts/`: `gatekit` EMPTIES that directory",
        "# before it runs and UNLINKS what it staged when the run was not green, so a",
        "# divergence list read from there is destroyed by the first red run and there is",
        "# then nothing left to edit.",
        "#",
        "# THE CLASS COLUMN IS NOT DECORATION. `classes_hold()` re-derives each row's class",
        "# from the lanes on every run -- a W3-BOUNDS row must be CPython's with the ALLOC's",
        "# width changed AND its `eb_` pair still agreeing -- so a pinned row that stops being",
        "# its class is a red run rather than a stale sentence.",
        "#",
        "# THE CLASS THAT IS NOT HERE IS `PROMOTION-FOLD`, AND ITS NINETEEN `iv_` ROWS ARE",
        "# GONE. `cr_const_of` folded on `from_py(v) == dt` -- the CALLER's dtype, the one",
        "# `ops.py:630` has already REPLACED with `from_py(b)` when `b is Invalid` -- so for",
        "# `Invalid` the test was `bool == dt`: true at ONE dtype of twenty (`iv_bool`, which",
        "# agreed and made the disagreement look narrow) and a minted `CAST/1` at the other",
        "# nineteen. `cr_const_of` now folds on the dtype the CONST HAS, `iv_bool` no longer",
        "# agrees by accident, and all twenty `iv_` rows match CPython byte for byte. THE",
        "# CLASS IS NOT RE-DECLARED: an `iv_` row that diverges again lands in no class and",
        "# `--refresh` REFUSES to pin it, because a cleared defect that COMES BACK is a new",
        "# finding and not a stale pin. `opscast_hold()` checks both halves of the new",
        "# predicate on every run, so the fix cannot silently un-fix itself either.",
        "#",
        "# A ZERO-LENGTH FILE IS NOT A MISSING ONE. `_pins()` answers REFUSED for a missing",
        "# file and an empty dict for an empty one, and only the second is a verdict.",
        "#",
    ])


def refresh() -> int:
    """REWRITE `crp_graph_census-pins.rows` from a fresh pair of lanes. Its only writer.

    It does NOT go through `Gate.run()`, because a refresh is exactly what a run cannot do
    when the pins are wrong: the whole point is to replace them. A row that disagrees and
    lands in NO declared class is REFUSED rather than pinned -- a pins file that grows a
    difference nobody has looked at is a weakened instrument wearing a gate's clothes."""
    lanes = {}
    for tag, argv in (("py", [str(PY), str(ORACLE)]), ("bd", [str(BEND), str(DRIVER)])):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode != 0:
            print(f"--refresh: lane {tag} failed rc={r.returncode}: "
                  f"{(r.stderr or '').strip()[:200]}", file=sys.stderr)
            return 1
        lanes[tag] = {l.split("=", 1)[0]: l.split("=", 1)[1]
                      for l in _lines(r.stdout) if "=" in l}
    want = expected_rows()
    if len(lanes["py"]) != len(want) or len(lanes["bd"]) != len(want):
        print(f"--refresh: the lanes hold {len(lanes['py'])} and {len(lanes['bd'])} rows, the "
              f"discovered population is {len(want)}", file=sys.stderr)
        return 1
    rows, unknown = [], []
    for row in want:
        if lanes["py"][row] == lanes["bd"][row]:
            continue
        cls = next((c for c, pat, _ in CLASSES if c != "UNEXPLAINED" and re.search(pat, row)),
                   None)
        if cls is None:
            unknown.append(row)
            continue
        rows.append((cls, row, lanes["py"][row], lanes["bd"][row]))
    if unknown:
        print(f"--refresh: no class for {unknown} -- declare one before refreshing, or a new "
              f"divergence is pinned with no reason", file=sys.stderr)
        return 1
    out = [_header(len(rows), len(want) - len(rows), len(want)), ""]
    last = None
    for cls, row, pv, bv in rows:
        if cls != last:
            why = next(w for c, _, w in CLASSES if c == cls)
            out.append(f"# {cls} -- {sum(1 for r in rows if r[0] == cls)} rows. {why}")
            out.append("")
            last = cls
        out.append(f"{row}\t{cls}\t{pv}\t{bv}")
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, "
          f"{len(want) - len(rows)} exact matches")
    return 0


if "--refresh" in sys.argv:
    sys.exit(refresh())
if DIVERGES is None:
    print(f"crp_graph_census-gate: REFUSED, NOT A VERDICT: {WHY}", file=sys.stderr)
    sys.exit(REFUSED)

ROWS = len(expected_rows())
GATE = Gate(
    "crp_graph_census-gate",
    bend="crp_graph_census.bend",
    oracle="crp_graph_census-oracle.py",
    rows=ROWS,
    compared=ROWS - len(DIVERGES),
    diverges={r: v for r, (_c, v) in DIVERGES.items()},
)

CHECKS = (names_hold, methods_hold, dtypes_hold, receiver_hold, frompy_hold, opscast_hold,
          drift_hold, classes_hold, fold_axis_hold, no_noop_bottom)

# THE `iv_` FAMILY, DISCOVERED from the row population and NOT TYPED. `cr_cast_dt` cleared
# every one of these twenty rows, and the verdict below counts them from here so the number
# it quotes and the number of rows the driver prints cannot come to disagree.
CLEARED = [r for r in expected_rows() if r.startswith("iv_")]


def checks_hold() -> bool:
    ok = True
    for fn in CHECKS:
        ok = fn() and ok
    return ok


if __name__ == "__main__":
    sys.exit(gate(GATE, f"crp_graph_census-gate: {ROWS} rows ({FAMS} dtype families x 20 "
                        f"dtypes + {SHFAMS} shape families x {SHAPES} shapes + {TAIL}), 3 "
                        f"lanes, {ROWS - len(DIVERGES)} deep cones match CPython byte for "
                        f"byte and {len(DIVERGES)} are DECLARED -- "
                        f"{sum(1 for c, _ in DIVERGES.values() if c == 'W3-BOUNDS')} is W3's "
                        f"missing vmin/vmax and NOTHING is the class-(b) NEVER-FOLDING CAST, "
                        f"whose {len(CLEARED)} `iv_` rows `cr_const_dt` cleared; the ten census "
                        f"METHODS are the intersection of "
                        f"creation.bend's cr_* names and creation.py's (self|cls names; the "
                        f"fold set is measured at bool/weakint/weakfloat; no lane reads the "
                        f"NOOP bottom",
                  checks=checks_hold))

# ===========================================================================
# THE MUTATION TABLE. Three one-token edits to `creation.bend`, each applied, each run, each
# reverted from a byte snapshot, and the snapshot's sha256 checked BEFORE and AFTER. A GATE
# NEVER SEEN TO FAIL IS NOT A GATE, and the three below are chosen so that each one moves a
# DIFFERENT class of row -- a fold, an arena, and the finding this census is reporting.
#
#   BASELINE  sha256 f545039d70509e87b0d455b48068be76e884452a274fa16cb17c6408a4b2c5df
#             git hash-object 2610114301c7e78ed87b3d4773e8adf82f3b03cb
#   ... WHICH IS THE PRE-FIX `creation.bend`, AND EVERY RESTORE BELOW WAS BYTE-IDENTICAL TO
#   IT. The file has MOVED since: `cr_cast_dt` + `cr_const_of` are the fix (see FINDING 1)
#   and the three mutations below were measured against the pre-fix bytes. `opscast_hold`
#   re-reads the source on every run, so the moving baseline is checked rather than trusted.
#
#   M0  THE FINDING ITSELF, INVERTED -- `cr_cast_dt`'s `case True{}` answers `dt` where
#       `ops.py:630` replaces it, which is the pre-fix predicate written out loud.
#       RED rc=1 with the nineteen `iv_` pins IN PLACE, naming `iv_void`; GREEN once they
#       are dropped. That pair IS the mutation: the pins were the mutation.
#
#   M1  `cr_const_of` folds ALWAYS -- `cr_cast(D.md_dt_eq(c0, de), ...)` becomes
#       `cr_cast(True{}, ...)` (creation.bend). The fold predicate INVERTED: every
#       concrete dtype now answers a BARE CONST where CPython builds the CAST.
#       RED rc=1. `DISAGREE (bd)` names `zl_void` and `zl_i8`, and the census moves from
#       187 to ... the gate stops at the FIRST two disagreements (`gatekit`'s `bad[:2]`),
#       which is the tree's own known limit and the reason `classes_hold` and `fold_axis_hold`
#       exist as SEPARATE reads rather than as part of the diff.
#
#   M2  `cr_after` builds the AFTER in `O.Arena.empty()` instead of in the STORE's arena
#       (creation.bend:252-254) -- the stale arena, defect class (a), the one this layer was
#       called highest-risk for. `mixin/op.bend`'s `mo_bin` and `tensor.bend`'s `tn_binop`
#       were both fixed for exactly this shape.
#       RED rc=1, AND THE PORT PRINTS THE SIGNATURE OF THE DEFECT: `zl_void=NOOP/0,NOOP/0`.
#       `NOOP` is `Arena.bottom()` -- what `Arena.node` answers for an index the arena does
#       not hold -- so the AFTER names two nodes the fresh arena does not have and the whole
#       cone collapses to the bottom. A `--check-only`-clean file, a plausible run, and a
#       gate that is RED: that is what the instrument is for.
#       (The FIRST attempt at M2 inlined the STORE instead of moving the arena, and did not
#       typecheck: `expected : U32 / observed : O.Found` at `cr_after`. The gate reported
#       `REFUSED`, exit 3 -- "a precondition was absent" -- which is `gatekit`'s own verdict
#       for a substrate that cannot be checked and is a demonstration that the five exits
#       are five. It is recorded because a mutation that cannot compile is not evidence
#       either way and the honest reading of it is "the experiment did not run".)
#
#   M3  `cr_from_py`'s `CInvalid` arm answers `S.weakint()` instead of `S.boolean()`
#       (creation.bend:191) -- one arm, one word. This was the mutation that said the whole
#       nineteen-row finding hung on ONE arm: `iv_bool` was the ONE `iv_` dtype that agreed,
#       and M3 moved it, because `from_py(Invalid)` is what both the fold predicate AND the
#       printed derived dtype read.
#       RED rc=1, `DISAGREE (bd)` names `iv_bool` and shows both halves at once --
#       `CONST/0[Invalid:bool],EXPAND/2` on CPython's side and
#       `CONST/0[Invalid:weakint],CAST/1,EXPAND/2` on the port's. One mutation, the dtype
#       AND the fold, which is the same pair the nineteen pins carried. AFTER THE FIX M3 IS
#       STILL RED AND NOW NAMES THE DERIVED DTYPE ALONE -- `cr_cast_dt`'s `True{}` arm is
#       `cr_from_py(O.CInvalid{})`, so breaking that arm breaks the dtype, the fold and
#       nothing else, and the two halves of the finding are no longer the same edit.
#
# EVERY RESTORE WAS BYTE-IDENTICAL: `shasum -a 256` is
# `f545039d70509e87b0d455b48068be76e884452a274fa16cb17c6408a4b2c5df` and `git hash-object` is
# `2610114301c7e78ed87b3d4773e8adf82f3b03cb` before the first mutation and after the third,
# and `git diff HEAD -- tinybendygrad/mixin/creation.bend` is EMPTY.
# ===========================================================================
# ===========================================================================
# THE FINDINGS, AND WHAT WAS DONE ABOUT THEM. `tinygrad/` IS LEFT BYTE-IDENTICAL.
# `tinybendygrad/mixin/creation.bend` IS NOT: finding 1 is FIXED in it and it is the ONLY
# file this revision touches on the port side.
#
# FINDING 1 -- FIXED. `cr_cast`'s FOLD PREDICATE WAS THE CALLER'S DTYPE, AND FOR `Invalid`
# CPYTHON'S IS NOT. `UOp.const` (ops.py:629-637, BYTE-IDENTICAL between `ad117c928^` and
# HEAD) is
#
#     if dtype is None or b is Invalid: dtype = dtypes.from_py(b)     # ops.py:630
#     ...
#     return UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)   # ops.py:637
#
# and `.cast` folds iff the CONST's DERIVED dtype equals its target (ops.py:634's own
# comment). `DType.const` returns `val` UNCHANGED for `InvalidType` (dtype.py:80), so
# `dt.const(Invalid) is Invalid` at EVERY dt, whose derived dtype is `bool` (ops.py:185) --
# and `dtype` has just been REPLACED by `from_py(Invalid) = bool`. So the fold test is
# `bool == bool`: TRUE at every dtype. `cr_const_of` folded instead on
#
#     cr_cast(D.md_dt_eq(c0, dt), T.tn_const(ar, v), dt)     with c0 = cr_from_py(v)
#
# i.e. `from_py(v) == dt`, comparing the CALLER'S `dt` -- the one ops.py:630 replaced.
# MEASURED BEFORE, over this census's own twenty dtypes:
#
#     iv_bool      py  ...CONST/0[Invalid:bool],EXPAND/2,      bd ...CONST/0[Invalid:bool],EXPAND/2,          AGREE
#     iv_i32       py  ...CONST/0[Invalid:bool],EXPAND/2,      bd ...CONST/0[Invalid:bool],CAST/1,EXPAND/2,    +1 CAST
#     iv_weakfloat py  ...CONST/0[Invalid:bool],EXPAND/2,      bd ...CONST/0[Invalid:bool],CAST/1,EXPAND/2,    +1 CAST
#     ... 19 of 20 differ, every one by EXACTLY one `CAST/1`, verified by `deleted()`.
#
# `iv_bool` was the cell where `from_py(v) == dt` HAPPENED to be true, and it is what made
# the disagreement look narrow. THE FIRST DRAFT OF THIS REPORT SAID "THE FIX IS NOT IN
# `creation.bend`", on the grounds that the replacement happens in the CALLER. THAT WAS
# WRONG, AND IT WAS WRONG IN THE DIRECTION THAT KEEPS A DEFECT: `cr_const_of` is not a
# callee of `UOp.const`, it IS `UOp.const` (creation.bend's own header says so), so there is
# no caller between it and the line it has to fold on. What the port cannot see is not
# THAT `dt` was replaced -- it is only ever handed one `dt` and has to answer ops.py:630's
# `dtype` ITSELF. So the fix is ops.py:630, transcribed:
#
#     def cr_cast_dt.of(isinv: Bool, dt: S.Dt) -> S.Dt:
#       match isinv:
#         case True{}: cr_from_py(O.CInvalid{})     # ops.py:630 REPLACES dt
#         case _:       dt
#
#     +de = cr_cast_dt(F.is_cinvalid.val(v), dt)
#     cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)
#
# `is_cinvalid.val` is `uop/fold.bend`'s EXISTING `O.Const` test (fold.bend:2385), not a new
# one, and `F` was already imported. `de` is what `.cast` is handed, so the fold test and
# the CAST's `ADt` arg can no longer disagree with each other -- which is the same shape as
# `wk_cast_at`/`cast_at`, where the source dtype is read off a FOLD. MEASURED AFTER, over the
# same twenty dtypes: 20 of 20 `iv_` rows AGREE, `el_weakint` is the only divergence left in
# 207, and no other row moved -- `f_`, `z_`, `zl_`, `ol_`, `cl_`, `eb_`, `ne_`, `fs_`, `nb_`
# and the seven tail rows are byte-identical to what they were, because for a NON-`Invalid`
# value `de` IS `dt` and the predicate is the old one. The fix moves the `Invalid` arm and
# nothing else.
#
# WHAT MADE THIS THE THIRD OF ITS CLASS, and the two before it are the reason the
# instruction "fold on the dtype the CONST ACTUALLY HAS" was the right shape to reach for:
# `renderer/amd/dsl.bend`'s `src_bit.vdst` compared `"vdst"` WITH ITSELF and so took its arm
# for every input, and `tensor.bend`'s `tn_logical_not` used the raw `O.UOp.cast`, which
# always mints, where `D.cast_at` folds. A literal compared with itself and a predicate read
# off the wrong value are the same mistake: the comparison is TRUE for a reason nobody
# chose, and it is true at exactly the wrong places.
#
# FINDING 2 -- `el_weakint`'s ALLOC IS `i64` WHERE CPYTHON'S IS `i32`, AND ITS PAIR IS WHAT
# NAMES THE CAUSE. `cr_empty_like` is handed `m`/`m2` as `Maybe<&1, H.I64>` because
# `commit_dtype` (dtype.py:16) reads `self._uop.vmin`/`vmax` off the receiver and this port
# has no `UOp._min_max` (creation.bend's W3). With `None{}` for both the ladder lands on the
# widest rung. The `eb` family is the SAME call with `Some{0}` for both, which is what
# `UOp._min_max`'s CONST arm (ops.py:1160) returns for `rx(weakint)`'s `0`:
#
#     el_weakint   py  ALLOC/0[i32 sz=6 ...]      bd  ALLOC/0[i64 sz=6 ...]      DIFFER
#     eb_weakint   py  ALLOC/0[i32 sz=6 ...]      bd  ALLOC/0[i32 sz=6 ...]      AGREE
#
# so `D.commit_dtype` is CLEARED and the two missing bounds are the cause. That is a buffer
# TWICE THE WIDTH, so it is a wrong graph and not a refusal. The fix is that `cr_empty_like`
# should derive the bounds the way `cr_full` does -- from the value it is handed -- and the
# reason it cannot is W3, not `commit_dtype`. REPORTED; `creation.bend` is unchanged HERE.
#
# WHAT WAS RULED OUT, BY MEASUREMENT RATHER THAN BY ARGUMENT:
#   * NOT THE ORACLE'S RECEIVER. `Tensor.zeros(shape, dtype=dt)` is not a `dt` tensor --
#     MEASURED, at `weakint` it is `i32` -- so the first draft of this oracle used it and
#     `cl_weakint` came out carrying a `CAST/1` where a real weakint receiver has none. The
#     receiver is `buffer=False` and `receiver_hold()` checks both halves every run. That is
#     `tn_bitwise_not`'s post-mortem and `decomp_graph_census`'s, in this file's own fixture.
#   * NOT THE TRUNCATION. `DType.const` truncates (`42.7` at `i32` is `42`, and `42.7` at
#     `f16` is `42.6875`), and transcribing that into a fixture would be asserting the
#     oracle's own reading of dtype.py -- so the VALUE comes from `dt.const(1)`, the real
#     method, on one side and `cr_cval1`, the port's own arms, on the other. The one place
#     this DID bite is recorded below.
#   * NOT A FIXTURE THAT FEEDS CPYTHON'S RAW `1` TO THE PORT. `cv1(dt)` is
#     `cr_cval1(is_bool(dt), is_float(dt))` and `dt.const(1)` is `DType.const`'s three arms,
#     so the two CAN differ and comparing them is the measurement that tells a real defect
#     from a fixture artefact. MEASURED, TWICE AND FROM BOTH SIDES, over all twenty dtypes:
#     the `f_<dtype>` FILL CONST is byte-identical on both lanes at every one of them --
#     `CONST/0[1:weakint]` at the eighteen int/void dtypes, `CONST/0[True:bool]` at `bool`,
#     and `CONST/0[bits=1065353216:weakfloat]` at the nine float dtypes -- and
#     `.venv/bin/python` on `dtypes.<n>.const(1)` prints the same twenty values. So `cv1`
#     IS `dt.const(1)` here, `creation.bend`'s post-truncation contract (`fill_value`
#     arrives AFTER `dtype.const`) makes the predicates identical, and the nineteen `iv_`
#     rows were never a fixture artefact. This is measured BEFORE any change was made,
#     because the census author nearly published twenty-one PHANTOM findings by assuming it.
#   * NOT THE PRINTER. Thirty rows moved on `H.f32_show(0.0)` being `"0"` where `repr(0.0)`
#     is `"0.0"`. Printing the IEEE-754 pattern instead (`F32.bits` is a law, base.bend:31)
#     took the rows to 187/207 with no formatter in the comparison, and `0.0`, `-0.0` and a
#     NaN payload are three tokens rather than one.
#   * NOT A STALE ARENA. `no_noop_bottom` reads both port lanes and finds none, and
#     `in_selfref`/`in_selfref_a` are rows rather than claims: `full`'s root is
#     `AFTER(ret, STORE(ret, val))` and an answer read off the arena HANDED IN would make
#     `AFTER.srcs` contain `AFTER`. Neither holds.
#
# A FIXTURE DEFECT THE VALUE AXIS CAUGHT, WHICH IS THE POINT OF THE AXIS. The first draft of
# the shape families passed `O.CInt{1}` to `cr_full` at `dtype=f32`, on the reasoning that
# `Tensor.full(shape, 1, dtype=float32)` passes the int `1`. It does pass an int -- to
# `DType.const`, which wraps it: `ConstFloat(truncate[f32](1.0))` (dtype.py:84). So CPython's
# CONST holds the FLOAT and the port's must too. MEASURED, that mistake moved all EIGHT
# `fs`/`nb` rows and `O.Rng.sig` CANNOT SEE IT, because both sides then print `CONST/0`
# followed by a `CAST/1` and nothing about the CONST's ARG is in a 4-field prefix. The deep
# printer found it in one run. A fixture that varies the VALUE is what found a fixture bug.
#
# WHAT THIS CENSUS CANNOT SEE, NAMED BECAUSE IT IS WHAT WOULD LET THE NEXT ONE LIVE.
#   * `DType.const`'s TRUNCATION is a P3 wall (creation.bend's TODO(p3) on dtype.py:84), so
#     every `full`/`zeros`/`ones` row is handed an already-truncated value and this census
#     CANNOT catch a port that mis-truncates -- it can only catch a FIXTURE that does, which
#     is what it just did once. `creation.bend`'s own `main` has a `TODO(p3)` row for it.
#     THE `iv_` FAMILY IS NOT BEHIND THAT WALL. `DType.const` returns `Invalid` UNCHANGED
#     (dtype.py:80), so nothing is truncated on the nineteen rows finding 1 was about, and
#     `opscast_hold` checks the predicate's spelling rather than trusting a row.
#   * `_multi_like` (creation.py:16) is W2 and has NO def, so `full_like`'s multi-device arm
#     (creation.py:102-104) is not censused. `cpy_only_methods()` NAMES it on every run
#     rather than letting its absence read as agreement.
#   * `argfix`'s REJECT (`empty((2,3), 4)` raises, creation.py:24) has no Bend form
#     (creation.bend's fact 6) and so has no row.
#   * `ParamArg.slot` is NOT printed. It is `next(UOp.unique_num)` and is covered by
#     `in_full`/`in_empty`/`in_diff` instead -- a count, which is what can see it.
# ===========================================================================