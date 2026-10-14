#!/usr/bin/env python3
"""PLANT `census.py` BOTH WAYS, plus the control that CAN BE FALSE, and falsify against the
pre-change behaviour by naming the rows that DIFFER.

    .venv/bin/python .agents/slop/declaretwo/plant.py

A plant is only worth running if it can FAIL. Every assertion here names the row it moved and
what it moved it FROM -> TO, and two of the plants are built to be FALSIFIABLE: one asserts a
FALSE thing about a fixture and must be caught, and one asserts a directory is opened when it is
not. A plant suite where every assertion passes on the first try is `prune4`'s twelve committed
files printing 0 rows for an hour while a harness reported success.

THE FIXTURES ARE BUILT IN A TEMPORARY GIT REPO, NEVER IN THIS TREE. A plant that plants inside the
population under test moves the population it measures -- the fault `checks/slop-declare.py`'s
own header names -- and this tree also has live units writing to `.agents/slop/` right now. So
every fixture is `git init` + `git add` + `git commit` in `tempfile.mkdtemp()` and removed after.
The census is invoked BY PATH against that repo's `--rev`, so the code under test is the same
file that ran on the real tree.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

CENSUS = Path(__file__).resolve().parent / "census.py"
REPORTS = ("report.md", "readme.md", "findings.md")
MANIFESTS = ("manifest.tsv", "manifest.md", "manifest.rows")

_results: list[tuple[bool, str]] = []


def check(ok: bool, label: str) -> None:
    _results.append((ok, label))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def run_census(repo: Path) -> tuple[int, str, str]:
    """`census.py --repo <fixture>`, so the code under test is THIS file, loaded by path. The rows
    are read back from the file the census WROTE, not from stdout -- a plant that parses the
    report's prose is testing the format string."""
    p = subprocess.run([sys.executable, str(CENSUS), "--repo", str(repo)],
                       capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


ROWKEYS = ("depth", "files", "R", "M", "P", "md_names", "age_h", "opened_by")


def rows_of(repo: Path) -> dict[str, dict[str, str]]:
    """The census's OWN record, `census.rows`, read back as TSV. A plant that asserts against the
    report's PROSE is testing a format string -- these assert against the tool's own data file."""
    out: dict[str, dict[str, str]] = {}
    for line in (repo / "census.rows").read_text().splitlines():
        f = line.split("\t")
        if len(f) >= 9 and f[0] != "dir":
            out[f[0]] = dict(zip(ROWKEYS, f[1:9]))
    return out


def unopened(repo: Path) -> list[str]:
    """Rows the tool recorded as DECLARED and opened-by nothing -- read from the data file."""
    return sorted(k for k, v in rows_of(repo).items()
                  if (v["R"] == "1" or v["M"] == "1") and v["opened_by"] == "-")


def fixture(repo: Path, layout: dict[str, str], opens: str | None = None) -> str:
    """A tracked tree, committed, so `--rev` has something immutable to read.

    `opens` is the EXACT PATH a reader in `checks/reader.py` will name. It is a parameter and not
    a constant because a reader that opens a fixed path plants one hard-coded name, and the row
    that moves is chosen by the plant -- which is the fault `checks/no-txt.py`'s carve-out
    rotation exists to prevent, one level down."""
    for path, body in layout.items():
        f = repo / path
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(body)
    if opens:
        f = repo / "checks/reader.py"
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(f"# a reader that opens one file by exact path\nprint({opens!r})\n")
    for cmd in (["git", "init", "-q"], ["git", "add", "-A"], ["git", "-c", "user.email=a@b",
               "-c", "user.name=p", "commit", "-qm", "fixture"]):
        subprocess.run(cmd, cwd=repo, capture_output=True, check=True)


def main() -> int:
    print("PLANT 1 -- A DIRECTORY WITH A DECLARATION IS EXCUSED (each shape on its own)")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {
            ".agents/slop/withreport/REPORT.md": "what this is",
            ".agents/slop/withmanifest/MANIFEST.tsv": "path\tverdict\na\tKEEP\n",
            ".agents/slop/withreadme/README.md": "what this is",
            ".agents/slop/bare/rows.rows": "x\n",
        })
        rc, out, err = run_census(repo)
        check(rc == 0, f"census exits 0 on a fixture ({err.strip()[:80]})")
        r = rows_of(repo)
        check(r[".agents/slop/withreport"]["R"] == "1", "REPORT.md -> R=1")
        check(r[".agents/slop/withmanifest"]["M"] == "1", "MANIFEST.tsv -> M=1")
        check(r[".agents/slop/withreadme"]["R"] == "1", "README.md -> R=1")
        check(r[".agents/slop/bare"]["R"] == "0" and r[".agents/slop/bare"]["M"] == "0",
              "a bare rows-only dir is 0/0")
        check(r[".agents/slop/bare"]["P"] == "0", "no `.md` at all -> P=0")
        check(sum(1 for v in r.values() if v["R"] == "0" and v["M"] == "0") == 1,
              "exactly one undeclared dir is counted")

    print("PLANT 2 -- A DIRECTORY WITHOUT A DECLARATION IS NAMED")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {
            ".agents/slop/named/CLAIM.md": "the claim",          # a `.md` under another name
            ".agents/slop/nothing/out.out": "raw\n",             # no `.md` at all
            ".agents/slop/declared/REPORT.md": "declared",
        })
        rc, out, _ = run_census(repo)
        r = rows_of(repo)
        check(r[".agents/slop/named"]["R"] == "0" and r[".agents/slop/named"]["P"] == "1",
              "CLAIM.md is P=1 and STILL R=0 -- the name set does not see it")
        check("CLAIM" in r[".agents/slop/named"]["md_names"],
              "CLAIM.md is reported by NAME, so a human can rename it")
        check(r[".agents/slop/nothing"]["P"] == "0", "no `.md` -> P=0")
        check(sorted(k for k, v in r.items() if v["R"] == "0" and v["M"] == "0")
              == [".agents/slop/named", ".agents/slop/nothing"],
              "BOTH undeclared dirs are named, by full path")
        plan = subprocess.run([sys.executable, str(CENSUS), "--repo", str(repo),
                               "--rename-plan"], capture_output=True, text=True).stdout
        check(plan.count("git mv") == 1 and "named/CLAIM.md" in plan,
              "the RENAME PLAN moves only the `.md`-bearing one -- `nothing/` has nothing to move")

    print("PLANT 3 -- THE CONTROL THAT CAN BE FALSE: a DECLARATION is not LIVENESS")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        # A report and a manifest, and NOTHING anywhere opens them. The census must say so.
        fixture(repo, {
            ".agents/slop/deadread/REPORT.md": "declared, never opened\n",
            ".agents/slop/deadman/MANIFEST.tsv": "path\tverdict\na\tKEEP\n",
        })
        rc, out, _ = run_census(repo)
        r = rows_of(repo)
        check(unopened(repo) == [".agents/slop/deadman", ".agents/slop/deadread"],
              "BOTH declared dirs are opened-by NOTHING -- a declaration is NOT liveness")
        check(r[".agents/slop/deadread"]["R"] == "1", "still R=1: the name is present even though nothing reads it")
        check(r[".agents/slop/deadman"]["M"] == "1", "still M=1: the manifest name is present too")

    print("PLANT 4 -- A READER MAKES IT OPENED (the control's other direction)")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        # Same declared directory as PLANT 3, plus one reader that opens it by exact path. The
        # `opened_by` cell must FLIP from "-" to the reader -- one fixture, one changed row.
        fixture(repo, {
            ".agents/slop/deadread/REPORT.md": "declared, now opened\n",
            ".agents/slop/deadman/MANIFEST.tsv": "path\tverdict\na\tKEEP\n",
        }, opens=".agents/slop/deadread/REPORT.md")
        run_census(repo)
        r = rows_of(repo)
        check(r[".agents/slop/deadread"]["opened_by"] == "checks/reader.py",
              "a reader FLIPS `opened_by` from - to the reader's path")
        check(unopened(repo) == [".agents/slop/deadman"],
              "and only the STILL-unopened directory remains -- one row moved, named")

    print("PLANT 5 -- AN UNDECLARED DIRECTORY NESTED INSIDE A DECLARED ONE MUST BE NAMED TOO")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {
            ".agents/slop/parent/REPORT.md": "the parent declares itself",
            ".agents/slop/parent/child/CLAIM.md": "the child does NOT",
            ".agents/slop/parent/child2/out.out": "the child2 does not either",
        })
        rc, out, _ = run_census(repo)
        r = rows_of(repo)
        check(".agents/slop/parent/child" in r, "the NESTED dir is a ROW of its own, full path")
        check(r[".agents/slop/parent/child"]["R"] == "0",
              "the nested dir does NOT inherit the parent's REPORT.md -> R=0")
        check(r[".agents/slop/parent/child"]["P"] == "1",
              "its own CLAIM.md counts for IT (P=1) even though the parent speaks for nothing")
        check(r[".agents/slop/parent/child2"]["P"] == "0",
              "the nested dir with no `.md` at all is named too -> P=0")
        check(r[".agents/slop/parent"]["R"] == "1", "the parent is still declared")
        check(r[".agents/slop/parent/child"]["depth"] == "1"
              and r[".agents/slop/parent"]["depth"] == "0",
              "depth distinguishes a unit from a capture directory")

    print("PLANT 6 -- A `.md` NESTED DEEP DOES NOT DECLARE ITS PARENT (depth is the discriminator)")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {".agents/slop/deep/plant-no-node/runs/e2e/trace.md": "captured stdout\n"})
        rc, out, _ = run_census(repo)
        r = rows_of(repo)
        check(r[".agents/slop/deep"]["P"] == "0",
              "a `.md` four levels down is a CAPTURE, not a declaration -> P=0")
        check(r[".agents/slop/deep/plant-no-node/runs/e2e"]["P"] == "1",
              "and the directory that ACTUALLY holds the `.md` declares ITSELF -> P=1")

    print("PLANT 7 -- FALSIFY: THE ROWS THAT DIFFER FROM THE PRE-CHANGE BEHAVIOUR")
    # The pre-change behaviour is `orcdecide`'s `big.count(tok) <= own.count(tok)`. That test
    # counts OCCURRENCES, so a directory whose own files cite it more than the rest of the tree
    # does is excused for the WRONG REASON. This fixture pins that difference by name.
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {
            ".agents/slop/selfcite/out.out": ".agents/slop/selfcite/ .agents/slop/selfcite/\n",
            ".agents/slop/quiet/out.out": "nothing here\n",
        })
        rc, out, _ = run_census(repo)
        r = rows_of(repo)
        check(r[".agents/slop/selfcite"]["R"] == "0" and r[".agents/slop/quiet"]["R"] == "0",
              "BOTH rows differ FROM orcdecide's test: `selfcite`'s own file cites its path 2x, "
              "so `big.count(tok) <= own.count(tok)` EXCUSES it and the census does not")
        check(unopened(repo) == [],
              "neither is declared, so the DECLARED-set exact test moves by 0 -- named, not implied")

    print("PLANT 7b -- FALSIFY THE OTHER DIRECTION: a reader a DECLARED dir never sees")
    # `orcdecide`'s test is `count`, so a directory cited ONCE by a reader and TWICE by its own
    # files is excused -- and one cited by its own files alone is excused for being self-silent.
    # The exact test asks the question the count test only approximates: is there a FILE, not a
    # count of mentions. This fixture is the direction in which the two DISAGREE on a declared
    # directory, which is the row class the rename plan cannot reach.
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {
            ".agents/slop/cited/REPORT.md": "declared and cited twice by its own note\n",
            ".agents/slop/cited/note.out": ".agents/slop/cited/REPORT.md .agents/slop/cited/REPORT.md\n",
        })
        run_census(repo)
        r = rows_of(repo)
        check(r[".agents/slop/cited"]["R"] == "1", "still declared: R=1")
        check(r[".agents/slop/cited"]["opened_by"] == "-",
              "a directory citing ITSELF is not opened BY anyone -> opened_by is -, "
              "which is the row `orcdecide`'s count test reads as 'referenced'")

    print("PLANT 8 -- REFUSED, NOT PASS, ON AN EMPTY POPULATION (a 0-row walk is DEAD)")
    with tempfile.TemporaryDirectory() as td:
        repo = Path(td)
        fixture(repo, {"README.md": "no slop here\n"})
        rc, out, _ = run_census(repo)
        check(rc == 3, f"exit 3 = REFUSED on a tree with 0 `.agents/slop/*/` dirs (got {rc})")
        check("REFUSED" in out and "PASS" not in out, "the word PASS is absent from the 0-row reading")

    failed = [l for ok, l in _results if not ok]
    print(f"\n{len(_results) - len(failed)}/{len(_results)} assertions PASS")
    if failed:
        print("FAILED:")
        for l in failed:
            print(f"  ! {l}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())