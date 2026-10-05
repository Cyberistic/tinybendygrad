#!/usr/bin/env python3
"""Refuse a `.txt` file. MEASURED 2026-10-05: this project held **795** of them.

    .agents/slop 258   oracles 259   runs 109   checks 24   gates 24

**386 OF THEM WERE NAMED BY NOTHING** — no gate, no report, no `AGENTS.md` — so they were pure scratch
carrying an extension that says "text" and therefore says nothing else. The rest were named, which
made the extension the *only* honest signal left: `.rows` already existed and `sweep.py`'s
`ORACLE_WORD` already matched it, so **the convention predated the rule and the rule is what was
missing.**

**A `.txt` EXTENSION IS A DECLARATION THAT THE AUTHOR DID NOT KNOW WHAT THE FILE WAS.** Every other
extension here states the content: `.rows` expected values, `.out`/`.err` captured streams, `.tsv`
tabular, `.md` prose. `.txt` is the absence of that, and a sweep that classifies by basename cannot
tell a row dump from a diary entry — WHICH IS THE SAME FAILURE AS `ORACLE_WORD`, ONE LEVEL DOWN.

    ## THE ONE CARVE-OUT, AND WHY IT IS NARROW

    `runs/graphcmp/D/` holds **103 `.txt` files this project therefore does not flag**, and every one
    of them is named by `checks/differ.py` — which is why the author *did* know what they were. They
    are an OUTPUT CONTRACT between two drivers, not constants in one script:

    | named by | how |
    |---|---|
    | `checks/differ.py` | writes all 103; reads 12 by name in its own summary block |
    | `.agents/slop/diffpy/oracle-run.sh` | **sha256-pinned**; writes all 103, reads 12 by name |
    | `.agents/slop/diffpy/oracle-repro.sh` | **sha256-pinned**; reads `D0-run-summary.txt` at `:61`, globs `*.txt` at `:105` |
    | `checks/corpus-figure.py:72` | reads `D0-run-summary.txt` and refuses on it |

    MEASURED: **103 of 103 are named by two or more instruments.** A rename must move all of them in
    one commit or a pair silently stops agreeing — and the pin cannot help, because a sha256 over an
    oracle's BYTES says nothing about which names that oracle READS. `.agents/slop/difftxt/` holds the
    inventory and the one-place-rename experiment, including the measurement that the emptiness guard
    fell from 53 findings to 0 while the pin still reported intact.

    So the carve-out is not the DIRECTORY, which would also excuse residue: it is the generator's own
    `declared()` set, IMPORTED, so a `.txt` under `runs/graphcmp/D/` that no command writes is still
    reported. `checks/differ.py:artefacts_ok()` reads the same declaration for the same reason.

    usage: .venv/bin/python checks/no-txt.py

    exit 0  no unexcused .txt anywhere the project owns
    exit 1  at least one, each printed with its full path and the byte that names it
"""
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Trees that are not this project: the git object store, the upstream clone, the tinygrad checkouts
# a port graph imports, and the report trees inside shadow copies of the source.
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
GRAPH_D = "runs/graphcmp/D"


def owned(path: str) -> bool:
    parts = path.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def graphcmp_artifacts() -> set[str]:
    """The `.txt` names `checks/differ.py` DECLARES, as project-relative paths.

    IMPORTED, NOT COPIED. A second list of 103 names in this file would itself be a contract with no
    generator, which is the failure this carve-out exists to avoid; `differ.py` is importable because
    its `main()` sits behind `if __name__ == "__main__"`. If the import fails the set is empty and the
    artifacts get REPORTED, because a carve-out that cannot be computed must never become a blanket
    exemption — it would exempt the directory silently and print nothing.
    """
    spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks/differ.py"))
    differ = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(differ)
    return {os.path.join(GRAPH_D, n) for n in differ.declared()}


def main() -> int:
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in sorted(filenames):
            if not f.endswith(".txt"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
            if owned(rel):
                found.append(rel)
    excused = set(found) & graphcmp_artifacts()
    hard = [rel for rel in found if rel not in excused]
    if excused:
        # PRINTED, ALWAYS, WITH ITS COUNT. A carve-out nobody can see in the output is a carve-out
        # nobody audits, and this one is a standing exception to the rule the rest of this file exists
        # to enforce. An orphan under GRAPH_D is NOT in `declared()` and is printed below as hard.
        print(f"  {len(excused)} `.txt` EXCUSED: `checks/differ.py`'s declared graphcmp artifacts,"
              f" which a sha256-pinned oracle reads BY NAME (oracle-repro.sh:61, :105; corpus-figure.py:72).")
    if not hard:
        print("  CLEAN: no .txt anywhere the project owns, outside that one named exception")
        return 0
    print(f"  {len(hard)} .txt FILE(S). `.txt` IS NOT AN EXTENSION THIS PROJECT USES.")
    for rel in hard[:40]:
        print(f"    {rel}")
    if len(hard) > 40:
        print(f"    ... and {len(hard) - 40} more")
    return 1


if __name__ == "__main__":
    sys.exit(main())
