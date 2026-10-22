#!/usr/bin/env python3
"""apply_edits.py -- HEAD's bytes of the port, PLUS the ncores fix, and NOTHING else.

    .venv/bin/python .agents/slop/ncores/apply_edits.py <in> <out>

WHY THIS EXISTS. Another unit was editing `tinybendygrad/runtime/ops_python.bend` at
the same time, so the WORKING TREE's copy of that file is not mine to commit: it
carries their in-flight work too, and it does not compile. So the bytes this
commit carries are computed from `git show HEAD:<path>` -- the tree's own committed
state -- with the ncores fix applied on top, and every edit is ASSERTED to have
applied exactly once. A file that cannot be produced this way is not committed.

The three edits are the whole of the fix:
  1. `cores_of`'s rdna4 count, 4 -> 7, and the comment that records why.
  2. the `*_tid` comment's false claim ("amd_rdna4 also has 4").
  3. the `tc.py:98` cite, which the re-vendor moved to `tc.py:99`.
"""
import sys
from pathlib import Path

EDITS = [
    # 1. THE COUNT, AND WHY IT IS SEVEN.
    ("""# The counts, read out of `tc.py`'s five tables by the oracle. `CORES_CUDA_SM89`
# is the answer for sm_89 AND sm_90 because get_cuda is a ladder, not a table.
# `CORES_NONE()` NEEDS ITS OWN ARM. The first revision of this function had eight
# `is_eq` tests and no NONE arm, so `cores_of(CORES_NONE())` fell off the end and
# answered 8 -- the SM89 count. The `pyr_sm_74_ncores` row is what caught it:
# `tc.get_cuda("sm_74")` is `[]`, so CPython says 0 and the port said 8. A ladder
# that can return "nothing" needs "nothing" spelled, or its bottom value is the
# last value you wrote down.
def cores_of(+tid: U32) -> U32:
  Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 0,
    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,
    Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA3()), 4,
      Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA3()), 4,
        Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA4()), 8,
          Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA4()), 4,""",
     """# The counts, read out of `tc.py`'s tables: `len()` of the LIST each arch selects.
# NOT a count of compute units, and NOT a count of the card's SIMDs -- `tc.py` builds
# one `TensorCore` per (dtype_in, dtype_out) pair, so a table's length is how many
# PAIRS it holds. `CORES_CUDA_SM89` is the answer for sm_89 AND sm_90 because get_cuda
# is a ladder, not a table.
# `CORES_NONE()` NEEDS ITS OWN ARM. The first revision of this function had eight
# `is_eq` tests and no NONE arm, so `cores_of(CORES_NONE())` fell off the end and
# answered 8 -- the SM89 count. The `pyr_sm_74_ncores` row is what caught it:
# `tc.get_cuda("sm_74")` is `[]`, so CPython says 0 and the port said 8. A ladder
# that can return "nothing" needs "nothing" spelled, or its bottom value is the
# last value you wrote down.
#
# `CORES_AMD_RDNA4()` IS SEVEN. It was FOUR until the re-vendor of `tinygrad/` to
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
          Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA4()), 7,"""),
    # 2. THE FALSE CLAIM IN THE `*_tid` COMMENT.
    ("""    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores and
    # amd_rdna4 also has 4 -- so three different tables answer 4 and a count cannot
    # tell them apart. `Rend.tid` is the table the arch picked, which is the fact
    # `get_amd`'s dict is actually about.""",
     """    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores, so
    # a count cannot tell those two apart. `Rend.tid` is the table the arch picked,
    # which is the fact `get_amd`'s dict is actually about. (amd_rdna4 is SEVEN, so
    # it is distinguishable by length too -- but the tid row is still the TABLE and
    # the count row is still the COUNT, and they are different facts about it.)"""),
    # 3. THE tc.py CITE, WHICH THE RE-VENDOR MOVED BY ONE LINE.
    ("# `tc.get_amd(arch)` (tc.py:98) is a FOUR-KEY dict whose DEFAULT is amd_rdna3, so",
     "# `tc.get_amd(arch)` (tc.py:99) is a FOUR-KEY dict whose DEFAULT is amd_rdna3, so"),
]


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: apply_edits.py <in> <out>", file=sys.stderr)
        return 2
    text = Path(sys.argv[1]).read_text()
    for i, (old, new) in enumerate(EDITS, 1):
        n = text.count(old)
        if n != 1:
            print(f"REFUSED: edit {i} matches {n} times, expected 1 -- the base is not "
                  f"the file this fix was written against", file=sys.stderr)
            return 3
        text = text.replace(old, new, 1)
    Path(sys.argv[2]).write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
