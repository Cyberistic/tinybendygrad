#!/usr/bin/env python3
"""Print, for the CURRENT tree, what `DELETE` catches that `UNKNOWN` would not.

    usage: .venv/bin/python .agents/slop/unknowns/what-delete-catches.py [--rows FILE] [--against FILE]

WHY IT COMPARES `HEAD`'s CLASSIFIER WITH THE WORKING TREE'S, AND NOT WITH A SNAPSHOT. Seven units are
writing into `.agents/slop` while this runs, and the DELETE count is a function of the clock as well as
of the tree -- the same file printed `DELETING 366 / 44 / 0` at windows 0, 60 and 1440 with nothing
edited. So a before/after pair taken minutes apart is not a measurement, it is two measurements of two
trees. **BOTH CLASSIFIERS ARE RUN ON ONE WALK, AT ONE INSTANT, ON ONE TREE**, and the difference
between them is exactly the change in the code. `git show HEAD:checks/sweep.py` is exec'd into a module
whose `__file__` points at the real `checks/sweep.py`, so `ROOT` resolves the same in both and `differ`
imports the same.

    the working tree IS `HEAD`'s   -> `DELTA 0`, and the DELETE partition is the BEFORE number.
    the working tree has the fix  -> `DELTA n`, and the partition is the AFTER number.

`--rows FILE` writes every row as TSV (`head-verdict  work-verdict  needs  bytes  path`) so two runs
can be joined on `path`; `--against FILE` does that join and prints how many rows the tree gained or
lost in between, so a delta computed across two runs is never silently attributed to the code.

`UNKNOWN` IS TAGGED -- `UNKNOWN:<needs>` -- so the cheapest test that would resolve the row travels
with the verdict instead of with a sentence. It is also why `--apply` cannot be pointed at it: no
argument equals `UNKNOWN:belts-disagree`.
"""
from __future__ import annotations

import argparse
import collections
import os
import subprocess
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SWEEP = os.path.join(ROOT, "checks/sweep.py")
RESIDUE_ROOTS = (".agents/slop", "runs")


def load_source() -> types.ModuleType:
    """`checks/sweep.py` as it is ON DISK, imported the way `checks/residue.py` imports it."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("sweep_work", SWEEP)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_head() -> tuple[types.ModuleType | None, str]:
    """`checks/sweep.py` AT HEAD, plus its source so `HEAD == worktree` is a BYTE QUESTION.

    exec'd from SOURCE with `__file__` set to the real path: `sweep.py` derives `ROOT` from
    `__file__` and the fixed version imports `checks/differ.py` relative to it, so a temp file on disk
    would resolve a different tree and the two classifiers would not be comparable.
    """
    src = subprocess.run(["git", "show", "HEAD:checks/sweep.py"], cwd=ROOT,
                         capture_output=True, text=True).stdout
    if not src:
        return None, ""
    mod = types.ModuleType("sweep_head")
    mod.__file__ = SWEEP
    exec(compile(src, SWEEP, "exec"), mod.__dict__)
    return mod, src


def walk() -> list[tuple[str, int]]:
    """(relpath, lstat bytes) for every file under both residue roots.

    `os.lstat`, never `os.path.getsize`: slop holds ~170 symlinks into `.venv` and into shadow trees,
    and following them reported 1,291 MB for a 149 MB tree -- a 7.5x headline on the one number this
    instrument exists to publish.
    """
    out = []
    for base in RESIDUE_ROOTS:
        for dirpath, _d, files in os.walk(os.path.join(ROOT, base)):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    out.append((os.path.relpath(p, ROOT), os.lstat(p).st_size))
                except OSError:
                    pass
    return out


def stamp(window: int) -> str:
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    dirty = len(subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                               capture_output=True, text=True).stdout.splitlines())
    return f"HEAD={head} dirty={dirty} at {time.strftime('%Y-%m-%dT%H:%M:%S')} window={window}m"


def bucket(verdict: str) -> str:
    return verdict.split(":", 1)[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", metavar="FILE", help="write every row as TSV")
    ap.add_argument("--against", metavar="FILE", help="join against an earlier --rows dump")
    ap.add_argument("--live-minutes", type=int, default=0,
                    help="liveness window; DEFAULT 0, because the window is a clock, not a measurement")
    args = ap.parse_args()

    work = load_source()
    head, head_src = load_head()
    named = work.mentioned_filenames(work.committed_named_text())
    rows = walk()

    # LIVE is applied by the caller in `sweep.py`, after `verdict_for`, so apply it here too or the
    # two columns are not the same classifier.
    live = work.live_set(args.live_minutes)

    out = []
    for rel, size in rows:
        w = work.verdict_for(rel, named)
        h = head.verdict_for(rel, named) if head else "NO-HEAD"
        if rel in live and w not in ("PROTECTED", "LIVE-UNIT"):
            w = "LIVE"
        if rel in live and h not in ("PROTECTED", "LIVE-UNIT"):
            h = "LIVE"
        out.append((h, w, w.partition(":")[2], size, rel))

    counts = collections.Counter(bucket(w) for _h, w, _n, _s, _r in out)
    bytes_ = collections.Counter()
    for _h, w, _n, sz, _r in out:
        bytes_[bucket(w)] += sz
    total = len(out)
    tb = sum(bytes_.values()) or 1

    print(f"# what DELETE catches that UNKNOWN would not -- {total} files, {tb / 1048576:.1f} MB")
    print(f"# {stamp(args.live_minutes)}")
    print(f"# HEAD == worktree: {head_src == open(SWEEP).read()}  "
          f"(a True here means this run measured the BEFORE state twice)")
    for v in ("DOC", "GATE", "ORACLE", "AUTHORED", "DELETE", "UNKNOWN", "LIVE", "LIVE-UNIT", "PROTECTED"):
        if counts[v]:
            print(f"#   {v:9s} {counts[v]:6d} rows {bytes_[v] / 1048576:8.2f} MB "
                  f"{bytes_[v] / tb * 100:5.1f}%")
    doomed = [r for r in out if bucket(r[1]) == "DELETE"]
    unk = [r for r in out if bucket(r[1]) == "UNKNOWN"]
    keep = counts["DOC"] + counts["GATE"] + counts["ORACLE"] + counts["AUTHORED"]
    print(f"#\n# KEEPING {keep} + REPORTING {len(unk)} UNKNOWN of {total}; "
          f"DELETING {len(doomed)} rows, {sum(r[3] for r in doomed) / 1048576:.2f} MB")
    print(f"# AT HEAD, THE SAME WALK PUT {sum(1 for r in out if bucket(r[0]) == 'DELETE')} ROWS IN DELETE "
          f"({sum(r[3] for r in out if bucket(r[0]) == 'DELETE') / 1048576:.2f} MB)")

    needs = collections.Counter(r[2].split(" (")[0] for r in unk)
    if needs:
        print("#\n# EVERY PATH BY WHICH A ROW REACHES `UNKNOWN` -- `needs=` is the cheapest test:")
        for k, n in needs.most_common():
            print(f"#   UNKNOWN:{k:36s} {n:5d} rows "
                  f"{sum(r[3] for r in unk if r[2] == k) / 1048576:7.2f} MB")

    moves = collections.Counter((bucket(h), bucket(w)) for h, w, _n, _s, _r in out
                                if bucket(h) != bucket(w))
    if moves:
        print(f"\n# MOVED {sum(moves.values())} rows between the two classifiers:")
        for (a, b), n in moves.most_common():
            print(f"#   {a:9s} -> {b:9s} {n:5d}")

    if doomed:
        print(f"\n# `DELETE` AND NOT `UNKNOWN` -- {len(doomed)} rows, and this list is what `--apply DELETE`"
              f" would destroy:")
        for h, w, _n, sz, rel in sorted(doomed, key=lambda r: -r[3])[:20]:
            print(f"#   {sz / 1024:9.1f} KB  {rel}")
        if len(doomed) > 20:
            print(f"#   ... and {len(doomed) - 20} more, all in the --rows dump")

    if args.rows:
        with open(args.rows, "w") as fh:
            for h, w, n, sz, rel in out:
                fh.write(f"{h}\t{w}\t{n or '-'}\t{sz}\t{rel}\n")
        print(f"# wrote {args.rows}: {len(out)} rows")

    if args.against:
        old = {}
        with open(args.against) as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 5:
                    old[parts[4]] = parts
        gone, born = set(old) - {r[4] for r in out}, {r[4] for r in out} - set(old)
        print(f"# against {args.against}: {len(gone)} rows left the tree, {len(born)} arrived"
              f" -- JOINED DELTAS BELOW COUNT ONLY THE {len(set(old) & {r[4] for r in out})} STILL HERE")
        joined = collections.Counter()
        for h, w, n, sz, rel in out:
            o = old.get(rel)
            if o and o[1] != w:
                joined[(bucket(o[1]), bucket(w))] += 1
        for (a, b), n in joined.most_common():
            print(f"#   {a:9s} -> {b:9s} {n:5d}")
        print(f"#   UNCHANGED on rows present in both: {len(set(old) & {r[4] for r in out}) - sum(joined.values())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
