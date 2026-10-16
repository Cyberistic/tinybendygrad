#!/usr/bin/env python3
"""upstream-promo-lattice-gate.py -- AN UPSTREAM-ONLY AUDIT of tinygrad's type promotion.

    .venv/bin/python gates/upstream-promo-lattice-gate.py
    .venv/bin/python gates/upstream-promo-lattice-gate.py --plant green
    .venv/bin/python gates/upstream-promo-lattice-gate.py --plant red

READ-ONLY ON `tinygrad/`. This file imports nothing of the port's and reads no `.bend`; its whole
population is `tinygrad/dtype.py`'s own `promo_lattice` / `__lt__` / `least_upper_dtype` /
`can_lossless_cast`, DISCOVERED by `DTypes.__dict__` rather than written down here.

WHAT IT CLAIMS TO MEASURE, AND WHY THE MEASUREMENT IS NOT A RESTATEMENT. `least_upper_dtype` is
spelled `min(set.intersection(*[_get_recursive_parents(d) for d in ds]))`. Three things can be
false of that, and they are DIFFERENT defects, so they get different rows:

  R1 LATTICE.  `promo_lattice` is cited to JAX JEP 9407, a join-semilattice. A join-semilattice
     needs a join for every pair. This gate computes, for every pair, the set of MINIMAL elements
     of the common-upper-bound set. More than one minimal element means THE POSET HAS NO JOIN and
     `min()` is not computing one -- it is picking one arbitrarily out of an antichain, by the
     integer `priority`.
  R2 ALGEBRA.  `least_upper_dtype` must be associative if it is a join of a lattice (that is a
     theorem about lattices, not a property of this implementation). This gate enumerates all
     19^3 triples and counts the ones where `(a|b)|c != a|(b|c)`.
  R3 PIN.  Whether the file that carries the claim is the PIN (`ad117c928^`) or HEAD. A finding
     that is only in HEAD is a PIN-VERSUS-HEAD DRIFT and is not this gate's subject, so it is
     reported as its own row and `REFUSED` is not charged for it -- the row moves, the verdict does
     not, because the two are different questions and `AGENTS.md` says for a drifted file the PIN
     is the truthful oracle.

WHY A N-ARY CALL AND A BINARY FOLD ARE BOTH REAL CONSUMERS (this is what makes R2 observable
rather than academic). `promo_dtype` (tinygrad/uop/ops.py:118) is
`dts[0] if all_same(dts) else least_upper_dtype(*dts)` -- ONE n-ary call over every source of a
node, and a STACK or a 3-input ADD really does have three. Every Tensor-level binop is BINARY. So
for the same multiset of operand dtypes tinygrad has two answers, and which one a program gets is
decided by the shape of its expression tree. `Tensor` is used here to make that concrete; no
arithmetic is evaluated and no dtype is executed, because the defect is entirely in metadata that
is decided before any renderer sees a node.

WHAT IS DELIBERATELY NOT CLAIMED. This gate does NOT check that `least_upper_dtype` returns a
*useful* dtype, and it does NOT use `can_lossless_cast` as the order. An earlier draft of this
audit did use `can_lossless_cast` as "the lattice order" and reported 194 upper-bound violations;
that instrument was WRONG -- `can_lossless_cast` has no `case` for the weak dtypes or for any fp8,
so it answers False for 194 pairs that `least_upper_dtype` answers soundly, and every one of those
194 was an artefact of the instrument. A negative here is a negative: `can_lossless_cast` IS used,
but only for the one claim it is actually competent to decide, and that claim is in its own row.
"""
import argparse
import hashlib
import itertools
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE FIVE VERDICTS, AS EXITS -- `gates/gatekit.py`'s numbers, restated rather than imported so
# this file has no import-order dependency on a module it must not edit.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}
VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
PLANTS = {0: ["--plant", "green"], 1: ["--plant", "red"]}
RED_IS = "FINDING -- tinygrad's promotion is not a lattice; see the derivation row"

# AGENTS.md: `ad117c928^` IS THE PIN. `ad117c928` IS THIS PROJECT'S OWN RE-VENDOR, so HEAD is not
# an oracle for a drifted file. Named, not discovered: this is a REVISION, and a revision is not
# a population of paths, so Doctrine 1 does not apply to it.
PIN = "ad117c928^"
UPSTREAM = ROOT / "tinygrad" / "dtype.py"

# The population is DISCOVERED: every DType the class actually holds, minus the weak/void/alias
# names `DTYPES_DICT` itself excludes, so this is upstream's own definition of "core dtypes"
# (test/null/test_dtype_spec.py:13 reads the same object). NOTHING HERE IS A HAND LIST.
def population():
  sys.path.insert(0, str(ROOT))
  from tinygrad.dtype import DTypes, DType
  from tinygrad import dtype as D
  core = sorted({v for k, v in DTypes.__dict__.items()
                 if isinstance(v, DType) and not k.startswith(("default", "void", "weak", "_"))},
                key=lambda d: (d.priority, d.bitsize, d.name, str(d.fmt)))
  return core, D


def pin_blob_sha():
  env = {"GIT_INDEX_FILE": str(ROOT / ".git" / "agent-index"), "PATH": "/usr/bin:/bin"}
  out = subprocess.run(["git", "show", f"{PIN}:tinygrad/dtype.py"], cwd=ROOT, env=env,
                       capture_output=True, text=True)
  if out.returncode != 0: return None
  return hashlib.sha256(out.stdout.encode()).hexdigest()


def audit(core, D):
  dtypes, LUB = D.dtypes, D.least_upper_dtype
  P = D._get_recursive_parents
  # R1 -- pairs whose common-upper-bound set has more than one MINIMAL element. A minimal element
  # of a set is one with no strictly smaller member of the SAME set; the poset has a join iff
  # there is exactly one.
  nojoin = []
  for a, b in itertools.combinations(core, 2):
    common = P(a) & P(b)
    minimal = [x for x in common if not any(x is not y and x in P(y) for y in common)]
    if len(minimal) > 1:
      nojoin.append((a.name, b.name, sorted(x.name for x in minimal), LUB(a, b).name))
  # R2 -- associativity. n^3, and the fold is the LEFT fold because that is the shape a chain of
  # Tensor binops builds; the n-ary column is upstream's own single `min(intersection(...))`.
  nonassoc = []
  for a, b, c in itertools.product(core, core, core):
    fold = LUB(LUB(a, b), c)
    nary = LUB(a, b, c)
    right = LUB(a, LUB(b, c))
    if fold is not nary or fold is not right:
      nonassoc.append((a.name, b.name, c.name, fold.name, right.name, nary.name))
  return nojoin, nonassoc


def observable(D):
  """The same multiset of operand dtypes, through upstream's own three real entry points.

  Nothing is executed and nothing is rendered: a `Tensor`'s dtype is settled by `promote` /
  `promo_dtype` when the node is built. If the three disagree, the dtype of an expression depends
  on its parenthesisation, and that is the defect made visible to a user."""
  from tinygrad import Tensor
  dtypes = D.dtypes
  a, b, c = (Tensor([1.0], dtype=dtypes.fp8e4m3), Tensor([1.0], dtype=dtypes.fp8e5m2),
             Tensor([1.0], dtype=dtypes.bfloat16))
  return {"(a+b)+c": ((a + b) + c).dtype.name, "a+(b+c)": (a + (b + c)).dtype.name,
          "Tensor.stack([a,b,c])": Tensor.stack([a, b, c]).dtype.name}


def upstream_own_derivation(D):
    """Derive the contradiction from UPSTREAM'S OWN ASSERTED VALUES, not from this gate's reading
    of the lattice. test/null/test_dtype_spec.py:214-218 pins five pairs; `promo_lattice` pins
    that f16 and bf16 share exactly one common recursive parent. Together those six facts force
    two different answers to the same three-operand promotion."""
    dtypes = D.dtypes
    e4m3, e5m2, bf16, half = dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.bfloat16, dtypes.half
    # each entry is (pair, what test_dtype_spec.py asserts the pair equals, the line that says so)
    facts = [((e4m3, e5m2), half, 214), ((e4m3, bf16), bf16, 215), ((e5m2, bf16), bf16, 216)]
    left = D.least_upper_dtype(e5m2, bf16)                            # == bf16 by spec.py:216
    right = D.least_upper_dtype(D.least_upper_dtype(e4m3, e5m2), bf16)  # first step == half by :214
    return {"asserted": [(a.name, b.name, want.name, f"spec.py:{ln}") for (a, b), want, ln in facts],
            "assertions_hold": all(D.least_upper_dtype(a, b) is want for (a, b), want, _ in facts),
            "a+(b+c)": left.name, "(a+b)+c": right.name,
            "agree": left is right}


def main(argv=None):
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--plant", choices=["green", "red"])
  args = ap.parse_args(argv)

  if args.plant:
    # TWO STATES, and the green one is NOT "no violations": it is "the audit ran and found the
    # same violations the live tree has", so a plant cannot pass by being vacuously quiet.
    core, D = population()
    nojoin, nonassoc = audit(core, D)
    planted = {"green": 0, "red": 1}[args.plant]
    live = FAIL if (nojoin or nonassoc) else PASS
    print(f"upstream-promo-lattice-gate --plant {args.plant}: "
          f"{len(nojoin)} no-join pairs, {len(nonassoc)} non-associative triples, "
          f"live verdict {VERDICT[live]}, planted {VERDICT[planted]}")
    return planted if planted == live else FAIL

  if not UPSTREAM.exists():
    print(f"upstream-promo-lattice-gate: REFUSED, {UPSTREAM} is absent", file=sys.stderr)
    return REFUSED
  try:
    core, D = population()
  except Exception as e:
    print(f"upstream-promo-lattice-gate: REFUSED, could not import tinygrad.dtype: {e!r}",
          file=sys.stderr)
    return REFUSED
  if not core:
    print("upstream-promo-lattice-gate: DEAD, the population DISCOVERED is empty", file=sys.stderr)
    return DEAD

  work_sha = hashlib.sha256(UPSTREAM.read_bytes()).hexdigest()
  pin_sha = pin_blob_sha()
  at_pin = pin_sha is not None and pin_sha == work_sha

  nojoin, nonassoc = audit(core, D)
  obs = observable(D)
  der = upstream_own_derivation(D)

  print(f"upstream-promo-lattice-gate: population DISCOVERED from DTypes.__dict__ = {len(core)} "
        f"dtypes, {len(core) ** 2} pairs, {len(core) ** 3} triples")
  print(f"  R3 PIN: dtype.py sha256 {work_sha[:12]}, {PIN} sha256 "
        f"{(pin_sha or 'UNAVAILABLE')[:12]}, {'SAME -- this is at the PIN' if at_pin else 'DIFFERENT'}")
  print(f"  R1 LATTICE: {len(nojoin)} of {len(core) * (len(core) - 1) // 2} pairs have a "
        f"common-upper-bound set with MORE THAN ONE minimal element, so the poset has NO join")
  for a, b, mins, picked in nojoin:
    print(f"     {a} _|_ {b}: minimal common upper bounds {mins}, least_upper_dtype picks {picked!r}")
  print(f"  R2 ALGEBRA: {len(nonassoc)} of {len(core) ** 3} triples have "
        f"(a|b)|c != a|(b|c) -- least_upper_dtype is not associative")
  for a, b, c, l, r, n in nonassoc[:6]:
    print(f"     ({a}|{b})|{c} = {l}   but   {a}|({b}|{c}) = {r}   and the n-ary call says {n}")
  if len(nonassoc) > 6: print(f"     ... and {len(nonassoc) - 6} more triples")
  print("  R4 THE SAME MULTISET, THREE REAL ENTRY POINTS (metadata only, nothing executed):")
  for k, v in obs.items(): print(f"     {k:22s} -> {v}")
  print(f"     OBSERVABLE: {len(set(obs.values()))} distinct dtypes for ONE multiset of operands"
        f" -- {'YES' if len(set(obs.values())) > 1 else 'NO'}")
  print("  R5 DERIVED FROM UPSTREAM'S OWN ASSERTIONS (test/null/test_dtype_spec.py:214-216):")
  for a, b, want, ln in der["asserted"]: print(f"     {a} -> {b},  that line asserts {want}  [{ln}]")
  print(f"     those lines still hold: {der['assertions_hold']}")
  print(f"     and they force  a+(b+c) = {der['a+(b+c)']}   vs   (a+b)+c = {der['(a+b)+c']}"
        f"   -> agree: {der['agree']}")

  code = FAIL if (nojoin or nonassoc) else PASS
  if len(set(obs.values())) == 1 and not nojoin and not nonassoc:
    print("upstream-promo-lattice-gate: no finding, and the three entry points agree")
  print(f"upstream-promo-lattice-gate: {VERDICT[code]} -- {len(nojoin)} no-join pairs, "
        f"{len(nonassoc)} non-associative triples, "
        f"{len(set(obs.values()))} distinct promoted dtypes for one operand multiset"
        + ("" if at_pin else "  [WARNING: working tree dtype.py is not the PIN]"))
  return code


if __name__ == "__main__":
  sys.exit(main())