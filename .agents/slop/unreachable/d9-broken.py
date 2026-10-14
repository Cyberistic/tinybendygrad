#!/usr/bin/env python3
"""d9-broken.py -- CAN THE CONTROL EVER SAY `BROKEN`?

d8 proved the asymmetry on EMPTY captures.  An empty capture is a weak witness:
a gate that answered `BROKEN` to nothing would also be a gate that answers
`BROKEN` to everything, and the asymmetry would mean nothing.  So the fifth case
d8 meant to run did not run -- it built the "different oracle" by removing the
lines the port does not have, and the two lanes are byte-identical, so the
"different" capture was EMPTY.

This file builds a capture that really differs: one row's VALUE is changed, and
the change is made in the ORACLE lane only.  Then both gates are driven, and the
question is whether `BROKEN` is reachable at all.

A gate whose only reachable verdict is `AGREE` is as useless as one whose only
reachable verdict is `REFUSED`, and it is not in anybody's census.

No .txt.
"""
import os, re, subprocess, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
GITENV = dict(os.environ, GIT_INDEX_FILE=".git/agent-index")
SUBJECT = (".agents/slop/nl/nl-oracle.py", "371cc64c9^:.agents/slop/nl/nl-oracle.py")
GATES = ("checks/nl-gate.py", "checks/nl-gate-noguard.py")
BUDGET = 120


def blob(ref):
    r = subprocess.run(["git", "cat-file", "blob", ref], cwd=REPO,
                       capture_output=True, env=GITENV, timeout=120)
    return r.stdout if r.returncode == 0 else None


def run(argv, timeout=BUDGET):
    try:
        r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", ""
    return r.returncode, r.stdout + r.stderr


def main():
    print(f"read {time.strftime('%H:%M:%S')}.\n")
    fp = REPO / SUBJECT[0]
    if fp.exists():
        print(f"REFUSED: {SUBJECT[0]} already on disk ({fp.stat().st_size} B); not mine.")
        return
    data = blob(SUBJECT[1])
    if data is None:
        print(f"REFUSED: no blob at {SUBJECT[1]}")
        return
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_bytes(data)
    try:
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            rc, p = run(["./bin/bend", "tinybendygrad/renderer/nir_llvmir.bend"])
            (td / "port.rows").write_text(p)
            rc, o = run([str(PY), str(REPO / SUBJECT[0]), "rows"])
            (td / "oracle.rows").write_text(o)
            pl, ol = p.splitlines(), o.splitlines()
            if not p or not o:
                print("A LANE PRODUCED NOTHING. No experiment is reported.")
                return
            print(f"lanes: port {len(p.splitlines())} lines, oracle {len(o.splitlines())} lines, "
                  f"identical={p == o}")

            # ONE row's value changed, ORACLE LANE ONLY -- and the row is chosen by
            # ASKING THE GATES' OWN SHARED READER which names it gates, because a
            # plant that lands on a discarded row moves nothing and a plant that
            # proves nothing is a plant worth nothing.
            sys_path = str(REPO / ".agents")
            pick = subprocess.run(
                [str(PY), "-c",
                 "import importlib.util,sys,pathlib;"
                 f"spec=importlib.util.spec_from_file_location('rb',r'{(REPO / '.agents/slop/rebase-gate.py')}');"
                 "m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);"
                 f"pr=m.rows(pathlib.Path({str(td / 'port.rows')!r}).read_text());"
                 f"orr=m.rows(pathlib.Path({str(td / 'oracle.rows')!r}).read_text());"
                 "shared=sorted(set(pr)&set(orr));"
                 "print(shared[0] if shared else '')"],
                cwd=REPO, capture_output=True, text=True, timeout=BUDGET)
            gated_name = pick.stdout.strip()
            gated_all = set()
            for line in subprocess.run(
                [str(PY), "-c",
                 "import importlib.util,pathlib;"
                 f"spec=importlib.util.spec_from_file_location('rb',r'{(REPO / '.agents/slop/rebase-gate.py')}');"
                 "m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);"
                 f"pr=m.rows(pathlib.Path({str(td / 'port.rows')!r}).read_text());"
                 f"orr=m.rows(pathlib.Path({str(td / 'oracle.rows')!r}).read_text());"
                 "print('\\n'.join(sorted(set(pr)&set(orr))))"],
                cwd=REPO, capture_output=True, text=True, timeout=BUDGET).stdout.split():
                gated_all.add(line)
            gated_name = sorted(gated_all)[0] if gated_all else ''
            print(f"the shared reader gates {len(gated_all)} name(s) in both lanes; "
                  f"first is {gated_name!r}")
            mutated = list(ol)
            # BROAD plant: corrupt the `py=` half of EVERY gated row, because a
            # narrow plant can land on a duplicate the reader overwrites and a
            # plant that moves nothing proves nothing about BROKEN.
            hits = [i for i, l in enumerate(mutated)
                    if l.split(" = ")[0].strip() in gated_all]
            if not hits:
                print("REFUSED: no gated rows located. No experiment is reported.")
                return
            for hit in hits:
                # THE COMPARED COLUMN IS `left` -- the value BEFORE the first `=`.
                # `rebase-gate.py:425` says `right` (the `py=` half) is DELIBERATELY
                # not compared, so a plant on `py=` moves nothing BY DESIGN. Planting
                # `py=` and calling the gate broken would be planting the wrong column.
                # Change the COMPARED VALUE, not the name: `rows()` keys on the
                # name, so renaming a row REMOVES a key instead of corrupting a
                # value, and that shrinks the shared set rather than disagreeing
                # (measured: 205 -> 205/155 by rename, verdict still AGREE).
                lhs = mutated[hit].split("=", 1)
                mutated[hit] = lhs[0] + "= [PLANTED]" + lhs[1]
            hit = hits[0]
            (td / "bad.rows").write_text("\n".join(mutated) + "\n")
            print(f"plant: oracle line {hit+1}, the COMPARED (left) value of {len(hits)} GATED rows, oracle lane only")
            print(f"       {ol[hit][:96]}")
            print(f"    -> {mutated[hit][:96]}")
            print(f"       the mutated capture differs from the port in "
                  f"{sum(1 for a, b in zip(pl, mutated) if a != b)} line(s), "
                  f"names unchanged={sum(1 for a, b in zip(pl, mutated) if a.split(chr(61))[0] == b.split(chr(61))[0])}"
)

            print(f"{'case':44} {'gate':26} {'rc':>4}  denominator / verdict")
            print("-" * 104)
            rows = []
            for label, portf, oracf in (
                ("honest: real port, real oracle", td / "port.rows", td / "oracle.rows"),
                ("PLANT:  real port, ONE oracle value changed", td / "port.rows", td / "bad.rows"),
            ):
                for gate in GATES:
                    rc, txt = run([str(PY), str(REPO / gate),
                                   "--port-stdout", str(portf),
                                   "--oracle-stdout", str(oracf)])
                    g = re.search(r"gated (\d+)", txt)
                    v = re.search(r"\b(AGREE|BROKEN)\b", txt)
                    d = re.search(r"disagree (\[.*?\])", txt)
                    print(f"{label:44} {gate.split('/')[-1]:26} {str(rc):>4}  "
                          f"gated={g.group(1) if g else '-'} {v.group(1) if v else '-'}")
                    if v and v.group(1) == "BROKEN":
                        print(f"{'':76}   {d.group(1)[:60] if d else ''}")
                    rows.append((gate, label, rc, g.group(1) if g else "-",
                                 v.group(1) if v else "-"))
            out = REPO / ".agents/slop/unreachable/d9-broken.rows"
            with out.open("w") as f:
                f.write("gate\tcase\trc\tdenominator\tverdict\n")
                for r in rows:
                    f.write("\t".join(map(str, r)) + "\n")
    finally:
        fp.unlink(missing_ok=True)
        d = fp.parent
        while d != REPO and REPO in d.parents:
            try:
                next(d.iterdir()); break
            except StopIteration:
                d.rmdir()
            except OSError:
                break
            d = d.parent
    print(f"\nRESIDUE: {1 if fp.exists() else 0} path(s) still on disk")


if __name__ == "__main__":
    main()