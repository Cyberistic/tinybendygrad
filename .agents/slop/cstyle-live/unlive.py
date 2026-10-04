#!/usr/bin/env python3
"""unlive.py -- the inverse of `extract.py`, for rows produced by `emit-real.bend`.

`extract.py` reads the PORT's GATE rows out of `cstyle.bend`'s own stdout with
`cstyle-gate.py`'s `rows_strict`/`split_py`.  This reads the rows the SCRATCH probe
(`emit-real.bend`, in a $TMPDIR copy of the tree) prints, which carry NO `py=` column --
they are live calls of `render_kernel` with fixtures, not gate rows.  Same unescape, same
refusal rather than an empty file, because "compiled nothing" must never read as
"compiled cleanly".

  usage: unlive.py <live.txt> <row-name> <out.c>
"""
import pathlib, sys


def unescape(s):
  """`C.esc_row` is `String.join(String.split(s, '\\n'), "\\\\n")` (cstyle.bend:1808): the
  only escape it introduces is a backslash-n.  One pass, no regex, so a backslash already
  in the text is not reinterpreted."""
  return s.replace("\\n", "\n")


def main():
  src, name, dest = sys.argv[1], sys.argv[2], sys.argv[3]
  lines = pathlib.Path(src).read_text().splitlines()
  hits = [l for l in lines if l.startswith(name + " = [") and l.endswith("]")]
  if len(hits) != 1:
    print(f"unlive: {len(hits)} rows match {name!r} ({len(lines)} lines read); "
          f"refusing to write {dest}", file=sys.stderr)
    return 2
  value = hits[0][len(name) + len(" = ["):-1]
  pathlib.Path(dest).write_text(unescape(value))
  print(f"unlive: {name!r} -> {dest}  ({unescape(value).count(chr(10)) + 1} physical lines)")
  return 0


if __name__ == "__main__":
  sys.exit(main())