#!/usr/bin/env python3
"""digest.py -- the substrate digest, and an ATTRIBUTED delta.

    .venv/bin/python .agents/slop/constid/digest.py                 # print the live digest
    .venv/bin/python .agents/slop/constid/digest.py --attr F1 F2    # attribute the move to F1, F2

`checks/differ.py` is imported BY PATH and its pure function is called; the file is NOT
edited.  `substrate_digest()` is a sha256 over the sorted `(relpath, sha256(bytes))` pairs
of `substrate_entries()`, and `substrate_entries()` walks `tinybendygrad/` and `tinygrad/`
plus a handful of NAMED inputs.  So a file's entry can be SWAPPED in the list and the
result is bit-identical to having swapped the file on disk -- which is how a delta is
attributed to MY files rather than to whatever else the tree did while I worked.

`--attr` answers: "if MY files had not been edited, what would the digest be?"  It replaces
their entries with the sha256 of their HEAD blobs, which is what their entries were when
the baseline was taken (they were CLEAN at the baseline -- `git status --porcelain` named
neither).  If the attributed digest equals the baseline, the whole move is MINE; if it does
not, the rest of the move belongs to another unit and is reported as such.
"""
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIFFER = ROOT / "checks" / "differ.py"


def load():
    spec = importlib.util.spec_from_file_location("differ", DIFFER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def digest_of(entries):
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def head_blob(rel, base="HEAD"):
    r = subprocess.run(["git", "show", f"{base}:{rel}"], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        return "ABSENT"
    return hashlib.sha256(r.stdout).hexdigest()


def main(argv):
    differ = load()
    entries = differ.substrate_entries()
    if len(argv) >= 2 and argv[1] == "--attr":
        mine = argv[2:]
        base = "HEAD"
        if len(argv) >= 4 and argv[-2] == "--base":
            base = argv[-1]
            mine = argv[2:-2]
        live = digest_of(entries)
        reverted = dict(entries)
        for rel in mine:
            reverted[rel] = head_blob(rel, base)
        without = digest_of(list(reverted.items()))
        print(f"digest_live={live}")
        print(f"digest_without_my_edits={without}")
        print(f"base={base}")
        for rel in mine:
            print(f"entry {rel}: {base}={reverted[rel]} now={dict(entries).get(rel)}")
        return 0
    print(differ.substrate_digest())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
