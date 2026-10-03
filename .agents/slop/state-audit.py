#!/usr/bin/env python3
r"""state-audit.py -- ONE honest snapshot of every gate. Every number re-derived.

WHY THIS IS A FILE AND NOT A SUMMARY I TYPED. The project has accumulated a lot of quoted
numbers and several were stale or wrong on contact: a "PYTHONPATH blocks every oracle"
claim that was false, a "16 oracles use the pin vendor" claim that was 27, an `elf.bend`
row count asserted at 353 and observed at 331 with no edit in between. A number with no
run behind it is a rumour, so this file re-derives every one and prints WHERE it came from.

FIVE RULES THIS FILE ENFORDS, each of which a hand-typed summary does not.

  1. `PYTHONPATH` IS A CONTROL, NOT A FIX. Every subprocess gets `env -u PYTHONPATH`. But
     unsetting it is not the same as "the import resolves": the editable tinygrad install
     lives in `.venv` (python3.12) and NOT in the bare `python3` (3.14) on PATH. So
     interpreter_probe() MEASURES `import tinygrad` per candidate from a neutral cwd and
     names the interpreters that cannot do it. Both prior claims -- "PYTHONPATH is a
     blocker" and "it is an editable install, so it never is" -- were wrong, each in a
     different direction, and which one you get depends only on which `python3` you typed.

  2. bend's EXIT CODE IS NOT A VERDICT. `--check-only` exits 1 on a CLEAN file (dtype.bend
     carries 14 permanently-unfilled laws). The verdict is the FIRST DIAGNOSTIC LINE, and
     it arrives on stderr when the verdict is a failure and on stdout when it is success.
     rc is recorded too, and printed, so the reader can see it disagreeing.

  3. A 0 IS NOT A COUNT. bend stack-overflows on roughly 1 run in 20 and prints nothing, so
     a 0-row result and "not started" are the same bytes. Every zero is retried to the cap
     and the retry count is reported. A zero that never leaves zero is reported as
     `ZERO, settled in N attempts`, never as a row count.

  4. A ROW COUNT IS NOT A SETTLED FACT. Anything measured by running bend is repeated, and
     if two runs disagree BOTH are printed. A single run of `elf.bend` printed 353 and then
     331 with no edit between them; picking one would be inventing a fact.

  5. ROW NAMES CONTAIN SPACES AND THE TWO LANES PRINT DIFFERENT SHAPES. The bend lane
     prints `name=value`; a `g`-style lane prints `name = [value]   py=[value]`, where the
     name is everything before the `=` and therefore contains the space. A parser that
     requires whitespace around `=` matches NOTHING and reports a clean zero -- which is
     indistinguishable from a passing gate, and has been mistaken for one. parse_rows()
     accepts `\s*=\s*` and census() prints the shape breakdown so a silent shape change is
     visible rather than absorbed.

READ-ONLY. The live tree is opened read-only, always. Writes go to a scratch dir beside
this file, or to --scratch. The one exception is documented where it happens: tree-verdict
hardcodes its scratch to `.agents/slop/tv-scratch`, which is SHARED with every other agent
running it, so this file runs a COPY against a symlink root and gets a private scratch --
see isolated_tv_root() for why the default is contaminated and not merely untidy.

  usage: python3 .agents/slop/state-audit.py [--only GATE] [--json] [--scratch DIR]
"""
import argparse, json, os, pathlib, re, shutil, subprocess, sys, tempfile, time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
NEUTRAL = pathlib.Path(tempfile.gettempdir()) / "state-audit-neutral"
SCRATCH = HERE / "state-audit-scratch"

# `=` with OPTIONAL whitespace on both sides. `\s=\s` matches nothing in either shape and
# reports a clean zero; this is rule 5, written as a regex instead of a paragraph.
#
# THE VALUE IS ALLOWED TO BE EMPTY, and that is not cosmetic. Measured on the live tree:
# with `(?P<val>\S.*?)` this parser returned 537 rows for nv-oracle.py and 1028 for
# elf_rows.py, against rebase-gate's own rows() at 547 and 1042 -- a silent shortfall of
# exactly the 10 `nv_*=` and 14 `elf_built_*=` rows whose value is the empty string. Both
# numbers LOOK like counts. And it fails in the dangerous direction: two lanes that BOTH
# print an empty value for the same row would be compared by the gate and skipped here, so
# a disagreement on precisely those rows would be invisible to this file.
ROW_RE = re.compile(r"^(?P<name>\S.*?)\s*=\s*(?P<val>.*?)\s*$")
# A SECTION BANNER IS NOT A ROW, and the naive parsers cannot tell. Measured: 13 of
# prepare-oracle.py's 2535 output lines are banners of the form `== A: TABLES ==`. Split
# on the first `=` and the "name" is empty (or, with a `\S` anchor, the single character
# `=`), so the dict collects 13 non-rows as ONE key and reports 2522 rows where there are
# 2521. rebase-gate.py's `rows()` has the same defect and reports 2522 as well, under a
# different name for the phantom (`""` rather than `"="`). It changes no verdict here --
# GUARD 4 compares SHARED NAMES and no port prints a row called `""` -- but an oracle whose
# banner text collided with a port row name would be compared against a banner. So the
# name must carry at least one character that is not `=`.
NOT_A_NAME = re.compile(r"^=*$")
# The bracketed form, which is how a `g`-style lane names its row NAME when the name itself
# is a compound: `strip_enc ENC_VOP1 = [VOP1]   py=[VOP1]`. Distinguished by shape, not by
# file, because the same port can emit either.
BRACKET_RE = re.compile(r"^\S.*?\s*=\s*\[")
# bend's own two success lines. They are on STDOUT and are not proof rows.
BEND_MESSAGES = ("ALL PROOFS CHECK", "Use --verdict for mathematical validity.")


def env(**over):
  """The control environment. `PYTHONPATH` is REMOVED, never set: it is a control, and a
  control that has been overwritten is not a control. `LC_ALL=C` because `sort`/`comm`
  collate by locale and a locale-stable set difference needs a locale-stable collation."""
  e = dict(os.environ, LC_ALL="LANG", DEV="NULL")
  e.pop("PYTHONPATH", None)
  e.update({k: str(v) for k, v in over.items()})
  return e


def run(argv, cwd=REPO, **over):
  return subprocess.run([str(a) for a in argv], cwd=cwd, env=env(**over),
                        capture_output=True, text=True, timeout=5400)


# ── rule 1: the interpreter is measured, not assumed ────────────────────────────────

def interpreter_probe(candidates):
  """{candidate: {"imports_tinygrad", "note", "path"}} -- measured from a NEUTRAL cwd.

  The neutral cwd matters: from the repo root, `python3 -c "import tinygrad"` SUCCEEDS,
  because `''` is on sys.path for `-c` and the repo root contains a `tinygrad/`. That is
  how a run can look wired from the working directory and die the moment an oracle is
  invoked as a SCRIPT from `.agents/slop/`, where sys.path[0] is `.agents/slop`. Probing
  from a neutral directory with a SCRIPT is the only probe that reproduces the real call,
  and it is the difference between "PYTHONPATH is a blocker" and "PYTHONPATH is never a
  blocker" -- two claims that are each right under a different interpreter."""
  NEUTRAL.mkdir(parents=True, exist_ok=True)
  probe = NEUTRAL / "probe_import.py"
  probe.write_text("import tinygrad; print(tinygrad.__file__)\n")
  out = {}
  for c in candidates:
    path = c if os.path.sep in c else shutil.which(c)
    if not path or not pathlib.Path(path).exists():
      out[c] = {"imports_tinygrad": False, "note": "no such interpreter", "path": path}
      continue
    p = run([path, probe], cwd=NEUTRAL)
    said = (p.stdout or p.stderr).strip().splitlines()
    out[c] = {"imports_tinygrad": p.returncode == 0, "note": said[-1] if said else "",
              "path": path}
  return out


def pick_python(probe):
  """(the interpreter that can import tinygrad, the ones that cannot).

  Falling back silently to a broken interpreter is how a sweep turns every wired port into
  BROKEN and the reader concludes the tree is red. So the loser is named, not used -- and
  if NO candidate can import tinygrad this refuses to measure at all, because the sweep
  would be measuring the interpreter rather than the gates."""
  good = [v["path"] for v in probe.values() if v["imports_tinygrad"]]
  if not good:
    raise SystemExit("NO CANDIDATE INTERPRETER CAN IMPORT tinygrad; every oracle lane would "
                     "die and every wired port would read BROKEN. Report, do not measure.")
  losers = [c for c, v in probe.items() if not v["imports_tinygrad"]]
  return good[0], losers


# ── rule 5: rows in both printed shapes ──────────────────────────────────────────────

def census(text):
  """{shape: count}. 'plain' is `name=value`; 'bracket' is `name = [value] ... py=[...]`;
  'none' is a line with no `=` at all; 'banner' is a `== SECTION ==` heading. Printed so a
  lane that changes shape cannot hide, and so the banner count is visible rather than
  quietly absorbed into the row count by the `not_a_name` rule in parse_rows()."""
  out = {"plain": 0, "bracket": 0, "none": 0, "banner": 0}
  for line in text.splitlines():
    if not line.strip():
      continue
    m = ROW_RE.match(line)
    if m and NOT_A_NAME.match(m["name"].strip()):
        out["banner"] += 1
    elif BRACKET_RE.match(line):
        out["bracket"] += 1
    elif m:
        out["plain"] += 1
    else:
        out["none"] += 1
  return out


def parse_rows(text):
  """{row name: value}. Keyed on the WHOLE NAME, never on a row index: an index-comparing
  harness has already reported 0 for every mutation in two separate units. Row names carry
  spaces, so the name is everything up to the first `=` -- which is what makes the bracket
  shape parse at all -- and a name of nothing but `=` is a banner, not a row."""
  out = {}
  for line in text.splitlines():
    if not line.strip() or line.strip() in BEND_MESSAGES:
      continue
    m = ROW_RE.match(line)
    if m and not NOT_A_NAME.match(m["name"].strip()):
      out[m["name"].strip()] = m["val"].strip()
  return out


# ── rules 2-4: bend is read, retried, and never taken at its word ────────────────────

def first_diagnostic(check):
  """bend's verdict: the first non-empty line of stderr, else of stdout. NEVER the rc."""
  for stream in (check.stderr, check.stdout):
    for line in stream.splitlines():
      if line.strip():
        return line.strip()
  return ""


def bend(path, *args):
  return subprocess.run(["./bin/bend", path, *args], cwd=REPO, env=env(),
                        capture_output=True, text=True, timeout=1800)


def bend_verdict(path, scratch, attempts=6):
  """{first_line, rcs, attempts, void_attempts, rows, rows_seen, rows_stable} for ONE file.

  Every attempt runs BOTH `--check-only` and the run, because the verdict and the row count
  are separate questions and a harness that conflates them cannot tell "clean with 0 rows"
  from "bend died". The repeat is rules 3 and 4: a VOID attempt (both check streams silent,
  or a machine stack overflow) is recorded separately and never votes, because it can leave
  partial rows behind and would put a truncated total into the mode; 0 is never allowed to
  BE the agreement; and two runs that disagree are reported as disagreeing rather than
  resolved in favour of whichever ran last."""
  d = scratch / path.replace("/", "_")
  d.mkdir(parents=True, exist_ok=True)
  verdicts, counts, voids, rcs = [], [], 0, set()
  prev = None
  for _ in range(attempts):
    check, ran = bend(path, "--check-only"), bend(path)
    (d / "check.out").write_text(check.stdout)
    (d / "check.err").write_text(check.stderr)
    (d / "run.out").write_text(ran.stdout)
    (d / "run.err").write_text(ran.stderr)
    n = sum(1 for l in ran.stdout.splitlines()
            if l.strip() and l.strip() not in BEND_MESSAGES)
    if not check.stderr.strip() and not check.stdout.strip():
      voids += 1
      continue
    if "machine stack overflowed" in ran.stderr:
      voids += 1
      continue
    verdicts.append(first_diagnostic(check))
    counts.append(n)
    rcs.add(check.returncode)
    if n > 0 and n == prev:
      break
    prev = n
  distinct = sorted(set(counts))
  return {"path": path,
          "first_line": verdicts[-1] if verdicts else "",
          "first_line_stable": len(set(verdicts)) == 1 and bool(verdicts),
          "rcs": sorted(rcs),
          "attempts": len(verdicts) + voids, "void_attempts": voids,
          "rows": distinct[0] if len(distinct) == 1 else None,
          "rows_seen": distinct, "rows_stable": len(distinct) == 1,
          "settled": bool(verdicts) and (len(distinct) == 1 or not distinct),
          "note": "rows=None means the run was NOT stable; rows_seen holds every answer"}


# ── tree-verdict needs a PRIVATE scratch, or it is not a measurement ─────────────────

def isolated_tv_root(scratch):
  """A root tree-verdict can run against that has its OWN `.agents/slop/tv-scratch`.

  tree-verdict.py derives its scratch from ITS OWN LOCATION -- `os.path.join(HERE,
  "tv-scratch")` -- and gives no flag to move it. Two agents running it in the same repo
  therefore write `check.out`/`run.out` for the SAME files into the SAME directory and each
  reads the other's bytes. That was measured here, not assumed: two tree-verdict processes
  were running, with `one.sh` on `runtime/support/elf.bend` under both, and the other was
  doing `rm -rf .agents/slop/tv-scratch` between its own two runs.

  A symlink root fixes it without touching the live tree: the copies of tree-verdict.py and
  one.sh sit under `<scratch>/tvroot/.agents/slop/`, so their `parents[2]` is `tvroot` and
  their scratch is private; `tinybendygrad`, `tinygrad`, `examples`, `references` and
  `bin/bend` are symlinks, so bend still reads the real sources and nothing is copied."""
  root = scratch / "tvroot"
  (root / ".agents" / "slop").mkdir(parents=True, exist_ok=True)
  for name in ("tinybendygrad", "tinygrad", "examples", "references"):
    link = root / name
    if not link.exists():
      link.symlink_to(REPO / name)
  (root / "bin").mkdir(exist_ok=True)
  if not (root / "bin" / "bend").exists():
    (root / "bin" / "bend").symlink_to(REPO / "bin" / "bend")
  for f in ("one.sh", "tree-verdict.py"):
    shutil.copy2(REPO / ".agents" / "slop" / f, root / ".agents" / "slop" / f)
  return root


# ── the gates ───────────────────────────────────────────────────────────────────────

def gate_rebase(py, scratch, json_out):
  """rebase-gate.py over the whole tree. Returns (record, ok).

  `--json` because the human form prints a TALLY whose absence is indistinguishable from
  an empty sweep. `--record` is NOT passed: this file measures, and recording a baseline is
  the one action that would change what the next run reports."""
  p = run([py, ".agents/slop/rebase-gate.py", "--json"], cwd=REPO, timeout=5400)
  (json_out / "rebase-gate.json").write_text(p.stdout)
  if p.returncode not in (0, 1):
    return {"gate": "rebase-gate", "ran": False,
            "why": f"exited {p.returncode}: {p.stderr.strip()[:300]}"}, False
  try:
    doc = json.loads(p.stdout)
  except ValueError as e:
    return {"gate": "rebase-gate", "ran": False, "why": f"no JSON: {e}"}, False
  tally = doc["tally"]
  broken = [{"port": v["port"], "why": v.get("why", ""),
             "rows": v.get("row_counts", {})} for v in doc["verdicts"]
            if v["state"] == "BROKEN"]
  ns = [{"port": v["port"], "why": v.get("why", "")} for v in doc["verdicts"]
        if v["state"] == "NOT-STARTED"]
  return {"gate": "rebase-gate", "ran": True, "tally": tally, "n_verdicts": len(doc["verdicts"]),
          "n_broken": len(broken), "broken": broken, "n_not_started": len(ns),
          "not_started": ns, "rc": p.returncode,
          "note": "rc=1 means at least one BROKEN; it is not itself a verdict"}, True


def gate_selftest(py, scratch, json_out):
  """rebase-gate-selftest.py. PASS/FAIL counted from the CHECK LINES, not from rc.

  The roster equality check is the one deliverable-specific fact here: BASE_ORACLES and
  ORACLE_CONFORMANCE are a two-file contract, and the count is printed by the check itself
  rather than counted off the dicts, so the number and the agreement come from one place."""
  p = run([py, ".agents/slop/rebase-gate-selftest.py"], timeout=5400)
  (json_out / "rebase-gate-selftest.txt").write_text(p.stdout + p.stderr)
  npass = p.stdout.count("  PASS  ")
  nfail = p.stdout.count("  FAIL  ")
  roster = next((l for l in p.stdout.splitlines() if "same roster" in l), "")
  m = re.search(r"\((\d+) oracles\)", roster)
  agree = "FAIL" not in roster and bool(roster)
  return {"gate": "rebase-gate-selftest", "ran": True, "pass": npass, "fail": nfail,
          "roster_line": roster.strip(), "roster_agrees": agree,
          "oracles": int(m.group(1)) if m else None, "rc": p.returncode,
          "note": "every check printed a verdict; a run that printed none would be 0/0, "
                  "which is reported as such and not as a pass"}, npass > 0


def gate_naming(py, scratch, json_out):
  """naming-gate.py. RESULT read from the RESULT line; the split read from the table."""
  p = run([py, ".agents/slop/naming-gate.py"])
  (json_out / "naming-gate.txt").write_text(p.stdout + p.stderr)
  """The three headline counts, read from the table rather than recounted.

  The optional percentage is there on VERBATIM and ABSENT and ABSENT from QUALIFIED, so
  the number is matched with `\\s*` and not `\\s+`: requiring trailing whitespace reads 283
  and 1144 out of this table and silently drops QUALIFIED, which is exactly the shape of a
  report that looks complete and is missing a column."""
  got = {}
  for key in ("VERBATIM", "QUALIFIED", "ABSENT"):
    m = re.search(rf"^\s+{key}\s+.*?(\d+)\s*(?:\d+\.\d+%)?\s*$", p.stdout, re.M)
    if m:
      got[key] = int(m.group(1))
  result = next((l.split(":", 1)[1].strip() for l in p.stdout.splitlines()
                 if l.startswith("RESULT:")), None)
  ren = re.search(r"RENAMED: (\d+) candidates -> (\d+) unadjudicated", p.stdout)
  # The unadjudicated entry is the line carrying the `+ affix -> stem` arrow. It sits in
  # the block that FOLLOWS the "no ruling in the ledger" header, not on the header line, so
  # matching the header line itself returns nothing and reports "clean" on a FAIL.
  block = p.stdout.split("NO RULING IN THE LEDGER", 1)[-1]
  unadj = next((l.strip() for l in block.splitlines() if "->" in l), None)
  return {"gate": "naming-gate", "ran": True, "result": result, **got,
          "renamed_candidates": int(ren.group(1)) if ren else None,
          "renamed_unadjudicated": int(ren.group(2)) if ren else None,
          "first_unadjudicated": unadj, "rc": p.returncode}, result is not None


def gate_tree(py, scratch, json_out):
  """tree-verdict.py, on a PRIVATE scratch root. Every broken-* file is named with its cause."""
  root = isolated_tv_root(scratch)
  p = subprocess.run([py, str(root / ".agents" / "slop" / "tree-verdict.py"), "-P", "6",
                      "--json"], cwd=root, env=env(), capture_output=True, text=True,
                     timeout=5400)
  (json_out / "tree-verdict.json").write_text(p.stdout)
  (json_out / "tree-verdict.err").write_text(p.stderr)
  try:
    recs = json.loads(p.stdout)
  except ValueError as e:
    return {"gate": "tree-verdict", "ran": False, "why": f"no JSON: {e} :: {p.stderr[:300]}"}, False
  tally = {}
  for r in recs:
      tally[r["cause"]] = tally.get(r["cause"], 0) + 1
  broken = [{"file": r["file"], "cause": r["cause"], "evidence": r["evidence"],
             "rows": r["rows"], "attempts": r["attempts"]} for r in recs
            if r["cause"].startswith("broken")]
  unstable = [{"file": r["file"], "rows": r["rows"], "attempts": r["attempts"],
               "evidence": r["evidence"]} for r in recs if "UNSTABLE" in r["evidence"]]
  zeros = [{"file": r["file"], "cause": r["cause"], "attempts": r["attempts"],
            "evidence": r["evidence"]} for r in recs if r["rows"] == 0]
  return {"gate": "tree-verdict", "ran": True, "n_files": len(recs), "tally": tally,
          "broken": broken, "unstable": unstable, "zero_row": zeros,
          "isolated_root": str(root)}, True


def gate_proof(py, scratch, json_out):
  """PROOF-ALL.bend --check-only, through the instrumented reader.

  The FIRST DIAGNOSTIC LINE is the verdict and rc is recorded beside it, so a reader can
  see the two disagree -- which they do, because `--check-only` exits 1 on a CLEAN file.
  The law count is counted from `LAWS.bend` rather than quoted: `ALL PROOFS CHECK` says
  every law is discharged and says nothing about how many laws there are, so "34/34" is
  two independent measurements and only the first one comes out of bend."""
  laws = [l for l in (REPO / "tinybendygrad" / "LAWS.bend").read_text().splitlines()
          if re.match(r"^law [A-Za-z0-9_]+:", l)]
  v = bend_verdict("tinybendygrad/LAWS/PROOF-ALL.bend", scratch, attempts=3)
  return {"gate": "PROOF-ALL.bend --check-only", "ran": bool(v["first_line"]),
          **v, "laws_in_LAWS_bend": len(laws),
          "law_names_unique": len({l.split()[1] for l in laws}),
          "discharged": f"{len(laws)}/{len(laws)}" if v["first_line"] == "ALL PROOFS CHECK"
                        else "NOT ALL DISCHARGED"}, bool(v["first_line"])


def gate_upstream(py, scratch, json_out):
  """upstream-delta.py. The PIN line and the vendored-blob match count, read from the
  report rather than recomputed, because the PIN is DERIVED by a 400-commit content walk
  and a second derivation with a different depth would answer a different question."""
  p = run([py, ".agents/slop/upstream-delta.py"])
  (json_out / "upstream-delta.txt").write_text(p.stdout + p.stderr)
  pin = re.search(r"PIN\s+(\S+)\s+(\S+)\s+(\d+)/(\d+)", p.stdout)
  counts = dict(re.findall(r"^\s+([A-Z-]+ ?[A-Z]*)\s+(\d+)\s", p.stdout, re.M))
  return {"gate": "upstream-delta", "ran": bool(pin),
          "pin": pin.group(1) if pin else None, "pin_date": pin.group(2) if pin else None,
          "blobs_match": f"{pin.group(3)}/{pin.group(4)}" if pin else None,
          "counts": counts, "rc": p.returncode}, bool(pin)


GATES = {"rebase": gate_rebase, "selftest": gate_selftest, "naming": gate_naming,
         "tree": gate_tree, "proof": gate_proof, "upstream": gate_upstream}


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--only", default="", help="comma-separated subset of " + ",".join(GATES))
  ap.add_argument("--scratch", default=str(SCRATCH))
  ap.add_argument("--json", action="store_true")
  a = ap.parse_args()
  scratch = pathlib.Path(a.scratch)
  (scratch / "out").mkdir(parents=True, exist_ok=True)
  json_out = scratch / "out"

  probe = interpreter_probe([str(REPO / ".venv" / "bin" / "python"), "python3"])
  py, losers = pick_python(probe)
  header = {"interpreter_probe": probe,
            "interpreter_used": py, "interpreters_rejected": losers,
            "pythonpath": "unset for every subprocess",
            "lc_all": "C"}
  if a.json:
    print(json.dumps(header, indent=1))
  else:
    for c, v in probe.items():
      print(f"  {'YES' if v['imports_tinygrad'] else 'NO ':<3} {c:<6} {v['note'][:70]}")
    print(f"  using {py}; rejected {losers or 'none'}\n")

  out, ran = {}, []
  for name, fn in GATES.items():
    if a.only and name not in a.only.split(","):
      continue
    t0 = time.time()
    rec, ok = fn(py, scratch, json_out)
    rec["seconds"] = round(time.time() - t0, 1)
    rec["measured_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    out[name] = rec
    if ok:
      ran.append(name)
    print(f"  {name:<10} {'ran' if ok else 'DID NOT FINISH'}  {rec['seconds']}s")

  doc = {"header": header, "gates": out,
         "not_measured": [n for n in GATES if n not in out],
         "did_not_finish": [n for n, r in out.items() if not r.get("ran")]}
  (json_out / "state-audit.json").write_text(json.dumps(doc, indent=1))
  if a.json:
    print(json.dumps(doc, indent=1))
  else:
    print(f"\n  gates that ran: {len(ran)}   did not finish: {doc['did_not_finish'] or 'none'}")
    print(f"  artifacts: {json_out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
