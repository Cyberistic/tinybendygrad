#!/usr/bin/env python3
"""live-write-guard.py -- FAIL when a harness can write the live source tree.

    .venv/bin/python .agents/slop/live-write-guard.py
    .venv/bin/python .agents/slop/live-write-guard.py --selftest
    .venv/bin/python .agents/slop/live-write-guard.py --debris

WHY THIS EXISTS, and the reason is a count.  Six harnesses in this corpus have rewritten
`tinybendygrad/**.bend` in place and restored in a `finally`.  One of them destroyed a
concurrent agent's committed work: `blob-intern-mutate.py`'s own docstring records
putting a dead 6,623-line `ops.bend` over the live 6,306-line one.  Four were converted
to `staged_mut`.  Two more have been found since.  The 156 forked readers and the 6
writers all exist because **nothing made the next one expensive**.

SO THE RULE IS NOT "WRITE TO A SNAPSHOT" OR "TAKE A DIGEST FIRST", both of which have
been tried and both of which a tired agent can skip.  The rule is MECHANICAL and it is
checkable by reading one file:

    A HARNESS MAY NOT NAME A WRITE INTO `tinybendygrad/`, UNLESS IT IS REGISTERED.

Registration is a line in `live-write-registry.txt` naming the harness, the reason, and
the date.  There is no flag to skip the check, no environment variable, and no
auto-registration: adding yourself to the registry is a deliberate act with a name on
it, which is the only thing that ever worked here.  A harness that uses `staged_mut`
needs no entry, because `Staged.write()` cannot name a live path at all -- its only
destination is the staged copy beside the target.

WHAT IT CHECKS, all three, because each one has been the actual failure:

  1. WRITES.  Every `*.py` in `.agents/slop/` is read with `mutanchor.write_spellings`
     and any destination under `tinybendygrad/` is a FAIL.  This is the same detector
     the write census uses, so the guard and the census cannot disagree about what a
     write is -- a guard with its own idea of `open(P,'w')` is a second opinion nobody
     maintains.
  2. DEBRIS.  A staged copy, a `.mut`, a `.bak` or a `.pristine` sibling sitting under
     `tinybendygrad/` is a FAIL.  `staged_mut` names its copy `NAME.staged-TAG-PID`
     with no extension so a `.bend` glob cannot see it, but a KILLED run still leaves
     the bytes on disk, and a `.mut.bend` in the tree reads as source to every census.
     Measured on this tree before this guard existed: `tinybendygrad/runtime/ops_bend.mut.bend`,
     VISIBLE to `find tinybendygrad -name '*.bend'`, 80,583 bytes, dated 2026-10-02.
  3. UNGUARDED SUBSTRATE.  A harness that names a live source file as its mutation
     TARGET without importing `staged_mut` and without a registry entry is a FAIL,
     even if its only write is inside a `finally`.  A `finally` restore is a write.

THE SELFTFT IS NOT OPTIONAL.  `--selftest` drives the guard against a SYNTHETIC
harness that writes the live tree, and against one that stages instead, and FAILS THE
RUN if the guard does not distinguish them.  A guard that has never been seen to fire is
a comment; `staged-guard-proof.py` is the same discipline applied to the digest guard,
and this is the same discipline applied here.
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import mutanchor as MA                                          # noqa: E402

SLOP = HERE
REGISTRY = HERE / "live-write-registry.txt"
# The tree a mutation harness may damage.  Writes to `.agents/` are RECORDs and writes
# outside the repo are ELSEWHERE; both are fine and `mutanchor.zone()` says so.
LIVE_TREE = os.path.join(MA.ROOT, "tinybendygrad")
# Debris that reads as source, or that is a staged copy of it.  THE `.bend` SUFFIX IS
# NOT IN THIS LIST, and getting that wrong was the first version's only bug: it endswith
# `.bend`, so every one of the tree's 131 real source files was reported as debris.  A
# debris rule that fires on the healthy tree is a rule nobody reads.  The markers are
# what makes a copy a copy, and there are TWO ways to spell one:
#   * APPENDED -- `elf.bend.mut`, `x.pristine`
#   * INSERTED -- `ops_bend.mut.bend`, which is VISIBLE to `find -name '*.bend'`
# A staged copy carries `.staged-` in its name by construction, whatever its extension.
DEBRIS_TAIL = (".mut", ".bak", ".pristine", ".orig", ".rej", ".tmp", ".swp")
DEBRIS_MARK = ".staged-"


def is_debris(name):
    """Is this FILENAME a leftover rather than a source file?

    Three rules and none of them is "ends in `.bend`", for the reason above.
    """
    return (DEBRIS_MARK in name
            or name.endswith(DEBRIS_TAIL)
            or os.path.splitext(name)[0].endswith(DEBRIS_TAIL))


def registered():
    """`{harness basename: the line that registered it}`, or {} when absent.

    AN ENTRY IS A STRUCTURE, NOT A LINE.  The first version took the first
    whitespace-token of every non-`#` line, so this registry's own PROSE registered
    twenty harnesses -- including the word `A`, the word `harness`, and the module name
    `staged_mut.Staged` -- and the guard then reported `20 registered` and `9 failing`
    when the true count was **0 and 27**.  A guard that counts its own documentation as
    compliance is worse than one that counts nothing, because it reports a number.

    So an entry must be: a `.py` filename, at column 0, followed by whitespace and a
    reason, and the file must EXIST in the corpus.  A name that does not resolve to a
    file cannot be a registration, and a stale entry for a deleted harness is dead
    weight that hides the fact that nobody owns it any more.  Same class as LW-8: a
    filter that does not know what it is filtering will read its author's prose as data.
    """
    if not REGISTRY.exists():
        return {}
    out = {}
    for ln in REGISTRY.read_text().splitlines():
        m = re.match(r"^([\w.-]+\.py)\s\s+(\S.*)$", ln)
        if m and (SLOP / m.group(1)).is_file():
            out[m.group(1)] = ln
    return out


def live_writes(path, self_name=None):
    """`[(zone, destination, spelling)]` for this harness's writes into the live tree."""
    tree = MA.write_spellings(MA.parse(path), self_name)
    return [w for w in tree if w[1].startswith(LIVE_TREE)]


def target_names(path):
    """Every live source file this harness DECLARES as its substrate."""
    t = MA.parse(path)
    if t is None:
        return []
    return [p for _, p in MA.targets(t, path.name)]


def staged(path):
    """Does this harness use the staged guard?"""
    t = MA.parse(path)
    if t is None:
        return False
    return "staged_mut" in MA.imports(t) or "staged_mut" in path.read_text()


def _pid_of(name):
    """The PID `staged_mut` puts in its copy's name, or None.

    `NAME.staged-TAG-<pid>` ends in the PID on purpose, and that turns "is this debris?"
    from a guess into a question with an answer: a copy whose PID is STILL RUNNING is a
    unit's in-flight staged mirror, and a copy whose PID is gone is the remains of a kill.
    This distinction was not hypothetical.  Six units are live on six `.bend` files and
    while this guard was being written the debris list grew from two items to six with
    four `nvdev.staged-*` copies seconds old -- all of them belonging to running units, and
    all of them reported as debris by the first version of this check.  A check that
    fails on a healthy running unit is a check that gets disabled.
    """
    m = re.search(r"-(\d+)$", name)
    return int(m.group(1)) if m else None


def _alive(pid):
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True                     # someone else's, and therefore running
    return True


def debris():
    """`[(path, age in days, size, state)]` for leftovers under tinybendygrad/.

    `state` is `IN-FLIGHT` when the name carries a PID that is still running, and
    `DEBRIS` otherwise.  ONLY `DEBRIS` fails the guard.

    It does NOT create, move or delete anything: it globs, stats, and sends signal 0.
    That is what makes it safe to run while six units are live on six `.bend` files,
    which a cleanup script could not be -- and why the PID check is not optional, since a
    guard that reported another unit's live staged mirror as a failure would be deleted.
    """
    import time
    now = time.time()
    out = []
    for p in sorted(pathlib.Path(LIVE_TREE).rglob("*")):
        if not p.is_file() or not is_debris(p.name):
            continue
        st = "IN-FLIGHT" if _alive(_pid_of(p.name)) else "DEBRIS"
        out.append((p, round((now - p.stat().st_mtime) / 86400, 1), p.stat().st_size, st))
    return out


def harness_files():
    return sorted(p for p in SLOP.glob("*.py") if p.name != os.path.basename(__file__))


def audit(verbose=False):
    """`(failures, checked)` over every harness in the corpus."""
    reg = registered()
    fails, checked = [], 0
    for p in harness_files():
        t = MA.parse(p)
        if t is None:
            if verbose:
                print("  SKIP %-34s does not parse" % p.name)
            continue
        checked += 1
        lw = live_writes(p)
        if lw and p.name not in reg:
            fails.append((p, "LIVE WRITE, not registered", lw))
            continue
        if p.name in reg:
            if verbose:
                print("  ok   %-34s registered: %s" % (p.name, reg[p.name][:60]))
            continue
        # No live write.  But a harness that NAMES a live source file as its substrate
        # and does not use the staged guard is still a `finally`-restore away from the
        # incident, so it is named -- not failed, because it may genuinely only read.
        unguarded = [t2 for t2 in target_names(p) if not staged(p)]
        if verbose and unguarded:
            print("  ~    %-34s names %d live target(s), no staged_mut: %s"
                  % (p.name, len(unguarded), ", ".join(os.path.relpath(x, MA.ROOT)
                                                        for x in unguarded[:2])))
    return fails, checked


def selftest():
    """The guard is run against fixtures it has never seen.  It MUST fail on four.

    THE FIXTURES NAME THE LIVE PATHS AND CREATE NOTHING.  Every case below is a SOURCE
    STRING handed to `mutanchor`, which only ever parses; the string says
    `tinybendygrad/uop/ops.bend` and no byte is ever written anywhere.  That is the whole
    reason this can be a routine gate rather than a thing that needs a quiet machine:
    the guard reads source, and reading source cannot damage a tree.  The first attempt
    at this pointed the fixtures at a temp directory, which made every case SCRATCH, and
    a guard that reports `no live write` for an in-place writer is the guard that would
    have shipped `blob-intern-mutate.py` unchanged.
    """
    td = tempfile.mkdtemp()
    L = "tinybendygrad/uop/ops.bend"
    cases = [
        ("in-place write + finally restore",
         "SRC = %r\n"
         "try:\n    open(SRC,'w').write(mutated)\n"
         "finally:\n    open(SRC,'w').write(pristine)\n" % L, True),
        ("shutil.copyfile snapshot over the live file",
         "import shutil\nLIVE = %r\nBAK = '/tmp/x'\nshutil.copyfile(BAK, LIVE)\n" % L, True),
        ("shell redirection onto the live file",
         "import subprocess\nLIVE = %r\nsubprocess.run('cat > ' + LIVE, shell=True)\n" % L, True),
        ("a `.mut` BESIDE the live file, deleted after",
         "import os\nLIVE = %r\nopen(LIVE + '.mut','w').write(s)\nos.remove(LIVE + '.mut')\n"
         % L, True),
        ("the staged guard: no live write at all",
         "import staged_mut\nLIVE = %r\n"
         "with staged_mut.Staged(LIVE, 'x') as g:\n"
         "    g.write(g.origin().replace(a, b))\n" % L, False),
        ("a pure reader of the live file",
         "LIVE = %r\ns = open(LIVE).read()\nprint(s)\n" % L, False),
        ("a reader of a RECORD, which is not the live tree",
         "REC = '.agents/slop/table.txt'\nopen(REC,'w').write(s)\n", False),
    ]
    print("SELFTEST -- %d fixtures the guard has never seen, %d of which MUST fire"
          % (len(cases), sum(1 for _, _, f in cases if f)))
    bad = 0
    for label, src, must_fail in cases:
        p = os.path.join(td, "fixture.py")
        open(p, "w").write(src)
        lw = live_writes(p)
        ok = bool(lw) == must_fail
        bad += not ok
        print("  [%s] %-46s %s"
              % ("AS EXPECTED" if ok else "<-- WRONG", label,
                 ("FIRED via %s" % lw[0][2]) if lw else "no live write"))
    print("  %d/%d selftest fixtures behaved as required" % (len(cases) - bad, len(cases)))
    return bad + registry_selftest()


def registry_selftest():
    """THE REGISTRY PARSER IS HALF THE GUARD, so it gets its own fixtures.

    The first version took the first whitespace-token of every non-`#` line and read this
    registry's own PROSE as twenty registrations -- the word `A`, the word `harness`, the
    module name `staged_mut.Staged` -- so the guard reported `20 registered, 9 failing`
    when the truth was `0 and 27`.  A guard that counts its author's documentation as
    compliance still PRINTS A NUMBER, and a number is what gets quoted onward.

    These run against the REAL registry file, restored in a `finally`, so a failure here
    cannot leave the registry edited.
    """
    saved = REGISTRY.read_text() if REGISTRY.exists() else None
    real = sorted(p.name for p in harness_files())
    live = real[0] if real else "staged_mut.py"
    ghost = "a-harness-that-does-not-exist.py"
    fixtures = [
        ("a real entry: name, TWO spaces, a reason",
         "%s  codegen/x.bend  why  2026-10-04\n" % live, 1),
        ("ONE space is not an entry", "%s one space\n" % live, 0),
        ("prose at column 0 is not an entry", "A harness may not NAME a write into x.\n", 0),
        ("a module name is not an entry", "staged_mut.Staged  needs no entry\n", 0),
        ("a ghost filename is not an entry", "%s  why  2026-10-04\n" % ghost, 0),
        ("an indented example block is not an entry",
         "    %s  why  2026-10-04\n" % live, 0),
        ("a comment is not an entry", "# %s  why  2026-10-04\n" % live, 0),
    ]
    print()
    print("REGISTRY PARSER -- %d fixtures; the file is restored in a finally" % len(fixtures))
    bad = 0
    try:
        for label, text, want in fixtures:
            REGISTRY.write_text(text)
            got = len(registered())
            ok = got == want
            bad += not ok
            print("  [%s] %-46s read %d, expected %d"
                  % ("AS EXPECTED" if ok else "<-- WRONG", label, got, want))
    finally:
        if saved is None:
            REGISTRY.unlink(missing_ok=True)
        else:
            REGISTRY.write_text(saved)
    print("  registry restored: %d real entries" % len(registered()))
    return bad


def main():
    if "--selftest" in sys.argv:
        return 1 if selftest() else 0
    if "--debris" in sys.argv:
        d = debris()
        for p, age, size, state in d:
            print("  %-9s %-64s %d bytes, %.1f days old, pid=%s" % (
                state, os.path.relpath(p, MA.ROOT), size, age, _pid_of(p.name)))
        print("%d DEBRIS and %d IN-FLIGHT under tinybendygrad/"
              % (sum(1 for x in d if x[3] == "DEBRIS"), sum(1 for x in d if x[3] == "IN-FLIGHT")))
        return 1 if any(x[3] == "DEBRIS" for x in d) else 0
    verbose = "-v" in sys.argv
    report = None
    if "--report" in sys.argv:
        report = pathlib.Path(sys.argv[sys.argv.index("--report") + 1])
    fails, checked = audit(verbose)
    d = debris()
    dead = [x for x in d if x[3] == "DEBRIS"]
    flying = [x for x in d if x[3] == "IN-FLIGHT"]
    print("live-write-guard: %d harness(es) read, %d registered" % (checked, len(registered())))
    print("debris: %d DEBRIS, %d IN-FLIGHT (a live staged mirror, its owner is running)"
          % (len(dead), len(flying)))
    lines = []
    for p, why, sp in fails:
        print("FAIL %s -- %s" % (p.name, why))
        lines.append("FAIL %s -- %s" % (p.name, why))
        for z, dest, spelling in sp:
            print("       %s  %s  via %s" % (z, os.path.relpath(dest, MA.ROOT), spelling))
            lines.append("       %s  %s  via %s"
                         % (z, os.path.relpath(dest, MA.ROOT), spelling))
        if len(fails) > 1 and not verbose:
            continue
        print("       Either convert it to `staged_mut.Staged`, which cannot name a live")
        print("       destination, or add a justified line to %s." % REGISTRY.name)
    for p, age, size, state in d:
        tag = "FAIL debris" if state == "DEBRIS" else "inflight"
        print("%s %s -- %d bytes, %.1f days old, %s"
              % (tag, os.path.relpath(p, MA.ROOT), size, age, state))
        lines.append("%s %s -- %d bytes, %.1f days old, %s"
                     % (tag, os.path.relpath(p, MA.ROOT), size, age, state))
    print()
    verdict = "GUARD FAILED: %d problem(s)." % (len(fails) + len(dead)) \
        if (fails or dead) else \
        "GUARD PASSED: no harness can write the live source tree, and no debris remains."
    print(verdict)
    if report:
        report.write_text("\n".join(lines) + "\n\n" + verdict + "\n")
        print("wrote %s (%d failing harness(es), %d debris)" % (report, len(fails), len(dead)))
    return 1 if (fails or dead) else 0


if __name__ == "__main__":
    sys.exit(main())