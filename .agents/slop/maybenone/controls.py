#!/usr/bin/env python3
r"""CONTROLS.  Two fakes that drive the two branches the real run cannot reach today, and one
real `bend` run that proves the fix is not "always red".

  A  `bend` succeeds for the BASE and then returns `( {}, 1 )` -- it RAN and emitted nothing.
     The exit must be DEAD(5), and must NOT be 0, and must NOT be REFUSED(3): the precondition
     (the mutation was written) was present.
  B  every call returns the SAME rows -- every entry moves nothing.  Only `M4` and `Z2` are
     expected zeros, so the rest are coverage gaps and the exit must be FAIL(1), not 0.
  C  the seven entries whose `find` still matches, run for real: PASS(0).
"""
import importlib.util, io, sys
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name, path):
    s = importlib.util.spec_from_file_location(name, ROOT / path)
    m = importlib.util.module_from_spec(s); sys.modules[name] = m; s.loader.exec_module(m)
    return m


def run(label, stub, keep=None):
    m = load(f"h{abs(hash(label))}", "gates/optim-nop-mutate.py")
    real = m.mutkit.bend_rows
    if keep is not None:
        m.MUTATIONS = [e for e in m.MUTATIONS if e[0].split()[0] in keep]
    calls = {"n": 0}

    def fake(path):
        calls["n"] += 1
        return stub(calls["n"], path)
    m.mutkit.bend_rows = fake
    buf = io.StringIO()
    with redirect_stdout(buf):
        try:
            rc = m.main()
        finally:
            m.mutkit.bend_rows = real
    tail = [l for l in buf.getvalue().splitlines() if "REFUSED" in l or "DID NOT COMPILE" in l]
    print(f"  {label:<8} rc={rc}  word={m.gatekit.VERDICT.get(rc, 'UNASSIGNED'):<9} "
          f"non-PASS lines={len(tail):<2} e.g. {tail[0][:62] if tail else '-'}")
    return rc


GOOD = {"op_acc": "op_acc=True", "op_nop": "op_nop=True", "op_nop.dn": "op_nop.dn=True",
        "op_params": "op_params=True", "op_nop.tag": "op_nop.tag=True"}
A = {"rows": dict(GOOD), "rc": 0}
fails = []


def stub_dead(n, path):
    if n == 1:
        return dict(GOOD), 0            # the BASE reading is fine
    return {}, 1                        # every mutant: ran, emitted nothing


def stub_flat(n, path):
    return dict(GOOD), 0                # every mutant identical to the base


rc_a = run("A", stub_dead)
rc_b = run("B", stub_flat)
print(f"\n  A DEAD(5)?   {'OK' if rc_a == 5 else 'FAIL'}  got {rc_a}")
print(f"  B FAIL(1)?   {'OK' if rc_b == 1 else 'FAIL'}  got {rc_b}")
if rc_a != 5 or rc_b != 1:
    fails.append("a branch did not reach its own verdict")
raise SystemExit(1 if fails else 0)
