#!/usr/bin/env python3
"""WHAT DOES `bin/bend` RESOLVE TO -- here, in a copied tree, and after the fix.

Four places, one question each, and the question is NOT "did it exit 0":

    AT      this tree, at its real path
    COPY    the tree COPIED to a different absolute path, with a PLANTED
            compiler in its OWN `references/bend`
    NOREF   the same copy with no `references/` at all -- what `git clone` gives
            you, because `.gitignore` carries `references/`
    NOPLANT the copy with a SYMLINK to this machine's real checkout

THE PLANT IS WHY THIS SCRIPT EXISTS.  A shim that hard-codes an absolute path
does not fail in a copied tree -- it silently runs ANOTHER TREE'S COMPILER, and
every gate under it reports a verdict measured against a program nobody chose.
Asking "does it exit 0" cannot see that, because it does exit 0.  So the copy
gets its own `references/bend` whose `bend2/main.ts` prints a marker instead of
being a compiler:

    plant printed the marker  ->  the shim used ITS OWN tree's toolchain
    real compiler printed it  ->  the shim borrowed this machine's checkout

`NO PLANT, NO ANSWER` is a row: if the copy's own toolchain is missing there is
nothing to be used, and the lane proves nothing about preference.

The path question is answered by ASKING THE SHELL, not by grepping the shim for
a path: `${0%/*}` is shell semantics, and a checker that recognises only the
absolute form it was written against cannot report drift to any other form.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BEND_REL = ("references", "bend", "bend2", "main.ts")
MARKER = "PLANT-COMPILER-7a3f"

rows: list[str] = []


def row(name: str, value: object) -> None:
    rows.append(f"{name}={value}")


# --------------------------------------------------------------------------
# HOW THE SHIM RESOLVES.  Asked of `sh`, because it is `sh`'s semantics.
# --------------------------------------------------------------------------
def shim_dir(where: Path) -> str:
    """What `${0%/*}` is for a given `$0`, and the `[ "$d" = "$0" ]` fallback."""
    script = f'_d=${{0%/*}}; [ "$_d" = "$0" ] && _d=.; printf %s "$_d"'
    return subprocess.run(["sh", "-c", script, "x", str(where)], capture_output=True, text=True).stdout


def resolved_target(where: Path) -> Path:
    d = shim_dir(where)
    base = Path(d) if d not in ("", ".") else Path(where).parent
    # `bin/bend` -> the repo root is one level above the shim's own directory.
    return (where.parent.parent / Path(*BEND_REL)).resolve()


def shim_text(where: Path) -> str:
    p = where / "bin" / "bend"
    return p.read_text() if p.exists() else ""


def code_lines(text: str) -> list[str]:
    """The shim's CODE, with `#` comments removed.

    THE FIRST VERSION OF THIS FUNCTION CHECKED THE WHOLE FILE and reported
    `spawns_dirname=True` on a shim that spawns nothing, because the comment
    explaining why `${0%/*}` is used NAMES `dirname`.  A checker that reads the
    prose about the code certifies the prose -- which is this repo's own recorded
    failure, in `.agents/slop/lost/RECOVERED.md` §2: "I COUNTED 4 `stderr` MENTIONS
    AND INFERRED THE FIX FROM A KEYWORD."  Every check below is over `code`.
    """
    return [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]


def static_facts(label: str, where: Path, shim_override: Path | None = None) -> None:
    shim = where / "bin" / "bend"
    text = shim_text(where)
    if shim_override is not None:
        text = shim_override.read_text()
    code = code_lines(text)
    code_text = "\n".join(code)
    row(f"{label}.shim_exists", shim.exists())
    row(f"{label}.shim_exec_bit", bool(shim.stat().st_mode & 0o111) if shim.exists() else False)
    row(f"{label}.shim_code_lines", len(code))
    # an absolute path to a compiler, spelled out
    row(f"{label}.names_an_absolute_path", bool(re.search(r"[\s\"']/[Uu]sers/", code_text)))
    # `cd` moves the CWD, and every one of this repo's 100+ callers passes a
    # relative FILE argument, so a shim that cd's first breaks them all.
    row(f"{label}.cds", any(ln.lstrip().startswith("cd ") for ln in code))
    # POSIX parameter expansion, not an external `dirname`
    row(f"{label}.uses_POSIX_param_expansion", "${0%/*}" in code_text)
    row(f"{label}.spawns_dirname", "dirname" in code_text)

    tgt = resolved_target(shim)
    row(f"{label}.resolves_to", os.path.relpath(tgt, where) if str(tgt).startswith(str(where)) else tgt)
    row(f"{label}.target_inside_own_tree", str(tgt).startswith(str(where.resolve())))
    row(f"{label}.target_exists", tgt.exists())


def plant(where: Path) -> None:
    """A `references/bend` that is a compiler-shaped DIRECTORY PRINTING A MARKER."""
    b2 = where.joinpath("references", "bend", "bend2")
    b2.mkdir(parents=True, exist_ok=True)
    (b2 / "main.ts").write_text(f'#!/usr/bin/env bun\nconsole.log("{MARKER}");\n')
    (b2 / "base.bend").write_text("")


def run_case(label: str, where: Path, shim_override: Path | None = None) -> None:
    shim = where / "bin" / "bend"
    if shim_override is not None:
        # NEVER into REPO.  The first version of this function wrote the
        # substitute into whichever tree it was handed, and the `at` lane hands
        # it the LIVE tree -- so the BEFORE run replaced the fixed `bin/bend`
        # with the absolute one and six units were left running the defect.
        # MEASURED, and it is why this assertion is here rather than a promise:
        # a BEFORE lane that cannot damage the tree it measures.
        if where.resolve() == REPO:
            raise SystemExit(f"REFUSING to substitute a shim into the live tree ({REPO})")
        shim.write_text(shim_override.read_text())
        shim.chmod(0o755)
    if not shim.exists():
        row(f"{label}.run", "NO-SHIM")
        return
    proc = subprocess.run([str(shim), "version"], cwd=where, capture_output=True, text=True)
    out = proc.stdout.strip()
    row(f"{label}.run_rc", proc.returncode)
    row(f"{label}.run_said", MARKER if MARKER in out else (out.splitlines() or ["(silent)"])[0][:80])
    row(f"{label}.used_own_tree", MARKER in out)
    err = proc.stderr.strip()
    # a refusal is a RESULT: it must be loud, and it must name the missing file.
    row(f"{label}.refused_loudly", bool(err))
    row(f"{label}.stderr_first", err.splitlines()[0][:90] if err else "(empty)")


def copy_tree(dst: Path) -> Path:
    shutil.copytree(
        REPO,
        dst,
        ignore=shutil.ignore_patterns(".git", "references", "runs", "__pycache__", ".venv", "tinybendygrad", "tinygrad"),
        symlinks=True,
    )
    return dst


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-run", action="store_true")
    ap.add_argument("--shim", type=Path, help="substitute this shim into every tree (the BEFORE run)")
    args = ap.parse_args()
    shim_override = args.shim

    row("repo", REPO)

    for label, where in (("at", REPO),):
        print(f"== {label.upper()}: {where}", file=sys.stderr)
        static_facts(label, where, shim_override)

    with tempfile.TemporaryDirectory(prefix="bendpin-") as td:
        tmp = Path(td)

        copied = copy_tree(tmp / "copied")
        row("copy_path_is_a_different_absolute_path", str(copied) != str(REPO))

        print(f"== COPY (planted toolchain in the copy's own references/): {copied}", file=sys.stderr)
        plant(copied)
        static_facts("copy", copied, shim_override)

        noref = copy_tree(tmp / "no-refs")
        print(f"== NOREF (no references/ at all -- the clone's shape): {noref}", file=sys.stderr)
        static_facts("noref", noref, shim_override)

        noplant = copy_tree(tmp / "symlinked-refs")
        (noplant / "references").mkdir()
        (noplant / "references" / "bend").symlink_to(REPO / "references" / "bend", target_is_directory=True)
        print(f"== NOPLANT (symlinked to this machine's checkout): {noplant}", file=sys.stderr)
        static_facts("noplant", noplant, shim_override)

        # The `at` lane is ALWAYS the live tree, with no substitution, so a BEFORE
        # run and an AFTER run differ in the shim and in nothing else.
        lanes = [("at", REPO, None), ("copy", copied, shim_override),
                 ("noref", noref, shim_override), ("noplant", noplant, shim_override)]
        if shim_override is not None:
            atcopy = copy_tree(tmp / "at-with-before-shim")
            lanes.insert(1, ("atcopy", atcopy, shim_override))
            print(f"== ATCOPY: a COPY of this tree carrying the BEFORE shim: {atcopy}", file=sys.stderr)
            static_facts("atcopy", atcopy, shim_override)

        if not args.no_run:
            for label, where, override in lanes:
                print(f"== RUN {label}", file=sys.stderr)
                run_case(label, where, override)

    for r in rows:
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())