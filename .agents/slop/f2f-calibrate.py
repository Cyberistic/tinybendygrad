#!/usr/bin/env python3
"""f2f-calibrate.py -- prove `f2f-arena.bend`'s FORWARD detector CAN FAIL, in BOTH
directions, and measure (not assert) the `f2f-pad.sh` sweep's calibration.

  f2f-calibrate.py [FIXED.bend]

WHY THIS FILE IS THE POINT. A detector that reports 0 on a correct file is a gate that
says PASS; a detector that reports N on a broken file is evidence. Neither is enough,
because the predecessor's FORWARD predicate was INVERTED -- `is_lt(src, i)` is TRUE for
every well-formed edge -- so it fired on EVERY row, including `0 NOOP <- 0,0`, and a
page of FORWARD read as a thorough report. Four directions, all MEASURED:

  1  FALSE POSITIVE. The INVERTED predicate is rebuilt as a probe and run on the FIXED
     file with the SAME harness. It must flag every row. If it does not, the account in
     `f2f-arena.bend`'s header is wrong and this file says so.
  2  FALSE NEGATIVE. Five defects are injected into the FIXED file one at a time. Each is
     reported as CAUGHT (FORWARD count rose) or BLIND, and the catch rate is printed as a
     NUMBER with the denominator.
  3  THE COUNT LANE. One of the five (`stale-name`) is the shape a forward count CANNOT
     see -- it clobbers nodes that had no forward edge -- so its symptom is a NODE COUNT.
     It is run through both lanes and the disagreement between them is reported: a suite
     where lane A catches four and lane B catches the fifth is the honest shape.
  4  THE PAD SWEEP'S CALIBRATION. `.agents/slop/f2f-pad.sh` prepends `pad` PARAMs at six
     sizes and asks whether the rows MOVE. Every relative cell compares `Found.i(u)`
     against `Found.i(v)`, so a UNIFORM SHIFT in how an index is read CANCELS. The sweep
     is therefore run on injected defects and its detection rate is REPORTED, not
     asserted -- and a clean sweep over a fixed file is stated to be no evidence at all
     for the aliasing fix, which is what `f2f-pad.sh`'s own header already says.
"""
import hashlib
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
S = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
PROBE = ".agents/slop/f2f-arena.bend"

FWD1_GOOD = """def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(j, src)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)"""

# THE INVERTED PREDICATE: `src < i` instead of `i <= src`. The parameters are swapped and
# NOTHING ELSE, so every other line of the probe is byte-identical to the good one and the
# only variable is the predicate.
FWD1_BAD = """def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(src, j)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)"""

GHOST = """
# INJECTED by f2f-calibrate.py: `f2f.em1` restored verbatim, so the mutation is about
# the ARENA THREADING and not about a missing def.
def f2f.em1.ghost(+ar: O.Arena, +k: U32) -> U32:
  +s = dd_wk(ar, T.tx_powi(k))
  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))
  +d = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))
  O.Found.i(d)
"""

INJECT = {
    # the ORIGINAL aliasing, restored VERBATIM at all THREE sites. `f2f.em1` grew three
    # nodes into a COPY and returned only the last INDEX, so the `tx_shl` that followed
    # wrote into the pre-`em1` arena -- the definition of one arena, two builders.
    "stale-arena": [(
        "  +qm = f2f.qmask(O.Found.ar(a), te, tm)\n  dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))",
        "  +b = T.tx_shl(O.Found.ar(a), f2f.em1.ghost(O.Found.ar(a), te), tm)\n"
        "  dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))"),
     ("  +q = f2f.qnan.c(O.Found.ar(fn), te, tm)",
        "  +q1 = T.tx_shl(O.Found.ar(fn), f2f.em1.ghost(O.Found.ar(fn), te), tm)\n"
        "  +qk = dd_wk(O.Found.ar(q1), T.tx_powi(U32.sub(tm, 1)))\n"
        "  +q = dd_or(O.Found.ar(qk), O.Found.i(q1), O.Found.i(qk))"),
     ("  +qm = f2f.qmask(O.Found.ar(a), te, tm)\n  +c = dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))",
        "  +b = T.tx_shl(O.Found.ar(a), f2f.em1.ghost(O.Found.ar(a), te), tm)\n"
        "  +c = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))"),
     ("def f2f.udt(+to: S.Dt) -> S.Dt:\n  f2f.udt.of(f2f_dt(to), S.uint32())",
      "def f2f.udt(+to: S.Dt) -> S.Dt:\n  f2f.udt.of(f2f_dt(to), S.uint32())\n"
      + GHOST.rstrip("\n"))],
    # ONE NODE STALE -- the shape that produced `MUL <- 4,6`
    "stale-found": [(
        "      +nm = dd_mul(O.Found.ar(n1), O.Found.i(mxc), O.Found.i(n1))",
        "      +nm = dd_mul(O.Found.ar(ne), O.Found.i(mxc), O.Found.i(n1))")],
    # THE ARENA NAME PASSED PAST A CALL THAT ALREADY GREW A COPY. `rne`'s own edges all
    # still point backwards, so nothing about this is a forward edge: it is a node COUNT.
    "stale-name": [(
        "    case Some{O.Found{+xa, +xi}}: f2f.down.norm.put(tudt, xa, xi, fr, to)",
        "    case Some{O.Found{+xa, +xi}}: f2f.down.norm.put(tudt, ar, xi, fr, to)")],
    # A WRONG CONSTANT: position independent, so no pad sweep can see it
    "wrong-const": [(
        "def dd_mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def dd_mask1(+k: U32) -> U32:\n  U32.add(T.tx_powi32(k), 1)")],
    # A WRONG OFFSET: the `- 1` dropped, also position independent
    "wrong-offset": [(
        "def dd_mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def dd_mask1(+k: U32) -> U32:\n  T.tx_powi32(k)")],
    # A FIXED WRONG INDEX: `dd_band`'s mask argument replaced by an arena INDEX
    "wrong-index": [(
        "  +b = dd_band(O.Found.ar(a), O.Found.i(a), dd_mask1(fe))\n"
        "  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))",
        "  +b = dd_band(O.Found.ar(a), O.Found.i(a), O.Found.i(a))\n"
        "  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))")],
}


base_shape = -1


def run_probe(tag, probe_rel, src_rel, minrows=200):
    out = S / f"cal-{tag}.txt"
    r = subprocess.run(["./.agents/slop/f2f-run.sh", probe_rel, str(out),
                        str(src_rel), str(minrows)],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        return None, r.stderr.strip().split("\n")[-1][:160]
    txt = out.read_text()
    fwd = sum(1 for ln in txt.split("\n") if "FORWARD" in ln)
    rows = sum(1 for ln in txt.split("\n") if ln and ln[0].isdigit())
    nodes = {ln.split()[1]: int(ln.split("next=")[1].split()[0])
             for ln in txt.split("\n") if ln.startswith("# ")}
    return {"fwd": fwd, "rows": rows, "nodes": nodes}, ""


def trackers(out):
    """How many fixtures' `sig`/`k` rows DIFFER between pad 0 and the other five pads.

    `dd-bandpad.bend` prints `w1.p0sig=`, `w1.p1sig=` ... in ONE run, so the pads are a
    within-file comparison and no extra bend invocation is needed.
    """
    per = {}
    for ln in out.split("\n"):
        m = re.match(r"^(\w+)\.p(\d+)(sig|k)=", ln)
        if m:
            per.setdefault((m.group(1), m.group(3)), {})[int(m.group(2))] = ln.split("=", 1)[1]
    if not per:
        return None
    moved = sum(1 for _, pads in per.items()
                if 0 in pads and len(set(pads.values())) > 1)
    return {"moved": moved, "n": len(per)}


def shape_rows(path):
    """The SHAPE-lane score: how many slots disagree with the FIXED file's own dump.

    It is measured against the FIXED baseline, not against CPython, because the question
    here is "did the detector notice", and comparing to CPython would confound "the
    detector is blind" with "the port was already wrong here". CPython is the oracle for
    the port's correctness (`.agents/slop/f2f-arena-diff.py`); the fixed baseline is the
    oracle for the DETECTOR's sensitivity.
    """
    r = subprocess.run([sys.executable, ".agents/slop/f2f-arena-diff.py",
                        str(path), str(S / "cal-base.txt")],
                       cwd=ROOT, capture_output=True, text=True)
    m = re.search(r"SHAPE=(\d+)", r.stdout)
    return int(m.group(1)) if m else -1


def inject(src, cls, dst):
    s = open(src).read()
    for old, new in INJECT[cls]:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f"ANCHOR {n}-BAD for {cls}: {old[:70]!r}")
        s = s.replace(old, new, 1)
    open(dst, "w").write(s)
    return hashlib.md5(open(dst, "rb").read()).hexdigest()


def main():
    src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                       else "tinybendygrad/codegen/decomp/dtype.bend")
    print(f"FIXED {src} md5={hashlib.md5(src.read_bytes()).hexdigest()}")

    base, err = run_probe("base", PROBE, src)
    if base is None:
        print(f"  BASE RUN FAILED: {err}")
        return 2
    global base_shape
    base_shape = shape_rows(S / "cal-base.txt")
    print(f"  BASE FORWARD={base['fwd']} rows={base['rows']} SHAPE={base_shape} "
          f"nodes={base['nodes']}")

    # ---- 1  the inverted predicate
    print("\n[1] FALSE POSITIVE -- the INVERTED predicate, same file, same harness")
    ps = pathlib.Path(PROBE).read_text()
    assert ps.count(FWD1_GOOD) == 1, ps.count(FWD1_GOOD)
    inv = HERE / "f2f-arena-inverted.bend"
    inv.write_text(ps.replace(FWD1_GOOD, FWD1_BAD, 1))
    r, e = run_probe("inverted", str(inv), src)
    if r is None:
        print(f"  RUN FAILED: {e}")
    else:
        every = r["fwd"] == r["rows"]
        print(f"  inverted FORWARD={r['fwd']} rows={r['rows']} -> "
              + ("FIRES ON EVERY ROW. A flag that measures nothing and reads as a report."
                 if every else
                 f"does NOT fire everywhere ({r['fwd']}/{r['rows']}); the header's account "
                 f"of the inversion is WRONG"))
        print(f"  good     FORWARD={base['fwd']} rows={base['rows']} -> "
              f"{base['fwd']}/{base['rows']} rows")

    # ---- 2/3  injected defects
    print("\n[2]+[3] FALSE NEGATIVE -- injected defects, per lane")
    print(f"  {'defect':<14} {'FORWARD':>8} {'SHAPE':>6} {'nodes':>6}  verdict")
    rows_ = []
    for cls in INJECT:
        dst = S / f"cal-{cls}.bend"
        md5 = inject(src, cls, dst)
        r, e = run_probe(cls, PROBE, dst)
        if r is None:
            print(f"  {cls:<14} {'RUN FAILED':>8} {'':>6} {'':>6}  {e}")
            continue
        moved = [k for k in base["nodes"] if base["nodes"][k] != r["nodes"].get(k)]
        saw = r["fwd"] > base["fwd"]
        shp = shape_rows(S / f"cal-{cls}.txt")
        bshp = base_shape
        lanes = []
        if saw:
            lanes.append("FORWARD")
        if shp != bshp:
            lanes.append(f"LABEL({shp - bshp:+d})")
        if not saw and moved:
            lanes.append(f"COUNT({len(moved)}/{len(base['nodes'])})")
        rows_.append((cls, saw, moved, shp != bshp))
        print(f"  {cls:<14} {r['fwd']:>8} {shp:>6} {len(moved):>6}  "
              + (", ".join(lanes) if lanes else "BLIND TO ALL THREE -- reported, not closed"))
    n = len(rows_)
    for lane, sel in (("FORWARD", lambda c, s, m, h: s),
                      ("LABEL   ", lambda c, s, m, h: h),
                      ("COUNT   ", lambda c, s, m, h: m or s)):
        got = [c for c, s, m, h in rows_ if sel(c, s, m, h)]
        print(f"  lane {lane} caught {len(got)}/{n}: {got}")
    any_lane = [c for c, s, m, h in rows_ if s or h or m]
    print(f"  ANY lane caught {len(any_lane)}/{n}; blind to every lane "
          f"{n - len(any_lane)}/{n}: {[c for c, s, m, h in rows_ if not (s or h or m)]}")
    print("  A clean FORWARD count over a fixed file is NOT evidence for the aliasing")
    print("  fix. The fix's evidence is `stale-arena` going 0 -> N on the SAME harness.")

    # ---- 4  the pad sweep, measured as PAD-TRACKING
    print("\n[4] THE PAD SWEEP, MEASURED AS PAD-TRACKING (not asserted)")
    print("  The sweep prepends `pad` PARAMs at pads 0 1 2 5 17 64. A wrong answer that is")
    print("  an arena INDEX is a function of the fixture's POSITION, so prepending PARAMs")
    print("  moves it by exactly `pad` and the row's value DIFFERS BETWEEN PADS. A wrong")
    print("  CONSTANT and a dropped OFFSET are position independent, so every pad prints the")
    print("  same value and the sweep sees nothing. That is the whole calibration, measured")
    print("  here per defect rather than quoted.")
    for cls in ("wrong-index", "wrong-const", "wrong-offset", "stale-arena", "stale-found"):
        dst = S / f"cal-{cls}.bend"
        if not dst.exists():
            continue
        # `f2f-pad.sh AFTER_BEND [BEFORE_BEND]`, and it writes the BEFORE rows to
        # `$S/f2f-pad-before.txt`. So the INJECTED file goes SECOND. Passing it first --
        # which the first version of this file did -- reads back the FIXED file's rows and
        # reports 0/6 moved for every defect including one that provably moves. That is
        # how a calibration harness comes to say "the sweep is blind" when it is not.
        r = subprocess.run([".agents/slop/f2f-pad.sh", str(src), str(dst)], cwd=ROOT,
                           capture_output=True, text=True)
        # `f2f-pad.sh` writes its rows to FILES, not to stdout, so the pad leg is read
        # from `$S/f2f-pad-before.txt` -- which is the INJECTED file at all six pads. The
        # pads are compared WITHIN that one file, so the fixed file is not involved at all
        # and a MOVE is attributable to the defect alone.
        pf = S / "f2f-pad-before.txt"
        got = trackers(pf.read_text()) if pf.exists() and pf.stat().st_size else None
        if got is None:
            print(f"  {cls:<14} (sweep did not complete: "
                  + (r.stdout.strip().split("\n") or [""])[-1][:110] + ")")
            continue
        print(f"  {cls:<14} pad-tracking fixtures moved: {got['moved']}/{got['n']}  "
              f"-> {'SEEN (position-dependent)' if got['moved'] else 'BLIND (position-independent)'}")
    print("  NOTE 1: `f2f-pad-oracle.py` still builds its receiver with the THREE-ARG")
    print("  `UOp.variable(nm, 0, fr)` -- `ops.py:1015` puts `dtype` FOURTH -- so the sweep's")
    print("  CPython lane measures the `v.cast(fr)` workaround, not `f2f_dt[fr]`. Only the")
    print("  port-vs-port pad leg above is sound; the CPython leg is reported, not trusted.")
    print("  NOTE 2: the sweep is a SIX-PAD FUNCTION of the fixture, not a function of the")
    print("  defect, so the detection rate above is a property of BOTH. One pad has no")
    print("  discriminating power at all.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
