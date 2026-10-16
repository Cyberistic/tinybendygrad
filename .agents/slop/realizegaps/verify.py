#!/usr/bin/env python3
"""THE GATE'S OWN DECISION, WITHOUT `gatekit.Gate.run()`.

    .venv/bin/python .agents/slop/realizegaps/verify.py

WHY THIS EXISTS AND WHAT IT IS NOT. `gates/gatekit.py` is ANOTHER AGENT'S FILE AND IS NOT
MINE TO EDIT, and at 2026-10-16 it carried an in-flight edit that makes EVERY gate in the tree
crash:

    gates/gatekit.py:503   if (code, why := device_precondition(...)) != PASS:

`code` is never bound by that walrus, so `Gate.run()` raises `NameError` on every gate. That
is MEASURED here, and `device_precondition` ITSELF is fine when called normally
(`device_plant()` prints all five states and exits 0) -- the defect is the call site.

So this script does what `gate()` does, in the order `gate()` does it, using the gate's OWN
defs and the gate's OWN pins, and it does not edit anything:

  1 run the two lanes (oracle, `bend` interpreted, `bend` compiled) into a directory this
    script owns,
  2 `_pins()` -- the declared-divergence population, loaded by path,
  3 the pin check `gatekit` does: every pin's CPython value a member of the `py` lane, every
    pin's port value a member of the `bd` and `bn` lanes, every pinned ROW PRESENT,
  4 the lanes identical where they are supposed to be (`bd` vs `bn`),
  5 the TEN checks, each called on its own so one crash cannot hide the other nine.

IT IS NOT A GATE AND NOT A SUBSTITUTE FOR ONE. It is the reading that says whether this
change is correct while `gate()` is unrunnable, and every number it prints is re-measurable
by running the gate once the other agent's edit lands.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATES = ROOT / "gates"
ART = Path(__file__).resolve().parent / "verify-art"
PY, BEND = ROOT / ".venv/bin/python", ROOT / "bin/bend"


def lane(name, cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    (ART / name).write_text(r.stdout)
    if r.returncode:
        print(f"-- {name} FAILED rc={r.returncode}\n{r.stderr[-400:]}")
        return False
    return True


def rows(name):
    return dict(l.split("=", 1) for l in (ART / name).read_text().splitlines() if "=" in l)


def main():
    ART.mkdir(exist_ok=True)
    for f in ART.iterdir():
        f.unlink()
    # THE COMPILED LANE IS `bend -o <bin>` AND THEN THE BINARY, which is what `gatekit` runs
    # (`gatekit.py:516-520`), so `bn` really is the compiled program and not the interpreter a
    # second time.
    c = subprocess.run([str(BEND), "gates/realize_graph_census.bend", "-o",
                        str(ART / "gate.bin")], capture_output=True, text=True, cwd=str(ROOT))
    if c.returncode:
        print(f"-- the native compile failed rc={c.returncode}: {(c.stderr or '')[-400:]}")
        return 1
    spec = importlib.util.spec_from_file_location("rgz", GATES / "realize_graph_census-gate.py")
    m = importlib.util.module_from_spec(spec)
    sys.modules["rgz"] = m
    spec.loader.exec_module(m)
    # `ART` IS THE GATE'S OWN MODULE CONSTANT AND IS NOT `HERE`-RELATIVE, the same trap the
    # mutation harness records as its FOURTH wiring bug: repointing nothing here leaves every
    # lane-reading check reading `gates/artifacts/realize_graph_census-gate/`, which is
    # EMPTY because a crashed run cleared it. MEASURED: eight of the ten checks answered "the
    # promoted lanes are not there" while the pins and the lane diff -- which read this
    # script's own files -- were clean. A guard that reads a directory nobody wrote is a guard
    # that has said nothing.
    m.ART = ART
    if not all((lane("py.rows", [str(PY), str(GATES / "realize_graph_census-oracle.py")]),
                lane("bd.out", [str(BEND), "gates/realize_graph_census.bend"]),
                lane("bn.out", [str(ART / "gate.bin")]))):
        print("a lane failed; nothing said")
        return 1
    print(f"lanes: { {n: len(rows(n)) for n in ('py.rows', 'bd.out', 'bn.out')} }"
          f"  (the gate declares {m.ROWS[0]})")
    py, bd, bn = rows("py.rows"), rows("bd.out"), rows("bn.out")
    bad = 0
    if not (m.DIVERGES is not None):
        print(f"REFUSED, NOT A VERDICT: {m.WHY}")
        return 3
    # (3) the pins, exactly as `gatekit` reads them: a LIST-MEMBERSHIP test on the raw line.
    for row, (want_py, want_bd) in sorted(m.DIVERGES.items()):
        for lane_name, want in (("py.rows", want_py), ("bd.out", want_bd), ("bn.out", want_bd)):
            raw = (ART / lane_name).read_text()
            if not any(l.startswith(row + "=") for l in raw.splitlines()):
                print(f"  {lane_name} has no {row!r} row -- a pinned claim changed")
                bad += 1
            elif want not in raw:
                print(f"  {lane_name}'s {row} is not {want!r}")
                bad += 1
    # (4) the two port lanes must be identical outside the declared divergences.
    for r in sorted(bd):
        if r in m.DIVERGING:
            continue
        if bd[r] != bn[r] or py[r] != bd[r]:
            print(f"  DISAGREE {r}: py={py.get(r)!r} bd={bd.get(r)!r} bn={bn.get(r)!r}")
            bad += 1
    print(f"pins + lane agreement: {len(m.DIVERGES)} declared divergences, {bad} problems")
    # (5) the checks, each on its own.
    for nm in ("classes_hold", "no_bottom_value", "drivers_hold", "axis_hold", "calls_hold",
               "pin_drift_holds", "compares_holds", "kern_blind_holds", "argkinds_hold",
               "ret_is_uop_fixed_holds"):
        try:
            ok = getattr(m, nm)()
        except Exception as e:                                       # noqa: BLE001
            print(f"  {nm}: EXC {type(e).__name__}: {e}")
            ok = False
        print(f"  {nm}: {'OK' if ok else 'RED'}")
        bad += 0 if ok else 1
    print(f"-- verify: {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())