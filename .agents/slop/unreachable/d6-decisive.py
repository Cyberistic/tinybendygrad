#!/usr/bin/env python3
"""d6-decisive.py -- THE SET, one gate at a time, driven through the interface
each gate ITSELF writes in its own docstring or its own argv reads.

d2's vocabulary discovery MISSED a positional interface (`checks/oracle_f64.py`
reads `sys.argv[1]` and `[2]` positionally, so no `add_argument` literal exists
to find and no `Compare` to harvest).  That is the third blind spot in my own
instruments, so the last gate is settled by running it the way its own header
says to run it, not by an extractor.

For each of the nine that answer rc=3 with no argv (stable over 3 rounds, 5
minutes apart, d3-census.out), this file drives EVERY argv shape the gate's own
text offers and prints the real exit code.  A gate is IN THE SET only if all of
them answer 3.

No .txt.
"""
import os, subprocess, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 40

NINE = [
    "checks/cl-port-gate.py", "checks/dup-census.py", "checks/e2e.py",
    "checks/gate.py", "checks/git-index-guard.py", "checks/nl-gate-noguard.py",
    "checks/nl-gate.py", "checks/oracle_f64.py", "checks/substrate.py",
]

# Every argv shape is either read out of the gate's own source by this file, or
# is the usage line the gate prints itself. Both are the gate's own words.
ARGV = {
    "checks/cl-port-gate.py":   [[], ["--help"], ["--plants"], ["--plants", "--help"]],
    "checks/dup-census.py":     [[], ["--help"], ["--all"], ["--one"], ["--names"]],
    "checks/e2e.py":            [[], ["--help"], ["-h"]],
    "checks/gate.py":           [[], ["--help"], ["--quick"], ["--predict"], ["--tree", "."]],
    "checks/git-index-guard.py":[[], ["--help"], ["snap"], ["check"], ["check", "--expect", "x"]],
    "checks/nl-gate-noguard.py":[[], ["--help"], ["--port-stdout", "@empty"],
                                 ["--oracle-stdout", "@empty"],
                                 ["--port-stdout", "@empty", "--oracle-stdout", "@empty"]],
    "checks/nl-gate.py":        [[], ["--help"], ["--selftest"], ["--compare"],
                                 ["--port-stdout", "@empty", "--oracle-stdout", "@empty"]],
    "checks/oracle_f64.py":     [[], ["--help"], ["@tmpdir", "@rows"], ["@rows", "@rows"]],
    "checks/substrate.py":      [[], ["--help"], ["@bendfile"], ["none"]],
}


def probe(rel, argv):
    """@empty = an EMPTY file; @tmpdir = a temp dir; @rows = a real rows file if
    the tree has one; @bendfile = the tree's own tinybendygrad -- check-only
    entry, which is what substrate.py's own usage names."""
    with tempfile.TemporaryDirectory() as td:
        empty = Path(td) / "empty.rows"
        empty.write_text("")
        cand = REPO / "tinybendygrad/PROOF.bend"
        out = []
        for a in argv:
            out.append({"@empty": str(empty), "@tmpdir": td,
                        "@rows": str(cand) if cand.exists() else str(empty),
                        "@bendfile": str(cand) if cand.exists() else "x"}[a] if a in
                       ("@empty", "@tmpdir", "@rows", "@bendfile") else a)
        try:
            r = subprocess.run([str(PY), str(REPO / rel), *out], cwd=REPO,
                               capture_output=True, text=True, timeout=BUDGET)
        except subprocess.TimeoutExpired:
            return "TIMED-OUT", "", ""
        txt = (r.stdout + r.stderr)
        return r.returncode, txt.strip().splitlines()[:1], txt[-300:]
    return None, None, None


def main():
    print(f"read {time.strftime('%H:%M:%S')}. BUDGET={BUDGET}s per invocation.\n")
    in_set, rows = [], []
    for rel in NINE:
        print(f"===== {rel}")
        verdicts = set()
        for argv in ARGV[rel]:
            rc, first, tail = probe(rel, argv)
            shown = " ".join(a.replace(str(REPO) + "/", "") for a in argv) or "(none)"
            f0 = (first or [""])[0][:86]
            print(f"   argv[{shown:34}] rc={str(rc):9} {f0}")
            verdicts.add(rc)
            rows.append((rel, shown, rc, f0))
            for line in (tail or "").strip().splitlines()[-2:]:
                print(f"        {line[:96]}")
        only3 = verdicts == {3}
        if only3:
            in_set.append(rel)
        print(f"   -> {'IN THE SET: every argv answers 3' if only3 else 'ARGV-REACHABLE: ' + str(sorted(verdicts, key=str))}\n")

    print(f"THE SET (no argv this gate declares reaches an exit other than 3): {len(in_set)}")
    for r in in_set:
        print(f"  {r}")

    p = REPO / ".agents/slop/unreachable/d6-decisive.rows"
    with p.open("w") as f:
        f.write("path\targv\trc\tfirst_line\n")
        for rel, a, rc, f0 in rows:
            f.write(f"{rel}\t{a}\t{rc}\t{f0}\n")


if __name__ == "__main__":
    main()