"""The mechanical half of a gate: three lanes, row counts, and a diff.

    from gatekit import Gate

A GATE IS A CLAIM, and this module holds only the parts that are the same in every gate so
that a gate FILE is left to hold the parts that differ: which rows exist, which diverge, and
what each divergence's content is PINNED to. Nothing here knows anything about any
particular gate, which is the point -- the policy is per gate and the plumbing is not.

WHY THIS IS PYTHON AND NOT SHELL. A rule now: gates are `.py`. The old shell form had four
defects that were all invisible until something went wrong, and three of them are recorded
in the tree's own history (commit d2cde2f2c, "gate harnesses: four of them LIED"):

  `diff A B && echo MATCHES` under `set -e` does NOT fire on a failing diff, because a command
  that fails inside an `&&` list is part of a compound condition -- so the script exits 0
  having printed a diff.
  `trap 'rm -rf "$OUT"' EXIT` makes the script exit with the STATUS OF `rm`, so a successful
  cleanup turns an earlier failure into exit 0.
  `<( ... )` is a bashism, so under `sh` the script does not parse at all -- and a gate that
  cannot parse is a gate nobody reads.
  `${=SUB}` is zsh-only, so under `sh` the array never expands, the loop body never runs, and
  a hash guard compares "" to "" and reports UNCHANGED.

None of those can happen here: there is no `&&` list guarding an exit, no trap, no process
substitution, and no shell at all. The two policies a shell form made awkward -- a missing
BASELINE and a stale DIVERGES list -- are explicit parameters instead.

WHAT THIS MODULE DELIBERATELY DOES NOT DO. It does not decide whether a gate passes. It
reports a disagreement and a non-zero exit; `main()` in each gate is the only place that
decides anything.
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ART = HERE / "artifacts"
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"

WARM = "ALL PROOFS CHECK"

# `checks/differ.py`'s OWN staging convention, reused rather than reinvented: a staged file is
# dot-named and lives in the artifact directory, so promoting it is a SAME-DIRECTORY atomic
# rename (`differ.py:158,163`) and nothing can observe a half-written file under a name anybody
# looks up. `differ.py:242` clears stale temps at the start of a run for the same reason.
TMP = ".tmp."

# THE FIVE VERDICTS, AS EXITS. `AGENTS.md`: "`SKIP` it could not run, so it measured nothing ·
# `DEAD` it ran and emitted nothing · `REFUSED` a precondition was absent" and "DEAD HAS NO EXIT
# ANYWHERE -- THAT IS THE GAP". It was a gap HERE: every failure in this file exited 1, so a lane
# that emitted nothing and a lane that emitted the WRONG ANSWER were the same number to a caller
# reading `$?`, and `main()` printed `FAILED` for both. 4 is `e2e.py`'s SKIP and 3 is
# `checks/sb-gate.sh`'s REFUSED, so a reader who knows those two recognises 5 as DEAD.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}

# THE FIVE ARE ALL SPELLED. `return SKIP` had no site in THIS file and was reported as a vacant
# slot, which is a claim about a NAME rather than about a CODE PATH: `SKIP` is produced by
# `gates/msgdiff-gate.py` (3 sites) and `checks/wallcheck.py` (as 4), and `run()` below can only
# ever return 0, 1, 3 or 5 -- so the four THIS FILE produces are reachable and 4 arrives from a
# consumer. A constant nothing in this file names is not a constant nothing can produce.


def verdict_of(code):
    """`code` -> the word, and an UNASSIGNED code is a REFUSAL rather than an exception.

    MEASURED, and the reason `gate()`/`main()` no longer index `VERDICT` directly: a gate
    returning `2` -- which 13 files in this tree do on purpose, `USAGE` by `checks/wallcheck.py`'s
    own declaration among them -- made `VERDICT[code]` raise `KeyError: 2`, so the runner that
    aggregated it CRASHED while reporting on a gate that had answered. A mapping that raises on a
    legitimate code is not a vocabulary, it is a trapdoor.

    WHY `REFUSED` AND NOT `DEAD`. `DEAD` is "it ran and emitted nothing" -- a claim about EXECUTION,
    which only something that watched the process can make. A code this table does not define has
    not been shown to have run at all, and `REFUSED` is "a precondition was absent": here, the
    absent precondition is a DEFINITION. So an unassigned code refuses.

    **THIS IS NOT A CRASH, AND THE DISTINCTION IS THE POINT.** A gate that raises, prints a
    traceback and exits 1 is `DEAD` -- it demonstrably ran and demonstrably failed, and
    `.agents/slop/hooks/run.py:112` maps it there deliberately and by name. Folding a traceback
    into "unassigned" would lose the one measurement that separates them; folding an unassigned
    code into `DEAD` claims a run nobody witnessed. Neither is the other.

    `bool` IS A SUBCLASS OF `int`, so `verdict_of(True)` is `FAIL` and `verdict_of(False)` is
    `PASS` -- which is not a bug here but is a trap for a caller that passes a computed flag. It
    is named rather than silently absorbed, so the aliasing is visible at the call site.
    """
    if isinstance(code, bool):  # FIRST: `True in VERDICT` is True, because True == 1
        return f"UNASSIGNED (bool {code} aliases onto {int(code)}, not a verdict)"
    if code in VERDICT:
        return VERDICT[code]
    return f"UNASSIGNED (code {code!r} is not one of the five)"


def charge(code):
    """`code` -> THE EXIT a runner should tally. The additive half, and it never raises.

    An assigned code resolves to itself -- `PASS` stays 0, so **nothing that reads this table
    today changes**, which is the property that makes it landable: 0 of the 46 discovered
    consumers are touched. An unassigned code charges `REFUSED`, for the reason in `verdict_of`.
    A traceback stays `DEAD`, because a caller that saw the traceback has already made that call
    and this function is not given the evidence to overturn it.
    """
    return code if code in VERDICT and not isinstance(code, bool) else REFUSED

# `bend` prints `bend <ver> is available: run bend update` on STDERR on EVERY invocation --
# MEASURED on a fully green `--check-only`, 42 bytes of it -- so "stderr is non-empty" is not
# "bend said something", and a flake guard cannot ask about stderr without asking about THIS.
NOTICE = re.compile(r"^bend \S+ is available: run bend update$")


LANE_ROWS = ".rows"   # the oracle's EXPECTED VALUES, verbatim
LANE_OUT = ".out"     # the two CAPTURED STREAMS, verbatim
LANE_CMP = ".cmp"     # the rows that SURVIVED the exclusion list -- what the diff saw


def _staged(name):
    """The name a run WRITES. `checks/differ.py:158`'s convention, unchanged."""
    return f"{TMP}{name}"


def _said(stream, lines=3):
    """What `bend` SAID, as against what it ANNOUNCED: the stderr lines that are neither blank
    nor the update notice, joined and truncated.

    STDERR IS THE DISCRIMINATOR between the two failures that look identical from stdout and the
    exit status. MEASURED on a driver with a type error in it: `bend --check-only` answers
    `rc=1`, **0 bytes on stdout**, and `SOME PROOFS FAIL / Error: / - expected : a defined name`
    on stderr. `bend`'s machine stack overflow answers no stdout and no error at all. A guard
    that asks only about stdout cannot tell them apart, so it retried a deterministic type error
    25 times and then reported "the stack flake" -- a lie about a file that has a type error in
    it, and 25 wasted runs of a 1.4 GB process.
    """
    said = [l.strip() for l in (stream or "").splitlines()
            if l.strip() and not NOTICE.match(l.strip())]
    return " | ".join(said[:lines])


def output_dir_plant() -> int:
    """THE TWO STATES OF A GATE'S OUTPUT DIRECTORY, IN TOKEN AND EXIT CODE -- no `bend` runs.

        .venv/bin/python gates/wk-cd-gate.py --plant

    A gate OWNS `gates/artifacts/<name>`, and that directory is `.gitignore`d, so its absence is
    not a precondition -- it is created. The only refusal is a directory that CANNOT be created.
    The three states are asserted HERE rather than in each gate because the plumbing is
    `gatekit`'s and a second copy of a plant is a second contract:

      absent   the constructor's `_ensure_dir` CREATES it -> token `OUTPUT-CREATED`, no exception
      present  an existing directory is left as-is        -> token `OUTPUT-PRESENT`, rc 0
      blocked  a FILE sits where the dir must go          -> token `REFUSED, NOT A VERDICT`, rc 3
    """
    global ART
    keep, bad = ART, []
    try:
        with tempfile.TemporaryDirectory() as td:
            ART = Path(td) / "fresh" / "artifacts"
            g = Gate("plant-absent", bend="unused.bend", oracle="unused.py", rows=1)
            hit = g.dir.is_dir()
            print(f"  absent   {'OUTPUT-CREATED' if hit else 'OUTPUT-MISSING'}")
            bad += [] if hit else ["absent: the output directory was not created"]

            ART.mkdir(parents=True, exist_ok=True)
            g = Gate("plant-present", bend="unused.bend", oracle="unused.py", rows=1)
            print(f"  present  OUTPUT-PRESENT  rc={g.dir_rc}")
            bad += [] if g.dir_rc == PASS else [f"present: rc={g.dir_rc}, expected 0"]

            blocker = Path(td) / "blocked"
            blocker.write_text("not a directory\n")
            ART = blocker
            g = Gate("plant-blocked", bend="unused.bend", oracle="unused.py", rows=1)
            print(f"  blocked  REFUSED, NOT A VERDICT  rc={g.dir_rc}")
            bad += [] if g.dir_rc == REFUSED else [f"blocked: rc={g.dir_rc}, expected {REFUSED}"]
    finally:
        ART = keep
    print(f"--plant: {'all three states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def oracle_drift(pins):
    """Every frozen shell oracle's ACTUAL sha against its pin. An empty list means intact.

        gates/gatekit.py:  from gatekit import oracle_drift
        if oracle_drift(ORACLE_PIN): ... exit 2

    WHY IT LIVES HERE AND IS CALLED BY THE GATE, rather than being a check inside `Gate`: the
    question this asks is NOT "is this gate well-formed", it is "is the SHELL still the thing
    the port was diffed against", and only `main()` knows whether a non-intact pin is fatal.
    `checks/substrate.py` carries the same function and the same two-sentence reason; one word
    was previously used for both questions, which is how a drift check became a verdict.

    A pin in a comment is a pin that cannot fail. `checks/differ.py`'s pin WAS correct and WAS a
    comment, and nothing read it. `pins` maps a repo-relative path to a hex sha256.
    """
    root = ROOT
    bad = []
    for rel, want in pins.items():
        p = root / rel
        if not p.is_file():
            bad.append(f"{rel}: MISSING -- the frozen oracle is gone")
            continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != want:
            bad.append(f"{rel}: {got[:16]} != pinned {want[:16]}")
    return bad


def _lines(path):
    return [l for l in path.read_text().splitlines() if l.strip() != ""]


class Gate:
    """One gate: a bend driver, a CPython oracle, a row count, and its divergences.

    bend      path to the .bend driver, relative to the repo root
    oracle    path to the CPython oracle, relative to the repo root
    rows      how many rows each lane emits BEFORE exclusions
    compared  how many after; defaults to `rows`
    diverges  row name -> (ORACLE's line, PORT's line), excluded from the diff and PINNED on
              both sides. A PAIR and not one string, because a divergence is precisely where
              the two sides differ: pinning one string can only ever describe half of it.
    port_only  row names the PORT emits and the ORACLE DELIBERATELY DOES NOT. Excluded from
              the diff like a divergence, but with nothing to pin on the oracle side -- the
              ABSENCE is the claim, and it is the DERIVED ORACLE ROW COUNT that holds it:
              `want = rows - len(port_only)`, so an oracle that grows one of these rows
              is one row too many and fails the count, which is why there is no separate
              assertion of the absence here. MEASURED, not assumed; see the commit.
    pins      extra (lane, row_name) assertions -- that row is PRESENT in that lane -- for
              claims a diff cannot express. Its CONTENT, if it matters, goes in `diverges`.
    warm      "fatal" (default) or "report". THE SHELL'S TWO VERDICT SHAPES, because the two
              gates being ported did NOT agree on this and a port that picks one is a verdict
              change: `mixin-op-gate.sh:22` runs `--check-only` bare under `set -e`, so a COLD
              driver aborts the gate at that line; `beautiful-mnist-gate.sh:29` runs it
              `--check-only || true` and says in its own header that it "does NOT gate on that
              line", so a COLD driver is REPORTED and the lanes are diffed anyway. Same driver,
              same verdict, opposite exit status, and the difference is the shell's.
    """

    def __init__(self, name, *, bend, oracle, rows, compared=None, diverges=None,
                 pins=None, port_only=None, warm="fatal"):
        self.name = name
        # A GATE CLEARS ITS OWN OUTPUT BEFORE ANY CHECK CAN FAIL, NOT AT THE TOP OF `run()`.
        # MEASURED 2026-10-06: `_clear()` sat in `run()`, and **5 of 17 exits are AFTER the lanes write** —
        # plus `gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` call `sys.exit(2)` *before*
        # `GATE.run()` is reached, so 6 artifacts survived a red run BYTE-IDENTICAL. Under this placement
        # both gates go rc=2 with an EMPTY directory.
        #
        # **A CALLER-SIDE REPAIR HAS A CORRECT POSITION AND A PLAUSIBLE WRONG ONE:** wrapped before the
        # first check it is EMPTY, wrapped between the drift check and `run()` it strands 6/6 STALE,
        # because `sys.exit(2)` is two lines above it. **ONLY CONSTRUCTION IS BEFORE EVERY PATH.**
        # THIS SURVIVES AN EARLY EXIT AT MODULE SCOPE, BEFORE `Gate(...)` EVEN EXISTS.
        # A GATE'S INPUTS LIVE BESIDE THE GATE. `.agents/slop/` is being pruned, and a
        # prune took seven of nine driver and oracle files out from under these gates --
        # every one of them went red on "no such file" rather than on a value. A gate whose
        # inputs live somewhere the tree is clearing is a gate with a shelf life.
        self.bend = self._resolve(bend)
        self.oracle = self._resolve(oracle)
        self.rows = rows
        self.compared = compared if compared is not None else rows
        self.diverges = dict(diverges or {})
        self.port_only = list(port_only or [])
        self.pins = list(pins or [])
        self.warm_mode = warm
        # THE WARM CHECK'S OWN STDOUT, kept so a gate can REPRODUCE the shell's whole output
        # rather than a summary of it. `--check-only` prints `ALL PROOFS CHECK` and
        # `Use --verdict for mathematical validity.` on stdout and both `.sh` gates let those
        # two lines through to the reader, so dropping them makes the artifact differ from the
        # oracle on the green path for no reason a reader could name.
        self.warm_out = ""
        self.dir = ART / name
        self.dir_rc = self._ensure_dir()      # CREATED here, before any module-scope `sys.exit(2)`
        # A GATE CLEARS ITS OWN OUTPUT BEFORE ANY CHECK CAN FAIL, NOT AT THE TOP OF `run()`.
        # MEASURED 2026-10-06: `_clear()` sat in `run()`, AND **5 OF 17 EXITS ARE AFTER THE LANES WRITE** --
        # PLUS `gates/mixin-op-gate.py` AND `gates/beautiful-mnist-gate.py` CALL `sys.exit(2)` *BEFORE*
        # `GATE.run()` IS REACHED, SO **6 ARTIFACTS SURVIVED A RED RUN BYTE-IDENTICAL.** UNDER THIS
        # PLACEMENT BOTH GATES GO rc=2 WITH AN EMPTY DIRECTORY.
        #
        # **A CALLER-SIDE REPAIR HAS A CORRECT POSITION AND A PLAUSIBLE WRONG ONE:** WRAPPED BEFORE THE
        # FIRST CHECK IT IS EMPTY; WRAPPED BETWEEN THE DRIFT CHECK AND `run()` IT STRANDS 6/6 STALE,
        # BECAUSE `sys.exit(2)` IS TWO LINES ABOVE IT. **ONLY CONSTRUCTION IS BEFORE EVERY PATH**, AND IT
        # SURVIVES AN EARLY EXIT AT MODULE SCOPE, BEFORE `Gate(...)` EVEN EXISTS.
        self._clear()

    def _resolve(self, p):
        """beside the gate first, then the repo root, then as given"""
        q = Path(p)
        if q.is_absolute():
            return q
        for base in (HERE, ROOT):
            if (base / q).exists():
                return base / q
        return HERE / q

    # ---- one step, so a failure names the STEP and not the script ------------
    def _say(self, msg):
        print(f"{self.name}: {msg}", file=sys.stderr)

    def _warm(self):
        """`--check-only`'s FIRST LINE, and never its exit status.

        FIRST LINE because an EMPTY FILE typechecks: `substrate-check.sh` MEASURED that
        `bend --check-only` answers `ALL PROOFS CHECK` for a 0-byte file and for one holding
        only a comment, and `helpers.bend` has been truncated to 0 bytes four times, each by
        a unit that then saw green. A gate that trusts the exit status alone would have
        reported a truncated file as warm.
        """
        # RETRIED, and that is not defensive padding. `bend`'s machine stack overflows on
        # roughly 1 run in 20 and prints NOTHING -- no stdout, no error -- which is
        # indistinguishable from "did not start". The lanes were already retried on their
        # row count; the warm check had no retry, so that one flake failed a gate that was
        # green a minute earlier and said only that bend had no first line. Both steps now
        # tolerate the same measured flake, and NEITHER retries a real failure: 25 tries, and
        # a file that is genuinely cold or genuinely empty still fails.
        #
        # WHAT COUNTS AS THE FLAKE IS `_said(stderr)` AND NOT THE EXIT STATUS -- see `_said`.
        # The guard was `not stdout and rc != 0`, which is the flake's shape AND a type error's
        # shape, so a deterministic failure was retried 25 times and then reported AS the flake.
        for _ in range(25):
            out = subprocess.run([str(BEND), str(self.bend), "--check-only"],
                                 capture_output=True, text=True)
            first = (out.stdout or "").splitlines()[:1]
            if first and first[0].strip() == WARM:
                if self.bend.stat().st_size == 0:
                    self._say("the driver is 0 bytes, and an empty file typechecks")
                    return False
                self.warm_out = out.stdout
                return True
            said = _said(out.stderr)
            if not said and not (out.stdout or "").strip():
                continue  # the stack-overflow flake: no output at all
            # REPORTED, THEN ANSWERED IN THE GATE'S OWN SHAPE. `warm="report"` is a ported
            # shell's `|| true`: the run continues and the lanes are still diffed, because
            # `beautiful-mnist-gate.sh:29` says in its own header that a cold driver is not
            # what this gate gates on. Failing here instead would be a VERDICT CHANGE, and it
            # is a change the two shells did not make in the first place.
            self.warm_out = out.stdout
            self._say((f"bend said: {said}" if said
                       else f"--check-only's first line is {first!r}, not {WARM!r}")
                      + f" (rc={out.returncode})"
                      + (" -- REPORTED, not gated on: the shell ran this `|| true`"
                         if self.warm_mode == "report" else ""))
            return self.warm_mode == "report"
        self._say("bend produced no --check-only output in 25 tries (the stack flake)")
        return False

    def _oracle(self):
        r = subprocess.run([str(PY), str(self.oracle)], capture_output=True, text=True)
        if r.returncode != 0:
            self._say(f"the oracle failed rc={r.returncode}: {r.stderr.strip()[:200]}")
            return False
        (self.dir / _staged("py.rows")).write_text(r.stdout)
        return True

    def _lane(self, argv, name):
        """Retried while it emits the wrong ROW COUNT, because `bend`'s machine stack
        overflows on roughly 1 run in 20 and prints ZERO rows -- indistinguishable from
        'did not start'.

        `name` is the PUBLISHED name and the file is staged under it, so a failure names the
        path a reader looks up rather than a temp -- which is also the only way the staged form
        could not leak into a verdict.
        """
        out = self.dir / _staged(name)
        for _ in range(25):
            r = subprocess.run(argv, capture_output=True, text=True)
            if r.returncode == 0 and len(_lines_text(r.stdout)) == self.rows:
                out.write_text(r.stdout)
                return True
            if _said(r.stderr):
                break  # bend NAMED it, so it is not the flake and 24 more tries cannot help
        said = _said(r.stderr)
        self._say(f"lane {name} did not produce {self.rows} rows"
                  + (f" -- {said}" if said else " in 25 tries (the flake)"))
        return False

    def run(self):
        """STAGE EVERY WRITE, AND SETTLE ON EVERY EXIT -- INCLUDING A RAISED ONE.

        THE FAILURE THIS EXISTS TO STOP. A run that failed used to leave the PREVIOUS run's
        `bd.out` exactly where it was, so a diff of `gates/artifacts/<gate>/bd.out` after a RED
        run diffed the last **GREEN** run. Same shape as `bend -o` leaving the previous exe,
        which is how a stage runs a stale binary and prints a plausible number. MEASURED on the
        live tree before this fix: after a red run, 7 of 7 artifacts were byte-identical to the
        previous green run's, and a second red shape left 6 of 7 stale with `py.rows` fresh.

        TWO HALVES, AND NEITHER IS ENOUGH ALONE. `_clear()` empties the directory FIRST, so a run
        that fails with nothing staged ends with an EMPTY directory; promotion by itself would
        leave the previous run's promoted files untouched, which IS the bug. `_settle()` then
        runs in ONE `finally`, so all sixteen `return 1`s below reach it AND so does an exception
        -- seventeen exits in all, counting the one at the bottom. The reasoning this replaces --
        "a failure-path cleanup is sixteen chances to forget one" -- is true per `return` and
        false for one `finally`: this method has seventeen exits and only that block has to know
        which of them were successes.
        """
        ok = False
        try:
            if (rc := self._ensure_dir()) != PASS:
                return rc               # the output directory cannot be created: REFUSED
            self._clear()
            if not self._warm():
                return REFUSED          # the substrate could not be checked at all
            if not self._oracle():
                return REFUSED          # CPython did not run, so nothing was compared
            bd, bn, binp = (self.dir / _staged(n) for n in ("bd.out", "bn.out", "gate.bin"))
            if not self._lane([str(BEND), str(self.bend)], "bd.out"):
                return DEAD             # `bend` ran and emitted no rows to compare
            c = subprocess.run([str(BEND), str(self.bend), "-o", str(binp)],
                               capture_output=True, text=True)
            if c.returncode != 0:
                self._say(f"the native compile failed: {(c.stderr or '').strip()[:200]}")
                return REFUSED          # the compiled lane's precondition, not its answer
            if not self._lane([str(binp)], "bn.out"):
                return DEAD

            lanes = {t: self.dir / _staged(f"{t}{LANE_ROWS if t == 'py' else LANE_OUT}")
                     for t in ("py", "bd", "bn")}
            # DERIVED, NOT DECLARED, AND THIS IS A FIX. The check used to demand `self.rows` of
            # EVERY lane, which makes the documented `port_only` shape UNREACHABLE: a port-only row
            # is by definition absent from the oracle, so the oracle lane is short by exactly
            # `len(port_only)`. `gates/README.md` claim 3 has therefore been describing a shape
            # that could not be constructed. MEASURED on the two gates ported here: `mixin` prints
            # 36 port rows against 32 oracle rows, 4 of them port-only, and the old check rejected
            # that as "py.rows has 32 rows, expected 36". Derived from `port_only` rather than
            # passed in, because a second number that can disagree with the first is a number
            # nobody can check.
            for tag, f in lanes.items():
                want = self.rows - len(self.port_only) if tag == "py" else self.rows
                n = len(_lines(f))
                if n != want:
                    self._say(f"{tag}{LANE_ROWS if tag == 'py' else LANE_OUT} has {n} rows, "
                              f"expected {want}"
                              + (f" ({self.rows} less {len(self.port_only)} port-only)"
                                 if tag == "py" and self.port_only else ""))
                    return DEAD if n == 0 else FAIL

            # THE RAW ROWS, SNAPSHOTTED, BECAUSE A PIN IS A CLAIM ABOUT THEM. The filtered
            # files below are written to the lanes' OWN paths, so after filtering `lanes[tag]`
            # no longer names what the program printed -- it names what survived the exclusion.
            # A pin is exactly the claim a diff CANNOT express, and the excluded rows are
            # precisely the pinned ones, so reading a pin off the filtered lane is asking
            # whether a row that was just deleted is still there. `wk-cd-gate` reported
            # "py's cd_none is not 'cd_none=i64'" with the value CORRECT on both sides.
            raw = {t: _lines(f) for t, f in lanes.items()}

            # BOTH SIDES ARE FILTERED. Filtering only the port would compare the row that is
            # KNOWN to differ, which is how a divergence list stops working.
            skip = list(self.diverges) + self.port_only
            pat = re.compile(r"^(" + "|".join(re.escape(k) for k in skip) + r")=") if skip else None
            subs = {}
            for tag, f in lanes.items():
                kept = [l for l in _lines(f) if not (pat and pat.match(l))]
                if len(kept) != self.compared:
                    self._say(f"{tag} has {len(kept)} COMPARED rows, expected {self.compared}")
                    return 1
                # `if skip:`, NOT `if self.diverges:`. The old guard ran the stale-exclusion check
                # only for a gate that happened to have a divergence, so a gate whose exclusions are
                # ALL port-only -- which is exactly the shape `mixin` and `bmn` have -- checked
                # nothing. The check is what makes a fifth BEND-ONLY row a gate failure instead of a
                # silently absorbed extra row.
                if skip:
                    hits = [l for l in _lines(f) if pat.match(l)]
                    want = len(skip)
                    if tag == "py":
                        want = len(self.diverges)
                    if len(hits) != want:
                        self._say(f"{tag} carries {len(hits)} excluded rows, expected {want} "
                                  f"-- the exclusion list is stale")
                        return 1
                s = self.dir / _staged(f"{tag}{LANE_CMP}")
                s.write_text("\n".join(kept) + "\n")
                subs[tag] = s

            base = _lines(subs["py"])
            for tag in ("bd", "bn"):
                other = _lines(subs[tag])
                if other != base:
                    bad = [(x, y) for x, y in zip(base, other) if x != y][:2]
                    extra = (f" (len {len(base)} vs {len(other)})"
                              if len(base) != len(other) else "")
                    self._say(f"DISAGREE ({tag}){extra}: {bad}")
                    return 1

            # PINNED ROWS, for the claims a diff cannot express. `want` here is the lane the
            # row must be present in, not its text -- a row's CONTENT is pinned by `diverges`,
            # and pinning text twice is how the two drift apart.
            for lane, row in self.pins:
                if not any(l.startswith(row + "=") for l in raw[lane]):
                    self._say(f"{lane} has no {row!r} row -- a pinned claim changed")
                    return 1
            for row, (want_py, want_port) in self.diverges.items():
                for lane, want in (("py", want_py), ("bd", want_port), ("bn", want_port)):
                    if want not in raw[lane]:
                        self._say(f"{lane}'s {row} is not {want!r} -- if the divergence is fixed, "
                                  f"drop it from DIVERGES; if it moved, update the pin")
                        return 1
            # A PORT-ONLY ROW: present in both port lanes, ABSENT from the oracle. The absence
            # is asserted too, because a gate that only checked the row would pass the moment the
            # oracle grew it -- and then the exclusion would be hiding a real comparison.
            for row in self.port_only:
                for lane in ("bd", "bn"):
                    if not any(l.startswith(row + "=") for l in raw[lane]):
                        self._say(f"{lane} lost its port-only row {row!r}")
                        return 1

            ok = True
        finally:
            self._settle(ok)
        return 0 if ok else 1

    def _ensure_dir(self) -> int:
        """The OUTPUT directory this gate owns, `gates/artifacts/<name>`, CREATED if absent.

        AN OUTPUT DIRECTORY IS NOT A PRECONDITION: a gate that OWNS it can `mkdir -p` it, so
        its absence is not a REFUSAL -- only an INPUT a gate cannot find is (see the input
        `_resolve`/`_warm`/`_oracle` paths, which return `REFUSED`). `gates/artifacts/` is
        `.gitignore`d, and `AGENTS.md` records `rm -rf gates/artifacts` as a live command, so
        the directory can be removed BETWEEN construction and the first write. That is why this
        runs at BOTH ends and not only in `__init__`: this file's own rule is "ONLY CONSTRUCTION
        IS BEFORE EVERY PATH", but a directory another process can delete needs a second glance
        before the path it deletes.

        MEASURED before this guard: removing the directory after construction made `_oracle`
        raise `FileNotFoundError` at the staged `py.rows` write -- the exact traceback a caller
        reads as "bend failed", aliased onto no verdict at all.
        """
        try:
            self.dir.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            self._say(f"cannot create the output directory {self.dir}: {e}")
            print(f"== REFUSED, NOT A VERDICT: output directory absent and uncreatable: "
                  f"{self.dir}", file=sys.stderr)
            return REFUSED
        return PASS

    def _clear(self):
        """The directory, EMPTIED, before anything is written.

        THE HALF OF THE FIX THAT PROMOTION CANNOT SUPPLY. Staging alone would leave a run that
        failed before its first write -- the warm check, or the oracle -- with the previous run's
        promoted files exactly where they were, which is the bug in its purest form. Emptied
        first, a red run ends with an EMPTY directory, and an empty directory cannot be diffed by
        accident. It also removes a `.tmp.` left by a run that was killed, which is the one
        residue `differ.py:242` clears for the same reason.

        A DIRECTORY THAT IS NOT THERE IS NOTHING TO EMPTY, AND A FILE THERE IS NOT A DIRECTORY
        TO EMPTY EITHER. MEASURED: an uncreatable output directory -- a FILE where the gate's
        directory must go -- made `_ensure_dir` REFUSE at construction and then `_clear` raise
        `NotADirectoryError` on `iterdir`, so the constructor crashed before `run()` could
        return the refusal. `_ensure_dir`'s exit 3 is the verdict; this cannot be an exception.
        """
        if not self.dir.is_dir():
            return
        for p in self.dir.iterdir():
            p.unlink()

    def _settle(self, ok):
        """PROMOTE OR DISCARD, in ONE place, for EVERY exit -- see `run`.

        `ok` promotes each staged file onto its published name with `os.replace`, a
        same-directory atomic rename and therefore the same shape `checks/differ.py:163` already
        uses. Not-`ok` unlinks it, so a red run leaves neither a half-written artifact nor a temp:
        the first fix at this bug did the first without the second, and its own second scenario
        is what caught it.
        """
        for t in self.dir.glob(f"{TMP}*"):
            if ok:
                os.replace(t, self.dir / t.name[len(TMP):])
            else:
                t.unlink()


def _lines_text(s):
    return [l for l in s.splitlines() if l.strip() != ""]


def gate(g, summary, checks=None):
    """`run()`, the gate's OWN checks if it has them, then THE EXIT THE RUN MEANT.

    Nine of the gates in this directory used to read `ok = GATE.run() == 0` and exit
    `0 if ok else 1`, which is how the DEAD/REFUSED distinction this file just gained was
    invisible in every one of them: a lane that emitted nothing and a lane that emitted the
    wrong answer were both "not ok". The rule this encodes is that a gate may add checks of its
    own -- `wk-f32-gate` asserts its two rows are DIFFERENT f32s -- and must not throw the
    verdict away while doing it. `checks` returns a Bool and a False one is a FAIL, not a crash.
    """
    code = g.run()
    if code == PASS and checks is not None and not checks():
        code = FAIL
    print(summary if code == PASS else f"{g.name}: {verdict_of(code)}")
    return code


def main(gate, summary):
    """The gate's OWN verdict, by NAME and by EXIT.

    `FAILED` used to be the word for all four non-PASS verdicts, which is how a lane that emitted
    nothing and a lane that emitted the wrong answer came to read the same in a transcript. The word
    is now the one the exit means, so a caller that only reads stdout cannot mistake DEAD for FAIL
    either -- which is the same reason `e2e.py` returns 4 rather than 0 for a SKIP.
    """
    code = gate.run()
    print(summary if code == PASS else f"{gate.name}: {verdict_of(code)}")
    return code
