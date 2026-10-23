#!/usr/bin/env python3
"""mkrows.py -- the 31 rows of `nn/layers.bend` as a `.rows` dump, AND the
cross-check that every `want` is CPython's answer and not the port's own `got`.

    .venv/bin/python .agents/slop/nnrowsfix/mkrows.py

WHAT IT WRITES. `.agents/slop/nnrowsfix/rows.rows`, one row per printed row, in
the house F2 shape `name = [port value] py=[CPython witness]` -- the shape
`gates/lanecmp.py:read_rows` reads, and the shape whose two halves mean exactly
what this file needs them to mean: the PORT's answer and the WITNESS's answer.

WHAT IT CHECKS, AND WHY IT IS NOT A RESTATEMENT. The `want` column of every row
lives in the `.bend` file and NOWHERE ELSE (`gates/nn-rows-gate.py` reads it from
the printed `want=` column). This script asks a different question of it: is that
`want` byte-equal to the value the CPython witness
(`.agents/slop/nnrowsfix/nn-oracle.py`) prints for the SAME name? A `want` that
was copied out of the port's own `got` would NOT be in the witness -- the witness
is upstream tinygrad's own graph and shape arithmetic, computed in this repo's
`.venv`, and it never reads the port. So this check is what makes "the want is
CPython's" a measurement rather than an assertion, and it runs over ALL 31 rows
and not only over the thirteen that were open.

THE MEASUREMENT ITSELF IS THE GATE'S. `gates/nn-rows-gate.py` is imported by
PATH and its `measure()` is called, so the rows here and the gate's rows come
from ONE bend run and cannot be a half-written pair. The gate's output directory
is REDIRECTED into this unit's own directory: `measure()` clears it on every call
(`gates/nn-rows-gate.py:522-525`), and `gates/artifacts/` is a shared path that
another unit's gate run also writes.
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent


def load_gate():
    """`gates/nn-rows-gate.py` as a module, loaded BY PATH."""
    spec = importlib.util.spec_from_file_location(
        "nnrowsgate", ROOT / "gates" / "nn-rows-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_witness(path: Path) -> dict:
    """The witness's `name=value` rows. The `#` lines are the witness's own
    commentary on the OTHER format and are not rows."""
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, sep, value = line.partition("=")
        if sep:
            out[name] = value
    return out


def main() -> int:
    mod = load_gate()
    mod.OUT = HERE / "artifacts" / "nn-rows-gate"
    witness = read_witness(HERE / "nn-oracle.rows")

    with tempfile.TemporaryDirectory(prefix="nnrowsfix-rows-") as td:
        port = mod._materialize(Path(td) / "port", None)
        code, counts, n_rows, n_expected, lines, rows = mod.measure(port, "mkrows")
        if code not in (mod.PASS, mod.FAIL):
            print(f"mkrows: REFUSED, NOT A VERDICT: the gate did not measure "
                  f"(rc={code})", file=sys.stderr)
            return 3

        names = [r.name for r in rows]
        dupes = sorted({n for n in names if names.count(n) > 1})
        print(f"mkrows: gate_rc={code} rows_printed={n_rows} rows_declared={n_expected} "
              f"duplicates={dupes or 'none'}")
        print(f"mkrows: witness_rows={len(witness)} "
              f"witness_names_not_in_the_port={sorted(set(witness) - set(names))} "
              f"port_names_not_in_the_witness={sorted(set(names) - set(witness))}")

        out, bad = [], []
        for r in rows:
            w = witness.get(r.name)
            if w is None:
                bad.append(f"{r.name}: the witness has NO row for this name")
                out.append(f"{r.name} = [{r.got}] py=[{r.want}]")
                continue
            if w != r.want:
                bad.append(f"{r.name}: want={r.want!r} but the witness says {w!r}")
            out.append(f"{r.name} = [{r.got}] py=[{r.want}]")

        (HERE / "rows.rows").write_text("\n".join(out) + "\n")
        print(f"mkrows: wrote {HERE / 'rows.rows'} with {len(out)} rows")
        if bad:
            print("mkrows: FAILED -- a `want` is not the witness's value:", file=sys.stderr)
            for b in bad:
                print(f"mkrows:   {b}", file=sys.stderr)
            return 1
        print(f"mkrows: every one of the {len(out)} `want`s is byte-equal to the "
              f"witness's value for the same name")
        return 0


if __name__ == "__main__":
    sys.exit(main())
