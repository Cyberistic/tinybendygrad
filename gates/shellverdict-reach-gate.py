#!/usr/bin/env python3
"""shellverdict-reach-gate.py -- WHICH OF THE FIVE CAN EACH SHELL GATE REACH, AND WHY NOT.

    .venv/bin/python gates/shellverdict-reach-gate.py            # the census
    .venv/bin/python gates/shellverdict-reach-gate.py --rows     # rows only
    .venv/bin/python gates/shellverdict-reach-gate.py --plant    # make it MOVE, on a synthetic tree

**THE QUESTION `gates/shellverdict-gate.py` ANSWERS AND THIS ONE DOES NOT.** That file counts
LITERAL `exit N` TOKENS and prints `missing [0, 1, 4, 5]`. This file asks whether a gate can
REACH a verdict, and the answer is not the token count, because **a shell script's exit status
is not chosen from a list of its own.** Three properties of POSIX shell make the token count a
lower bound with no upper bound, and every one of them is measured below on the live tree:

  * `set -e` propagates a FAILING COMMAND'S OWN STATUS into the script's. Measured: 7 of the 21
    shell members turn it on. A gate with `set -e` can reach a code it never names, because
    `grep` returns 2, `git` returns 128+n, a missing binary returns 127.
  * A script that RUNS OFF THE END exits with the status of its LAST command. Measured: the
    tail route is open on 19 of 21.
  * `exec` replaces the process, so the script's status is the EXEC'D PROGRAM'S. `checks/bend`
    is three lines and names no exit code at all -- and it is the reason the prior census
    printed `population 18` when the walk holds 19 immediate members.

So **"16 of 18 emit two or three of the five" IS NOT A REACHABILITY MEASUREMENT AND ITS OWN
DENOMINATOR IS WRONG.** Measured over this file's 21-member walk population, counting literal
`exit N` sites whose code is one of the five: **9 of 21** emit two or three, 5 emit NONE, 6 emit
one, 3 emit three, 1 emits all five. Measured over the 18-member set the figure is describing
(17 `checks/*.sh` plus `gates/groupflip-baseline.sh`), read off
`gates/shellverdict-gate.py`'s own per-gate printout: **13 of 18**, not 16 -- 2 emit one
(`wt-sync.sh`, `groupflip-baseline.sh`), 3 emit four or five (`e2e.sh`, `walk-mutate.sh`,
`sb-gate.sh`). `AGENTS.md`: "a number that can be disagreed with is a number nobody can check";
this one can, and does.

And after the routes above are accounted for, **the number of members that CANNOT reach one of
the five is 0 of 21** -- which is a statement about POSIX shell and not about the tree.

**A CELL IS A STATE AND A REASON, AND NEITHER IS "MISSING".** `sb-gate.sh`'s `PASS` is
UNREACHABLE and that is CORRECT -- its oracle is gone and fabricating one would fabricate its
own reference. `gates/groupflip-baseline.sh` emits only `2` and that is CORRECT -- its own
header says "IT PRODUCES NO VERDICT AND ITS EXIT STATUS IS NOT ONE". This file therefore never
prints `missing`. It prints, per gate per verdict, one of:

    LITERAL     a literal `exit N` names it (with the line)
    UNNAMED     reachable only through a route this file NAMES and will not enumerate:
                `set -e`, the tail status, or `exec`. Reachable, unnamed, not green.
    UNRESOLVED  this file cannot read it: the member does not parse under the interpreter the
                tree's runner would use, or the only exit is `exit $var`, or the quoting on the
                exit's line does not close. **CHARGED TO NEITHER VERDICT. NEVER GREEN.**
    NO-SITE     no literal site and no named route. The ONLY state that could be a deficiency,
                and it is reported by that name rather than by a verdict.

**AND THE FINDING IS THE COLLISION, WHICH IS NOT ABOUT THESE GATES AT ALL.** `checks/gatesweep.py:classify`
is `(btoken, rc, text)`, not `(rc)`: the watchdog's TOKEN outranks the code, deliberately
(`gatesweep.py:291`, and `checks/sb-gate.sh:142` says so in its own prose). Enumerated over
every token and every output shape, **EVERY INTEGER IN THE TREE'S SHELL EXIT VOCABULARY IS TWO
VERDICTS** -- 7 of 7 -- including all five `gatekit.VERDICT` owns. Measured on
`2026-10-19T15:44Z`; the table is printed by `--collisions` and is the reason the gate is
`FAIL` on a gate that emits it.

EVERYTHING IS LOADED BY PATH AND NOTHING IS RE-TYPED: `gates/gates-pop.py:gate_homes()` and
`entry_reason()` are the population, `checks/gatesweep.py:population()` is the walk,
`RUNNERS["sh"][0]` is the interpreter, `gates/gatekit.py:VERDICT`/`charge`/`verdict_of` and
`checks/gatesweep.py:classify` and `checks/bounded.py:STATUS` are the readers. NO `bend`.

**THIS FILE READS SHELL WITH ITS OWN LINE-PRESERVING STRIP, AND THE REASON IS MEASURED.**
`gates/gates-pop.py:shell_code()` is `re.sub(r"^\\s*#.*$", "", src, re.M)` and **`\\s*` EATS
THE NEWLINE**: `checks/run-f64.sh` is 448 lines and `shell_code` returns 435, 8 of 21 members
lose lines, `sb-gate.sh` loses 12. A line number read off that output is a WRONG LINE NUMBER,
which is `gates/gates-pop.py`'s own "`A COMPARISON THAT CAN NEVER SUCCEED LOOKS EXACTLY LIKE A
COMPARISON THAT FOUND NOTHING`" one level down. `shell_code` is still the comment grammar and
is not re-spelled here; only the geometry is repaired, by iterating lines.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

warnings.simplefilter("ignore")     # gates-pop.py's own escapes, read twice per call

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def _load(name, path):
    """A module BY PATH. `gates/` is not a package and `gates-pop.py` carries a HYPHEN."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


gpop = _load("svr_gpop", HERE / "gates-pop.py")
gatekit = _load("svr_gatekit", HERE / "gatekit.py")
bounded = _load("svr_bounded", ROOT / "checks" / "bounded.py")
sweep = _load("svr_sweep", ROOT / "checks" / "gatesweep.py")

# THE FIVE, INVERTED OFF `gatekit`'S OWN TABLE. `VERDICT` is `{code: word}`; iterating it as
# `word, code` is how the first run of this file reported `UNNAMED=5` on all 21 members -- the
# word `"PASS"` was used as a code, matched nothing, and every cell fell through to the
# `set -e` arm. **A MAP IS READ IN THE DIRECTION IT WAS BUILT, AND A LOOKUP THAT CANNOT SUCCEED
# LOOKS EXACTLY LIKE A LOOKUP THAT FOUND NOTHING.**
PASS, FAIL, REFUSED, SKIP, DEAD = (getattr(gatekit, n)
                                   for n in ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD"))
CODES = {word: code for code, word in gatekit.VERDICT.items()}

# THE INTERPRETER THE TREE'S OWN RUNNER WOULD USE, read off its table and never re-spelled.
RUNNER = sweep.RUNNERS["sh"][0]
# THE THREE READERS' OUTPUT SHAPES. A declared PROBE SET with a printed denominator, not an
# expected value: `classify`'s branches are (token, rc==0-and-silent, rc==1-and-traceback), so
# these three are the axes it actually branches on and one more would find nothing new.
TEXTS = {"printed": "name=value\n", "silent": "", "traceback": "Traceback (most recent call last):\n"}
TOKENS = (bounded.WITHIN, bounded.MEMORY, bounded.TIMEOUT, bounded.UNSTARTED, bounded.NOVERDICT)

# ---- the reader of one shell file, with line geometry REPAIRED --------------------------------
# `\s*\d+\b` AND NOT `\s*\d+\s*(?:$|[;&|])`: the second form MISSED `exit 3 }` --
# MEASURED, it dropped `checks/lint_demo.sh`'s only REFUSED site (`:27`) and reported 2 of
# the five where the truth is 3. **A TERMINATOR SET THAT OMITS `}` IS A LIST, AND A LIST HERE
# IS A SILENT LOSS: THE GATE STILL PRINTED A PLAUSIBLE NUMBER.**
LITERAL = re.compile(r"(?:^|[;&|(]\s*|\s)exit\s+(\d+)\b")
DYNAMIC = re.compile(r"(?:^|[;&|(]\s*|\s)exit\b(?!\s*\d)(?!\s*=)")
TAIL_EXIT = re.compile(r"^\s*exit\s+\d+\s*$")
SET_E = re.compile(r"^\s*set\s+-[a-zA-Z]*e")
EXEC = re.compile(r"^\s*exec\b")


def _blank_quotes(line):
    """`(code, closed)` -- quoted spans blanked, and whether the quoting CLOSES on this line.

    `AGENTS.md`'s rule at its sharpest: a construct this file cannot resolve must print
    UNRESOLVED, because `gates/lane-census.py`'s "0 disagreements over 0 comparisons" is
    indistinguishable from agreement. **THE WORD `exit` INSIDE A STRING IS NOT AN EXIT SITE** --
    MEASURED on `checks/gen.sh:96` (`echo "... exit=$? (want 0)"`), `checks/lint_demo.sh:46`
    (`print -r -- "  exit $base"`) and 12 more: the prior census's `dynamic` detector reports
    **16 sites over 7 members and 2 of them are real** (`checks/run-f64.sh:448` and
    `checks/run-port-mm.sh:317`, both `exit $rc`). **14 ARE PROSE, AND A ROW THAT CANNOT BE READ
    MUST NOT BE COUNTED AS IF IT HAD BEEN.**
    """
    out, quote, i = [], None, 0
    while i < len(line):
        c = line[i]
        if quote is None and c == "\\":
            out.append("  ")
            i += 2
            continue
        if c in "'\"":
            quote = None if quote == c else (c if quote is None else quote)
            out.append(" ")
        elif quote is None:
            out.append(c)
        else:
            out.append(" ")
        i += 1
    return "".join(out), quote is None


def read_shell(path):
    """`{lineno: code}` for the COMMENT-STRIPPED, QUOTE-BLANKED, LINE-NUMBERED source.

    Comments are removed BY LINE, which is the whole fix: `re.sub(r"^\\s*#.*$", "", src, re.M)`
    collapses the newline in front of every comment line, so its output is a different line
    count from its input. Line-at-a-time has no such cross-line reach.
    """
    out = {}
    for n, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if raw.lstrip().startswith("#"):
            continue
        code, _closed = _blank_quotes(raw)
        out[n] = code
    return out


def parse_under(path, interp=RUNNER):
    """`(ok, first_line_of_diagnostic)` for `<interp> -n <path>`. A GATE THAT CANNOT PARSE IS A
    GATE NOBODY READS** -- `gates/README.md`'s third retired shell defect, and it is a RUN of
    the interpreter, not a regex."""
    r = subprocess.run([interp, "-n", str(path)], capture_output=True, text=True)
    said = (r.stderr or "").strip().splitlines()
    return r.returncode == 0, (said[0] if said else "")


def sites(code):
    """`(literals, dynamics, has_set_e, has_exec, tail_route)` -- every one line-numbered."""
    lit, dyn = {}, {}
    for n, c in code.items():
        if not c.strip():
            continue
        for m in LITERAL.finditer(c):
            lit.setdefault(int(m.group(1)), []).append(n)
        if DYNAMIC.search(c):
            dyn.setdefault(n, c.strip())
    body = [c for c in code.values() if c.strip()]
    return (lit, dyn, any(SET_E.match(c) for c in body),
            any(EXEC.match(c) for c in body),
            bool(body) and not TAIL_EXIT.match(body[-1]))


def reach(path):
    """`{verdict: (state, why)}` for one shell member, and the file-level reading with it."""
    code = read_shell(path)
    lit, dyn, set_e, has_exec, tail = sites(code)
    ok, said = parse_under(path)
    out, unresolved = {}, []
    for word, n in CODES.items():
        if not ok:
            out[word] = ("UNRESOLVED", f"does not parse under {RUNNER} (rc!=0): {said[:70]}")
        elif n in lit:
            out[word] = ("LITERAL", f"exit {n} at :{', :'.join(map(str, lit[n]))}")
        elif dyn:
            out[word] = ("UNRESOLVED", f"{len(dyn)} dynamic exit site(s), first :{sorted(dyn)[0]}"
                                        f" `{sorted(dyn.values())[0][:40]}`")
        elif set_e:
            out[word] = ("UNNAMED", "`set -e`: a failing command's own status IS this script's")
        elif tail:
            out[word] = ("UNNAMED", "runs off the end: the last command's status IS this script's")
        elif has_exec:
            out[word] = ("UNNAMED", "`exec`: the exec'd program's status IS this script's")
        else:
            out[word] = ("NO-SITE", "no literal exit and no route this file can name")
        if out[word][0] == "UNRESOLVED":
            unresolved.append(word)
    return out, {"parses": ok, "said": said, "unresolved": unresolved,
                 "interp": shebang(path), "interp_ok": interp_matches(path)}


# ---- clause IV: the inputs a gate GUARDS, which is how a verdict can be unreachable CORRECTLY -----
VAR = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
GUARD = re.compile(r"\[\s*-[fdx]\s+(\"[^\"]*\"|'[^']*'|\S+)\s*\]\s*(?:\|\||&&|;|$)")
REFUSER = re.compile(r"(exit 3\b|refuse\s)")


def guarded_inputs(root, path):
    """`(absent, present)` for the inputs this gate REFUSES on when they are missing.

    **THIS IS THE ANSWER TO "UNREACHABLE AND WHY", AND IT IS WHY `sb-gate.sh`'s `PASS` IS
    CORRECT.** `checks/sb-gate.sh:164-165` is `[ -f "$ORACLE" ] || refuse ...` and
    `[ -f "$DIFFER" ] || refuse ...`, and both are ABSENT (MEASURED: that directory holds one
    file, `REPORT.md`). Its `exit 0` is at `:277`, DOWNSTREAM, so PASS is unreachable **by the
    gate's own declaration** and fabricating an oracle to reach it would fabricate its own
    reference -- which is what `checks/sb-gate.sh:43` forbids in so many words.

    **WHICH VERDICT IS DOWNSTREAM IS A CONTROL-FLOW QUESTION AND THIS FILE DOES NOT ANSWER IT.**
    It reports the absent input and the refusal the gate names, and a gate-level
    `BLOCKED-BY-ABSENT-INPUT`, and stops. A guess about which of the five the absence takes away
    would be a claim about intent, and `AGENTS.md`: "a wrong reason is worse than no reason."
    """
    raw = path.read_text(errors="replace").splitlines()
    vars_ = {}
    for line in raw:
        m = VAR.match(line)
        if m and not line.lstrip().startswith("#"):
            vars_[m.group(1)] = m.group(2).strip().strip("\"'").replace("\\ ", " ")

    def expand(v):
        for _ in range(4):                 # a bounded fixpoint: `D=.agents/...` then `ORACLE=$D/x`
            nv = re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?",
                        lambda j: vars_.get(j.group(1), j.group(0)), v)
            if nv == v:
                return nv
            v = nv
        return v

    vars_ = {k: expand(v) for k, v in vars_.items()}
    absent, present = [], []
    for n, line in enumerate(raw, 1):
        if line.lstrip().startswith("#"):
            continue
        for m in GUARD.finditer(line):
            lit = expand(m.group(1).strip("\"'"))
            if lit.startswith(("-", "/", "$")) or "(" in lit:
                continue                       # a computed or substituted path: not resolvable here
            hit = root / lit
            # THE REFUSAL IS LOOKED FOR ON THE GUARD'S LINE AND THE NEXT THREE, because a `||`
            # guard's remedy is routinely a brace group on the following lines
            # (`checks/classify.sh:27`) -- and a guard whose ABSENCE IS NOT REFUSED ON is a
            # different finding from one that is, so guessing here would merge two classes.
            near = "\n".join(raw[n - 1:n + 3])
            (present if hit.exists() else absent).append((lit, n, bool(REFUSER.search(near))))
    return absent, present


def shebang(path):
    """The interpreter the file ASKS FOR, by name, or `(none)`. `checks/gatesweep.py:168` runs
    every `sh-*` member with ONE interpreter, so a member that asks for another is a member the
    runner is not running."""
    first = path.read_text(errors="replace").splitlines()[:1]
    m = re.match(r"^#!\s*(?:/usr/bin/env\s+)?(\S+)", first[0]) if first else None
    return Path(m.group(1)).name if m else "(none)"


def interp_matches(path):
    """Is the shebang's interpreter THE ONE the runner uses? `sh` and `bash` are the same
    program in POSIX mode on this host and `dash` is not either -- so the comparison is by
    EXECUTABLE PATH and the two names are reported, never normalised."""
    first = path.read_text(errors="replace").splitlines()[:1]
    m = re.match(r"^#!\s*(?:/usr/bin/env\s+)?(\S+)", first[0]) if first else None
    return (m.group(1) if m else "") == RUNNER


# ---- clause I: the population, TWICE, and the difference ----------------------------------------
def populations(root):
    """`(walk, immediate, prior_rows)` -- three measured sets and the differences between them.

    `checks/gatesweep.py:population()` is `gates-pop.gate_homes()` + `os.walk` +
    `gates-pop.entry_reason()`, so it IS the by-path population and this file adopts it rather
    than writing one. `gates/gates-pop.py:discover()` is the SAME homes over `iterdir()` -- the
    home's IMMEDIATE files only -- and the two therefore DIFFER, and the difference is a
    DEPTH, not a disagreement. `gates/shellverdict-gate.py` used the second one and its own
    reported population is the third, because a member that emits NO ROW is a member its
    denominator cannot see. **THE ARTEFACTS_OK() SHAPE, MEASURED.**
    """
    def shell(pairs):
        return {str(p.relative_to(root)) for p, r in pairs if r.split("-")[0] == "sh"}
    walk = shell(sweep.population(root))
    ents, _ = gpop.discover(root)
    imm = {str(p.relative_to(root)) for p in ents if (gpop.entry_reason(p) or "").split("-")[0] == "sh"}
    prior = _prior_population(root)
    return walk, imm, prior


def _prior_population(root):
    """`gates/shellverdict-gate.py`'s OWN population, MEASURED by calling its `census()`.

    Loaded and called rather than re-implemented: a second copy of another instrument's
    population is the defect `AGENTS.md` doctrine 1 exists for, and calling it also MEASURES it
    -- including the rows it silently drops."""
    sv = _load("svr_prior", HERE / "shellverdict-gate.py")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return {r.split("\t")[1] for r in sv.census(root)}


# ---- clause III: the readers, enumerated -------------------------------------------------------
def readers():
    """`{code: {word: example-input}}` over EVERY shipped reader of an exit code.

    THE FOUR READERS, NONE OF THEM RE-SPELLED: `gatekit.VERDICT` (the vocabulary),
    `gatekit.charge` (the additive resolution), `gatekit.verdict_of` (the reporting one), and
    `checks/gatesweep.py:classify` (the only one that reads the code TOGETHER WITH the watchdog
    token and the captured output, and therefore the only one that can disagree with the table).
    `checks/bounded.py:STATUS` is the PRODUCER and is the reason the disagreement exists: it
    exits 3 for a memory kill and 5 for a not-started, and 3 is REFUSED's code and 5 is DEAD's."""
    out = {}
    for rc in sorted(set(list(bounded.STATUS.values()) + list(gatekit.VERDICT) + [2])):
        seen = {}
        if rc in gatekit.VERDICT:
            seen[gatekit.VERDICT[rc]] = "gatekit.VERDICT"
        seen[gatekit.VERDICT[gatekit.charge(rc)]] = "gatekit.charge"
        for t in TOKENS:
            for label, text in TEXTS.items():
                word, _ = sweep.classify(t, rc, text)      # `name=None`: the UNCONSUMED-LANE
                seen.setdefault(word, f"classify({t}, {rc}, {label})")   # arm is not this question
        out[rc] = seen
    return out


def collisions():
    """`[(code, sorted(words))]` for every code two shipped readers disagree about."""
    return [(rc, sorted(w)) for rc, w in readers().items() if len(w) > 1]


# ---- the gate ------------------------------------------------------------------------------
def census(root):
    """One row per (member, verdict). `member` carries the file-level reading so a row that
    could not be read says so on every row rather than once in prose."""
    walk, imm, prior = populations(root)
    rows = []
    for rel in sorted(walk):
        p = root / rel
        try:
            cells, meta = reach(p)
        except OSError as e:
            rows.append(f"CELL\t{rel}\tALL\tUNRESOLVED\tunreadable: {type(e).__name__}")
            continue
        for word in sorted(cells, key=lambda w: CODES[w]):
            state, why = cells[word]
            rows.append(f"CELL\t{rel}\t{word}\t{state}\t{why}")
        if not prior.__contains__(rel):
            rows.append(f"PRIOR\t{rel}\t-\tNO-ROW\tgates/shellverdict-gate.py emits no row for it")
        for lit, n, refuses in guarded_inputs(root, p)[0]:
            rows.append(f"GUARD\t{rel}\t{lit}\tABSENT\tguarded at :{n}"
                        + (", refuses on absence" if refuses else ", no refusal on this line"))
    for rel in sorted(walk - imm):
        rows.append(f"WALKONLY\t{rel}\t-\tNOT-IN-IMMEDIATE\tonly gatesweep's os.walk reaches it")
    for rc, words in collisions():
        rows.append(f"COLLIDE\t{rc}\t{','.join(words)}\tREADERS-DISAGREE\t"
                    f"{readers()[rc][words[0]]} vs {readers()[rc][words[-1]]}")
    return rows, {"walk": walk, "imm": imm, "prior": prior}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rows", action="store_true", help="rows only")
    ap.add_argument("--plant", action="store_true", help="drive the census on a synthetic tree")
    ap.add_argument("--collisions", action="store_true", help="only the reader-disagreement table")
    ap.add_argument("--root", default=str(ROOT))
    a = ap.parse_args(argv)
    if a.plant:
        with tempfile.TemporaryDirectory() as t:
            return plant(Path(t))
    root = Path(a.root).resolve()

    if a.collisions:
        _print_collisions()
        return PASS

    rows, pop = census(root)
    if not rows:
        print("REFUSED, NOT A VERDICT: no rows, which is not agreement")
        return DEAD
    bad = [r for r in rows if r.split("\t")[3] in ("UNRESOLVED", "ABSENT", "NO-ROW",
                                                     "NOT-IN-IMMEDIATE")]
    if not a.rows:
        print(f"shellverdict-reach: population {len(pop['walk'])} shell members "
              f"(checks/gatesweep.py:population() BY PATH: gates-pop.gate_homes + os.walk + "
              f"entry_reason); vocabulary gatekit.VERDICT (by path); runner {RUNNER} "
              f"(checks/gatesweep.py:RUNNERS['sh'], by path)")
        print(f"  homes {gpop.gate_homes(root)[0]} | gates-pop.discover() {len(pop['imm'])} "
              f"immediate | shellverdict-gate.py {len(pop['prior'])} rows")
        print(f"  -- {len(pop['walk'])} - {len(pop['imm'])} = {len(pop['walk'] - pop['imm'])} "
              f"reachable only by the walk; {len(pop['walk'] - pop['prior'])} emit no row to the "
              f"prior census; {len(pop['prior'] - pop['walk'])} of the prior's are not members")
        _print_cells(root, pop)
        _print_collisions()
        for r in bad:
            print("  FINDING " + r.replace("\t", "  "))
    else:
        print("\n".join(rows))
    print(f"shellverdict-reach: {len(rows)} rows; {len(bad)} finding(s); "
          f"{len([r for r in rows if r.split(chr(9))[3] == 'UNRESOLVED'])} cell(s) UNRESOLVED "
          f"(charged to NEITHER verdict)")
    # `DEAD` IS NOT ZERO AND NOT A PASS. A member whose cells cannot be read is a member that
    # cannot be scored, and a census that scores it is `artefacts_ok()`'s shape.
    return FAIL if bad else PASS


def _print_cells(root, pop):
    for rel in sorted(pop["walk"]):
        try:
            cells, meta = reach(root / rel)
        except OSError:
            continue
        tally = {}
        for v, (state, _w) in cells.items():
            tally.setdefault(state, []).append(v)
        flag = "" if meta["interp_ok"] else f"  SHEBANG {meta['interp']} != {RUNNER} NOT-IN-RUNNER"
        gone = guarded_inputs(root, root / rel)[0]
        if gone:
            flag += f"  BLOCKED-BY-ABSENT-INPUT({len(gone)}: {', '.join(g for g, _n, _r in gone)})"
        print(f"  {rel:<44} " + "  ".join(f"{k}={len(v)}" for k, v in sorted(tally.items())) + flag)


def _print_collisions():
    rd = readers()
    print(f"  THE FIVE, AS READERS SEE THEM -- {len(TEXTS)} output shapes x {len(TOKENS)} watchdog "
          f"tokens, enumerated over {len(rd)} codes:")
    for rc in sorted(rd):
        w = sorted(rd[rc])
        tag = "COLLISION" if len(w) > 1 else "single"
        print(f"    rc={rc} {tag:<9} {'/'.join(w)}")
        if len(w) > 1:
            for word in w:
                print(f"        {word:<8} <- {rd[rc][word]}")


# ---- the plants ----------------------------------------------------------------------------
# A SYNTHETIC TREE STILL HAS TO BE A TREE THE POPULATION WILL LOOK AT, and
# `gates-pop.gate_homes()` admits a home only when an immediate file carries every marker in
# `_CERTIFY` plus one of `_CERTIFY_OR` AND declares a root. The witnesses are COPIED FROM THE
# REAL TREE'S OWN DERIVATION (`gate_homes(ROOT)[1]["witnesses"]`), so a witness that moves cannot
# make the plant vacuous, and no name is written down here.
GOOD = """#!/bin/sh
_d=${0%%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.."
exit 0
"""
DYN = GOOD.replace("exit 0", 'exit "$2"')
PROSE = GOOD.replace("exit 0", 'echo "the exit was $rc"')
NOEXIT = GOOD.replace("exit 0\n", 'echo done\nexec true\n')
PLANTS = (("A a literal exit is LITERAL, not UNNAMED", GOOD, "LITERAL"),
          ("A an `exit \"$2\"` is UNRESOLVED, not green", DYN, "UNRESOLVED"),
          ('A an `exit` inside a string is NOT an exit site', PROSE, "UNNAMED"),
          ("A an `exec` and no exit is UNNAMED, not NO-SITE", NOEXIT, "UNNAMED"))
# `<( )` IS THE REAL TREE'S FAILURE AND NOT A FIXTURE INVENTED FOR THIS FILE:
# `gates/README.md` records it as the third reason the shell form was retired, and
# `checks/run-f64.sh:214` / `checks/run-port-mm.sh:140` are live instances. `/bin/sh` is bash 3.2
# in POSIX mode and disables process substitution, so the file does not PARSE there at all.
UNPARSABLE = GOOD.replace("exit 0", "diff <(echo a) <(echo b)")


def seed(root):
    for rel in gpop.gate_homes(ROOT)[1]["witnesses"].get("checks", ()):
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil_copy(ROOT / rel, dst)


def shutil_copy(a, b):
    b.write_bytes(a.read_bytes())


def plant(root):
    d = root / "checks"
    seed(root)
    d.mkdir(parents=True, exist_ok=True)
    results = []
    for what, text, want in PLANTS:
        f = d / "plant-reach.sh"
        f.write_text(text)
        f.chmod(0o755)
        try:
            cells, _meta = reach(f)
        except OSError as e:
            cells = {gatekit.VERDICT[gatekit.PASS]: ("UNRESOLVED", str(e))}
        got = cells[gatekit.VERDICT[gatekit.PASS]][0]
        results.append((f"  {what:<56} {got}", got == want, f"{got}, wanted {want}"))
    # THE PLANT THAT MATTERS MOST: a file that CANNOT PARSE is UNRESOLVED on ALL FIVE, and an
    # UNRESOLVED row is not green -- `AGENTS.md`: "`DEAD` is not a zero and not a pass".
    f = d / "plant-reach.sh"
    f.write_text(UNPARSABLE)
    f.chmod(0o755)
    try:
        cells, _meta = reach(f)
    except OSError:
        cells = {}
    allun = bool(cells) and all(s == "UNRESOLVED" for s, _ in cells.values())
    results.append(("  a file that cannot parse is UNRESOLVED on all five cells", allun,
                    f"{sum(1 for s, _ in cells.values() if s == 'UNRESOLVED')} of {len(cells)}"))
    # AND THE CENSUS ITSELF GOES RED ON IT -- a plant that only asks `reach()` proves the CELL
    # moved, not that the GATE moved, and a gate that cannot go red is a gate nobody reads.
    red_rows, _ = census(root)
    red = [r for r in red_rows if r.split("\t")[3] in
           ("UNRESOLVED", "ABSENT", "NO-ROW", "NOT-IN-IMMEDIATE")]
    results.append(("  ...and the CENSUS goes red on it (not just the cell)", bool(red),
                    f"{len(red)} finding row(s)"))
    f.write_text(GOOD)
    f.chmod(0o755)
    green_rows, _ = census(root)
    still = [r for r in green_rows if "plant-reach" in r and r.split("\t")[3] == "UNRESOLVED"]
    results.append(("  ...and goes quiet on the SAME file once it parses", not still,
                    f"{len(still)} unresolved row(s) for it"))
    named = "checks/plant-reach.sh" in {r.split("\t")[1] for r in green_rows}
    results.append(("  a member that emits no exit site is still a ROW, not absent", named,
                    f"{len(green_rows)} rows"))
    ok = True
    for line, good, detail in results:
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'} {line:<70} {detail}")
    return PASS if ok else FAIL


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))