#!/usr/bin/env python3
"""dsp-fix.py -- restore the indentation `dsp-gen.py`'s line copier drops.

`rewrite()` copies the text BEFORE each row call with `gate[i:m.start()]`, which already
carries the indent -- but a row whose call spans lines also swallows the next row's
indent, because `m.start()` for that row is measured against a `gate` whose earlier
lines have already been consumed. Rather than reason about it, this re-indents every
statement of every `do IO<Unit>:` block in the gate to four spaces, which is the shape
the file had before the conversion and the shape `bend` accepts.

    .venv/bin/python .agents/slop/dsp-fix.py
"""
import re
from pathlib import Path

TARGET = Path(__file__).resolve().parents[2] / "tinybendygrad/runtime/ops_dsp.bend"
CALL = re.compile(r'^(row|urow|srow|lrow)\(')
# A line inside a `do IO<Unit>:` block that is neither blank, nor a comment, nor a row,
# nor a `do`, is a FRAGMENT: the tail of a row call whose own literal once held a real
# newline. `split_top` counts parens inside string literals correctly, but the fragments
# were written by an earlier generator run and nothing else removes them.
FRAGMENT = re.compile(r'^(?!\s)(?!\s*#)(?!\s*(row|urow|srow|lrow|do|def)\b).*\)$')


def main():
  lines = TARGET.read_text().split("\n")
  lo = next(i for i, l in enumerate(lines) if l.startswith("def t_rpcsc()"))
  hi = next(i for i, l in enumerate(lines) if l.startswith("def main()"))
  kept = [l for l in lines[:lo]]
  n = frag = 0
  i = lo
  while i < hi:
    l = lines[i]
    if FRAGMENT.match(l):
      frag += 1
      i += 1
      continue
    if CALL.match(l):
      depth = l.count("(") - l.count(")")
      if not l.startswith("    "):
        kept.append("    " + l)
        n += 1
      else:
        kept.append(l)
      i += 1
      while depth > 0:
        l = lines[i]
        if not l.startswith("    "):
          l = "    " + l
          n += 1
        kept.append(l)
        depth += l.count("(") - l.count(")")
        i += 1
      continue
    kept.append(l)
    i += 1
  kept.extend(lines[hi:])
  TARGET.write_text("\n".join(kept))
  print(f"re-indented {n} lines, dropped {frag} fragment lines")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())