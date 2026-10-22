#!/usr/bin/env python3
"""render_derive-plant.py -- what the two RENDER gates CAN see, and what they CANNOT.

    .venv/bin/python gates/render_derive-plant.py

FIVE ARMS AND TWO CONTROLS, EACH ON A COPY, EACH NAMING THE ROW IT MOVES.

  P2  a `py=` LITERAL put back beside a correct row     RED, 1 row, and the row's
      `got=` half does NOT move -- only the expectation does.  This is the rot the
      derivation removes: `tc.bend` measured 71 of its 286 transcriptions WRONG and
      the file agreed with itself, because a transcription has no generator.
  V   a row's VALUE put wrong                           RED, 1 row, and the row's
      `got=` half DOES move.  **THIS IS THE ARM THAT PROVES THE LANE IS NOT A
      SELF-CONSISTENCY CHECK.**  The `py=` half is the port's own value now, so the
      two halves of a row always agree with EACH OTHER; a gate that only compared
      them would be blind to a wrong value, and this arm is what shows that it is
      not one.
  C   CONTROL: a comment-only edit                       GREEN, 0 rows.  A control that
      moves something is not a control, and without it the other numbers do not
      mean anything.

THE COPIES.  A mutation is an edit that must appear EXACTLY ONCE, and it is applied
to a COPY BESIDE the original -- Bend resolves `import ./x.bend` relative to the
FILE's own directory, so a copy anywhere else answers `no such file`.  The copies
are named `*.mut.bend`, which `.gitignore:36` already ignores, and they are DELETED
in a `finally`.  Nothing in the real tree is edited, ever: the copies are the subject
and the real files are only read.

WHAT MOVED IS MEASURED, NOT ASSERTED.  The gate writes its lanes under
`gates/artifacts/<gate>/` BEFORE it compares them, so the number of rows that moved
is the DIFF of two artefacts, and an arm that moved nothing is a coverage gap
rather than a pass.  The arm also says WHICH HALF moved, because that is the
difference between the two arms and it is the whole point of having two.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from renderkit import split_rows  # noqa: E402

PY = ROOT / ".venv" / "bin" / "python"

# (gate, port, the copy's path beside it, the gate's artifact directory)
PORTS = (
    ("llvmir_render", "tinybendygrad/renderer/llvmir.bend",
     "tinybendygrad/renderer/llvmir.mut.bend"),
    ("ops_dsp_render", "tinybendygrad/runtime/ops_dsp.bend",
     "tinybendygrad/runtime/ops_dsp.mut.bend"),
)

# THE EDITS.  Each is (arm, port, what, old, new) and each `old` must appear
# EXACTLY ONCE in the port's source.
EDITS = (
    # -- P2: the `py=` half becomes a LITERAL again, and a ROTTEN one.  The row's
    # VALUE is untouched: `f8names()` still answers the four fp8 names.  Only the
    # expectation is a transcription, and it is a transcription that has gone stale
    # -- which is what every transcription eventually does.
    ("P2", "llvmir_render", "a `py=` LITERAL put back beside a correct row",
     'def r_f8o() -> String: rd("fp8s.order", f8names())',
     'def r_f8o() -> String: r("fp8s.order", f8names(), "fp8e4m3,fp8e5m2")'),
    # -- V: the row's VALUE is put wrong.  `is_volatile BUFFER vol True` answers
    # False -- a BUFFER is not a PARAM -- and the fixture's `is_param` is flipped,
    # so the port computes True and CPython still says False.
    ("V", "llvmir_render", "a row's VALUE put wrong",
     'r_iv("is_volatile BUFFER vol True", False{}, True{})',
     'r_iv("is_volatile BUFFER vol True", True{}, True{})'),
    ("C", "llvmir_render", "CONTROL: a comment-only edit",
     "# THE DERIVED ROW.",
     "# THE DERIVED ROW.  # PLANT-CONTROL"),
    # -- V on the SECOND port, because a gate that is not run is not a gate.  The
    # row is a COMPARED one (`dsp_sc_0000` is not one of the thirty declared
    # divergences), and a mutation on a DIVERGENCE row would move nothing -- which
    # is a property of every excluded row, and is why the thirty are PINNED.
    ("V", "ops_dsp_render", "a row's VALUE put wrong",
     'urow("dsp_sc_0000",     rpc_sc(0, 0, 0, 0))',
     'urow("dsp_sc_0000",     rpc_sc(0, 0, 0, 1))'),
    ("C", "ops_dsp_render", "CONTROL: a comment-only edit",
     "# A ROW IS A COMPARISON.",
     "# A ROW IS A COMPARISON.  # PLANT-CONTROL"),
)


def refuse(why):
    print(f"== REFUSED, NOT A VERDICT: render_derive-plant: {why}", file=sys.stderr)
    raise SystemExit(3)


def run_gate(gate, port=None):
    argv = [str(PY), str(HERE / f"{gate}-gate.py")]
    if port is not None:
        argv += ["--port", str(port)]
    return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))


def lane(gate):
    p = HERE / "artifacts" / gate / "bd.out"
    if not p.exists():
        return None
    return dict(split_rows(p.read_text()))


def halves(row):
    """(the `got=` half, the `py=` half) of a row's text."""
    body = row.split("]   py=[", 1)
    return (body[0].split(" = [", 1)[1] if " = [" in body[0] else body[0],
            body[1].rstrip("]") if len(body) > 1 else "")


def main():
    base = {}
    for gate, port, _copy in PORTS:
        r = run_gate(gate)
        if r.returncode != 0:
            print(r.stdout, r.stderr)
            refuse(f"the {gate} gate is RED at rest (rc={r.returncode}); "
                   f"a plant measures a green gate")
        base[gate] = lane(gate)
        if not base[gate]:
            refuse(f"the {gate} gate wrote no port lane")
    print("render_derive-plant.py: both gates are GREEN at rest\n")

    copies = {g: ROOT / c for (g, _p, c) in PORTS}
    results = []
    try:
        for (arm, gate, what, old, new) in EDITS:
            port = next(p for g, p, _c in PORTS if g == gate)
            src = (ROOT / port).read_text()
            if src.count(old) != 1:
                refuse(f"{arm}/{gate}: the edit must appear EXACTLY ONCE; "
                       f"it appears {src.count(old)}")
            (ROOT / port).with_suffix(".mut.bend").write_text(src.replace(old, new))
            mut = copies[gate]
            r = run_gate(gate, mut)
            after = lane(gate)
            if after is None:
                refuse(f"{arm}/{gate}: the gate wrote no port lane")
            moved = [n for n, t in after.items() if base[gate].get(n) != t]
            gone = [n for n in base[gate] if n not in after]
            got_moved = [n for n in moved
                         if halves(base[gate][n])[0] != halves(after[n])[0]]
            results.append((arm, gate, what, r.returncode, moved, gone, got_moved))
            print(f"  {arm} {gate}: gate rc={r.returncode}, {len(moved)} rows moved "
                  f"({', '.join(moved[:3]) or 'none'}), {len(got_moved)} of them had "
                  f"their VALUE moved")
            print(f"      {what}")
    finally:
        for p in copies.values():
            p.unlink(missing_ok=True)

    bad = []
    for (arm, gate, what, rc, moved, gone, got_moved) in results:
        if arm == "C":
            if rc != 0 or moved or gone:
                bad.append(f"{arm}/{gate}: the CONTROL moved something (rc={rc}, "
                           f"{len(moved)} rows)")
        else:
            if rc == 0:
                bad.append(f"{arm}/{gate}: the gate stayed GREEN")
            if len(moved) != 1:
                bad.append(f"{arm}/{gate}: {len(moved)} rows moved, expected 1")
            if gone:
                bad.append(f"{arm}/{gate}: {len(gone)} rows disappeared")
            if arm == "P2" and got_moved:
                bad.append(f"{arm}/{gate}: the VALUE moved too -- the arm was supposed "
                           f"to move the expectation only")
            if arm == "V" and not got_moved:
                bad.append(f"{arm}/{gate}: the VALUE did not move -- the arm is not "
                           f"putting the value wrong")
    if bad:
        for b in bad:
            print(f"  FAILED: {b}")
        return 1
    print("\n--plant: all arms ran; P2 moved the EXPECTATION on 1 row and left the "
          "value alone, V moved the VALUE on 1 row, and every CONTROL moved nothing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
