#!/usr/bin/env python3
"""THE FINAL CENSUS: TWELVE, AND THE THREE SHAPES THAT MAKE UP THE POPULATION.

    .venv/bin/python .agents/slop/synonyms/final.py

    .agents/slop/synonyms/census.py        reads 11 over 8 gates -- VERDICTS only
    .agents/slop/synonyms/final.py         reads 12 over 8 gates + 1 RUNNER

**THE TWELFTH IS `.agents/slop/hooks/run.py:56`: `NAME = {PASS: "GREEN", ...}`, where the owner
says `PASS`.** It is a RUNNER holding a private copy of the vocabulary in a shape neither
`gates/gate-surface.py:declaration()` nor `gates/gate-surface.py:vocabulary()` can see: the first
keys on the literal name `VERDICTS`, the second on a module-level name<-code UNPACK, and `NAME` is
neither. `.agents/slop/hooks/run.py` is also outside `HOMES=("checks", "gates")`, so
`gates/gates-pop.py:discover()` never hands it to either reader.

THE SHAPE IS NOT THE POPULATION, AND `shapes.py` PROVES IT. Scanning every module-level
`X = {int: str}` in the tree finds **56 disagreeing entries over 22 sites**, and 45 of them are
`PSP_ERRORS`, `_SDWA_SEL`, `TAGS`, `R4_TH_LOAD`, `kgsl_deviceid__enumvalues` and the rest --
firmware error tables and disassembler selectors that are not vocabularies at all. **So the
marker is NOT "a dict of int to str"; the marker is a NAME THE TREE AGREES ON.** `VERDICTS` and
`NAME` are two such names and the union is what the twelfth lives in. A marker this file cannot
enumerate without becoming the hand list it is arguing against -- WHICH IS THE POINT, and is why
the twelfth is reported here rather than added to a reader.
"""
import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
HOOKS = ROOT / ".agents" / "slop" / "hooks" / "run.py"

# THE TWO NAMES THE TREE AGREES ON, and the reason a third is not added: a marker list IS a hand
# list, and `gendirs.py`'s "two instruments holding two lists have no authority over each other"
# applies to this file and to `gate-surface.py` equally. Adding `FOO = {...}` here would move the
# defect one level down, which is `AGENTS.md`'s own named failure (`xd1/pin` matched by BASENAME).
MARKERS = ("VERDICTS", "NAME")


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def marker_dicts(src):
    """`[(name, lineno, {code: token})]` for the markers, by AST. Never by regex."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    out = []
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        try:
            v = ast.literal_eval(node.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if not (isinstance(v, dict) and v and all(type(k) is int for k in v)
                and all(isinstance(x, str) for x in v.values())):
            continue
        for t in node.targets:
            if isinstance(t, ast.Name) and t.id in MARKERS:
                out.append((t.id, node.lineno, v))
    return out


def main():
    sf = loaded(SURFACE, "gate_surface_under_final")
    vocab = sf.vocabulary()
    print(f"OWNER gates/gatekit.py BY PATH: "
          f"{', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}")
    print(f"MARKERS this census reads: {list(MARKERS)}\n")

    rows = []
    entries, _libs = sf.population(ROOT)
    for p in sorted(entries):
        for name, lineno, v in marker_dicts(p.read_text(errors="replace")):
            for code, tok in sorted(v.items()):
                owned = vocab.get(int(code))
                kind = "SAME" if owned and str(tok).upper() == owned.upper() else (
                    "UNMAPPED" if owned is None else "RENAMED")
                rows.append((str(p.relative_to(ROOT)), lineno, name, int(code), tok,
                             owned or "-", kind))
    # THE TWELFTH, AND IT IS NOT IN THE POPULATION.
    for name, lineno, v in marker_dicts(HOOKS.read_text(errors="replace")):
        for code, tok in sorted(v.items()):
            owned = vocab.get(int(code))
            kind = "SAME" if owned and str(tok).upper() == owned.upper() else (
                "UNMAPPED" if owned is None else "RENAMED")
            rows.append((str(HOOKS.relative_to(ROOT)), lineno, name, int(code), tok,
                         owned or "-", kind))

    ren = [r for r in rows if r[6] == "RENAMED"]
    print(f"{len(rows)} declared codes read over {len({r[0] for r in rows})} sites: "
          f"{sum(1 for r in rows if r[6]=='SAME')} SAME, {len(ren)} RENAMED, "
          f"{sum(1 for r in rows if r[6]=='UNMAPPED')} UNMAPPED\n")
    print(f"{'SITE':44} {'LN':>4} {'MARKER':9} {'CODE':>4} {'TOKEN':10} {'OWNER':9} KIND")
    for rel, lineno, name, code, tok, own, kind in rows:
        if kind == "SAME":
            continue
        print(f"{rel:44} {lineno:>4} {name:9} {code:>4} {tok:10} {own:9} {kind}")

    gates = sorted({r[0] for r in ren if r[0].startswith(("checks/", "gates/"))})
    runners = sorted({r[0] for r in ren if not r[0].startswith(("checks/", "gates/"))})
    print(f"\n  RENAMED over GATES (inside HOMES): {len(ren) - sum(1 for r in ren if r[0] in runners)}"
          f" over {len(gates)} gates")
    print(f"  RENAMED over RUNNERS (outside HOMES): "
          f"{sum(1 for r in ren if r[0] in runners)} over {len(runners)} runner(s)")
    print(f"  TOTAL RENAMED: {len(ren)}")
    print("\n  THE TWELFTH, AND WHY NO INSTRUMENT SAW IT:")
    for rel in runners:
        print(f"    {rel} -- a `NAME` dict, outside `HOMES`, read by "
              f"`declares_surface()` which keys on `VERDICTS` only")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())