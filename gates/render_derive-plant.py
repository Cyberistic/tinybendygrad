#!/usr/bin/env python3
"""render_derive-plant.py -- what the two RENDER gates CAN see, and what they CANNOT.

    .venv/bin/python gates/render_derive-plant.py

FIVE ARMS AND TWO CONTROLS, EACH ON A COPY, EACH NAMING THE ROW IT MOVES, PLUS TWO
DECLARATION ARMS THAT PLANT WHAT A GATE DECLARES RATHER THAN WHAT A PORT SAYS.

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

  S   a DECLARED DIVERGENCE that is STALE                REFUSED (3), not green and
      not red.  A declaration is a CLAIM -- "the port's row and CPython's row
      DIFFER on this row" -- and a claim can go stale: the port was fixed, or the
      oracle was, and the two sides are the same row now.  The arm declares a
      COMPARED row -- a row whose two sides ARE the same -- and the gate must
      REFUSE it as stale instead of excluding it from the diff and calling the
      run green.  **A DECLARED DIVERGENCE THAT CANNOT GO STALE IS A LABEL.**
  SL  CONTROL for S: a DECLARED DIVERGENCE that is LIVE   GREEN (0), with the row
      EXCLUDED from the diff.  This is the arm that says S is not a gate that
      refuses everything: the port is mutated so the row really does differ, and
      the same declaration is then accepted.  S and SL are a PAIR, and either one
      alone would prove nothing.

THE COPIES.  A mutation is an edit that must appear EXACTLY ONCE, and it is applied
to a COPY BESIDE the original -- Bend resolves `import ./x.bend` relative to the
FILE's own directory, so a copy anywhere else answers `no such file`.  The copies
are named `*.mut.bend`, which `.gitignore:36` already ignores, and they are DELETED
in a `finally`.  Nothing in the real tree is edited, ever: the copies are the subject
and the real files are only read.

THE DECLARATION ARMS ARE NOT MUTATIONS: they change what the gate DECLARES, and
they do it by loading the gate MODULE and setting its `DIVERGES` -- the file name
has dashes, so it cannot be imported by name, and `importlib` loads it by path.
The declaration is pinned to the lanes the gate has just written, so it is a
CLAIM ABOUT THE LIVE LANES and not a hand-written pin.

WHAT MOVED IS MEASURED, NOT ASSERTED.  The gate writes its lanes under
`gates/artifacts/<gate>/` BEFORE it compares them, so the number of rows that moved
is the DIFF of two artefacts, and an arm that moved nothing is a coverage gap
rather than a pass.  The arm also says WHICH HALF moved, because that is the
difference between the two arms and it is the whole point of having two.
"""
import contextlib
import importlib.util
import io
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

# THE DECLARATION ARMS.  `dsp_sc_0000` is a COMPARED row -- the port's row and
# CPython's row ARE the same -- so declaring it a divergence is a claim that they
# DIFFER, and they do not.  `S` plants that and the gate must REFUSE it as stale;
# `SL` plants the same declaration on a copy whose row really does differ, and
# the gate must accept it.  The pair is the point: a gate that refused every
# declaration would pass `S` alone.
DECL_GATE = "ops_dsp_render"
DECL_ROW = "dsp_sc_0000"
DECL_EDIT = ('urow("dsp_sc_0000",     rpc_sc(0, 0, 0, 0))',
             'urow("dsp_sc_0000",     rpc_sc(0, 0, 0, 1))')


def refuse(why):
    print(f"== REFUSED, NOT A VERDICT: render_derive-plant: {why}", file=sys.stderr)
    raise SystemExit(3)


def load_gate(gate):
    """the gate MODULE, by path -- the file name has dashes, so `import` cannot
    name it, and `importlib` loads it from its path instead."""
    path = HERE / f"{gate}-gate.py"
    spec = importlib.util.spec_from_file_location(f"{gate}_plant", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_declared(gate, port, row):
    """run the gate with `row` DECLARED a divergence, PINNED TO THE LANES the
    gate has just written -- so the declaration is a claim about the live lanes
    and not a hand-written pin.  Returns (code, the gate's own output)."""
    mod = load_gate(gate)
    d = HERE / "artifacts" / gate
    py, bd = dict(split_rows((d / "py.rows").read_text())), dict(split_rows((d / "bd.out").read_text()))
    if row not in py or row not in bd:
        refuse(f"{gate}: the row {row!r} is not in the lanes")
    mod.DIVERGES = {row: (py[row], bd[row])}
    old, buf = sys.argv, io.StringIO()
    sys.argv = [f"{gate}-gate.py"] + (["--port", str(port)] if port else [])
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            code = mod.main()
    finally:
        sys.argv = old
    return code, buf.getvalue()


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

    # -- THE DECLARATION ARMS.  They plant what the gate DECLARES, not what the
    # port says, and they are a PAIR: `S` is the arm this work needs and `SL` is
    # its control.
    decl = []
    decl_port = next(p for g, p, _c in PORTS if g == DECL_GATE)
    decl_copy = copies[DECL_GATE]
    try:
        # S: the STALE declaration.  `DECL_ROW` is a COMPARED row, so the two
        # sides are the SAME row and the declaration is a claim that they
        # differ.  The gate must REFUSE it -- exit 3 -- and say STALE.
        code, out = run_declared(DECL_GATE, None, DECL_ROW)
        decl.append(("S", code, out))
        print(f"  S {DECL_GATE}: gate rc={code} "
              f"({'REFUSED' if code == 3 else 'NOT REFUSED'}), "
              f"declared {DECL_ROW} as a divergence")
        print("      a DECLARED DIVERGENCE that is STALE")
        # SL: the LIVE declaration.  The port is MUTATED so the row really does
        # differ from CPython's, and then the SAME declaration is accepted: the
        # gate is GREEN and the row is EXCLUDED from the diff.
        src = (ROOT / decl_port).read_text()
        if src.count(DECL_EDIT[0]) != 1:
            refuse(f"SL/{DECL_GATE}: the edit must appear EXACTLY ONCE; it appears "
                   f"{src.count(DECL_EDIT[0])}")
        decl_copy.write_text(src.replace(*DECL_EDIT))
        r = run_gate(DECL_GATE, decl_copy)
        if r.returncode == 0:
            bad_live = "the MUTATED port's gate stayed GREEN"
        else:
            bad_live = None
        code, out = run_declared(DECL_GATE, decl_copy, DECL_ROW)
        decl.append(("SL", code, out))
        print(f"  SL {DECL_GATE}: gate rc={code} "
              f"({'GREEN' if code == 0 else 'NOT GREEN'}), the SAME declaration on a "
              f"port whose row really does differ")
        print("      CONTROL: a DECLARED DIVERGENCE that is LIVE")
        if bad_live:
            print(f"  FAILED: {bad_live}")
    finally:
        decl_copy.unlink(missing_ok=True)

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
    for (arm, code, out) in decl:
        if arm == "S":
            if code != 3:
                bad.append(f"S: the STALE declaration was not REFUSED (rc={code}); a "
                           f"declaration that cannot go stale is a label")
            if "STALE" not in out:
                bad.append("S: the refusal did not say STALE, so the reader cannot "
                           "tell a stale declaration from any other refusal")
        else:
            if code != 0:
                bad.append(f"SL: the LIVE declaration was not accepted (rc={code}); "
                           f"S alone would not prove anything")
    if bad:
        for b in bad:
            print(f"  FAILED: {b}")
        return 1
    print("\n--plant: all arms ran; P2 moved the EXPECTATION on 1 row and left the "
          "value alone, V moved the VALUE on 1 row, every CONTROL moved nothing, "
          "S was REFUSED as a stale declaration and SL accepted the same "
          "declaration on a port whose row really does differ.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
