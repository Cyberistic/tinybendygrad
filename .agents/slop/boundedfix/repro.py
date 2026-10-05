#!/usr/bin/env python3
"""THE REPRO for the two `checks/bounded.py` defects, against the FROZEN pre-fix copy and against
whatever `checks/bounded.py` currently is. Run it twice -- once before the fix, once after -- and
the second run is the only evidence the first was worth anything.

    .venv/bin/python .agents/slop/boundedfix/repro.py

FIVE CASES, AND EACH ONE NAMES THE DEFECT IT IS HERE TO PROVE.

  1. SPLIT        a WARM `bend --check-only` through the guard, stdout captured. A guard that
                   forwards the child's stdout must produce BYTE-IDENTICAL stdout. It does not,
                   because `bounded.py:103` opened `stderr=subprocess.STDOUT` and then printed its
                   own verdict line to that same stdout, so `./bin/bend > rows.rows` through it puts
                   the 42-byte update notice AND `[bounded] ...` into the row census.
                   DENOMINATOR: `notname=value` -- lines in the captured stdout that are NOT whole
                   `name=value` rows, which is exactly `checks/sb-gate.sh:117`'s comparison unit.
  2. NOISE        the same run, asked the question the naive fix asks: "is stderr empty?" NO, and it
                   is 42 bytes on a healthy green run. So the discriminator has to be gatekit's
                   `_said()`, and this case prints BOTH numbers so the trap is visible.
  3. COLLISION    `sh -c 'exit 3'` (a CORRECT REFUSAL, 0 MB) against a memory bomb at a 300 MB
                   ceiling (AN ACTUAL KILL). Both exit 3. The token is what tells them apart, and
                   pre-fix the token is only reachable on the polluted stdout.
  4. EMPTY        a 0-byte `.bend`. `bend --check-only` answers `ALL PROOFS CHECK` for it -- the
                   FOURTEENTH instance of the project's oldest trap. Does the guard's exit path
                   distinguish "proved" from "did not run"? It must not claim a proof it cannot
                   see.
  5. SILENT       a child that exits non-zero having said nothing, and a child that exits 0 having
                   said nothing. The second is `cc -fsyntax-only` on a clean file and
                   `node --check` on a clean file -- REAL, and green. A guard that reports both as
                   "did not run" has changed a lane's verdict, which is the thing this project
                   reversed a previous fix for doing.

CASE 5b: `FILL`. 1 MB on stdout through the guard's 64 KB pipe. Pre-fix the child BLOCKS in write()
and the guard reports TIMED-OUT for a child that had nothing left to say -- the instrument's own
pipe decides the verdict. Same line, same root cause as case 1, and it is measured rather than
asserted.

NO TWO `bend` PROCESSES AT A TIME, EVER: `sz.bend` peaks at 1,468 MB and a gate was killed at
2,048 MB during this session. Every case here is sequential, and the only bomb is capped at 300 MB.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
GUARDS = [("prefix", HERE / "bounded-prefix.py"), ("current", ROOT / "checks" / "bounded.py")]

# `gates/gatekit.py`'s OWN notice regex and `_said`, imported rather than re-typed: the whole point
# of case 2 is that "stderr is non-empty" is not "bend said something", and a SECOND copy of the
# answer to that question is how the two drift apart.
sys.path.insert(0, str(ROOT / "gates"))
from gatekit import NOTICE, _said  # noqa: E402

TOKEN = re.compile(r"^\[bounded\] ([A-Z-]+)")
ROW = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*=")


def run(guard: Path, args: list[str]) -> tuple[int, str, str]:
    """`(exit status, stdout, stderr)` of the GUARD -- its own streams, never merged here."""
    p = subprocess.run([str(PY), str(guard), *args], capture_output=True, text=True, cwd=ROOT)
    return p.returncode, p.stdout, p.stderr


def token(stdout: str, stderr: str) -> str:
    """The verdict TOKEN, wherever it was printed, so a case reports the claim and not the stream."""
    for blob in (stderr, stdout):           # stderr FIRST: that is where the contract lives now
        for ln in blob.splitlines():
            if m := TOKEN.match(ln):
                return m.group(1)
    return "NONE"


def notice_bytes(blob: str) -> int:
    return sum(len(ln) + 1 for ln in blob.splitlines() if NOTICE.match(ln.strip()))


def peak(out: str, err: str) -> str:
    m = re.search(r"peak-RSS=(\d+)", out + err)
    return f"{m.group(1)}MB" if m else "?"


# --------------------------------------------------------------------------- the cases
def case_split(tmp: Path) -> dict:
    """Case 1 + 2 together, because they are the same captured stdout asked two questions."""
    warm = "tinybendygrad/mixin/__init__.bend"
    truth = subprocess.run([str(BEND), warm, "--check-only"], capture_output=True, text=True, cwd=ROOT)
    got = {}
    for name, guard in GUARDS:
        _, out, err = run(guard, ["--seconds", "300", "--mb", "4096", "--",
                                  str(BEND), warm, "--check-only"])
        (tmp / f"split-{name}.out").write_text(out)
        (tmp / f"split-{name}.err").write_text(err)
        got[name] = {
            "stdout_bytes": len(out),
            "child_stdout_bytes": len(truth.stdout),
            "stdout_is_child_stdout": out == truth.stdout,
            "verdict_lines_in_stdout": sum(1 for ln in out.splitlines() if TOKEN.match(ln)),
            "notice_bytes_in_stdout": notice_bytes(out),
            "not_a_row": sum(1 for ln in out.splitlines() if ln.strip() and not ROW.match(ln)),
            "stderr_notices": notice_bytes(err),
            "stderr_said": _said(err),
            "token": token(out, err),
        }
    got["_ground_truth"] = {"child_stdout_bytes": len(truth.stdout),
                            "child_stderr_bytes": len(truth.stderr),
                            "child_stderr_is_all_notice": _said(truth.stderr) == ""}
    return got


def case_collision(tmp: Path) -> dict:
    """A CORRECT REFUSAL against an ACTUAL KILL -- and the refusal PRINTS, because a refusal that
    says nothing is the `NO-VERDICT` case below and would not collide with anything. `run-port-mm.sh`
    refuses with 3 and prints why; this is that shape."""
    bomb = tmp / "bomb.pl"
    bomb.write_text("my @a; while (1) { push @a, (\"x\" x 1_000_000) }\n")
    out = {}
    for name, guard in GUARDS:
        refuse = run(guard, ["--seconds", "60", "--mb", "4096", "--", "sh", "-c",
                             "echo 'refusing: cold substrate' >&2; exit 3"])
        kill = run(guard, ["--seconds", "60", "--mb", "300", "--", "perl", str(bomb)])
        out[name] = {
            "refusal": {"exit": refuse[0], "token": token(*refuse[1:]), "peak": peak(*refuse[1:])},
            "memkill": {"exit": kill[0], "token": token(*kill[1:]), "peak": peak(*kill[1:])},
        }
        out[name]["AMBIGUOUS_EXIT"] = out[name]["refusal"]["exit"] == out[name]["memkill"]["exit"]
        out[name]["TOKEN_SEPARATES"] = out[name]["refusal"]["token"] != out[name]["memkill"]["token"]
    return out


def case_empty(tmp: Path) -> dict:
    """A 0-byte input, which `bend --check-only` reports as PROOF."""
    empty = tmp / "empty.bend"
    empty.write_bytes(b"")
    truth = subprocess.run([str(BEND), str(empty), "--check-only"],
                           capture_output=True, text=True, cwd=ROOT)
    out = {"_ground_truth": {"exit": truth.returncode, "stdout": truth.stdout.strip(),
                             "stderr_said": _said(truth.stderr)}}
    for name, guard in GUARDS:
        rc, sout, serr = run(guard, ["--seconds", "120", "--mb", "4096", "--",
                                     str(BEND), str(empty), "--check-only"])
        out[name] = {"exit": rc, "token": token(sout, serr),
                     "stdout_bytes": len(sout), "peak": peak(sout, serr)}
    return out


def case_silent(tmp: Path) -> dict:
    """A child that says NOTHING, exiting 0 and exiting non-zero -- both shapes are real."""
    out = {}
    for name, guard in GUARDS:
        rows = {}
        for label, argv in (("exits0_silent", ["/usr/bin/true"]),
                            ("exits1_silent", ["/usr/bin/false"]),
                            ("says_something", ["sh", "-c", "echo to-stderr >&2; exit 1"])):
            rc, sout, serr = run(guard, ["--seconds", "60", "--mb", "4096", "--", *argv])
            rows[label] = {"exit": rc, "token": token(sout, serr),
                           "stdout": sout.strip(), "said": _said(serr)}
        out[name] = rows
    return out


def case_notstarted(tmp: Path) -> dict:
    """A COMMAND THAT CANNOT BE STARTED -- the docstring's exit 5. `Path.exists()` follows
    symlinks and a bare filename resolves against the WORKING DIRECTORY, so a path that is not
    there is the shape a caller actually produces by accident."""
    out = {}
    for name, guard in GUARDS:
        rc, sout, serr = run(guard, ["--seconds", "30", "--mb", "4096", "--",
                                     str(tmp / "no-such-binary")])
        out[name] = {"exit": rc, "token": token(sout, serr),
                     "traceback": "Traceback" in serr, "said": _said(serr)[:60]}
    return out


def case_orphan(tmp: Path) -> dict:
    """A GRANDCHILD that outgrows the ceiling after its PARENT has already exited. `os.getpgid`
    on an exited parent raises, the pre-fix `except` falls back to `proc.kill()`, and the bomb
    that was about to take the machine is never signalled. The instrument reports the run it can
    see and walks away from the one that is eating the memory."""
    bomb = tmp / "bomb-orphan.pl"
    bomb.write_text("my @a; while (1) { push @a, (\"z\" x 1_000_000) }\n")
    out = {}
    for name, guard in GUARDS:
        rc, sout, serr = run(guard, ["--seconds", "20", "--mb", "250", "--",
                                     "perl", "-e", "if (fork() == 0) { exec $^X, $ARGV[0] } exit 0",
                                     str(bomb)])
        out[name] = {"exit": rc, "token": token(sout, serr), "peak": peak(sout, serr)}
    return out


def case_fill(tmp: Path) -> dict:
    """1 MB on stdout, against the guard's 64 KB pipe. A guard that cannot drain cannot measure."""
    out = {}
    for name, guard in GUARDS:
        rc, sout, serr = run(guard, ["--seconds", "6", "--mb", "4096", "--",
                                     "sh", "-c", "head -c 1000000 /dev/zero | tr '\\0' 'x'"])
        out[name] = {"exit": rc, "token": token(sout, serr),
                     "stdout_bytes": len(sout), "peak": peak(sout, serr)}
    return out


# --------------------------------------------------------------------------- the report
def main() -> int:
    with tempfile.TemporaryDirectory(prefix="boundedfix.") as td:
        tmp = Path(td)
        # Each case function runs ONCE: two `bend` processes at a time is how this session lost a
        # gate, and case 1 and case 2 are the SAME captured stdout asked two questions.
        split, col, empty, silent, fill = (case_split(tmp), case_collision(tmp), case_empty(tmp),
                                           case_silent(tmp), case_fill(tmp))
        notstarted, orphan = case_notstarted(tmp), case_orphan(tmp)
        cases = [
            ("1 SPLIT + 2 NOISE (stdout must be the child's stdout, byte for byte; and stderr is "
             "42 bytes on a GREEN run, so only `_said` is 'bend said something')", split),
            ("3 COLLISION (a CORRECT REFUSAL and a REAL KILL are both exit 3)", col),
            ("4 EMPTY (a 0-byte input that `bend --check-only` calls PROOF)", empty),
            ("5 SILENT (said nothing, exit 0 -- `cc -fsyntax-only` and `node --check` look like "
             "this)", silent),
            ("5b FILL (1 MB on stdout through a 64 KB pipe)", fill),
            ("6 NOT-STARTED (the docstring's exit 5, on a command that is not there)", notstarted),
            ("7 ORPHAN (a grandchild over the ceiling whose parent has ALREADY EXITED)", orphan),
        ]
        body = "\n".join(sum(([f"== {title}"] + [f"   {k:16} {v}" for k, v in val.items()] + [""]
                              for title, val in cases), []))
    print(body)

    pre = col["prefix"]
    facts = [("prefix.stdout_is_child_stdout", split["prefix"]["stdout_is_child_stdout"]),
             ("prefix.notice_bytes_in_stdout", split["prefix"]["notice_bytes_in_stdout"]),
             ("prefix.not_a_row", split["prefix"]["not_a_row"]),
             ("prefix.AMBIGUOUS_EXIT", pre["AMBIGUOUS_EXIT"]),
             ("prefix.TOKEN_SEPARATES", pre["TOKEN_SEPARATES"]),
             ("prefix.empty.token", empty["prefix"]["token"]),
             ("prefix.exits1_silent.token", silent["prefix"]["exits1_silent"]["token"]),
             ("prefix.exits0_silent.token", silent["prefix"]["exits0_silent"]["token"]),
             ("prefix.notstarted.exit", notstarted["prefix"]["exit"]),
             ("prefix.notstarted.traceback", notstarted["prefix"]["traceback"]),
             ("prefix.fill.exit", fill["prefix"]["exit"]),
             ("prefix.orphan.token", orphan["prefix"]["token"]),
             ("prefix.orphan.peak", orphan["prefix"]["peak"])]
    print("== FACTS")
    for k, v in facts:
        print(f"   {k:34} {v}")

    shas = ["guard\tsha256\tpath"] + [f"{n}\t{hashlib.sha256(g.read_bytes()).hexdigest()}\t"
                                     f"{os.path.relpath(g, ROOT)}" for n, g in GUARDS]
    (HERE / "REPRO.rows").write_text(
        body + "\n== FACTS\n" + "\n".join(f"{k}={v}" for k, v in facts) + "\n"
        + "\n".join(shas) + "\n")
    (HERE / "SHA256SUMS.md").write_text(
        "# sha256 of the two guards this repro compares. `prefix` is FROZEN: it is the file as it\n"
        "# stood before the fix and it is the only evidence that the pre-fix numbers were measured\n"
        "# rather than remembered. If `prefix` ever changes, this repro has stopped being a repro.\n"
        + "\n".join(f"{s.split(chr(9))[1]}  {s.split(chr(9))[2]}" for s in shas[1:]) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
