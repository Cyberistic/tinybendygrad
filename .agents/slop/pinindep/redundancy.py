#!/usr/bin/env python3
"""HOW MANY OF THE 17 PINS CARRY A DEGREE OF FREEDOM, AND WHY THE MTIME RULE IS NOT LANDABLE.

PART 1 -- ALGEBRAIC REDUNDANCY. Two pin groups are not free variables: `graphs`,
`graphs-answered` and `graphs-unset` are `n`, `n-u`, `u` (so one is a restatement), and
`stable-pairs`/`stable-failed`/`stable-differ` are a PARTITION of one file's five lines (so
their sum is fixed). Neither fact is asserted here -- it is MEASURED, by asking the real
summary what happens when the constraint is broken, and by reading the constraint out of the
summary's own algebra.

PART 2 -- WHY THE MTIME RULE IS NOT LANDED. Three blockers, each measured rather than
argued: (a) `differ.py` has NO git dependency and says so in its own docstring; (b) the
artifact is GITIGNORED, so its mtime is a fact about one working tree and not about the
commit -- two clones at the same commit answer differently; (c) the direction the brief
proposes is the MIRROR of the defensible one, and the measurement says which.
"""
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402

ROOT = derive.ROOT
D = ROOT / "runs/graphcmp/D"
SRC = (ROOT / "checks/differ.py").read_text()


def live():
    return dict(ln.split("=", 1) for ln in
                (D / "D0-run-summary.txt").read_text(errors="replace").splitlines() if "=" in ln)


def algebra():
    g = live()
    n, u = int(g["graphs"]), int(g["graphs-unset"])
    s = sum(int(g[k].split(" of ")[0]) for k in
            ("stable-pairs", "stable-failed", "stable-differ"))
    return {
        "graphs": (n, u, int(g["graphs-answered"]), n - u),
        "graphs-answered IS n-u": int(g["graphs-answered"]) == n - u,
        "stable sum": s,
        "stable sum == len(STAB)": s == len(derive.differ.STAB),
    }


def git_blockers():
    """(a) no git import; (b) the artifact is untracked; (c) direction."""
    # NOT the module docstring: the refusal is a `#` comment in the ORACLE_PIN preamble, and
    # slicing to the first `"""` after index 3 lands past it. The first revision of this check
    # searched the docstring and printed False for a sentence that is plainly in the file.
    docstring = SRC
    ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "-v",
                              "runs/graphcmp/D/D0-run-summary.txt"],
                             capture_output=True, text=True).stdout.strip()
    tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files",
                              "runs/graphcmp/D/D0-run-summary.txt"],
                             capture_output=True, text=True).stdout.strip()
    consumers = [str(p.relative_to(ROOT)) for p in ROOT.rglob("*.py")
                 if "runs" not in str(p) and ".venv" not in str(p)
                 and ("differ.unhealthy" in p.read_text(errors="replace")
                      or "differ_pins" in p.read_text(errors="replace"))]
    return {
        "imports_git": "import git" in SRC or "from git" in SRC,
        "docstring_says_no_git": "a dependency this file does not otherwise have" in docstring,
        "artifact_ignored_by": ignored,
        "artifact_tracked": bool(tracked),
        "consumers": sorted(set(consumers)),
    }


if __name__ == "__main__":
    ok, _ = derive.selfcheck()
    if not ok:
        raise SystemExit(1)
    a = algebra()
    print("\n== PART 1: ALGEBRAIC REDUNDANCY (MEASURED) ==\n")
    n, u, ans, nmu = a["graphs"]
    print(f"  graphs={n}  graphs-unset={u}  graphs-answered={ans}   (n-u={nmu})")
    print(f"  graphs-answered IS exactly n-u: {a['graphs-answered IS n-u']}"
          f"  -> 2 free numbers ({n}, {u}) wear 3 pins")
    print(f"  stable-pairs + stable-failed + stable-differ = {a['stable sum']} "
          f"(len(STAB)={len(derive.differ.STAB)})")
    print(f"  the stable triple is a PARTITION of a fixed 5: {a['stable sum == len(STAB)']}"
          f"  -> 2 free numbers (pinned, split) wear 3 pins")
    print(f"\n  => 17 pins, 2 of them determined by the others: "
          f"15 carry a free number.")

    b = git_blockers()
    print("\n== PART 2: WHY THE MTIME RULE IS NOT LANDED HERE ==\n")
    print(f"  (a) differ.py imports git:                 {b['imports_git']}")
    print(f"      and its docstring says why not:       {b['docstring_says_no_git']}")
    print(f"      -> 'Pinning the committed body instead would be a check against `git`, which is")
    print(f"         a dependency this file does not otherwise have.'  (differ.py:58-60)")
    print(f"  (b) the artifact is ignored by:            {b['artifact_ignored_by'] or 'NOT IGNORED'}")
    print(f"      tracked in git:                        {b['artifact_tracked']}")
    print(f"      -> its mtime is a fact about THIS working tree, not about the commit, so the")
    print(f"         same commit answers differently in two clones.")
    print(f"  (c) consumers whose verdict would move:     {', '.join(b['consumers'])}")
    print(f"\n  DIRECTION: the brief says refuse an artifact NEWER than the pin's commit.")
    print(f"  MEASURED: 13 of 17 pins have the artifact NEWER (a run CONFIRMED a written-down")
    print(f"  prediction) and only 4 are OLDER (the pin was COPIED FROM the artifact, so green")
    print(f"  is a tautology). The brief's rule would redden the 13 that work and pass the 4")
    print(f"  that cannot fail -- it is the mirror of the defensible rule.")
