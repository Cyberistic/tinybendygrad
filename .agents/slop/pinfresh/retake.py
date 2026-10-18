#!/usr/bin/env python3
"""TAKE ONE READ-ONLY SNAPSHOT OF THE SUBSTRATE, AND PRINT THE DIGEST THE WRITER HIMSELF COMPUTES.

`checks/differ.py` is LOADED BY PATH, never re-implemented: its module level is constants
(`ROOT` at :42 and the tables) and `main()` is behind the guard at :1427, so loading it runs no
gate, no subprocess and no compile. Two snapshots taken by THIS file are what make "which declared
input moved" a witnessed set instead of an inference -- provided both are written by one writer
that cannot tear, so every row is terminated and the header ends with its newline.

`.rows` columns: `relpath TAB sha256 TAB state` (state is against the 2026-10-17 manifest, which is
the only per-member record on disk, and is only a label -- nothing here depends on it).
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/pinfresh"
SNAP = HERE / "live-entries.rows"
MANIFEST = ROOT / "runs/graphcmp/MANIFEST.tsv"
ENV = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def baseline() -> dict[str, str]:
    if not MANIFEST.is_file():
        return {}
    return {rel: blob for ln in MANIFEST.read_text().splitlines()
            if "\t" in ln for blob, rel in [ln.split("\t", 1)]}


def main() -> int:
    HERE.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("differ_writer", ROOT / "checks/differ.py")
    w = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w)

    took, entries = stamp(), sorted(w.substrate_entries())
    digest = w.substrate_digest()
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                          text=True, env=ENV, timeout=10).stdout.strip()
    base = baseline()
    body = [f"# differ.substrate_entries() at {took} HEAD {head} digest {digest} -- "
            f"{len(entries)} members; relpath TAB sha256 TAB state\n"] + [
        f"{rel}\t{blob}\t" + ("ABSENT" if blob == "ABSENT" else "new-vs-manifest"
                              if rel not in base else "changed-vs-manifest"
                              if base[rel] != blob else "same-as-manifest") + "\n"
        for rel, blob in entries]
    SNAP.write_text("".join(body))

    fold = hashlib.sha256()
    for rel, blob in entries:
        fold.update(rel.encode() + b"\0" + blob.encode() + b"\0")
    print(f"{took} head {head} members {len(entries)} digest {digest} "
          f"replay {fold.hexdigest()} replay-agrees {fold.hexdigest() == digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())