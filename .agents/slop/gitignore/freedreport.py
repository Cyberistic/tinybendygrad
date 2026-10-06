#!/usr/bin/env python3
"""The stable population the anchored rule acts on, independent of what a
concurrent unit happened to commit: paths matched by the OLD broad `runs/`
that no OTHER rule covers. Splits by tracked-before (from before.lsfiles).
"""
import collections
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matchlib as M  # noqa: E402

ROOT = M.ROOT


def main():
    all_rules = M.load_all_rules()
    with open(os.path.join(ROOT, ".agents/slop/gitignore/before-lsfiles.rows")) as fh:
        before_tracked = set(l for l in fh.read().splitlines() if l)
    paths = list(M.walk_paths())

    rule = [r for r in all_rules if r["file"] == ".gitignore"
            and r["pattern"] == "runs"][0]
    broad = dict(rule)
    broad["anchored"] = False
    others = [r for r in all_rules
              if not (r["file"] == ".gitignore" and r["pattern"] == "runs")]

    pop = [(p, d) for p, d in paths
           if M.matched_rules([broad], p, d) and not M.matched_rules(others, p, d)]
    nested = [(p, d) for p, d in pop
              if not (p == "runs" or p.startswith("runs/"))]
    rootonly = [(p, d) for p, d in pop
                if p == "runs" or p.startswith("runs/")]

    def klass(p):
        if "e2epy/fixtures" in p or "figure2/plant" in p:
            return "EVIDENCE(fixture)"
        if "differverdict/pristine" in p:
            return "EVIDENCE(oracle-baseline)"
        if "/scratch/" in p or "checkshells" in p:
            return "OUTPUT(scratch-artifacts)"
        return "OUTPUT(graphcmp-run)"

    untr = [(p, d) for p, d in nested if p not in before_tracked]
    tr = [(p, d) for p, d in nested if p in before_tracked]
    print(f"broad_population={len(pop)} ({sum(1 for _,d in pop if not d)} files)")
    print(f"  nested_population={len(nested)}")
    print(f"  root_runs_population={len(rootonly)}")
    print(f"nested_tracked_before={len(tr)}  nested_untracked_before={len(untr)}")
    print("untracked_before_ext=", dict(collections.Counter(
        os.path.splitext(p)[1] or "(dir/none)" for p, _ in untr)))
    print("untracked_before_class=", dict(collections.Counter(
        klass(p) for p, _ in untr)))
    print("nested_tracked_before_class=", dict(collections.Counter(
        klass(p) for p, _ in tr)))
    print("untracked_files_only=", sum(1 for _, d in untr if not d))
    print("nested_untracked_under_slop=", sum(
        1 for p, _ in untr if p.startswith(".agents/slop/")))
    print("nested_untracked_not_under_slop=", [p for p, _ in untr
                                               if not p.startswith(".agents/slop/")][:20])
    # what /runs/ still ignores now
    now = [p for p, d in paths if M.matched_rules([rule], p, d)]
    print(f"now_ignored_by_/runs/={len(now)} (all root):",
          all(p == "runs" or p.startswith("runs/") for p in now))


if __name__ == "__main__":
    main()
