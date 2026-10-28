#!/usr/bin/env python3
"""put.py -- PUT AN UPSTREAM TOKEN ON THE CITATION'S OWN LINE.

    .venv/bin/python .agents/slop/unv3/put.py <port-file> <line-no> <token> <replacement-fragment>

THE RULE THIS TOOL ENCODES, MEASURED FROM `gates/pin-cite-gate.py`'s OWN CODE:
`collect()` calls `window_tokens(c["line"], spans, i)` -- THE CITATION'S OWN LINE.
So a claim token that sits on the NEXT line is a token of no citation, and the
citation it was meant for reads as UNVERIFIABLE. This tool moves the fragment so
the token and the citation share a line.
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]


def main() -> int:
  rel, at, tok, frag = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
  p = ROOT / rel
  lines = p.read_text().splitlines(keepends=True)
  idx = at - 1
  if idx < 0 or idx >= len(lines):
    print(f"REFUSED: {rel} has {len(lines)} lines, no line {at}")
    return 3
  line = lines[idx]
  if f"`{tok}`" in line:
    print(f"NO-OP: {rel}:{at} already carries `{tok}`")
    return 0
  # THE FRAGMENT IS INSERTED AT THE CITATION, AND THE TOKEN GOES WITH IT.
  out = line.replace(f" {frag}", f" {frag} `{tok}`", 1)
  if out == line:
    print(f"REFUSED: {rel}:{at} does not carry the fragment {frag!r}")
    return 3
  lines[idx] = out
  p.write_text("".join(lines))
  print(f"{rel}:{at} -> {out.rstrip()}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
