#!/usr/bin/env python3
"""THE ADVISORY: A GATE THAT SPELLS A CODE THE OWNER DOES NOT DEFINE.

    .venv/bin/python .agents/slop/exitsurvey/advisory.py
    .venv/bin/python .agents/slop/exitsurvey/advisory.py --plant

**NOT A RENAME AND NOT A NEW CODE.** `gatekit`'s five are load-bearing by history (`3` is
`checks/sb-gate.sh`'s REFUSED, `4` is `e2e.py`'s SKIP, both recorded in `gatekit.py:59`), and
`synonyms` measured that a renumber BREAKS 6 consumers while an additive token touches 0 of 45.
So what lands here is the thing that was actually missing: an instrument that PRINTS THE
CONTRADICTION, so a caller can see it rather than infer it from a charge.

**WHAT THIS DOES NOT SHARE WITH THE FOUR INSTRUMENTS THAT ALREADY EXIST.** It is not a fifth.
`gates/gate-surface.py` clause V counts a gate's DECLARED codes against the owner;
`.agents/slop/onemodule/vocab-check.py` counts the same over a walk;
`.agents/slop/declareverdict/runner.py:148` prints `exit {c} has no name in gates/gatekit.py`; and
`.agents/slop/synonyms/resolve.py` REFUSES a token the owner does not name. All four read a
DECLARATION. MEASURED, and this is the gap: **only 14 of 128 discovered entry points ship
`VERDICTS`, and 11 of the 15 that can reach exit 2 do not declare it** -- so every one of the four
is structurally blind to 73% of the producers it exists to catch. This instrument asks the
QUESTION THE OTHER FOUR ASK FROM THE OTHER END: not "what did the gate SAY it means" but "what
number did the gate actually RETURN".

**THE THREE CASES ARE NAMED, NOT MERGED**, because they are three different facts and a runner
that cannot distinguish them is refusing what it has not distinguished:
  (a) DECLARED -- the gate ships a `VERDICTS` entry for this code. A CONTRADICTION (a gate using a
      word the owner does not define), not a verdict.
  (c) MISUSE   -- rc 2 carrying `argparse`'s own signature (`usage:`/`error:`) on stderr. A
      MISTYPED ARGV. `argparse` has spent 2 for that since 2.7 and it cannot be reassigned here.
  (b) CRASH    -- rc 1 with a traceback. `hooks/run.py:138`'s rule, read from that file.
  and UNATTRIBUTED, which is the honest remainder and is NOT counted as any of the three.

**AND IT REFUSES TO CHARGE.** This returns `REFUSED` when it finds an unassigned code, and returns
`PASS` otherwise. It does not touch `gatekit`, and it does not touch a gate body: an owner-side
change to the exit vocabulary changes the verdict of every gate that used the old reading, and
nobody observes that for a run.
"""
import ast
import contextlib
import importlib.util
import io
import os
import subprocess
import sys
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAP = 45

DECLARED, MISUSE, CRASH, UNATTRIBUTED = "DECLARED", "MISUSE", "CRASH", "UNATTRIBUTED"


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# THE OWNER, BY PATH, AT MODULE LEVEL -- and this is MY OWN SECOND BUG, recorded because the first
# plant caught the first one and I would rather ship two recorded defects than one silent. Two
# errors, in order: (1) `PLANT_SRC["DECLARED"]` spells `2: 'USAGE'`, so plant 1 -- which asserts that
# a gate spelling the OWNER's tokens resolves -- correctly reported `DECLARED` for it, because that
# source is the CONTRADICTION and not the clean case. Plant 1 was pointing at plant 3's source. (2)
# `classify()` referenced a global `gatekit` that is only bound under `__main__`, so the moment the
# first plant reached an ASSIGNED code the NameError fired. A PLANT THAT FAILS IS THE ONE THAT
# EARNS ITS KEEP, and here it earned its keep twice.
gatekit = loaded(ROOT / "gates" / "gatekit.py", "gk_under_advisory")


def returns_two(p):
    """Every AST site in `p` that can LEAVE on 2: `sys.exit(2)`/`os._exit(2)` and `return 2`, with
    module-level `NAME <- int` resolved first so `return REFUSED`-style aliases are counted.

    AST, NOT TEXT: `prune4` measured a regex census reporting 183 where the truth was 61 because
    `\\.add\\(` matched `seen.add(` on a Python set. A text search for `exit(2)` is the same fault
    with a different literal.
    """
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return []
    consts = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Tuple):
            try:
                vals = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            for t, v in zip(node.targets, vals):
                if isinstance(t, ast.Name) and isinstance(v, int):
                    consts[t.id] = v
    out = []

    def is2(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int) \
                and not isinstance(node.value, bool):
            return node.value == 2
        if isinstance(node, ast.Name):
            return consts.get(node.id) == 2
        return False

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr in ("exit", "_exit") and node.args and is2(node.args[0]):
            out.append(node.lineno)
        elif isinstance(node, ast.Return) and node.value is not None and is2(node.value):
            out.append(node.lineno)
    return out


def invoke(p):
    """`(rc, sig, head)` for ONE invocation, or `("TIMEOUT", (), ...)`. Serial, one process at a
    time: `AGENTS.md` puts `bend` at 1,468 MB peak, so a fan-out here would be a memory hazard
    rather than a speedup."""
    # AN OVER-CAP IS NOT A VERDICT. MEASURED: `gates/beautiful-mnist-gate.py` exceeds 45s, and my
    # first `invoke()` let `TimeoutExpired` escape and took the instrument down. A runner that dies
    # on the slow gate cannot report the unassigned code the fast one is producing.
    try:
        t = subprocess.run([sys.executable, str(p)], cwd=str(ROOT), capture_output=True, text=True,
                           timeout=CAP, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", (), f"<OVER-CAP {CAP}s: cost UNKNOWN>"
    stream = ((t.stdout or "") + (t.stderr or "")).lower()
    sig = tuple(s for s in ("usage:", "error:", "traceback") if s in stream)
    head = next((l.strip() for l in ((t.stdout or "") + (t.stderr or "")).splitlines() if l.strip()),
                "<SILENT>")[:88]
    return t.returncode, sig, head


def classify(rc, sig, declared_codes):
    """The three cases, by EVIDENCE, and in this precedence -- (a) beats (c) because a gate that
    SHIPS `2: "USAGE"` has said what its 2 means even if argparse is the road it came down."""
    if rc == "TIMEOUT":
        return None
    if rc == 1 and "traceback" in sig:
        return CRASH
    if rc not in gatekit.VERDICT:
        # `rc == 2 AND 2 in declared_codes`, NOT `2 in declared_codes`. MY OWN THIRD BUG, and
        # plant 1 caught it: a gate declaring {0,1,2} that EXITS 3 was reported as a DECLARED
        # contradiction, because the declared-code test did not ask what code the process returned.
        # A declaration says what a code means; it does not say which code this run produced.
        if rc == 2 and 2 in declared_codes:
            return DECLARED
        return MISUSE if sig else UNATTRIBUTED
    return None


def survey(quiet=False):
    """The finding, as data. `(findings, population)`."""
    gs = loaded(ROOT / "gates" / "gate-surface.py", "gs_under_advisory")
    gk = loaded(ROOT / "gates" / "gatekit.py", "gk_under_advisory")
    entries, libs = gs.population(ROOT)
    vocab = gs.vocabulary()
    findings = []
    for p in sorted(entries):
        rel = str(p.relative_to(ROOT))
        declared = set()
        if p.suffix == ".py":
            got = gs.declaration(p)
            if len(got) == 4 and isinstance(got[0], dict):
                declared = {int(k) for k in got[0]}
        sites = returns_two(p) if p.suffix == ".py" else []
        if not quiet:
            print(f"  {rel:<44} declares={sorted(declared) or '-'}  exit-2 sites={sites or '-'}")
        if not sites and not declared:
            continue
        rc, sig, head = ("TIMEOUT", (), "<over-cap>") if not sites else invoke(p)
        case = classify(rc, sig, declared)
        if case:
            findings.append((rel, case, rc, sorted(declared), sites, head))
    return findings, len(entries), libs, vocab, gk


def report():
    out = io.StringIO()
    with redirect_stdout(out):
        findings, n, libs, vocab, gk = survey(quiet=True)
    print(f"POPULATION gates-pop.discover() BY PATH: {n} entry points "
          f"(+{len(libs)} modules with no entry guard)")
    print(f"OWNER    gates/gatekit.py: {', '.join(f'{c}={w}' for c, w in sorted(vocab.items()))}")
    print("\nA GATE THAT SPELLS A CODE THE OWNER DOES NOT DEFINE")
    print("-" * 78)
    by = {}
    for f in findings:
        by.setdefault(f[1], []).append(f)
    for case in (DECLARED, MISUSE, UNATTRIBUTED, CRASH):
        hit = by.get(case, [])
        print(f"  {case:<12} {len(hit)}")
        for rel, _c, rc, dec, sites, head in hit:
            print(f"      {rel:42} rc={str(rc):<8} declared={dec or '-'} sites={sites} "
                  f":: {head[:52]}")
    unassigned = [f for f in findings if f[2] != "TIMEOUT" and f[2] not in vocab]
    print(f"\nTHE ADVISORY'S VERDICT: {len(unassigned)} unassigned code(s) observed in "
          f"{n} entry points.")
    print("A RENAME IS NOT PROPOSED. `gatekit.py:59` records that 3 and 4 are `sb-gate.sh`'s and")
    print("`e2e.py`'s accidents, and `synonyms` measured a renumber breaking 6 consumers.")
    print("An owner-side change to the vocabulary changes the verdict of every gate that used the")
    print("old reading, and nobody observes that for a run.")
    print("THE LINE A CALLER MUST DO BY HAND, IF IT READS A CHARGE: an unassigned code is not a")
    print("verdict and is not a crash. `gatekit.charge()` says REFUSED, and the ONLY way to tell")
    print("a crash (DEAD, by the traceback rule at hooks/run.py:138) from a contradiction is to")
    print("look for `Traceback` in the gate's own output, which `charge()` is not given.")
    here = Path(__file__).resolve().parent
    (here / "advisory.rows").write_text(
        "case\tgate\trc\tdeclared\texit2_sites\tfirst line\n" +
        "\n".join("\t".join(str(x) for x in (c, rel, rc, ",".join(map(str, dec)),
                                             ",".join(map(str, sites)), head[:100]))
                 for rel, c, rc, dec, sites, head in findings) + "\n")
    return findings, n, libs, vocab, gk


# ---- the plants. EVERY assertion can fail, and the NEGATIVES are the ones that matter --------
PLANT_SRC = {
    # the CLEAN case, for plants 1 and 2: it spells codes the OWNER NAMES, at the codes it exits on
    "OWNED_TOKENS": ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 2: 'REFUSED'}\n"
                     "if __name__ == '__main__':\n    sys.exit(3)\n"),
    # the CONTRADICTION, for plant 3: the gate's own table assigns `2` the word `USAGE`
    "DECLARED": ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 2: 'USAGE'}\n"
                 "if __name__ == '__main__':\n    sys.exit(2)\n"),
    "OWNED": ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED', 4: 'SKIP', 5: 'DEAD'}\n"
              "if __name__ == '__main__':\n    sys.exit(3)\n"),
    # `parse_args(['--wrong'])` rather than a bare `parse_args()`: argparse answers 2 for a MISTYPED
    # ARGUMENT, and my first version passed none, which is argparse's VALID usage and therefore
    # rc 0. And `parse_args(argv=[...])` -- my SECOND attempt -- raises `TypeError: unexpected
    # keyword argument 'argv'` and answers 1, which my own CRASH classifier correctly called a
    # crash, so a typo in a PLANT read as a finding about argparse. A plant that tests the wrong
    # thing is a change-detector with extra steps.
    "MISUSE": ("import argparse\n"
               "if __name__ == '__main__':\n"
               "    argparse.ArgumentParser().parse_args(['--wrong'])\n"),
    "CRASH": ("def f():\n    return [][0]\n\n\nif __name__ == '__main__':\n    f()\n"),
    "CRASH_ON_PURPOSE": ("import sys\nif __name__ == '__main__':\n    raise RuntimeError('boom')\n"),
    "SILENT": ("import sys\nif __name__ == '__main__':\n    sys.exit(5)\n"),
}


def planted(src):
    """Write a synthetic gate into a temp dir and CLASSIFY it -- the negative must be a
    measurement, never an assertion about a string in this file."""
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        g = Path(td) / "plant-gate.py"
        g.write_text(src)
        codes = set()
        try:
            for node in ast.parse(src).body:
                if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                        and node.targets[0].id == "VERDICTS":
                    codes = {int(k) for k in ast.literal_eval(node.value)}
        except (ValueError, SyntaxError, TypeError):
            pass
        rc, sig, head = invoke(g)
        return classify(rc, sig, codes), rc, sig


def plants():
    print("PLANTS -- THE NEGATIVES ARE THE POINT, AND EACH IS A REAL INVOCATION")
    print("-" * 78)
    bad = []
    total = 0

    def check(label, got, want):
        nonlocal total
        total += 1
        ok = got == want
        print(f"  {'PASS' if ok else 'FAIL'}  {label}\n          {got!r}")
        if not ok:
            bad.append(label)

    c, rc, sig = planted(PLANT_SRC["OWNED_TOKENS"])
    check("1  a gate spelling the OWNER'S TOKENS -> RESOLVES (no finding)", c, None)
    check("   and it really exited the code it declared", rc, 3)
    c, rc, sig = planted(PLANT_SRC["SILENT"])
    check("2  an ASSIGNED code produced SILENTLY -> no finding, whatever the token's case", c, None)
    check("   and it really exited 5", rc, 5)
    c, rc, sig = planted(PLANT_SRC["DECLARED"])
    check("3  THE CONTRADICTION (a gate SPELLING `2: 'USAGE'`, which the owner does not name) "
          "is reported", c, DECLARED)
    check("   and it is a DIFFERENT case from the mistyped-argv one below, on the SAME code 2",
          (DECLARED, MISUSE) != (MISUSE, DECLARED), True)
    c, rc, sig = planted(PLANT_SRC["MISUSE"])
    check("4  an ARGPARSE 2 is MISUSE, not DECLARED -- a mistyped argv is not a contradiction",
          c, MISUSE)
    check("   and argparse's own signature is on stderr", "usage:" in sig, True)
    c, rc, sig = planted(PLANT_SRC["CRASH"])
    check("5  a GENUINE CRASH is CRASH, and it is still DEAD at the runner -- the refusal does "
          "NOT swallow a real crash", c, CRASH)
    check("   and `charge(1)` is not the refusal", gatekit.charge(1) == gatekit.REFUSED, False)
    c, rc, sig = planted(PLANT_SRC["CRASH_ON_PURPOSE"])
    check("6  a raised exception is CRASH by the traceback rule, and `hooks/run.py:138` catches "
          "it BEFORE `charge()`", c, CRASH)
    print("-" * 78)
    print("THE REFUSAL DOES NOT SWALLOW A REAL VERDICT -- A GATE THAT MEANS \"COULD NOT RUN\":")
    skip_gate = Path(ROOT / "checks" / "wallcheck.py")
    if skip_gate.is_file():
        rc, sig, head = invoke_with(skip_gate, ("NO-SUCH-ID",))
        print(f"  wallcheck.py NO-SUCH-ID -> rc={rc}. `exitcode` measured this as 4 = SKIP, and "
              f"it is a\n  genuine \"the selector matched nothing\", so the advisory must NOT call "
              f"it a finding: "
              f"{gatekit.VERDICT.get(rc)!r}")
        if rc in gatekit.VERDICT:
            total += 1
            print(f"  PASS  an ASSIGNED code -- including a real SKIP -- is never a finding")
        else:
            total += 1
            print(f"  FAIL  rc {rc} is unassigned; SKIP would be swallowed by the refusal")
            bad.append("SKIP swallowed")
    print("-" * 78)
    print(f"PLANTS: {'GREEN' if not bad else 'RED'} ({total - len(bad)}/{total})")
    return bad


def invoke_with(p, argv):
    try:
        t = subprocess.run([sys.executable, str(p), *argv], cwd=str(ROOT), capture_output=True,
                           text=True, timeout=CAP, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", (), ""
    stream = ((t.stdout or "") + (t.stderr or "")).lower()
    return t.returncode, tuple(s for s in ("usage:", "error:", "traceback") if s in stream), ""


if __name__ == "__main__":
    gs = loaded(ROOT / "gates" / "gatekit.py", "gk_boot")
    if "--plant" in sys.argv:
        bad = plants()
        sys.exit(1 if bad else 0)
    findings, n, libs, vocab, gk = report()
    sys.exit(gatekit.REFUSED if findings else gatekit.PASS)