#!/usr/bin/env python3
"""PROVE `declared()`'s size is DERIVED, not typed: plant a smaller set and show it MOVES.

The fix removes the literal from the comment and defers to `declared()`. A number that a
reader can trust is one that is recomputed, so this edits `differ.py` in place, re-reads the
size, and restores the exact original bytes -- asserting the restore by sha256, because an
unreverted plant is a worse lie than the stale number it replaced.
"""
import hashlib
import importlib.util
import os

DIFFER = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))), "checks", "differ.py")


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def size() -> int:
    spec = importlib.util.spec_from_file_location("differ_plant", DIFFER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return len(mod.declared())


def main() -> int:
    orig = open(DIFFER, "rb").read()
    print(f"HASH before plant : {sha(orig)}")
    print(f"len(declared())   : {size()}")
    # PLANT: the run sees four fewer graphs, so `declared()` must lose 4*4 names.
    planted = orig.replace(b"    graphs = corpus()\n", b"    graphs = corpus()[:30]\n")
    assert planted != orig, "plant did not apply -- the anchor moved"
    try:
        open(DIFFER, "wb").write(planted)
        print(f"PLANTED (corpus[:30]) len(declared()): {size()}")
    finally:
        open(DIFFER, "wb").write(orig)
    print(f"HASH after revert : {sha(open(DIFFER, 'rb').read())} "
          f"({'RESTORED' if open(DIFFER, 'rb').read() == orig else 'MISMATCH'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
