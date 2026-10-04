#!/usr/bin/env python3
"""extract.py -- take ONE `kern2 <NAME> = [...]   py=[...]` row out of cstyle.bend's
stdout and write the row's OWN value to a real .c file.

WHY THE UNESCAPE IS THE WHOLE POINT. The gate's row is a STRING COMPARISON: the port's
value and CPython's are both newline-escaped (`esc_row`, cstyle.bend:1808) so a row can
stay one physical line. Every one of the ~227 comparisons therefore happens on ESCAPED
TEXT. Nothing downstream has ever asked what the text looks like after the escape is
undone, which is what a COMPILER sees.

THE READER IS `cstyle-gate.py`'s, IMPORTED -- not a copy. cstyle-gate.py's own docstring
records that a forked row reader was wrong on 4 of 6 shapes while claiming to be
`rebase-gate.rows` "verbatim", so a second reader here would be the same defect a third
time. `rows_strict` + `split_py` are used verbatim; this file only adds the unescape,
which is the one step the gate deliberately never performs.

  usage: extract.py <port.txt> <row-name> <out.c>
"""
import importlib.util, pathlib, sys

GATE = pathlib.Path(__file__).resolve().parents[1] / "cstyle-gate.py"
_spec = importlib.util.spec_from_file_location("cstyle_gate", GATE)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


def unescape(s):
  """`esc_row` is `String.join(String.split(s, '\\n'), "\\\\n")` (cstyle.bend:1808), so the
  only escape it introduces is a backslash-n. Reverse exactly that -- one pass, no regex,
  so a literal backslash already in the source text cannot be silently reinterpreted."""
  return s.replace("\\n", "\n")


def main():
  port, name, dest = sys.argv[1], sys.argv[2], sys.argv[3]
  rows, shreds, dups = gate.rows_strict(pathlib.Path(port).read_text())
  if dups:
    print(f"extract: {len(dups)} duplicate row name(s): {sorted(set(dups))}", file=sys.stderr)
  if name not in rows:
    print(f"extract: no row named {name!r}; {len(rows)} rows read, {len(shreds)} shredded. "
          f"Refusing to write {dest}.", file=sys.stderr)
    return 2
  got, lit = gate.split_py(rows[name])
  py = unescape(lit) if lit is not None else None
  pathlib.Path(dest).write_text(unescape(got))
  print(f"extract: {name!r} -> {dest}  value {len(got)} escaped bytes -> "
        f"{unescape(got).count(chr(10))+1} physical lines  |  "
        f"value==py_literal: {py == unescape(got)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())