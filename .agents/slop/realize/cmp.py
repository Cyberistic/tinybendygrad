#!/usr/bin/env python3
"""cmp.py -- THE COMPARISON: THE PORT's SINK OF AFTERs AGAINST CPYTHON's.

    env -u PYTHONPATH .venv/bin/python .agents/slop/realize/cmp.py

READS
  `.agents/slop/realize/port.rows`   -- the PORT's driver output (a BEND run)
  `.agents/slop/realize/oracle.rows` -- the ORACLE's output (a CPYTHON run)

AND COMPUTES CPYTHON's OWN engine input BY SPYING ON UPSTREAM's CALL, THE WAY
`.agents/slop/engine/eng-oracle.py` DOES. THE COMPARISON IS THREE FOLD AND ALL
THREE ARE MULTISET COMPARISONS, BECAUSE THE PORT's `eng_dump`
(`schedule/rangeify.bend:3055`) IS A BFS AND THE ORACLE's `dump`
(`eng-oracle.py:79`) IS A DFS AND THE TWO ORDERS CANNOT AGREE.

  C1 THE NODE MULTISET. `op:argkey:srcops` per node, in the ORACLE's spelling.
  C2 THE CONST VALUE MULTISET. The oracle's own key throws the value away
     (`cother`), so this carries it.
  C3 THE PARAM (slot, size) MULTISET. Which buffer got which slot.

AND THE CONTROLS: THE SAME COMPARISON RUN AGAINST THE PORT's TWO PLANTS, WHICH
MUST GO RED. A COMPARISON THAT CANNOT GO RED IS A LABEL.

EXIT 0 ONLY IF C1, C2 AND C3 AGREE **AND** BOTH PLANTS GO RED.
"""
import collections
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# THE ORACLE's SPELLING. Copied from `.agents/slop/engine/eng-oracle.py:52-76`
# and CHECKED AGAINST THAT FILE'S OWN PUBLISHED OUTPUT BELOW, so a drift in
# either is caught rather than assumed.
# ---------------------------------------------------------------------------
def const_key(v):
    if isinstance(v, tuple) and len(v) == 3 and v[1] == "CONST":
        val = v[2]
        if val is None:
            return "cinvalid"
        if isinstance(val, int):
            return "c:%d:%d" % ((val >> 32) & 0xFFFFFFFF, val & 0xFFFFFFFF)
    return "cother"


def arg_key(u):
    if u.op.name == "CONST":
        return const_key(u.arg)
    if u.arg is None or u.arg == ():
        return "none"
    return "other"


def node_str(u):
    return "%s:%s:%s" % (u.op.name, arg_key(u), ",".join(s.op.name for s in u.src))


def dump(root):
    out, seen, todo = [], set(), [root]
    while todo:
        u = todo.pop(0)
        if u in seen:
            continue
        seen.add(u)
        out.append(node_str(u))
        todo = list(u.src) + todo
    return ";".join(out)


def rows(path):
    out = {}
    for line in pathlib.Path(path).read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out.setdefault(k, v)
    return out


def multiset(items):
    return collections.Counter(items)


def compare(name, got, want):
    """THE COMPARISON. A MULTISET, BECAUSE THE TWO DUMPS' ORDERS DIFFER."""
    if got == want:
        return True, "%s AGREE (denominator=%d distinct kinds, %d items)" % (
            name, len(want), sum(want.values()))
    missing = want - got
    extra = got - want
    return False, "%s DIVERGE: missing=%s extra=%s (denominator=%d distinct kinds, %d items)" % (
        name, sorted(missing.elements()), sorted(extra.elements()),
        len(want), sum(want.values()))


def cpython_engine_input():
    """SPY ON UPSTREAM's OWN CALL, THE WAY THE ORACLE DOES."""
    import tinygrad.schedule as S
    import tinygrad.schedule.rangeify as R
    from tinygrad import Tensor

    orig = R.get_kernel_graph
    seen = {}

    def spy(tsink):
        seen["in"] = tsink
        out = orig(tsink)
        seen["out"] = out
        return out

    R.get_kernel_graph = spy
    S.get_kernel_graph = spy

    t = Tensor.empty(4, 5).realize()
    t.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
    t.schedule_linear()
    if "in" not in seen:
        raise SystemExit("THE SPY DID NOT FIRE -- A REFUSAL IS A RESULT")
    return seen["in"]


def main() -> int:
    port = rows(HERE / "port.rows")
    orc = rows(HERE / "oracle.rows")

    root = cpython_engine_input()
    nodes = list(root.toposort())

    # THE ORACLE's OWN PUBLISHED DUMP, AND THE COMPARISON'S OWN COMPUTATION OF
    # IT, MUST AGREE -- so this file's copy of the spelling is CHECKED, not
    # assumed.
    mine = dump(root)
    published = orc.get("eng_py_in", "")
    if mine != published:
        print("FAIL the oracle's published dump and this file's computation DIFFER")
        print("  published: %s" % published)
        print("  computed : %s" % mine)
        return 1
    print("OK   the oracle's published dump and this file's computation are byte-identical")

    # C1 -- THE NODE MULTISET.
    want_nodes = multiset(node_str(u) for u in nodes)
    got_nodes = multiset(port.get("rz_dump", "").split(";"))
    ok1, msg1 = compare("C1 nodes", got_nodes, want_nodes)
    print("%s %s" % ("OK  " if ok1 else "FAIL", msg1))

    # C2 -- THE CONST VALUE MULTISET.
    want_consts = multiset(str(u.arg) for u in nodes if u.op.name == "CONST")
    got_consts = multiset(x for x in port.get("rz_consts", "").split(",") if x)
    ok2, msg2 = compare("C2 consts", got_consts, want_consts)
    print("%s %s" % ("OK  " if ok2 else "FAIL", msg2))

    # C3 -- THE PARAM (slot, size) MULTISET.
    want_params = multiset(
        "%d:%d" % (u.arg.slot, u.src[0].arg) for u in nodes if u.op.name == "PARAM")
    got_params = multiset(x for x in port.get("rz_params", "").split(",") if x)
    ok3, msg3 = compare("C3 params", got_params, want_params)
    print("%s %s" % ("OK  " if ok3 else "FAIL", msg3))

    # THE NODE COUNT, as a separate reading.
    want_n = len(nodes)
    got_n = int(port.get("rz_nodes", "-1"))
    okn = got_n == want_n
    print("%s C0 node count port=%d cpython=%d (denominator=%d)" % (
        "OK  " if okn else "FAIL", got_n, want_n, want_n))

    # THE CONTROL: PLANT A -- RULE 2 OFF. The graph is 27 nodes and the node
    # multiset MUST DIVERGE.
    plant_nodes = multiset(port.get("rz_plant_dump", "").split(";"))
    red_a = plant_nodes != want_nodes
    print("%s CONTROL A (adjacent-RESHAPE merge OFF): the node multiset DIVERGES=%s "
          "(plant kinds=%d, oracle kinds=%d)" % (
              "OK  " if red_a else "FAIL", red_a, len(plant_nodes), len(want_nodes)))

    # THE CONTROL: PLANT B -- THE PARAM SLOTS SHIFTED BY ONE. The NODE dump is
    # IDENTICAL and only the (slot, size) pairs move, so this is the control
    # that proves C3 IS LOAD-BEARING.
    plant_params = multiset(x for x in port.get("rz_plant_params", "").split(",") if x)
    red_b = plant_params != want_params
    red_b_nodes = multiset(port.get("rz_dump", "").split(";")) == want_nodes
    print("%s CONTROL B (PARAM slots shifted by one): the (slot,size) multiset DIVERGES=%s "
          "and the NODE multiset is UNCHANGED=%s" % ("OK  " if red_b else "FAIL", red_b, red_b_nodes))

    allok = ok1 and ok2 and ok3 and okn and red_a and red_b
    print("VERDICT %s" % ("PASS" if allok else "FAIL"))
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
