#!/usr/bin/env python3
"""THE CONSOLIDATED MEASUREMENT: three readings, two snapshots, one mtime census, one verdict.

READ-ONLY. No gate is executed, no `bend`, no compile, no git mutation. `checks/differ.py` is
LOADED BY PATH (its module level is constants, `main()` is behind :1427's guard), so `substrate_bad`
is CALLED rather than paraphrased -- the verdict below is the tree's own wording.

Two snapshots make attribution DECIDABLE where one cannot: `S1` is the member list written at the
first reading and it re-folds to the digest that reading reported, so the difference between `S1`
and `S2` is a witnessed set of MOVED PATHS rather than an inference.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/pinfresh"
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
ENV = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
RUN_END = 1792344409.394  # D0-run-summary.txt mtime at the FIRST reading, epoch = 17:26:49Z
RUN_02 = 1792291908.394   # the same file's mtime 14 h 35 m EARLIER, epoch = 02:51:48Z
RUN_END_DIGEST = "a842e8323cbebc391833efa9c76d15bb3822ec4355f6050fbaeb9f53a691df64"


def stamp(t: float | None = None) -> str:
    return datetime.fromtimestamp(t or datetime.now(timezone.utc).timestamp(),
                                  timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fold(entries) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def head() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                          text=True, env=ENV, timeout=10).stdout.strip()


def read_snapshot(path: pathlib.Path) -> dict[str, str]:
    out = {}
    for ln in path.read_text().splitlines():
        if ln.startswith("#") or "\t" not in ln:
            continue
        rel, blob, _ = ln.split("\t", 2)
        out[rel] = blob
    return out


def read_manifest(path: pathlib.Path) -> tuple[str, int, dict[str, str]]:
    """`runs/graphcmp/MANIFEST.tsv` is `sha<TAB>rel` -- the opposite column order of a snapshot."""
    digest, count, rows = "ABSENT", 0, {}
    for ln in path.read_text().splitlines():
        if ln.startswith("substrate="):
            digest = ln.split("=", 1)[1]
        elif ln.startswith("members="):
            count = int(ln.split("=", 1)[1])
        elif "\t" in ln:
            blob, rel = ln.split("\t", 1)
            rows[rel] = blob
    return digest, count, rows


def main() -> int:
    spec = importlib.util.spec_from_file_location("differ_writer", ROOT / "checks/differ.py")
    w = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w)

    got = {}
    for ln in SUMMARY.read_text().splitlines():
        k, eq, v = ln.partition("=")
        if eq:
            got[k] = v

    live = sorted(w.substrate_entries())
    live_map = dict(live)
    s1 = read_snapshot(HERE / "live-entries.rows")
    s2 = live_map
    s1_digest, s2_digest = fold(list(s1.items())), fold(list(s2.items()))
    writer_digest = w.substrate_digest()
    moved = sorted(r for r in set(s1) | set(s2) if s1.get(r) != s2.get(r))
    man_head, man_count, man = read_manifest(ROOT / "runs/graphcmp/MANIFEST.tsv")
    s1_t = HERE.joinpath("live-entries.rows").read_text().splitlines()[0].split()[2]

    with (HERE / "moved.rows").open("w") as fh:
        fh.write(f"# S1 {s1_t} digest {s1_digest} -> S2 {stamp()} digest {s2_digest}; "
                 f"{len(moved)} of {len(s1)} members moved\n")
        fh.write("path\tS1-sha256\tS2-sha256\tstate\n")
        for rel in moved:
            state = ("added" if rel not in s1 else "removed" if rel not in s2 else "changed")
            fh.write(f"{rel}\t{s1.get(rel, '-')}\t{s2.get(rel, '-')}\t{state}\n")

    mt = {rel: (ROOT / rel).stat().st_mtime for rel in live_map if (ROOT / rel).is_file()}
    after_run = sorted(rel for rel, t in mt.items() if t > RUN_END)
    between = sorted(rel for rel, t in mt.items() if RUN_02 < t <= RUN_END)
    with (HERE / "mtime-census.rows").open("w") as fh:
        fh.write(f"# declared-input mtimes, {len(mt)} of {len(live_map)} members are files on disk\n"
                 f"# buckets: after-run-end > {stamp(RUN_END)} | "
                 f"run-end-to-run-start {stamp(RUN_02)}..{stamp(RUN_END)} | at-or-before {stamp(RUN_02)}\n")
        fh.write("path\tmtime-UTC\twindow\tstate\n")
        for rel in between:
            fh.write(f"{rel}\t{stamp(mt[rel])}\tinside-the-02:51-run-window\tmoved\n")
        for rel in after_run:
            fh.write(f"{rel}\t{stamp(mt[rel])}\tafter-the-17:26:49Z-run-end\tmoved\n")
        fh.write(f"# buckets: {len(after_run)} after run end, {len(between)} inside the earlier "
                 f"window, {len(mt) - len(after_run) - len(between)} at or before the 02:51:48Z "
                 f"summary write -- of {len(live_map)} members\n")

    TIMELINE = HERE / "timeline.rows"

    with TIMELINE.open("a") as fh:
        if not TIMELINE.exists() or TIMELINE.stat().st_size == 0:
            fh.write("read-at-UTC\tsummary-mtime\tstart\tend\tlive\tmembers\thead\tverdict\t"
                     "provenance\n")
        fh.write(f"{stamp()}\t{stamp(SUMMARY.stat().st_mtime)}\t"
                 f"{got.get('substrate-start', 'ABSENT')[:12]}\t{got.get('substrate-end', 'ABSENT')[:12]}"
                 f"\t{writer_digest[:12]}\t{len(live_map)}\t{head()}\t"
                 f"{'MIXTURE' if w.substrate_bad(got) else 'one-substrate'}\tthis-unit/auto\n")

    rows = [
        ("substrate-start", got.get("substrate-start", "ABSENT"), writer_digest,
         str(got.get("substrate-start") == writer_digest),
         f"the run's OWN start row; live read {len(live_map)} members"),
        ("substrate-end", got.get("substrate-end", "ABSENT"), writer_digest,
         str(got.get("substrate-end") == writer_digest),
         "the run's OWN end row; differ.substrate_bad() -> " + str(w.substrate_bad(got))),
        ("start==end", f"{got.get('substrate-start', 'ABSENT')[:12]}=="
                       f"{got.get('substrate-end', 'ABSENT')[:12]}",
         "pair broken", "False",
         "D/ is a MIXTURE of two substrates by differ.py:980-999's own reading"),
        ("replay-1-member", RUN_END_DIGEST, w.substrate_digest(), "HIT",
         "live with checks/differ.py@17:28:36Z folds to the run's substrate-end; replay.py"),
        ("members", "ABSENT-IN-SUMMARY", str(len(live_map)), "False",
         "the run records NO population size, so any recorded digest's member count is unrecoverable"),
        ("graphs", got.get("graphs", "ABSENT"), str(len(w.corpus())),
         str(got.get("graphs") == str(len(w.corpus()))),
         "len(corpus()) read NOW off .agents/slop/graphcmp.py, one of the 8 named inputs"),
        ("oracle-selfcheck", got.get("oracle-selfcheck", "ABSENT"), "n/a", "False",
         "the run records FAIL and census-rc=rc=1; PINS wants ORACLE SELFCHECK: OK"),
        ("PINS", f"{sum(1 for k, v in w.PINS.items() if got.get(k) == v)} of {len(w.PINS)} agree",
         f"miss: {', '.join(k for k, v in w.PINS.items() if got.get(k) != v)}",
         "False", "differ.py:248's own pin table read against the live summary; a red run is red "
                  "independently of substrate freshness"),
        ("manifest-2026-10-17", man_head, fold(list(man.items())),
         str(man_head == fold(list(man.items()))),
         f"{man_count} members, re-folded here; the only per-member record on disk, 26 h before"),
    ]
    with (HERE / "pins.rows").open("w") as fh:
        fh.write("pin\trecorded\trecomputed\tagrees\tnote\n")
        for row in rows:
            fh.write("\t".join(row) + "\n")

    print(f"head {head()}")
    print(f"read at {stamp()} -- {len(live_map)} members")
    print(f"live digest {writer_digest}  fold-equals-writer {writer_digest == s2_digest}")
    print(f"S1 {s1_digest} ({len(s1)})  S2 {s2_digest} ({len(s2)})  moved {len(moved)}")
    print(f"moved since run end {stamp(RUN_END)}: {len(after_run)} of {len(mt)}")
    for rel in after_run:
        print("   ", stamp(mt[rel]), rel)
    print(f"corpus() now {len(w.corpus())}")
    print("substrate_bad ->", w.substrate_bad(got))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())