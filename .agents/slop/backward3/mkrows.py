"""THE TRANSCRIPTION -- the oracle's rows become the EXPECTATIONS.

IT IS A WITNESS, NOT A TRANSCRIPT.  **This file's only input is the ORACLE's output
file.**  It opens exactly one path, the one on the command line, and that path is the
oracle's.  It never reads the port's output, and no expectation in the file it writes
was typed by a human: every value is a substring of a byte the oracle printed.

THE NAME MAP IS A RULE AND ONE NAMED EXCEPTION.  The oracle prints `oracle_dag_<x>`
and the port prints `walk_<x>`, so the prefix changes.  FOURTEEN of the FIFTEEN names
follow the rule `oracle_dag_` -> `walk_`; the ONE exception is `oracle_dag_walk` ->
`walk_sig`, because the port's row is named after WHAT IT IS (the walk's SIGNATURE)
and not after the oracle's spelling of it.  **A FIFTEEN-ENTRY HAND LIST WOULD BE A
SECOND COPY OF THE CORRESPONDENCE, and a second copy rots without anyone noticing.**

THE NAMED LOSS: the oracle's `osig` prints THREE fields -- the node count, the root's
op/arity, and the SORTED `srcs=` multiset -- and the port gates only the first two
(the port's own comment says so).  The cut is ` srcs=`, below.

THE COMPOSED ROW: the port prints `walk_row`, which is the walk's signature and the
gradient count in ONE string.  The oracle prints those as TWO rows and never prints
`walk_row` itself, so this script COMPOSES it from the two -- by composition, not by
typing.

THE DENOMINATOR IS ASSERTED, NOT ASSUMED: exactly FIFTEEN `oracle_dag_*` rows are
gated, and exactly SIXTEEN port rows are expected (the fifteen plus the composite).
"""
import sys

# THE NAME MAP: a rule and ONE named exception.
EXCEPTIONS = {"oracle_dag_walk": "walk_sig"}

# THE NAMED LOSS -- the oracle's third `osig` field.
SRCS = " srcs="

# THE ORACLE'S PREFIX for the rows this script gates.  The oracle's other rows
# (`oracle_hole_*`, `oracle_pmul*`, `oracle_seed`, `oracle_fwdwalk*`,
# `oracle_hole_error`) are CPython's OWN DIAGNOSTICS and are NOT gated: the port has
# no row for them, and a row that cannot be compared is not a gate.
GATED_PREFIX = "oracle_dag_"

# THE PORT'S PREFIX.
PORT_PREFIX = "walk_"


def port_name(oracle_name: str) -> str:
    """`oracle_dag_<x>` -> `walk_<x>`, with ONE named exception."""
    if oracle_name in EXCEPTIONS:
        return EXCEPTIONS[oracle_name]
    if not oracle_name.startswith(GATED_PREFIX):
        raise SystemExit("not a gated oracle row: %s" % oracle_name)
    return PORT_PREFIX + oracle_name[len(GATED_PREFIX):]


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
    gated = [n for n in oracle if n.startswith(GATED_PREFIX)]
    if len(gated) != 15:
        raise SystemExit("expected 15 %s* rows, found %d: %s"
                         % (GATED_PREFIX, len(gated), sorted(gated)))

    port = {}
    for name in gated:
        pname = port_name(name)
        value = oracle[name]
        if pname.startswith("walk_grad_"):
            # THE NAMED LOSS: the third `osig` field is not gated.
            value = value.split(SRCS)[0]
        if pname in port:
            raise SystemExit("two oracle rows map to the port row %s" % pname)
        port[pname] = value

    # THE COMPOSED ROW -- built from two gated rows, never typed.
    port["walk_row"] = "%s | grads_n=%s" % (port["walk_sig"], port["walk_grads_n"])
    if len(port) != 16:
        raise SystemExit("expected 16 port rows, composed %d" % len(port))

    # THE ORDER: the headline first, then the oracle's own order.
    order = ["walk_row"] + [port_name(n) for n in gated if port_name(n) != "walk_row"]
    assert sorted(order) == sorted(port), "the composed row is not in the order"
    with open(dst, "w") as fh:
        for name in order:
            fh.write("%s=%s\n" % (name, port[name]))
    print("transcribed %d oracle rows -> %d port rows in %s" % (len(gated), len(port), dst))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
