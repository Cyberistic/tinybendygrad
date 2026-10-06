#!/usr/bin/env python3
"""THE THREE UPSTREAM TESTS THE SIX COMMITS ADDED, RUN UNDER BOTH COMPILERS.

`compare.py` over the port's own 138 files answers "does the PORT compile the
same".  This answers the sharper question the six commit subjects point at:
"do the SPECIFIC CONSTRUCTS those commits changed behave the same", using the
upstream tests the commits themselves added.

    tests/check/erased_field_bare_arm.bend    #1157  a match inside a TYPE
    tests/check/spec_arg_depth.bend           #1168  a SPECIALIZED argument's depth
    tests/check/spec_arg_unused_column.bend   #1178  a SPECIALIZED argument's liveness

All three exist ONLY at HEAD -- `git show v2.0.34:tests/check/...` says
`path ... exists on disk, but not in 'v2.0.34'` for each -- so the tag lane
answers "no such file" for them, and the two lanes cannot be compared on a file
one of them cannot see.  Each is therefore COPIED OUT of the checkout into a
scratch dir and run under both, which is the only way the pre-fix behaviour is
observable at all.

Two lanes, ONE PROCESS AT A TIME, under BOTH bounds:
    tag   bun <worktree>/bend2/main.ts
    head  ./bin/bend

`--verdict` IS THE LANE THESE COMMITS ARE ABOUT -- every one of the three
subjects names it -- AND IT CANNOT RUN HERE: `safe_check` builds
`bend2/bendtt.lean` with Lean, and `lean` is not on PATH on this machine.
MEASURED:
    Error: the kernel did not build (lean: Executable not found in $PATH: "lean")
So this runs `--check-only`, and every row says which lane it ran.  A reader
must not read "same" as "the kernel agreed": the kernel was never asked.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
REF = REPO / "references" / "bend"
BOUNDED = REPO / "checks" / "bounded.py"
PY = REPO / ".venv/bin/python"
UPDATE_NOTICE = re.compile(r"^bend [\d.]+ is available: run bend update\s*$", re.M)

TESTS = [
    ("erased_field_bare_arm", "tests/check/erased_field_bare_arm.bend", "#1157 a match inside a TYPE"),
    ("spec_arg_depth", "tests/check/spec_arg_depth.bend", "#1168 a SPECIALIZED argument's DEPTH"),
    ("spec_arg_unused_column", "tests/check/spec_arg_unused_column.bend", "#1178 a SPECIALIZED argument's LIVENESS"),
]


def strip_noise(t: str) -> str:
    return UPDATE_NOTICE.sub("", t).strip()


def lane(cmd: list[str], f: Path, mode: str) -> dict[str, str]:
    p = subprocess.run(
        [str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--", *cmd, str(f), mode],
        cwd=REPO, capture_output=True, text=True,
    )
    out = strip_noise(p.stdout)
    first = next((ln for ln in out.splitlines() if ln.strip()), "(silent)")
    m = re.search(r"\[bounded\] (\S+)", p.stderr)
    bound = m.group(1) if m else "(no-token)"
    child_err = strip_noise("\n".join(ln for ln in p.stderr.splitlines() if not ln.startswith("[bounded] ")))
    return {
        "verdict": first if bound == "WITHIN-LIMITS" else bound,
        "bound": bound,
        "rc": str(p.returncode),
        "sha": hashlib.sha256((out + "\x00" + child_err).encode()).hexdigest()[:16],
    }


def emit_bendtt(cmd: list[str], f: Path, out: Path) -> dict[str, str]:
    """The KERNEL ELABORATION, which needs no Lean.

    `--verdict` cannot run on this machine -- `lean` is not on PATH -- and the
    three commits are about what the kernel ELABORATES, not about what
    `--check-only` accepts.  So this is the lane that reaches the change:
    `-o out.bendtt` runs `safe_emit`, which elaborates and reports every def
    that goes OUT OF SCOPE, and Lean is only needed to CHECK the result.  Two
    rows per test: the out-of-scope set, and the elaboration's bytes.

    THE OUT-OF-SCOPE SET IS THE ROW THAT MATTERS.  `#1157` is "before, the first
    went out live and the kernel rejected it, and the second was out of scope";
    `#1168` is a lambda-match with a default arm "out of scope"; `#1178` is a
    wrong-but-well-typed body `--verdict` ACCEPTED.  So `0 out of scope` is the
    fix being present, and it is legible without Lean.
    """
    if out.exists():
        out.unlink()
    p = subprocess.run(
        [*cmd, str(f), "-o", str(out)], cwd=REPO, capture_output=True, text=True,
    )
    err = strip_noise(p.stderr)
    oos = tuple(sorted(re.findall(r"^- (\S+):", err, re.M)))
    body = out.read_text() if out.exists() else ""
    return {
        "oos": ",".join(oos) or "(none)",
        "n_oos": str(len(oos)),
        "bytes": str(len(body)),
        "sha": hashlib.sha256(body.encode()).hexdigest()[:16] if body else "(no-file)",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tag", type=Path, required=True, help="worktree at v2.0.34")
    ap.add_argument("--rows", type=Path, required=True)
    ap.add_argument("--mode", default="--check-only", choices=["--check-only", "--verdict"])
    ap.add_argument("--keep", type=Path, help="keep the scratch .bend and .bendtt files here")
    args = ap.parse_args()

    rows = [f"lane={args.mode}", f"tag_worktree={args.tag}"]
    disagree = oos_disagree = elab_disagree = 0
    td = None
    scratch = args.keep if args.keep else Path(tempfile.mkdtemp(prefix="bendregress-"))
    td = str(scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        for name, rel, what in TESTS:
            src = REF / rel
            # copied OUT of the checkout: the tag worktree has no such file, and
            # a scratch file is also what keeps this from reading a checkout
            # that six other units are running from.
            dst = scratch / f"{name}.bend"
            shutil.copyfile(src, dst)
            in_tag = subprocess.run(
                ["git", "-C", str(args.tag), "cat-file", "-e", f"v2.0.34:{rel}"],
                capture_output=True,
            ).returncode == 0
            t = lane(["bun", str(args.tag / "bend2" / "main.ts")], dst, args.mode)
            h = lane([str(REPO / "bin" / "bend")], dst, args.mode)
            same = t["verdict"] == h["verdict"] and t["sha"] == h["sha"]
            et = emit_bendtt(["bun", str(args.tag / "bend2" / "main.ts")], dst, scratch / f"{name}.tag.bendtt")
            eh = emit_bendtt([str(REPO / "bin" / "bend")], dst, scratch / f"{name}.head.bendtt")
            oos_same = et["oos"] == eh["oos"]
            elab_same = et["sha"] == eh["sha"]
            disagree += not same
            oos_disagree += not oos_same
            elab_disagree += not elab_same
            rows.append(
                f"{name}\t{what}\tin_tag={in_tag}\ttag={t['verdict']}\thead={h['verdict']}\t"
                f"check_same={'yes' if same else 'NO'}\tsha_tag={t['sha']}\tsha_head={h['sha']}\t"
                f"oos_tag={et['n_oos']}\toos_head={eh['n_oos']}\toos_same={'yes' if oos_same else 'NO'}\t"
                f"oos_which={et['oos'] if not oos_same else ''}\t"
                f"elab_bytes={et['bytes']}/{eh['bytes']}\telab_same={'yes' if elab_same else 'NO'}"
            )
            print(f"{name:24} check_same={'yes' if same else 'NO'}  "
                  f"oos_tag={et['n_oos']} oos_head={eh['n_oos']} oos_same={'yes' if oos_same else 'NO'}  "
                  f"elab_same={'yes' if elab_same else 'NO'}", file=sys.stderr)
    finally:
        if args.keep is None:
            shutil.rmtree(td, ignore_errors=True)
    rows.append(
        f"SUMMARY\ttests={len(TESTS)}\tcheck_disagree={disagree}\toos_disagree={oos_disagree}\telab_disagree={elab_disagree}"
    )
    args.rows.write_text("\n".join(rows) + "\n")
    # A disagreement in the ELABORATION is a real finding and must not be
    # laundered into a pass by returning on the `--check-only` verdict alone.
    return 1 if (disagree or oos_disagree or elab_disagree) else 0


if __name__ == "__main__":
    sys.exit(main())