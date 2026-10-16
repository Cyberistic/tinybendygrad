#!/usr/bin/env python3
"""devtag-gate.py -- the four `.bend` sites that named the ABSENT `Device.tag`, MEASURED.

    .venv/bin/python gates/devtag-gate.py

ZERO bend LANES, ZERO rows of its own, TWO claims, and both are about CLAIMS rather than
values. `gates/realize_graph_census-gate.py`'s `device_vocab_holds` already measures the
CPython side on every run -- `hasattr(Device,'tag')` is False, `ParamArg.device` is a
`str`, `Device.__getitem__` is string-keyed, `ALL_DEVICES` is a `list[str]`,
`_canonicalize` is a `str -> str`, and `device.bend`'s `tag_of` has exactly three named
arms -- so this gate RE-MEASURES NONE OF THAT. Duplicating an instrument is how two
witnesses start disagreeing, and a second copy with no generator is the `checks/sweep.py`
`LIVE_UNITS` defect all over again.

IT MEASURES THE ONE THING THOSE SIX WITNESSES DO NOT COVER, and it is a finding rather
than a restatement. `nn/optim.bend`'s M3 mutation row read:

    "The fixture that closes it needs an `S.Dn` optimizer, which needs a multi-device
     param, which needs `Device.tag` to intern two names -- that is P6 runtime."

`device_vocab_holds` cannot touch that sentence: it measures that CPython has no
`str -> int` device index and that `tag_of` is a SENTINEL, and "the `String -> U32`
direction is missing" is consistent with both. What is NOT consistent with them is a
`U32 -> String` table's absence, and the port does not need one for this: `tag_of` sends
`DISK` to 6 and every other name to 0, so **TWO NAMES ALREADY GET TWO DISTINCT TAGS**
(`C1`). MEASURED, on a copy of the tree, in three steps: `g_opt()`'s `S.D1{0}` ->
`S.Dn{[6, 0]}` took `op_nop` True -> False; `nn/optim.bend`'s `op_nop` expectation
`Nzs` -> `Nzl` took it back -> True; M3's own edit then took it -> False. The `Dn` arm
is gateable in three tokens. The M3 row's blocker was a FIXTURE nobody wrote, and it
described that as a SYMBOL that does not exist.

`C2` IS A CENSUS OF PROSE, AND ITS POPULATION IS DISCOVERED. `os.walk('tinybendygrad')`
plus `endswith('.bend')`, which is the only one of the three populations `AGENTS.md` admits
-- a generator's own declaration or a DIRECTORY WALK, not a hand list of the four files. A
four-element tuple of paths would have gone stale the moment a fifth citation appeared,
which is exactly what `checks/sweep.py`'s removed `LIVE_UNITS` did.

`C2` READS THE RAW TEXT AND `C1` READS `device.bend`'s CODE, and that asymmetry is the
finding rather than an inconsistency. **MEASURED HERE: run through the comment stripper,
all four citations `C2` exists to catch VANISH** -- a citation of an upstream symbol is not
code, it is prose in a `#` line. So the census of citations must read prose, and the
measurement of `tag_of` must not, and neither half can be satisfied by the other.

**WHAT THIS CENSUS CANNOT SEE, STATED RATHER THAN LEFT IMPLIED.** It matches the SPELLING
`Device.tag`. A site that wrote the mechanism down as `Device["CPU"].tag`, as
`dev.tag`, or in any other paraphrase would walk past it, and a census of a spelling is
a census of a spelling. `C1` has no such hole -- it reads `tag_of` out of CODE -- so it
is the half of this gate that cannot be evaded by rewording, and it is why `C1` is here
rather than the census alone.

WHY `REFUSED` IS REACHABLE. This gate asserts nothing about CPython and can prove nothing
about CPython; `device_vocab_holds` is the instrument that does, every run. If that
function is renamed or deleted, this gate's reason evaporates silently, so it REFUSES
(exit 3) rather than passing a premise nothing is holding. `DEAD` is exit 5 and means
`device.bend` grew no `tag_of` to read, or the walk found no `.bend` at all -- the two
ways this gate can run and emit nothing.

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (the CPython-side
precondition `device_vocab_holds` is absent) · 5 DEAD (no `tag_of`, or no `.bend`).
"""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, verdict_of  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = ROOT / "tinybendygrad"
DEVICE = PORT / "device.bend"
# THE CPYTHON-SIDE INSTRUMENT. Named, not reimplemented: this gate measures the PORT and
# refuses when the other half is not being measured by anybody.
CPY_HOLDER = HERE / "realize_graph_census-gate.py"

# `def tag_of(` matched to ITS OWN END OF LINE rather than to `):`, for the reason
# `realize_graph_census-gate.py`'s witness 6 records -- this file spells the return type
# BEFORE the colon (`-> U32:`), so a `):` match finds no `tag_of` in a file that has one.
TAG_OF = re.compile(r"^def tag_of\([^\n]*\n((?:[ \t]+[^\n]*\n)*)", re.M)
# AN ARM IS A NAME AND THE TAG IT SENDS IT TO: `String.eq(h, "DISK"), 6`.
ARM = re.compile(r'String\.eq\(\s*\w+\s*,\s*"(\w+)"\s*\)\s*,\s*(\d+)')
# THE `else 0` TAIL. Without it this is not a sentinel but a partial function that RAISES,
# and C1's claim would be about a different function.
DEFAULT = re.compile(r",\s*(\d+)\)*\s*$")
# THE ABSENT SYMBOL, IN THE ONE SPELLING THIS CENSUS CAN SEE.
CITED = re.compile(r"Device\.tag")


def _code(text: str) -> str:
    """`text` line by line with every `#` comment cut at its `#`, HONOURING `"`.

    The census's own `_code()` is not importable from a gate without running its module
    scope, and this is the same rule for the same reason: a guard that reads a COMMENT
    cannot fail on the comment being wrong, and the comment here WAS wrong. `String.eq(h,
    "DISK")` is on the other side of that rule, so a `"` opens a span a `#` cannot cut.
    """
    cut_lines = []
    for line in text.splitlines():
        in_str, esc, cut = False, False, len(line)
        for i, ch in enumerate(line):
            if esc:
                esc = False
            elif in_str:
                in_str = ch != '"'
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = True
            elif ch == "#":
                cut = i
                break
        cut_lines.append(line[:cut])
    return "\n".join(cut_lines)


def bend_files():
    """The population, DISCOVERED. `os.walk` + `endswith('.bend')`, sorted for a stable
    order. `glob('*.bend')` returns `[]` on a tree where `.bend` is on disk and tracked,
    which is why this is a walk and not a glob."""
    found = []
    for root, _dirs, names in os.walk(PORT):
        found += [Path(root) / n for n in names if n.endswith(".bend")]
    return sorted(found)


def c1_two_names_two_tags() -> int:
    """`tag_of` sends DISK somewhere OTHER than the default, so a second name -- anything
    that is not DISK, NPY or PYTHON -- lands on a DIFFERENT tag. That is the whole claim:
    `String -> U32` interning of TWO names already works, so `nn/optim.bend`'s M3 blocker
    is a fixture and not a symbol.

    PRINTS ITS OWN WITNESSES AS `name=value` ROWS, so a run that measured nothing is a run
    with no rows rather than a green silence -- the `DEAD` state `gatekit` spells with exit
    5 and which a bare `assert` here would have worn.
    """
    m = TAG_OF.search(_code(DEVICE.read_text()))
    if m is None:
        print("devtag-gate: DEAD: `device.bend` has no `tag_of` to read, so the port's only "
              "`String -> U32` map is not measured and C1 cannot be answered", file=sys.stderr)
        return DEAD
    body = m.group(1)
    arms = ARM.findall(body)
    tail = DEFAULT.search(body)
    names = [n for n, _ in arms]
    tags = [int(t) for _, t in arms]
    default = int(tail.group(1)) if tail else None
    print(f"tag_of_named_n={len(names)}")
    print(f"tag_of_arms={','.join(names)}")
    print(f"tag_of_tags={','.join(str(t) for t in tags)}")
    print(f"tag_of_default={default}")
    ok = True
    if names != ["DISK", "NPY", "PYTHON"]:
        print(f"devtag-gate: FAIL: `tag_of`'s named arms are {names} and not "
              f"['DISK', 'NPY', 'PYTHON']; a fourth arm or a renamed one means C1's "
              f"'two names, two tags' is no longer the shape being measured", file=sys.stderr)
        ok = False
    if default is None:
        print("devtag-gate: FAIL: `tag_of` does not end in a literal, so it is not the "
              "three-valued sentinel C1 reads the second name off", file=sys.stderr)
        ok = False
    elif default == 0 and tags and default in tags:
        print(f"devtag-gate: FAIL: the default tag {default} is ALSO a named arm's tag, so a "
              f"second name does not get a distinct tag and `nn/optim.bend`'s multi-device "
              f"blocker is REAL after all", file=sys.stderr)
        ok = False
    if ok and tags:
        # THE ROW C1 EXISTS TO PRODUCE. `C` is not one of `tag_of`'s three names, so it takes
        # the default; `DISK` takes its own arm. Distinct integers are two distinct tags.
        other = next(t for t in tags if t != default) if default is not None else None
        print(f"two_names_two_tags={other is not None and other != default}")
    return PASS if ok else FAIL


def c2_no_citation() -> int:
    """ZERO `.bend` files under `tinybendygrad/` name `Device.tag`. The symbol is ABSENT
    from this tree's upstream, so every occurrence is a citation of something upstream does
    not have, and the corrected wording (`uop/spec.bend`'s `is_device` note) names the
    MECHANISM -- a `U32 -> String` table the port must mint, against a CPython with no
    `str -> int` device index -- instead of the symbol.

    The population is the walk, not a list of the four files, so a fifth citation is caught
    by this run rather than by the next reader.
    """
    files = bend_files()
    print(f"bend_files={len(files)}")
    if not files:
        print("devtag-gate: DEAD: the walk found no `.bend` file under `tinybendygrad`, so "
              "the census compared nothing", file=sys.stderr)
        return DEAD
    # THE RAW TEXT, AND NOT `_code(...)`. **MEASURED, and it is the whole reason this line
    # exists: stripped of comments, all four of the citations this census is for DISAPPEAR,
    # because a citation of an upstream symbol is not code -- it is prose in a `#` line.**
    # So the two claims read different halves of the file and neither can be satisfied by
    # the other: `C1` needs CODE so that a paragraph cannot fake a measurement, and `C2`
    # needs PROSE because that is where the defect is written. Reading `C2` through
    # `_code()` was measured here as a PASS over four live citations.
    hits = [(f, i + 1, l.strip()) for f in files
            for i, l in enumerate(f.read_text().splitlines()) if CITED.search(l)]
    print(f"device_tag_citations={len(hits)}")
    for f, n, l in hits:
        print(f"devtag-gate: FAIL: `{f.relative_to(ROOT)}:{n}` cites `Device.tag`, which this "
              f"tree's upstream does not have -- {l}", file=sys.stderr)
    return PASS if not hits else FAIL


def worst(codes):
    """THE WORST OF THE CLAIMS' EXITS, AND THE PRECEDENCE IS WRITTEN DOWN RATHER THAN
    ASSUMED. `gatekit` gives `DEAD` its own exit precisely so "it ran and emitted nothing"
    is distinguishable from "it ran and got the wrong answer", and MY OWN SUMMARY SPONGE
    ADE THAT FIRST TIME OUT. MEASURED HERE, on mutation C below: `tag_of` deleted, `C1`
    printed its `DEAD` sentence and the gate exited **0**, because the summary was
    `FAIL if FAIL in codes else PASS` and `DEAD` is neither. A `DEAD` lane inside a
    two-claim gate was being reported as a PASS -- `gatekit`'s `_checks_answer` docstring
    names this shape as "an instrument that reports a result for something it never ran",
    and this file had it in its last three lines.

    THE ORDER IS A CLAIM ABOUT WHICH VERDICT A CALLER SHOULD HEAR, so it is argued here.
    `DEAD` FIRST: a claim that measured nothing cannot be outranked by one that measured
    something, because its answer is unknown rather than good. `REFUSED` SECOND: a
    precondition was absent, so the instrument did not get to try. `SKIP` third, same
    shape. `FAIL` LAST: it is the only one of the four that means an answer was produced.
    """
    for code in (DEAD, REFUSED, SKIP, FAIL):
        if code in codes:
            return code
    return PASS


def main() -> int:
    # THE ROOT IS ASSERTED BEFORE IT IS USED, because `ROOT` IS `Path(__file__).parents[1]`
    # AND A GATE THAT READS FOUR FILES OUT OF A WRONG ROOT ANSWERS DEAD RATHER THAN SAYING SO.
    # `gates/gates-pop.py`'s clause II counts a gate that names a root and REFUSES on a wrong
    # one separately from one that merely resolves on-repo, and MEASURED HERE this file
    # scored `asserts=NO` without this: a copy of it run from anywhere else would have
    # reported DEAD on a `tag_of` that was never looked for.
    if not (ROOT / "pyproject.toml").is_file():
        print(f"devtag-gate: REFUSED, NOT A VERDICT: `{ROOT}` is not at the repo root (no "
              f"`pyproject.toml`), so this gate would report on a tree that is not this one",
              file=sys.stderr)
        return REFUSED
    # THE PRECONDITION IS ABSENT-OR-NOT, CHECKED FIRST AND NOT LAST. This gate holds no
    # claim about CPython, and the instrument that does (`device_vocab_holds`) is named
    # here rather than copied: if it stops existing, the reason for this gate's two claims
    # stops being measured by anybody and a PASS would be a PASS over nothing.
    if not CPY_HOLDER.exists() or "def device_vocab_holds(" not in CPY_HOLDER.read_text():
        print(f"devtag-gate: REFUSED: `{CPY_HOLDER.relative_to(ROOT)}` does not define "
              f"`device_vocab_holds`, so the CPython side of the wall this gate stands on is "
              f"unmeasured rather than held", file=sys.stderr)
        return REFUSED
    codes = [c1_two_names_two_tags(), c2_no_citation()]
    code = PASS if all(c == PASS for c in codes) else worst(codes)
    print(f"devtag-gate: {'PASS' if code == PASS else verdict_of(code)} -- two claims, no bend "
          f"lane, no row of its own")
    return code


if __name__ == "__main__":
    sys.exit(main())