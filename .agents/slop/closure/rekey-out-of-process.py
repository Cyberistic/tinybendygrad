#!/usr/bin/env python
"""RE-KEY THE 68 SLOTS, OUT OF PROCESS, ONE GRAPH PER PROCESS -- and PROVE the provenance first.

WHY OUT OF PROCESS, MEASURED.  The py lane's `P(i..)` slot comes from a module-level
`itertools.count` reaching the rows through `ParamArg(next(...))`, so a run that regenerates many
graphs in ONE PROCESS writes rows that depend on how many graphs preceded them: regenerating 68
slots in one process wrote 37 distinct `P(i..)` values where a per-process run gives 4.  So
`--fresh` over all 34 is not a regeneration, it is a corruption that exits 0.  This harness
therefore runs `census.py --only <graph> --fresh` in a FRESH PROCESS per graph, which is exactly
the condition the 68 cached rows were written under.

WHY VERIFY BEFORE RE-KEYING.  `write_key` records "these rows were produced by this generator".
Changing the key's SHAPE means the 68 existing rows have never been vouched for by the new key,
and writing the new key over them would assert a provenance nobody checked.  So: snapshot
`checks/rows/`, regenerate all 68 out of process, DIFF every slot against the snapshot, and only
if all 68 reproduce byte-for-byte write the new key.  Any slot that does not reproduce is
reported and the whole snapshot is restored -- the cache keeps its old keys and the run is a
REFUSAL, not a silent re-key.

`runs/graphcmp/D` is NEVER read for writing and never touched.  `checks/rows/` is the only tree
this writes, and it is backed up first.
"""
import filecmp, pathlib, shutil, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[3]
HERE = REPO / "checks"
ROWS = HERE / "rows"
BACKUP = pathlib.Path(__file__).resolve().parent / "rows-backup"
PY = str(REPO / ".venv/bin/python")

def slots() -> list[tuple[str, str]]:
    return [(ln.split("\t")[0], ln.split("\t")[1]) for ln in (ROWS / "keys.rows").read_text().splitlines()]

def main() -> int:
    names = sorted({g for g, _ in slots()})
    print(f"slots     {len(slots())} over {len(names)} graphs")
    if BACKUP.exists():
        shutil.rmtree(BACKUP)
    shutil.copytree(ROWS, BACKUP)
    print(f"backup    {BACKUP.relative_to(REPO)}  ({len(list(BACKUP.iterdir()))} files)\n")

    t0, log = time.time(), []
    for i, g in enumerate(names, 1):
        r = subprocess.run([PY, "checks/census.py", "--only", g, "--fresh"],
                           cwd=REPO, capture_output=True, text=True)
        log.append((g, r.returncode))
        print(f"  [{i:2}/{len(names)}] {g:<10} rc={r.returncode}  {time.time()-t0:5.1f}s"
              + ("" if r.returncode == 0 else f"  {r.stderr.strip().splitlines()[-1][:70] if r.stderr.strip() else ''}"),
              flush=True)

    bad = [g for g, rc in log if rc != 0]
    print(f"\nregenerate: {len(names) - len(bad)}/{len(names)} graphs exited 0")

    # `keys.rows` DIFFERING IS THE SUCCESS CONDITION -- re-keying it is the entire point -- so it
    # is counted apart from the row files, and lumping it in with a row that failed to reproduce
    # would have called this run a refusal for doing its job.  The first draft did exactly that
    # and reported "67/69" against a run where 68 of 68 rows were fine.
    allf = sorted(x.name for x in ROWS.iterdir())
    rowf = [f for f in allf if f != "keys.rows"]
    diff = [f for f in rowf if not filecmp.cmp(ROWS / f, BACKUP / f, shallow=False)]
    keydiff = filecmp.cmp(ROWS / "keys.rows", BACKUP / "keys.rows", shallow=False)
    print(f"rows       : {len(rowf) - len(diff)}/{len(rowf)} byte-identical to the snapshot")
    print(f"keys.rows  : {'UNCHANGED (the re-key did nothing -- FAIL)' if keydiff else 'CHANGED (expected; this is the re-key)'}")
    if diff:
        print(f"DIFFER     {diff}")

    if bad or diff or keydiff:
        shutil.rmtree(ROWS)
        shutil.copytree(BACKUP, ROWS)
        print("\nRESTORED   the snapshot; NOT re-keyed. This is a REFUSAL (3), not a verdict.")
        print(f"           graphs rc!=0 : {bad}")
        print(f"           rows differing: {diff}")
        print(f"           keys unchanged: {keydiff}")
        return 3

    print("\nPROVENANCE VERIFIED -- every one of the 68 rows reproduced byte-for-byte out of")
    print("process, one graph per process, so the new key is written over rows it has seen.")
    print(f"elapsed   {time.time() - t0:.0f}s")
    return 0

if __name__ == "__main__":
    sys.exit(main())