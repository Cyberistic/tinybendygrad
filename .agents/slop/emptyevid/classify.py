"""Final classification of the 201 empty captures.

Every decision is a named rule with a named witness file. The point of the task:
a 0-byte capture is EVIDENCE only if its producer's exit code / verdict token is
recorded somewhere else. If it is, the empty file is REDUNDANT (the token is the
evidence). If the producer is known and nothing else records it, the empty file
is a HOLE -- it records nothing and cannot be re-read. If neither the producer
nor a token can be established, it is UNCLASSIFIED -- which is NOT REDUNDANT.
"""
import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# dir -> (class, token witness). `*` means every capture under the dir.
DIR_RULES = {
    "gatesrun": ("REDUNDANT", "gatesrun/CLASSES.tsv (rc,token cols)"),
    "canrun/census": ("REDUNDANT", "canrun/census/rc.tsv|rc-venv.tsv"),
    "rerun/D-before": ("REDUNDANT", "rerun/D-before/D0-run-summary.txt+D1-verdicts.txt"),
    "needsaudit": ("REDUNDANT", "needsaudit/REPORT.md (records live.err empty, rc=0)"),
    "substrate/artifacts/pop": ("REDUNDANT", "substrate/artifacts/pop/oracle.out"),
    "txtgen": ("REDUNDANT", "txtgen/REPORT.md"),
    "spine": ("REDUNDANT", "spine/SPINE.md (rc before/after + diff verdicts)"),
    "canrun": ("REDUNDANT", "canrun/REPORT.md rc/state table"),
}
# per-file rules: (relative path) -> (class, token witness)
FILE_RULES = {
    ".agents/slop/skipexit/BEFORE.stderr": ("REDUNDANT", "skipexit/BEFORE.rc"),
    ".agents/slop/skipexit/AFTER.stderr": ("REDUNDANT", "skipexit/AFTER.rc"),
    ".agents/slop/skipexit/AFTER2.stderr": ("REDUNDANT", "skipexit/AFTER2.rc"),
    ".agents/slop/abi4check/now-py3.stdout": ("REDUNDANT", "abi4check/now-py3.rc (RC=1)"),
    ".agents/slop/abi4check/now-venv.stdout": ("REDUNDANT", "abi4check/now-venv.rc (RC=1)"),
    ".agents/slop/fixures/after.err": ("REDUNDANT", "fixures/after.rc (GATE rc=0)"),
    ".agents/slop/agend/spec0.err": ("REDUNDANT", "agend/spec0.rows"),
    ".agents/slop/agend/spec1.err": ("REDUNDANT", "agend/spec1.rows"),
    ".agents/slop/agend/spec2.err": ("REDUNDANT", "agend/spec2.rows"),
    ".agents/slop/agend/spec3.err": ("REDUNDANT", "agend/spec3.rows"),
    ".agents/slop/censroot/before-census.out": ("REDUNDANT", "censroot/statuses.tsv before_rc=1"),
    ".agents/slop/censroot/after-census.err": ("REDUNDANT", "censroot/statuses.tsv after_rc=0"),
    ".agents/slop/censroot/before-hermetic.out": ("REDUNDANT", "censroot/statuses.tsv before_rc=1"),
    ".agents/slop/censroot/after-hermetic.out": ("REDUNDANT", "censroot/statuses.tsv after_rc=3 REFUSED"),
    ".agents/slop/censroot/full-corpus.err": ("UNCLASSIFIED", "-"),
    ".agents/slop/censroot/repro.err": ("UNCLASSIFIED", "-"),
    ".agents/slop/loopfix/loop-before.err": ("REDUNDANT", "loopfix/loop-before.rows"),
    ".agents/slop/loopfix/oracle-rng.err": ("REDUNDANT", "loopfix/oracle-rng.rows"),
    "oracles/sb-oracle.err": ("REDUNDANT", "oracles/sb-oracle.rows"),
    ".agents/slop/canrun/gate.out": ("HOLE", "producer checks/gate_norm.py:261; no token file"),
    "checks/check.out": ("HOLE", "producer .agents/slop/one.sh:47; no token file"),
}
# canrun files the REPORT names by unit
CANRUN_REDUNDANT = {
    "abi4.out", "dup-census.out", "dup-gate.out", "dup-gate2.out",
    "final-dup-gate.out", "norm_check.err", "final-norm_check.err", "herm.out",
}


def main():
    pop = json.loads((HERE / "population.json").read_text())
    prior = {}
    for line in (HERE.parent / "emptyblob" / "EMPTY.tsv").read_text().splitlines()[1:]:
        c = line.split("\t")
        if len(c) >= 4:
            prior[c[0]] = c[3]
    sent = [r["path"] for r in pop["empty"]
            if prior.get(r["path"]) == "SENTINEL/UNKNOWN"]

    rows = []
    for cap in sent:
        rel = cap[len(".agents/slop/"):] if cap.startswith(".agents/slop/") else cap
        name = cap.rsplit("/", 1)[-1]
        ext = name.rsplit(".", 1)[-1]
        cls, tok = None, "-"
        if cap in FILE_RULES:
            cls, tok = FILE_RULES[cap]
        else:
            # longest matching dir rule
            for d in sorted(DIR_RULES, key=len, reverse=True):
                if rel.startswith(d + "/"):
                    cls, tok = DIR_RULES[d]
                    break
        if cls is None and cap.startswith(".agents/slop/canrun/"):
            if name in CANRUN_REDUNDANT:
                cls, tok = "REDUNDANT", "canrun/REPORT.md rc/state table"
            else:
                cls, tok = "UNCLASSIFIED", "-"
        if cls is None and cap.startswith(".agents/slop/loopfix/"):
            cls, tok = "UNCLASSIFIED", "-"
        if cls is None and cap.startswith(".agents/slop/skipexit/artifacts/"):
            cls, tok = "UNCLASSIFIED", "-"
        if cls is None and (cap.startswith(".agents/slop/rerun/")
                            or cap.startswith(".agents/slop/arghalf/")
                            or cap.startswith(".agents/slop/bitcastrow/")
                            or cap.startswith("oracles/")):
            cls, tok = "UNCLASSIFIED", "-"
        if cls is None:
            cls, tok = "UNCLASSIFIED", "-"
        prod = name
        rows.append({"path": cap, "ext": ext, "producer": prod,
                     "token": tok, "class": cls})

    (HERE / "classified.json").write_text(json.dumps(rows, indent=2) + "\n")
    with (HERE / "CAPTURES.tsv").open("w") as f:
        f.write("path\text\tproducer_name\ttoken_recorded_elsewhere\tclass\n")
        for r in rows:
            f.write(f"{r['path']}\t{r['ext']}\t{r['producer']}\t{r['token']}\t{r['class']}\n")

    print("class counts:", dict(Counter(r["class"] for r in rows)))
    print("ext counts:  ", dict(Counter(r["ext"] for r in rows)))
    for c in ("HOLE", "UNCLASSIFIED"):
        print(f"\n{c}:")
        for r in rows:
            if r["class"] == c:
                print(f"  {r['path']}\t{r['token']}")


if __name__ == "__main__":
    main()
