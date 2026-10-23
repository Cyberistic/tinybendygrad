#!/usr/bin/env python3
"""THE FALSIFICATION, ON A COPY OF THE PORT TREE.

EVERY EDIT IS A TEXT EDIT ON A COPY. NEVER `git show HEAD:`. The live `tinybendygrad/`
is owned by other units and is not touched.

Four arms:
  CONTROL   a byte-identical copy of the snapshot        -> the verdict must NOT move
  FALS-A   the cited LINE is moved out of the file        -> must go RED
  FALS-B   the claim TOKEN exists in the file, not at the cited line -> must go RED
  FALS-C   the claim TOKEN does not exist in the file at all -> must become UNVERIFIABLE
"""
from __future__ import annotations
import csv, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SNAP = HERE / "snap"
WORK = HERE / "fals"
GATE = ROOT / "gates" / "pin-cite-gate.py"
TARGET = "tinybendygrad/extra/datasets/wikipedia_download.bend"
OLD = "# TODO(port): STOPPED AT `gdrive_download` (extra/datasets/wikipedia_download.py:10)."

ARMS = {
    "CONTROL": None,
    "FALS-A": ("# TODO(port): STOPPED AT `gdrive_download` "
               "(extra/datasets/wikipedia_download.py:9999)."),
    "FALS-B": ("# TODO(port): STOPPED AT `gdown` "
               "(extra/datasets/wikipedia_download.py:10)."),
    "FALS-C": ("# TODO(port): STOPPED AT `port_only_name_zzz9f3a2c` "
               "(extra/datasets/wikipedia_download.py:10)."),
}


def freeze() -> Path:
  """The SNAPSHOT of the port tree. THE PORT TREE IS OWNED BY OTHER UNITS AND MOVES, so
  every arm and the baseline are judged against ONE frozen copy -- and the copy is made
  HERE, at run time, so a reader never has to trust a stored tree."""
  if not (SNAP / "tinybendygrad").is_dir():
    shutil.copytree(ROOT / "tinybendygrad", SNAP / "tinybendygrad")
  return SNAP


def run_gate(tree: Path, rows: Path) -> dict[str, str]:
    p = subprocess.run([".venv/bin/python", str(GATE), "--tree", str(tree),
                        "--rows", str(rows), "--no-report"],
                       cwd=ROOT, capture_output=True, text=True)
    out = {}
    for line in p.stdout.splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k] = v
    out["_rc"] = str(p.returncode)
    out["_verdict"] = next((l for l in p.stdout.splitlines() if l.startswith("# pin-cite-gate:")), "")
    return out


def row_for(rows: Path) -> dict:
    with open(rows) as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            if r["rel"] == TARGET:
                return r
    return {}


def main() -> int:
    WORK.mkdir(exist_ok=True)
    snap = freeze()
    base = run_gate(snap, HERE / "FALS-base.rows")
    print("== THE BASELINE, the snapshot as frozen ==")
    for k in ("cite.total", "cite.checkable", "cite.at_pin", "cite.only_older_revision",
              "cite.at_no_revision", "cite.at_no_revision_dangling",
              "cite.ambient_relocated", "cite.unverifiable_no_claim_about_the_file"):
        print(f"   {k:48s} {base[k]}")
    print(f"   {base['_verdict']}   (rc={base['_rc']})")
    brow = row_for(HERE / "FALS-base.rows")
    print(f"   the target row: {brow.get('class')}  at_pin={brow.get('at_pin')}  "
          f"present_in_file={brow.get('present_in_file')!r}")
    print()
    for arm, new in ARMS.items():
        tree = WORK / arm
        if tree.exists():
            shutil.rmtree(tree)
        shutil.copytree(snap, tree)
        f = tree / TARGET
        text = f.read_text()
        assert OLD in text, f"{arm}: the target line is not what this script expects"
        if new is not None:
            f.write_text(text.replace(OLD, new, 1))
        rows = WORK / f"{arm}.rows"
        got = run_gate(tree, rows)
        r = row_for(rows)
        same = (tree / TARGET).read_bytes() == (snap / TARGET).read_bytes()
        print(f"== {arm} ==")
        print(f"   the edited file is byte-identical to the snapshot: {same}")
        for k in ("cite.at_pin", "cite.only_older_revision", "cite.at_no_revision",
                  "cite.at_no_revision_dangling", "cite.ambient_relocated",
                  "cite.unverifiable_no_claim_about_the_file"):
            mark = "  <-- MOVED" if got[k] != base[k] else ""
            print(f"   {k:48s} {got[k]:>6s}  (base {base[k]}){mark}")
        print(f"   {got['_verdict']}   (rc={got['_rc']})")
        print(f"   the target row: {r.get('class')}  at_pin={r.get('at_pin')}  "
              f"newest_rev={(r.get('newest_rev') or 'NONE')[:12]}  "
              f"present_in_file={r.get('present_in_file')!r}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
