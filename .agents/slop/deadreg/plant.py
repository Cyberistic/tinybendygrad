#!/usr/bin/env python3
"""plant.py -- THE PLANT: delete the twenty registrations and see what moves.

The ten C registrations are `dtype.c`'s LAST 53 lines and the ten JS ones are
`dtype.js`'s LAST 13, so deleting them renumbers NOTHING above them -- which is
the only reason this is a candidate at all: `dtype.bend` cites `dtype.c` by
`file:line` in eight places, including `:262-263` for the zero branch, so any
deletion inside the file body falsifies a citation in a file this unit does not
own.  This runs the same six configurations as `build4.py` with the tails gone.
"""
import pathlib, re, shutil, subprocess, sys, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build4 as B

TAILS = {"tinybendygrad/runtime/dtype.c": "// One guard per registration",
         "tinybendygrad/runtime/dtype.js": "io_eff(CID(Dt.bf16)"}

def run_one(tree, work, tag, names, seam=None):
    if seam is not None:
        B.patch_seam(tree, "bf16" if seam == "disarm" else seam)
    (work / f"{tag}.bend").write_text(B.PROLOGUE % (
        tree, tree, B.body(names, (tree / "tinybendygrad" / "dtype.bend").read_text()), tag, len(names)))
    res = {}
    for ext in ("c", "js"):
        a = work / f"{tag}.{ext}"
        a.unlink(missing_ok=True)
        r = B.bend([str(work / f'{tag}.bend'), "-o", str(a)])
        res[ext] = {"rc": r.returncode, "text": a.read_text() if a.exists() else "",
                    "err": (r.stdout + r.stderr)[-500:] if r.returncode else ""}
    cc = subprocess.run(["cc", "-w", "-o", str(work / f"{tag}.exe"), str(work / f"{tag}.c")],
                        capture_output=True, text=True) if res["c"]["rc"] == 0 else None
    exe = None
    if cc is not None and cc.returncode == 0:
        p = subprocess.run([str(work / f"{tag}.exe")], capture_output=True, text=True, timeout=60)
        exe = (p.returncode, p.stdout.strip(), (p.stderr or "").strip()[:200])
    nd = subprocess.run(["node", str(work / f"{tag}.js")], capture_output=True, text=True, timeout=60) \
        if res["js"]["rc"] == 0 else None
    return {"tag": tag, "bend_c": res["c"]["rc"], "bend_js": res["js"]["rc"],
            "cc": cc.returncode if cc else None, "exe": exe,
            "node": (nd.returncode, nd.stdout.strip(), (nd.stderr or "").strip()[:300]) if nd else None,
            "emitted_c": res["c"]["text"].count("bf16_run"),
            "err": res["c"]["err"] or res["js"]["err"]}

def counts(src):
    """`(dtype.c registrations, dtype.js registrations)` counted from SOURCE TEXT.

    Whitespace-tolerant on purpose: the DISARM deletes exactly the spaces this
    regex would otherwise depend on, and both arms must count the same."""
    c = len(re.findall(r"io_eff\(CID\(Dt\.\w+\)\s*,\s*\w+_run\s*,\s*0\s*\)", src["tinybendygrad/runtime/dtype.c"]))
    j = len(re.findall(r"^io_eff\(CID\(Dt\.\w+\)", src["tinybendygrad/runtime/dtype.js"], re.M))
    return (c, j)

def arms():
    """shipped / DISARM (whitespace only) / PLANT (the registrations deleted).

    THE DISARM IS WHAT MAKES THE PLANT'S ZERO A MEASUREMENT.  Deleting the twenty
    registrations moves nothing in every reachable configuration -- and so would a
    file that had been emptied of something irrelevant.  A whitespace-only
    reformat of those same twenty lines is the same program with the same
    registrations, and it MUST count identically; if it counted differently, the
    counter would be reading text rather than registrations and the plant's zero
    would be about the counter.
    """
    shipped = {r: (B.REPO / r).read_text() for r in TAILS}
    dis = dict(shipped)
    for r, s in dis.items():
        # Whitespace only, and inside `io_eff(CID(Dt.…` calls only.  `[^;]*?` spans
        # newlines so the MULTI-LINE JS arrow registrations are covered too -- a
        # single-line regex matched all ten of `dtype.c` and none of `dtype.js`,
        # which is a disarm that disarmed half the lane.
        dis[r] = re.sub(r"(io_eff\(CID\(Dt\.[^;]*?)\s*,\s*", r"\1,", s)
        assert dis[r] != shipped[r], "%s: the disarm changed nothing, so it is not one" % r
    gone = {r: s[:s.index(TAILS[r])] for r, s in shipped.items()}
    return shipped, dis, gone

def main():
    shipped, dis, gone = arms()
    print("THE THREE ARMS, AS SOURCE TEXT:  %s"
          % ", ".join("%s %s" % (n, counts(a)) for n, a in
                      (("shipped", shipped), ("DISARM", dis), ("PLANT", gone))))
    print("  the counts are (dtype.c registrations, dtype.js registrations)")
    cfgs = [("none", [], None), ("bf16", ["bf16"], None), ("all", B.TEN, None),
            ("ctl-seam", ["bf16"], "bf16"), ("ctl-disarm", ["bf16"], "disarm")]
    print("THE THREE ARMS OVER THE FIVE CONFIGURATIONS.  `cc` is the BUILD; `bend -o`")
    print("only emits, and an emit that does not compile leaves the PREVIOUS artifact")
    print("behind -- so every artifact is unlinked first (agent-core.md).")
    for label, tree_src in (("shipped", shipped), ("DISARM whitespace-only", dis),
                            ("PLANT registrations deleted", gone)):
        print("\n-- %s --" % label)
        with tempfile.TemporaryDirectory() as td:
            base = pathlib.Path(td)
            for tag, names, seam in cfgs:
                tree, work = base / tag / "t", base / tag / "w"
                tree.mkdir(parents=True); work.mkdir(parents=True)
                shutil.copytree(B.REPO / "tinybendygrad", tree / "tinybendygrad")
                for rel, text in tree_src.items():
                    (tree / rel).write_text(text)
                if seam == "disarm":
                    c = tree / B.C_LANE
                    s = c.read_text()
                    if s.count("#ifdef CID(Dt.bf16)") == 1:
                        c.write_text(s.replace("#ifdef CID(Dt.bf16)", "#ifdef CID(Dt.i64_cmod)"))
                r = run_one(tree, work, tag, names, seam)
                print("  %-12s bendC=%d bendJS=%d cc=%s  exe=%s  node=%s"
                      % (tag, r["bend_c"], r["bend_js"], r["cc"],
                         r["exe"][:2] if r["exe"] else None,
                         (r["node"][0], r["node"][1][:40]) if r["node"] else None))
                for who in ("exe", "node"):
                    if r[who] and r[who][0] != 0:
                        print("      %s: %s" % (who, r[who][2].replace("\n", " ")[:130]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
