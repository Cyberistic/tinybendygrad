#!/usr/bin/env python3
"""msgdiff2 C3 -- is the INVERSION LANE PROVEN, or merely un-fired?

The parent asked about ONE case: a message saying "restored" whose diff DELETES. The strict lane
found no such commit in the last 250 commits of history. That is not yet a finding, because a
lane that cannot fire and a lane that was never exercised look identical. So this probes WIDER
and with TWO strengths, and reports both:

  C3-strict  the message's restore/add verb GOVERNS the removed path (verb-adjacent, within 40
             chars, gap-filtered -- the same rule the gate uses for delete verbs). Zero hits over
             N commits is a real measurement: the shape does not occur in this history under the
             rule that makes it checkable.
  C3-weak    the message carries a restore/add verb ANYWHERE and separately NAMES a path the
             diff removes. Strictly more permissive, so it can only find more; it is the probe
             that answers "does this shape exist at all", and a hit here is NOT yet a false claim
             -- it is a commit to read by hand.

A hit on EITHER is reported with its commit and its clause. NO hit on either is reported as
UNPROVEN, never as "the lane works".
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import classify  # noqa: E402

WINDOW = int(sys.argv[1]) if len(sys.argv) > 1 else 600


def main():
    shas = classify.git("rev-list", "--max-count", str(WINDOW), "HEAD").split()
    strict, weak, verb_any = [], [], 0
    for sha in shas:
        msg = classify.git("log", "-1", "--format=%B", sha)
        if not classify.INVERSE.search(msg):
            continue
        verb_any += 1
        inv = [t for t, _c, k in classify.inverse_claims(msg) if k == "claim" and t]
        if not inv:
            continue
        _p, _d, removed, _ch = classify.commit_view(sha, False)
        hits = sorted({p for t in inv for p in removed
                       if p == t or p.endswith("/" + t) or classify._covered(p, (t,))})
        if hits:
            strict.append((sha, hits))
        names, parents = classify._message_names(msg)
        decl = names | parents | set(classify.GLOB_RE.findall(msg)) | set(classify.DIR_RE.findall(msg))
        w = sorted(p for p in removed if any(classify._covered(p, (d,)) for d in decl))
        if w:
            weak.append((sha, w))
    with (HERE / "c3.rows").open("w") as fh:
        fh.write("strength\tsha\tremoved_paths\tsubject\n")
        for sha, paths in strict:
            fh.write(f"strict\t{sha[:12]}\t{','.join(paths[:4])}\t"
                     f"{classify.git('log', '-1', '--format=%s', sha)[:100]}\n")
        for sha, paths in weak:
            if any(s == sha for s, _ in strict):
                continue
            fh.write(f"weak\t{sha[:12]}\t{','.join(paths[:4])}\t"
                     f"{classify.git('log', '-1', '--format=%s', sha)[:100]}\n")
    print(f"window={len(shas)} commits; messages carrying a restore/add verb: {verb_any}")
    print(f"C3-strict hits: {len(strict)}")
    for sha, paths in strict:
        print(f"  {sha[:12]} {paths[:3]} :: {classify.git('log', '-1', '--format=%s', sha)[:90]}")
    print(f"C3-weak hits (excluding strict): {len([w for w in weak if w[0] not in {s for s, _ in strict}])}")
    for sha, paths in weak:
        if any(s == sha for s, _ in strict):
            continue
        print(f"  {sha[:12]} {paths[:3]} :: {classify.git('log', '-1', '--format=%s', sha)[:90]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())