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

    ## THE CARVE-OUTS, AND WHY EACH IS NARROW

    A `.txt` is excused ONLY when the code that PRODUCES it declares the name, loaded by path — never
    by a list typed here. Three declarations are loaded, each beside its own generator, and the
    excused set is `found & (all three)`. A generator that stops writing its name stops excusing it,
    because the name comes from the same declaration the writer uses:

    | generator (loaded by path) | declares | why the name is forced |
    |---|---|---|
    | `checks/differ.py:declared()` | the graphcmp artifacts **and their `.tmp.<name>` staging** | `differ.run()` stages each output as `.tmp.<name>` and `os.replace`s it (`:304`), so a concurrent run puts `.tmp.<declared>.txt` on disk; the staging name is DERIVED from `declared()`, not listed |
    | `.agents/slop/figure2/plant.py:declared()` | its two plant summaries | `checks/corpus-figure.py` reads `runs/graphcmp/D/D0-run-summary.txt` under its OWN root and the plant root is a shadow copy — renaming stops the plant from testing anything |
    | `.agents/slop/txtexec/rename.py:LEFT_EMPTY` | the deliberate 0-byte remnant | `oracles/rows-bd.txt` is 0 bytes with NO generator; the renamer LEFT it a `.txt` on purpose, and the excuse is honoured only while the file is STILL 0 bytes |

    The graphcmp set is an OUTPUT CONTRACT between two drivers, not constants in one script:

    | named by | how |
    |---|---|
    | `checks/differ.py` | writes every declared name; reads 12 by name in its own summary block |
    | `.agents/slop/diffpy/oracle-run.sh` | **sha256-pinned**; writes every declared name, reads 12 by name |
    | `.agents/slop/diffpy/oracle-repro.sh` | **sha256-pinned**; reads `D0-run-summary.txt` at `:61`, globs `*.txt` at `:105` |
    | `checks/corpus-figure.py:72` | reads `D0-run-summary.txt` and refuses on it |

    MEASURED: **every declared name is named by two or more instruments.** A rename must move all of them in
    one commit or a pair silently stops agreeing — and the pin cannot help, because a sha256 over an
    oracle's BYTES says nothing about which names that oracle READS. `.agents/slop/difftxt/` holds the
    inventory and the one-place-rename experiment, including the measurement that the emptiness guard
    fell from 53 findings to 0 while the pin still reported intact.

    So a carve-out is never the DIRECTORY, which would also excuse residue: it is a generator's own
    `declared()` set, IMPORTED, so a `.txt` under `runs/graphcmp/D/` that no command writes is still
    reported, and an orphan under a plant root is still reported. `checks/differ.py:artefacts_ok()`
    reads the same declaration for the same reason. A loader that FAILS returns an empty set, so the
    files are REPORTED — a carve-out that cannot be computed must never become a blanket exemption.

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
#
# `test/` IS UPSTREAM TINYGRAD'S OWN SUITE, NOT THIS PROJECT'S — `AGENTS.md`, `Testing`: *"`test/` IS
# UPSTREAM TINYGRAD'S SUITE AND IS THE ORACLE, NOT OUR TESTS"* — and NO author of this project has a
# commit under it (measured 2026-10-06: `git log --format=%ae -- test/` carries 287 distinct
# addresses and 0 `tinybendygrad@localhost`). Its one `.txt`,
# `test/models/efficientnet/imagenet1000_clsidx_to_labels.txt`, is the 999-line ImageNet index that
# upstream's `test_efficientnet.py` reads; the last commit to touch it is upstream's own
# `8919ca816 test cleanups` (George Hotz, 2023-03-03). This project does not own it, so owning it
# here was the same class of false positive as walking `tinygrad/` would have been.
SKIP = {".git", "references", "node_modules", "__pycache__", "test"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
GRAPH_D = "runs/graphcmp/D"
PLANT = ".agents/slop/figure2/plant.py"
RENAMER = ".agents/slop/txtexec/rename.py"


def owned(path: str) -> bool:
    parts = path.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def load(rel: str, name: str):
    """A generator, imported BY PATH so its own declaration is the population."""
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def graphcmp_artifacts() -> set[str]:
    """The `.txt` names `checks/differ.py` DECLARES, as project-relative paths, PLUS their staging.

    IMPORTED, NOT COPIED. A second list of the declared names in this file would itself be a contract with no
    generator, which is the failure this carve-out exists to avoid; `differ.py` is importable because
    its `main()` sits behind `if __name__ == "__main__"`. If the import fails the set is empty and the
    artifacts get REPORTED, because a carve-out that cannot be computed must never become a blanket
    exemption — it would exempt the directory silently and print nothing.

    `differ.run()` writes each output to `.tmp.<name>` and `os.replace`s it into place (`differ.py:304`),
    so a CONCURRENT `differ.py run` puts `.tmp.<declared>.txt` on disk for a window and the walk catches
    it. That staging name is DERIVED from the declaration — the same rule the writer applies — so it
    moves with `declared()` and cannot go stale behind it.
    """
    names = load("checks/differ.py", "differ").declared()
    return {os.path.join(GRAPH_D, n) for n in (*names, *((".tmp." + n) for n in names))}


def plant_artifacts() -> set[str]:
    """The `D0-run-summary.txt` a `checks/corpus-figure.py` plant writes, per its own generator.

    `checks/corpus-figure.py` reads `runs/graphcmp/D/D0-run-summary.txt` under its OWN root and the plant
    roots are shadow copies of the repo layout, so the plant MUST carry that exact path/name or it tests
    nothing. DECLARED by `figure2/plant.py:declared()`, the script that writes it, LOADED by path.
    """
    plant = load(PLANT, "figure2_plant")
    return {str((plant.PLANT / r / plant.SUMMARY_REL).relative_to(ROOT)) for r in plant.ROOTS}


def empty_remnants() -> set[str]:
    """`.txt` a renamer LEFT by decision because the file is EMPTY — re-checked here as 0 bytes.

    `oracles/rows-bd.txt` is 0 bytes with NO generator: the orphan of `checks/sb-gate.sh`'s `rows-bd.txt`
    row-dump name, whose live counterpart is `oracles/schedule-bodies/rows-bd.rows`. The declaration is
    the renamer's decision (`txtexec/rename.py:LEFT_EMPTY`), and it is honoured only while the file is
    STILL 0 bytes, so the excuse lapses the moment it gains content.
    """
    paths = load(RENAMER, "txtexec_rename").LEFT_EMPTY
    return {p for p in paths if os.path.exists(os.path.join(ROOT, p))
            and os.path.getsize(os.path.join(ROOT, p)) == 0}


def skipexit_artifacts() -> set[str]:
    """`skipexit/repro.py`'s PRE-FIX LANE outputs, DERIVED from the frozen lane's own write sites.

    The lane it runs IS the pre-fix code (`.agents/slop/skipexit/prefix/checks/e2e.py` at `3ed5ab069^`),
    so a run re-emits `.txt` under each fixture's `runs/e2e/`. Its `declared()` is that frozen gate's write
    names crossed with the fixture roots, so it MOVES WITH THE LANE: rename a write and the excuse goes with it.
    """
    return set(load(".agents/slop/skipexit/repro.py", "skipexit_repro").declared())


def carveouts() -> tuple[tuple[str, set[str]], ...]:
    """(label, declared set) per generator. A loader that raises contributes nothing but a report."""
    out = []
    for label, fn in (("`checks/differ.py`'s graphcmp artifacts + `.tmp.` staging", graphcmp_artifacts),
                      ("`.agents/slop/figure2/plant.py`'s forced plant summaries", plant_artifacts),
                      ("`.agents/slop/txtexec/rename.py`'s deliberate 0-byte remnant", empty_remnants),
                      ("`.agents/slop/skipexit/repro.py`'s PRE-FIX LANE outputs", skipexit_artifacts)):
        try:
            out.append((label, fn()))
        except Exception as e:                     # a carve-out that cannot be computed is not one
            print(f"  CARVE-OUT UNCOMPUTED ({label}): {e!r} — its files are REPORTED")
    return tuple(out)


def excused_names() -> set[str]:
    """Every carved-out path — the union of all generator declarations, loaded by path.

    `checks/txt-owners.py` asks for this rather than subtracting one group, so the two instruments
    cannot hold two opinions about which files are exempt; a second opinion about an exemption is how
    an exemption becomes a blanket.
    """
    return set().union(*(declared for _, declared in carveouts()))


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
    groups = carveouts()
    excused = set(found) & set().union(*(declared for _, declared in groups))
    hard = [rel for rel in found if rel not in excused]
    # PRINTED, ALWAYS, WITH ITS COUNT AND ITS DECLARING GENERATOR. A carve-out nobody can see in the
    # output is a carve-out nobody audits, and these are standing exceptions to the rule the rest of
    # this file exists to enforce. An orphan under a carved directory is NOT in any `declared()` set
    # and is printed below as hard.
    for label, declared in groups:
        n = len(set(found) & declared)
        if n:
            print(f"  {n} `.txt` EXCUSED: {label} (loaded by path, imported not copied).")
    if not hard:
        print("  CLEAN: no .txt anywhere the project owns, outside those named exceptions")
        return 0
    print(f"  {len(hard)} .txt FILE(S). `.txt` IS NOT AN EXTENSION THIS PROJECT USES.")
    for rel in hard[:40]:
        print(f"    {rel}")
    if len(hard) > 40:
        print(f"    ... and {len(hard) - 40} more")
    return 1


if __name__ == "__main__":
    sys.exit(main())
