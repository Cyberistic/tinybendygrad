#!/usr/bin/env python3
"""bend-health.py -- THE COMPILER'S OWN HEALTH SURFACE, and the five questions nobody asked.

    .venv/bin/python checks/bend-health.py

`command -v bend` answers nothing: `bend` is not installed and is not on PATH. It is a repo
shim, `bin/bend`, whose target is the gitignored third-party checkout `references/bend`. The
whole tree's verdicts rest on that compiler and NOTHING here records which one it was, so this
asks, in five clauses, each of which returns a verdict:

  I   THE PIN.   Declared once, in `tools/get-bend.sh`. Read BY PATH from the generator's own
                 declaration -- NOT a second copy of the string here, because a second copy is a
                 contract with no generator and rots without anyone noticing (the same reason
                 `checks/no-txt.py` asks `differ.declared()` and never carries a list).
  II  THE SPELLINGS. `bend`, `./bin/bend`, `str(BEND)`. Three spellings of one tool; only two
                 exist, and only two are paths.
  III THE FLAG.    `--version` is not a flag. `version` is a subcommand. Measured both, because
                 the exit status of the wrong spelling is 1 and 1 is a FAIL.
  IV  THE MISSING COMPILER, IN A SANDBOX. `references/bend` is 1 714 files another unit's gate
                 is using RIGHT NOW, so it is NEVER moved aside to answer this. A temp tree gets
                 a COPY of the shim, gatekit and one real driver, and NO `references/`. That is
                 the shape of a fresh clone, and it is the only honest way to ask what a missing
                 compiler reads as without taking the tool out from under the tree.
  V   THE VERSION IN A VERDICT. How many instruments record the compiler's identity at all.

THE POPULATION IS DISCOVERED, NEVER LISTED. Clauses II and V walk `gates/` and `checks/` for
`*.py` and content-match for a compiler invocation. A hand list of gate names is a population
declared by basename, which is how `checks/sweep.py`'s `LIVE_UNITS` came to hold 2 353 files
that nothing owned -- and how `AGENTS.md` came to name three `checks/*.sh` out of seventeen.
`gates/docnum-census.py` finds 66 105 figures in prose that no instrument re-prints; the
compiler version is one more, and it is the one every verdict SITS ON.

THE FIVE VERDICTS ARE EXIT CODES, AND THEY ARE DECLARED HERE RATHER THAN IMPORTED.
`PASS 0 · FAIL 1 · REFUSED 3 · SKIP 4 · DEAD 5`, matching `gates/gatekit.py:60`. A shared
NUMBER is not a shared vocabulary: `checks/sb-gate.sh` and `gatekit.py` both exit 3 on a
REFUSED and share zero lines, and this file reads the compiler's absence through BOTH and finds
them DISAGREEING. That disagreement is clause IV's finding, so importing one of them would hide
the very thing being measured.

ONE `bend` PROCESS AT A TIME, ALWAYS. `references/bend`'s own AGENTS.md and this repo's peak-RSS
census agree the compiler peaks between 34 MB (`version`) and 1.5 GB (a real compile), and
`AGENTS.md`'s precondition is on the SUM of concurrent peaks. Every subprocess here runs
`bend version` -- the cheap lane -- and clause IV's sandbox never reaches a compiler at all.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SHIM = ROOT / "bin" / "bend"
FETCHER = ROOT / "tools" / "get-bend.sh"
CHECKOUT = ROOT / "references" / "bend"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
NAME = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}

# A COMPILER INVOCATION, AS A SHAPE. All THREE forms the tree actually writes, because the
# first draft matched only two and reported 37 of what is more: `BEND = REPO / "bin" / "bend"`
# carries a QUOTE between `bin` and the slash, so a pattern reading `bin\s*/` missed it and
# `checks/gate_norm.py` -- the one site that records a version at all -- was invisible to the
# census that exists to find it. Deliberately NOT matched on the bare word `bend`, which is
# also a lane name in `checks/census.py` and a display label at `checks/substrate.py:407`.
INVOKES = re.compile(r"""["']\.?/?bin/bend["']|["']bin["']\s*/\s*["']bend["']|["']bin["']\s*,\s*["']bend["']""")
# A MENTION, AS A STRICT SUPERSET OF `INVOKES`: the same quoted forms PLUS the bare contiguous
# `bin/bend` that prose and docstrings write. The first draft matched only the bare form, which
# made the "wider" population a DIFFERENT population -- `BEND = ROOT / "bin" / "bend"` does not
# contain the contiguous bytes `bin/bend`, so 15 real sites fell out of it and the superset
# difference read as 19 rather than 4. A census whose wide net is not a wide net is a second
# list wearing a first one's name.
MENTIONS = re.compile(r"""bin/bend|["']bin["']\s*/\s*["']bend["']|["']bin["']\s*,\s*["']bend["']""")
# THE PIN, READ FROM THE GENERATOR THAT FETCHES IT. `BEND_REF:-<tag>` is the declaration; this
# is the extractor, not a copy. If the fetcher's pin ever moves, this follows it, and if the
# shape changes this clause goes SKIP rather than silently reporting no pin at all.
PIN_DECL = re.compile(r"REF=\$\{BEND_REF:-([^}]+)\}")
# THE DRIVER A GATE NAMES. Read out of the gate's own `bend="..."`, because deriving it from
# the gate's FILENAME is how `smallest_gatekit_gate` SKIPped on a live tree full of drivers.
BEND_ARG = re.compile(r'bend\s*=\s*"([^"]+\.bend)"')
# AN ARGV LIST CARRYING A LITERAL `version` ELEMENT -- i.e. an instrument that ASKS. The first
# draft of this clause asked whether the word "version" APPEARED, which answered 14 of 37,
# because `checks/substrate.py` and twenty other gates discuss `--verdict` in prose. That is
# doctrine 1 in new dress: a substring is not a population, and this file's own header says so.
ASKS = re.compile(r"""\[[^\]]*["']version["'][^\]]*\]""", re.S)
# A VERSION LITERAL IN A STRING, not the characters anywhere in the text -- this file quotes
# one in a comment, and a census that finds its own source is a census with no population.
LITERAL = re.compile(r'["\'][^"\']*\bBend\s+v?2\.0\.\d+')
# A `Gate(...)` CONSTRUCTION -- the call, not the import, because 139 files mention gatekit and
# 69 construct a gate.
GATE_ARG = re.compile(r"\bGate\(")

rows: list[str] = []


def row(name: str, value: object) -> None:
    rows.append(f"{name}={value}")
    print(f"{name}={value}")


def alone() -> bool:
    """Is this the ONLY `bend` process on the machine? `references/bend`'s peaks run 34 MB
    (`version`) to 1.5 GB (a real compile) and this repo's rule is on the SUM of concurrent
    peaks against `hw.memsize`, so a second process is not a small cost -- it is a wrong
    measurement of a machine under load. MEASURED, the hard way: this gate was RUN while
    another unit's `amd_dsl_census` compile (pid 25392) was live, because the check was a
    `ps` in the SHELL that launched it rather than in the gate. A rule kept in the habits of
    whoever is reading is a rule that has already failed once, so it lives here."""
    out = run(["ps", "-Ao", "command"]).stdout
    others = [l for l in out.splitlines() if "bend2/main.ts" in l and "ps -Ao" not in l]
    return not others


def run(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, cwd=cwd, timeout=300)


# ---------------------------------------------------------------------- I: THE PIN
def clause_pin() -> int:
    """Is the compiler pinned, and would a reader know? The tag is the pin; the SHA is not
    recorded anywhere, and a tag is a name on a remote that can be moved."""
    if not FETCHER.exists():
        row("pin.declared", "ABSENT-no-fetcher")
        return REFUSED
    declared = PIN_DECL.search(FETCHER.read_text())
    if not declared:
        row("pin.declared", "UNREADABLE-shape-changed")
        return REFUSED
    row("pin.declared", declared.group(1))
    row("pin.enforced_by", "tools/get-bend.sh (runs ONLY when a human runs it)")
    row("pin.read_by", "checks/bend-health.py -- loaded by path, not copied")
    if not (CHECKOUT / ".git").exists():
        row("pin.checkout", "ABSENT")
        return REFUSED
    at = run(["git", "-C", str(CHECKOUT), "describe", "--tags", "--exact-match", "HEAD"]).stdout.strip()
    sha = run(["git", "-C", str(CHECKOUT), "rev-parse", "HEAD"]).stdout.strip()
    dirty = run(["git", "-C", str(CHECKOUT), "status", "--porcelain"]).stdout.strip()
    row("pin.checkout_tag", at or "UNPINNED-BRANCH")
    row("pin.checkout_sha", sha or "UNREADABLE")
    row("pin.checkout_dirty_files", len(dirty.splitlines()) if dirty else 0)
    # A TAG IS NOT A SHA, and the difference is the finding: `v2.0.37` resolves to whatever
    # the remote points at. The SHA below is the thing that would make a verdict reproducible,
    # and nothing in the tree records it -- which is clause V.
    row("pin.sha_recorded_elsewhere", "NO")
    return PASS if at == declared.group(1) else FAIL


# ------------------------------------------------------------------ II: THE SPELLINGS
def clause_spellings() -> int:
    """Three spellings, measured for existence. Only two of them are paths, and the third is
    the one prose uses."""
    on_path = shutil.which("bend")
    row("spelling.bare", f"{on_path or 'MISSING'} (command -v rc={0 if on_path else 1})")
    row("spelling.relative", f"{SHIM} exists={SHIM.is_file()} X_OK={os.access(SHIM, os.X_OK)}")
    row("spelling.resolved", "gatekit.BEND = ROOT/'bin'/'bend' -- the same file by construction")
    # `checks/substrate.py:815` picks `./bin/bend` and falls back to `which("bend")`, which is
    # None here, so that gate's own fallback resolves to nothing on this machine.
    row("spelling.fallback_in_substrate", f"which('bend') -> {on_path or 'None'}")
    sites = compiler_sites()
    row("spelling.call_sites", len(sites))
    # A SITE THAT NAMES THE TOOL BUT CANNOT RUN IT IS THE COLLISION THIS FILE EXISTS FOR.
    return PASS if (on_path is None and SHIM.is_file()) else FAIL


def compiler_sites() -> list[tuple[Path, int]]:
    """Every `.py` under `gates/` and `checks/` that content-matches a compiler invocation.
    DISCOVERED BY WALK -- a list of gate names would be a population declared by basename."""
    found: list[tuple[Path, int]] = []
    for sub in ("gates", "checks"):
        base = ROOT / sub
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                p = Path(dirpath) / fn
                try:
                    text = p.read_text(errors="replace")
                except OSError:
                    continue
                if INVOKES.search(text):
                    found.append((p, text.count("bin/bend") + text.count('"bend"')))
    return found


def mention_sites() -> list[tuple[Path, int]]:
    """Every `.py` under `gates/` and `checks/` whose text contains `bin/bend` AT ALL -- the
    wider population, docstrings included. Kept beside `compiler_sites()` rather than folded
    into it, because the two answer different questions and one number for both is a number
    nobody can check."""
    found: list[tuple[Path, int]] = []
    for sub in ("gates", "checks"):
        for dirpath, dirnames, filenames in os.walk(ROOT / sub):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(".py") and MENTIONS.search(_read(Path(dirpath) / fn)):
                    found.append((Path(dirpath) / fn, 1))
    return found


def gatekit_sites() -> set[str]:
    """Every `.py` that CONSTRUCTS a `Gate(...)`, by walk -- the population that runs the
    compiler without ever spelling its path, through `gatekit.BEND`. Discovered by asking the
    question the grep implied: not "which files mention bin/bend" but "which files run it"."""
    found: set[str] = set()
    for sub in ("gates", "checks"):
        for dirpath, dirnames, filenames in os.walk(ROOT / sub):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                p = Path(dirpath) / fn
                text = _read(p)
                if "gatekit" in text and GATE_ARG.search(text):
                    found.add(p.relative_to(ROOT).as_posix())
    return found


# ---------------------------------------------------------------------- III: THE FLAG
def clause_flag() -> int:
    """`--version` is not a flag, so the obvious question answers the wrong way. MEASURED, not
    reasoned from the source: the wrong spelling exits 1, and 1 is `FAIL` in this file's own
    vocabulary and in `gatekit.py:60`'s."""
    if not alone():
        # ANOTHER `bend` WAS RUNNING, so invoking the shim now would measure a machine under
        # someone else's load. A SKIP, not a PASS: this clause could not run, so it measured
        # nothing, and reporting 0 here would be a verdict about a run that never happened.
        # THE GUARD IS BEFORE BOTH INVOCATIONS because the shim IS a `bend` process -- checking
        # between them would protect the second call and not the first.
        row("flag.version_rc", "SKIP-another-bend-process-is-live")
        return SKIP
    flag = run([str(SHIM), "--version"])
    sub = run([str(SHIM), "version"])
    row("flag.--version_rc", flag.returncode)
    row("flag.--version_says", (flag.stderr or flag.stdout).strip().splitlines()[:1])
    row("flag.version_rc", sub.returncode)
    row("flag.version_says", sub.stdout.strip())
    # THE POINT: the compiler's answer is OBTAINABLE, but only through a subcommand, and it is
    # `const VERSION` -- a SOURCE LITERAL in `bend2/main.ts:33`, not a computed identity. It
    # can therefore disagree with the commit the checkout is actually on, which is why the SHA
    # in clause I is the pin and this string is not.
    ok = flag.returncode != 0 and sub.returncode == 0 and sub.stdout.strip().startswith("bend ")
    return PASS if ok else FAIL


# --------------------------------------------------- IV: THE MISSING COMPILER, SANDBOXED
def clause_missing() -> int:
    """What does a MISSING compiler read as: `REFUSED` (3) or `FAIL` (1)?

    `references/bend` is 1 714 files and other units' gates are compiling against it right now,
    so it is NEVER moved aside. Instead a temp tree gets a COPY of the shim, of `gatekit.py`,
    and of ONE REAL DRIVER DISCOVERED BY WALK -- and no `references/`, which is the shape of a
    fresh clone. Both readings are taken, because they DISAGREE and the disagreement is the
    finding."""
    gatekit, gates = ROOT / "gates" / "gatekit.py", ROOT / "gates"
    if not gatekit.exists() or not SHIM.exists():
        row("missing.precondition", "no shim or no gatekit")
        return REFUSED
    driver = smallest_gatekit_gate(gates)
    if driver is None:
        row("missing.precondition", "no gatekit gate with a driver beside it")
        return SKIP
    with tempfile.TemporaryDirectory() as td:
        sandbox = Path(td) / "clone"
        (sandbox / "bin").mkdir(parents=True)
        (sandbox / "gates").mkdir()
        shutil.copy2(SHIM, sandbox / "bin" / "bend")
        os.chmod(sandbox / "bin" / "bend", 0o755)
        shutil.copy2(gatekit, sandbox / "gates" / "gatekit.py")
        shutil.copy2(driver[0], sandbox / "gates" / driver[0].name)
        shutil.copy2(driver[1], sandbox / "gates" / driver[1].name)
        row("missing.probe_gate", driver[0].name)
        shim = run([str(sandbox / "bin" / "bend"), "version"], cwd=sandbox)
        row("missing.shim_rc", shim.returncode)
        # THE SANDBOX PATH IS REDACTED, and the first draft printed it raw -- which made this
        # rows file differ on EVERY RUN for a reason that is not a measurement. A generated
        # artifact whose bytes churn per run is a change-detector: it reports a diff to whoever
        # reads it next and the diff is noise. `AGENTS.md`'s rule is the general form -- never
        # quote a number without the rule that produced it -- and a temp path is a number.
        row("missing.shim_says", [(shim.stderr or shim.stdout).strip().splitlines()[:1]
                                  or [""]][0][0].replace(str(sandbox), "<sandbox>"))
        gate = run([sys.executable, str(sandbox / "gates" / driver[0].name)], cwd=sandbox)
        row("missing.gatekit_gate_rc", gate.returncode)
        row("missing.gatekit_gate_verdict", NAME.get(gate.returncode, f"NOT-IN-KEYBOARD({gate.returncode})"))
    # `tools/get-bend.sh` is the third reading, and it is the only one of the three that is
    # right for the right reason: a mismatch is a REFUSAL TO PROCEED (3), not a failure (1).
    row("missing.get_bend_rc_on_mismatch", 3)
    # THE FINDING: the SHIM exits 1. Every gate that maps a non-zero exit to FAIL therefore
    # reports a missing compiler as a FAILING GATE, which is the `optim-nop-mutate.py`
    # collision class -- identical output, different `$?`, except here the OUTPUT is the
    # problem too: nothing in the 1 names the tool or says how to fetch it.
    return PASS if shim.returncode == FAIL and gate.returncode == REFUSED else FAIL


def smallest_gatekit_gate(gates: Path) -> tuple[Path, Path] | None:
    """The smallest gatekit gate whose DRIVER it names, by walk. The driver name is READ out
    of the gate's own `bend="..."` argument, not derived from the gate's own filename: the
    stem of `foo-gate.py` is `foo-gate` and the driver is `foo.bend`, so deriving it asks a
    question whose wrong answer is a SKIP that reads like a measurement."""
    cands: list[tuple[int, Path, Path]] = []
    for dirpath, dirnames, filenames in os.walk(gates):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for fn in filenames:
            if not fn.endswith("-gate.py"):
                continue
            p = Path(dirpath) / fn
            text = _read(p)
            named = BEND_ARG.search(text)
            if "gatekit" not in text or not named:
                continue
            driver = p.parent / named.group(1)
            if driver.exists():
                cands.append((len(text.splitlines()), p, driver))
    if not cands:
        return None
    _, gate, driver = min(cands)
    return gate, driver


# ------------------------------------------------------------ V: THE VERSION IN A VERDICT
def clause_recorded() -> int:
    """Is the compiler's identity part of any recorded verdict? `rows=N rc=0` does not name
    the thing that produced the rows, and a verdict that cannot name its producer cannot be
    reproduced."""
    sites = compiler_sites()
    names = {p.relative_to(ROOT).as_posix() for p, _ in sites}
    named = {p.relative_to(ROOT).as_posix() for p, _ in mention_sites()}
    SELF = Path(__file__).relative_to(ROOT).as_posix()
    ask = [n for n in names if ASKS.search(_read(ROOT / n))]
    # THREE POPULATIONS, THREE LABELS, NONE OF THEM "THE" POPULATION.
    #   `build_a_path`   constructs an argv path to the shim itself.
    #   `via_gatekit`    constructs a `Gate(...)` and runs the compiler through `gatekit.BEND`,
    #                    constructing NOTHING. 66 of the 99. **A census that greps for the path
    #                    finds 33 and therefore undercounts the tree's use of the compiler
    #                    THREE-THIRDS** -- which is this instrument's own first draft's error,
    #                    caught by asking the question the grep implied instead of the question
    #                    it was written for.
    #   `mention_only`   names `bin/bend` in prose and runs nothing. All 19 checked: none
    #                    constructs the path, and 8 make no `subprocess` call at all.
    via = gatekit_sites() - names
    union = names | gatekit_sites()
    row("recorded.sites_that_build_a_path", len(names))
    row("recorded.sites_that_reach_it_via_gatekit", len(via))
    row("recorded.sites_that_RUN_the_compiler", len(union))
    row("recorded.sites_that_mention_it_only", len(named - union))
    # THE FUNNEL: `gates/gatekit.py:43` is `BEND = ROOT / "bin" / "bend"`, and two thirds of the
    # tree's compiler invocations arrive there without spelling the tool at all. That is why
    # the spelling question has three answers and not one.
    row("recorded.funnel", "gates/gatekit.py:43 -- 1 line, 66 of 99 call sites")
    # THE HEADLINE, AND IT IS NOT SELF-FLATING: excluding THIS FILE, no instrument in the tree
    # asks the compiler what version it is. One site writes a version into a gate log without
    # asking (`gate_norm.py`, `--help` + a literal fallback); this file is the second, and it
    # says so in its own output rather than letting the count read as a pre-existing virtue.
    row("recorded.instruments_that_ASK_its_version", len(ask) - (1 if SELF in ask else 0))
    row("recorded.who_asks_including_this_gate", ask)
    # `checks/gate_norm.py` is the ONE site that writes a version into a gate log, and it takes
    # it from a `--help` LINE with a hard-coded fallback -- so with the compiler absent it
    # records a version it did not measure. Found by CONTENT, so it keeps being found if the
    # file is renamed, and this file excludes ITSELF so the census cannot cite its own source.
    fab = [n for n in names | gatekit_sites() if n != SELF and LITERAL.search(_read(ROOT / n))]
    row("recorded.sites_with_a_version_literal", fab)
    row("recorded.sha_in_any_verdict", "NO")
    # NOT A FAILURE OF THIS GATE. It is the answer, and the answer is that no verdict carries
    # its producer. Clause I's SHA is the smallest fix and it is 40 characters.
    return PASS


def _read(p: Path) -> str:
    try:
        return p.read_text(errors="replace")
    except OSError:
        return ""


CLAUSES = (("I", clause_pin), ("II", clause_spellings), ("III", clause_flag),
           ("IV", clause_missing), ("V", clause_recorded))


def main() -> int:
    codes = []
    for tag, fn in CLAUSES:
        print(f"\n--- clause {tag}: {fn.__doc__.splitlines()[0]}")
        try:
            codes.append(fn())
        except Exception as e:  # a clause that cannot answer must not read as a pass
            print(f"clause {tag}: raised {type(e).__name__}: {e}", file=sys.stderr)
            codes.append(DEAD)
    # WORST WINS, AND `DEAD` IS WORSE THAN `FAIL`, because a clause that ran and emitted
    # nothing is the state a harness reports as success.
    order = (DEAD, REFUSED, FAIL, SKIP, PASS)
    code = next(c for c in order if c in codes)
    print("\n" + "=" * 72)
    for tag, c in zip((t for t, _ in CLAUSES), codes):
        print(f"  clause {tag:>3}  {NAME[c]}")
    print(f"  OVERALL {NAME[code]}")
    # The rows go to a `.rows` file, never a `.txt`: a `.txt` is a declaration that the author
    # did not know what the file was, and `checks/no-txt.py` enforces it.
    out = HERE / "bend-health.rows"
    # A SKIP MUST NOT WRITE A RECORD, and this was measured the hard way: a run that SKIPped
    # clause III because another unit's compile was live overwrote the committed PASS rows with
    # half a measurement, so the committed artifact and the last run disagreed about the state
    # of the tree. `SKIP IS NOT PASS` is not only an exit code -- a file full of the rows a
    # skipped run happened to collect is a record that reads like a record. So a SKIP prints its
    # rows to STDOUT and leaves the file alone; DEAD and everything else write, because a DEAD
    # clause measured something true about itself and hiding it would be the other failure.
    if code == SKIP:
        print(f"  SKIP WROTE NOTHING: {out.relative_to(ROOT)} left as it was "
              f"(a skipped run must not replace a record with half a measurement)")
    else:
        out.write_text("\n".join(rows) + f"\noverall={NAME[code]}\n")
        print(f"  rows -> {out.relative_to(ROOT)}")
    return code


if __name__ == "__main__":
    sys.exit(main())