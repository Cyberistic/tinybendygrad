#!/usr/bin/env python3
"""MEASURE the split in `quiesce/snapshot.py`'s input declaration, by asking its OWN code.

`COPIES` (snapshot.py:63-67) is a hand list and `FILES` (:50-59) is its anchor table. The
question this answers: how many hand-list entries have NO anchor, i.e. are BARE -- and is that
the same fault `zerogate` named in `coindependent`'s 42.
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("snap", ROOT / ".agents/slop/quiesce/snapshot.py")
snap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snap)

copies = [c for _, _, c in [] ] # placeholder removed below
copies = list(snap.COPIES)
anchored_files = {f for _, f, _ in snap.FILES}
# an anchor row (line, file, token) covers a COPY when the copy's basename appears in a FILE
# row's file field, OR when the token at that anchor is the copy's own literal assignment.
anchor_text = {}
for line, f, tok in snap.FILES:
    anchor_text[f"{line}|{tok}"] = (ROOT / f).read_text() if (ROOT / f).exists() else ""

print(f"port walk (tinybendygrad/**)  : {len([p for p in (ROOT/'tinybendygrad').rglob('*') if p.is_file()])} files")
exts = {}
for p in (ROOT / "tinybendygrad").rglob("*"):
    if p.is_file():
        exts[p.suffix or "(none)"] = exts.get(p.suffix or "(none)", 0) + 1
print(f"  by extension: {exts}")
print(f"COPIES hand list              : {len(copies)} entries")
print(f"FILES anchor table            : {len(snap.FILES)} rows -> {len(anchored_files)} distinct files")
print()
present = unanchored = 0
print(f"{'COPY':<44} {'ON DISK':<8} {'FILES':>5}  ANCHOR")
for c in copies:
    p = ROOT / c
    here = "yes" if (p.is_file() or p.is_dir()) else "ABSENT"
    # the anchor table's rows that MENTION this copy's basename
    hits = [f"{line} {tok!r}" for line, f, tok in snap.FILES if pathlib.Path(c).name in f]
    if here == "yes":
        present += 1
    if not hits:
        unanchored += 1
    print(f"{c:<44} {here:<8} {len(hits):>5}  {'; '.join(hits) or '** NO ANCHOR **'}")
print()
inputs = snap.inputs()
port = {p for p in inputs if "tinybendygrad" in p.parts}
copied = {p for p in inputs if "tinybendygrad" not in p.parts}
print(f"inputs() total                : {len(inputs)}")
print(f"  from the DIRECTORY WALK     : {len(port)}   (tinybendygrad/**)")
print(f"  from the HAND LIST          : {len(copied)}   files over {len(copies)} entries")
print(f"  declared-but-absent         : {len([c for c in copies if not (ROOT/c).exists()])}"
      f"  -> {', '.join(c for c in copies if not (ROOT/c).exists())}")
print()
print("HAND-LIST entries with NO entry in the FILES anchor table: ", unanchored, "of", len(copies))
print("   ", ", ".join(c for c in copies
                        if not [h for h in (f"{l} {t!r}" for l, f, t in snap.FILES
                                            if pathlib.Path(c).name in f)]))
symlinks = [p for p in inputs if p.is_symlink()]
print(f"symlinks inside inputs()      : {len(symlinks)}"
      + (f" -> {', '.join(str(p.relative_to(ROOT)) for p in symlinks)}" if symlinks else ""))
nbytes = sum(p.stat().st_size for p in inputs)
print(f"bytes hashed                  : {nbytes} ({nbytes/1e6:.2f} MB)")
sys.exit(0)