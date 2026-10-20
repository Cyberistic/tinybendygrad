#!/usr/bin/env python3
"""THROWAWAY: the substrate digest, before and after the dtype.js edit.

`checks/differ.py`'s own `substrate_digest()` over the LIVE tree gives the digest as it
is now.  The "before" is the SAME walk with ONE file's blob taken from `git show HEAD:`
-- so the movement attributed to this edit is a derivation, not a second implementation
of the digest, and the tree is never modified to produce it.
"""
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "checks"))
import differ  # noqa: E402

REL = "tinybendygrad/runtime/dtype.js"


def digest_with(overrides: dict[str, bytes]) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(differ.substrate_entries()):
        if rel in overrides:
            blob = hashlib.sha256(overrides[rel]).hexdigest()
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


live = differ.substrate_digest()
head_bytes = subprocess.run(["git", "show", f"HEAD:{REL}"], cwd=ROOT,
                            capture_output=True, check=True).stdout
work_bytes = (ROOT / REL).read_bytes()
before = digest_with({REL: head_bytes})
print(f"substrate digest LIVE (after the edit) : {live}")
print(f"substrate digest with {REL} at HEAD   : {before}")
print(f"moved by this edit                     : {live != before}")
print(f"  {REL} sha256 HEAD   = {hashlib.sha256(head_bytes).hexdigest()}")
print(f"  {REL} sha256 work   = {hashlib.sha256(work_bytes).hexdigest()}")
print(f"  declared inputs: {len(differ.substrate_entries())} entries")
