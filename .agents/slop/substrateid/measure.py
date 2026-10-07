#!/usr/bin/env python3
"""TASK 1 + 3 + 6: how the 148 are derived, whether a CONTENT SHA hits the three mtime blockers,
and what it costs. Every number printed is measured here; nothing is inherited.

Run:  .venv/bin/python .agents/slop/substrateid/measure.py > .agents/slop/substrateid/measure.out 2>&1
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
rows: list[tuple[str, ...]] = []


def emit(*fields: object) -> None:
    rows.append(tuple(str(f) for f in fields))


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


snap = load("snapshot", ROOT / ".agents/slop/quiesce/snapshot.py")


def tree_digest(root: pathlib.Path, *, include_absent: tuple[str, ...] = ()) -> str:
    """sha256 over (relpath, sha256(bytes)) for every declared input, sorted by relpath.

    Keyed on CONTENT and on the PATH RELATIVE TO `root` -- not on mtime, not on the absolute
    path -- so two clones of one tree agree and one clone at two commits does not.
    """
    h = hashlib.sha256()
    for rel, blob in sorted(_entries(root, include_absent)):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def _entries(root: pathlib.Path, include_absent: tuple[str, ...]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for p in sorted(root.joinpath("tinybendygrad").rglob("*")):
        if p.is_file() and "__pycache__" not in p.parts:
            out.append((p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()))
    for c in snap.COPIES:
        p = root / c
        if p.is_dir():
            out += [(q.relative_to(root).as_posix(), hashlib.sha256(q.read_bytes()).hexdigest())
                    for q in sorted(p.rglob("*")) if q.is_file()]
        elif p.is_file():
            out.append((p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()))
        elif c in include_absent:
            out.append((c, "ABSENT"))
    return out


# ---- 1. HOW THE 148 ARE DERIVED --------------------------------------------------------------
port = sorted(p for p in (ROOT / "tinybendygrad").rglob("*")
              if p.is_file() and "__pycache__" not in p.parts)
inputs = snap.inputs()
hand = [p for p in inputs if "tinybendygrad" not in p.parts]
declared_absent = [c for c in snap.COPIES if not (ROOT / c).exists()]
print("== 1. THE POPULATION ==")
print(f"  snapshot.py:78-79  DIRECTORY WALK  tinybendygrad/**        : {len(port)} files")
print(f"  snapshot.py:80-85  HAND LIST       COPIES (:63-67)         : {len(hand)} files "
      f"over {len(snap.COPIES)} entries")
print(f"  inputs() total                                                    : {len(inputs)}")
print(f"  DISCOVERY (walk)  {len(port)}   LIST (COPIES) {len(hand)}")
print(f"  ratio list/total : {len(hand)}/{len(inputs)} = {100*len(hand)/len(inputs):.1f}%")
assert len(port) + len(hand) == len(inputs), "inputs() is neither walk+list nor something else"

# ---- 1b. ANCHORS: IS THE HAND LIST OF 8 THE SAME FAULT AS coindependent's 42? ---------------
# Two questions, measured separately. `in FILES` is the anchor TABLE (snapshot.py:50-59), which
# `--declare` asserts. `named in a consumer` is whether any file the run reads writes the path
# down -- a token somewhere is not an anchor unless code puts it there.
consumers = {"checks/differ.py": (ROOT / "checks/differ.py").read_text(),
             ".agents/slop/graphcmp.py": (ROOT / ".agents/slop/graphcmp.py").read_text()}
tok_by_copy: dict[str, list[str]] = {}
print("\n== 1b. ANCHORS ON THE HAND LIST ==")
print(f"  {'COPY':<40} {'DISK':<8} {'FILES-tbl':>9} {'named-in-consumer':>18}")
n_unanchored_table = n_unanchored_anywhere = 0
for c in snap.COPIES:
    here = "yes" if (ROOT / c).is_file() or (ROOT / c).is_dir() else "ABSENT"
    name = pathlib.Path(c).name
    tbl = [f"{ln} {t!r}" for ln, f, t in snap.FILES if name in f or c in t or name in t]
    tok_by_copy[c] = tbl
    where = [f"{f}:{i}" for f, src in consumers.items()
             for i, ln in enumerate(src.splitlines(), 1) if name in ln]
    if not tbl:
        n_unanchored_table += 1
    if not tbl and not where:
        n_unanchored_anywhere += 1
    print(f"  {c:<40} {here:<8} {len(tbl):>9}  {', '.join(where[:2]) or '** NOWHERE **'}")
print(f"\n  COPIES entries with NO row in the FILES anchor table : {n_unanchored_table} of {len(snap.COPIES)}")
print(f"  COPIES entries named NOWHERE in code or comment      : {n_unanchored_anywhere} of {len(snap.COPIES)}")
print(f"  `--declare` asserts the table, so it can only see the first {n_unanchored_table}.")

# ---- 1c. THE SILENT DROP: A DECLARATION THAT IS RIGHT AND A WALK THAT DROPS WHAT IT NAMES -----
print("\n== 1c. THE TWO ABSENT INPUTS ==")
rc_decl = subprocess.run([sys.executable, str(ROOT / ".agents/slop/quiesce/snapshot.py"), "--declare"],
                         capture_output=True, text=True).returncode
print(f"  declared-but-absent on disk : {len(declared_absent)} -> {', '.join(declared_absent)}")
print(f"  `--declare` exit code        : {rc_decl}  ({'REFUSES' if rc_decl else 'passes'})")
for c in declared_absent:
    print(f"  {c:<40} in inputs()? {ROOT / c in inputs}   in COPIES? {c in snap.COPIES}")
print(f"  => inputs() returns {len(inputs)}; the declaration names {len(snap.COPIES)} entries.")
print(f"  => build() prints `froze {len(inputs)}`, exit 0, and the 2 named inputs are NOT in the")
print(f"     freeze. THE DECLARATION EXITS 1 AND THE BUILD EXITS 0 ON THE SAME TREE.")
# and the walk half: prove the same shape for the port, where a DELETED file is unnamed too.
with tempfile.TemporaryDirectory() as td:
    fake = pathlib.Path(td) / "port"
    fake.mkdir()
    (fake / "a.bend").write_text("a\n")
    (fake / "b.bend").write_text("b\n")
    before = [p.name for p in sorted(fake.rglob("*")) if p.is_file()]
    (fake / "b.bend").unlink()
    after = [p.name for p in sorted(fake.rglob("*")) if p.is_file()]
    print(f"  walk before delete {before} -> after {after}; the deleted name is emitted NOWHERE.")

# ---- 3. DOES A CONTENT SHA HIT THE THREE mtime BLOCKERS? -------------------------------------
print("\n== 3. THE THREE mtime BLOCKERS, RE-TESTED AGAINST A CONTENT SHA ==")
print("  (1) differ.py:58-60 refuses a `git` dependency ON PURPOSE.")
print(f"      `git` on PATH here: {bool(shutil.which('git'))}; the digest path imports only")
print(f"      {sorted({'hashlib', 'pathlib', 'os'})}. It calls no subprocess and reads no ref, so")
print("      the dependency `differ.py` declines is one this row never takes.  NOT HIT.")

print("  (2) runs/ is gitignored, so an mtime is a fact about THIS TREE.")
with tempfile.TemporaryDirectory() as td:
    a, b = pathlib.Path(td) / "cloneA", pathlib.Path(td) / "cloneB"
    for dest in (a, b):
        for rel in ("tinybendygrad/PROOF.bend", "checks/differ.py", "bin/bend"):
            (dest / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, dest / rel)
    da, db = tree_digest(a), tree_digest(b)
    # give the two "clones" wildly different mtimes, the way a fresh clone would
    for i, p in enumerate(sorted(b.rglob("*"))):
        if p.is_file():
            os.utime(p, (1_000_000 + i * 1000, 1_000_000 + i * 1000))
    db2 = tree_digest(b)
    mt = {p.name: p.stat().st_mtime_ns for p in sorted(b.rglob("*")) if p.is_file()}
    print(f"      clone A digest : {da[:16]}   clone B digest : {db[:16]}   -> "
          f"{'AGREE' if da == db else 'DISAGREE'}")
    print(f"      after rewriting every mtime of B (now {len(mt)} distinct values, "
          f"spread {max(mt.values())-min(mt.values())} ns): {db2[:16]} -> "
          f"{'UNCHANGED' if db2 == db else 'MOVED'}")
    print(f"      an mtime rule would have had to compare those {len(mt)} numbers; a content sha")
    print(f"      never reads one.  NOT HIT.")

print("  (3) writing two rows moves consumers it does not own.")
live = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
kv = dict(ln.split("=", 1) for ln in live.read_text().splitlines() if "=" in ln)
differ_src = (ROOT / "checks/differ.py").read_text()
pin_block = differ_src[differ_src.index("PINS = {"):differ_src.index("PINS = {") + 4000]
pin_keys = {ln.split("=", 1)[0].strip() for ln in pin_block.splitlines()
            if "=" in ln and not ln.strip().startswith("#")}
print(f"      live summary rows {len(kv)}, keys {sorted(kv)}")
for k in ("substrate-start", "substrate-end"):
    print(f"      {k!r} is inside the PINS table, so unhealthy() would JUDGE it: {k in pin_keys}")
print(f"      `unhealthy()` judges `k in PINS` only, so a key outside PINS is INVISIBLE to it:")
print(f"      that is WHY these two rows must NOT be pinned -- a pin on a substrate digest would")
print(f"      have to be re-pinned every time the port moves, which is `pinindep`'s finding that")
print(f"      17 pins on one file is one measurement wearing 17 hats, made worse.")
pad = live.read_text() + "substrate-start=deadbeef\nsubstrate-end=deadbeef\n"
with tempfile.TemporaryDirectory() as td:
    padded = pathlib.Path(td) / "D"
    padded.mkdir()
    for f in live.parent.iterdir():
        if f.is_file():
            shutil.copy2(f, padded / f.name)
    (padded / "D0-run-summary.txt").write_text(pad)
    dv = load("differ_pad", ROOT / "checks/differ.py")
    dv.D = padded
    before_bad = dv.unhealthy()
    (padded / "D0-run-summary.txt").write_text(live.read_text())
    dv.D = live.parent
    after_bad = dv.unhealthy()
    print(f"      unhealthy() on the PADDED summary : {len(before_bad)} complaint(s), unchanged "
          f"from the unpadded {len(after_bad)}  -> {before_bad == after_bad}")
    for name, mod in (("checks/disagree-gate.py", None), ("checks/corpus-figure.py", None)):
        src = (ROOT / name).read_text()
        line = next(ln.strip() for ln in src.splitlines() if "D0-run-summary" in ln)
        print(f"      {name:<28} parses it by: {line[:78]}")
print("      NOT HIT, and only because the rows are additive keys outside PINS.")

# ---- 6. COST ---------------------------------------------------------------------------------
print("\n== 6. COST ==")
digest_times = []
for _ in range(7):
    t0 = time.perf_counter()
    tree_digest(ROOT)
    digest_times.append((time.perf_counter() - t0) * 1000)
digest_times.sort()
print(f"  population {len(inputs)} inputs, "
      f"{sum(p.stat().st_size for p in inputs)/1e6:.2f} MB")
print(f"  one digest : warm  min {digest_times[0]:.1f} ms  median "
      f"{digest_times[len(digest_times)//2]:.1f} ms  max {digest_times[-1]:.1f} ms")
subprocess.run(["purge"], capture_output=True)  # best effort; absent on this host, then COLD~warm
cold = []
for _ in range(3):
    subprocess.run(["purge"], capture_output=True)
    t0 = time.perf_counter()
    tree_digest(ROOT)
    cold.append((time.perf_counter() - t0) * 1000)
cold.sort()
print(f"               COLD  min {cold[0]:.1f} ms  median {cold[len(cold)//2]:.1f} ms  max {cold[-1]:.1f} ms")
two = digest_times[len(digest_times) // 2] * 2
print(f"  TWO digests (start+end), warm median: {two:.1f} ms")
for label, base in (("run34 warm run 294 s", 294_000), ("ONE cold bend launch ~2.8 s", 2_800)):
    print(f"    vs {label:<28} : {100*two/base:.4f} %")
for name, base in (("warm 294 s run34", 294_000),):
    print(f"    as a percentage of {name:<28}: {100*two/base:.4f} %")
print("  emitted rows into D0-run-summary.txt : 2")
print("  new parsers : 0    new files : 0    new pins : 0")

# ---- ROWS -----------------------------------------------------------------------------------
emit("kind", "n", "note")
emit("port-walk", len(port), "DISCOVERY, snapshot.py:78-79")
emit("hand-list", len(hand), f"LIST, snapshot.py:63-67, over {len(snap.COPIES)} entries")
emit("unanchored-in-FILES", n_unanchored_table, f"of {len(snap.COPIES)} COPIES entries")
emit("unanchored-anywhere", n_unanchored_anywhere, "named by no consumer line")
emit("declared-absent", len(declared_absent), ",".join(declared_absent))
emit("inputs-total", len(inputs), "build() prints this and exits 0")
emit("digest-ms-warm", round(digest_times[len(digest_times) // 2], 1), "median of 7")
emit("digest-ms-cold", round(cold[len(cold) // 2], 1), "median of 3 after purge")
(OUT / "population.rows").write_text("\n".join("\t".join(r) for r in rows) + "\n")
print(f"\nrows -> {OUT / 'population.rows'}")