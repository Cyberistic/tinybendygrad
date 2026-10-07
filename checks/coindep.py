"""THE CO-INDEPENDENT DECLARATIONS -- one module, N consumers, loaded BY PATH.

WHY THIS EXISTS. `coindependent`'s sweep found FIVE pairs of instruments that assert one fact
from two independently-edited literals, where the PASS condition is that the two literals agree.
Agreement-by-two-copies is a rubber stamp: a shared OMISSION is invisible to both, which is the
`names.py`/`ARMED` shape (a 3-name hand list; a FOURTH substituted graph was invisible to both
until the set was DERIVED). This module is the `gates/gendirs.py` fix -- a single declaration,
loaded by path -- for the three pairs that ARE the same fact.

WHAT IS HERE, AND WHAT DELIBERATELY IS NOT:

  ABI_OTHER_TOKENS   pair 1  `checks/abi_gate.py` `JS_ARM_TOKENS` <-> `checks/abi4_gate.py`
                             `OTHER_ABI_TOKENS`.  Identical 9 strings.  WIDENED (see below).
  I64SHL_VALUES      pair 3  `gates/i64-shl-gate.py`'s inline value tuple <-> the oracle's
                             `VALUES` NAMES.
  SKIP_DIRS          pair 5  `checks/no-strays.py` <-> `checks/unowned.py`.

WHAT IS NOT HERE, AND WHY:
  * pair 2 (`gates/mixin-op-gate.py` `port_only` <-> the oracle's `BEND_ONLY`) is DELIBERATELY
    REDUNDANT and stays two copies: the gate's row-count check compares its declaration against
    the ORACLE'S OWN OUTPUT, so an oracle that read the gate's list would be checked against
    itself.  An oracle must not be told what the gate expects.
  * pair 4 (`checks/disagree-gate.py` `ARMED` <-> `checks/differ.py` `WANT`) is NOT THE SAME
    FACT: ARMED says "the dispatcher routes these three to their own builder" and WANT says
    "these graphs' run verdicts are AGREE".  Same three NAMES, two different predicates.

THE WIDENING OF `ABI_OTHER_TOKENS`, WITH ITS EVIDENCE.  The fence is a CONTENT check: an arm
whose bytes mention another ABI's token is not an ABI-4 arm.  The 9 hand-written strings cover
ABI-1/2/3/5 markers only by SUPERSTRING -- `>>> 32n` covers `>> 32n`, `BigInt` covers
`BigInt.asIntN`/`asUintN` -- and a discovery over the tree's other-ABI vocabulary
(`tinybendygrad/runtime/dtype.js` + `checks/abi_gate.py`'s own ABI-2 edit constants +
`checks/jsfix_gate.py`'s ABI-5 plant) finds markers NO token covers:

    `pack64`, `i64_of`   (the ABI-1/2 helpers, rewritten by the ABI-2 repair)
    `Number(`            (the ABI-5 marker: the words must reach BigInt as JS numbers)
    `$: "tinybendygrad/helpers.I64"`  (the ABI-2 outbound record tag -- the fence names the
                                      WRONG outbound shape `io_tup`, not the right one)

NONE of these four strings occurs in ANY legitimate ABI-4 arm (`fp8_decode` / `dtype_fp16` /
`dtype_fp8_to` and their plants/disarms/ALT), so adding them cannot false-positive; they are a
DEFECT in the fence, not a scope statement.  The 9th token, `>>> 32n`, is a PHANTOM -- it occurs
NOWHERE in the tree outside the three hand lists -- which is the evidence that the list was not
derived from anything.
"""

# pair 1.  The 9 original tokens + the 4 discovered, uncovered other-ABI markers.
ABI_OTHER_TOKENS = (
    # --- original 9, character-identical in both gates before this module
    "p.hi", "p.lo", "p.fst", "p.snd", "io_tup", "BigInt", "asIntN", "<< 32n", ">>> 32n",
    # --- WIDENED: discovered by scanning the other ABIs' own bytes (see module docstring)
    "pack64", "i64_of", "Number(", '$: "tinybendygrad/helpers.I64"',
)

# pair 3.  The fixture VALUE names.  The oracle also holds each name's two U32 words; only the
# NAMES are shared, because the words are the oracle's own measurement.
I64SHL_VALUES = ("neg1", "one", "lowhi")

# pair 5.  Top-level directories that are not part of the population.  The two instruments apply
# the set differently (`no-strays` prunes walk dirnames; `unowned` substring-tests a git path),
# and that difference is theirs to keep -- only the SET is shared.
SKIP_DIRS = (".git", ".venv", "__pycache__", "node_modules", "references")
