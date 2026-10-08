#!/usr/bin/env python3
"""Freeze the run's INPUTS into a directory a `differ.py run` can execute against, so the live
tree may keep moving.

    usage: .venv/bin/python checks/substrate-snapshot.py --build DEST [--out DIR]
           .venv/bin/python checks/substrate-snapshot.py --verify DEST
           .venv/bin/python checks/substrate-snapshot.py --declare
           .venv/bin/python checks/substrate-snapshot.py --plant

WHY THIS LIVES HERE, IN GIT, BESIDE THE GATE THAT ASKS IT. Measured 2026-10-08: from
`.agents/slop/quiesce/`, `git ls-tree -r HEAD -- .agents/slop/quiesce/` answered **0 paths** over 9
files on disk, so `checks/substrate-id.py` -- which loads this file BY PATH and asks it for the
population -- was a gate whose entire population was invisible to a `git archive HEAD` tree. It
hashed ZERO inputs and returned `PASS` over the sha256 of the empty string. `AGENTS.md` doctrine 1
calls this a hand list when it is a path outside the tree, and its "a gate's required input belongs
beside the gate in git" is why this file is here.

THE MOVE COST ONE THING AND NOT ANOTHER. `ROOT` went `parents[3]` -> `parents[1]` and two sibling
loaders in `.agents/slop/quiesce/` changed how they name this file. **The DIGEST DID NOT MOVE**,
because `inputs()` reads `tinybendygrad/` and `COPIES` and this file is in neither -- measured as an
A/B in one process over one tree, so a concurrent edit could not have been mistaken for the move.

WHY THIS EXISTS. `quiesce.py` measures the tree's longest quiet window; if that window is shorter
than the run (294 s, run34), the answer is NOT to wait -- a window that long does not exist -- it is
to run against a FROZEN COPY. This is that copy.

WHAT IS COPIED AND WHAT IS SYMLINKED, and the split is the whole design. The run RE-READS its
inputs throughout: every `gc()` spawns a fresh `.venv/bin/python graphcmp.py` (which re-reads
`graphcmp.py` and `graphcmp.bend` from disk), and every `emit` runs `bin/bend` on the port. So the
port, the two harness files, the oracles, the driver and `devpin.py` are COPIED -- a real byte copy,
never a hardlink, because a unit that edits a file in place would move the shared inode and a
hardlink would freeze nothing. The TOOLCHAIN (`.venv`, `references/`, `tinygrad/`) is SYMLINKED:
it is not what moves, it is what makes the copy runnable, and copying 264 MB to freeze 11 MB is not
a snapshot, it is a backup.

THE OUTPUT DIRECTORY IS RE-POINTED, and it is the one thing a run cannot resolve for itself.
`differ.py` computes `D = ROOT/"runs/graphcmp/D"` from its own `__file__`, so the snapshot's driver
writes to the SNAPSHOT's `runs/` -- which is why `--out DIR` symlinks `DEST/runs` at `DIR`
(default: the snapshot's own `runs/`). Point it at the live `runs/graphcmp/D` to keep the canonical
artifact location (`runs/` is gitignored output, not an input, so it is safe to share).
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SLOP = ROOT / ".agents" / "slop"

REFUSED = 3

#: The inputs `checks/differ.py run` reads, as the run's OWN declarations name them:
#:   differ.py:43  PY, GCMP = ... ".agents/slop/graphcmp.py"
#:   graphcmp.py:273-274  BEND_PROBE / BEND_DBG
#:   differ.py:541  "--bend-probe" ".agents/slop/graphcmp-empty.bend"
#:   differ.py:544,547,551  the three oracle scripts `capture()` runs
#: plus the port itself, which `graphcmp.bend` imports. A path here with no anchor is a hand-list
#: entry; `--declare` asserts the anchor line exists for each and names any that does not.
FILES: tuple[tuple[str, str, str], ...] = (
    ("differ.py:43", "checks/differ.py", "PY, GCMP = "),
    ("differ.py:541", "checks/differ.py", '"--bend-probe"'),
    ("differ.py:721", "checks/differ.py", "checks/devpin.py"),
    ("graphcmp.py:273", ".agents/slop/graphcmp.py", "BEND_PROBE = "),
    ("graphcmp.py:274", ".agents/slop/graphcmp.py", "BEND_DBG = "),
    ("differ.py:544", "checks/differ.py", "graphcmp-oracle.py"),
    ("differ.py:547", "checks/differ.py", "graphcmp-dbg-oracle.py"),
    ("differ.py:551", "checks/differ.py", "graphcmp-p13-ops.py"),
)
#: the runnable toolchain + the driver. Symlinked, not copied. `bin` is copied (it is 2 kB and it
#: resolves its own `../references`), the rest are the heavy immutable trees.
TOOLING = (".venv", "references", "tinygrad")
COPIES = ("bin", "checks/differ.py", "checks/devpin.py",
          ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
          ".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend",
          ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
          ".agents/slop/graphcmp-p13-ops.py")


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs() -> list[pathlib.Path]:
    """The run's DECLARED inputs, every one of them, whether or not it is on disk.

    The port is a DIRECTORY WALK (`rglob`), so it cannot miss a member; the declared copies are
    asked for, not filtered for. THE `else` IS THE WHOLE FIX: a declared path that is not on disk
    is still a member of the population, and `build()` writes it as the token `ABSENT` rather than
    leaving it out. A path with no `else` here was emitted NOWHERE -- not in the freeze, not in
    `MANIFEST.tsv`, not in `froze N` -- and `build()` printed `froze 148` over 150 declared inputs
    and exited 0, while its own docstring said they were "never silently dropped".

    The token is not new to this tree: `checks/differ.py:882` (`... if p.is_file() else "ABSENT"`)
    and `checks/substrate-id.py:131` (`h.update(b"ABSENT")`) already emit it for the same two
    members. The walk was the only one of the three not using it.
    """
    files = [p for p in (ROOT / "tinybendygrad").rglob("*")
             if p.is_file() and "__pycache__" not in p.parts]
    for c in COPIES:
        p = ROOT / c
        if p.is_dir():
            files += [q for q in p.rglob("*") if q.is_file()]
        else:
            files.append(p)  # declared and ABSENT is still a member; `build` writes it ABSENT
    return sorted(set(files))


def absent() -> list[str]:
    """The declared paths `inputs()` carries as members with no bytes -- named, because a
    population that shrank silently and one that shrank by a stated amount are different facts."""
    return [p.relative_to(ROOT).as_posix() for p in inputs() if not p.is_file()]


def build(dest: pathlib.Path, out: pathlib.Path | None) -> int:
    """Copy the moving inputs, symlink the toolchain, re-point `runs/`, write `MANIFEST.tsv`.

    The manifest is the EVIDENCE `--verify` re-reads, so the freeze is checkable without keeping
    the live tree in the same state. `--out` symlinks `dest/runs` at `out`; the default makes a real
    `dest/runs/graphcmp/D` so a snapshot run cannot collide with the live output directory.
    """
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    rows = []
    for src in inputs():
        rel = src.relative_to(ROOT)
        dst = dest / rel
        if src.is_file():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            rows.append(f"{sha(dst)}\t{rel.as_posix()}")
        else:
            # A DECLARED MEMBER WITH NO BYTES. There is nothing to copy, and the population still
            # contains it -- so the manifest says so, by name, and the count below is honest.
            # Without this the freeze reported 148 of 150 declared and exited 0.
            rows.append(f"ABSENT\t{rel.as_posix()}")
    for name in TOOLING:
        if (ROOT / name).exists():
            (dest / name).symlink_to(ROOT / name)
    if out is not None:
        (dest / "runs").symlink_to(pathlib.Path(out).resolve())
    else:
        (dest / "runs/graphcmp/D").mkdir(parents=True)
    (dest / "MANIFEST.tsv").write_text("\n".join(rows) + "\n")
    gone = [rel for blob, rel in (r.split("\t") for r in rows) if blob == "ABSENT"]
    print(f"froze {len(rows)} declared input(s) into {dest}"
          + (f"; {len(gone)} ABSENT and NAMED in MANIFEST.tsv" if gone else ""))
    for rel in gone:
        print(f"  ABSENT  {rel}  declared, not on disk, NOT COPIED")
    print(f"toolchain symlinked: {', '.join(n for n in TOOLING if (ROOT / n).exists())}")
    print(f"runs -> {out or dest / 'runs'}")
    return 0


def verify(dest: pathlib.Path) -> int:
    """Re-hash every frozen input against the manifest, and print the LIVE hash beside it. A row
    where `snap` and `live` differ is a write that did NOT reach the snapshot -- the property the
    whole file exists to give."""
    man = dest / "MANIFEST.tsv"
    if not man.exists():
        print(f"== REFUSED, NOT A VERDICT: no manifest at {man}", file=sys.stderr)
        return REFUSED
    bad = 0
    for ln in man.read_text().splitlines():
        want, rel = ln.split("\t")
        if want == "ABSENT":
            # The freeze recorded a declared member with no bytes. There is nothing to compare --
            # but "still absent" and "appeared since" are different facts and both must be said.
            print(f"  {'APPEARED ' if (ROOT / rel).exists() else 'ABSENT  '} {rel}"
                  f"  declared, no bytes frozen")
            bad += (ROOT / rel).exists()
            continue
        snap = sha(dest / rel) if (dest / rel).exists() else "MISSING"
        live = sha(ROOT / rel) if (ROOT / rel).exists() else "MISSING"
        if snap != want:
            bad += 1
            print(f"  MUTATED  {rel}  snap={snap[:12]} want={want[:12]}")
        elif snap != live:
            print(f"  frozen   {rel}  snap={snap[:12]} live={live[:12]}  <- live moved, snap did not")
    n = len(man.read_text().splitlines())
    if bad:
        print(f"VERIFY: FAILED -- {bad} of {n} frozen inputs changed")
        return 1
    changed = sum(1 for ln in man.read_text().splitlines()
                  for _w, rel in [ln.split("\t")]
                  if (ROOT / rel).exists() and sha(dest / rel) != sha(ROOT / rel))
    print(f"VERIFY: OK -- {n} of {n} frozen inputs unchanged; {changed} differ from the live tree")
    return 0


def declare() -> int:
    """Name every input, its anchor, and whether the anchored line exists. An anchor that is gone
    is a path the run no longer names, and a path named but absent is the other half."""
    missing = []
    print("run inputs (relative to repo root):")
    for anchor, f, tok in FILES:
        src = (ROOT / f).read_text() if (ROOT / f).exists() else ""
        ok = any(tok in ln for ln in src.splitlines())
        print(f"  {'ok  ' if ok else 'MISS'} {anchor:<20} {f}  anchor {tok!r}")
        if not ok:
            missing.append(f"{f}: no line contains {tok!r}")
    for c in COPIES:
        p = ROOT / c
        here = p.is_file() or p.is_dir()
        print(f"  {'ok  ' if here else 'MISS'} copy                 {c}"
              + ("" if here else "  ABSENT ON DISK"))
        if not here:
            missing.append(f"{c} ABSENT")
    print(f"port: DIRECTORY WALK over tinybendygrad/ = "
          f"{len([p for p in (ROOT / 'tinybendygrad').rglob('*') if p.is_file()])} files")
    for m in missing:
        print(f"  MISSING: {m}")
    return 1 if missing else 0


def plant() -> int:
    """Both halves on a FABRICATED tree: a snapshot must survive an edit to its source, and must
    CHANGE when the snapshot itself is edited. A freeze that cannot tell those apart is not a
    freeze. No real tree is touched."""
    with tempfile.TemporaryDirectory() as td:
        src, snap = pathlib.Path(td) / "live", pathlib.Path(td) / "snap"
        (src / "port").mkdir(parents=True)
        (src / "port/a.bend").write_text("one\n")
        (src / "harness.py").write_text("two\n")
        snap.mkdir()
        # same SHAPE as build(): copy, then manifest
        for rel in ("port/a.bend", "harness.py"):
            dst = snap / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src / rel, dst)
        want = {rel: sha(snap / rel) for rel in ("port/a.bend", "harness.py")}
        # HALF 1: edit the SOURCE; the snapshot must not move.
        (src / "port/a.bend").write_text("one\nEDITED LIVE\n")
        frozen = all(sha(snap / rel) == want[rel] for rel in want)
        print(f"  {'PASS' if frozen else 'FAIL'}  source edited -> snapshot unchanged")
        # HALF 2: edit the SNAPSHOT; the check MUST see it.
        (snap / "harness.py").write_text("two\nEDITED SNAP\n")
        moved = sha(snap / "harness.py") != want["harness.py"]
        print(f"  {'PASS' if moved else 'FAIL'}  snapshot edited -> change detected")
        ok = frozen and moved
        print(f"PLANT: {'OK' if ok else 'FAILED'}")
        return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", metavar="DEST", help="freeze the inputs into DEST")
    ap.add_argument("--out", metavar="DIR", help="symlink DEST/runs at DIR (default DEST/runs)")
    ap.add_argument("--verify", metavar="DEST", help="re-hash DEST against its manifest")
    ap.add_argument("--declare", action="store_true", help="print the input population")
    ap.add_argument("--plant", action="store_true")
    a = ap.parse_args()
    if a.plant:
        return plant()
    if a.declare:
        return declare()
    if a.verify:
        return verify(pathlib.Path(a.verify))
    if a.build:
        return build(pathlib.Path(a.build), pathlib.Path(a.out) if a.out else None)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
