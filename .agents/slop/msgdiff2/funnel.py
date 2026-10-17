#!/usr/bin/env python3
"""msgdiff2 funnel -- how many of the 55 commits can this instrument see AT ALL, and why.

The prior unit reported "28/49 messages contain a deletion word; only 2 have actually-deleted
paths; 26 changed >=1 file but deleted NOTHING". That is a measurement of MESSAGES CONTAINING A
WORD, which is not the population of a message-vs-diff gate and not a verdict. The numbers below
are the successive populations a claim has to survive, so the 28 becomes a denominator with stages
rather than a conclusion:

    STAGE 1  message contains a delete VERB          -- `VERB` matched at all
    STAGE 2  that verb is not negated and not a meta-report
    STAGE 3  the verb GOVERNS a path (forward, 40 chars, gap-filtered)
    STAGE 4  the path resolves in this commit's diff or tree
    STAGE 5  the claim is WITNESSED or CONTRADICTED

Each stage is a strict subset of the one above, and the last line is the instrument's real
denominator. Printed as rows so the funnel is an artifact and not a sentence.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import classify  # noqa: E402


def main():
    shas = [s.strip() for s in (HERE / ".range-snapshot.rows").read_text().split() if s.strip()]
    s1 = s2 = s3 = s4 = s5 = 0
    with (HERE / "funnel.rows").open("w") as fh:
        fh.write("stage\tcount\tdenominator\tdefinition\n")
        rows = [
            ("1-verb-present", 0, len(shas),
             "message contains a delete verb (VERB matched somewhere)"),
            ("2-not-negated-not-meta", 0, len(shas),
             "NEGATION in the 48 chars before it, or META in its clause, did not demote it"),
            ("3-governs-a-path", 0, len(shas),
             "_nearest_path found a PATH within 40 chars and no GAP_STOP between"),
            ("4-path-resolves", 0, len(shas),
             "the token matches a path in this commit's diff D-set or in its tree"),
            ("5-witnessed-or-contradicted", 0, len(shas),
             "the claim was graded; this is the instrument's real denominator"),
        ]
        for sha in shas:
            msg = classify.git("log", "-1", "--format=%B", sha)
            claims = classify.deletion_claims(msg)
            if not claims:
                continue
            s1 += 1
            live = [c for c in claims if c[2] == "claim"]
            if not live:
                continue
            s2 += 1
            tokened = [c for c in live if c[0]]
            if not tokened:
                continue
            s3 += 1
            present, deleted, _r, _c = classify.commit_view(sha, True)
            resolvable = [c for c in tokened
                          if any(p == c[0] or p.endswith("/" + c[0]) for p in (present | deleted))]
            if not resolvable:
                continue
            s4 += 1
            s5 += 1
        counts = [s1, s2, s3, s4, s5]
        for (name, _c, den, definition), n in zip(rows, counts):
            fh.write(f"{name}\t{n}\t{den}\t{definition}\n")
            print(f"{name}: {n} of {den}")
    return 0


if __name__ == "__main__":
    sys.exit(main())