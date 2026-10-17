#!/usr/bin/env python3
"""opseven-gate.py -- the seven `Ops` `runs/graphcmp/D/D1-graph-*.txt` never reaches.

    .venv/bin/python gates/opseven-gate.py
    .venv/bin/python gates/opseven-gate.py --refresh    # rewrites the pins file

31 ROWS, THREE LANES, 4 DECLARED DIVERGENCES IN ONE CLASS. THE SEVEN are `CUSTOM CUSTOMI INS
PROGRAM PYLITERAL REWRITE_ERROR SOURCE`: the seven members of `tinybendygrad/uop/ops.bend`'s 77-variant
`type Op is Data:` block that the 34-graph corpus does not build, so nothing in this tree ever had an
opinion about the port's answers for them.

**SO THE INSTRUMENT BUILDS THEM.** `gates/opseven.bend` MINTS all twelve fixture nodes and
`gates/opseven-oracle.py` builds the same twelve from upstream's own construction sites, and the two
lanes are diffed. That is the `gates/ops_bend_exec-e2e.py` move -- force the shape rather than wait for
a program to make it -- and it is what makes the port's answer comparable to CPython's for the FIRST
time on these ops. Twenty-seven of the thirty-one rows are compared exactly and the four that are not are
one class; `classes_hold` below proves what the divergence class IS rather than naming it.

CAN CPYTHON EMIT ALL SEVEN? YES, and six of the seven by one `UOp(...)` call -- `REWRITE_ERROR`
(ops.py:1713), `PYLITERAL` (upat.py:26 and :29), `SOURCE` (codegen/__init__.py:453), `CUSTOM`
(upat.py:26, llm/kernels/amd.py:45), `CUSTOMI` (upat.py:66, llm/kernels/amd.py:113), `INS` (ops.py:600
`UOp.ins`), `PROGRAM` (codegen/__init__.py:500). So every fixture here is a DIRECT construction and none
is a forced failure: there is no `D8`-style fixture that always throws, because a fixture that cannot
fail is not a witness. The one op that is only legal in ONE of the five spec tables -- `REWRITE_ERROR`,
whose sole rule is spec.py:239 in `spec_full`, the matcher whose own comment reads "these ops can exist
in programs but not the tensor spec / everything should be deleted from here" -- is therefore MEASURED
ON ITS OWN TERMS (`rewrite_error=... st=9 sf=1 sh=9 sk=9`, `sp_rewrite_error=9`) rather than forced
into a program graph.

CLASS 1, `SPEC_PROGRAM`, WAS A DEFECT IN `tinybendygrad/uop/spec.bend` AND IS NOW FIXED, so it is no longer
a class of pinned divergence: it is a REGRESSION GUARD on the fix, stated in the falsifiable form -- the
port's `sp_*` column is not constant. The port read

    def pr_0.claims(fx, self): Bool.not(O.UOp.is_none(self))
    def pr_0.body(fx, self):   Bool.not(sp_op(fx, self, O.OpsCAST{}))

where `spec.py:204` is

    (UPat(GroupOp.All-GroupOp.Defines, name="x"),
     lambda x: False if x.op is not Ops.CAST and any(s.op is Ops.CONST for s in x.src) else None)

so the claim DROPPED `-GroupOp.Defines` and the body DROPPED THE SECOND CONJUNCT, and the file's OWN HEADER
quoted the rule it dropped, three lines above the def that dropped it. MEASURED here while it was live:
the port's `sp_*` column was the CONSTANT `0` on **12 of 12** rows while CPython's took three values on
the same twelve -- **5 at `1`, 4 at `9`, 3 at `0`** -- so the column carried no information about the
node. **3 OF THE 12 AGREED, AND ALL THREE AGREED BY COINCIDENCE**: `custom_void`, `custom_f32` and
`customi_f32` each carry a CONST src, so CPython's `pr_0` fired on the conjunct the port dropped while the
port fired on being non-CAST. Same verdict, two different rules, so `3 of 12` was NOT a pass rate.

AFTER THE FIX the column agrees with CPython's on **12 of 12** and the nine pinned rows are COMPARED rows,
so the ordinary diff guards them: re-drop either half and nine rows go red, which no pin is needed for.
Both halves call code that was ALREADY PORTED AND UNCALLED -- `GroupOp.defines` at `ops.bend:495` and
`any_const` at `spec.bend:526` -- so the fix was a caller, not a reimplementation. The gate keeps the claim
because a guard that names nothing can go green by accident.

CLASS 2, `OPS_VALUE` (4 rows, `value_custom value_customi value_ins value_pyliteral`). NOT A DEFECT: the
port's `Ops.value` table is a FAITHFUL reading of its own 77-member enum. `FastEnum`'s
`_generate_next_value_` is `1 + max(...)` over every `FastEnum` subclass and `Ops` is the only one, so the
number IS the declaration order -- and `uop/ops.bend`'s own header says so ("`__init__.py` says the order
of these Ops controls the order of the toposort"). MEASURED by parsing the file in `classes_hold`:
`type Op is Data:` has **77** variants, `Ops.value` has **77** arms, `Ops.name.of` has **77**,
`all_ops` has **77**, and **every one of the 77 sits at its own declaration position**. Upstream
(`git show upstream:tinygrad/uop/__init__.py`) declares **75**: it DELETED `GROUP` and `FLIP`, and those
two are the WHOLE of the disagreement. So `classes_hold` PREDICTS the offset per row from where `GROUP`
and `FLIP` sit in the port's own declaration block -- 0 before position 14, 1 from 14 to 72, 2 from 73 --
rather than transcribing four numbers. The three rows declared BEFORE `GROUP` already agree:
`value_rewrite_error=5`, `value_source=10`, `value_program=8`. WHEN THE RE-VENDOR REMOVES THE TWO
MEMBERS FROM `ops.bend` THESE FOUR PINS GO STALE AND THIS GATE GOES RED, WHICH IS CORRECT: refresh
them. That is the class doing its job rather than a gate that cannot notice a set change.

THE RE-VENDOR, AND WHY THIS LANE IS SAFE UNDER IT. This tree's `tinygrad/` was the PRE-re-vendor vendor
(77 members, `GROUP` and `FLIP` present) while the other unit was landing upstream's 75. MEASURED: the 31
rows are byte-identical under `git archive HEAD:tinygrad` (the 77-member tree) and under
`git archive upstream:tinygrad` (the 75-member tree) EXCEPT the four `value_*` rows, which differ for
exactly the reason class 2 names and no other. So `TGROOT` exists in the oracle for the measurement, the
gate runs it with no `TGROOT` at all, and the only four rows the re-vendor can move are the four already
declared as divergences.

ONE FIXTURE CPYTHON HAS AND THE PORT CANNOT SPELL, AND IT IS NOT A ROW. `upat.py:25` builds
`UOp(Ops.PYLITERAL, arg=frozenset(self.op))` -- a SET of ops, and the common case, because every
multi-op `UPat` takes it. `type Arg is Data:` in `tinybendygrad/uop/ops.bend` has NO set-of-`Op`
constructor, so the port cannot represent it. A row the port cannot print measures nothing, so it is not
one; the oracle PRINTS IT TO STDERR on every run (`pyliteral_frozenset=... port_can_spell=no`) so the gap
is a number in the transcript and not a reading of the source, and `spec.py:116`'s `UPat(Ops.PYLITERAL)`
puts no test on the arg at all, so nothing in the port's spec needs the frozenset TODAY.

WHAT THIS GATE CANNOT SEE, NAMED. (a) It compares ONE NODE per row, so it says nothing about how these ops
behave as a SUBGRAPH -- `customi_f32`'s `sp=0` is `pr_0`'s defect, and a caller that asks the right
question of `spec_program` on a graph would get `spec_program` over the toposort, which this does not
measure. (b) The `SINK` in the two `program_*` fixtures carries `ANone{}` on the port's side and a
`KernelInfo` on CPython's, because the port's `Arg` has no `KernelInfo` for a SINK; no rule on any row
reads it and the SINK is not itself a row, so the difference is outside the comparison rather than
smoothed away. (c) `Ops.value` is compared only for the seven; the other 70 numbers are in no row here,
and the class-2 prediction is over these seven only. (d) `spec_kernel_graph` is `9` on all 12 rows, so
that column is consistent-but-uninformative: this gate does not show it can distinguish anything.
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, gate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "opseven-pins.rows"
ART = HERE / "artifacts" / "opseven-gate"
OPS_BEND = ROOT / "tinybendygrad" / "uop" / "ops.bend"

# THE 31 ROWS, in the driver's own order: twelve fixtures, each of which prints its main row and then
# its `sp_` row, then the seven `Ops.value` rows. The COUNT is the driver's, and `gatekit` refuses the
# run if a lane disagrees with it, so this is a MEASUREMENT of the lanes and not a typed inventory.
FIXTURES = ("rewrite_error", "pyliteral_op", "pyliteral_str", "source", "custom_void", "custom_f32",
            "customi_void", "customi_f32", "ins_void", "ins_f32", "program_1", "program_4")
SP_ROWS = tuple(f"sp_{r}" for r in FIXTURES)
VALUE_OPS = ("rewrite_error", "source", "program", "custom", "customi", "ins", "pyliteral")
VALUE_ROWS = tuple(f"value_{o}" for o in VALUE_OPS)
ROWS = tuple(r for f in FIXTURES for r in (f, f"sp_{f}")) + VALUE_ROWS

# THE DIVERGENCE POPULATION, HAND-DECLARED IN GIT, AND THE CLASS IS CHECKED AGAINST IT IN BOTH
# DIRECTIONS BY `_pins()`. A row pinned and not declared is a pin nothing will ever exclude; a row
# declared and not pinned is an exclusion with no content behind it. There is ONE class: the
# `spec_program` rows are COMPARED rows now, so a second class naming them would be a pin with no
# divergence behind it -- and `_pins()` refuses that shape rather than accepting it.
OPS_VALUE = ("value_custom", "value_customi", "value_ins", "value_pyliteral")
DIVERGING = OPS_VALUE

# UPSTREAM DELETED THESE TWO, AND THE GATE FINDS THEM ITSELF: `_removed()` parses the port's own
# `type Op is Data:` block and returns every variant upstream does not have, so the class-2 prediction
# below is derived from the tree rather than from a list typed here.
REMOVED_BY_UPSTREAM = ("GROUP", "FLIP")


def _declared_ops():
  """The port's `type Op is Data:` variants IN DECLARATION ORDER, parsed from its own source.

  This is a DIRECTORY-FREE population by REGEX OVER ONE FILE'S OWN DECLARATION BLOCK, and it is the
  only thing in this gate that reads `uop/ops.bend`; everything else reads the two lanes. It is here
  because class 2's claim is a claim about declaration order, and a claim about declaration order has
  to be checked against the declaration.
  """
  src = OPS_BEND.read_text()
  m = re.search(r"type Op is Data:(.*?)\n(?=\S)", src, re.S)
  if m is None:
    raise ValueError(f"no `type Op is Data:` block in {OPS_BEND}")
  return [v[len("Ops"):] for v in re.findall(r"^\s*(Ops[A-Z0-9_]+)\{\}", m.group(1), re.M)]


def _upstream_ops():
  """Upstream's `Ops` member names, from `git show upstream:tinygrad/uop/__init__.py`.

  THE REGEX HAS TO SEE PAST THE SEMICOLONS, and getting that wrong is how this function first
  answered. `__init__.py` is written `# allow semicolons to put multiple ops on one line`, so
  `SINK = auto(); AFTER = auto()` is ONE line and TWO members; `re.findall(r"^\\s*([A-Z]...)\\s*=\\s*auto\\(\\)")`
  with an anchor measured **48** members where the enum has **75**, which made the class-2 check
  report 45 deleted members and refuse the gate. The fix is to drop the anchor and to read only the
  `class Ops(FastEnum):` block, so `auto()` from another FastEnum cannot leak in.
  """
  up = subprocess.run(["git", "show", "upstream:tinygrad/uop/__init__.py"], cwd=ROOT,
                      capture_output=True, text=True, check=True).stdout
  m = re.search(r"class Ops\(FastEnum\):(.*?)\n(?=class |\Z)", up, re.S)
  if m is None:
    raise ValueError("no `class Ops(FastEnum):` block in upstream:tinygrad/uop/__init__.py")
  return re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=\s*auto\(\)", m.group(1))


def _removed(declared):
  """`{member: 1-based position}` for every declared variant upstream does NOT have.

  UPSTREAM'S OWN ENUMERATION, NOT A COPY OF IT: the two enumerations are differenced, which is a
  MEASUREMENT, where naming `("GROUP", "FLIP")` would be a transcription. `REMOVED_BY_UPSTREAM` is
  checked against that measurement rather than used as its input, so a third deletion upstream goes RED
  instead of being predicted on a stale pair.
  """
  have = set(_upstream_ops())
  return {name: i for i, name in enumerate(declared, 1) if name not in have}


def _header(n_div, n_same):
  return f"""# opseven-pins.rows -- GENERATED by `gates/opseven-gate.py --refresh`, which is its ONLY
# writer. One TAB-separated triple per declared divergence: `<row>\\t<CPython's line>\\t<the port's
# line>`, i.e. the expected content on BOTH sides.
#
# {n_div} DIVERGENCES IN ONE CLASS, {n_same} OF THE {len(ROWS)} ROWS AGREE EXACTLY. It is git-resident and beside the
# gate because a gate's required inputs live in git and not in `gates/artifacts/`: `gatekit` EMPTIES
# that directory before it runs and UNLINKS what it staged when the run was not green, so a
# divergence list read from there is destroyed by the first red run and there is then nothing to edit.
#
# NO `SPEC_PROGRAM` CLASS ANY MORE, AND THE REASON IS THE POINT: `tinybendygrad/uop/spec.bend`'s `pr_0`
# dropped spec.py:204's `-GroupOp.Defines` op set AND the body's `any(s.op is Ops.CONST for s in x.src)`
# conjunct, so the port's `spec_program` answered VFalse for every node that was not a CAST -- MEASURED,
# a CONSTANT `0` on {len(SP_ROWS)} of {len(SP_ROWS)} rows where CPython took three values. It is FIXED:
# both halves now call code that was already ported and uncalled (`GroupOp.defines` at `ops.bend:495`,
# `any_const` at `spec.bend:526`), and the {len(SP_ROWS)} `sp_*` rows agree with CPython EXACTLY, so they are
# COMPARED rows and the ordinary diff guards them -- re-drop either half and {len(SP_ROWS)} rows go red.
# `spec_program_holds` keeps the claim in its falsifiable form, "the column is not constant", because a
# check that names nothing goes green by accident. What this fix did NOT do is measure `spec_full`: the
# only reader of the spec tables in the tree is `gates/opseven.bend`'s `sf` column, and `sf` is 1 on
# {len(SP_ROWS)} of {len(SP_ROWS)} before and after, so the unmasking it performs in `full_table` -- where `pr_0`
# sits at tag 59, behind 63 entries, so entries 60..70 were dead -- is REAL BY CONSTRUCTION and
# UNOBSERVED HERE. That is a gap, not a result, and it is named here so the next reader inherits it.
#
# CLASS `OPS_VALUE` ({len(OPS_VALUE)} rows): NOT A DEFECT. The port's `Ops.value` table is declaration order
# over its own 77-member enum, measured arm-by-arm, and upstream declares 75 because it deleted `GROUP`
# and `FLIP`. These four are declared after `GROUP`. `ops_value_holds` PREDICTS the offset from where those
# two sit in the port's own block, so it is derived; when the re-vendor removes them from `ops.bend` these
# pins go stale ON PURPOSE and the gate goes RED until `--refresh`.
"""


def refresh() -> int:
  """REWRITE `gates/opseven-pins.rows` from a fresh pair of lanes. Its ONLY writer.

  It does not go through `Gate.run()`, because a refresh is exactly what a run cannot do when the pins
  are wrong: the whole point is to REPLACE them. The divergence rows are whatever DISAGREES, so the
  population is a MEASUREMENT of the pair, and the header is rewritten with it -- a pins file whose
  prose outlives its content is a second document disagreeing with the first.
  """
  py = subprocess.run([str(PY), str(HERE / "opseven-oracle.py")], capture_output=True, text=True, cwd=ROOT)
  bd = subprocess.run([str(BEND), "gates/opseven.bend"], capture_output=True, text=True, cwd=ROOT)
  if py.returncode or bd.returncode:
    print(f"--refresh: a lane failed (py rc={py.returncode}, bd rc={bd.returncode}); nothing written",
          file=sys.stderr)
    return 1
  got = {t: {l.split("=", 1)[0]: l for l in s.splitlines() if "=" in l}
         for t, s in (("py", py.stdout), ("bd", bd.stdout))}
  if any(len(got[t]) != len(ROWS) for t in ("py", "bd")):
    print(f"--refresh: lane row counts are py={len(got['py'])} bd={len(got['bd'])}, "
          f"expected {len(ROWS)}; nothing written", file=sys.stderr)
    return 1
  rows = [r for r in ROWS if got["py"].get(r) != got["bd"].get(r)]
  out = [_header(len(rows), len(ROWS) - len(rows))]
  for r in rows:
    out.append("# %-20s %-72s cpy %4dB %s | port %4dB %s" % (
      r, "OPS_VALUE, declared after GROUP; the port's enum has 2 more members than upstream's",
      len(got["py"][r]), hashlib.sha256(got["py"][r].encode()).hexdigest()[:12],
      len(got["bd"][r]), hashlib.sha256(got["bd"][r].encode()).hexdigest()[:12]))
    out.append("%s\t%s\t%s" % (r, got["py"][r], got["bd"][r]))
  PINS.write_text("\n".join(out) + "\n")
  print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, "
        f"{len(ROWS) - len(rows)} exact matches")
  return 0


def _pins():
  """`(DIVERGES, why)` -- the pins LOADED BY PATH, and the population they must agree with.

  The CONTENT comes from the file and the POPULATION comes from the tuples above, and the two are
  checked against each other here rather than one being derived from the other.
  """
  if not PINS.is_file():
    return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live in git, not in "
                  f"its own output directory. Write it with `--refresh`.")
  pins = {}
  for ln in PINS.read_text().splitlines():
    if not ln.strip() or ln.startswith("#"):
      continue
    row, py, bd = ln.split("\t")
    pins[row] = (py, bd)
  if set(pins) != set(DIVERGING):
    extra, gone = sorted(set(pins) - set(DIVERGING)), sorted(set(DIVERGING) - set(pins))
    return None, (f"the pins file and the declared classes disagree: pinned but not declared {extra}, "
                  f"declared but not pinned {gone}")
  return pins, ""


DIVERGES, WHY = _pins()


def _lane(name):
  """`(row_name -> value)` for one lane's own artifact, or `{}` when it is absent.

  It reads the lane's OWN output rather than a second derivation that could drift from it, which is the
  rule `gates/ew_graph_census-gate.py`'s `no_noop_bottom` follows. Both extensions are read because a
  row is in exactly one of them after the exclusion list has run: compared rows land in `.cmp` and
  excluded rows are in the pins file.
  """
  out = {}
  for ext in (".cmp", ".rows", ".out"):
    f = ART / f"{name}{ext}"
    if f.is_file():
      out.update({l.split("=", 1)[0]: l.split("=", 1)[1] for l in f.read_text().splitlines() if "=" in l})
  return out


def spec_program_holds() -> bool:
  """CLASS 1 AS A REGRESSION GUARD: the port's `spec_program` column is NOT the constant `0` it was.

  `spec.bend`'s `pr_0` dropped BOTH halves of spec.py:204 -- the `-GroupOp.Defines` op set and the
  body's `any(s.op is Ops.CONST ...)` conjunct -- so the column was `0` on every row and carried no
  information about the node. The fix made it agree with CPython on all twelve. Stated as "not constant"
  rather than only as "agrees with CPython" because the ordinary diff already owns the second claim, and
  what the diff does NOT own is that this column was ever a constant: this check is what makes the old
  defect unrepresentable as a green gate.

  Four assertions, all of which can fail:

    1. every `sp_*` row is present on BOTH lanes -- a missing row is a named False, not a `KeyError`;
    2. the port's twelve values take MORE THAN ONE distinct value: the old defect's exact shape;
    3. CPython's column is not itself constant, so assertion 2 cannot pass by CPython being flat;
    4. the two columns agree on all twelve, and a disagreement is printed with both values.

  It reads `.get` with a default rather than subscripting, so a MISSING row is a False here and not a
  `KeyError` that `gate()` would report as the same number as an honest FAIL.
  """
  if not DIVERGES:
    print("spec_program_holds: the pins file is absent, so there is nothing to hold")
    return False
  port, py = _lane("bd"), _lane("py")
  cpy = {r: (py[r] if r in py else DIVERGES[r][0].split("=", 1)[1])
         for r in SP_ROWS if r in py or r in DIVERGES}
  for r in SP_ROWS:
    if r not in port or r not in cpy:
      print(f"spec_program_holds: {r} is missing from the {'port' if r not in port else 'CPython'} lane")
      return False
  if len(set(port[r] for r in SP_ROWS)) < 2:
    print(f"spec_program_holds: the port's sp_* column is CONSTANT ({sorted({port[r] for r in SP_ROWS})})"
          " -- spec.bend's pr_0 has dropped spec.py:204's `-GroupOp.Defines` or its `any(... CONST)` "
          "conjunct again, and a constant column carries no information about the node")
    return False
  if len(set(cpy.values())) < 2:
    print(f"spec_program_holds: CPython's sp_* column is constant ({sorted(set(cpy.values()))}), so "
          "'the port's is not' would be vacuous")
    return False
  bad = [(r, port[r], cpy[r]) for r in SP_ROWS if port[r] != cpy[r]]
  if bad:
    print(f"spec_program_holds: {len(bad)} of {len(SP_ROWS)} rows disagree with CPython: {bad}")
    return False
  n1 = sum(1 for v in cpy.values() if v == "1")
  n9 = sum(1 for v in cpy.values() if v == "9")
  print(f"spec_program_holds: SPEC_PROGRAM holds -- the port's sp_* is NOT the constant it was and agrees "
        f"with CPython on {len(SP_ROWS)} of {len(SP_ROWS)} ({n1} at '1', {n9} at '9', "
        f"{len(cpy) - n1 - n9} at '0'); spec.py:204's `-GroupOp.Defines` and its `any(... CONST)` "
        f"conjunct are both in the rule")
  return True

def ops_value_holds() -> bool:
  """CLASS 2's claim, DERIVED: the offset is the count of upstream-deleted members declared EARLIER.

  Nothing here is typed. `_removed()` enumerates upstream's `Ops` from `git show upstream:...` and
  returns the positions of the variants this tree declares and upstream does not; the prediction is then
  `port - py == |{those declared before this op}|`. `REMOVED_BY_UPSTREAM` is checked against that
  measurement rather than used as the input, so a third deletion upstream goes RED instead of being
  predicted on a stale pair.
  """
  if not DIVERGES:
    return False
  py, port = _lane("py"), _lane("bd")
  declared = _declared_ops()
  pos = {name: i for i, name in enumerate(declared, 1)}
  removed = _removed(declared)
  if sorted(removed) != sorted(REMOVED_BY_UPSTREAM):
    print(f"ops_value_holds: upstream does NOT have exactly {sorted(REMOVED_BY_UPSTREAM)}; measured "
          f"{sorted(removed)} at positions {removed}. The class-2 prediction is over a stale pair.")
    return False
  for o in VALUE_OPS:
    r = f"value_{o}"
    if r not in DIVERGES:
      continue
    # `VALUE_OPS` is lowercase because it names the ROW (`value_custom`), and the declaration block is
    # uppercase because it names the member (`OpsCUSTOM`). `.upper()` is the join, and a missing key
    # here is a named False rather than a `KeyError`.
    at = pos.get(o.upper())
    if at is None:
      print(f"ops_value_holds: {o.upper()} is not in the port's `type Op is Data:` block")
      return False
    # `DIVERGES[r]` is `(CPython's line, the port's line)` in THAT ORDER. Naming the two
    # `cpy_line`/`port_line` and then re-deriving each from its OWN source is deliberate: the first
    # version of this read them the wrong way round and compared `port - cpython` against a
    # non-negative prediction, so a correct pair of pins reported an offset of -1.
    cpy_line, port_line = DIVERGES[r]
    cpy_v, port_v = int(cpy_line.split("=", 1)[1]), int(port.get(r, port_line))
    want = sum(1 for m in removed.values() if m < at)
    if port_v - cpy_v != want:
      print(f"ops_value_holds: {r} is {port_v} on the port and {cpy_v} on CPython, a difference of "
            f"{port_v - cpy_v}, and {want} removed member(s) are declared before {o.upper()} "
            f"(position {at})")
      return False
  print(f"ops_value_holds: OPS_VALUE holds -- {sorted(removed)} at positions "
        f"{sorted(removed.values())} explain every one of the {len(OPS_VALUE)} offsets; the port's "
        f"Ops.value is declaration order over its own {len(declared)} variants")
  return True


def classes_hold() -> bool:
  return spec_program_holds() and ops_value_holds()


GATE = Gate(
  "opseven-gate",
  bend="opseven.bend",
  oracle="opseven-oracle.py",
  rows=len(ROWS),
  compared=len(ROWS) - len(DIVERGING),
  diverges=DIVERGES or {},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def main() -> int:
  if "--refresh" in sys.argv:
    return refresh()
  if WHY:
    print(f"== REFUSED, NOT A VERDICT: opseven-gate: {WHY}", file=sys.stderr)
    return 3
  return gate(GATE,
              f"opseven-gate: PASS -- {len(ROWS)} rows, {len(ROWS) - len(DIVERGING)} compared exactly, "
              f"{len(DIVERGING)} pinned divergences in 1 class "
              f"({len(OPS_VALUE)} OPS_VALUE)", checks=classes_hold)


if __name__ == "__main__":
  sys.exit(main())