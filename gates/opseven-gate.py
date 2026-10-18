#!/usr/bin/env python3
"""opseven-gate.py -- the seven `Ops` `runs/graphcmp/D/D1-graph-*.txt` never reaches.

    .venv/bin/python gates/opseven-gate.py
    .venv/bin/python gates/opseven-gate.py --refresh    # rewrites the pins file
    .venv/bin/python gates/opseven-gate.py --plant      # the class-2 claim, made to FAIL

31 ROWS, THREE LANES, ZERO DECLARED DIVERGENCES. THE SEVEN are `CUSTOM CUSTOMI INS
PROGRAM PYLITERAL REWRITE_ERROR SOURCE`: the seven members of `tinybendygrad/uop/ops.bend`'s 77-variant
`type Op is Data:` block that the 34-graph corpus does not build, so nothing in this tree ever had an
opinion about the port's answers for them.

**SO THE INSTRUMENT BUILDS THEM.** `gates/opseven.bend` MINTS all twelve fixture nodes and
`gates/opseven-oracle.py` builds the same twelve from upstream's own construction sites, and the two
lanes are diffed. That is the `gates/ops_bend_exec-e2e.py` move -- force the shape rather than wait for
a program to make it -- and it is what makes the port's answer comparable to CPython's for the FIRST
time on these ops. All thirty-one rows are compared exactly and `classes_hold` below holds two standing
claims that no row and no diff can express: that the port's `spec_program` column was never a constant,
and that the port's `Ops` declarations and upstream's agree in BOTH directions.

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

CLASS 2, `OPS_VALUE`, IS NO LONGER A CLASS OF DIVERGENCE AND IS NOT ONE ANY MORE. `FastEnum`'s
`_generate_next_value_` is `1 + max(...)` over every `FastEnum` subclass and `Ops` is the only one, so
the number IS the declaration order -- and `uop/ops.bend`'s own header says so ("`__init__.py` says the
order of these Ops controls the order of the toposort"). `ops_value_is_declaration_order` is what
MEASURES that, over EVERY arm and not over the seven `value_*` rows: it reads the port's
`type Op is Data:` block and the three tables keyed off it (`Ops.value`, `Ops.name.of`, `all_ops`) and
holds that each has one entry per variant, IN DECLARATION ORDER, with `Ops.value` numbering them `1..N`
and no gap. MEASURED at 75/75/75/75 with every arm at its own position.

THE OLD CLAIM AND THE NEW ONE, AND WHY THE NEW ONE IS STRONGER. The old claim was "the port sits at an
OFFSET from upstream equal to the number of upstream-deleted members the port still declares earlier",
and it was graded FROM THE PIN: `ops_value_holds` read only the PORT lane on purpose, "reading the live
py lane instead would make the prediction grade its own input" -- so the CPython side of the prediction
was four TYPED NUMBERS, which is exactly why it went stale (`59/60/61/77` against a re-vendor that moved
them to `58/59/60/75`) and left the gate REFUSED. The new claim is "the port's VALUE ROWS SIT AT THE SAME
POSITIONS AS UPSTREAM's", derived from BOTH LIVE LANES and from `_absent()`'s own two enumerations
(`type Op is Data:` and `git show upstream:tinygrad/uop/__init__.py`), with nothing transcribed. It is
STRICTLY STRONGER because it needs NO REFRESH when upstream moves: the CPython side is now read, not
pinned, so a member upstream adds or deletes shifts `cpy_v` and the row goes red on its own -- where the
old form's four numbers could only be corrected by a human noticing they were stale.

THE HISTORICAL RECORD, KEPT AS PROSE AND NOT AS AN INPUT. Upstream used to declare 77 and deleted `GROUP`
and `FLIP` (`900880433`, "remove Ops.FLIP", 2026-10-11), which is why four rows were pinned once. BOTH
MEMBERS ARE NOW GONE FROM THE PORT TOO, so `_absent(declared, upstream)` measures `{}` and the offset is
ZERO. `OPS_VALUE` and `REMOVED_BY_UPSTREAM` were two hand-typed tuples standing in for that measurement,
and both are GONE RATHER THAN RENAMED: a renamed list is still an input, and an input that is only ever
read to be compared against a measurement is the list that rots silently. What replaced them asserts the
VACUITY instead of the emptiness -- `_absent()` is empty IN BOTH DIRECTIONS, and each of the seven rows
sits at offset zero -- so "there is nothing to predict" is a RESULT the gate reached and checked, not a
condition it was handed.

THE RE-VENDOR, AND WHY THIS LANE IS SAFE UNDER IT. `a741a469f` (2026-10-17) RE-VENDORED `tinygrad/`
to upstream `002630241`, and that vendor IS upstream now -- MEASURED today, `HEAD:tinygrad` and
`upstream:tinygrad` are the SAME tree `62319c8ae612e51102916000d401d601a090353f`, so the oracle's
`from tinygrad.uop import Ops` already reads the 75-member enum and `TGROOT` is no longer needed for
this comparison. `TGROOT` STAYS because it is still the only way to read a lane against a vendor other
than the checked-out one, and a lane that cannot be pointed elsewhere cannot be re-read against an older
vendor when the next re-vendor lands. `--plant` is what proves this class still moves: six states, five
of them red, none of which needs a `bend`.

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
smoothed away. (c) `Ops.value` is compared only for the seven; the other 68 numbers are in no row here,
and the class-2 claim is about the DECLARATIONS rather than about those 68. (d) `spec_kernel_graph` is `9`
on all 12 rows, so that column is consistent-but-uninformative: this gate does not show it can distinguish
anything.
"""

import contextlib
import hashlib
import io
import re
import subprocess
import sys
import tempfile
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

# ZERO DECLARED DIVERGENCES, AND THE POPULATION IS STILL CHECKED AGAINST THE FILE.
# `_pins()` loads `opseven-pins.rows` by path and holds `set(<the file's rows>) == set(DIVERGING)` in
# BOTH directions, so an empty declaration is a CLAIM that the last `--refresh` found no divergence --
# and a row the lanes now disagree on is a REFUSAL with the row's name, not a silent green. A gate that
# has no divergence list has no shape in which one can rot; what it still owes is the census, and the
# census lives in the file.
#
# WHAT WAS DELETED HERE, AND WHY IT WAS NOT RENAMED. `OPS_VALUE` was the four row names the class-2
# prediction failed on, and it was an INPUT: it decided which rows the check even looked at, so four
# rows that came back equal could not re-enter the class without an edit to this file. `REMOVED_BY_UPSTREAM`
# was `("GROUP", "FLIP")`, typed into a file whose own docstring said the gate "finds them itself", and it
# fired BEFORE ANY PIN WAS READ -- so `_absent(declared, upstream)` measuring `{}` returned False
# whatever the pins said, which is a gate measuring nothing and calling it a verdict. Both are gone,
# and the names `GROUP` and `FLIP` survive in the module docstring above as the historical record
# they are.
DIVERGING = ()


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


def _body(def_re):
  """The body of one `def` in `uop/ops.bend`, by ITS OWN signature -- not by line number.

  `AGENTS.md` on line-number citations: a locator that a rename invalidates is not a locator.
  Every arm table below is read through its `def` header, so a file that grows above them moves
  nothing, and an arm table that is RENAMED stops being read at all -- which is a `False` in the
  checks that use this, not a silent zero.
  """
  m = re.search(def_re + r"[^\n]*:\n(.*?)\n(?=\S)", OPS_BEND.read_text(), re.S)
  if m is None:
    raise ValueError(f"no `{def_re}` in {OPS_BEND}")
  return m.group(1)


def _value_arms():
  """`(name, value)` per arm of `Ops.value`, IN SOURCE ORDER. `name` has no `Ops` prefix."""
  return re.findall(r"^\s*case Ops([A-Z0-9_]+)\{\}:\s*(\d+)\s*$", _body(r"def Ops\.value\(op: Op\)"), re.M)


def _name_arms():
  """`(variant, string)` per arm of `Ops.name.of`, IN SOURCE ORDER.

  BOTH halves, because the arm's key and the arm's answer are separate claims: the key must be the
  variant at that position and the answer must be that variant's own member name.
  """
  return re.findall(r'^\s*case Ops([A-Z0-9_]+)\{\}:\s*"([A-Z0-9_]+)"\s*$',
                    _body(r"def Ops\.name\.of\(op: Op\)"), re.M)


def _all_ops():
  """`Ops.value`'s SIBLING list `all_ops`, in source order -- `tuple(Ops)` / `GroupOp.All`."""
  return re.findall(r"Ops([A-Z0-9_]+)\{\}", _body(r"def all_ops\(\)"), re.M)


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


def _absent(names, universe):
  """`{name: 1-based position in `names`}` for every entry `universe` does NOT have. A SET DIFFERENCE.

  THE PRIMITIVE BOTH ENUMERATIONS ARE READ THROUGH, and it reads `universe` AS AN ARGUMENT rather than
  reaching for `git` itself, so `--plant` can difference two synthetic enumerations with the same code
  that differences the real ones. Nothing here names an `Op`.
  """
  have = set(universe)
  return {name: i for i, name in enumerate(names, 1) if name not in have}


def _header(n_div, n_same, declared, upstream):
  return f"""# opseven-pins.rows -- GENERATED by `gates/opseven-gate.py --refresh`, which is its ONLY
# writer. One TAB-separated triple per declared divergence: `<row>\\t<CPython's line>\\t<the port's
# line>`, i.e. the expected content on BOTH sides.
#
# {n_div} DECLARED DIVERGENCES, {n_same} OF THE {len(ROWS)} ROWS AGREE EXACTLY. It is git-resident and beside the
# gate because a gate's required inputs live in git and not in `gates/artifacts/`: `gatekit` EMPTIES
# that directory before it runs and UNLINKS what it staged when the run was not green, so a
# divergence list read from there is destroyed by the first red run and there is then nothing to edit.
# An empty census is still a census: it is `gates/opseven-gate.py`'s `DIVERGING = ()` MEASURED, and the
# gate refuses this file if it carries a row, which is what makes "no pins, nothing to check" false.
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
# `OPS_VALUE` IS NO LONGER A CLASS AND IS NOT RENAMED INTO ONE. Four of the seven `value_*` rows were
# pinned once, while the port declared more members than upstream -- the two upstream had deleted being
# `GROUP` and `FLIP` -- and the port has since dropped both, so the offset is zero, all {len(ROWS)} rows
# compare, and there is nothing to pin. `ops_value_holds` no longer predicts an offset FROM a list of
# deleted names: it differences the port's `type Op is Data:` block ({len(declared)} members) against
# `git show upstream:tinygrad/uop/__init__.py` ({len(upstream)} members) in BOTH directions and holds
# that both differences are empty AND that each `value_*` row sits at offset zero -- so the vacuity is a
# RESULT it reached rather than an empty set it was handed. Nothing here is transcribed and nothing needs
# a `--refresh` when upstream moves.
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
  declared = _declared_ops()
  out = [_header(len(rows), len(ROWS) - len(rows), declared, _upstream_ops())]
  for r in rows:
    out.append("# %-20s %-72s cpy %4dB %s | port %4dB %s" % (
      r, "declared divergence: the two lanes answer this row differently, and neither side is named",
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

  IT DOES NOT ASK WHETHER THERE ARE PINS. `if not DIVERGES: return False` sat above this body and is
  GONE: with the class-2 hand-lists deleted the divergence set is empty by measurement, so the guard
  made this check return False on a green tree -- a gate that refused to look because it had nothing to
  compare against, which is `DEAD` wearing the costume of a verdict. Both columns now come from the two
  LIVE lanes and from nowhere else; there is no fallback and no branch that can skip the assertions.
  """
  port, py = _lane("bd"), _lane("py")
  cpy = {r: py[r] for r in SP_ROWS if r in py}
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


def _value_positions_hold(declared, upstream, port, cpy) -> bool:
  """CLASS 2, RESTATED: the port's VALUE ROWS SIT AT THE SAME POSITIONS AS UPSTREAM's.

  THE OLD CLAIM WAS: "the port sits at an OFFSET from upstream equal to the number of
  upstream-deleted members the port still declares earlier", and it was graded FROM THE PIN -- only the
  port lane was read, "reading the live py lane instead would make the prediction grade its own input" --
  so its CPython side was four typed numbers, which is how `59/60/61/77` outlived the re-vendor that made
  them `58/59/60/75` and left the gate REFUSED at exit 3 having run neither lane. Both sides are live now
  and nothing is transcribed.

  THE VACUITY IS CHECKED, NOT ASSUMED. Four assertions, each of which can fail:

    1. `_absent(declared, upstream)` is empty -- the port declares no variant upstream lacks. Upstream
       deleted `GROUP` and `FLIP` and the port now declares neither, so this is the assertion that would
       have gone red on a port that had not caught up, and it is a MEASUREMENT rather than the old
       `sorted(removed) != sorted(REMOVED_BY_UPSTREAM)` comparison against two typed names;
    2. `_absent(upstream, declared)` is empty -- the OTHER direction, which the old one-sided
       difference could not express at all. A variant upstream has and the port lacks does not appear
       in `_absent(declared, upstream)`, so the old check read that world as "the port declares
       nothing extra" and then had only the port-side offset to notice it by; here it is named with
       the member and its upstream position before any row is compared;
    3. each of the seven `value_*` rows is present on BOTH live lanes -- a missing row is a named False
       and not a `KeyError`, so a lane that dropped one cannot read as agreement;
    4. and each sits at offset ZERO. Not "the offset the deleted members predict", which is the same
       claim with a list in front of it: zero, asserted, because the deletions are gone.

  `declared` is the port's own `type Op is Data:` block and `upstream` is `_upstream_ops()`'s reading of
  `git show upstream:tinygrad/uop/__init__.py`. Both lanes are live. Nothing is transcribed, and there
  is no branch that can skip these four assertions because a set happens to be empty.
  """
  pos = {name: i for i, name in enumerate(declared, 1)}
  extra, lacking = _absent(declared, upstream), _absent(upstream, declared)
  if extra:
    print(f"ops_value_holds: the port declares {sorted(extra)} at port positions "
          f"{sorted(extra.values())} and upstream does NOT -- the claim is that the two declare the SAME "
          f"Ops, so the port is behind upstream and its value rows cannot line up")
    return False
  if lacking:
    print(f"ops_value_holds: upstream declares {sorted(lacking)} at upstream positions "
          f"{sorted(lacking.values())} and the port's `type Op is Data:` block does NOT -- the port is "
          f"missing {len(lacking)} member(s) upstream has")
    return False
  for o in VALUE_OPS:
    r = f"value_{o}"
    for lane, vals in (("port", port), ("CPython", cpy)):
      if r not in vals:
        print(f"ops_value_holds: {r} is missing from the {lane} lane -- {len(vals)} row(s) staged")
        return False
    # `VALUE_OPS` is lowercase because it names the ROW (`value_custom`), and the declaration block is
    # uppercase because it names the member (`OpsCUSTOM`). `.upper()` is the join, and a missing key
    # here is a named False rather than a `KeyError`.
    if o.upper() not in pos:
      print(f"ops_value_holds: {o.upper()} is not in the port's `type Op is Data:` block")
      return False
    # `_lane` hands back the value WITHOUT the `row=` prefix, so these are the numbers themselves.
    port_v, cpy_v = int(port[r]), int(cpy[r])
    if port_v - cpy_v != 0:
      print(f"ops_value_holds: {r} is {port_v} on the port and {cpy_v} on CPython -- a difference of "
            f"{port_v - cpy_v}, and the claim is that the port's value rows sit at the SAME positions as "
            f"upstream's ({o.upper()} is declared at port position {pos[o.upper()]})")
      return False
  print(f"ops_value_holds: OPS_VALUE holds -- the port declares {len(declared)} variants and upstream "
        f"{len(upstream)}, `_absent()` is empty IN BOTH DIRECTIONS, and all {len(VALUE_OPS)} `value_*` "
        f"rows sit at offset ZERO on the two live lanes (nothing was pinned to compare them against)")
  return True


def ops_value_holds() -> bool:
  """THE CLAIM ABOVE, READ: the two enumerations and the two live lanes, and nothing else.

  A ONE-LINE WRAPPER on purpose, because every input is bound HERE and at run time rather than at
  import. `--plant` drives `_value_positions_hold` with synthetic enumerations and synthetic lanes and
  moves no module state at all, which is the shape `gates/gapcensus-gate.py` got wrong the first time
  it reported FAILED: an instrument whose subject it had already bound at import cannot be moved by
  anything, and a plant that cannot move the thing is not a plant.
  """
  declared = _declared_ops()
  return _value_positions_hold(declared, _upstream_ops(), _lane("bd"), _lane("py"))


def ops_value_is_declaration_order() -> bool:
  """THE CLAIM THE HEADER ABOVE MADE AND NOBODY MEASURED, NOW MEASURED: EVERY ARM, not 7 rows.

  The header used to say "`Ops.value` has **77** arms, `Ops.name.of` has **77**, `all_ops` has **77**, and
  **every one of the 77 sits at its own declaration position**". MEASURED, before this function
  existed: `classes_hold` reached `Ops.value` only through the FOUR rows in `DIVERGING`, and never
  opened `Ops.name.of` or `all_ops` AT ALL. So a header claim about 77 arms was carried by a check
  over 4 of them, and the other two tables were named as measured while nothing read them -- which is
  `AGENTS.md`'s own "AN INSTRUMENT THAT CANNOT SEE ITS POPULATION CANNOT BE WRONG, BECAUSE IT CANNOT
  BE ANYTHING", with the instrument quoting a number it never took. The count is `len(declared)` here
  rather than a figure in this sentence, because a header that carries a count stops carrying it the
  day the enum moves.

  This is the check a re-index needs and did not have. DELETING an upstream member renumbers every
  arm below it, and a renumbering that is off by one in a single arm is invisible to the four pinned
  rows -- they only ever read `CUSTOM CUSTOMI INS PYLITERAL`. So the failure it exists to catch is
  the one this task is about, and before it existed nothing would have caught it.

  It is PURELY ADDITIVE: no row is dropped, no pin moves, no expectation is rewritten. Every claim it
  makes is read out of `uop/ops.bend` and every population is DISCOVERED (`_declared_ops`, and the
  three tables' own bodies), never typed here.

  Four assertions, each of which can fail, and the first two name the FILE and the TABLE:

    1. all three tables carry exactly `len(declared)` entries -- a deleted arm is a LENGTH diff, not a
       silent shift, because a table one shorter would otherwise renumber every arm below it;
    2. each table lists the variants in DECLARATION ORDER, so arm *i* is variant *i*;
    3. `Ops.value`'s numbers are `1..N` with no gap and no repeat, which is `FastEnum`'s
       `_generate_next_value_` (`1 + max`) expressed as the claim it actually is;
    4. `Ops.name.of`'s arm *i* answers variant *i*'s OWN member name, so the string cannot drift off
       the key it is keyed by.
  """
  declared = _declared_ops()
  # `all_ops` is a LIST of variants, so it yields names where the two `match` tables yield
  # `(key, answer)` pairs. Normalising here rather than in the parsers keeps each parser reading as
  # the shape its own table has in the source.
  value, names = _value_arms(), _name_arms()
  for label, table in (("Ops.value", value), ("Ops.name.of", names), ("all_ops", _all_ops())):
    keys = [k for k, _ in table] if label != "all_ops" else table
    if len(keys) != len(declared):
      print(f"ops_value_is_declaration_order: {label} has {len(keys)} entries and "
            f"`type Op is Data:` has {len(declared)} variants in {OPS_BEND.name}")
      return False
    if keys != declared:
      i = next(j for j, k in enumerate(keys) if k != declared[j])
      print(f"ops_value_is_declaration_order: {label} entry {i + 1} is {keys[i]}, "
            f"not {declared[i]} -- it is not in the declaration block's order")
      return False
  if [int(v) for _, v in value] != list(range(1, len(declared) + 1)):
    print(f"ops_value_is_declaration_order: Ops.value's numbers are not 1..{len(declared)} with no gap "
          f"and no repeat, so it is not FastEnum's `1 + max` over its own declaration order")
    return False
  if [k for k, s in names] != [s for k, s in names]:
    print("ops_value_is_declaration_order: an `Ops.name.of` arm does not answer its own variant's name")
    return False
  print(f"ops_value_is_declaration_order: OPS_VALUE's THREE tables hold -- Ops.value, Ops.name.of and "
        f"all_ops each carry {len(declared)} entries, every one at its own declaration position, and "
        f"Ops.value numbers them 1..{len(declared)} with no gap")
  return True


def classes_hold() -> bool:
  return spec_program_holds() and ops_value_holds() and ops_value_is_declaration_order()


GATE = Gate(
  "opseven-gate",
  bend="opseven.bend",
  oracle="opseven-oracle.py",
  rows=len(ROWS),
  compared=len(ROWS) - len(DIVERGING),
  diverges=DIVERGES or {},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def plant() -> int:
  """THE SIX STATES OF THE CLASS-2 CLAIM, IN TOKEN AND EXIT CODE -- no `bend` runs, no lanes read.

      .venv/bin/python gates/opseven-gate.py --plant

  ONE GREEN AND FIVE RED, BECAUSE THE FAILURE MODE THIS FILE WAS ASKED TO AVOID IS "no pins, so there
  is nothing to predict, so PASS". If the class-2 claim could not go red on its own, deleting
  `OPS_VALUE` and `REMOVED_BY_UPSTREAM` would have been a weakening dressed as a simplification, and
  the gate would have said nothing about the seven `value_*` rows at all. `--plant` is what says it
  still says something.

  THE STATES, AND WHICH ASSERTION EACH ONE EXERCISES:

    HOLD                 the two enumerations agree and every `value_*` row sits at the same position
                         on both lanes -- the vacuous prediction, VACUOUS AND THEREFORE TRUE;
    OFFSET               the port's `value_custom` sits one position higher than CPython's, with both
                         enumerations still equal -- assertion 4, and the state a silent renumbering
                         produces;
    PORT-HAS-A-VARIANT   upstream's enumeration drops `CUSTOM`, so the port declares a member upstream
                         lacks -- assertion 1, the shape the deleted `GROUP`/`FLIP` would have had if
                         the port had not followed upstream;
    UPSTREAM-HAS-A-ONE   upstream's enumeration grows `CUSTOM2` -- assertion 2, the direction the old
                         one-sided difference could not see at all;
    MISSING-ROW          the port lane has no `value_pyliteral` -- assertion 3, and a NAMED False
                         rather than a `KeyError` that `gate()` would score as an honest FAIL;
    WRAPPER-RUNS         `ops_value_holds()` ITSELF, against an artifact directory with nothing in it.
                         The former `if not DIVERGES: return False` at the head of this check
                         returned False here too, so the exit code cannot tell that guard from a real
                         finding and this state reads the MESSAGE instead: it must name the missing row,
                         which is only reachable if the function got past the guard into the
                         assertions.

  NOTHING IS BOUND AT IMPORT AND NOTHING IS ARMED, SO THERE IS NOTHING TO DISARM. Every input to
  `_value_positions_hold` is a local here: the enumerations come from `_declared_ops()` and
  `_upstream_ops()` (the tree) and the lane dicts are built by `_plant_lanes` from the declaration's own
  positions, so no expected VALUE is transcribed and no file is written, edited or unlinked. The only
  module state the plant touches is `ART`, rebound inside a `try`/`finally` so the last state reads
  "the temp directory" is impossible.
  """
  declared = _declared_ops()
  upstream = _upstream_ops()
  same = _plant_lanes(declared)
  off = dict(same)
  off["value_custom"] = str(int(same["value_custom"]) + 1)
  holed = {k: v for k, v in same.items() if k != "value_pyliteral"}
  behind = [n for n in upstream if n != "CUSTOM"]
  ahead = list(upstream) + ["CUSTOM2"]
  cases = (
    ("HOLD", declared, upstream, same, dict(same), True),
    ("OFFSET", declared, upstream, off, dict(same), False),
    ("PORT-HAS-A-VARIANT", declared, behind, dict(same), dict(same), False),
    ("UPSTREAM-HAS-A-ONE", declared, ahead, dict(same), dict(same), False),
    ("MISSING-ROW", declared, upstream, holed, dict(same), False),
  )
  bad = []
  for name, decl, up, port, cpy, want in cases:
    got = _value_positions_hold(decl, up, port, cpy)
    print(f"  {name:<20} {'HELD' if got else 'RED ':<6} rc={0 if got else 1}"
          + ("" if got == want else f"  <-- EXPECTED {'HELD' if want else 'RED '}, THE PLANT IS WRONG"))
    if got != want:
      bad.append(f"{name}: {'HELD' if got else 'RED'}, expected {'HELD' if want else 'RED'}")
  # THE WRAPPER, with the artifact directory pointed somewhere empty. `ART` is rebound inside the
  # `try` so a reader can see the plant cannot leave it there.
  keep, buf = ART, io.StringIO()
  try:
    with tempfile.TemporaryDirectory() as td:
      globals()["ART"] = Path(td)
      with contextlib.redirect_stdout(buf):
        got = ops_value_holds()
  finally:
    globals()["ART"] = keep
  named = any(r in buf.getvalue() for r in VALUE_ROWS)
  print(f"  {'WRAPPER-RUNS':<20} {'HELD' if got else 'RED ':<6} rc={0 if got else 1}"
        + ("" if (not got and named) else
           "  <-- the assertions were never reached, so this check measures nothing"))
  if got or not named:
    bad.append(f"WRAPPER-RUNS: {'HELD' if got else 'RED'}"
               + ("" if named else " without naming a missing row"))
  print(f"--plant: {'all ' + str(len(cases) + 1) + ' states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
  return 1 if bad else 0


def _plant_lanes(declared):
  """`{row: value}` for the seven `value_*` rows, BUILT FROM THE DECLARATION rather than typed.

  Each value is the variant's OWN 1-based position, which is what "the two lanes sit at the same
  positions" means, so the plant never transcribes a number the tree already knows.
  """
  pos = {n: str(i) for i, n in enumerate(declared, 1)}
  return {f"value_{o}": pos[o.upper()] for o in VALUE_OPS}


def main() -> int:
  if "--plant" in sys.argv:
    return plant()
  if "--refresh" in sys.argv:
    return refresh()
  if WHY:
    print(f"== REFUSED, NOT A VERDICT: opseven-gate: {WHY}", file=sys.stderr)
    return 3
  return gate(GATE,
              f"opseven-gate: PASS -- {len(ROWS)} rows, {len(ROWS) - len(DIVERGING)} compared exactly, "
              f"{len(DIVERGING)} declared divergences; the standing claims are that the port's "
              f"`spec_program` is not a constant and that the port's `Ops` and upstream's are the same "
              f"members at the same positions, read from both live lanes", checks=classes_hold)


if __name__ == "__main__":
  sys.exit(main())