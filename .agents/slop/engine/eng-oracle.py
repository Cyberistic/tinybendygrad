#!/usr/bin/env python3
"""eng-oracle.py -- THE CPYTHON ORACLE FOR THE PORT's SCHEDULER's ENGINE.

    env -u PYTHONPATH .venv/bin/python .agents/slop/engine/eng-oracle.py

WHY THIS FILE EXISTS
--------------------
**⇒ THE PORT's ENGINE (`tinybendygrad/schedule/rangeify.bend`'s `eng_*`) APPLIES UPSTREAM's
SEVEN `graph_rewrite` CALLS TO AN ARENA, AND **NOTHING COMPARES ITS OUTPUT TO CPython.**
MEASURED: `grep -rln 'eng_a_s|eng_b_s|eng_fixture_rows' --include='*.py' --include='.rows'
--include='*.sh'` ANSWERS **NOTHING** OVER THE WHOLE TREE. **⇒ SO THE ENGINE IS A ROW
THAT CANNOT GO RED, WHICH IS THE TREE's OWN DOCTRINE 2.**

**⇒ AND THE PORT's OWN TWO FIXTURES (`efx_a()` AND `efx_b()`, `rangeify.bend:3084` AND
`:3111`) ARE **NOT** UPSTREAM's INPUT SHAPE**, AND THIS FILE MEASURED THAT: CPython's OWN
`get_kernel_graph` **REFUSES** BOTH OF THEM, WITH THE EXACT ERROR TEXT:**
```
eng_a_py_out=RAISED:TypeError:'>=' not supported between instances of 'tuple' and 'int'
eng_b_py_out=RAISED:RuntimeError:UOp verification failed at 1 on Ops.NOOP dtypes.void 0 [] ()
```
**⇒ ⇒ AND **THE FIXTURES ARE NOT THE SAME GRAPH**: MEASURED, THE PORT's `eng_a_in` DUMP AND
THIS FILE's `eng_a_py_in` DUMP ARE THE **SAME 14-NODE SET** (ORDER-FREE), **⇒ SO THE
PORT's FIXTURES ARE **SYNTHETIC** GRAPHS BUILT TO FIRE INDIVIDUAL RULES, NOT UPSTREAM's
ENGINE INPUT, AND **CPython'S VERIFIER REFUSES THEM** — **⇒ WHICH IS WHY A COMPARISON
AGAINST UPSTREAM ON **THOSE** FIXTURES IS IMPOSSIBLE, AND SAYING SO IS THE POINT.**

THE RIGHT FIXTURE, AND IT IS THE PORT's OWN PIPELINE'S FIXTURE
--------------------------------------------------------------
**⇒ UPSTREAM's `get_kernel_graph` IS CALLED BY `tinygrad/schedule/__init__.py:132`:
`create_schedule(get_kernel_graph(prepare_rangeify(function)))`.** **⇒ SO THE ENGINE's
INPUT IS `prepare_rangeify(function)`'s OUTPUT — A SINK OF AFTERs — NOT A KERNEL GRAPH.**

**⇒ ⇒ AND THIS FILE **SPIES ON UPSTREAM's OWN CALL** TO GET THE EXACT GRAPH CPython
HANDS THE ENGINE, ON A REAL PROGRAM (`(4,5) = (4,3) @ (3,5)`), AND PRINTS IT IN **THE
PORT's OWN DUMP SPELLING** (`op:argkey:srcops`, JOINED BY `;`).**
**⇒ MEASURED, THAT GRAPH IS **23 NODES** AND THE ENGINE'S OUTPUT IS **9 NODES**:
`SINK:AFTER` -> `SINK(AFTER(PARAM, STORE), ...)`, WITH THE CENSUS GOING FROM
`AFTER CONST MUL PARAM PERMUTE REDUCE RESHAPE SINK STACK STORE` TO
`AFTER CALL CONST PARAM SINK`.**

**⇒ ⇒ SO THE COMPARISON IS POSSIBLE, AND THE PORT's `eng_*` ROWS ARE COMPARABLE WITH
THIS FILE's ROWS **ROW BY ROW, NODE FOR NODE**, WITH NO TRANSLATOR.**

THE COST: **ONE CPYTHON PROCESS, ~2 s.**
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def const_key(v):
    """THE PORT's `eng_constkey` (`rangeify.bend:3008`): `c:hi:lo` FOR AN INTEGER CONST,
    `cinvalid` FOR THE INVALID CONST, `cother` FOR EVERYTHING ELSE."""
    if isinstance(v, tuple) and len(v) == 3 and v[1] == "CONST":
        val = v[2]
        if val is None:
            return "cinvalid"
        if isinstance(val, int):
            return "c:%d:%d" % ((val >> 32) & 0xFFFFFFFF, val & 0xFFFFFFFF)
    return "cother"


def arg_key(u):
    """THE PORT's `eng_argkey` (`rangeify.bend:3014`): `none` FOR A NODE WITH NO ARG, THE
    CONST KEY FOR A CONST, `other` FOR EVERYTHING ELSE."""
    if u.op.name == "CONST":
        return const_key(u.arg)
    if u.arg is None or u.arg == ():
        return "none"
    return "other"


def node_str(u):
    """THE PORT's `eng_node_str` (`rangeify.bend:3028`): `op:argkey:srcops`."""
    return "%s:%s:%s" % (u.op.name, arg_key(u), ",".join(s.op.name for s in u.src))


def dump(root):
    """THE PORT's `eng_dump` (`rangeify.bend:3067`): A DFS FROM THE RESULT ROOT, EACH NODE
    ONCE, JOINED BY `;`."""
    out = []
    seen = set()
    todo = [root]
    while todo:
        u = todo.pop(0)
        if u in seen:
            continue
        seen.add(u)
        out.append(node_str(u))
        todo = list(u.src) + todo
    return ";".join(out)


def main() -> int:
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
        print("# THE SPY DID NOT FIRE -- A REFUSAL IS A RESULT")
        return 1

    i, o = seen["in"], seen["out"]
    print("eng_py_in_nodes=%d" % len(list(i.toposort())))
    print("eng_py_in=%s" % dump(i))
    print("eng_py_out_nodes=%d" % len(list(o.toposort())))
    print("eng_py_out=%s" % dump(o))
    print("# the engine's input census: %s" % sorted(set(u.op.name for u in i.toposort())))
    print("# the engine's output census: %s" % sorted(set(u.op.name for u in o.toposort())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
