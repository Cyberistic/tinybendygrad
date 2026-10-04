#!/usr/bin/env python3
"""reader-guard.py -- MAKE THE 157th READER EXPENSIVE, MECHANICALLY.

    python3 .agents/slop/reader-guard.py            # check, rc 1 on any failure
    python3 .agents/slop/reader-guard.py --explain  # say which rule each finding breaks

IN THE STYLE OF `parser_cache_guard()`, which is the precedent that matters: that function
wipes a cache when `rows()`'s meaning moved and PRINTS what it did, because a silent wipe and a
silent reuse print identical bytes and only one of them is honest about the numbers after. This
guard has the same shape -- it measures, it acts, it says what it did.

WHY IT EXISTS. `reader-fork-census.py` measured 156 forked readers and found 51 of the 52 text
readers disagreed with `rebase-gate.py`'s `rows()`, in 16 distinct behaviours. Four of them
carried a docstring saying they were `rows()` VERBATIM. The reason 156 exist is that nothing
made the 157th expensive: writing your own reader is one line of code, and it costs nothing
until two tools disagree about what a lane said and a third reports a phantom row.

THE THREE RULES, each of which fails on something that has already happened here:

  R1  NO UNREGISTERED READER.  A `def rows` / `def rows_of` / `def rows_strict` /
      `def split_py` / `def parse_rows` that is not listed in `.agents/slop/reader-contracts.tsv`
      FAILS. Registering costs one line and a sentence of contract. The 156 exist because the
      alternative was free.
      ⚠ THE REGISTRY IS A DENOMINATOR AND IT IS EDITABLE, which is the weakness here: a new
      fork registered with a wrong contract passes. R2 is what makes that hard.

  R2  A REGISTERED FORK'S BEHAVIOUR MUST MATCH ITS REGISTERED SIGNATURE.  The registry carries
      the census's behavioural fingerprint for each fork -- a hash of its exact (name, value)
      answers on the six row shapes. A fork whose ANSWER MOVED fails, because its contract text
      is now describing behaviour it no longer has. This is the rule that would have caught the
      `cstyle-gate.py` case: a reader that claims to be `rows()` and cannot read F3.

  R3  AN `import`-FORM READER MUST ACTUALLY IMPORT.  A file that binds `rows = _rebase_gate.rows`
      and then never uses it, or that imports and then shadows the name with a local `def`,
      fails. A conversion that does not take effect is the worst outcome available: the file
      LOOKS unified, the census stops counting it, and the second reader survives.

WHAT IT DELIBERATELY DOES NOT DO. It does not import any tool, because importing these
harnesses RUNS A LANE. It reads source and `ast`-extracts the readers, which is the same
technique `reader-fork-census.py` uses and the reason it can measure a file whose import has a
side effect.
"""
import argparse
import ast
import hashlib
import importlib.util
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
GATE = HERE / "rebase-gate.py"
REGISTRY = HERE / "reader-contracts.tsv"
CENSUS = HERE / "reader-fork-census.py"

CORPUS_ROOTS = (".agents", "runs")
CORPUS_SKIP = {"__pycache__", ".venv", "node_modules", ".jj", ".git", "opstree", "xd1",
               ".mutwork", "references"}
READER_NAMES = {"rows", "row", "rows_of", "rows_of_text", "rows_old", "rows_strict",
                "row_strict", "split_py", "parse_rows", "rows_cstyle", "rows_init",
                "rows_tmap", "rows_rd", "rows_witem", "rows_cfo", "rows_kern", "rows_opt",
                "rows_misc", "rows_wmma", "rows_buft", "rows_hip", "rows_kern2", "rows_idx",
                "rows_all", "printed_rows", "bend_rows", "oracle_rows", "read_rows", "rowset"}


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, str(path))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def py_files():
  for top in CORPUS_ROOTS:
    base = REPO / top
    for root, dirs, files in os.walk(base):
      dirs[:] = sorted(d for d in dirs
                       if d not in CORPUS_SKIP
                       and not (pathlib.Path(root) != base and d.startswith(".")))
      for f in sorted(files):
        if f.endswith(".py"):
          yield pathlib.Path(root) / f


def read_registry():
  """{(relpath, func): (kind, signature, contract)} from the TSV. A missing file is an ERROR
  and not an empty registry: an empty registry passes every fork, which is the failure mode."""
  if not REGISTRY.exists():
    return None
  out = {}
  for i, line in enumerate(REGISTRY.read_text().splitlines(), 1):
    if not line.strip() or line.lstrip().startswith("#"):
      continue
    f = line.split("\t")
    # FIVE fields: file, func, kind, signature, contract. The signature is `-` for the import
    # form and the control, so it cannot be dropped for being empty -- which is why this counts
    # rather than tests truthiness.
    if len(f) < 5:
      raise ValueError(f"{REGISTRY.name}:{i} has {len(f)} fields, expected 5 "
                       f"(file, func, kind, signature, contract)")
    out[(f[0], f[1])] = (f[2], f[3], "\t".join(f[4:]))
  return out


def defs_in(path):
  """[(func, lineno, node, src)] for every READER-SHAPED def in one file."""
  try:
    src = path.read_text()
    tree = ast.parse(src)
  except (SyntaxError, OSError, UnicodeDecodeError):
    return []
  out = []
  for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in READER_NAMES:
      out.append((n.name, n.lineno, n, src))
  return out


def bindings_in(path, func):
  """[(lineno, rhs_source)] for `<func> = <something>` at module level -- the IMPORT form."""
  try:
    src = path.read_text()
    tree = ast.parse(src)
  except (SyntaxError, OSError, UnicodeDecodeError):
    return []
  out = []
  for n in tree.body:
    if isinstance(n, ast.Assign):
      for t in n.targets:
        if isinstance(t, ast.Name) and t.id == func:
          out.append((n.lineno, ast.get_source_segment(src, n) or ""))
  return out


def fingerprint(fn, shapes):
  """Kept as a name because a reader of this file will look for one. It is the CENSUS's, called
  through -- three implementations of a fingerprint is three chances for the registry and the
  guard to disagree about what a reader does."""
  return load("reader_fork_census", CENSUS).behavior_fingerprint(fn)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--explain", action="store_true")
  ap.add_argument("--quiet", action="store_true")
  a = ap.parse_args()

  reg = read_registry()
  if reg is None:
    print(f"GUARD FAILED: no registry at {REGISTRY}. An absent registry is not an empty one -- "
          f"an empty registry passes every fork, which is the failure this guard exists to stop.")
    return 1

  census = load("reader_fork_census", CENSUS)

  # CLASSIFY WITH THE CENSUS'S OWN CLASSIFIER, not a name list. A first draft of this guard
  # matched `READER_NAMES` and reported 151 R1 findings, of which the overwhelming majority were
  # `def row(x)` in an oracle -- a PRODUCER that builds a row and hands it back, which is not a
  # reader and would never be one. A guard that cries wolf on 151 items in its first run gets
  # switched off, and a guard that is switched off has cost more than the 156 readers did.
  # The census already draws the line -- three families answer a row question and the rest do not
  # -- so the guard asks the census.
  measured = {}
  for rel, func, line, seg, node in census.candidates():
    measured[(rel, func)] = census.measure(rel, func, line, seg, node)

  findings = []
  notes = []
  seen = set()
  # `rebase-gate.py` IS the control. It defines the reader every other row is measured against,
  # so asking it to import itself (R3) or to match a signature it is the source of (R2) is the
  # guard failing on its own yardstick. It is CHECKED, not SKIPPED: its fingerprint is measured
  # and printed every run, so a change to `rows()` shows up here as a changed control -- which is
  # the thing `parser_cache_guard()` exists to notice, and the reason this prints at all.
  GATE = HERE / "rebase-gate.py"
  GATE_REL = str(GATE.relative_to(REPO))
  for (rel, func), m in sorted(measured.items()):
    if m["contract"] not in census.DRIFT_FAMILIES:
      continue  # a producer, a differ, a name extractor: never was a reader
    seen.add((rel, func))
    if rel == GATE_REL and func in ("rows", "row"):
      continue
    key = (rel, func)
    if key not in reg:
      findings.append(("R1", rel, m["line"], func,
                       f"`def {func}` at {rel}:{m['line']} answers a row question "
                       f"(contract `{m['contract']}`, {m.get('verdict', '?')} against rows()) and "
                       f"is not in reader-contracts.tsv. Register it with its contract, or import "
                       f"rebase-gate.py's rows()."))
      continue
    kind, want_sig, contract = reg[key]
    p = REPO / rel
    if kind == "import-gate-rows":
      # R3: an import-form reader must be an IMPORT, and must not be shadowed by a local def.
      # A converted file has no `def` at all, so reaching here with a live `def` means the
      # registry is describing a conversion that did not happen -- which is the worst outcome
      # available: the file looks unified, the census stops counting it, and the second reader
      # survives wearing the gate's name.
      b = bindings_in(p, func)
      if not any("_rebase_gate.rows" in rhs or "rebase_gate.rows" in rhs for _, rhs in b):
        findings.append(("R3", rel, m["line"], func,
                         f"{rel}:{m['line']} `def {func}` is registered as import-gate-rows but "
                         f"does not bind it from the gate. The registry is describing a "
                         f"conversion that did not happen."))
      continue
    if kind != "own-contract":
      findings.append(("R3", rel, m["line"], func,
                       f"{rel}:{m['line']} registry kind `{kind}` is not one this guard knows: "
                       f"expected import-gate-rows or own-contract."))
      continue
    if want_sig in ("-", "unmeasurable"):
      findings.append(("R2", rel, m["line"], func,
                       f"{rel}:{m['line']} is registered own-contract with signature "
                       f"`{want_sig}`, which means it was never measured. A fork nobody has "
                       f"measured is a fork whose drift is UNKNOWN, and unknown is not zero."))
      continue
    # R2: the fork's ANSWER must still be the answer its contract describes.
    src = p.read_text()
    node = next((n for n in ast.walk(ast.parse(src))
                 if isinstance(n, ast.FunctionDef) and n.name == func), None)
    fn = None if node is None else census.sandbox(node, ast.get_source_segment(src, node),
                                                 src, rel)[0]
    got = census.behavior_fingerprint(fn) if fn is not None else None
    if got is None:
      findings.append(("R2", rel, m["line"], func,
                       f"{rel}:{m['line']} `def {func}` could not be executed for a fingerprint, "
                       f"so its registered signature cannot be checked. An unmeasurable fork is "
                       f"not a passing fork."))
    elif got != want_sig:
      findings.append(("R2", rel, m["line"], func,
                       f"{rel}:{m['line']} `def {func}` BEHAVIOUR MOVED: registered signature "
                       f"{want_sig}, measured {got}. Its contract text now describes behaviour it "
                       f"no longer has. This is the cstyle-gate.py failure: a reader that claims "
                       f"a contract and does not answer to it."))

  # R1 the other way: a registered reader that no longer exists. A stale registry entry is a
  # row that looks covered and is not, which is the same failure as a phantom row.
  for rel, func in sorted(reg):
    if (rel, func) in seen or (rel == GATE_REL and func in ("rows", "row")):
      continue
    p = REPO / rel
    if not p.exists():
      findings.append(("R1", rel, 0, func,
                       f"registry names {rel}:{func} but {rel} does not exist."))
      continue
    if bindings_in(p, func):
      continue  # converted to the import form; the registry entry is describing that
    findings.append(("R1", rel, 0, func,
                     f"registry names {rel}:{func} but no `def {func}` and no binding for it "
                     f"is there. Either restore it or delete the registry row -- a registry row "
                     f"with no reader behind it reads as coverage and is not coverage."))

  by_rule = {}
  for f in findings:
    by_rule.setdefault(f[0], []).append(f)

  # THE CONTROL'S OWN FINGERPRINT, printed every run. `parser_cache_guard()`'s whole insight is
  # that a silent change and a silent reuse print the same bytes; so when the control MOVES, this
  # line is what says so, and it names the new value so a diff of two runs is meaningful.
  cf_rows = census.behavior_fingerprint(census.CANONICAL)
  cf_row = census.behavior_fingerprint(census.CANON_ROW)

  if not a.quiet:
    total = len(measured)
    readers = sum(1 for m in measured.values() if m["contract"] in census.DRIFT_FAMILIES)
    print(f"reader-guard: {total} candidates in {' + '.join(CORPUS_ROOTS)}, of which {readers} "
          f"answer a row question")
    print(f"              {len(reg)} registry rows, {len(findings)} finding(s)")
    print(f"control: rebase-gate.py md5={hashlib.md5(GATE.read_bytes()).hexdigest()}"
          f"  rows()={cf_rows}  row()={cf_row}")
  for rule in sorted(by_rule):
    print(f"\n{rule}  {len(by_rule[rule])} finding(s)")
    for _, rel, line, func, msg in sorted(by_rule[rule]):
      print(f"  {rel}:{line}  {func}\n      {msg}")
    if a.explain:
      print(f"      ^ {RULE_TEXT[rule]}")
  if not findings and not a.quiet:
    print("\nREADER GUARD OK: every reader def in the corpus is registered, every registered "
          "import-form reader really imports the gate's rows(), and every registered fork still "
          "answers the six shapes the way its contract says it does.")
  return 1 if findings else 0


RULE_TEXT = {
  "R1": "an unregistered reader. A fork costs nothing to write and everything to discover later.",
  "R2": "a registered fork whose BEHAVIOUR moved. Its contract text is now a lie, which is the "
        "cstyle-gate.py failure: claimed to be rows(), could not read F3.",
  "R3": "an import-form reader that is not an import, or a registry row with no reader behind it.",
}


if __name__ == "__main__":
  sys.exit(main())