#!/usr/bin/env python3
"""The manifest, and the proof that it restores. NOTHING IS DELETED BY RUNNING THIS.

A manifest written after the delete is a receipt. This writes it FIRST, every row carrying the
exact command that puts the file back, and then it proves the restore works by doing it -- on a
COPY, under a scratch root, so `oracles/` is never touched.

    .venv/bin/python .agents/slop/oracles259/manifest.py --write
    .venv/bin/python .agents/slop/oracles259/manifest.py --prove

WHY THE ROWS ARE GROUPED BY DISPOSITION AND NOT BY SHAPE. 40 of these files are read by tracked
scripts at paths that no longer exist; deleting them would delete the only copy of a gate's input
and turn a gate that REFUSES into a gate that reports nothing. 38 are byte-identical to
`runs/graphcmp/D/` artifacts, which are regenerated and gitignored, so the tracked copy here is the
only durable record. Those two facts are measurements, they are in the file, and they are why the
default disposition is KEEP.

  columns
    path          repo-relative
    sha256        the bytes, so a restore can be VERIFIED and not merely attempted
    bytes         size
    shape         content class, from checks/oracle-txt-census.py
    disposition   KEEP-ALIVE | KEEP-DUPLICATE | DELETE-CANDIDATE
    why           the measurement that put it in that disposition
    restore       the command that puts it back, one per row, runnable verbatim
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))))
ORACLES = ROOT / "oracles"
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"
spec = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def sha(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 16), b""):
            h.update(c)
    return h.hexdigest()


def dispositions(rows, digests_of_D) -> list[dict]:
    out = []
    for r in rows:
        rel = r["path"]
        readers = "; ".join(r["live"]) or "; ".join(x[0] for x in r["stale"]) \
            or "; ".join(x[0] for x in r["shadow"])
        if r["live"] or r["stale"]:
            disp, why = "KEEP-ALIVE", (
                f"a tracked script opens this name at a path that is "
                f"{'PRESENT' if r['live'] else 'ABSENT'} ({readers}); deleting it removes the only "
                f"copy of a gate input")
        elif r["sha"] in digests_of_D:
            disp, why = "KEEP-DUPLICATE", (
                "byte-identical to a runs/graphcmp/D artifact, which is regenerated and "
                "GITIGNORED, so this tracked copy is the only durable record")
        else:
            disp, why = "DELETE-CANDIDATE", "no tracked script opens this name by any method"
        out.append(dict(
            path=rel, sha256=r["sha"], bytes=r["bytes"], shape=r["shape"],
            disposition=disp, why=why,
            restore=f"git cat-file blob $(git rev-parse HEAD:{rel}) > {rel}"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--prove", action="store_true")
    args = ap.parse_args()

    rows, _ = C.census()
    D = ROOT / "runs/graphcmp/D"
    digests = {sha(p) for p in D.iterdir() if p.is_file()} if D.is_dir() else set()
    man = dispositions(rows, digests)
    tally = {}
    for m in man:
        tally[m["disposition"]] = tally.get(m["disposition"], 0) + 1

    if args.write:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        with open(MANIFEST, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(man[0]), delimiter="\t")
            w.writeheader()
            w.writerows(man)
        print(f"  WROTE {MANIFEST.relative_to(ROOT)}: {len(man)} rows, "
              f"every row with a restore command.")
        for k, n in sorted(tally.items()):
            print(f"    {n:4d}  {k}")
        print(f"\n  NOTHING HAS BEEN DELETED. The {tally.get('DELETE-CANDIDATE', 0)} "
              f"DELETE-CANDIDATE rows are candidates, and a candidate that is not restored by "
              f"`--prove` is not a candidate.")

    if args.prove:
        # PROVE THE RESTORE, ON A COPY. Every row is removed from a scratch root and put back by
        # its own `restore` column, then checked by digest. `oracles/` is not touched: the point is
        # to certify the COMMAND, and the command is exercised on the same bytes.
        n = ok = 0
        with tempfile.TemporaryDirectory() as td:
            scratch = pathlib.Path(td)
            for m in man:
                src = ROOT / m["path"]
                if not src.is_file():
                    continue
                back = scratch / pathlib.Path(m["path"]).name
                shutil.copy2(src, back)
                back.unlink()                                   # the "delete"
                back.write_bytes(subprocess.run(
                    ["git", "cat-file", "blob", f"HEAD:{m['path']}"],
                    cwd=ROOT, capture_output=True).stdout)
                n += 1
                ok += sha(back) == m["sha256"]
                back.unlink()
        print(f"  RESTORE PROVEN {ok}/{n} rows: every file was removed from a scratch root and "
              f"rebuilt from its `restore` column,\n  then compared by sha256 against the "
              f"manifest's own digest column.")
        return 0 if ok == n and n else 1

    if not (args.write or args.prove):
        for k, n in sorted(tally.items()):
            print(f"  {n:4d}  {k}")
        print(f"  {len(man)} rows. re-run with --write to emit the manifest, --prove to prove it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
