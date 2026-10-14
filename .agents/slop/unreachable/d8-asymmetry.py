#!/usr/bin/env python3
"""d8-asymmetry.py -- THE CONTROL AND THE GATE, ON THE SAME BYTES, IN ONE WINDOW.

`modulerefuse` reported a VACUOUS GREEN reachable through
`checks/nl-gate-noguard.py --oracle-stdout <empty>`, and reported the same
finding on the CONTROL, never on the gate.  d7 measured that the SAME argument
against `checks/nl-gate.py` answers rc=1 and says "a lane printed NOTHING, so
nothing was compared. NOT a pass."

Two files written for one class, one with the guard and one without it, are the
only thing in this tree that can prove the guard is load-bearing.  So: restore
the subject ONCE, and drive BOTH gates with the same four captures in the same
process window.

  4 captures x 2 gates = 8 exit codes, all parsed out of the gates' own output,
  all under one restore, with the residue counted on the way out.

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


def live_captures(td):
    """The two REAL lanes, produced the way each gate produces them when it is
    NOT given a capture: the port through `./bin/bend <PORT>`, the oracle through
    the very oracle the guard names. If either fails, every zero below would be
    my fixture's, and this file says so instead of printing them."""
    cap = {}
    port = REPO / "tinybendygrad/renderer/nir_llvmir.bend"
    r = subprocess.run(["./bin/bend", str(port)], cwd=REPO,
                       capture_output=True, text=True, timeout=BUDGET)
    if r.returncode == 0 and r.stdout:
        p = Path(td) / "port.rows"
        p.write_text(r.stdout)
        cap["port"] = p
    ora = Path(td) / "oracle.rows"
    r = subprocess.run([str(PY), str(REPO / SUBJECT[0]), "rows"],
                       cwd=REPO, capture_output=True, text=True, timeout=BUDGET)
    if r.returncode == 0 and r.stdout:
        ora.write_text(r.stdout)
        cap["oracle"] = ora
    return cap


def run(gate, port, oracle):
    argv = [str(PY), str(REPO / gate)]
    if port is not None:
        argv += ["--port-stdout", str(port)]
    if oracle is not None:
        argv += ["--oracle-stdout", str(oracle)]
    try:
        r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=BUDGET)
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", ""
    return r.returncode, r.stdout + r.stderr


def verdict(txt):
    g = re.search(r"gated (\d+)", txt)
    a = re.search(r"\b(AGREE|BROKEN)\b", txt)
    v = re.search(r"VERDICT:.*", txt)
    return (f"gated={g.group(1)}" if g else "gated=<none>"), (a.group(1) if a else "-")


def main():
    print(f"read {time.strftime('%H:%M:%S')}. One restore, both gates, four captures.\n")
    fp = REPO / SUBJECT[0]
    if fp.exists():
        print(f"REFUSED to run: {SUBJECT[0]} is ALREADY on disk ({fp.stat().st_size} B). "
              f"Another unit owns it; this file does not touch what it did not create.")
        return
    data = blob(SUBJECT[1])
    if data is None:
        print(f"REFUSED: no blob at {SUBJECT[1]}")
        return
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_bytes(data)
    print(f"restore: {SUBJECT[0]} {len(data)} B <- {SUBJECT[1]} "
          f"byte-exact={fp.read_bytes() == data}\n")
    try:
        with tempfile.TemporaryDirectory() as td:
            cap = live_captures(td)
            empty = Path(td) / "empty.rows"
            empty.write_text("")
            print(f"captures: port={'%d B' % cap['port'].stat().st_size if cap['port'] else 'NONE'}"
                  f"  oracle={'%d B' % cap['oracle'].stat().st_size if cap['oracle'] else 'NONE'}")
            if not cap["port"] or not cap["oracle"]:
                print("A REAL LANE PRODUCED NOTHING. Every zero below would be my "
                      "fixture's, not the gate's. NO EXPERIMENT IS REPORTED.")
                return
            diff = Path(td) / "diff.rows"
            d = cap["oracle"].read_text().splitlines()
            p = cap["port"].read_text().splitlines()
            diff.write_text("\n".join(x for x in p if x not in d) + "\n")
            cases = [
                ("empty port, empty oracle  (nothing captured at all)", None, None),
                ("REAL port, EMPTY oracle  <- the vacuous green", cap["port"], empty),
                ("EMPTY port, REAL oracle", empty, cap["oracle"]),
                ("REAL port, REAL oracle  (the honest run)", cap["port"], cap["oracle"]),
                ("REAL port, DIFFERENT oracle (the gate must be able to say BROKEN)",
                 cap["port"], diff),
            ]
            print(f"\n{'case':56} {'gate':26} {'rc':>4}  {'denominator':16} verdict")
            print("-" * 118)
            rows = []
            for label, pth, oth in cases:
                for gate in GATES:
                    rc, txt = run(gate, pth, oth)
                    den, v = verdict(txt)
                    print(f"{label:56} {gate.split('/')[-1]:26} {str(rc):>4}  "
                          f"{den:16} {v}")
                    rows.append((gate, label, rc, den, v))
                    if "NOT a pass" in txt or "printed NOTHING" in txt:
                        for line in txt.splitlines():
                            if "NOT a pass" in line or "printed NOTHING" in line:
                                print(f"{'':78}   ^ {line.strip()[:60]}")
            p = REPO / ".agents/slop/unreachable/d8-asymmetry.rows"
            with p.open("w") as f:
                f.write("gate\tcase\trc\tdenominator\tverdict\n")
                for g, l, rc, den, v in rows:
                    f.write(f"{g}\t{l}\t{rc}\t{den}\t{v}\n")
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