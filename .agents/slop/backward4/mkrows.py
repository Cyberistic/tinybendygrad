"""THE TRANSCRIPTION -- the oracle's rows become the EXPECTATIONS.

IT IS A WITNESS, NOT A TRANSCRIPT.  **This file's only input is the ORACLE's output
file.**  It opens exactly one path, the one on the command line, and that path is the
oracle's.  It never reads the port's output, and no expectation in the file it writes
was typed by a human: every value is a substring of a byte the oracle printed.

THE NAME MAP IS ONE RULE AND IT HAS NO EXCEPTIONS: the oracle's rows are named
`oracle_<the port's row name>`, so STRIPPING THE `oracle_` PREFIX IS THE WHOLE MAP.
The prior art needed a rule plus one named exception (`.agents/slop/backward3/mkrows.py`);
this one does not, because the port's row names were chosen to make the prefixes line
up: `pm_*` for the 3-D fixture, `pm1_*` for the 1-D identity fixture and
`pm_argsort_*` for the argsort rows.

THE DENOMINATOR IS ASSERTED, NOT ASSUMED: exactly 36 rows are transcribed, and the
script says so out loud.
"""
import sys

ORACLE_PREFIX = "oracle_"
EXPECTED = 36


def port_name(oracle_name: str) -> str:
    """`oracle_<x>` -> `<x>`.  ONE RULE, NO EXCEPTIONS."""
    if not oracle_name.startswith(ORACLE_PREFIX):
        raise SystemExit("not an oracle row: %s" % oracle_name)
    return oracle_name[len(ORACLE_PREFIX):]


def read_rows(path: str) -> dict:
    rows = {}
    for line in open(path):
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        name, _, value = line.partition("=")
        rows[name] = value
    return rows


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    oracle = read_rows(src)
    gated = [n for n in oracle if n.startswith(ORACLE_PREFIX)]
    if len(gated) != EXPECTED:
        raise SystemExit("expected %d %s* rows, found %d: %s"
                         % (EXPECTED, ORACLE_PREFIX, len(gated), sorted(gated)))

    port = {}
    for name in gated:
        pname = port_name(name)
        if pname in port:
            raise SystemExit("two oracle rows map to the port row %s" % pname)
        port[pname] = oracle[name]

    with open(dst, "w") as fh:
        for name in sorted(port):
            fh.write("%s=%s\n" % (name, port[name]))
    print("transcribed %d oracle rows -> %d port rows in %s" % (len(gated), len(port), dst))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
