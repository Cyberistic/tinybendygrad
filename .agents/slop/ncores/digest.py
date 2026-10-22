#!/usr/bin/env python3
"""The digest, and the attribution: what MY change moved, on a MOVING tree.

    .venv/bin/python .agents/slop/ncores/digest.py

`checks/differ.py:substrate_digest()` is a pure function of the tree's bytes. The
tree is MOVING under several units, so the interesting number is not "the digest
before" versus "the digest after" -- those two differ by other units' edits too.
The interesting number is the SAME tree with MY change reverted, which is what this
computes, WITHOUT writing to the tree: the digest is a sha256 over the sorted
`(relpath, sha256(bytes))` pairs, so a file's entry can be swapped in the list and
the result is bit-identical to having swapped the file on disk.
"""
import hashlib
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
spec = importlib.util.spec_from_file_location("d", ROOT / "checks/differ.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

PORT_REL = "tinybendygrad/runtime/ops_python.bend"

# MY CHANGE, REVERSED: the three edits, as (new, old) pairs.
EDITS = [
    # 1. the count: 7 back to 4, and the comment that records WHY it is 7.
    ("""# `CORES_AMD_RDNA4()` IS SEVEN. It was FOUR until the re-vendor of `tinygrad/` to
# upstream `002630241` (2026-10-16) added three (di,do) pairs to `tc.py`'s
# `amd_rdna4` -- fp8e4m3/float, fp8e5m2/float and int8/int32 (tc.py:80-81) -- and
# the port's `4` was a transcription of the OLD table's length. A transcribed
# LENGTH is a pin on a file that can move, so this ladder is re-derived against
# `tc.py` on every run by `cores_axis_hold()` in
# `gates/ops_python_census-gate.py`: a count that no longer matches its table is a
# red run naming the table and the two numbers, not a row that quietly disagrees.
def cores_of(+tid: U32) -> U32:
  Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 0,
    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,
    Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA3()), 4,
      Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA3()), 4,
        Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA4()), 8,
          Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA4()), 7,""",
     """def cores_of(+tid: U32) -> U32:
  Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 0,
    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,
    Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA3()), 4,
      Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA3()), 4,
        Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA4()), 8,
          Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA4()), 4,"""),
    # 2. the tid comment's false claim.
    ("""    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores, so
    # a count cannot tell those two apart. `Rend.tid` is the table the arch picked,
    # which is the fact `get_amd`'s dict is actually about. (amd_rdna4 is SEVEN, so
    # it is distinguishable by length too -- but the tid row is still the TABLE and
    # the count row is still the COUNT, and they are different facts about it.)""",
     """    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores and
    # amd_rdna4 also has 4 -- so three different tables answer 4 and a count cannot
    # tell them apart. `Rend.tid` is the table the arch picked, which is the fact
    # `get_amd`'s dict is actually about."""),
    # 3. the tc.py line cite, which moved with the re-vendor.
    ("# `tc.get_amd(arch)` (tc.py:99) is a FOUR-KEY dict whose DEFAULT is amd_rdna3, so",
     "# `tc.get_amd(arch)` (tc.py:98) is a FOUR-KEY dict whose DEFAULT is amd_rdna3, so"),
]


def sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def digest_of(entries) -> str:
    """`substrate_digest()` over a GIVEN list -- the same function, same bytes."""
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def main() -> int:
    live = (ROOT / PORT_REL).read_text()
    without = live
    for new, old in EDITS:
        if new not in without:
            print(f"REFUSED: the edit to reverse is not in the port any more:\n{new[:120]}",
                  file=sys.stderr)
            return 3
        without = without.replace(new, old, 1)
    entries = d.substrate_entries()
    idx = [i for i, (rel, _) in enumerate(entries) if rel == PORT_REL]
    if not idx:
        print(f"REFUSED: {PORT_REL} is not in the substrate's population", file=sys.stderr)
        return 3
    i = idx[0]
    before_entries = list(entries)
    before_entries[i] = (PORT_REL, sha(without))
    after = digest_of(entries)
    before = digest_of(before_entries)
    print(f"substrate_head            = {d.substrate_head()}")
    print(f"digest AFTER  (my change) = {after}")
    print(f"digest BEFORE (mine reverted, same tree, same instant) = {before}")
    print(f"ATTRIBUTED DELTA           = {'MOVED' if after != before else 'UNCHANGED'}")
    print(f"the port's blob  after    = {sha(live)}")
    print(f"the port's blob  reverted = {sha(without)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
