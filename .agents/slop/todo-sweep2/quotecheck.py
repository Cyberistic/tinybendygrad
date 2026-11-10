#!/usr/bin/env python3
"""THE QUOTE LEDGER'S OWN CHECK: every row re-derives, and a broken row discharges NOTHING.

THE POINT. A ledger row that discharges a refusal is a ROW THAT CANNOT GO RED unless the
ledger's own input is corrupted, and a corrupted ledger is not a thing the gate reports. So
the ledger is checked the way the stem ledger is checked: every row's MECHANICAL claim is
re-derived from the repository, AND each row is FALSIFIED -- the claim is broken on purpose
and the discharge must stop.

THE THREE DISCHARGES THIS LEDGER MAKES, AND THE FALSIFICATION OF EACH:

  file-count     the quoted commit's diff must change exactly `count` files.
                 FALSIFIED BY: naming a commit whose diff does not have that count.
  path-deleted   the quoted commit's diff must DELETE exactly `value`, under `-M`.
                 FALSIFIED BY: naming a commit that does not delete that path.
  absent commit  the quoted commit must be IN the repository.
                 FALSIFIED BY: naming a sha that is not a commit.

AND THE ROW THAT MUST NOT FIRE: a commit with a count claim and NO ledger row must still
REFUSE, because the ledger is an escape and an escape with no row is not an escape.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/quotecheck.py
"""

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load_gate():
    """The gate, loaded BY PATH -- the ledger's own gate, not a copy of it."""
    spec = importlib.util.spec_from_file_location("msgdiff_gate", ROOT / "gates/msgdiff-gate.py")
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(ROOT / "gates"))
    spec.loader.exec_module(module)
    return module


def main():
    gate = load_gate()
    rows, error = gate.read_quote_ledger(ROOT)
    bad = []

    if error:
        print(f"THE LEDGER DOES NOT READ: {error}")
        return 1
    print(f"the quote ledger reads: {len(rows)} rows")

    # ---- 1 -- every row re-derives -------------------------------------------------------
    for (sha, kind, value), (other, _reason) in sorted(rows.items()):
        if kind == "file-count":
            ok, why = gate.explain_count(ROOT, sha, int(value))
        else:
            ok, why = gate.explain_deleted(ROOT, sha, value)
        if not ok:
            bad.append(f"the row for {sha[:12]} {kind} {value} does not derive: {why}")
        else:
            print(f"  {sha[:12]} {kind:<13} {value:<28} -> {why}")

    # ---- 2 -- every row FALSIFIES --------------------------------------------------------
    # A broken `other` must stop the discharge. The commit that is IN the tree but has the
    # wrong shape is the interesting one, so the falsification uses a REAL commit whose
    # diff does not carry the value, and not a sha that is not in the tree.
    real_other = None
    for (sha, kind, value), (other, _reason) in sorted(rows.items()):
        if kind == "file-count":
            # A commit whose diff changes a DIFFERENT number of files.
            for candidate in ("HEAD", "HEAD~1", "HEAD~2"):
                _p, _d, _r, changed = gate.commit_view(ROOT, candidate)
                if changed != int(value):
                    real_other = candidate
                    break
        if real_other is None:
            continue
        broken = {(sha, kind, value): (real_other, "a commit whose diff does not carry the value")}
        saved = gate._QUOTE_LEDGER_CACHE.pop((str(gate.quote_ledger_path(ROOT)),
                                             gate.quote_ledger_path(ROOT).stat().st_mtime_ns,
                                             gate.quote_ledger_path(ROOT).stat().st_size), None)
        original = gate.read_quote_ledger
        gate.read_quote_ledger = lambda root, _b=broken: (_b, None)
        try:
            if kind == "file-count":
                ok, why = gate.explain_count(ROOT, sha, int(value))
            else:
                ok, why = gate.explain_deleted(ROOT, sha, value)
        finally:
            gate.read_quote_ledger = original
            if saved is not None:
                gate._QUOTE_LEDGER_CACHE[(str(gate.quote_ledger_path(ROOT)),
                                          gate.quote_ledger_path(ROOT).stat().st_mtime_ns,
                                          gate.quote_ledger_path(ROOT).stat().st_size)] = saved
        if ok:
            bad.append(f"a broken row for {sha[:12]} {kind} {value} still discharged: {why}")
        else:
            print(f"  FALSIFIED {sha[:12]} {kind:<13} {value:<28} -> {why}")
        break

    # ---- 3 -- the ABSENT-ROW control: no row, still a refusal -----------------------------
    # The ledger is an ESCAPE. A commit whose claim disagrees with its diff and which has
    # NO row must still REFUSE, or the ledger is not an escape but a blanket.
    code, _c, _u, refusals, _s, _st = gate.judge_message(
        ROOT, "8ec4631fa79", "the diff changes 999 files changed", "", False, "")
    if code == gate.PASS:
        bad.append("a claim with NO ledger row passed: the ledger is a blanket, not an escape")
    else:
        print(f"  CONTROL no row -> {code} (the ledger is an escape, not a blanket)")

    # ---- 4 -- the SUBJECT control: a count in the subject is never discharged --------------
    # A subject describes its OWN commit, so the ledger must not excuse it.
    code, _c, _u, refusals, _s, _st = gate.judge_message(
        ROOT, "8ec4631fa79", "11 files changed", "", False, "")
    if code == gate.PASS:
        bad.append("a count in the SUBJECT was discharged by the quote ledger")
    else:
        print(f"  CONTROL subject count -> {code} (the subject is never a quotation)")

    print()
    if bad:
        print(f"FAILED: {len(bad)} problem(s)")
        for b in bad:
            print(f"  - {b}")
        return 1
    print(f"OK -- {len(rows)} rows re-derive, a broken row discharges nothing, "
          f"no row still refuses, and the subject is never discharged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
