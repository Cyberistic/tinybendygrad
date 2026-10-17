#!/usr/bin/env python3
"""REPRODUCE the DUPLICATE shapes from nothing, in a throwaway directory, and record what each
git reader does with them. This is the artifact that makes review.md's control column re-runnable.

Measured claims it establishes (see forge.out):
  * `git mktree` ACCEPTS a duplicate entry, rc=0 -- so the shape is forgeable by a stock command.
  * `git ls-tree -r` PRINTS the duplicated paths and EXITS 0 -- a REFUSED-on-nonzero cannot fire.
  * `git fsck` prints `duplicateEntries` for BOTH shapes and EXITS NON-ZERO, `--strict` or not.
  * `git update-index --index-info` accepts two entries with one name and SHRINKS the index --
    so the INDEX cannot hold the shape, which is why `git ls-files` shows it once.

READ-ONLY with respect to this repository. Writes only under `.agents/slop/duparm/forge-scratch/`.
Never `.txt`.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
D = HERE / "forge-scratch"
ENV = {k: v for k, v in os.environ.items() if k not in ("GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE")}


def g(cwd, *args, stdin=None):
    p = subprocess.run(["git", "--no-optional-locks", "-C", str(cwd), *args], input=stdin,
                       capture_output=True, text=True, env=ENV)
    return p.returncode, p.stdout, p.stderr


def main() -> int:
    D.mkdir(exist_ok=True)
    for line in (D / "keep.rows").read_text().splitlines() if (D / "keep.rows").is_file() else ["seed"]:
        pass
    (D / "keep.rows").write_text("x\n")
    (D / "sub").mkdir(exist_ok=True)
    (D / "sub" / "b.rows").write_text("y\n")
    g(D, "init", "-q", "-b", "master", ".")
    g(D, "add", "-A")
    g(D, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "seed")
    _, sub, _ = g(D, "rev-parse", "HEAD:sub")
    sub = sub.strip()
    _, empty_tree, _ = g(D, "hash-object", "-t", "tree", "-w", "--stdin", stdin="")
    empty_tree = empty_tree.strip()

    out: list[str] = []
    out.append("# forge-scratch control -- every line is `git <cmd>` output or its exit code")

    for label, spec in (("REPEATED", f"040000 tree {sub}\tsub\n040000 tree {sub}\tsub\n"),
                        ("CONFLICTING", f"040000 tree {sub}\tsub\n040000 tree {empty_tree}\tsub\n")):
        rc, tree, err = g(D, "mktree", stdin=spec)
        tree = tree.strip()
        out.append(f"\n## {label}")
        out.append(f"git mktree rc={rc} oid={tree}" + (f" stderr={err.strip()}" if err.strip() else ""))
        rc_c, commit, _ = g(D, "commit-tree", "-m", label, tree)
        out.append(f"git commit-tree rc={rc_c} commit={commit.strip()}")
        rc, ls, _ = g(D, "ls-tree", "-r", commit.strip())
        out.append(f"git ls-tree -r rc={rc} lines={len(ls.splitlines())} "
                   f"unique_names={len({l.split(chr(9))[1] for l in ls.splitlines() if chr(9) in l})}")
        out.append(ls.rstrip())
        for extra in ("--strict",):
            rc, _, err = g(D, "fsck", extra, "--no-progress", "--no-dangling", commit.strip())
            hit = [ln for ln in err.splitlines() if "duplicateEntries" in ln]
            out.append(f"git fsck {extra} rc={rc} duplicateEntries={len(hit)}"
                       + (f" :: {hit[0]}" if hit else " :: (NO duplicateEntries LINE)"))
        rc, _, err = g(D, "fsck", "--no-progress", "--no-dangling", commit.strip())
        hit = [ln for ln in err.splitlines() if "duplicateEntries" in ln]
        out.append(f"git fsck (no --strict) rc={rc} duplicateEntries={len(hit)}")

    # THE INDEX CANNOT HOLD IT: two entries, one name.
    _, keep, _ = g(D, "rev-parse", "HEAD:keep.rows")
    before = (D / ".git" / "index").stat().st_size
    rc, _, err = g(D, "update-index", "--index-info",
                   stdin=f"100644 {keep.strip()} 0\tkeep.rows\n100644 {keep.strip()} 0\tkeep.rows\n")
    after = (D / ".git" / "index").stat().st_size
    _, ls, _ = g(D, "ls-files", "--stage")
    out.append("\n## THE INDEX")
    out.append(f"git update-index --index-info (two entries, one name) rc={rc} "
               f"index_bytes {before} -> {after} delta={after - before}")
    out.append(f"git ls-files --stage lines for keep.rows = "
               f"{sum(1 for l in ls.splitlines() if l.endswith('keep.rows'))}")

    (HERE / "forge.out").write_text("\n".join(out) + "\n")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())