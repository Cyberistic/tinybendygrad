#!/usr/bin/env python3
"""Splice ga_fix.py's fixture+gate tail into tinybendygrad/renderer/amd/generate.bend.

WHY A SPLICER AND NOT A HAND EDIT.  Every `py=` literal in the gate is a row of
`.agents/slop/ga-oracle.txt`, which CALLS generate.py's own functions.  Hand
copying them is the mistake this project has paid for five times.  So the tail is
GENERATED.

THE TAIL IS EIGHT DEFS -- `g`, `gl`, `main` -- AND IT IS NOT CONTIGUOUS.  `g` and
`gl` are callees of `main`, so `ga_topo.py` hoists them to the top of the file
and leaves `main` at the bottom; cutting "from `def g` to end of file" therefore
deleted everything in between, which was 618 lines of port.  So this removes the
three defs WHEREVER they are and appends them at the end, which is also where
`main` has to be.

Every `py=` here is spliced from the oracle and the escaping is the oracle
harness's job (`bq`): the emitter rows carry a whole generated file joined with
REAL newlines, and a raw newline inside a `"..."` literal ends the literal, which
bend reports against the LAST row of the file, pointing at the wrong line.

Run:  python3 .agents/slop/ga_splice.py          # rewrite in place
      python3 .agents/slop/ga_splice.py --check  # sizes only
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
BEND = HERE.parent.parent / "tinybendygrad/renderer/amd/generate.bend"
GATE_DEFS = ("def g(nm: String", "def gl(nm: String", "def main() -> IO(Unit):",
             "def fx_encs()", "def fx_eos()", "def fx_tys()", "def fx_fbs()",
             "def fx_ots()", "def fx_ssx()", "def fx_ps()")
TOP = re.compile(r"^(type |def |import )")


def fresh():
    r = subprocess.run([sys.executable, str(HERE / "ga_fix.py")],
                       capture_output=True, text=True)
    if r.returncode != 0 or "NO ORACLE ROW" in r.stderr:
        sys.exit("ga_fix.py refused:\n" + r.stderr)
    return r.stdout.rstrip("\n").split("\n")


def strip_gate_defs(lines):
    """Every top-level block whose def header is one of GATE_DEFS, gone."""
    out, i, n, dropped = [], 0, len(lines), []
    while i < n:
        if TOP.match(lines[i]):
            j = i + 1
            while j < n and not TOP.match(lines[j]):
                j += 1
            if lines[i].startswith(GATE_DEFS):
                dropped.append(lines[i].split("(")[0])
                i = j
                continue
            out.extend(lines[i:j])
            i = j
            continue
        out.append(lines[i])
        i += 1
    return out, dropped


def main(check):
    tail = fresh()
    lines = BEND.read_text().split("\n")
    head, dropped = strip_gate_defs(lines)
    # the gate banner belongs to the tail, so drop it from the head too
    while head and head[-1].startswith("#"):
        head.pop()
    out = head + tail
    assert len(out) > 0
    if check:
        print("would drop %s and write %d lines" % (dropped, len(out)))
        return
    BEND.write_text("\n".join(out) + "\n")
    print("spliced: dropped %s, %d -> %d lines" % (dropped, len(lines), len(out) + 1))


if __name__ == "__main__":
    main("--check" in sys.argv)