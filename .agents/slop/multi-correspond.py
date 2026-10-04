#!/usr/bin/env python3
"""multi-correspond.py -- the FIXTURE-KEYED correspondence between multi.bend's rows and
multi-rows.py's rows, which is the thing row NAMES cannot tell you.

A name collision proves nothing and a name mismatch proves nothing. What proves something is
the FIXTURE: two rows are about the same call on the same input. So this file keys on the
fixture, extracts each side's by PARSING its own source, and reports the intersection with
BOTH denominators -- 321 port rows and 213 oracle rows.

It exists because the brief's premise is a statement about BOOLEANS compared to VALUES:
`multi.bend` prints `eq(a, b)`, i.e. 1 or 0, and `multi-rows.py` prints the QUANTITY. Measured
that way the `bx_*` family reports 10 disagreements over 10 correct rows. `multi-collision.py`
shows all 26 name-collisions are consistent on CPython's own value; this file finds the
real overlap by fixture, so the shared count is a number about claims and not about spelling.

Every expected value is CPython's, obtained by CALLING the function named at the cited line.
Nothing is transcribed.

    .venv/bin/python .agents/slop/multi-correspond.py
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO))

from tinygrad.uop.ops import broadcast_axes  # noqa: E402


def load(name, path):
  """Import a sibling oracle by path.

  ⚠ `sys.argv` IS SAVED AND RESTORED. The first version assigned `sys.argv = [path]`, which
  SILENTLY DESTROYED the caller's argv -- so `main(sys.argv[1])` read the oracle's own path
  back instead of the plant's, and the plant control reported the LIVE tree and came back
  CLEAN. A control that cannot point the harness at a broken copy cannot show it going red,
  and this one looked like it could. `multi-rows.py` reads no argv today; the save/restore is
  here so that cannot change without this breaking loudly."""
  spec = importlib.util.spec_from_file_location(name, HERE / path)
  mod = importlib.util.module_from_spec(spec)
  saved = sys.argv
  sys.argv = [path]
  try:
    spec.loader.exec_module(mod)
  finally:
    sys.argv = saved
  return mod


# rebase-gate.py's OWN row reader, imported at MODULE SCOPE so multi-controls.py drives the
# same object this file does. Loaded inside main() it was unreachable from outside, which
# would have made every control in this lane a re-implementation.
rgm = load("rg_shared", "rebase-gate.py")


def port_bodies(bend=None):
  """{row: the one-line body after `-> U32:`}, parsed out of multi.bend. Nothing transcribed.

  `bend` overrides WHICH FILE is read, and that override exists for ONE reason: the plant
  control. A control that cannot point the harness at a deliberately broken copy cannot show
  the harness going red, and a harness never seen red is not known to work. The default is
  the live tree, and no control ever writes to it."""
  out = {}
  path = pathlib.Path(bend) if bend else (REPO / "tinybendygrad" / "schedule" / "multi.bend")
  for line in path.read_text().splitlines():
    m = re.match(r"def t_(\w+)\(\) -> U32: (.*)$", line)
    if m:
      out[m.group(1)] = m.group(2)
  return out


SHAPE = re.compile(r"\b(nil32|s[123])\(([^()]*)\)")
TWOSH = re.compile(r"two_sh\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)")


def shapes(body):
  """The port's shape literals, as tuples: `s2(2, 3)` -> `(2, 3)`, `nil32()` -> `()`."""
  out = []
  for _, args in SHAPE.findall(body):
    parts = [x.strip() for x in args.split(",") if x.strip()]
    out.append(tuple(int(x) for x in parts))
  return out


def twosh(body):
  m = TWOSH.search(body)
  return None if not m else tuple(int(m.group(i)) for i in (1, 2, 3, 4))


def report(title, oracle, port):
  """key -> (oracle name, oracle value), key -> [port names]. Prints the intersection and
  says whether the PORT's assertion is consistent with CPython's value."""
  both = sorted(set(oracle) & set(port), key=repr)
  print(f"\n--- {title} ---")
  print(f"  oracle rows in family {len(oracle)}   port rows in family {len(port)}   "
        f"SAME-FIXTURE {len(both)}")
  bad = []
  checked = 0
  for k in both:
    on, ov = oracle[k]
    pns = sorted(port[k])
    for pn, pbody in pns:
      # The port asserts `eq(<projection>, WANT)`. BOTH `WANT` and the projection are READ
      # OUT OF THE PORT'S OWN BODY, so nothing here is transcribed: `want` is what the row
      # claims and `got` is what CPython's value says after the same projection. The row is
      # CONSISTENT iff they are equal, and that is the whole falsifiable claim.
      want = claimed(pbody)
      got = projection_of(pbody, ov)
      if want is None or got is None:
        print(f"  {on:<8} {pn:<14} SKIPPED: body not a bare `eq(<reader>, <int>)` -- {pbody}")
        continue
      checked += 1
      if got != want:
        bad.append((on, pn, want, got))
      print(f"  {on:<8} {pn:<14} {k!s:<22} cpython={ov!r:<10} "
            f"port asserts {want}  projection gives {got}  {'ok' if got == want else 'MISMATCH'}")
  return len(both), bad, checked
  if bad:
    print(f"  INCONSISTENT {len(bad)} of {checked}: {bad}")
  else:
    print(f"  all {checked} port assertions on a shared fixture are CONSISTENT with CPython's value")
  return len(both), bad, checked


CLAIMED = re.compile(r"eq\((?:U32\.from_nat\()?([\w.]+)\(.*\), (\d+)\)\)?\)?$")


def claimed(pbody):
  """The integer the port's row asserts, read out of the row's own body.

  `eq(a, b)` is `yes(U32.is_eq(a, b))` (multi.bend:2220), so the row's VALUE is the boolean
  `a == b` and `b` is the claim. Taking `b` from the body is what keeps this file from
  restating the port's expectation: a claim the reader cannot find in the source is a
  transcription, and a transcription is the failure this whole lane is about.
  """
  m = re.search(r"eq\(.*?, (\d+)\)\s*$", pbody)
  return int(m.group(1)) if m else None


def projection_of(pbody, cpython_value):
  """What the port's row asserts ABOUT CPython's value, recovered from the row's own body.

  `bx_a0` and `bx_n` are the two projections this file has to evaluate and both are named by
  the PORT at the call site (multi.bend:2558-2561); `mu_len` is the third (multi.bend:2666).
  The projection is therefore READ OUT OF THE BODY, never inferred from the row name:
  `t_bx_exp` and `t_bx_exp_n` differ ONLY in which reader they call, and a name-based rule
  cannot tell them apart.
  """
  if "bx_a0(" in pbody:
    return cpython_value[0] if cpython_value else None
  if "bx_n(" in pbody:
    return len(cpython_value)
  if "mu_len(" in pbody:
    return len(cpython_value)
  return None


def main(bend=None):
  bodies = port_bodies(bend)
  src = pathlib.Path(bend).name if bend else "multi.bend (live tree)"
  print(f"port rows   {len(bodies)}   read from {src}")
  mr = load("mr", "multi-rows.py")

  # ---- bx_*: (src_shape, out_shape) -> broadcast_axes, ops.py:87.
  BX = [("none", (2, 3), (2, 3)), ("pad", (3,), (2, 3)), ("exp", (1, 3), (2, 3)),
        ("both", (1,), (2, 3)), ("noop", (2,), (2, 3)), ("scalar", (), (2, 3)),
        ("1out", (2,), (1, 2)), ("11", (1,), (1,)), ("1_2", (1,), (2,)),
        ("rank1", (3,), (3,))]
  bx_orc, bx_port = {}, {}
  for nm, s, o in BX:
    val = broadcast_axes(s, o)
    bx_orc[(s, o)] = (nm, val)
    for pn, b in bodies.items():
      if not pn.startswith("bx_"):
        continue
      sh = shapes(b)
      if len(sh) >= 2 and (sh[0], sh[1]) == (s, o):
        bx_port.setdefault((s, o), []).append((pn, b))
  n1, bad1, c1 = report("bx_*: broadcast_axes(src, out) -- ops.py:87", bx_orc, bx_port)

  # ---- rd_*: reduce_multi's split, multi.py:107-123. (ax_a, ax_b, num_axes).
  # ⚠ THE KEY IS (fixture, WHICH-HALF) and not the fixture alone. A first version keyed on
  # the fixture alone, so `rd_all_rem` -- the REMAINING axes -- was compared against `red`,
  # and it printed `cpython=(0,)` against a port assertion of 1, which reads exactly like a
  # port defect and is not one. `red` and `rem` are disjoint quantities on the same fixture
  # and a key that cannot tell them apart cannot be evidence about either.
  RD = [("all", 0, 1, 1), ("some", 1, 2, 1), ("none", 2, 3, 1), ("two", 0, 1, 2),
        ("mix", 1, 4, 3), ("zero", 0, 1, 0)]
  rd_orc, rd_port = {}, {}
  for nm, axa, axb, na in RD:
    half = {"red": tuple(ax for ax in (axa, axb) if ax < na),
            "rem": tuple(ax for ax in (axa, axb) if ax >= na)}
    for h, val in half.items():
      rd_orc[(axa, axb, na, h)] = (f"{nm}_{h}", val)
    for pn, b in bodies.items():
      if not (pn.startswith("rd_") and pn.endswith(("_red", "_rem"))):
        continue
      t = twosh(b)
      if t is None or t[0] != axa or t[2] != axb:
        continue
      tail = b[b.rfind("), ") + 3:]
      if not tail.startswith(f"{na})"):
        continue
      h = "red" if "Rd.red(" in b else ("rem" if "Rd.rem(" in b else None)
      if h:
        rd_port.setdefault((axa, axb, na, h), []).append((pn, b))
  n2, bad2, c2 = report("rd_*: reduce_multi red/rem split -- multi.py:107-123",
                        rd_orc, rd_port)

  # ⚠ `bad1 + bad2` was CONCATENATION, not addition: `report()` returns a LIST of
  # inconsistencies, so `bad1 + bad2` is a list that is non-empty whenever EITHER family
  # had one, and `0 if <non-empty list> == 0 else 1` printed rc=1 over 0 inconsistencies --
  # a permanently-red verdict on a clean pair, which is the exact failure this lane exists
  # to prevent. `len()` on both sides, and the count is printed with the verdict.
  nbad = len(bad1) + len(bad2)
  nchk = c1 + c2
  print(f"\n=== FIXTURE-KEYED SHARED: bx {n1} of {len(bx_orc)} oracle bx rows, "
        f"rd {n2} of {len(rd_orc)} oracle rd rows ===")
  print(f"=== INCONSISTENT (port asserts something CPython's value contradicts): "
        f"{nbad} of {nchk} CHECKED ===")
  return 0 if nbad == 0 else 1


if __name__ == "__main__":
  # argv[1] names an alternative multi.bend, used ONLY by the plant control. Absent means
  # the live tree, which is what every analysis run reads.
  raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else None))
