#!/usr/bin/env python3
"""The substrate gate: HALF 1 judges each file by ITS OWN instrument, HALF 2 resolves every
`<Mod>.<name>` a file references against the modules that file imports.

It is the Python successor of `checks/substrate-check.sh` / `.agents/slop/substrate-check.sh`.
Both `.sh` files stay on disk as `exec` shims, and the shell's body is frozen at
`.agents/slop/substrate/oracle-check.sh` as the ORACLE this port is diffed against, because the
rule this project wrote for itself is that the Python reproduces the shell's verdict on EVERY
INPUT or it does not move. Its sha256 is in `ORACLE_PIN`, checked IN CODE on every run: a pin in
a comment is a pin that cannot fail.

WHAT IT GATES, AND THE DENOMINATOR EACH VERDICT TRAVELS WITH -- because a gate whose scope is a
comment is a gate nobody can check.

  HALF 1, per file, in the order the files were given:
    MISSING          the path is not a file.                                       +1 finding
    EMPTY            0 lines OR 0 bytes. `bend --check-only` answers `ALL PROOFS CHECK` for an
                     empty file, so the verdict is meaningless and is not taken.  +1 finding
    WARM / COLD       `.bend` -> `bend --check-only`   [.bend on disk; `bend=` counts what it
                       `.c`   -> `cc -fsyntax-only` +  was HANDED, which may be more]
                       `.mjs`     bend's generated C
                       anything else -> NO INSTRUMENT, counted apart, never COLD
    SKIP-VERDICT      `-n`, and the file has an instrument.
  `COLD` is EXACTLY: the FIRST line of the instrument's merged output is not the literal string
  `ALL PROOFS CHECK` (bend), or the exit status is non-zero (node, cc). IT IS A COUNT OF FILES,
  NOT OF CAUSES -- `--causes` says how many causes those files are, because the unit of work is a
  cause (`COLDNESS.md` §5: 35 red files, 15 causes, one missing def reddens 19). `--check-only`
  loads the whole transitive import closure, so a COLD file is very often red because of something
  it merely imports; THE SEMANTICS ARE THE SHELL'S, DELIBERATELY, because a port that changes the
  verdict is not a port.
    ROUTE   bend=, cc=, node=, no-instrument=, of N file(s) handed.
  PROVENANCE `port=` / `non-port=` derived from `git ls-files`, plus a PORT ALARM for any
    `tinybendygrad/` path that is not in the index. Reported, never silently absorbed.

  HALF 2, over the same files, and it reports its own coverage because an instrument that
  silently skips most of its input is the defect this project has catalogued twenty times:
    NAMES per file: modules, refs, exact, suffix-only, unresolved, unseen, unused-import
    TOTALS refs=, exact=, suffix=, unresolved=, unseen=, missing_module=, dead_import=
    BAD    deduped problem SITES, not files. Every site is +1 finding.
    COVERAGE qualified=, checked=, UNSEEN= -- the DENOMINATOR the name check travels with, so
      a reader sees the fraction of qualified refs it cannot decide. `unseen` counts qualified
      `Foo.bar` refs whose `Foo` is NOT an import alias -- a LOCAL type declared in the same
      file, or the unaliased `import Base` stdlib surface (`List`/`String`/`U32`/...). It is a
      named class of refs OUTSIDE the graph, not a name-resolution result and NOT a finding:
      the pool is built only from ALIASED imports, so these are unresolvable BY CONSTRUCTION.

POPULATION: with no file arguments, `--root [DIR]` sweeps every instrumented file under DIR
  (default `tinybendygrad`, the `.bend`/`.c`/`.js`/`.mjs` classes the router claims) discovered
  by `os.walk`, so the tree can be swept WITHOUT a caller's `find`. File arguments still take
  precedence and are judged exactly as before, so the 1-file and 2-file callers are unmoved.

EXIT STATUS: 0 clean · 1 at least one finding · 2 the scratch directory could not be made ·
3 no files given, or the frozen oracle moved. **ZERO ARGUMENTS IS A MISUSE, NOT A VERDICT:**
refused with a usage line, because `SUBSTRATE CLEAN: 0 file(s)` is the same verdict as a green
run over a population.

THE MEMORY BOUND IS NEW AND THE SHELL HAD NONE. All four instrument invocations in the shell are
`perl -e 'alarm 300; exec @ARGV'` or worse: that idiom bounds TIME and nothing else, `ulimit`
appears ZERO times in `agent-core.md`, `substrate-check.sh` and `e2e.sh` combined, and two
unbounded `bend` processes took this machine's memory to zero on 2026-10-05. Every invocation
here goes through `checks/bounded.py`, which watches the child's RSS and kills it, and ONE `bend`
PROCESS RUNS AT A TIME because 1,152 MB + 1,108 MB is the crash (`PEAKRSS.md`). The ceiling is
2048 MB rather than the 1 GB used for the census BECAUSE the measured maximum of the population is
1,152 MB (`renderer/nir.bend`) and `sz.bend` is 1,108 MB -- a ceiling below the population's own
maximum is a ceiling that changes verdicts. Kills and timeouts are reported on STDERR, never in
the verdict line, so the artifact stays the shell's byte for byte.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(os.environ["SUBSTRATE_ROOT"] if os.environ.get("SUBSTRATE_ROOT")
            else Path(__file__).resolve().parents[1])
GATES = Path(__file__).resolve().parents[1] / "gates"   # for `gatekit`, below
PY, BOUNDED = ".venv/bin/python", "checks/bounded.py"
# `env -u PYTHONPATH`: contamination is real here and `differ.py` measures it in a control.
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN.
#
# The hash is of the ORACLE COPY, which differs from the committed body by exactly one documented
# edit -- a `SUBSTRATE_REPO` default in its first `cd`, so a copy that sits one level deeper can
# still be run. Pinning the copy is what detects the copy drifting; pinning the committed body
# instead would be a check against `git`, a dependency this file does not otherwise have.
# `checks/differ.py` learned this the hard way: its pin WAS correct and WAS a comment, and
# nothing read it.
ORACLE_PIN = {
    "substrate/oracle-check.sh":
        "6d1000712f0f290ca479539f863dc76c6793cf4bbe94e983f94d56698994600e",
}

HERE = ".agents/slop/guardfix"
C_PROBE = f"{HERE}/probe-c.bend"
# THE `.c` THAT PROBE PULLS IN, whose FIRST LINE marks where the foreign block begins in the emit.
# NAMED, NOT GUESSED, and `c_context` FAILS LOUD if that exact line is not in the emit.
C_PROBE_FOREIGN = "tinybendygrad/runtime/dtype.c"
CC_WHY = "cc and a compiling bend C context are both required, and one is absent"
SHELL_SECONDS = 300   # the shell's `alarm 300`, kept so the TIME a run may take does not change
DEFAULT_MB = 2048     # above the measured 1,152 MB maximum; see the docstring

# THE POPULATION DECLARATION. The shell admitted the population was a caller's `find` and named
# no generator of its own -- doctrine 1. The classes below are exactly the ones `instrument_for`
# can judge; walking them is the tree sweep the usage line used to ask a caller to perform.
POP_ROOT = "tinybendygrad"
POP_SUFFIXES = (".bend", ".c", ".js", ".mjs")


def discover(root: str) -> list[str]:
    """Every instrumented file under `root`, by `os.walk`, in a stable order.

    A DIRECTORY WALK, not a hand list and not a suffix over a caller's text: the extensions are
    the router's own classes, and `os.walk` decides membership. The `*.staged-*` scratch copies
    and `*.mut` mutants do not end in one of these, so they are excluded by the same rule that
    includes the real files.
    """
    out: list[str] = []
    for d, dirs, fs in os.walk(root):
        dirs.sort()
        out += [os.path.join(d, f) for f in sorted(fs) if f.endswith(POP_SUFFIXES)]
    return out


# `gates/gatekit.py`'s OWN update-notice regex, imported rather than re-typed, and the reason is
# measured: `bend` prints `bend <ver> is available: run bend update` on STDERR on EVERY invocation,
# 42 bytes of it, so "stderr is non-empty" is not "bend said something" and a first-line rule that
# forgets the notice reads it as the instrument's answer on a perfectly healthy file.
sys.path.insert(0, str(GATES))
from gatekit import NOTICE  # noqa: E402  (the path has to exist before this line runs)

IF_OPEN = re.compile(r"^\s*#\s*(?:if|ifdef|ifndef)")
IF_CLOSE = re.compile(r"^\s*#\s*endif")
FRAG_LOC = re.compile(r"frag\.c:(\d+):")
FRAG_STRIP = re.compile(r"^.*frag\.c:\d+:\d+:\s*")
NODE_ERR = re.compile(r"^[A-Za-z]*Error")
NODE_LOC = re.compile(r"^.*:(\d+)$")


def oracle_drift() -> list[str]:
    """Every frozen oracle's actual sha against its pin. An empty list means intact.

    Named distinctly from anything this driver reports about its OWN rows: that asks whether the
    PYTHON side is well-formed, this asks whether the SHELL side is still the thing the port was
    diffed against. Two different questions, and one word was previously used for both.
    """
    import hashlib
    bad = []
    for name, want in ORACLE_PIN.items():
        path = ROOT / ".agents/slop" / name
        if not path.exists():
            bad.append(f"{name}: MISSING -- the frozen oracle is gone")
            continue
        got = hashlib.sha256(path.read_bytes()).hexdigest()
        if got != want:
            bad.append(f"{name}: {got[:16]} != pinned {want[:16]}")
    return bad


def which(*names: str) -> str:
    """`command -v`, first match wins, empty string for none. The shell's `-z "$CC"` tests."""
    for name in names:
        for d in os.environ.get("PATH", "").split(os.pathsep):
            if d and os.access(os.path.join(d, name), os.X_OK):
                return os.path.join(d, name)
    return ""


FLAGS = {"-n": 0, "--causes": 0, "-h": 0, "--help": 0}
VALUED = {"--mb": 1, "--seconds": 1}


def split_leading(argv: list[str]) -> tuple[list[str], list[str]]:
    """THE SHELL'S ARGUMENT GRAMMAR IS `-n` THEN FILES and nothing else -- `[ "$1" = "-n" ]`
    reads ONE slot, so a `-n` anywhere else is a FILENAME and becomes `MISSING`. argparse would
    accept an option after a filename, so this program's own options are read from the LEADING
    block only, against THIS table, and the first argument that is not one of them ends the parse:
    the old grammar, plus "the new flags go first". AN UNRECOGNISED `-x` IS A FILENAME, which is
    what the shell did with it, because the shell had no `-x` at all.

    `--root` TAKES AN OPTIONAL DIRECTORY. It consumes the next token only when that token is
    itself a DIRECTORY -- the disambiguator is `os.path.isdir`, because a file argument is never
    a directory, so `--root` followed by a file does not eat it. `--root` alone (or `--root=`)
    means the default root.
    """
    head: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root" or a.startswith("--root="):
            head.append(a)
            i += 1
            if a == "--root" and i < len(argv) and not argv[i].startswith("-") \
                    and os.path.isdir(argv[i]):
                head.append(argv[i])
                i += 1
        elif a in FLAGS:
            head.append(a)
            i += 1
        elif a in VALUED:
            head += argv[i:i + 1 + VALUED[a]]
            i += 1 + VALUED[a]
        elif a.startswith(tuple(f"{k}=" for k in VALUED)):
            head.append(a)
            i += 1
        else:
            break
    return head, argv[i:]


def parse(head: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="checks/substrate.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-n", dest="names_only", action="store_true",
                    help="HALF 2 only: suppress every per-file verdict and judge nothing")
    ap.add_argument("--causes", action="store_true",
                    help="after the gate, group the COLD files by CAUSE and say whether the "
                         "count is over files or causes. Does not change a verdict or an exit "
                         "status; costs one full compiler pass over the COLD files")
    ap.add_argument("--mb", type=int, default=DEFAULT_MB,
                    help=f"per-invocation memory ceiling in MB (default {DEFAULT_MB}, above the "
                         "measured 1,152 MB maximum, because a ceiling below the population's own "
                         "maximum is a ceiling that changes verdicts)")
    ap.add_argument("--seconds", type=int, default=SHELL_SECONDS,
                    help=f"time ceiling per invocation (default {SHELL_SECONDS}, the shell's alarm)")
    ap.add_argument("--root", nargs="?", const=POP_ROOT, default=None, metavar="DIR",
                    help=f"with no file arguments, sweep the instrumented files under DIR by "
                         f"os.walk (default {POP_ROOT}); file arguments, when given, take "
                         "precedence and are judged as before")
    return ap.parse_args(head)


# ------------------------------------------------------------------ the instruments
def bounded(cmd: list[str], opts: argparse.Namespace, what: str) -> tuple[str, int, str]:
    """One instrument invocation, under BOTH bounds. Returns `(first line, exit status, output)`.

    THE SHELL'S FOUR INVOCATIONS ARE `perl -e 'alarm 300; exec @ARGV'` (bend, node) or BARER
    (both `cc` calls, at what are now lines 157 and 228). That idiom bounds TIME and nothing
    else, and two unbounded `bend` processes took this machine's memory to zero on 2026-10-05.
    `checks/bounded.py` watches the child's RSS and kills it: exit 3 = killed on memory, 4 = timed
    out, 5 = could not start, 6 = measured nothing. EITHER WAY THE RUN PROVES NOTHING.

    ITS OWN LINES ARE ON ITS OWN CHANNEL. `bounded.py` guarantees its stdout is the child's stdout
    byte for byte and prints its `[bounded] ...` record on stderr, so the verdict line below is the
    shell's, byte for byte, and the fact that this one was KILLED goes to stderr, where it cannot
    contaminate the artifact. A gate is a text: a line added to the artifact is a line the oracle
    does not have. (The old code stripped `[bounded] ` lines out of what it thought was the merged
    stream; that stream was stdout and the record was never in it, so the strip did nothing for the
    verdict and the diagnostics it did remove were the child's.)
    """
    p = subprocess.run(
        [PY, BOUNDED, "--seconds", str(opts.seconds), "--mb", str(opts.mb), "--", *cmd],
        env=ENV, capture_output=True, text=True)
    # `bounded.py`'s contract, and the reason this changed at all: STDOUT IS THE CHILD'S, byte for
    # byte, and the `[bounded]` record is on STDERR. The strip below was deleting lines from the
    # child's own stdout that were never there -- it was removing the verdict line bounded.py used
    # to print INTO the stream it was measuring, and leaving the diagnostics it had merged there.
    # The verdict therefore arrives where it belongs, on a channel of its own.
    lines = [ln for ln in p.stdout.split("\n") if ln]
    for ln in p.stderr.split("\n"):
        if ln.startswith("[bounded] ") or ln.startswith("  "):
            print(f"[substrate] {what}: {ln}", file=sys.stderr)
    # THE SHELL'S `COLD` IS "the FIRST LINE of the instrument's MERGED output is not `ALL PROOFS
    # CHECK`", and `bend` puts its two streams in different places: a healthy file answers on
    # STDOUT, a broken one answers NOTHING on stdout and `SOME PROOFS FAIL / Error: / - expected`
    # on STDERR (MEASURED, both on this tree). So the two are joined HERE, in this function, where
    # the shell's merge used to be -- stdout first, because that is the order `2>&1` gave, and the
    # 42-byte update notice is not one of the two answers. `bounded.py` no longer merges anything;
    # this gate still needs the merged FIRST LINE, and saying so is cheaper than a second
    # definition of what `COLD` means.
    said = [ln for ln in p.stderr.split("\n")
            if ln.strip() and not NOTICE.match(ln.strip()) and not ln.startswith(("[bounded]", "  "))]
    merged = lines + said
    # A KILL, A TIMEOUT AND A NON-MEASUREMENT ARE NOT VERDICTS, and each has its own status:
    # 3 = killed on memory, 4 = timed out, 5 = could not start, 6 = measured nothing. Under the
    # shell's alarm every one of those produced NO first line either, so the verdict line below is
    # unchanged -- but saying which is true, on stderr, is what keeps "COLD :: <empty>" from being
    # read as a property of the file under test. `bounded.py`'s OWN token is `WITHIN-LIMITS` for
    # all four, so the status is what distinguishes them and it is read HERE, once.
    if p.returncode in (3, 4, 5, 6):
        print(f"[substrate] {what}: bounded.py reports exit {p.returncode} -- THIS RUN PROVES "
              "NOTHING, it was killed or never ran. NOT a verdict about the file.", file=sys.stderr)
    return (merged[0] if merged else ""), p.returncode, "\n".join(merged)


class Ctx:
    """bend's generated C runtime, ONCE, so `cc` can read a `.c` fragment AT ALL.

    MEASURED 2026-10-04, every number in the shell's `c_context`: `cc -fsyntax-only
    tinybendygrad/runtime/dtype.c` on its own is **190 errors** and every distinct one is "bend's
    runtime is not here". So the bare invocation is a CATEGORY ERROR, asked of a different tool:
    it reports a file RED that bend's own backend builds and runs. The generated unit also cannot
    be halved -- lines 1..2839 of the emit carry 44 `#if` opens against 43 `#endif` closes, so
    there is no self-contained preamble to `-include`. So the deficit is COUNTED here and the
    closure is APPENDED, which can only ADD declarations and can never turn a real syntax error
    green. The finished context is compiled ONCE ON ITS OWN before any fragment is judged: if the
    context does not compile the instrument produced nothing, and NO INSTRUMENT is printed --
    never a pass, never a cold.
    """
    def __init__(self, tmp: Path, opts: argparse.Namespace, bend: str, cc: str):
        self.tmp, self.opts, self.bend, self.cc = tmp, opts, bend, cc
        self.pre: Path | None = None
        self.lines = 0

    def ok(self) -> bool:
        """`[ -n "$CTX" ] && return 0` -- memoized, so the 300-second emit happens at most once."""
        if self.pre is not None:
            return True
        if not self.bend or not os.path.isfile(C_PROBE) or not os.path.isfile(C_PROBE_FOREIGN):
            return False
        gen = self.tmp / "gen.c"
        bounded([self.bend, C_PROBE, "-o", str(gen)], self.opts, "c_context emit")
        if not gen.is_file() or gen.stat().st_size == 0:
            return False
        body = gen.read_bytes()
        marker = b""
        for raw in Path(C_PROBE_FOREIGN).read_bytes().split(b"\n"):
            marker = raw
            break
        lines = body.splitlines(keepends=True)
        at = next((i + 1 for i, ln in enumerate(lines) if ln.rstrip(b"\n") == marker), 0)
        if not at.isdigit() or at < 2:   # `case $at in ''|*[!0-9]*) return 1` then `[ $at -gt 1 ]`
            return False
        pre = b"".join(lines[:at - 1])
        opened = sum(bool(IF_OPEN.match(ln)) for ln in lines[:at - 1])
        closed = sum(bool(IF_CLOSE.match(ln)) for ln in lines[:at - 1])
        if opened < closed:
            return False
        pre += b"#endif\n" * (opened - closed)
        # `CID(x)` IS NOT C: bend substitutes it for an effect id at EMIT time and no generated C
        # defines it, so without this stub `sz.c:51` reported COLD on 7 "undeclared CID" -- an
        # INSTRUMENT DEFECT, not a defect in `sz.c`. NEUTRAL is correct: the id's VALUE is
        # irrelevant to whether a fragment parses. TODO(GXR-11): this one thing the instrument
        # cannot judge.
        pre += b"#define CID(x) 0\n"
        path = self.tmp / "pre.c"
        path.write_bytes(pre)
        _, rc, _ = bounded([self.cc, "-fsyntax-only", str(path)], self.opts, "c_context compile")
        if rc != 0:
            return False
        self.pre, self.lines = path, grep_c_empty(pre)
        return True


def grep_c_empty(body: bytes) -> int:
    """`grep -c ''`: every line counts, INCLUDING a last line with no newline."""
    return body.count(b"\n") + (0 if body.endswith(b"\n") else 1) if body else 0


# ------------------------------------------------------------------ HALF 1
def instrument_for(path: str) -> tuple[str, str, str]:
    """THE ROUTER, and why it is FOUR verdicts and not three: a file with no instrument has NOT
    BEEN JUDGED, and printing `COLD` for it is a lie about a verdict nobody took. `.bend` was run
    through the bend instrument in an earlier cut, which sent `dtype.c` and `dtype.js` down it:
    all six non-`.bend` files in tinybendygrad/ read `SOME PROOFS FAIL` and not one of them is a
    Bend file, so the guard was always red on a class of files and its green was worth less."""
    if path.endswith(".bend"):
        return "bend", "bend --check-only", ""
    if path.endswith(".c"):
        return "cc", "cc -fsyntax-only + bend's C context", CC_WHY
    if path.endswith(".js") or path.endswith(".mjs"):
        return "node", "node --check", "node is not installed"
    return "none", "no instrument exists for this file class", "no instrument exists for this file class"


def half1(files: list[str], opts: argparse.Namespace, bend: str, cc: str, node: str,
          ctx: Ctx) -> tuple[list[str], int, dict[str, int], list[tuple[str, str]]]:
    """Every per-file verdict, in the order the files were given.

    `cold` is returned as `(path, first line)` pairs so `--causes` can attribute them without a
    second compiler pass in the common case; the text is only kept when `--causes` asked for it.
    """
    out: list[str] = []
    findings = 0
    tally = {"bend": 0, "cc": 0, "node": 0, "none": 0}
    cold: list[tuple[str, str]] = []
    for path in files:
        if not os.path.isfile(path):
            out.append(f"MISSING     {path}")
            findings += 1
            continue
        body = Path(path).read_bytes()
        # `wc -l` is a count of NEWLINES, so a non-empty file with no trailing newline is EMPTY.
        lines, size = body.count(b"\n"), len(body)
        if lines == 0 or size == 0:
            out.append(f"EMPTY       {path}  ({lines} lines, {size} bytes)  "
                       "<-- THE VERDICT IS MEANINGLESS")
            findings += 1
            continue
        inst, tag, why = instrument_for(path)
        if inst == "cc" and not cc:
            inst, why = "none", "cc is not installed"
        if inst == "node" and not node:
            inst, why = "none", "node is not installed"
        if inst == "bend" and not bend:
            inst, why = "none", "bend is not installed"
        if opts.names_only and inst != "none":
            out.append(f"SKIP-VERDICT {path}  ({lines} lines, verdict suppressed by -n)")
            continue
        head = f"{path}  ({lines} lines)"
        if inst == "none":
            tally["none"] += 1
            out.append(f"NO INSTRUMENT  {head}  :: {why} -- **NOT JUDGED, AND NOT COLD**")
            continue
        if inst == "bend":
            tally["bend"] += 1
            first, _, full = bounded([bend, path, "--check-only"], opts, path)
            if first == "ALL PROOFS CHECK":
                out.append(f"WARM        {head}  [{tag}]")
            else:
                # THE EXIT STATUS IS DISCARDED, deliberately: `--check-only` exits 1 on 14 clean
                # files (`dtype.bend`'s permanently-red laws), so the status is not the signal
                # and the FIRST LINE is.
                out.append(f"COLD        {head}  [{tag}]  :: {first}")
                findings += 1
                if opts.causes:
                    cold.append((path, full))
            continue
        if inst == "node":
            tally["node"] += 1
            first, rc, full = bounded([node, "--check", path], opts, path)
            err = full.split("\n")
            if rc == 0:
                out.append(f"WARM        {head}  [{tag}]")
            else:
                # node's FIRST line is only the path and the line number; the sentence that says
                # what is wrong is the `...Error:` line. A verdict that prints a path is not a
                # verdict.
                hit = next((ln for ln in err if NODE_ERR.match(ln)), err[0] if err else "")
                top = err[0] if err else ""
                loc = NODE_LOC.match(top)
                out.append(f"COLD        {head}  [{tag}]  :: {hit}  :: "
                           f"{path}:{loc.group(1) if loc else top}")
                findings += 1
                if opts.causes:
                    cold.append((path, full))
            continue
        if not ctx.ok():
            tally["none"] += 1
            # NO `-- **NOT JUDGED, AND NOT COLD**` HERE, and that asymmetry is the shell's. The
            # unrouteable class says it; a missing context says only why.
            out.append(f"NO INSTRUMENT  {head}  :: {why}")
            continue
        tally["cc"] += 1
        frag = ctx.tmp / "frag.c"
        # THE FRAGMENT GOES IN *AFTER* THE CONTEXT, so a diagnostic at context line L is the
        # fragment's line L-CTX_LINES.
        frag.write_bytes(ctx.pre.read_bytes() + body)
        _, rc, full = bounded([cc, "-fsyntax-only", str(frag)], opts, path)
        if rc == 0:
            out.append(f"WARM        {head}  [{tag}]")
            continue
        msg = next((ln for ln in full.split("\n") if "error:" in ln), "")
        at = FRAG_LOC.search(msg)
        # REWRITTEN, because `frag.c:2891` names a file that does not exist in the repo. THE
        # FIRST `error:` ONLY: cc cascades, and seven lines saying the same thing is not seven
        # findings.
        out.append(f"COLD        {head}  [{tag}]  :: "
                   + (msg if not at else f"{path}:{int(at.group(1)) - ctx.lines}: "
                                          + FRAG_STRIP.sub("", msg)))
        findings += 1
        if opts.causes:
            cold.append((path, full))
    return out, findings, tally, cold


# ------------------------------------------------------------------ PROVENANCE
def provenance(paths: list[str]) -> tuple[list[str], int]:
    """`bend=` ABOVE COUNTS WHATEVER IT WAS HANDED, and that is what this block exists for.

    THE CRITERION IS DERIVED, NOT DECLARED. A registry -- a `PROBES.md` the router reads, or a
    list of known-scratch names -- reproduces the defect one level down, because the probe that
    moves the count is the probe nobody remembered to register. Instead: PORT iff `git ls-files`
    knows the path. No registration, no convention, no memory. `no-upstream` is the SECOND,
    WEAKER criterion and is REPORTED, NOT FAILED: 16 files are legitimately not 1:1 with an
    upstream `.py`, so failing on it would report 16 findings forever.
    FAIL-SAFE DIRECTION: the alarm fails, and the only way to silence it is to `git add` the file.
    SCOPE: the alarm fires only for a path INSIDE `tinybendygrad/` -- a `$TMPDIR` scratch copy is
    not in the index either, and failing it would be a false positive on a sanctioned workflow.
    THE RESIDUAL IS A SUBTRACTION AND NOT A CLAIM, because a conditional sentence about agreement
    is a claim that can be wrong.
    """
    port = non = not_index = no_up = alarm = bendpop = nonbend = 0
    rows: list[str] = []
    alarms: list[str] = []
    for p in paths:
        # AN EXACT PATHSPEC. `git ls-files <path>` IS THE QUESTION; a `grep -r tinybendygrad` is
        # not -- a path SUBSTRING is not a path, and that mistake produced 315 phantom "files
        # swept", every one a `.agents/slop/.../tinybendygrad/...` copy.
        idx = subprocess.run(["git", "ls-files", "--error-unmatch", "--", p],
                             capture_output=True).returncode == 0
        live = p.startswith("tinybendygrad/")
        # `"tinygrad/"`, NOT `"tinybendygrad/"`: the upstream `.py` lives in the OTHER TREE. A
        # first cut of this port looked for `tinybendygrad/uop/ops.py`, so every live `.bend` read
        # `no-upstream`, `port=` fell to 0, and the PORT ALARM was the only line still true.
        up = os.path.isfile("tinygrad/" + p[len("tinybendygrad/"):-5] + ".py") \
            if live and p.endswith(".bend") else None
        if p.endswith(".bend"):
            bendpop += 1
        if idx and up is not False:
            port += 1
            continue
        non += 1
        if p.endswith(".bend"):
            nonbend += 1
        if not idx:
            not_index += 1
        if up is False:
            no_up += 1
            rows.append(f"  no-upstream   {p}")
        if live and not idx:
            alarm += 1
            alarms.append(
                f"  NOT-PORT      {p}\n"
                f"                :: NOT IN THE INDEX. NO PORT FILE IS UNTRACKED, so this is a probe, a\n"
                f"                :: mutant, or scratch copy -- whatever it is, it is not in the tree.\n"
                f"                :: IT IS STILL COUNTED IN `bend=` ABOVE. Silence requires ownership:\n"
                f"                :: `git add` it, or delete it.")
    return ([f"PROVENANCE  port={port}  non-port={non}   of which not-in-index={not_index} "
             f"no-upstream={no_up}   (of {port + non})"] + rows + alarms
            + [f"PORT ALARM  {alarm} file(s) inside tinybendygrad/ are not in the index.",
               # COUNTED FROM THE `.bend` POPULATION HANDED, NOT FROM `bend=` ABOVE, AND THE REASON
               # IS MEASURED COST: a full 138-file verdict pass is minutes while this line is 2.4 s,
               # and a number too expensive to check is a number nobody checks.
               f"DENOMINATOR .bend handed={bendpop}, of which non-port={nonbend}  =>  "
               f"the port count to compare against is {bendpop - nonbend}"],
            1 if alarm else 0)


# ------------------------------------------------------------------ HALF 2
IMPORT = re.compile(r"^import\s+(?:\./)?([A-Za-z0-9_./-]*\.bend)\s+as\s+([A-Za-z_]\w*)\s*$")
DEF = re.compile(r"^def\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")
TYPE = re.compile(r"^type\s+([A-Za-z_]\w*)")
LAW = re.compile(r"^law\s+([A-Za-z_]\w*)")
VARIANT = re.compile(r"^[ \t]+([A-Za-z_]\w*)\s*[{(:=]")
REF = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")
# THE SHELL'S STRING-LITERAL REGEX, CHARACTER FOR CHARACTER, and it is NOT the one a reader
# would write. The shell's `python3 -c` body is inside a SHELL SINGLE-QUOTED STRING, so the four
# backslashes in `re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"", ...)` are passed through as FOUR and reach
# Python's raw string as four, which the regex engine then reads as TWO escaped backslashes. So
# the engine is matching `\\\\` -- a run of TWO literal backslashes -- where `[^"\\]` excludes ONE.
#
# MEASURED, and this is not a curiosity: the port that "fixed" this to the obvious `\"(?:[^"\\]|
# \\.)*\"` disagreed with the oracle by exactly ONE `unseen` on `uop/validate.bend`, 547 vs 548,
# on a 663-reference line. A single mis-stripped string literal turned a quoted name into a
# `Foo.bar` reference. **THE ORACLE IS RIGHT BY ACCIDENT AND THE PORT WAS WRONG ON PURPOSE** --
# there is nothing to fix here, only to reproduce, and this comment is the only thing standing
# between the next reader and a well-meaning repair that breaks the gate.
STRING = re.compile(r"\"(?:[^\"\\\\]|\\\\.)*\"")
_DECLS: dict[str, set[str]] = {}


def decls(path: str) -> set[str]:
    """Every name a module declares. `def`/`type`/`law` are always at column 0 in this tree
    (measured: 27,661/804/44, none indented). A `type X is Data:` block's VARIANTS are at
    arbitrary indent and are ADDRESSABLE BARE -- `def ParamArg.no_slot` sits alongside
    `ParamArg.of` and a cross-file `O.ParamArg.no_slot` resolves to the DEF PATH, not to `O.` plus
    a prefix."""
    if path in _DECLS:
        return _DECLS[path]
    out: set[str] = set()
    if os.path.isfile(path):
        inb = False
        with open(path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                if inb:
                    s = ln.strip()
                    if not s or s.startswith("#"):
                        continue
                    if ln[:1] in (" ", "\t"):
                        m = VARIANT.match(ln)
                        if m:
                            out.add(m.group(1))
                        continue
                    inb = False
                m = DEF.match(ln) or TYPE.match(ln) or LAW.match(ln)
                if m:
                    out.add(m.group(1))
                    inb = bool(TYPE.match(ln))
    _DECLS[path] = out
    return out


def code_only(line: str) -> str:
    """String literals first, then the comment -- in that order, because a `#` inside a string
    is not a comment. See `STRING` for why its pattern is not the obvious one."""
    line = STRING.sub("\"\"", line)
    i = line.find("#")
    return line[:i] if i >= 0 else line


def half2(paths: list[str]) -> tuple[list[str], Counter[str]]:
    """COLLECTIVE COMPLETENESS: does every `<Mod>.<name>` a file references exist in a module that
    file imports. HALF 1 ANSWERS "does this file parse?", which is a question about ONE FILE; the
    real failure today is the other question -- a file that compiles can still be missing a name
    something else needs, and this is what catches the `helpers.bend` truncation HALF 1 was built
    for, because an empty provider declares nothing and every call into it goes unresolved.

    `BAD` COUNTS DEDUPED PROBLEM SITES, NOT FILES, and `unseen` counts the qualified references
    this check is BLIND to -- an uppercase `Foo.bar` whose `Foo` is not an import alias. That is
    TWO things and the earlier comment named only one: a LOCAL type declared in the same file
    (`Reg.foo`, `Asm.foo`), and the unaliased `import Base` stdlib surface (`List`/`String`/
    `U32`). Both are OUTSIDE the graph by construction, because the pool is built only from
    ALIASED imports -- so `unseen` is a coverage class, not a name-resolution result. The
    COVERAGE line carries the DENOMINATOR (qualified = refs + unseen) so the blind fraction is
    legible. An instrument that hides its own blind spot is the defect this project has
    catalogued twenty times, so the numbers ride in the output AND are tied to their whole.
    """
    t: Counter[str] = Counter()
    problems: dict[tuple[str, int, str], str] = {}

    def note(key, why):
        if key not in problems:
            problems[key] = why

    lines: list[str] = []
    for path in paths:
        if not os.path.isfile(path):
            note((path, 0, "<the file under test>"), "FILE UNDER TEST IS ABSENT")
            continue
        alias = {}
        with open(path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                m = IMPORT.match(ln)
                if m:
                    alias[m.group(2)] = os.path.normpath(
                        os.path.join(os.path.dirname(path), m.group(1)))
        pool = defaultdict(set)
        for a, t_ in alias.items():
            pool[a] |= decls(t_)
            t["nomod"] += 0 if os.path.isfile(t_) else 1
            if not os.path.isfile(t_):
                note((path, 0, a + " -> " + t_), "MODULE FILE IS ABSENT")
        used: Counter[str] = Counter()
        unseen0 = t["unseen"]
        k = u = refs = 0
        with open(path, encoding="utf-8", errors="replace") as f:
            for n, raw in enumerate(f, 1):
                for m in REF.finditer(code_only(raw)):
                    al, dotted = m.group(1), m.group(2)
                    if al not in alias:
                        if al[:1].isupper():
                            t["unseen"] += 1
                        continue
                    used[al] += 1
                    t["total"] += 1
                    refs += 1
                    parts = dotted.split(".")
                    d = pool[al]
                    if ".".join(parts) in d:
                        t["exact"] += 1
                    elif any(".".join(parts[i:]) in d for i in range(1, len(parts))):
                        k += 1
                        t["suffix"] += 1
                        note((path, n, al + "." + dotted), "ONLY A SUFFIX MATCHES")
                    else:
                        u += 1
                        t["unres"] += 1
                        note((path, n, al + "." + dotted), "NOT DECLARED IN " + alias[al])
        dead = sum(1 for a in alias if not used[a])
        t["deadimport"] += dead
        lines.append(f"NAMES     {path}  ({len(alias)} modules, {refs} refs, {refs - k - u} exact, "
                     f"{k} suffix-only, {u} unresolved, {t['unseen'] - unseen0} unseen, "
                     f"{dead} unused-import)")
    lines.append("---")
    lines += [f"UNRESOLVED  {p}:{ln}: {ref}  :: {why}" for (p, ln, ref), why in problems.items()]
    lines.append(f"TOTALS refs={t['total']} exact={t['exact']} suffix={t['suffix']} "
                 f"unresolved={t['unres']} unseen={t['unseen']} missing_module={t['nomod']} "
                 f"dead_import={t['deadimport']}")
    qualified = t["total"] + t["unseen"]
    pct = (100.0 * t["unseen"] / qualified) if qualified else 0.0
    # THE COVERAGE LINE IS THE DENOMINATOR THE NAME CHECK TRAVELS WITH. `unseen` is NOT a finding
    # -- it is a named class of refs the import-graph pool cannot decide (see the docstring) --
    # so it does not move a verdict, but a reader who sees only `exact=refs` would read 100%
    # resolved. This line says the fraction that was never in scope.
    lines.append(f"COVERAGE qualified={qualified} checked={t['total']} "
                 f"UNSEEN={t['unseen']} ({pct:.1f}%)  <- unseen refs are OUTSIDE the import "
                 "graph (local types + the unaliased `import Base` stdlib). NOT findings; an "
                 "unaccounted surface.")
    lines.append(f"BAD {len(problems)}")
    return lines, t


# ------------------------------------------------------------------ --causes
# THE ERROR SHAPES `COLD` ACTUALLY STANDS FOR, most specific first, so the generic type-mismatch
# shape cannot swallow `a defined name`. Measured over the whole population (`COLDNESS.md` §1);
# every one of these is a line `--check-only` prints, not a paraphrase.
CAUSES = (
    (re.compile(r"^Error: (\d+) TODOs? found\."), "HOLES", 1),
    (re.compile(r"^Error: (\d+) defs rely on unsafe or foreign code:"), "FOREIGN", 1),
    (re.compile(r"^- expected : a defined name / observed : (\S+)"), "MISSING-DEF", 1),
    (re.compile(r"^- expected : a fresh name \(duplicate declaration: (\S+?)\)"), "DUPLICATE", 1),
    (re.compile(r"^- message : a declared constructor \(unknown: (\S+?)\)"), "UNKNOWN-CTOR", 1),
    (re.compile(r"^- expected : ('def','type' or 'law') / observed : (\S+)"), "SYNTAX", 2),
    (re.compile(r"^- expected : (\S+) / observed : (\S+)"), "TYPE-MISMATCH", 2),
)


def cause_of(output: str) -> tuple[str, str] | None:
    for rx, shape, group in CAUSES:
        if m := rx.search(output):
            return shape, " ".join(m.group(group).split())
    return None


def causes_section(cold: list[tuple[str, str]], files: list[str]) -> list[str]:
    """WHETHER THE `COLD` COUNT ABOVE IS OVER FILES OR OVER CAUSES, stated, because the unit of
    work is a CAUSE: 35 red files came from 15, and one missing def reddens 19 of them. The owner
    is looked up in the names the files UNDER TEST declare, so "declared nowhere" means exactly
    that and is not a guess -- the census that found `O.ParamArg.no_slot` did the same lookup."""
    owner: dict[str, list[str]] = defaultdict(list)
    for p in files:
        for name in decls(p):
            owner[name.split(".")[-1]].append(p)
    grouped: dict[tuple[str, str], list[str]] = defaultdict(list)
    for path, output in cold:
        grouped[cause_of(output) or ("UNATTRIBUTED", "")].append(path)
    out = ["", "CAUSES  (NOT the gate. This is what the COLD count above is counting, and a count",
           "        whose value depends on a neighbour's contents is measuring the wrong thing.)",
           f"COLD counts {len(cold)} FILES. Those files are {len(grouped)} CAUSES. "
           "THE UNIT OF WORK IS A CAUSE."]
    for (shape, symbol), paths in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
        declared = sorted({q for q in owner.get(symbol.split(".")[-1], [])})
        where = (f"declared in {declared[0]}" if declared else
                 "DECLARED NOWHERE in the files under test")
        out.append(f"  {len(paths):3d} file(s)  {shape:<14} {symbol or '(none)':<24} {where}")
        out.append(f"                   :: {', '.join(paths)}")
    return out


# ------------------------------------------------------------------ the run
def refuse(prog: str) -> int:
    """ZERO ARGUMENTS IS A MISUSE, NOT AN EMPTY VERDICT. MEASURED 2026-10-05: invoked with no
    arguments this script printed `SUBSTRATE CLEAN: 0 file(s)`, which is the SAME VERDICT AS A
    GREEN RUN OVER A POPULATION. A guard that measures nothing must not report agreement. This is
    the FOURTEENTH instance of the project's oldest failing -- `--check-only` reports `ALL PROOFS
    CHECK` FOR AN EMPTY FILE -- and the first where the EMPTINESS IS IN THE ARGUMENT LIST. The
    usage line prints `$0` exactly as the shell did, so the two agree on everything but the name
    of the program they are."""
    for ln in ("REFUSED: no files given. A guard invoked with an empty population must not",
               "report agreement -- that is indistinguishable from a green run over nothing.",
               f"usage: {prog} <file.bend|file.c|file.js> [more ...]",
               f"       or: {prog} --root [DIR]   (sweeps DIR by os.walk; DIR defaults to "
               f"{POP_ROOT})"):
        print(ln)
    return 3


def run(files: list[str], opts: argparse.Namespace, tmp: Path, origin: str | None = None) -> int:
    bend = "./bin/bend" if os.access("./bin/bend", os.X_OK) else which("bend")
    cc = which("cc", "clang")
    node = which("node")
    out: list[str] = []
    findings = 0
    ctx = Ctx(tmp, opts, bend, cc)
    # HALF 1 iterates the RAW arguments. HALF 2 iterates what `print -l -- "$@"` fed to
    # `python3 -c`, which SPLITS AN ARGUMENT ON AN EMBEDDED NEWLINE and drops an empty one --
    # so an argument containing a newline is judged by one file and name-checked as two. Kept,
    # because it is the shell's shape and a silent tidy-up is not a port.
    paths = [ln for a in files for ln in a.split("\n") if ln]
    half, findings, tally, cold = half1(files, opts, bend, cc, node, ctx)
    out += half
    out.append(f"ROUTE   bend={tally['bend']}  cc={tally['cc']}  node={tally['node']}  "
               f"no-instrument={tally['none']}  (of {len(files)} file(s))")
    if origin is not None:
        out.append(f"POPULATION root={origin} files={len(files)} by os.walk "
                   f"({' '.join(POP_SUFFIXES)})")
    prov, prov_rc = provenance(paths)
    # CAPTURED IMMEDIATELY, which is the point: `$?` after a `[` is that `[`'s status and not the
    # block's, and a vacuous verdict looks identical to a pass.
    out += prov or [""]
    findings += prov_rc
    names, ntot = half2(paths)
    out += names or [""]
    bad = next((int(ln[4:]) for ln in names if ln.startswith("BAD ")), 1)
    findings += max(bad, 1) if bad else 0
    checked, unseen = ntot["total"], ntot["unseen"]
    qualified = checked + unseen
    if opts.causes and cold:
        out += causes_section(cold, paths)
    if findings > 0:
        out += ["",
                f"SUBSTRATE NOT CLEAN: {findings} finding(s) across {len(files)} file(s) -- "
                "empty, missing, cold, or collectively incomplete.",
                "ANY VERDICT TAKEN AGAINST THESE FILES IS **INCONCLUSIVE**, NOT A RESULT."]
    else:
        out.append("")
        if tally["none"] > 0:
            out += [f"NO INSTRUMENT: {tally['none']} of {len(files)} file(s) were **NOT JUDGED** "
                    "(no instrument exists, or it produced nothing).",
                    "A FILE WITH NO INSTRUMENT IS NOT A PASS AND NOT A FAILURE. It is an "
                    "unmeasured surface."]
        out.append(f"NAMES CLEAN: {len(files)} file(s), all non-empty, {checked} of {qualified} "
                   "qualified refs checked, all cross-file names resolved. "
                   "**VERDICT NOT TAKEN** (-n)." if opts.names_only else
                   f"SUBSTRATE CLEAN: {len(files)} file(s), all non-empty, each judged by its OWN "
                   f"instrument, all cross-file names resolved ({checked} of {qualified} qualified "
                   f"refs checked; {unseen} unseen).")
        out += ["(name check is scoped to the IMPORT graph. It cannot see the unaliased "
                "`import Base`",
                " surface -- List. String. U32. -- nor a LOCAL type (`Reg.`/`Asm.`), which together",
                " are the COVERAGE UNSEEN class. Read the `COVERAGE` and `unseen=` numbers, not just",
                " the verdict: an instrument that hides its own blind spot is the defect this project",
                " has catalogued twenty times.)"]
    if opts.causes and cold:
        out += causes_section(cold, paths)
    for ln in out:
        print(ln)
    return 1 if findings else 0


def main() -> int:
    if drift := oracle_drift():
        # Refuse, loudly, and name the file. A gate that diffs against a moved oracle reports a
        # verdict about a comparison nobody is making.
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_PIN in checks/"
              "substrate.py -- do not delete the pin.", file=sys.stderr)
        return 3
    os.chdir(ROOT)   # the shell's `cd "$(dirname "$0")/../.."`; every path below is repo-relative
    argv = sys.argv[1:]
    head, files = split_leading(argv)
    opts = parse(head)
    # `SCR=$(mktemp -d ...) || exit 2` came FIRST in the shell, so a scratch directory that cannot
    # be made is exit 2 and the refusal is exit 3 -- in that order.
    with tempfile.TemporaryDirectory(prefix="substrate.") as tmp:
        origin = None
        if not files and opts.root is not None:
            origin, files = opts.root, discover(opts.root)
        if not files:
            return refuse(sys.argv[0])
        return run(files, opts, Path(tmp), origin)


if __name__ == "__main__":
    sys.exit(main())