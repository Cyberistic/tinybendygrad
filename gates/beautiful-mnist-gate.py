#!/usr/bin/env python3
"""beautiful-mnist-gate.py -- the Python gate for `examples/beautiful_mnist.bend`.

    .venv/bin/python gates/beautiful-mnist-gate.py

WHAT IT GATES, AND THE DENOMINATOR THE VERDICT TRAVELS WITH.

    36 rows, THREE LANES, and the DENOMINATOR IS 30.
      py    CPython, `.agents/slop/beautiful-mnist-gate.py`   -- 30 rows
      bd    the port, interpreted, `./bin/bend examples/beautiful_mnist.bend` -- 36 rows
      bn    the port, NATIVE, `bend -o` then run                              -- 36 rows
    30 rows are COMPARED byte for byte across all three lanes, and 6 are PORT-ONLY -- the two
    `row_round_*` rows, `unverified_lin2`, `unverified_adam`, `unverified_arange_dims` and
    `unverified_step` -- excluded BY NAME on both sides, with the oracle's ABSENCE of them
    asserted. Name, not position: a positional filter drops whatever row happens to sit sixth
    today and compares something else tomorrow.

    THE SIX ARE NOT NOISE, and the oracle's own docstring says so for four of them:
      row_round_2.3456, row_round_2.30   measure `H.f32_fixed`'s TRUNCATING `%.2f`, a defect in
                                          `tinybendygrad/helpers.bend` that only the Bend lane
                                          can answer. Both print False.
      unverified_lin2      the 2-D `dot` graph, wrong on the port because `uop/fold.bend`
                           defers PERMUTE's dtype.
      unverified_adam      `nn.optim.Adam` == `LAMB(adam=True)`; `nn/optim.bend`'s own row is
                           RED, 1 node against CPython's 49.
      unverified_arange_dims  prints EMPTY on purpose -- `mxw_dims_of` answers the EMPTY LIST
                           because `op_arange` puts a `U1` quantiser in its pad's shape arg.
                           An empty value IS the measurement.
      unverified_step      `mn_step` itself. CPython cannot answer it at all: the port takes `y`
                           as a parameter and CPython builds it from `arange`, so the graphs
                           differ from the first node. The row exists because `mn_step` was the
                           file's largest blind spot -- NOTHING called it, so the whole closure
                           behind it was invisible to this gate.

EXIT STATUS: 0 identical · 1 a lane took the wrong row count, the oracle failed, the native
compile failed, or the lanes disagree · 2 the frozen oracle moved. **A COLD DRIVER IS REPORTED,
NOT GATED ON**, and that is `warm="report"` and it is THE SHELL'S, not a convenience:
`beautiful-mnist-gate.sh:29` runs `--check-only || true` and its header at line 20 says it
"does NOT gate on that line", because "the failure this lane exists to catch is a SYNTAX or a
PROOF error, which the message names". `mixin-op-gate.py` ported the OTHER shell, which ran the
same command bare under `set -e` and aborted. Same instrument, opposite verdict, because the two
shells disagreed -- and a port that picked one of them silently would have been a verdict change.

IT IS THE PORT OF `.agents/slop/beautiful-mnist-gate.sh`, under the rule that THE PYTHON
REPRODUCES THE SHELL'S VERDICT ON EVERY INPUT OR IT DOES NOT MOVE. The shell body is frozen
verbatim at `gates/oracles/beautiful-mnist-oracle.sh` and is still runnable; its sha256 is in
ORACLE_PIN and is CHECKED IN CODE on every run, because a pin in a comment is a pin that cannot
fail. MEASURED over 8 input sets, shell and Python: verdict and exit status agree on all 8.

WHAT MOVED AND WHAT DID NOT. Lane files went from `/tmp/bmn.{py,bd,bn}` to
`gates/artifacts/beautiful-mnist-gate/`, because `.agents/slop/` is being pruned. The bound is
NOT changed, for the reason `mixin-op-gate.py` states in full: the shell bounded nothing here,
`checks/bounded.py` returns 3 for a memory kill and 4 for a timeout, and neither is a status
these lanes produce -- so a bound is a verdict, not a safety improvement. MEASURED peak RSS for
the whole shell run: 1,531 MB. TODO(GXR-12): bound at 2048 MB or not at all.

ONE BEND AT A TIME, for the reason in `mixin-op-gate.py`: `sz.bend` peaks at 1,468 MB and two of
those concurrently took this machine's memory to zero on 2026-10-05.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, oracle_drift, VERDICT

ORACLE_PIN = {
    "gates/oracles/beautiful-mnist-oracle.sh":
        "d4243578cca6053fb2b9af56631475439db3dd4c81886880be39808425d06ada",
}

GATE = Gate(
    "beautiful-mnist-gate",
    bend="examples/beautiful_mnist.bend",
    oracle=".agents/slop/beautiful-mnist-gate.py",
    rows=36,
    compared=30,
    warm="report",
    port_only=["row_round_2.3456", "row_round_2.30", "unverified_lin2", "unverified_adam",
               "unverified_arange_dims", "unverified_step"],
)

if __name__ == "__main__":
    if bad := oracle_drift(ORACLE_PIN):
        for line in bad:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_PIN -- do not delete "
              "the pin.", file=sys.stderr)
        sys.exit(2)
    code = GATE.run()
    ok = code == 0
    # THE SHELL'S OWN LINES. `|| true` lets `--check-only`'s stdout through to the reader
    # whatever it says, so this prints it either way rather than only when the gate is green.
    print(GATE.warm_out, end="" if GATE.warm_out.endswith("\n") else "\n")
    print(f"beautiful-mnist-gate: {GATE.compared} shared rows, 3 lanes identical"
          if ok else f"{GATE.name}: {VERDICT[code]}")
    sys.exit(code)
