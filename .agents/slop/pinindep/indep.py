#!/usr/bin/env python3
"""THE TWO THINGS `sens.py` CANNOT SEE.

1. INDEPENDENCE WITHIN A SHARED ARTIFACT. `sens.py` perturbs one file and asks which pins move.
   It cannot see a pin that moves only as a CONSEQUENCE of another pin moving, which is the
   question that decides whether 17 pins are 17 measurements. So this builds the states the
   sweep cannot reach: a perturbation that moves one pin of a shared artifact WITHOUT moving
   its siblings. Where no such state exists, the pins are not independent measurements and the
   count of independent ones is lower than 17.

2. THE MTIME QUESTION `citeresolve` raised and nobody closed: a pin against a LIVE artifact is
   true and false in the same paragraph, because nothing in the reading path records WHEN the
   artifact was written. Measured here: the pins' source commit against the artifact's mtime,
   over every consumer of `unhealthy()`.
"""
import importlib.util
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402

ROOT = derive.ROOT
PINS = derive.differ.PINS


def pin_moves(before, after):
    return sorted(k for k, v in before if k in PINS and dict(after).get(k) != v)


def divergence_tests():
    """Perturbations that MUST move one pin and MUST NOT move a sibling reading the same file."""
    D0 = ROOT / "runs/graphcmp/D"
    cases = []

    # A DISAGREE graph whose artifact also carries a superseded `VERDICT: AGREE`. `verdict()`
    # takes the LAST match; `files_with` takes ANY match. So expect-moved (which reads
    # `verdict()`) must stay 0 while graphs-agree (which reads the substring anywhere) moves.
    # If this perturbation moves both, the two pins are ONE measurement wearing two hats.
    want_disagree = [g for g, v in derive.differ.WANT.items() if v == "DISAGREE"]
    cases.append(("graphs-agree vs expect-moved, same 34 artifacts",
                  f"D1-graph-{want_disagree[0]}.txt",
                  [("VERDICT: DISAGREE", "VERDICT: AGREE\nSHOULD-VE-LAST VERDICT: DISAGREE")],
                  {"expect-moved"}, "graphs-agree"))

    # byte-identical and not-comparable are two greps of ONE file. A report that says
    # BYTE-IDENTICAL must move only the first; one that says NOT COMPARED only the second.
    cases.append(("byte-identical vs not-comparable, same D2-bytediff.txt",
                  "D2-cmp-matmul.txt", [("matmul BYTE-IDENTICAL", "matmul DIFFERS:")],
                  {"not-comparable"}, "byte-identical"))

    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        base = derive.scratch_copy(Path(tmp) / "base")
        derive.compose_bytediff(base)
        derive.compose_stability(base)
        before = derive.rederive(base)
        for n, (name, artifact, edits, must_hold, must_move) in enumerate(cases):
            D = derive.scratch_copy(Path(tmp) / f"c{n}")
            derive.compose_bytediff(D)
            derive.compose_stability(D)
            p = D / artifact
            body = p.read_text(errors="replace")
            for old, new in edits:
                body = body.replace(old, new, 1)
            p.write_text(body)
            derive.compose_bytediff(D)
            derive.compose_stability(D)
            moved = set(pin_moves(before, derive.rederive(D)))
            wanted = {must_move}
            rows.append((name, artifact, sorted(wanted & moved), sorted(moved & must_hold),
                         sorted(moved)))
    del D0
    return want_disagree, rows


def mtime_facts():
    """WHEN was each pin's source last written, and WHEN was the artifact it reads written?"""
    D = ROOT / "runs/graphcmp/D"
    summary = D / "D0-run-summary.txt"
    git = lambda *a: subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True,
                                    text=True).stdout.strip()
    last_commit = git("log", "-1", "--format=%H %cI", "--", "checks/differ.py")
    commit, _, when = last_commit.partition(" ")
    artifact_mtime = datetime.fromtimestamp(summary.stat().st_mtime, timezone.utc)
    # Every consumer of the pins, by DISCOVERY over the tree -- not a hand list.
    consumers = sorted(p for p in (ROOT / "checks").glob("*.py")
                      if "unhealthy" in p.read_text(errors="replace")
                      or "differ_pins" in p.read_text(errors="replace"))
    consumers += sorted(p for p in (ROOT / "gates").glob("*.py")
                        if "unhealthy" in p.read_text(errors="replace"))
    return {
        "pin_source_commit": commit, "pin_source_when": when,
        "artifact_mtime": artifact_mtime.isoformat(),
        "artifact_newer": artifact_mtime > datetime.fromisoformat(when),
        "age_hours": round((artifact_mtime - datetime.fromisoformat(when)).total_seconds() / 3600, 2),
        "consumers": [str(p.relative_to(ROOT)) for p in consumers],
        "artifacts_in_D": len([p for p in D.glob("*") if p.is_file()]),
        "summary_written_among": sorted(
            p.name for p in D.glob("*") if p.is_file() and p.stat().st_mtime > summary.stat().st_mtime),
    }


if __name__ == "__main__":
    ok, msg = derive.selfcheck()
    print(msg)
    if not ok:
        raise SystemExit(1)
    disagree, rows = divergence_tests()
    print(f"\n== WITNESSES WANT DISAGREE (n={len(disagree)}): {', '.join(disagree)} ==\n")
    print("== INDEPENDENCE WITHIN A SHARED ARTIFACT ==")
    print(f"{'CLAIM':44} {'MOVED (wanted)':22} {'ALSO MOVED (redundant)':24}")
    for name, artifact, moved, also, everything in rows:
        print(f"{name:44} {', '.join(moved) or '**NONE**':22} "
              f"{', '.join(also) or 'none -- INDEPENDENT':24}")
    f = mtime_facts()
    print("\n== THE MTIME QUESTION ==")
    print(f"pin source   : checks/differ.py at {f['pin_source_commit'][:12]}  {f['pin_source_when']}")
    print(f"artifact read: runs/graphcmp/D/D0-run-summary.txt  {f['artifact_mtime']}")
    print(f"artifact NEWER than the pin's source: {f['artifact_newer']} "
          f"(by {f['age_hours']} h)")
    print(f"files in D: {f['artifacts_in_D']}; written AFTER the summary: "
          f"{len(f['summary_written_among'])}")
    print(f"pin consumers (discovered, not listed): {', '.join(f['consumers'])}")
