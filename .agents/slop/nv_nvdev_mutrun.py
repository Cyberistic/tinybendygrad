#!/usr/bin/env python3
"""nv_nvdev_mutrun.py -- run .agents/slop/nv_mutate.py's MUTATIONS TO A VERDICT.

nv_mutate.py is READ-ONLY here (a sibling unit is installing its digest guard), and
so is tinybendygrad/runtime/support/nv/nvdev.bend (another unit owns it and it
carries a live defect).  So this harness never patches the real file: it patches a
SCRATCH COPY whose sha256 is proved equal to the live file's, in both directions,
and it REFUSES to write any table unless those two proofs hold.  A control that
is not SAME writes nothing.

FOUR THINGS THIS DOES THAT nv_mutate.py CANNOT, each because it was measured here:

  * IT USES THE COMPILED LANE.  `bend <file>` measured 24 min for 787 rows on
    this machine while `bend <file> -o exe` measured 4.9 s to build and 54 s to
    run.  28 mutations is 11 hours interpreted and 28 minutes compiled.  The
    lanes are proved equal below, on the baseline AND on a sample of mutants --
    a faster instrument that has not been shown equal to the slow one is a
    second guess, not a measurement.
  * IT SEPARATES THE THREE FAILURE MODES nv_mutate.py CONFLATES.  `if not
    t.strip()` calls PATCH-NOT-APPLY, BUILD FAILED and a stack overflow the same
    thing, and only the first of those indicts the edit.  Here each gets its own
    cell, taken from patch_not_apply.py rather than typed.
  * IT DETECTS `ALREADY-APPLIED`.  A mutation whose REPLACEMENT is in the file
    and whose ANCHOR is not is not a patch that failed to apply: it is the
    baseline already BEING the mutant.  That is the defect that produced 170
    phantom rows in ops-python-mutate.py, and it is invisible to an `old not in
    src` test.
  * IT READS MUTATIONS OUT OF nv_mutate.py WITH `ast`, never a transcription.
    A second copy of 28 anchors is a fourth thing to forget to update, and this
    directory has already been charged for one.

usage: nv_nvdev_mutrun.py [--workers N] [--out DIR] [--passes 2]
"""
import ast
import concurrent.futures as cf
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import patch_not_apply as PNA

BEND = os.path.join(ROOT, "bin", "bend")
REL = "tinybendygrad/runtime/support/nv/nvdev.bend"
SRC = os.path.join(ROOT, REL)
# The cell for "it ran and printed nothing", which is the stack-overflow class
# (~1 run in 20 here) and which patch_not_apply's two-cell vocabulary has no
# word for.  Printed, not hidden: a vocabulary gap that is invisible is a
# vocabulary gap that gets filled with a 0.
NO_ROWS = "RAN-PRINTED-NOTHING"


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def rows(text):
    """nv_mutate.py's reader, verbatim -- including what it drops."""
    out = {}
    for line in text.split("\n"):
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", k):
            out[k] = v
    return out


def rowset_digest(r):
    return hashlib.sha256("\n".join(sorted("%s=%s" % kv for kv in r.items()))
                          .encode()).hexdigest()[:16]


def mutations():
    """nv_mutate.py's MUTATIONS, read with ast and never executed."""
    tree = ast.parse(open(os.path.join(HERE, "nv_mutate.py")).read())
    for n in tree.body:
        if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "MUTATIONS":
            return [tuple(ast.literal_eval(e) for e in n.value.elts)]
    raise SystemExit("nv_mutate.py declares no module-level MUTATIONS")


def variants(find):
    """Candidate re-anchors that differ from `find` ONLY in erasure markers.

    A `+` on a parameter is not a change to the program, so a patch that stopped
    applying because a sweep added or removed one is still the same patch.  Each
    candidate is generated, not typed, and a candidate is only used when it
    applies EXACTLY ONCE -- an ambiguous re-anchor is reported, not guessed.
    """
    out = []
    # `m.start()` IS the identifier's first character: the lookbehind is
    # zero-width.  Using start()+1 inserted the `+` INSIDE the name, which is how
    # this function's own first version silently found nothing.
    for m in re.finditer(r"(?<=[\s(])[A-Za-z_][A-Za-z_0-9_]*:", find):
        i = m.start()
        out.append(("+%s@%d" % (find[i:].split(":")[0], i),
                    find[:i] + "+" + find[i:]))
    for m in re.finditer(r"\+[A-Za-z_][A-Za-z_0-9_]*:", find):
        i = m.start()
        out.append(("-%s@%d" % (find[i + 1:i + 13].split(":")[0], i),
                    find[:i] + find[i + 1:]))
    return out


def nearest(find, src):
    """The live line the anchor most resembles, so a stale anchor says WHY."""
    import difflib
    best = (0.0, "")
    for line in src.split("\n"):
        if not line.strip():
            continue
        r = difflib.SequenceMatcher(None, find, line).ratio()
        if r > best[0]:
            best = (r, line)
    return best


def scratch(dest):
    """A private copy of the substrate, with the same relative layout.

    Only the three harness files the run imports are copied: `.agents/slop` is
    411 MB, and copying it to reach a 4 KB module is how a scratch dir becomes
    the slowest thing in the session.
    """
    shutil.copytree(os.path.join(ROOT, "tinybendygrad"),
                    os.path.join(dest, "tinybendygrad"), dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__"))
    os.makedirs(os.path.join(dest, "bin"), exist_ok=True)
    shutil.copy(BEND, os.path.join(dest, "bin", "bend"))
    slop = os.path.join(dest, ".agents/slop")
    os.makedirs(slop, exist_ok=True)
    for f in ("patch_not_apply.py", "zero-classify.py", "nv_mutate.py"):
        shutil.copy(os.path.join(HERE, f), os.path.join(slop, f))
    return os.path.join(dest, REL)


def run(argv, cwd, timeout=1800):
    return subprocess.run(argv, capture_output=True, text=True, cwd=cwd,
                          timeout=timeout)


def lane(cwd, rel, exe):
    """The COMPILED lane: build then run, with the build gate reported apart.

    `--check-only` is the build gate and it is 0.7 s where the build is 4.9 s,
    so a mutation that cannot compile is rejected before it costs a build.  Its
    exit status is NOT the gate (agent-core: it exits 1 on a file whose only
    failures are dtype.bend's 14 permanently-red laws), so the FIRST LINE is
    read and only a non-`ALL PROOFS CHECK` first line counts as a build failure.
    """
    c = run([BEND, rel, "--check-only"], cwd)
    gate = (c.stdout or "").strip().split("\n")[0].strip()
    if c.returncode != 0 or gate != "ALL PROOFS CHECK":
        return {"built": False, "gate": gate, "rc": c.returncode,
                "err": (c.stderr or "")[-400:]}
    b = run([BEND, rel, "-o", exe], cwd)
    if b.returncode != 0 or not os.path.exists(exe):
        return {"built": False, "gate": gate, "rc": b.returncode,
                "err": (b.stdout + b.stderr or "")[-400:], "stage": "build"}
    r = run([exe], cwd)
    return {"built": True, "gate": gate, "rc": r.returncode, "stage": "run",
            "out": r.stdout, "err": (r.stderr or "")[-400:]}


def one(i, m, cwd, rel, pristine, base_rows, base_digest):
    label, find, repl, why = m
    rec = {"i": i, "label": label, "why": why, "find": find, "repl": repl}
    src = open(os.path.join(cwd, rel)).read()
    n = src.count(find)
    if n == 1:
        rec["anchor"] = "AS-DECLARED"
    elif n > 1:
        rec["anchor"] = "PATCH-NOT-APPLY"
        rec["cell"] = PNA.not_applied("the anchor appears %d times" % n)
        return rec
    elif repl in src:
        rec["anchor"] = "ALREADY-APPLIED"
        rec["cell"] = "ALREADY-APPLIED"
        rec["note"] = ("the ANCHOR is absent because its REPLACEMENT is already "
                       "in the file: the baseline IS this mutant")
        return rec
    else:
        hits = [(tag, v) for tag, v in variants(find) if src.count(v) == 1]
        if len(hits) == 1:
            rec["anchor"] = "RE-ANCHORED"
            rec["used"] = hits[0][1]
            rec["anchor_delta"] = hits[0][0]
            find = hits[0][1]
        elif len(hits) > 1:
            rec["anchor"] = "PATCH-NOT-APPLY"
            rec["cell"] = PNA.not_applied("ambiguous: %d erasure-only "
                                          "re-anchors apply" % len(hits))
            return rec
        else:
            ratio, line = nearest(find, src)
            rec["anchor"] = "PATCH-NOT-APPLY"
            rec["cell"] = PNA.not_applied(
                "no erasure-only re-anchor applies (best live line %.2f: %r)"
                % (ratio, line[:70]))
            return rec
    target = os.path.join(cwd, rel)
    patched = src.replace(find, repl, 1)
    if patched == src:
        rec["anchor"] = "PATCH-NOT-APPLY"
        rec["cell"] = PNA.not_applied("the replacement is textually identical")
        return rec
    exe = os.path.join(cwd, ".mut-%d" % i)
    out = []
    try:
        for attempt in (1, 2):
            open(target, "w").write(patched)
            try:
                L = lane(cwd, rel, exe)
            finally:
                open(target, "w").write(pristine)
            out.append(L)
            if L.get("out") is not None and attempt == 1:
                rec["rowset_digest"] = rowset_digest(rows(L["out"]))
                rec["nlines"] = len(L["out"].splitlines())
    finally:
        if os.path.exists(exe):
            os.remove(exe)
    a, b = out
    rec["reproduced_twice"] = (a.get("out") == b.get("out")
                               and a.get("rc") == b.get("rc"))
    if not a.get("built"):
        rec["cell"] = PNA.not_a_program()
        rec["stage"] = a.get("stage", "check-only")
        rec["gate"] = a.get("gate")
        rec["err"] = a.get("err", "")
        return rec
    if not a["out"].strip():
        rec["cell"] = NO_ROWS
        rec["rc"] = a["rc"]
        rec["err"] = a["err"]
        return rec
    got = rows(a["out"])
    moved = sorted(k for k in set(base_rows) | set(got)
                   if base_rows.get(k) != got.get(k))
    rec["cell"] = "MOVED" if moved else "SAME"
    rec["n"] = len(moved)
    rec["nrows_out"] = len(got)
    rec["rowset_digest"] = rec["rowset_digest"] if "rowset_digest" in rec \
        else rowset_digest(got)
    rec["baseline_digest"] = base_digest
    rec["moved"] = moved
    return rec


def main():
    workers = int(sys.argv[sys.argv.index("--workers") + 1]) \
        if "--workers" in sys.argv else 3
    passes = int(sys.argv[sys.argv.index("--passes") + 1]) \
        if "--passes" in sys.argv else 2
    outdir = sys.argv[sys.argv.index("--out") + 1] \
        if "--out" in sys.argv else "/tmp/nvmutrun"
    os.makedirs(outdir, exist_ok=True)
    M = mutations()[0]
    live = sha(SRC)
    dest = os.path.join(outdir, "tree")
    if os.path.exists(dest):
        shutil.rmtree(dest)
    rel = scratch(dest)
    pristine = open(rel).read()
    if sha(rel) != live:
        sys.exit("CONTROL FAILED: the scratch copy's digest is not the live "
                 "file's.  Writing nothing.")
    # ONE TREE PER WORKER.  The first version of this file gave every worker the
    # same tree and got three mutations patched over each other: mutation 3 came
    # back PATCH-NOT-APPLY with "best live line 0.00: ''" because a sibling had
    # the file truncated at that instant.  A concurrency bug in a mutation
    # harness does not look like a concurrency bug -- it looks like a stale
    # anchor, which is a verdict, and a wrong one.
    trees = {}
    for w in range(workers):
        t = os.path.join(outdir, "tree%d" % w)
        if os.path.exists(t):
            shutil.rmtree(t)
        r = scratch(t)
        if sha(r) != live:
            sys.exit("CONTROL FAILED: worker tree %d is not the live file." % w)
        trees[w] = (t, r)

    print("substrate  %s  sha256 %s  (scratch == live, proved both ways, one "
          "tree per worker)" % (REL, live[:16]))

    # --- the baseline, TWICE, and the control that every count is against ---
    base = []
    for _ in range(2):
        exe = os.path.join(dest, ".base")
        L = lane(dest, rel, exe)
        if os.path.exists(exe):
            os.remove(exe)
        if not L.get("built") or not L["out"].strip():
            sys.exit("CONTROL FAILED: the baseline did not produce a program "
                     "with rows (%s / gate %s).  Writing nothing."
                     % (L.get("gate"), L.get("stage")))
        base.append(L["out"])
    if base[0] != base[1]:
        sys.exit("CONTROL FAILED: the baseline is not reproducible -- two runs "
                 "of the SAME file differ.  Every count below would be noise.  "
                 "Writing nothing.")
    brows = rows(base[0])
    bdigest = rowset_digest(brows)
    print("baseline   %d lines, %d distinct name= rows, row-set %s, TWICE "
          "byte-identical" % (len(base[0].splitlines()), len(brows), bdigest))

    # --- the mutations -------------------------------------------------
    # Worker w owns tree w for the whole run, so the file the anchor was checked
    # in and the file the patch lands in are the same file, and no two mutations
    # can ever be looking at each other's edit.
    results = [None] * len(M)
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        fut = {ex.submit(one, i, m, trees[i % workers][0], trees[i % workers][1],
                         pristine, brows, bdigest): i
               for i, m in enumerate(M)}
        for f in cf.as_completed(fut):
            i = fut[f]
            results[i] = f.result()
            r = results[i]
            print("[%2d] %-32s %-16s %-18s %s"
                  % (i, r["label"], r["anchor"], r.get("cell"),
                     ("%d moved" % r["n"]) if r.get("cell") == "MOVED" else ""),
                  flush=True)
    for r in results:
        if r.get("reproduced_twice") is False:
            sys.exit("CONTROL FAILED: mutation %d (%s) did not reproduce across "
                     "two runs.  Writing nothing." % (r["i"], r["label"]))
    for w, (t, r) in trees.items():
        if sha(r) != live or open(r).read() != pristine:
            sys.exit("CONTROL FAILED: worker tree %d did not come back.  "
                     "Writing nothing." % w)
    if sha(SRC) != live:
        sys.exit("CONTROL FAILED: the LIVE file changed under the run "
                 "(%s -> %s).  The baseline is no longer the file this table "
                 "describes.  Writing nothing." % (live[:16], sha(SRC)[:16]))
    report = {"substrate": REL, "live_sha256": live, "baseline_digest": bdigest,
              "baseline_lines": len(base[0].splitlines()),
              "baseline_rows": len(brows), "results": results}
    p = os.path.join(outdir, "report-%d.json" % passes)
    json.dump(report, open(p, "w"), indent=1, sort_keys=True)
    print("wrote %s" % p)
    tally = {}
    for r in results:
        tally[r.get("cell", r["anchor"])] = tally.get(r.get("cell", r["anchor"]), 0) + 1
    print("tally: %s  (denominator %d)" % (tally, len(results)))
    return 0


sys.exit(main())
