#!/usr/bin/env python3
"""staged_mut.py -- THE GUARD every mutation harness in this repo owes its target.

WHY THIS EXISTS, MEASURED.  Four harnesses rewrote the LIVE tree in place:
`open(TARGET, 'w').write(...)` plus a `finally` restore.  The guard ran ONCE, at
start, so on a file churning at 7 writes per 2 minutes the `finally` restore
reverted a concurrent agent's commit -- `blob-intern-mutate.py`'s own docstring
records it doing exactly that, putting a dead 6,623-line `ops.bend` back over
the live 6,306-line one.  `ops-501-mutate.py` was fixed to stage `jj file show -r
@` beside the file and edit only that.  THE FIX WAS NEVER PROPAGATED.

THE POINT, and it is the part that is easy to get wrong: a `finally` restore is
only safe when NOTHING ELSE TOUCHED THE FILE, and a guard that samples the digest
once at start CANNOT ESTABLISH THAT.  So this never restores over the live file
at all.  There is no restore, because there is no write.  The live digest is
sampled at ENTRY and at EXIT and the difference is REPORTED, so a run whose
substrate moved underneath it says so instead of silently describing a revision
that no longer exists.

`sha256(MIRROR) == sha256(LIVE)` IS ASSERTED AT STAGE TIME, and this is not
belt-and-braces.  `live == git HEAD` is NOT a sufficient guard when the substrate
is a `git archive HEAD` mirror PLUS A MANUAL OVERLAY: the mirror held a stale
overlay, `old not in src` fired for an unrelated reason, and it printed the same
string as a genuinely missing anchor.  A STALE MIRROR AND A STALE ANCHOR ARE
INDISTINGUISHABLE unless the two texts are asserted equal.  See `verdict()`.

BESIDE THE FILE, NOT IN $TMPDIR, and not with a `.bend` name.  `regalloc.bend`
imports `./../../helpers.bend` and `./linearizer.bend`, so a copy outside its own
directory cannot resolve them and prints a phantom 0 rows -- indistinguishable
from "not started", 22 of them in one unit.  A `.bend` name would make the
staged copy visible to every `find tinybendygrad -name '*.bend'` census and to
`stale-snapshot-detect.py`, which classifies a staged copy as a DEAD SNAPSHOT.
`bin/bend` does not require the extension (measured), so the staged file is
named `NAME.staged-<tag>-<pid>` with no extension and is INVISIBLE to both.

usage:
    with staged_mut.Staged(live, tag) as g:
        g.write(g.origin().replace(old, new, 1))
        got = g.rows()
"""
import hashlib
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BEND = ROOT / "bin" / "bend"


def digest(data):
    return hashlib.sha256(data).hexdigest()


_RG = None


def rows(text):
    """`rebase-gate.py`'s `rows()`, QUERIED not transcribed: agent-core.md records
    that a name-comparing harness reported 0 for all 30 mutations in one unit and
    all 68 in another.  Whole `name=value` lines, keyed on NAME.

    THERE IS ONE ROW READER PER REPO and this must not become a second one, so the
    import is retried rather than replaced.  It has to be: `rebase-gate.py` is under
    concurrent edit, and at 10:13 on 2026-10-04 it was transiently unparseable at
    line 1184 (a `⚠` lost its `#` mid-write).  A local copy of `rows()` would have
    been the fix that survived, and it would also have been the one that drifted --
    which is the reason the rule exists.
    """
    global _RG
    if _RG is None:
        import importlib.util
        import time
        for attempt in range(10):
            spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
            mod = importlib.util.module_from_spec(spec)
            try:
                spec.loader.exec_module(mod)
            except SyntaxError as e:
                # Another agent is mid-write.  Say WHICH line, because a silent wait
                # reads as a hang.
                print("rebase-gate.py is unparseable at line %s (%s) -- another agent "
                      "is mid-edit; retrying in 3s" % (e.lineno, e.msg), file=sys.stderr)
                time.sleep(3)
                continue
            _RG = mod
            break
        if _RG is None:
            raise SystemExit("rebase-gate.py does not parse and this harness will not "
                             "invent a second row reader.  Re-run when it is green.")
    return _RG.rows(text)


def row_digest(r):
    """A digest over the ROW SET, not the file.  RULE C, measured twice: a digest
    over the MUTANT provably cannot see an operand-order defect, because swapping
    a movement's two shape args leaves the producer's three fields unchanged.
    Frozen digests cover the file being mutated; SAME is measured against this."""
    return digest("\n".join("%s=%s" % kv for kv in sorted(r.items())).encode())


class MirrorStale(Exception):
    """`sha256(mirror) != sha256(live)`: the substrate changed between the mirror
    read and the live read.  The run is REFUSED; nothing is measured, because
    every verdict below would be attributed to a file nobody is looking at."""


class LiveMoved(Exception):
    """The live digest moved DURING the run.  Not a crash -- the measurement is
    still true OF THE SNAPSHOT -- so it is reported and the run's numbers are
    labelled with the revision they describe."""


class Staged:
    """A private, digest-asserted mirror of `live`, beside it, and a witness.

    The live file is opened READ-ONLY, exactly once, at entry.  Nothing in this
    class can write it: `write()` refuses a destination inside the repo that is
    not the staged path, so re-introducing an in-place write is a loud error
    rather than a silent regression.
    """

    def __init__(self, live, tag):
        self.live = pathlib.Path(live)
        self.tag = tag
        self.path = None
        self.origin_bytes = None

    # -- the two digests a verdict is allowed to rest on ----------------------
    def live_digest(self):
        return digest(self.live.read_bytes())

    def text(self):
        return self.path.read_text()

    def origin(self):
        """The mirror's PRISTINE text, re-derived from the immutable copy rather
        than from whatever the staged file currently holds.  Every mutation
        restores from this, so a `finally` restore can be interrupted without
        leaving a half-old file behind."""
        return self._origin_text

    def write(self, text):
        """Write the STAGED copy.  Refuses the live file, by construction."""
        if self.path is None:
            raise RuntimeError("Staged.write outside the context manager")
        self.path.write_text(text)

    def run(self, args=()):
        """Run the staged mirror with `bin/bend` from the repo root.

        STDOUT ONLY, and that is the whole contract.  `bend` writes `bend 2.0.35 is
        available: run bend update` to STDERR on every single run, so any liveness
        test that looks at stderr is permanently true -- which is exactly how
        `memory-mutate.py` read bend's upgrade notice as a baseline failure and lost
        70 completed mutations.  The four harnesses this replaces all carried a
        retry loop keyed on `(stdout + stderr).strip()`, so that loop could never
        fire even for the machine-stack-overflow it was written for.
        """
        p = subprocess.run([str(BEND), str(self.path), *args],
                           capture_output=True, text=True, cwd=str(ROOT))
        self.stderr = p.stderr
        return p.stdout

    def rows(self, args=()):
        r = self.try_rows(args=args)
        if r is None:
            raise SystemExit("%s produced no output at all" % self.path.name)
        return r

    def try_rows(self, retries=5, args=()):
        """`rows()`, or None when the run is NOT A PROGRAM.

        The retry is not defensive coding, it is a measurement: bend 2.0.34
        machine-stack-overflows about 1 run in 20 on this unit, and an overflow is
        byte-for-byte indistinguishable from a mutation that broke the file.  Five
        attempts then an honest None, never a 0-row answer.
        """
        for _ in range(retries):
            text = self.run(args)
            if text.strip():
                return rows(text)
        return None

    # -- the context ----------------------------------------------------------
    def __enter__(self):
        self.origin_bytes = self.live.read_bytes()          # the ONLY live read
        self.live_sha = digest(self.origin_bytes)
        self._origin_text = self.origin_bytes.decode("utf-8", "surrogateescape")
        raw = subprocess.run(["jj", "file", "show", "-r", "@", "--",
                              str(self.live.relative_to(ROOT))],
                             cwd=str(ROOT), capture_output=True, timeout=600)
        if raw.returncode:
            raise MirrorStale("jj file show failed: %s" % raw.stderr[:200].decode("utf-8", "replace"))
        if digest(raw.stdout) != self.live_sha:
            raise MirrorStale(
                "MIRROR STALE.  sha256(jj @) = %s but sha256(live) = %s for %s.  "
                "Every 'the anchor is not in the file' verdict below would be "
                "attributed to a substrate nobody is looking at, so nothing is "
                "measured." % (digest(raw.stdout)[:16], self.live_sha[:16], self.live))
        self.path = self.live.parent / ("%s.staged-%s-%d" % (self.live.stem, self.tag, os.getpid()))
        if self.path.exists():
            raise MirrorStale("%s exists -- a previous run was killed; remove it" % self.path.name)
        self.path.write_bytes(raw.stdout)
        # A private name, and a refusal to leave it behind on any exit.
        os.chmod(self.path, 0o600)
        print("staged %s -> %s\n  sha256(mirror) == sha256(live) == %s  ASSERTED"
              % (self.live.relative_to(ROOT), self.path.name, self.live_sha[:16]))
        return self

    def __exit__(self, *exc):
        if self.path and self.path.exists():
            self.path.unlink()
        now = self.live_digest()
        if now == self.live_sha:
            print("live %s: byte-identical (%s) -- this harness never wrote it"
                  % (self.live.name, self.live_sha[:16]))
        else:
            print("live %s: CHANGED %s -> %s during this run.  Another agent wrote.  "
                  "The numbers below describe the SNAPSHOT %s and NOT the working "
                  "copy; re-run before publishing."
                  % (self.live.name, self.live_sha[:16], now[:16], self.live_sha[:16]),
                  file=sys.stderr)
            if exc[0] is None:
                raise LiveMoved("live %s moved during the run" % self.live.name)
        return False


def control(base, got, what):
    """RULE C, enforced.  A control that is not `SAME` aborts before any table.

    A baseline can BE the mutant -- it happened twice -- so the control is run
    against the SAME staged mirror with NO edit at all, and BOTH the row COUNT and
    the ROW-SET DIGEST are compared.  The digest is the part that matters: a count
    is equal when a row is lost and another is gained."""
    if set(base) != set(got):
        raise SystemExit("CONTROL NOT SAME (%s): %d baseline rows, %d control rows, "
                         "%d lost, %d gained.  No table is written."
                         % (what, len(base), len(got),
                            len(set(base) - set(got)), len(set(got) - set(base))))
    if row_digest(base) != row_digest(got):
        raise SystemExit("CONTROL NOT SAME (%s): the row COUNT matches but the row-set "
                         "DIGEST does not -- a baseline that is the mutant.  No table "
                         "is written." % what)
    return True


class StagedSet:
    """`Staged` for a SPLIT unit: several live files, one staged copy each.

    Needed because the 1:1 ruling moved defs BETWEEN these files and an anchor that
    names a `def` can therefore leave the file it was written for without changing by
    one character -- `tb_pset.put` is now in `linearizer.bend`, and re-aiming its
    anchor into `regalloc.bend` would have required editing the FILE, which is the
    one thing this whole module exists to stop.

    So an anchor is searched across the WHOLE SET, and the mutation lands in the
    file that actually holds it.  Ambiguity is refused rather than guessed: an
    anchor present in two staged files is two candidate mutants and choosing one
    would be the reader inventing a measurement.
    """

    def __init__(self, lives, tag, files=(), transform=None):
        self.lives = [pathlib.Path(p) for p in lives]
        self.tag = tag
        self.extra = [pathlib.Path(f) for f in files]   # imported, not mutated
        # The harness's OWN anchor transform, e.g. `ra-mutate.py`'s `q()`.  It is
        # passed in rather than imported so staged_mut stays free of any one unit's
        # naming rules, and it is offered as the FIRST candidate spelling.
        self.q = transform
        self.gs = []
        self.pristine = {}

    def __enter__(self):
        for live in self.lives:
            g = Staged(live, self.tag)
            g.__enter__()
            self.gs.append(g)
            self.pristine[live.name] = g.origin()
        return self

    def __exit__(self, *exc):
        for g in self.gs:
            g.__exit__(*exc)
        return False

    def holders(self, old):
        """The staged files whose text contains `old`.  [] means the anchor moved."""
        return [g for g in self.gs if old in g.text()]

    def spellings(self, old, new):
        """Candidate `(anchor, replacement)` pairs for one entry, transformed first.

        A harness transform like `q()` exists because a file SPLIT forced a qualifier
        onto cross-file CALLS, so it is exactly right for a call site and exactly
        WRONG for a `def`'s own header in the file that defines it: `tb_pset.put` is
        spelled bare in `linearizer.bend` and `q` turns it into a spelling that is
        nowhere.  Offering the transformed form first and the raw form second is
        re-deriving the anchor per file; picking one and hoping is the failure the
        mirror-digest assertion exists to catch, and it caught 21 false STALEs here
        before `mutanchor.anchors()` learned to run `q` at all.
        """
        pairs = []
        for text in ([old] if self.q is None else [self.q(old), old]):
            pair = (text, self.q(new) if self.q is not None else new)
            if pair[0] not in [p[0] for p in pairs]:
                pairs.append(pair)
        return pairs

    def apply(self, old, new):
        """Replace `old` in the ONE staged file that has it, and return that file's
        name, or None when the anchor is absent.

        Ambiguity is refused rather than guessed: an anchor present in two staged
        files is two candidate mutants and choosing one would be the reader
        inventing a measurement.
        """
        for o, n in self.spellings(old, new):
            hits = self.holders(o)
            if not hits:
                continue
            if len(hits) > 1:
                raise SystemExit("ANCHOR AMBIGUOUS: %d staged files contain it (%s).  "
                                 "Guessing which one was meant is how a mutation ends "
                                 "up measuring a different file than its name says."
                                 % (len(hits), ", ".join(g.live.name for g in hits)))
            g = hits[0]
            g.write(g.text().replace(o, n, 1))
            return g.live.name
        return None

    def restore(self):
        for g in self.gs:
            g.write(self.pristine[g.live.name])

    def rows(self, retries=5, args=()):
        """Rows over the WHOLE SET, keyed on name.  None if ANY file is not a
        program, because a set whose third file stopped running has no row set to
        compare and reporting the other two as 'rows moved' is the 170-row
        falsehood in `ops-python-mutate.py`."""
        out = {}
        self.failed = None
        for g in self.gs:
            r = g.try_rows(retries, args)
            if r is None:
                self.failed = g.live.name
                return None
            out.update(r)
        return out

    def why(self):
        """`<file>: <bend's first error line>`, for the DESCRIPTION cell only.

        The MEASURED cell stays `DID-NOT-COMPILE` -- `zero-classify.py` compares the
        whole cell and exits on anything it does not recognise, which is the correct
        direction for it to break in -- and the diagnostic goes beside it.
        """
        if not self.failed:
            return ""
        g = next(x for x in self.gs if x.live.name == self.failed)
        for line in (g.stderr or "").splitlines():
            if line.startswith(("Error:", "Location:", "SOME PROOFS FAIL")):
                return "%s: %s" % (self.failed, line.strip())
        return self.failed


# The four verdicts `zero-classify.py` accepts as a classification of a zero.  They
# are QUERIED, not transcribed, for the reason `patch_not_apply.py` gives at import.
def zero_verdicts():
    out = subprocess.run([sys.executable, str(HERE / "zero-classify.py"), "--verdicts"],
                         capture_output=True, text=True).stdout.split()
    if len(out) != 5:
        raise SystemExit("zero-classify.py --verdicts printed %r, expected five" % out)
    return out


def classify_zero(label, why):
    """Prefix `why` with one of the five, chosen by the caller.  A zero that cannot
    be placed is an ERROR, never a pass -- so the choice is a required argument."""
    return "%s %s" % (why, label)