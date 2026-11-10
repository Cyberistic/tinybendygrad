#!/usr/bin/env python3
"""CLAIM THE REPOSITORY ROOT's **DIRECTORY** SET, WHICH NO INSTRUMENT IN THIS TREE CLAIMS.

THE GAP, MEASURED. `checks/no-strays.py` CLAIMS "**every FILE at the repository root**" -- IT
SCOPES ITSELF TO FILES, AND ITS `root_files()` IS
`sorted(p for p in ROOT.iterdir() if p.is_file() and p.name not in ROOT_ENTRIES)`. **⇒ A STRAY
ROOT **DIRECTORY** IS INVISIBLE TO IT, AND THAT IS NOT A DEFECT IN IT: THE CLAIM IS ABOUT FILES.**

**⇒ AND A SEARCH OVER EVERY `checks/*.py` AND `gates/*.py` FINDS **NO** INSTRUMENT THAT
LOOKS AT THE ROOT's DIRECTORY SET AT ALL.** THE ONE CANDIDATE,
`gates/retention-check.py:150`, WALKS A DIRECTORY's SUBDIRECTORIES FOR THE
`gates/artifacts/` RETENTION QUESTION, NOT THE ROOT's OWN DIRECTORIES.

**⇒ SO A DIRECTORY NAMED AFTER A FLAG SITS AT THE REPO ROOT AND **NOTHING IN THE TREE CAN SEE
IT**.** MEASURED: `./--help/` EXISTS, IS **UNTRACKED**, IS **NOT GITIGNORED**, AND WAS CREATED
BY `checks/run-f64.sh`'s `W=${1:-...}` TAKING `--help` AS ITS SCRATCH DIRECTORY. THE CAUSE IS
**FIXED** (`19eb01580` REFUSES A FLAG-SHAPED ARGUMENT AND A PATH INSIDE THE REPO, BOTH rc 3),
BUT THE **RESIDUE IS UNOWNED** -- **⇒ AND A RESIDUE NO INSTRUMENT CAN SEE IS A RESIDUE THAT
CANNOT BE CLEANED BY ANY RULE.**

⇒ **⇒ AND THE FIX IS **NOT** "ADD `--help` TO A LIST".** THE POPULATION IS **DISCOVERED**: the
root's directories are what `ROOT.iterdir()` holds, and the CLAIM is a comparison against the
directories the tree **KNOWS IT OWNS**. A HAND LIST OF THE OWNED DIRECTORIES WOULD BE A LIST,
AND A LIST IS WHAT THIS LEDGER KEEPS FINDING.

⇒ **⇒ SO THE INSTRUMENT READS THE OWNED SET **BY DISCOVERY**, FROM THE PLACES THAT NAME IT:**
  - **`checks/no-strays.py`'s `ROOT_ENTRIES`** -- the tree's OWN list of what lives at the
    root, loaded **BY PATH**, and **⇒ ITS DIRECTORY MEMBERS ARE THE OWNED SET.**
  - **`git ls-tree HEAD`** -- the directories the COMMIT TREE carries. **⇒ A DIRECTORY THAT IS
    IN THE COMMIT TREE IS OWNED WHATEVER ITS NAME IS**, AND THAT IS THE HALF A LIST CANNOT
    ANSWER.

⇒ **⇒ AND THE INSTRUMENT'S THREE VERDICTS ARE THE ONES THIS TREE USES:**
  - **PASS** -- every root directory is owned.
  - **FAIL** -- a root directory is owned by NOTHING (neither the commit tree, nor the tree's
    own root list).
  - **REFUSED** -- the inputs could not be read, so nothing was measured.

⇒ **⇒ AND THE ROW MUST BE FALSIFIABLE.** A ROW THAT NAMES A STRAY DIRECTORY AND CANNOT GO
RED IS WORSE THAN NO ROW, **⇒ SO THE INSTRUMENT PLANTS ONE**: it computes the verdict for a
DIRECTORY NAME THAT IS **DEFINITELY** NOT OWNED AND ASSERTS THE VERDICT IS **FAIL**. **⇒ AND
A PLANT THAT PASSES IS A BROKEN INSTRUMENT, NOT A CLEAN TREE.**

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/rootdirs.py
        .venv/bin/python .agents/slop/todo-sweep2/rootdirs.py --plant
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# **⇒ THE REPO ROOT IS `parents[3]` FROM THIS FILE, WHICH IS THE REPO ROOT.**
# **⇒ AND THE FIRST VERSION OF THIS LINE GUESSED AT IT** (`ROOT.parent.parent`) AND
# READ `/Users/cyberistic/src/checks/no-strays.py`, WHICH IS **ABOVE THE REPO** --
# **⇒ A PATH THAT IS OFF BY TWO LEVELS IS A PATH THAT FINDS SOMETHING ELSE.**
REPO = ROOT if (ROOT / ".git").exists() else ROOT.parents[3]


def git(*args):
    return subprocess.run(("git",) + args, cwd=REPO, capture_output=True, text=True).stdout


def owned_by_commit_tree():
    """The directory names the COMMIT TREE carries at the root. DISCOVERED, never listed."""
    out = git("ls-tree", "-d", "--name-only", "HEAD")
    return {n for n in out.splitlines() if n}


def owned_by_the_trees_own_list():
    """The DIRECTORY members of `checks/no-strays.py`'s `ROOT_ENTRIES`.

    LOADED **BY PATH** -- the tree's OWN list of what lives at the root, and **⇒ ITS DIRECTORY
    MEMBERS ARE THE OWNED SET.** A LIST IS NOT A POPULATION, BUT A LIST THAT IS **THE TREE's OWN
    RECORD OF ITS OWN ROOT** IS A WITNESS, NOT A HAND LIST THIS INSTRUMENT CHOSE.
    """
    path = REPO / "checks/no-strays.py"
    src = path.read_text(errors="replace")
    m = re.search(r'ROOT_ENTRIES = set\("""\n(.*?)\n"""\.split\(\)\)', src, re.S)
    if not m:
        return None
    names = m.group(1).split()
    return {n for n in names if not n.endswith((".md", ".toml", ".json", ".yaml", ".yml",
                                                ".lock", ".cfg", ".ini", ".txt", ".sh", ".py"))
            and not n.endswith(".coveragerc") and not n.endswith(".gitignore")}


def root_directories():
    """Every directory at the repo root, EXCLUDING the dot-dirs (`.git`, `.venv`, ...).

    **⇒ THE DOT-DIRS ARE EXCLUDED BY NAME AND NOT BY A LIST**, because a dot-dir is a
    CONVENTION the tree and its tools share, and the tree's own `no-strays.py` excludes them
    the same way (`SCRATCH_NAME`'s `^` + `.` arm).
    """
    return sorted(p for p in REPO.iterdir() if p.is_dir() and not p.name.startswith("."))


def verdict(owned, dirs):
    """(code, unexplained). The code is the tree's vocabulary: PASS / FAIL / REFUSED."""
    if owned is None:
        return "REFUSED", []
    unexplained = [d.name for d in dirs if d.name not in owned]
    return ("FAIL", unexplained) if unexplained else ("PASS", [])


def main():
    plant = "--plant" in sys.argv
    commit = owned_by_commit_tree()
    roots = owned_by_the_trees_own_list()
    dirs = root_directories()

    print(f"the repo root: {REPO}")
    print(f"root directories found: {len(dirs)}")
    print()
    if commit is None or roots is None:
        print("REFUSED: an input could not be read, so nothing was measured")
        return 3
    owned = set(commit) | set(roots)
    print(f"owned by the commit tree : {len(commit)}")
    print(f"owned by the tree's own root list : {len(roots)}")
    print(f"the OWNED SET (union)     : {len(owned)}")
    print()
    for d in dirs:
        mark = "owned " if d.name in owned else "STRAY "
        print(f"  {mark} {d.name}")

    code, unexplained = verdict(owned, dirs)
    print()
    print(f"VERDICT: {code}")
    for u in unexplained:
        print(f"  unexplained root directory: {u}")

    if plant:
        # **⇒ THE PLANT. A DIRECTORY NAME THAT IS **DEFINITELY** NOT OWNED MUST PRODUCE
        # FAIL. A PLANT THAT PASSES IS A BROKEN INSTRUMENT, NOT A CLEAN TREE.**
        fake = [type("D", (), {"name": "zz-plant-not-a-real-root-directory"})]
        pcode, pun = verdict(owned, fake)
        print()
        print(f"PLANT: a directory named {fake[0].name!r} -> {pcode} "
              f"{pun} (the expected verdict is FAIL)")
        if pcode != "FAIL" or not pun:
            print("PLANT FAILED: the instrument cannot go red, so its PASS is not a verdict")
            return 1
        print("PLANT OK: the instrument CAN go red")

    if code == "FAIL":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
