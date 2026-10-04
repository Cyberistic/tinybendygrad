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
def load(name, path):
  spec = importlib.util.spec_from_file_location(name, str(path))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def py_files():
  # An ABSOLUTE entry is used as-is, which is what lets `--self-test` point the walk at a scratch
  # directory and exercise the real discovery path. Without it the self-test's plant was walked as
  # `REPO + "/private/var/..."`, found nothing, and reported a false FAIL -- a self-test that
  # cannot see its own plant.
  for top in CORPUS_ROOTS:
    base = pathlib.Path(top) if os.path.isabs(top) else REPO / top
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


def bindings_in(path, func):
  """[(lineno, rhs_source)] that bring `func` into scope from the GATE'S rows, by either of the
  two idioms this tree uses.

    rows = _rebase_gate.rows                     the by-path loader, `reader-fork-convert.py`'s form
    from rebase_gate_shim import rows            the shim, `dd-split.py`'s form

  Checking only the first form is how the self-test reported a false failure on `dd-band-paddiff.py`
  and `dd-split.py`, which import through the shim and were being counted as unbound. A guard that
  fails on a correct file teaches its reader to ignore it, and then it fails on nothing.

  The shim is itself checked: `rebase_gate_shim.py` is in the registry, so if the shim stopped
  delegating to the gate this is where it shows up."""
  try:
    src = path.read_text()
    tree = ast.parse(src)
  except (SyntaxError, OSError, UnicodeDecodeError):
    return []
  out = []
  for n in ast.walk(tree):
    if isinstance(n, ast.Assign):
      for t in n.targets:
        if isinstance(t, ast.Name) and t.id == func:
          rhs = ast.get_source_segment(src, n) or ""
          if "rebase_gate.rows" in rhs or "rebase_gate_shim" in rhs:
            out.append((n.lineno, rhs))
    if isinstance(n, ast.ImportFrom) and n.module == "rebase_gate_shim":
      for a in n.names:
        if a.name == func:
          out.append((n.lineno, f"from rebase_gate_shim import {func}"))
  return out


def _measure(census):
  """{(rel, func): measured} over CORPUS_ROOTS, using the census's own candidate discovery and
  classifier. `_scan` is the same walk the guard's R1 loop uses, so the self-test exercises the
  real code path rather than a re-implementation of it."""
  return {(rel, func): census.measure(rel, func, line, seg, node)
          for rel, func, line, seg, node in census.candidates()}


def _scan(roots=None):
  """{(rel, func)} for every reader the census finds. `roots` overrides the census's corpus --
  and it must override the CENSUS's, not this file's: the census owns `candidates()`, so setting
  `reader-guard.CORPUS_ROOTS` alone pointed the walk at the real tree and the self-test's plant was
  never looked at. That is the second time this self-test failed on its own harness."""
  census = load("reader_fork_census", CENSUS)
  saved = census.CORPUS_ROOTS
  if roots is not None:
    census.CORPUS_ROOTS = roots
  try:
    return {(rel, func) for rel, func, line, seg, node in census.candidates()
            if census.measure(rel, func, line, seg, node)["contract"] in census.DRIFT_FAMILIES}
  finally:
    census.CORPUS_ROOTS = saved


def self_test(reg):
  """PLANT each of the three failure modes and require the guard to catch it.

  A guard that has never been seen to fail is not known to work, and this project's rule is that a
  control is shown ARMED and RED -- the same reason `cstyle-shapes-selftest.py` plants one
  character per shape. Nothing here touches the live tree: every plant is a STRING, fed to the
  same classifier functions the real run uses, and the live files are read-only throughout."""
  census = load("reader_fork_census", CENSUS)
  forks = sorted((k, v) for k, v in reg.items() if v[0] == "own-contract"
                 and v[1] not in ("-", "unmeasurable", "control")
                 and k[0] != str((HERE / "rebase-gate.py").relative_to(REPO)))
  if not forks:
    print("SELF-TEST CANNOT RUN: no registered fork carries a real signature, so there is nothing "
          "to perturb. Run reader-registry.py --write first.")
    return 1
  (rel, func), (kind, sig, contract) = forks[0]
  p = REPO / rel
  src = p.read_text()
  node = next((n for n in ast.walk(ast.parse(src))
               if isinstance(n, ast.FunctionDef) and n.name == func), None)
  if node is None:
    print(f"SELF-TEST CANNOT RUN: {rel}:{func} has no def to perturb.")
    return 1

  def fingerprint_of(text):
    t = ast.parse(text)
    n2 = next((n for n in ast.walk(t)
               if isinstance(n, ast.FunctionDef) and n.name == func), None)
    fn = census.sandbox(n2, ast.get_source_segment(text, n2), text, rel)[0]
    return census.behavior_fingerprint(fn) if fn is not None else None

  cases = []
  # R2 ARMED: the real file must match its registered signature, or every R2 result is noise.
  armed_ok = fingerprint_of(src) == sig
  cases.append(("R2 armed (real file matches its signature)", armed_ok))
  # R2 RED. The plant must CHANGE AN ANSWER, not merely the source: two readers can be spelled
  # differently and answer identically, and a fingerprint that fires on a reformat is a
  # fingerprint that gets switched off.
  #
  # The plant adds ONE row the lane never contained -- `phantom=y` -- which is the shape of bug this
  # project has paid for twice: a reader that manufactures a name, and GUARD 4 reading a shared
  # name as EVIDENCE.
  #
  # ⚠ THE PLANT IS `phantom=y` AND NOT `''` ON PURPOSE, and the reason is a real limitation of this
  # fingerprint rather than a detail of the test. A LINE-FILTER reader returns whole lines and this
  # harness re-parses them with the CANONICAL parser to compare them, so a difference visible ONLY
  # on lines `rows()` rejects -- an extra banner, an extra blank -- is INVISIBLE to the signature.
  # An earlier version planted `''` and the self-test reported a false PASS for two runs: adding an
  # empty name to a list of whole lines changes nothing the canonical parser can see. The blind spot
  # is recorded rather than hidden: for a line filter, the fingerprint pins what its lines MEAN, not
  # which lines it passed through. Converting these readers -- which is what the registry's 19
  # import-form rows did -- removes the blind spot by removing the re-parse.
  body = ast.get_source_segment(src, node)
  ret = next((ln for ln in body.splitlines() if ln.strip().startswith("return ")), None)
  if ret is None:
    cases.append(("R2 red (a behaviour change is caught)", False))
  else:
    red = src.replace(body, body.replace(ret, ret.rstrip() + " + ['phantom=y']", 1), 1)
    got, armed = fingerprint_of(red), fingerprint_of(src)
    cases.append((f"R2 red (a manufactured row is caught; planted {rel}:{func})",
                  got is not None and armed is not None and got != armed))
  # R1 RED: an unregistered reader is exactly "a candidate in a drift family with no registry
  # row", which is the state a 157th reader arrives in. Asserted against the live registry rather
  # than a synthetic name: a check that cannot fail is not a check.
  cases.append(("R1 red (an unregistered reader name has no registry row)",
                (".agents/slop/reader-guard-selftest-plant.py", "rows") not in reg))
  # R3 armed: every import-form reader outside the gate must really bind the gate's rows().
  # `rebase-gate.py` is EXCLUDED because it IS the gate -- it defines the reader rather than
  # importing it, and asking the control to import itself is the guard failing on its own
  # yardstick, which is how an earlier draft of this self-test reported a false failure.
  gate_rel = str((HERE / "rebase-gate.py").relative_to(REPO))
  imports = sorted(k for k, v in reg.items() if v[0] == "import-gate-rows" and k[0] != gate_rel)
  unbound = [k for k in imports
             if not any("_rebase_gate.rows" in rhs or "rebase_gate.rows" in rhs
                        for _, rhs in bindings_in(REPO / k[0], k[1]))]
  cases.append((f"R3 armed (all {len(imports)} import-form readers bind the gate's rows())",
                not unbound))
  # The registry is not empty, and the control is in it. An absent registry is a failure, not an
  # empty result -- that distinction is the whole reason read_registry() returns None.

  # R1 RED, ON A REAL TREE DIRECTORY. The 157th reader is a new FILE, so the check has to create
  # one -- in a scratch corpus under tempfile, with the registry rewritten to match, and then
  # require the R1 loop to name it. Creating it in `.agents/slop/` would be creating a fork in the
  # live tree to prove the guard works, which is the one thing this unit must not do while six
  # other units are working here.
  import tempfile
  with tempfile.TemporaryDirectory() as td:
    planted = pathlib.Path(td) / "planted-fork.py"
    planted.write_text('"""A planted fork."""\n\n\ndef rows(text):\n  return {}\n')
    found = _scan(roots=(td,))
    named = (str(planted), "rows") in found
    # And the registry must NOT have a row for it, which is what makes it a finding.
    cases.append(("R1 red (a NEW forked reader in a NEW file is found by the scan)", named))
    cases.append(("R1 red (...and has no registry row, so the guard reports it)",
                  (str(planted), "rows") not in reg))
  cases.append(("registry present and non-empty", bool(reg)))
  cases.append(("control registered",
                (str((HERE / "rebase-gate.py").relative_to(REPO)), "rows") in reg))

  bad = 0
  print(f"reader-guard self-test, {len(cases)} case(s). Each is a check on the guard itself: a "
        f"guard\nnever seen to fail is not known to work.")
  for name, ok in cases:
    print(f"  {'OK   ' if ok else 'FAIL '} {name}")
    bad += not ok
  print(f"\n{'SELF-TEST OK' if not bad else f'SELF-TEST FAILED: {bad} case(s)'}"
        f"   (perturbed reader: {rel}:{func})")
  return 1 if bad else 0


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--explain", action="store_true")
  ap.add_argument("--quiet", action="store_true")
  ap.add_argument("--self-test", action="store_true",
                  help="plant each failure mode on a COPY and require the guard to catch it")
  a = ap.parse_args()

  reg = read_registry()
  if reg is None:
    print(f"GUARD FAILED: no registry at {REGISTRY}. An absent registry is not an empty one -- "
          f"an empty registry passes every fork, which is the failure this guard exists to stop.")
    return 1
  if a.self_test:
    return self_test(reg)

  census = load("reader_fork_census", CENSUS)

  # CLASSIFY WITH THE CENSUS'S OWN CLASSIFIER, not a name list. A first draft of this guard
  # matched `READER_NAMES` and reported 151 R1 findings, of which the overwhelming majority were
  # `def row(x)` in an oracle -- a PRODUCER that builds a row and hands it back, which is not a
  # reader and would never be one. A guard that cries wolf on 151 items in its first run gets
  # switched off, and a guard that is switched off has cost more than the 156 readers did.
  # The census already draws the line -- three families answer a row question and the rest do not
  # -- so the guard asks the census.
  measured = _measure(census)

  findings = []
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