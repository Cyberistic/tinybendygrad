#!/usr/bin/env python3
"""separation.py -- do (a) ALLOWLIST and (b) RATIO separate the six from legitimate history?

A MEASUREMENT. It reads `survey.rows`'s inputs and asks ONE question per rule:

  (a) ALLOWLIST  -- how many DELETIONS does a commit carry that its message does not name?
                    The rule needs no threshold; the number IS the refusal.
  (b) RATIO      -- how many paths outside the subject, and what fraction of the diff?

The six incidents are the POSITIVE class. Everything else since the cut is the NEGATIVE
class, and a rule that fires on the negative class is a policy, not a guard.

    .venv/bin/python .agents/slop/diffrule/separation.py [--since=2026-10-06T00:00]

Writes `separation.rows`: one row per commit, then the per-rule verdict count over the
WHOLE population, with the population stated on every number.
"""
import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

_spec = importlib.util.spec_from_file_location("msgdiff_gate", ROOT / "gates" / "msgdiff-gate.py")
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)
PATH = _g.PATH

# THE SIX, by sha where the ledger named one. The three "(armed)" rows of the ledger are
# INDEX STATES, not commits -- they were reported before they fired -- so they are absent
# here and that absence is itself a finding.
SIX = {"9144d179e25a", "c83f04ad1c12", "75ab9b8f8984"}


def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"separation: git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def entries(sha):
    """(status, path-the-commit-ENDS-with, path-the-commit-REMOVES).

    The third element exists because `c83f04ad1c12`'s 46 reverted renames read as `R100` under
    `-M` and therefore as NO deletion at all -- which is exactly why they were "invisible in a
    diffstat". A rename REMOVES its source path; counting only `D` misses the whole class.
    """
    out = []
    for line in git("diff-tree", "-r", "-M", "--no-commit-id", "--name-status", sha).splitlines():
        p = line.split("\t")
        if len(p) < 2:
            continue
        st = p[0]
        if st.startswith("R") and len(p) >= 3:
            out.append((st, p[2], p[1]))    # (R100, new, old) -- old is what ceased to exist
        else:
            out.append((st, p[1], p[1]))    # (D, gone, gone) -- the path itself is removed
    return out


def named_paths(msg):
    return set(PATH.findall(msg))


def measure(sha, msg):
    """(outside, outside_removed, outside_added, total).

    `outside_removed` counts `D` PLUS every rename SOURCE. MEASURED, and it is not a detail:
    `c83f04ad1c12`'s 46 reverted renames are `R100` under `-M`, so a rule that counts `D` alone
    sees 20 removals on that commit and misses all 46.

    The `named` test is the gate's OWN PATH grammar against the exact path or any parent
    directory it ends with -- the generous reading, because the strict one refuses a message
    that says `gates` for editing three files in it."""
    toks = named_paths(msg)
    parents = set()
    for t in toks:
        parts = t.split("/")
        for i in range(1, len(parts)):
            parents.add("/".join(parts[:i]))

    def named(p):
        return p in toks or any(p.startswith(pre + "/") for pre in parents)

    es = entries(sha)
    # REMOVALS use the removal path; ADDITIONS/MODIFICATIONS use the path that survives.
    out_removed = [(st, gone) for st, _end, gone in es if gone is not None and not named(gone)]
    out_added = [(st, end) for st, end, _gone in es
                 if not st.startswith("D") and not st.startswith("R") and not named(end)]
    total = len({end for _st, end, _g in es if _g is not None} | {g for _s, _e, g in es if g})
    return (len(out_removed) + len(out_added), len(out_removed), len(out_added), total)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-06T00:00")
    a = ap.parse_args()
    shas = git("log", "--format=%H", f"--since={a.since}").split()

    rows = ["sha\ttotal\toutside\toutside_R\toutside_A\tin-the-six\tverdict-a\tverdict-b@8"]
    recs = []
    for sha in shas:
        msg = git("log", "-1", "--format=%B", sha)
        out, outd, outa, total = measure(sha, msg)
        # (a) ALLOWLIST: any REMOVAL outside the subject is unacknowledged. NO THRESHOLD.
        va = "REFUSED" if outd else "PASS"
        # (b) RATIO at N=8 outside paths, the largest count 99 of 300 commits still clear.
        vb = "REFUSED" if out >= 8 else "PASS"
        recs.append((sha, out, outd, outa, total, va, vb))
        rows.append("\t".join([sha[:12], str(total), str(out), str(outd), str(outa),
                               "yes" if sha[:12] in SIX else "-", va, vb]))

    (HERE / "separation.rows").write_text("\n".join(rows) + "\n")
    n = len(recs)
    print(f"population: {n} commits, git log --since={a.since}, HEAD (every commit, no filter)")
    print()
    print("THE SIX, measured:")
    for sha, out, outd, outa, total, va, vb in recs:
        if sha[:12] in SIX:
            print(f"  {sha[:12]}  total={total:4d} outside={out:4d} outside_R={outd:3d}  "
                  f"(a)={va:8s} (b)={vb}")
    print()
    fa = sum(1 for r in recs if r[5] == "REFUSED")
    fb = sum(1 for r in recs if r[6] == "REFUSED")
    fa_pos = sum(1 for r in recs if r[5] == "REFUSED" and r[0][:12] in SIX)
    fb_pos = sum(1 for r in recs if r[6] == "REFUSED" and r[0][:12] in SIX)
    print(f"(a) ALLOWLIST  fires on {fa} of {n} commits since {a.since}; "
          f"{fa_pos} of {len(SIX & {r[0][:12] for r in recs}) } named incidents")
    print(f"(b) RATIO@8    fires on {fb} of {n} commits since {a.since}; "
          f"{fb_pos} of {len(SIX & {r[0][:12] for r in recs}) } named incidents")
    print()
    print("every (a) or (b) firing, with the subject it fired on:")
    for sha, out, outd, outa, total, va, vb in recs:
        if va == "REFUSED" or vb == "REFUSED":
            subj = git("log", "-1", "--format=%s", sha)[:70]
            print(f"  {sha[:12]} outside={out:4d} outside_R={outd:3d} a={va:8s} b={vb:8s} {subj}")
    return 0


if __name__ == "__main__":
    sys.exit(main())