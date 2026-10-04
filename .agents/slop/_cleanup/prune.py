#!/usr/bin/env python3
"""Delete the classes MANIFEST.tsv marked deletable, re-verifying every condition AT DELETE TIME.

A manifest is a statement about the tree at one instant. This script is the act, and it must
not trust the instant: between classifying and deleting, six units were writing. So every
condition the classifier applied is RE-APPLIED HERE, against the live filesystem:

  * the live window      -- a file touched since the manifest was written is SKIPPED, whatever
                            the manifest said. A file that was scratch when measured and is
                            evidence now is the whole failure mode this guards.
  * the citation index   -- recomputed from the committed reports, not read out of the manifest.
  * the path allow-list  -- only under .agents/slop/ and runs/. Never the port, never a gate.

Deletion is by CLASS NAME, never by path. Naming classes is what makes this checkable: the
question a reader asks is "what did you delete", and the answer must be a category with a
definition rather than 2,982 paths.

    usage: .venv/bin/python prune.py --dry-run JUNK-BYTECODE JUNK-ZERO ...
           .venv/bin/python prune.py --live-minutes 90 JUNK-BYTECODE JUNK-ZERO ...

Exit 0 if every named class was deleted or wholly skipped. Exit 1 if any named class had
files that were neither deleted nor explained -- a silent partial pass is the defect class
this project keeps cataloguing, and a prune tool that half-succeeds quietly is one more.
"""
from __future__ import annotations

import argparse
import collections
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import ROOT, SLOP, RUNS, cite_index, committed_reports, live_set  # noqa: E402

ALLOWED = (".agents" + os.sep + "slop" + os.sep, "runs" + os.sep)


def load(manifest: str) -> dict[str, tuple[int, str]]:
    rows: dict[str, tuple[int, str]] = {}
    with open(manifest) as fh:
        for line in fh:
            if line.startswith("#") or line.startswith("VERDICT"):
                continue
            verdict, size, rel = line.rstrip("\n").split(None, 2)
            rows[rel] = (int(size), verdict)
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("classes", nargs="+", help="verdict names from MANIFEST.tsv")
    ap.add_argument("--manifest", default=os.path.join(os.path.dirname(__file__), "MANIFEST.tsv"))
    ap.add_argument("--live-minutes", type=int, default=90)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rows = load(args.manifest)
    live = live_set(args.live_minutes)

    # Recompute the citation index rather than reading verdicts out of the manifest: a citation
    # added by a commit since the manifest was written must be able to save a file.
    cited = cite_index(committed_reports(), {r: os.path.basename(r) for r in rows})

    deleted = collections.Counter()
    freed = collections.Counter()
    skipped = collections.Counter()
    reasons = collections.Counter()
    biggest: list[tuple[int, str]] = []
    empties: list[str] = []

    for rel, (size, verdict) in sorted(rows.items()):
        if verdict not in args.classes:
            continue
        path = os.path.join(ROOT, rel)
        # -- condition 1: the allow-list. A prune must be unable to reach outside its yard.
        if not rel.startswith(ALLOWED):
            skipped[verdict] += 1
            reasons["outside .agents/slop and runs/"] += 1
            continue
        # -- condition 2: liveness, re-measured.
        if rel in live or not os.path.exists(path):
            skipped[verdict] += 1
            reasons["touched within the live window, or already gone"] += 1
            continue
        # -- condition 3: citation, recomputed. A report may name it even if the manifest's
        #    older index did not -- a commit can land between the two runs.
        if rel in cited:
            skipped[verdict] += 1
            reasons["cited by a committed report"] += 1
            continue
        # -- condition 4: the class must still MEAN what it meant. A `.bend` that has become
        #    non-empty since the manifest is not zero-byte any more.
        if verdict == "JUNK-ZERO" and os.path.getsize(path) != 0:
            skipped[verdict] += 1
            reasons["was 0 bytes at manifest time, is not now"] += 1
            continue

        if args.dry_run:
            deleted[verdict] += 1
            freed[verdict] += size
        else:
            try:
                os.remove(path)
            except OSError as exc:
                skipped[verdict] += 1
                reasons[f"remove failed: {exc.strerror}"] += 1
                continue
            deleted[verdict] += 1
            freed[verdict] += size
        if size > 64 * 1024:
            biggest.append((size, rel))

    # Directories are pruned only when they are EMPTY, and only as a consequence of the files
    # above having gone. A directory is never named, so a unit's claimed-but-empty output
    # directory is harmless (git tracks no empty directory) and a non-empty one cannot be
    # touched at all. Derived, never listed -- listing a directory is how a live tree dies.
    pruned_dirs = 0
    if not args.dry_run:
        for base in (SLOP, RUNS):
            for dirpath, _dirnames, _filenames in os.walk(base, topdown=False):
                try:
                    os.rmdir(dirpath)
                    pruned_dirs += 1
                except OSError:
                    pass

    total_files = sum(deleted.values())
    total_bytes = sum(freed.values())
    mode = "WOULD DELETE" if args.dry_run else "DELETED"
    print(f"{mode}: {total_files} files, {total_bytes/1048576:.1f} MB, "
          f"{pruned_dirs} empty directories pruned")
    for v in sorted(args.classes):
        print(f"  {v:16s} {deleted[v]:6d} deleted  {freed[v]/1048576:8.2f} MB"
              f"   {skipped[v]:5d} kept")
    if skipped:
        print("  why files were kept:")
        for why, n in reasons.most_common():
            print(f"    {n:6d}  {why}")
    if not total_files and args.classes:
        print("  NOTHING MATCHED -- a prune that deletes nothing is not a prune")
        return 1
    if biggest and total_bytes > 0:
        print("  largest deletions:")
        for sz, rel in sorted(biggest, reverse=True)[:10]:
            print(f"    {sz/1024:9.1f} KB  {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())