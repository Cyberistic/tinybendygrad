#!/usr/bin/env python3
"""nir_render-plant.py -- what `gates/nir_render-gate.py` CAN see, and what it CANNOT.

    .venv/bin/python gates/nir_render-plant.py

FOUR ARMS AND ONE CONTROL, EACH ON A COPY, EACH NAMING THE ROWS IT MOVES.

  S   the port's `SQRT` ABSENCE put back          RED, 4 rows: `cfo nir`, `cfo lvp`,
      `cfo nak`, `cfo ir3`.  **THIS IS THE ARM THE DEFECT CAME FROM.**  MEASURED
      2026-10-22: the port's `cfo_names()` had no `SQRT` while upstream's
      `tinygrad/renderer/nir.py:23` has `Ops.SQRT: "fsqrt"`, and the port's `py=`
      half was a TRANSCRIPTION that AGREED with the wrong port, so the lane was GREEN
      on a wrong answer.  The `py=` half is now DERIVED, so the port's two halves
      always agree with each other -- and only the byte diff against live CPython can
      catch a wrong VALUE.  This arm is the proof that it does.
  F   the port's `f_ops()` LIST drops `SQRT`     RED, 2 rows: `aop f  table   ` and
      `aop rev f      `, and they differ BY LENGTH.  **THIS IS THE ARM THAT SHOWS
      THE DENOMINATOR NOW BITES.**  The recovered oracle's `F_OPS` was a HAND LIST of
      twelve names, and the port's `f_ops()` was a hand list of twelve names, and the
      two agreed -- so the `aop f` row was GREEN on a denominator that was wrong on
      BOTH sides.  The oracle's list is now read off upstream's live table, so the
      denominator is upstream's and a port that drops an op disagrees by LENGTH.
  V   a VALUE put wrong                           RED, 1 row, and the row's `got=`
      half DOES move.  **THIS IS THE ARM THAT PROVES THE LANE IS NOT A
      SELF-CONSISTENCY CHECK.**  A derived `py=` half cannot disagree with the port's
      own `got=` half, so a gate that only compared them would be blind to a wrong
      value; this arm is what shows that it is not one.
  C   CONTROL: a comment-only edit                 GREEN, 0 rows.  A control that moves
      something is not a control, and without it the other numbers do not mean
      anything.

EVERY ARM IS A TEXT EDIT.  **THE PLANT NEVER READS `git show HEAD:`.**  A plant that
reads HEAD plants nothing the moment HEAD carries the defect's fix: the text it
plants would be the FIXED text, and the arm would be green.  So each arm holds the
OLD text and writes it back, and the old text is the port's own text as it was before
`SQRT` was added -- which is the same text the port carried on 2026-10-06.

THE COPIES.  A mutation is an edit that must appear EXACTLY ONCE, and it is applied
to a COPY BESIDE the original -- Bend resolves `import ./x.bend` relative to the
FILE's own directory, so a copy anywhere else answers `no such file`.  The copies are
named `*.mut.bend`, which `.gitignore:36` already ignores, and they are DELETED in a
`finally`.  **AND THEY MATTER FOR MORE THAN TIDINESS:** `checks/differ.py`'s
`substrate_entries()` walks `tinybendygrad/` and hashes every file it finds, so a
`*.mut.bend` left behind MOVES THE CORPUS's FRESHNESS PIN.  That is measured in this
tree: a unit that dropped a mutation probe in the tree moved the digest and the
corpus reported it as somebody else's change.
"""
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from renderkit import split_rows  # noqa: E402

PY = ROOT / ".venv" / "bin" / "python"
GATE = HERE / "nir_render-gate.py"
PORT = ROOT / "tinybendygrad" / "renderer" / "nir.bend"
COPY = ROOT / "tinybendygrad" / "renderer" / "nir.mut.bend"
ART = HERE / "artifacts" / "nir_render"

# THE EDITS.  Each arm is a list of (old, new) TEXT EDITS, and each `old` must
# appear EXACTLY ONCE in the port's source.  `old` is the port's text BEFORE
# `SQRT` was added, so these are the arm that puts the defect back.
EDITS = {
    "S": ("the port's `SQRT` ABSENCE put back (its `cfo_names()` and `cfo.is`)",
          [('    case "SIN": True{}\n    case "SQRT": True{}\n',
            '    case "SIN": True{}\n'),
           ('"SHR","SIN","SQRT","TRUNC","WHERE","XOR"]',
            '"SHR","SIN","TRUNC","WHERE","XOR"]')]),
    "F": ("the port's `f_ops()` LIST drops `SQRT` -- the denominator moves",
          [('def f_ops() -> List<&2, String>: ["ADD","MUL","CMPLT","CMPNE","CMPEQ",'
            '"FDIV","RECIPROCAL","MAX","TRUNC","SIN","EXP2","LOG2","SQRT"]',
            'def f_ops() -> List<&2, String>: ["ADD","MUL","CMPLT","CMPNE","CMPEQ",'
            '"FDIV","RECIPROCAL","MAX","TRUNC","SIN","EXP2","LOG2"]')]),
    "V": ("a VALUE put wrong -- `SQRT`'s mesa symbol",
          [('    case O.OpsSQRT{}: "fsqrt"\n', '    case O.OpsSQRT{}: "fsqrtX"\n')]),
    "C": ("CONTROL: a comment-only edit",
          [("# THE GATE PRIMITIVES. Same shape as",
            "# THE GATE PRIMITIVES. Same shape as  # PLANT-CONTROL")]),
}

# WHAT EACH ARM MUST MOVE, AND WHICH HALF.  A row that moved is counted from the
# DIFF of two artefacts, so an arm that moved nothing is a coverage gap rather than
# a pass.
EXPECT = {
    "S": (4, "cfo nir, cfo lvp, cfo nak, cfo ir3", "both"),
    "F": (2, "aop f  table   , aop rev f      ", "both"),
    "V": (2, "aop f  table   , aop rev f      ", "got"),
    "C": (0, "none", "none"),
}


def refuse(why):
    print(f"== REFUSED, NOT A VERDICT: nir_render-plant: {why}", file=sys.stderr)
    raise SystemExit(3)


def run_gate(port=None):
    argv = [str(PY), str(GATE)]
    if port is not None:
        argv += ["--port", str(port)]
    return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))


def lane():
    p = ART / "bd.out"
    if not p.exists():
        return None
    return dict(split_rows(p.read_text()))


def halves(row):
    """(the `got=` half, the `py=` half) of a row's text."""
    body = row.split("]   py=[", 1)
    return (body[0].split(" = [", 1)[1] if " = [" in body[0] else body[0],
            body[1].rstrip("]") if len(body) > 1 else "")


def main():
    r = run_gate()
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        refuse(f"the gate is RED at rest (rc={r.returncode}); a plant measures a green gate")
    base = lane()
    if not base:
        refuse("the gate wrote no port lane")
    print("nir_render-plant.py: the gate is GREEN at rest\n")

    src = PORT.read_text()
    results = []
    try:
        for arm, (what, edits) in EDITS.items():
            out = src
            for (old, new) in edits:
                n = out.count(old)
                if n != 1:
                    refuse(f"{arm}: the edit must appear EXACTLY ONCE; it appears {n}")
                out = out.replace(old, new)
            COPY.write_text(out)
            g = run_gate(COPY)
            after = lane()
            if after is None:
                refuse(f"{arm}: the gate wrote no port lane")
            moved = [n for n, t in after.items() if base.get(n) != t]
            gone = [n for n in base if n not in after]
            got_moved = [n for n in moved if halves(base[n])[0] != halves(after[n])[0]]
            py_moved = [n for n in moved if halves(base[n])[1] != halves(after[n])[1]]
            results.append((arm, what, g.returncode, moved, gone, got_moved, py_moved))
            print(f"  {arm}: gate rc={g.returncode}, {len(moved)} rows moved "
                  f"({', '.join(n.strip() for n in moved) or 'none'}), "
                  f"{len(got_moved)} had their `got=` half moved, "
                  f"{len(py_moved)} had their `py=` half moved")
            print(f"      {what}")
    finally:
        COPY.unlink(missing_ok=True)

    bad = []
    for (arm, what, rc, moved, gone, got_moved, py_moved) in results:
        want, _names, which = EXPECT[arm]
        if arm == "C":
            if rc != 0 or moved or gone:
                bad.append(f"{arm}: the CONTROL moved something (rc={rc}, {len(moved)} rows)")
            continue
        if rc == 0:
            bad.append(f"{arm}: the gate stayed GREEN")
        if len(moved) != want:
            bad.append(f"{arm}: {len(moved)} rows moved, expected {want}")
        if gone:
            bad.append(f"{arm}: {len(gone)} rows disappeared")
        if which == "got" and not got_moved:
            bad.append(f"{arm}: the `got=` half did not move -- the arm is not putting "
                       f"the VALUE wrong")
        if which == "both" and not (got_moved and py_moved):
            bad.append(f"{arm}: the row's two halves did not move together -- the "
                       f"derived `py=` half should track the port's own value")
    if bad:
        for b in bad:
            print(f"  FAILED: {b}")
        return 1
    print("\n--plant: all arms ran; S put the port's `SQRT` absence back and the ORACLE "
          "lane went RED on 4 rows, F dropped the port's `f_ops()` entry and the "
          "`aop f`/`aop rev f` rows disagreed BY LENGTH, V put a VALUE wrong and the "
          "`got=` half moved, and the CONTROL moved nothing.  EVERY ARM IS A TEXT EDIT: "
          "no arm reads `git show HEAD:`.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
