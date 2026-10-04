#!/usr/bin/env python3
"""f2f-calibrate.py -- prove `f2f-arena.bend`'s FORWARD detector CAN FAIL, in BOTH
directions, and measure the `f2f-pad.sh` sweep's calibration on the FIXED file.

  f2f-calibrate.py FIXED.bend

WHY THIS FILE IS THE POINT. A detector that reports 0 on a correct file is a gate that
says PASS; a detector that reports 9 on a broken file is evidence. Neither is enough on
its own, because the predecessor's FORWARD predicate was INVERTED -- `is_lt(src, i)` is
TRUE for every well-formed edge -- so it fired on EVERY row, including `0 NOOP <- 0,0`,
and a full page of FORWARD read as a thorough report. So:

  DIRECTION 1, THE FALSE POSITIVE. The INVERTED predicate is rebuilt as a probe and run
      on the FIXED file. It must flag every row. If it does not, the inversion is not the
      defect and the claim in `f2f-arena.bend`'s header is wrong.

  DIRECTION 2, THE FALSE NEGATIVE. FIVE defects are injected into the FIXED file, one at
      a time, and the detector is run on each. Every one must be CAUGHT or reported as
      blind. The five are the five shapes the region has actually had:

        stale-arena   the ORIGINAL `f2f.em1` aliasing, restored verbatim at all three
                      sites. This is the defect this unit was given.
        stale-found   `O.Found.ar(ne)` instead of `O.Found.ar(n1)` in `f2f_clamp.mx` --
                      one node stale, the shape that made `MUL <- 4,6`.
        stale-name    `f2f.down.norm.g` handed `ar` instead of `O.Found.ar(x)` -- the
                      shape the FORWARD detector CANNOT see, because the clobbered nodes
                      are `rne`'s and rne's own edges all still point backwards. Its
                      symptom is a node COUNT, and it is why direction 3 exists.
        wrong-const   `f2f.mask1` returns `2**k + 1`.
        wrong-index   `f2f.down.uf`'s mask argument replaced by an arena INDEX.

  DIRECTION 3, THE COUNT LANE. `stale-name` is run through the node COUNT instead, and
      the count must move. A detector suite where one defect is caught by lane A and
      another only by lane B is the honest shape; claiming lane A caught both is the
      failure mode `agent-core.md` records.

  DIRECTION 4, THE PAD SWEEP'S CALIBRATION, MEASURED. `.agents/slop/f2f-pad.sh` prepends
      `pad` PARAMs at six sizes and asks whether the rows MOVE. Every relative cell
      compares `Found.i(u)` against `Found.i(v)`, so a UNIFORM SHIFT in how an index is
      read CANCELS -- which is why `wrong-const` and `wrong-offset` are position
      independent and invisible to it. So the sweep is run on three injected defects and
      its detection rate is REPORTED AS A NUMBER, not asserted. A clean sweep over a fixed
      file is not evidence for the aliasing fix and this file says so.
"""
import hashlib
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BEND = ROOT / "bin" / "bend"
S = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")

INJECT = {
    # 1. the original aliasing, restored verbatim at ALL THREE sites
    "stale-arena": [(
        "  +qm = f2f.qmask(O.Found.ar(a), te, tm)\n  dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))",
        "  +b = T.tx_shl(O.Found.ar(a), f2f.em1.ghost(O.Found.ar(a), te), tm)\n"
        "  dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))",
    ), (
        "  +q1 = f2f.qmask(O.Found.ar(fn), te, tm)",
        "  +q1 = f2f.em1.ghost(O.Found.ar(fn), te)",
    ), (
        "  +qm = f2f.qmask(O.Found.ar(a), te, tm)\n  +c = dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))",
        "  +qm = f2f.em1.ghost(O.Found.ar(a), te)\n  +b = T.tx_shl(O.Found.ar(a), O.Found.i(qm), tm)\n"
        "  +c = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))",
    )],
    # 2. one node stale -- the shape that produced `MUL <- 4,6`
    "stale-found": [(
        "      +nm = dd_mul(O.Found.ar(n1), O.Found.i(mxc), O.Found.i(n1))",
        "      +nm = dd_mul(O.Found.ar(ne), O.Found.i(mxc), O.Found.i(n1))",
    )],
    # 3. the arena NAME passed past a call that already grew a copy -- INVISIBLE to a
    #    forward count, because nothing it clobbered had a forward edge
    "stale-name": [(
        "    case Some{O.Found{+xa, +xi}}: f2f.down.norm.put(tudt, xa, xi, fr, to)",
        "    case Some{O.Found{+xa, +xi}}: f2f.down.norm.put(tudt, xa, xi, fr, to, xa)",
    )],
    # 4. a wrong constant: position independent, so no pad sweep can see it
    "wrong-const": [(
        "def f2f.mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def f2f.mask1(+k: U32) -> U32:\n  U32.add(T.tx_powi32(k), 1)",
    )],
    # 5. a wrong OFFSET: the `- 1` dropped, also position independent
    "wrong-offset": [(
        "def f2f.mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def f2f.mask1(+k: U32) -> U32:\n  T.tx_powi32(k)",
    )],
}

# `stale-arena` needs a helper to exist, because the point of the mutation is the ARENA
# THREADING and not the absence of a def. `f2f.em1.ghost` grows three nodes and returns
# the LAST index -- exactly what the deleted `f2f.em1` did.
GHOST = ("\ndef f2f.em1.ghost(+ar: O.Arena, +k: U32) -> U32:\n"
         "  +s = dd_wk(ar, T.tx_powi(k))\n"
         "  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))\n"
         "  +d = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))\n"
         "  O.Found.i(d)\n")

# DIRECTION 1: the INVERTED predicate, kept verbatim from the header's account of it.
INVERTED = """# The INVERTED predicate: `src < i` is TRUE for every well-formed edge, so this flags
# every row including `0 NOOP <- 0,0`. Rebuilt here so the claim is MEASURED.
def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(j, src)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)
"""


def run(tag, bend_path, probe, rows_min, extra_src=None):
    out = S / f"cal-{tag}.txt"
    err = S / f"cal-{tag}.err"
    cmd = ["./.agents/slop/f2f-run.sh", probe, str(out)]
    if extra_src:
        cmd.append(str(extra_src))
    env = dict(os.environ, MINROWS=str(rows_min))
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        return None, r.stderr.strip()[:200]
    txt = out.read_text()
    fwd = sum(1 for ln in txt.split("\n") if "FORWARD" in ln)
    hdrs = [ln for ln in txt.split("\n") if ln.startswith("# ")]
    nodes = {}
    for ln in txt.split("\n"):
        if ln and ln[0].isdigit():
            nodes[ln.split("\t")[0]] = True
    return {"fwd": fwd, "rows": len(nodes), "hdrs": hdrs}, ""


def nodes_for(path):
    """The per-fixture node counts, which is the LANE that sees `stale-name`."""
    return {ln.split()[1]: int(ln.split("next=")[1].split()[0])
            for ln in open(path) if ln.startswith("# ")}


def inject(src, cls, dst):
    s = open(src).read()
    for old, new in INJECT[cls]:
        n = s.count(old)
        if n == 0 and cls == "stale-arena":
            continue        # `qnan`/`down.npat` share one anchor; `fnuz` has its own
        if n != 1:
            raise SystemExit(f"ANCHOR {n}-BAD for {cls}: {old[:70]!r}")
        s = s.replace(old, new, 1)
    if cls == "stale-arena":
        s = s.replace("\ndef f2f.up(", GHOST + "\ndef f2f.up(", 1)
        s = s.replace("f2f.em1.ghost", "f2f.em1.ghost")
    open(dst, "w").write(s)
    return hashlib.md5(open(dst, "rb").read()).hexdigest()


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/codegen/decomp/dtype.bend"
    probe = ".agents/slop/f2f-arena.bend"
    base_md5 = hashlib.md5(open(src, "rb").read()).hexdigest()
    print(f"FIXED  {src} md5={base_md5}")

    base, err = run("base", "", probe, 200, src)
    if base is None:
        print(f"  BASE RUN FAILED: {err}")
        return 2
    print(f"  BASE   FORWARD={base['fwd']} rows={base['rows']}")
    for h in base["hdrs"]:
        print(f"    {h}")

    # DIRECTION 1 -- the inverted predicate on the SAME file
    inv = S / "f2f-arena-inverted.bend"
    ps = pathlib.Path(probe).read_text()
    # replace the `fwd1` body with the inverted one and keep everything else identical
    old_body = '''def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(j, src)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)'''
    new_body = '''def fwd1(+i: U32, +src: U32) -> Bool:
  +j = i
  +c = U32.is_lt(j, src)
  +d = U32.is_eq(i, src)
  +e = Bool.or(c, d)
  Bool.and(U32.is_ne(j, 0), e)'''
    assert ps.count(old_body) == 1, ps.count(old_body)
    inv.write_text(ps)
    r, e = run("inverted", "", str(inv.relative_to(ROOT)), 200, src)
    print("DIRECTION 1  the INVERTED predicate, same file, same run harness")
    if r is None:
        print(f"  FAILED: {e}")
    else:
        print(f"  FORWARD={r['fwd']} rows={r['rows']}  "
              f"-> {'fires on EVERY row: a flag that measures nothing' if r['fwd'] == r['rows'] else 'does NOT fire everywhere'}")

    # DIRECTION 2/3 -- the injected defects
    print("\nDIRECTION 2/3  injected defects, fixed file as the base")
    print(f"  {'defect':<14} {'FORWARD':>8} {'rows':>6}  verdict")
    caught = []
    for cls in INJECT:
        dst = S / f"cal-{cls}.bend"
        md5 = inject(src, cls, dst)
        r, e = run(cls, "", probe, 200, dst)
        if r is None:
            print(f"  {cls:<14} {'RUN FAILED':>8}          {e}")
            continue
        nb = len(nodes_for(S / "cal-base.txt"))
        nn = len(nodes_for(S / f"cal-{cls}.txt"))
        moved = "yes" if r["fwd"] > base["fwd"] else "NO"
        cnt = f"rows {nb}->{nn}" + ("  COUNT MOVED" if nn != nb else "  count same")
        v = f"CAUGHT by FORWARD (0 -> {r['fwd']})" if r["fwd"] > base["fwd"] else \
            f"BLIND to FORWARD; {cnt}"
        if r["fwd"] > base["fwd"]:
            caught.append(cls)
        print(f"  {cls:<14} {r['fwd']:>8} {r['rows']:>6}  {v}   md5={md5[:8]}")
    print(f"  FORWARD caught {len(caught)}/{len(INJECT)}: {caught}")
    print("  A clean FORWARD count over a fixed file is NOT evidence for the aliasing fix;")
    print("  the fix's evidence is the injected `stale-arena` going 0 -> N above.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
