#!/usr/bin/env python3
"""THE MTIME PROBLEM, MEASURED IN BOTH DIRECTIONS.

`citeresolve` said it and nobody closed it: a claim about a generated file must carry the
file's mtime. `grep mtime checks/differ.py checks/corpus-figure.py` returns NOTHING, so the
pins carry no time at all. This measures what a time-aware rule would actually have to
compare, and it measures BOTH directions, because "a pin must refuse an artifact newer than
the commit that set it" and its mirror image are opposite rules and only one of them is
defensible:

  NEWER  artifact written AFTER the pin's commit. The pin was set, THEN a run tested it.
         A match here is a genuine PREDICTION -- the strongest thing a pin can do.
  OLDER  artifact written BEFORE the pin's commit. The pin was retro-fitted FROM that file,
         so matching is a COPY, not a test. THIS is the pin that cannot fail: the next run
         has to change before the pin can notice, and nothing in the tree forces it to.

So the defensible rule is the mirror of the one in the brief. Both readings are printed.
"""
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402

ROOT = derive.ROOT
D = ROOT / "runs/graphcmp/D"
SRC = (ROOT / "checks/differ.py").read_text()


def git(*a):
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True,
                          text=True).stdout.strip()


def pins_block():
    lines = SRC.splitlines()
    start = next(i for i, l in enumerate(lines, 1) if l.startswith("PINS = {"))
    end = next(i for i, l in enumerate(lines, 1) if i > start and l.startswith("}"))
    return start, end


def last_touch(start, end):
    """The commit that last wrote ANY line of the PINS block, with its COMMITTER date."""
    out = git("log", "-1", "--format=%H%n%cI%n%ci", "-L",
              f"{start},{end}:checks/differ.py").splitlines()
    return out[0], datetime.fromisoformat(out[1])


def per_value_blame():
    """For each pin VALUE, the commit that last introduced that exact `key=value` pair.

    `git log -S` on the rendered row, because the dict is four keys to a line and a per-key
    line number does not exist (measured: blaming per key returns 0 for all 17).
    """
    live = dict(ln.split("=", 1) for ln in
                (D / "D0-run-summary.txt").read_text(errors="replace").splitlines() if "=" in ln)
    out = []
    for k, v in derive.differ.PINS.items():
        needle = f'"{k}": "{v}"'
        h = git("log", "-1", "--format=%h|%cI", "-S", needle, "--", "checks/differ.py")
        parts = h.split("|") if h else ["?", ""]
        out.append((k, v, parts[0],
                    datetime.fromisoformat(parts[1]) if len(parts) > 1 and parts[1] else None))
    return out, live


def mtimes():
    files = [p for p in D.glob("*") if p.is_file()]
    return (min(p.stat().st_mtime for p in files),
            max(p.stat().st_mtime for p in files),
            sorted(p.name for p in files if p.name.endswith(".err")))


if __name__ == "__main__":
    ok, _ = derive.selfcheck()
    if not ok:
        raise SystemExit(1)
    start, end = pins_block()
    commit, set_at = last_touch(start, end)
    summary = D / "D0-run-summary.txt"
    art = datetime.fromtimestamp(summary.stat().st_mtime, timezone.utc)
    set_utc = set_at.astimezone(timezone.utc)
    lo, hi, errs = mtimes()

    print(f"\n== THE TWO CLOCKS ==\n")
    print(f"  PINS block   checks/differ.py:{start}-{end}")
    print(f"  last touched {commit[:12]} at {set_at.isoformat()}  (committer date)")
    print(f"  artifact     D0-run-summary.txt at {art.isoformat()}")
    delta = (set_utc - art).total_seconds()
    print(f"\n  the pins were set {abs(delta) / 60:.1f} min "
          f"{'AFTER' if delta > 0 else 'BEFORE'} the artifact they are matched against.")
    print(f"  DIRECTION: artifact is {'NEWER' if art > set_utc else 'OLDER'} than the pin's commit.")
    print(f"  -> A match here is {'A PREDICTION (pin set first, run tested it)' if art > set_utc else 'A RETRO-FIT (pin copied FROM this artifact -- it cannot fail)'}"
          .replace("->", "=>", 1))
    print(f"\n  earliest artifact {datetime.fromtimestamp(lo, timezone.utc).isoformat()}")
    print(f"  latest   artifact {datetime.fromtimestamp(hi, timezone.utc).isoformat()}")
    print(f"  {len(errs)} `.err` files present (all zero-byte is correct; `artefacts_ok()` excludes them)")

    rows, live = per_value_blame()
    print(f"\n== PER-PIN: WHEN WAS THIS VALUE WRITTEN, AND IS THE ARTIFACT OLDER? ==\n")
    print(f"{'PIN':18} {'VALUE':26} {'SET BY':10} {'SET AT':30} DIRECTION")
    older = newer = none = 0
    for k, v, h, when in rows:
        if when is None:
            dirn, older = "no -S hit (value predates -S tracking)", older
            none += 1
        else:
            dirn = "artifact NEWER (prediction)" if art > when else "artifact OLDER (retro-fit)"
            if art > when:
                newer += 1
            else:
                older += 1
        print(f"{k:18} {v[:26]:26} {h:10} {(when.isoformat() if when else '?')[:30]:30} {dirn}")
    print(f"\n  artifact NEWER than the pin's value (a real prediction): {newer}")
    print(f"  artifact OLDER than the pin's value (a retro-fit):        {older}")
    print(f"  untraceable by -S (value predates the search):             {none}")
    print(f"\n  => A 'refuse when the artifact is NEWER' rule would REDDEN {newer} of "
          f"{len(rows)} pins TODAY.")
    print(f"  => A 'refuse when the artifact is OLDER' rule would REDDEN {older} of "
          f"{len(rows)} pins TODAY.")
