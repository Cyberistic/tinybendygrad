#!/usr/bin/env python3
"""PRINT ONE FIXTURE RECORD FROM THE TREE'S OWN FIXTURE FILE.

    .venv/bin/python .agents/slop/execfix/show.py <name>

THE FILE IS `gates/ops_python_exec-fixtures.rows`, READ IN PLACE. THE RECORD IS
`@ <name> <gx> <gy> <gz> <vals...>` FOLLOWED BY THE VERBATIM `PACKET.in` -- THE
UOP LINES AND THEN THE BUFFER LINES. THE UOP LINES ARE `ops_bend.encode`'s OWN
OUTPUT, SO THEY ARE THE PROGRAM THE EXECUTOR RUNS.
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"


def records():
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    return recs


def main():
    want = sys.argv[1]
    for name, argv, body in records():
        if name != want:
            continue
        print(f"@ {name} {' '.join(str(v) for v in argv)}")
        for ln in body:
            print(ln)
        return 0
    print(f"no fixture named {want}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
