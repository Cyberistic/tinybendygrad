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
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = Path(__file__).resolve().parent / "artifacts"
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"

WARM = "ALL PROOFS CHECK"


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
    """

    def __init__(self, name, *, bend, oracle, rows, compared=None, diverges=None,
                 pins=None, port_only=None, canon=None):
        self.name = name
        self.bend = bend if os.path.isabs(bend) else ROOT / bend
        self.oracle = oracle if os.path.isabs(oracle) else ROOT / oracle
        self.rows = rows
        self.compared = compared if compared is not None else rows
        self.diverges = dict(diverges or {})
        self.port_only = list(port_only or [])
        self.canon = list(canon or [])
        self.pins = list(pins or [])
        self.dir = ART / name
        self.dir.mkdir(parents=True, exist_ok=True)

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
        out = subprocess.run([str(BEND), str(self.bend), "--check-only"],
                             capture_output=True, text=True)
        first = (out.stdout or "").splitlines()[:1]
        if not first or first[0].strip() != WARM:
            self._say(f"--check-only's first line is {first!r}, not {WARM!r}")
            return False
        if self.bend.stat().st_size == 0:
            self._say("the driver is 0 bytes, and an empty file typechecks")
            return False
        return True

    def _oracle(self):
        r = subprocess.run([str(PY), str(self.oracle)], capture_output=True, text=True)
        if r.returncode != 0:
            self._say(f"the oracle failed rc={r.returncode}: {r.stderr.strip()[:200]}")
            return False
        (self.dir / "py.txt").write_text(r.stdout)
        return True

    def _lane(self, argv, out):
        """Retried while it emits the wrong ROW COUNT, because `bend`'s machine stack
        overflows on roughly 1 run in 20 and prints ZERO rows -- indistinguishable from
        'did not start'."""
        for _ in range(25):
            r = subprocess.run(argv, capture_output=True, text=True)
            if r.returncode == 0 and len(_lines_text(r.stdout)) == self.rows:
                out.write_text(r.stdout)
                return True
        self._say(f"lane {out.name} did not produce {self.rows} rows in 25 tries: "
                  f"{(r.stderr or '').strip()[:200]}")
        return False

    def run(self):
        if not self._warm():
            return 1
        if not self._oracle():
            return 1
        bd, bn, binp = self.dir / "bd.txt", self.dir / "bn.txt", self.dir / "gate.bin"
        if not self._lane([str(BEND), str(self.bend)], bd):
            return 1
        c = subprocess.run([str(BEND), str(self.bend), "-o", str(binp)],
                           capture_output=True, text=True)
        if c.returncode != 0:
            self._say(f"the native compile failed: {(c.stderr or '').strip()[:200]}")
            return 1
        if not self._lane([str(binp)], bn):
            return 1

        lanes = {"py": self.dir / "py.txt", "bd": bd, "bn": bn}
        for f in lanes.values():
            n = len(_lines(f))
            if n != self.rows:
                self._say(f"{f.name} has {n} rows, expected {self.rows}")
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
            if self.diverges:
                hits = [l for l in _lines(f) if pat.match(l)]
                want = len(self.diverges) + len(self.port_only) + len(self.canon)
                if len(hits) != want:
                    self._say(f"{tag} carries {len(hits)} excluded rows, expected {want} "
                              f"-- the exclusion list is stale")
                    return 1
            s = self.dir / f"{tag}.sub"
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
        return 0


def _lines_text(s):
    return [l for l in s.splitlines() if l.strip() != ""]


def main(gate, summary):
    ok = gate.run() == 0
    print(summary if ok else f"{gate.name}: FAILED")
    return 0 if ok else 1
