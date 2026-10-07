#!/usr/bin/env python3
"""d7-run.py -- THE FOUR, each with its subject RESTORED FROM GIT, each RUN.

A gate that has been refusing may have been hiding a defect, so the answer to
"is it a gate or a statement" cannot be a reason.  It has to be an exit code.

Every restore is guarded three ways: the path must be ABSENT before the write
(another unit may own it), the bytes written are compared against
`git cat-file blob <rev>:<path>` AFTER the write, and every removal is in a
`finally` with the residue counted.

DISCLOSURE, FIRST: restoring these subjects RUNS `bend` (nl-gate.py and
rn-gate.py's lanes drive the port binary).  This unit was told not to run bend
unless nothing else needed it; the brief's own question -- what would the gate say
if its subject came back -- needs it, and `modulerefuse` recorded the same run.

No .txt.
"""
import os, subprocess, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
GITENV = dict(os.environ, GIT_INDEX_FILE=".git/agent-index")
BUDGET = 180
SWEEP = "371cc64c9^"

# gate -> the paths its own module-scope guard names, and where git still has them.
PLAN = [
    ("checks/nl-gate.py", [(".agents/slop/nl/nl-oracle.py", f"{SWEEP}:.agents/slop/nl/nl-oracle.py")],
     [[], ["--compare"], ["--port-stdout", "@empty", "--oracle-stdout", "@empty"]]),
    ("checks/nl-gate-noguard.py", [(".agents/slop/nl/nl-oracle.py", f"{SWEEP}:.agents/slop/nl/nl-oracle.py")],
     [[], ["--port-stdout", "@empty", "--oracle-stdout", "@empty"]]),
    ("checks/gate.py", [("checks/drive.mjs", f"{SWEEP}:.agents/slop/jsfp8/drive.mjs")],
     [[], ["--quick"]]),
    ("checks/cl-port-gate.py",
     [(".agents/slop/clangshim/oracle.py", f"{SWEEP}:.agents/slop/clangshim/oracle.py"),
      (".agents/slop/clangshim/libclang-ffi.c", f"{SWEEP}:.agents/slop/clangshim/libclang-ffi.c"),
      (".agents/slop/clangshim/fixture.h", f"{SWEEP}:.agents/slop/clangshim/fixture.h")],
     [[], ["--plants"]]),
]


def blob(ref):
    r = subprocess.run(["git", "cat-file", "blob", ref], cwd=REPO,
                       capture_output=True, env=GITENV, timeout=120)
    return r.stdout if r.returncode == 0 else None


def run(rel, argv, extra=()):
    with tempfile.TemporaryDirectory() as td:
        empty = Path(td) / "empty.rows"
        empty.write_text("")
        out = [str(empty) if a == "@empty" else a for a in argv]
        t0 = time.time()
        try:
            r = subprocess.run([str(PY), str(REPO / rel), *out, *extra], cwd=REPO,
                               capture_output=True, text=True, timeout=BUDGET)
        except subprocess.TimeoutExpired:
            return "TIMED-OUT", "", time.time() - t0
        return r.returncode, (r.stdout + r.stderr), time.time() - t0


def show(rc, txt, dt, indent="      "):
    lines = [l for l in txt.strip().splitlines() if l.strip()]
    print(f"{indent}rc={str(rc):9} {dt:5.1f}s")
    for l in lines[-6:]:
        print(f"{indent}{l[:104]}")


def main():
    print(f"read {time.strftime('%H:%M:%S')}. BUDGET={BUDGET}s. git cat-file blob, GIT_INDEX_FILE set.\n")
    created = []
    try:
        for rel, subjects, argvs in PLAN:
            print(f"===== {rel}")
            rc0, txt0, dt0 = run(rel, [])
            show(rc0, txt0, dt0)
            restored, blocked, missing = [], [], []
            for path, ref in subjects:
                fp = REPO / path
                if fp.exists():
                    blocked.append(f"{path} ALREADY ON DISK ({fp.stat().st_size} B) -- not ours, not touched")
                    continue
                data = blob(ref)
                if data is None:
                    missing.append(f"{path}: NO BLOB at {ref}")
                    continue
                fp.parent.mkdir(parents=True, exist_ok=True)
                fp.write_bytes(data)
                created.append(fp)
                exact = fp.read_bytes() == data
                restored.append(f"{path} {len(data)} B <- {ref} byte-exact={exact}")
            for m in restored + blocked + missing:
                print(f"    restore: {m}")
            if not restored:
                print("    NOTHING RESTORED -- the gate will refuse again, and that is the finding\n")
                continue
            for argv in argvs:
                print(f"    WITH THE SUBJECT RESTORED, argv = {' '.join(argv) or '(none)'}")
                rc, txt, dt = run(rel, argv)
                show(rc, txt, dt)
                import re
                g = re.search(r"gated (\d+)", txt)
                if g:
                    print(f"      >>> DENOMINATOR the gate printed: gated={g.group(1)}")
            print()
    finally:
        for fp in created:
            fp.unlink(missing_ok=True)
            d = fp.parent
            while d != REPO and REPO in d.parents:
                try:
                    next(d.iterdir())
                    break
                except StopIteration:
                    d.rmdir()
                except OSError:
                    break
                d = d.parent
    residue = [str(p.relative_to(REPO)) for p in created if p.exists()]
    print(f"RESTORED {len(created)} path(s); RESIDUE {len(residue)} {residue}")


if __name__ == "__main__":
    main()