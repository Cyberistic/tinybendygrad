#!/usr/bin/env python3
# .agents/slop/load-census.py -- THE CENSUS OF RECORDED COUNTS THAT CARRY NO LOAD.
#
# WHAT IT ASKS, of every count this project has written down: what was the machine doing while you
# took it? The answer, measured over the corpus, is: almost never recorded, because nothing
# recorded it. This tool makes that answer a NUMBER with a DENOMINATOR instead of a mood.
#
#   THE INVARIANT UNDER TEST (loadwatch.py states it in prose; this tool makes it mechanical):
#
#       A COUNT MEASURED UNDER UNKNOWN LOAD IS NOT A COUNT.
#
# IT DOES NOT re-measure anything. The brief is explicit: re-running a suspect baseline under a
# known load to replace it would DESTROY THE RECORD of what was actually measured. So every count
# here is left exactly as recorded and is MARKED. The census adds a second column to a table that
# already exists; it does not overwrite the table.
#
# ONE SCANNER, TWO CALLERS, in the style of `rows()` being shared rather than reimplemented:
# rebase-gate-selftest.py's `load_guard()` calls `census()` from here. If the two ever disagreed
# about what a count claim is, the guard would be checking a different population than the census
# reports, which is the same defect as "a reader matching a format no lane emits".
#
# A "count claim" is defined MECHANICALLY, and the definition is printed by --vocab so it can be
# argued with:
#   * an INTEGER followed by a COUNT NOUN from SENSITIVE or INSENSITIVE below, in a .md or .txt
#     record under .agents/slop (the human-readable record layer);
#   * a tool-emitted `key=<int>` whose key is a ROW-COUNT KEY (the machine-readable layer);
#   * a length-of-rows in a JSON baseline's `lanes` map (the recorded-baseline layer).
# A claim is LOAD-QUALIFIED if a LOAD TOKEN appears on its own line or within a CONTEXT WINDOW of
# CONTEXT_LINES blank-line-delimited lines around it. The window exists because NV7's record puts
# "load average 6-7" on the line AFTER the "108 rows" it qualifies -- a line-only rule would
# under-report qualification and flatter the corpus.

import json
import pathlib
import re
import sys

CONTEXT_LINES = 8

# Count NOUNS whose referent is produced BY A RUNNING LANE or BY THE RUN QUEUE. These are the ones
# a starved process can move. "rows", "lanes", "graphs", "nodes", "fields", "disagreements" are the
# vocabulary of gate stdout; "defs" and "files" are properties of the TREE and cannot be starved.
SENSITIVE_NOUNS = (
  "rows", "row", "lanes", "lane", "graphs", "graph", "nodes", "node", "fields", "field",
  "disagreements", "targets", "ports", "proofs", "checked", "calls", "mutations-run",
)
INSENSITIVE_NOUNS = (
  "defs", "files", "mutations", "constants", "lines", "commits", "names", "rules", "rows-tables",
)

# `key=<int>` in a record is a row count only if the key names ROWS. `BROKEN=`/`DISAGREE=` are
# verdicts over lanes and DO move under load (a starved lane drops rows and can flip a verdict),
# so they are counted as sensitive too -- a tally is a function of its lanes.
ROWCOUNT_KEYS = ("rows", "row_counts", "interpreted", "native", "graphs", "nodes", "fields",
                 "shared", "shared-cores", "BROKEN", "DISAGREE", "ZERO-ROWS", "LANE-DEATH",
                 "INCOMPARABLE", "ROWS-LOST", "UNWIRED", "distinct row name", "row name")

# LOAD TOKENS. Each is a phrase this project actually uses for the run-queue. The list is printed
# so a reader can disagree with a specific entry rather than with the concept.
LOAD_TOKENS = (
  "load1", "load5", "load15", "loadavg", "load average", "load=", "load at", "at load",
  "n_bends", "bends resident", "processes resident", "concurrent", "nice ", "idle machine",
  "unloaded", "cores", "cpu", "run-queue", "run queue", "starved", "starvation", "under load",
  "machine load", "load1_start", "threshold=",
)

#: This census's own files, excluded from the text layer so it cannot qualify itself.
SELF = frozenset({"load-census.py", "loadwatch.py", "lane-load.py", "lane-load-sweep.sh"})


def _count_key_re():
  keys = "|".join(sorted((re.escape(k) for k in ROWCOUNT_KEYS), key=len, reverse=True))
  return re.compile(r"\b(" + keys + r")\s*=\s*([0-9][0-9,]*)", re.I)


def _noun_count_re(nouns):
  words = "|".join(sorted((re.escape(n) for n in nouns), key=len, reverse=True))
  return re.compile(r"(?<![\w.])(\d[\d,]*)\s+(" + words + r")(?![\w-])", re.I)


def _load_re():
  return re.compile("|".join(re.escape(t) for t in LOAD_TOKENS), re.I)


_COUNT_KEY = _count_key_re()
_SENS = _noun_count_re(SENSITIVE_NOUNS)
_INsens = _noun_count_re(INSENSITIVE_NOUNS)
_LOAD = _load_re()


def qualified(lineno, lines):
  """True if a load token is on the claim's line or in the blank-line-delimited window around it.
  `lineno` is 1-based into `lines`."""
  lo, hi = max(0, lineno - 1 - CONTEXT_LINES), min(len(lines), lineno + CONTEXT_LINES)
  for j in range(lo, hi):
    if j != lineno - 1 and not lines[j].strip():
      continue  # a blank line ends the block
    if _LOAD.search(lines[j]):
      return True, j + 1
  return False, None


def claims_in_text(name, text):
  """[(lineno, kind, count_str, line_text, qualified, load_lineno)] for every count claim in
  `text`. `kind` is `sensitive` or `insensitive` (a noun count) or `key` (a row-count key)."""
  lines = text.splitlines()
  out = []
  for i, line in enumerate(lines):
    for m in _COUNT_KEY.finditer(line):
      q, j = qualified(i + 1, lines)
      out.append((i + 1, "key", m.group(2), line.strip()[:110], q, j))
    for rx, kind in ((_SENS, "sensitive"), (_INsens, "insensitive")):
      for m in rx.finditer(line):
        q, j = qualified(i + 1, lines)
        out.append((i + 1, kind, m.group(1), line.strip()[:110], q, j))
  return out


def census(root, layers):
  """The census. Returns a dict with the totals and every finding.

  `layers`: which record layers to sweep.
    "text"   .md / .txt under .agents/slop and .agents/slop/notes
    "json"   the recorded baselines in .agents/slop/rebase
  Each layer reports its own denominator; they are NOT summed into one grand total, because a
  `.md` sentence and a baseline row-count are different kinds of claim and a combined ratio would
  be a number about nothing."""
  slop = pathlib.Path(root) / ".agents" / "slop"
  findings, per_layer = [], {}
  for layer in layers:
    if layer == "text":
      files = sorted(slop.rglob("*.md")) + sorted(slop.rglob("*.txt"))
      # ⚠ THE CENSUS DOES NOT COUNT ITSELF. Its own source carries load vocabulary in its
      # docstrings, so including it would raise the qualified fraction with claims that exist only
      # because this file was written. A census that measures its own prose is not evidence.
      files = [f for f in files if f.name not in SELF]
    elif layer == "json":
      files = sorted((slop / "rebase").glob("*.json"))
    else:
      raise ValueError(f"unknown layer {layer!r}")
    tot = sens = ins = q = qs = 0
    for f in files:
      try:
        text = f.read_text(errors="replace")
      except OSError:
        continue
      if layer == "json":
        cs = _json_claims(f, text)
      else:
        cs = claims_in_text(f.name, text)
      for lineno, kind, cnt, snippet, isq, j in cs:
        tot += 1
        if kind == "sensitive":
          sens += 1
          if isq:
            qs += 1
        else:
          ins += 1
        findings.append({"layer": layer, "file": str(f.relative_to(slop)), "line": lineno,
                         "kind": kind, "count": cnt, "text": snippet, "load_qualified": isq,
                         "load_line": j})
    per_layer[layer] = {"files": len(files), "claims": tot, "sensitive": sens,
                        "insensitive": ins, "sensitive_load_qualified": qs,
                        "sensitive_unqualified": sens - qs}
  return {"per_layer": per_layer, "findings": findings}


def _json_claims(f, text):
  """Count claims in a recorded JSON baseline: the length of each lane's row dict is a recorded
  count, and a load beside it would be a `load1` key on that lane, that port, or the document.
  There is no such key anywhere in baseline.json -- 108 occurrences of the substring "load" and
  ZERO keys that begin with it -- so all of these are unqualified by construction. That is the
  finding, and it is why the layer is checked structurally rather than by grepping for a word
  that also occurs inside row values."""
  try:
    doc = json.loads(text)
  except ValueError:
    return []
  if not isinstance(doc, dict) or "lanes" not in doc:
    return []
  docload = any(str(k).startswith("load") for k in doc)
  out = []
  for port, lanes in (doc.get("lanes") or {}).items():
    if not isinstance(lanes, dict):
      continue
    portload = docload or any(str(k).startswith("load") for k in lanes)
    for lane, rowsd in lanes.items():
      if not isinstance(rowsd, dict):
        continue
      laneload = portload or any(str(k).startswith("load") for k in rowsd)
      n = len(rowsd)
      # kind is `sensitive`: a recorded lane's row count is the single most load-sensitive number
      # this project writes down. Reporting it as anything else would drop every baseline in the
      # corpus out of the suspect set, which is the exact failure the census exists to catch.
      out.append((0, "sensitive", str(n), f"{port} {lane}: {n} recorded row name(s)", laneload, None))
  return out


def main():
  import argparse
  ap = argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[2]))
  ap.add_argument("--layer", action="append", choices=["text", "json"],
                  help="record layer to sweep (default: both)")
  ap.add_argument("--vocab", action="store_true", help="print the scanner's vocabulary and exit")
  ap.add_argument("--suspect", action="store_true", help="print every unqualified SENSITIVE claim")
  ap.add_argument("--json", help="write the full census here")
  a = ap.parse_args()
  if a.vocab:
    print("SENSITIVE_NOUNS   =", ", ".join(SENSITIVE_NOUNS))
    print("INSENSITIVE_NOUNS =", ", ".join(INSENSITIVE_NOUNS))
    print("ROWCOUNT_KEYS     =", ", ".join(ROWCOUNT_KEYS))
    print("LOAD_TOKENS       =", ", ".join(LOAD_TOKENS))
    print(f"CONTEXT_LINES     = {CONTEXT_LINES} blank-line-delimited")
    return 0
  layers = a.layer or ["text", "json"]
  c = census(a.root, layers)
  for layer, d in c["per_layer"].items():
    s, sq = d["sensitive"], d["sensitive_load_qualified"]
    pct = (100.0 * sq / s) if s else 0.0
    print(f"LAYER {layer}: {d['files']} file(s), {d['claims']} count claim(s)")
    print(f"  sensitive (lane- or run-queue-derived): {s}   load-qualified {sq}   "
          f"UNQUALIFIED {s - sq}   ({pct:.1f}% qualified)")
    if d["insensitive"]:
      print(f"  insensitive (tree-derived: defs/files/constants): {d['insensitive']}  "
            f"[not load-starvable; excluded from the suspect set]")
  tot_s = sum(d["sensitive"] for d in c["per_layer"].values())
  tot_q = sum(d["sensitive_load_qualified"] for d in c["per_layer"].values())
  print(f"\nSUSPECT SET: {tot_s - tot_q} of {tot_s} sensitive recorded counts carry NO load "
        f"({100.0 * (tot_s - tot_q) / tot_s if tot_s else 0:.1f}%). "
        f"A count measured under unknown load is not a count.")
  if a.suspect:
    print("\n-- every unqualified SENSITIVE claim --")
    for f in c["findings"]:
      if f["kind"] == "sensitive" and not f["load_qualified"]:
        print(f"  {f['layer']}/{f['file']}:{f['line']}  {f['count']}  {f['text']}")
  if a.json:
    pathlib.Path(a.json).write_text(json.dumps(c, indent=1))
    print(f"\nwrote {a.json}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
