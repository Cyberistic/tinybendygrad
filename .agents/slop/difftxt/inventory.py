#!/usr/bin/env python3
"""The `.txt` inventory for `checks/differ.py`'s OUTPUT CONTRACT, derived rather than typed.

    usage: .venv/bin/python .agents/slop/difftxt/inventory.py

THE DECLARED SET COMES FROM THE GENERATOR, not from a list written here. `differ.py` builds its
artifact names out of its own `WANT`/`PLANTS`/`CONTROLS`/`STAB` tables plus thirteen literals, so
a list typed into this file would be a second copy of a contract that already exists in code -- and
a second copy is what goes stale without anyone noticing.

The load-bearing output is not the name list. It is, per name, WHICH INSTRUMENT NAMES IT: "is this
a constant or a contract" is not a property of the name, it is a property of who reads it.
"""
import importlib.util
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("d", ROOT / "checks/differ.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

LITERALS = ("D0-selfcheck", "D1-verdicts", "D2-bytediff", "D0-run-summary", "D4-cross-range",
            "D7-conf", "D8-dbg-012", "D8-dbg-03", "D9-stability", "D10-zerorow-guard",
            "D0-coverage-census", "D8b-cpython-dbg1-reachability", "D0-ops-probe")
# Read, never parsed: the question is "does this file's own text name the artifact", and a mention
# in a comment is still a coupling -- a reader who greps for the name finds it.
# `differ.py` is DELIBERATELY NOT IN THIS TABLE. Its set is derived from it above, and its names
# are f-string templates (`f"D6-{g}-ordered.txt"`) that contain neither the family nor the member,
# so a text search would UNDERCOUNT it -- which is how the first run of this script reported 14
# artifacts as named by nobody when the generator names every one of them.
OTHERS = {
    "oracle-run.sh (FROZEN, sha256-pinned)": ".agents/slop/diffpy/oracle-run.sh",
    "oracle-repro.sh (FROZEN, sha256-pinned)": ".agents/slop/diffpy/oracle-repro.sh",
    "corpus-figure.py (mentions it; its only READ is D0-run-summary.txt)": "checks/corpus-figure.py",
}
DOCS = ("AGENTS.md", "checks/README.md", ".agents/TODO.md", ".agents/TOOLS.md")


def declared() -> set[str]:
    """EVERY `.txt` name `cmd_run` writes. The count is a denominator, so it is printed."""
    return {n + ".txt" for n in LITERALS} \
        | {f"D1-graph-{g}.txt" for g in d.WANT} \
        | {f"D2-canon-{s}-{g}.txt" for g in d.WANT for s in ("py", "bend")} \
        | {f"D2-cmp-{g}.txt" for g in d.WANT} \
        | {f"D3-control-{g}.txt" for g in d.CONTROLS} \
        | {f"D5-plant-{p}.txt" for p, _ in d.PLANTS} \
        | {f"D6-{g}-{k}.txt" for g in ("matmul", "commute") for k in ("ordered", "equiv")} \
        | {f"D9-stability-{g}-{s}.txt" for g, _ in d.STAB for s in "ab"}


def prefixes(stem: str) -> list[str]:
    """Every hyphen-delimited prefix of the stem, longest first. A file names the artifact if it
    contains ANY of them, because a shorter prefix reaches strictly more members: the frozen
    oracle writes `D9-stability-$g-a.txt` and globs `D9-stability-*.txt`, neither of which
    contains the stem `D9-stability-commute-a`. Stopping at the longest common prefix of the
    family instead UNDERCOUNTED those ten, and `D6-` likewise covers `D6-srcswap-*`, which the
    oracle spells differently from the generator -- the measured 4-LOST/4-NEW name finding.
    """
    parts = stem.split("-")
    return ["-".join(parts[:i + 1]) + "-" for i in range(len(parts) - 1)] or [stem]


def named_by(names: list[str], body: str) -> bool:
    """True iff this file's own text contains a hyphen-prefix of any member's stem."""
    probes = {p for n in names for p in prefixes(n.removesuffix(".txt"))}
    return any(re.search(rf"(?<![A-Za-z0-9-]){re.escape(p)}", body) for p in probes)


def main() -> None:
    dec = declared()
    fam: dict[str, list[str]] = {}
    for n in sorted(dec):
        fam.setdefault(n.rsplit("-", 1)[0] if "-" in n else n, []).append(n)
    srcs = {k: (ROOT / v).read_text() for k, v in OTHERS.items() if (ROOT / v).exists()}
    on_disk = {p.name for p in (ROOT / "runs/graphcmp/D").glob("*.txt")}
    print(f"DECLARED `.txt` SET: {len(dec)} names in {len(fam)} families, all derived from\n"
          f"`checks/differ.py`'s own tables -- so this file holds no second copy of the list.\n")
    print(f"  on disk under runs/graphcmp/D : {len(on_disk)}")
    print(f"  declared but ABSENT          : {sorted(dec - on_disk) or 'none'}")
    print(f"  on disk but UNDECLARED       : {sorted(on_disk - dec) or 'none'}")
    print("    (an orphan is a PASS-shaped file no command produces -- the defect `cmd_run`'s")
    print("     stale-prune exists to prevent, and the only thing that ever caught it,")
    print("     `D1-verdicts.txt`, does not look at file NAMES.)\n")

    # `differ.py` GENERATES all 103; the table counts how many of the OTHER instruments also name
    # each family, which is the coupling a rename has to move.
    readers = {k: [who for who, body in srcs.items() if named_by(names, body)] + ["differ.py"]
               for k, names in fam.items()}
    depth = Counter(len(v) for k, v in readers.items() for _ in fam[k])
    print("HOW MANY INSTRUMENTS NAME EACH ARTIFACT -- what decides constant vs contract:")
    for k in sorted(depth):
        print(f"  {k} instrument(s) name {depth[k]:>3} of {len(dec)}")
    solo = sorted(n for k, v in readers.items() if len(v) == 1 for n in fam[k])
    print(f"  => {len(dec) - len(solo)} of {len(dec)} are named by TWO OR MORE instruments, so a")
    print("     rename must move all of them at once or the pair silently stops agreeing.")

    print("FAMILIES, AND WHO ELSE NAMES EACH:\n")
    for key, names in fam.items():
        print(f"  {len(names):>3}x  {key}-*")
        for r in readers[key]:
            print(f"          {'generates' if r == 'differ.py' else 'named by'} {r}")

    print("\nDOCS NAMING ONE:")
    for doc in DOCS:
        p = ROOT / doc
        if p.exists():
            hits = {m for m in re.findall(r"D[0-9]+[a-z]?-[A-Za-z0-9{}*.=-]*\.txt", p.read_text())}
            print(f"  {doc}: {len(hits)} distinct name(s)")


if __name__ == "__main__":
    main()