"""Re-run the executor-bound test/null files under DEV=BEND with the POST-FIX executor, one process
per file, and report whether each now completes (the fix's effect on the reachable fraction).

The file set is the bend suite's zero-measured set, named in its own sweep-bend.tsv (verdict
FAULTHANDLER-TIMEOUT or KILLED-BY-SWEEP with 0 passed/failed/errored).

usage: .venv/bin/python reach.py [--timeout S]
"""
import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent

FILES = [
    "test_allreduce", "test_arange", "test_assign", "test_attention", "test_function",
    "test_linearizer", "test_real_world", "test_schedule", "test_symbolic_tensor", "test_winograd",
]
SUMMARY = re.compile(r"(\d+) (passed|failed|error|errors|skipped|xfailed)")


def counts(text: str) -> dict[str, int]:
    """Count `-v` per-test lines, so an ABORTED file still reports the tests that DID complete:
    the faulthandler kills the process with exit=True, so a summary line may never be printed."""
    c = {"passed": 0, "failed": 0, "errored": 0, "skipped": 0}
    for ln in text.splitlines():
        for kind in c:
            if f" {kind.upper()} " in ln or ln.endswith(f" {kind.upper()}"):
                c[kind] += 1
                break
    if not any(c.values()):
        for n, kind in SUMMARY.findall(text):
            key = {"error": "errored", "errors": "errored"}.get(kind, kind)
            c[key] = c.get(key, 0) + int(n)
    return c


def main() -> None:
    argv = sys.argv[1:]
    per = 240.0
    if argv and argv[0] == "--timeout":
        per, argv = float(argv[1]), argv[2:]
    files = [f for f in FILES if not argv or f in argv]
    rows = ["file\tverdict\twall_s\tpassed\tfailed\terrored\tskipped"]
    print(rows[0], flush=True)
    for stem in files:
        env = dict(os.environ, DEV="BEND", TEST_TIMEOUT="180")
        t = time.perf_counter()
        killed = False
        try:
            r = subprocess.run([str(ROOT / ".venv/bin/python"), "-m", "pytest", f"test/null/{stem}.py",
                                "-v", "-p", "no:cacheprovider", "--continue-on-collection-errors"],
                               cwd=ROOT, env=env, capture_output=True, text=True, timeout=per)
            rc, out = r.returncode, r.stdout + r.stderr
        except subprocess.TimeoutExpired as e:
            killed, rc = True, -1
            out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        wall = time.perf_counter() - t
        (OUT / f"reach-{stem}.out").write_text(out)
        c = counts(out)
        v = "KILLED-BY-SWEEP" if killed else ("COMPLETED" if SUMMARY.search(out) else "ABORTED")
        row = "\t".join([stem, v, f"{wall:.1f}", str(c.get("passed", 0)), str(c.get("failed", 0)),
                         str(c.get("errored", 0)), str(c.get("skipped", 0))])
        rows.append(row)
        print(row, flush=True)
    (OUT / "reach.tsv").write_text("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
