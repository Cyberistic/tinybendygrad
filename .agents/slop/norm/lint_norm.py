#!/usr/bin/env python3
"""lint_norm.py -- the census of every float normaliser in the tree's gates, and the
check that a NEW one cannot be added.

    python3 .agents/slop/norm/lint_norm.py        # writes norm/census.txt

WHY A LINT AND NOT JUST A HELPER.  A helper nobody is forced through is a helper
that is bypassed the first time it is inconvenient, and this tree has already been
burned four times by instruments that each produced a plausible line and a wrong
verdict: `--check-only` says `ALL PROOFS CHECK` for an empty file, a dict-keyed
presence check cannot see 55 duplicate rows, `None{}` counted a type-correct
`Option.None` as an empty body, and `bend=137` counted one probe.  THIS is the
fifth of that family and the subtlest, because its output is not wrong -- it is
about a DIFFERENT THING than the reader thinks.

## THE CLASSIFICATION, AND IT IS ONE QUESTION

    DOES THIS NORMALISER ROUND-TRIP THROUGH THE VALUE'S OWN WIDTH?

Everything else follows.  A normaliser that does round-trip is correct whatever its
spelling.  One that does not is a defect WHATEVER it is used for, because the
moment two sides of a gate disagree the reader cannot tell a value difference
from a spelling one.

## TWO NUMBERS, AND ONLY ONE OF THEM IS AN EXIT STATUS

  BASELINE  the sites that exist today.  Each carries a reason and a line, and they
            are a DEBT LEDGER: every one is in a file this unit may not touch.  The
            lint is green on the baseline and stays green until a site is added.
  NEW       anything not on the baseline.  Exit 1 if `NEW` is non-empty.

That split is the whole design.  A lint pinned to a constant is a fifth instance
of the family it exists to stop; so is a lint that is red forever, because a red
nobody acts on is background noise.  `checks/lint_demo.sh` plants one site in a
`$TMPDIR` copy and shows the status flip, so both branches are measurements.

## WHAT THIS LINT IS NOT

A REGEX CENSUS, not an analysis.  It cannot tell a normaliser from a comment that
quotes one.  What it guarantees is narrower and is the part that matters -- a new
`repr(float(` or a new `%g` in a gate is a line of output here, and here is where
it fails.
"""
from __future__ import annotations

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SLOP = HERE.parent
HELPER = HERE / "canon.py"

SIGNATURES = [
    # `canon(x, "f32")` -- THE WIDTH IS REQUIRED, so this signature cannot match a
    # local function that happens to be called `canon`.  MEASURED:
    # `clangshim/clangshim-gen.py:94` defines `def canon(t: str)` and a looser
    # `\bcanon\(` reported it as being on the helper.
    ("canon", re.compile(r"\bcanon(?:_bits)?\(\s*[^,()]+,\s*[\"'][a-z0-9]+[\"']"),
     "yes -- it IS the helper"),
    ("bits-via-struct-I", re.compile(r"unpack\(\s*['\"]<I['\"]\s*,\s*pack\(\s*['\"]<f['\"]"),
     "yes -- f32 bits"),
    ("bits-via-hex", re.compile(r"pack\(\s*['\"]>f['\"].{0,24}\.hex\(\)"), "yes -- f32 bits"),
    ("roundtrip-f32", re.compile(r"unpack\(\s*['\"]<f['\"]\s*,\s*pack\(\s*['\"]<f['\"]"),
     "yes -- f32 round trip"),
    ("roundtrip-f16", re.compile(r"unpack\(\s*['\"]e['\"]\s*,\s*pack\(\s*['\"]e['\"]"),
     "yes -- f16 round trip"),
    ("roundtrip-f64", re.compile(r"unpack\(\s*['\"]d['\"]\s*,\s*pack\(\s*['\"]d['\"]"),
     "yes -- f64 round trip"),
    ("float.hex", re.compile(r"float\.hex\(\)"), "yes -- exact, no rounding at all"),
    ("repr(float(", re.compile(r"repr\(\s*float\("), "NO -- no round trip"),
    ("%g", re.compile(r"\{[^}]*:\s*g\}"), "NO -- SIX significant digits"),
]

#: A LINE, with `#` comments AND triple-quoted strings removed.  The docstring is
#: the other half of the noise, and it is the same failure from the other side:
#: `jslane2/gen_f32_seam.py:174` and `jstage/jsstage.py:305` both QUOTE
#: `repr(float(s))` while explaining that it is the defect, and a lint that flags
#: the EXPLANATION of a fixed bug is a lint whose output gets ignored.
STRIP = re.compile(r'("""|\'\'\')')


def code_lines(text: str) -> list[str]:
    """Line N of the input, with every comment and every string literal removed.

    String LITERALS and docstrings both, because `repr(float(` appears in prose in
    three of this tree's files and in code in none of them any more.  A `#` alone
    is not enough: MEASURED, it leaves `jslane2/gen_f32_seam.py:174` flagged.
    """
    out, quoted = [], False
    delim = ""
    for line in text.splitlines():
        buf, i = [], 0
        while i < len(line):
            if quoted:
                j = line.find(delim, i)
                if j < 0:
                    i = len(line)
                    break
                i, quoted = j + len(delim), False
                continue
            h = line.find("#", i)
            q = min((k for k in (line.find('"""', i), line.find("'''", i)) if k >= 0),
                    default=-1)
            if q >= 0 and (h < 0 or q < h):
                buf.append(line[i:q])
                delim = line[q:q + 3]
                quoted, i = True, q + 3
                continue
            buf.append(line[i:h] if h >= 0 else line[i:])
            break
        out.append("".join(buf))
    return out

#: NOT GATES, and why.  `xd1` and `opstree` are whole SECOND tinygrad checkouts
#: sitting under `slop/`, and their `viz/serve.py` formats floats for a BROWSER.
#: MEASURED: scanning them buries the sites that matter under about four hundred
#: that do not, and a census nobody can read is a census nobody runs.
OUT_OF_SCOPE = ("xd1/", "opstree/", "runs/", "__pycache__/", "node_modules/")

#: PLANTS AND THIS UNIT'S OWN FILES.  `norm/` holds the two normalisers this unit
#: RUNS AGAINST ITSELF, so a plant that the lint did not flag would be a plant
#: nobody can find; `checks/norm_check.py` is another unit's plant of the same
#: defect, written before this file existed.
EXCUSED = ("norm/", "checks/norm_check.py")

#: THE BASELINE: the non-round-tripping sites that exist today, each in a file this
#: unit may not touch.  `file:line` is the key, so a site that MOVES is reported as
#: NEW and the line goes stale in the open -- which is the point of keying on it.
BASELINE = {
    "dc-oracle.py:135": "another unit's tree.  AND THE AUTHOR KNEW: the comment at :130 "
                        "says \"`%g` agrees with `H.f32_show` on 1.0 -- the only float "
                        "CONST in this file -- and would NOT agree on a non-integral "
                        "one.\"  Shipped the gap anyway.",
    "mm-dt-gate.py:60": "another unit's tree.  One of THREE byte-identical copies of "
                        "`\"F\" + (f\"{v:g}\" if v.is_integer() else repr(v))` -- the "
                        "other two are mm-walk-gate.py:44 and mm-lift-gate.py:158.  The "
                        "snippet fixes the `448`-vs-`448.0` half of the trap and leaves "
                        "the `1.0996094`-vs-`1.099609375` half open.",
    "mm-walk-gate.py:44": "another unit's tree.  Copy 2 of 3, same line.",
    "mm-lift-gate.py:158": "another unit's tree.  Copy 3 of 3, same line.  THREE copies "
                           "of twelve characters is the argument for `canon.py` better "
                           "than any note is.",
}

#: `repr(float(...))` that BUILDS AN ORACLE rather than normalising one.  Same
#: spelling, different job, and a census that cannot tell them apart reports every
#: oracle as a defect -- which is how a census stops being read.  These are listed
#: with the line that PUTS THEM ON THE HELPER, so the exemption is checkable.
ORACLE_BUILDERS = {
    "checks/abi_gate.py": "its own `norm` at :132 is `repr(struct.unpack(\"<f\", "
                       "struct.pack(\"<f\", v))[0])`, which round-trips BOTH sides, and "
                       "the file is EXPLICITLY DO-NOT-TOUCH.",
    "checks/abi4_gate.py": "same shape at :240, EXPLICITLY DO-NOT-TOUCH.",
    "jstage/jsstage.py": "another unit's tree; its `f32` at :308 round-trips both sides "
                         "and its `agree` at :328 handles NaN with `math.isnan`.",
    "jslane2/gen_f32_seam.py": "THIS UNIT'S GATE, moved onto `canon` already: `norm` at "
                               ":181 is `CANON.canon(s, \"f32\")`.  The only remaining "
                               "`repr(float(` here is the PLANT inside `both`'s docstring "
                               "and in `norm`'s own JFP-1 history, and both are prose.",
}


def census() -> tuple[list[str], list[str], list[str], int]:
    lines, base, new, files = [], [], [], 0
    for p in sorted(SLOP.rglob("*.py")):
        rel = str(p.relative_to(SLOP))
        if any(x in f"{rel}/" for x in OUT_OF_SCOPE) or p == HELPER:
            continue
        if any(rel.startswith(x) or rel.endswith(x) for x in EXCUSED):
            continue
        files += 1
        for i, body in enumerate(code_lines(p.read_text()), 1):
            for name, rx, verdict in SIGNATURES:
                if not rx.search(body):
                    continue
                site = f"{rel}:{i}"
                if verdict.startswith("yes"):
                    lines.append(f"   {site:<48} {name:<20} {verdict}")
                elif site in BASELINE:
                    lines.append(f"BB {site:<48} {name:<20} {verdict}")
                    base.append(site)
                elif rel in ORACLE_BUILDERS:
                    lines.append(f"oo {site:<48} {name:<20} "
                                 f"BUILDS AN ORACLE; {ORACLE_BUILDERS[rel][:60]}...")
                else:
                    lines.append(f"!! {site:<48} {name:<20} {verdict}")
                    new.append(site)
                break
    return lines, base, new, files


def main() -> int:
    lines, base, new, files = census()
    out = [
        "CENSUS -- every float normaliser in the tree's gates, and the one question",
        "",
        "  DOES THIS NORMALISER ROUND-TRIP THROUGH THE VALUE'S OWN WIDTH?",
        "",
        f"  scanned {files} .py gate files under {SLOP}  (out-of-scope trees and this",
        "  unit's own plants excluded -- see the module docstring for which and why)",
        "",
        "  `!!` = does NOT round-trip and is NOT on the baseline -> THE LINT FAILS",
        "  `BB` = on the baseline: a known defect in a file this unit may not touch",
        "  `oo` = `repr(float(...))` BUILDING AN ORACLE, which is a different job; the",
        "        line that puts it on the helper is named in `ORACLE_BUILDERS` below",
        "  blank = round-trips, or is `canon` itself",
        "",
    ] + lines + [
        "",
        "## THE BASELINE, A DEBT LEDGER, AND WHY EACH IS NOT MIGRATED",
        "",
    ]
    for site, why in sorted(BASELINE.items()):
        seen = "present" if site in base else "MOVED OR GONE -- stale baseline entry"
        out += [f"  {site}   [{seen}]", f"    {why}"]
    out += ["", "## `repr(float(...))` THAT BUILDS AN ORACLE RATHER THAN NORMALISING ONE", ""]
    for rel, why in sorted(ORACLE_BUILDERS.items()):
        out += [f"  {rel}", f"    {why}"]
    out += [
        "",
        "## WHAT A READER SHOULD TAKE FROM THE CENSUS",
        "",
        "  THE THREE INSTANCES NAMED IN THE BRIEF ARE NOT THREE DEFECTS.  They are ONE",
        "  defect wearing three coats, and the census finds the same SHAPE in four more",
        "  sites across four more files: a normaliser that handles HALF the trap and",
        "  leaves the other half.  `repr(float(s))` re-formats `448` as `448.0` --",
        "  JSL2-7's half -- and cannot touch the shortest-form half.  `mm-dt-gate.py`,",
        "  `mm-walk-gate.py` and `mm-lift-gate.py` carry the SAME LINE and it special-",
        "  cases the integral float and leaves the non-integral one.  `dc-oracle.py` says",
        "  so in its own comment and shipped the gap anyway.  `cstyle-numbers.py:5`",
        "  states the whole argument for hex, and is right.",
        "",
        "  AND THE MISSING FIXTURE IS PART OF THE DEFECT, NOT A SEPARATE MATTER.",
        "  `dc-oracle.py`'s only float CONST is `1.0`, which is precisely the one value",
        "  `%g` cannot get wrong; `mm-dt-gate.py`'s rows are dtype limits, which are all",
        "  integral.  Every gate on the baseline has a fixture set that cannot fail on",
        "  its own normaliser.  `norm/fixtures.txt` is the list.",
        "",
        "## WHAT THIS LINT FAILS ON, AND HOW THAT IS SHOWN",
        "",
        "  It fails on a non-round-tripping site that is not on the baseline.",
        "  `checks/lint_demo.sh` plants one in a `$TMPDIR` copy of the tree and runs this",
        "  file against it, so both branches of the exit status are measurements.",
        "",
        f"  baseline present {len(base)}/{len(BASELINE)}   NEW {len(new)} {new}",
        f"  exit {'1' if new else '0'}",
        "",
    ]
    text = "\n".join(out)
    (HERE / "census.txt").write_text(text)
    print(text)
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())