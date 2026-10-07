#!/usr/bin/env python3
"""`D0-run-summary.txt` RE-DERIVED from the artifacts, by `differ.py`'s OWN expressions.

This file is the instrument for `.agents/slop/pinindep/REPORT.md`. Two properties make its
output trustworthy, and both are checked rather than asserted:

  CONTROL  `rederive(D)` on the LIVE directory must reproduce the live summary BYTE FOR BYTE.
           If it does not, the transcription below is wrong and every negative below is
           a transcription artefact, not a finding. So `selfcheck()` runs it and REFUSES.
  SCOPE    the expressions are copied from `checks/differ.py:571-628` (the `write(...)` call in
           `cmd_run`) and the helpers (`lines_with`, `anchored`, `files_with`, `first_line`,
           `last_line`, `grep_line`, `corpus`) are IMPORTED by path, not retyped. The
           intermediate `D2-bytediff.txt` / `D9-stability.txt` composition is reproduced too,
           because two pins read those compositions rather than the per-graph files.

No `bend`, no `tinygrad`, no write into `runs/graphcmp/D`: `D` is rebound to a scratch copy.
"""
import importlib.util
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRATCH = Path(sys.argv[1]) if len(sys.argv) > 1 else None


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


differ = load("differ_indep", "checks/differ.py")


def rederive(D, dev_rows=()):
    """`checks/differ.py`'s summary lines, recomputed from the artifacts under `D`.

    `dev_rows` overrides `precondition_rows()`, which reads the DEVICE off the artifacts
    through `checks/devpin.py`; a caller that perturbs the device wire-files needs to say what
    it expects instead of silently re-deriving the true answer.
    """
    differ.D = D
    graphs = differ.corpus()
    unset = [g for g in graphs if g not in differ.WANT]
    moved = [g for g in graphs
             if g in differ.WANT and differ.verdict(f"D1-graph-{g}.txt") != differ.WANT[g]]
    files_with, lines_with = differ.files_with, differ.lines_with
    anchored, grep_line = differ.anchored, differ.grep_line
    first_line, last_line = differ.first_line, differ.last_line

    def graphs_agree():
        return files_with("D1-graph-*.txt", "VERDICT: AGREE")

    def graphs_disagree():
        return files_with("D1-graph-*.txt", "VERDICT: DISAGREE")

    def byte_identical():
        return lines_with("D2-bytediff.txt", "BYTE-IDENTICAL")

    def not_comparable():
        return lines_with("D2-bytediff.txt", "NOT COMPARED")

    def stable_pairs():
        return f"{anchored('D9-stability.txt', r': 2 runs BYTE-IDENTICAL$')} of 5"

    def stable_failed():
        return f"{lines_with('D9-stability.txt', 'ONE SIDE IS A 0-ROW FAILURE')} of 5"

    def stable_differ():
        return f"{anchored('D9-stability.txt', r': 2 runs DIFFER$')} of 5"

    rows = [
        ("graphs", str(len(graphs))),
        ("graphs-answered", str(len(graphs) - len(unset))),
        ("graphs-unset", str(len(unset))),
        ("expect-moved", str(len(moved))),
        ("graphs-agree", str(graphs_agree())),
        ("graphs-disagree", str(graphs_disagree())),
        ("byte-identical", str(byte_identical())),
        ("not-comparable", str(not_comparable())),
        ("stable-pairs", stable_pairs()),
        ("stable-failed", stable_failed()),
        ("stable-differ", stable_differ()),
        ("plants-disagree", f"{files_with('D5-plant-*.txt', 'VERDICT: DISAGREE')} of 7"),
        ("cross", f"{lines_with('D4-cross-range.txt', 'CROSS VERDICT: OK')} of 1"),
        ("selfcheck", first_line("D0-selfcheck.txt")),
        ("conflations", f"{lines_with('D7-conf.txt', 'VERDICT: OK')} of 4"),
        ("controls", f"{files_with('D3-control-*.txt', 'CONTROL VERDICT: OK')} of 5"),
        ("oracle-selfcheck", grep_line("D0-coverage-census.txt", "ORACLE SELFCHECK")),
        ("census-rc", last_line("D0-coverage-census.txt")),
    ]
    # `precondition_rows()` yields whole `k=v` STRINGS, not pairs (`differ.py:729`).
    rows += [tuple(ln.split("=", 1)) for ln in (dev_rows or differ.precondition_rows())]
    return rows


def summary_text(rows):
    return "\n".join(f"{k}={v}" for k, v in rows) + "\n"


def compose_bytediff(D):
    """`cmd_run`'s `D2-bytediff.txt`: the `D2-cmp-*` reports concatenated in glob order."""
    differ.D = D
    (D / "D2-bytediff.txt").write_text(
        "".join(f.read_text(errors="replace") for f in sorted(D.glob("D2-cmp-*.txt"))))


def compose_stability(D):
    """`cmd_run`'s `D9-stability.txt`, recomputed from the ten pair files."""
    differ.D = D
    report = []
    for g, _ in differ.STAB:
        a, b = f"D9-stability-{g}-a.txt", f"D9-stability-{g}-b.txt"
        if differ.one_line(a) or differ.one_line(b):
            report.append(f"{g}: ONE SIDE IS A 0-ROW FAILURE after a retry -- NOT a "
                          "reproducibility result")
        elif (D / a).read_bytes() == (D / b).read_bytes():
            report.append(f"{g}: 2 runs BYTE-IDENTICAL")
        else:
            report.append(f"{g}: 2 runs DIFFER\n" + differ.byte_diff(D / a, D / b, 20))
    (D / "D9-stability.txt").write_text("\n".join(report) + "\n")


def selfcheck():
    """The CONTROL. Byte identity over the live run, or the instrument is discarded."""
    D = ROOT / "runs/graphcmp/D"
    live = (D / "D0-run-summary.txt").read_text()
    got = summary_text(rederive(D))
    if got == live:
        return True, "CONTROL OK -- rederive(live) == D0-run-summary.txt BYTE FOR BYTE"
    got_d, live_d = got.splitlines(), live.splitlines()
    diff = [(g, l) for g, l in zip(got_d, live_d) if g != l]
    return False, f"CONTROL FAILED -- {len(diff)} line(s) differ: {diff[:6]}"


def scratch_copy(tmp):
    dst = Path(tmp).resolve()
    dst.mkdir(parents=True, exist_ok=True)
    for p in (ROOT / "runs/graphcmp/D").glob("*"):
        if p.is_file():
            shutil.copy2(p, dst / p.name)
    return dst


if __name__ == "__main__":
    ok, msg = selfcheck()
    print(msg)
    raise SystemExit(0 if ok else 1)
