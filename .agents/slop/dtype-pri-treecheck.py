#!/usr/bin/env python3
"""dtype-pri-treecheck.py -- ROW COUNTS for every tinybendygrad .bend with a `main`,
before and after the uop/fold.bend change.

The rule being enforced: a file this unit did not intend to change must print the SAME
output. It counts rows AND hashes the whole output, because a count cannot see a row
that changed VALUE.

*** NON-DESTRUCTIVE BY CONSTRUCTION. *** The first version of this script swapped the
pristine `uop/fold.bend` into the REAL tree, and a server restart killed it between the
write and the restore -- which silently reverted the whole unit's work. The "before"
tree is therefore a full COPY under `.agents/slop/tree-before/`, and the real tree is
never opened for writing. Copying the whole directory is required, not a convenience:
every import in this repo is RELATIVE, so a single-file copy elsewhere cannot resolve
`./ops.bend` (a $TMPDIR copy produced 22 phantom blind spots in another unit).

`LAWS/spec.bend` is not patched: it is byte-identical to `@-` already (measured), so
this unit's entire change to the tree is `uop/fold.bend`.
"""
import hashlib
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRATCH = os.path.join(REPO, ".agents", "slop", "tree-before")
COPY = os.path.join(SCRATCH, "tinybendygrad")


def mains(root):
    out = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
        for f in files:
            if not f.endswith(".bend") or "work" in f or "probe" in f:
                continue
            p = os.path.join(dirpath, f)
            try:
                if "\ndef main(" in open(p, errors="ignore").read():
                    out.append(os.path.relpath(p, root))
            except OSError:
                pass
    return sorted(out)


def measure(root, paths):
    res = {}
    for rel in paths:
        b = subprocess.run(["./bin/bend", os.path.join(root, rel)], cwd=REPO,
                           capture_output=True, text=True)
        txt = b.stdout + b.stderr
        res[rel] = (b.returncode, txt.count("\n"),
                    hashlib.sha256(txt.encode()).hexdigest()[:12])
    return res


def main():
    real = os.path.join(REPO, "tinybendygrad")
    pristine = subprocess.run(
        ["jj", "file", "show", "-r", "@-", "tinybendygrad/uop/fold.bend"],
        cwd=REPO, capture_output=True, text=True).stdout
    if not pristine.strip().startswith("#"):
        print("could not read the pristine fold.bend")
        return 1

    if os.path.exists(SCRATCH):
        shutil.rmtree(SCRATCH)
    shutil.copytree(real, COPY, symlinks=True)
    with open(os.path.join(COPY, "uop/fold.bend"), "w") as fh:
        fh.write(pristine)

    paths = mains(real)
    paths = [p for p in paths if os.path.exists(os.path.join(COPY, p))]
    print("files with a main, in both trees: %d" % len(paths), flush=True)

    before = measure(COPY, paths)
    print("before done", flush=True)
    after = measure(real, paths)
    print("after done", flush=True)

    moved = [(p, before[p], after[p]) for p in paths
             if before[p][1:] != after[p][1:]]
    for p, (rb, nb, hb), (ra, na, ha) in moved:
        print("MOVED  %-46s exit %d->%d  rows %d->%d  hash %s->%s"
              % (p, rb, ra, nb, na, hb, ha))
    print("\n%d of %d files moved. A file this unit did not edit appearing here means"
          "\nfold.bend's ANSWER changed under it." % (len(moved), len(paths)))
    print("(uop/fold.bend itself is expected: 288 rows before, 295 after.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())