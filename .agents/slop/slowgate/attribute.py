#!/usr/bin/env python3
""".agents/slop/slowgate/attribute.py -- WHERE `checks/residue.py`'s TIME GOES, PER STAGE.

    .venv/bin/python .agents/slop/slowgate/attribute.py [--stages NAME,NAME] [--rowlimit N]

It re-runs `main()`'s statements one at a time and prints a wall-clock row for each, so the
attribution is a MEASUREMENT and not an estimate. The two statements that spawn a subprocess per
item are counted as well as timed: `belt_git` is one `git grep -w -F` PER residue row, and a
statement that is cheap per call and quadratic in the population is the shape a total does not
show. `--rowlimit` classifies only N rows and reports the rate, which is what makes an unbounded
run measurable.

The module is imported BY PATH, never by name, and it calls `main()`'s statements rather than
re-implementing them: a second copy of the pipeline is a second answer to the same question.
"""
from __future__ import annotations

import argparse
import collections
import importlib.util
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]   # slowgate/slop/.agents/ROOT -- `oracle_f64.py` records
                                            # the same off-by-one as its own MEASURED lesson
sys.path.insert(0, str(ROOT / "checks"))


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "checks" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rowlimit", type=int, default=25,
                    help="classify only N rows, then extrapolate the rate (default 25)")
    ap.add_argument("--window", type=int, default=0, help="`--live-minutes` for the classify stage")
    args = ap.parse_args()

    t0 = time.monotonic()
    stage_t: dict[str, float] = collections.OrderedDict()

    def stage(name):
        class _S:
            def __enter__(self):
                self.t = time.monotonic()
                return self

            def __exit__(self, *a):
                stage_t[name] = time.monotonic() - self.t
        return _S()

    with stage("import sweep"):
        r = load("residue")
        sweep = r.sweep_module()
    with stage("sweep.committed_named_text + mentioned_filenames"):
        named = sweep.mentioned_filenames(sweep.committed_named_text())
    with stage("git_tracked"):
        tracked = r.git_tracked(str(ROOT))
    with stage("walk (residue population)"):
        files = r.walk(str(ROOT))
    with stage("dir_ages"):
        age = r.dir_ages(str(ROOT), files)
    with stage("authorities"):
        auth = r.authorities()

    first = lambda rel, n: sweep.verdict_for(rel, n)      # noqa: E731  main()'s own lambda
    with stage("sweep.verdict_for over the whole walk"):
        rows = [(rel, sz, first(rel, named)) for rel, sz in files]
    residue_rows = [r_ for r_ in rows if r_[2] == "DELETE"]

    with stage("outside_twins (sha256 over every tracked file)"):
        twins = r.outside_twins(str(ROOT), tracked, residue_rows)

    with stage("citation index (every tracked blob)"):
        cites: dict[str, set[str]] = collections.defaultdict(set)
        for rel in sorted(tracked):
            if r.excluded(rel):
                continue
            try:
                with open(os.path.join(ROOT, rel), "rb") as fh:
                    blob = fh.read(4 << 20).decode("utf-8", "replace")
            except OSError:
                continue
            r.index_citations(cites, str(ROOT), rel, blob)

    # HOW MANY `git grep` PROCESSES WOULD THE FULL RUN SPAWN? One per row with a citation
    # candidate, so it is a function of the classified rows and is measured on the sampled ones.
    greps = 0
    real_belt = r.belt_git

    def counting_belt(root, name):
        nonlocal greps
        greps += 1
        return real_belt(root, name)

    r.belt_git = counting_belt
    sample = residue_rows[:args.rowlimit]
    with stage(f"classify {len(sample)} of {len(residue_rows)} rows"):
        for rel, sz, _f in sample:
            r.classify(str(ROOT), rel, sz, sweep_named=named, first_pass=first, auth=auth,
                       age=age, window=args.window, twins=twins, cites=cites, disabled=set())
    r.belt_git = real_belt

    total = time.monotonic() - t0
    print(f"population: {len(files)} residue files, {len(tracked)} tracked, "
          f"{len(residue_rows)} DELETE rows, {len(auth)} authority(ies)")
    print(f"{'stage':52s} {'seconds':>9s}  {'share':>6s}")
    for k, v in stage_t.items():
        print(f"{k:52s} {v:9.2f}  {100 * v / total:5.1f}%")
    print(f"{'TOTAL (the stages above)':52s} {total:9.2f}")
    if sample:
        rate = stage_t[f"classify {len(sample)} of {len(residue_rows)} rows"] / len(sample)
        print(f"\nclassify rate: {rate * 1000:.0f} ms/row -> "
              f"{rate * len(residue_rows):.0f} s for all {len(residue_rows)} rows")
        print(f"git grep spawns: {greps} for {len(sample)} sampled rows "
              f"({greps / len(sample):.2f} per row) -> "
              f"{greps / len(sample) * len(residue_rows):.0f} for the full run")
    return 0


if __name__ == "__main__":
    sys.exit(main())