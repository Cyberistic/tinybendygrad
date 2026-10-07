#!/usr/bin/env python3
"""THE RENAMED-CODE CENSUS. AST, NOT TEXT.

    .venv/bin/python .agents/slop/synonyms/census.py

`prune4`'s lesson is why this parses: a regex census reported 183 where the truth was 61,
because `\\.add\\(` matched `seen.add(` on a Python set. A census of VERDICT TOKENS whose
matcher is a regex would make the same mistake on `seen[V] = ...`, on `NAME[...]`, and on
every dict in the tree that is not a declaration. **So: `ast.literal_eval` over each gate's
MODULE BODY, and every code that appears anywhere else in a file is reported separately as
UNDECLARED rather than silently dropped.**

THE POPULATION IS `gates/gates-pop.py:discover()` LOADED BY PATH -- the same one gate-
surface uses, so the twelve are measured against the tree's own definition of a gate and not
against a list written here. THE OWNER IS `gates/gate-surface.py:vocabulary()`, which reads
`gates/gatekit.py`'s module-level unpack BY PATH; re-typing `{0:...,1:...}` here would be the
second copy this report is arguing against.

THE CLASSIFICATION IS DERIVED, NOT DECLARED, and it turns on ONE question that is asked of
the token's own DENOMINATOR rather than of its spelling:

    RENAMED  the gate declares code C with a token T, and the owner names C differently
    UNMAPPED the gate declares code C and the owner has no name for C at all

A renamed code is a SYNONYM or a COLLISION, and that distinction is a question about MEANING,
so this file computes it and prints BOTH readings rather than deciding. See REPORT.md.
"""
import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"


def loaded(path, name):
    """A module BY PATH, never by name -- `gate-surface.py`'s own loader, verbatim in intent."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    sf = loaded(SURFACE, "gate_surface_under_census")
    vocab = sf.vocabulary()                       # {code: NAME} from gates/gatekit.py, BY PATH
    entries, libs = sf.population(ROOT)           # gates-pop.discover(), THE population

    print(f"OWNER  gates/gatekit.py, read by gates/gate-surface.py:vocabulary() BY PATH: "
          f"{', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}")
    print(f"POP    gates-pop.discover(): {len(entries)} entry points, {len(libs)} modules\n")

    rows, undeclared = [], []
    for p in sorted(entries):
        got = sf.declaration(p)
        # MEASURED DEFECT, NOT A COMPATIBILITY SHIM: `gates/gate-surface.py:251` returns a
        # THREE-tuple (`None, None, "UNPARSEABLE (...)"`) where its other six branches return
        # four. So the one gate that is a SYNTAX ERROR crashes every reader that unpacks its
        # result -- and there is no syntax error in the population today, which is why it has
        # never fired. The readers that must survive it are the ones that CANNOT be trusted to
        # crash loudly, because a crash here reads as "this gate declared nothing", which is
        # the answer the census would otherwise have given anyway.
        if len(got) == 3:
            verdicts, _plants, note = None, None, got[2]
            undeclared.append((str(p.relative_to(ROOT)), f"UNPARSEABLE -> 3-tuple: {note}"))
            continue
        verdicts, _plants, _red, note = got
        rel = str(p.relative_to(ROOT))
        if verdicts is None:
            undeclared.append((rel, note or "no VERDICTS in the module body"))
            continue
        for code, token in sorted(verdicts.items()):
            owner = vocab.get(int(code))
            kind = ("COLLISION?" if owner and token.upper() != owner.upper()
                    else "SAME" if owner else "UNMAPPED")
            rows.append((rel, code, token, owner or "-", kind))

    renamed = [r for r in rows if r[4] == "COLLISION?"]
    unmapped = [r for r in rows if r[4] == "UNMAPPED"]
    same = [r for r in rows if r[4] == "SAME"]

    print(f"DECLARED CODES: {len(rows)} over {len({r[0] for r in rows})} declaring gates")
    print(f"  SAME-TOKEN    {len(same)}")
    print(f"  RENAMED       {len(renamed)}   <-- the population of the collision question")
    print(f"  UNMAPPED      {len(unmapped)}  (the owner has no name for the code at all)\n")

    print("RENAMED, BY TOKEN -- SYNONYM OR COLLISION IS A QUESTION OF MEANING, NOT SPELLING:\n")
    bytok = {}
    for rel, code, tok, owner, _k in renamed:
        bytok.setdefault((code, tok, owner), []).append(rel)
    for (code, tok, owner), rels in sorted(bytok.items()):
        print(f"  exit {code}: {tok!r} vs the owner's {owner!r}  -- {len(rels)} declaration(s)")
        for r in sorted(rels):
            print(f"      {r}")

    if unmapped:
        print("\nUNMAPPED -- the owner has no name for these numbers:\n")
        for rel, code, tok, _o, _k in unmapped:
            print(f"  exit {code}: {tok!r}   {rel}")

    print(f"\nNOT DECLARED AT ALL (no `VERDICTS` in the module body): {len(undeclared)} of "
          f"{len(entries)} entry points")
    for rel, why in undeclared:
        print(f"  {rel:48} {why}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())