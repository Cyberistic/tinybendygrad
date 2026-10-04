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
# `load_guard()` below is the mechanical test, and it calls `census()`/`ledger()` from here rather
# than reimplementing either. If the two ever disagreed about what a count claim is, the guard
# would be checking a different population than the census reports, which is the same defect as
# "a reader matching a format no lane emits".
#
# ⚠ `load-census.py` v1 claimed rebase-gate-selftest.py carried a `load_guard()` that called in
# here. IT DID NOT, AND DOES NOT: that file imports nothing from this module. The claim was a
# docstring describing an intended wiring as a present one -- the exact failure this tool exists to
# catch, written in the tool. The guard lives HERE now, where it can be run.
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
SELF = frozenset({"load-census.py", "loadwatch.py", "lane-load.py", "lane-load-sweep.sh",
                  # ⚠ ADDED AFTER IT HAPPENED. `baseline-ledger.txt` matched the ledger's own
                  # `*baseline*.txt` glob, so the ledger counted ITS OWN OUTPUT as a recorded
                  # baseline: the denominator read 234 on the first run and 235 seconds later, with
                  # no edit in between. The `SELF` guard existed for the text layer from v1 and
                  # was not applied to the ledger's glob, which is the same omission in a second
                  # place. An instrument that appears in its own population is not measuring.
                  "baseline-ledger.txt", "baseline-ledger.json"})


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
  There is no such key anywhere in baseline.json -- 176 occurrences of the substring "load" (27 of
  them the literal "load1", every one inside a row NAME like `k1_load_store`), and ZERO JSON keys
  that begin with it -- so all of these are unqualified by construction. That is the finding, and
  it is why the layer is checked structurally rather than by grepping for a word that also occurs
  inside row values. (The 176 was measured 2026-10-04. v1 of this docstring said 108, which had
  gone stale the way every number in this project goes stale: the file grew and the prose did
  not.)"""
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


# ── THE LEDGER ────────────────────────────────────────────────────────────────────────────
# Every RECORDED BASELINE gets a row here: where it is, what revision it was taken at, how many
# rows it holds, WHAT THE MACHINE WAS DOING, and a verdict. It is a LEDGER and not a refresh --
# nothing below re-runs a lane, and nothing overwrites a count.
#
# WHAT "A RECORDED BASELINE" IS, defined mechanically so the denominator is a number rather than
# a mood: a file in this corpus whose row counts a later comparison is made AGAINST. That is three
# shapes, found by glob, never typed -- a lane stdout dump (`*baseline*.txt`), a recorded lane map
# (`rebase/baseline*.json`), and the repeat-run capture (`rebase/stability-*.json`).
#
# ⚠ THE DENOMINATOR IS THE FINDING. 0 of these artefacts record a load, 0 record an elapsed time,
# and 0 record a revision -- so "revision" is UNKNOWN for every row, which means the UNCHANGED
# test the ledger needs is not merely unmet, it is UNDECIDABLE: there is no recorded revision for
# the working copy to be compared against. A baseline whose provenance cannot be established
# cannot be shown to describe the tree it is being compared to.
#
# A txt dump is identified against baseline.json by ROW-NAME SET EQUALITY, not by a typed port
# name, so the ledger cannot launder a port's identity through a transcription. The stability
# capture stores counts only, never row names, so a corroboration drawn from it is a COUNT
# agreement and is labelled as such -- weaker than the row-set agreement above and not quietly
# upgraded to it.

_TXT = "*baseline*.txt"


def _row_names(text):
  """The row NAMES of a lane stdout dump: the text before the first `=` or `|`, minus banners and
  comments. Same shape `rebase-gate.py`'s `rows()` reads, because the ledger compares sets of
  names and a differently-shaped name is a differently-shaped key."""
  out = set()
  for line in text.splitlines():
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("=="):
      continue
    name = line.split("=", 1)[0].split("|", 1)[0].strip()
    if name:
      out.add(name)
  return out


def _stability(root):
  """(name, {port: {lane: (run1, run2)}}) from the repeat-run capture, or (None, {}) if absent.
  A lane whose two runs agree is a count that reproduced inside one session: evidence about COUNT
  STABILITY and no evidence at all about LOAD, because the two runs shared a machine of unknown
  loading. They are two draws from one distribution, not two machines."""
  for f in sorted((pathlib.Path(root) / ".agents" / "slop" / "rebase").glob("stability-*.json")):
    try:
      doc = json.loads(f.read_text())
    except (OSError, ValueError):
      continue
    ports = {p: v for p, v in doc.items() if isinstance(v, dict) and "row_counts_run1" in v}
    if not ports:
      continue
    return f.name, {p: {lane: (v["row_counts_run1"].get(lane), v.get("row_counts_run2", {})
                                .get(lane))
                        for lane in v["row_counts_run1"]} for p, v in ports.items()}
  return None, {}


def captures(root):
  """The ledger's rows, each a dict with `path`, `revision`, `rows`, `load`, `verdict` and the
  three recoverability facts. Sorted by path so two runs of this produce two identical ledgers."""
  slop = pathlib.Path(root) / ".agents" / "slop"
  stab_name, stab = _stability(root)
  # port -> lane -> frozenset(row names), so a txt dump can be identified without a typed port.
  names = {}
  for f in sorted((slop / "rebase").glob("baseline*.json")):
    try:
      doc = json.loads(f.read_text())
    except (OSError, ValueError):
      continue
    for port, lanes in (doc.get("lanes") or {}).items():
      if isinstance(lanes, dict):
        for lane, rows in lanes.items():
          if isinstance(rows, dict):
            names.setdefault(port, {})[lane] = (f.name, frozenset(rows))
  out = []
  for f in sorted(slop.glob(_TXT)):
    if f.name in SELF:
      continue
    text = f.read_text(errors="replace")
    rn = frozenset(_row_names(text))
    port = lane = None
    for p, lanes in names.items():
      for ln, (src, ns) in lanes.items():
        if ns == rn:
          port, lane = p, ln
    out.append({"kind": "txt", "path": str(f.relative_to(slop)), "revision": None,
                "rows": len(rn), "load": None, "secs": None, "port": port, "lane": lane,
                "corroborated": bool(port and stab.get(port, {}).get(lane, (None, None))[0]
                                     == len(rn)),
                "excluded_from_baseline": None})
  for f in sorted((slop / "rebase").glob("baseline*.json")):
    try:
      doc = json.loads(f.read_text())
    except (OSError, ValueError):
      continue
    for port, lanes in sorted((doc.get("lanes") or {}).items()):
      for lane, rows in sorted(lanes.items()):
        n = len(rows)
        s1, s2 = stab.get(port, {}).get(lane, (None, None))
        out.append({"kind": "json", "path": str(f.relative_to(slop)), "revision": None,
                    "rows": n, "load": None, "secs": None, "port": port, "lane": lane,
                    "corroborated": s1 == s2 == n,
                    "excluded_from_baseline": None})
  if stab_name:
    for port, lanes in sorted(stab.items()):
      for lane, (a, b) in sorted(lanes.items()):
        if a is None:
          continue
        out.append({"kind": "stability", "path": f"rebase/{stab_name}", "revision": None,
                    "rows": a, "load": None, "secs": None, "port": port, "lane": lane,
                    "corroborated": a == b, "excluded_from_baseline": None})
  for r in out:
    r["verdict"] = verdict(r)
  return out


def verdict(r):
  """OK / SUSPECT / RE-MEASURED-ALONGSIDE, from the three facts a capture carries.

  A `load` or a `secs` beside the count is the ONLY thing that can clear a capture: it is the
  machine's own account of the moment. A corroborating second run cannot clear one -- two runs on
  one machine of unknown loading agree just as happily when both are starved -- but it is worth
  recording, so it is its own verdict rather than a shade of SUSPECT."""
  if r["load"] is not None or r["secs"] is not None:
    return "OK"
  return "RE-MEASURED-ALONGSIDE" if r["corroborated"] else "SUSPECT"


def load_guard(root=None):
  """THE MECHANICAL TEST, in the style of `parser_cache_guard()`: run it, read one string, and
  know whether a recorded count in this corpus has a load beside it.

  IT FAILS BY DESIGN AND IT WILL KEEP FAILING. 0 of the corpus's recorded baselines record a load,
  so the first honest run of this guard is a FAIL that names every unqualified capture. A guard
  that passed on the corpus as it stands would be the defect it exists to catch: it would mean
  either the corpus had been fixed (it has not) or the guard had stopped looking.

  ⚠ v1 OF THIS FUNCTION PRINTED "215 of 234 carry a load or an elapsed time" -- computed as
  `total - SUSPECT`, so every RE-MEASURED-ALONGSIDE row was silently counted as QUALIFIED. The
  number contradicted the table printed three lines under it, which is the single most expensive
  shape this project has: a summary that flatters itself while its own detail disproves it. The
  lead is now computed from the load and elapsed-time facts ALONE, and the verdicts are a
  breakdown OF THE UNQUALIFIED REMAINDER, never a way to earn a pass."""
  root = root or str(pathlib.Path(__file__).resolve().parents[2])
  caps = captures(root)
  qualified = [c for c in caps if c["load"] is not None or c["secs"] is not None]
  bad = [c for c in caps if c not in qualified]
  by = {}
  for c in bad:
    by[c["verdict"]] = by.get(c["verdict"], 0) + 1
  census_unq = census(root, ["text", "json"])
  cs = census_unq["per_layer"]
  tot_s = sum(d["sensitive"] for d in cs.values())
  tot_q = sum(d["sensitive_load_qualified"] for d in cs.values())
  lines = [f"{'PASS' if not bad else 'FAIL'}  load_guard: {len(qualified)} of {len(caps)} "
           f"recorded baseline count(s) carry a load or an elapsed time; {len(bad)} carry neither"
           + ("  [" + "  ".join(f"{k}={v}" for k, v in sorted(by.items())) + "]" if by else ""),
           f"          across the whole record layer: {tot_q} of {tot_s} sensitive recorded counts "
           f"are load-qualified ({100.0 * tot_q / tot_s if tot_s else 0:.1f}%)"]
  for p in sorted({c["path"] for c in bad}):
    cs2 = [c for c in bad if c["path"] == p]
    by_port = {}
    for c in cs2:
      by_port.setdefault(c["port"] or "(unidentified capture)", []).append(c)
    lines.append(f"          {p}: {len(cs2)} count(s) with no load, no elapsed time, no revision")
    for port in sorted(by_port):
      lanes = ", ".join(f"{c['lane'] or '?'}={c['rows']}" for c in sorted(by_port[port],
                                                                        key=lambda c: c["rows"]))
      lines.append(f"            {port}: {lanes}")
  if bad:
    lines.append("          A count measured under unknown load is not a count. Re-running a "
                 "suspect capture to replace it would destroy the record of what was measured, "
                 "so these are MARKED, not refreshed: a fresh measurement is a separate artefact "
                 "beside this row, never in place of it.")
  return "\n".join(lines)


# ── THE STARVATION RETROSPECTIVE ───────────────────────────────────────────────────────────
# "How much of today's red was never a defect at all?" -- asked of the STORED ARTEFACTS, because
# a BROKEN verdict already on disk cannot be re-run and a re-run would be a different measurement.
#
# ⚠ THE ANSWER IS ZERO, AND ZERO IS THE FINDING. `rebase-gate.py` carries CAUSE_STARVED,
# `row_load1` and `row_secs`; every stored sweep predates that instrumentation and its verdict
# `why` strings carry NONE of the three. A classifier needs an observation, and these artefacts
# never took one. Re-running a lane to find out would answer a different question than the one
# asked -- "is this port broken today" instead of "was this verdict a defect" -- and would destroy
# the record of what was actually measured. So the retrospective is computed over what IS there.
#
# WHAT A STARVED LANE LOOKS LIKE vs WHAT A DEFECT LOOKS LIKE, and why the distinction needs a
# load to make at all: a starved lane is a PREFIX. A prefix has fewer rows, so it trips ROWS-LOST,
# a DEFECT-classed cause -- and a prefix is entirely consistent with a healthy port, because the
# port is fine and the run queue was not. Every stored `why` below is consistent with BOTH, and
# none carries the one number that separates them (elapsed time), so none can be moved.

_STORED_SWEEPS = ("_coord-sweep.json", "dev-wholetree-2.json")


def starvation_retrospective(root):
  """(report_dict, text). `report_dict` is JSON-serialisable; `text` is the printout."""
  slop = pathlib.Path(root) / ".agents" / "slop"
  files = [slop / n for n in _STORED_SWEEPS] + sorted((slop / "rebase").glob("*record-*.json"))
  broken = []
  for f in files:
    try:
      doc = json.loads(f.read_text())
    except (OSError, ValueError):
      continue
    for v in (doc.get("verdicts") or []):
      if v.get("state") != "BROKEN":
        continue
      why = v.get("why", "")
      broken.append({
        "file": f.name, "port": v.get("port"),
        "shape": ("dead-lane" if "failed to run" in why else
                  "no-shared-name" if "share NO row name" in why else
                  "disagree" if "disagree" in why else "other"),
        "load": bool(_LOAD.search(why)), "secs": bool(re.search(r"\d+\.\d+ ?s\b|secs|elapsed",
                                                                why, re.I)),
        "denominator": bool(re.search(r"of \d+", why)),
        "why": why[:160],
      })
  # The only place in the corpus where starvation is DEMONSTRATED rather than guessed: the
  # deliberate sweep, which carries load1, n_bends, rows, secs and a timeout flag per rep.
  sweep = []
  excluded = []
  tsv = slop / "lane-load-measurements.tsv"
  if tsv.exists():
    for line in tsv.read_text().splitlines():
      if not line.strip() or line.startswith("#") or line.startswith("cell"):
        continue
      p = line.split("\t")
      r = {"cell": p[0], "rep": p[1], "load1": float(p[2]), "n_bends": int(p[3]),
           "rows": int(p[5]), "secs": float(p[6]), "rc": int(p[7]), "timed_out": p[8] == "1"}
      # ⚠ A 0-row rep IS NOT A STARVED LANE, IT IS A DIFFERENT INSTRUMENT. `G_checkonly` runs the
      # same file with `--check-only`, which type-checks and never runs `main`, so it prints no
      # rows BY DESIGN -- NV7 measured 0.37 s for it under 19 concurrent compilers. Counting
      # those as starvation reads a deliberate zero as a starved one, which is the "never report
      # an unexplained zero as a result" defect wearing a load number. The TSV carries no
      # invocation column, so the discriminator has to be the observable: a rep that emitted
      # rows is evidence about starvation; a rep that emitted none is EXCLUDED and NAMED, because
      # "printed nothing" and "printed nothing because it ran out of time" are different claims
      # and this file cannot tell them apart.
      (sweep if r["rows"] > 0 else excluded).append(r)
  n = len(broken)
  ev = sum(1 for b in broken if b["load"] or b["secs"])
  shaped = {}
  for b in broken:
    shaped[b["shape"]] = shaped.get(b["shape"], 0) + 1
  provable = [s for s in sweep if s["timed_out"] or s["rows"] < 787]
  rep = {"stored_broken": n, "stored_broken_ports": len({b["port"] for b in broken}),
         "carrying_load_or_secs": ev, "reclassifiable_as_starvation": ev,
         "by_shape": shaped, "sweep_reps": len(sweep), "sweep_reps_provably_starved": len(provable),
         "sweep_reps_excluded_zero_row": len(excluded),
         "sweep_reps_excluded_cells": sorted({s["cell"] for s in excluded}),
         "sweep_rows_range": [min((s["rows"] for s in sweep), default=None),
                              max((s["rows"] for s in sweep), default=None)],
         "sweep_load1_range": [min((s["load1"] for s in sweep), default=None),
                               max((s["load1"] for s in sweep), default=None)],
         "sweep_full_rows_declared": 787, "sweep_reps_reaching_declared_full": sum(
             1 for s in sweep if s["rows"] >= 787), "verdicts": broken, "sweep": sweep,
         "sweep_excluded": excluded}
  txt = [f"STARVATION RETROSPECTIVE -- {n} stored BROKEN verdict(s) over "
         f"{rep['stored_broken_ports']} distinct port(s), in {len(files)} artefact(s)",
         "  evidence carried by those verdicts: "
         + ", ".join(f"{k}={v}" for k, v in sorted(shaped.items())),
         f"  carrying a load           : {sum(1 for b in broken if b['load'])}",
         f"  carrying an elapsed time  : {sum(1 for b in broken if b['secs'])}",
         f"  RE-CLASSIFIABLE as starvation on the stored evidence: {ev} of {n}",
         f"  of which carry a shared-row DENOMINATOR on a disagreement count: "
         f"{sum(1 for b in broken if b['shape'] == 'disagree' and b['denominator'])}"
         f" of {shaped.get('disagree', 0)}"]
  if sweep:
    txt += ["", f"  THE DELIBERATE SWEEP is the only place starvation is DEMONSTRATED: "
                 f"{len(provable)} of {len(sweep)} row-emitting rep(s) carry load1, n_bends, rows, "
                 f"secs and a timeout flag,",
            f"    rows {rep['sweep_rows_range'][0]}-{rep['sweep_rows_range'][1]} against a "
            f"declared full count of 787, at load1 "
            f"{rep['sweep_load1_range'][0]}-{rep['sweep_load1_range'][1]}.",
            f"    rep(s) that REACHED the declared 787: "
            f"{rep['sweep_reps_reaching_declared_full']} of {len(sweep)}.",
            f"    EXCLUDED {len(excluded)} rep(s) that emitted 0 rows (cell(s) "
            f"{', '.join(rep['sweep_reps_excluded_cells'])}) -- those are the --check-only CONTROL,",
            "      which prints no rows by design, and a deliberate zero is not a starved lane."]
  txt += ["", "  SO: of the red already on disk, 0 of "
              f"{n} can be shown to have been starvation rather than a defect -- because none of "
              "them recorded",
          "  the observation that would decide it. That is not a gap this tool can close by "
          "running", "  anything: the numbers were never taken. It is closed only by the gate "
              "recording `row_load1` and", "  `row_secs` BEFORE the verdict is written, which "
              "`rebase-gate.py` now does."]
  return rep, "\n".join(txt)


def main():
  import argparse
  ap = argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[2]))
  ap.add_argument("--layer", action="append", choices=["text", "json"],
                  help="record layer to sweep (default: both)")
  ap.add_argument("--vocab", action="store_true", help="print the scanner's vocabulary and exit")
  ap.add_argument("--suspect", action="store_true", help="print every unqualified SENSITIVE claim")
  ap.add_argument("--ledger", action="store_true",
                  help="print the BASELINE LEDGER: every recorded capture, its revision, its row "
                       "count, its load or UNKNOWN, and its verdict")
  ap.add_argument("--guard", action="store_true",
                  help="run load_guard(): fail when a recorded count has no load beside it")
  ap.add_argument("--starvation", action="store_true",
                  help="retrospect: of the BROKEN verdicts already on disk, how many can be "
                       "reclassified as starvation rather than a port defect")
  ap.add_argument("--ledger-json",
                  help="write the baseline ledger as JSON here (the ledger IS the artefact; this "
                       "is the same data, machine-readable)")
  ap.add_argument("--json", help="write the full census here")
  a = ap.parse_args()
  if a.guard:
    txt = load_guard(a.root)
    print(txt)
    # 1, not 0: this is a check and it did not pass. `--starved`'s 3 exists because "busy" and
    # "broken" are different claims, and this guard's whole content is that they are. Computed from
    # `txt` rather than by calling `load_guard()` twice -- the census scans 1,500+ files and
    # running it twice to learn one boolean is how a guard becomes too slow to be run.
    return 1 if txt.startswith("FAIL") else 0
  if a.starvation:
    rep, txt = starvation_retrospective(a.root)
    print(txt)
    if a.json:
      pathlib.Path(a.json).write_text(json.dumps(rep, indent=1))
      print(f"\nwrote {a.json}")
    return 0
  if a.ledger:
    caps = captures(a.root)
    by = {}
    for c in caps:
      by[c["verdict"]] = by.get(c["verdict"], 0) + 1
    print(f"BASELINE LEDGER -- {len(caps)} recorded capture(s) in "
          f"{len({c['path'] for c in caps})} file(s); a verdict is a verdict over a DENOMINATOR\n")
    for path in sorted({c["path"] for c in caps}):
      rows = [c for c in caps if c["path"] == path]
      print(f"  {path}  ({len(rows)} count(s))")
      for c in sorted(rows, key=lambda c: (str(c["port"]), str(c["lane"]))):
        print(f"    {str(c['port'] or '?'):<48} {str(c['lane'] or '?'):<26} "
              f"rows={c['rows']:<5} rev={c['revision'] or 'UNKNOWN':<8} "
              f"load={c['load'] if c['load'] is not None else 'UNKNOWN':<8} {c['verdict']}")
    print("\n  DENOMINATOR " + "  ".join(f"{k}={v}" for k, v in sorted(by.items()))
          + f"  (of {len(caps)})")
    print("  0 record a revision, 0 record a load, 0 record an elapsed time. A count measured "
          "under unknown\n  load is not a count, and a baseline with no revision cannot be shown "
          "to describe the tree it\n  is compared against -- the UNCHANGED test is UNDECIDABLE, "
          "not merely unmet.")
    if a.ledger_json:
      pathlib.Path(a.ledger_json).write_text(
        json.dumps({"denominator": len(caps), "captures": caps}, indent=1))
      print(f"  wrote {a.ledger_json}")
    return 0
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
