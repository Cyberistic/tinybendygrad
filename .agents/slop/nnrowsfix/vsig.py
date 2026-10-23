#!/usr/bin/env python3
"""vsig.py -- the STRONGER cross-check on the five GRAPH rows: the port's OWN
node list against CPython's node list, node for node.

    .venv/bin/python .agents/slop/nnrowsfix/vsig.py

WHY THIS EXISTS. `mxw_sig` -- the spelling the five `_sig` rows use -- is a
FOUR-TUPLE summary: node count, root op, root arity, root's source op names.
Two different graphs can share all four. The port already has a printer for the
WHOLE list: `M.mo_valsig.of` (mixin/op.bend:1255) prints
`<n> OP/nsrc OP/nsrc ... ` with the CONST payloads, and the CPython witness
prints the same format (`oracle_valsig` in `nn-oracle.py`). So the four-tuple
can be CHECKED AGAINST THE WHOLE LIST, which is what this script measures.

**NO FILE IN THE REPOSITORY IS WRITTEN.** The port is COPIED into a temporary
directory (the gate's own `_materialize`), the driver is written INTO THE COPY,
bend runs against the copy, and `tempfile` removes it. The repo's `.bend` tree
is not touched -- this unit owns `tinybendygrad/nn/layers.bend` and nothing else.

THE FIXTURES ARE THE PORT'S OWN FIXTURES, through the port's own defs:
`L.nn_dot`, `L.nn_sum`, `L.nn_conv2d`, `MX.mxw_reshape`, `MX.mxw_permute`,
`T.tn_mul` and `M.mo_cast_t` -- the same calls `nn/layers.bend` makes in
`nn_row_dbg` and `nn_row_fold`.
"""
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent

DRIVER = """\
# A SCRATCH DRIVER, written into a COPY of the port by `vsig.py`. It is not in
# the repository and it is not a gate: it prints the port's own node list so the
# CPython witness's node list can be compared with it.
import Base
import ./../uop/ops.bend as O
import ./../tensor.bend as T
import ./../LAWS/spec.bend as S
import ./../mixin/op.bend as M
import ./../mixin/movement.bend as MX
import ./layers.bend as L

def vs.t(ns: List<&2, U32>, slot: U32, size: U32) -> T.Tensor:
  MX.mxw_reshape(MX.mxw_buf(O.Arena.empty(), slot, size), ns)

def vs.of(+t: T.Tensor) -> String: M.mo_valsig.of(T.Tensor.ar(t), T.Tensor.u(t))

def vs.maybe(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: vs.of(t)
    case None{}: "NONE"

def main() -> IO(Unit):
  +x = vs.t([2, 3], 0, 6)
  +w = vs.t([3, 4], 1, 12)
  +c = L.nn_conv2d(vs.t([1, 3, 32, 32], 0, 3072), vs.t([8, 3, 3, 3], 1, 216),
    1, 1, 1, 1, None{}, None{})
  +xr = MX.mxw_reshape(x, [2, 1, 3])
  +wr = MX.mxw_permute(MX.mxw_reshape(w, [1, 3, 4]), [0, 2, 1])
  +xw = T.tn_mul(xr, wr)
  +sm = L.nn_sum(False{}, xw, [2])
  +cc = M.mo_cast_t(sm, S.single())
  do IO<Unit>:
    IO.print(String.concat(["dbg_x_sig=", vs.of(x)]))
    IO.print(String.concat(["dbg_dot_sig=", vs.maybe(L.nn_dot(x, w))]))
    IO.print(String.concat(["dbg_conv_sig=", vs.maybe(c)]))
    IO.print(String.concat(["fold_xw_sig=", vs.of(xw)]))
    IO.print(String.concat(["fold_cc_sig=", vs.of(cc)]))
"""


def load_gate():
    spec = importlib.util.spec_from_file_location(
        "nnrowsgate", ROOT / "gates" / "nn-rows-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


NAMES = ["dbg_x_sig", "dbg_dot_sig", "dbg_conv_sig", "fold_xw_sig", "fold_cc_sig"]


def oracle_lines():
    """The witness's node lists -- the block it prints under
    `# ORACLE FORMAT WITH CONST PAYLOADS`, whose lines are `# name=<list>`."""
    out = []
    for line in (HERE / "nn-oracle.rows").read_text().splitlines():
        if line.startswith("# ") and "=" in line and "ORACLE FORMAT" not in line:
            out.append(line[2:].strip())
    return out


def pick(block, name):
    hits = [l for l in block if l.startswith(name + "=")]
    return hits[-1] if hits else None


def main() -> int:
    mod = load_gate()
    with tempfile.TemporaryDirectory(prefix="nnrowsfix-vsig-") as td:
        port = mod._materialize(Path(td) / "port", None)
        driver = port / "nn" / "vsig.bend"
        driver.write_text(DRIVER)
        proc = subprocess.run([str(mod.BEND), str(driver)], capture_output=True,
                              text=True, timeout=900)
        if proc.returncode != 0:
            print(f"vsig: REFUSED, NOT A VERDICT: the scratch driver failed "
                  f"(rc={proc.returncode}). bend said: "
                  f"{proc.stderr.strip()[:400]}", file=sys.stderr)
            return 3
        (HERE / "vsig.port.rows").write_text(proc.stdout)
        port_rows = [l.strip() for l in proc.stdout.splitlines() if l.strip()]
        oracle = oracle_lines()
        bad = []
        print()
        print("vsig: THE WHOLE NODE LIST, the port's against the witness's:")
        for name in NAMES:
            o, p = pick(oracle, name), pick(port_rows, name)
            if o is None or p is None:
                bad.append(f"{name}: one side has no node list "
                           f"(oracle={'yes' if o else 'no'} port={'yes' if p else 'no'})")
                continue
            if o == p:
                print(f"vsig: {name}: IDENTICAL ({len(p.split()) - 1} tokens)")
            else:
                bad.append(f"{name}: the node lists DIFFER")
                print(f"vsig: {name}: DIFFERENT")
                print(f"vsig:   oracle: {o}")
                print(f"vsig:   port  : {p}")
        if bad:
            print("vsig: FAILED -- " + "; ".join(bad), file=sys.stderr)
            return 1
        print(f"vsig: all {len(NAMES)} node lists are IDENTICAL, node for node, "
              f"CONST payloads included")
    return 0


if __name__ == "__main__":
    sys.exit(main())
