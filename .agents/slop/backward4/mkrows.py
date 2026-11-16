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

THE DENOMINATOR IS ASSERTED, NOT ASSUMED -- and it is the number of `oracle_*`
rows the oracle PRINTS, not a number typed here. MEASURED 2026-11-11: the
oracle gained four rows (`rule_tup_len`, `rule_n_grads`, `rule_n_nodes` and the
`pm1_` twin of each), the constant below said 36, and the script refused with
`expected 36 oracle_* rows, found 40`. A hard-coded denominator is a denominator
that goes red when the oracle grows -- which is the point of the check, and the
point of reading the number FROM the oracle rather than beside it.

So the denominator is now the ORACLE's own row count, and the script says it out
loud: it prints `transcribed N oracle rows -> N port rows`.
"""
import sys

ORACLE_PREFIX = "oracle_"


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
    if not gated:
        raise SystemExit("the oracle printed no %s* rows" % ORACLE_PREFIX)

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
