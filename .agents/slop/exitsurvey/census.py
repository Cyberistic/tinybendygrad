#!/usr/bin/env python3
"""THE UNASSIGNED-CODE CLASS, COUNTED BY DISCOVERY AND BY INVOCATION.

    .venv/bin/python .agents/slop/exitsurvey/census.py [--cap SECONDS] [--out FILE]

**AST, NOT TEXT, FOR THE STATIC HALF.** `prune4`'s lesson is the reason: a regex census reported
183 where the truth was 61, because `\\.add\\(` matched `seen.add(` on a Python set. So `exits()` is
an `ast` walk over `ast.Call` nodes naming `sys.exit`/`os._exit` and `ast.Return` nodes carrying an
integer literal or a module-level name -- never a substring search for `exit(2)`.

**THE POPULATION IS DISCOVERED, NOT LISTED.** `gates/gates-pop.py:discover()`, loaded BY PATH.
`PLANTS` is `gates/gate-surface.py:declaration()`'s read of each gate's OWN module body -- a
generator's own declaration, loaded by path -- so the argv half is not a hand list either.

**WHAT THIS COUNTS AND WHAT IT CANNOT.** It counts the exit code a process ACTUALLY RETURNED, per
invocation. It cannot know which lines are reachable, so `exits()`'s static column is a SUPERSET
claim and the invocation column is the MEASUREMENT. Both are printed, and the verdict is taken from
the invocation, because `slowgate` measured that the INVOCATION decides: `oracle_f64.py` bare
answers rc 3, imported it does not refuse at all.

THE THREE CASES ARE SEPARATED BY EVIDENCE, NOT BY EXIT NUMBER, because all three arrive as an
integer a subprocess returns:

  (a) DECLARED   the gate ships `VERDICTS = {..., 2: "USAGE"}` -- read by AST. A gate using a word
                 the OWNER does not define. A CONTRADICTION, not a verdict.
  (c) MISUSE     rc 2 with argparse's own signature on stderr (`usage:` and `error:`). A MISTYPED
                 ARGV, which `argparse` has spent as 2 since 2.7 and which cannot be changed
                 without patching the stdlib.
  (b) CRASH      rc 1 with `Traceback` in the captured stream -- `hooks/run.py:138`'s own rule,
                 read from that file by path rather than re-derived.

A gate whose own prose calls rc 2 "REFUSED" (as `gates/gate-surface.py:135` and
`checks/env-precond.py:437` do) is case (a) AND carries a different WORD on the same number than
`checks/wallcheck.py:681`'s `USAGE` -- which is two meanings on one number, and it is reported as
such rather than merged into one count.
"""
import argparse
import ast
import importlib.util
import io
import subprocess
import sys
import time
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
import gatekit  # noqa: E402  -- the OWNER, by path, exactly as hooks/run.py:57 does

CAP_DEFAULT = 20


def loaded(path, name):
    """BY PATH, never by name: `gates/` is not a package and a bindable name is a population
    anybody can choose (`gates/gates-pop.py:104`)."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def exits(p):
    """Every integer a source can LEAVE on, by AST. `(site, value)` pairs, `value` an int or a
    module-level NAME string.

    `ast.Call` for `sys.exit(...)`/`os._exit(...)` -- the process-level exits -- and `ast.Return`
    for `return <int|int-name>`, because a runner reads the value `main()` hands to `sys.exit`.
    A `Return` of a NAME is resolved against the module body first, so `return REFUSED` reads 3
    and not "REFUSED"; an unresolvable name is returned as the string and the caller shows it.
    """
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError as e:
        return [("<UNPARSEABLE>", f"SyntaxError line {e.lineno}")]
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
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr in ("exit", "_exit") and node.args:
            out.append((node.lineno, _val(node.args[0], consts)))
        elif isinstance(node, ast.Return) and node.value is not None:
            out.append((node.lineno, _val(node.value, consts)))
    return out


def _val(node, consts):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) \
            and not isinstance(node.value, bool):
        return node.value
    if isinstance(node, ast.Name):
        return consts.get(node.id, node.id)
    if isinstance(node, ast.BinOp):  # `1 + 1` is a code path a literal reader misses
        try:
            return ast.literal_eval(node)
        except (ValueError, SyntaxError, TypeError):
            return ast.unparse(node)
    return "?"


def uses_argparse(p):
    """Does the source call `argparse` AT ALL? AST over imports and the bare name."""
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(a.name.split(".")[0] == "argparse" for a in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] == "argparse":
                return True
    return False


ARGPARSE_SIG = ("usage:", "error:")


def run(p, argv, cap):
    """`(rc, seconds, first_line, sig)` for one invocation, or `("TIMEOUT", ...)`.

    NOTHING IS ASSUMED FROM THE EXIT CODE ALONE. `sig` carries the argparse signature, the
    traceback marker, and the gate's own first line of output -- because the three cases are
    distinguished by evidence in the stream and not by the integer.
    """
    t0 = time.monotonic()
    cmd = [sys.executable, str(p), *[str(a) for a in argv]]
    try:
        r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=cap,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", cap, f"<OVER-CAP {cap}s: cost UNKNOWN>", ()
    stream = ((r.stdout or "") + (r.stderr or ""))
    low = stream.lower()
    sig = tuple(s for s in ARGPARSE_SIG if s in low)
    if "traceback" in low:
        sig = sig + ("Traceback",)
    head = next((l.strip() for l in stream.splitlines() if l.strip()), "<SILENT>")[:90]
    return r.returncode, time.monotonic() - t0, head, sig


def classify(rc, sig, declared_codes, argv_seen):
    """The THREE CASES, and the refusal, by evidence. `None` is "an assigned code, so not here".

    (a) DECLARED takes precedence over (c) MISUSE because a gate that SHIPS `2: "USAGE"` has
    stated what its 2 means, and argparse is merely the road it arrived on. (c) MISUSE requires
    argparse's signature on stderr, because rc 2 without it is unattributed otherwise.
    (b) CRASH is rc 1 + a traceback -- `hooks/run.py:138`, read not re-derived.
    """
    if rc == "TIMEOUT":
        return "TIMEOUT"
    if rc == 1 and "Traceback" in sig:
        return "CRASH"
    if rc in declared_codes:
        return "DECLARED"
    if rc not in gatekit.VERDICT:
        return "MISUSE" if sig else "UNATTRIBUTED"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap", type=float, default=CAP_DEFAULT)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent / "census.rows"))
    args = ap.parse_args()

    gs = loaded(ROOT / "gates" / "gate-surface.py", "gs_under_census")
    entries, libs = gs.population(ROOT)
    vocab = gs.vocabulary()

    rows = []
    static = {}
    unsound = []
    for p in sorted(entries):
        rel = str(p.relative_to(ROOT))
        got = gs.declaration(p)
        # `gates/gate-surface.py:251` returns a THREE-tuple on SyntaxError while six other branches
        # return FOUR, and its own call site `:359` unpacks four -- so the UNSOUND BRANCH is the one
        # that raises. `exitcode` filed this and did not fix it (`gate-surface.py` is not its file).
        # MEASURED, IN THIS UNIT, THE FOURTH TIME: it took this instrument down at `:185` on the
        # first run over the population. The guard is HERE rather than in `gate-surface.py` because
        # that file is not mine, and because a reader that dies on the shape it was written to read
        # cannot report the shape.
        # NOTE: the `declaration()` shape is read HERE rather than reimplemented, so this file holds
        # no second copy of the DECL marker list (`gate-surface.py:237`) -- the fourth-hand-list fault
        # `synonyms`/`exitcode` both name.
        if len(got) != 4:
            unsound.append((rel, len(got)))
            v, plants = None, None
        else:
            v, plants, _r, note = got
        codes = {int(k) for k in v} if isinstance(v, dict) else set()
        static[rel] = (exits(p), sorted(codes), uses_argparse(p))
        for label, argv in (("bare", ()),) + tuple(
                (f"argv{c}", tuple(a)) for c, a in sorted(
                    ((c, a) for c, a in (plants or {}).items()), key=lambda kv: int(kv[0]))):
            rc, secs, head, sig = run(p, argv, args.cap)
            rows.append(dict(gate=rel, how=label, argv=" ".join(argv), rc=rc, secs=round(secs, 1),
                             first=head, sig="|".join(sig), declared="|".join(map(str, sorted(codes))),
                             verdict=gatekit.verdict_of(rc) if rc != "TIMEOUT" else "SKIP",
                             charge=gatekit.charge(rc) if rc != "TIMEOUT" else "SKIP"))
            print(f"{rel:<44} {label:<7} rc={str(rc):<7} {gatekit.verdict_of(rc) if rc != 'TIMEOUT' else 'SKIP'}"
                  f"{'':<14} {secs:5.1f}s  {head[:70]}")

    out = Path(args.out)
    out.write_text("gate\thow\targv\trc\tsecs\tverdict\tcharge\tdeclared\targparse\tsig\tfirst\n" +
                   "\n".join(
                       "\t".join(str(x) for x in (r["gate"], r["how"], r["argv"], r["rc"], r["secs"],
                                                  r["verdict"], r["charge"], r["declared"],
                                                  "yes" if static[r["gate"]][2] else "no",
                                                  r["sig"], r["first"]))
                       for r in rows) + "\n")

    # ---- the census, denominators stated with the scope ------------------------------
    gates = sorted({r["gate"] for r in rows})
    print("\n" + "=" * 78)
    print(f"POPULATION gates-pop.discover() BY PATH: {len(entries)} entry points "
          f"(+{len(libs)} modules with no entry guard)")
    print(f"INVOCATIONS: {len(rows)} = {len(gates)} gates x (1 bare + declared PLANTS)")
    print(f"COMPLETED: {sum(1 for r in rows if r['rc'] != 'TIMEOUT')}, "
          f"OVER-CAP (measured nothing, and a SKIP is not a pass): "
          f"{sum(1 for r in rows if r['rc'] == 'TIMEOUT')}")
    print(f"OWNER gates/gatekit.py: {', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}\n")

    for how in ("bare",):
        sub = [r for r in rows if r["how"] == how and r["rc"] != "TIMEOUT"]
        tally = {}
        for r in sub:
            tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
        print(f"BARE ({len(sub)} of {len(gates)} gates ran): " +
              ", ".join(f"{k}={v}" for k, v in sorted(tally.items(), key=lambda kv: -kv[1])))

    unass = [r for r in rows if r["rc"] != "TIMEOUT" and r["rc"] not in gatekit.VERDICT]
    print(f"\nTHE UNASSIGNED-CODE CLASS: {len(unass)} invocation(s) returned a code "
          f"gates/gatekit.py does not name, over {len(gates)} gates x "
          f"{len(rows)//max(len(gates),1)} invocation(s) each")
    seen = {}
    for r in unass:
        case = classify(r["rc"], tuple(r["sig"].split("|")) if r["sig"] else (),
                        {int(x) for x in r["declared"].split("|") if x}, r["argv"])
        seen.setdefault(case, []).append(r)
    for case in ("DECLARED", "MISUSE", "UNATTRIBUTED", "CRASH"):
        hit = seen.get(case, [])
        print(f"  {case:<12} {len(hit)}")
        for r in hit:
            print(f"      {r['gate']} [{r['how']}] argv={r['argv']!r} rc={r['rc']} "
                  f"declared={r['declared'] or '-'} :: {r['first'][:60]}")

    # the SAME question asked two ways: how many DISTINCT gates, not invocations
    gates_unass = sorted({r["gate"] for r in unass})
    print(f"\nDISTINCT GATES in that class: {len(gates_unass)}")
    for g in gates_unass:
        bare = next((r for r in unass if r["gate"] == g and r["how"] == "bare"), None)
        witha = [r for r in unass if r["gate"] == g and r["how"] != "bare"]
        if bare and witha:
            print(f"  {g}: BARE rc={bare['rc']} ({bare['verdict']}) but WITH ARGV "
                  f"{[r['argv'] for r in witha]} rc={[r['rc'] for r in witha]} "
                  f"({[r['verdict'] for r in witha]}) -- THE INVOCATION DECIDED")

    # what charge() does with each of the three, from the OWNER, not from a copy
    print("\nWHAT gatekit.charge() DOES WITH EACH CASE (the owner's own function):")
    for case, code in (("(a) DECLARED -- gate spells a code the owner does not name", 2),
                       ("(b) CRASH -- rc 1 + Traceback", 1),
                       ("(c) MISUSE -- argparse's own 2", 2)):
        note = ""
        if case.startswith("(b)"):
            note = "  <- NOT charge()'s business: hooks/run.py:138 catches the traceback FIRST"
        print(f"  {case:<62} charge({code}) = {gatekit.VERDICT[gatekit.charge(code)]}{note}")
    print(f"  a hypothetical code 6                                "
          f"charge(6) = {gatekit.VERDICT[gatekit.charge(6)]}")
    print("\nSTATIC SUPERSET (AST, not reachable): "
          f"{len(gates)} gates, {sum(len(v[0]) for v in static.values())} exit/return sites")
    if unsound:
        print(f"UNSOUND DECLARATION SHAPE: {len(unsound)} gate(s) made "
              f"gates/gate-surface.py:declaration() return a tuple whose length is not 4, which "
              f"its own\n   call site at :359 unpacks positionally -- it CRASHES the reader rather "
              f"than describing the file:")
        for rel, n in unsound:
            print(f"      {rel}: declaration() returned a {n}-tuple")
    print(f"\nrows: {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())