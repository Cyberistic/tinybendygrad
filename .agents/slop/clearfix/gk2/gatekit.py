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
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "bin" / "bend").is_file())
ART = HERE / "gk2-artifacts"
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"

WARM = "ALL PROOFS CHECK"

# `checks/differ.py`'s OWN staging convention, reused rather than reinvented: a staged file is
# dot-named and lives in the artifact directory, so promoting it is a SAME-DIRECTORY atomic
# rename (`differ.py:158,163`) and nothing can observe a half-written file under a name anybody
# looks up. `differ.py:242` clears stale temps at the start of a run for the same reason.
TMP = ".tmp."

# `bend` prints `bend <ver> is available: run bend update` on STDERR on EVERY invocation --
# MEASURED on a fully green `--check-only`, 42 bytes of it -- so "stderr is non-empty" is not
# "bend said something", and a flake guard cannot ask about stderr without asking about THIS.
NOTICE = re.compile(r"^bend \S+ is available: run bend update$")


LANE_ROWS = ".rows"   # the oracle's EXPECTED VALUES
LANE_OUT = ".out"     # the two CAPTURED STREAMS


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
              absence IS the claim, and a gate that only asserted the row's presence would
              pass the moment the oracle grew it.
    canon      row names compared as a TOKEN MULTISET rather than verbatim, for a difference
              that is ORDER and not content. Both sides' orders are then asserted, so a
              change in EITHER toposort is a gate failure rather than something the
              canonicalisation silently absorbs.
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
                 pins=None, port_only=None, canon=None, warm="fatal"):
        self.name = name
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
        self.canon = list(canon or [])
        self.pins = list(pins or [])
        self.warm_mode = warm
        # THE WARM CHECK'S OWN STDOUT, kept so a gate can REPRODUCE the shell's whole output
        # rather than a summary of it. `--check-only` prints `ALL PROOFS CHECK` and
        # `Use --verdict for mathematical validity.` on stdout and both `.sh` gates let those
        # two lines through to the reader, so dropping them makes the artifact differ from the
        # oracle on the green path for no reason a reader could name.
        self.warm_out = ""
        self.dir = ART / name
        self.dir.mkdir(parents=True, exist_ok=True)
        self._clear()   # OPTION 2

    def _resolve(self, p):
        """beside the gate first, then the repo root, then as given"""
        q = Path(p)
        if q.is_absolute():
            return q
        for base in (HERE, ROOT, ROOT / "gates"):
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
            self._clear()
            if not self._warm():
                return 1
            if not self._oracle():
                return 1
            bd, bn, binp = (self.dir / _staged(n) for n in ("bd.out", "bn.out", "gate.bin"))
            if not self._lane([str(BEND), str(self.bend)], "bd.out"):
                return 1
            c = subprocess.run([str(BEND), str(self.bend), "-o", str(binp)],
                               capture_output=True, text=True)
            if c.returncode != 0:
                self._say(f"the native compile failed: {(c.stderr or '').strip()[:200]}")
                return 1
            if not self._lane([str(binp)], "bn.out"):
                return 1

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
                    return 1

            # BOTH SIDES ARE FILTERED. Filtering only the port would compare the row that is
            # KNOWN to differ, which is how a divergence list stops working.
            skip = list(self.diverges) + self.port_only + self.canon
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
                        want = len(self.diverges) + len(self.canon)
                    if len(hits) != want:
                        self._say(f"{tag} carries {len(hits)} excluded rows, expected {want} "
                                  f"-- the exclusion list is stale")
                        return 1
                s = self.dir / _staged(f"{tag}{LANE_ROWS}")
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
                if not any(l.startswith(row + "=") for l in _lines(lanes[lane])):
                    self._say(f"{lane} has no {row!r} row -- a pinned claim changed")
                    return 1
            for row, (want_py, want_port) in self.diverges.items():
                for lane, want in (("py", want_py), ("bd", want_port), ("bn", want_port)):
                    if want not in _lines(lanes[lane]):
                        self._say(f"{lane}'s {row} is not {want!r} -- if the divergence is fixed, "
                                  f"drop it from DIVERGES; if it moved, update the pin")
                        return 1
            # A PORT-ONLY ROW: present in both port lanes, ABSENT from the oracle. The absence
            # is asserted too, because a gate that only checked the row would pass the moment the
            # oracle grew it -- and then the exclusion would be hiding a real comparison.
            for row in self.port_only:
                for lane in ("bd", "bn"):
                    if not any(l.startswith(row + "=") for l in _lines(lanes[lane])):
                        self._say(f"{lane} lost its port-only row {row!r}")
                        return 1
                if any(l.startswith(row + "=") for l in _lines(lanes["py"])):
                    self._say(f"the ORACLE now emits {row!r} -- drop it from port_only and let "
                              f"the two sides COMPARE it")
                    return 1

            # AN ORDER-ONLY DIVERGENCE: the tokens are equal and the ORDER is not. Compared as a
            # multiset, then BOTH orders are asserted from the file rather than from a literal
            # here, so this module carries no knowledge of any gate's rows.
            for row in self.canon:
                got = {}
                for lane, f in lanes.items():
                    line = next((l for l in _lines(f) if l.startswith(row + "=")), None)
                    if line is None:
                        self._say(f"{lane} has no {row!r} row")
                        return 1
                    got[lane] = line
                toks = {k: sorted(v.split(" ")) for k, v in got.items()}
                if not (toks["py"] == toks["bd"] == toks["bn"]):
                    self._say(f"{row}'s node MULTISET differs: "
                              f"py={toks['py']} port={toks['bd']}")
                    return 1
                if got["py"] == got["bd"]:
                    self._say(f"{row}: the port's order now MATCHES CPython's -- drop it from "
                              f"`canon` and let the line diff have it")
                    return 1
            ok = True
        finally:
            self._settle(ok)
        return 0 if ok else 1

    def _clear(self):
        """The directory, EMPTIED, before anything is written.

        THE HALF OF THE FIX THAT PROMOTION CANNOT SUPPLY. Staging alone would leave a run that
        failed before its first write -- the warm check, or the oracle -- with the previous run's
        promoted files exactly where they were, which is the bug in its purest form. Emptied
        first, a red run ends with an EMPTY directory, and an empty directory cannot be diffed by
        accident. It also removes a `.tmp.` left by a run that was killed, which is the one
        residue `differ.py:242` clears for the same reason.
        """
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


def main(gate, summary):
    ok = gate.run() == 0
    print(summary if ok else f"{gate.name}: FAILED")
    return 0 if ok else 1
