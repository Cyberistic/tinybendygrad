#!/usr/bin/env python3
"""Quietness reading: sample mtimes of the port tree + graphcmp.bend, report distinct writes."""
import os
import time
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGETS = [ROOT / "tinybendygrad", ROOT / ".agents/slop/graphcmp.bend"]
DUR = 300
PERIOD = 15


def snap() -> dict:
    out = {}
    for t in TARGETS:
        if t.is_file():
            out[str(t.relative_to(ROOT))] = t.stat().st_mtime_ns
        else:
            for p in t.rglob("*"):
                if p.is_file():
                    out[str(p.relative_to(ROOT))] = p.stat().st_mtime_ns
    return out


def main() -> None:
    start = time.time()
    prev = snap()
    baseline = dict(prev)
    last_change = start
    changes = []  # (t, path)
    samples = 1
    while time.time() - start < DUR:
        time.sleep(PERIOD)
        cur = snap()
        samples += 1
        now = time.time()
        for k, v in cur.items():
            if baseline.get(k) != v:
                changes.append((now, k))
                baseline[k] = v
        if changes:
            last_change = now
    distinct = sorted({c[1] for c in changes})
    print(f"duration={DUR}s samples={samples} period={PERIOD}s")
    print(f"distinct_files_changed={len(distinct)}")
    for p in distinct:
        print(f"changed {p}")
    print(f"writes={len(changes)}")
    print(f"verdict={'QUIET' if not changes else 'MOVING'}")
    print(f"last_write_at={time.strftime('%H:%M:%S', time.localtime(last_change))}")
    print(f"now={time.strftime('%Y-%m-%dT%H:%M:%S%z')}")


if __name__ == "__main__":
    main()
