"""Split the empty population by extension and by the prior SENTINEL class.

The task's "201" is the prior audit's SENTINEL/UNKNOWN class. This script does
not trust that list: it re-derives from git and reports both the extension
histogram of the whole 273 and the extension histogram of the 201-shaped subset.
"""
import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
EMP = HERE / "population.json"
PRIOR = HERE.parent / "emptyblob" / "EMPTY.tsv"

CAPTURE_EXTS = {"err", "out", "stdout", "stderr", "said", "log"}


def ext_of(path: str) -> str:
    name = path.rsplit("/", 1)[-1]
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def main():
    pop = json.loads(EMP.read_text())
    paths = [r["path"] for r in pop["empty"]]

    # prior class map (SENTINEL/UNKNOWN etc.), by exact path
    prior_cls = {}
    for line in PRIOR.read_text().splitlines()[1:]:
        cols = line.split("\t")
        if len(cols) >= 4:
            prior_cls[cols[0]] = cols[3]

    total_ext = Counter(ext_of(p) for p in paths)
    missing = [p for p in paths if p not in prior_cls]
    sentinel = [p for p in paths
                if prior_cls.get(p) == "SENTINEL/UNKNOWN"]
    sent_ext = Counter(ext_of(p) for p in sentinel)
    captured_any = [p for p in paths if ext_of(p) in CAPTURE_EXTS]
    cap_ext = Counter(ext_of(p) for p in captured_any)

    print("ext histogram, all 273 empty:")
    for e, n in total_ext.most_common():
        print(f"  .{e or '(none)'}: {n}")
    print(f"\nprior SENTINEL/UNKNOWN rows seen in current pop: {len(sentinel)}")
    print(f"paths in prior EMPTY.tsv but NOT in current pop: {len(missing)}")
    print("\next histogram, SENTINEL/UNKNOWN 201:")
    for e, n in sent_ext.most_common():
        print(f"  .{e or '(none)'}: {n}")
    print("\next histogram, ALL capture-ext empties:")
    for e, n in cap_ext.most_common():
        print(f"  .{e or '(none)'}: {n}")
    print(f"capture-ext total: {len(captured_any)}")

    # sanity: does SENTINEL == capture-ext within the 273?
    sset = set(sentinel)
    cset = set(captured_any)
    print(f"\nSENTINEL \\ capture-ext: {len(sset - cset)}")
    print(f"capture-ext \\ SENTINEL: {len(cset - sset)}")
    for p in sorted(cset - sset):
        print("   cap-not-sentinel:", p, prior_cls.get(p))


if __name__ == "__main__":
    main()
