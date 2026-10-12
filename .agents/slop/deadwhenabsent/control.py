"""THE CONTROL, DRIVEN: absent / present-empty / stale / present-fresh, through the REAL gate.

Four real directories under a TemporaryDirectory, `runs/graphcmp/` never touched. Each gate is
imported by path and its reader is exercised with `root` pointed at the planted tree -- which is
why `require()` takes `root` as a parameter: `checks/substrate-id.py:138` already makes that
argument for exactly this reason ("`root` IS A PARAMETER AND NOT THE MODULE GLOBAL, AND THAT IS NOT
TIDINESS").

    usage: .venv/bin/python .agents/slop/deadwhenabsent/control.py
"""
import importlib.util, os, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
FAIL = []
LIMIT = 24 * 3600


def plant_states(td, now):
    """Four REAL directories. Nothing asserts a branch; the gate reads the tree and we read back
    its exit."""
    out = {}
    out["absent"] = os.path.join(td, "absent")                       # never created
    empty = os.path.join(td, "empty"); os.makedirs(os.path.join(empty, "runs/graphcmp/D"))
    out["empty"] = empty
    stale = os.path.join(td, "stale"); os.makedirs(os.path.join(stale, "runs/graphcmp/D"))
    q = os.path.join(stale, "runs/graphcmp/D/D0-run-summary.txt"); open(q, "w").write("graphs=25\n")
    os.utime(q, (now - 10 * 86400, now - 10 * 86400)); out["stale"] = stale
    fresh = os.path.join(td, "fresh"); os.makedirs(os.path.join(fresh, "runs/graphcmp/D"))
    p = os.path.join(fresh, "runs/graphcmp/D/D0-run-summary.txt"); open(p, "w").write("graphs=34\n")
    os.utime(p, (now, now)); out["fresh"] = fresh
    return out


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name.replace("/", "_"), os.path.join(ROOT, rel))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def check(label, want_code, want_token, got_code, got_token):
    ok = got_code == want_code and got_token == want_token
    FAIL.append(label) if not ok else None
    print(f"  {'OK  ' if ok else 'FAIL'} {label:<34} exit={got_code} want={want_code}  {got_token}")


def main():
    ra = load("ra", "checks/runs-artifacts.py")
    print(f"limits: MAX_AGE_S={ra.MAX_AGE_S}  (a THRESHOLD, named so raising it is a visible edit)")
    print("\nBRANCH 1-4: the helper's four states, on four real directories")
    now = 1_000_000.0
    with tempfile.TemporaryDirectory() as td:
        st = plant_states(td, now)
        for name, code, tok in (("absent", ra.REFUSED, "ARTIFACTS-ABSENT"),
                                ("empty", ra.DEAD, "ARTIFACTS-EMPTY"),
                                ("stale", ra.REFUSED, "ARTIFACTS-STALE"),
                                ("fresh", ra.PASS, "ARTIFACTS-FRESH")):
            c, t, _ = ra.state(root=st[name], max_age_s=ra.MAX_AGE_S, now=now)
            check(name, code, tok, c, t)
        toks = {ra.state(root=st[n], max_age_s=ra.MAX_AGE_S, now=now)[1] for n in st}
        print(f"\n  {'OK  ' if len(toks)==4 else 'FAIL'} distinct tokens: {len(toks)}/4 "
              f"{sorted(toks)}")
        if len(toks) != 4:
            FAIL.append("tokens collapsed")
        # THE SPECIFIC TRAP: stale must NOT be absent, and absent must NOT be empty.
        a = ra.state(root=st["absent"], now=now)[1]
        s = ra.state(root=st["stale"], now=now)[1]
        e = ra.state(root=st["empty"], now=now)[1]
        for collapsed, msg in ((a == s, "stale and absent are DISTINGUISHED"),
                               (a == e, "absent and empty are DISTINGUISHED"),
                               (s == e, "stale and empty are DISTINGUISHED")):
            print(f"  {'FAIL' if collapsed else 'OK  '} {msg}")
            if collapsed:
                FAIL.append(msg)

    print("\nBRANCH 5: max_age_s=None DISABLES staleness and nothing else")
    with tempfile.TemporaryDirectory() as td:
        st = plant_states(td, now)
        c, t, d = ra.state(root=st["stale"], max_age_s=None, now=now)
        check("stale, no limit", ra.PASS, "ARTIFACTS-FRESH", c, t)
        print(f"        ({d})")

    print("\nBRANCH 6: THE LIVE TREE. `runs/graphcmp/D` is PRESENT and STALE, so the honest answer")
    print("is STALE, NOT ABSENT and NOT EMPTY -- the three-way distinction the brief asks for.")
    c, t, d = ra.state()
    check("live runs/graphcmp/D", ra.REFUSED, "ARTIFACTS-STALE", c, t)
    print(f"        ({d})")

    print("\nBRANCH 7: sweep.py's NEW `GENERATED` BUCKET, on real paths, no filesystem writes")
    if "--slow" not in sys.argv:
        # `verdict_for` calls `facts()` at its first line, and `facts()` builds the citation corpus
        # -- MEASURED, `checks/sweep.py --plan` does not finish inside 300 s on this tree, which is
        # why it is behind a flag rather than silently making this control slow. `generated_read_dirs()`
        # alone is 3.8 s and that is the part this unit added.
        print("        SKIPPED without --slow (facts() costs >300 s here; see the report)")
        return 0 if not FAIL else 1
    sw = load("sw", "checks/sweep.py")
    gen = sw.generated_read_dirs()
    print(f"        derived {len(gen)} unrecoverable read dirs: {sorted(gen)}")
    t0 = time.time()
    f = sw.facts()
    print(f"        facts() took {time.time() - t0:.0f}s")
    for rel, want in (("runs/graphcmp/D/D0-run-summary.txt", "GENERATED"),
                      ("runs/graphcmp/D/D1-cases/x.rows", "GENERATED"),
                      ("runs/other/x.rows", "GENERATED"),
                      (".agents/slop/spine/art-a/f.txt", None),
                      (".agents/slop/REPORT.md", "DOC")):
        got = sw.verdict_for(rel, set(), f)
        ok = (got == want) if want else (got != "GENERATED")
        print(f"  {'OK  ' if ok else 'FAIL'} verdict_for({rel:<40}) -> {got}")
        FAIL.append(rel) if not ok else None

    print(f"\n--control: {'all branches OK' if not FAIL else 'FAILED: ' + '; '.join(FAIL)}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
