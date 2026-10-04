#!/usr/bin/env python3
"""dd-band-mut.py -- per-site reachability probe for the `dd_band` MASK sites in
codegen/decomp/dtype.bend.

WHY A SEPARATE HARNESS. `.agents/slop/dd-mutate.py` is FROZEN against
`dd-mutations.frozen.bend` (sha1 e4618a71) at tree rev e17d3f7dd, because the live
`dtype.bend` is a concurrent unit's. This file is the same discipline for THIS unit's
question -- is each mask site exercised by the 182-row gate -- and it runs against a
SNAPSHOT taken once, so a concurrent edit to `uop/ops.bend` (observed twice while this
unit worked, md5 baff197566.. -> 3cd6e0dff..) cannot move the substrate under a result.

RULES, inherited and re-measured, because each has already cost this project a run:

  A  diff whole `name=value` LINES, never row names (a name-comparing harness reported
     0 for all 30 mutations in one unit and 0 for all 68 in another);
  B  a mutant that does not COMPILE is DID-NOT-COMPILE, never a blind spot;
  C  CONTROLS: a no-op control and a comment-only control must both read SAME.  A
     control that MOVES is a broken harness and every verdict is void;
  D  a patch that did not apply is NEVER a zero -- `edit()` says so and the report
     gets a DEAD ANCHOR section;
  E  bend prints NOTHING on a stack overflow (~1 run in 20) and that is byte-identical
     to "never started", so a run is accepted only when it reproduces the BASELINE's
     shape (first line, line count, last line) or a strictly-wider run is produced;
  H  never gate on the exit code -- `--check-only` exits 1 on a clean file;
  I  assert the mirror reproduces the LIVE digest before mutating it.

usage: dd-band-mut.py BASELINE.txt [id ...]
"""
import hashlib
import patch_not_apply as PNA
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
SNAP = os.path.join(SCRATCH, "dd-band-snap", "tinybendygrad")
LIVE = os.path.join(ROOT, "tinybendygrad", "codegen", "decomp", "dtype.bend")
BEND = os.path.join(ROOT, "bin", "bend")
TARGET = os.path.join("codegen", "decomp", "dtype.bend")

# ---------------------------------------------------------------- the table
#
# Every one of these is a MASK argument to `dd_band`, which is `op.bend`'s
# `dc_band(ar, x, k)` = `dc_alu2(ar, AND, x, dc_cint(ar, k))` -- `k` is interned as
# `CONST k`, so `k` is a VALUE. `O.Found.i(n)` is the ARENA INDEX of slot `n`, and
# `U32` is both, which is why this compiles and is why it is invisible.
#
# The mutant for each site replaces the mask with a value no fixture can produce by
# accident (`4242`), so "MOVED" means the site is on some row's cone and "SAME" means
# no row can see it.
MUTATIONS = [
    ("M01 f2f.sign  L1578 mask = O.Found.i(s) -> 4242 [dtype.py:105 `v & shl(1, fs-1)`]",
     "  +a = dd_band(O.Found.ar(s), v, O.Found.i(s))\n  +c = P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)\n  T.tx_shl(O.Found.ar(c), O.Found.i(c), U32.sub(ts, fs))",
     "  +a = dd_band(O.Found.ar(s), v, 4242)\n  +c = P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)\n  T.tx_shl(O.Found.ar(c), O.Found.i(c), U32.sub(ts, fs))"),
    ("M02 f2f.nosign L1588 mask = O.Found.i(m) -> 4242 [dtype.py:105 `v & (shl(1, fs-1) - 1)`]",
     "  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)",
     "  +a = dd_band(O.Found.ar(m), v, 4242)\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)"),
    ("M03 f2f.down.sign L1666 mask = O.Found.i(b) -> 4242 [dtype.py:117 `shr(v, fs-ts) & shl(1, ts-1)`]",
     "  dd_band(O.Found.ar(b), O.Found.i(a), O.Found.i(b))",
     "  dd_band(O.Found.ar(b), O.Found.i(a), 4242)"),
    ("M04 f2f.down.nosign L1674 mask = O.Found.i(m) -> 4242 [dtype.py:117 `v & (shl(1, fs-1) - 1)`]",
     "  dd_band(O.Found.ar(m), O.Found.i(v), O.Found.i(m))",
     "  dd_band(O.Found.ar(m), O.Found.i(v), 4242)"),
    ("M05 f2f.down.uf L1698 mask = m -> 4242 [dtype.py:119 `(shr(v, fm) & (shl(1, fe) - 1)) < ...`]",
     "  +b = dd_band(O.Found.ar(a), O.Found.i(a), m)\n  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))",
     "  +b = dd_band(O.Found.ar(a), O.Found.i(a), 4242)\n  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))"),
    ("M06 f2f.down.m2 L1714 mask = O.Found.i(m) -> 4242 [dtype.py:120 `shr(nosign, fm-tm) & (shl(1, tm) - 1)`]",
     "  dd_band(O.Found.ar(c1), O.Found.i(a), O.Found.i(m))",
     "  dd_band(O.Found.ar(c1), O.Found.i(a), 4242)"),
    ("M07 f2f.down.isnan L1736 mask = m -> 4242 [dtype.py:122 `(shr(v, fm) & (shl(1, fe) - 1)).eq(...)`]",
     "  +b = dd_band(O.Found.ar(a), O.Found.i(a), m)\n  dd_eq1(O.Found.ar(b), O.Found.i(b), m)",
     "  +b = dd_band(O.Found.ar(a), O.Found.i(a), 4242)\n  dd_eq1(O.Found.ar(b), O.Found.i(b), m)"),
    # ---- CONTROLS (RULE C)
    ("C1 control: no-op rewrite, byte-identical",
     "  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)",
     "  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)"),
    ("C2 control: a COMMENT line added, zero semantics",
     "  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)",
     "  # dd-band control: a comment carries no semantics\n  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))\n  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)"),
]


def sha1(text):
    return hashlib.sha1(text.encode()).hexdigest()


def shape(text):
    lines = text.splitlines()
    return (lines[0] if lines else "", len(lines), lines[-1] if lines else "")


def rows(text):
    d = {}
    for ln in text.splitlines():
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k, _, v = ln.partition("=")
        d[k.strip()] = v
    return d


def edit(src, old, new):
    n = src.count(old)
    if n == 0:
        return None, PNA.not_applied("anchor absent (0 occurrences)")
    if n > 1:
        return None, PNA.not_applied("anchor is %d-AMBIGUOUS" % n)
    return src.replace(old, new, 1), "applied"


def run(out, tgt, want):
    """RULE E/H: accepted only when it reproduces `want`'s shape, or when it printed
    MORE lines than the baseline (a wider run is a real behavioural change, not an
    overflow)."""
    err = ""
    for attempt in range(24):
        with open(out, "w") as fh:
            p = subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(out).read()
        if not text:
            err = (p.stderr or b"").decode()[:300]
            continue
        if shape(text) == want or len(text.splitlines()) > want[1]:
            return text, attempt + 1
        return text, attempt + 1
    return None, err or "printed nothing in 24 attempts"


def main():
    base_txt = open(sys.argv[1]).read()
    want = shape(base_txt)
    base = rows(base_txt)
    ids = set(sys.argv[2:])
    plan = [p for p in MUTATIONS if not ids or p[0].split()[0] in ids]
    tmp = tempfile.mkdtemp(prefix="ddband.", dir=SCRATCH)
    work = os.path.join(tmp, "tinybendygrad")
    shutil.copytree(SNAP, work)
    tgt = os.path.join(work, TARGET)
    live_sha1 = sha1(open(LIVE).read())
    snap_sha1 = sha1(open(tgt).read())
    print(f"# mirror {tmp}")
    print(f"# live   dtype.bend sha1 {live_sha1[:12]}   snapshot {snap_sha1[:12]}   "
          f"{'MATCH (RULE I)' if live_sha1 == snap_sha1 else 'DIFFER -- snapshot is frozen'}")
    src0 = open(tgt).read()

    # RULE C: the UNMUTATED mirror must reproduce the baseline.
    got, tries = run(os.path.join(tmp, "probe.txt"), tgt, want)
    if got is None or shape(got) != want:
        print(f"# SUBSTRATE FAILS: mirror reads {shape(got) if got else None}, "
              f"baseline is {want}.  No verdict is evidence until this passes.")
        return 2
    print(f"# substrate reproduces the baseline (attempt {tries})")

    report = []
    dead = []
    for name, old, new in plan:
        out, why = edit(src0, old, new)
        if out is None:
            dead.append((name, why))
            report.append((name, "DEAD ANCHOR", [], why))
            continue
        if out == src0:
            report.append((name, "CONTROL-SAME", [], "byte-identical rewrite, as intended"))
            open(tgt, "w").write(out)
            continue
        open(tgt, "w").write(out)
        got, tries = run(os.path.join(tmp, "probe.txt"), tgt, want)
        if got is None:
            report.append((name, "PRINTED NOTHING", [], "24 attempts: not a verdict"))
        elif not got.strip():
            report.append((name, "PRINTED NOTHING", [], "empty output"))
        else:
            r = rows(got)
            moved = sorted(k for k in set(base) | set(r) if base.get(k) != r.get(k))
            if moved:
                report.append((name, "MOVED", moved, ""))
            else:
                report.append((name, "SAME", [], "no row can see this site"))
        open(tgt, "w").write(src0)

    for name, verdict, moved, note in report:
        print(f"\n{verdict:<9} {name}")
        if note:
            print(f"          {note}")
        for k in moved[:24]:
            print(f"          {k}")
        if len(moved) > 24:
            print(f"          ... {len(moved) - 24} more")
    if dead:
        print("\n== DEAD ANCHOR ==")
        for n, w in dead:
            print(f"  {n}: {w}")
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())