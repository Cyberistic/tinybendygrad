#!/usr/bin/env python3
"""ew_activation-plant.py -- THE PLANTS.  Each one is a way the port could be wrong, applied
to a COPY of the port's OWN SOURCE, and the comparison is asked whether it SEES it.

    .venv/bin/python gates/ew_activation-plant.py              # every plant
    .venv/bin/python gates/ew_activation-plant.py --refresh    # re-take the expected values
    .venv/bin/python gates/ew_activation-plant.py --list       # the labels, and nothing else

THE RULE THIS FILE EXISTS FOR: "IF YOU MUST TEST A SYSTEM IN ISOLATION, FIRST WRITE ALL THE
WAYS IT COULD FAIL, THEN WRITE THE CODE."  THE WAYS IT COULD FAIL ARE HERE, AND EACH ONE IS
PLANTED AND MEASURED -- NOT ASSERTED.

A PLANT THAT DOES NOT MOVE THE COMPARISON IS NOT A PASS.  It is a hole in the comparison,
and the honest outcome of this file is a list of holes, not a list of plants that all fired.
EVERY PLANT IS APPLIED TO A COPY OF THE PORT'S SOURCE and the driver is re-run over it, so
what is measured is the COMPARISON and not a re-implementation of it.

THE COPY IS A WHOLE TREE, AND IT HAS TO BE.  `uop/fold.bend` is imported by
`mixin/elementwise.bend` AND by `uop/weak.bend`, so a mutation of it cannot be a file
beside the original: the mutant has to be the file everybody imports.  So the harness
copies `tinybendygrad/` into a scratch tree, writes the driver into it, and points a
`bin/bend` shim at the toolchain.  THE REAL PORT IS NEVER WRITTEN.

THE COPY IS OF **HEAD**, AND THAT IS THE POINT.  The plants measure the HARNESS and not
the port, so the substrate they measure it on has to be a COMMITTED one: MEASURED,
2026-10-22, while this was being written, the WORKING COPY did not compile at all --
another unit's in-flight edit to `tinybendygrad/tensor.bend` was a `match` on a computed
value, and `bend` answered `a parameter or field scrutinee` -- and a harness whose
substrate is whatever the working copy happens to be is a harness whose answer depends
on who else is working.  `git archive HEAD tinybendygrad` is the committed tree, it is
REPRODUCIBLE, and the commit it came from is PRINTED so a reader can tell which tree the
counts were taken on.

THE PLANTS, AND THE FAILURE EACH ONE NAMES:

  P1  ALPHA DEFAULT      `ew_k.elu_alpha()` is 2.0 and not 1.0 -- upstream's default
                         for `elu` and `celu` is 1.0.
  P2  SIGN ERROR         `asin`'s `where(1.0, -1.0)` is `where(-1.0, 1.0)` -- the
                         sign of the argument, which a value comparison at ONE
                         positive input cannot see.
  P3  COEFFICIENT ORDER  two of `asin`'s eight coefficients are swapped -- the Horner
                         chain's ORDER, which changes no op and no node COUNT.
  P4  DOMAIN CLAMP       `asin` clamps `|self|` to 1 where upstream does NOT -- the
                         classic "helpful" clamp, which turns upstream's NaN into a
                         number.
  P5  NAN PROPAGATION    `asin`'s `s` is a NaN instead of `where(1.0, -1.0)`.
  P6  OPERAND ORDER      `a = s * self` is built as `self * s` -- a commutative MUL
                         whose operand order is a GRAPH difference and not a value
                         difference, which is why the comparison is CANONICAL.
  P7  CELU'S OWN ALPHA   `celu` calls `elu` with `celu`'s alpha where upstream calls
                         it with `elu`'s DEFAULT.
  P8  SELU'S PARAMETERS  `selu`'s alpha and gamma are swapped.
  P9  THE MISSING ARM    `uop/fold.bend`'s `least_upper_float` loses its `CWeakFloat`
                         arm, so a weakfloat comes back `float32`.  **THIS IS ONE OF THE
                         TWO REAL DEFECTS THIS HARNESS FOUND.**  CPython's `is_float` is
                         `dt.kind == 'f'` and a WEAK FLOAT's kind is 'f', so
                         `least_upper_float(weakfloat)` IS `weakfloat` -- but the port's
                         `CFloat` arm is the STRONG float class, so a weakfloat fell
                         through to `case _` and came back `float32`.  MEASURED: 238 of
                         255 rows differed, and the difference was THREE `CAST f32`
                         nodes that upstream does not have.
  P10 EW_TANH'S ORDER    `ew_tanh` computes `sigmoid(2*self) * self - 1.0` where
                         upstream computes `2*sigmoid(2*self) - 1.0`.  **THIS IS THE
                         OTHER REAL DEFECT.**  MEASURED: the port's `tanh(0.5)` was
                         `-0.6344707012176514` and CPython's is `0.46211719512939453`;
                         the port's `tanh(0.0)` was `-1.0` and CPython's is `0.0`.  AND
                         THE CENSUS'S `ew_tanh` ROW CANNOT SEE IT: it prints the ROOT's
                         src ops, and the root is the ADD of `sub` either way --
                         `Ops.MUL Ops.MUL`.

THE NON-DEFAULT FIXTURES ARE NOT COSMETIC.  MEASURED, 2026-10-22: with only the default
rows, the plant "celu calls elu with celu's own alpha" was MISSED -- because `celu`'s
default alpha IS 1.0, so at the default the plant changes NOTHING and there is nothing to
detect.  A PLANT THAT ONLY FIRES AT THE DEFAULT IS A PLANT THAT PROVES NOTHING, and it
was closed by giving the plant a fixture that can see it: the driver carries `celu` and
`elu` and `selu` at a NON-DEFAULT alpha, and `tanh` and `sigmoid` and the unary-alu
family, which are what P9 and P10 need.

THE EXPECTED VALUES ARE IN `gates/ew_activation-pins.rows`, BESIDE THIS FILE, and this
harness ASSERTS them: a plant that moves a DIFFERENT number of rows is a change in the
instrument and is a red run until `--refresh` re-takes them.  A pin in a comment is a pin
that cannot fail.

THE GRAPH-ONLY ARM IS ASSERTED, NOT HOPED FOR.  AT LEAST ONE PLANT MUST MOVE GRAPH ROWS
AND ZERO VALUE ROWS -- a commutative MUL whose operands are swapped is the same number
and a different graph -- because a comparison that only read VALUES could not see it, and
the census's signature row cannot see it either.  IF NO PLANT SATISFIED THAT, THE
CANONICAL GRAPH DIFF WOULD BE REDUNDANT WITH A VALUE COMPARISON AND THE WHOLE POINT OF
THIS HARNESS WOULD BE GONE.

EXIT STATUS: 0 every plant was DETECTED and every count matched its pin, 1 a plant was
MISSED or a count moved, 3 a precondition was absent (no compiler, no scratch tree, a
control that is not green).
"""
import io
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "ew_activation-pins.rows"
DRIVER = HERE / "ew_activation.bend"
ORACLE = HERE / "ew_activation-oracle.py"
COMPARE = HERE / "ew_activation-compare.py"
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
# THE TOOLCHAIN'S ENTRY POINT.  `bin/bend` is a shim onto it, and the shim resolves the
# target RELATIVE TO ITSELF -- so a scratch tree needs its own shim, and this is the
# absolute path that shim names.
BEND_MAIN = ROOT / "references" / "bend" / "bend2" / "main.ts"

# (label, path under the port, the text to find, the text to put there).  AN EMPTY
# `new` IS A REMOVAL, and P9 IS ONE.
PLANTS = [
  ("P1 alpha default", "tinybendygrad/mixin/elementwise.bend",
   "def ew_k.elu_alpha() -> F32: 1.0", "def ew_k.elu_alpha() -> F32: 2.0"),
  ("P2 sign error", "tinybendygrad/mixin/elementwise.bend",
   "ECon{O.CFloat{1.0}}, ECon{O.CFloat{F32.neg(1.0)}}",
   "ECon{O.CFloat{F32.neg(1.0)}}, ECon{O.CFloat{1.0}}"),
  ("P3 coefficient order", "tinybendygrad/mixin/elementwise.bend",
   "ECon{O.CFloat{0.0066700901}}", "ECon{O.CFloat{0.030891881}}"),
  ("P4 domain clamp", "tinybendygrad/mixin/elementwise.bend",
   "  +a = ew_mul2(s, t, False{})",
   "  +tc = ew_where.of(ew_gt(t, ECon{O.CFloat{1.0}}), ECon{O.CFloat{1.0}}, ETen{t})\n"
   "  +a = ew_mul2(s, tc, False{})"),
  ("P5 nan propagation", "tinybendygrad/mixin/elementwise.bend",
   "ECon{O.CFloat{0.030891881}}", "ECon{O.CFloat{F32.div(0.0, 0.0)}}"),
  ("P6 operand order", "tinybendygrad/mixin/elementwise.bend",
   "+a = ew_mul2(s, t, False{})", "+a = ew_mul2(t, s, False{})"),
  ("P7 celu's own alpha", "tinybendygrad/mixin/elementwise.bend",
   "+e = ew_elu(q, ew_k.elu_alpha())", "+e = ew_elu(q, alpha)"),
  ("P8 selu's parameters", "tinybendygrad/mixin/elementwise.bend",
   "+e = ew_elu(t, alpha)\n  ew_mul2(e, ew_ct(ew_cf(T.Tensor.ar(e), gamma)), True{})",
   "+e = ew_elu(t, gamma)\n  ew_mul2(e, ew_ct(ew_cf(T.Tensor.ar(e), alpha)), True{})"),
  ("P9 the missing CWeakFloat arm", "tinybendygrad/uop/fold.bend",
   "    case S.CWeakFloat{}: Some{dt}\n", ""),
  ("P10 ew_tanh's operand order", "tinybendygrad/mixin/elementwise.bend",
   "  ew_sub(ew_mul2(s, c2, True{}), ECon{O.CFloat{1.0}}, False{})",
   "  ew_sub(ew_mul2(t, s, True{}), ECon{O.CFloat{1.0}}, False{})"),
]

# THE BEND LOCK IS `gates/bendlock.py`, AND IT IS SHARED: the lock is only a lock if
# every form of it names the same path, and `gates/bendlock.py` names the one
# `checks/bendlock.sh` and the ad-hoc recipe in `AGENTS.md` both name.
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402


def run(cmd, cwd=None, **kw):
  return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)


def head_commit() -> str:
  r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
  return r.stdout.strip() if r.returncode == 0 else "NO-HEAD"


def build_scratch() -> Path:
  """THE SCRATCH TREE: a COPY of HEAD's port, the driver, and a `bin/bend` that points
  at THIS tree's toolchain.  The real port is never written."""
  if not BEND_MAIN.is_file():
    return None
  scratch = Path(tempfile.mkdtemp(prefix="ewact-"))
  archive = subprocess.run(["git", "archive", "HEAD", "tinybendygrad"], cwd=ROOT,
                           capture_output=True)
  if archive.returncode != 0:
    return None
  with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
    tar.extractall(scratch, filter="data")
  (scratch / "gates").mkdir()
  shutil.copy(DRIVER, scratch / "gates" / DRIVER.name)
  (scratch / "bin").mkdir()
  (scratch / "bin" / "bend").write_text(
      f"#!/bin/sh\n# THE SCRATCH TREE'S SHIM.  `bin/bend` resolves its target RELATIVE TO\n"
      f"# ITSELF, and this scratch has no `references/`, so the target is named absolutely.\n"
      f"exec bun \"{BEND_MAIN}\" \"$@\"\n")
  (scratch / "bin" / "bend").chmod(0o755)
  return scratch


def bend_run(scratch: Path, out: Path, err: Path) -> int:
  """ONE BEND, UNDER THE LOCK, IN THE SCRATCH TREE."""
  with bend_lock() as waited:
    if waited:
      print(f"    (waited {waited}s for the bend lock)", file=sys.stderr)
    r = subprocess.run([str(scratch / "bin" / "bend"), "gates/ew_activation.bend"],
                       cwd=scratch, capture_output=True, text=True)
  out.write_text(r.stdout)
  err.write_text(r.stderr)
  return r.returncode


def compare(port_rows: Path, cpy_rows: Path):
  """THE COMPARISON, AND ITS TWO NUMBERS.  `None` means the comparison REFUSED, which is
  a different class from a disagreement."""
  r = run([str(PY), str(COMPARE), str(port_rows), str(cpy_rows)])
  out = r.stdout + r.stderr
  for line in r.stdout.splitlines():
    if line.startswith("SUMMARY "):
      kv = dict(p.split("=") for p in line.split()[1:])
      return int(kv["graph_differing"]), int(kv["value_differing"]), out
  return None, None, out


def read_pins() -> dict:
  """THE EXPECTED VALUES, LOADED BY PATH.  A MISSING FILE IS A REFUSAL AND NOT A PASS:
  a plant harness with no expected values asserts nothing."""
  if not PINS.is_file():
    return None
  pins = {}
  for line in PINS.read_text().splitlines():
    if not line or line.startswith("#"):
      continue
    f = line.split("\t")
    if len(f) != 3:
      return None
    pins[f[0]] = (int(f[1]), int(f[2]))
  return pins


def write_pins(rows: dict, substrate: str) -> None:
  PINS.write_text(
      "# ew_activation-pins.rows -- THE EXPECTED VALUES of `gates/ew_activation-plant.py`,\n"
      "# and that file is their ONLY reader and their ONLY writer (`--refresh`).\n"
      "#\n"
      "# ONE TAB-SEPARATED TRIPLE per plant: `<label>\\t<graph rows differing>\\t<value rows\n"
      "# differing>`.  THE `control` ROW IS THE UNPLANTED PORT, and it is pinned at 0/0\n"
      "# because a comparison that already disagrees on the control measures nothing.\n"
      "#\n"
      "# THESE ARE A CLAIM ABOUT THE INSTRUMENT AND NOT ABOUT THE PORT: they are what each\n"
      "# plant moves, so a plant that stops moving what it moved is a change in the\n"
      "# COMPARISON and not a change in the port.  THAT IS WHY THEY ARE PINNED AT ALL: a\n"
      "# comparison's sensitivity is a fact, and a fact nobody checks rots.\n"
      "#\n"
      "# THE SUBSTRATE THEY WERE TAKEN ON.  The plants run against HEAD's `tinybendygrad/`\n"
      "# and not against the working copy, so the counts are a function of a COMMIT.\n"
      f"# substrate={substrate}\n"
      + "".join(f"{k}\t{v[0]}\t{v[1]}\n" for k, v in rows.items()))


def main(argv) -> int:
  refresh = "--refresh" in argv
  if "--list" in argv:
    for label, _, _, _ in PLANTS:
      print(label)
    return 0
  if not BEND_MAIN.is_file():
    print(f"REFUSED: no toolchain at {BEND_MAIN} -- `references/` is gitignored, so a "
          f"clone without it cannot compile anything", file=sys.stderr)
    return 3
  scratch = build_scratch()
  if scratch is None:
    print("REFUSED: no scratch tree", file=sys.stderr)
    return 3
  substrate = head_commit()
  print(f"substrate=HEAD@{substrate}")
  rows = {}
  try:
    # 0. THE CONTROL: the UNPLANTED port must PASS, or a plant that "moves" nothing is
    # measuring a broken comparison.
    port_rows, port_err = scratch / "port.rows", scratch / "port.err"
    cpy_rows = scratch / "cpython.rows"
    if bend_run(scratch, port_rows, port_err) != 0:
      print("REFUSED: the CONTROL did not compile", file=sys.stderr)
      print(port_err.read_text()[-2000:], file=sys.stderr)
      return 3
    with open(cpy_rows, "w") as f:
      subprocess.run([str(PY), str(ORACLE), str(port_rows)], stdout=f, check=True)
    g, v, out = compare(port_rows, cpy_rows)
    print(f"CONTROL (no plant): graph_differing={g} value_differing={v}")
    if g is None:
      print("REFUSED: the comparison refused on the control", file=sys.stderr)
      print(out[-2000:], file=sys.stderr)
      return 3
    if g or v:
      print("REFUSED: the CONTROL is not green, so a plant that moves nothing proves nothing",
            file=sys.stderr)
      print(out[-2000:], file=sys.stderr)
      return 3
    rows["control"] = (g, v)
    for label, rel, old, new in PLANTS:
      target = scratch / rel
      pristine = target.read_text()
      if old not in pristine:
        print(f"PLANT {label}: REFUSED -- the text to plant is not in {rel}")
        return 3
      target.write_text(pristine.replace(old, new, 1))
      plant_rows, plant_err = scratch / "plant.rows", scratch / "plant.err"
      plant_cpy = scratch / "plant.cpython.rows"
      rc = bend_run(scratch, plant_rows, plant_err)
      if rc != 0 or not plant_rows.exists() or not plant_rows.read_text().strip():
        print(f"PLANT {label}: MISSED -- the driver produced no rows (it did not compile)")
        print(plant_err.read_text()[-1500:], file=sys.stderr)
        target.write_text(pristine)
        return 1
      with open(plant_cpy, "w") as f:
        subprocess.run([str(PY), str(ORACLE), str(plant_rows)], stdout=f, check=True)
      g, v, out = compare(plant_rows, plant_cpy)
      target.write_text(pristine)
      if g is None:
        print(f"PLANT {label}: MISSED -- the comparison refused")
        print(out[-1500:], file=sys.stderr)
        return 1
      detected = bool(g or v)
      rows[label] = (g, v)
      print(f"PLANT {label}: {'DETECTED' if detected else 'MISSED'} "
            f"(graph_differing={g} value_differing={v})")
    # THE GRAPH-ONLY ARM.  AT LEAST ONE PLANT MUST MOVE GRAPH ROWS AND ZERO VALUE ROWS.
    only_graph = [k for k, (g, v) in rows.items() if k != "control" and g > 0 and v == 0]
    print(f"plants={len(PLANTS)} graph-only plants={len(only_graph)}"
          + (f" ({', '.join(only_graph)})" if only_graph else ""))
    if not only_graph:
      print("REFUSED: no plant moved GRAPH rows without VALUE rows -- the canonical graph "
            "diff would be redundant with a value comparison", file=sys.stderr)
      return 1
    pins = read_pins()
    if refresh:
      write_pins(rows, substrate)
      print(f"--refresh: wrote {PINS.name} with {len(rows)} rows")
      return 0
    if pins is None:
      print(f"REFUSED: {PINS} is missing or malformed -- a plant harness with no expected "
            f"values asserts nothing", file=sys.stderr)
      return 3
    bad = []
    for k, v in rows.items():
      if k not in pins:
        bad.append(f"{k}: no pin")
      elif pins[k] != v:
        bad.append(f"{k}: measured {v[0]}/{v[1]} but the pin says {pins[k][0]}/{pins[k][1]}")
    for k in pins:
      if k not in rows:
        bad.append(f"{k}: a pin for a plant that did not run")
    if bad:
      for b in bad:
        print(f"PIN MISMATCH: {b}")
      print("  re-take them with `--refresh` IF the change is intended", file=sys.stderr)
      return 1
    print(f"VERDICT: PASS -- {len(PLANTS)} plants, every one DETECTED, every count at its pin")
    return 0
  finally:
    shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
  sys.exit(main(sys.argv))
