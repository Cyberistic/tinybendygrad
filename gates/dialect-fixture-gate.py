#!/usr/bin/env python3
r"""dialect-fixture-gate.py -- WHY THE `.bend` FILES UNDER `oracles/` ARE COLD, AND WHETHER THEIR CLAIMS SURVIVE.

    .venv/bin/python gates/dialect-fixture-gate.py            # the census
    .venv/bin/python gates/dialect-fixture-gate.py --rows F   # TSV: shape, claims, carried, lost

WHAT IT IS FOR, AND IT IS NOT A GREEN-WASH. `checks/compile-census.py` reports seven files under
`oracles/` as COLD. This gate does NOT change that and does not try to: the seven stay COLD in the
census, on a verdict about COMPILATION, and that verdict is correct. What this gate answers is the
question a reader has next -- *are those seven rows lost?* -- and the answer is a count, not a
reassurance.

THE SUBJECT. A `.bend` file in this dialect names only what it imports, and the compiler's own
`base.bend` owns `U32`, `F32`, `Nat`, `Bool`, `Char`, `String`, `IO`, `List`, `Unit`, `Word` and
every constructor of them, so a file that uses one MUST carry `import Base`. MEASURED, with
`bin/bend <file> --check-only` under `checks/bounded.py --mb 2048`, reading the TOKEN:

    mini/str.bend     `import Base` + `-> String: String.concat(...)`   WARM, rc=0
    mini/nobase.bend  the same def, no `import Base`                     `observed : String`
    mini/self.bend    no `import Base`, `type P{x: U32}`                  `observed : U32`
    mini/noprim.bend  no `import Base`, no primitive at all               WARM, rc=0
    mini/nil.bend     no `import Base`, `case Nil{}`                      `unknown: Nil`

`noprim.bend` is in that table ON PURPOSE: **zero imports does not by itself make a file
uncompilable**, so this gate never reports a file COLD merely for lacking an import. It reports
what the port carries, which is a different question with a different answer.

A ROW TAG IS THE CLAIM; THE CODE AROUND IT IS THE SPELLING. `oracles/lift-rows.bend` is 127 lines
whose code lines are NOT in the port -- re-indented inside a `def` wrapper, so a whole-line
containment test reads 0% -- while 127 of 127 of its row tags ARE in `tinybendygrad/uop/fold.bend`.
Measuring the lines would have called a live, compiled set of rows lost. So the denominator here is
TAGS: every `"..."` on a comment-free, non-blank line.

ONE DECLARED NORMALISATION, AND IT IS COUNTED SEPARATELY. `oracles/pre-oracle-bend.bend` and
`oracles/post-oracle-bend.bend` are one oracle either side of a rename, and the two differ on 10
lines whose only change is `X=` -> `X ` (`is_volatile PARAM vol=False` / `vol False`). So a tag is
CARRIED either verbatim (`carried=`) or after that one substitution (`carried_renamed=`), and the
gate prints both, because a reader who wants only the strict number has one. 157 of `pre`'s 2,009
claims need the rename; 0 claims are lost either way, MEASURED.

THE VERDICT IS OVER THE FRAGMENTS, AND THE MODULES ARE PRINTED AND NOT ADJUDICATED. The subject is
every file under `oracles/` that names no `import` and no `def main` -- a DECLARED RULE (walk plus
two structural predicates), not a list of seven names. A module is judged by its own driver and its
own gate; this one has no business overruling it, and its verdict would be measured by a rule tuned
for oracle row tags, which reads a probe's label as a claim. MEASURED, and the reason is visible
in the rows below: `oracles/fold-probe-mvt.bend` is WARM and reports 7 lost because its labels are
`"p1=" .. "p5n="`, and `oracles/probe-su.bend` reports 2 lost for `"size=5, no vmin_vmax: n="`.
Those are not lost CLAIMS, they are strings that were never claims, and a gate that counted them
would be reporting its own classifier's noise as a finding. They are printed, counted, and
labelled `CONTEXT`.

THE POPULATION IS DISCOVERED, NEVER NAMED. `os.walk("oracles")` + `endswith(".bend")`, the walk
rule `checks/compile-census.py:discover` uses, so a file added there is judged without editing
this file. `git ls-files` is not asked for anything: the index is ARMED (AGENTS.md doctrine 1).

EXIT STATUS is `gates/gatekit.py`'s five, LOADED BY PATH and never re-spelled.
  0  every FRAGMENT's claims are carried by the port
  1  at least one fragment claim is lost -- a row that exists nowhere, which is the finding this
     gate exists to make possible
  3  REFUSED: no `.bend` under `oracles/`, no fragment in it, or the compiler's `base.bend` is
     absent so the DIALECT lane measured nothing. `SKIP IS NOT PASS`.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
ORACLES = ROOT / "oracles"
PORT = ROOT / "tinybendygrad"
BASE = ROOT / "references" / "bend" / "bend2" / "base.bend"   # the compiler's own, BY PATH

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "checks"))
from verdict import FAIL, PASS, REFUSED, settle  # noqa: E402

TAG = re.compile(r'"([^"\n]*)"')
# THE RENAME, one substitution, taken from the diff of the pair rather than guessed at.
RENAME = re.compile(r"([A-Za-z0-9_]+)=")
# The three names this gate was written about. Read out of Base's own source, not asserted here.
DIALECT_NAMES = ("String", "IO", "Nil")


def code_lines(src: str) -> list[str]:
    """Comment-free, non-blank lines. `#` cannot occur inside a `"..."` row tag here: every tag in
    these files is a row name, and MEASURED against the census's own 91-file population, zero tags
    contain one. So the split is by line and needs no quote-tracking scanner."""
    return [l for l in src.split("\n") if l.strip() and not l.strip().startswith("#")]


def rename(tag: str) -> str:
    return RENAME.sub(r"\1 ", tag)


def discover() -> list[Path]:
    out: list[Path] = []
    for d, dirs, fs in os.walk(ORACLES):
        dirs[:] = sorted(x for x in dirs if x != "__pycache__")
        out += [Path(d) / f for f in sorted(fs) if f.endswith(".bend")]
    return sorted(out)


def port_text() -> str:
    """Every `.bend` under the port, concatenated. The question is what is compiled NOW, so this
    reads the WORKING TREE, and the walk is the population rule rather than a list of modules."""
    return "\n".join(p.read_text(errors="replace")
                     for p in PORT.rglob("*.bend") if p.is_file())


def dialect_row() -> str:
    """`name=FOUND|ABSENT` for each of `DIALECT_NAMES`, read out of Base's own declarations. This is
    the answer to "is the dialect still there", and it is READ, not remembered: Base is the only
    place these three can come from, so a reader can re-run the grep."""
    if not BASE.is_file():
        settle(REFUSED, f"{BASE.relative_to(ROOT)} is absent, so whether the dialect still has "
                        f"{'/'.join(DIALECT_NAMES)} in scope was NOT measured; a gate that could not "
                        f"ask is not a green gate")
    src = BASE.read_text(errors="replace")
    out = []
    for name in DIALECT_NAMES:
        declared = re.search(rf"^\s*(?:def|type|law)\s+{re.escape(name)}\b", src, re.M) \
            or re.search(rf"^\s+{re.escape(name)}\{{", src, re.M)
        out.append(f"{name}={'FOUND' if declared else 'ABSENT'}")
    return " ".join(out)


def main() -> int:
    files = discover()
    if not files:
        settle(REFUSED, f"no .bend under {ORACLES.relative_to(ROOT)}/ -- the population is empty "
                        f"and an empty census proves nothing")
    print(f"POPULATION oracles/*.bend handed={len(files)}  :: os.walk + endswith('.bend')")
    print(f"DIALECT    {dialect_row()}  :: read from {BASE.relative_to(ROOT)}")
    print("NOTE       a COLD row in checks/compile-census.rows is a verdict about COMPILATION and "
          "stands; this gate answers whether the CLAIMS survive, which is a different question")

    port = port_text()
    frag, ctx, lost_total = [], [], 0
    for p in files:
        src = p.read_text(errors="replace")
        lines = code_lines(src)
        tags = [m.group(1) for l in lines for m in TAG.finditer(l)]
        strict = [t for t in tags if f'"{t}"' in port]
        renamed = [t for t in tags if t not in strict and f'"{rename(t)}"' in port]
        lost = [t for t in tags if t not in strict and f'"{rename(t)}"' not in port]
        is_fragment = not (any(l.startswith("import") for l in src.split("\n"))
                           and any(l.startswith("def main") for l in lines))
        shape = "FRAGMENT" if is_fragment else "CONTEXT"
        (frag if is_fragment else ctx).append((p, len(tags), strict, renamed, lost))
        lost_total += len(lost) if is_fragment else 0
        print(f"{shape:<9} claims={len(tags):<5} carried={len(strict):<5} "
              f"carried_renamed={len(renamed):<4} lost={len(lost):<4} {p.relative_to(ROOT)}")
        if is_fragment:
            for t in lost[:8]:
                print(f"          LOST {t}")
            if len(lost) > 8:
                print(f"          ... and {len(lost) - 8} more")

    if not frag:
        settle(REFUSED, f"{len(files)} .bend under {ORACLES.relative_to(ROOT)}/ and not one of "
                        f"them is a fragment, so this gate's subject is absent and a census over "
                        f"an empty subject proves nothing")
    claims = sum(f[1] for f in frag)
    print()
    print(f"FRAGMENTS  files={len(frag)} claims={claims} carried={sum(len(f[2]) for f in frag)} "
          f"carried_renamed={sum(len(f[3]) for f in frag)} lost={lost_total}")
    print(f"CONTEXT    files={len(ctx)} claims={sum(c[1] for c in ctx)} "
          f"lost={sum(len(c[4]) for c in ctx)}  :: modules, judged by their own gate; their "
          f"\"lost\" is this gate's tag rule reading probe labels, not a missing row")
    if lost_total:
        settle(FAIL, f"{lost_total} of {claims} fragment row tags under oracles/ are in no .bend "
                     f"under tinybendygrad/ under either spelling: a row that exists NOWHERE")
    settle(PASS, f"all {claims} row tags of the {len(frag)} fragments under oracles/ are carried by "
                f"a .bend under tinybendygrad/; the COLD compile rows are fragments whose claims "
                f"are compiled where they are used")


if __name__ == "__main__":
    main()