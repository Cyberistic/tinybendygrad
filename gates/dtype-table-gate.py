#!/usr/bin/env python3
"""dtype-table-gate.py -- are `dtype.bend`'s OP GROUPS CPython's `GroupOp` members?

    .venv/bin/python gates/dtype-table-gate.py

WHY THIS AND NOT THE RULE TABLE. `gates/symbolic-table-gate.py` can project a table row
because `symbolic.bend` transcribes CPython's patterns one for one. `dtype.bend` does not:

  * `l2i_pair` (dtype.py:89) is `UPat(Ops.BITCAST, src=(UPat(Ops.STACK, src=(x,)),))`, so SIX
    of `pm_long_decomp`'s ten patterns CLAIM `BITCAST` while the port's corresponding rows
    claim the INNER op (`LOAD`, `CAST`, the elementwise set). Projecting `p.op` reports six
    rules with "no port row inside" that are not missing -- they are shaped differently.
  * the float rows are REORDERED, and one MERGES upstream's catch-all with `{BITCAST}`.

A correspondence the port does not record cannot be checked, and a gate that guessed one
would report six false failures and be ignored within a week. What DOES hold is the op
GROUPS: the port spells `GroupOp.All` as `dd_ops.all()` and `GroupOp.Defines` as a literal
list, so both are directly comparable to CPython's own declaration.

THE THREE ROWS, AND WHY EACH IS A ROW RATHER THAN A FIXED LIST: the population is CPython's
`GroupOp`, discovered; the port side is parsed out of `dtype.bend`. Nothing is typed.

WHAT THE FIRST RUN FOUND (2026-11-25), BOTH FIXED HERE: `dd_ops.all()` was 75 of
`GroupOp.All`'s 76 (no `REFPARAM`), and `pm_long_decomp`'s `GroupOp.Defines` row was
`{ALLOC, BUFFER, PARAM}` of five (no `BINARY`, no `REFPARAM`). A node at a long dtype that
was a `REFPARAM`, or a defining `BINARY`, was a node the decomposition never saw.
`dd_ops.cmp()` already matched `GroupOp.Comparison` exactly.

NOT PART OF THE CLAIM, AND PRINTED SO THAT IS VISIBLE: the rule tables themselves. This gate
says nothing about whether `pm_long_decomp`'s thirteen rows rewrite what CPython's ten rewrite.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pmtable  # noqa: E402  (the parser, shared with the symbolic gate)
from gatekit import DEAD, FAIL, PASS  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
PORT = ROOT / "tinybendygrad/codegen/decomp/dtype.bend"


def flat_src(p) -> list:
    """`UPat.src` nests tuples (`[(UPat,)]`), so the patterns inside need unwrapping."""
    out: list = []

    def go(x):
        if isinstance(x, (tuple, list)):
            for y in x:
                go(y)
        elif hasattr(x, "op"):
            out.append(x)
    go(p.src or [])
    return out


def pair_wrapped(p) -> bool:
    """`l2i_pair`'s shape: a BITCAST whose single src is a STACK. Discovered, not listed."""
    return (p.op and frozenset(o.name for o in p.op) == {"BITCAST"}
            and len(flat_src(p)) == 1 and flat_src(p)[0].op
            and frozenset(o.name for o in flat_src(p)[0].op) == {"STACK"})


def main() -> int:
    text = PORT.read_text()
    mac = pmtable.macros(text)
    if not mac:
        print("== DEAD: dtype-table-gate: no op-set macro parsed -- every group would read as an "
              "empty set and agree with nothing")
        return DEAD

    from tinygrad.uop import GroupOp
    import tinygrad.codegen.decomp.dtype as d

    rows = []
    # Two named helpers, one literal row, all comparable to a declared `GroupOp` member.
    for label, got, gname in (("dd_ops.all()", mac.get("dd_ops.all"), "All"),
                              ("dd_ops.cmp()", mac.get("dd_ops.cmp"), "Comparison")):
        rows.append((label, got, frozenset(o.name for o in getattr(GroupOp, gname)), gname))
    tag1 = {t: o for t, o, _ in pmtable.table(text, "pm_long_decomp")}.get(1)
    if tag1:
        rows.append(("pm_long_decomp row 1", pmtable.opnames(tag1, mac),
                     frozenset(o.name for o in GroupOp.Defines), "Defines"))

    bad = 0
    for label, got, want, gname in rows:
        if got is None:
            print(f"== DEAD: dtype-table-gate: `{label}` not found in the file")
            return DEAD
        miss, extra = sorted(want - got), sorted(got - want)
        status = "OK" if not miss and not extra else "DIFFERS"
        print(f"group.{gname:12} {label:24} port={len(got):2} up={len(want):2} "
              f"missing={miss} extra={extra}  {status}")
        bad += bool(miss or extra)

    wrapped = sum(pair_wrapped(p) for p, _ in d.pm_long_decomp.patterns)
    print(f"rules: NOT-PROJECTABLE -- {wrapped}/{len(d.pm_long_decomp.patterns)} long patterns "
          f"are `l2i_pair` wrappers whose claimed op is BITCAST and whose rule is the inner op; "
          f"the float rows are reordered and one merges the catch-all. Not part of this claim.")

    if bad:
        print(f"== FAIL: dtype-table-gate: {bad} op group(s) differ from CPython's GroupOp")
        return FAIL
    print("== PASS: dtype-table-gate: every named op group equals CPython's GroupOp expansion")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
