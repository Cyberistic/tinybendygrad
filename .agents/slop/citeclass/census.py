#!/usr/bin/env python3
"""census.py -- HOW MANY CITATIONS ARE OUTSIDE THE `TODO(pN)` POPULATION, AND HOW MANY
OF THOSE ARE FALSE.

    .venv/bin/python .agents/slop/citeclass/census.py --pin ROWS --todo ROWS --out ROWS

THE CLASS. The port's `.bend` files cite upstream as `file.py:NNN` inside comments. Two
instruments measure those citations and they have DIFFERENT populations:

  `gates/pin-cite-gate.py`  every citation it can parse. It discovers the population by
                            walking the tree and loading its parser from
                            `gates/header-census-gate.py` BY PATH.
  `gates/todo-cite-gate.py` ONLY the citations carried by a `TODO(pN)` marker. The
                            marker is the port's own priority tag.

The `TODO(pN)` population is a SUBSET, so every citation outside it is INVISIBLE to the
todo-cite gate -- and a citation nobody measures is a citation nobody can be wrong
about.

THE POPULATION HERE IS DISCOVERED, NOT NAMED. The `.bend` files are found by `os.walk`
over `tinybendygrad/`, never by a list, and the rows come from the two gates' own rows
files. The only thing this file knows in advance is the MARKER SPELLING, which is the
port's own tag and not a population.

TWO CLASSIFICATIONS, AND THE SECOND IS THE ONE THAT COUNTS.

  BY LINE   the pin-cite row's OWN source line carries a `TODO(pN)` marker.
  BY GATE   the citation is one the todo-cite gate ACTUALLY measures -- its own rows
            file says so. The two differ: the todo-cite gate also measures a citation
            that sits in the PROSE of a comment block, on a line of its own, with the
            marker further down. A census that counted only the marker-bearing lines
            would UNDERCOUNT the gate's population, and a census that counted only
            the gate's rows would not answer the question as asked. Both are reported.

FALSE means THE CITATION DOES NOT HOLD AT THE PIN, and the gate's own class says how:
  `at_pin`                the cited line holds what the port's comment claims.
  `only_older_revision`  it holds at an OLDER upstream revision and not at the pin.
  `dangling`              it holds at NO upstream revision and names one file outright.
  `ambient_relocated`     it holds at ANOTHER upstream file with the same basename.
  `unverifiable`          it makes NO claim about the cited file (the port's own
                          vocabulary), so it is COUNTED and NOT VERDICTED.
  `uncheckable_no_claim_token`
                          no claim token at all, so it is COUNTED and NOT VERDICTED.

So the FALSE count is reported two ways: the VERDICTED false (the gate made a negative
verdict on a checkable claim) and the COUNTED-BUT-UNVERIFIABLE (the gate could not
falsify it). Reporting only the first would hide a third of the population; reporting
only the second would call an unfalsifiable claim a failure.
"""

from __future__ import annotations

import argparse
import collections
import csv
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT_REL = "tinybendygrad"

#: The port's own marker spelling. NOT a population: it says what a marker LOOKS LIKE.
MARKER = re.compile(r"TODO\((p\d+)\)")


def walk_bend(root: Path) -> list[Path]:
  """Every `.bend` file under `root`, DISCOVERED. `glob` is a trap here."""
  out: list[Path] = []
  for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in {".git", "__pycache__", "node_modules"}]
    for f in fn:
      if f.endswith(".bend"):
        out.append(Path(dp) / f)
  return sorted(out, key=lambda p: str(p))


def read_rows(path: Path) -> list[dict]:
  with path.open(encoding="utf-8", errors="replace", newline="") as fh:
    return list(csv.DictReader(fh, delimiter="\t"))


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--pin", required=True, help="the pin-cite gate's rows file")
  ap.add_argument("--todo", required=True, help="the todo-cite gate's rows file")
  ap.add_argument("--out", required=True, help="where the census rows go")
  ap.add_argument("--report", default="", help="where the census report goes")
  args = ap.parse_args()

  pin_rows = read_rows(Path(args.pin))
  todo_rows = read_rows(Path(args.todo))

  # THE TODO-CITE GATE'S OWN POPULATION, AS A SET OF (rel, subject, lo). It is the
  # instrument's own answer, not a re-derivation of it.
  gate_pop = {(r["rel"], r["subject"], r["lo"]) for r in todo_rows}

  # THE SOURCE LINES, DISCOVERED.
  lines_by_rel: dict[str, list[str]] = {}
  for p in walk_bend(ROOT / PORT_REL):
    rel = str(p.relative_to(ROOT))
    lines_by_rel[rel] = p.read_text(encoding="utf-8", errors="replace").splitlines()

  out_rows: list[dict] = []
  for r in pin_rows:
    rel, at = r["rel"], int(r["at"])
    src = lines_by_rel.get(rel)
    if src is None:
      raise SystemExit(f"REFUSED: the pin rows name {rel}, which the walk did not find")
    if at < 1 or at > len(src):
      raise SystemExit(f"REFUSED: {rel}:{at} is outside the file")
    line = src[at - 1]
    by_line = bool(MARKER.search(line))
    by_gate = (rel, r["subject"], r["lo"]) in gate_pop
    cls = r["class"]
    if cls == "at_pin":
      false = "no"
    elif cls == "uncheckable_no_claim_token":
      false = "unverifiable-no-claim-token"
    elif cls == "unverifiable":
      false = "unverifiable-no-claim-about-the-file"
    else:
      false = "yes"
    out_rows.append({
      "rel": rel, "at": at, "subject": r["subject"], "lo": r["lo"], "hi": r["hi"],
      "class": cls, "at_pin": r["at_pin"], "false_at_pin": false,
      "tagged_by_line": int(by_line), "tagged_by_gate": int(by_gate),
      "marker": (MARKER.search(line).group(1) if by_line else ""),
      "claim": r["claim"], "line": line,
    })

  outp = Path(args.out)
  outp.parent.mkdir(parents=True, exist_ok=True)
  with outp.open("w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()), delimiter="\t",
                       lineterminator="\n")
    w.writeheader()
    w.writerows(out_rows)

  total = len(out_rows)
  by_line = [r for r in out_rows if r["tagged_by_line"]]
  by_gate = [r for r in out_rows if r["tagged_by_gate"]]
  outside_line = [r for r in out_rows if not r["tagged_by_line"]]
  outside_gate = [r for r in out_rows if not r["tagged_by_gate"]]

  def split(rows):
    verdicted = [r for r in rows if r["false_at_pin"] == "yes"]
    unverifiable = [r for r in rows if r["false_at_pin"].startswith("unverifiable")]
    return verdicted, unverifiable

  lv, lu = split(outside_line)
  gv, gu = split(outside_gate)

  lines: list[str] = []
  lines.append("# THE CLASS -- CITATIONS OUTSIDE THE `TODO(pN)` POPULATION")
  lines.append("")
  lines.append(f"Pin-cite rows read : {args.pin} ({total} citations)")
  lines.append(f"Todo-cite rows read : {args.todo} ({len(todo_rows)} marker citations)")
  lines.append(f"`.bend` files walked : {len(lines_by_rel)}")
  lines.append("")
  lines.append("## BY LINE -- the citation's OWN source line carries a `TODO(pN)` marker")
  lines.append("")
  lines.append(f"  total citations                    {total}")
  lines.append(f"  tagged (marker on the source line) {len(by_line)}")
  lines.append(f"  OUTSIDE the tagged population       {len(outside_line)}")
  lines.append(f"    of those, FALSE at the pin        {len(lv)}")
  lines.append(f"    of those, unverifiable            {len(lu)}")
  lines.append("")
  lines.append("## BY GATE -- the citation is one `todo-cite-gate.py` MEASURES")
  lines.append("")
  lines.append(f"  measured by todo-cite-gate.py      {len(by_gate)}")
  lines.append(f"  NOT measured by it                  {len(outside_gate)}")
  lines.append(f"    of those, FALSE at the pin        {len(gv)}")
  lines.append(f"    of those, unverifiable            {len(gu)}")
  lines.append("")
  lines.append("## THE CLASSES OF THE UNMEASURED CITATIONS, BY THE PIN-CITE GATE'S OWN CLASS")
  lines.append("")
  c = collections.Counter(r["class"] for r in outside_gate)
  cfalse = collections.Counter(r["class"] for r in outside_gate if r["false_at_pin"] == "yes")
  for cls, n in c.most_common():
    lines.append(f"  {cfalse.get(cls, 0):5d} false  {n:5d} total  {cls}")
  lines.append("")
  lines.append("## THE DENSEST FILES BY FALSE COUNT (citations the todo-cite gate does NOT measure)")
  lines.append("")
  per = collections.defaultdict(lambda: [0, 0])
  for r in outside_gate:
    per[r["rel"]][1] += 1
    if r["false_at_pin"] == "yes":
      per[r["rel"]][0] += 1
  for rel, (nf, nt) in sorted(per.items(), key=lambda kv: (-kv[1][0], -kv[1][1], kv[0])):
    if nf == 0 and nt == 0:
      continue
    lines.append(f"  {nf:5d} false  {nt:5d} unmeasured  {rel}")
  lines.append("")
  lines.append("## THE DENSEST FILES BY FALSE COUNT (citations the todo-cite gate does NOT measure,")
  lines.append("## restricted to the rows whose OWN source line carries no `TODO(pN)` marker)")
  lines.append("")
  per2 = collections.defaultdict(lambda: [0, 0])
  for r in outside_line:
    per2[r["rel"]][1] += 1
    if r["false_at_pin"] == "yes":
      per2[r["rel"]][0] += 1
  for rel, (nf, nt) in sorted(per2.items(), key=lambda kv: (-kv[1][0], -kv[1][1], kv[0]))[:30]:
    lines.append(f"  {nf:5d} false  {nt:5d} untagged  {rel}")
  lines.append("")
  text = "\n".join(lines) + "\n"
  if args.report:
    Path(args.report).write_text(text, encoding="utf-8")
  print(text)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
