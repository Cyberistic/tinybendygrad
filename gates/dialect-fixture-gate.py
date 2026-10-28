#!/usr/bin/env python3
r"""dialect-fixture-gate.py -- WHY THE `.bend` FILES UNDER `oracles/` ARE COLD, AND WHETHER THEIR CLAIMS SURVIVE.

    .venv/bin/python gates/dialect-fixture-gate.py            # the census
    .venv/bin/python gates/dialect-fixture-gate.py --plant    # the plant and its control

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

A ROW TAG IS THE CLAIM; THE CODE AROUND IT IS THE SPELLING. `oracles/lift-rows.bend` is 175 lines
whose code lines are NOT in the port -- re-indented inside a `def` wrapper, so a whole-line
containment test reads 0% -- while 126 of 126 of its row tags ARE in `tinybendygrad/uop/fold.bend`.
Measuring the lines would have called a live, compiled set of rows lost. So the denominator here is
TAGS: the row name each row-maker is handed.

WHAT A ROW TAG IS, AND IT IS NOT "EVERY QUOTED STRING". MEASURED 2026-10-29: the rule this file
used -- `re.compile(r'"([^"\n]*)"')`, EVERY quoted string -- read **472 "lost" row tags** across
the seven fragments, and **NOT ONE OF THOSE 472 WAS A ROW TAG**. `oracles/pre-oracle-bend.bend` and
`oracles/post-oracle-bend.bend` are PTX/LLVM ORACLES: they carry the oracle's ASSEMBLY alongside
their row tags, so a rule that reads every quoted string reads assembly as claims.

THE 472, PARTITIONED BY WHERE EACH STRING SITS (MEASURED, per file, and the two files agree
EXACTLY because the two differ only on the rename):
    236 old-lost strings in each of the two files, 472 in all.
    231 of each file's 236 are a LATER ARGUMENT of a row-maker call -- the VALUES:
      `r_lcs("lconst special +inf", True{}, False{}, "0x7FF0000000000000")` -- the row tag is the
      FIRST argument and the later ones are the values (a dtype name, a number, a PTX/LLVM TEXT,
      a LABEL, a REGISTER NAME).
      and 5 of each file's 236 are an argument of a call that is NOT a row-maker at all -- PTX
      DIRECTIVES (`"alwaysinline"`, `"nounwind"`, `"attributes"`), a LABEL (`"#0"`), and one DTYPE
      LIST (`"fp8e4m3,fp8e5m2,fp8e4m3fnuz,fp8e5m2fnuz"`).
THE WHOLE POPULATION OF EACH FILE, for the same measurement: 2,009 quoted strings, of which
**445 are row tags**, 1,529 are later arguments of a row-maker call, 35 are arguments of a call
that is not a row-maker, and 0 are outside every call.

SO THE RULE IS STRUCTURAL, AND THE ROW-MAKER SET IS DISCOVERED FROM THE PORT, NEVER TYPED. A row
tag is a quoted string **iff it lies inside the FIRST ARGUMENT of a call to a ROW-MAKER**, and a
row-maker is a function **the port defines** whose **first parameter is the row name** (`nm`).
MEASURED, the port's own definitions: `def r_lt(+nm: String, +d: S.Dt) -> String:` at
`tinybendygrad/renderer/llvmir.bend:481`, `def lf_row(nm: String, b: Bnd2) -> IO(Unit):` at
`tinybendygrad/uop/fold.bend:4661`, `def srow(nm: String, v: String) -> IO(Unit):` and
`def urow(nm: String, v: U32) -> IO(Unit):` at `tinybendygrad/examples/train_resnet.bend:106,108`,
and `def u1(nm: String, v: U32) -> String:` at `tinybendygrad/runtime/support/usb.bend:98`. The
gate PRINTS the set it discovered and WHERE each definition is, so a reader can re-run the grep
and see that the set is not a list somebody typed. The port's def names are DOTTED
(`Enc.emit.head`, `Op.in_.go`), so a call is matched on its LAST COMPONENT too.

THE FIRST ARGUMENT MAY BE A COMPOSITION. `oracles/usb-arith-rows.bend` spells a row name as
`u1(String.concat(["usb_split_empty", "_full"]), ...)`, so the pieces of the name are the strings
inside that first argument and BOTH are checked. MEASURED, and the carried check is the same
literal containment either way, because the port spells it the same way.

ONE DECLARED NORMALISATION, AND IT IS COUNTED SEPARATELY. `oracles/pre-oracle-bend.bend` and
`oracles/post-oracle-bend.bend` are one oracle either side of a rename, and the two differ on 10
lines whose only change is `X=` -> `X ` (`is_volatile PARAM vol=False` / `vol False`). So a tag is
CARRIED either verbatim (`carried=`) or after that one substitution (`carried_renamed=`), and the
gate prints both, because a reader who wants only the strict number has one. 157 of `pre`'s 445
row tags need the rename; 0 row tags are lost either way, MEASURED.

THE VERDICT IS OVER THE ROW TAGS, AND THE OLD DENOMINATOR IS STILL PRINTED. A gate that silently
drops rows is a gate that cannot be checked, so the census prints, per fragment, EVERY quoted
string (`quoted=`), how many of them ARE row tags (`rowtags=`), and how many were NOT counted as
row tags and WHY (`not_a_rowtag=`). The old rule's own numbers are printed beside them (`old_*=`),
so the delta is on the face of the output and a reader can see the gate did not lose information
-- it stopped counting assembly.

THE POPULATION IS DISCOVERED, NEVER NAMED. `os.walk("oracles")` + `endswith(".bend")`, the walk
rule `checks/compile-census.py:discover` uses, so a file added there is judged without editing
this file. `git ls-files` is not asked for anything: the index is ARMED (AGENTS.md doctrine 1).

EXIT STATUS is `gates/gatekit.py`'s five, LOADED BY PATH and never re-spelled.
  0  every FRAGMENT's row tags are carried by the port
  1  at least one fragment row tag is lost -- a row that exists nowhere, which is the finding this
     gate exists to make possible
  3  REFUSED: no `.bend` under `oracles/`, no fragment in it, no row-maker in the port, or the
     compiler's `base.bend` is absent so the DIALECT lane measured nothing. `SKIP IS NOT PASS`.

THE PLANT, AND IT IS A TEXT EDIT ON A COPY OF THE TREE. `--plant` copies the port, the oracles and
this gate into a directory of its own and runs the census against the COPY, four times: the
unedited copy (the CONTROL, which must be GREEN), a copy whose FRAGMENT carries a row tag the
port does not carry (which must be RED and must NAME the tag), the same copy with the tag put back
(which must be GREEN again), a copy whose PORT no longer carries a row tag (which must be RED and
must NAME the row the port lost), and the same copy with the port's tag put back (GREEN again).
**THE DENOMINATOR IS PRINTED BESIDE THE PLANT**, because a green run that is green only because
the gate counts FEWER rows proves nothing: the row-tag count is UNCHANGED by the plant, and only
the CARRIED count moves.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
ORACLES = ROOT / "oracles"
PORT = ROOT / "tinybendygrad"
BASE = ROOT / "references" / "bend" / "bend2" / "base.bend"   # the compiler's own, BY PATH

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "checks"))
from verdict import FAIL, PASS, REFUSED, settle  # noqa: E402

TAG = re.compile(r'"([^"\n]*)"')
# A CALL: a name, optionally dotted, then `(`. The last component is what a maker is matched on.
CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
# A ROW-MAKER: a `def` whose FIRST parameter is the row name. The port's own convention.
MAKER = re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\+?nm\s*:\s*String\b")
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


def port_quoted(port: str) -> set[str]:
    """THE TEXT BETWEEN EVERY PAIR OF CONSECUTIVE QUOTES IN THE PORT.

    THE CARRIED CHECK IS `f'"{t}"' in port`, and that is a substring test over a 12 MB string --
    MEASURED, 3.5 ms per miss, so 7,365 of them cost 21 s and the gate was slower than the
    work it measures. **THE SET BELOW IS THE SAME ANSWER, AND IT IS EXACT FOR EVERY STRING THAT
    DOES NOT CONTAIN A QUOTE ITSELF**: if `t` holds no `"`, then `"t"` is in the port exactly when
    `t` is the text between two CONSECUTIVE quotes of the port -- there is no third quote to skip
    over, because `t` has none. MEASURED against the substring test on every string in every
    fragment: **0 disagreements**. A string that DOES contain a quote is not covered by that
    argument, so it is not covered by the set either: `carried()` falls back to the substring
    test for those, and the fallback is not a guess."""
    out, prev = set(), None
    for m in re.finditer('"', port):
        if prev is not None:
            out.add(port[prev + 1:m.start()])
        prev = m.start()
    return out


def carried(tag: str, port: str, chunks: set[str]) -> bool:
    """Is the row tag CARRIED by the port, verbatim? The declared check, unchanged."""
    if '"' in tag:
        return f'"{tag}"' in port
    return tag in chunks


def row_makers() -> dict[str, list[tuple[Path, int]]]:
    """THE ROW-MAKER SET, DISCOVERED FROM THE PORT, with where each definition is.

    A row-maker is a function the port defines whose FIRST parameter is the row name. The
    definition's file and line are kept so the gate can PRINT them, and a reader can re-run the
    grep and see the set is not a list somebody typed."""
    out: dict[str, list[tuple[Path, int]]] = {}
    for p in sorted(PORT.rglob("*.bend")):
        if not p.is_file():
            continue
        for i, line in enumerate(p.read_text(errors="replace").split("\n"), 1):
            m = MAKER.match(line)
            if m:
                out.setdefault(m.group(1), []).append((p, i))
    return out


def split_args(text: str, base: int) -> list[tuple[str, int]]:
    """Split a call's argument text at TOP-LEVEL commas, QUOTE-AWARE, and return
    `[(arg_text, absolute_start)]`.

    The quote-awareness is load-bearing and was MEASURED: `r_rs("range_str 0,1", [0, 1], "0_1")`
    carries a COMMA inside a string literal, and a splitter that does not know about quotes splits
    that one argument into two and then reads the row name as a later argument -- which is how the
    rule under test would have been measured WRONG."""
    parts, d, cur, cur_start, i = [], 0, "", base, 0
    while i < len(text):
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, len(text))
            cur += text[i:j]
            i = j
            continue
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            parts.append((cur, cur_start))
            cur, cur_start = "", base + i + 1
        else:
            cur += ch
        i += 1
    parts.append((cur, cur_start))
    return parts


def call_args(text: str, at: int) -> tuple[int, list[tuple[str, int]]]:
    """The argument list of the call whose `(` is at `at`: `(end_offset, [(arg, abs_start)])`."""
    depth, i = 1, at
    while i < len(text) and depth:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
        i += 1
    return i - 1, split_args(text[at:i - 1], at)


def maker_first_arg_spans(line: str, makers: set[str]) -> list[tuple[int, int]]:
    """The absolute spans of the FIRST argument of every row-maker call on the line.

    A string inside that first argument is a piece of a row NAME, whether it is the whole name
    (`r_lt("lt void", ...)`) or a component of a composed one
    (`u1(String.concat(["usb_split_empty", "_full"]), ...)`)."""
    out = []
    for m in CALL.finditer(line):
        if m.group(1).split(".")[-1] not in makers:
            continue
        _, args = call_args(line, m.end())
        if not args:
            continue
        part, off = args[0]
        out.append((off + (len(part) - len(part.lstrip())), off + len(part.rstrip())))
    return out


def row_tags(line: str, makers: set[str]) -> tuple[list[str], list[str]]:
    """`(row_tags, not_row_tags)` for one line, and the second is the strings this rule did NOT
    count -- so the gate can say how many it dropped and not merely drop them."""
    spans = maker_first_arg_spans(line, makers)
    tags, others = [], []
    for m in TAG.finditer(line):
        s, e = m.span()
        (tags if any(ps <= s and e <= pe for ps, pe in spans) else others).append(m.group(1))
    return tags, others


def local_makers(files: list[Path]) -> list[tuple[Path, int, str]]:
    """A row-maker SHAPE DEFINED BY A FRAGMENT, which the port does not define.

    THE RULE'S POPULATION IS THE PORT'S, and that boundary is printed rather than assumed:
    `oracles/fold-mvt-e2e.bend:94` defines `def report(nm: String, +f: O.Found) -> IO(Unit):`,
    which IS a row-maker shape, and the row tags it is handed are therefore NOT counted by this
    gate. A reader who wants to know what the rule left out reads this line."""
    out = []
    for p in files:
        for i, line in enumerate(p.read_text(errors="replace").split("\n"), 1):
            m = MAKER.match(line)
            if m:
                out.append((p, i, m.group(1)))
    return out


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


def census(tree: Path) -> tuple[int, str, str]:
    """RUN THIS GATE against a COPY of the tree and return `(rc, stdout, stderr)`.

    The copy is a PARAMETER, so the plant can measure the gate on a tree it edited without
    touching the tree it audits."""
    g = subprocess.run([sys.executable, str(tree / "gates" / "dialect-fixture-gate.py")],
                       cwd=str(tree), capture_output=True, text=True)
    return g.returncode, g.stdout, g.stderr


def rowtags_of(out: str) -> int:
    """The FRAGMENTS row-tag denominator, read back out of the census's own printed line.

    The plant needs the DENOMINATOR the gate counted, and it reads it off the gate's output
    rather than recomputing it, so the number it compares is the number the gate reported."""
    for line in out.split("\n"):
        if line.startswith("FRAGMENTS "):
            m = re.search(r"\browtags=(\d+)", line)
            if m:
                return int(m.group(1))
    return 0


def copy_tree(tree: Path) -> None:
    """A COPY of the tree's substrate, oracles and this gate, in a directory of its own.

    The port is COPIED and not symlinked because a `.bend` file imports its neighbours by a PATH
    SPELLING, and the compiler resolves that spelling against the tree it is given. The gate reads
    the port as TEXT, so a symlink would read the live tree's port -- which would make the plant
    measure the tree it was supposed to have changed."""
    for rel in ("checks/verdict.py", "gates/gatekit.py", "gates/dialect-fixture-gate.py"):
        (tree / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, tree / rel)
    shutil.copytree(ROOT / "tinybendygrad", tree / "tinybendygrad",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(ROOT / "oracles", tree / "oracles",
                    ignore=shutil.ignore_patterns("__pycache__"))
    (tree / "references" / "bend" / "bend2").mkdir(parents=True, exist_ok=True)
    shutil.copy2(BASE, tree / "references" / "bend" / "bend2" / "base.bend")


def plant() -> int:
    """THE PLANT: A ROW TAG THE PORT DOES NOT CARRY. THE CONTROL: THE SAME TREE, UNCHANGED.

        .venv/bin/python gates/dialect-fixture-gate.py --plant

    **THE PLANT IS A TEXT EDIT ON A COPY, AND THE COPY IS THE SUBJECT.** The gate must go RED on
    a fragment carrying a row tag the port does not carry, and it must stay GREEN on the
    byte-identical copy. **THE PLANT MUST NOT BE A PLANT THAT CANNOT FAIL**: the edit changes the
    ROW TAG's TEXT, so the gate has to notice a string it never saw."""
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "tree"
        copy_tree(tree)

        # THE CONTROL: the copy, unchanged. The gate must be GREEN on it.
        rc, out_control, err = census(tree)
        ok_control = rc == 0
        print(f"CONTROL     the copy, byte-identical to the live tree  rc={rc}  "
              f"::  {'GREEN' if ok_control else 'NOT GREEN'}  {err.strip()[:160]}")
        if not ok_control:
            print("  THE CONTROL IS NOT A CONTROL: an unedited copy of the tree must pass, or the "
                  "plant arm is satisfied by a gate that always fails.")
            bad += 1

        # THE PLANT: ONE ROW TAG's TEXT, changed so the port does not carry it. **A TEXT EDIT**:
        # the tag is still a row tag (still the first argument of a row-maker call), so the gate
        # must still COUNT it -- and then find that the port does not carry it. A plant that
        # changed the tag's POSITION would be measuring the other rule.
        frag = tree / "oracles" / "lift-rows.bend"
        src = frag.read_text()
        m = re.search(r'lf_row\("([^"]+)"', src)
        if m is None:
            print("PLANT       NOT APPLICABLE, AND THAT IS A MEASUREMENT: no fragment carries a "
                  "row-maker call with a literal row tag")
            bad += 1
        else:
            old, new = m.group(1), m.group(1) + "-PLANTED-NOT-IN-THE-PORT"
            frag.write_text(src.replace(f'lf_row("{old}"', f'lf_row("{new}"', 1))
            rc, out, err = census(tree)
            named = f"LOST {new}" in out
            ok_plant = rc == FAIL and named
            print(f"PLANT       one row tag's TEXT changed, in a COPY  rc={rc}  "
                  f"::  {'RED' if ok_plant else 'NOT RED'}"
                  + (f"  -- AND IT NAMED THE PLANTED TAG: {new}" if named
                     else "  -- AND IT DID NOT NAME THE PLANTED TAG")
                  + f"  {err.strip()[:200]}")
            if not ok_plant:
                print("  THE PLANT DID NOT FIRE: a row tag the port does not carry must be a FAIL, "
                      "or this gate cannot see a missing row and a green run means nothing.")
                bad += 1
            # **THE DENOMINATOR DID NOT MOVE, AND THAT IS THE POINT.** A green run that is green
            # only because the gate counts FEWER rows proves nothing, so the plant shows the two
            # readings side by side: the same number of row tags, and one of them lost.
            before = rowtags_of(out_control)
            after = rowtags_of(out)
            same = before == after and before > 0
            print(f"DENOM      the row-tag denominator, control={before} planted={after}  "
                  f"::  {'UNCHANGED' if same else 'MOVED'}"
                  + ("" if same else "  -- THE PLANT MOVED THE DENOMINATOR, so it did not prove "
                                      "that a carried row can go lost"))
            if not same:
                print("  THE DENOMINATOR MOVED: a green run that is green because it counts fewer "
                      "rows is not a green run, and this plant must not be allowed to hide that.")
                bad += 1
            # AND THE CONTROL AFTER THE PLANT: the SAME tree with the row tag put BACK must be
            # green again, so the plant measured the tag and not the copy.
            frag.write_text(src)
            rc2, _, _ = census(tree)
            ok_back = rc2 == 0
            print(f"RESTORE     the same copy, the row tag put back  rc={rc2}  "
                  f"::  {'GREEN' if ok_back else 'NOT GREEN'}")
            if not ok_back:
                print("  THE RESTORE DID NOT HOLD: the plant measured the COPY and not the row "
                      "tag, so the plant proves nothing about the gate.")
                bad += 1

        # THE OTHER ARM, AND IT IS THE ONE THAT MATTERS: **THE PORT LOSES A ROW TAG.** A gate
        # that only notices a fragment gaining a tag is measuring the wrong direction -- the
        # defect this gate exists to find is the PORT's row disappearing, with the fragment
        # unchanged. Same text edit, same shape, applied to the PORT's own call site.
        port = tree / "tinybendygrad" / "uop" / "fold.bend"
        psrc = port.read_text()
        pm = re.search(r'lf_row\("([^"]+)"', psrc)
        if pm is None:
            print("PORT-PLANT  NOT APPLICABLE, AND THAT IS A MEASUREMENT: the port carries no "
                  "row-maker call with a literal row tag")
            bad += 1
        else:
            port.write_text(psrc.replace(f'lf_row("{pm.group(1)}"',
                                         f'lf_row("{pm.group(1)}-GONE-FROM-THE-PORT"', 1))
            rc, out, err = census(tree)
            # THE GATE MUST NAME THE ROW THE PORT LOST -- the ORIGINAL tag, not the planted one.
            named = f"LOST {pm.group(1)}" in out
            ok_port = rc == FAIL and named
            print(f"PORT-PLANT  the PORT's own row tag's TEXT changed, the FRAGMENT untouched  "
                  f"rc={rc}  ::  {'RED' if ok_port else 'NOT RED'}"
                  + (f"  -- AND IT NAMED THE ROW THE PORT LOST: {pm.group(1)}" if named
                     else "  -- AND IT DID NOT NAME THE ROW THE PORT LOST")
                  + f"  {err.strip()[:200]}")
            if not ok_port:
                print("  THE PORT-PLANT DID NOT FIRE: a row the PORT no longer carries must be a "
                      "FAIL, and this is the direction the defect this gate exists to find runs "
                      "in.")
                bad += 1
            port.write_text(psrc)
            rc3, _, _ = census(tree)
            ok_back2 = rc3 == 0
            print(f"PORT-RESTORE the same copy, the port's row tag put back  rc={rc3}  "
                  f"::  {'GREEN' if ok_back2 else 'NOT GREEN'}")
            if not ok_back2:
                print("  THE PORT-RESTORE DID NOT HOLD: the plant measured the COPY and not the "
                      "port's row tag, so it proves nothing about the gate.")
                bad += 1

    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return FAIL if bad else PASS


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--plant", action="store_true", help="the plant and its control")
    a = ap.parse_args()
    if a.plant:
        return plant()

    files = discover()
    if not files:
        settle(REFUSED, f"no .bend under {ORACLES.relative_to(ROOT)}/ -- the population is empty "
                        f"and an empty census proves nothing")
    makers = row_makers()
    if not makers:
        settle(REFUSED, f"no row-maker under {PORT.relative_to(ROOT)}/ -- a row tag is the first "
                        f"argument of a row-maker call, and with no row-maker the rule measures "
                        f"nothing; SKIP IS NOT PASS")
    names = {k.split(".")[-1] for k in makers}
    print(f"POPULATION oracles/*.bend handed={len(files)}  :: os.walk + endswith('.bend')")
    print(f"DIALECT    {dialect_row()}  :: read from {BASE.relative_to(ROOT)}")
    print(f"ROW-MAKERS {len(makers)} distinct, {len(names)} last-components  :: DISCOVERED from "
          f"{PORT.relative_to(ROOT)} by `def NAME(... nm: String ...)`, not typed:")
    for k in sorted(makers):
        for p, i in makers[k]:
            print(f"           {k:<24} {p.relative_to(ROOT)}:{i}")
    locals_ = local_makers(files)
    if locals_:
        print(f"LOCAL-MAKERS {len(locals_)} row-maker SHAPE(S) DEFINED BY A FRAGMENT, which the port "
              f"does not define -- the row tags they are handed are NOT counted by this gate:")
        for p, i, k in locals_:
            print(f"           {k:<24} {p.relative_to(ROOT)}:{i}")
    print("NOTE       a COLD row in checks/compile-census.rows is a verdict about COMPILATION and "
          "stands; this gate answers whether the CLAIMS survive, which is a different question")

    port = port_text()
    chunks = port_quoted(port)
    frag, ctx = [], []
    lost_total = quoted_total = tags_total = nottag_total = 0
    for p in files:
        src = p.read_text(errors="replace")
        lines = code_lines(src)
        quoted = [m.group(1) for l in lines for m in TAG.finditer(l)]
        tags, others = [], []
        for l in lines:
            t, o = row_tags(l, names)
            tags += t
            others += o
        strict = [t for t in tags if carried(t, port, chunks)]
        renamed = [t for t in tags if t not in strict and carried(rename(t), port, chunks)]
        lost = [t for t in tags if t not in strict and not carried(rename(t), port, chunks)]
        # THE OLD RULE, kept and printed: EVERY quoted string is a "claim". Its numbers are the
        # gate's BEFORE, so the reader can see the delta and its cause.
        old_strict = [t for t in quoted if carried(t, port, chunks)]
        old_renamed = [t for t in quoted if t not in old_strict and carried(rename(t), port, chunks)]
        old_lost = [t for t in quoted if t not in old_strict and not carried(rename(t), port, chunks)]
        is_fragment = not (any(l.startswith("import") for l in src.split("\n"))
                           and any(l.startswith("def main") for l in lines))
        shape = "FRAGMENT" if is_fragment else "CONTEXT"
        row = {"file": p, "quoted": len(quoted), "rowtags": len(tags), "carried": strict,
               "renamed": renamed, "lost": lost, "others": others, "old_lost": old_lost,
               "old_carried": old_strict, "old_renamed": old_renamed}
        (frag if is_fragment else ctx).append(row)
        if is_fragment:
            quoted_total += len(quoted)
            tags_total += len(tags)
            nottag_total += len(others)
            lost_total += len(lost)
        print(f"{shape:<9} quoted={len(quoted):<5} rowtags={len(tags):<5} carried={len(strict):<5} "
              f"carried_renamed={len(renamed):<4} lost={len(lost):<4} "
              f"not_a_rowtag={len(others):<5} old_lost={len(old_lost):<4} "
              f"{p.relative_to(ROOT)}")
        if is_fragment:
            for t in lost[:8]:
                print(f"          LOST {t}")
            if len(lost) > 8:
                print(f"          ... and {len(lost) - 8} more")

    if not frag:
        settle(REFUSED, f"{len(files)} .bend under {ORACLES.relative_to(ROOT)}/ and not one of "
                        f"them is a fragment, so this gate's subject is absent and a census over "
                        f"an empty subject proves nothing")
    print()
    print(f"FRAGMENTS  files={len(frag)} quoted={quoted_total} rowtags={tags_total} "
          f"carried={sum(len(f['carried']) for f in frag)} "
          f"carried_renamed={sum(len(f['renamed']) for f in frag)} lost={lost_total} "
          f"not_a_rowtag={nottag_total}")
    print(f"CONTEXT    files={len(ctx)} quoted={sum(c['quoted'] for c in ctx)} "
          f"rowtags={sum(c['rowtags'] for c in ctx)} "
          f"lost={sum(len(c['lost']) for c in ctx)} "
          f"old_lost={sum(len(c['old_lost']) for c in ctx)}  :: modules, judged by their own gate; "
          f"they call no row-maker THE PORT DEFINES (see LOCAL-MAKERS for the one that defines "
          f"its own), so this gate's rule reads NO row tag in them and their \"lost\" is 0 by the "
          f"rule and not by the port")
    print(f"NOT-COUNTED {nottag_total} quoted strings were NOT row tags: a row tag is the first "
          f"argument of a row-maker call, and the rest are VALUES (a later argument -- an expected "
          f"value, a dtype name, a register name, a number), ASSEMBLY (PTX/LLVM text), LABELS, "
          f"PTX DIRECTIVES, and a DTYPE LIST. They are the ORACLE's payload, not its claims.")
    old_lost_total = sum(len(f["old_lost"]) for f in frag)
    old_lost_that_are_tags = sum(len([t for t in f["old_lost"] if t in f["carried"] + f["renamed"]])
                                 for f in frag)
    print(f"OLD-RULE   the rule this gate used before: every quoted string is a claim. "
          f"old_carried={sum(len(f['old_carried']) for f in frag)} "
          f"old_carried_renamed={sum(len(f['old_renamed']) for f in frag)} "
          f"old_lost={old_lost_total} over the same fragments, and "
          f"{old_lost_total - old_lost_that_are_tags} of those are strings that are NOT row tags "
          f"({old_lost_that_are_tags} are row tags) -- the OLD numbers are printed per fragment "
          f"so the delta is on the face of the output.")
    if lost_total:
        settle(FAIL, f"{lost_total} of {tags_total} fragment row tags under oracles/ are in no "
                     f".bend under tinybendygrad/ under either spelling: a row that exists NOWHERE")
    settle(PASS, f"all {tags_total} row tags of the {len(frag)} fragments under oracles/ are "
                f"carried by a .bend under tinybendygrad/; the COLD compile rows are fragments "
                f"whose claims are compiled where they are used")


if __name__ == "__main__":
    sys.exit(main())
