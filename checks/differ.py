#!/usr/bin/env python3
"""One driver for the graphcmp corpus: every artifact, plus the two-run stability check.

It replaces `.agents/slop/graphcmp-run.sh` and `.agents/slop/graphcmp-repro.sh`, whose
artifacts under `runs/graphcmp/D/` it reproduces byte for byte; both `.sh` files stay on
disk as `exec` shims, and the shell's bodies are frozen in `.agents/slop/diffpy/` as the
ORACLE the port is diffed against.

Two gates, and WHAT EACH ONE CLAIMS, because a gate whose scope is a comment is a gate
nobody can check:

  run     the per-graph VERDICT line and its DENOMINATOR line for every graph in the
          CORPUS (`graphcmp.GRAPHS`), each against the verdict it is EXPECTED to print -- and
          the DEFAULT is AGREE, so the expectations are a table of EXCEPTIONS and not a
          table of graphs; plus a count of how many rows were WRONG; then the canonical
          py-vs-bend byte identity of each graph, 5 same-side controls, 1 cross-graph
          comparison, 8 plants that must DISAGREE and name something, the ordered/`--equiv`
          split on the same reordered pair, 4 conflations, the DEBUG-level comparison, 5
          two-run stability pairs, the 0-row guard fired on purpose, the both-sides coverage
          census, the CPython `DEBUG>=1` reachability question, and the raw CPython ops probe.
          It REFUSES (exit 1) while any row disagrees with what the port emitted, and
          REFUSES (exit 3) before it starts while the POPULATION is not decided -- a graph
          list that nobody has re-decided is a corpus that cannot certify itself.

  repro   that ONE run is reproducible: two clean runs, sha256 over the non-blank lines of
          every artifact, byte-compared. It first WAITS for the substrate (`--check-only`'s
          FIRST line, never its exit status) and then insists the run is HEALTHY -- pinned
          counts a silent step cannot imitate -- and that no artifact is malformed.

  snap    the snapshot primitive both of those are built from, so a third party can compare
          two runs of either driver without re-implementing the hashing.

EVERY COMMAND HERE IS UNDER THE CORPUS LOCK, and the corpus is a SINGLETON: `run` and
`repro` both write the ONE directory `runs/graphcmp/D`, so two of them at once interleave two
verdicts into one directory.  MEASURED 2026-10-23: a `repro` at 03:37 and a `run` at 03:45 ran
CONCURRENTLY, the `run` overwrote a green `D0-run-summary.txt` with one that was green too
while its own two substrate digests DISAGREED, and `gates/corpuswitness-gate.py` went red on
4 of its 7 readings while `verdict.reported` stayed OK.  A second run now REFUSES, names the
holder, and exits 3 (`REFUSED`) without touching the directory -- and the lock is an
`fcntl.flock`, so the kernel releases it when the holder dies and it cannot be stolen.
See `CORPUS_LOCK` below.
"""
import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import inspect
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
D = ROOT / "runs/graphcmp/D"
PY, GCMP = ".venv/bin/python", ".agents/slop/graphcmp.py"
# `env -u PYTHONPATH` is REQUIRED (it contaminates a control) and `LC_ALL=C` is REQUIRED (a
# locale-colated sort fabricates diffs). `DEV=NULL` is the rebase gate's own setting;
# graphcmp.py overrides it from its own `--dev`, which is why every artifact names its device.
#
# `BEND_NO_TELEMETRY=1` is REQUIRED, AND IT IS THE ONLY OFF-REPO INPUT IN THE MEASUREMENT.
# The compiler's daily check (`references/bend/bend2/main.ts:185-211`) fetches
# `https://bend-lang.com/check` ONCE A DAY into `~/.bend/check.json` -- a file in the
# DEVELOPER's HOME, not in this repository -- and prints `bend <published> is available` on
# stderr when the published version beats the local one. That notice IS D10's transcript
# (`attempt_note`, `graphcmp.py:2369-2371`), so the corpus's D10 pin was a pin on a network
# answer. MEASURED 2026-10-22, five cases, the oracle's own `emit_bend`, each with its own
# `HOME` so the user's cache was never touched:
#     cache ver=2.0.38  -> e166842f40741d48... (the transcript's note)   == THE PIN
#     cache ver=2.0.39  -> 312e2b4f4c75494d...                          != THE PIN  <- upstream's next release
#     BEND_NO_TELEMETRY -> e7f59eefc308ea3b...                          == the OLD PIN, and IDENTICAL
#                                                                              with and without a cache
# So: with the flag the transcript is a function of THIS REPOSITORY alone; without it, the
# next upstream Bend release reds the pin with NO repo change, NO port change and NO commit
# to explain it. The flag is the compiler's OWN switch (`main.ts:186-188`), so this asks the
# compiler to be quiet, not to be different.
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C", "DEV": "NULL", "PYTHONHASHSEED": "0", "NOOPT": "0", "BEND_NO_TELEMETRY": "1"}

# --------------------------------------------------------------------------- THE CORPUS LOCK
#
# ONE WRITER, ONE ARTEFACT DIRECTORY.  `runs/graphcmp/D/` is a SINGLETON: `run` and `repro`
# both write it, artifact by artifact, and a second run over the first one's artifacts
# interleaves two verdicts into one directory.
#
# MEASURED 2026-10-23, AND IT IS THE DEFECT THIS LOCK EXISTS FOR: a `repro` started at 03:37
# and a `run` started at 03:45 ran CONCURRENTLY.  The `run` overwrote a green
# `D0-run-summary.txt` -- and the summary it wrote was green too (35/35 agree, 35/35
# byte-identical, 8/8 plants) while its OWN two substrate digests DISAGREED
# (`substrate-start=0c950c47...` vs `substrate-end=074e0233...`), because a `.bend` edit landed
# mid-run.  `gates/corpuswitness-gate.py` then went RED on 4 of its 7 readings
# (`verdict.current`, `witness.fresh`, `witness.substrate`, `claim`) while `verdict.reported`
# stayed OK: a summary that says green and a witness that says the claim is not established.
# Both processes had to be killed by hand.
#
# IT IS NOT THE BEND LOCK, AND THE MEASUREMENT IS WHY.  `checks/bendlock.sh` serialises
# COMPILER invocations; this serialises WRITERS to one directory -- two different resources,
# and a lock is only a lock if every form of it shares one path.  `bendlock.sh`'s own header
# says a command that runs MANY bends MONOPOLISES the lock for the WHOLE command (MEASURED: 26
# minutes for an 11-bend gate), and the corpus runs ~100 bends and takes 271 s (AGENTS.md,
# 2026-10-22), so holding the bend lock for a corpus run would park every other unit's
# compiler for the whole run.  MEASURED: the corpus takes NO bend lock at all today -- 0
# references to `bendlock` in `checks/differ.py` and in `.agents/slop/graphcmp.py`, and the
# bends are spawned by `graphcmp.py` as `subprocess.run([str(BEND), ...])`.  So a corpus-wide
# lock MUST BE ITS OWN LOCK; and the corpus taking the bend lock PER BEND, which is what
# `bendlock.sh`'s header prescribes for a many-bend command, is a SEPARATE change and is NOT
# this one.
#
# THE OWNER IS A PID, AND THIS PROCESS IS THE WRITER.  The owner is the process that writes
# the artifacts -- `clean_run` calls `cmd_run` IN-PROCESS (see `one_run()`) -- so "is the owner
# alive" is the whole liveness question.  There is no `bun` child to check, because there is no
# shell in between: the bend lock's second check exists because its owner is a shell, and this
# owner is not.
#
# **THE KERNEL IS THE LOCK, AND THAT IS THE SHAPE THAT CANNOT FAIL.**  `fcntl.flock` on an open
# file description has three properties that the mkdir-and-write-a-PID shape does not:
#   * THE LOCK IS RELEASED WHEN THE HOLDER DIES -- there is no stale lock to reclaim, and no
#     window in which a killed run blocks the next one.  `checks/bendlock.sh` needs 300 s of
#     stale-owner reclamation and a SECOND check for the `bun` child, because its owner is a
#     shell that can die while its child lives; this lock has no such owner.
#   * IT CANNOT BE STOLEN -- the kernel refuses, so there is no read-then-remove window in
#     which a live holder's lock is deleted by a second process that read it a moment earlier.
#   * IT CANNOT BE DOUBLE-HELD -- one `flock` per open file description, so two processes
#     cannot both win it, and a refusal is a REFUSAL rather than a race.
# `checks/bendlock.sh` cannot use it: it is POSIX `sh`, where `flock(2)` does not exist.
CORPUS_LOCK = ROOT / "runs/graphcmp/.corpus.lock"
#: THE HOLDER'S OWN RECORD OF ITSELF, written into the lock file AFTER the lock is taken, so
#: a refusal can NAME the holder: `<pid> <epoch>`.  It is a NAME, not the lock -- the lock is
#: the `flock`, and this file says who holds it.
_LOCK_FD: int | None = None
#: **HOW DEEP THE HOLD IS.**  The lock is RE-ENTRANT inside one process, because `repro` runs
#: `cmd_run` in the process that holds it -- and a re-entrant lock that released on the inner
#: `drop_lock()` would let a SECOND HOLDER in while the outer one still believed it held the
#: directory.  MEASURED 2026-10-23: that exact bug ran a corpus into the tree's evidence.
_LOCK_DEPTH = 0


def relpath(path: Path) -> str:
    """THE PATH AS THE TREE WOULD NAME IT, and ABSOLUTE when it is outside the tree.

    A `relative_to` that raises turns a redirected artefact directory into a traceback
    instead of a verdict, and the redirected directory is a supported configuration."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def lock_holder() -> tuple[int, float]:
    """THE HOLDER, as `(pid, age_seconds)`, and `(0, 0.0)` when the file names nobody.

    THE PID IS THE HOLDER'S OWN RECORD OF ITSELF, so `(0, 0.0)` means "the holder has not
    named itself yet" and NEVER "there is no holder" -- the kernel is the authority on
    whether there is one, and this only says who."""
    try:
        pid_s, epoch_s = CORPUS_LOCK.read_text().split()
        return int(pid_s), max(0.0, time.time() - float(epoch_s))
    except (OSError, ValueError):
        return (0, 0.0)


def holder_command(pid: int) -> str:
    """THE HOLDER's COMMAND LINE, so a refusal names WHO and not merely a number."""
    if pid <= 0:
        return "the holder has not named itself yet"
    q = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return q.stdout.strip() or "no such process"


def process_alive(pid: int) -> bool:
    """`kill -0` ASKS THE KERNEL.  This is not how the lock is held -- the kernel is -- it is
    how a refusal knows that the name it is about to print is still a live process."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def take_lock() -> str | None:
    """HOLD THE CORPUS LOCK, OR NAME THE HOLDER THAT HAS IT.

    `None` means this process holds the lock now.  A STRING IS A REFUSAL: it names the
    holder, and the caller must print it and exit WITHOUT touching `runs/graphcmp/D/` --
    because a refusal that has already pruned the artifact directory is not a refusal.

    **IT IS RE-ENTRANT INSIDE ONE PROCESS**, and that is what `repro` needs: `clean_run` runs
    `cmd_run` in the process that holds the lock.  A second HOLDER is a second PROCESS."""
    global _LOCK_FD, _LOCK_DEPTH
    if _LOCK_DEPTH:
        _LOCK_DEPTH += 1
        return None  # WE ALREADY HOLD IT
    CORPUS_LOCK.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(3):
        fd = os.open(CORPUS_LOCK, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return _refusal()
        # THE FILE WE LOCKED MUST STILL BE THE FILE AT THAT PATH.  A sweep that deletes
        # `runs/` would leave this process holding an INODE nobody else can find, and the
        # next holder would lock a NEW file -- two holders, one directory.
        try:
            same = os.fstat(fd).st_ino == os.stat(CORPUS_LOCK).st_ino
        except OSError:
            same = False
        if not same:
            os.close(fd)
            continue
        os.ftruncate(fd, 0)
        os.write(fd, f"{os.getpid()} {time.time()}\n".encode())
        _LOCK_FD = fd
        _LOCK_DEPTH = 1
        return None
    return _refusal()


def _refusal() -> str:
    """THE REFUSAL, AND IT NAMES THE HOLDER.

    **A REFUSAL IS NOT A CORRUPTION**, and the difference is the whole point: the second run
    says who has the lock and exits, and the artifacts the first run is writing are left
    exactly as they were.

    **A NAME IS ONLY PRINTED IF IT IS STILL ALIVE.**  The kernel is the authority on whether
    there IS a holder, and the file is only the holder's own record of itself -- so a name
    whose process is gone is not printed, because a refusal that names a dead process is a
    lie about a live lock."""
    pid, age = lock_holder()
    if pid and not process_alive(pid):
        pid = 0
    return (f"another corpus run holds the lock: {relpath(CORPUS_LOCK)} is held by "
            f"pid {pid or 'UNKNOWN'} (held for {age:.0f}s, {holder_command(pid)}).  This run "
            f"refuses to start: the corpus is a SINGLETON -- two runs write the SAME directory "
            f"({relpath(D)}) and would overwrite each other's artifacts.  Wait for the holder.")


def drop_lock() -> None:
    """RELEASE THE LOCK.  Closing the descriptor releases the `flock` -- that is the kernel's
    promise, and it is why there is no stale lock and nothing to reclaim.  The NAME is
    cleared on the way out, so the file never carries a holder that is gone.

    **IT RELEASES ONE HOLD, NOT THE LOCK.**  The hold is counted, so an inner `drop_lock()`
    (the one `command()` does around a `repro`'s inner `cmd_run`) cannot release the outer
    hold.  MEASURED 2026-10-23: without the count, the inner release let a SECOND process
    into the tree's artefacts while the outer one still believed it held the directory."""
    global _LOCK_FD, _LOCK_DEPTH
    if _LOCK_DEPTH <= 0:
        return
    _LOCK_DEPTH -= 1
    if _LOCK_DEPTH:
        return
    os.ftruncate(_LOCK_FD, 0)
    os.close(_LOCK_FD)
    _LOCK_FD = None



# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN.
#
# Both `.sh` shims carry a sha256 in a comment and claim the frozen copy "cannot drift
# unnoticed". MEASURED 2026-10-05: nothing read it. The pin was CORRECT -- it is the hash of the
# committed body -- and it was still a comment that added up, because a pin no code consults
# cannot fail, and this file's own docstring names that as the reason a gate must state what it
# CLAIMS. So the pins moved here, where `run` and `repro` both refuse to start on drift.
#
# The hash is of the ORACLE COPY. The copy differs from the committed body by exactly one
# documented edit -- a `GCMP_REPO` default in its first `cd`, so the copy can be run from
# anywhere -- and pinning the copy is what detects the copy drifting. Pinning the committed body
# instead would be a check against `git`, which is a dependency this file does not otherwise have.
ORACLE_PIN = {
    "diffpy/oracle-run.sh":
        "94e7108d428bae3fb211db5cce000819b63e2bfbfd51dad4c512e42626d15905",
    "diffpy/oracle-repro.sh":
        "a5d23505b3e93816370e67df130993e812abd2db7e5c6919d6e98d51af92d2ea",
}


def check_oracle() -> list[str]:
    """Every frozen oracle's actual sha against its pin. Empty list means intact.

    Named distinctly from the `oracle-selfcheck` this driver already reports, which is
    tinygrad's own oracle asserting about ITS rows. That one asks whether the PYTHON side is
    well-formed; this asks whether the SHELL side is still the thing the port was diffed
    against. Two different questions, and the previous spelling used one word for both.
    """
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

_MODULES: dict[str, object] = {}


def graphcmp_module(path=None):
    """`graphcmp.py` BY PATH -- the generator's own declaration of the corpus AND its plants.

    CACHED BY PATH, and the key is the PATH, because the corpus is asked for by the pin
    table at IMPORT and by the run at its start, and TWO LOADS OF ONE FILE COULD DISAGREE if
    the file moved between them. A DIFFERENT path is a DIFFERENT key, so a MUTATED COPY --
    the plant below -- is loaded as itself and never served from the cache.

    THE MODULE SCOPE IS INERT, and that is measured rather than assumed: MEASURED 2026-10-22,
    importing it costs **0.018 s** and leaves `tinygrad` ABSENT from `sys.modules`, so asking
    it for its own keys is cheap and side-effect-free.
    """
    key = str(path or (ROOT / GCMP))
    if key not in _MODULES:
        spec = importlib.util.spec_from_file_location("graphcmp_corpus", key)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _MODULES[key] = mod
    return _MODULES[key]


def corpus() -> tuple[str, ...]:
    """`graphcmp.GRAPHS` -- THE GRAPHS THE CORPUS IS, read from the generator.

    THE CORPUS IS THE AUTHORITY ON WHAT EXISTS; THE EXPECTATIONS ARE THE AUTHORITY ON WHAT IT
    MUST PRINT. Two questions, two tables, and the defect was that one table was doing both
    jobs: the run loop iterated the expectations, so a graph absent from them was never run
    and never counted, and `graphs=` counted what the table wrote.

    **THE POPULATION IS DISCOVERED, NEVER TYPED.** `graphcmp.py`'s `GRAPHS` is the GENERATOR'S
    OWN DECLARATION, loaded BY PATH -- so a graph that joins the corpus joins it by being
    ADDED to the generator, and no list in this file has to learn about it. MEASURED
    2026-10-22: **35** graphs.

    IMPORTED, not copied, for the reason `checks/no-txt.py` gives: a second list of graph
    names is a contract with no generator, which is the failure this whole change exists to
    remove. And it is the SAME object `diff --graph` validates against, so a name here is a
    name the run can actually run.
    """
    return tuple(sorted(graphcmp_module().GRAPHS))


def population_digest(path=None) -> str:
    """sha256 over the POPULATION's NAMES and over the BYTES THAT DEFINE EACH GRAPH.

    **THIS IS A CONTENT PIN, AND THAT IS THE HOUSE PATTERN.** A REVISION pin is a pin on a
    file that can move; a CONTENT pin is a pin on the BYTES -- `gates/gatekit.py:oracle_drift`
    reads a sha256 of the bytes the oracle imports, and five gates were converted that way.
    So the thing that must NOT move is the population's IDENTITY, and it is measured over
    bytes: the NAMES (so a graph that joins the corpus moves it) and the SOURCE of each
    graph's defining function (so a fixture that CHANGES moves it too, because a changed
    fixture can flip a verdict and is the same class of event as a new graph).

    **THE SOURCE, NOT THE BYTECODE.** A pin has to survive a Python upgrade, and bytecode is
    version-dependent -- the tree already learned that a pin is a SEED and a sort is a LAW.
    The source text is version-independent, and it is the corpus's own words about its own
    fixtures.

    IT IS NOT A SECOND COPY OF THE POPULATION: the names come from the generator and the
    bytes come from the generator. A different `path` is a different population, which is
    what makes the plant below possible.
    """
    mod = graphcmp_module(path)
    h = hashlib.sha256()
    for name in sorted(mod.GRAPHS):
        h.update(name.encode())
        h.update(b"\0")
        h.update(inspect.getsource(mod.GRAPHS[name]).encode())
        h.update(b"\0")
    return h.hexdigest()


# THE POPULATION'S IDENTITY, AS A CONTENT PIN. **THIS IS THE ONE PIN IN THIS FILE THAT A
# GRAPH ADDITION MUST MOVE**, and moving it is a DELIBERATE EDIT: the diff that adds a graph
# to `graphcmp.GRAPHS` carries this line, and a reader of that diff sees the corpus grow and
# the pin move together.
#
# MEASURED 2026-10-22 over the live tree: `4a44f98e3964353a7e11247af8bebbcdb9acab1efbb8be19e933f93cae501ed2`
# over 35 graphs. **A PIN THAT IS A COUNT OF A DISCOVERABLE POPULATION IS NOT ONE OF THESE** --
# the four count pins in `PINS` below are DERIVED, and this one is not, because a digest is
# not a count: it moves when the population's CONTENT moves and it cannot be re-derived from
# the population, which is the whole difference between a pin and a label.
#
# THE DELTA HERE IS NIL, and the reason is MEASURED, because a reader lands on this line and
# asks what changed. On 2026-10-22 the port's SPEC TABLES were fixed -- `fu_block.go`'s three
# thresholds each read one more than the block base they select, so a block's FIRST rule was
# dispatched into the PREVIOUS block's ladder -- and `gates/specreach-gate.py` went from three
# differing cells to none. The corpus's population did NOT change, and it could not have:
# the corpus never runs the port's spec tables (its bend lane imports `LAWS/spec.bend`, a
# DIFFERENT file, and the port's `verify_*` entry points have zero callers), and its bend
# lane's dispatcher names the same 35 graphs, so a new graph needs a builder inside
# `.agents/slop/graphcmp.bend`, which a `.bend` file outside that directory cannot import at
# all -- the compiler rejects an import path with a segment starting with `.`. The population
# DOES carry the shapes (`getaddr` a GETADDR, `binblob` a BINARY, and the gate prints both);
# what is missing is a VERDICT LANE over it, and that is `gates/specreach-map.rows` (the map)
# and `gates/specreach-gate.py` (the verdict).
POPULATION_PIN = "4a44f98e3964353a7e11247af8bebbcdb9acab1efbb8be19e933f93cae501ed2"


def population_bad(digest=None) -> list[str]:
    """THE POPULATION'S IDENTITY AGAINST ITS PIN. Empty means the corpus is DECIDED.

    **THIS IS THE PROTECTION AGAINST "A GRAPH WAS ADDED AND NOT RE-DECIDED", AND IT IS THE
    ONLY ONE.** The count pins below are DERIVED from the population, so they follow it
    wherever it goes and CANNOT notice that it moved -- which is exactly the trade the
    derivation makes: a count that follows the population cannot go stale, and a population
    that changes must move A PIN. This is that pin, and it is compared by every reader of
    health.

    **THE RUN REFUSES ON IT TOO** (`cmd_run`), and that refusal is the difference between
    "the corpus noticed" and "the corpus certified a population nobody had an opinion
    about". A graph that joins the corpus and is not re-decided makes the corpus UNHEALTHY
    and UNRUNNABLE, and the remedy is one visible line in this file.

    `digest` is the identity of SOME population -- the live one by default, and a PLANTED one
    in the plant below, which is how the plant can ask the question without editing the tree.
    """
    try:
        live = population_digest() if digest is None else digest
    except Exception as e:                     # a population nobody can read is not decided
        return [f"population ABSENT -- the corpus's graph list could not be read "
                f"({type(e).__name__}: {e}), so nothing can be decided about it"]
    if live == POPULATION_PIN:
        return []
    return [f"population={live[:16]} but POPULATION_PIN is {POPULATION_PIN[:16]} -- the corpus's "
            f"graph list has CHANGED since it was decided, so a run over it certifies a "
            f"population nobody has re-decided. Re-decide it, and move POPULATION_PIN here in "
            f"the SAME COMMIT as the change."]


# THE EXPECTATIONS, AS A TABLE OF **EXCEPTIONS** -- AND THE DEFAULT IS "AGREE".
#
# **A GRAPH THAT IS NOT NAMED HERE IS EXPECTED TO AGREE.** So ADDING A GRAPH MUST NOT REQUIRE
# EDITING THIS TABLE: the corpus's population is DISCOVERED (`corpus()` reads `graphcmp.GRAPHS`
# BY PATH, the generator's own declaration) and every graph in it is expected to agree unless
# it is named here. What this table holds is the graphs that are NOT expected to agree, and
# **THE COUNT OF EXCEPTIONS IS THE DENOMINATOR THAT MATTERS** -- not the number of graphs,
# which follows the population and is DERIVED (see `PINS`).
#
# **AND THE EXCEPTIONS ARE EMPTY TODAY, WHICH IS A MEASUREMENT AND NOT AN OMISSION.** Every
# graph this corpus held on 2026-10-21 was a DISAGREE at some point, and each moved to AGREE
# with a located cause. The causes are the port's history and they are recorded here because a
# table that has been empty for a REASON is worth more than a table that was never full:
#
#   `lin`     the port typed the SINK's `applied_opts` as `List<U32>` where the pin has a
#             three-field `Opt`; the port now defines `OPT{op, axis, arg}` in `uop/ops.bend`
#             and `graphcmp.bend` renders it. Row 46 went 45/46 -> 46/46 with no other graph
#             moving.
#   `loop`    the port printed the CALL's slot UNCONDITIONALLY where the pin's own `__repr__`
#             suppresses it for void (`ad117c928^:tinygrad/uop/ops.py:1404`). Fixed in
#             `3b183700a`, re-derived on the live driver at 25/25.
#   `flip`    the `ABoolList` fix landed, so both lanes read `n(b1,b0)`. And the `GROUP` node
#             the old prediction named was never a port defect: `tinygrad/uop/ops.py:559` reads
#             `if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]`, so a ONE-src
#             `UOp.group` builds NO NODE -- and of 12 hand-built `OpsGROUP` statements `g_flip`
#             was the only one carrying a single src. The FIXTURE modelled a call its own
#             oracle collapses, and the py lane was right all along.
#   `allred`, `cdiv`, `late`  the bend side emitted `matmul`'s graph because `rows.pick3` had no
#             arm for them (`.agents/slop/unsetexp/`); `adevfix` and `armfour` (`c3b4da262`)
#             landed, so `D2-cmp-*.txt` are BYTE-IDENTICAL and the verdicts read AGREE.
#   `mselect` the port stored an int arg as a one-byte ABlob (`uop/ops.bend:4560`, the
#             `WALL(p3)` trigger at `:4554`); `mselectarg`'s `AInt` variant closed it.
#   `stage`, `wmma`  the port's fold had no arm for the op, so BOTH columns were unsettled
#             (`dtype py=f32 bend=? shape py=(...) bend=?`); `foldgap`'s WMMA-shape fix and the
#             STAGE arm closed them.
#   `unshard` the same stale `GROUP` census `mulacc` and `getaddr` carried -- a dispute about
#             `graphcmp.bend`'s own comments, not about the port.
#   `getaddr` the arena's `UOp.new` RETURNED was not threaded (`graphcmp.bend:1358`), so the
#             emission was a single `NOOP ... BAD` row and `diff --graph getaddr` exited 2
#             `NOT WELL-POSED`.
#
# **A PREDICTION IS NOT A PIN.** It moves when the measurement moves, and it moves with the
# evidence written down next to it. That is why the causes above are PROSE and not rows: a
# row here is a CLAIM the run checks, and a claim that holds for every graph in the corpus is
# ONE NUMBER -- the population's identity, pinned by CONTENT in `POPULATION_PIN` -- and not
# thirty-five.
WANT: dict[str, str] = {}


def expectation(g: str) -> str:
    """THE VERDICT A GRAPH IS EXPECTED TO PRINT. **THE DEFAULT IS "AGREE".**

    The expectations are a table of EXCEPTIONS (`WANT`), so a graph that joins the corpus is
    expected to agree the moment it is added -- and the corpus's growth is caught by the
    POPULATION PIN, which is a content pin over the graph list's own names and bytes.

    **THE DENOMINATOR THAT MATTERS IS THE NUMBER OF EXCEPTIONS**, and it is `len(WANT)`.
    """
    return WANT.get(g, "AGREE")
# THE PLANTS. Every one must DISAGREE and NAME something; a plant that agrees is a plant that
# is not load-bearing. `sym1` needs the `sym` graph, `params` needs the `prog` graph and the
# others need the matmul, so they are not one loop. NOT the attributable measurement for the
# symbolic dim: a plant edits the PY side only (planting the bend side is six DAG rewrites in
# Bend -- the reason `--plant-side` was removed), so `D5-plant-sym1.txt` carries the plant's
# effect AND `sym`'s pre-existing `?` disagreements together.
#
# **IT IS A TUPLE OF PAIRS AND NOT A DICT, BECAUSE `gates/corpuslane-gate.py:244` ITERATES IT
# AS PAIRS** -- `for plant, g in differ.PLANTS` -- so the shape is a CONTRACT with a consumer
# and changing it would break that gate in a way no test here would notice.
#
# `params` is the PLANT FOR THE `pI(` FORM: it drops the LAST param of `prog`'s PROGRAM, so
# the third component of the `pI(` row goes from three `P(...)` records to two. It is the only
# plant that can reach a `ProgramInfo`, and the form was DEAD in both sides for the corpus's
# whole life until `prog` joined (MEASURED 2026-10-22: the 34 graphs produced ZERO `pI(` rows).
PLANTS = tuple((p, "matmul") for p in ("dtype", "srcswap", "shape", "bytes", "pyuop", "opt")) \
    + (("sym1", "sym"), ("params", "prog"))
# THE PLANTS THE CORPUS'S OWN INSTRUMENT DECLARES AND THE CORPUS DOES NOT RUN.
#
# **THE PLANT POPULATION IS DISCOVERED, AND IT IS `graphcmp.PLANTS`** -- the generator's own
# declaration of the plants it can apply, read BY PATH from `.agents/slop/graphcmp.py`, which
# MEASURED 10 members on 2026-10-22. `PLANTS` above is the corpus's SELECTION of them, and a
# selection is not a population: a hand list of plants is the same class of defect as a hand
# list of graphs, so the difference between the two is CHECKED rather than left to be noticed.
#
# TWO are declared and not run. `gates/corpuslane-gate.py:254` already runs them, on `bw`,
# and reports them as their own class -- `unwired` -- so "the number of plants the corpus
# exercises" and "the number that exist" stop being different numbers nobody notices. Their
# target is an EXPAND whose margin is `CONST 3`, and the corpus's own fixtures have none.
#
# **A PLANT ADDED TO `graphcmp.PLANTS` AND TO NEITHER LIST REDS THE CORPUS**, because a plant
# the corpus's instrument declares and the corpus neither runs nor excuses is a plant whose
# absence nobody would notice.
PLANTS_UNWIRED = ("dsexpand", "disarm")


def plants_bad() -> list[str]:
    """THE PLANT POPULATION AGAINST THE CORPUS'S SELECTION OF IT. Empty means the two agree.

    **A PLANT THAT IS NOT IN `PLANTS` IS A PLANT THE CORPUS DOES NOT RUN** -- so the
    population is not "the plants the corpus runs" but "every plant the corpus's own
    instrument declares", and the SELECTION is checked against it from both sides: a plant
    the corpus runs must be a declared plant (a typo would plant nothing and report a
    DISAGREE for its own reasons), and a declared plant the corpus does not run must be
    NAMED in `PLANTS_UNWIRED` with the reason it is not run.
    """
    try:
        declared = set(graphcmp_module().PLANTS)
    except Exception as e:
        return [f"plants ABSENT -- the corpus's plant list could not be read "
                f"({type(e).__name__}: {e}), so nothing can be decided about it"]
    selected = {p for p, _ in PLANTS}
    bad = []
    if unknown := sorted(selected - declared):
        bad.append(f"plants {unknown} are RUN but the corpus's instrument does not declare them, "
                   f"so the run would plant nothing and count a DISAGREE for its own reasons")
    if missing := sorted(declared - selected - set(PLANTS_UNWIRED)):
        bad.append(f"plants {missing} are DECLARED by the corpus's instrument and are neither run "
                   f"nor excused in PLANTS_UNWIRED, so the corpus does not run every plant it "
                   f"declares")
    try:
        graphs = set(corpus())
    except Exception:
        graphs = set()
    if unknown_graphs := sorted({g for _, g in PLANTS} - graphs):
        bad.append(f"plants run on graphs the corpus does not have: {unknown_graphs}")
    return bad
# THE CONTROLS: each side against ITSELF. A differ never seen to agree with itself is not
# known to work. `group` is the first DAG, so a control over a tree-only corpus is a control
# that has never met a two-parent node; `gate` and `loop` are the widest-fan-in and a
# disagreeing graph, so a control that only runs on AGREEing fixtures has never had to agree
# with itself WHILE disagreeing.
CONTROLS = ("matmul", "binblob", "group", "gate", "loop")
# THE STABILITY PAIRS, FIVE, because the interesting shapes differ. A 0-row side is a
# one-line `rc=N` file, which is why a pair is RE-RUN once and a side that is still one line
# is named FAILED rather than compared: two identical FAILURES compare equal.
STAB = tuple((g, ()) for g in ("group", "sym", "loop", "gate")) + (("commute", ("--plant", "srcswap")),)
# A HEALTHY RUN, not merely a FINISHED one. Every pin is matched BY CONTENT, never by line
# number. MEASURED: the shell pinned `graphs-agree=13`, then `14`, against a corpus reading
# `22`, so this gate reported a fully correct run unhealthy and sat retrying it -- a health
# gate pinned to a count can be wrong in the direction of refusing to measure.
#
# **NINE OF THE SEVENTEEN ARE DERIVED, AND THAT IS THE POINT.** A COUNT OF A DISCOVERABLE
# POPULATION MUST NOT BE TYPED: a typed count is stale the moment the population moves, and a
# stale count is either a red nobody can fix by doing the right thing or a green that hides a
# growth. MEASURED 2026-10-06, `checks/corpus-figure.py` found the corpus at **34** while
# `differ.py` pinned `graphs=25`, and printed `RUN HEALTH : OK` over the stale run -- "the
# figure and the health gate were two witnesses to one stale run". So the counts below are
# FUNCTIONS of the population, and the thing that must NOT move is the population's IDENTITY,
# which is a CONTENT PIN (`POPULATION_PIN`).
#
# **AND THE DERIVED VALUES ARE STILL COMPARED AGAINST THE ARTEFACT** -- `unhealthy()` reads the
# run's own rows and compares them with these -- so a derived expectation is an EXPECTATION
# and not a decoration: a run whose `graphs` row disagrees with the discovered corpus is RED.
# THE NINE DERIVED ROWS, BY NAME -- so the fail-safe below can enumerate them, and so a reader
# can see at a glance which of the seventeen follow a population and which are pins.
COUNT_PINS = ("graphs", "graphs-answered", "graphs-agree", "byte-identical",
              "stable-pairs", "stable-failed", "stable-differ", "plants-disagree", "controls")


def derived_counts() -> dict[str, str]:
    """THE NINE ROWS WHOSE VALUE IS A FUNCTION OF A POPULATION. DERIVED, NEVER TYPED.

    `graphs`, `graphs-answered`, `graphs-agree` and `byte-identical` count the CORPUS, whose
    membership is `graphcmp.GRAPHS` -- discovered, by path. `stable-*`, `plants-disagree` and
    `controls` count SELECTIONS this file holds (`STAB`, `PLANTS`, `CONTROLS`), and their
    DENOMINATORS were typed into the summary writer as `of 5`, `of 7`, `of 5` -- the same
    defect one level down: a typed denominator is a literal that goes stale when the selection
    grows, and `plants-disagree` would have read `8 of 7` the moment `params` joined.

    **THE EXCEPTIONS ARE THE DENOMINATOR THAT MATTERS.** `graphs-agree` and `byte-identical`
    expect every graph the corpus runs to agree and to be byte-identical, so the expectation
    is `N - len(WANT)`: the number of graphs MINUS the number of exceptions. A graph expected
    to disagree is not counted as agreeing, and it is not counted as byte-identical either --
    a DISAGREE is a difference, and a difference is not byte-identity.

    **IF THE CORPUS CANNOT BE READ, EVERY DERIVED VALUE IS "UNREADABLE"** -- which is not any
    pin, so every comparison REDS. A population nobody can read is not a healthy one, and the
    failure is in the direction that reports.
    """
    try:
        n = len(corpus())
        stab, controls, plants, exceptions = len(STAB), len(CONTROLS), len(PLANTS), len(WANT)
    except Exception:
        return {k: "UNREADABLE" for k in COUNT_PINS}
    return {
        "graphs": str(n),
        "graphs-answered": str(n),
        "graphs-agree": str(n - exceptions),
        "byte-identical": str(n - exceptions),
        "stable-pairs": f"{stab} of {stab}",
        "stable-failed": f"0 of {stab}",
        "stable-differ": f"0 of {stab}",
        "plants-disagree": f"{plants} of {plants}",
        "controls": f"{controls} of {controls}",
    }


PINS = {
    # `expect-moved` is the ONLY pin that asks whether the EXPECTATIONS HELD, and it is not a
    # function of the corpus: it is a function of the PORT against the exceptions table. **It is
    # 0 and it is a ZERO-TOLERANCE INVARIANT**, so it does not need re-pinning when the corpus
    # grows -- a graph that joins and agrees contributes nothing, and a graph that joins and
    # disagrees is exactly what this counts. Nothing pinned it and nothing exited on it:
    # `cmd_run` used to return 0 whenever `unset` was empty, so a run in which a row was simply
    # WRONG was healthy and green, and the only thing that would have noticed is `graphs-agree`
    # -- which nets out, and so misses the case where one row moves to AGREE while another moves
    # to DISAGREE. MEASURED 3/3 stable per graph, warm substrate, and 0 moved over all 20 rows
    # (`.agents/slop/unsetexp/trials.tsv`).
    "expect-moved": "0",
    "not-comparable": "0",
    "selfcheck": "# SELFCHECK: OK", "census-rc": "rc=0",
    # THE POPULATION'S IDENTITY, AS A CONTENT PIN. **THE ONE PIN A GRAPH ADDITION MUST MOVE**,
    # and the one that replaces `graphs-unset`: a graph that joins the corpus and is not
    # re-decided leaves the pin stale, and a stale pin is a red in `unhealthy()` and a REFUSED
    # run in `cmd_run`. MEASURED 2026-10-22 over the live tree's 35 graphs.
    "population": POPULATION_PIN,
    # `cross` is ONE comparison and `conflations` are the ORACLE's own four cases -- neither is a
    # count of a population this file discovers, so both stay literal.
    "cross": "1 of 1", "conflations": "4 of 4",
    "oracle-selfcheck": "# ORACLE SELFCHECK: OK",
    **derived_counts(),
}
# THE SECOND WITNESS, AND WHY IT IS NOT AN EIGHTEENTH MEMBER OF `PINS`.
#
# Every key above is a `key=value` row of `D0-run-summary.txt`. So `PINS` green is ONE run's rows
# read out of ONE file, and the denominator of the health claim is **1 artifact, not 17** -- 12
# witnesses, 10 independent measurements, all from a single run (`.agents/slop/pinindep/REPORT.md`,
# measured by perturbation, not by reading these lines). **ADDING A KEY HERE DOES NOT CHANGE THAT.**
# It would be the 18th row of the same file, which is the shape `pinindep` measured rather than the
# defect it names.
#
# `cmd_repro` ALREADY makes the tree's only INDEPENDENT measurement -- two clean runs, sha256 over
# every artifact, byte-compared (`:984-999`). It computed that verdict and printed it to stdout, and
# nothing on disk could read it, so the second measurement had no memory. It is now written to
# `REPRO_ARTIFACT`, and `REPRO_PINS` is the one pin table read from it: **the denominator for
# "this run is healthy" becomes TWO artifact reads.**
#
# ONE KEY, NOT THREE. `repro-files` is `len(snap())` -- a function of `declared()` and the `.err`
# files beside it -- and it GROWS BY ONE after the first `repro`, so a literal there is an inventory
# that must be re-pinned whenever an artifact is added, not a claim. `repro-identical` equals
# `repro-files` exactly when `repro-rc` is `0`, so a pin on it could only restate this one.
REPRO_ARTIFACT = "D0-repro.txt"
# THE DIFFERING ROWS, when a repro FAILS. `repro` prints the differing bytes and then throws the
# snapshots away; without this file the failure is a NOTIFICATION, not a finding.
REPRO_DIFF_ARTIFACT = "D0-repro-diff.txt"
# THE SUMMARY ROWS THAT RECORD THE OBSERVER, NOT THE SUBJECT. `substrate-head` says WHICH COMMIT
# measured the run; the rest of the summary says WHAT was measured. A comparison over the whole
# file is therefore a comparison of the run AND the moment it was read, which is not the same claim
# twice. See `snap()`.
OBSERVER_ROWS = ("substrate-head",)
# THE DIFFERING ROWS, when a repro FAILS. `repro` prints the differing bytes and then throws the
# snapshots away; without this file the failure is a NOTIFICATION, not a finding.
REPRO_DIFF_ARTIFIFACT = "D0-repro-diff.txt"
# `d10-transcript` PINS D10's VERBATIM, WHICH IS THE ONE ARTIFACT THE CORPUS NEVER JUDGED.
# MEASURED 2026-10-15: `snap()` byte-compares `D10-zerorow-guard.txt.err` across the two runs, so
# `repro-rc=rc=0` proves it REPRODUCIBLE and says NOTHING about whether it is RIGHT -- and a `classify`
# (`.agents/slop/graphcmp.py:1999`) that regressed to retrying would write `bend attempt 2` in BOTH
# runs, so both would AGREE and both checks would pass over a wrong transcript. The sha256 is
# `snap()`'s OWN output for that file, read back by `d10_sha()` rather than recomputed, so the pin and
# the sweep cannot disagree about which bytes are the claim.
#
# **IT IS A PIN OVER BYTES, SO A COSMETIC CHANGE TO `attempt_note`'s PROSE ALSO REDS IT.** Deliberate:
# the remedy for a red pin is to RE-TAKE (`checks/differ.py repro`), never to hand-edit -- which is
# the rule `checks/corpus-figure.py:178` already states. An absent file answers `ABSENT`, which is
# not the pin, so the arm is fail-safe in the direction that reports.
D10 = "D10-zerorow-guard"
# THE DELTA THIS PIN MOVED OVER, WITH ITS COUNT AND ITS REASON. **MEASURED 2026-10-22, AND IT
# IS NOT THE PORT.** The transcript is `graphcmp.py`'s STDERR for `emit --side bend --bend-probe
# .agents/slop/graphcmp-empty.bend`, and it is ONE line:
#     # bend attempt 1: 0 rows, ANSWER, rc=0, # prints no rows at all, stderr: <LAST 240 CHARS>
# (`attempt_note`, `graphcmp.py:2364-2371`). **THOSE 240 CHARACTERS ARE THE COMPILER'S "A NEWER
# BEND IS AVAILABLE" NOTICE**, and the notice is a NETWORK ANSWER: `bend2/main.ts:185-211` fetches
# `https://bend-lang.com/check` ONCE A DAY into `~/.bend/check.json` and prints
# `bend <published> is available: run bend update` when the published version beats the local
# `VERSION`. **SO BOTH VALUES OF THIS PIN WERE REBUILT BY HAND AND HASHED, AND THE OLD ONE IS
# EXACTLY THE EMPTY-STDERR TRANSCRIPT:**
#     stderr empty                      -> 9bfb85176a4fca0698633780d5845f781076d0e57035e76dd0dfa08cbe6d1e84  (WAS)
#     stderr "bend 2.0.38 is available" -> f35b2d90bdbe49b0361af9fe392e162fc51b44b63caf22d6c2e75062eee343f9  (NOW)
# The cache was refreshed at 2026-10-21T20:52:55Z and recorded `{"ver":"2.0.38"}`. **THE LOCAL
# COMPILER WAS 2.0.37 (`references/bend` at `4ff8545`, 2026-10-13) UNTIL 2026-10-23, WHEN IT
# WAS UPGRADED TO `v2.0.38` (`references/bend` at `0a57ca0d21de`, 2026-10-20) -- SO THE
# LOCAL COMPILER NOW *IS* THE VERSION THE NOTICE NAMES, AND THE NOTICE WILL GO QUIET ON ITS
# OWN.** UPSTREAM'S 2.0.38 RELEASE IS WHAT TURNED THE NOTICE ON, AND NOTHING IN THIS
# REPOSITORY TURNED IT ON.
# **⇒ AND THIS PIN WAS A PIN ON A NETWORK ANSWER, AND IT IS NO LONGER ONE.** The next upstream
# release moved it again with NO REPO CHANGE AT ALL. `BEND_NO_TELEMETRY=1` (`main.ts:186-188`)
# suppresses the check and puts the transcript BACK on the empty-stderr value, and it is NOW
# APPLIED -- in `ENV` above, which every child of this driver inherits, and in
# `graphcmp.py`'s `clean_env()`, so the oracle is hermetic when it runs on its own too. The pin
# is therefore back on the value it held BEFORE upstream's 2.0.38 release turned the notice on,
# and it is the value a fresh clone with no network, no cache and no `~/.bend` produces.
#
# **⇒ AND THE PIN MOVED BACK, WHICH IS NOT A RE-FREEZE.** The rule above ("the remedy for a red
# pin is to RE-TAKE, never to hand-edit") is about a pin whose SUBJECT moved; here the SUBJECT
# was never the repository's, so removing the off-repo input is the only move that can be right,
# and re-taking afterwards is what re-anchors the bytes. MEASURED 2026-10-22, five cases, the
# oracle's own `emit_bend`, each with its own `HOME` so the user's cache was never touched:
#     cache ver=2.0.38  -> the notice's transcript   == f35b2d90...
#     cache ver=2.0.39  -> a DIFFERENT transcript    != f35b2d90...   <- upstream's next release
#     BEND_NO_TELEMETRY -> the empty-stderr one      == 9bfb8517...   <- THIS PIN, and IDENTICAL
#                                                                              with and without a cache
# The corpus's own `repro` then compares the two clean runs byte for byte, so the claim "319 of
# 319 identical" is a claim about the REPOSITORY and not about the developer's home directory.
#
# **THE CORPUS's OTHER DELTA, WHICH IS NOT THIS ONE.** Four changes moved the CORPUS between the
# pin's commit (`6ed9f4256`, 2026-10-15) and today, and NONE of them moved THIS transcript --
# the probe compiles `tinybendygrad/uop/ops.bend` and prints a FIXED header, and the notice was
# the only thing in the stderr. They are declared here because they are why the corpus's
# POPULATION and the port's RULES moved. **COUNT AND REASON, EACH:**
#   1. THE POPULATION GREW 34 -> 35 GRAPHS, BY ONE: `prog`. MEASURED: `graphcmp.GRAPHS` has 35
#      members and `POPULATION_PIN` (`4a44f98e...`) equals `population_digest()`. REASON: `prog`
#      is the FIRST graph whose `ProgramInfo` is COMPARED -- upstream's own
#      `ProgramInfo.from_sink` over the `lin` kernel, whose three params are the three BUFFER
#      params (out 4x5, left 4x3, right 3x5) -- so the `pI(` lane is alive where the 34 graphs
#      produced ZERO `pI(` rows. COUNT OF THE ARTEFACTS: **9** (`repro-files` 310 -> 319): six
#      `D1`/`D2` artefacts for `prog` plus `D1-graph-prog.txt.err`, plus the plant's
#      `D5-plant-params.txt` and its `.err`.
#   2. `tinybendygrad/renderer/nir_llvmir.bend` WAS STALE IN **4** PLACES AT ONCE: `arcp` in
#      the flags; the three intrinsics `EXP2`/`LOG2`/`SQRT` in the AMD override and not in the
#      base's; `half` kept on a non-Darwin host; and `amd_fp8s` with one answer where upstream
#      has two. REASON: all four were RIGHT on 2026-10-01 and WRONG on 2026-10-20, because the
#      2026-10-16 re-vendor moved the pin out from under the port (`06cf7f7da`).
#   3. `tinybendygrad/renderer/tc_ptx.bend`'s `fmt` HAD UPSTREAM's DELETED `$` EARLY RETURN --
#      **1** branch. REASON: upstream removed it in `96397341d` ("dead code cleanups [PR]
#      (#18593)", 2026-10-03) because it was DEAD CODE: at its parent `ptx.py` held exactly ONE
#      occurrence of `$`, the `fmt` line itself, and nothing in `tinygrad/renderer/` could
#      produce a `$`-prefixed line -- so the pin's defaults are FIVE EMPTY STRINGS and the
#      port's target must not be a machine's (`87738d316`).
#   4. `gates/ptx_render_census_axis.bend` WAS REGENERATED, and the axis was stale by **+14**
#      ROWS. REASON: the 2026-10-16 re-vendor moved a BUFFER's SIZE out of the `ParamArg` and
#      into a SIZE CONST SRC, so CPYTHON's OWN graphs gained a node -- **15** fixtures gained
#      one and `f14_skips` LOST one, 15 - 1 = +14 -- and the axis now carries a
#      `# UPSTREAM-PIN <path> <sha256>` line for each of the **7** files the oracle reads
#      (`a7b3cede3`).
REPRO_PINS = {"repro-rc": "rc=0",
              "d10-transcript": "9bfb85176a4fca0698633780d5845f781076d0e57035e76dd0dfa08cbe6d1e84"}
# AND THE ROW THAT MAKES THE WITNESS FALSIFIABLE. Both pins above are claims about a COMPARISON,
# not about a TIME, so nothing in `D0-repro.txt` said WHEN it was taken -- and a witness nobody
# re-took is then indistinguishable from one taken a minute ago.
# MEASURED 2026-10-18: `D0-repro.txt` was dated Oct 17 01:50, four lines, and `repro_bad()`
# returned `[]`. So a STALE FILE WAS SERVING AS THE WITNESS, which is worse than the staleness:
# a pin a stale file can satisfy reports success with no measurement behind it.
#
# IT IS A ROW AND NOT A PIN, and that is the whole distinction. A pin would have to move with
# every port edit -- `pinindep`'s finding, and this file's own stated reason for leaving
# `substrate` out of `PINS` (`:895-901`). This is a COMPARISON against `substrate_digest()`,
# the generator's own declared population, which `gates/corpusverdict-gate.py:170` already
# reads by path for the run summary. **ONE question, ONE mechanism, asked of both witnesses.**
REPRO_SUBSTRATE = "repro-substrate"
# THE ARTIFACT NAMES ARE AN OUTPUT CONTRACT, NOT CONSTANTS, and this is the declaration of it.
# `oracle-run.sh` writes all `declared()` names and reads twelve of them by name in its own
# summary block;
# `oracle-repro.sh` reads one by name (`:61`) and globs five families (`:105`, `:114`); this file
# reads twelve by name and globs the rest; `checks/corpus-figure.py:72` reads `D0-run-summary.txt`
# and refuses on it. So the list lives with the GENERATOR and the two things that must agree with
# it -- `artefacts_ok()`'s population and `checks/no-txt.py`'s `.txt` carve-out -- ask it here
# rather than carrying a second copy that would go stale without anyone noticing.
LITERALS = ("D0-selfcheck", "D1-verdicts", "D2-bytediff", "D0-run-summary", "D4-cross-range",
            "D7-conf", "D8-dbg-012", "D8-dbg-03", "D9-stability", D10,
            "D0-coverage-census", "D8b-cpython-dbg1-reachability", "D0-ops-probe")
# WHAT `cmd_repro` WRITES, HELD SEPARATELY FROM `LITERALS` ON PURPOSE.
#
# `LITERALS` is ONE `cmd_run`'s output, and `artefacts_ok()` REQUIRES every member of the
# population it is given after a run. `D0-repro.txt` is written by a DIFFERENT command, one `run`
# later, so a `MISSING D0-repro.txt` arm firing after every `run` would be a guard that is always
# red -- and a guard that is always red is not a guard, it is `artefacts_ok()`'s own failure mode
# written down in its docstring. `declared()` below names it anyway, because the union is what the
# `.txt` carve-out and the `UNEXPECTED` arm ask about: a `.txt` this file writes that nothing
# declares is an orphan artifact, which is a different complaint from a declared one being absent.
REPRO_LITERALS = ("D0-repro",)
# THE `diff` REPORTS, by the prefix a glob in the frozen oracle spells. Named here rather than
# inline at the one call site because `oracle-repro.sh:114` uses the identical five, so this is
# the same list twice in two languages.
REPORTS = ("D1-graph-", "D3-control-", "D5-plant-", "D6-", "D9-stability-")


def declared() -> set[str]:
    """Every `.txt` artifact ANY command here writes, with its extension, as a set of names.

    DERIVED, never typed: a list written out here is a third copy of the tables above, and the
    measured failure of a stale copy is in `differverdict/VERDICT.md`, where 4 LOST and 4 NEW
    artifact names sat between two runs of the SAME driver and only a name-by-name diff found
    them. `cmd_run` builds these names out of `corpus()`/`CONTROLS`/`PLANTS`/`STAB`, so this
    reads the same sources it does.

    **IT READS `corpus()`, NOT THE EXPECTATIONS.** The run writes one `D1-graph-`, two
    `D2-canon-` and one `D2-cmp-` artifact for EVERY graph in the corpus, and the corpus is
    the DISCOVERED population -- so a graph that joins it joins the artefact list with it, and
    a `declared()` built from the expectations would call every one of those `UNEXPECTED` and
    leave graphcmp `.txt` files with no `.txt` policy -- the exact orphan
    `checks/no-txt.py`'s carve-out is for.
    A DECLARATION THAT MISSES ONE NAME IS A POPULATION THAT EXCLUDES IT.
    """
    graphs = corpus()
    return {f"{n}.txt" for n in (*LITERALS, *REPRO_LITERALS)} \
        | {f"D1-graph-{g}.txt" for g in graphs} \
        | {f"D2-canon-{s}-{g}.txt" for g in graphs for s in ("py", "bend")} \
        | {f"D2-canonform-{s}-{g}.txt" for g in graphs for s in ("py", "bend")} \
        | {f"D2-cmp-{g}.txt" for g in graphs} \
        | {f"D3-control-{g}.txt" for g in CONTROLS} \
        | {f"D5-plant-{p}.txt" for p, _ in PLANTS} \
        | {f"D6-{g}-{k}.txt" for g in ("matmul", "commute") for k in ("ordered", "equiv")} \
        | {f"D9-stability-{g}-{s}.txt" for g, _ in STAB for s in "ab"}


def gc(*args, **kw):
    """`graphcmp.py` under the two required env settings, with no timeout of our own."""
    return subprocess.run([PY, GCMP, *args], cwd=ROOT, env=ENV, **kw)


def run(out, *args):
    """ONE FILE, ONE WRITE, ONE ATOMIC MOVE, and the artifact carries its own `rc=` stamp.

    MEASURED 2026-10-04, and the SECOND time this project has been bitten by it: the version
    that appended `rc=` to the SAME file the child had just written left a window between the
    two, and a run killed in that window produced a report MISSING its last line and with no
    `rc=` at all -- which the stability step then reported as `2 runs DIFFER`, i.e. a
    reproducibility difference whose difference was "the second file is shorter". The temp is
    dot-named and inside the artifact dir, so the rename is same-directory (atomic) and no
    snapshot can see a temp a kill left behind.

    THE `.err` THIS WRITES CARRIES A CEILING WHERE A COUNT BELONGS, AND THE FIX IS **NOT IN THIS
    FILE**. MEASURED 2026-10-17 by AST over `.agents/slop/graphcmp.py` (the frozen oracle this
    driver runs; `ORACLE_PIN` above pins only the two `.sh` files, not this one):

        :2086-2087   `... after %d attempt(s) ...`  %  `(graph, verdict, tries, notes)`  -- `%d` IS `tries`
        :2911-2912   `... after %d attempt(s) ...`  %  `(level, verdict, tries, notes)`  -- `%d` IS `tries`
        :1964        `TRIES, BEND_TIMEOUT = 3, 60`
        :2085,:2910  `break` on any verdict that is not `RETRY`

    `emit_bend()` returns on `ANSWER`, breaks on anything else, and then formats **`tries`** into
    a sentence that reads like an observation. So `emit bend allred: BROKE after 3 attempt(s)` with
    **ONE** `bend attempt 1:` note under it is the expected shape whenever the FIRST attempt is not
    a `RETRY`: the number is the loop's CEILING, never its count. It is true only when all `tries`
    attempts ran. **AND THE SAME FUNCTION GETS IT RIGHT TEN LINES EARLIER** -- `:2077-2078` prints
    `TIMED-OUT after {BEND_TIMEOUT}s on attempt {attempt}` and
    `{tries - attempt} attempt(s) held back`, both derived from the attempt it is standing ON --
    so one function carries two opposite conventions ten lines apart, and a reader of a `.err` has
    no way to tell which one produced the sentence in front of them.

    THE PATCH IS TWO FORMAT STRINGS AND IT IS NOW APPLIED (2026-10-22). It was left NAMED for a
    grant reason, not a technical one: `.agents/slop/graphcmp.py` was outside that unit's grant,
    and a `.slop/` file is inside a tree other units are pruning, so the honest action was to NAME
    IT rather than to patch a file whose next revision might not be its own. `%d attempt(s)`
    became `%d of %d attempt(s)` with `(len(notes), tries)` in both tuples -- `len(notes)` is
    `attempt` on the exhaustion path and `1` on the break path, so it is the count in every case
    where the message is printed at all. NOTHING READ THE NUMBER: `checks/substrate-id.py`'s
    `--repro-files` counts `.err` FILES, and `snap()` compares them byte-wise, so the mislabel
    moved no verdict here -- **which is exactly why it survived, and the same reason a documented
    defect outlives the document that found it.**  The two `.err` files that carry the sentence
    are byte-compared by `snap()`, so the re-take below re-anchors them.
    """
    tmp = D / f".tmp.{out}"
    with tmp.open("wb") as f, (D / f"{out}.err").open("wb") as err:
        rc = gc(*args, stdout=f, stderr=err).returncode
    with tmp.open("ab") as f:
        f.write(b"rc=%d\n" % rc)
    os.replace(tmp, D / out)


def capture(out, script, stamp_rc=False):
    """The oracle/probe steps: BOTH streams are the artifact, so they are merged into it.
    `stamp_rc` is the census's, because a step whose output is a TABLE must say whether the
    table is finished -- `graphcmp-oracle.py` calls `emit_bend`, so when a concurrent edit to
    `tinybendygrad/uop/ops.bend` made every bend emission 0 rows the oracle DIED at
    `rangeflat`, printing a nine-row census and nothing about the seven graphs after it."""
    with (D / out).open("wb") as f:
        rc = subprocess.run([PY, script], cwd=ROOT, env=ENV, stdout=f, stderr=f).returncode
    if stamp_rc:
        with (D / out).open("ab") as f:
            f.write(b"rc=%d\n" % rc)


def text(out):
    return (D / out).read_text(errors="replace")


def write(out, body):
    """Verbatim: a `> file` from a block of `echo`s ends in a newline and a `cat` of nothing
    is 0 bytes, and an artefact's size is one of the things `repro` checks."""
    (D / out).write_text(body)


def lines_with(out, needle):
    """`grep -c`: the number of LINES containing `needle`, not the number of occurrences."""
    return sum(needle in ln for ln in text(out).splitlines())


def anchored(out, regex):
    """`lines_with`'s regex twin: the number of LINES containing a match, not the number
    of matches.

    IT WAS `sum(re.search(regex, ln) for ln in ...)`, AND `re.search` RETURNS A MATCH OR
    None -- so `differ.py run` DIED with
        TypeError: unsupported operand type(s) for +: 'int' and 'NoneType'
    on the first line that did not match, which is nearly all of them. The sibling one
    line above has the same shape and is CORRECT, because `needle in ln` is a bool and
    bools sum; that one difference is the whole bug.

    `bool(...)` and NOT `len(re.findall(...))`, because the two callers ask "how many of
    the 5 stability pairs", which is a LINE count, and findall would silently change the
    meaning if a line ever matched twice.
    """
    return sum(bool(re.search(regex, ln)) for ln in text(out).splitlines())


def files_with(pattern, needle):
    """`grep -l ... | wc -l`. The counting form; `grep -c` over a GLOB prints ONE COUNT PER
    FILE and does not total them, which once made the summary's own total line five lines
    long."""
    return sum(needle in f.read_text(errors="replace") for f in D.glob(pattern))


def grep_line(out, needle):
    return "\n".join(ln for ln in text(out).splitlines() if needle in ln)


def conjoin(xs):
    # The EMPTY case is the good one and it used to crash. It is reached the moment the corpus is
    # whole -- 34 of 34 graphs byte-identical, `bad` empty -- and every earlier run had at least
    # one disagreement to name, so no branch covered it. A gate that cannot render its own
    # success state cannot report it: `IndexError` on the run that found nothing wrong.
    if not xs:
        return "none"
    return xs[0] if len(xs) == 1 else " and ".join(xs) if len(xs) == 2 \
        else ", ".join(xs[:-1]) + " and " + xs[-1]


def byte_diff(a, b, n):
    """The SYSTEM `diff`, on purpose. The DIFFERS branch is an artifact, and difflib spells
    the same difference differently, so a re-spelling would make every failing artifact
    differ for a reason that is the PORT's."""
    p = subprocess.run(["diff", a, b], cwd=ROOT, capture_output=True, text=True)
    return "".join(p.stdout.splitlines(keepends=True)[:n])


# ---------------------------------------------------------------------------
# THE CANONICAL FORM, because `byte-identical` COMPARED A COLUMN THE PROJECT CALLS
# REPORTING-ONLY.
#
# `.agents/slop/graphcmp.py:1999-2001` numbers the CPython side by TOPOSORT POSITION
# (`ix = {id(n): i + 1 for i, n in enumerate(lst)}`) while `tinybendygrad/uop/ops.bend:1322`
# says the port's arena "starts with the bottom at index 0", i.e. its `i` is a HASH-CONS
# INDEX. Two different quantities, one spelling -- and `graphcmp.py:1986` says so in this
# file's own tree: "THE IDS ARE REPORTING ONLY AND THE DIFFER NEVER KEYS ON THEM". MEASURED 2026-10-18T18:04Z with `gates/emitverdict-gate.py --why`:
# py's emitted id column is monotonic in 34 of 34 graphs and the PORT's in 23, and the 11
# that are not are EXACTLY the 11 that byte-differ while carrying `VERDICT: AGREE`. So
# `byte-identical=20` was counting ALLOCATION ORDER, and 14 of 34 graphs were being called
# byte-different for being interned in a different order. **A FALSE DISAGREEMENT IS WORSE
# THAN A MISSED ONE**: it inflates the defect count and so hides the real defects behind
# noise.
#
# **THIS IS A CANONICALISATION AND NOT A RENUMBERING, AND THAT IS THE WHOLE DIFFERENCE.**
# A renumbering would give the py side the port's arena order: true for one tree, false the
# moment the port's allocation order moves, i.e. it fits the symptom to today's tree. The
# form below is derived from the GRAPH and from nothing else -- each node is labelled by its
# whole subtree (`canon_key`), the rows are ORDERED by that label, and the ids are assigned
# `1..n` in THAT order. No step of it reads either side's allocation order, so a change to
# the port's arena cannot move it, and a change to the port's CONTENT will.
#
# **AND IT IS A BIJECTION, WHICH IS A PROPERTY AND NOT A HOPE.** Three wrong canonical forms
# got here first and every one of them reported the same 14 graphs as different (they are in
# `gates/emitverdict-gate.py`'s docstring, which took them): refining on the previous round's
# LITERAL label never settles; re-ranking to FIRST-APPEARANCE order is not injective in the
# labels, so a reference can be handed a number another node then claims -- a DANGLING
# reference that reads as a graph defect; iterating a hash over the previous round's hash
# never settles either. Here the output ids are `1..n`, each used exactly once, BY
# CONSTRUCTION, and `canon_bijection()` CHECKS that on every graph of every run rather than
# asserting it in a comment -- so a form that is not a bijection cannot reach `D2-cmp-*.txt`
# and cannot be counted by `byte-identical`. Plant 6 and plant 7 below are the two halves:
# the first proves the form is INVARIANT to numbering, the second that it does not MASK one.
CANON_REF = re.compile(r"i(\d+)")


def unchunk(line):
    """The eight `<len>:<value>` fields. THE LENGTH PREFIX IS THE PARSE: a field cannot
    contain a space, so nothing here can be confused for a delimiter and no regex is needed."""
    out, i = [], 0
    while i < len(line):
        j = line.index(":", i)
        n = int(line[i:j])
        out.append(line[j + 1:j + 1 + n])
        i = j + 1 + n
    return out


def canon_key(i, parsed, at, keys, live):
    """`(op, dtype, shape, depth, tag, arg, child keys)` -- the label of the WHOLE subtree.

    MEMOISED AND CYCLE-CHECKED rather than iterated to a fixpoint. A fixpoint over literal
    labels is one of the three wrong forms above; a fixpoint over DIGESTS is another, because
    the digest is rebuilt from a value that moved. Hashing the recursion bottom-up is
    injective in the structure and needs no shared state, so `keys` can be filled in one
    pass in EITHER emission order -- which is the whole requirement, since one side emits in
    toposort order and the other in arena order.

    A reference that does not resolve and a cycle both RAISE. A graph whose shape this
    cannot decide must never reach a byte comparison, because a canonical form of an
    undecidable graph is a canonical form of nothing.
    """
    if keys[i] is not None:
        return keys[i]
    if i in live:
        raise ValueError("a reference cycle, so there is no subtree to label")
    live.add(i)
    _, op, dt, sh, dp, tg, ag, srcs = parsed[i]
    kids = tuple(canon_key(at[k], parsed, at, keys, live) for k in srcs if k in at)
    if len(kids) != len(srcs):
        raise ValueError(f"a reference that names no row: {srcs}")
    live.discard(i)
    keys[i] = (op, dt, sh, dp, tg, ag, kids)
    return keys[i]


def canon_rows(rows):
    """`rows` -> THE CANONICAL FORM: canonical ids, canonical order, same eight fields.

    The ids are assigned by SORTING the subtree labels, so they are a function of the graph
    alone. Ties -- two nodes whose entire subtrees are equal -- are resolved by the original
    emit order and that is HARMLESS rather than lucky: if two subtrees are equal, then every
    row that references them has an equal label too, so swapping their ids cannot change the
    emitted text.
    """
    parsed = []
    for ln in rows:
        f = unchunk(ln)
        if len(f) != 8:
            raise ValueError(f"a row that is not eight length-prefixed fields: {ln[:60]!r}")
        parsed.append((f[0].removeprefix("i"), *f[1:7], tuple(CANON_REF.findall(f[7]))))
    at = {nid: i for i, (nid, *_r) in enumerate(parsed)}
    if len(at) != len(parsed):
        raise ValueError("two rows claim one id, so the id column is not injective")
    keys: list = [None] * len(parsed)
    for i in range(len(parsed)):
        canon_key(i, parsed, at, keys, set())
    order = sorted(range(len(parsed)), key=lambda i: keys[i])
    new = {parsed[i][0]: rank for rank, i in enumerate(order, 1)}
    out = []
    for rank, i in enumerate(order, 1):
        nid, *_f = parsed[i]
        srcs = ",".join(f"i{new[k]}" for k in parsed[i][7])
        fields = (f"i{rank}", *parsed[i][1:7], f"n({srcs})")
        out.append(" ".join(f"{len(x)}:{x}" for x in fields))
    return out


def canon_bijection(rows):
    """THE PROOF, AS A CHECK. `(ok, why)` over a canonical form's own bytes.

    It asks two questions and both are decidable from the text: is the id column exactly
    `1..n`, each used ONCE, and does every `src` reference name a row in it? A form that
    fails either is not a relabelling of the graph and must not be compared, so this runs on
    every graph of every run -- a claim about a bijection asserted in a docstring is the
    thing this file exists to stop trusting.
    """
    ids, refs = [], set()
    for ln in rows:
        f = unchunk(ln)
        if len(f) != 8:
            return False, f"not eight fields: {ln[:60]!r}"
        if not f[0].startswith("i"):
            return False, f"the id field is {f[0]!r}"
        ids.append(int(f[0][1:]))
        refs.update(int(k) for k in CANON_REF.findall(f[7]))
    n = len(ids)
    if sorted(ids) != list(range(1, n + 1)):
        return False, f"the id column is not 1..{n} each once ({len(ids)} rows, {len(set(ids))} ids)"
    if not refs <= set(ids):
        return False, f"a reference names no row: {sorted(refs - set(ids))[:4]}"
    return True, f"ids=1..{n} each once, {len(refs)} reference(s) all resolve"


def canon_body(raw):
    """A side's bytes -> `(canonical bytes, why)`, and `why` names a refusal.

    A side with no rows has no canonical form, and the artifact still gets written with the
    reason IN it rather than left 0 bytes -- `artefacts_ok()` counts an empty artifact as a
    defect and would report the same missing rows twice under two names.
    """
    rows = [ln for ln in raw.decode(errors="replace").splitlines() if ln.strip()]
    if not rows:
        return b"", "this side emitted 0 rows, and 0 rows is not a canonical form"
    try:
        canon = canon_rows(rows)
        ok, why = canon_bijection(canon)
        if not ok:
            return b"", f"the canonical form is not a bijection: {why}"
        return ("\n".join(canon) + "\n").encode(), why
    except (ValueError, IndexError) as e:
        return b"", f"no canonical form: {e}"


def one_line(out):
    return (D / out).read_bytes().count(b"\n") <= 1


def cmd_run(a, wait=None):
    # **THE BOUND IS THE CLI'S OWN `wait` WHEN THERE IS A NAMESPACE, AND A PARAMETER
    # OTHERWISE, BECAUSE `one_run()` CALLS THIS IN-PROCESS WITH `None` (differ.py:2345).**
    # READING `a.wait` DIRECTLY WOULD RAISE THERE, AND `one_run`'s `except Exception` WOULD
    # TURN THAT INTO rc=1 AND *"run raised AttributeError"* -- **WHICH WOULD BREAK
    # `cmd_repro` QUIETLY RATHER THAN LOUDLY.**
    bound = getattr(a, "wait", 9) if wait is None else wait
    # **THE POPULATION MUST BE DECIDED BEFORE THE RUN, OR THE RUN CERTIFIES NOTHING.**
    # A graph that joins the corpus and is not re-decided leaves `POPULATION_PIN` stale, and a
    # run over it would be a measurement of a population nobody has an opinion about -- which is
    # the defect the exceptions table used to prevent by refusing to run. So this is a REFUSED
    # (3) and not a FAIL (1): a PRECONDITION was absent, not a comparison that came out wrong.
    # The plant population is the same shape: a plant the corpus's instrument declares and the
    # corpus neither runs nor excuses is a gap nobody would notice.
    #
    # **AND IT REFUSES BEFORE IT TOUCHES THE ARTEFACT DIRECTORY**, because a run that cannot
    # certify its population must not leave a half-written set behind for a reader to find.
    if bad := population_bad() + plants_bad():
        for line in bad:
            print(line, file=sys.stderr)
        print("  the corpus cannot certify a population that has not been decided: re-decide it, "
              "and move POPULATION_PIN in this file in the SAME COMMIT as the change.",
              file=sys.stderr)
        return gatekit().REFUSED

    # **AND THE RUN MUST NOT BEGIN OVER A BEND LANE THAT IS NOT HEALTHY.** `cmd_repro` HAS
    # ALWAYS GATED ON THIS -- `clean_run` (differ.py:2326) WAITS FOR A HEALTHY RUN AND
    # REFUSES (3) IF NONE COMES -- **AND `cmd_run` DID NOT, WHICH IS A DIFFERENT HAZARD FROM
    # TWO RUNS INTERLEAVING.** THE DIFFERENCE IS THE WHOLE CLAIM: THE CORPUS IS NOW A SINGLETON
    # (AN `fcntl.flock` ON `runs/graphcmp/.corpus.lock`, AND A SECOND RUN EXITS 3 WITH THE
    # HOLDER'S PID), SO TWO RUNS CANNOT INTERLEAVE -- **BUT A SINGLE RUN OVER A DEAD BEND LANE
    # STILL OVERWRITES 243 FILES OF EVIDENCE WITH A DEAD LANE, AND THE ARTEFACT DIRECTORY
    # THEN HOLDS A MIXTURE.** MEASURED 2026-10-23, REPEATEDLY, ON THIS TREE: A RUN WHOSE
    # `substrate-start` AND `substrate-end` DIFFER SAYS EXACTLY THAT -- *"THE SUBSTRATE MOVED
    # WHILE THE RUN WAS IN FLIGHT"* -- AND `unhealthy()` NAMES IT AS ITS ONE LINE.
    # **⇒ SO THE GATE IS HERE, BEFORE `D.mkdir`, AND IT IS THE SAME SHAPE AS `cmd_repro`'s:**
    # `ready()` IS A **PURE PROBE** (`settled()` RUNS THE DRIVER'S `--check-only` AND READS
    # ITS FIRST LINE; IT WRITES NOTHING TO `D/`), SO WAITING ON IT CANNOT DAMAGE THE EVIDENCE
    # IT IS PROTECTING.
    # **⇒ AND IT IS `REFUSED` (3) AND NOT `FAIL` (1), BECAUSE A PRECONDITION WAS ABSENT AND
    # NOTHING WAS DETERMINED: NOT `SKIP` (THE RUN NEVER EXECUTED), NOT `DEAD` (IT EMITTED NO
    # COMPLAINT), AND NOT 0 (A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO
    # GATE).** AND `D/` IS LEFT EXACTLY AS IT WAS, SO A READER FINDS THE PREVIOUS RUN'S
    # EVIDENCE AND NOT A HALF-WRITTEN SET.
    if not ready(bound):
        gk = gatekit()
        print(f"RUN: {gk.VERDICT[gk.REFUSED]} -- the bend lane did not settle in {bound} "
              f"probe(s), so the run would have OVERWRITTEN `D/` WITH A DEAD BEND LANE. "
              f"`{D}` IS EXACTLY WHAT IT WAS BEFORE THIS COMMAND STARTED, and `unhealthy()` "
              f"will now say so: it refuses a witness that names no bytes or names bytes that "
              f"have moved. THIS IS NOT A MEASUREMENT.", file=sys.stderr)
        return gk.REFUSED

    D.mkdir(parents=True, exist_ok=True)
    for tmp in D.glob(".tmp.*"):
        tmp.unlink()

    # THE FIRST HALF OF THE PAIR, taken before anything is emitted. Everything below re-reads
    # these bytes -- `graphcmp.py` is re-loaded by every `gc()` -- so a run is a mixture of two
    # substrates the moment any of them moves, and nothing else in `D/` can see it.
    substrate_start = substrate_digest()

    run("D0-selfcheck.txt", "selfcheck")

    # ONE LINE OF SUBSTANCE PER GRAPH: `diff --graph NAME` prints exactly one `# VERDICT:`
    # line and its `# DENOMINATOR:` line, and NAME is the only argument. The verdict step
    # ASSERTS each graph rather than leaving a reader to check thirty-five files by eye.
    #
    # **THE LOOP IS OVER `corpus()`, NOT OVER THE EXPECTATIONS.** This is the whole defect, and
    # the loop itself was the evidence: it used to read `for g in WANT:`, which meant
    # `graphcmp.GRAPHS` was never consulted by the run at all and every graph the corpus
    # declared but the table omitted was INVISIBLE -- not failed, not skipped, INVISIBLE,
    # while `graphs=` reported the table's own length as though it were the corpus.
    #
    # **AND NOW EVERY GRAPH HAS AN EXPECTATION, BECAUSE THE DEFAULT IS "AGREE"**
    # (`expectation()`). There is no UNSET state and no `graphs-unset` row: a graph that joins
    # the corpus is EXPECTED TO AGREE, and the corpus's growth is caught by the POPULATION PIN
    # instead -- a content pin over the graph list's own names and bytes, so a graph that joins
    # without a re-decision leaves a stale pin and the run REFUSES (see the top of this
    # function). **THE DENOMINATOR THAT MATTERS IS THE NUMBER OF EXCEPTIONS**, and it is 0.
    graphs = corpus()
    for g in graphs:
        run(f"D1-graph-{g}.txt", "diff", "--graph", g)
    # **A GRAPH THAT REFUSED IS NOT A GRAPH WHOSE VERDICT MOVED, AND CONFLATING THEM WAS
    # LOSING THE NAME.** MEASURED 2026-10-18T18:04Z: `loop` printed `loop: VERDICT=
    # EXPECTED=AGREE` -- an empty verdict cell with nothing after it -- while its OWN
    # artifact was a one-line `rc=2` and its `.err` named the refusal in full. So the run
    # held the name in two artifacts and dropped it from the one a reader reads, and then
    # counted the loss as a verdict that had MOVED, which is a different claim: a moved
    # verdict is the port answering wrongly, and a refusal is the port not answering.
    # FIVE VERDICTS (`gates/gatekit.py:60`), so `expect-moved` counts only graphs that
    # ANSWERED, `graphs-refused` counts the ones that did not, and the run refuses on
    # either -- see the return below.
    refused = [g for g in graphs if not verdict(f"D1-graph-{g}.txt")]
    moved = [f"{g}: VERDICT={verdict(f'D1-graph-{g}.txt')} EXPECTED={expectation(g)}" for g in graphs
             if verdict(f"D1-graph-{g}.txt") and verdict(f"D1-graph-{g}.txt") != expectation(g)]
    # **AND `na`/`bad` COUNT THE ANSWERS, NOT THE EXPECTATIONS.** They used to be
    # `sum(WANT[g] == "AGREE")` and `[g for g in WANT if WANT[g] == "DISAGREE"]`, which are two
    # censuses of the TABLE, and the sentence they appear in is about the RUN. MEASURED on the
    # first run of the canonical form (2026-10-18T18:18Z): the row read `33 of 34 graphs with
    # an expectation ANSWERED and every answer was as expected (34 AGREE; ...)`, because the
    # 34th graph had an AGREE *expectation* and no answer at all. A row that counts the table
    # beside a sentence that counts the run is a row with two numbers in one place.
    answered = [g for g in graphs if verdict(f"D1-graph-{g}.txt")]
    na = sum(1 for g in answered if expectation(g) == "AGREE")
    bad = [g for g in answered if verdict(f"D1-graph-{g}.txt") == "DISAGREE"]

    write("D1-verdicts.txt", "\n".join(moved + [
        # THE REFUSAL ROW. `first_line` is the artifact's own text -- `rc=2`, or a refusal
        # sentence -- and `.err`'s first line is beside it because that is where
        # `graphcmp.py` writes the reason (it exits before printing a verdict). **THE NAME OF
        # A REFUSAL HAS TO REACH THE ROW A READER READS**, or the run's own `.err` file is the
        # only place it exists and a summary that drops it reports a clean corpus.
        f"{g}: REFUSED -- EXPECTED={expectation(g)}, and the artifact answered "
        f"{first_line(f'D1-graph-{g}.txt')!r}; "
        f"{first_line(f'D1-graph-{g}.txt.err')!r}" for g in refused
    ] + [
        "AT LEAST ONE GRAPH'S VERDICT MOVED" if moved else
        (f"{len(answered)} of {len(graphs)} graphs ANSWERED and every answer was as expected "
         f"({na} AGREE; {conjoin(bad)} DISAGREE, each with a named cause in the exceptions table "
         f"above)"
         + (f"; {len(refused)} REFUSED and said so above: {conjoin(refused)}" if refused else ""))
    ]) + "\n")

    # THE CANONICAL FILES ARE BYTE-IDENTICAL, the cheapest check here: it fails first when an
    # atom letter moves. THIS STEP WAS A VACUOUS PASS until 2026-10-04: it ran `emit py` /
    # `emit bend`, which argparse rejects (`--side` is a FLAG, not a positional), so both
    # children exited 2 having written ZERO BYTES and `cmp -s` on two empty files returns
    # success. Hence the byte-count guard: a verdict line cannot tell an empty comparison
    # from a satisfied one.
    #
    # THE CANONICAL FILES, and THE CANONICAL FORM OF THEM. Two artifacts per side, two
    # questions, and they are NOT the same question:
    #
    #   `D2-canon-{side}-{g}.txt`     the rows as emitted, ids and all. It is the artifact
    #                                  `gates/emitverdict-gate.py` reads and it is LEFT
    #                                  BYTE-FOR-BYTE, because that gate's whole subject is the
    #                                  disagreement between this step and the structural
    #                                  verdict, and rewriting its input would delete the
    #                                  second opinion instead of answering the first.
    #   `D2-canonform-{side}-{g}.txt` the same rows under ids derived FROM THE GRAPH.
    #
    # `byte-identical` counts the SECOND. It used to count the first, which compared a
    # TOPOSORT POSITION against a HASH-CONS INDEX -- see the block above `canon_rows` for the
    # measurement and for the three canonical forms that were tried and were wrong first.
    for g in graphs:
        # A BARE redirect, deliberately not `run()`: this step needs stdout in two files at
        # once, so neither is staged and either can be left 0 bytes.
        sides, forms, whys = {}, {}, {}
        for side in ("py", "bend"):
            with (D / f"D2-canon-{side}-{g}.txt").open("wb") as f:
                gc("emit", "--side", side, "--graph", g, stdout=f, stderr=subprocess.DEVNULL)
            sides[side] = (D / f"D2-canon-{side}-{g}.txt").read_bytes()
            forms[side], whys[side] = canon_body(sides[side])
            # NEVER 0 BYTES: `artefacts_ok()` counts an empty artifact as a defect, and a
            # refusal with its reason in it is the same fact stated once instead of twice.
            (D / f"D2-canonform-{side}-{g}.txt").write_bytes(
                forms[side] or (f"# NOT COMPARED: {whys[side]}\n").encode())
        py, bend = sides["py"], sides["bend"]
        cpy, cbend = forms["py"], forms["bend"]
        report = []
        if not py or not bend:
            report.append(f"{g} NOT COMPARED: py={len(py)} bytes bend={len(bend)} bytes "
                          "(a 0-byte side is a FAILURE, not a pass)")
        else:
            # `RAW-IDENTICAL` / `RAW-DIFFERS`, NOT `BYTE-IDENTICAL` / `DIFFERS`: the summary
            # row is `grep -c 'BYTE-IDENTICAL'` over the concatenation of these reports, so a
            # word that also said BYTE-IDENTICAL would count one graph twice and the row would
            # stop being a count of graphs. The raw comparison stays here because it is a real
            # measurement -- it is the arena-vs-toposort difference itself -- and it is just no
            # longer the thing `byte-identical` names.
            report.append(f"{g} {'RAW-IDENTICAL' if py == bend else 'RAW-DIFFERS'} "
                          f"(py={len(py)} bytes bend={len(bend)} bytes)"
                          + ("" if py == bend else "\n" + byte_diff(
                              D / f"D2-canon-py-{g}.txt", D / f"D2-canon-bend-{g}.txt", 20)))
        if not cpy or not cbend:
            report.append(f"{g} NOT COMPARED (canonical): py -- {whys['py']}; "
                          f"bend -- {whys['bend']}")
        else:
            report.append(f"{g} {'CANONICAL BYTE-IDENTICAL' if cpy == cbend else 'CANONICAL DIFFERS'} "
                          f"(py={len(cpy)} bytes bend={len(cbend)} bytes)"
                          + ("" if cpy == cbend else "\n" + byte_diff(
                              D / f"D2-canonform-py-{g}.txt", D / f"D2-canonform-bend-{g}.txt", 20)))
        write(f"D2-cmp-{g}.txt", "\n".join(report) + "\n")
    # PER-GRAPH FILE, THEN CONCATENATED ONCE, in glob order. Both wrong shapes were tried:
    # `>>` accumulates until the file reads like a coverage table when it is one line
    # repeated, and `>` inside the loop leaves only the LAST graph's line.
    write("D2-bytediff.txt",
          "".join(f.read_text(errors="replace") for f in sorted(D.glob("D2-cmp-*.txt"))))

    for g in CONTROLS:
        run(f"D3-control-{g}.txt", "control", "--graph", g)
    run("D4-cross-range.txt", "cross", "--graph", "range")
    for plant, g in PLANTS:
        run(f"D5-plant-{plant}.txt", "diff", "--graph", g, "--plant", plant)
    # THE ORDERED / EQUIV SPLIT on the same reordered pair. Same fixture, two answers, and
    # both are results. It runs on `commute` too, which is the point: `--equiv` used to be
    # measured on ONE commutative op (a MUL), and here it is six of them in one graph.
    for g in ("matmul", "commute"):
        run(f"D6-{g}-ordered.txt", "diff", "--graph", g, "--plant", "srcswap")
        run(f"D6-{g}-equiv.txt", "diff", "--graph", g, "--plant", "srcswap", "--equiv")
    run("D7-conf.txt", "conf")
    run("D8-dbg-012.txt", "dbg", "--levels", "0,1,2")
    run("D8-dbg-03.txt", "dbg", "--levels", "0,3")

    for g, extra in STAB:
        for side in "ab":
            run(f"D9-stability-{g}-{side}.txt", "diff", "--graph", g, *extra)
    report = []
    for g, extra in STAB:
        a, b = f"D9-stability-{g}-a.txt", f"D9-stability-{g}-b.txt"
        if one_line(a) or one_line(b):
            for side in "ab":
                run(f"D9-stability-{g}-{side}.txt", "diff", "--graph", g, *extra)
        if one_line(a) or one_line(b):
            report.append(f"{g}: ONE SIDE IS A 0-ROW FAILURE after a retry -- NOT a "
                          "reproducibility result")
        elif (D / a).read_bytes() == (D / b).read_bytes():
            report.append(f"{g}: 2 runs BYTE-IDENTICAL")
        else:
            report.append(f"{g}: 2 runs DIFFER\n" + byte_diff(D / a, D / b, 20))
    write("D9-stability.txt", "\n".join(report) + "\n")

    # THE 0-ROW GUARD, FIRED ON PURPOSE, and the guard is that this is NOT retried:
    # `graphcmp-empty.bend` prints a `#` header and no rows, and `classify` (`graphcmp.py:1999`)
    # calls that an ANSWER -- `lines`, not `rows`, is the witness. MEASURED 2026-10-15:
    # `D10-zerorow-guard.txt.err` reads `bend attempt 1: 0 rows, ANSWER, rc=0, ...`, so an earlier
    # revision of THIS comment, claiming the probe "must RAISE rather than answer", was wrong about
    # the code it sits above. `CRASH_CONTROL`'s second row already names the opposite rule as a
    # defect: "a retry that fires on an answer".
    #
    # HISTORY, CORRECTED 2026-10-18: this said **THAT PROBE NO LONGER EXISTS**, deleted in sweep
    # `371cc64c9`. Sweep `371cc64c9` (2026-10-05) DID delete it -- and both files were RESTORED
    # after that, `graphcmp-empty.bend` by `c51c5ffd2` (2026-10-15) and `graphcmp-dbg.bend` by
    # `1a0ef5108` (2026-10-17). **BOTH ARE IN `HEAD` TODAY**, so the claim stopped being true and
    # nothing updated it: a sweep that deletes a file makes a later restore invisible to every
    # sentence that remembers the delete. The belief outlived its cause because
    # `.agents/slop/graphcmp.py:2138` keeps a VERBATIM FROZEN COPY of the old stderr as a
    # `CRASH_CONTROL` fixture, so the old error text still appears verbatim in a tracked file.
    # (The second mention, at the `write(...)` below, is a string INSIDE the `if not
    # probe.is_file():` branch -- accurate when it fires, so it is deliberately NOT changed.)
    # HISTORY: it and `graphcmp-dbg.bend`
    # were deleted in sweep `371cc64c9`, so `D10-zerorow-guard.txt` has been reading `rc=1` off a
    # **`no such file`**, which is the SAME exit code the guard raises when the probe WORKS. **A GUARD
    # THAT CANNOT DISTINGUISH "MY FIXTURE IS MISSING" FROM "MY FIXTURE BEHAVED" IS CERTIFYING A MISSING
    # FILE** -- and nothing read its rc, so it was `DEAD` (it ran, emitted a verdict, and nothing
    # consulted it). THE FIX IS NOT TO RESTORE A FIXTURE, IT IS TO **SAY WHICH**: the probe is a
    # REQUIRED INPUT and its absence is `REFUSED, NOT A VERDICT` -- absent is not a pass
    # (`gates/gatekit.py:60` is the vocabulary). `midrun` names two other absent inputs on a different
    # path (`.agents/slop/diffpy/`, pinned by `ORACLE_PIN`): the same shape, and the same fix.
    probe = Path(".agents/slop/graphcmp-empty.bend")
    if not probe.is_file():
        write(f"{D10}.txt",
              "zerorow-guard=REFUSED\nzerorow-guard-rc=3\nzerorow-guard-why=probe "
              ".agents/slop/graphcmp-empty.bend is ABSENT (deleted in 371cc64c9); an absent fixture "
              "cannot witness that a 0-row emission RAISES\n")
    else:
        run(f"{D10}.txt", "emit", "--side", "bend", "--bend-probe", str(probe))
    # THE COVERAGE DENOMINATOR, tabulated, emitting BOTH sides so an op or atom the py side
    # never produces shows up as a per-side difference rather than an absorbed AGREE.
    capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)  # DEV/PYTHONHASHSEED/NOOPT/LC_ALL are set by ENV above, not by this call
    # WHETHER CPYTHON's OWN `DEBUG >= 1` SITE CAN BE REACHED HERE. It cannot, on 13 real
    # graphs, which is why `dbg` is port-vs-port and says so in its own output.
    capture("D8b-cpython-dbg1-reachability.txt", ".agents/slop/graphcmp-dbg-oracle.py")
    # THE OPS PROBE: the raw CPython measurements every coverage claim rests on. It asks
    # CPython DIRECTLY -- does GROUP carry a `params` list, which Tensor op emits which NODE
    # op -- and those questions have no answer a port-vs-port diff can produce.
    capture("D0-ops-probe.txt", ".agents/slop/graphcmp-p13-ops.py")

    # REMOVE THE STALE FILES no command here produces. The byte-identity step used to run four
    # graphs, and an earlier unquoted `for c in $STAB` split on the space in
    # `--plant srcswap` and produced a SIXTH pair named `srcswap`, which is not a graph. A
    # directory carrying a PASS-shaped file that no command produces is exactly what this
    # prevents -- and `D1-verdicts.txt` is the only thing that caught it, because it does not
    # look at file NAMES.
    for stale in ("D9-stability-a.txt", "D9-stability-b.txt"):
        (D / stale).unlink(missing_ok=True)
    for stale in D.glob("D9-stability-srcswap-*"):
        stale.unlink()

    write("D0-run-summary.txt", "\n".join([
        # `graphs` COUNTS WHAT WAS ASKED FOR -- `len(corpus())` -- AND NOT WHAT WAS ANSWERED.
        # It used to be `len(list(D.glob('D1-graph-*.txt')))`, which counted the artifacts
        # `WANT` wrote and therefore reported the TABLE's length wearing the CORPUS's name:
        # 9 graphs were declared, never run, and the line said nothing. A denominator that
        # counts only the answered cases is a denominator that cannot shrink and so cannot be
        # wrong.
        #
        # **`graphs` AND `graphs-answered` ARE TWO VIEWS OF ONE NUMBER NOW** -- there is no
        # `u` to subtract, because every graph has an expectation (the default is AGREE). They
        # are kept as two spellings because a health gate that answers one number twice is
        # easier to notice rot in, and because `graphs-answered` is the one that moves when a
        # graph REFUSES to answer.
        f"graphs={len(graphs)}",
        f"graphs-answered={len(answered)}",
        # **THE POPULATION'S IDENTITY, IN THE RUN'S OWN SUMMARY.** A row that says which
        # population was measured, so the run is comparable to a corpus rather than to a
        # number. It is a CONTENT digest over the graph list's names and the bytes that define
        # each graph, and `PINS` holds the pinned one: a run over a population nobody has
        # re-decided leaves this row disagreeing with the pin, which is a RED in `unhealthy()`
        # and a REFUSED run in `cmd_run`.
        f"population={population_digest()}",
        # **THE COUNT OF ROWS THAT ARE WRONG**, which nothing counted until now. Distinct from
        # every line above it: `graphs`/`graphs-answered` are about how many ROWS the corpus
        # has, `graphs-agree`/`graphs-disagree` are about how many ARTIFACTS carry a verdict,
        # and this one is about whether the rows that exist were RIGHT. All of them can be
        # self-consistent and wrong at once, which is the state this file ran in until now.
        f"expect-moved={len(moved)}",
        # **THE FIFTH VERDICT, AND IT IS NOT `expect-moved` WITH A DIFFERENT SPELLING.** A
        # graph whose artifact carries no `VERDICT:` line answered nothing: `graphcmp.py`
        # exited 2 on a precondition (the device sets, or an emission that BROKE) and wrote
        # the reason to its `.err`. Counting that as a moved verdict says the PORT is wrong
        # when the HARNESS declined to compare, which is the same confusion the empty
        # `loop: VERDICT=` cell was. MEASURED 2026-10-18T18:04Z: `expect-moved=3` was
        # `gate`, `lin` and `loop`, and `loop` was not a moved verdict at all.
        f"graphs-refused={len(refused)}",
        f"graphs-agree={files_with('D1-graph-*.txt', 'VERDICT: AGREE')}",
        f"graphs-disagree={files_with('D1-graph-*.txt', 'VERDICT: DISAGREE')}",
        f"byte-identical={lines_with('D2-bytediff.txt', 'BYTE-IDENTICAL')}",
        f"not-comparable={lines_with('D2-bytediff.txt', 'NOT COMPARED')}",
        # **THE DENOMINATORS ARE DERIVED, NOT TYPED.** `of 5` and `of 7` were literals in this
        # writer, so a selection that grew made the row read `8 of 7` -- a number nobody can
        # check. They come from `STAB`, `PLANTS` and `CONTROLS` now, which are this file's own
        # declarations, so they cannot drift from what was run.
        f"stable-pairs={anchored('D9-stability.txt', r': 2 runs BYTE-IDENTICAL$')} of {len(STAB)}",
        f"stable-failed={lines_with('D9-stability.txt', 'ONE SIDE IS A 0-ROW FAILURE')} of {len(STAB)}",
        f"stable-differ={anchored('D9-stability.txt', r': 2 runs DIFFER$')} of {len(STAB)}",
        # EIGHT, NOT SEVEN: the eighth is `params`, the plant for the `pI(` form, which needs
        # the `prog` graph rather than the matmul, so it is not in the six-above loop.
        f"plants-disagree={files_with('D5-plant-*.txt', 'VERDICT: DISAGREE')} of {len(PLANTS)}",
        f"cross={lines_with('D4-cross-range.txt', 'CROSS VERDICT: OK')} of 1",
        f"selfcheck={first_line('D0-selfcheck.txt')}",
        f"conflations={lines_with('D7-conf.txt', 'VERDICT: OK')} of 4",
        f"controls={files_with('D3-control-*.txt', 'CONTROL VERDICT: OK')} of {len(CONTROLS)}",
        # The oracle's own assertions ride in the same summary as the differ's, because a
        # coverage claim whose printer is broken is a coverage claim about the printer.
        f"oracle-selfcheck={grep_line('D0-coverage-census.txt', 'ORACLE SELFCHECK')}",
        f"census-rc={last_line('D0-coverage-census.txt')}",
        # THE FOUR ROWS, AND WHY FOUR ROWS AND NOT A NEW FILE. This summary is already parsed as
        # `key=value` by `gates/retention-check.py`'s CLAUSE IV, by `checks/corpus-figure.py:140`,
        # by `checks/disagree-gate.py:128` and by `checks/env-precond.py`'s METHOD B, so a row
        # here is read by four consumers and NO NEW PARSER EXISTS ANYWHERE. A separate file would
        # be a THIRD place the device is claimed, and two claims about one run is a second
        # opinion -- which is the thing `gates/retention-check.py`'s own header says it exists to
        # avoid.
        *precondition_rows(),
        # THE SECOND HALF OF THE PAIR, after the last `emit` and before the summary is written.
        # Both halves ride here because this summary is already parsed as `key=value` by four
        # consumers and a fifth file would be a second place the run is claimed.
        *substrate_rows(substrate_start, substrate_digest())
         + [f"substrate-head={substrate_head()}"]]) + "\n")
    print(f"wrote {relpath(D)}")
    # **A RUN WHOSE ROWS ARE WRONG IS A SEPARATE REFUSAL, AND IT USED NOT TO BE RAISED.**
    # MEASURED: the exit was `if unset` and nothing else, so with every graph answered a run
    # in which a row was simply WRONG returned 0 and read HEALTHY -- and the one pin that could
    # have noticed, `graphs-agree`, NETS OUT over the corpus and so misses the case where one
    # row moves to AGREE while another moves to DISAGREE. That is the failure this whole file is
    # about (a claim with no denominator, or a count that cannot distinguish right from wrong),
    # and it was in the gate itself. The refusals are reported separately because they are
    # different questions: `expect-moved` says a row is wrong, a REFUSAL says the corpus was
    # not answered, and only the first is a claim the port made.
    #
    # **AND IT DOES NOT CONSULT `PINS`, WHICH IS THE CORRECT SHAPE AND WAS MEASURED.** `run`
    # honours ONE of the 17 (`expect-moved`) and returns 0 unconditionally otherwise. Making it
    # consult the other 16 would make `run` A GATE ON ITS OWN OUTPUT: a run that finds the port
    # changed a row would refuse to EXIT, so the change could never be recorded, and the pins
    # are hand-written literals that move when the port's next fix lands (the block above
    # `PINS` says so itself). **A MEASUREMENT MUST NOT BE CITED AS A HEALTH GATE, AND THE JUDGE
    # MUST NOT BE THE RUN.** `unhealthy()` and `checks/corpus-figure.py` are the judges; `run`
    # is the measurement.
    for line in ("RUN WRONG: expect-moved=N -- these rows' EXPECTED verdicts did not match what "
                 "the port emitted, and a run whose expectations are wrong is not a measurement "
                 "of them:\n  " + "\n  ".join(moved) if moved else None,
                 # A REFUSAL IS NOT A WRONG ROW AND IS NOT A PASS. `cmd_run` refuses on it for
                 # the same reason it refuses on a moved row: the corpus was not answered, so
                 # nothing in this run may be read as a verdict about those graphs. MEASURED
                 # 2026-10-18T18:04Z, `loop` was refused here (device precondition, exit 2)
                 # and the run still reported it as a moved VERDICT, which is a claim about
                 # the port the port never made.
                 f"RUN INCOMPLETE: {len(refused)} of {len(graphs)} graphs REFUSED and so have "
                 f"NO verdict: {', '.join(refused)}. Each refusal is named with its own reason "
                 f"in D1-verdicts.txt; `expect-moved` does not count them, because a graph "
                 f"that did not answer is not a graph whose answer moved." if refused else None):
        if line:
            print(line, file=sys.stderr)
    return 1 if moved or refused else 0


# ---- THE PRECONDITIONS, AND THE CROSS-CHECK THAT KEEPS THE ROWS FROM BEING LABELS ---------
#
# `differ.py` BUILDS the child environment (`ENV`, `:47`), so it can record what a run used
# without asking a shell: a shell's environment is not a run's, and a harness's default is not a
# run's value. `checks/env-precond.py` declares the same four and reads them out of this summary,
# so every row has TWO INDEPENDENT readings -- a source line it scans, and this file.
#
# `dev` IS NOT READ OUT OF `ENV`, BECAUSE `ENV["DEV"]` IS DEAD. MEASURED: every consumer of `ENV`
# overwrites it before `tinygrad`'s `Device.DEFAULT` resolves -- `graphcmp.py:2853` from its own
# `--dev`, and `graphcmp-oracle.py` and `graphcmp-p13-ops.py:28` by assignment -- so the device is
# read off the artifacts, which are the only place it survives.
#
# WHY A PIN IS NOT REDUNDANT WITH A SORT. MEASURED over five seeds of one 6-member set: **5
# distinct `set(...)` renderings, 1 sorted rendering.** A PIN IS A SEED and a SORT IS A LAW -- a pin
# fixes the order on THIS interpreter, a sort fixes it on EVERY interpreter, and the claim being
# protected ("the port and CPython disagree") has to survive a Python upgrade. So recording the
# seed is NECESSARY AND NOT SUFFICIENT, which is why both land; the sort is `graphcmp-oracle.py:233`,
# which is not this file's.
#
# THE LEDGER IS EIGHT, NOT 147. MEASURED by AST-counting every `getenv`/`ContextVar` in `tinygrad/`
# and sweeping each one in its own subprocess: **8 can move a verdict** -- `DEV` `IMAGE` `NOOPT`
# `DEFAULT_FLOAT` `NO_COLOR` `DEBUG` `DEBUG_RANGEIFY` `MAX_BUFFER_SIZE` -- plus 5 that make the side
# unbuildable, and **128 measured inert because the comparison never REALIZES a graph**, so every
# runtime and compiler flag sits downstream of a boundary this harness does not cross. A LIST OF
# VARIABLES A PROGRAM CAN READ IS NOT A LIST OF VARIABLES THAT MATTER.
ROW_VALUES = {"lc_all": "C", "noopt": "0", "pythonhashseed": "0"}
ROW_KEYS = ("dev",) + tuple(ROW_VALUES)


def _pinned(key):
    """`key` as every child was handed it, with `unset` and the EMPTY value spelled apart from a
    zero. They are three states and they behave differently: MEASURED, `NOOPT=` is `int("")` at
    `tinygrad/helpers.py:163` and raises `ValueError` AT IMPORT, so a row that collapsed the three
    would report a crash as a zero."""
    got = ENV.get(key.upper())
    return "unset" if got is None else (got or "empty")


def devices():
    """(by the `# devices` HEADER, by the `SGLOBAL,s<DEV>` FIELD) over the run's own artifacts.

    TWO METHODS THAT SHARE NO REGEX, because SELF-CONSISTENCY IS NOT INDEPENDENCE: the header is a
    comment the report writes and the field is a substring of a `P(...)` arg, so a belt built on
    one pattern catches only what that pattern sees. `devpin.observed()` is IMPORTED rather than
    retyped -- it already knows that `N` is `ATOMS["none"]` (graphcmp's absence token) and not a
    device called `N`, which is a distinction this tree has already paid for once.

    MEASURED over the live 139 artifacts: 51 name a device by header, 50 by field, and both
    answer `{CPU}`.

    LOADED BY PATH, like `corpus()` loads `graphcmp.py`, because a bare `import devpin` works only
    when this file happens to be `sys.path[0]` -- and four callers load it by path.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location("devpin", ROOT / "checks/devpin.py")
    devpin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(devpin)
    devpin.D = D                     # the same rebinding `gates/retention-check.py` does
    heads, fields, _, _ = devpin.observed()
    return heads, fields


def device_of_run():
    """The ONE device the artifacts name, or a refusal that says why not. An empty or a mixed
    answer is NOT silently `CPU`: a reader that found nothing must say so, because this string is
    the only place a run states what it ran on."""
    heads, fields = devices()
    if not heads and not fields:
        return "UNNAMED -- no artifact names a device"
    if heads != fields or len(heads) != 1:
        return f"DISPUTED headers={sorted(heads)} fields={sorted(fields)}"
    return next(iter(heads))


def precondition_rows():
    """The four `key=value` lines, ready to join `D0-run-summary.txt`."""
    return [f"dev={device_of_run()}"] + [f"{k}={_pinned(k)}" for k in ROW_VALUES]


def preconditions_bad(got):
    """THE ROWS AGAINST WHAT THEY PRECONDITION. Each row is a CLAIM; this is the check that
    keeps it from being a LABEL -- a green row nothing compares to can never go red, which is the
    `?`-assertion with no fixture.

    `dev` is checked against the artifacts (99 independent witnesses) and the other three against
    `ENV` (the dict every child was handed). `dev` is deliberately NOT also checked against a
    pinned constant: that is `checks/devpin.py`'s question, and answering it twice here would be a
    second opinion about one fact.
    """
    bad = [f"{k} ABSENT -- a precondition nothing records is a precondition nobody can audit"
           for k in ROW_KEYS if k not in got]
    bad += [f"{k}={got[k]} but ENV pins {ROW_VALUES[k]}" for k in ROW_VALUES
            if k in got and got[k] != ROW_VALUES[k]]
    if "dev" in got and (seen := device_of_run()) != got["dev"]:
        bad.append(f"dev={got['dev']} but the artifacts say {seen}")
    return bad


# ---- THE SUBSTRATE: WHICH BYTES PRODUCED THIS RUN, IN TWO ROWS --------------------------------
#
# WHY TWO ROWS AND NOT ONE. One `substrate=H` says what the substrate WAS. That is a LABEL, and
# a label cannot go red. Two rows say what the substrate was BEFORE the first `emit` and what it
# was AFTER the last one, and the PAIR is a comparison: `start != end` means this run is a
# MIXTURE of two substrates, so no artifact set in `D/` describes one thing. MEASURED by
# `midrun` on 2026-10-07: a `PROOF.bend` edit mid-run moved the substrate and changed no
# artifact, no row and no pin, "because no row can name bytes". These are the first two rows in
# `D/` that can, and they answer the case `pinindep` names as never tested: all eleven of its
# perturbations edited a FINISHED artifact set.
#
# WHERE H0 COMES FROM, WHICH IS THE PART THAT LOOKS LIKE IT NEEDS A LEDGER AND DOES NOT. It is not
# pinned and must not be: a pin on a substrate digest would have to be re-pinned every time the
# port moves, which is `pinindep`'s finding -- 17 pins on ONE file is one measurement wearing 17
# hats -- made worse by a pin that is red by construction after any real edit. So H0 is
# `substrate-start`, written by this run, into the file four parsers already read; H1 is
# `substrate-end`, written by the same run. Both live in the one artifact, so the comparison
# needs no second witness, no external ledger and no new parser.
SUBSTRATE_ROWS = ("substrate-start", "substrate-end")

#: The inputs, by DISCOVERY where the tree can be walked and by this file's OWN declarations
#: where it cannot. The port is a DIRECTORY WALK. The eight named files are the ones `run`
#: hands to a subprocess or reads itself, and each is anchored to the line that names it.
#: CORRECTED 2026-10-17 -- ALL SIX NUMBERS BELOW WERE WRONG, EACH RESOLVED BY PRINTING IT:
#:   :44 GCMP         .agents/slop/graphcmp.py      :1040 ./bin/bend
#:   :1040 BEND_PROBE .agents/slop/graphcmp.bend    :840 devpin
#:   :671,:674,:678   the three `capture()` oracle scripts
#:   and `checks/differ.py` itself, which every artifact's driver is. A path here with no
#:   anchor would be a bare hand-list entry. THE READER IS `checks/substrate-snapshot.py
#:   --declare` -- BESIDE THE GATE AND IN GIT; `.agents/slop/quiesce/snapshot.py`, WHICH THIS
#:   COMMENT NAMED, IS ABSENT (7 paths in HEAD under that directory, none of them `snapshot.py`).
#:   BUT `--declare` DOES NOT READ THESE NUMBERS: `checks/substrate-snapshot.py:201` IS
#:   `ok = any(tok in ln for ln in src.splitlines())`, A WHOLE-FILE SEARCH, SO IT REPORTS `ok` ON
#:   6 OF 8 ANCHORS THAT ARE AT THE WRONG LINE AND EXITS 0. IT ANSWERS "DOES THIS STRING APPEAR
#:   ANYWHERE?" WHERE THE CALLER ASKED "DOES LINE N STILL NAME IT?", SO THIS TABLE IS A HUMAN
#:   CONTRACT AND SAYS SO INSTEAD OF NAMING A CHECKER THAT CANNOT CHECK IT.
# THE TWO DRIVERS `cmd_run` ACTUALLY EXECUTES, AND A GREP CENSUS MISSES BOTH. `.agents/slop/` is
# reached ONLY by explicit names here, and neither name appeared, so a substrate move in either file
# was invisible to the digest that exists to catch one. `graphcmp-dbg.bend` is assembled at RUNTIME
# (`SLOP / "graphcmp-dbg.bend"`) and handed to `subprocess.run` at `graphcmp.py:3064`, so searching
# the source for the literal finds nothing; `graphcmp-empty.bend` is the `else` branch at `:904`.
# MEASURED 2026-10-18 by an AST census that resolves runtime-assembled constants: both were
# uncovered, and the same census rejected all 7 PROSE mentions of them.
SUBSTRATE_INPUTS = ("checks/differ.py", "checks/devpin.py", "bin/bend",
                    ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
                    ".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend",
                    ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
                    ".agents/slop/graphcmp-p13-ops.py")


def substrate_digest() -> str:
    """sha256 over `(relpath, sha256(bytes))` for every declared input, SORTED by relpath.

    Keyed on CONTENT and on the path RELATIVE TO `ROOT`. Never on `st_mtime`, never on the
    absolute path: a fresh clone of one tree writes every file at the moment it is cloned, so an
    mtime key is a fact about THIS TREE and two clones would disagree. MEASURED
    (`.agents/slop/substrateid/measure.py`, re-testing `pinindep`'s blocker 2): rewriting every
    mtime of a second copy across a 4e12 ns spread left the digest byte-identical.

    A declared path that is ABSENT contributes the token `ABSENT`, so a deletion and an addition
    both move the digest and the population cannot silently shrink -- the defect
    `quiesce/snapshot.py:80-85` has, where `inputs()` appends only `elif p.is_file()` and two
    declared inputs (`graphcmp-dbg.bend`, `graphcmp-empty.bend`) are named at `:65-66` and
    dropped from the build that prints `froze 148` and exits 0.
    """
    h = hashlib.sha256()
    for rel, blob in sorted(substrate_entries()):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


# THE OTHER WALK. `tinygrad/` IS THE REFERENCE EVERY VERDICT IS RELATIVE TO, AND IT WAS NOT IN THE
# POPULATION: MEASURED 2026-10-18, the digest covered **156** declared inputs and **0 of the 213**
# `tinygrad/*.py`. So if the CPython side moved mid-run -- the likeliest move of all, since an
# upstream re-vendor rewrites it -- `substrate_digest()` could not notice, and the run's whole claim,
# "ONE run measured ONE substrate", would have been blind to the input that decides every comparison.
# The dependency is executed, not decorative: `graphcmp-oracle.py:244` does `import tinygrad` and
# `graphcmp-p13-ops.py:33` does `from tinygrad import Tensor, dtypes`.
#
# **A DIGEST THAT OMITS THE SUBJECT OF THE COMPARISON IS A PIN ON THE SCALE, NOT THE SUBJECT.**
# This walk is what makes `tinygrad/` the SECOND subject, so a substrate move now names the member
# that moved instead of hiding behind 213 unpinned files.
SUBSTRATE_WALKS = ("tinybendygrad", "tinygrad")


def substrate_entries() -> list[tuple[str, str]]:
    """`(relpath, sha256)` per input: the walks plus the named files, ABSENT where not on disk."""
    out = []
    for root in SUBSTRATE_WALKS:
        out += [(p.relative_to(ROOT).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
                for p in (ROOT / root).rglob("*")
                if p.is_file() and "__pycache__" not in p.parts]
    for rel in SUBSTRATE_INPUTS:
        p = ROOT / rel
        out.append((rel, hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "ABSENT"))
    return out


def substrate_rows(start: str, end: str) -> list[str]:
    """The two lines, in summary order. `start` is taken before the first `emit` and `end`
    after the last, so the pair BRACKETS the whole run rather than sampling it once."""
    return [f"{k}={v}" for k, v in zip(SUBSTRATE_ROWS, (start, end))]


def substrate_head(root: Path = ROOT) -> str:
    """THE COMMIT THE RUN MEASURED, RECORDED BESIDE THE PAIR -- and it is a THIRD row, not a
    replacement for the other two.

    **WHY IT CANNOT REPLACE THEM.** MEASURED 2026-10-18 over 18 readings / 3 digests / 5 HEADs:
    `substrate_digest()` is a function of the WORKING COPY, and **0 of 4 commits in the window moved
    it** while **1 of 1 fixed-HEAD interval contained a move** -- another unit's edit to this file was
    hashed 33 seconds BEFORE it was committed, so the digest briefly described a state no commit ever
    named. **MOVE-DETECTION AND COMMIT-IDENTITY ARE THE SAME PROPERTY, AND A `ls-tree`-BASED DIGEST
    CANNOT MOVE DURING A RUN -- IT WOULD `PASS` ON EXACTLY THE MIXTURE IT EXISTS TO CATCH.** So the
    worktree pair STAYS and this row is ADDED.

    **WITHOUT IT THE ROWS ARE UNREADABLE.** The digest covers 389 members of which **14 are in NO
    commit at all** (`bin/bend` is `.gitignore:5`, and the walks sweep up `*-mut.bend`/`.bak` probe
    scratch), so a FRESH CLONE HASHES **375** and would report a different substrate for the same
    commit. Two readers of these rows name the worktree scope; **NONE named it in the row's key.**
    `ABSENT` or not, this row is what makes the other two comparable to a tree.
    """
    q = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root,
                       capture_output=True, text=True)
    head = q.stdout.strip()
    return head if q.returncode == 0 and head else "NO-HEAD"


def substrate_bad(got) -> list[str]:
    """THE TWO ROWS AGAINST EACH OTHER. Empty means the run is one substrate; anything here is a
    run whose artifacts cannot be read as a measurement of one thing.

    ABSENT IS A COMPLAINT AND NOT A PASS: a summary carrying neither row was written before these
    rows existed, so its other 22 pins are claims about bytes nobody recorded. That is the same
    rule `preconditions_bad()` applies to `dev` and the three ENV rows, and it is why this is a
    function beside `unhealthy()` rather than a branch inside `PINS`.
    """
    if absent := [k for k in SUBSTRATE_ROWS if k not in got]:
        return [f"{k} ABSENT -- a run that does not say which bytes produced it is a measurement "
                f"with no subject; re-run `checks/differ.py run`" for k in absent]
    a, b = (got[k] for k in SUBSTRATE_ROWS)
    return [] if a == b else [
        f"{SUBSTRATE_ROWS[0]}={a[:12]} but {SUBSTRATE_ROWS[1]}={b[:12]} -- THE SUBSTRATE MOVED "
        f"WHILE THE RUN WAS IN FLIGHT, so D/ holds a MIXTURE of two substrates and no artifact "
        f"set here describes one thing"]


def verdict(out):
    """`grep -o 'VERDICT: [A-Z]*' ... | tail -1 | cut -d' ' -f2`. The LAST one, because a
    report carries the verdict twice and the operative line is the one at the bottom.

    **A MISSING ARTIFACT HAS NO VERDICT, AND SAYING SO IS NOT A CRASH.** The file is absent
    when the artefact set on disk is older than the corpus -- and then the graph did not
    answer, which is a REFUSAL and not an exception. MEASURED 2026-10-22: the corpus grew to
    35 graphs while the artefact set still held 34, so reading a graph that was never run
    raised `FileNotFoundError` from inside a PLANT -- and a crash is not a verdict.
    """
    p = D / out
    if not p.exists():
        return ""
    found = re.findall(r"VERDICT: [A-Z]*", p.read_text(errors="replace"))
    return found[-1].split()[1] if found else ""


def first_line(out):
    p = D / out
    return p.read_text(errors="replace").split("\n", 1)[0] if p.exists() else ""


def last_line(out):
    return text(out).rstrip("\n").split("\n")[-1]


def snap(stream=sys.stdout):
    """sha256 over the NON-BLANK lines of every artifact, dotfiles pruned.

    The exclusion is not cosmetic: `run()` stages each output as `.tmp.<name>` inside this
    directory, so a run killed mid-write leaves a temp whose presence in one snapshot and
    absence in the other is a difference in the HARNESS's staging and not in the artifact.
    Dropping blank lines is load-bearing rather than fussy: a trailing BLANK LINE is a real
    difference this project has already paid for (a count-based diff reported 16 apparent
    deltas that were 16 blank lines), while a hash of the whole file would call a blank line
    a difference too. This form asks whether any CONTENT moved, which is the question.
    """
    for p in sorted((q for q in D.rglob("*")
                     if q.is_file() and not q.is_symlink()
                     and not any(part.startswith(".") for part in q.relative_to(D).parts)),
                    key=relpath):
        body = b"".join(ln + b"\n" for ln in p.read_bytes().split(b"\n")[:-1] if ln.strip())
        # **AN OBSERVER ROW IS NOT PART OF THE SUBJECT, AND HASHING IT MAKES A PIN FLAKY.**
        # MEASURED 2026-10-20: `substrate-head=` was added to the summary to make a run comparable to
        # a COMMIT -- and then two clean runs of the SAME TREE differed in EXACTLY ONE of 310 files,
        # because that row records WHICH COMMIT measured the run and a commit landed between them
        # (`77e6c2bec` at 03:53:51Z, `4e76b4cb` at 03:59:38Z). The corpus did not move; the OBSERVER
        # did. **A ROW THAT MAKES A RUN COMPARABLE TO A TREE MAKES TWO RUNS OF THE SAME TREE
        # INCOMPARABLE** -- both properties are wanted and they are NOT the same property, so the
        # comparison is over the SUBJECT and the observer is recorded but not hashed.
        if p.name == "D0-run-summary.txt":
            body = b"".join(ln + b"\n" for ln in body.split(b"\n")[:-1]
                             if ln.strip() and not any(ln.startswith(r.encode() + b"=")
                                                  for r in OBSERVER_ROWS))
        print(f"{hashlib.sha256(body).hexdigest()}  {relpath(p)}", file=stream)


def d10_sha(shot: str) -> str:
    """D10's transcript hash, TAKEN FROM `snap()`'s OWN OUTPUT rather than recomputed here.

    The snapshot `cmd_repro` writes is `<sha256>  <path>` per line, so the pin and the sweep read the
    SAME number by construction and cannot drift apart -- the alternative, hashing the file again in
    this function, would be a second copy of `snap()`'s rule (non-blank lines, dotfiles pruned) and a
    second thing to keep correct. An artifact the snapshot does not carry answers `ABSENT`, which is
    not any pin, so a missing transcript REDS rather than passes.
    """
    for ln in shot.splitlines():
        sha, sep, rel = ln.partition("  ")
        if sep and rel.endswith(f"{D10}.txt.err"):
            return sha
    return "ABSENT"


def settled():
    """ONE probe line, and it is `--check-only`'s FIRST line only: agent-core.md's trap is
    that it exits 1 even on a clean file (`dtype.bend`'s 14 permanently-red laws), so the exit
    status is not the signal and the text is."""
    p = subprocess.run(["./bin/bend", ".agents/slop/graphcmp.bend", "--check-only"],
                       cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.stdout.split("\n", 1)[0]


def ready(wait):
    for probe in range(wait):
        if settled() == "ALL PROOFS CHECK":
            return True
        if probe + 1 < wait:
            time.sleep(60)
    return False


def unhealthy():
    """Every pin matched BY CONTENT, and a FAILING PIN NAMED.

    The shell's `healthy()` answered one boolean, so a stale pin was indistinguishable from a
    broken run. That is the whole reason this returns the offenders: a health gate that says
    only "not healthy" has spent an hour of wall clock saying nothing about why.

    IT ALSO NAMES A MISSING SUMMARY INSTEAD OF RAISING, which is the second half of the same
    rule. This used to `text("D0-run-summary.txt")` straight, so the one state in which there is
    no run at all -- an empty artifact directory, or a driver whose output names moved -- came
    out as a `FileNotFoundError` traceback. A traceback says which line raised and nothing about
    which run or which pin, which is the "says only that something is wrong" failure this
    function exists to remove. MEASURED 2026-10-05: renaming the artifacts `*.txt` -> `*.rows`
    took `check_oracle()` to `[] -- PIN INTACT` and this call to exactly that traceback.
    """
    if not (D / "D0-run-summary.txt").exists():
        return ["D0-run-summary.txt ABSENT -- there is no run to be healthy about, so every pin "
                "below is unknown rather than matched"]
    got = dict(ln.split("=", 1) for ln in text("D0-run-summary.txt").splitlines() if "=" in ln)
    # THE PRECONDITION ROWS ARE HEALTH, NOT BOOKKEEPING, so they ride here rather than in a gate
    # of their own: `gates/retention-check.py`'s CLAUSE IV calls THIS function by reference, so a
    # run whose summary records no device -- or records one the artifacts contradict -- makes the
    # retention rule fire with no new parser and no new clause.
    #
    # **AND THE POPULATION AND THE PLANTS RIDE HERE TOO, BECAUSE THEY ARE HEALTH IN THE SAME
    # SENSE.** A run over a population nobody has re-decided is not healthy, and a run whose
    # plant population has drifted from the corpus's instrument's is not healthy -- and both are
    # facts about the TREE the run is on, which is what this function is about. **THE DERIVED
    # COUNTS ARE COMPARED HERE AND NOWHERE ELSE**, so a derived expectation that is never
    # compared would be an expectation in name only: the run's own `graphs=` row is checked
    # against the DISCOVERED corpus, and a disagreement is a red.
    return [f"{k}={v} (expected {PINS[k]})" for k, v in got.items() if k in PINS and v != PINS[k]] \
        + [f"{k} ABSENT" for k in PINS if k not in got] + preconditions_bad(got) \
        + substrate_bad(got) + population_bad() + plants_bad()


def repro_bad() -> list[str]:
    """THE SECOND WITNESS, judged on its own artifact, by a SEPARATE reading of the disk.

    **THIS IS THE WHOLE POINT OF `REPRO_PINS`, SO IT IS STATED HERE WHERE A READER LANDS.**
    `PINS` is 17 claims, all of them `key=value` rows of `D0-run-summary.txt`, so `PINS` green is
    ONE run's seventeen rows and the denominator of "this run is healthy" is **1 artifact**, not
    17 -- 12 witnesses and 10 independent measurements behind it, every one of them a function of
    the same run (`/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/pinindep/REPORT.md`,
    measured by perturbing artifacts, not by reading them). `cmd_repro` is the tree's only
    INDEPENDENT measurement: two clean runs, sha256 over every artifact, byte-compared
    (`snap()`, `:798`). It computed that verdict and printed it to a tty. Reading it here is what
    makes the denominator **2 artifact reads**.

    **IT IS A FUNCTION BESIDE `unhealthy()`, NOT A BRANCH INSIDE IT, AND THAT IS A VERDICT
    CHOICE.** `unhealthy()` is called by `clean_run()` -- i.e. BY `cmd_repro` ITSELF, one run
    before this file exists on disk. A check that demanded `D0-repro.txt` from inside the loop
    that is about to write it could never pass, so it would be a check that reports red forever
    and gets ignored. **A GATE MUST NOT BE THE JUDGE OF ITS OWN OUTPUT**: `run` measures, and the
    readers judge. `checks/corpus-figure.py` is the reader, and it consults this beside
    `unhealthy()`.

    THE THREE STATES, ALL NAMED, NONE OF WHICH IS A PASS:
      * the artifact ABSENT -- `repro` has never been run to completion on this tree, so the
        second measurement was never TAKEN. Absence is not agreement.
      * a pinned key ABSENT from the artifact -- the writer's row moved, so the pin can see a gap
        its own shape would otherwise hide.
      * a value that differs -- the two runs DID differ, or the writer's shape moved.

    **AND THE FOURTH STATE, WHICH IS THE ONE THAT LIES: A WITNESS NOBODY RE-TOOK.** The three
    above are all about CONTENT, so all three are silent about TIME, and a file written on any
    past day answers them exactly as one written a minute ago. MEASURED 2026-10-18: this
    artifact was dated Oct 17 01:50 and this function returned `[]` -- a four-day-old file
    satisfying a pin as though the second measurement had been taken, which it had not. The
    `REPRO_SUBSTRATE` arm closes that, using the comparison `gates/corpusverdict-gate.py`
    already makes for the summary. `cmd_repro` refusing its bound is what makes the arm
    necessary: a refusal leaves the OLD artifact in place, so without this row the worst
    outcome of a refusal is that the previous success keeps reading as one.
    """
    if not (D / REPRO_ARTIFACT).exists():
        return [f"{REPRO_ARTIFACT} ABSENT -- the SECOND MEASUREMENT was never taken, so the "
                "denominator for `repro-rc` is 0 runs rather than 2. Run `checks/differ.py repro` "
                "to take it. `PINS` above stays green on one run and says nothing about this."]
    got = dict(ln.split("=", 1) for ln in text(REPRO_ARTIFACT).splitlines() if "=" in ln)
    bad = [f"{k}={v} (expected {REPRO_PINS[k]}, from {REPRO_ARTIFACT})" for k, v in got.items()
           if k in REPRO_PINS and v != REPRO_PINS[k]] \
        + [f"{k} ABSENT from {REPRO_ARTIFACT}" for k in REPRO_PINS if k not in got]
    live = substrate_digest()
    if REPRO_SUBSTRATE not in got:
        bad.append(f"{REPRO_SUBSTRATE} ABSENT from {REPRO_ARTIFACT} -- a witness that names no "
                   "bytes is a measurement with no subject, which is `substrate_bad()`'s own rule "
                   "for a summary and applies here unchanged. RE-TAKE it with "
                   "`checks/differ.py repro`; never hand-edit a value into it")
    elif got[REPRO_SUBSTRATE] != live:
        bad.append(f"{REPRO_SUBSTRATE}={got[REPRO_SUBSTRATE][:12]} but the live substrate is "
                   f"{live[:12]} -- this witness describes a tree that NO LONGER EXISTS, so the "
                   f"`repro-rc=rc=0` beside it is a true statement about bytes nobody is shipping")
    return bad


def artefacts_ok():
    """THE ARTEFACTS THEMSELVES, not the summary about them.

    A gate that reads the summary trusts that the summary and the files were written at the
    same time by the same attempt, and they were not when a step can fail. So this counts the
    SHAPE of every artifact: no artifact may be empty, and no diff REPORT may be a single
    `rc=` line -- the 0-row failure shape, and two of them compared equal. `*.err` files are
    legitimately empty and are excluded: a rule that flags a correct file is a rule that
    always fails, and then it is not a rule.

    **THE POPULATION IS `declared()`, NOT A GLOB.** This is the finding, and it was measured
    before it was fixed. The first version globbed `*.txt`, and a glob is a set of names this
    file chooses, so the day those names move the guard inspects NOTHING and reports NOTHING.
    MEASURED 2026-10-05 by renaming one extension with nothing else changed:

        population      findings
        live              53
        renamed to .rows    0     <- the guard stopped existing, and said so by succeeding
        no files at all     0     <- so it was never a guard; the rename only found it

    while `check_oracle()` reported `[] -- PIN INTACT` throughout, because a sha256 over an
    oracle's bytes says nothing about which names that oracle reads. So the guard now NAMES its
    population: `MISSING` for a declared artifact that is absent -- which is exactly the state a
    rename produces -- and `UNEXPECTED` for something no command writes, which is the stale
    residue `cmd_run` prunes and which only a name-aware check can see.

    **THE `MISSING` ARM IS `declared()` MINUS `REPRO_LITERALS`, AND THAT IS NOT A LOOSENING.**
    This runs immediately after a `cmd_run`, and `D0-repro.txt` is written by a DIFFERENT command
    one run later, so demanding it here is demanding a file the command that just ran cannot
    produce -- a `MISSING` that never clears, which is the guard reporting red forever and being
    ignored, which is worse than the guard not existing. It is NOT excused: `repro_bad()` reads it
    and reports it ABSENT, which is the honest complaint at the honest time.
    """
    # `present` IS A DIRECTORY WALK, NOT THE `*.txt` GLOB THIS USED TO BE. It was the last arm of
    # this function still answering with a suffix set, and that made `UNEXPECTED` and the
    # `EMPTY`/`ONE-LINE` arms weaker than the function's own docstring claims: a stale artifact
    # with ANY other extension was invisible to them, while `MISSING` -- the arm everyone reads --
    # had already moved to `declared()`. **ONE POPULATION, ONE MECHANISM.** A glob is a set of names
    # this file chooses, so the day the extension moves the guard inspects nothing and reports
    # nothing, which is the same finding as `LIVE_UNITS` and `ORACLE_WORD`.
    #
    # `*.txt.err` IS EXCLUDED, and that is the DECLARED CONVENTION rather than an extension set:
    # `snap()` already reads the population as `declared()` PLUS the `.err` beside each artifact, so
    # an `.err` is derived from a declared name and is not an undeclared artifact. MEASURED
    # 2026-10-15 on the live run: 242 files, of which 176 are this population and 66 are `.err`;
    # `D.glob("*.txt")` reads **the same 176**, and a walk-based `UNEXPECTED` returns **0** against
    # the live tree -- so this is a correctness gain at ZERO current cost, not a re-baseline.
    present = {p.name for p in D.iterdir() if p.is_file() and not p.name.endswith(".err")}
    here = present & declared()
    run_writes = declared() - {f"{n}.txt" for n in REPRO_LITERALS}
    return [f"MISSING {n}" for n in sorted(run_writes - present)] \
        + [f"UNEXPECTED {n}" for n in sorted(present - declared())] \
        + [f"EMPTY {relpath(D / n)}" for n in sorted(here) if not (D / n).stat().st_size] \
        + [f"ONE-LINE {relpath(D / n)}" for n in sorted(here)
           if n.startswith(REPORTS) and one_line(n)]


# ---- the plants --------------------------------------------------------------------------
# FOUR PLANTS, AND BOTH HALVES OF EACH. A check that only proves it can fire is half a check --
# two gates in this project failed the other half in OPPOSITE directions, one because it never
# refused and one because it reported DID-NOT-REFUSE for a CORRECT refusal that exited before it
# could print the value asserted. **EVERY VALUE IS PRINTED BEFORE THE EXIT**, for the second of
# those two.
#
# PLANT 3 IS THE ONE NOBODY ASKED FOR AND IT IS THE POINT: **CHANGE A VALUE IN THE ARTIFACTS
# WITHOUT CHANGING THE SUMMARY ROW, AND THE CHECK MUST GO RED.** If it does not, the row is a
# label. This is the only plant that can distinguish "the row is right" from "the row is present".
#
# THE FIXTURE IS THE LIVE BYTES, COPIED, never a retyped row: a retyped fixture agrees with the
# reader by construction, and one prior instrument in this project shipped a `satisfied` plant that
# passed on its first run because its field regex was `^`-anchored and read ZERO values. And no
# plant writes into `runs/graphcmp/D` -- a plant that mutates the state under test measures the
# other units, not itself.
# THE PLANT NAMES ARE A DECLARATION AND NOT A REGEX OVER THE SENTENCES, so `plant --name N`
# selects by the key each check carries rather than by a substring of prose that a reword
# would silently break. **A NAME THAT IS NOT IN IT IS `REFUSED` (3) AND NEVER `PASS`**: a
# plant that does not exist measured nothing, and the five-state vocabulary (`gates/
# gatekit.py:60`) has a word for that and it is not `PASS`.
PLANT_NAMES = ("1", "2", "3", "4", "5", "6", "7", "8", "9", "10")


def report_plants(checks, only=None) -> int:
    """THE PLANTS, PRINTED. One line per check, and the count at the end.

    A plant that selected nothing is `SKIP` and never `PASS`: it ran, it selected nothing,
    and it measured nothing.
    """
    checks = [c for c in checks if only is None or c[0].startswith(f"{only}:")]
    print("PLANTS -- both halves of each, over COPIES; no `bend`, no write into runs/graphcmp/D")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
    bad = sum(1 for c in checks if not c[1])
    if not checks:
        # IT RAN, IT SELECTED NOTHING, AND IT MEASURED NOTHING. `0 of 0` with a green word is
        # the "compared nothing reads as agreement" failure wearing a pin.
        print(f"PLANTS: plant {only!r} SELECTED NO CHECK -- NOT RUN")
        return gatekit().SKIP
    print(f"PLANTS: {'GREEN' if not bad else 'RED'} ({len(checks) - bad}/{len(checks)})")
    return 1 if bad else 0


# THE ONE GRAPH A PLANT ADDS, AS A TEXT EDIT ON A COPY OF THE CORPUS'S OWN GENERATOR.
# **IT IS NOT READ FROM `git show HEAD:`** -- an arm that reads HEAD plants nothing the moment
# HEAD carries the fix, which is how one unit's plant scored green under `--falsify` on
# 2026-10-22. The edit is APPENDED, so it cannot collide with the generator's own text, and
# the graph it adds is never CALLED -- only NAMED, which is what moves the population's
# identity.
PLANTED_GRAPH_SRC = b'''

def g_planted():
  """A PLANT, AND IT IS NOT IN THE CORPUS."""
  return g_matmul()


GRAPHS["planted"] = g_planted
'''


def population_plants() -> list[tuple[str, bool, str]]:
    """PLANTS 9 AND 10 -- THE POPULATION, AND THE COUNTS DERIVED FROM IT.

    **SELF-CONTAINED: EVERY ARM IS A TEXT EDIT ON A COPY, AND NO LIVE ARTEFACT IS READ.**
    That is the lesson from 2026-10-22: one unit's arm read `git show HEAD:`, so it planted
    NOTHING the moment HEAD carried the defect's fix, scored green under `--falsify`, and had
    to be rewritten. So the corpus's generator is COPIED and EDITED here, and the artefact is
    SYNTHESISED here -- neither is read from the tree's history and neither is the live run.

    PLANT 9 is the PROTECTION AGAINST "A GRAPH WAS ADDED AND NOT RE-DECIDED": the population
    is a CONTENT PIN, so a graph that joins the corpus moves it, and a graph that joins
    without the pin moving MUST GO RED. PLANT 10 is the protection against a DERIVED
    EXPECTATION THAT IS NEVER COMPARED: the run's own `graphs=` row is checked against the
    DISCOVERED corpus, and a disagreement MUST FAIL.
    """
    checks = []
    # PLANT 9 -- THE POPULATION PIN. THE COPY IS A TEXT EDIT, never a read of HEAD.
    live = population_digest()
    with tempfile.TemporaryDirectory() as td:
        mutated = Path(td) / "graphcmp.py"
        mutated.write_bytes((ROOT / GCMP).read_bytes() + PLANTED_GRAPH_SRC)
        planted = population_digest(mutated)
    # THE ARTEFACT IS SYNTHESISED FROM THE PIN TABLE AND THE PRECONDITION ROWS, so it is
    # COMPLETE and GREEN -- and then one row at a time is made to disagree with the tree.
    global D
    keep_dir = D
    try:
        with tempfile.TemporaryDirectory() as td:
            D = Path(td).resolve()
            body = dict(PINS)
            body.update(dict(ln.split("=", 1) for ln in precondition_rows()))
            body["substrate-start"] = body["substrate-end"] = substrate_digest()

            def summary(**over):
                (D / "D0-run-summary.txt").write_text(
                    "".join(f"{k}={over.get(k, v)}\n" for k, v in body.items()))

            summary()
            green = unhealthy()
            summary(graphs=str(len(corpus()) + 1))
            red_count = unhealthy()
            summary(population=planted)
            red_pop = unhealthy()
    finally:
        D = keep_dir
    # PLANT 9 -- ***a graph added to the corpus's list WITHOUT the population pin moving MUST
    # GO RED***, AND THE PIN IS A CONTENT PIN OVER THE GRAPH LIST'S OWN NAMES AND BYTES.
    # THREE HALVES: the LIVE tree is green (or the plant proves nothing); the PLANTED
    # population's identity is not the pin, so the pin reds; and a RUN over the planted
    # population is red END TO END, through the health check every reader uses.
    checks.append(("9: ***a graph added to the corpus's list WITHOUT the population pin moving "
                   "MUST GO RED*** -- and the pin is a CONTENT pin over the graph list's own "
                   "names and bytes",
                   live == POPULATION_PIN and not green and bool(population_bad(planted))
                   and bool(red_pop),
                   f"live={live[:12]} pin={POPULATION_PIN[:12]} planted={planted[:12]} -> "
                   f"{population_bad(planted) or '[]'}; a run over it -> {red_pop or '[]'}"))
    # PLANT 10 -- ***the artefact's counts disagreeing with the DISCOVERED population MUST
    # FAIL***. A derived expectation that is never compared is not an expectation.
    checks.append(("10: ***the artefact's counts disagreeing with the DISCOVERED population "
                   "MUST FAIL*** -- a derived expectation that is never compared is not an "
                   "expectation",
                   not green and any("graphs" in b for b in red_count),
                   f"green={green or '[]'} planted graphs={len(corpus()) + 1} -> {red_count or '[]'}"))
    return checks


def plant(only=None):
    global D
    if only is not None and only not in PLANT_NAMES:
        print(f"plant: no such plant {only!r}; have {list(PLANT_NAMES)}")
        return gatekit().REFUSED
    # PLANTS 9 AND 10 ARE SELF-CONTAINED -- they build their own copies and read NO live
    # artefact -- so they can be asked for on their own, and so a tree with no run on disk can
    # still be asked whether the POPULATION is pinned and whether the DERIVED COUNTS are
    # compared. The other eight need the live artefacts, so they are not reachable from here.
    if only in ("9", "10"):
        return report_plants(population_plants(), only)
    live = D
    kv = dict(ln.split("=", 1) for ln in text("D0-run-summary.txt").splitlines() if "=" in ln)
    checks = []
    with tempfile.TemporaryDirectory() as td:
        D = Path(td).resolve()
        try:
            for p in sorted(live.glob("*.txt")):
                shutil.copy2(p, D / p.name)
            rows = dict(ln.split("=", 1) for ln in precondition_rows())
            # PLANT 1 -- THE PIN SATISFIED. Must be CLEAN, or nothing below means anything: a
            # check that cannot pass is not a check.
            checks.append(("1: the rows `differ.py` derives from the artifacts agree with those "
                           "same artifacts -- the CLAIM and the WITNESSES",
                           not preconditions_bad(kv | rows), f"rows={rows}"))
            # PLANT 2 -- THE PIN MOVED, in the SUMMARY.
            checks.append(("2: a summary row that contradicts ENV is caught",
                           bool(preconditions_bad(kv | rows | {"noopt": "1"})),
                           f"noopt=1 -> {preconditions_bad(kv | rows | {'noopt': '1'})}"))
            # PLANT 3 -- ***THE ARTIFACTS MOVE AND THE ROW DOES NOT.*** The device in one wire
            # file is rewritten; the summary is untouched.
            wire = D / "D2-canon-py-lin.txt"
            keep = wire.read_bytes()
            wire.write_bytes(keep.replace(b"SGLOBAL,sCPU", b"SGLOBAL,sMETAL"))
            try:
                moved = preconditions_bad(kv | rows)
            finally:
                wire.write_bytes(keep)
            checks.append(("3: ***AN ARTIFACT CHANGED WITH THE ROW UNCHANGED MUST GO RED*** -- the "
                           "one plant that separates a CLAIM from a LABEL",
                           bool(moved), f"dev=CPU row, sMETAL artifact -> {moved}"))
            # PLANT 4 -- THE ROWS ABSENT. `checks/env-precond.py --check` refused today for exactly
            # this, and a check that reports nothing when its input is missing is a printer.
            # `kv` IS THE SUMMARY, and the summary CARRIES the rows, so the absence the plant
            # claims to test has to be built: strip the four ROW_KEYS and require a complaint
            # for each. Passing `kv` whole is a plant that can never fire (MEASURED: 0 of 4).
            absent = {k: v for k, v in kv.items() if k not in ROW_KEYS}
            checks.append(("4: no rows at all is a REFUSAL, never a pass",
                           len(preconditions_bad(absent)) == len(ROW_KEYS),
                           f"{len(preconditions_bad(absent))} complaint(s) for {len(ROW_KEYS)} "
                           f"absent row(s)"))
            # PLANT 5 -- ***THE WITNESS NOBODY RE-TOOK.*** `repro_bad()` is the only thing that
            # can tell a fresh witness from a four-day-old one, and before `REPRO_SUBSTRATE`
            # existed it could not: MEASURED 2026-10-18, it returned `[]` over an Oct-17 file.
            # ALL THREE HALVES, because a comparator that says STALE for anything is as
            # worthless as one that never says it -- `gates/corpusverdict-gate.py:103-117`
            # states that as the reason its own control plants TWO digests and the identical one.
            witness = D / REPRO_ARTIFACT
            keep = witness.read_text() if witness.exists() else None
            pins = "".join(f"{k}={v}\n" for k, v in REPRO_PINS.items())
            try:
                witness.write_text(pins + f"{REPRO_SUBSTRATE}={'0' * 64}\n")
                stale = [b for b in repro_bad() if REPRO_SUBSTRATE in b]
                witness.write_text(pins + f"{REPRO_SUBSTRATE}={substrate_digest()}\n")
                fresh = [b for b in repro_bad() if REPRO_SUBSTRATE in b]
                witness.write_text(pins)
                norow = [b for b in repro_bad() if REPRO_SUBSTRATE in b]
            finally:
                if keep is None:
                    witness.unlink(missing_ok=True)
                else:
                    witness.write_text(keep)
            checks.append(("5: ***a witness nobody re-took must NOT read as a measurement*** -- "
                           "stale digest reds, live digest is silent, absent row reds",
                           len(stale) == 1 and not fresh and len(norow) == 1,
                           f"stale={len(stale)} live={len(fresh)} row-absent={len(norow)}"))
            # PLANTS 6 AND 7 -- CAUSE 3, AND THEY ARE OPPOSITE PLANTS ON THE SAME QUESTION.
            # `byte-identical` used to compare a TOPOSORT POSITION against a HASH-CONS INDEX,
            # so 14 of 34 graphs were called byte-different for being interned in a different
            # order. The canonical form (`canon_rows`) answers that. A claim that a new form
            # removes a class of false difference needs BOTH halves: one plant that must MOVE
            # the verdict (a real content change is not swallowed) and one that must NOT (a
            # pure renumbering still compares equal, or the "removal" is a mask).
            # THE SUBJECT IS DISCOVERED, NOT NAMED, and it is discovered BY CANONICALISING THE RAW
            # ARTIFACTS rather than by reading the canonical-form artifacts -- so this plant
            # tests the FUNCTION and not the presence of a file the run happens to have
            # written. The population is exactly the class the fix is for: raw-different and
            # canonical-equal. It is EMPTY if the fix did anything else, and an empty
            # population here is a FAILURE, not a pass.
            gap = []
            for g in corpus():
                pa, pb = D / f"D2-canon-py-{g}.txt", D / f"D2-canon-bend-{g}.txt"
                if not (pa.exists() and pb.exists()) or pa.read_bytes() == pb.read_bytes():
                    continue
                ca, wa = canon_body(pa.read_bytes())
                cb, wb = canon_body(pb.read_bytes())
                if ca and cb and ca == cb:
                    gap.append(g)
            if not gap:
                checks.append(("6+7: CAUSE 3 -- the canonical form must remove the "
                               "numbering-only differences and nothing else",
                               False, "no graph is raw-different and canonical-equal, so "
                                      "there is nothing to plant and the claim is untested"))
            else:
                name = gap[0]
                src = [ln for ln in (D / f"D2-canon-bend-{name}.txt").read_text().splitlines()
                       if ln.strip()]
                body = canon_body(("\n".join(src) + "\n").encode())[0]

                def planted(rows, kind):
                    """The bend side re-emitted after ONE edit. Pure; writes nothing.

                    `number` is a ROTATION of the id set applied to the node id AND to every
                    `src` reference, and a bijection is the entire point: renumbering "by
                    first appearance" is not one -- the id field and the references are
                    consumed in different orders, so a reference can be handed a number some
                    other node then claims and the result is a dangling reference that reads
                    as a graph defect."""
                    n = len(rows)
                    rot = {i: (i + 3) % n + 1 for i in range(1, n + 1)}
                    out = []
                    for ln in rows:
                        f = unchunk(ln)
                        if kind == "content" and f[1] == "CONST":
                            f[1] = "AFTER"
                        if kind == "number":
                            f[0] = CANON_REF.sub(lambda m: f"i{rot[int(m.group(1))]}", f[0])
                            f[7] = CANON_REF.sub(lambda m: f"i{rot[int(m.group(1))]}", f[7])
                        out.append(" ".join(f"{len(x)}:{x}" for x in f))
                    return ("\n".join(out) + "\n").encode()

                moved_c = canon_body(planted(src, "content"))[0] != body
                same_c = canon_body(planted(src, "number"))[0] == body
                ok_num, why_num = canon_bijection(canon_body(planted(src, "number"))[0]
                                                  .decode().splitlines())
                checks.append(("6: CAUSE 3 -- ***a CONTENT change must MOVE the canonical "
                               "verdict***, or the form is a mask and not a canonicalisation",
                               moved_c, f"{name}: canonical BYTE-IDENTICAL -> DIFFERS = "
                                        f"{moved_c}"))
                checks.append(("7: CAUSE 3 -- ***a pure RENUMBERING must NOT move it***, and "
                               "the renumbering must be a bijection (ids 1..n each once, every "
                               "reference resolving)", same_c and ok_num,
                               f"{name}: canonical BYTE-IDENTICAL -> BYTE-IDENTICAL = {same_c}; "
                               f"bijection = {ok_num} ({why_num})"))
            # PLANT 8 -- CAUSE 1. A REFUSAL MUST CARRY ITS NAME INTO THE ROW A READER READS.
            # MEASURED 2026-10-18T18:04Z: `D1-verdicts.txt` printed `loop: VERDICT=
            # EXPECTED=AGREE` while the artifact beside it was a one-line `rc=2` and its `.err`
            # named the cause. A refusal that only exists in a `.err` is invisible to every
            # consumer of the summary, and the graph it belongs to reads as an empty verdict.
            rows_txt = (D / "D1-verdicts.txt").read_text() if (D / "D1-verdicts.txt").exists() else ""
            bare = [ln for ln in rows_txt.splitlines()
                    if "VERDICT= " in ln or ln.rstrip().endswith("VERDICT=")]
            named = [ln for ln in rows_txt.splitlines() if ": REFUSED -- " in ln]
            refused_now = [g for g in corpus() if not verdict(f"D1-graph-{g}.txt")]
            named_ok = all(any(ln.startswith(f"{g}: REFUSED -- ") and
                               first_line(f"D1-graph-{g}.txt") in ln for ln in named)
                           for g in refused_now)
            checks.append(("8: CAUSE 1 -- ***a REFUSED graph is named in D1-verdicts.txt with "
                           "its artifact's own text***, and no row has an empty verdict cell",
                           named_ok and not bare and len(named) == len(refused_now),
                           f"refused={refused_now} named={len(named)} empty-verdict-rows={bare}"))
            # PLANTS 9 AND 10 -- THE POPULATION. Self-contained, so they run here too.
            checks += population_plants()
        finally:
            D = live
    return report_plants(checks, only)
    return report_plants(checks, only)


@contextlib.contextmanager
def redirected(path):
    """THE ARTEFACT DIRECTORY, FOR THE DURATION OF ONE COMMAND.

    **THE CORPUS IS A SINGLETON, AND A SINGLETON NEEDS A WAY TO BE EXERCISED WITHOUT BEING
    THE ONE.**  `GRAPHCMP_ARTIFACTS` names the directory the corpus writes, so a run can be
    pointed at a scratch directory instead of the tree's evidence.  It exists for two
    reasons that are the same reason: a gate that MEASURES the corpus must not be able to
    overwrite the corpus, and a plant that proves two runs exclude each other must not
    destroy 319 files of evidence to do it.

    **THE SAVE/RESTORE SHAPE IS NOT COSMETIC.**  `checks/runs-artifacts.py` derives the
    artifact directory from `checks/differ.py`'s OWN SOURCE by resolving its module-level
    bindings (`_env`), and it reads the LAST binding of `D` it finds.  A redirect that did
    not restore `D` would leave that resolver reading an empty path, and the 14 readers of
    `runs/graphcmp/D` would silently become readers of NOTHING -- a clean zero from a
    broken instrument, which is that file's own named failure mode.  `plant()` above keeps
    the same shape for the same reason."""
    global D
    live = D
    D = Path(path).resolve()
    try:
        yield D
    finally:
        D = live


def one_run(wait=9) -> int:
    """ONE `run`, IN THIS PROCESS.

    **THIS USED TO BE A SUBPROCESS, AND THE CORPUS LOCK IS WHY IT IS NOT.**  `run` holds the
    corpus lock, and the lock is held by the process that WRITES the artifacts -- so a `run` in
    a CHILD would be a second writer, and the only ways out are a re-entrancy rule that any
    second `differ.py` could forge, or a parent-death check that a killed parent fails.  One
    process, one writer, one lock.  MEASURED 2026-10-23: the child's two streams were
    `DEVNULL`, so they are captured here and RE-EMITTED ONLY WHEN THE RUN FAILED -- a refusal
    that exists only in a swallowed stream is a refusal nobody can read, and the run's own
    summary names the artefacts anyway."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = cmd_run(None, wait)
        except Exception as e:  # a child that died used to be a non-zero rc, and nothing more
            rc = 1
            err.write(f"run raised {type(e).__name__}: {e}\n")
    if rc:
        sys.stderr.write(err.getvalue())
    return rc


def clean_run(label, wait):
    """Run until healthy, BOUNDED, and say how long the bound was. Record the DEFECT below.

    **THE BOUND IS `wait` ATTEMPTS AND IT WAS NEVER MISSING -- WHAT WAS MISSING IS THE
    ARITHMETIC.** MEASURED 2026-10-18: `for attempt in range(wait)` has always been the bound
    and `wait` defaults to 9, so this was NEVER AN INFINITE LOOP, and "a timer bounding an
    infinite loop" misdescribes it. But `ready(wait)` is called once PER ATTEMPT and itself
    probes `wait` times with `time.sleep(60)` between probes, so the ceiling is
    `60*(wait-1) + 30` seconds of pure SLEEP per ATTEMPT -- `9 * (540 + 30) = 4590 s` of sleep
    for ONE `clean_run` at the default `wait=9`, and `cmd_repro` calls it TWICE. (That is
    SLEEP; the runs themselves add more, so it is a floor on the ceiling and never an
    overstatement.) `checks/bounded.py:209-212` already
    measured the consequence: "`differ.py repro` ran 184 s on 2026-10-13 and was killed at 900 s
    on 2026-10-14 with `out=0B err=0B`".
    **A BOUND NO CALLER CAN COMPUTE IS INDISTINGUISHABLE FROM NO BOUND**, so a watchdog stopping
    it looks exactly like a hang, and the observed "600 s" was a CALLER's budget meeting a
    4590 s ceiling rather than a timeout policy. So the refusal now reports the wall clock and
    the attempt count: a bounded refusal is answerable, and `TIMED-OUT` stops meaning the same
    thing as `REFUSED`. The ceiling is not reduced here -- `--seconds` remains the budget, and
    this only makes the two distinguishable.

    `ready() && <run>` is the SHELL's order and it is wrong, and this is where it lives. When
    the substrate never settles, `ready` is False, the runner is never executed, and
    `unhealthy()` then reads the PREVIOUS run's summary -- so a gate reports the last good
    run's health while waiting for a run that did not happen. Reported, not fixed: fixing it
    means running unconditionally and letting the pins judge the result, which changes what a
    `repro` refusal MEANS and is not this function's decision to make.
    **MEASURED 2026-10-18, so the first half of that is no longer hypothetical on this tree**:
    `settled()` returned `ALL PROOFS CHECK` and `gates/corpusverdict-gate.py` recorded
    `bend ... rc=0`, so the run DOES execute and `unhealthy()` reads THIS attempt.

    **THIS USED TO END "Reported, not fixed -- see DIFFPY.md", AND `DIFFPY.md` EXISTED
    NOWHERE IN THE REPO** (MEASURED: 0 files; the pointer was carried by `checks/README.md:93`
    and by a ticked `- [x] Report.` box at `.agents/TODO.md:12108`). A pointer to a document
    that is not there is not a dangling path, it is a claim that a fix was reported SOMEWHERE
    and the somewhere is absent -- so the finding now lives HERE, in the function that has the
    defect, where a reader of the defect finds it. `checks/README.md:93` still points at the
    missing file; that pointer is NOT MINE and is reported, not edited.
    """
    t0 = time.monotonic()
    for attempt in range(wait):
        if ready(wait):
            one_run(wait)
        if bad := unhealthy():
            print(f"# {label}: run {attempt + 1} summary was NOT healthy -- waiting: "
                  + "; ".join(bad))
        elif bad := artefacts_ok():
            print(f"# {label}: summary healthy but {len(bad)} malformed artefact(s): "
                  + " ".join(bad[:2]))
        else:
            print(f"# {label}: healthy run, and every artefact has a body")
            return True
        time.sleep(30)
    print(f"# {label}: no healthy run in {wait} attempts, {time.monotonic() - t0:.0f}s spent "
          f"(ceiling {wait * (60 * (wait - 1) + 30)}s of sleep, i.e. {wait} attempts x "
          f"{60 * (wait - 1) + 30}s) -- this is NOT a measurement")
    return False


def gatekit():
    """`gates/gatekit.py` BY PATH, because it OWNS the five exits and nothing else does.
    `gatekit.py:60` declares `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` and
    `gates/gatesweep.py:134` maps an exit through it, so a number retyped here would be a
    second copy of a table that HAS A GENERATOR -- the defect `artefacts_ok()` and
    `checks/no-txt.py` were each fixed for, one level apart. `gatekit` imports nothing from
    this file, so loading it here closes no cycle.

    **IT IS RETURNED AS THE MODULE, NOT UNPACKED, AND THAT IS THE SECOND HALF OF THE FIX.** The
    first version of this returned `VERDICT` -- a `code -> word` table -- and the call site wrote
    `verdicts()[3]`, which yields the WORD `'REFUSED'`. Returning that as the exit status sends
    the string to `sys.exit`, which prints it and returns **1**: the fix for an unnamed exit code
    would have turned `repro` into a silent `FAIL`, i.e. indistinguishable from "the two runs
    DIFFER". So the table is read in the direction the caller needs and the code is named by
    `gatekit` itself.
    """
    spec = importlib.util.spec_from_file_location("gatekit", ROOT / "gates/gatekit.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def cmd_repro(a):
    with tempfile.TemporaryDirectory() as tmp:
        shots = {}
        for label, run_label in (("A", "run A"), ("B", "run B")):
            if not clean_run(run_label, a.wait):
                # MEASURED 2026-10-18: this was `return 2`, and 2 IS A CODE NO VOCABULARY NAMES.
                # `gates/gatekit.py:94-101` already measured that consequence for another gate --
                # "a gate returning 2 ... made `VERDICT[code]` raise `KeyError: 2`, so the runner
                # that aggregated it CRASHED while reporting on a gate that had answered". So the
                # exit was not a sixth verdict, it was a TRAPDOOR, and a caller reading `$?` had
                # nothing to read.
                #
                # IT IS `REFUSED` AND NOT `FAIL`, and the difference is the whole claim. `FAIL` (1)
                # is what `cmd_repro` returns below when it DID take both runs and they differed --
                # a measurement. Reaching this line means a healthy run to SNAPSHOT was absent, so
                # the second measurement was never taken and nothing was determined about
                # reproducibility: a precondition was absent, which is `REFUSED`'s own definition.
                # Not `SKIP` (the run executed, repeatedly, and produced verdicts), not `DEAD` (it
                # emitted complaints), not 0 (a gate that exits 0 having measured nothing is worse
                # than no gate).
                gk = gatekit()
                print(f"REPRO: {gk.VERDICT[gk.REFUSED]} -- no healthy {run_label} in "
                      f"{a.wait} attempt(s), so the SECOND MEASUREMENT WAS NOT TAKEN. "
                      f"`{REPRO_ARTIFACT}` is whatever it was BEFORE this command started, and "
                      f"`repro_bad()` will now say so: it refuses a witness that names no bytes "
                      f"or names bytes that have moved.")
                return gk.REFUSED
            path = Path(tmp) / f"gcrepro{label}.sha"
            with path.open("w") as f:
                snap(f)
            shots[label] = path
            print(f"# run {label} done: {len(path.read_text().splitlines())} files snapshotted")
        n = len(shots["B"].read_text().splitlines())
        # `repro` IS the tree's only INDEPENDENT measurement. Every one of `PINS` reads
        # `D0-run-summary.txt`, so `17/17 green` is ONE RUN'S 17 ROWS AND THE DENOMINATOR IS 1, NOT 17
        # (`.agents/slop/pinindep/REPORT.md`: 17 of 17 pins read the same file; the true
        # independent-measurement count is 10). This two-run byte comparison is the cheapest way to make
        # the denominator 2 -- and it was COMPUTED AND THROWN AWAY: printed, never persisted. So write it,
        # as `key=value`, where a pin can read it BESIDE the summary it makes non-independent.
        d10 = d10_sha(shots["B"].read_text())
        base = f"{REPRO_SUBSTRATE}={substrate_digest()}\n"
        if shots["A"].read_bytes() == shots["B"].read_bytes():
            write(REPRO_ARTIFACT, f"repro-files={n}\nrepro-identical={n}\nrepro-rc=rc=0\n"
                                  f"d10-transcript={d10}\n" + base)
            print(f"REPRO: {n} of {n} files identical across two clean runs "
                  "(sha256 over non-blank lines)")
            return 0
        write(REPRO_ARTIFACT, f"repro-files={n}\nrepro-identical=0\nrepro-rc=rc=1\n"
                              f"d10-transcript={d10}\n" + base)
        print(f"REPRO: NOT IDENTICAL -- {n} files:")
        sys.stdout.write(byte_diff(shots["A"], shots["B"], 40))

        # **A REPRODUCIBILITY FAILURE THAT CANNOT BE DIAGNOSED AFTER THE FACT IS NOT A FINDING, IT IS
        # A NOTIFICATION.** MEASURED 2026-10-20: two clean runs differed in EXACTLY ONE of 310 files,
        # and the differing BYTES were a pair of sha256s IN THE SNAPSHOT -- so the output named the
        # ARTIFACT but not the ROW, and both snapshots lived in a `TemporaryDirectory` deleted on exit.
        # **THE DIFFERENCE WAS THEREFORE UNRECOVERABLE**, and its cause turned out to be that
        # `substrate-head` -- THE ROW ADDED TO MAKE A RUN COMPARABLE TO A TREE -- RECORDS WHICH COMMIT
        # MEASURED IT, SO TWO RUNS OF THE SAME TREE ARE INCOMPARABLE WHILE HEAD MOVES. The artifact
        # below names the differing ROWS, so the next failure is a FINDING.
        for _line in byte_diff(shots["A"], shots["B"], 40).splitlines():
            if not (_line.startswith("<") and "  runs/" in _line):
                continue
            _rel = _line.split("  ", 1)[1].strip()
            _live = D / Path(_rel).name
            if not _live.is_file():
                continue
            _a = Path(tmp) / ("runA-" + _live.name)
            shutil.copy2(_live, _a)
            _d = byte_diff(_a, _live, 40)
            write(REPRO_DIFF_ARTIFACT, f"# {_rel}\n" + _d)
            print(f"  differing rows of {_rel} written to {REPRO_DIFF_ARTIFACT}:")
            sys.stdout.write("".join(f"     {ln}\n" for ln in _d.splitlines()))
        return 1


def main():
    ap = argparse.ArgumentParser(
        prog="checks/differ.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    run_p = sub.add_parser("run", help="write every graphcmp artifact under runs/graphcmp/D")
    # **AND THE RUN GETS THE SAME BOUND `repro` HAS.** `cmd_run` WAITS FOR THE BEND LANE TO
    # SETTLE BEFORE IT WRITES ANYTHING, AND THE BOUND IS HOW MANY PROBES THAT WAIT MAY
    # TAKE -- SO THE BOUND BELONGS IN THE PARSER, NEXT TO `repro`'s, NOT INSIDE THE
    # FUNCTION. IT IS A POSITIONAL WITH A DEFAULT, SO EVERY EXISTING INVOCATION
    # (`differ.py run`) IS UNCHANGED.
    run_p.add_argument("wait", nargs="?", type=int, default=9,
                       help="substrate probes before the run writes anything (the same bound "
                            "`repro` uses; default 9)")
    r = sub.add_parser("repro", help="two clean runs of `run`, byte-compared (the gate)")
    r.add_argument("wait", nargs="?", type=int, default=9,
                   help="attempts per run, and 60s substrate probes per attempt "
                        "(the shell's WAIT; default 9)")
    sub.add_parser("snap", help="print the snapshot both gates are built from")
    p = sub.add_parser("plant", help="assert the plants on a COPY of the artifacts")
    # NO `choices=`: argparse would exit 2 on a name that is not a plant, and 2 IS A CODE NO
    # VOCABULARY NAMES (`checks/differ.py`'s own `cmd_repro` comment says so and is why that
    # exit became 3). An unknown plant is REFUSED by `plant()` itself, which is the shape
    # that keeps the five exits in one place.
    p.add_argument("--name", default=None, metavar="N",
                   help=f"run ONE plant of {list(PLANT_NAMES)}; an unknown name is REFUSED "
                        f"(exit 3), never PASS")
    a = ap.parse_args()
    # THE ARTEFACT DIRECTORY IS A PARAMETER, and this is where it is read.  The corpus is a
    # SINGLETON, so a run that must not touch `runs/graphcmp/D` needs somewhere else to write:
    # a gate that MEASURES the corpus, and a plant that proves two runs exclude each other,
    # both need that, and neither may destroy 319 files of evidence to get it.
    if override := os.environ.get("GRAPHCMP_ARTIFACTS"):
        with redirected(override):
            return command(a)
    return command(a)


def command(a):
    """THE COMMANDS, AND EVERY ONE OF THEM IS UNDER THE CORPUS LOCK.

    **THE LOCK IS TAKEN BEFORE ANYTHING ELSE, INCLUDING `D.mkdir` AND THE STALE-TEMP SWEEP**,
    because a refusal that has already created or pruned the artifact directory is not a
    refusal.  `run` and `repro` WRITE `runs/graphcmp/D`; `plant` copies it and `snap` hashes
    it, and a reader that reads a directory a writer is halfway through is the same corruption
    as two writers, so all four are serialised."""
    if refusal := take_lock():
        print(refusal, file=sys.stderr)
        return gatekit().REFUSED
    try:
        return _command(a)
    finally:
        drop_lock()


def _command(a):
    if a.cmd == "plant":
        return plant(a.name)
    D.mkdir(parents=True, exist_ok=True)
    drift = check_oracle()
    if drift:
        # Refuse, loudly, and name the file. A driver that diffs against a moved oracle would
        # report a verdict about a comparison nobody is making.
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it from the commit that froze it, or re-freeze it deliberately and "
              "update ORACLE_PIN here -- do not delete the pin.", file=sys.stderr)
        return 3
    if a.cmd == "snap":
        # `snap` READS the run that is already on disk, so it is guarded. `run` and `repro` are NOT:
        # they WRITE that directory, so requiring them to find it fresh would be the remedy refusing
        # to be the remedy -- `ARTIFACTS-STALE` would be answered by the one command that clears it.
        # `checks/runs-artifacts.py` LOADED BY PATH (`checks/sweep.py:101` does the same) so there
        # is one vocabulary for ABSENT / EMPTY / STALE / FRESH and no second copy of it.
        spec = importlib.util.spec_from_file_location(
            "runs_artifacts", str(ROOT / "checks/runs-artifacts.py"))
        ra = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ra)
        if code := ra.require(ra.GRAPH_D, root=str(ROOT), label="differ snap",
                              remedy=ra.REGENERATE):
            return code
        snap()
        return 0
    return {"run": cmd_run, "repro": cmd_repro}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
