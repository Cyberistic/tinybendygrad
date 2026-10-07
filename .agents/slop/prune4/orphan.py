#!/usr/bin/env python3
"""prune4 reachability, one git call per question.

`git cat-file -t` answering `blob` proves the object is in the STORE, not that a
REF reaches it. An object survives `git rm` of its path until gc, so "in the
store" is NOT "recoverable by a reader". This answers the question that matters,
in one `git ls-tree -r --all` pass instead of one process per path.
"""
import hashlib, os, subprocess, sys


def sh(*a, inp=None):
    return subprocess.run(a, input=inp, capture_output=True).stdout


def blob_id(path):
    b = open(path, "rb").read()
    return hashlib.sha1(f"blob {len(b)}\0".encode() + b).hexdigest(), len(b)


def main():
    # ONE pass: every blob reachable from every ref, with one path per blob
    raw = sh("git", "rev-list", "--objects", "--all")
    oid2path = {}
    for line in raw.decode(errors="replace").splitlines():
        parts = line.split(" ", 1)
        oid2path.setdefault(parts[0], parts[1] if len(parts) > 1 else None)
    ids = list(oid2path)
    out = sh("git", "cat-file", "--batch-check=%(objectname) %(objecttype)",
             inp=("\n".join(ids) + "\n").encode()).decode()
    live = {l.split()[0] for l in out.splitlines() if l.endswith(" blob")}

    for p in sys.argv[1:]:
        bid, size = blob_id(p)
        path = oid2path.get(bid)
        reach = bid in live
        print(f"{p}")
        print(f"   size={size} blob={bid[:12]}")
        print(f"   reachable from a REF : {reach}"
              + (f"  at path {path}" if reach and path else ""))
        print(f"   store-only (gc will drop it): {not reach}")
        # live twins, hashed in this process only (bounded to plausible sizes)
        twins = [p]
        for dp, _dn, fns in os.walk(os.path.dirname(p) + "/.."):
            for fn in fns:
                q = os.path.join(dp, fn)
                if q == p or os.path.islink(q):
                    continue
                try:
                    st = os.lstat(q)
                    if st.st_size != size:
                        continue
                    if blob_id(q)[0] == bid:
                        twins.append(q)
                except OSError:
                    pass
        print(f"   live byte-identical copies under .agents/slop: {len(twins)}")
        for t in twins[1:9]:
            print(f"      {t}")


if __name__ == "__main__":
    main()