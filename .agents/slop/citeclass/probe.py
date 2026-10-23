#!/usr/bin/env python3
"""probe.py -- EVERY citation in ONE `.bend` file, judged against the pin.

    .venv/bin/python .agents/slop/citeclass/probe.py FILE.bend

WHY THIS EXISTS. `gates/pin-cite-gate.py` reads a file's HEADER BLOCK, because that is
where the port declares its upstream target. A citation in the BODY of a file -- the
comment that explains a rule and points at the upstream line it came from -- is INVISIBLE
to it. `gates/todo-cite-gate.py` reads the BODY, but only the part a `TODO(pN)` marker
touches.

So there is a third population: the body's citations that neither instrument reads.
This probe measures it, with the SAME parser (`gates/header-census-gate.py`, loaded BY
PATH) and the SAME content test (`gates/pin-cite-gate.py`, loaded BY PATH), so a rule
changes in one place.

THE VERDICT IS THE PIN-CITE GATE'S OWN. A citation HOLDS if the cited line holds one of
the claim tokens the port backticked near it, or declares the construct, or is inside a
construct's body. A citation that holds at NO upstream revision and names ONE file
outright is a DANGLING claim. A citation that holds only at an OLDER revision is a ROW
and not a failure -- the port's header was pinned to the revision it was written against.
"""

from __future__ import annotations

import collections
import importlib.util
import os
import re
import subprocess
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


pin_cite = load("probe_pin_cite", ROOT / "gates" / "pin-cite-gate.py")
census = pin_cite.load_census()


def main() -> int:
  path = Path(sys.argv[1])
  rel = str(path.relative_to(ROOT)) if path.is_absolute() else str(path)
  body = path.read_text(encoding="utf-8", errors="replace").splitlines()
  first, _last, blk = census.header_block(body)
  tgt = census.declared_target(blk) if blk else ""
  # THE WHOLE FILE IS THE BLOCK. `citation_claims` reads a list of lines and returns
  # `(rel, at, subject, kind, lo, hi, line)` for every citation in it, with the BARE
  # `:N` form resolved against the declared target.
  cites = census.citation_claims(body, 1, rel, tgt)
  up_dir = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
  # THE CLAIM TOKENS, per citation, by the pin-cite gate's own rule.
  by_line: dict[int, list[dict]] = collections.defaultdict(list)
  for c in cites:
    by_line[c["at"]].append(c)
  for at, group in by_line.items():
    spans = pin_cite.line_spans(census, body[at - 1])
    for i, c in enumerate(group):
      c["toks"] = pin_cite.window_tokens(c["line"], spans, i) if i < len(spans) else []
  # THE LOCAL-SIDED RULE, the pin-cite gate's own: a bare `:N` on a line that names a
  # file that is NEITHER `.py` NOR `.bend` is about THAT file, not about the header's
  # declared upstream target. And a `.bend` subject is the PORT's own file.
  up = []
  for c in cites:
    if not c["subject"].endswith(".py"):
      continue
    explicit = f"{c['subject']}:{c['lo']}" in c["line"]
    if not explicit and pin_cite.local_sided(c["line"]):
      continue
    c["prefer_dir"] = up_dir
    c["explicit"] = explicit
    up.append(c)
  pin_cite.resolve_all(census, up)
  print(f"# {rel}: {len(cites)} citations ({len(up)} upstream), target={tgt or '(none)'}")
  counts = collections.Counter(pin_cite.row_class(c) for c in up)
  for k, n in counts.most_common():
    print(f"#   {n:5d}  {k}")
  print()
  for c in sorted(up, key=lambda c: c["at"]):
    cls = pin_cite.row_class(c)
    flag = "  " if cls in ("at_pin", "only_older_revision") else "**"
    print(f"{flag}{c['at']:>6}  {c['subject']}:{c['lo']}"
          + (f"-{c['hi']}" if c["hi"] != c["lo"] else "")
          + f"  [{cls}]  tokens={','.join(c['toks'])[:50]}")
    if cls not in ("at_pin",):
      print(f"        {c['line'][:140]}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
