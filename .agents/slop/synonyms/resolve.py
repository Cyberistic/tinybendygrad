#!/usr/bin/env python3
"""THE SYNONYM RELATIONSHIP, AND THE COLLISION PLANTED BOTH WAYS.

    .venv/bin/python .agents/slop/synonyms/resolve.py
    .venv/bin/python .agents/slop/synonyms/resolve.py --plant

THE RELATIONSHIP IS NOT A TABLE IN THE OWNER. It is a `resolve()` that reads EACH GATE'S OWN
`VERDICTS` -- the same `ast.literal_eval`-off-the-module-body read `gate-surface.declaration()`
performs, and the same marker -- and asks ONE question of the token:

    the token is the SAME VERDICT as the owner's token for that code  -> SYNONYM, resolve
    the token is a DIFFERENT VERDICT                              -> COLLISION, REFUSE (exit 3)

**WHICH QUESTION IS NOT DECIDED HERE, AND THAT IS THE POINT.** `resolve()` compares TOKEN against
the owner's token and refuses when they differ. It does not know that `NO-ROW` and `SKIP` mean
different things -- that is a question about MEANING, and the instrument that can answer it is
the GATE, because only the gate's author knows whether its own 4 is "could not run" or "ran and
found nothing to grade". So the shape shipped is the RELATIONSHIP plus a REFUSAL, and the
MEANING is left for the gate to settle by declaring its token as one the owner names.

THE DIRECTION, AND WHAT IT IMPLIES. `gatekit` is imported BY the gates (40 sites by walk), so
the vocabulary can only travel owner -> gate. A gate that renamed its token is therefore a gate
that has opted out of the owner's name and must say so itself. **A HAND LIST INSIDE `gatekit`
would invert the arrow**: it would make the owner the author of 8 gates' vocabulary, which is
`gendirs.py`'s "two instruments holding two lists have no authority over each other" with the
owner named as the second holder. So the table lives in the GATE, and `gatekit` keeps only the
five names it owns -- which is what it already has.
"""
import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"

# THE OWNER'S FIVE, BY IMPORT -- not re-spelled here. `gates/gatekit.py` is the owner; this
# module asks `gate-surface.vocabulary()` to READ it, exactly as `declareverdict/runner.py:57`
# does, for exactly the reason in `hooks/run.py:31`: two copies of a mapping are blind where
# they disagree.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def verdict_of(vocab):
    """`(rc, NAME)`, the owner's own reader, so this file cannot drift from `gatekit`."""
    return {v: k for k, v in vocab.items()}, vocab


def resolve(vocab, declared, owner_path="checks/wallcheck.py"):
    """`(code, name, kind)` for a declared table. REFUSED on a token the owner does not name.

    THE REFUSAL IS THE WHOLE POINT (item 6). `declareverdict`'s plant 5c: an AMBIGUOUS owner is
    REFUSED rather than guessed. The same rule here: a token that is not one of the owner's five
    is AMBIGUOUS -- it could be a synonym this tree has not agreed on, or a collision, and there
    is no way to tell from the SPELLING. Defaulting it to the nearest token (`NO-ROW` -> `SKIP`)
    would be a runner that GUESSES, and a guess that is wrong once is a wrong verdict forever.

    **THE `return`-INSIDE-THE-LOOP BUG IS MEASURED, NOT HYPOTHETICAL.** The first version of
    this function returned on the FIRST code, so `{0: PASS, 1: FAIL, 3: REFUSED, 4: NO-ROW,
    5: DEAD}` -- a table with FOUR agreeing rows and ONE collision -- came back `SAME`. Plants
    3 and 4 caught it on their first run and both read RED. That is `AGENTS.md`'s `DEAD` in its
    purest form: **"0 disagreements over 0 comparisons" is indistinguishable from agreement, and
    so is "1 disagreement" that was never looked at.** Every code is examined; only the FIRST
    refusal is reported, because a caller needs a verdict and not a list.
    """
    bad = None
    for code, token in sorted(declared.items(), key=lambda kv: int(kv[0])):
        code = int(code)
        owned = vocab.get(code)
        if owned is None:
            bad = bad or (REFUSED, token, f"exit {code} has no name in gates/gatekit.py")
        elif str(token).upper() != owned.upper():
            bad = bad or (REFUSED, token, (f"exit {code} is '{token}' where the owner names it "
                                           f"'{owned}'; a token the owner does not use cannot be "
                                           f"resolved from its spelling, because a SYNONYM and a "
                                           f"COLLISION are spelled alike"))
    if bad:
        return bad
    return PASS, "PASS", "SAME"


# ---- the two plants, on synthetic gates, on a table the OWNER does not own -----------
def planted(vocab, name, table):
    """`resolve()` over a SYNTHETIC table, so the negative is a measurement."""
    return resolve(vocab, table, owner_path=name)


def main():
    sf = loaded(SURFACE, "gate_surface_under_resolve")
    vocab = sf.vocabulary()
    byname, _ = verdict_of(vocab)
    entries, _libs = sf.population(ROOT)
    owner_reads = {}
    for p in sorted(entries):
        got = sf.declaration(p)
        if len(got) == 3:
            continue
        v, _pl, _r, _n = got
        if isinstance(v, dict):
            owner_reads[str(p.relative_to(ROOT))] = v

    print(f"OWNER gates/gatekit.py BY PATH: {', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}\n")

    rows = []
    for rel, v in sorted(owner_reads.items()):
        for code, token in sorted(v.items(), key=lambda kv: int(kv[0])):
            code = int(code)
            owned = vocab.get(code)
            kind = "SAME" if owned and str(token).upper() == owned.upper() else (
                "UNMAPPED" if owned is None else "COLLISION?")
            rows.append((rel, code, token, owned or "-", kind))

    same = [r for r in rows if r[4] == "SAME"]
    col = [r for r in rows if r[4] == "COLLISION?"]
    unm = [r for r in rows if r[4] == "UNMAPPED"]
    print(f"{len(rows)} declared codes over {len(owner_reads)} declaring gates: "
          f"{len(same)} SAME, {len(col)} RENAMED, {len(unm)} UNMAPPED\n")
    print(f"{'GATE':40} {'CODE':>4}  {'TOKEN':10} {'OWNER':9} KIND")
    for rel, code, tok, own, kind in rows:
        if kind == "SAME":
            continue
        print(f"{rel:40} {code:>4}  {tok:10} {own:9} {kind}")

    print("\nPLANTS -- THE NEGATIVE IS THE ONE THAT MATTERS\n")
    checks = []
    r = resolve(vocab, {0: "PASS", 1: "FAIL", 3: "REFUSED"}, "synonym: PASS/FAIL/REFUSED")
    checks.append(("1  a gate spelling the owner's tokens RESOLVES (same meaning, same word)",
                   r == (PASS, "PASS", "SAME"), f"{r}"))
    r = resolve(vocab, {0: "AGREE", 1: "FAIL", 3: "REFUSED"}, "synonym: AGREE for PASS")
    checks.append(("2  a SYNONYM in the SAME MEANING that is a DIFFERENT WORD (AGREE/PASS) still "
                   "REFUSES, because the spelling alone cannot say the meanings agree",
                   r[0] == REFUSED, f"{r}"))
    r = resolve(vocab, {0: "PASS", 1: "FAIL", 3: "REFUSED", 4: "NO-ROW", 5: "DEAD"},
                "collision: NO-ROW for SKIP")
    checks.append(("3  THE COLLISION REFUSES (exit 3) rather than defaulting NO-ROW to the "
                   "nearest token SKIP -- and it is found BEYOND four agreeing rows, which is "
                   "what the first version of resolve() got wrong",
                   r[0] == REFUSED and r[1] == "NO-ROW", f"{r}"))
    r = resolve(vocab, {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED"}, "unmapped: USAGE")
    checks.append(("4  an UNMAPPED code (2 USAGE, which the owner does not name) REFUSES",
                   r[0] == REFUSED and r[1] == "USAGE", f"{r}"))
    r = resolve(vocab, {0: "PASS", 1: "FAIL", 3: "REFUSED", 4: "SKIP", 5: "DEAD"},
                "negative: the collision is spelled the OWNER's word instead")
    checks.append(("5  the SAME table with the collision spelled the OWNER's word (SKIP) resolves "
                   "clean -- so the refusal reads the TOKEN, not the table's shape or its length",
                   r == (PASS, "PASS", "SAME"), f"{r}"))

    for name, ok, obs in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          {obs}")
    bad = sum(1 for c in checks if not c[1])
    print(f"\nPLANTS: {'GREEN' if not bad else 'RED'} ({len(checks) - bad}/{len(checks)})")
    return 1 if bad else 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())