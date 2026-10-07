#!/usr/bin/env python3
"""Two things a hook author must not assume, each measured.

  H  does `git commit` preserve a pre-commit hook's exit 3, or flatten every refusal to 1?
  X  what does a gate that CRASHES look like next to one that REFUSES? If a runner cannot
     tell them apart it will turn a broken instrument into a pass, which is the whole
     `refusalsweep`/`envguard` finding.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

LIVE = Path(__file__).resolve().parents[3]
WORK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/hookprobe")
PY = sys.executable
bad = []


def git(*a, cwd=WORK):
    return subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True)


def hook(name, body):
    p = WORK / ".git" / "hooks" / name
    p.write_text(body)
    p.chmod(0o755)


def stage(path, body):
    (WORK / path).write_text(body)
    git("add", path)


def main():
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    git("init", "-q", "-b", "main")
    git("config", "user.email", "p@example.invalid")
    git("config", "user.name", "probe")
    stage("seed.tsv", "a\n")
    git("commit", "-q", "-m", "seed")

    # ---- H: the hook's OWN exit code vs the exit code git RETURNS --------------
    print("H  a pre-commit hook that exits 3 (REFUSED)")
    for want, label in ((3, "REFUSED 3"), (1, "FAIL 1"), (5, "DEAD 5"), (4, "SKIP 4")):
        hook("pre-commit", f"#!/bin/sh\nexit {want}\n")
        stage(f"{want}.tsv", f"{want}\n")
        r = git("commit", "-m", f"honest message, no claims {want}")
        print(f"   hook exits {label:>9} -> `git commit` returns rc={r.returncode}")
        if r.returncode != want:
            bad.append(f"H: hook exit {want} -> git commit rc {r.returncode}")
    hook("pre-commit", "#!/bin/sh\nexit 0\n")
    stage("ok.tsv", "ok\n")
    print(f"   hook exits PASS 0     -> `git commit` returns rc="
          f"{git('commit', '-q', '-m', 'seed the ok row').returncode}")

    # ---- X: REFUSED beside CRASHED, and a runner's naive aggregation -----------
    print("\nX  a runner that maps exit codes without reading a word")
    cases = {
        "REFUSED, precondition absent (exit 3)": (LIVE / "gates/msgdiff-gate.py", "check", "00b101574"),
        "DEAD, git could not answer  (exit 5)": (LIVE / "gates/msgdiff-gate.py", "check", "0" * 40),
        "SKIP, nothing to measure  (exit 4)": (LIVE / "gates/msgdiff-gate.py", "check"),
        "CRASH, traceback          (exit 1)": (LIVE / "gates/msgdiff-gate.py", "nonsense-mode"),
        "PASS                        (exit 0)": (LIVE / "gates/msgdiff-gate.py", "check", "HEAD"),
    }
    print(f"   {'case':<44} {'rc':>3}  first line of output")
    for label, (g, *a) in cases.items():
        r = subprocess.run([PY, str(g), *a], capture_output=True, text=True, cwd=str(LIVE))
        out = ((r.stdout or "") + (r.stderr or "")).strip().splitlines()
        first = out[0][:52] if out else "<silent>"
        print(f"   {label:<44} {r.returncode:>3}  {first}")
        if r.returncode == 1 and "Traceback" not in (r.stdout or "") + (r.stderr or ""):
            bad.append(f"X: {label} returned 1 without a traceback -- 1 is ambiguous")

    # ---- the aggregation a runner must NOT do --------------------------------
    # `all(rc == 0)` is the tempting one-liner. Under it, 3/4/5 are all "not a pass",
    # which is right; but `rc != 0` as "RED" also claims a SKIP is a FAIL, and `rc == 0`
    # as "GREEN" claims a crashed-as-0 gate is agreement. Show the degenerate case.
    silent = WORK / "silent-gate.py"
    silent.write_text("import sys\nsys.exit(0)\n")   # exits 0 having measured nothing
    r = subprocess.run([PY, str(silent)], capture_output=True, text=True)
    print(f"\n   a gate that exits 0 SILENTLY: rc={r.returncode}, "
          f"bytes of output={len(r.stdout) + len(r.stderr)}")
    print("   under `all(rc==0)` that is GREEN. It is the AGENTS.md sentence exactly:")
    print("   'a gate that exits 0 having measured nothing is worse than no gate'.")

    print(f"\n--probe: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
