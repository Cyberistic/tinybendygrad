#!/usr/bin/env python3
"""Drive `bend --check-only` and fix the ONE error class generate.bend keeps hitting.

THE CLASS.  `String.eq`, `String.starts_with`, `String.drop`, `String.is_lt`
CONSUME their argument: they destructure it.  bend therefore tracks LINEAR use,
and a def parameter WITHOUT `+` is BORROWED -- it may be consumed once.  Every
place generate.py asks one string two questions (`enc_name in ("FLAT","VFLAT",
"VGLOBAL","VSCRATCH")`, `TY.base(a)` after `TY.name(a)`) is refused as
`observed : x (consumed more than once)`, and the fix is to mark the parameter
`+x`, which makes it owned/shared and therefore re-consumable.

This script reads that one error and adds the `+`.  It touches NOTHING else, and
it stops -- loudly -- the moment the error is not of that class, so a real type
error can never be papered over.

Run:  python3 .agents/slop/ga_plus.py <file.bend> [max_iters]
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def check(path):
    r = subprocess.run([str(ROOT / "bin/bend"), path, "--check-only"],
                       capture_output=True, text=True, cwd=ROOT)
    return r.stdout + r.stderr


def main():
    path = pathlib.Path(sys.argv[1])
    for it in range(int(sys.argv[2]) if len(sys.argv) > 2 else 60):
        out = check(path)
        if "ALL PROOFS CHECK" in out:
            print("GREEN after %d fix(es)" % it)
            return 0
        m = re.search(r"- expected : (\S+)\n- observed : \S+ \(consumed more than once\)\n"
                      r"(?:.*\n)*?Location: (\S+)", out)
        if not m:
            print("STOPPED on a non-consumption error after %d fix(es):" % it)
            print(out[:1400])
            return 1
        param, where = m.group(1), m.group(2)
        lines = path.read_text().split("\n")
        hit = 0
        # the header may span several lines, so patch from `def NAME(` to the
        # `-> ` that closes it
        start = None
        for i, ln in enumerate(lines):
            if ln.startswith("def " + where + "(") and not ln.startswith("def " + where + ".of("):
                start = i
                break
        if start is not None:
            stop = start
            while "->" not in lines[stop]:
                stop += 1
                if stop > start + 8:
                    stop = start
                    break
            for i in range(start, stop + 1):
                new = re.sub(r"(?<![+\w])" + re.escape(param) + r"(?=: )", "+" + param, lines[i])
                if new != lines[i]:
                    lines[i] = new
                    hit += 1
        for i, ln in enumerate(lines):
            if ln.lstrip().startswith("case ") and ": " in ln:
                pat, body = ln.split(": ", 1)   # `+` goes in the PATTERN only
                newpat = re.sub(r"(?<![+\w])" + re.escape(param) + r"(?![\w])", "+" + param, pat)
                if newpat != pat:
                    lines[i] = newpat + ": " + body
                    hit += 1
        if not hit:
            print("could not find %s in def %s -- STOPPING" % (param, where))
            return 1
        path.write_text("\n".join(lines))
        print("+%s in def %s" % (param, where))
    print("iteration cap reached")
    return 1


if __name__ == "__main__":
    sys.exit(main())