#!/usr/bin/env python3
"""rand_census-gate.py -- THE CENSUS for `tinybendygrad/mixin/rand.bend`, layer 3 of 3.

    .venv/bin/python gates/rand_census-gate.py        # 32 rows compared, 4 pinned, 19 port-only
    .venv/bin/python gates/rand_census-gate.py --plant

THIS LAYER HAD A GATE AND IT IS GONE. `mixin/rand.bend`'s header names the runner:

    #   sh $ORACLE_DIR/rd-gate.sh
    #   .venv/bin/python $ORACLE_DIR/rd-truth.py                  > /tmp/py.txt

`$ORACLE_DIR` is `.agents/slop/`, and MEASURED today: `rd-truth.py` is ABSENT, `rd-gate.sh` is
ABSENT, `rd-mutate.py` is ABSENT, and `git log --all -- .agents/slop/rd-truth.py` is EMPTY --
none of the three was ever committed. So the file's own "GATE STATUS, MEASURED 2026-10-02:
**RED** ... 31 of 49 shared rows match and 18 do not" cannot be re-taken, and the 31 green rows
had no instrument to produce them -- and that status line is GONE from `mixin/rand.bend`
now, because THIS gate prints one that IS re-takeable. `AGENTS.md` names this exact failure -- "a gate whose inputs
live somewhere the tree is clearing is a gate with a shelf life" -- and this is the instance.
The only surviving gate on this layer is `gates/rd_graph_census-gate.py`, which is FOUR rows
over `_threefry_random_bits` (`p64`, `x`, `three`, `tfb`) and 184 of this file's 188 defs
untouched. 188 is `grep -c "^def " tinybendygrad/mixin/rand.bend`.

WHAT THIS GATE COVERS, AND WHAT IT CANNOT, AS NUMBERS. 55 rows in the port's lane:

  32 COMPARED against CPython. Every `ref_*` predicate row: `dtypes.floats` membership,
         `rand`'s `low < high`, `normal`'s `std >= 0`, `randint`'s `all_int`, `dropout`'s
         `0 <= p <= 1` over FOUR fixtures including both boundaries, `multinomial`'s
         `1 <= ndim <= 2 and num_samples > 0` and its `replacement or ...`, the third
         `least_upper_dtype` arity at `mixin/rand.py:319`, and `_bits_to_rand`'s
         `bitsize - nmant`, `bitcast(1.0, ...)`, the `uint_dtype` table and
         `ceildiv(prod(shape)*itemsize, 4)`. TWENTY-EIGHT OF THE THIRTY-TWO ARE THOSE
         PREDICATES AND ALL TWENTY-EIGHT MATCH BYTE-FOR-BYTE.
    4 `st_*_v` COUNTER VALUES -- `Tensor._next_counter`'s OWN returned `low.cat(high)`,
         realised, against a stored counter this oracle sets to the fixture. THESE ARE THE
         WITNESS for the generator state and they were RED until the port grew the write;
         see THE FIX below. `st_wrap_v`'s counter is `[0xFFFFFFFF, 0]` and its `num` is 6, so
         `new_low` WRAPS and both halves of tensor.py:467/470's borrow comparison are True --
         which `st_after` could never be, because its counter is an ALLOC and no CONSTANT ever
         reaches a graph row.
   4 DECLARED DIVERGENCES, pinned on BOTH sides: `st_zero_g`, `st_six_g`, `st_after_g`,
         `st_max_g`. See THE FINDING below. A pinned divergence is not a hidden defect: if
         either side moves, `gatekit` fails on the pin, so the fix and the regression are the
         same event. THEY ARE RED BECAUSE `O.Arena` IS AFFINE AND THE PORT FILE IS NOT
         THREADED (the file's own R1), NOT because of ANY SEMANTIC DISAGREEMENT: with the
         write ported the four `_v` rows agree, and `_v` is the half that can see a value.
  19 PORT-ONLY, and their ABSENCE from the oracle is asserted by the derived oracle row count
         (`55 - 19 = 36`). They are the fifteen `*_g`/`*_d`/`*_np` graph rows -- `op_arange`,
         `rd_tfb`, `rd_bits`, `rd_btr`, `rd_rand`, `rd_rand_like` over an INJECTED counter, a
         parameterisation CPython does not offer -- and `ref_drop_arm0/1/2`, an ORDINAL of a
         three-way arm selector where CPython has three branches and no ordinal. NAMED, NOT
         DROPPED: a port-only row whose oracle row grew by one would fail the count, which is
         what stops the exclusion from hiding a real comparison.

THE FINDING, AND IT IS THE PORT'S, NOT UPSTREAM'S -- AND IT IS FIXED. `mixin/rand.bend`'s
header used to say:

    # `counter.assign(...)` (tensor.py:468) is NOT ported: it is nine nodes that exist
    # only to write a counter back to a device, so `rd_next` returns the same
    # `low.cat(high)` and drops the store.

**THE REASON WAS WRONG, AND THE CLAIM "THE SAME `low.cat(high)`" WAS FALSE.** `assign` is not a
write-only side effect: it REBINDS the counter's `UOp` to the `AFTER` node it builds, and
`tinygrad/tensor.py:469-470` reads `counter[0:1]` and `counter[1:2]` AFTER that line. MEASURED
on this tree:

    before  _next_counter("PYTHON", 6)   counter.uop.op == BUFFER
    after   _next_counter("PYTHON", 6)   counter.uop.op == AFTER, value [6, 0]
    returned                                  [0, 0]
    the PRE-assign reading the port modelled    [4294967290, 0]

So the port's `rd_next` WAS `_next_counter` with the `assign` REMOVED, and removing it changes
the value, not only the node count. THE FIX IS LANDED: `rd_next.stored` is the rebound counter,
`rd_next.lo`/`cmp2`/`hi2` read IT instead of the injected one, and the four `st_*_g` pins are
re-taken at 26/27/47/24 nodes against CPython's 30/32/44/32.

WHY IT TOOK A WITNESS, AND WHAT THE WITNESS COST. The four graph rows could not see it and the
measurement is the whole argument: with the fix REVERTED, `st_zero_g`..`st_max_g` are
13/14/24/13 -- BYTE-IDENTICAL to the pins this gate carried before the fix, so every pinned
divergence in this file was GREEN on a port that returned the wrong number. `num` reaches
`_next_counter`'s graph only as CONSTANTS, so reading the counter before the write and after it
differ by `num` in every returned WORD and in NO NODE. The four `_v` rows, with the witness
transcribed against the port as it stood, read (port against CPython):

    st_zero_v  0:0             vs  0:0             agree   -- the CONTROL, num = 0
    st_six_v   4294967295:4294967290  vs  0:0      DISAGREE
    st_wrap_v  0:4294967289    vs  0:4294967295    DISAGREE  -- and this is the BORROW
    st_max_v   4294967295:1     vs  0:0             DISAGREE

SO THE WITNESS IS HALF A WITNESS, AND THE HALF IS NAMED RATHER THAN LEFT. The port's side of
each `_v` row is `rd_next.v`, a host `H.I64` model of the SAME five lines over a counter that
has a value, and it reads no Tensor. MEASURED: reverting ONLY the tensor `rd_next` -- leaving
`rd_next.v` alone -- moved 4 of 55 rows and NONE of them was a `_v` row. The cause is a
separate def, and it is the same shape as `gates/tn_bitwise_not-oracle.py`'s, so it is written
down instead of relied on.

AND THE WITNESS IS BLIND TO `num`, WHICH IS NOT A GAP BUT THE ALGEBRA. `_next_counter` RETURNS
THE COUNTER: `low = (ctr0 + m) - m = ctr0`, and
`high = (ctr1 + h + (nl < ctr0)) - h - (nl < m)` where the two borrows are the same
comparison, so `m = num & 0xffffffff` and `h32 = num >> 32` both CANCEL. MEASURED: M1
(`rd_mask`'s mask dropped, `n -> n - 1`) moves 2 rows -- `st_zero_g` and `st_max_g` -- and NONE
of the four `_v` rows, even though `rd_next.v` CALLS the same `rd_mask` the tensor form does.
A value row that moved on `num` would be pinning something CPython says does not exist. THE
SPLIT IS THEREFORE: the `_v` rows pin the five lines' ALGEBRA (WHICH counter the reads come
off) and the `_g` rows pin `num`'s ARRIVAL (WHICH constants and nodes are built), and neither
one alone is the method.

THE OTHER FINDING IS A PIN THAT DID NOT MOVE. `oracles/tinybendygrad_mixin_rand.bend.rows` is a
frozen snapshot of this layer's oracle output and it was 19 OF 51 ROWS STALE against HEAD.
Four of those (`ref_sdpa_dt`, `ref_uint_dt_f32`, `rand23_d`, `ctrl_rand_d`, `rand_like23_d`)
are the `DType.name` rename from tinygrad `793abbb16`; the other fifteen are graph rows that
moved because the PORT moved after the freeze -- `st_zero_g` from `2 ... srcops=STACK|STACK
topo=CONST/0 CAST/1` (a toposort of ONE data node, i.e. not a graph at all, the header's R1) to
`13 ... topo=ALLOC/0 ... ADD/2 STACK/2 RESHAPE/2`, and `arange3_g` from 28 nodes to 26. So the
frozen file predates the arena-threading fix, and the fix above moves `st_zero_g` again (to 26)
-- so it is now STALE BY MORE, at 23 OF 55. IT IS LEFT ALONE -- `oracles/` is not in this
unit's grant, and `differ.declared()` does not name it (MEASURED: `len(differ.declared())` is
176, and neither this file nor `oracles/tinybendygrad_nn_onnx.bend.rows` is in it), so nothing
in the tree regenerates or checks either one. THAT IS A REPORT ITEM.

DRIFT, PINNED IN CODE. Four blobs: `tinygrad/mixin/rand.py` (the oracle's subject),
`tinygrad/tensor.py` (`_next_counter` AND `Tensor.__len__`-adjacent shapes),
`tinygrad/dtype.py` (`ref_uint_dt_f32` is a `DType.name`, and that is the one that MOVED), and
this gate's own oracle.

EXIT STATUS: 0 lanes agree on all 32 compared rows and every pin is intact · 1 a lane
disagreed, a pin moved, or the population/class census failed · 3 a precondition was absent ·
5 a lane emitted nothing.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, oracle_drift
from state_census import (class_census as _class_census, lanes, plant as _plant,
                          row_population as _row_population)

DRIVER = "tinybendygrad/mixin/rand.bend"   # THE PORT FILE IS THE DRIVER: `main` is 55 rows
ORACLE = "rand_census-oracle.py"
PORT = "tinybendygrad/mixin/rand.bend"
ROOT = Path(__file__).resolve().parent.parent

# `tinygrad/dtype.py` and `tinygrad/tensor.py` MOVED WITH THE DELIBERATE RE-VENDOR TO
# upstream `002630241` (2026-10-16) -- not drift to restore. `tinygrad/mixin/rand.py` did
# not change. See `gates/onnx_census-gate.py:DRIFT_PIN` for why this pin moved.
DRIFT_PIN = {
  "tinygrad/mixin/rand.py":
    "19623f666365a318b6730123dd0fad27469ced754740415b86563ce0857c0363",
  "tinygrad/tensor.py":
    "5680ec3b2a716e435ae8f8ca42f39697ed46de7a3d50018a7becb9a368bcc56d",
  "tinygrad/dtype.py":
    "7800592dcccbdd5a5beaee889342b5f62790d37445938fe601416c8b76057926",
  "gates/rand_census-oracle.py": "ee782a0ef7107341f9dc2857823f49ed63359bd1c72018ea6f97b8ac4376b92c",
}

# THE FOUR `st_*` ROWS, PINNED ON BOTH SIDES. The PORT side is measured from
# `./bin/bend tinybendygrad/mixin/rand.bend` and the CPython side from
# `gates/rand_census-oracle.py`; NEITHER is transcribed here, because a transcribed pin is a
# pin that agrees with whatever was copied out of the lane it was meant to check. Both were
# captured from the two lanes on 2026-10-16 and are reproduced in the commit message.
# THE PINS ARE WHOLE LINES, NOT VALUES. `gatekit` tests `want not in raw[lane]` against
# the lane's LINES, so a value without its `row=` prefix can never match and the first
# run of this gate reported `py's st_zero_g is not '30 op=...'`. `rd_graph_census-gate.py`
# says the same thing about its trailing space. The port's `cr_g` prints a separator
# after EVERY op, so these lines end in a space and the pin carries it.
# THE PINS ARE WHOLE LINES, NOT VALUES. `gatekit` tests `want not in raw[lane]` against the
# lane's LINES, so a value without its `row=` prefix can never match and the first run of this
# gate reported `py's st_zero_g is not '30 op=...'. `rd_graph_census-gate.py` says the same
# thing about its trailing space: the port's `cr_g` prints a separator after EVERY op, so
# these lines end in a space and the pins carry it. THEY ARE WRAPPED AS ADJACENT LITERALS and
# each chunk ends on a space, so the concatenated value is byte-identical to the lane's line;
# the gate is what verifies that, because a pin that stopped matching would fail it.
# THE PINS ARE WHOLE LINES, NOT VALUES. `gatekit` tests `want not in raw[lane]` against the
# lane's LINES, so a value without its `row=` prefix can never match: the first run of this
# gate reported `py's st_zero_g is not '30 op=...'`. They are WRAPPED AS ADJACENT LITERALS,
# each chunk ending on a space, so the concatenation is byte-identical to the lane's line.
#
# THE TWO SIDES DO NOT END THE SAME WAY, AND THAT IS NOT A TYPO. The PORT's `cr_g` prints a
# separator after EVERY op (`rd_graph_census-gate.py` records the same), so `bd`'s line ends
# in a space; the ORACLE's `sig()` ends in the last token. The first wrapped attempt gave
# BOTH a trailing space and the gate said so: `py's st_zero_g is not '...RESHAPE/2 '`.
# THE PINS ARE WHOLE LINES, NOT VALUES. `gatekit` tests `want not in raw[lane]` against the
# lane's LINES, so a value without its `row=` prefix can never match: the first run of this
# gate reported `py's st_zero_g is not '30 op=...'. They are WRAPPED AS ADJACENT LITERALS,
# each chunk ending on a space, so the concatenation is byte-identical to the lane's line.
#
# THE TWO SIDES DO NOT END THE SAME WAY, AND THAT IS NOT A TYPO. The PORT's `cr_g` prints a
# separator after EVERY op (`rd_graph_census-gate.py` records the same), so `bd`'s line ends
# in a space and the oracle's does not. Two wrapped attempts got this wrong -- the first gave
# the oracle side a trailing space it does not have, the second gave both -- and the GATE is
# what said so, by printing the pin it could not match. A pin is not a constant; it is a
# claim about a lane, and only the lane can settle it.
# THE PINS ARE WHOLE LINES, NOT VALUES. `gatekit` tests `want not in raw[lane]` against the
# lane's LINES, so a value without its `row=` prefix can never match: the first run of this
# gate reported `py's st_zero_g is not '30 op=...'. They are WRAPPED AS ADJACENT LITERALS, each
# chunk ending on a space, so the concatenation is byte-identical to the lane's line.
#
# THE TWO SIDES DO NOT END THE SAME WAY, AND THAT IS NOT A TYPO. The PORT's `cr_g` prints a
# separator after EVERY op (`rd_graph_census-gate.py` records the same), so `bd`'s line ends in
# a space and the oracle's does not. TWO wrapped attempts got this wrong -- the first gave the
# oracle side a trailing space it does not have, the second removed the closing quote -- and
# the GATE is what said so both times, by printing the pin it could not match. A pin is not a
# constant; it is a claim about a lane, and only the lane settles it.
DIVERGES = {
  "st_zero_g": (
      "st_zero_g=30 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 BUFFER/1 CONST/0 CONST/0 "
      "SHRINK/3 ADD/2 SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 STORE/2 "
      "AFTER/2 SHRINK/3 CONST/0 MUL/2 ADD/2 SHRINK/3 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 "
      "STACK/2 RESHAPE/2",
    # the port: rd_next(ctr, 0, ctr) -- 26 nodes
    "st_zero_g=26 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 SHRINK/3 CONST/0 ADD/2 "
    "SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
    "RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_six_g": (
      "st_six_g=32 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 BUFFER/1 CONST/0 CONST/0 SHRINK/3 "
      "CONST/0 ADD/2 SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 STORE/2 "
      "AFTER/2 SHRINK/3 CONST/0 MUL/2 ADD/2 SHRINK/3 MUL/2 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 "
      "STACK/2 RESHAPE/2",
    # the port: rd_next(ctr, 6, ctr) -- 27 nodes
    "st_six_g=27 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 SHRINK/3 "
    "ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
    "RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_after_g": (
      "st_after_g=44 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 BUFFER/1 CONST/0 CONST/0 "
      "SHRINK/3 CONST/0 ADD/2 SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 "
      "STORE/2 AFTER/2 SHRINK/3 ADD/2 SHRINK/3 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 "
      "STORE/2 AFTER/2 SHRINK/3 CONST/0 MUL/2 ADD/2 SHRINK/3 MUL/2 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 "
      "MUL/2 ADD/2 STACK/2 RESHAPE/2",
    # the port: rd_next(ctr, 6, ctr) -- 47 nodes
    "st_after_g=47 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 "
    "SHRINK/3 ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 "
    "SHRINK/3 RESHAPE/2 CMPLT/2 CAST/1 CAST/1 CONST/0 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2 SHRINK/3 "
    "CAST/1 ADD/2 SHRINK/3 CAST/1 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 SHRINK/3 "
    "RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
  "st_max_g": (
      "st_max_g=32 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 BUFFER/1 CONST/0 CONST/0 SHRINK/3 "
      "CONST/0 ADD/2 SHRINK/3 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 RESHAPE/2 STORE/2 "
      "AFTER/2 SHRINK/3 CONST/0 MUL/2 ADD/2 SHRINK/3 MUL/2 ADD/2 RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 "
      "STACK/2 RESHAPE/2",
    # the port: rd_next(ctr, 4294967295, ctr) -- 24 nodes
    "st_max_g=24 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=ALLOC/0 CONST/0 CONST/0 SHRINK/3 SHRINK/3 "
    "ADD/2 CONST/0 ADD/2 STACK/0 RESHAPE/2 CMPLT/2 CAST/1 ADD/2 STACK/2 CONST/0 RESHAPE/2 SHRINK/3 "
    "RESHAPE/2 CMPLT/2 CAST/1 MUL/2 ADD/2 STACK/2 RESHAPE/2"),
}

# THE NINETEEN PORT-ONLY ROWS, NAMED. `gatekit` derives the oracle's expected count as
# `rows - len(port_only)`, so an oracle that grew one of these fails the COUNT rather than
# being quietly compared -- which is the property that stops an exclusion from hiding a
# comparison. The list is transcribed from the MEASURED lane, and the population census below
# checks it against the rows `main` actually declares.
PORT_ONLY = [
  "ref_drop_arm0", "ref_drop_arm1", "ref_drop_arm2",
  "arange3_g", "fold_np", "arange5_g", "fold5_np", "tfb3_g", "bits6_g", "btr6_g",
  "rand23_g", "rand23_d", "rand23nc_g", "rand23nc_d",
  "ctrl_rand_g", "ctrl_rand_d", "rand_like23_g", "rand_like23_d", "ctrl_arange3_g",
]

GATE = Gate("rand_census-gate", bend=DRIVER, oracle=ORACLE, rows=55, compared=32,
            diverges=DIVERGES, port_only=PORT_ONLY,
            pins=[("py", r) for r in ("ref_dropout_p1", "ref_sdpa_dt", "ref_bits_num223")])

# THE DECLARATION PATTERNS. BOTH GATES' DRIVERS ARE THE PORT FILES, so the driver and the
# port are the same text and one pattern reads both -- which is the cleanest instance of the
# rule in this tree: the rows a layer ships ARE the rows its own generator declares, and
# nothing about the row set is transcribed into the gate.
_DECL = re.compile(r'(?<!\w)(?:rd_row|rd_bl|rd_nm)\("([^"]+)"')
_DEF = re.compile(r'^def ([\w.]+)\(', re.M)
_CALL = re.compile(r'(?<![\w.])([a-z_][\w]*)\(')

# THE DECLARED POPULATION IS THE ROWS `main` REACHES, NOT THE ROWS THE FILE MENTIONS.
# `tinybendygrad/mixin/rand.bend` carries SEVENTEEN `cr_row(...)` call sites whose `t_*`
# helpers `main` never calls -- the header's R4 says so in as many words ("the eleven rows that
# depend on `randn_like` ... are therefore NOT IN `main` and are UNMEASURED") -- and MEASURED a
# file-wide scan declares 87 rows against a 55-row lane. A declaration census that reads the
# whole file therefore REFUSES a lane that is exactly right, which is the recorded "an
# instrument that reports a result for something it never ran" shape pointed the other way.
#
# THE THREE SUFFIX PRINTERS ARE WHY A PLAIN SCAN FAILS TWICE OVER. `rd_np("fold", t)` prints
# `fold_np=`, and `CR.cr_row("rand23", t)` prints `rand23_g=` AND `rand23_d=`: each printer
# APPENDS its suffix in its own `String.concat`, so the ARGUMENT IS NOT THE ROW NAME. Measured
# by the census itself: `declared=49` on the whole file, then `declared=45` with `rd_np` added
# to `_DECL` (which added `fold` and `fold5` and so missed their `_np` rows), then 83.
# "THE ROW IS NAMED AFTER ITS ARGUMENT" is false for this file's printers, so the suffixes are
# spelled out rather than assumed.
_NP = re.compile(r'(?<!\w)rd_np\("([^"]+)"')
_CR = re.compile(r'(?<!\w)cr_row\("([^"]+)"')


def _defs(src):
  """`name -> body`, split on the file's own top-level `def` headers."""
  out, marks = {}, [(m.group(1), m.start()) for m in _DEF.finditer(src)]
  for i, (nm, at) in enumerate(marks):
    out[nm] = src[at:marks[i + 1][1] if i + 1 < len(marks) else len(src)]
  return out


def reached_rows(src):
  """THE ROWS `main` PRINTS, as a CLOSURE over the file's own call sites.

  LEXICAL, NOT TYPED: it reads `t_st_zero()` as a call, not as a resolved value. That is a
  weaker guarantee than a type checker and a stronger one than a hand list, and the difference
  is named rather than papered over -- a call site reached only through a name this scan
  cannot see would leave its rows undeclared and the census would REFUSE.
  """
  bodies = _defs(src)
  seen, rows, work = set(), set(), ["main"]
  while work:
    nm = work.pop()
    if nm in seen or nm not in bodies:
      continue
    seen.add(nm)
    body = bodies[nm]
    rows |= set(_DECL.findall(body))
    rows |= {m.group(1) + "_np" for m in _NP.finditer(body)}
    rows |= {m.group(1) + sfx for m in _CR.finditer(body) for sfx in ("_g", "_d")}
    work += [c for c in _CALL.findall(body) if c in bodies]
  return rows


def row_population() -> bool:
  return _row_population(reached_rows((ROOT / PORT).read_text()),
                         [k for k, _ in lanes(_lane_text())], " (rand)")

def _lane_text():
  f = GATE.dir / "bd.out"
  return f.read_text() if f.is_file() else ""


# THE NEGATIVE FIXTURES: every `ref_*_not`, every `absent`, and the `_d`/`_np` rows whose
# whole claim is that the fold CANNOT answer -- a class whose expected answer is False.
NEG = tuple(k for k in ("ref_rand_weak_wf", "ref_rand_weak_i32", "ref_uniform_not",
                        "ref_normal_not", "ref_randint_not", "ref_dropout_not",
                        "ref_multi_n31", "fold_np", "fold5_np"))
CONST = ("ref_drop_arm0", "ref_drop_arm1", "ref_drop_arm2")


def class_census() -> bool:
  rows = lanes(_lane_text())
  # NO C-EMPTY FLOOR, AND THE ABSENCE IS THE FINDING: this file's printers cannot print an
  # empty value. `rd_bl` prints `True`/`False` and `rd_nm` prints a token, and every fixture in
  # `t_ref` produces one of the two, so `C-EMPTY` is 0 and asking for 1 is asking for a row
  # the layer does not have. MEASURED 0, and stated rather than floored, because a floor a
  # layer cannot meet is a floor that will be lowered to 0 by the next unit and the class will
  # have stopped meaning anything.
  ok = _class_census(rows, neg=NEG, const=CONST,
                     floors={"C-CTRL": 1, "C-NEG": 8, "C-BOOL": 1, "C-VALUE": 1})
  # The PORT-ONLY rows are a class of their own: they are in no lane that has a peer, so
  # nothing can move them and the only claim they carry is that the port still prints them.
  missing = [r for r in PORT_ONLY if not any(k == r for k, _ in rows)]
  print(f"-- CLASS C-PORTONLY n={len(PORT_ONLY) - len(missing)} of {len(PORT_ONLY)} declared "
        f"cannot-distinguish=anything about CPython: there is NO CPython row for these, "
        f"because `.agents/slop/rd-truth.py` -- the only oracle this layer ever had -- is gone")
  if missing:
    print(f"-- CLASS FAIL: C-PORTONLY names rows the lane did not emit: {missing[:4]}")
    ok = False
  return ok


if __name__ == "__main__":
  if "--plant" in sys.argv:
    sys.exit(_plant())
  bad = oracle_drift(DRIFT_PIN)
  if bad:
    print("== REFUSED, NOT A VERDICT: the CPython side this gate diffs against has moved",
          file=sys.stderr)
    for b in bad:
      print(f"   {b}", file=sys.stderr)
    sys.exit(3)
  sys.exit(gate(GATE, "rand_census-gate: 55 port rows, 32 compared against CPython and all 32 "
                      "agree byte-for-byte, 4 `st_*` divergences PINNED ON BOTH SIDES, "
                      "19 port-only with their absence from the oracle asserted; four CPython "
                      "pins intact",
               checks=lambda: row_population() and class_census()))
