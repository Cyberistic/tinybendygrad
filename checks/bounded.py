#!/usr/bin/env python3
"""Run a command under BOTH a time bound and a memory bound, and say which one fired.

    usage: checks/bounded.py [--seconds N] [--mb N] -- <command> [args ...]
           checks/bounded.py --selftest

THE CONTRACT. TWO LINES, AND BOTH OF THEM WERE BROKEN.

  1. STDOUT IS THE CHILD'S, BYTE FOR BYTE, AND NOTHING OF THIS FILE'S IS ADDED TO IT. An
     instrument's own output inside the stream it measures is how a row census acquires lines it
     cannot account for: line 103 used to open `stderr=subprocess.STDOUT` and then print the
     verdict to that same stdout, so `./bin/bend ... > rows.rows` through this guard put the
     42-byte update notice AND the `[bounded]` record into `rows.rows`, and `checks/sb-gate.sh:117`
     -- whose comparison unit is a whole `name=value` line -- counted 4 lines that are not rows.
     A census that counts the verdict can never be clean, and a clean-looking one is worse.
  2. STDERR IS THE CHILD'S, PLUS THIS FILE'S OWN RECORD. The record is ONE line beginning
     `[bounded] `, and the TOKEN on it is THE VERDICT. Diagnostics keep the channel they had;
     the sentence about what the run means keeps a channel of its own.

WHY THE CHILD'S TWO STREAMS LAND IN FILES AND NOT PIPES. A pipe holds 64 KB and this guard cannot
read it while the child runs, so a child with more to say BLOCKS in write() and the guard reports
TIMED-OUT for a child that was never given the chance to finish. MEASURED on the pre-fix file: 1 MB
on stdout gave `exit 4 TIMED-OUT` with 65,785 bytes captured and 934,215 never written -- the
instrument's own pipe decided the verdict. Two files remove the deadlock, separate the streams, and
cost no drain loop.

EXIT STATUS: A COARSE SUMMARY. THE TOKEN IS THE CONTRACT, because 3 cannot mean one thing.
MEASURED, same run: `sh -c 'exit 3'` is a CORRECT REFUSAL at 0 MB and a memory kill is exit 3 at
2,988 MB. A unit lost 425 rows by believing the status instead of the token, and `checks/e2e.py`
refuses to route its stages through this file for exactly that reason (`e2e.py:79`). So the
statuses stay the ones callers already depend on, and the token carries what the status cannot:

  0   no bound fired                                     WITHIN-LIMITS
  3   KILLED ON MEMORY                                   KILLED-ON-MEMORY
  4   TIMED OUT                                          TIMED-OUT
  5   the command could not be STARTED                   NOT-STARTED
  6   the run is not a measurement: nothing out of it,   NO-VERDICT
      nothing said, and it exited non-zero
  *   otherwise the CHILD's own status, passed through unchanged

  **THE CALLER THAT MUST CHANGE ITS MIND IS THE ONE ASKING "WAS IT KILLED?": it must read the
  token.** `checks/sb-gate.sh:103` already does. `checks/substrate.py` reads the FIRST LINE of
  stdout, which this split makes purer, so its verdicts do not move. Exit 6 is the only status
  that is new, and it cannot be produced by a lane that produced a verdict before: it needs a
  non-zero child, no stdout and nothing said, which is a failure that printed nothing.

`WITHIN-LIMITS` IS A CLAIM ABOUT THE BOUNDS AND NEVER ABOUT THE CHILD. A child that exits 1 having
said nothing is `WITHIN-LIMITS rc=1`; a child that exits 0 having said nothing is `WITHIN-LIMITS
rc=0`, and that is what `cc -fsyntax-only` and `node --check` look like on a CLEAN file -- so
reporting it as a failure would redden a green lane, which is what the reverted `gatekit.py` bound
was reverted for. What this file CANNOT see is the project's oldest trap: `bend --check-only`
answers `ALL PROOFS CHECK` FOR A 0-BYTE FILE (MEASURED, and `helpers.bend` has been truncated to
0 bytes four times by units that then saw green). Catching that needs a bend-aware guard --
`checks/substrate.py` HALF 1's EMPTY case, `gates/gatekit.py`'s `stat().st_size == 0` -- and this
file says so rather than pretending to have proved something.

WHY IT WATCHES THE TREE AFTER THE DIRECT CHILD EXITS. The runaway this exists for was a SPAWNED
child, and a grandchild is reparented to init the moment its parent goes: `pgrep -P <dead pid>`
finds nothing, so a guard that walks from the direct child alone stops watching the process that is
eating the machine. MEASURED on the pre-fix file: a bomb behind a parent that exited at once gave
`WITHIN-LIMITS rc=0 peak-RSS=3 MB` with the bomb past 1 GB and still running. The watch list is
kept and the group is killed by the pgid captured AT SPAWN -- `start_new_session` makes the
child's pgid its pid and it stays valid afterwards, which `os.getpgid` on a reaped pid does not.

WHY THIS EXISTS, AND IT IS NOT HYPOTHETICAL. 2026-10-05, twice in one afternoon, two
`references/bend/bend2/main.ts` processes consumed all system memory and crashed the machine:
swap went to 1.6 of 2.0 GB and free pages to ~19 MB. The project's own timeout idiom is
`perl -e 'alarm N; exec @ARGV'` and **it appears in `agent-core.md`, in every unit's brief, and in
every gate -- and `ulimit` appears ZERO times in `agent-core.md`, `substrate-check.sh` and
`e2e.sh` combined.** An alarm bounds TIME. A compiler that allocates without bound is killed by
neither an alarm nor a reviewer watching a load average.

WHY A WATCHDOG AND NOT `ulimit -v`.  `ulimit -v` is unreliable on macOS -- it exists in the shell
but address-space limits are not consistently enforced -- and `RLIMIT_AS` from Python is subject
to the same kernel behaviour. **A GUARD THAT DOES NOT ENFORCE ON THE PLATFORM IT IS WRITTEN FOR
IS A COMMENT**, which is the same defect this project has now catalogued seventeen of. So the
bound is enforced by the only mechanism that cannot be ignored: watch the child's RSS and kill it.
**AND IT IS A POLLING GUARD, NOT A HARD LIMIT, AND THE DOCSTRING MUST SAY SO: MEASURED, a bomb
that allocates 1 MB per 50 ms passed a 300 MB ceiling at 2,217 MB before the first poll that saw
it.** The ceiling bounds the DAMAGE, not the allocation.

WHY IT PRINTS THE PEAK.  A guard that reports only "killed" leaves the next reader with no number,
and a kill with no number is indistinguishable from a hang. **THE PEAK IS THE FACT.**

DISTINGUISHING THE TWO BOUNDS IS THE POINT.  The project's alarm exits 142 (128+SIGALRM), and a
kill exits 137 (128+SIGKILL) -- **and 142 has been read in this project as "the run failed" when it
means "my own alarm killed it, so it proves nothing."** A caller must be able to tell a slow build
from a hungry one, because the fixes are unrelated.

ONE ORDERING CHANGE A READER WILL NOTICE: the record now reaches stderr BEFORE the child's own
stderr, because the two are no longer interleaved in one pipe. Each line still belongs to one
stream, which is the point.
"""
from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
# `gates/gatekit.py`'s OWN `_said`, imported rather than re-typed, and the reason is measured: `bend`
# prints `bend <ver> is available: run bend update` on STDERR on EVERY invocation -- 42 bytes of it,
# on a fully green `--check-only` -- so "stderr is non-empty" is NOT "bend said something". A second
# copy of that regex is how the two drift apart, and a drift here would put noise back into the
# diagnostics. This module has no other dependency, and a missing `gates/` breaks every gate anyway.
sys.path.insert(0, str(HERE.parent / "gates"))
from gatekit import _said  # noqa: E402  (the path has to exist before this line runs)

# 4 GB. This machine has 8-ish; a build that wants more than this is a build with a term that
# did not terminate, not a build that needs the memory. Adjust per machine, never upward to
# accommodate one failure -- that is how the ceiling stops being a ceiling.
DEFAULT_MB = 4096
DEFAULT_SECONDS = 900
POLL = 0.25
# The token is parsed by `checks/sb-gate.sh:103` as `[bounded] <TOKEN>  rc=`, so the two spaces are
# part of the contract and the prose below deliberately does NOT carry the `[bounded] ` prefix.
RECORD = re.compile(r"^\[bounded\] ([A-Z-]+)  rc=")
WITHIN, MEMORY, TIMEOUT, UNSTARTED, NOVERDICT = (
    "WITHIN-LIMITS", "KILLED-ON-MEMORY", "TIMED-OUT", "NOT-STARTED", "NO-VERDICT")
STATUS = {MEMORY: 3, TIMEOUT: 4, UNSTARTED: 5, NOVERDICT: 6}
WHY = {
    MEMORY: ("THIS IS NOT A TIMEOUT, AND THIS RUN PROVES NOTHING: the term being built did not "
             "terminate and the watchdog killed it. Look for Peano `Nat` arithmetic near its "
             "2^48-1 ceiling, or a plant that made a multiplier symbolic. Note the PEAK is where "
             "it got to, not where the ceiling is -- this guard polls."),
    TIMEOUT: ("THIS RUN PROVES NOTHING: it was killed, it did not fail. rc=142 would be SIGALRM; "
              "here the watchdog sent SIGKILL, and the peak says whether it was also hungry on the "
              "way out."),
    NOVERDICT: ("NOT A MEASUREMENT: the child exited non-zero having written nothing and said "
                "nothing beyond the update notice. That is either a failure that printed nothing "
                "or `bend`'s machine-stack overflow -- which prints nothing at all, roughly 1 run "
                "in 20 -- and the two are indistinguishable from here. Do not read this as a pass "
                "and do not read it as a clean failure; RETRY, and if it persists, say so."),
    UNSTARTED: ("The command does not exist, or could not be executed. A wrong path is not a "
                "verdict about the thing you meant to measure."),
}


def rss_mb(pid: int) -> float:
    """Resident size of one pid, in MB. `ps` rather than a library: no external dependencies."""
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return int(out) / 1024 if out else 0.0
    except Exception:
        return 0.0


def group_rss(pgid: int) -> tuple[float, list[int]]:
    """`(RSS in MB, the pids)` of EVERY process in the child's PROCESS GROUP.

    **BY GROUP, NOT BY `pgrep -P`.** MEASURED on macOS: a grandchild whose parent has already
    exited is reparented to init, and `pgrep -P <dead pid>` returns NOTHING for it -- so the
    pre-fix walk saw an empty tree and reported `WITHIN-LIMITS peak-RSS=3 MB` with a 1 GB bomb
    running. `pgrep -g <pgid>` still names it, and the group is exactly what `os.killpg` signals,
    so the thing MEASURED and the thing KILLED finally cover the same set. A descendant that calls
    `setsid()` leaves the group and no process group can see it: stated here rather than hidden.
    """
    try:
        pids = [int(k) for k in subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True,
                                               text=True, timeout=5).stdout.split()]
    except Exception:
        pids = []
    return sum(rss_mb(p) for p in pids), pids


def record(verdict: str, rc: int, peak: float, ceiling: float, elapsed: float, cmd: list[str],
           out: str, err: str) -> None:
    """The ONE line a caller has to read, on stderr, with the child's own output left alone."""
    said = _said(err)
    print(f"[bounded] {verdict}  rc={rc}  peak-RSS={peak:.0f} MB (ceiling {ceiling:.0f})  "
          f"{elapsed:.0f}s  :: {' '.join(cmd[:3])}  out={len(out)}B err={len(err)}B"
          + (f"  said={said}" if said else ""), file=sys.stderr)
    if why := WHY.get(verdict):
        print(f"  {why}", file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=int, default=DEFAULT_SECONDS)
    ap.add_argument("--mb", type=int, default=DEFAULT_MB)
    ap.add_argument("--selftest", action="store_true",
                    help="run this file's own cases and exit 0 only if every one of them holds")
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        print("usage: checks/bounded.py [--seconds N] [--mb N] -- <command> [args ...]",
              file=sys.stderr)
        return STATUS[UNSTARTED]

    ceiling, peak, started = float(args.mb), 0.0, time.monotonic()
    verdict = WITHIN
    with tempfile.TemporaryDirectory(prefix="bounded.") as td:
        opath, epath = Path(td) / "child.out", Path(td) / "child.err"
        with opath.open("w") as out_f, epath.open("w") as err_f:
            try:
                # Its own process group, so a kill reaches a grandchild. `start_new_session`
                # detaches it from ours, which also means a Ctrl-C here does not race the
                # watchdog.
                proc = subprocess.Popen(cmd, start_new_session=True, stdout=out_f, stderr=err_f)
            except OSError as exc:
                # EXIT 5 WAS DOCUMENTED AND UNREACHABLE: a command that is not there raised out of
                # `Popen`, printed a Python traceback, and exited 1 -- the same status as an
                # ordinary failure, with no verdict line anywhere. MEASURED on the pre-fix file.
                record(UNSTARTED, STATUS[UNSTARTED], 0.0, ceiling, 0.0, cmd, "", str(exc))
                return STATUS[UNSTARTED]
            # The child's pgid IS its pid under `start_new_session`, and it stays valid after the
            # child is reaped -- which `os.getpgid` does not: pre-fix, a kill whose parent had
            # already exited raised, fell into `except`, and called `proc.kill()` on a corpse.
            pgid = proc.pid
            while True:
                now, group = group_rss(pgid)
                peak = max(peak, now)
                if now >= ceiling:
                    verdict = MEMORY
                    break
                if time.monotonic() - started > args.seconds:
                    verdict = TIMEOUT
                    break
                # BOTH conditions, not the child's alone: a run whose parent has gone but whose
                # bomb has not is still a run in flight, and reporting it now is how a 1 GB bomb
                # gets called a 3 MB pass.
                if proc.poll() is not None and not group:
                    break
                time.sleep(POLL)
        if verdict != WITHIN:
            try:
                os.killpg(pgid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        try:
            rc = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            rc = proc.wait()
        # BYTES, and the child's stdout goes to this file's stdout UNCHANGED -- no decoding, no
        # newline translation, nothing appended. Everything this file has to say goes to stderr,
        # which is the whole of the split.
        raw_out, raw_err = opath.read_bytes(), epath.read_bytes()
    sys.stdout.buffer.write(raw_out)
    sys.stdout.flush()
    out, err = raw_out.decode("utf-8", "replace"), raw_err.decode("utf-8", "replace")

    # NOTHING OUT, NOTHING SAID, NON-ZERO: a run that measured nothing, and which must not be
    # reported as agreement with a clean one. `WITHIN-LIMITS` would be TRUE here and USELESS.
    if verdict == WITHIN and rc and not out.strip() and not _said(err):
        verdict = NOVERDICT
    record(verdict, rc, peak, ceiling, time.monotonic() - started, cmd, out, err)
    # THE CHILD'S OWN STDERR, verbatim, AFTER the record -- so `[bounded] ...` heads the stream and
    # the diagnostics it is talking about follow it. Bytes, for the same reason stdout is bytes.
    sys.stderr.buffer.write(raw_err)
    sys.stderr.flush()
    return STATUS.get(verdict) or (rc or 0)


# --------------------------------------------------------------------------- the selftest
def selftest() -> int:
    """Every bound SHOWN FIRING, and every lie SHOWN NOT FIRING.

    A guard that has never been shown to fire is the project's seventeenth instrument defect, so
    both bounds fire here, the grandchild fires, and the ORPHANED grandchild fires -- the runaway
    was a spawned child and the one after it an orphaned one. The bomb is 10 MB per iteration so
    the ceiling arrives in a second: a bomb slow enough to be polite is a bomb that outlives the
    reader. ONE PROCESS AT A TIME, ALWAYS, and no two `bend` processes at once.
    """
    here = Path(__file__).resolve()
    bend = here.parents[1] / "bin" / "bend"
    bomb = "a=[]\nwhile 1: a.append(b'x'*10000000)\n"
    results: list[tuple[str, bool | None, str]] = []

    def guard(*argv: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(here), *argv], capture_output=True, text=True)

    def tok(blob: str) -> str:
        m = RECORD.search(blob)
        return m.group(1) if m else "NONE"

    # 1 + 2. THE SPLIT, and the 42 bytes that make "stderr is non-empty" the wrong question.
    if os.access(bend, os.X_OK):
        truth = subprocess.run([str(bend), "tinybendygrad/mixin/__init__.bend", "--check-only"],
                               capture_output=True, text=True, cwd=here.parents[1])
        r = guard("--seconds", "300", "--mb", "4096", "--", str(bend),
                  "tinybendygrad/mixin/__init__.bend", "--check-only")
        results.append(("SPLIT: stdout is the child's stdout, byte for byte",
                        r.stdout == truth.stdout and tok(r.stdout) == "NONE",
                        f"stdout {len(r.stdout)}B == child's {len(truth.stdout)}B; "
                        f"no verdict in stdout; token on stderr = {tok(r.stderr)}"))
        # The guard's stderr is the CHILD'S stderr plus the record, so the discriminator is
        # `_said` OVER THE CHILD'S HALF. Pre-fix the two were one pipe and this question had no
        # answer; asking `_said` of the whole stream would match this file's own record, which is
        # why the notice is measured against the direct invocation and the record is excluded.
        child_only = "\n".join(ln for ln in r.stderr.splitlines() if not ln.startswith(("[bounded]", "  ")))
        results.append(("NOISE: 42 bytes on stderr is the notice, and `_said` knows it",
                        _said(truth.stderr) == "" and _said(child_only) == "",
                        f"notice={len(truth.stderr)}B, _said(direct)={_said(truth.stderr)!r}, "
                        f"_said(guard's stderr minus the record)={_said(child_only)!r}"))
    else:
        results.append(("SPLIT / NOISE (needs ./bin/bend)", None, "not run: no ./bin/bend"))

    # 3, 4, 5. Both bounds fire, and the direct child, and a grandchild.
    r = guard("--seconds", "120", "--mb", "300", "--", sys.executable, "-c", bomb)
    results.append(("MEMORY: the ceiling fires", r.returncode == 3 and tok(r.stderr) == MEMORY,
                    f"exit {r.returncode}, token {tok(r.stderr)}"))
    r = guard("--seconds", "2", "--mb", "4096", "--", "/bin/sleep", "30")
    results.append(("TIME: the alarm fires", r.returncode == 4 and tok(r.stderr) == TIMEOUT,
                    f"exit {r.returncode}, token {tok(r.stderr)}"))
    grand = str(Path(tempfile.gettempdir()) / "bounded-grandchild.py")   # ABSOLUTE, and see below
    Path(grand).write_text(bomb)
    # THE ABSOLUTE PATH IS THE POINT AND IT WAS MISSED ONCE: a bare filename resolves against the
    # WORKING DIRECTORY, the grandchild never started, and the guard reported WITHIN-LIMITS -- a
    # PASS produced by a bomb that never exploded. A test that cannot fail has told me nothing
    # about the thing it names.
    r = guard("--seconds", "120", "--mb", "300", "--", sys.executable, "-c",
              "import subprocess,sys; subprocess.Popen([sys.executable, sys.argv[1]])", grand)
    results.append(("GRANDCHILD: the watchdog sees a SPAWNED child", r.returncode == 3
                    and tok(r.stderr) == MEMORY, f"exit {r.returncode}, token {tok(r.stderr)}"))

    # 6. A clean child is not a bound.
    r = guard("--seconds", "30", "--mb", "4096", "--", "/bin/echo", "ok")
    results.append(("CLEAN: exits 0, stdout untouched", r.returncode == 0
                    and r.stdout == "ok\n" and tok(r.stderr) == WITHIN,
                    f"exit {r.returncode}, stdout {r.stdout!r}, token {tok(r.stderr)}"))

    # 7. THE COLLISION, which is the whole of the exit-status contract -- and it only EXISTS when
    # the child actually says something. `sh -c 'exit 3'` in silence is caught by NO-VERDICT above
    # (a refusal that measured nothing), so the sharp case is a refusal that PRINTS: it exits 3,
    # WITHIN-LIMITS passes 3 straight through, and the status is indistinguishable from a memory
    # kill's. The tokens differ; the statuses do not. That is the contract, asserted.
    refuse = guard("--seconds", "30", "--mb", "4096", "--", "/bin/sh", "-c",
                   "echo refusing >&2; exit 3")
    kill = guard("--seconds", "120", "--mb", "300", "--", sys.executable, "-c", bomb)
    results.append((f"COLLISION: a PRINTING refusal and a kill are BOTH {STATUS[MEMORY]} -- and "
                    "the tokens differ, which is the contract",
                    refuse.returncode == kill.returncode == STATUS[MEMORY]
                    and tok(refuse.stderr) == WITHIN and tok(kill.stderr) == MEMORY,
                    f"refusal: exit {refuse.returncode}/{tok(refuse.stderr)}; "
                    f"kill: exit {kill.returncode}/{tok(kill.stderr)} -- the STATUS is ambiguous "
                    "and the TOKEN is not"))

    # 8. A command that cannot be started.
    r = guard("--seconds", "30", "--mb", "4096", "--", "/nonexistent/bounded-selftest-target")
    results.append(("NOT-STARTED: the documented exit 5, with no traceback", r.returncode == 5
                    and tok(r.stderr) == UNSTARTED and "Traceback" not in r.stderr,
                    f"exit {r.returncode}, token {tok(r.stderr)}"))

    # 9. A silent failure, and a silent SUCCESS -- `cc -fsyntax-only` and `node --check` look
    # like the second one on a clean file, so it must stay 0.
    r = guard("--seconds", "30", "--mb", "4096", "--", "/usr/bin/false")
    results.append(("NO-VERDICT: a non-zero child that said nothing", r.returncode == 6
                    and tok(r.stderr) == NOVERDICT, f"exit {r.returncode}, token {tok(r.stderr)}"))
    r = guard("--seconds", "30", "--mb", "4096", "--", "/usr/bin/true")
    results.append(("SILENT 0 STAYS 0: a clean `cc -fsyntax-only` must not be reddened",
                    r.returncode == 0 and tok(r.stderr) == WITHIN,
                    f"exit {r.returncode}, token {tok(r.stderr)}"))

    # 10. The pipe the old file wrote into: 1 MB is 934,215 bytes past the 64 KB a pipe holds.
    r = guard("--seconds", "10", "--mb", "4096", "--", "/bin/sh", "-c",
              "head -c 1000000 /dev/zero | tr '\\0' 'x'")
    results.append(("FILL: 1 MB on stdout does not deadlock the guard", r.returncode == 0
                    and len(r.stdout) == 1000000,
                    f"exit {r.returncode}, {len(r.stdout)}B captured (a pipe holds 65,536)"))

    # 11. The grandchild that outlives its parent -- the pre-fix guard called this WITHIN-LIMITS
    # at 3 MB with the bomb past 1 GB.
    r = guard("--seconds", "60", "--mb", "300", "--", sys.executable, "-c",
              "import os,subprocess,sys; pid=os.fork()\n"
              "if pid == 0: os.execv(sys.executable, [sys.executable, sys.argv[1]])\n"
              "sys.exit(0)", grand)
    results.append(("ORPHAN: a grandchild is still watched after its parent exits",
                    r.returncode == 3 and tok(r.stderr) == MEMORY,
                    f"exit {r.returncode}, token {tok(r.stderr)}"))

    # 12. CONTROL, and it pins a lie that is NOT this file's: `bend` calls a 0-byte file PROOF.
    # If a future bend stops lying, this case goes red and somebody has to look.
    if os.access(bend, os.X_OK):
        empty = Path(tempfile.gettempdir()) / "bounded-empty.bend"
        empty.write_bytes(b"")
        truth = subprocess.run([str(bend), str(empty), "--check-only"], capture_output=True,
                               text=True, cwd=here.parents[1])
        r = guard("--seconds", "120", "--mb", "4096", "--", str(bend), str(empty), "--check-only")
        results.append(("CONTROL: a 0-byte input is `ALL PROOFS CHECK`, and WITHIN-LIMITS claims "
                        "only the bounds", truth.returncode == 0
                        and "ALL PROOFS CHECK" in truth.stdout and tok(r.stderr) == WITHIN,
                        f"bend says {truth.stdout.splitlines()[0]!r} for 0 bytes; the guard says "
                        f"{tok(r.stderr)} -- which is a claim about the CEILING, not a proof"))
        empty.unlink(missing_ok=True)
    else:
        results.append(("CONTROL 0-byte (needs ./bin/bend)", None, "not run: no ./bin/bend"))
    Path(grand).unlink(missing_ok=True)

    failed = 0
    for name, ok, detail in results:
        print(f"[{('PASS' if ok else 'NOT RUN' if ok is None else 'FAIL'):>7}] {name}\n"
              f"          {detail}")
        failed += 1 if ok is False else 0
    ran = sum(ok is not None for _, ok, _ in results)
    print(f"\n=== selftest {'PASS' if not failed else 'FAIL'}: {ran} case(s) run, {failed} failed"
          + (", and NOT RUN IS NOT PASS" if ran != len(results) else "") + " ===")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
