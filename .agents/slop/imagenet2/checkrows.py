#!/usr/bin/env python3
"""RUN THE PROBE, RUN THE ORACLE, COMPARE BOTH AGAINST THE LITERAL EXPECTATIONS.

    .venv/bin/python .agents/slop/imagenet2/checkrows.py <fixture-root>

What it does, in order:

  1. reads `expected.rows` -- the HAND-WRITTEN literals (name <TAB> want);
  2. runs the bend probe once per case root and takes the line the row names;
  3. runs the CPython oracle on the same tree and takes ITS line, where the
     oracle has an answer at all (the oracle refuses with upstream's own
     `FileNotFoundError`, so it has no answer for the refusal rows);
  4. writes `rows.rows` -- name <TAB> got <TAB> want;
  5. prints one line per row: PASS or FAIL, and the oracle's answer beside it.

The exit status is 0 when every row agrees and 1 when any row does not, so the
file is a gate and not a report.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
BEND = REPO / "bin" / "bend"
PY = REPO / ".venv" / "bin" / "python"

root = pathlib.Path(sys.argv[1]).resolve()
expected = {}
order = []
for line in (HERE / "expected.rows").read_text().split("\n"):
    if not line.strip() or line.startswith("#"):
        continue
    name, want = line.split("\t", 1)
    order.append(name)
    expected[name] = want.replace("<ROOT>", str(root))

# name -> (case root, line index, does the oracle have an answer?)
CASES = {
    "train_files": (root, 0, True),
    "val_files": (root, 1, True),
    "categories": (root, 2, True),
    "mock_categories": (root / "mock", 2, True),
    "train_files_absent": (root / "mock", 0, False),
    "train_files_empty": (root / "empty", 0, False),
    "categories_absent": (root / "empty", 2, False),
    "root_absent": (root / "absent", 0, False),
}

probe_cache: dict[str, list[str]] = {}
oracle_cache: dict[str, list[str]] = {}


def probe(case_root: pathlib.Path) -> list[str]:
    key = str(case_root)
    if key not in probe_cache:
        p = subprocess.run([str(BEND), str(HERE / "probe.bend"), key],
                           capture_output=True, text=True, cwd=REPO)
        if p.returncode != 0:
            raise SystemExit(f"the probe failed on {key}: rc={p.returncode}\n{p.stderr}")
        probe_cache[key] = p.stdout.strip("\n").split("\n")
    return probe_cache[key]


def oracle(case_root: pathlib.Path) -> list[str]:
    key = str(case_root)
    if key not in oracle_cache:
        p = subprocess.run([str(PY), str(HERE / "oracle.py"), key],
                           capture_output=True, text=True)
        oracle_cache[key] = p.stdout.strip("\n").split("\n") if p.returncode == 0 else []
    return oracle_cache[key]


rows = []
bad = 0
for name in order:
    case_root, idx, has_oracle = CASES[name]
    got = probe(case_root)[idx]
    want = expected[name]
    ok = got == want
    if has_oracle:
        o = oracle(case_root)[idx]
        ok = ok and o == want
        oshow = o
    else:
        oshow = "(the oracle refuses with upstream's FileNotFoundError here)"
    rows.append((name, got, want))
    if not ok:
        bad += 1
    print(f"{'PASS' if ok else 'FAIL':<5} {name}")
    print(f"      got  = {got}")
    print(f"      want = {want}")
    print(f"      cpy  = {oshow}")

with (HERE / "rows.rows").open("w") as fh:
    fh.write("# name\tgot\twant\n")
    for name, got, want in rows:
        fh.write(f"{name}\t{got}\t{want}\n")

print(f"\n{len(rows) - bad} of {len(rows)} rows agree with the literal expectations")
print(f"ARTIFACT {HERE / 'rows.rows'}")
sys.exit(1 if bad else 0)
