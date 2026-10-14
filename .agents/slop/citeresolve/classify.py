#!/usr/bin/env python3
"""Classify every scan row into the five kinds the brief names, by EVIDENCE.

  (a) DRIFT         -- the target moved; the subject still exists elsewhere.
  (b) DEAD SUBJECT  -- the subject was deleted from a file that remains.
  (c) NEVER EXISTED -- the path or subject was invented; it is nowhere in history.
  (d) STALE COUNT   -- (handled in `counts.py`; not a `<path>:<N>` claim)
  (e) NARRATIVE     -- the cite records what something USED to say; must NOT move.

Evidence used (never a hand call):
  * GONE-FILE + basename in `hist.tsv` bases  -> the path existed before  (b or d-adjacent)
  * GONE-FILE + basename absent from history  -> (c) NEVER EXISTED
  * OUT-OF-RANGE + subject absent from the file -> the subject is gone here
  * OUT-OF-RANGE / RESOLVES + subject present elsewhere in the file -> (a) DRIFT
  * a narrative cue in the SOURCE line (`was`, `then`, `used to`, `historical`,
    `no longer`, `renumber`, `pre-`, `at the time`) -> (e) NARRATIVE, which wins
    over (a): the number is a datum, not an anchor.

The needle is a LINE-LEVEL heuristic; `ELSEWHERE` only asserts that some code
token on the citing line occurs in the target file, so it is a CANDIDATE class,
not a proof.  `AT-LINE` is the only positive confirmation.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

NARR = (
    "used to", "historical", "no longer", "renumber", "at the time", "formerly",
    "had been", "(was ", "pre-deletion", "pre-fix", "pre-fix lane", "existed once",
    "at the parent", "recorded position", "then named",
)


def load_hist() -> set[str]:
    bases: set[str] = set()
    with open(os.path.join(HERE, "hist.tsv"), encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if parts[0] == "base":
                bases.add(parts[1])
    return bases


def classify(status: str, needle: str, base: str, src: str, hist: set[str]) -> str:
    if any(c in src.lower() for c in NARR):
        return "e:NARR"
    if status == "GONE-FILE":
        return "b:DEAD-PATH" if base in hist else "c:NEVER-EXISTED"
    if status == "AMBIG":
        return "?:AMBIG"
    if status == "OUT-OF-RANGE":
        return {"ELSEWHERE": "a:DRIFT", "NOWHERE": "a/b:SUBJECT-GONE"}.get(needle, "?:OOR-UNATTR")
    if status == "RESOLVES":
        return {
            "AT-LINE": "OK:AT-LINE",
            "ELSEWHERE": "a:DRIFT-CAND",
            "NOWHERE": "a/b:RESOLVES-NOWHERE",
            "UNCHECKED": "OK:UNCHECKED",
        }.get(needle, "?")
    return "?"


def main() -> int:
    hist = load_hist()
    from collections import Counter
    rows = []
    with open(os.path.join(HERE, "scan.tsv"), encoding="utf-8") as fh:
        next(fh)
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 9:
                continue
            src, status, needle, path = f[8], f[5], f[6], f[2]
            base = os.path.basename(path)
            rows.append((classify(status, needle, base, src, hist), *f))
    print("kind\tsurface\tsline\tpath\tspec\ttarget\tstatus\tneedle\tline_text\tsource_line")
    for r in rows:
        print("\t".join(str(x) for x in r))
    c = Counter(r[0] for r in rows)
    print(f"# total={len(rows)} " + " ".join(f"{k}={v}" for k, v in sorted(c.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
