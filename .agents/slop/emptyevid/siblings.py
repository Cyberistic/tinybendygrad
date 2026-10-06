"""For each capture directory, list sibling non-capture files (token candidates).

A token record is a committed file in the same tree that is NOT a capture
(.out/.err/.stdout/.stderr/.said) and is not a census of emptiness. For each
such sibling we record its size and whether it mentions rc/verdict/PASS/FAIL.
"""
import json
import subprocess
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAP = (".out", ".err", ".stdout", ".stderr", ".said")
CENSUS = ("emptyblob/", "residue/", "unknowns/", "stale71/", "_cite/",
          "oracles259/", "agend/", "emptyevid/", "gendirs/", "txt259/")
TOKENWORDS = ("rc=", "\trc", " rc ", "PASS", "FAIL", "SKIP", "REFUSED",
              "DEAD", "token", "GREEN", "RED", "verdict", "WITHIN-LIMITS",
              "KILLED", "TIMED-OUT")


def all_tracked():
    out = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return out.splitlines()


def main():
    pop = json.loads((HERE / "population.json").read_text())
    prior = {}
    for line in (HERE.parent / "emptyblob" / "EMPTY.tsv").read_text().splitlines()[1:]:
        c = line.split("\t")
        if len(c) >= 4:
            prior[c[0]] = c[3]
    sent = [r["path"] for r in pop["empty"]
            if prior.get(r["path"]) == "SENTINEL/UNKNOWN"]

    tracked = all_tracked()
    by_dir = defaultdict(list)
    for p in tracked:
        d = p.rsplit("/", 1)[0] if "/" in p else "."
        by_dir[d].append(p)

    result = {}
    for cap in sent:
        d = cap.rsplit("/", 1)[0]
        sibs = []
        for p in by_dir.get(d, []):
            if p == cap or p.endswith(CAP):
                continue
            if any(c in p for c in CENSUS):
                continue
            try:
                text = (ROOT / p).read_text(errors="replace")
            except OSError:
                text = ""
            hits = [w for w in TOKENWORDS if w in text]
            sibs.append({"path": p, "bytes": len(text), "tokenwords": hits})
        result[cap] = sibs

    (HERE / "siblings.json").write_text(json.dumps(result, indent=2) + "\n")
    # per-directory summary
    print(f"{'dirname':50s} {'caps':>4s} {'sibs':>4s} {'sibs-with-token':>15s}")
    seen = {}
    for cap, sibs in result.items():
        d = cap.rsplit("/", 1)[0]
        s = seen.setdefault(d, {"caps": 0, "sibs": set(), "tok": set()})
        s["caps"] += 1
        for x in sibs:
            s["sibs"].add(x["path"])
            if x["tokenwords"]:
                s["tok"].add(x["path"])
    for d, s in sorted(seen.items()):
        print(f"{d:50s} {s['caps']:4d} {len(s['sibs']):4d} {len(s['tok']):15d}")


if __name__ == "__main__":
    main()
