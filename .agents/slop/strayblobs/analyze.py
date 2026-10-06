#!/usr/bin/env python3
"""analyze.py -- establish what the four ops.staged-blob-* files are.

READ-ONLY. Prints a `.tsv`-shaped table to stdout. No `.txt`.
"""
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
UOP = ROOT / "tinybendygrad" / "uop"
LIVE = UOP / "ops.bend"
PIDS = ["36145", "64022", "66397", "97648"]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def lines(p):
    return p.read_text(errors="replace").splitlines()


def diff(a, b):
    """difflib-free byte/line counts: how many lines differ and net direction."""
    la, lb = lines(a), lines(b)
    sa, sb = set(la), set(lb)
    return {
        "a_lines": len(la), "b_lines": len(lb),
        "only_a": len(sa - sb), "only_b": len(sb - sa),
        "bytes_a": a.stat().st_size, "bytes_b": b.stat().st_size,
    }


def main():
    files = [UOP / f"ops.staged-blob-{p}" for p in PIDS]
    print("# sha256 / size / lines")
    print("name\tbytes\tsha256\tlines")
    for p in [LIVE] + files:
        print("%s\t%d\t%s\t%d" % (p.name, p.stat().st_size, sha(p), len(lines(p))))

    print()
    print("# each blob vs live ops.bend")
    print("blob\tbytes_blob\tbytes_live\tdelta_bytes\tblob_lines\tlive_lines\tonly_blob\tonly_live\tidentical")
    for p in files:
        d = diff(p, LIVE)
        print("%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s" % (
            p.name, d["bytes_a"], d["bytes_b"], d["bytes_a"] - d["bytes_b"],
            d["a_lines"], d["b_lines"], d["only_a"], d["only_b"],
            sha(p) == sha(LIVE)))

    print()
    print("# blob vs blob (pairwise, identical?)")
    print("a\tb\tidentical\tbytes_a\tbytes_b")
    for i in range(len(files)):
        for j in range(i + 1, len(files)):
            print("%s\t%s\t%s\t%d\t%d" % (
                files[i].name, files[j].name, sha(files[i]) == sha(files[j]),
                files[i].stat().st_size, files[j].stat().st_size))

    print()
    print("# live readers: git grep by exact name (working tree, then HEAD)")
    for p in files:
        r = subprocess.run(["git", "grep", "-l", "-F", p.name],
                           cwd=ROOT, capture_output=True, text=True)
        hits = [x for x in r.stdout.splitlines() if x]
        print("%s\tworking=%d\t%s" % (p.name, len(hits), ",".join(hits) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
