"""Per-file BEND sweep: run each upstream test file under DEV=BEND in its own pytest process.

WHY PER-FILE AND NOT ONE PROCESS. conftest.py installs a per-test watchdog
(faulthandler.dump_traceback_later(TEST_TIMEOUT, exit=True)) that kills the WHOLE pytest process. So one
slow test in a 200-test file takes the other 199 down with it, and a single whole-suite run reports
nothing about them. A process per file bounds that blast radius to one file.

THE FIVE NUMBERS ASKED OF EVERY RUN: collected, passed, failed, errored, skipped (+xfailed). A file that
prints no pytest summary measured NOTHING -- it is ABORTED or KILLED-BY-SWEEP, never a pass.

Population by DISCOVERY (doctrine 1): os.walk over test/null for test_*.py, never a hand list.
"""
import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent / "bend"
OUT.mkdir(parents=True, exist_ok=True)

DEV = sys.argv[1] if len(sys.argv) > 1 else "BEND"
PER_FILE_TIMEOUT = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0
TEST_TIMEOUT = str(int(PER_FILE_TIMEOUT * 0.8))

SUMMARY = re.compile(r"(\d+) (passed|failed|error|errors|skipped|xfailed|xpassed)")


def discover() -> list[pathlib.Path]:
    return sorted(p for p in (ROOT / "test" / "null").glob("test_*.py"))


def parse_counts(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for n, kind in SUMMARY.findall(text):
        key = {"error": "errored", "errors": "errored"}.get(kind, kind)
        counts[key] = counts.get(key, 0) + int(n)
    return counts


def verdict_for(text: str, rc: int, killed: bool) -> str:
    if killed:
        return "KILLED-BY-SWEEP"
    if "Timeout (" in text:
        return "FAULTHANDLER-TIMEOUT"
    if SUMMARY.search(text):
        return "COMPLETED" if rc == 0 else "COMPLETED-RED"
    return "ABORTED"


def main() -> None:
    files = discover()
    print(f"# device={DEV} files={len(files)} per_file_timeout={PER_FILE_TIMEOUT}s test_timeout={TEST_TIMEOUT}s")
    header = "file\tverdict\twall_s\tcollected\tpassed\tfailed\terrored\tskipped\txfailed"
    print(header)
    rows = [header]
    for f in files:
        env = {**os.environ, "DEV": DEV, "TEST_TIMEOUT": TEST_TIMEOUT}
        # the denominator: collected test ids, from a collect-only pass (imports the module, runs nothing)
        try:
            cr = subprocess.run(
                [str(ROOT / ".venv/bin/python"), "-m", "pytest", str(f.relative_to(ROOT)),
                 "-q", "-p", "no:cacheprovider", "--collect-only"],
                cwd=ROOT, env=env, capture_output=True, text=True, timeout=PER_FILE_TIMEOUT,
            )
            collected = sum(1 for ln in (cr.stdout or "").splitlines() if "::" in ln)
        except subprocess.TimeoutExpired:
            collected = 0
        t = time.perf_counter()
        killed = False
        try:
            r = subprocess.run(
                [str(ROOT / ".venv/bin/python"), "-m", "pytest", str(f.relative_to(ROOT)),
                 "-q", "-p", "no:cacheprovider", "--continue-on-collection-errors", "-rE"],
                cwd=ROOT, env=env, capture_output=True, text=True, timeout=PER_FILE_TIMEOUT,
            )
            rc, out = r.returncode, r.stdout + r.stderr
        except subprocess.TimeoutExpired as e:
            killed = True
            rc = -1
            out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        wall = time.perf_counter() - t
        (OUT / f"{f.stem}.out").write_text(out)
        c = parse_counts(out)
        v = verdict_for(out, rc, killed)
        row = "\t".join([str(f.relative_to(ROOT)), v, f"{wall:.1f}",
                         str(collected), str(c.get("passed", 0)), str(c.get("failed", 0)),
                         str(c.get("errored", 0)), str(c.get("skipped", 0)), str(c.get("xfailed", 0))])
        rows.append(row)
        print(row, flush=True)
    (pathlib.Path(__file__).resolve().parent / f"sweep-{DEV.lower()}.tsv").write_text("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
