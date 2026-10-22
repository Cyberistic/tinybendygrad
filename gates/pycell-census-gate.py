#!/usr/bin/env python3
"""pycell-census-gate.py -- THE GATE OVER THE PORT's `py=` CELLS.

    .venv/bin/python gates/pycell-census-gate.py             # the gate
    .venv/bin/python gates/pycell-census-gate.py --refresh   # regenerate the baseline
    .venv/bin/python gates/pycell-census-gate.py --plant     # the plant alone, no bend
    .venv/bin/python gates/pycell-census-gate.py --plan      # the census, no bend, no verdict

THE FOUR LANES, AND WHY THERE ARE FOUR
---------------------------------------
  1  THE INSTRUMENT.  The classifier's own correctness, asserted by
     `gates/pycell-plant.py`'s arms -- every arm a TEXT EDIT of a fixture, and the 224
     KNOWN CASES on a PINNED CONTENT-ADDRESSED blob.  **THIS LANE RUNS ON EVERY
     INVOCATION**, because a census that cannot tell a transcription from a derived cell
     is a rule that cannot fail, and `AGENTS.md`'s DOCTRINE 2 is about exactly that.
  2  THE CENSUS.  Every `py=` cell in the port, classified by PROVENANCE, compared
     against the committed baseline.  **A FILE WHOSE TRANSCRIPTION COUNT RISES IS A
     FAILURE**: a new frozen value in the port is new rot.  A fall is PROGRESS and is
     reported, not charged.
  3  THE ROT.  The port RUN, and the two halves of every row compared.  **A ROW WHOSE
     `py=` HALF DISAGREES WITH THE PORT'S OWN `got=` HALF IS A ROT CELL**, and a rot cell
     the baseline does not carry is a FAILURE.  This lane needs `bin/bend`, and it takes
     the bend lock PER INVOCATION -- `checks/bendlock.sh` is the wrapper for a SINGLE
     compiler run, and a gate that holds the lock for its whole command is the 26-minute
     hold `checks/bendlock.sh`'s header records.
  4  THE BEND-ONLY ROWS.  A row whose `py=` half is a MARKER (`census.MARKERS`) has NO
     CPython counterpart: the port asserts that CPython has no answer for that row at
     all.  **COMPARING A MARKER WITH A VALUE IS A CATEGORY ERROR** -- the ROT lane's
     question ("does the port disagree with its own claim about CPython?") has NO
     ANSWER for a row whose claim is "there is nothing to compare".  MEASURED, and this
     is the lane's whole reason to exist: `renderer/nir_llvmir.bend`'s `f32show 240.0`
     carries the marker `BEND-ONLY`, because CPython's `str(240.0)` is `240.0` and the
     port's `F32.show(240.0)` is `240`, so the port's own spelling has no oracle --
     **AND THE PORT'S ORACLE GENERATES THE MARKER**, and `checks/nl-gate.py` requires
     the port's stdout to be BYTE-IDENTICAL to that oracle's, so the row cannot be
     re-spelled to make the two halves agree.

**A ROW THAT QUIETLY AGREED WITH ITSELF WOULD BE THE DISHONEST CHOICE**, so the marker
rows are COUNTED, REPORTED BY NAME, and held to the baseline: a marker row the baseline
does not carry is a FAILURE (a new row with no CPython counterpart is new rot of the
same kind as a new transcription), and a baseline marker row that is no longer a marker
is PROGRESS and is reported.

THE DEAD LANES, AND WHY THEY ARE A LANE
---------------------------------------
**A DEAD LANE IS NOT A RED LANE, AND NOTHING IN THE TREE SAYS SO.**  The corpus's `pI(`
lane is DEAD: its 34 graphs produce ZERO `pI(` rows, so the `ProgramInfo` FIELD LIST is
not exercised at all and the corpus cannot see the `vars` -> `params` rename.  A DEAD form
is a `py=` value the SOURCE declares and no row ever carries -- a comparison the port
claims to make and does not make.  **THIS GATE NAMES THEM**, and a form that was REACHED
in the baseline and is DEAD now is a FAILURE: the port stopped exercising a comparison.

EXIT STATUS: 0 PASS · 1 FAIL · 3 REFUSED (a precondition was absent) · 4 SKIP (the rows
could not be measured) · 5 DEAD (this gate emitted no row).
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
BENDLOCK = ROOT / "checks" / "bendlock.sh"
BOUNDED = ROOT / "checks" / "bounded.py"
BASELINE = HERE / "pycell-census.rows"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

sys.path.insert(0, str(HERE))
from gatekit import DEAD as GK_DEAD, FAIL as GK_FAIL, PASS as GK_PASS  # noqa: E402
from gatekit import REFUSED as GK_REFUSED, SKIP as GK_SKIP  # noqa: E402

PASS, FAIL, REFUSED, SKIP, DEAD = GK_PASS, GK_FAIL, GK_REFUSED, GK_SKIP, GK_DEAD


def load(name, path):
    """A MODULE, LOADED BY PATH, and never re-derived here."""
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def census_mod():
    return load("pycell_census_for_gate", HERE / "pycell-census.py")


def plant_mod():
    return load("pycell_plant_for_gate", HERE / "pycell-plant.py")


# ------------------------------------------------------------------ the bend lane

def run_port(path, timeout=300):
    """`(stdout, token)` for ONE port program, under the bend lock and the watchdog.

    **THE LOCK IS TAKEN PER INVOCATION.**  `checks/bendlock.sh` holds it for the whole
    command it wraps, and a gate that ran twelve bends inside one wrapped command would
    hold it for the whole gate -- which is the 26-minute hold its own header records.
    """
    with tempfile.TemporaryDirectory() as td:
        out_f = Path(td) / "o"
        err_f = Path(td) / "e"
        cmd = [str(BENDLOCK), "--", str(PY), str(BOUNDED), "--seconds", str(timeout),
               "--mb", "2048", "--", str(BEND), path]
        try:
            with out_f.open("wb") as o, err_f.open("wb") as e:
                r = subprocess.run(cmd, stdout=o, stderr=e, cwd=str(ROOT), timeout=timeout * 3)
        except (OSError, subprocess.SubprocessError) as exc:
            return "", f"NO-RUNNER({type(exc).__name__})"
        err = err_f.read_text(errors="replace")
        tok = re.search(r"\[bounded\] (\S+)", err)
        token = tok.group(1) if tok else "NO-RECORD"
        return out_f.read_text(errors="replace"), f"{token}:rc={r.returncode}"


# ------------------------------------------------------------------ the baseline

def read_baseline(path=BASELINE):
    """`{kind: {key: row}}` -- the committed record of what the port looked like."""
    out = {"ROT": {}, "COUNT": {}, "DEAD": {}, "BENDONLY": {}}
    if not path.is_file():
        return None
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = dict(p.split("=", 1) for p in line.split(" ") if "=" in p)
        kind = parts.get("kind")
        if kind in out:
            out[kind][parts.get("key", "")] = line
    return out


def write_baseline(rows, path=BASELINE):
    path.write_text("\n".join(rows) + "\n")


# ------------------------------------------------------------------ the gate

def gate(refresh=False, do_bend=True, plant_only=False):
    cm = census_mod()
    pm = plant_mod()
    if cm is None:
        print("== REFUSED, NOT A VERDICT: gates/pycell-census.py is absent -- the classifier is "
              "LOADED BY PATH, not re-derived here", file=sys.stderr)
        return REFUSED
    if pm is None:
        print("== REFUSED, NOT A VERDICT: gates/pycell-plant.py is absent", file=sys.stderr)
        return REFUSED
    port = str(ROOT / "tinybendygrad")
    if not Path(port).is_dir():
        print("== REFUSED, NOT A VERDICT: the port root is absent", file=sys.stderr)
        return REFUSED

    # -- LANE 1: THE INSTRUMENT.  The plant's arms, every one a text edit.
    checks = pm.plant(cm, (HERE / "pycell-plant.bend").read_text())
    plant_bad = [c for c in checks if not c[1]]
    for (label, ok, detail) in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  instrument/{label:<40} -> {detail}")
    print(f"INSTRUMENT: {'GREEN' if not plant_bad else 'RED'} "
          f"({len(checks) - len(plant_bad)}/{len(checks)} arms)")
    if plant_only:
        return PASS if not plant_bad else FAIL

    # -- LANE 2: THE CENSUS.
    rows, per_file, files, port_defs = cm.census(port)
    tally = Counter(r["kind"] for r in rows)
    per = {}
    cells_by_file = {}
    for r in rows:
        t = per.setdefault(r["file"], Counter())
        t[r["kind"]] += 1
        cells_by_file.setdefault(r["file"], []).append(r)
    print(f"CENSUS    : {len(files)} `.bend` files (DISCOVERED), {len(rows)} cells: "
          f"TRANSCRIPTION {tally[cm.TRANSCRIPTION]}  DERIVED {tally[cm.DERIVED]}  "
          f"PARAM {tally[cm.PARAM]}")

    # -- LANE 3: THE ROT, the DEAD LANES and the BEND-ONLY LANE.  The port RUN.
    rot_rows = []
    row_counts = {}
    dead_forms = []
    bendonly_rows = []
    measured = 0
    if do_bend:
        if not BEND.is_file() or not BENDLOCK.is_file():
            print("ROT       : REFUSED -- `bin/bend` or `checks/bendlock.sh` is absent")
            return REFUSED
        for rel in sorted(per_file):
            if not per_file[rel]:
                continue
            src = os.path.join(port, rel)
            out, token = run_port(src)
            if not token.startswith("WITHIN-LIMITS"):
                print(f"ROT       : REFUSED -- {rel} ran under {token}, and a lane that did not "
                      f"run measured nothing")
                return REFUSED
            emitted = cm.parse_rows(out)
            measured += 1
            row_counts[rel] = len(emitted)
            for (name, got, want) in emitted:
                # LANE 4: A MARKER IS NOT A VALUE.  The row claims CPython has NO
                # answer here, so there is nothing to disagree with; it is COUNTED and
                # NAMED, and it is not a rot cell.
                if want in cm.MARKERS:
                    bendonly_rows.append(f"kind=BENDONLY key={rel}|{name[:80]} file={rel} "
                                         f"name={name[:80]} got={got[:120]} marker={want}")
                    continue
                if got != want:
                    rot_rows.append(f"kind=ROT key={rel}|{name[:80]} file={rel} "
                                    f"name={name[:80]} got={got[:120]} want={want[:120]}")
            # THE DEAD FORMS: a value the SOURCE declares and no row carries.
            seen = {w for (_n, _g, w) in emitted}
            for r in cells_by_file.get(rel, []):
                if r["kind"] != cm.TRANSCRIPTION or r["form"] != cm.LITERAL_STRING:
                    continue
                v = r["value"]
                if "\n" in v or "," in v:
                    continue          # a LIST site: its value is a list, not one row's value
                if v not in seen:
                    dead_forms.append(f"kind=DEAD key={rel}|{r['builder']}|{r['site']} "
                                      f"file={rel} builder={r['builder']} "
                                      f"site={r['site']} value={v[:100]}")
        print(f"ROT       : {measured} port program(s) run, {sum(row_counts.values())} rows, "
              f"{len(rot_rows)} row(s) whose `py=` half DISAGREES with the port's own "
              f"`got=` half")
        print(f"BEND-ONLY : {len(bendonly_rows)} row(s) whose `py=` half is a MARKER -- CPython "
              f"has NO counterpart for them, so there is nothing to compare and they are NOT rot "
              f"cells.  THEY ARE COUNTED AND NAMED, because a row that quietly agreed with "
              f"itself would be the dishonest choice")
        for b in bendonly_rows[:12]:
            print(f"            BENDONLY  {b}")
        print(f"DEAD LANES: {len(dead_forms)} `py=` value(s) the SOURCE declares and no row "
              f"carries -- A DEAD LANE IS NOT A RED LANE, AND NOTHING ELSE SAYS SO")
        for d in dead_forms[:12]:
            print(f"            DEAD  {d}")

    base = read_baseline()
    if base is None and not refresh:
        print("== REFUSED, NOT A VERDICT: gates/pycell-census.rows is absent -- the baseline is "
              "this gate's input and it is in git, next to it", file=sys.stderr)
        return REFUSED

    # THE BASELINE ROWS.
    count_rows = [f"kind=COUNT key={rel} file={rel} transcription={per[rel][cm.TRANSCRIPTION]} "
                  f"derived={per[rel][cm.DERIVED]}" for rel in sorted(per) if per.get(rel)]
    new_rows = (sorted(rot_rows) + sorted(count_rows) + sorted(dead_forms)
                + sorted(bendonly_rows))

    if refresh:
        header = (
            "# pycell-census.rows -- GENERATED by `gates/pycell-census-gate.py --refresh`,\n"
            "# which is its ONLY writer.  One TAB-free space-separated set of `key=value`\n"
            "# pairs per row, and a `key=` that is the row's IDENTITY:\n"
            "#\n"
            "#   kind=COUNT  the per-file census: how many `py=` cells are TRANSCRIPTIONS\n"
            "#              and how many are DERIVED.  **A COUNT THAT RISES IS NEW ROT.**\n"
            "#   kind=ROT    a row whose `py=` half DISAGREES with the port's own `got=`\n"
            "#              half -- a ROT CELL.  The key is `file|name`.\n"
            "#   kind=DEAD   a `py=` value the SOURCE declares and no row carries -- a DEAD\n"
            "#              LANE.  The key is `file|builder|site`.\n"
            "#   kind=BENDONLY a row whose `py=` half is a MARKER: CPython has NO\n"
            "#              counterpart for it, so there is NOTHING TO COMPARE and it is\n"
            "#              NOT a rot cell.  The key is `file|name`.\n"
            "#\n"
            "# A gate cannot read a sentence, so the prose is for the reader and the rows are\n"
            "# for the gate.\n")
        write_baseline([header.rstrip("\n")] + new_rows)
        print(f"REFRESHED : {BASELINE.name} written, {len(new_rows)} rows")
        return PASS

    # THE COMPARISON.  A rise in a file's transcription count is NEW ROT; a fall is
    # PROGRESS.  A rot row the baseline does not carry is NEW ROT.  A form that was
    # REACHED and is DEAD now is a REGRESSION.
    fail = []
    # LANE 4, ASSERTED AND NOT ONLY TRUE BY THE ORDER OF TWO LINES.  A MARKER is
    # not a VALUE: the ROT lane's question ("does the port disagree with its own
    # claim about CPython?") has NO ANSWER for a row whose claim is "there is
    # nothing to compare", so such a row goes to the BEND-ONLY lane and is
    # COUNTED and NAMED there.  The `continue` above makes that structurally
    # true, and THIS makes it a CHECK: if a future edit to the lane ever lets a
    # marker into the ROT set, the census says so instead of the reader having
    # to notice that `1 bend-only row(s)` and `1 rot row(s)` are the same row.
    # MEASURED, the row that made the lane: `renderer/nir_llvmir.bend`'s
    # `f32show 240.0` -- CPython's `str(240.0)` is `240.0`, the port's
    # `F32.show(240.0)` is `240`, and the port's own oracle GENERATES the
    # marker, so the row cannot be re-spelled to make the halves agree.
    marker_rot = [r for r in rot_rows
                  if dict(p.split("=", 1) for p in r.split(" ") if "=" in p
                          ).get("want") in cm.MARKERS]
    if marker_rot:
        fail.append(f"{len(marker_rot)} row(s) whose `py=` half is a MARKER are in the "
                    f"ROT lane: {marker_rot[:3]} -- a marker is not a value and "
                    f"comparing the two is a category error")
    if plant_bad:
        fail.append(f"the instrument's own plant is RED on {len(plant_bad)} arm(s): "
                    + ", ".join(c[0] for c in plant_bad))
    base_counts = base["COUNT"]
    for rel in sorted(per):
        if not per.get(rel):
            continue
        want = base_counts.get(rel)
        if want is None:
            fail.append(f"{rel} carries `py=` cells and the baseline has no count for it")
            continue
        d = dict(p.split("=", 1) for p in want.split(" ") if "=" in p)
        was, now = int(d["transcription"]), per[rel][cm.TRANSCRIPTION]
        if now > was:
            fail.append(f"{rel}: {now - was} NEW transcription cell(s) -- a new frozen value in "
                        f"the port is new rot (was {was}, now {now})")
        elif now < was:
            print(f"PROGRESS  : {rel} transcription cells {was} -> {now}")
    base_rot = {v.split(" ", 1)[1].split(" ", 1)[0] if False else
                dict(p.split("=", 1) for p in v.split(" ") if "=" in p).get("key", "")
                for v in base["ROT"].values()}
    for r in rot_rows:
        key = dict(p.split("=", 1) for p in r.split(" ") if "=" in p).get("key", "")
        if key not in base_rot:
            fail.append(f"NEW ROT row: {r}")
    base_dead = {dict(p.split("=", 1) for p in v.split(" ") if "=" in p).get("key", "")
                 for v in base["DEAD"].values()}
    for d in dead_forms:
        key = dict(p.split("=", 1) for p in d.split(" ") if "=" in p).get("key", "")
        if key not in base_dead:
            fail.append(f"NEW DEAD `py=` form: {d}")
    # LANE 4: A MARKER ROW THE BASELINE DOES NOT CARRY IS A FAILURE -- a new row with
    # no CPython counterpart is new rot of the same kind as a new transcription, and a
    # marker that is silently accepted is a filter rather than a lane.
    base_bend = {dict(p.split("=", 1) for p in v.split(" ") if "=" in p).get("key", "")
                 for v in base["BENDONLY"].values()}
    for b in bendonly_rows:
        key = dict(p.split("=", 1) for p in b.split(" ") if "=" in p).get("key", "")
        if key not in base_bend:
            fail.append(f"NEW BEND-ONLY row (a `py=` MARKER the baseline does not carry -- a row "
                        f"with NO CPython counterpart): {b}")
    for key in sorted(base_bend - {dict(p.split("=", 1) for p in b.split(" ") if "=" in p)
                                   .get("key", "") for b in bendonly_rows}):
        print(f"PROGRESS  : {key} is no longer a BEND-ONLY row -- it has a CPython counterpart "
              f"now")

    if not rows and not rot_rows:
        print("DEAD      : the census emitted no row")
        return DEAD
    if fail:
        print("\nPYCELL-CENSUS: FAIL")
        for f in fail:
            print(f"  FAIL  {f}")
        return FAIL
    print(f"\nPYCELL-CENSUS: PASS -- {tally[cm.TRANSCRIPTION]} transcription cell(s), "
          f"{len(rot_rows)} rot row(s), {len(dead_forms)} dead form(s), "
          f"{len(bendonly_rows)} bend-only row(s), "
          f"over {len(files)} discovered files.")
    return PASS


def main(argv=None):
    ap = argparse.ArgumentParser(prog="gates/pycell-census-gate.py",
                                 description=__doc__.split("\n")[0])
    ap.add_argument("--refresh", action="store_true",
                    help="regenerate the baseline; it is this gate's ONLY writer")
    ap.add_argument("--plant", action="store_true", help="the instrument's plant alone")
    ap.add_argument("--plan", action="store_true", help="the census, no bend, no verdict")
    a = ap.parse_args(argv)
    return gate(refresh=a.refresh, do_bend=not a.plan, plant_only=a.plant)


if __name__ == "__main__":
    raise SystemExit(main())
