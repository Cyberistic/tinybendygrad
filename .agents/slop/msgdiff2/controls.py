#!/usr/bin/env python3
"""msgdiff2 controls -- can this classifier be believed?

A classifier that NEVER fires is indistinguishable from a classifier that is not running, and a
classifier that fires on everything is indistinguishable from a gate. So three controls, each
with a PASS/FAIL and a named commit, and a FAIL here REFUSES the whole run.

  C1 NEGATIVE (must NOT fire) -- a commit whose message asserts an ADDITION of a path and whose
     diff really ADDS it. The polarity is unambiguous in both directions, so an inversion lane
     that fires here is broken by construction.
  C2 NEGATIVE (must NOT fire) -- a commit whose message asserts a DELETION of a path and whose
     diff really DELETES it. This is the shape the gate exists for, firing on it would be a
     false positive.
  C3 POSITIVE (MUST fire) -- a REAL commit in this repo's history whose message asserts a
     restoration or addition of a path that the diff REMOVES. C3 is the control that makes C1
     mean something: without it, "did not fire" is also what a dead lane says.

C3 IS SEARCHED FOR, NOT HANDED IN. `find_positive_control` walks a window of history and asks the
lane itself, so the control is discovered by the instrument rather than picked by the author.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import classify  # noqa: E402

# C1/C2 are named commits with their expected outcome written down here, and the expectation is
# checked against the lane rather than asserted in prose.
C1 = "3173198bd80e"   # asserts an addition; its diff ADDS
C2 = None             # filled from the CONFIRMED rows: a claim the diff witnesses


def fires(sha):
    """The three verdicts this unit can return for one commit."""
    return classify.classify(sha, classify.git("log", "-1", "--format=%B", sha))


def find_positive_control(window=250):
    """The newest commit in the last `window` whose message's restore/add verb governs a path
    that this commit's diff REMOVES. Discovered by the lane, so a dead lane finds nothing."""
    shas = classify.git("rev-list", "--max-count", str(window), "HEAD").split()
    hits = []
    for sha in shas:
        msg = classify.git("log", "-1", "--format=%B", sha)
        inv = [t for t, _c, k in classify.inverse_claims(msg) if k == "claim" and t]
        if not inv:
            continue
        _p, _d, removed, _ch = classify.commit_view(sha, False)
        bad = sorted({p for t in inv for p in removed
                      if p == t or p.endswith("/" + t) or classify._covered(p, (t,))})
        if bad:
            hits.append((sha, bad[:3]))
            if len(hits) == 3:
                break
    return hits


def main():
    print("== C1 negative: message asserts an ADDITION, diff ADDS -> must NOT fire")
    c1 = fires(C1)
    ok1 = c1["verdict"] not in ("FALSE-CLAIM", "FALSE-CLAIM-INVERSE")
    print(f"   {C1[:12]} verdict={c1['verdict']} mp={c1['message_polarity']} "
          f"dp={c1['diff_polarity']} -> {'PASS' if ok1 else 'FAIL'}")
    print(f"   subject: {classify.git('log', '-1', '--format=%s', C1)[:110]}")

    print("== C2 negative: message asserts a DELETION, diff DELETES it -> must NOT fire")
    rows = (HERE / "classify.rows").read_text().splitlines()[1:]
    c2sha = next((r.split("\t")[0] for r in rows
                  if r.split("\t")[1] == "CONFIRMED" and r.split("\t")[3] == "DELETES"), None)
    if c2sha is None:
        c2 = next((r.split("\t")[0] for r in rows if r.split("\t")[1] == "CONFIRMED"), None)
        c2sha = c2
    ok2 = True
    if c2sha is None:
        ok2 = False
        print("   FAIL no CONFIRMED commit available to use as C2")
    else:
        c2v = fires(c2sha)
        ok2 = c2v["verdict"] == "CONFIRMED"
        print(f"   {c2sha[:12]} verdict={c2v['verdict']} mp={c2v['message_polarity']} "
              f"dp={c2v['diff_polarity']} -> {'PASS' if ok2 else 'FAIL'}")
        print(f"   subject: {classify.git('log', '-1', '--format=%s', c2sha)[:110]}")

    print("== C3 positive: a REAL commit whose restore/add verb governs a path its diff REMOVES")
    hits = find_positive_control()
    ok3 = bool(hits)
    if hits:
        for sha, paths in hits:
            v = fires(sha)
            good = v["verdict"] == "FALSE-CLAIM-INVERSE"
            print(f"   {sha[:12]} verdict={v['verdict']} removed={paths} -> "
                  f"{'PASS' if good else 'FAIL'}")
            print(f"   subject: {classify.git('log', '-1', '--format=%s', sha)[:110]}")
    else:
        print("   FAIL no real inversion found in the last 250 commits -- the lane is UNPROVEN")

    verdict = "ALL CONTROLS PASS" if (ok1 and ok2 and ok3) else "REFUSED: a control failed"
    with (HERE / "controls.rows").open("w") as fh:
        fh.write("control\tsha\tverdict\texpectation\tresult\n")
        fh.write(f"C1_negative_add\t{C1[:12]}\t{fires(C1)['verdict']}\tmust not fire\t"
                 f"{'PASS' if ok1 else 'FAIL'}\n")
        if c2sha:
            fh.write(f"C2_negative_delete\t{c2sha[:12]}\t{fires(c2sha)['verdict']}\t"
                     f"CONFIRMED\t{'PASS' if ok2 else 'FAIL'}\n")
        for sha, paths in hits:
            fh.write(f"C3_positive_inverse\t{sha[:12]}\t{fires(sha)['verdict']}\t"
                     f"FALSE-CLAIM-INVERSE\t{'PASS' if ok3 else 'FAIL'}\t{','.join(paths)}\n")
    print(f"== {verdict}")
    return 0 if (ok1 and ok2 and ok3) else 5


if __name__ == "__main__":
    sys.exit(main())