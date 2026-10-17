"""GATE the structural re-vendor census: a new `READ-AND-BROKEN` row is a FAIL, not a fact to note.

    .venv/bin/python gates/revendor-struct-gate.py [--json]

WHY THIS IS NOT `gatekit.Gate`. That class is a BEND DRIVER and a CPython ORACLE with a row
count; this gate has neither lane -- it compares two git REVISIONS of upstream with an AST
census and diffs the census against a tracked baseline. Filing it as a `Gate` would be a claim
this instrument does not make. What IS reused is `gatekit`'s FIVE EXITS and `verdict_of`, so a
caller reading `$?` gets the same vocabulary every other gate speaks.

THE FIVE VERDICTS ARE EXITS HERE TOO, AND `SKIP` IS NOT `PASS`. A census that could not run --
`git` absent, a revision unresolvable -- is `SKIP` (4) and says so, because a gate that reports
"no breaks" having measured nothing is the failure this whole line of work is about.

THE BASELINE IS A GATE'S INPUT AND LIVES BESIDE THE GATE, in git, at `gates/revendor-struct.rows`.
`.agents/slop/` is being pruned, and a prune once took seven of nine driver and oracle files out
from under these gates; `gates/artifacts/` is `.gitignore`d and is where runs WRITE, so one
`rm -rf` there deletes anything kept in it. Neither is a place to keep a required input.

WHAT FAILS. Two things, and only two:
  1 a NEW verdict of `READ-AND-BROKEN` or `READ-AND-NOT-NOTICED` that the baseline does not
    have -- a structural break with a reader in this tree; and
  2 the census's own CONTROL reporting a `VIOLATED` bucket -- a record the blobs contradict.
Both are the two ways this gate can tell that something moved. A changed `UNREAD` count, a new
`CONST-VALUE` row, a different `UNKNOWN`: printed, not failed, because none of them is a break
and a gate that cries wolf on ordinary upstream work gets ignored on the day it matters.
"""
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, SKIP, verdict_of  # noqa: E402

ROWS = HERE / "revendor-struct.rows"
_spec = importlib.util.spec_from_file_location("revendor_struct", HERE.parent / "checks"
                                               / "revendor-struct.py")
RS = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(RS)


def main():
    try:
        census = RS.census()
    except Exception as exc:
        print(f"SKIP: the census could not run: {type(exc).__name__}: {exc}")
        return SKIP
    tally, violations = RS.control(census["recs"], RS.OLD, RS.NEW)
    if any(k.startswith("n/a-") for k in tally) and not any(
            k.endswith("CONFIRMED") for k in tally):
        print(f"SKIP: the control confirmed nothing, so no row can be believed: {tally}")
        return SKIP

    breaks = {r["target"]: r["verdict"] for r in census["recs"]
              if r["verdict"] in ("READ-AND-BROKEN", "READ-AND-NOT-NOTICED")}
    print(f"HEAD           {census['head']}  old={RS.OLD}  new={RS.NEW}")
    print(f"CONTROL        " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    for kind, tgt in violations[:12]:
        print(f"      VIOLATED {kind} {tgt}")

    want = json.loads(ROWS.read_text())["breaks"] if ROWS.exists() else {}
    fresh = {k: v for k, v in breaks.items() if want.get(k) != v}
    gone = [k for k in want if k not in breaks]
    for tgt, verdict in sorted(fresh.items()):
        print(f"NEW-BREAK      {verdict}  {tgt}")
    for tgt in sorted(gone):
        print(f"NO-LONGER      {tgt}  (the baseline had it as {want[tgt]})")
    verdict = FAIL if (fresh or gone or any("VIOLATED" in k for k in tally)) else PASS
    print(f"BREAKS         {len(breaks)} in this census, {len(fresh)} not in the baseline, "
          f"{len(gone)} baseline rows gone")
    print(f"VERDICT        {verdict_of(verdict)}")
    return verdict


if __name__ == "__main__":
    sys.exit(main())