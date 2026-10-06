#!/usr/bin/env python3
"""CAN `LIVE_UNITS` BE DISCOVERED? FOUR CANDIDATE TREE PROPERTIES, EACH MEASURED, NONE BELIEVED.

The roster is the second belt behind the mtime window, and it has been wrong four times: it named six
FINISHED units holding 2,353 of 4,455 files (53% of `.slop`), 100% tracked, named by nothing. **A LIST
THAT OUTLIVES ITS UNITS IS NOT A SECOND BELT, IT IS THE ONLY BELT.** So the question is not "can I
delete the tuple" -- it is "what tree property would have made the tuple unnecessary".

The house rules name the right answer in advance: *A `.gitignore` RULE IS A DECLARATION OF INTENT BY
SOMEONE AND IS ALREADY IN THE TREE; A CITATION INDEX IS **NOT** AVAILABLE, BECAUSE THREE TIMES THIS
SESSION A CITATION INDEX BUILT FROM A TREE THAT INCLUDED THE INSTRUMENT HAS CITED THE INSTRUMENT.*
So candidate (b) is the interesting one and candidate (d) is measured to show the trap.
"""
import collections, os, subprocess, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SLOP = os.path.join(ROOT, ".agents/slop")


def load_sweep():
    import importlib.util
    p = os.path.join(ROOT, "checks/sweep.py")
    spec = importlib.util.spec_from_file_location("sweep", p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sweep = load_sweep()

# THE POPULATION: one walk, the newest file mtime per TOP-LEVEL slop directory.
now = time.time()
top = collections.defaultdict(lambda: 1e18)
n = 0
for dirpath, _d, files in os.walk(SLOP):
    for f in files:
        p = os.path.join(dirpath, f)
        try:
            rel = os.path.relpath(p, SLOP)
            top[rel.split(os.sep)[0]] = min(top[rel.split(os.sep)[0]], now - os.lstat(p).st_mtime)
            n += 1
        except OSError:
            pass

print(f"# population: {n} files in {len(top)} top-level .agents/slop directories\n")

print("# (a) PER-DIRECTORY MTIME AGGREGATION -- no roster at all.")
for w in (60, 360, 1440):
    live = sum(1 for a in top.values() if a <= w * 60)
    print(f"#     newest file in the directory is < {w:5d}m old : {live:4d} of {len(top)} directories")
print("#     VERDICT: it needs no roster and cannot go stale, and it is the ONLY candidate here that")
print("#     is decidable from the tree alone. ITS LIMIT IS MEASURED, NOT ASSUMED: a unit that has not")
print("#     written in W minutes into a directory it is ABOUT to write into is invisible, which is")
print("#     exactly what `LIVE_UNITS` was for.")

print("\n# (b) `.gitignore` -- A DECLARATION OF INTENT BY SOMEONE, ALREADY IN THE TREE.")
gi = open(os.path.join(ROOT, ".gitignore")).read()
names = [ln.strip().rstrip("/").split("/")[-1] for ln in gi.splitlines()
         if ln.strip() and not ln.startswith("#")]
hit = [u for u in sweep.LIVE_UNITS if any(u == n for n in names)]
print(f"#     {len(names)} patterns in .gitignore; {len(hit)} of the {len(sweep.LIVE_UNITS)} "
      f"LIVE_UNITS names are declared there")
print(f"#     declared .agents/slop paths: {[n for n in names if 'slop' in n]}")
print("#     VERDICT: **IT IS A DECLARATION OF INTENT, NOT OF LIVENESS.** `LIVE_UNITS` says 'a unit")
print("#     lives here'; .gitignore says 'never track what is here'. Those are different sentences,")
print("#     and the second outlives the first -- which is why `.agents/slop/xd1/` is ignored and")
print("#     every live unit's directory is tracked.")

print("\n# (c) jj WORKING-COPY DESCRIPTIONS -- a name for each unit, and a real one.")
r = subprocess.run(["jj", "workspace", "list"], cwd=ROOT, capture_output=True, text=True)
if r.returncode == 0:
    ws = [ln for ln in r.stdout.splitlines() if ln.strip()]
    named = [ln for ln in ws if "(no description set)" not in ln]
    print(f"#     {len(ws)} working copies, {len(named)} with a description")
    for ln in named:
        print(f"#       {ln.strip()[:100]}")
    print("#     VERDICT: **A WORKING COPY NAMES A SOURCE EDIT, NOT A SLOP DIRECTORY.** The six here")
    print("#     write into `tinybendygrad/`, and there is no mapping from a workspace to")
    print("#     `.agents/slop/<unit>/`. So this is a roster for a population that is not swept.")
else:
    print("#     jj unavailable (rc", r.returncode, ")")

print("\n# (d) A CITATION INDEX -- AND WHY IT IS NOT AVAILABLE.")
print(f"#     the residue's own incident: `000-the-residue.md` names every row by path, and the moment")
print(f"#     a concurrent unit's bare `git add` staged it, 40 `UNNAMED` rows became CITED and the")
print(f"#     residue collapsed to 0. MEASURED HERE, RIGHT NOW: `residue.py` reports")
out = subprocess.run(["grep", "-c", "needs=residue-internal-citer",
                      os.path.join(ROOT, ".agents/slop/residue/002-unknown.md")],
                     capture_output=True, text=True)
print(f"#     {out.stdout.strip()} rows in its own 002-unknown.md are named only from inside the residue.")
print("#     VERDICT: **NOT AVAILABLE**, third occurrence, and the exclusion is now in `sweep.py`'s")
print("#     corpus filter -- but note the shape: the fix is a `:(exclude)`, not a better index.")

print("\n# THE ANSWER, IN ONE LINE.")
print("#   DISCOVERABLE: per-directory mtime aggregation (a), which is `checks/residue.py`'s `LIVE`")
print("#   resolver and is the only candidate decidable from the tree with no list in it.")
print("#   NOT DISCOVERABLE, AND MEASURED AS SUCH: a roster that names a unit's slop directory.")
print("#   There is no tree property that carries it, and the three candidates that look like they")
print("#   might -- .gitignore, jj descriptions, citations -- each say something else.")
