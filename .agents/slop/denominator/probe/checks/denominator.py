"""denominator.py -- ONE assertion for the denominator class, loaded BY PATH.

`checks/coindep.py` is the precedent this file follows: *one module, N consumers, loaded by
path* -- because a second copy of a rule is a contract with no generator, and it rots without
anyone noticing.

WHY THIS EXISTS.  `checks/dup-census.py:202` reads `checks/lanes/`, a directory that is **not in
git at all** (`git ls-tree -r HEAD --name-only | grep -c 'checks/lanes/'` = 0).  Restoring one
swept input turned its truthful `REFUSED (3)` into a green `OK (0)` that printed `0 of 0` -- and
then `dup-census.py:276` **overwrote a tracked 797,251-byte census with `[]`**.  Reproduced in an
isolated probe tree; see `.agents/slop/denominator/REPORT.md`.

THE RULE, and it is one line:

    A COUNT OF ZERO IS A REFUSAL UNLESS THE GATE CAN PROVE IT LOOKED.

THE TWO FUNCTIONS SPLIT THAT RULE ALONG THE LINE WHERE IT ACTUALLY BITES, and the split is the
reason a genuine zero is not a special case needing an escape hatch:

  `enumerate_population`  -- for INPUTS.  Refuses ONLY when the source is not a readable
    directory, i.e. when nothing was walked.  It NEVER fires on a source that exists and is
    legitimately empty, so a census that genuinely finds nothing passes here untouched.

  `require_denominator`   -- for DIVISORS, and only for divisors.  A gate that computes
    `n of m` or `n/m` has made 0 an undefined ratio, which is not the same claim as "zero were
    found".  `require_denominator` refuses that, and refuses nothing else.

SO `checks/gates-pop.py`, which enumerates `gates/*.sh` and correctly reports **0** beside 62
`.py`, uses `enumerate_population` and is untouched: *"the shell form is retired"* is its
finding, it has a real denominator (62 files), and zero findings is a PASS.  A gate that would
have been damaged by this assertion is one that DIVIDES BY the count, and there are far fewer
of those -- which is what makes this safe to land in a tranche.
"""
import pathlib
import sys

# `gates/gatekit.py:59` SPELLS THE FIVE VERDICTS AS EXITS: PASS, FAIL, REFUSED, SKIP, DEAD =
# 0, 1, 3, 4, 5.  This module reuses 3 and nothing else.
REFUSED = 3


def refuse(why: str) -> "None":
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Before any assertion it asserts, because an assertion DOWNSTREAM of what it asserts cannot
  turn a bad state into a verdict -- it can only produce a traceback, which carries no
  denominator and so counts nowhere.
  """
  print("== REFUSED, NOT A VERDICT: " + why, file=sys.stderr)
  raise SystemExit(REFUSED)


def enumerate_population(source: pathlib.Path, pattern: str, what: str) -> "list[pathlib.Path]":
  """The population, READ -- and the proof that the caller looked.

  A source that is absent, or is a file, or is anything but a directory, is a REFUSAL: nothing
  was enumerated, so no count over it is an answer.  This is the single check that stops
  `dup-census.py`'s `CACHE.glob()` over an absent directory from reading as a clean lane.

  A source that EXISTS and matches nothing is returned empty, deliberately and without comment,
  because that is a genuine answer: `gates/*.sh` is empty and that is true.
  """
  if not source.is_dir():
    refuse(f"{what}: population source is not a directory: {source}\n"
           "         nothing was enumerated, so a count over it is not an answer")
  return sorted(source.glob(pattern))


def require_denominator(found: int, what: str, source: pathlib.Path) -> int:
  """Assert a DIVISOR is usable, and return `found` so the call can stay in the expression.

  Called where a count becomes a RATIO -- `n of m`, `n/m`, a percentage, a mean -- and nowhere
  else.  **Refuses on ANY zero**, because at a divisor zero is not an answer, it is an
  undefined ratio: `0 of 0` is indistinguishable from a gate that never looked.

  THE CALL-SITE IS THE DISCRIMINATOR, and that is the whole risk of this function, so it is
  stated rather than hidden.  Whether a zero is fatal is a fact about the CALLER:

    * `dup-census.py`'s divisor IS its own population (`TOTAL over N lane texts`, `N of M`),
      so an empty cache means nothing was examined and 0 must never read as a clean census.
    * `gates-pop.py`'s 0 is a NUMERATOR over a declared denominator of 62 files -- "no shell
      gates remain" is a real finding -- so it calls `enumerate_population` and never this.

  A gate whose honest answer is "zero" therefore does not call this; it enumerates and reports.
  There is no flag and no escape hatch, because the distinction is not a property of the
  number -- it is a property of what the number is divided by, and only the caller knows.
  """
  if found == 0:
    refuse(f"{what}: the DENOMINATOR is 0.  A ratio with a zero divisor cannot distinguish\n"
           f"         'zero found' from 'never looked' (enumerated from {source}), so this\n"
           "         gate refuses rather than printing a figure that means nothing")
  return found