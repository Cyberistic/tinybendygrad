#!/usr/bin/env python3
"""reader-registry.py -- BUILD `.agents/slop/reader-contracts.tsv` FROM A MEASUREMENT.

    python3 .agents/slop/reader-registry.py --write   # regenerate the registry
    python3 .agents/slop/reader-registry.py           # print it, change nothing

A registry is only worth something if its rows are FACTS rather than intentions, so every row
carries a behavioural fingerprint -- the census's hash of the reader's exact (name, value) answers
on the six row shapes -- and `reader-guard.py` re-measures it. A fork whose answer moves fails,
because its contract text is then describing behaviour it no longer has.

ONLY READERS THAT ANSWER A ROW QUESTION GET A ROW. The census classifies every candidate by
contract, and a `row_names()` in an oracle or a `bend_rows()` in a gate wrapper is not a reader:
it is a producer, a differ, or a name extractor. Putting those in the registry would inflate the
denominator with 200 rows that describe nothing, which is the mistake the 156-count itself was.

THE `own-contract` COLUMN IS WHERE THE DRIFTS GET TO EXPLAIN THEMSELVES. A row may only say
"own contract" with a sentence saying WHAT the contract is. That is the line the brief draws
between a fork with a stated contract, which is acceptable, and a fork that claims to be the
same reader, which is not.
"""
import argparse
import ast
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
REGISTRY = HERE / "reader-contracts.tsv"

# Loaded by PATH: `reader-fork-census.py` has a hyphen and cannot be imported by name. Loading
# the census rather than copying its shapes and its sandbox is the discipline this is about.
_spec = importlib.util.spec_from_file_location("reader_fork_census",
                                                str(HERE / "reader-fork-census.py"))
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

# ── THE CONTRACTS. Keys are bare filenames as they appear under `.agents/slop/`, or
# `tools/name.py`. Every one of these was read out of the fork's own docstring and call sites.
CONTRACTS = {
  # ── PARITY READERS WITH A GENUINELY DIFFERENT CONTRACT. Not candidates for substitution, and
  # cannot be, because they read something `rows()` deliberately does not.
  ("cstyle-gate.py", "rows_strict"):
    "PARITY reader. Demands ` = [` and a closing `]`, so it CANNOT read F3 (two-space) rows at "
    "all -- measured by cstyle-shapes-selftest.py: 0 rows on F3 where rows() reads 1, and 0 on "
    "F1 too. Returns (mapping, shreds, dups) so a DUPLICATE is reported rather than silently "
    "overwritten, which rows() cannot do. Substituting rows() here would turn cstyle.bend's 227 "
    "rows into a different comparison entirely -- 225 of them BROKEN.",
  ("cstyle-gate.py", "row_strict"):
    "PER-LINE half of the parity reader above: one line in, one answer out. rows() is a "
    "whole-TEXT reader and cannot be decomposed into it.",
  ("cstyle-gate.py", "split_py"):
    "INVERSE FOLD. rows() returns `left` with the `]   py=[` tail folded away; split_py reads "
    "that tail back OUT of a value. Its input is a VALUE, not a line, and the two are not "
    "interchangeable in either direction. This is the fork-with-a-stated-contract the brief "
    "names: rows() cannot be substituted for it, and it cannot be substituted for rows().",
  ("cs-fixpy.py", "rows_strict"):
    "PARITY reader, byte-for-byte the F2 subset of cstyle-gate.py's. Kept as its own copy "
    "because it WRITES rows back into a .bend file: its own docstring records that a "
    "one-character off-by-one there once turned blockIdx.x into lockIdx.x. A writer needs its "
    "own asserted reader; a reader borrowed from a verifier is a writer trusting a paraphrase.",

  # ── FORMAT-SPECIFIC. The lane is not the shared `name=value` format at all.
  ("multi-mutate.py", "rows"):
    "FORMAT-SPECIFIC: matches `(t_\\w+)=(-?\\d+)` and casts the value to INT. A lane of ints is "
    "not a lane of strings; rows() would keep '7' where this returns 7, and a mutation count "
    "computed on the wrong type is a wrong number rather than a failed one.",
  ("mm-mutate.py", "rows"):
    "FORMAT-SPECIFIC: matches `^(mm_\\S+) (.*)$` -- an mm_ NAME, a SPACE, the value. This is the "
    "F3 shape and ONLY the F3 shape; there is no `=` anywhere in it, so rows() reads NONE of "
    "its rows. Measured: 1 row where rows() reads 0.",
  ("wire_parse.py", "rows"):
    "FORMAT-SPECIFIC: `name = value` first, then `name=value`, by regex, skipping `#` comments. "
    "It deliberately ACCEPTS the spaced form that rows() reads as F3, with a different value -- "
    "the regex captures after the space, rows() takes the tail -- and drops comments rows() "
    "keeps. Measured: it reads a row on F2 where rows() reads the same NAME with a different "
    "VALUE, which is the one comparison direction this project has paid for six times.",

  # ── LANE-OWNERSHIP. Keeps rows the shared reader would drop, on purpose, with the reason.
  ("ops-mutate.py", "rows_of"):
    "LANE-OWNERSHIP: keys on the name but STORES THE WHOLE LINE, and deliberately KEEPS every "
    "`#shared_axis_*` row -- its own docstring records that skipping `#` lines silently removed "
    "four GATED rows and made four mutations look like they moved three. It also drops "
    "`#shared_tree` and `#bend_only*`, so its `#` policy is lane-specific and not the gate's.",
  ("bnxt_mutate.py", "rows_of"):
    "MULTI-VALUE: a dict of SETS, so a name printed twice keeps BOTH answers, and a line with "
    "no `=` becomes the row `#<the line>` rather than being dropped. Measured: its F3 row is "
    "named `#ctlf3  half` with an EMPTY value where rows() reads no row at all.",
  ("bnxt_sweep.py", "rows_of"):
    "MULTI-VALUE, same contract as bnxt_mutate.py's: dict of SETS and `#<line>` rows for lines "
    "with no `=`. A separate tool from that one and never meant to be the shared reader.",
  ("nv-diff.py", "rows_of"):
    "LAST-`=`: rsplit('=', 1) where rows() splits at the FIRST. On F2 this yields the name "
    "`ctl OPENCL sz1 k0 = [half]   py` and the value `[half]` -- a DIFFERENT NAME -- so it "
    "cannot share a single row with a lane read any other way. GUARD 4 compares over shared row "
    "NAMES, so this reader reports zero shared rows and therefore compares NOTHING.",
  ("nv_ip_mutate.py", "rows_of"):
    "PROSE-EATING: reads EVERY line, not just lines with `=`, so a single-space prose line and a "
    "TAB line both become rows with an EMPTY value. Measured: it reads 1 row on F5 and 1 on F6 "
    "where rows() reads 0, and its F3 row name is the whole line rather than the first token.",
  ("dd-band-mut.py", "rows"):
    "STRIPPING: keeps a row whose NAME is a `#` comment (`# c` -> 3) and does not strip the "
    "name or the value, so it reads a different STRING on F2 than rows() does. A lane of "
    "unstripped names and stripped names does not intersect.",
  ("mop-mut.py", "rows"): None,
  ("ext_mutate.py", "rows_of"): None,

  # ── DELIBERATE COMPARISONS. The fork IS the measurement.
  ("rows-blast.py", "rows_old"):
    "THE CONTROL ITSELF. rows-blast.py exists to measure the blast radius of CHANGING rows(), "
    "so it needs the OLD parser to compare against and cannot import the new one -- its own "
    "docstring says so in as many words. A copy is the instrument here, not an accident, and "
    "converting it would delete the measurement.",
  ("formblind-audit.py", "rows_pre_f3"):
    "AUDIT VARIANT: the reader BEFORE the F3 arm existed. formblind-audit.py exists to compare "
    "readers against each other, so each of its variants is a labelled experiment and none of "
    "them is trying to be the shipped reader.",
  ("formblind-audit.py", "rows_name_must_be_one_token"):
    "AUDIT VARIANT: rows()'s F3 arm with the single-token name rule ENFORCED. That rule is the "
    "arm rows() lost in a previous refactor, kept here so it cannot be dropped a second time.",
  ("formblind-audit.py", "rows_eq_then_gap_greedy"):
    "AUDIT VARIANT: tries `=` first and falls back to the gap GREEDILY. A deliberately worse "
    "reader, kept to show what greedy costs.",
  ("formblind-audit.py", "rows_eq_or_gap_no_tab"):
    "AUDIT VARIANT: accepts `=` OR a gap and rejects TAB explicitly, to isolate what the no-TAB "
    "rule alone is worth.",
  ("formblind-audit.py", "rows_fold_at_first_tail"):
    "AUDIT VARIANT: folds at the FIRST `]   py=[` where rows() uses rfind. A value's own bracket "
    "can precede the boundary, so this cuts values in half; kept as the counterexample.",

  # ── LINE FILTERS. A list of whole lines, with the split left to the caller.
  ("amdev_mutate.py", "rows"):
    "A LINE FILTER: returns the whole `name=value` LINES and leaves the split to its caller, so "
    "its output is a list of strings rather than a mapping. Delegating the split is its shape, "
    "and it is not substitutable for rows() -- the caller splits, and may split differently.",
  ("memory-mutate.py", "rows_of"):
    "A LINE FILTER, same contract as amdev_mutate.py's: returns whole lines. Measured: on F1 it "
    "agrees with rows() once the caller splits, and on F2 it hands over a line rows() would have "
    "folded -- so the difference moves to the call site rather than going away.",

  # ── RUNNERS.
  ("table-pin.py", "rowset"):
    "A RUNNER: reads a table file and returns (rows, something), not a row mapping. Registered "
    "so the guard does not read it as an unregistered fork.",
  ("blob-rows.py", "rows_of"):
    "A RUNNER: runs a lane twice to prove the lane is STABLE and returns (rows, stderr). The "
    "stability check is its contract; rows() has no such notion and cannot stand in for it.",
}

# Every reader that IS the gate's rows(), imported. Kept as data so R3 has something to check.
IMPORTS = {
  "ga_controls.py": "rows", "ga_rows_blast.py": "rows", "pin-tree-oracle.py": "rows",
  "rebase-oracle-ops.py": "rows", "ga_rows.py": "rows", "rebase-break.py": "rows",
  "rebase-shadow.py": "rows", "commute-detect.py": "rows_of", "ops-python-mutate.py": "rows_of",
  "helpers-tc-mutate.py": "rows", "mt_diff.py": "rows", "mop-mut.py": "rows",
  "debug-mutate.py": "rows_of", "ext_mutate.py": "rows_of_text", "mutate.py": "rows",
  "dtype-pri-mutate.py": "rows_of", "tools/mutate-dm.py": "rows",
  "tools/mutate-allreduce.py": "rows", "tools/mutate-memory.py": "rows",
  "dd-band-paddiff.py": "rows",  # already unified before this census
}

DROP = {("mop-mut.py", "rows"), ("ext_mutate.py", "rows_of")}  # both converted; see IMPORTS


def fingerprint(fn):
  """Kept as a name because a reader of this file will look for one. It is the census's."""
  return C.behavior_fingerprint(fn)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--write", action="store_true")
  a = ap.parse_args()

  # MEASURE first, with the census's own classifier, so the registry contains readers and only
  # readers. `measure()` is the census's; calling it is not restating it.
  cands = C.candidates()
  measured = {}
  for rel, func, line, seg, node in cands:
    measured[(rel, func)] = C.measure(rel, func, line, seg, node)

  # FIVE fields per row: file, func, kind, signature, contract. `kind` is `import-gate-rows` or
  # `own-contract` and nothing else -- reader-guard.py REJECTS any other value, so a row cannot
  # quietly acquire a kind it has never been checked against. The provenance label (control /
  # import / fork) belongs in the contract text, where it is prose rather than a machine field.
  rows = []
  rows.append((".agents/slop/rebase-gate.py", "rows", "import-gate-rows", "-",
               "THE CONTROL: the one reader. Every other row here is measured against it. The "
               "signature is `-` on purpose -- an imported reader moves when the GATE moves, and "
               "pinning it would make one improvement look like 19 simultaneous regressions in 19 "
               "files."))
  rows.append((".agents/slop/rebase-gate.py", "row", "own-contract", "control",
               "THE PER-LINE READER rows() is built on. Returns (name, left, right) or None; "
               "`right` is the `py=` column and is deliberately NOT the compared column."))

  forked = uncontracted = 0
  for (rel, func), m in sorted(measured.items()):
    if rel.endswith(".agents/slop/rebase-gate.py") and func in ("rows", "row"):
      continue
    bare = rel.split(".agents/slop/", 1)[-1]
    if m["contract"] not in C.DRIFT_FAMILIES:
      continue  # a producer, a differ, a name extractor: not a row reader
    if bare in IMPORTS and IMPORTS[bare] == func:
      rows.append((rel, func, "import-gate-rows", "-",
                   "IMPORT FORM: binds rebase-gate.py's rows() by path. No second parser, so "
                   "there is exactly one answer to \"what does this lane's output mean\"."))
      continue
    if (bare, func) in DROP:
      continue
    forked += 1
    p = C.REPO / rel
    src = p.read_text()
    node = next((n for n in ast.walk(ast.parse(src))
                 if isinstance(n, ast.FunctionDef) and n.name == func), None)
    fn = None if node is None else C.sandbox(node, ast.get_source_segment(src, node), src, rel)[0]
    contract = CONTRACTS.get((bare, func))
    if contract is None:
      uncontracted += 1
      contract = ("NO CONTRACT WRITTEN YET. Measured divergent from rows() -- see the census. "
                  "This row exists so the guard can MEASURE it and fail when its answer moves; "
                  "it is NOT an endorsement, and the next reader here deserves one.")
    rows.append((rel, func, "own-contract", fingerprint_of(m, fn), contract))

  rows.sort()
  out = [
    "# reader-contracts.tsv -- GENERATED by reader-registry.py. Do not hand-edit the signature",
    "# column: reader-guard.py re-measures it, and a hand-written signature is a guard that only",
    "# checks itself.",
    "#",
    "# file\tfunc\tkind\tsignature\tcontract",
    "",
  ]
  for r in rows:
    out.append("\t".join(r))
  text = "\n".join(out) + "\n"
  if a.write:
    REGISTRY.write_text(text)
    print(f"wrote {REGISTRY.relative_to(REPO)}: {len(rows)} rows "
          f"({forked} forks, {uncontracted} with no contract written yet)")
  else:
    sys.stdout.write(text)
  return 0


def fingerprint_of(m, fn):
  """The census's OWN fingerprint function, on the same sandboxed function the census measured.

  A reader the census could not classify -- a RUNNER that does real work -- has NO fingerprint,
  and the registry says `unmeasurable` rather than inventing one. `reader-guard.py` treats that
  token as a FAILURE, which is the point: a registry row whose drift is unknown must not read as
  a registry row whose drift is zero."""
  return C.behavior_fingerprint(fn) if fn is not None else "unmeasurable"


if __name__ == "__main__":
  sys.exit(main())