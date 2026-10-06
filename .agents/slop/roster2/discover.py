#!/usr/bin/env python3
"""THE ROSTER DISCOVERED, OR THE REFUSAL. Discovery rule, stated as a tree property:

    A unit is LIVE iff the newest file under `.agents/slop/<name>/` is younger
    than the window. Nothing names a unit. The roster is a derived view of mtimes.

`sweep.LIVE_UNITS` is the tuple it replaces, and it has been wrong four times.

REPRODUCIBLE: `--snap` freezes the walk into `.rows` (tab-separated, with the
reference clock embedded in the first line), `--from` reads the freeze, so a run
is a function of ONE input file, not of when you looked.

PLANT (`--plant`): the frozen input is edited in exactly one field -- the newest
mtime of one directory crosses the window boundary -- and the rule's answer MUST
move. A rule invariant under its own condition is a label, not a clause.

DENOMINATOR, always: N top-level directories, M files under them, out of the
total M_total files the walk saw -- never a disagreement count.
"""
import argparse, collections, os, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SLOP = os.path.join(ROOT, ".agents/slop")
SNAP = os.path.join(ROOT, ".agents/slop/roster2/frozen.rows")
WINDOWS = (0, 60, 1440)


def walk():
    """One walk. (dir, newest_mtime, n_files) per top-level directory under .agents/slop."""
    newest = {}
    count = collections.Counter()
    now = time.time()
    for dirpath, _d, files in os.walk(SLOP):
        for f in files:
            p = os.path.join(dirpath, f)
            try:
                top = os.path.relpath(p, SLOP).split(os.sep)[0]
                mt = os.path.getmtime(p)
            except OSError:
                continue
            count[top] += 1
            newest[top] = max(newest.get(top, 0.0), mt)
    total = sum(count.values())
    rows = sorted(((d, newest[d], count[d]) for d in count), key=lambda r: r[0])
    return now, rows, total


def write_snap(path, now, rows):
    with open(path, "w") as fh:
        fh.write(f"# now={now:.0f}\n")
        for d, mt, n in rows:
            fh.write(f"{d}\t{mt:.0f}\t{n}\n")


def read_snap(path):
    now = None
    rows = []
    for ln in open(path):
        if ln.startswith("# now="):
            now = float(ln.split("=")[1])
            continue
        d, mt, n = ln.rstrip("\n").split("\t")
        rows.append((d, float(mt), int(n)))
    return now, rows


def roster(rows, now, window):
    """THE RULE: directories whose newest file is younger than `window` minutes. No names."""
    cutoff = now - window * 60
    live = {d for d, mt, _n in rows if mt >= cutoff}
    files = sum(n for d, _mt, n in rows if d in live)
    covered = sum(n for _d, _mt, n in rows)
    return live, files, covered


def load_tuple():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "sweep", os.path.join(ROOT, "checks/sweep.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return set(m.LIVE_UNITS)


def report(path):
    now, rows = read_snap(path)
    total = sum(n for _d, _n, n in
                ((d, mt, n) for d, mt, n in rows)) if rows else 0
    total = sum(n for _d, _mt, n in rows)
    named = load_tuple()
    print(f"# frozen now={now:.0f}  {len(rows)} top-level dirs  {total} files, one walk")
    for w in WINDOWS:
        live, files, _cov = roster(rows, now, w)
        stale = sorted(d for d in named if d in {d for d, _m, _n in rows} and d not in live)
        fresh_not_named = sorted(d for d in live if d not in named)
        print(f"#   w={w:5d}m: rule names {len(live):3d} dirs covering {files:5d} of {total} files")
        print(f"#     of which the tuple ALSO names {len(live & named):3d}; the tuple names "
              f"{len(stale):3d} dirs this window already lost (stale second belt);")
        print(f"#     the rule names {len(fresh_not_named):3d} dirs the tuple never heard of")


def plant(path):
    """Edit ONE mtime across a window boundary: the rule's answer must move."""
    now, rows = read_snap(path)
    # pick the directory whose newest file sits just inside the 60m window, if any;
    # else any directory; move its newest mtime to 3 hours old.
    target = None
    for d, mt, n in rows:
        age = now - mt
        if 0 <= age <= 3600:
            target = (d, mt, n)
            break
    if target is None:
        target = rows[0]
    d, mt, n = target
    age_before = (now - mt) / 60
    before, bf, _ = roster(rows, now, 60)
    edited = [(dd, (now - 3 * 3600 if dd == d else mm), nn) for dd, mm, nn in rows]
    after, af, _ = roster(edited, now, 60)
    moved_out = before - after
    print(f"# PLANT: {d}/'s newest file aged {age_before:.0f}m -> 180m")
    print(f"#   roster(60m) moved: {len(before)} dirs -> {len(after)} dirs, "
          f"the dir leaves: {d in moved_out}")
    print(f"#   files covered: {bf} -> {af}")
    # negative control: the tuple does not move no matter what the tree does
    named = load_tuple()
    print(f"#   LIVE_UNITS never moves: still {len(named)} names, including "
          f"{len(named & after)} of the now-live dirs")
    ok = (d in moved_out) and before != after
    print(f"# PLANT {'PASS' if ok else 'FAIL'} -- the rule moved under the edit; "
          f"the tuple cannot")
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--snap", action="store_true")
    ap.add_argument("--from", dest="src", metavar="FILE")
    ap.add_argument("--plant", action="store_true")
    args = ap.parse_args()
    if args.snap:
        now, rows, total = walk()
        write_snap(SNAP, now, rows)
        print(f"# wrote {SNAP}: {len(rows)} dirs, {total} files, now={now:.0f}")
    src = args.src or SNAP
    if args.plant:
        sys.exit(plant(src))
    if args.src or not args.snap:
        report(src)
