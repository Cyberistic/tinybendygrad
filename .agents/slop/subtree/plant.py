"""PLANT BOTH DEPTHS IN A SCRATCH CLONE, AND SHOW THE PLANT MOVES A REAL COUNT.

`zerogate` found two of its own plants were GREEN-ONLY AND PROVED NOTHING (a pre-rename capture
already red; an invented row name that did not exist, so a no-op exiting 0), and `prune4` found
a clause VACUOUSLY TRUE FOR 3974 FILES. So every assertion below is written to FAIL LOUDLY:

  * a no-op cannot pass -- the two depths must move DIFFERENT numbers in DIFFERENT directions;
  * a vacuous predicate cannot pass -- each assertion is checked against a control that must
    read the OPPOSITE;
  * restore is verified by SHA-256 over the clone before and after, not by "it looked fine".

The clone is made by COPY (`git clone --no-hardlinks`) with `symlinks=True`, in a temp dir
OUTSIDE the repo, and the live tree is never written to.
"""
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "plant.rows"
rows = []


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tree_digest(root: Path, skip=(".git", "__pycache__")) -> str:
    """SHA-256 over (relpath, bytes) for every file outside `skip`, so 'restored' is a
    measurement. Order-independent: sorted by relpath."""
    h = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in skip)
        for fn in sorted(filenames):
            p = Path(dirpath) / fn
            rel = str(p.relative_to(root))
            h.update(rel.encode())
            h.update(b"\0")
            try:
                h.update(p.read_bytes())
            except OSError as e:
                h.update(f"ERR{e.errno}".encode())
            h.update(b"\0")
    return h.hexdigest()


def counts(clone: Path):
    """`(discover_entries, discover_libs, walk_total, only_walk, only_discover)` from the CLONE'S
    OWN `gates/gates-pop.py` -- the real function, loaded by path, not a re-implementation."""
    gp = by_path(clone / "gates" / "gates-pop.py", f"gp_{os.getpid()}_{abs(hash(str(clone)))}")
    entries, libs = gp.discover(clone)
    disc = {str(p.relative_to(clone)) for p in list(entries) + list(libs)}
    walk = set()
    for home in gp.HOMES:
        h = clone / home
        if not os.path.isdir(h):
            continue
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(gp.SUFFIXES):
                    walk.add(str((Path(dirpath) / fn).relative_to(clone)))
    return (len(entries), len(libs), len(walk),
            sorted(walk - disc), sorted(disc - walk), gp)


CLONE_SUBDIRS = ("checks", "gates")
CLONE_FILES = ("pyproject.toml",)


def make_clone(tmp: Path) -> Path:
    """A scratch clone by `git init` + COPY of the two gate homes.

    NOT `git clone`: this repo's `.git` is 246 MB (measured) and a full object copy is minutes
    of work for a measurement that needs two directories. The population is `HOMES` = checks,
    gates and nothing else, so the two homes plus `pyproject.toml` ARE the clone. `copytree` with
    `symlinks=True` so a symlink is copied as a symlink, which is the property under test.
    """
    clone = tmp / "clone"
    clone.mkdir()
    r = subprocess.run(["git", "init", "--quiet", str(clone)], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"git init failed rc={r.returncode} {r.stderr[:400]}")
    for rel in CLONE_SUBDIRS:
        shutil.copytree(ROOT / rel, clone / rel, symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__", "artifacts", "*.pyc"))
    for rel in CLONE_FILES:
        src = ROOT / rel
        if src.is_file():
            shutil.copy2(src, clone / rel)
        else:
            (clone / rel).touch()
    return clone


def plant(clone: Path, rel: str, body: str):
    p = clone / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)
    return p


SH_BODY = "#!/bin/sh\n# a planted gate: it dispatches on its own $0\necho \"planted gate $0\"\n"


def main():
    emit("PLANT", "field", "value")
    tmp = Path(tempfile.mkdtemp(prefix="subtree-plant-"))
    failures = []
    try:
        clone = make_clone(tmp)
        emit("PLANT", "clone", str(clone))
        emit("PLANT", "symlinks_true", "yes -- gates/ and checks/ copied with copy2, links kept")

        e0, l0, w0, ow0, od0, gp = counts(clone)
        digest0 = tree_digest(clone)
        emit("PLANT", "BASE_discover_entries", e0)
        emit("PLANT", "BASE_discover_libs", l0)
        emit("PLANT", "BASE_recursive_walk", w0)
        emit("PLANT", "BASE_only_walk", len(ow0))
        emit("PLANT", "BASE_only_discover", len(od0))
        for r in ow0:
            emit("PLANT", "BASE_only_walk_name", r)
        emit("PLANT", "BASE_files_digested", sum(1 for _ in clone.rglob("*") if _.is_file()))
        emit("PLANT", "BASE_sha256", digest0)

        # ---- THE EMPTY-POPULATION CONTROL, run FIRST so a later 0 is readable ----
        e_empty = gp.discover(tmp / "nothing-here")[0]
        emit("PLANT", "CTRL_empty_root_entries", len(e_empty))
        emit("PLANT", "CTRL_VERDICT_EMPTY",
             "the walk is capable of returning 0, so a later 0 is a MEASUREMENT"
             if len(e_empty) == 0 else "the walk cannot return 0 -- later zeros are vacuous")
        if len(e_empty) != 0:
            failures.append("CONTROL: an absent root did not give an empty population")

        # ================= DEPTH 0: top level =================
        p0 = plant(clone, "checks/zzz-plant-top.sh", SH_BODY)
        e1, l1, w1, ow1, od1, _ = counts(clone)
        emit("PLANT", "TOP_discover_entries", e1)
        emit("PLANT", "TOP_recursive_walk", w1)
        emit("PLANT", "TOP_d_entry", e1 - e0)
        emit("PLANT", "TOP_d_walk", w1 - w0)
        gp_t0 = by_path(clone / "gates" / "gates-pop.py", "gp_t0")
        rels0 = {str(q.relative_to(clone)) for q in gp_t0.discover(clone)[0]}
        emit("PLANT", "TOP_appears_in_discover_entries",
             "checks/zzz-plant-top.sh" in rels0)
        # the CONTROL: a top-level plant CANNOT be a no-op, because every projection must move.
        if not (e1 - e0 == 1 and w1 - w0 == 1 and "checks/zzz-plant-top.sh" in rels0):
            failures.append(f"TOP: expected +1/+1 and a named entry, got {e1 - e0}/{w1 - w0}")
        emit("PLANT", "TOP_VERDICT", "MOVES +1/+1" if (e1 - e0, w1 - w0) == (1, 1) else "NO-OP")
        p0.unlink()

        # ================= DEPTH 1: one directory deep =================
        p1 = plant(clone, "gates/oracles/zzz-plant-deep.sh", SH_BODY)
        e2, l2, w2, ow2, od2, gp2 = counts(clone)
        disc2 = {str(q.relative_to(clone)) for q in
                 list(gp2.discover(clone)[0]) + list(gp2.discover(clone)[1])}
        emit("PLANT", "DEEP_file_on_disk", p1.is_file())
        emit("PLANT", "DEEP_entry_reason", gp2.entry_reason(p1))
        emit("PLANT", "DEEP_is_an_entry_by_that_reason",
             gp2.entry_reason(p1) in ("py-main", "sh-dispatch", "sh-selfref"))
        emit("PLANT", "DEEP_discover_entries", e2)
        emit("PLANT", "DEEP_recursive_walk", w2)
        emit("PLANT", "DEEP_d_entry", e2 - e0)
        emit("PLANT", "DEEP_d_walk", w2 - w0)
        emit("PLANT", "DEEP_in_discover_set", "gates/oracles/zzz-plant-deep.sh" in disc2)
        emit("PLANT", "DEEP_in_only_walk", "gates/oracles/zzz-plant-deep.sh" in ow2)
        emit("PLANT", "DEEP_only_walk_now", len(ow2))
        emit("PLANT", "DEEP_only_discover_now", len(od2))
        # THE ASSERTION THAT MAKES THIS A PLANT AND NOT A NO-OP:
        #   the file EXISTS, it is classified as an ENTRY by the owner, and the recursive
        #   projection moves while the shared one does not.
        deep_moves = (w2 - w0 == 1) and (e2 - e0 == 0) and "gates/oracles/zzz-plant-deep.sh" in ow2
        emit("PLANT", "DEEP_VERDICT",
             "MOVES +1 walk / +0 discover -- the split onemodule measured, reproduced"
             if deep_moves else "NO-OP OR BOTH MOVED")
        if not deep_moves:
            failures.append("DEEP: the deep plant did not split the two projections")
        # VACUITY CONTROL: a predicate that is true for the whole tree proves nothing, so the
        # same assertion is run against a file that is NOT a gate and must NOT be counted.
        p2 = plant(clone, "gates/oracles/zzz-notagate.txt", "not a gate\n")
        e3, l3, w3, ow3, od3, gp3 = counts(clone)
        emit("PLANT", "CTRL_txt_discover_entries", e3)
        emit("PLANT", "CTRL_txt_recursive_walk", w3)
        emit("PLANT", "CTRL_d_entry", e3 - e2)
        emit("PLANT", "CTRL_d_walk", w3 - w2)
        emit("PLANT", "CTRL_VERDICT",
             "VACUITY EXCLUDED: a .txt one level deep moves NEITHER projection"
             if (e3 - e2 == 0 and w3 - w2 == 0) else "SUFFIX LEAK")
        if not (e3 - e2 == 0 and w3 - w2 == 0):
            failures.append("CONTROL: a .txt moved a count, so SUFFIXES is not the gate")
        p2.unlink()
        p1.unlink()

        # ================= RESTORE =================
        e4, l4, w4, ow4, od4, _ = counts(clone)
        digest4 = tree_digest(clone)
        emit("PLANT", "RESTORE_discover_entries", e4)
        emit("PLANT", "RESTORE_recursive_walk", w4)
        emit("PLANT", "RESTORE_sha256", digest4)
        emit("PLANT", "RESTORE_byte_identical", digest0 == digest4)
        emit("PLANT", "RESTORE_counts_match_base",
             (e4, l4, w4) == (e0, l0, w0))
        if digest0 != digest4:
            failures.append("RESTORE: digest differs")
        if (e4, l4, w4) != (e0, l0, w0):
            failures.append("RESTORE: counts differ")

        # ================= THE LIVE TREE, UNTOUCHED =================
        # The plants went to `tmp`, which is outside ROOT; assert that structurally rather than
        # by digesting 5.9M + 7.9M of the live tree twice.
        emit("PLANT", "LIVE_root", str(ROOT))
        emit("PLANT", "LIVE_clone_is_outside_root", not str(clone).startswith(str(ROOT)))
        emit("PLANT", "LIVE_plant_paths", str(p0.parent), str(p1.parent))
        for rel in ("checks/zzz-plant-top.sh", "gates/oracles/zzz-plant-deep.sh"):
            emit("PLANT", f"LIVE_absent_{rel}", not (ROOT / rel).exists())

        emit("PLANT", "FAILURES", failures or "none")
        emit("PLANT", "OVERALL", "ALL ASSERTIONS HELD" if not failures else "ASSERTION FAILED")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(rows))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()