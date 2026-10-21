#!/usr/bin/env python3
"""Plant for the vendordep dated record. Copies only. The real files are not written.

    .venv/bin/python gates/vendordep-census-plant.py
    .venv/bin/python gates/vendordep-census-plant.py --falsify

The comparator is `gates/rotclaim-gate.py`, loaded by path. A direction that emits
no row is REFUSED. `--falsify` inverts the control's expected live count and must
exit non-zero: a plant whose expectation cannot be violated measures nothing.

A retired sha on the next line is PIN and does not increment `live`. The check
reads that row's state: a live count of 0 with the row dropped is not a pass.
A current-tree sha with the bindings stripped is LIVE. A comment does not exempt it.
A retired sha on the next line of a `.rows` copy is PIN the same way. A count of
transcribed hits is not that row. A current-tree sha in that copy is LIVE.
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import PASS, REFUSED  # noqa: E402

GATE = HERE / "vendordep-census-gate.py"
LEDGER = HERE / "vendordep-census.rows"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


def classified(rotclaim, text, trees):
    got = rotclaim.assess(text, trees, ROOT)
    if not any(r["kind"] == "file" for r in got):
        return None
    live = sum(1 for r in got if r["kind"] == "live")
    state = next((r["state"] for r in got if r["kind"] == "record"), "ABSENT")
    return (live, state)


def scored(rotclaim, text, trees):
    """`(live, pins, pin_state, record)`. `pin_state` is the row's own state."""
    got = rotclaim.assess(text, trees, ROOT)
    if not any(r["kind"] == "file" for r in got):
        return None
    pins = [r for r in got if r["kind"] == "pin"]
    live = sum(1 for r in got if r["kind"] == "live")
    record = next((r["state"] for r in got if r["kind"] == "record"), "ABSENT")
    return (live, len(pins), pins[0]["state"] if pins else "ABSENT", record)


def without_bindings(rotclaim, text):
    """The dated-record lines, dropped by the comparator's own spans. None if it saw none."""
    drop = set()
    for rec in rotclaim.records_of(text).values():
        for key in ("date", "derive"):
            start, end, _value = rec[key]
            drop.update(range(start, end + 1))
    if not drop:
        return None
    return "\n".join(ln for i, ln in enumerate(text.splitlines(), 1) if i not in drop)


def rows_hits(pinned, text, trees):
    with tempfile.TemporaryDirectory(prefix="vendordep-rows-") as td:
        home = Path(td) / "gates"
        home.mkdir()
        (home / "vendordep-census.rows").write_text(text)
        return pinned.transcribed(Path(td), [home], trees)


def rows_scored(rotclaim, text, trees):
    """`(live, pins, pin_state, live_state)` for a `.rows` copy. None if no hit row."""
    got = rotclaim.assess(text, trees, ROOT, name="vendordep-census.rows")
    pins = [r for r in got if r["kind"] == "pin"]
    lives = [r for r in got if r["kind"] == "live"]
    if not pins and not lives:
        return None
    return (
        len(lives),
        len(pins),
        pins[0]["state"] if len(pins) == 1 else "ABSENT",
        lives[0]["state"] if len(lives) == 1 else "ABSENT",
    )


def main(argv):
    warnings.filterwarnings("ignore", category=SyntaxWarning)
    rotclaim = load("vendordep_rotclaim", HERE / "rotclaim-gate.py")
    pinned = rotclaim.pinned_mod()
    trees = pinned.tree_values(ROOT)
    cur = pinned.resolve(ROOT, "HEAD:tinygrad")
    retired = next((t for t in trees if t != cur), "")
    if not cur or not retired:
        print("vendordep-census-plant: REFUSED -- fewer than two tree values")
        return REFUSED
    gate_bytes = GATE.read_bytes()
    ledger_bytes = LEDGER.read_bytes()
    text = gate_bytes.decode()
    ledger = ledger_bytes.decode()
    rows = []

    def check(label, got, want):
        if got is None:
            rows.append(f"plant.{label}\tstate=REFUSED\tverdict=SILENT\twanted={want}")
            return
        rows.append(f"plant.{label}\tstate={'OK' if got == want else 'REFUSED'}\tverdict={got}\twanted={want}")

    date = rotclaim.records_of(text).get("REVENDOR", {}).get("date", (None, None, None))[2]
    needle = f'REVENDOR_RECORD_DATE = "{date}"' if date else ""
    broken = text.replace(needle, 'REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"', 1) if needle in text else None
    control_want = (1, "VERIFIED") if "--falsify" in argv else (0, "VERIFIED")

    stripped = without_bindings(rotclaim, text)
    check("control", classified(rotclaim, text, trees), control_want)
    check("retired-sha-on-the-next-line-is-pin",
          scored(rotclaim, text + f"\n# {retired}\n", trees), (0, 1, "PIN", "VERIFIED"))
    check("current-sha-bindings-stripped-is-live",
          classified(rotclaim, stripped + f"\n# {cur}\n", trees) if stripped is not None else None, (1, "ABSENT"))
    check("comment-does-not-exempt", classified(rotclaim, text + f"\n# {cur}\n", trees), (1, "VERIFIED"))
    check("wrong-date-is-refused", classified(rotclaim, broken, trees) if broken is not None else None, (0, "REFUSED"))
    check("control-unbroken", classified(rotclaim, GATE.read_text(), trees), (0, "VERIFIED"))
    check("disk-unwritten", (GATE.read_bytes() == gate_bytes, LEDGER.read_bytes() == ledger_bytes), (True, True))
    check("rows-pointer-is-not-live", len(rows_hits(pinned, ledger, trees)), 0)
    check("rows-retired-sha-on-the-next-line-is-pin",
          rows_scored(rotclaim, ledger + f"\n{retired}\n", trees), (0, 1, "PIN", "ABSENT"))
    check("rows-current-sha-on-the-next-line-is-live",
          rows_scored(rotclaim, ledger + f"\n{cur}\n", trees), (1, 0, "ABSENT", "LIVE"))

    ok = sum(1 for r in rows if "\tstate=OK\t" in r)
    print("\n".join(rows))
    print(f"vendordep-census-plant: {'OK' if ok == len(rows) and rows else 'REFUSED'} ({ok} of {len(rows)})")
    return PASS if ok == len(rows) and rows else REFUSED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
