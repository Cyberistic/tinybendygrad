#!/usr/bin/env python3
"""pushshim.py -- the pre-push adapter for a gate that has no `push` mode.

`gates/msgdiff-gate.py` offers `check <rev>` and `range <rev-list args...>` and nothing else.
It does not need a new mode for pre-push: `range` forwards its argv straight to `git rev-list`
(`gates/msgdiff-gate.py:233-238`), so `range <local> --not <remote>` already IS the pre-push
half. What is missing is the ARGUMENT, and this is where it is genuinely missing:

  MEASURED on this git: a pre-push hook receives argc=2 -- `$1` remote name, `$2` remote URL --
  and the refspecs on STDIN as `<local_ref> <local_sha> <remote_ref> <remote_sha>` per line.
  `.agents/slop/jjreset/wire.py:31` generates `... push "$@"`, and the gate's `mode_push` then
  reads `argv[1]` (the remote NAME) instead of stdin, so every line misses its 4-field check
  and the function falls through to `return PASS`. MEASURED end to end in `_deadpush.py`: a
  520-file deletion was PUSHED, the hook printed nothing, and `git push` returned 0. Removing
  `"$@"` -- so the gate reads stdin as its own docstring says it does -- REFUSES the same
  push. One token is the whole difference between a guard and a decoration.

WHY THIS SHIM EXISTS ANYWAY. A shell hook cannot read stdin into positional parameters
without either `read` (which is `sh`-fine but needs a parse loop) or a subshell, and `sh` here
has already cost this tree four documented failures. So the parsing is Python, and the hook
stays two lines.

THE VERDICT FILE. MEASURED in `_probe_hooks.py` state H: `git push` returns 1 whether the hook
exited 3, 4 or 5. REFUSED, SKIP and DEAD are indistinguishable from the exit code alone, so
the verdict is appended to `last-verdict.tsv` where it can still be told apart. The five exits
of `gates/gatekit.py:60` and NO sixth.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MSG = ROOT / "gates/msgdiff-gate.py"
VERDICT = HERE / "last-verdict.tsv"
PASS, REFUSED, SKIP, DEAD = 0, 3, 4, 5
ZERO = "0" * 40


def spec_lines():
    out = []
    for raw in sys.stdin.read().splitlines():
        parts = raw.split()
        if len(parts) == 4:
            out.append(parts)
    return out


def judge(local_sha, remote_sha):
    """`range local --not remote`. On a FIRST push (`remote_sha` all zeros) the remote has
    nothing, so this is the whole branch history -- which is a POLICY, not a gate, and is why
    the caller can ack it out with `MESSAGE_DIFF_ACK`."""
    argv = [sys.executable, str(MSG), "range", local_sha, "--not", remote_sha]
    r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
    for line in ((r.stdout or "") + (r.stderr or "")).splitlines():
        print(line)
    return r.returncode


def main():
    rows = spec_lines()
    if not rows:
        # Nothing on stdin that is a refspec. That is NOT a pass: it is a hook that could not
        # see what it was asked to judge, and `AGENTS.md`'s SKIP is not a PASS.
        print(f"pushshim: DEAD: pre-push stdin carried no 4-field refspec (got {len(rows)})",
              file=sys.stderr)
        return DEAD
    rc = PASS
    for _local_ref, local_sha, _remote_ref, remote_sha in rows:
        if local_sha == ZERO:
            continue
        one = judge(local_sha, remote_sha)
        rc = one if one != PASS else rc
    with VERDICT.open("a") as fh:
        fh.write(f"hook\tpre-push\t{rc}\t{len(rows)} refspec(s)\n")
    return rc


if __name__ == "__main__":
    sys.exit(main())
