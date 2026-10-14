#!/usr/bin/env python3
"""The negative control: a synthetic tree with one write site per spelling, and the answer.

    usage: .venv/bin/python .agents/slop/constfix/selftest.py

**THIS FILE EXISTS BECAUSE THE CENSUS REPORTED `0 INVISIBLE SITES` AND THAT NUMBER WAS WORTH
NOTHING.** MEASURED 2026-10-14: `writecensus.py --sites` printed "write sites that MENTION
`.agents/slop` but yield no directory: 0" while `.agents/slop/declare` -- a real output of
`checks/slop-declare.py` -- was invisible to it, because the resolver resolved module-level
constants against an empty environment. **AN INSTRUMENT THAT CANNOT SEE PRINTS THE COUNT OF
WHAT IT CAN SEE, AND `0` IS THE SIGNATURE.** A census whose only evidence that it is complete
is its own silence is not a census.

So the completeness claim is moved OFF the census and ONTO THIS FILE, where a planted site can
fail. Every case below is a spelling, an expected answer, and the reason the answer is what it
is. **THE HARNESS COMES FIRST OR IT IS NOT A HARNESS** -- it was written second here, after the
defect it catches, and that is recorded rather than hidden.

VERDICTS. `PASS 0` every planted site resolved as declared. `FAIL 1` a site resolved as
`MISS` (expected a directory, got none) or `EXTRA` (named a directory it should not).
`REFUSED 3` the synthetic tree could not be built. `DEAD 5` the census returned nothing at all,
which is a different failure from returning the wrong thing and must not be reported as `0`.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import writecensus as wc  # noqa: E402

# (label, source, expected directory NAME under .agents/slop, or None to plant a site that must
#  name NO directory -- in which case `must_not_see` names the directory it must stay away from)
CASES: list[tuple[str, str, str | None, str | None, str]] = [
    ("literal-makedirs", 'import os\nos.makedirs(".agents/slop/a05")\n', "a05", None,
     "the base case: a literal, a module function, arg 0"),
    ("literal-open-w", 'open(".agents/slop/a06/x.rows", "w").close()\n', "a06", None,
     "`open` with a WRITE mode is a write"),
    ("literal-open-read", 'open(".agents/slop/a07/x.rows").close()\n', None, "a07",
     "`open` with no mode is a READ, and a read is not a write target"),
    ("open-mode-keyword", 'open(".agents/slop/a08/x.rows", mode="w").close()\n', "a08", None,
     "`open(p, mode=\"w\")` is a hole in `sweep.py:218`, which reads `args[1]` only"),
    ("open-mode-plus", 'open(".agents/slop/a19/x.rows", "r+").close()\n', "a19", None,
     "`r+` opens for writing as well as reading"),
    ("receiver-write-text",
     'from pathlib import Path\nPath(".agents/slop/a09").mkdir()\n', "a09", None,
     "the path is the RECEIVER of a Path method; `sweep.py` reads `node.args` and misses it"),
    ("div-chain", 'from pathlib import Path\nROOT = Path(__file__).resolve().parent\n'
     '(ROOT / ".agents/slop/a02").mkdir()\n', "a02", None,
     "`Path.__truediv__` -- 612 of the tree's 854 Div sites in checks/+gates/ are path-shaped"),
    ("binop-add", 'SLOP = ".agents/slop"\nD = SLOP + "/a12"\nimport os\nos.makedirs(D)\n', "a12", None,
     "`+` is the other path spelling; the report named only `/`"),
    ("const-from-const", 'from pathlib import Path\nROOT = Path(__file__).resolve().parent\n'
     'SLOP = ".agents/slop"\nHERE = ROOT / SLOP / "a03"\nHERE.mkdir()\n', "a03", None,
     "a constant built from TWO constants above it -- the case an empty environment lost"),
    ("join-literal-tail", 'import os\nROOT = "/x"\nos.makedirs(os.path.join(ROOT, ".agents/slop/a04"))\n',
     "a04", None, "an OPAQUE PREFIX is harmless: the tail is a literal"),
    ("join-opaque-tail", 'import os\nROOT = "/x"\nSLOP = ".agents/slop"\n'
     'for name in ("a11",):\n    os.makedirs(os.path.join(ROOT, SLOP, name))\n', None, "a11",
     "the PREFIX is real and the first component is a LOOP VARIABLE: refused, never invented"),
    ("str-join", 'SLOP = ".agents/slop"\nimport os\nos.makedirs("".join([SLOP, "a20"]))\n', "a20", None,
     "`str.join` passes ONE list argument, not N; the spelling `sweep.py` claims to support"),
    ("function-default",
     'from pathlib import Path\nHERE = Path(__file__).resolve().parent / ".agents/slop/a13"\n'
     'def w(out: Path = HERE):\n    out.mkdir(parents=True, exist_ok=True)\nw()\n', "a13", None,
     "a PARAMETER DEFAULT is a binding; a local re-assignment is too"),
    ("local-reassign",
     'from pathlib import Path\ndef w():\n    d = Path(__file__).resolve().parent / ".agents/slop/a14"\n'
     '    d.write_text("")\nw()\n', "a14", None, "a local binding, which 120 of 209 instruments use"),
    ("parents-subscript", 'from pathlib import Path\n'
     '(Path(__file__).resolve().parents[1] / ".agents/slop/a10").mkdir()\n', "a10", None,
     "`parents` is a PROPERTY: a `Subscript` whose `.value` is a bare `ast.Attribute`, so the "
     "branch that required a `Call` could never see it. The PREFIX is a separate literal in "
     "the right operand, so the tail IS nameable and the honest answer is the directory"),
    ("parents-subscript-alone", 'from pathlib import Path\n'
     '_ = Path(__file__).resolve().parents[1]\n', None, "a15",
     "`parents[1]` ALONE names a directory, and which one this resolver cannot say -- so it "
     "must not invent one. Planted under a name no case may claim"),
    ("file-shaped-write", 'from pathlib import Path\n'
     '(Path(__file__).resolve().parent / ".agents/slop/a16.md").write_text("")\n', None, "a16.md",
     "a FILE an instrument writes is not an output DIRECTORY"),
    ("trailing-slash", 'import os\nos.makedirs(".agents/slop/a17/")\n', "a17", None,
     "a trailing slash is not a suffix; the tail is stripped and one component is taken"),
    ("str-replace-is-not-a-write",
     'LIVE = \'import "../../../.agents/slop/clangshim/libclang-ffi.c"\'\n'
     'text = "import \\"./libclang-ffi.c\\""\n_ = text.replace(LIVE, text)\n', None, "clangshim",
     "THE DEFECT THIS HARNESS WAS WRITTEN FOR: 62 of 62 `replace` sites on this tree are "
     "`str.replace`, and one of them names `clangshim`, a live gate's REQUIRED INPUT"),
    ("rmtree-is-not-a-write", 'import shutil\nshutil.rmtree(".agents/slop/a18")\n', None, "a18",
     "wanting a path GONE is not owning it; excluding it would protect a doomed directory"),
    ("write-text-content-is-not-a-path",
     'from pathlib import Path\nout = Path("/tmp/x")\n'
     'out.write_text("see .agents/slop/notes/a21.md for the derivation")\n', None, "notes",
     "a mention inside CONTENT is a mention; `sweep.py` reads `node.args` and reads content"),
]


def build(tmp: str) -> None:
    for sub in ("checks", "gates"):
        os.makedirs(os.path.join(tmp, sub), exist_ok=True)
    for i, case in enumerate(CASES):
        with open(os.path.join(tmp, "checks", f"case{i:02d}.py"), "w") as fh:
            fh.write(case[1])
    # A control that is NOT a write at all, so an empty answer is distinguishable from no input.
    with open(os.path.join(tmp, "gates", "nothing.py"), "w") as fh:
        fh.write("X = '.agents/slop/a99-not-written'\n")


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="constfix-selftest-")
    try:
        build(tmp)
        rows = wc.census(tmp)
        got = {r["dir"] for r in rows if r["dir"]}
        walked = wc.instruments(tmp)
        if not walked:
            print("DEAD 5: the census returned nothing at all on a tree it was handed")
            return 5
        fails = 0
        print(f"# synthetic tree: {len(walked)} instruments, {len(CASES)} planted sites")
        print(f"# census named {len(got)} directories: {sorted(got)}\n")
        for label, _src, want, must_not, why in CASES:
            if want is not None:
                target = f"{wc.SLOP_PREFIX}/{want}"
                seen = [g for g in sorted(got) if g == target]
                verdict = "PASS 0" if seen else "FAIL 1"
                detail = f"want={target}"
            else:
                target = f"{wc.SLOP_PREFIX}/{must_not}"
                seen = [g for g in sorted(got) if g == target or g.startswith(target + "/")]
                verdict = "FAIL 1" if seen else "PASS 0"
                detail = f"want=(none), must not see {target}"
            if verdict != "PASS 0":
                fails += 1
            print(f" {verdict}  {label:34s} {detail:48s} got={seen or '[]'}")
            print(f"          {why}")
        print(f"\n# {len(CASES) - fails} of {len(CASES)} PASS")
        return 1 if fails else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
