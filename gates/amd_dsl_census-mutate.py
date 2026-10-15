#!/usr/bin/env python3
"""Mutation harness for `amd_dsl_census-gate.py`.

    .venv/bin/python gates/amd_dsl_census-mutate.py          # the whole table
    .venv/bin/python gates/amd_dsl_census-mutate.py A1 A2    # only these labels

ONE JOB: prove each of the eight checks has a mutation, and prove the POPULATION and AXIS
guards speak when the row set or a fixture axis is wrong. Four kinds, kept apart because a
mutation that finds nothing is a COVERAGE GAP and a mutation that cannot compile is a DEAD
DEF, and neither is a pass:

    VALUE        one row's ANSWER moves on the port lane.
    POPULATION   the ROW SET moves -- a `g_*` group is dropped, a row is renamed, a pin is
                 deleted. This is what catches a guard that stopped speaking.
    AXIS         the FIXTURE AXES drift. A fixture axis can change with every row still
                 matching, which is `cstyle_render_census`'s `render_index` lesson: its
                 mutation moved 0 of 358 rows at rc=0 and only `fixtures_hold` caught it.
    GUARD        the gate's OWN `*_hold` is mutated and must go red. A check never seen to
                 fail is not a check, and this gate carries eight of them.

THE PINS SHAPE IS ASSERTED BEFORE ANYTHING IS COUNTED. `amd_dsl_census-pins.rows` is
`row<TAB>oracle<TAB>port` -- THREE fields -- and `crp_graph_census-pins.rows` is FOUR with a
CLASS in column 2, while `decomp_value-pins.rows` is a THIRD shape whose verdict column holds
`same` 175 times; a tally parser that assumed one of them reported 452 declared divergences
where the truth is 254. `assert_pins()` fails LOUDLY on a shape mismatch and refuses a bare
verdict token in a value column, rather than counting whatever it finds.

EVERY COPY LIVES BESIDE ITS ORIGINAL, never in a tmpdir: `dsl.bend` imports
`../../helpers.bend` RELATIVE TO ITS OWN PATH, so a copy elsewhere answers "the substrate did
not warm" -- a REFUSED exit for the wrong reason. THE TREE'S OWN `dsl.bend` IS NEVER WRITTEN;
this unit reports bugs and the caller fixes them.

THE MUTATED ROWS ARE READ BEFORE THE GATE RUNS, and read from the INTERPRETED lane only.
The gate runs three lanes (`py`, `bend` interpreted, `bend` native) and empties
`gates/artifacts/` on every run, so the rows are read here with `bend` directly. The native
lane is a COMPILE check on the same source and adds no row the interpreted lane lacks.

GUARD MUTATIONS REUSE THE LANES INSTEAD OF REBUILDING THEM -- they import the mutated gate
copy and call `checks_hold()` against the artifacts the unmutated baseline run left in
`gates/artifacts/amd_dsl_census-gate/` -- because a guard reads lanes and a guard mutation is
not what touched them. Every other kind runs the whole gate, all three lanes. That is stated
rather than implied because it halves the cost of the eight guard mutations and a reader who
does not know it will read the timings wrong.

THE FIXTURE-VALUE MUTATIONS ARE THE POINT OF THE `AXIS` KIND HERE, and the gate's own header
names their history: `F64_VALS`'s `lit` was `0x1234` on one side and `0x12345678` on the other,
"two different FIXTURES, and no row noticed", because `hex8` masked both lanes to 32 bits and
`lit` sits at [63:32]. The word is an `H.I64` now and `raw_f64i` prints 64 bits, so the same
mutation must move a row TODAY. A mutation that moved nothing would mean the widening did not
close the hole, and that is worth more than the mutation. **MEASURED: `X1` moves 2 of 1178
(`raw_f64i` and `to_bytes_f64i`), so the widening closed it.**

**AND `fixtures_hold` SPEAKS ON IT TOO, WHICH THE TRANSCRIPT DOES NOT SHOW.** `main()` is
`code = run(); if code == 0 and not checks_hold()`, so **THE EIGHT CHECKS ARE UNREACHABLE ONCE A
LANE DISAGREES** -- X1's red run prints `DISAGREE` and never reaches a check. MEASURED by
calling `checks_hold()` alone against the unmutated lanes with a mutated `PORT`:
`fixtures_hold: F64_VALS.lit: VALUE port has1:'int:4660', oracle has1:'int:305419896'`, i.e.
`False`. **SO A FIXTURE DRIFT IS CAUGHT BY TWO INDEPENDENT INSTRUMENTS AND ONE RUN NAMES ONLY
ONE OF THEM.**
"""
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
GATE = HERE / "amd_dsl_census-gate.py"
PORT = ROOT / "tinybendygrad" / "renderer" / "amd" / "dsl.bend"
ORACLE = HERE / "amd_dsl_census-oracle.py"
PINS = HERE / "amd_dsl_census-pins.rows"

# `*mut.bend` IS IN `.gitignore` (line 36), so a run killed mid-flight cannot sweep the copy
# into a commit. `bend` REFUSES an import path whose first segment starts with a dot --
# MEASURED, `expected : an import path of plain names (letters, digits, _ and -; the hub's
# files import the hub's)` -- so the dot-prefixed spelling the other harnesses use is NOT
# available here.
MUT_PORT = PORT.with_name("dsl-mut.bend")
MUT_ORACLE = HERE / "amd-mut-oracle.py"
MUT_PINS = HERE / "amd-mut-pins.rows"
MUT_GATE = HERE / "amd-mut-gate.py"
MUT_RUN = HERE / "amd-mut-run.py"
COPIES = (MUT_PORT, MUT_ORACLE, MUT_PINS, MUT_GATE, MUT_RUN)

VERDICT_TOKENS = {"same", "DIFFER", "DIFF", "AGREE", "MATCH", "EXACT"}

# THE FOUR PINS WHOSE ORACLE COLUMN IS EMPTY, and the reason is a MEASUREMENT rather than a
# hole in the assertion below. `amds_dsl`'s own header says it: "The four MESSAGE rows MOVE
# rather than clear, because CPython never raises here, so its column is EMPTY and a moved row
# keeps its pin" -- `SrcField.__init__` (dsl.py:155-157) compares `1 << bits` (512) with the
# range count (512), accepts, and answers an empty message. MEASURED: `awk -F'\t'` over the
# pins file finds exactly 4 of 31 lines with an EMPTY column 2 and they are exactly these four.
# So the carve-out is a NAMED POPULATION and the assertion checks it in BOTH directions -- a
# FIFTH row emptying its oracle column fails the harness rather than passing it, which is the
# only way a carve-out is anything but a hole.
ORACLE_EMPTY = {(1, n) for n in
                ("sf_widthmsg_8_0", "sf_widthmsg_17_9", "sf_widthmsg_25_17", "sf_widthmsg_9_1")}


def assert_pins(path, nfields, value_columns, empty_allowed=()):
    """THE PINS SHAPE, OR LOUDLY NOTHING.

    `decomp_value-pins.rows` carries `same` in its verdict column 175 times (MEASURED) and a
    parser that added up column 2 there reported 452 declared divergences where the truth is
    254. A pins file of the wrong shape read as if it were the right one is how a number with
    no meaning gets quoted, so this asserts rather than counts -- and `empty_allowed` is a
    DECLARED SET OF `(column, row name)` PAIRS, checked in BOTH directions, never a rule that
    "sometimes empties are fine".
    """
    rows, bad, empties = [], [], set()
    for i, ln in enumerate(path.read_text().splitlines()):
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != nfields:
            bad.append(f"line {i + 1} has {len(parts)} fields, not {nfields}: {ln!r}")
            continue
        for c in value_columns:
            if not parts[c].strip():
                if (c, parts[0]) in empty_allowed:
                    empties.add((c, parts[0]))
                    continue
                bad.append(f"line {i + 1} column {c + 1} is EMPTY for {parts[0]!r} and that "
                           f"pair is not in the declared empty set "
                           f"{sorted(n for c_, n in empty_allowed)}")
            elif parts[c] in VERDICT_TOKENS:
                bad.append(f"line {i + 1} column {c + 1} is the VERDICT TOKEN {parts[c]!r}, "
                           f"not a rendered value -- this is the `decomp_value` shape")
        rows.append(parts)
    for pair in sorted(empty_allowed - empties):
        bad.append(f"column {pair[0] + 1} of {pair[1]!r} is declared EMPTY and is not -- the "
                   f"carve-out is stale and belongs in the comment, not in the set")
    if bad:
        print(f"{path.name}: THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS -- {nfields} "
              f"fields, value columns {tuple(c + 1 for c in value_columns)}:\n  "
              + "\n  ".join(bad[:6]), file=sys.stderr)
        raise SystemExit(2)
    return rows


def _runner(checks_only):
    """A driver that imports the gate COPY with its three paths pointed at the mutated files.

    `DIVERGES` AND `_U32_DEFS` ARE BOTH READ AT IMPORT TIME -- the pins through `_pins()`, and
    the `def X() -> U32` table out of `PORT` -- so overriding `m.PORT`/`m.PINS` alone would
    leave BOTH mutated files unused and every port and pins mutation a silent green. Both are
    re-derived here, from the mutated files, in the gate's own words.
    """
    head = ("import importlib.util, sys, re\nfrom pathlib import Path\n"
            "spec = importlib.util.spec_from_file_location('g', %r)\n"
            "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
            "m.PORT = Path(%r)\nm.ORACLE = Path(%r)\nm.PINS = Path(%r)\n"
            "m.DIVERGES, m.WHY = m._pins()\n"
            "m._U32_DEFS = {x.group(1): int(x.group(2)) for x in re.finditer(\n"
            "    r'^def (\\w+)\\(\\) -> U32: (\\d+)$', m.PORT.read_text(), re.M)}\n"
            % (str(MUT_GATE), str(MUT_PORT), str(MUT_ORACLE), str(MUT_PINS)))
    if checks_only:
        return head + "sys.exit(0 if m.checks_hold() else 1)\n"
    return head + "sys.exit(m.main())\n"


def _clean():
    for p in COPIES:
        p.unlink(missing_ok=True)


def write_copies(**which):
    """The mutated copies, with EVERY FILE WRITTEN -- a missing one is a REFUSED exit for the
    wrong reason, and a harness that calls that `the mutation was found` has learned
    nothing. `which` names the files to mutate; the rest get the originals."""
    MUT_PORT.write_text(which.get("port") or PORT.read_text())
    MUT_ORACLE.write_text(which.get("oracle") or ORACLE.read_text())
    MUT_PINS.write_text(which.get("pins") or PINS.read_text())


def run_gate(checks_only=False, gate_text=None):
    MUT_GATE.write_text(GATE.read_text() if gate_text is None else gate_text)
    MUT_RUN.write_text(_runner(checks_only))
    try:
        r = subprocess.run([sys.executable, str(MUT_RUN)], capture_output=True, text=True,
                           cwd=str(ROOT))
        return r.returncode, r.stdout + r.stderr
    finally:
        _clean()


def lane_rows(argv):
    """The lane's lines, AS A LIST, and read MYSELF and BEFORE the gate runs -- `gatekit` and
    this gate both empty their artifact directory on every run and a red run discards what it
    staged, so reading the rows afterwards compares the BASE against itself.

    A LIST AND NOT A DICT, and that is FINDING A: `dsl.bend`'s body prints 1177 rows under
    1163 distinct names, so a `{name: line}` reader answers 1164 where the lane printed 1178
    and the fourteen duplicates vanish silently -- MEASURED here, on the unmutated tree, as
    `bd=1164 rows`. `gatekit` diffs LANE BY LINE for the same reason: "a missing duplicate
    would misalign every row after it and the value diff would be reading the wrong pairs".
    """
    r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        return None, ((r.stderr or r.stdout).strip().splitlines() or ["no output"])[-1:]
    return [l for l in r.stdout.splitlines() if "=" in l], []


def moved(base, got):
    """`(moved, appeared, vanished)` POSITIONALLY, the way `gatekit` diffs.

    Equal lengths are compared index by index -- a renamed row is then a moved row, which is
    the truth: `gatekit` would red on it. Unequal lengths are reported as an appearance or a
    disappearance BY NAME with a MULTISET count, because a population change is a mutation
    that moved and not one that failed to compile: MEASURED precedent, `mutkit`'s own note on
    `ra*t>_a<i`.
    """
    if got is None:
        # A LANE THAT DID NOT COMPILE reports everything as gone. `[]` here is the bug this
        # harness shipped with: `moved()`'s first element is a COUNT, and a list in that slot
        # raises `TypeError: can only concatenate list (not "int") to list` on the caller's
        # `mv + len(ap)`, which aborts the run before it prints the summary.
        return 0, [], sorted({l.split("=", 1)[0] for l in base})
    if len(got) == len(base):
        return sum(1 for a, b in zip(base, got) if a != b), [], []
    bn, gn = Counter(l.split("=", 1)[0] for l in base), Counter(l.split("=", 1)[0] for l in got)
    return 0, sorted((gn - bn).elements()), sorted((bn - gn).elements())


# THE TABLE. `(label, kind, file, find, replace)`, plus an OPTIONAL fifth element
# `(gate_old, gate_new)` applied to the GATE ITSELF alongside the file edit. `file` is one of
# port/oracle/pins/gate. Every `find` is ASSERTED UNIQUE in its own file before it is applied,
# so a mutation that silently stopped matching is a REFUSED entry and not a green one.
MUTATIONS = [
    # ---------------------------------------------------------------- VALUE
    ("A1 wplaced drops the shift -- the AMDWORD32 word", "VALUE", "port",
     "def wplaced(enc: U32, lo: U32) -> H.I64: H.i64_shl(H.i64_of_i32(enc), U32.to_nat(lo))",
     "def wplaced(enc: U32, lo: U32) -> H.I64: H.i64_of_i32(enc)"),
    ("A2 bf_in_word never refuses -- the WORD_64 guard is dropped", "VALUE", "port",
     "def bf_in_word(+f: Fld) -> Bool: U32.is_le(Fld.hi(f), WORD_HI())",
     "def bf_in_word(+f: Fld) -> Bool: True{}"),
    ("A3 al_shift_of's two arms are swapped", "VALUE", "port",
     "  Bool.pick(U32, al_shift_of.is2(a), al_shift_of.two(), al_shift_of.four())",
     "  Bool.pick(U32, al_shift_of.is2(a), al_shift_of.four(), al_shift_of.two())"),
    ("A4 src_bit.vdst tests \"vdsty\" against itself -- the tautology again", "VALUE", "port",
     '  Bool.pick(U32, String.eq(name, "vdst"), MOD_VDST_BIT(), rest)',
     '  Bool.pick(U32, String.eq(name, "vdsty"), MOD_VDST_BIT(), rest)'),
    ("A5 mod_hit loses the NEG arm", "VALUE", "port",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.ab(m, v, mod_hit.opsel(m, v, False{})))",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.ab(m, v, mod_hit.opsel(m, v, False{}))"),
    ("A6 mod_hit loses the ABS arm", "VALUE", "port",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.ab(m, v, mod_hit.opsel(m, v, False{})))",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.opsel(m, v, False{}))"),
    ("A7 mod_hit loses the OPSEL arm", "VALUE", "port",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.ab(m, v, mod_hit.opsel(m, v, False{})))",
     "def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.ab(m, v, False{}))"),
    ("A8 bf_set.placed puts the field at bit 0", "VALUE", "port",
     "def bf_set.placed(f: Fld, enc: U32) -> H.I64: wplaced(enc, Fld.lo(f))",
     "def bf_set.placed(f: Fld, enc: U32) -> H.I64: wplaced(enc, 0)"),
    ("A9 bf_in_word refuses at 32 rather than at 64", "VALUE", "port",
     "def bf_in_word(+f: Fld) -> Bool: U32.is_le(Fld.hi(f), WORD_HI())",
     "def bf_in_word(+f: Fld) -> Bool: U32.is_le(Fld.hi(f), 32)"),

    # ------------------------------------------------------------ POPULATION
    ("P1 main() no longer calls g_lit()", "POPULATION", "port",
     "    h : Unit <- g_lit()\n", ""),
    ("P2 main() calls g_lit() where g_inst() was", "POPULATION", "port",
     "    h : Unit <- g_lit()\n    +i : Unit <- g_inst()\n",
     "    h : Unit <- g_inst()\n    +i : Unit <- g_lit()\n"),
    ("P3 the ORACLE drops its completion marker", "POPULATION", "oracle",
     '    print("dsl-done=1")\n', "    pass\n"),
    ("P4 one bfset row is RENAMED (same count, new name)", "POPULATION", "port",
     'row("bfset_word63"', 'row("bfset_wordXX"'),
    # THE DUPLICATE IS A WHOLE REPEATED STATEMENT. The first version read
    # `row("bfset_word63"` and spliced `row("bfset_word63", 0n, 0n, 0n, 0n)` in front of it,
    # which is not the port's spelling -- `dsl.bend` uses `srow` and `bfs` takes THREE arguments
    # -- so `bend` answered with a type error and the run came back REFUSED. **A mutation that
    # does not compile is not evidence in either direction**, so it is reported as its own
    # outcome and not filed as a coverage gap.
    ("P5 one bfset row is DUPLICATED (FINDING A's 14 grows to 15)", "POPULATION", "port",
     '    srow("bfset_word63", bfs(Fld.plain("lit", 63, 32), w32(0), 2147483648))\n',
     '    srow("bfset_word63", bfs(Fld.plain("lit", 63, 32), w32(0), 2147483648))\n'
     '    srow("bfset_word63", bfs(Fld.plain("lit", 63, 32), w32(0), 2147483648))\n'),

    # ----------------------------------------------------------------- AXIS
    # A3 OF THE GATE'S OWN HEADER: `F64_VALS`'s `lit` was `0x1234` on one side and
    # `0x12345678` on the other and NO ROW NOTICED, because `hex8` masked both lanes to 32
    # bits and `lit` sits at [63:32]. The word is an `H.I64` now. A mutation that moved
    # nothing would mean the widening did not close the hole.
    ("X1 F64_VALS' lit is 0x1234 -- the pre-widening fixture value", "AXIS", "port",
     'Ov.int(305419896)', 'Ov.int(4660)'),
    ("X2 VOP2_ALL's src0 is a different register -- a fixture AXIS, not a value", "AXIS",
     "port",
     'Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, True{}), True{})',
     'Vf.of(Fld.src("src0", 25, 17), Ov.reg(4, 1, False{}, False{}, True{}), True{})'),
    ("X3 VOP2_NEG's `src0` has neg set, so the neg family asks about a different register", "AXIS",
     "port",
     '   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, True{}, False{}, False{}), True{}),\n'
     '   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(5, 1, False{}, False{}, False{}), True{}),\n'
     '   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),\n'
     '   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]\n\ndef VOP2_HI()',
     '   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, False{}), True{}),\n'
     '   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(5, 1, False{}, False{}, False{}), True{}),\n'
     '   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),\n'
     '   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]\n\ndef VOP2_HI()'),
    ("X4 the ORACLE's `lit` fixture drifts, port untouched", "AXIS", "oracle",
     'F64_VALS = [("op", None), ("lit", 305419896)]',
     'F64_VALS = [("op", None), ("lit", 4660)]'),
    # `fmt_105_1` IS PRINTED TWICE BY `g_fmt` -- one of FINDING A's fourteen -- so the pattern
    # has to carry the surrounding lines to be unique, which is itself a reminder that the
    # census is not a keyed table.
    ("X5 the fmt axis loses the 105 width, so a `Reg.fmt` arm boundary is uncovered", "AXIS",
     "port",
     '    srow("fmt_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))\n'
     '    srow("fmtp_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, True{}, True{})))\n'
     '    srow("fmtm_105_1", Res.msg(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))\n'
     '    srow("fmt_256_1"',
     '    srow("fmt_115_1", Res.s(reg_fmt(Rg{115, 1, False{}, False{}, False{}}, 0, False{}, False{})))\n'
     '    srow("fmtp_115_1", Res.s(reg_fmt(Rg{115, 1, False{}, False{}, False{}}, 0, True{}, True{})))\n'
     '    srow("fmtm_115_1", Res.msg(reg_fmt(Rg{115, 1, False{}, False{}, False{}}, 0, False{}, False{})))\n'
     '    srow("fmt_256_1"'),

    # ---------------------------------------------------------------- GUARD
    ("G1 groups_hold: the driver axis is ten groups, not eleven", "GUARD", "gate",
     'GROUPS = ("tables", "const", "get", "fmt", "mod", "bf", "enc", "lit", "inst",\n'
     '          "ops", "vs")',
     'GROUPS = ("tables", "const", "get", "fmt", "mod", "bf", "enc", "lit", "inst",\n'
     '          "ops")'),
    ("G2 names_hold: the port's completion marker is `dsl-done=2`", "GUARD", "gate",
     'return names + ["dsl-done=1"]', 'return names + ["dsl-done=2"]'),
    ("G3 dup_rows_hold: thirteen duplicated names, not fourteen", "GUARD", "gate",
     "    if len(dups) != 14:", "    if len(dups) != 13:"),
    ("G4 axes_hold: only offset 125 is uncovered, not 125 and 127", "GUARD", "gate",
     'if sorted(o for o in d.Reg._NAMES if o not in covered) != [125, 127]:',
     'if sorted(o for o in d.Reg._NAMES if o not in covered) != [125]:'),
    # `ad117c928^^` WAS TRIED HERE AND IS **NOT** A MUTATION: it is the GRANDPARENT, a valid
    # revision, and `dsl.py` has not moved in the file's whole history, so all three blobs are
    # `6526706b` and the check is green. A revision that LOOKS malformed and resolves is the
    # cheapest way to write a green that means nothing, so the rev here must be one `git`
    # cannot resolve at all.
    ("G5 pin_drift_hold: the PIN is a revision git cannot resolve", "GUARD", "gate",
     'PIN = "ad117c928^"          # the pin AGENTS.md names for a drifted file',
     'PIN = "nosuchrev"          # the pin AGENTS.md names for a drifted file'),
    ("G6 fixtures_hold: one fixture value is ADMITTED as a difference", "GUARD", "gate",
     "VAL_DIFF_ADMITTED = ()",
     'VAL_DIFF_ADMITTED = (("F64_VALS", "lit"),)'),
    ("G7 divergences_hold: thirty pinned divergences, not thirty-one", "GUARD", "gate",
     "    if len(DIVERGES) != 31:", "    if len(DIVERGES) != 30:"),
    ("G8 classes_hold: SRC_WIDTH's pattern matches nothing, so the class has no rows", "GUARD",
     "gate", '("SRC_WIDTH", r"^sf_width(msg)?_")', '("SRC_WIDTH", r"^sf_widthxx_")'),
    ("G8b classes_hold: a pin matches TWO classes", "GUARD", "gate",
     '("WORD_64", r"^bfset_word\\d+$")', '("WORD_64", r"^bfset_word\\d+$|^afenc_sr_127$")'),
    # THE NEEDLE IS CHOSEN BY MEASUREMENT, NOT BY MEMORY: `00000000` LOOKS absent and is
    # PRESENT, as a substring of `bfset_word64`'s pinned `0x10000000000000000`, so the first
    # version of this mutation was a GREEN that meant nothing. `65267000` is `grep -c` 0 in the
    # pins file and is the right shape -- eight hex digits, one digit off the real blob.
    ("G9 pin_drift_hold: the blob it demands is one the pins file does not record", "GUARD",
     "gate", '        if head and head not in PINS.read_text():',
     '        if head and "65267000" not in PINS.read_text():'),
    ("G9b pin_drift_hold: the recording assertion is REMOVED (a WEAKENING)", "GUARD",
     "gate", "        if head and head not in PINS.read_text():",
     "        if False:"),
]

SOURCES = {"port": PORT, "oracle": ORACLE, "pins": PINS, "gate": GATE}


def main(argv):
    pins = assert_pins(PINS, 3, (1, 2), empty_allowed=ORACLE_EMPTY)
    print(f"amd pins shape ASSERTED: 3 fields (row<TAB>oracle<TAB>port), columns 2 and 3 are "
          f"rendered values, {len(ORACLE_EMPTY)} of them declared EMPTY (CPython does not "
          f"refuse on those rows); {len(pins)} pin(s)\n")

    want = [m for m in MUTATIONS if not argv or m[0].split()[0] in argv]
    # GUARDS FIRST, AND THE ORDER IS LOAD-BEARING. A guard mutation reads the lanes in
    # `gates/artifacts/amd_dsl_census-gate/`, and this gate EMPTIES that directory at the top
    # of `run()` and leaves it EMPTY when the run was not green -- so a guard mutation that
    # runs after a red input mutation reads an EMPTY artifact and every check that reads a
    # lane goes red for a reason that has nothing to do with the mutation. MEASURED on the
    # sibling `crp` harness: 10 of its 11 guards were red for exactly that reason.
    want.sort(key=lambda m: m[1] != "GUARD")
    width = max(len(m[0]) for m in want)
    kinds, moved_any, zero, zero_red, refused, guards, guard_fail, notrun = \
        {}, 0, [], [], 0, 0, 0, []
    try:
        write_copies()
        rc0, out0 = run_gate()
        base_bd, why = lane_rows([str(BEND), str(PORT)])
        base_py, _ = lane_rows([str(PY), str(ORACLE)])
        if rc0 != 0 or base_bd is None or base_py is None:
            print(f"amd_dsl_census-gate: the UNMUTATED tree is rc={rc0} and the lanes are "
                  f"{len(base_bd or {})} / {len(base_py or {})}, so every mutation below would "
                  f"be meaningless\n{out0}{why}")
            return 1
        ndiv = sum(1 for a, b in zip(base_py, base_bd) if a != b)
        print(f"UNMUTATED  rc={rc0}  bd={len(base_bd)} lines  py={len(base_py)} lines  "
              f"{len(Counter(l.split('=', 1)[0] for l in base_bd))} distinct port row names  "
              f"{ndiv} divergence(s)\n")
        for entry in want:
            label, kind, f, old, new = entry[:5]
            gate_patch = entry[5] if len(entry) > 5 else None
            kinds[kind] = kinds.get(kind, 0) + 1
            # `moved()` RETURNS A COUNT, a list of appearances and a list of disappearances, so
            # `mv` is 0 and not `[]` -- the first version of this line wrote `[]` and every
            # mutation that moved rows without changing a count raised
            # `TypeError: can only concatenate list (not "int") to list`.
            mv, ap, va = 0, [], []
            src = SOURCES[f].read_text()
            if src.count(old) != 1:
                print(f"  {label:<{width}}  [{kind}]  REFUSED: the pattern occurs "
                      f"{src.count(old)} times, expected 1")
                refused += 1
                continue
            if f == "gate":
                guards += 1
                write_copies()
                rc, out = run_gate(checks_only=True, gate_text=src.replace(old, new))
                if rc != 0:
                    guard_fail += 1
                print(f"  {label:<{width}}  [GUARD]  rc={rc}  "
                      + ("RED  the guard speaks" if rc
                         else "GREEN  <-- THE CHECK DID NOT FIRE"))
            else:
                write_copies(**{f: src.replace(old, new)})
                gtext = None
                if gate_patch is not None:
                    if GATE.read_text().count(gate_patch[0]) != 1:
                        print(f"  {label:<{width}}  [{kind}]  REFUSED: the GATE pattern occurs "
                              f"{GATE.read_text().count(gate_patch[0])} times, expected 1")
                        refused += 1
                        continue
                    gtext = GATE.read_text().replace(*gate_patch)
                bd, w = lane_rows([str(BEND), str(MUT_PORT)])
                py, _ = lane_rows([str(PY), str(MUT_ORACLE)])
                mv, ap, va = moved(base_bd, bd)
                if py is not None and py != base_py:
                    pm, pa, pv = moved(base_py, py)
                    mv, ap, va = mv + pm, ap + pa, va + pv
                rc, out = run_gate(gate_text=gtext)
                n = mv + len(ap) + len(va)
                if n:
                    moved_any += 1
                elif rc == 0:
                    zero.append(label)
                else:
                    # MOVED NOTHING AND STILL WENT RED: caught by a check that does not read a
                    # row, so the 1178 lines said nothing about the mutation and only a guard
                    # did. Kept as its own list because "moved nothing" and "moved nothing AND
                    # the gate noticed" are different findings.
                    zero_red.append(label)
                if bd is None:
                    notrun.append(label)
                print(f"  {label:<{width}}  [{kind}]  rc={rc} "
                      + ("RED" if rc else "GREEN  <-- THE MUTATION WAS NOT FOUND")
                      + f"  {n} rows moved"
                      + (f", {len(ap)} appeared" if ap else "")
                      + (f", {len(va)} vanished" if va else "")
                      + (f", bend rc!=0 -- {w[0][:70]}" if bd is None else ""))
            said = [ln.strip() for ln in out.splitlines()
                    if ln.strip() and ": OK" not in ln and "AMDWORD32-ONLY" not in ln
                    and not ln.startswith(("UNMUTATED", "amd pins", "amd_dsl_census: PASS"))
                    and any(k in ln for k in ("_hold:", "DISAGREE", "REFUSE", "rows,",
                                              "is not '", "appears", "FAIL", "DEAD",
                                              "not declared", "expected"))]
            for ln in said[:3]:
                print(f"      {ln[:170]}")
            if mv:
                print(f"      {mv} rows differ BY POSITION out of {len(base_bd)}")
            if ap:
                print(f"      APPEARED {', '.join(ap[:6])}")
            if va:
                print(f"      VANISHED {', '.join(va[:6])}")
    finally:
        _clean()
    nin = len(want) - guards
    print(f"\namd_dsl_census-mutate: {kinds} by kind; {moved_any} of {nin} input mutations "
          f"moved rows; {len(zero)} moved NOTHING at rc=0; {len(zero_red)} moved nothing but "
          f"still went RED (caught by a check that does not read a row); {len(notrun)} did not "
          f"compile (a dead def or a load-bearing type); {refused} refused on a non-unique "
          f"pattern; {guard_fail} of {guards} guard mutations went red")
    for z in zero:
        print(f"  MOVED NOTHING AT rc=0: {z}")
    for z in zero_red:
        print(f"  MOVED NOTHING, RED ANYWAY (no row saw it): {z}")
    for z in notrun:
        print(f"  DID NOT COMPILE: {z}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))