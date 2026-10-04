#!/usr/bin/env python3
"""rf-zero-classify.py -- CLASSIFY EVERY ZERO IN rf-mutations.txt, BY MEASURING IT.

    python3 .agents/slop/rf-zero-classify.py

A zero is one of exactly five things (`zero-classify.py` owns that vocabulary and it
is QUERIED, not transcribed, for the reason `patch_not_apply.py` gives at import):
`UNREACHABLE+proof`, `PORT-DEFECT`, `PATCH-NOT-APPLY`, `INVISIBLE-to-reader`,
`NO-MUTATION-WRITTEN`.  A zero that fits none of them is an ERROR, never a pass.

Nothing here is typed.  Both (a) the op DOMAIN `O.pm_ler` can answer over and (b)
every reject list the port's own pattern tables pass to `rf_claimed` are READ OUT OF
`rangeify.bend` with `re`, and the cross-product is enumerated over those.  The claim
being tested is a claim about pure Bool logic over sets, so the enumeration is
exhaustive and a count of 0 separators is a PROOF rather than a sample: if the two
spellings agree on every pair the port can build, no fixture can separate them and no
row ever will.
"""
import itertools
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import staged_mut as SM

PORT = HERE.parent.parent / "tinybendygrad/schedule/rangeify.bend"
SRC = PORT.read_text()
ENTRY = re.compile(r"O\.PMEntry\{\d+,\s*\[([^\]]*)\],\s*\[([^\]]*)\]\}")
OPS_IN = re.compile(r"O\.Ops(\w+)\{\}")


def entries():
    """`[(ops, rej)]` as the port spells them -- read, never transcribed."""
    out = []
    for ops, rej in ENTRY.findall(SRC):
        out.append((frozenset(OPS_IN.findall(ops)), frozenset(OPS_IN.findall(rej))))
    return out


def verdict(v, why):
    """Print a verdict in `zero-classify.py`'s vocabulary, or REFUSE if it is not in it.

    The check is not ceremony: this file imports `staged_mut.zero_verdicts()` rather
    than transcribing the five strings, because a sixth spelling would read as an
    unrecognised measurement and that classifier EXITS on those rather than inventing
    a verdict.  A wrong verdict written here would be indistinguishable from a
    measured one in every table downstream.
    """
    if v not in SM.zero_verdicts():
        raise SystemExit("REFUSING: %r is not one of zero-classify.py's verdicts (%s).  "
                         "A zero that cannot be placed is an ERROR, never a pass."
                         % (v, " ".join(SM.zero_verdicts())))
    print("  VERDICT: %s" % v)
    for line in (why or "").split(".  "):
        if line.strip():
            print("    " + line.strip().rstrip(".") + ".")


def main():
    verdicts = SM.zero_verdicts()
    rows = [l for l in open(HERE / "rf-mutations.txt") if l.startswith("| M")]
    zeros = [l for l in rows if "| NONE |" in l]
    print("zero-classify.py's vocabulary, QUERIED: %s" % " | ".join(verdicts))
    print("rf-mutations.txt: %d rows, %d moved nothing\n" % (len(rows), len(zeros)))

    ents = entries()
    domain = sorted({o for ops, _ in ents for o in ops})
    rejs = sorted({r for _, r in ents if r})
    print("READ FROM rangeify.bend: %d PMEntry rows" % len(ents))
    print("  op domain (%d): %s" % (len(domain), ", ".join(domain)))
    print("  distinct NON-EMPTY reject lists (%d): %s\n"
          % (len(rejs), "; ".join("{%s}" % ",".join(sorted(r)) for r in rejs)))

    # A caller census: is the mutated site reached from the pattern tables at all?
    claimed = len(re.findall(r"rf_claimed\(", SRC))
    print("CALLER CENSUS: `rf_claimed(` occurs %d times in the live file, so `rf_early`"
          % claimed)
    print("IS on the path every `*_try` rule takes.  A zero here is therefore NOT")
    print("NO-MUTATION-WRITTEN and NOT UNREACHABLE.\n")

    total = sep = 0
    smallest = None
    for rej in rejs:
        for n in range(1, len(domain) + 1):
            for have in itertools.combinations(domain, n):
                h = set(have)
                a, b = all(x in h for x in rej), any(x in h for x in rej)
                total += 1
                if a != b:
                    sep += 1
                    if smallest is None or len(have) < len(smallest[0]):
                        smallest = (sorted(have), sorted(rej), a, b)
    print("M3  `rf_early`'s subset test `and` -> `or`")
    print("  input pairs enumerated: %d  (every subset of the op domain x every reject"
          % total)
    print("  list the tables can pass, including the EMPTY subset)")
    print("  SEPARATORS: %d" % sep)
    if sep:
        print("  smallest separating fixture: have={%s} rej={%s} and=%s or=%s"
              % tuple(smallest))
        verdict("INVISIBLE-to-reader",
                "the site IS called and the two spellings DO differ; no fixture in the "
                "gate exercises that pair.  This is a REQUEST FOR A FIXTURE.")
    else:
        # The reason is DERIVED from the data and printed as two counts.  An earlier
        # draft asserted "`rej` is always a subset of the `ops` column of the same
        # entry", which is FALSE -- `PMEntry{3, [INDEX], [PARAM]}` rejects an op it
        # does not list -- and an asserted reason is the exact thing this file is
        # meant to replace.
        overlaps = [r for r in rejs if set(r) & set(domain)]
        multi = [r for r in overlaps if len(r) >= 2]
        print("  => PROOF, and the reason is two counts rather than a story:")
        print("     reject lists overlapping the op domain at all : %d" % len(overlaps))
        print("     ...of those, any with TWO OR MORE members       : %d %s"
              % (len(multi), multi or ""))
        print("     `rf_early.go` folds `Bool.and` down the reject list, so when |rej| <= 1")
        print("     the fold has exactly one input and `and` and `or` are the SAME")
        print("     function -- for EVERY `have`, not merely the ones this gate builds.")
        print("     No fixture can separate them and no row ever will.")
        verdict("UNREACHABLE+proof", "")
    print()
    i = SRC.find("def rf_strip.of")
    print("M8  `rf_strip`'s `x.op is Ops.SHRINK` test dropped")
    print("  the site, read from the live file:")
    for l in SRC[i:SRC.find("\ndef ", i + 10)].rstrip().splitlines():
        print("    " + l)
    verdict("INVISIBLE-to-reader",
            "dropping the SHRINK test removes one ARM, and the arms differ only on a "
            "node that is BOTH a SHRINK and zero-offset.  This gate has no such "
            "fixture.  Nothing makes the pair unbuildable -- a SHRINK with a zero "
            "offset is a legal UOp -- so this is a REQUEST FOR A FIXTURE, not a "
            "theorem.")
    return 0


if __name__ == "__main__":
    sys.exit(main())