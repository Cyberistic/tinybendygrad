#!/usr/bin/env python3
"""Mutation harness for `linearizer_census-gate.py`. THE MECHANISM IS `gates/mutkit.py`.

    .venv/bin/python gates/linearizer_census-mutate.py

Each entry is `(name, upstream line, find, replace)` on `linearizer.bend`'s TEXT, applied to
a COPY beside the original -- the tree's own `linearizer.bend` is never written, because this
unit reports bugs and the caller fixes them.

EVERY ENTRY NAMES THE `linearizer.py` LINE IT BREAKS, so a moved row can be traced to the
rule it is a row for, and every entry's pattern is asserted UNIQUE before it is applied.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mutkit

MUTATIONS = [
    ("heap: the sorted heap is flipped", "linearizer.py:39-45",
     "  U32.is_ge(LtKey.k(x), LtKey.k(y))\n", "  U32.is_le(LtKey.k(x), LtKey.k(y))\n"),
    ("the heap loop's accumulator PREPENDS (the reversal)", "linearizer.py:42",
     "List.append(&2, U32, acc, [PS.v(lt_hq.step(h, srt, ar))]))",
     "List.append(&2, U32, [PS.v(lt_hq.step(h, srt, ar))], acc))"),
    ("the nkey sort is reversed", "linearizer.py:36",
     "def lt_kle(x: LtKey, y: LtKey) -> Bool:\n  U32.is_le(LtKey.k(x), LtKey.k(y))",
     "def lt_kle(x: LtKey, y: LtKey) -> Bool:\n  U32.is_ge(LtKey.k(x), LtKey.k(y))"),
    ("run_count: the product becomes a sum", "linearizer.py:20",
     "    case v <> +t : lt_rc.go(t, U32.mul(acc, U32.add(v, 1)))",
     "    case v <> +t : lt_rc.go(t, U32.add(acc, U32.add(v, 1)))"),
    ("ladder: RANGE's priority is 24 not 25", "linearizer.py:30",
     "  Bool.pick(U32, range, 25,", "  Bool.pick(U32, range, 24,"),
    ("ladder: LOAD's priority is 20 (the `case _` arm)", "linearizer.py:28",
     "  Bool.pick(U32, load, 19,", "  Bool.pick(U32, load, 20,"),
    ("ladder: PARAM's priority is 1", "linearizer.py:26",
     "  Bool.pick(U32, param, 0,", "  Bool.pick(U32, param, 1,"),
    ("ladder: LOCAL and GLOBAL swap", "linearizer.py:27",
     "  Bool.pick(U32, buf, Bool.pick(U32, local, 3, 2), 20)",
     "  Bool.pick(U32, buf, Bool.pick(U32, local, 2, 3), 20)"),
    ("deps: the self-add is dropped", "linearizer.py:69",
     "  Bool.pick(List<&2, U32>, lt_is_loopend(op), List.append(&2, U32, d, [u]), d)",
     "  Bool.pick(List<&2, U32>, lt_is_loopend(op), d, d)"),
    ("cfg: the edges are bucketed under the child", "linearizer.py:73",
     "def cfg_sib.put(+acc: RaTb, +ns: RaTb, +u: U32, +k: U32) -> RaTb:\n  tb_put(acc, u, k, [k])",
     "def cfg_sib.put(+acc: RaTb, +ns: RaTb, +u: U32, +k: U32) -> RaTb:\n  tb_put(acc, k, k, [k])"),
    ("split_ends: the descending sort becomes ascending", "linearizer.py:90",
     "  se_unkey(List.sort(Sb, sb_ge, se_key(rngs, ar, rngs)), Nil{})",
     "  se_unkey(List.sort(Sb, sb_le, se_key(rngs, ar, rngs)), Nil{})"),
    ("vms: the length prefix is not consumed", "the W1 caller's table",
     "  lt_vm.take2(List.take(&2, U32, r, n), List.drop(&2, U32, r, n))",
     "  lt_vm.take2(List.take(&2, U32, r, n), r)"),
    ("out_degree: src_without_body becomes src", "linearizer.py:17",
     "O.Arena.src_without_body(ar, u), acc, ar)", "O.Arena.srcs(ar, u), acc, ar)"),
    ("heap release: src_without_body becomes src", "linearizer.py:43",
     "  lt_hp.ss(O.Arena.src_without_body(ar, v),",
     "  lt_hp.ss(O.Arena.srcs(ar, v),"),
    ("lin_edg: src_without_body becomes src", "the EDGE-ROW printer",
     "  String.concat([U32.show(n), \":\", lt_epos(ix, ar, O.Arena.src_without_body(ar, u))])",
     "  String.concat([U32.show(n), \":\", lt_epos(ix, ar, O.Arena.srcs(ar, u))])"),
]

if __name__ == "__main__":
    sys.exit(mutkit.main(Path(__file__).resolve().parent / "linearizer_census-gate.py",
                          Path(__file__).resolve().parents[1] /
                          "tinybendygrad/codegen/late/linearizer.bend",
                          MUTATIONS))