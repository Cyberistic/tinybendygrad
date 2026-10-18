#!/usr/bin/env python3
"""REPLAY: DID `checks/differ.py` ALONE ACCOUNT FOR THE DIGEST MOVING OFF THE RUN'S `substrate-end`?

ONE PREDICTION, AND IT CAN FAIL. The run's end digest is `a842e832…`; the live digest is
`7f84fd3d…`; the mtime census over all 156 declared members names exactly ONE file written after
the run's summary write, `checks/differ.py` at 17:29:01Z. So: take the CURRENT member list, put
that one file back to the sha the 17:28:36Z reading recorded for it, fold, and ask whether the
answer is `a842e832…`.

  HIT   -> that one member's bytes account for the move, and the census that named it was right.
  MISS  -> something else moved and the census missed it. Reported as a miss. Not retuned.

NOT A FULL REPLAY, AND THE REASON IS THIS UNIT'S OWN BUG: the 17:28:36Z snapshot was written with
an unterminated header line, which swallowed its own first member row, and re-taking the snapshot
overwrote it. So the run-end member LIST is gone and the full 156-member replay is impossible.
This is the narrow version that survives, and it is a prediction rather than a reconstruction --
the substituted sha comes from `moved.rows`, not from a list of the run's members.
"""

from __future__ import annotations

import hashlib
import pathlib
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/pinfresh"
RUN_END_DIGEST = "a842e8323cbebc391833efa9c76d15bb3822ec4355f6050fbaeb9f53a691df64"
#: `checks/differ.py` sha256 recorded at 17:28:36Z, from the row `moved.rows` kept when the torn
#: snapshot's OWN FIRST ROW was eaten (that row was the 156th member, not this one).
DIFFER_THEN = "8485eb209e1adc088e5dab549e3285c99c53f0072303df7b717f3755b39d4615"
MOVED = "checks/differ.py"
RUN_END_MTIME = 1792344409.394  # D0-run-summary.txt, epoch seconds, observed 2026-10-18T17:26:49Z


def stamp(t: float | None = None) -> str:
    return datetime.fromtimestamp(t or datetime.now(timezone.utc).timestamp(),
                                  timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fold(entries) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode() + b"\0" + blob.encode() + b"\0")
    return h.hexdigest()


def snapshot(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for ln in path.read_text().splitlines():
        if ln.startswith("#") or "\t" not in ln:
            continue
        rel, blob, _ = ln.split("\t", 2)
        out[rel] = blob
    return out


def main() -> int:
    now = snapshot(HERE / "live-entries.rows")
    census = [ln for ln in (HERE / "mtime-census.rows").read_text().splitlines()
              if ln.startswith(MOVED + "\t")]
    print(f"read {stamp()} members {len(now)}")
    print(f"mtime census, '{MOVED}' after the run's summary write: {census or 'NO ROW'}")
    print(f"live digest                       {fold(now.items())}")
    print(f"  == run's substrate-end          {fold(now.items()) == RUN_END_DIGEST}")
    reverted = dict(now, **{MOVED: DIFFER_THEN})
    got = fold(reverted.items())
    print(f"one-member replay, {MOVED}@{DIFFER_THEN[:12]} -> {got}")
    print(f"  == run's substrate-end          {got == RUN_END_DIGEST}"
          f"   {'HIT' if got == RUN_END_DIGEST else 'MISS -- another member moved'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())