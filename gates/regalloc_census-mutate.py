#!/usr/bin/env python3
"""Mutation harness for `regalloc_census-gate.py`. THE MECHANISM IS `gates/mutkit.py`.

    .venv/bin/python gates/regalloc_census-mutate.py

Each entry is `(name, upstream line, find, replace)` on `regalloc.bend`'s TEXT, applied to a
COPY beside the original -- the tree's own `regalloc.bend` is never written, because this unit
reports bugs and the caller fixes them.

THE TWO THAT MATTER MOST ARE THE PAIR `ra0`/`ra1` EXISTS FOR. `is_two_address` only REORDERS
`cons` (`regalloc.py:72-74`), which is invisible without a tie, so the tie in `ra*t>_a7` is
the only row in the file that can see it -- and both entries below break one half of the
reorder, so a mutation that moves nothing would mean the tie is not a tie.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mutkit

HERE = Path(__file__).resolve().parent
DRIVER = HERE.parents[0] / "tinybendygrad/codegen/late/regalloc.bend"

MUTATIONS = [
    ("two-address: the reused src is not moved first", "regalloc.py:73-74",
     "    case +r <> +t  : ra_tw.go(us, t, Bool.pick(List<&2, U32>, u32_in(us, r), pre,\n"
     "                                              List.append(&2, U32, pre, [r])))",
     "    case +r <> +t  : ra_tw.go(us, t, Bool.pick(List<&2, U32>, False{}, pre,\n"
     "                                              List.append(&2, U32, pre, [r])))"),
    ("two-address: the reused src is APPENDED, not prepended", "regalloc.py:73-74",
     "def ra_tw.pre(+hd: U32, cs: List<&2, U32>) -> List<&2, U32>:\n"
     "  Bool.pick(List<&2, U32>, Bool.and(U32.is_ne(hd, LT.u32_none()), u32_in(cs, hd)), [hd], Nil{})",
     "def ra_tw.pre(+hd: U32, cs: List<&2, U32>) -> List<&2, U32>:\n"
     "  Bool.pick(List<&2, U32>, Bool.and(U32.is_ne(hd, LT.u32_none()), u32_in(cs, hd)), Nil{}, [hd])"),
    ("alloc: the i+1 for a non-RANGE def becomes i", "regalloc.py:76",
     "  Bool.pick(U32, LT.lt_is_range(op), i, U32.add(i, 1))",
     "  Bool.pick(U32, LT.lt_is_range(op), i, i)"),
    ("live range: the backward walk becomes forward", "regalloc.py:22",
     "  ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 0)",
     "  ra_run.go(ops, ra_lr.go(ops, U32.sub(ra_nm(s), 1), s), 0)"),
    ("loops: the RANGE's last use is the FIRST use", "regalloc.py:29",
     "                        Bool.pick(List<&2, U32>, u32_in(RaUop.ss(u), k), i, best))",
     "                        Bool.pick(List<&2, U32>, U32.is_eq(i, k), i, best))"),
    ("the END/BACKEDGE use-skip is dropped", "regalloc.py:60",
     "  match ex:\n    case True{} : s\n    case False{}: ra_uses.go(ss, i, s, ops)",
     "  match ex:\n    case True{} : ra_uses.go(ss, i, s, ops)\n    case False{}: ra_uses.go(ss, i, s, ops)"),
    ("rewrite: the tag spills are dropped", "regalloc.py:112",
     "    case +v <> +r  : rw_aft.go(s, r,\n"
     "                     Bool.pick(List<&2, Em>, U32.is_ne(LT.tb_get(RaSt.sp(s), v), 0),\n"
     "                               List.append(&2, Em, acc,\n"
     "                                           [Em{O.OpsCUSTOM{}, rw_spillarg(ra_slot(RaSt.un(s), v))}]),\n"
     "                               acc))",
     "    case +v <> +r  : rw_aft.go(s, r, acc)"),
    ("rewrite: the insert_before fills are dropped", "regalloc.py:111",
     "def rw_before(+s: RaSt, +i: U32) -> List<&2, Em>:\n"
     "  rw_bef.go(s, i, LT.tb_vs(RaSt.ib(s), i), Nil{})",
     "def rw_before(+s: RaSt, +i: U32) -> List<&2, Em>:\n"
     "  Bool.pick(List<&2, Em>, U32.is_zero(i), Nil{}, Nil{})"),
    ("PSEUDO_OPS: BARRIER is dropped", "regalloc.py:8",
     "  [O.PMEntry{0, [O.OpsCONST{}, O.OpsCAST{}, O.OpsBITCAST{}, O.OpsNOOP{},",
     "  [O.PMEntry{0, [O.OpsCONST{}, O.OpsCAST{}, O.OpsBITCAST{},"),
]

if __name__ == "__main__":
    sys.exit(mutkit.main(HERE / "regalloc_census-gate.py", DRIVER, MUTATIONS))