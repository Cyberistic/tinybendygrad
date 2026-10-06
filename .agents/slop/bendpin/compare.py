#!/usr/bin/env python3
"""DOES THE PORT COMPILE THE SAME UNDER v2.0.34 AS IT DOES UNDER v2.0.34-6-g0187512?

The question is not "is the pin right".  It is whether MOVING the checkout from
where it is to where the pin says it should be changes any answer.  If it does
not, the pin is cosmetic and the drift is harmless.  If it does, the pin IS the
finding and nobody should have assumed either.

THE DENOMINATOR IS EVERY `.bend` FILE IN THE TREE, not a sample.  `tinybendygrad/`
holds 138 of them and 11 MB, and a `--check-only` pass over a 67 KB file costs
0.34 s and 33 MB, so the whole corpus is affordable and a sample would be a
choice nobody asked for.  `files=138 of 138` is printed by the summary and the
summary refuses to print a verdict line if that number is not 138.

TWO LANES, ONE PROCESS AT A TIME.  `sz.bend` peaks at 1,468 MB and a green gate
run peaks at 1,713-2,072 MB, so every lane goes through `checks/bounded.py` under
a 2,048 MB ceiling and NOTHING IS RUN CONCURRENTLY.  A memory kill is a TOKEN, not
an exception, and `KILLED-ON-MEMORY` is compared like any other token: both lanes
get the same bound, so "both killed" is agreement about the bound and not about
the program.

THE COMPARISON UNIT IS THE VERDICT TOKEN -- `ALL PROOFS CHECK` /
`SOME PROOFS FAIL` / `KILLED-ON-MEMORY` / `TIMED-OUT` -- NOT THE EXIT CODE.
`--check-only` exits 0 on a file this repo calls fine, and `bounded.py`'s status
is a coarse summary of two bounds at once.

AND THE 42 BYTES ON STDERR ARE STRIPPED BEFORE ANY HASH.  `bend` prints
`bend 2.0.35 is available: run bend update` on EVERY invocation, green ones
included -- 42 bytes, MEASURED.  Hashing raw stderr would report every file as
different between two runs of the SAME compiler.

USAGE
  .venv/bin/python .agents/slop/bendpin/compare.py --rows OUT.rows [--tag DIR]
  --tag DIR   a worktree at v2.0.34.  Created by `pin_check.py --mkworktree`,
              which asserts the worktree's HEAD is the tag's commit BEFORE this
              script is allowed to call it a tag lane.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BOUNDED = REPO / "checks" / "bounded.py"
PY = REPO / ".venv/bin/python"

# THE BACKGROUND NOISE, MEASURED AT 42 BYTES ON A GREEN FILE.  Stripped, and the
# byte count is asserted below rather than assumed -- if upstream ever stops
# printing it, the assertion fires and the strip becomes a no-op that is KNOWN to
# be one, which is the difference between a measurement and a habit.
UPDATE_NOTICE = re.compile(r"^bend [\d.]+ is available: run bend update\s*$", re.M)

MB = 1024 * 1024


def strip_noise(text: str) -> str:
    return UPDATE_NOTICE.sub("", text).strip()


def verdict_of(stdout: str) -> str:
    """The first non-empty stdout line, or `(silent)`.

    `--check-only`'s FIRST LINE is the contract in this repo (TOOLS.md, the e2e
    header, and `README.md` of `tinybendygrad/viz`), because a broken file prints
    its refusal on stdout and exits 0.
    """
    for line in stdout.splitlines():
        if line.strip():
            return line.strip()
    return "(silent)"


def lane(cmd: list[str], file: Path) -> dict[str, str]:
    """One `--check-only` under BOTH bounds, one process, and read the TOKEN."""
    proc = subprocess.run(
        [str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--", *cmd, str(file), "--check-only"],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    # bounded.py keeps its own record on stderr and nothing of its own on stdout,
    # so stdout here is the child's, byte for byte.
    bounded = proc.stderr
    token = verdict_of(stdout := proc.stdout)
    m = re.search(r"\[bounded\] (\S+)", bounded)
    bound = m.group(1) if m else "(no-token)"
    # THE CHILD'S STDERR, WITH bounded.py's OWN RECORD REMOVED.  The record is
    # one `[bounded] ` line and it PRINTS THE COMMAND LINE, which differs between
    # the lanes BY CONSTRUCTION -- `bun /.../bendtag/bend2/main.ts` against
    # `./bin/bend`.  Hashing it reported all 138 files as DIFF with identical
    # verdict tokens: the instrument comparing the two lane's ARGUMENT VECTORS.
    # A byte comparison is only about the program if both sides are the program.
    err = "\n".join(ln for ln in bounded.splitlines() if not ln.startswith("[bounded] "))
    err = strip_noise(err)
    m2 = re.search(r"err=(\d+)B", bounded)
    stderr_bytes = m2.group(1) if m2 else "?"
    digest = hashlib.sha256((strip_noise(stdout) + "\x00" + err).encode()).hexdigest()[:16]
    return {
        "token": token if bound == "WITHIN-LIMITS" else f"{bound}",
        "raw_first_line": verdict_of(stdout),
        "bound": bound,
        "rc": str(proc.returncode),
        "stderr_bytes_measured": stderr_bytes,
        "sha": digest,
    }


def corpus() -> list[Path]:
    return sorted(Path(p) for p in (REPO / "tinybendygrad").rglob("*.bend"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", type=Path, required=True, help="write name=value rows here")
    ap.add_argument("--tag", type=Path, required=True, help="worktree at the pinned tag")
    ap.add_argument("--head", type=Path, default=REPO / "bin" / "bend", help="the HEAD shim, measured through itself")
    ap.add_argument("--only", type=int, default=0, help="first N files only (0 = all)")
    args = ap.parse_args()

    tag_main = args.tag / "bend2" / "main.ts"
    if not tag_main.exists():
        print(f"NO TAG LANE: {tag_main} is not there", file=sys.stderr)
        return 2

    files = corpus()
    if args.only:
        files = files[: args.only]
    rows: list[str] = []
    agree = disagree = 0

    for i, f in enumerate(files, 1):
        rel = f.relative_to(REPO)
        # ONE PROCESS AT A TIME.  The two lanes are sequential statements, never
        # a thread pool, and there is no --jobs flag to add later.
        t = lane(["bun", str(tag_main)], f)
        h = lane([str(args.head)], f)
        same = t["token"] == h["token"] and t["sha"] == h["sha"]
        agree += same
        disagree += not same
        rows.append(
            f"{rel}\tsize={f.stat().st_size}\ttag={t['token']}\thead={h['token']}\t"
            f"same={'yes' if same else 'NO'}\tbound={t['bound']}/{h['bound']}\tsha_tag={t['sha']}\tsha_head={h['sha']}"
        )
        print(f"[{i}/{len(files)}] {'same ' if same else 'DIFF '} {rel}  tag={t['token']!r} head={h['token']!r}", file=sys.stderr)

    rows.append(f"SUMMARY\tfiles={len(files)}\tagree={agree}\tdisagree={disagree}\tdenominator={len(corpus())}")
    args.rows.write_text("\n".join(rows) + "\n")
    print(f"\nfiles={len(files)} agree={agree} disagree={disagree} -> {args.rows}", file=sys.stderr)
    return 0 if disagree == 0 else 1


if __name__ == "__main__":
    sys.exit(main())