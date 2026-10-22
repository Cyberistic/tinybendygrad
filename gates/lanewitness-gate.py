#!/usr/bin/env python3
"""lanewitness-gate.py -- DOES EVERY LANE THAT PRINTS `py=` ROWS HAVE A LIVE WITNESS?

    .venv/bin/python gates/lanewitness-gate.py            # the three lanes this unit owns
    .venv/bin/python gates/lanewitness-gate.py --census   # the census of ALL the lanes
    .venv/bin/python gates/lanewitness-gate.py --plant    # the plants

THE QUESTION, AND WHY IT IS A QUESTION ABOUT LANES.

A `py=` row is a row in which the port prints CPython's answer BESIDE its own.  Nine
of the port's files print such rows, and the rows are the only thing that makes a
port's answer CHECKABLE against upstream: a derived row's two halves always agree
with each other, so the `py=` half is not a witness and never was meant to be -- the
WITNESS is an ORACLE that computes the same question in CPython, and the assertion
is the diff between the two.

**A DERIVED ROW WITH NO WITNESS IS A ROW THAT CANNOT GO RED.**  The census that
derived those rows measured 369 `py=` cells whose value was a TRANSCRIPTION -- frozen
text, agreeing with the port today and rotting the moment either side moves -- and
replaced them with DERIVED rows.  And a derived row is WORSE than a transcription for
the purpose of going red, because it agrees with itself BY CONSTRUCTION: the teeth
have nowhere to land until an oracle answers the same question in CPython.

SO THE COUNT IS THE DELIVERABLE: the number of lanes that print `py=` rows and have
NO LIVE ORACLE LANE.  It is measured, it is named, and it must be ZERO.

THE POPULATIONS, AND NEITHER OF THEM IS A LIST.

  THE LANES   `gates/pycell-census.py`, LOADED BY PATH -- the tree's own instrument
              for "which `.bend` files carry `py=` cells", and it discovers them by
              walking the port root (`os.walk` + `endswith`, never `glob`, which
              returns `[]` when `.bend` files are on disk).  The census's own file is
              another unit's LIVE file, so it is loaded and not copied, and a
              refusal to load it is a REFUSED verdict and not a zero.
  THE ORACLES a WALK of the two gate homes for a file whose stem carries `oracle`.
              That is a SHAPE and not a population, and it is reported as such: an
              oracle no lane names is a denominator, not a verdict.  The walk covers
              `gates/` and `checks/` and NOT `.agents/slop/`, and that is the whole
              point -- `.agents/slop/` is being pruned, and an oracle that lives in a
              pruned directory is an oracle that can lose its own ability to fail.

THE WITNESS TEST IS A MEASUREMENT, NOT A DECLARATION.  A lane is WITNESSED when some
oracle, RUN, emits a row whose NAME is one of the rows the lane prints.  Both sides
are run, so the pairing cannot be a comment that went stale and cannot be a hand
list of "these two go together".  An oracle that RUNS but answers none of the lane's
rows is not a witness of that lane, and it is said so by name.

THE THREE LANES THIS UNIT OWNS, AND WHAT EACH ONE'S WITNESS LOOKS LIKE.

  objc             `gates/objc-oracle.py` -- RECOVERED.  123 port rows, 105 of them
                   answered, 91 agreeing, 14 DECLARED DIVERGENCES pinned on BOTH
                   sides, 18 the oracle does not answer.
  amd/generate     `gates/ga-oracle.py` -- RECOVERED.  726 port rows, 726 agreeing,
                   and every one of the 726 is BYTE-IDENTICAL as a whole row.
  renderer/__init__ `gates/renderer_init-oracle.py` -- BUILT, because the lane had NO
                   ORACLE AT ALL: its header said its `py=` text "is diffed against
                   CPython on this `tinygrad/` tree with `.venv/bin/python -c "..."`",
                   and A COMMAND IS NOT AN ORACLE.  18 port rows, 18 agreeing.

THE VERDICTS ARE `gatekit`'s: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.  A lane that
emitted no rows is DEAD, not PASS, and an input that is not there is REFUSED, not
FAIL.  "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO GATE."
"""
from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from lanecmp import compare, read_rows  # noqa: E402

PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
BOUNDED = ROOT / "checks" / "bounded.py"
LOCK = ROOT / "checks" / "bendlock.sh"
PORT_ROOT = ROOT / "tinybendygrad"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
ORACLE_TIMEOUT = 90
BEND_TIMEOUT = 600


def say(msg: str) -> None:
    print(f"lanewitness-gate: {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# THE THREE LANES, AND THEIR DECLARED DIVERGENCES.
#
# A DIVERGENCE is a row where the two sides are KNOWN to differ, and it is pinned on
# BOTH sides -- pinning one side can only ever describe half of it.  The pin is the
# COMPARED VALUE, not the whole row, because the two sides do not share a shape here:
# the recovered objc oracle is F1 (`name=value`) and the port's rows are F2
# (`name = [value]   py=[value]`), so a whole-row pin would pin the spelling and not
# the answer.
#
# AND EVERY ONE OF THE FOURTEEN IS NAMED, because a divergence nobody can explain is
# a divergence nobody can trust:
#
#   ELEVEN are a REPRESENTATION difference: the port encodes a ctypes type as a
#   small INT (`id_` is 1, `c_ulong` is 4) because Bend has no Python type object,
#   and CPython prints the type's NAME.  `msg_argtypes_one` is `1,1,4` here and
#   `[id_,id_,c_ulong]` there, and NEITHER IS WRONG.
#   TWO are a SYNTHETIC ADDRESS: the oracle's fake loader hands out `0x1000+8n` and
#   the port has its own, and two fabrications cannot be equal.
#   ONE is a POLARITY difference: the oracle's `shape_at_2_absent` ASSERTS that
#   index 2 is absent (a hardcoded `True` -- a transcription inside the ORACLE, which
#   is the rot this whole exercise is about), while the port's row of the same name
#   ANSWERS "is index 2 present" and answers `False`.  The two rows ask OPPOSITE
#   questions under ONE name, and the port's answer is the one that agrees with the
#   truth.
DIVERGES = {
    "msg_argtypes_none": ("[]", ""),
    "msg_argtypes_one": ("[id_,id_,c_ulong]", "1,1,4"),
    "msg_argtypes_two": ("[id_,id_,c_ulong,c_ulong]", "1,1,4,4"),
    "msg_argtypes_keeps_declared_tail": ("[id_,id_,c_ulong]", "1,1,4"),
    "shape_argv_order": ("7,9,c_ulong,c_ulong", "7,9,4,4"),
    "shape_send_recv_cls": ("4160", "48059"),
    "shape_send_recv_cls_in_three": ("4160", "48059"),
    "shape_at_2_absent": ("True", "False"),
    "meth_ret_inst_becomes_class": ("ChildFake", "7"),
    "meth_ret_plain_passes_through": ("c_ulong", "4"),
    "meth_args_inst_becomes_class": ("[id_,id_,ChildFake]", "1,1,7"),
    "meth_args_scalar_pass_through": ("[id_,id_,c_ulong]", "1,1,4"),
    "meth_args_inst_third": ("ChildFake", "7"),
    "meth_args_inst_both_ends": ("[id_,id_,TwoArgFake,c_ulong,TwoArgFake]", "1,1,7,4,7"),
}

# THE PORT-ONLY ROWS: the port prints them and the oracle DELIBERATELY DOES NOT.
# The ABSENCE is the claim and it is held by the row counts, so there is nothing to
# pin on the oracle side -- there is no oracle side.
PORT_ONLY = [
    "meth_args_inst_is_not_8", "objc-done", "sel_empty_count", "sel_empty_miss",
    "sel_ix_absent_is_0", "sel_ix_commit_is_1", "shape_at_2_is_MISSING",
    "shape_send_sel_ix", "shape_send_sel_ix_third", "sym_libm_exports_selname",
    "sym_libobjc_exports_msgsend", "sym_libobjc_exports_selname",
    "sym_libobjc_handle_same_address", "sym_libsystem_exports_selname",
    "sym_metal_exports_msgsend", "sym_metal_exports_selname",
    "sym_metal_handle_reaches_msgsend", "sym_metal_handle_reaches_selname",
]

LANES = [
    ("runtime/support/objc.bend", "gates/objc-oracle.py"),
    ("renderer/amd/generate.bend", "gates/ga-oracle.py"),
    ("renderer/__init__.bend", "gates/renderer_init-oracle.py"),
]


# --------------------------------------------------------------------------- runners

def port_rows(rel: str) -> tuple[list | None, str]:
    """the PORT's lane, through the lock and the watchdog.  `(rows, why)`.

    `rel` is the path BELOW the port root -- the census's own key, `renderer/isa/x86.bend`
    -- and the port root is `tinybendygrad/`, so the two are joined here and not at
    every call site.  (Joining them at the call site is how the first run of this
    census answered "the driver is absent" for all THIRTEEN lanes: it looked for
    `<repo>/renderer/isa/x86.bend`, which is not a path in this tree.)
    """
    src = PORT_ROOT / rel
    if not src.is_file():
        return None, f"the driver is absent: {src}"
    cmd = [str(LOCK), "--", str(PY), str(BOUNDED), "--seconds", "300", "--mb", "2048",
           "--", str(BEND), str(src)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT),
                           timeout=BEND_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, "the port did not finish"
    token = ""
    for line in (r.stderr or "").splitlines():
        if "[bounded]" in line:
            token = line.split("[bounded]", 1)[1].strip().split()[0]
    if r.returncode != 0 or not token.startswith("WITHIN-LIMITS"):
        said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()[-3:])[:200]
        return None, f"the port ran under {token or 'NO-RECORD'} rc={r.returncode}: {said}"
    if not r.stdout.strip():
        return None, "the port ran and emitted no rows"
    return read_rows(r.stdout), ""


def oracle_rows(path: Path) -> tuple[list | None, str]:
    """an ORACLE's rows.  `(rows, why)` -- `why` is set when the lane could not answer."""
    if not path.is_file():
        return None, "the oracle is absent"
    try:
        r = subprocess.run([str(PY), str(path)], capture_output=True, text=True,
                           cwd=str(ROOT), timeout=ORACLE_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, f"the oracle did not finish in {ORACLE_TIMEOUT}s"
    if r.returncode != 0:
        said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()[-3:])[:200]
        return None, f"the oracle failed rc={r.returncode}: {said}"
    if not r.stdout.strip():
        return None, "the oracle ran and emitted no rows"
    return read_rows(r.stdout), ""


# --------------------------------------------------------------------------- the lanes

def lane_verdict(rel: str, oracle: Path) -> tuple[int, str]:
    """the comparison for ONE lane.  `(verdict, summary)`."""
    prows, why = port_rows(rel)
    if prows is None:
        return REFUSED, why
    orows, why = oracle_rows(oracle)
    if orows is None:
        return REFUSED, why
    c = compare(prows, orows)
    diverges = DIVERGES if "objc" in rel else {}
    port_only = set(PORT_ONLY if "objc" in rel else [])

    # THE DECLARED DIVERGENCES ARE CHECKED AGAINST THE LANES, NOT TRUSTED.  A
    # declaration says "the two sides DIFFER here", so if they are the SAME the
    # declaration is STALE and the gate REFUSES rather than excluding a row it no
    # longer measures.  A divergence that cannot go stale is a label.
    for name, (want_oracle, want_port) in diverges.items():
        got_o = [r.value for r in _named(orows, name)]
        got_p = [r.value for r in _named(prows, name)]
        if not got_o or not got_p:
            return FAIL, f"the declared divergence {name!r} is not in both lanes"
        if want_oracle not in got_o or want_port not in got_p:
            return FAIL, (f"the declared divergence {name!r} moved: oracle={got_o} "
                          f"port={got_p}; if it is fixed, drop the declaration")
    skip = set(diverges) | port_only
    differ = [(n, p, o) for n, p, o in c["differ"] if n not in skip]
    unanswered = [(n, p) for n, p in c["unanswered"] if n not in port_only]
    if differ:
        n, p, o = differ[0]
        return FAIL, (f"{len(differ)} row(s) DISAGREE; first {n!r}: port={p.value!r} "
                      f"oracle={[r.value for r in o]!r}")
    if unanswered:
        n, p = unanswered[0]
        return FAIL, f"{len(unanswered)} row(s) the oracle does not answer; first {n!r}"
    ambiguous = c["agree_many"]
    note = f"{len(c['agree'])} agree"
    if ambiguous:
        note += f", {len(ambiguous)} agree among a DUPLICATED oracle name"
    return PASS, (f"{len(prows)} port rows, {len(c['agree']) + len(ambiguous)} answered "
                  f"and agreeing, {len(diverges)} declared divergences, {note}")


def _named(rows, name):
    return [r for r in rows if r.name == name]


# --------------------------------------------------------------------------- the census

def tracked_paths() -> set[str]:
    """the paths the COMMIT TREE carries, and NOT the index.

    `git ls-tree -r HEAD` reads the COMMIT, and `git ls-files` reads the INDEX --
    and this tree's index is ARMED (an armed index lists fresh files as DELETIONS),
    so an index-derived "is this tracked" answers about a tool and not about the
    tree.  A witness that is UNTRACKED is reported as such: it works today and it
    can be swept tonight, and a witness that can be swept is not a witness.
    """
    r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"],
                       capture_output=True, text=True, cwd=str(ROOT))
    return set(r.stdout.split())


def census() -> int:
    """EVERY lane that prints `py=` rows, and whether it has a live oracle lane."""
    spec = importlib.util.spec_from_file_location("pycell_census_for_witness",
                                                  HERE / "pycell-census.py")
    cm = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(cm)
    except Exception as exc:  # noqa: BLE001
        print(f"== REFUSED, NOT A VERDICT: the census instrument did not load: "
              f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return REFUSED
    _rows, per_file, _files, _defs = cm.census(str(PORT_ROOT))
    lanes = sorted(rel for rel, c in per_file.items() if c)

    oracles = []
    for home in ("gates", "checks"):
        for p in sorted((ROOT / home).glob("*oracle*.py")):
            oracles.append(p)
    print(f"LANES  : {len(lanes)} (DISCOVERED by gates/pycell-census.py, loaded by path)")
    print(f"ORACLES: {len(oracles)} (a WALK of gates/ and checks/ for a stem carrying "
          f"`oracle` -- a SHAPE, reported as a second class, and NOT `.agents/slop/`, "
          f"which is being pruned)")

    tracked = tracked_paths()
    cache: dict[Path, tuple[list | None, str]] = {}
    unwitnessed = []
    untracked_only = []
    for rel in lanes:
        prows, why = port_rows(rel)
        if prows is None:
            print(f"  {rel:38s} NO WITNESS -- the lane could not be run: {why}")
            unwitnessed.append(rel)
            continue
        pnames = {r.name for r in prows}
        hits = []
        for o in oracles:
            if o not in cache:
                cache[o] = oracle_rows(o)
            orows, _why = cache[o]
            if not orows:
                continue
            if pnames & {r.name for r in orows}:
                hits.append(o)
        if hits:
            names = ", ".join(f"{h.relative_to(ROOT)}{'' if str(h.relative_to(ROOT)) in tracked else ' (UNTRACKED)'}"
                              for h in hits)
            print(f"  {rel:38s} WITNESSED by {names}")
            if not any(str(h.relative_to(ROOT)) in tracked for h in hits):
                untracked_only.append(rel)
        else:
            print(f"  {rel:38s} NO WITNESS -- no oracle answers any of its rows")
            unwitnessed.append(rel)
    print(f"LANES WITHOUT A LIVE ORACLE LANE: {len(unwitnessed)} of {len(lanes)}")
    for rel in unwitnessed:
        print(f"  NO-WITNESS {rel}")
    print(f"LANES WHOSE ONLY WITNESS IS UNTRACKED: {len(untracked_only)} of {len(lanes)}")
    for rel in untracked_only:
        print(f"  UNTRACKED-ONLY {rel}")
    return PASS if not unwitnessed else FAIL


# --------------------------------------------------------------------------- the plants

# THE PLANTS, AND THEY ARE TEXT EDITS ON THE ORACLE'S OWN SOURCE.
#
# THE EDIT IS NOT ON THE ORACLE'S OUTPUT BUT ON THE SOURCE THAT PRODUCES THE ROW:
# an oracle COMPUTES its rows, so `msg_argtypes_one=[id_,id_,c_ulong]` is not a
# string in the file -- the string is `row("msg_argtypes_one", kinds(_a1))`, and that
# is what the plant replaces.  A plant that edited the OUTPUT would be editing a
# value the oracle never wrote down, and it would be a plant of nothing.
#
# EACH EDIT MOVES ONE ROW.  `strip_enc` would move EIGHTEEN (it is a loop over
# eighteen fixtures), so the ga plant is on `xml_url`, which is one row.
PLANTS = [
    ("gates/objc-oracle.py", "runtime/support/objc.bend",
     'row("msg_argc_one", _c1)',
     'row("msg_argc_one", "MUTATED")'),
    ("gates/ga-oracle.py", "renderer/amd/generate.bend",
     'row(f"strip_enc {s}", G._strip_enc(s))',
     'row(f"strip_enc {s}", "MUTATED" if s == "ENC_VOP1" else G._strip_enc(s))'),
    ("gates/renderer_init-oracle.py", "renderer/__init__.bend",
     '"is_alu ADD": lambda: str(Ops.ADD in GroupOp.ALU),',
     '"is_alu ADD": lambda: str(Ops.SINK in GroupOp.ALU),'),
]


def _comment_only(text: str, old: str) -> str:
    """the CONTROL: a COMMENT-ONLY edit, on a line of its own, at the TARGET's OWN
    INDENTATION.

    Two shapes of "comment-only edit" do NOT move nothing, and both were MEASURED on
    the first run of this plant.  Appending a comment to the target line comments
    out the SECOND statement on that line -- the objc oracle writes
    `row("msg_argtypes_one", kinds(_a1)); row("msg_argc_one", _c1)` on ONE line, and
    the appended comment DELETED the second row, which is a DELETION and not a
    comment.  And inserting the comment at column 0 breaks the INDENTATION of a
    target inside a loop -- the ga oracle's target is the body of a `for`, and the
    control died with an IndentationError, which is a RED for a reason that has
    nothing to do with the lane.
    """
    for line in text.splitlines(keepends=True):
        if old in line:
            indent = line[:len(line) - len(line.lstrip())]
            return text.replace(line, f"{indent}# a comment-only edit\n{line}", 1)
    return text


def plants() -> int:
    """THE PLANT, AND IT MUST BE A TEXT EDIT.

    A copy of the ORACLE with ONE row's value changed must make the lane go RED, and
    a copy with a COMMENT-ONLY edit must move nothing.  Both are TEXT EDITS on a COPY
    -- never `git show HEAD:`, because a plant that reads HEAD plants nothing the
    moment HEAD carries the defect's fix, and one unit's arm did exactly that and
    scored green under `--falsify`.

    THE COPY IS BESIDE THE ORIGINAL, because the original derives the tree it reads
    from its OWN directory (`Path(__file__).resolve().parents[1]`), so a copy
    anywhere else would read a tree that is not there -- and the ORIGINAL is never
    touched, because a file others are executing is a path others hold.
    """
    bad = []
    for oracle_rel, lane_rel, old, new in PLANTS:
        oracle = ROOT / oracle_rel
        text = oracle.read_text()
        if old not in text:
            say(f"the plant's target {old!r} is not in {oracle_rel} -- the plant would "
                f"edit nothing and the CONTROL would pass VACUOUSLY")
            bad.append(f"target {oracle_rel}")
            continue
        copy = HERE / f".tmp-lanewitness-plant-{Path(oracle_rel).stem}.py"
        for label, edited, want_red in (("PLANT", text.replace(old, new, 1), True),
                                         ("CONTROL", _comment_only(text, old), False)):
            if edited == text:
                say(f"the {label} edit for {oracle_rel} changed NOTHING")
                bad.append(f"{label} {oracle_rel}")
                continue
            copy.write_text(edited)
            try:
                verdict, summary = lane_verdict(lane_rel, copy)
            finally:
                copy.unlink(missing_ok=True)
            red = verdict != PASS
            ok = red == want_red
            print(f"  {'PASS' if ok else 'FAIL'}  {label:7s} {oracle_rel}: "
                  f"{'RED' if red else 'GREEN'} (want {'RED' if want_red else 'GREEN'})"
                  f" -- {summary[:110]}")
            if not ok:
                bad.append(f"{label} {oracle_rel}")
    print(f"PLANTS: {'GREEN' if not bad else 'RED'} ({len(PLANTS) * 2 - len(bad)}"
          f"/{len(PLANTS) * 2} arms)")
    return PASS if not bad else FAIL


# --------------------------------------------------------------------------- the gate

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--plant", action="store_true")
    args = ap.parse_args()
    if args.census:
        return census()
    if args.plant:
        return plants()
    worst = PASS
    for rel, oracle_rel in LANES:
        verdict, summary = lane_verdict(rel, ROOT / oracle_rel)
        print(f"  {rel:38s} {verdict} -- {summary}")
        if verdict != PASS:
            worst = verdict
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
