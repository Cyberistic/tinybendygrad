#!/usr/bin/env python3
"""float-halfclass-gate.py -- the two half classes, and the OPPOSITE property each one has.

    .venv/bin/python gates/float-halfclass-gate.py [--plant NAME]

WHY THIS FILE EXISTS.  `gates/subnormal-flush-gate.py` asks WHICH of the port's two f16
rules is odd, over the half SUBNORMALS and the f32->half subnormal band, and it answers
that the C lane agrees with CPython on all 2200 rows and the JS lane on none (before the
fix that landed in `636e797cb`).  That is a COMPARISON, and a comparison cannot say what
is wrong with the odd side.  This file asks two questions that need no oracle to ASK,
only CPython to ANSWER:

    the half SUBNORMALS are a map that must be INJECTIVE, and
    the half NaNs are a map that must NOT be.

THE TWO POPULATIONS ARE DISCOVERED, NEVER LISTED, by the format's own rule -- a half's
exponent field is bits 10..14:

  h2s  the SUBNORMALS: exponent field 0, mantissa not 0, BOTH SIGNS.  A half subnormal
       is `m * 2^-24` and every one of those 1023 values is EXACTLY representable as an
       f32, so the map half -> f32 must be injective: 1023 inputs, 1023 distinct
       outputs.  A rule that is not injective loses information the format can carry,
       and the loss is visible without calling anything.
  h2n  the NaNs: exponent field 0x1f, mantissa not 0, BOTH SIGNS.  Here the map must
       NOT be injective: CPython's own codec canonicalises every half NaN to the one
       f32 NaN per sign, so the class collapses onto TWO patterns.  A lane that keeps
       the payload answers 2046 patterns where CPython answers 2, and it is WRONG.

THE TWO PROPERTIES ARE THE SAME CLAIM, MEASURED AGAINST THE ORACLE RATHER THAN WRITTEN
DOWN: the JS lane's distinct-pattern count must EQUAL the ORACLE's on each class, and
the two lanes must agree row for row.  No expected count is transcribed here, because a
number written in a gate is an expected value nobody computed.

THE THREE LANES, each the tree's OWN bytes:
  JS      `tinybendygrad/runtime/dtype.js`, verbatim, behind the three-global shim.
  C       `tinybendygrad/runtime/dtype.c`'s own `fp16_f32`, EXTRACTED and compiled.
  ORACLE  CPython's `struct.pack('e')`, CALLED.

WHAT IS REUSED, AND NOT COPIED: the fixture, the shim, the C extractor and the three
lanes all come from `gates/subnormal-flush-gate.py`, imported BY PATH -- a second copy
of a rule is the thing that rots.

THE ARMS, each anchored, each COUNTED, each applied to a COPY of the lane it perturbs
-- the live tree is never a base.  A plant that cannot fail is a comment, and a control
that moves rows is an instrument reading a TOKEN instead of a VALUE:

  norm-plant    the JS lane's half-subnormal normalisation is given the fixed
                `m << 14` back.  MUST take the h2s distinct count BELOW the oracle's
                and the h2s disagreements ABOVE zero.
  norm-disarm   the SAME line, re-spelled.  MUST move neither count.
  nan-plant     the half NaN's payload is carried instead of canonicalised -- the
                spelling `dtype.bend:736` has.  MUST take the h2n distinct count ABOVE
                the oracle's and the h2n disagreements ABOVE zero.
  nan-disarm    the SAME line, re-spelled.  MUST move neither count.

WHAT THIS FILE CANNOT SEE, because a row that cannot say what it cannot see is a row
that will be read as more than it is:

  the half NORMALS, the f32 -> half direction (whose subject is
  `gates/subnormal-flush-gate.py` and `gates/js-lane-census.py`), and every pattern
  class the fixture does not contain.
  THE BEND LANE.  `dtype.bend` implements this rule too, and it is a different lane
  with its own defect; this file measures the JS and the C, and the Bend's own fp16 is
  measured by `.agents/slop/floatfix/measure-bend-lane.py`.
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

# THE FIXED NORMALISATION AND THE FIXED NaN ARM, AS THE JS LANE NOW SPELLS THEM.  The
# arms perturb a COPY of the lane, and the anchor must be the tree's own text: an arm
# that perturbs a transcription is measuring the transcription.
JS_NORM = "return (s | ((k + 103) << 23) | ((m << (23 - k)) & 0x7fffff)) >>> 0;"
JS_NORM_BROKEN = "return (s | (103 << 23) | (m << 14)) >>> 0;"
JS_NAN = "if (e === 0x1f) return ((s | 0x7f800000 | (m ? 0x400000 : 0)) >>> 0);"
JS_NAN_PAYLOAD = "if (e === 0x1f) return ((s | 0x7f800000 | (m << 13)) >>> 0);"

ARMS: dict[str, tuple[list[tuple[str, str]], dict[str, str]]] = {
    # THE PRE-FIX RULE, GIVEN BACK.  It is the rule whose distinct count is BELOW the
    # oracle's, and the arm is what proves this instrument can SEE that.
    "norm-plant": ([(JS_NORM, JS_NORM_BROKEN)],
                   {"h2s/distinct": "below", "h2s/disagree": "increase"}),
    # THE SAME LINE, RE-SPELLED.  Must move neither count: this is what separates a
    # TOKEN check from a VALUE check.
    "norm-disarm": ([(JS_NORM, JS_NORM.replace("(k + 103)", "(k  + 103)"))],
                    {"h2s/distinct": "same", "h2s/disagree": "same"}),
    # THE PAYLOAD CARRIED INSTEAD OF CANONICALISED -- `dtype.bend:736`'s spelling.
    "nan-plant": ([(JS_NAN, JS_NAN_PAYLOAD)],
                  {"h2n/distinct": "above", "h2n/disagree": "increase"}),
    # THE SAME LINE, RE-SPELLED.
    "nan-disarm": ([(JS_NAN, JS_NAN.replace("0x400000", "0x400000 "))],
                   {"h2n/distinct": "same", "h2n/disagree": "same"}),
}


def refuse(*why: str) -> int:
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


def half_classes() -> tuple[list[int], list[int]]:
    """The two classes, DISCOVERED by the half format's own rule.

    A half's exponent field is bits 10..14, so `h & 0x7c00` is the field and
    `h & 0x3ff` is the mantissa.  Both signs, because the negative half subnormals
    are as much of the class as the positive ones.
    """
    sub = [h for h in range(0x10000) if (h & 0x7C00) == 0 and (h & 0x3FF) != 0]
    nan = [h for h in range(0x10000) if (h & 0x7C00) == 0x7C00 and (h & 0x3FF) != 0]
    return sub, nan


def measure(rows: dict[str, str], oracle: dict[str, str], keys: list[str]) -> dict[str, int]:
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

    # THE ARM'S EDIT IS MADE ON A COPY OF THE SOURCE, BEFORE ANY LANE RUNS, and the
    # anchor must be found EXACTLY ONCE: an anchor that moved is a measurement of
    # nothing, and a plant that cannot fail is a comment.
    jsrc, csrc = JS_LANE.read_text(), C_LANE.read_text()
    j2 = jsrc
    for old, new in (ARMS.get(arm) or [[]])[0]:
        n = j2.count(old)
        if n != 1:
            return refuse(f"arm {arm}: anchor {old.strip()[:56]!r} found {n} site(s), "
                          f"expected 1 -- dtype.js moved")
        j2 = j2.replace(old, new)

    sub, nan = half_classes()
    sub_pos = [h for h in sub if h < 0x8000]
    keys_all = [f"h2f_{h:x}" for h in sub + nan]
    keys_sub, keys_nan = [f"h2f_{h:x}" for h in sub], [f"h2f_{h:x}" for h in nan]
    keys_pos = [f"h2f_{h:x}" for h in sub_pos]
    oracle = sfg.oracle_rows(sub + nan, [])
    want = len(keys_all)

    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            base_js = sfg.js_lane(work, jsrc, sub + nan, [])
            base_c = sfg.c_lane(work, csrc, sub + nan, [])
            arm_js = sfg.js_lane(work, j2, sub + nan, [])
    except RuntimeError as exc:
        return refuse(str(exc))

    for name, lane in (("js", base_js), ("c", base_c), ("js-arm", arm_js)):
        if len(lane) != want:
            return refuse(f"the {name} lane emitted {len(lane)} rows, expected {want}")
        missing = sorted(set(keys_all) - set(lane))
        if missing:
            return refuse(f"the {name} lane is missing {len(missing)} rows: {missing[:3]}")

    o_sub = measure(oracle, oracle, keys_sub)
    o_nan = measure(oracle, oracle, keys_nan)
    o_pos = measure(oracle, oracle, keys_pos)
    m = {("js", "h2s"): measure(base_js, oracle, keys_sub),
         ("js", "h2n"): measure(base_js, oracle, keys_nan),
         ("js", "h2s+"): measure(base_js, oracle, keys_pos),
         ("c", "h2s"): measure(base_c, oracle, keys_sub),
         ("c", "h2n"): measure(base_c, oracle, keys_nan),
         ("c", "h2s+"): measure(base_c, oracle, keys_pos),
         ("js-arm", "h2s"): measure(arm_js, oracle, keys_sub),
         ("js-arm", "h2n"): measure(arm_js, oracle, keys_nan),
         ("js-arm", "h2s+"): measure(arm_js, oracle, keys_pos)}

    print(f"float-halfclass-gate: {len(sub)} half subnormals + {len(nan)} half NaNs, "
          f"3 lanes (ORACLE / dtype.c / dtype.js)")
    print(f"  h2s SUBNORMALS: the map must be INJECTIVE -- {len(sub_pos)} positive "
          f"inputs, {len(sub_pos)} distinct outputs")
    print("  h2n NaNs: the map must NOT be injective -- CPython canonicalises every "
          "half NaN to one f32 NaN per sign")
    for lane in ("js", "c"):
        print(f"  {lane:<7} h2s distinct {m[(lane, 'h2s+')]['distinct']}/{len(sub_pos)} "
              f"positive (oracle {o_pos['distinct']}), {m[(lane, 'h2s')]['distinct']}"
              f"/{len(sub)} both signs, disagree {m[(lane, 'h2s')]['disagree']}"
              f"/{len(sub)} | h2n distinct {m[(lane, 'h2n')]['distinct']} "
              f"(oracle {o_nan['distinct']}), disagree {m[(lane, 'h2n')]['disagree']}"
              f"/{len(nan)}")
    print(f"  WITNESS h2s m=1 -> {base_js['h2f_1']} | m=513 -> {base_js['h2f_201']} | "
          f"h2n 0x7c01 -> {base_js['h2f_7c01']} | 0x7fff -> {base_js['h2f_7fff']}")
    print(f"  RULE c extracted sha256="
          f"{hashlib.sha256(sfg.extract_c(csrc, 'fp16_f32').encode()).hexdigest()[:16]} "
          f"bytes={len(sfg.extract_c(csrc, 'fp16_f32'))}")

    if arm is None:
        for lane in ("js", "c"):
            for cls, keys, o in (("h2s", keys_sub, o_sub), ("h2n", keys_nan, o_nan)):
                got = m[(lane, cls)]
                if got["distinct"] != o["distinct"]:
                    print(f"float-halfclass-gate: {verdict_of(FAIL)} -- the {lane} lane "
                          f"answers {got['distinct']} distinct f32 patterns on the {cls} "
                          f"class where the oracle answers {o['distinct']}")
                    return FAIL
                if got["disagree"]:
                    print(f"float-halfclass-gate: {verdict_of(FAIL)} -- the {lane} lane "
                          f"disagrees with the oracle on {got['disagree']} {cls} rows")
                    return FAIL
            # THE INJECTIVITY CLAIM, ON THE POSITIVE CLASS ALONE: the sign bit cannot
            # collide with itself, so the positive class is where injectivity is a
            # question at all, and its count is stated against the ORACLE's.
            if m[(lane, "h2s+")]["distinct"] != o_pos["distinct"]:
                print(f"float-halfclass-gate: {verdict_of(FAIL)} -- the {lane} lane "
                      f"answers {m[(lane, 'h2s+')]['distinct']} distinct f32 patterns "
                      f"over the {len(sub_pos)} positive half subnormals where the "
                      f"oracle answers {o_pos['distinct']}")
                return FAIL
        print(f"float-halfclass-gate: {verdict_of(PASS)} -- the js lane has the oracle's "
              f"shape on both classes and agrees with it on {want} rows")
        return PASS

    # THE ARM'S STATEMENT, CHECKED AGAINST THE RUN.
    print(f"  ARM {arm}: h2s distinct {m[('js', 'h2s')]['distinct']} -> "
          f"{m[('js-arm', 'h2s')]['distinct']}, disagree "
          f"{m[('js', 'h2s')]['disagree']} -> {m[('js-arm', 'h2s')]['disagree']} | "
          f"h2n distinct {m[('js', 'h2n')]['distinct']} -> "
          f"{m[('js-arm', 'h2n')]['distinct']}, disagree "
          f"{m[('js', 'h2n')]['disagree']} -> {m[('js-arm', 'h2n')]['disagree']}")
    for old, new in ARMS[arm][0]:
        print(f"    {old.strip()[:58]!r} -> {new.strip()[:58]!r}")
    for key, rel in ARMS[arm][1].items():
        cls, field = key.split("/")
        base_v = m[("js", cls)][field]
        arm_v = m[("js-arm", cls)][field]
        if rel == "same":
            ok = arm_v == base_v
        elif rel in ("below", "decrease"):
            ok = arm_v < base_v
        elif rel in ("above", "increase"):
            ok = arm_v > base_v
        else:
            ok = False
        if not ok:
            print(f"  ARM {arm} VIOLATED: {key} is {arm_v}, and the arm says {rel} "
                  f"of {base_v}")
            return FAIL
    print(f"float-halfclass-gate: {verdict_of(PASS)} -- arm {arm} did what it says")
    return PASS


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="the two half classes, and their properties")
    ap.add_argument("--plant", choices=sorted(ARMS))
    ns = ap.parse_args()
    sys.exit(run(arm=ns.plant))
