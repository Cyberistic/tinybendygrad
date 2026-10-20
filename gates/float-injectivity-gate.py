#!/usr/bin/env python3
"""float-injectivity-gate.py -- the half SUBNORMAL class, and the INJECTIVITY the JS lane must have.

    .venv/bin/python gates/float-injectivity-gate.py [--plant NAME]

WHY THIS FILE EXISTS, and it is not "the census is red".  `gates/subnormal-flush-gate.py`
asks WHICH of the port's two f16 rules is odd: it runs the CPython oracle, the C lane
(compiled out of the live `dtype.c`) and the JS lane (the live `dtype.js`) over the same
2200 rows, and it answers that the C lane agrees with the oracle on all of them and the
JS lane on none.  That is a COMPARISON, and a comparison cannot say what is wrong with
the odd side -- it can only say that the sides differ.  This file asks the question that
needs no oracle at all:

    a half subnormal is `m * 2^-24` for m in [1, 1023], and every one of those 1023
    values is EXACTLY representable as an f32, so the map half -> f32 must be INJECTIVE
    on the class: 1023 inputs, 1023 distinct outputs.  A rule that is not injective
    loses information the format can carry, and the loss is visible without calling
    anything.

THE POPULATION IS DISCOVERED, NEVER LISTED: the half patterns whose exponent field is
0 and whose mantissa is not 0, BOTH SIGNS.  It is `gates/subnormal-flush-gate.py`'s own
`half_subnormals()`, imported BY PATH -- this file holds no second copy of the fixture,
of the three-global shim, or of the C extractor, because a second copy of a rule is the
thing that rots.

THE THREE LANES, each the tree's OWN bytes:
  JS      `tinybendygrad/runtime/dtype.js`, verbatim, behind the three-global shim.
  C       `tinybendygrad/runtime/dtype.c`'s own `fp16_f32`, EXTRACTED and compiled.
  ORACLE  CPython's `struct.pack('e')`, CALLED.

WHAT IS MEASURED, per lane: the number of DISTINCT f32 patterns the 1023 POSITIVE
half subnormals map onto, the same over both signs, and the disagreements against the
oracle.  The distinct count is COUNTED FROM THE LANE'S OWN OUTPUT -- it is not a
number written here, and it is not a number derived by reading the rule.

THE ARMS, each anchored, each COUNTED, each applied to a COPY of the lane it perturbs
-- the live tree is never a base.  A plant that cannot fail is a comment, and a control
that moves rows is an instrument reading a TOKEN instead of a VALUE:

  norm-plant      the JS lane's half-subnormal normalisation is given back the fixed
                  `m << 14` and the fixed exponent.  MUST take the distinct count BELOW
                  the number of inputs and the disagreements ABOVE zero.
  norm-disarm     the SAME line, re-spelled.  MUST move neither count.
  clz-plant       the leading-bit position is taken one lower.  MUST take the
                  disagreements ABOVE zero: the values are then wrong by a factor of
                  two, which is a different defect from losing the pattern.

WHAT THIS FILE CANNOT SEE, because a row that cannot say what it cannot see is a row
that will be read as more than it is:

  the class is the half SUBNORMALS, so it says nothing about the half NORMALS, and it
  says nothing about the f32 -> half direction, whose subject is
  `gates/subnormal-flush-gate.py` and `gates/js-lane-census.py`.
  the fixture is a SET OF PATTERNS, so a defect that needs a pattern class the fixture
  does not contain is invisible here.
  INJECTIVITY IS NOT CORRECTNESS.  A lane can be injective and still answer the wrong
  number, and the disagreements against the oracle are the only thing in this file
  that says which.  Both are counted, and both are printed.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, verdict_of  # noqa: E402

ROOT = HERE.parent
JS_LANE = ROOT / "tinybendygrad" / "runtime" / "dtype.js"
C_LANE = ROOT / "tinybendygrad" / "runtime" / "dtype.c"
NODE, CC = "node", "cc"

# THE SIBLING GATE'S OWN MODULE, BY PATH.  Its filename has a hyphen, so it is not
# importable by name, and the honest way in is `importlib` -- a second copy of the
# fixture, the shim or the C extractor would be a second copy of the RULE.
_spec = importlib.util.spec_from_file_location(
    "subnormal_flush_gate", HERE / "subnormal-flush-gate.py")
sfg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sfg)

# THE FIXED NORMALISATION, AS THE JS LANE NOW SPELLS IT.  The arms perturb a COPY of
# the lane, and the anchor must be the tree's own text: an arm that perturbs a
# transcription is measuring the transcription.
JS_NORM = "return (s | ((k + 103) << 23) | ((m << (23 - k)) & 0x7fffff)) >>> 0;"
JS_NORM_BROKEN = "return (s | (103 << 23) | (m << 14)) >>> 0;"
JS_K = "const k = 31 - Math.clz32(m);"

ARMS: dict[str, tuple[list[tuple[str, str]], dict[str, str]]] = {
    # THE PRE-FIX RULE, GIVEN BACK.  It is the rule whose distinct count is BELOW the
    # number of inputs, and the arm is what proves this instrument can SEE that.
    "norm-plant": ([(JS_NORM, JS_NORM_BROKEN)],
                   {"distinct": "below", "disagree": "increase"}),
    # THE SAME LINE, RE-SPELLED.  Must move neither count: this is what separates a
    # TOKEN check from a VALUE check.
    "norm-disarm": ([(JS_NORM, JS_NORM.replace("(k + 103)", "(k  + 103)"))],
                    {"distinct": "same", "disagree": "same"}),
    # THE LEADING BIT TAKEN ONE LOWER.  The values are then wrong by a factor of two
    # while the map stays a map, so this arm is the one that separates "injective"
    # from "correct".
    "clz-plant": ([(JS_K, JS_K.replace("31 -", "30 -"))],
                  {"distinct": "below", "disagree": "increase"}),
}

# WHAT THE GATE ITSELF ASSERTS, and it is a RELATION and not a number: the map must be
# injective on the class, so the distinct count EQUALS the number of inputs, and the
# lane must agree with the oracle on every row.
INJECTIVE, AGREE = "equal", "zero"


def refuse(*why: str) -> int:
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


def measures(rows: dict[str, str], oracle: dict[str, str], keys: list[str]) -> dict[str, int]:
    """(distinct patterns, disagreements) over `keys` -- COUNTED from the lane's own
    output, never written down here."""
    return {"distinct": len({rows[k] for k in keys}),
            "disagree": sum(1 for k in keys if rows.get(k) != oracle.get(k))}


def run(*, arm: str | None) -> int:
    if not (ROOT / "pyproject.toml").is_file() or not (ROOT / "tinybendygrad").is_dir():
        return refuse(f"ROOT is not the repo root: {ROOT}")
    for p in (JS_LANE, C_LANE):
        if not p.exists():
            return refuse(f"input absent: {p}")
    if arm is not None and arm not in ARMS:
        return refuse(f"unknown arm {arm!r}; one of {sorted(ARMS)}")
    if bad := sfg.oracle_drift(sfg.ORACLE_PIN):
        return refuse("the CPython side drifted: " + "; ".join(bad))
    for tool in (NODE, CC):
        if not shutil.which(tool):
            return refuse(f"{tool} is not on PATH")

    jsrc, csrc = JS_LANE.read_text(), C_LANE.read_text()
    h2f = sfg.half_subnormals()
    pos = [h for h in h2f if h < 0x8000]
    keys = [f"h2f_{h:x}" for h in h2f]
    pkeys = [f"h2f_{h:x}" for h in pos]
    oracle = sfg.oracle_rows(h2f, [])
    want = len(h2f)

    # THE ARM'S EDIT IS MADE ON A COPY OF THE SOURCE, BEFORE ANY LANE RUNS, and the
    # anchor must be found EXACTLY ONCE: an anchor that moved is a measurement of
    # nothing, and a plant that cannot fail is a comment.
    j2 = jsrc
    for old, new in (ARMS.get(arm) or [[]])[0]:
        n = j2.count(old)
        if n != 1:
            return refuse(f"arm {arm}: anchor {old.strip()[:56]!r} found {n} site(s), "
                          f"expected 1 -- dtype.js moved")
        j2 = j2.replace(old, new)

    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            base_js = sfg.js_lane(work, jsrc, h2f, [])
            base_c = sfg.c_lane(work, csrc, h2f, [])
            arm_js = sfg.js_lane(work, j2, h2f, [])
    except RuntimeError as exc:
        return refuse(str(exc))

    for name, lane in (("js", base_js), ("c", base_c), ("js-arm", arm_js)):
        if len(lane) != want:
            return refuse(f"the {name} lane emitted {len(lane)} rows, expected {want}")
        missing = sorted(set(keys) - set(lane))
        if missing:
            return refuse(f"the {name} lane is missing {len(missing)} rows: {missing[:3]}")

    m_js = measures(base_js, oracle, keys)
    m_c = measures(base_c, oracle, keys)
    m_jp = measures(base_js, oracle, pkeys)
    m_cp = measures(base_c, oracle, pkeys)
    m_arm = measures(arm_js, oracle, keys)
    m_armp = measures(arm_js, oracle, pkeys)

    print(f"float-injectivity-gate: {want} half subnormals (both signs), "
          f"{len(pos)} of them positive, 3 lanes (ORACLE / dtype.c / dtype.js)")
    print(f"  INJECTIVE means: distinct f32 patterns == inputs. "
          f"positive {len(pos)}, all {want}")
    print(f"  js   distinct {m_jp['distinct']}/{len(pos)} positive, "
          f"{m_js['distinct']}/{want} all | disagree {m_js['disagree']}/{want}")
    print(f"  c    distinct {m_cp['distinct']}/{len(pos)} positive, "
          f"{m_c['distinct']}/{want} all | disagree {m_c['disagree']}/{want}")
    print(f"  WITNESS m=1 -> {base_js['h2f_1']} | m=513 -> {base_js['h2f_201']} "
          f"| oracle m=1 -> {oracle['h2f_1']} | oracle m=513 -> {oracle['h2f_201']}")
    print(f"  RULE c extracted sha256="
          f"{hashlib.sha256(sfg.extract_c(csrc, 'fp16_f32').encode()).hexdigest()[:16]} "
          f"bytes={len(sfg.extract_c(csrc, 'fp16_f32'))}")

    if arm is None:
        for lane, m, n_pos in (("js", m_js, m_jp), ("c", m_c, m_cp)):
            if n_pos["distinct"] != len(pos) or m["distinct"] != want:
                print(f"float-injectivity-gate: {verdict_of(FAIL)} -- the {lane} lane is not "
                      f"injective: {n_pos['distinct']}/{len(pos)} positive, "
                      f"{m['distinct']}/{want} all")
                return FAIL
            if m["disagree"]:
                print(f"float-injectivity-gate: {verdict_of(FAIL)} -- the {lane} lane "
                      f"disagrees with the oracle on {m['disagree']} rows")
                return FAIL
        if base_js["h2f_1"] == base_js["h2f_201"]:
            print(f"float-injectivity-gate: {verdict_of(FAIL)} -- m=1 and m=513 share the "
                  f"f32 pattern {base_js['h2f_1']}")
            return FAIL
        print(f"float-injectivity-gate: {verdict_of(PASS)} -- the js lane is injective on "
              f"the class and agrees with the oracle on {want} rows")
        return PASS

    # THE ARM'S STATEMENT, CHECKED AGAINST THE RUN.
    print(f"  ARM {arm}: baseline distinct {m_js['distinct']} (positive {m_jp['distinct']}), "
          f"disagree {m_js['disagree']} -> armed distinct {m_arm['distinct']} "
          f"(positive {m_armp['distinct']}), disagree {m_arm['disagree']}")
    for old, new in ARMS[arm][0]:
        print(f"    {old.strip()[:58]!r} -> {new.strip()[:58]!r}")
    for key, rel in ARMS[arm][1].items():
        base_v = m_js["distinct"] if key == "distinct" else m_js["disagree"]
        arm_v = m_arm["distinct"] if key == "distinct" else m_arm["disagree"]
        if rel == "same":
            ok = arm_v == base_v
        elif rel == "below":
            ok = arm_v < base_v
        elif rel == "increase":
            ok = arm_v > base_v
        else:
            ok = False
        if not ok:
            print(f"  ARM {arm} VIOLATED: {key} is {arm_v}, and the arm says {rel} "
                  f"of {base_v}")
            return FAIL
    print(f"float-injectivity-gate: {verdict_of(PASS)} -- arm {arm} did what it says")
    return PASS


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="the half subnormal class, and injectivity")
    ap.add_argument("--plant", choices=sorted(ARMS))
    ns = ap.parse_args()
    sys.exit(run(arm=ns.plant))
