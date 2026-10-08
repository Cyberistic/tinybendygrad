#!/usr/bin/env python3
"""porting.py -- DOES THE NEW RULE FIRE ON LEGITIMATE PORTING WORK?

The brief's hard constraint: "a `tn_*` unit adding `gates/tn_*.bend` + `tinybendygrad/*.bend`
is normal work". A rule that refused those would be a policy wearing a guard's name.

The test is run against the GATE ITSELF, not against a reimplementation of it, because a
calibration that measures a second copy of the rule measures nothing about the rule.

    .venv/bin/python .agents/slop/diffrule/porting.py [--since=...]

Two populations, both DISCOVERED:
  PORTING  -- commits whose subject line names a `tn_*` gate AND whose diff touches
              `gates/tn_*` or `tinybendygrad/`. That is the shape the brief names; it is a
              REGEX OVER COMMIT SUBJECTS AND DIFF PATHS, not a list of shas.
  ADDS-ONLY -- commits whose diff has NO `D` and no rename source at all. These are the
              commits a REMOVALS rule must be structurally unable to refuse.

Writes `porting.rows`.
"""
import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

_spec = importlib.util.spec_from_file_location("g", ROOT / "gates" / "msgdiff-gate.py")
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)


def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"porting: git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-06T12:00")
    a = ap.parse_args()
    shas = git("log", "--format=%H", f"--since={a.since}").split()

    rows = ["sha\tclass\tremovals\tunack\tsubject-verdict\tsubject"]
    n_port = n_addonly = n_ref_port = n_ref_add = 0
    for sha in shas:
        msg = git("log", "-1", "--format=%B", sha)
        subj = git("log", "-1", "--format=%s", sha)
        _p, _d, removed, _c = _g.commit_view(ROOT, sha)
        bad = _g.unacknowledged_removals(removed, msg, "")
        v = _g.REFUSED if bad else _g.PASS
        vt = {0: "PASS", 3: "REFUSED"}.get(v, str(v))

        touches_port = any(p.startswith(("gates/tn_", "tinybendygrad/")) for p in
                           git("diff-tree", "-r", "--no-commit-id", "--name-only", sha).splitlines())
        is_porting = ("tn_" in subj or "ported" in subj.lower()) and touches_port
        if is_porting:
            n_port += 1
            n_ref_port += v == _g.REFUSED
            rows.append("\t".join([sha[:12], "PORTING", str(len(removed)), str(len(bad)),
                                   vt, subj[:60]]))
        if not removed:
            n_addonly += 1
            n_ref_add += v == _g.REFUSED
            rows.append("\t".join([sha[:12], "ADDS-ONLY", "0", "0", vt, subj[:60]]))

    (HERE / "porting.rows").write_text("\n".join(rows) + "\n")
    n = len(shas)
    print(f"population: {n} commits, git log --since={a.since}, HEAD")
    print()
    print(f"PORTING   {n_port} of {n} commits (subject names tn_*/ported AND the diff touches "
          f"gates/tn_* or tinybendygrad/)")
    print(f"          {n_ref_port} of those REFUSED by the diff subject")
    print(f"ADDS-ONLY {n_addonly} of {n} commits (diff removes nothing at all)")
    print(f"          {n_ref_add} of those REFUSED -- MUST be 0: a removals rule cannot fire "
          f"on a commit that removes nothing")
    print()
    if n_ref_add:
        print("DEFECT: the rule fired on a commit with no removals.")
    print("PORTING commits refused, with the count that made them refuse:")
    for line in rows:
        f = line.split("\t")
        if f[1] == "PORTING" and f[4] == "REFUSED":
            print(f"  {f[0]} removals={f[2]:>4s} unack={f[3]:>4s}  {f[5]}")
    print("rows: porting.rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())