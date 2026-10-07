#!/usr/bin/env python3
"""vocab-check.py -- IS THERE ONE VERDICT VOCABULARY, OR FIVE?

    .venv/bin/python .agents/slop/onemodule/vocab-check.py            # the census, rc charged
    .venv/bin/python .agents/slop/onemodule/vocab-check.py --report   # census only, rc 0

THE QUESTION, and why it is not the brief's. The brief asks who OWNS the verdict vocabulary and
proposes one module for population, vocabulary and declaration. Measured, those are THREE subjects
and `gates/gatekit.py:60` already owns the middle one. So this file does not consolidate: **it
checks whether the thing that already has an owner is actually USED, and it answers by discovery.**

BY DISCOVERY, twice over. The population is an `os.walk` over every `.py` under `checks/` and
`gates/` — never a hand list of the five spellings, because a census of copies that names the
copies cannot see a sixth. And the MAPPING is read as a source literal per file (by `ast`, off the
module body, never by import — importing a gate RUNS it), so a file that derives its exits from
`gatekit` is distinguishable from one that re-spells them, which is the only distinction that
matters here.

THE THREE FINDINGS, all measured:

  1. COPIES. `gates/gatekit.py` owns `PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5`. Four other files
     spell it themselves. They AGREE today -- and they agree by hand, with nothing comparing
     them, so a SIXTH verdict would be invisible to all of them. Two of the four have already
     dropped `SKIP`, which doctrine 2 of `AGENTS.md` says is one of the five.
  2. THE OWNER IS NOT AN EXIT THE TREE CAN NAME. `gates/gate-surface.py:131` prints
     `REFUSED, NOT A VERDICT` and exits **2**. `gatekit` uses 0/1/3/4/5, so 2 is in NO vocabulary,
     and `.agents/slop/hooks/run.py:116` maps an unrecognised rc to `DEAD` -- so a refusal is
     scored DEAD by the tree's own runner. This is the instrument whose subject is "a gate that
     exits 0 having measured nothing is worse than no gate" and it cannot report its own
     precondition-absent state in its own words.
  3. DECLARATIONS ARE NOT VOCABULARIES. A gate's `VERDICTS = {0: "PASS", 1: "FAIL"}` is a claim
     about ITSELF; `gatekit.VERDICT` is the tree's meaning for a code. Counting a declaration as a
     copy of the vocabulary is the error that produced "13 gates declare a surface" being read as
     a second vocabulary.

EXIT: 0 green · 1 red · 2 REFUSED (an empty population: a census of zero copies is not a census).
`--report` always 0. RED is the correct current verdict and is the deliverable.
"""
from __future__ import annotations

import argparse
import ast
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
HOMES = ("checks", "gates")          # the same two homes `gates/gates-pop.py:HOMES` names
THE_FIVE = {"PASS": 0, "FAIL": 1, "REFUSED": 3, "SKIP": 4, "DEAD": 5}


def refuse(*why: str) -> None:
    """exit 2 = REFUSED, and NOT a verdict. Before any measurement: an assertion downstream of
    what it asserts cannot turn an exception into a refusal."""
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    sys.exit(2)


def gatekit():
    """`gates/gatekit.py` BY PATH, never by name: `gates/` is not a package, and an instrument
    loaded by a bindable name is an instrument whose population anybody can choose."""
    import importlib.util
    p = ROOT / "gates" / "gatekit.py"
    if not p.is_file():
        refuse("gates/gatekit.py is gone -- it OWNS the vocabulary, and this file cannot check "
               "whether the copies agree with an owner that is absent")
    spec = importlib.util.spec_from_file_location("om_gatekit", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def spells(src: str) -> dict | None:
    """The five-exit MAPPING, read off the module body by `ast` -- never by import.

    Two shapes are accepted because two shapes are in the tree: the tuple-unpacking form
    (`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`) and the dict form (`EXITWORDS = {...}`).
    A partial mapping is returned too, and PARTIAL is the finding: a file carrying four of the
    five has not agreed with the owner, it has diverged from it silently.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    out: dict[str, int] = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            tgt = node.targets[0]
            # tuple unpacking: A, B, C = 0, 1, 3
            if isinstance(tgt, ast.Tuple) and isinstance(node.value, ast.Tuple) \
                    and len(tgt.elts) == len(node.value.elts):
                for name, val in zip(tgt.elts, node.value.elts):
                    if isinstance(name, ast.Name) and name.id in THE_FIVE \
                            and isinstance(val, ast.Constant) and isinstance(val.value, int) \
                            and not isinstance(val.value, bool):
                        out[name.id] = val.value
            # dict literal: NAME = {"PASS": 0, ...}
            if isinstance(node.value, ast.Dict):
                d = {}
                for k, v in zip(node.value.keys, node.value.values):
                    if isinstance(k, ast.Constant) and k.value in THE_FIVE \
                            and isinstance(v, ast.Constant) and isinstance(v.value, int) \
                            and not isinstance(v.value, bool):
                        d[k.value] = v.value
                if len(d) >= 3:
                    out.update(d)
    return out or None


def declared_verdicts(src: str) -> dict | None:
    """A gate's SELF-declaration (`VERDICTS = {...}`). A DIFFERENT SUBJECT from the vocabulary:
    this one is a claim about this file, and it is deliberately NOT counted as a copy of
    `gatekit.VERDICT`. Reading one as the other is how "13 gates declare a surface" got read as
    a second vocabulary."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "VERDICTS" for t in node.targets):
            try:
                v = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                return None
            return v if isinstance(v, dict) else None
    return None


def population(root=ROOT):
    """DISCOVERY: every `.py` under the two homes, recursively. `__pycache__` is skipped by name
    -- and that is admitted as the one name-shaped rule here, because it is a DIRECTORY the tree
    generates, and the alternative (`rglob` + suffix filter) counts a `.pyc`."""
    out = []
    for home in HOMES:
        h = root / home
        if not os.path.isdir(h):
            continue
        for dp, dns, fns in os.walk(h):
            dns[:] = [d for d in dns if d != "__pycache__"]
            for fn in sorted(fns):
                if fn.endswith(".py"):
                    out.append(Path(dp) / fn)
    return out


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args(argv)

    gk = gatekit()
    # `gatekit.VERDICT` is CODE -> NAME (`{0: 'PASS', ...}`, read from `gates/gatekit.py:61`); the
    # constant every copy re-spells is NAME -> CODE. The first version inverted this and the
    # `refuse()` below caught it at exit 2 -- which is precisely what a refusal placed BEFORE any
    # measurement is for, and why the two maps are written out here rather than compared by eye.
    owner = {name: code for code, name in gk.VERDICT.items()} if hasattr(gk, "VERDICT") else None
    if not owner or owner != THE_FIVE:
        refuse(f"gates/gatekit.py does not spell the five exits; it spells {owner}")

    files = population()
    if not files:
        refuse("empty population -- a census of 0 copies is not a census")

    copies, decls = [], []
    for p in files:
        src = p.read_text(errors="replace")
        m = spells(src)
        if m:
            copies.append((str(p.relative_to(ROOT)), m, p.name == "gatekit.py"))
        d = declared_verdicts(src)
        if d is not None:
            decls.append((str(p.relative_to(ROOT)), d))

    other = [c for c in copies if not c[2]]
    partial = [(p, m) for p, m, _ in other if m != THE_FIVE]
    disagree = [(p, m) for p, m, _ in other if m != THE_FIVE and any(m[k] != THE_FIVE[k] for k in m)]

    print(f"OWNER   gates/gatekit.py:60  {THE_FIVE}")
    print(f"POPULATION  {len(files)} .py file(s) under {'/'.join(HOMES)}/ (os.walk, by discovery)")
    print(f"COPIES OF THE VOCABULARY  {len(copies) - 1} other file(s) spell it themselves "
          f"(+1 owner)")
    for p, m, is_owner in copies:
        tag = "OWNER " if is_owner else ("PARTIAL" if m != THE_FIVE else "copy  ")
        print(f"  {tag} {p:44} {m}")
    # The declared maps are keyed by EXIT CODE; the owner's reverse map `owner` is keyed by NAME.
    # Comparing a code against a set of names answers "is this code a verdict NAME", which is
    # always true and so reported all 15 -- the second version of this file, and the same
    # key-direction mistake as the `gk.VERDICT` inversion above. `CODES` is the code set.
    CODES = set(gk.VERDICT)
    outside = [(p, sorted(c for c in d if c not in CODES)) for p, d in decls]
    outside = [(p, c) for p, c in outside if c]
    print(f"\nDECLARATIONS (a DIFFERENT subject, not counted above)  {len(decls)} gate(s) "
          f"declare their own surface")
    print(f"SELF-DECLARATIONS THAT USE A CODE OUTSIDE THE FIVE  {len(outside)}")
    # THE PAYING ROW. A code the tree's own vocabulary does not name is not a sixth verdict; it is
    # a code two different instruments call REFUSED. `gatekit` says 3, and these gates say 2.
    codes = sorted({c for _, cs in outside for c in cs})
    for p, cs in outside:
        print(f"  outside-the-five {p:44} {cs}")
    if codes:
        print(f"  -> the tree has TWO refusal codes: {sorted(CODES)} from the owner, "
              f"{codes} from {len(outside)} gate(s). "
              f"`.agents/slop/hooks/run.py:116` maps any rc outside the five to DEAD, so a gate "
              f"refusing with {codes[0]} is scored DEAD by the tree's own runner.")

    reds = []
    if other:
        reds.append(f"{len(other)} file(s) re-spell the vocabulary instead of importing it")
    if partial:
        reds.append(f"{len(partial)} spell it PARTIALLY (a silent divergence from the owner)")
    if disagree:
        reds.append(f"{len(disagree)} DISAGREE with the owner on a code they both spell")
    if decls:
        reds.append(f"{len(decls)} gate(s) declare VERDICTS, which is a self-claim and a "
                    f"SEPARATE subject -- do not read it as a second vocabulary")

    print(f"\nVERDICT: {'RED -- ' + '; '.join(reds) if reds else 'GREEN'}")
    if args.report:
        return 0
    return 1 if reds else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))