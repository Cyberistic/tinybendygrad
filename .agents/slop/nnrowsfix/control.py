#!/usr/bin/env python3
"""control.py -- the controls for the thirteen rows this unit closed.

    .venv/bin/python .agents/slop/nnrowsfix/control.py

THREE CONTROLS, AND WHAT EACH ONE CLAIMS.

  C1  a CLASS ONE row's `want` perturbed -- a DTYPE row, whose `want` is spelled
      `f32` -- into a WRONG BUT NON-EMPTY `f16`. The claim: that row goes red and
      NO OTHER ROW DOES.
  C2  a CLASS TWO row's `want` perturbed -- a GRAPH row -- into a WRONG BUT NON-
      EMPTY signature (the `srcops` list truncated). The claim: that row goes red
      and NO OTHER ROW DOES.
  C3  THE CONTROL ON THE CONTROL: a `want` EMPTIED. The claim: the gate's
      VACUITY class (`UNCHECKABLE`) is a DIFFERENT class from its WRONGNESS class
      (`MISMATCH`), and C1 and C2 fired `MISMATCH`. If the gate only ever caught
      emptiness, then C1 and C2 would have been catching vacuity and not
      wrongness, and the thirteen closed rows would be worthless.

THE MEASUREMENT IS THE GATE'S OWN. `gates/nn-rows-gate.py` is imported BY PATH
and its `measure()` -- the SHIPPED decision, the same function the gate's own
`run_gate` prints -- is what decides each control. `gates/README.md` records the
reason in one line: "a plant that drives a helper is not a plant of the
decision". The mutation is the gate's own `_set_want`, which edits the COPY's
source and never the live tree.

THE GATE'S OUTPUT DIRECTORY IS REDIRECTED into this unit's own directory.
`measure()` clears its output directory on every call
(`gates/nn-rows-gate.py:522-525`) and `gates/artifacts/` is a SHARED path: a
control run that wrote there would delete another unit's gate artifacts
mid-run. The output of every control is a COPY, in a temporary directory that
`tempfile` removes.
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent

FAILING = ("MISMATCH", "UNCHECKABLE", "DEAD-ROW", "SHRUNK", "EXTRA", "DUPLICATE")

# (id, class-under-test, row, new want, what the mutation claims)
CONTROLS = [
    ("C1", "class one (a DTYPE row)", "where_xdt", "f16",
     "the `want` was spelled `f32` (the port's `E.ew_dtnm` spelling, and "
     "CPython's own `DType.name`); it is now a wrong-but-non-empty `f16`"),
    ("C2", "class two (a GRAPH row)", "fold_xw_sig",
     "n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE",
     "the `want` was the whole signature with `srcops=Ops.RESHAPE|Ops.PERMUTE`; "
     "it is now a wrong-but-non-empty signature whose `srcops` list is "
     "truncated -- a graph with a PERMUTE source and a signature that does not "
     "say so"),
    ("C3", "the control on the control", "fold_xw_sig", "",
     "the `want` is EMPTY again -- this is the VACUITY class, and it must be a "
     "DIFFERENT class from C2's WRONGNESS"),
]


def load_gate():
    spec = importlib.util.spec_from_file_location(
        "nnrowsgate", ROOT / "gates" / "nn-rows-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.OUT = HERE / "artifacts" / "nn-rows-gate"
    return mod


def fired(counts):
    """The rows that are in a failing class, by name, and the counts."""
    names = []
    for cls in FAILING:
        names += [(cls, n) for n, _ in counts.get(cls, [])]
    return names


def summary(counts):
    return " ".join(f"{c}={len(counts.get(c, []))}" for c in
                     ("MATCH", "MISMATCH", "UNCHECKABLE", "DEAD-ROW", "SHRUNK", "EXTRA",
                      "DUPLICATE"))


def main() -> int:
    mod = load_gate()
    bad = []

    with tempfile.TemporaryDirectory(prefix="nnrowsfix-control-") as td:
        base = Path(td) / "base"
        port = mod._materialize(base, None)
        b_code, b_counts, b_n, b_e, _bl, _br = mod.measure(port, "control/before")
        print(f"control: BASELINE (the live tree, copied) rc={b_code} "
              f"rows={b_n} {summary(b_counts)}")
        if b_code != mod.PASS:
            print("control: REFUSED, NOT A VERDICT: the baseline is not green, so a "
                  "control cannot show that its mutation is what made the gate red",
                  file=sys.stderr)
            return 3

        for cid, klass, row, new_want, claim in CONTROLS:
            print()
            print(f"control: {cid} class={klass}")
            print(f"control: {cid} row={row}")
            print(f"control: {cid} mutation={claim}")
            work = Path(td) / cid
            cport = mod._materialize(work, None)
            driver = cport / "nn" / "layers.bend"
            try:
                text = mod._set_want(driver.read_text(), row, new_want)
            except KeyError as exc:
                print(f"control: {cid} REFUSED, NOT A VERDICT: {exc}", file=sys.stderr)
                bad.append(f"{cid}: the mutation could not be applied")
                continue
            driver.write_text(text)
            a_code, a_counts, a_n, _e, _l, a_rows = mod.measure(cport, f"control/{cid}")

            before = {(c, n) for c, n in fired(b_counts)}
            after = {(c, n) for c, n in fired(a_counts)}
            new = sorted(after - before)
            gone = sorted(before - after)
            print(f"control: {cid} before: rc={b_code} {summary(b_counts)}")
            print(f"control: {cid} after:  rc={a_code} {summary(a_counts)}")
            print(f"control: {cid} rows_that_went_red={new if new else 'NONE'}")
            print(f"control: {cid} rows_that_stopped_being_red={gone if gone else 'NONE'}")
            print(f"control: {cid} rows_still_green={len(a_counts.get('MATCH', []))} "
                  f"of {a_n}")
            for cls, n in new:
                detail = next((d for c, nm, d in
                               [(c, nm, d) for c in FAILING
                                for nm, d in a_counts.get(c, [])] if c == cls and nm == n), "")
                print(f"control: {cid} {cls} {n} {detail}")

            if len(new) != 1:
                bad.append(f"{cid}: expected exactly one row to go red, {len(new)} did")
            elif new[0][1] != row:
                bad.append(f"{cid}: the row that went red is {new[0][1]!r}, not {row!r}")
            if a_code != mod.FAIL:
                bad.append(f"{cid}: the gate returned {a_code}, expected FAIL (1)")
            if gone:
                bad.append(f"{cid}: a row stopped being red: {gone}")
            if len(a_counts.get("MATCH", [])) != b_n - 1:
                bad.append(f"{cid}: {len(a_counts.get('MATCH', []))} rows stayed green, "
                           f"expected {b_n - 1} of {b_n}")

    print()
    if bad:
        print("control: FAILED -- " + "; ".join(bad), file=sys.stderr)
        return 1
    print("control: all three controls OK: one row went red each time, the class "
          "fired was the one the control claims, and every other row stayed green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
