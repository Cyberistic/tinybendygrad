#!/usr/bin/env python
# helpers-tc-mutate.py -- the MUTATION TABLE for the trange/GlobalCounters/Context
# block added to tinybendygrad/helpers.bend.
#
#   .venv/bin/python .agents/slop/helpers-tc-mutate.py
#
# WHY A MIRROR AND NOT THE TREE. `helpers.bend` is imported by 88 files and seven
# agents are live, so a mutation that leaves it wrong -- or uncompilable -- for even a
# second is everybody's outage. Every mutation is applied to a COPY under
# `.agents/slop/helpers-mut/` and the gate is rewritten to import the copy. The real
# `tinybendygrad/helpers.bend` is not written at all; the script asserts that by
# hashing it before and after.
#
# The harness diffs WHOLE `name=value` LINES, not row names -- a name-comparing
# harness reported 0 for every mutation in two other units, because the row names are
# identical in both runs by construction and only the VALUES differ.
import hashlib, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MUT = os.path.join(ROOT, ".agents/slop/helpers-mut")
GATE = ".agents/slop/helpers-tc.bend"
TARGET = "tinybendygrad/helpers.bend"
ENV = dict(os.environ, DEFAULT_FLOAT="f16", DEFAULT_INT="i64", NO_COLOR="0")

# (id, the exact source text to find, the replacement, what it is meant to break)
MUTATIONS = [
  ("M-a", "def trange(+n: U32) -> Tqdm:\n  Tqdm{n, List.range(U32.to_nat(n))}",
   "def trange(+n: U32) -> Tqdm:\n  Tqdm{n, List.range(U32.to_nat(n))}", "no-op control"),
  ("M-b", "Tqdm{n, List.range(U32.to_nat(n))}", "Tqdm{U32.add(n, 1), List.range(U32.to_nat(n))}",
   "total is n+1, i.e. `total=n` dropped"),
  ("M-c", "Tqdm{n, List.range(U32.to_nat(n))}", "Tqdm{n, List.range(U32.to_nat(U32.sub(n, 1)))}",
   "the range is short by one (off-by-one at the END)"),
  ("M-c2", "Tqdm{n, List.range(U32.to_nat(n))}", "Tqdm{n, List.range(U32.to_nat(U32.add(n, 1)))}",
   "the range is long by one (off-by-one at the START-END)"),
  ("M-d", "Tqdm{n, List.range(U32.to_nat(n))}", "Tqdm{n, Nil{}}",
   "the sequence is dropped entirely"),
  ("M-e", "case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(ops, d), mem, t, k, used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, k, used, devs}",
   "bump_ops does not add -- a counter that cannot count"),
  ("M-f", "case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(ops, d), mem, t, k, used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(d, ops), mem, t, k, used, devs}",
   "bump_ops adds to the wrong side"),
  ("M-g", "case Counters{ops, mem, t, k, used, devs}: Counters{0, 0, 0.0, 0, used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{0, 0, 0.0, 0, 0, devs}",
   "reset also zeroes mem_used, which upstream does NOT reset"),
  ("M-h", "case Counters{ops, mem, t, k, used, devs}: Counters{0, 0, 0.0, 0, used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{0, 0, 0.0, 0, used, Nil{}}",
   "reset also drops the per-device bag"),
  ("M-i", "case Counters{ops, mem, t, k, used, devs}: Counters{ops, U32.add(mem, d), t, k, used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, k, used, devs}",
   "bump_mem does not add"),
  ("M-j", "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, U32.add(k, 1), used, devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, U32.add(k, 2), used, devs}",
   "bump_kernel steps by 2 instead of 1"),
  ("M-k", "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, k, U32.add(used, d), devs}",
   "case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, k, used, devs}",
   "bump_mem_used does not add"),
  ("M-l", "Counters{ops, mem, t, k, used,\n        GlobalCounters.mupd_put(dev, U32.add(GlobalCounters.mupd_get(dev, devs), d), devs)}",
   "Counters{ops, mem, t, k, used,\n        GlobalCounters.mupd_put(dev, d, devs)}",
   "per-device add REPLACES instead of accumulating"),
  ("M-m", "    case Nil{}: GlobalCounters.mupd_put.end(found, dev, n, out)",
   "    case Nil{}: List.append(&2, Mupd, out, [Mupd{dev, n}])",
   "per-device put appends even when it FOUND the key (the duplicate-key bug)"),
  ("M-m2", "def GlobalCounters.mupd_put.end(found: Bool, +dev: U32, n: U32, out: List<&2, Mupd>) -> List<&2, Mupd>:\n  match found:\n    case True{}: out",
   "def GlobalCounters.mupd_put.end(found: Bool, +dev: U32, n: U32, out: List<&2, Mupd>) -> List<&2, Mupd>:\n  match found:\n    case True{}: List.append(&2, Mupd, out, [Mupd{dev, n}])",
   "per-device put ALWAYS appends"),
  ("M-m3", "    case +e <> t: GlobalCounters.mupd_get.go(t, dev, GlobalCounters.mupd_get.pick(found, U32.is_eq(GlobalCounters.mupd_dev(e), dev), e))",
   "    case +e <> t: GlobalCounters.mupd_get.go(t, dev, found)",
   "per-device get always answers 0 -- the defaultdict read stops seeing stored keys"),
  ("M-m4", 'case "DEFAULT_FLOAT": CV{"DEFAULT_FLOAT", nc, df}', 'case "DEFAULT_FLOAT": CV{"DEFAULT_FLOAT", nc, di}',
   "the snapshot reads DEFAULT_INT where upstream reads DEFAULT_FLOAT"),
  ("M-n", "def Context.__exit__(c: Ctx, f: Flags) -> Flags:\n  Flags.put(f, Context.old(c))",
   "def Context.__exit__(c: Ctx, f: Flags) -> Flags:\n  f",
   "__exit__ restores nothing"),
  ("M-o", "def Context.__exit__(c: Ctx, f: Flags) -> Flags:\n  Flags.put(f, Context.old(c))",
   "def Context.__exit__(c: Ctx, f: Flags) -> Flags:\n  Context.inside(c)",
   "__exit__ REPLAYS THE ENTERED RECORD -- the stack-pop reading of __exit__"),
  ("M-p", "def Context.__enter__(+f: Flags, +cvs: List<&2, CV>) -> Ctx:\n  Ctx{Flags.snap(f, cvs), Flags.put(f, cvs)}",
   "def Context.__enter__(+f: Flags, +cvs: List<&2, CV>) -> Ctx:\n  Ctx{Nil{}, Flags.put(f, cvs)}",
   "the snapshot is empty, so exit restores nothing"),
  ("M-q", "def Context.__enter__(+f: Flags, +cvs: List<&2, CV>) -> Ctx:\n  Ctx{Flags.snap(f, cvs), Flags.put(f, cvs)}",
   "def Context.__enter__(+f: Flags, +cvs: List<&2, CV>) -> Ctx:\n  Ctx{Flags.snap(f, cvs), f}",
   "`entered` is the record BEFORE the kwargs were written, so the block sees the outside"),
  ("M-q2", "def Context.inside(c: Ctx) -> Flags:\n  match c:\n    case Ctx{old_context, entered}: entered",
   "def Context.inside(c: Ctx) -> Flags:\n  match c:\n    case Ctx{old_context, entered}: entered",
   "CONTROL: inside/old unchanged"),
  ("M-q3", "def Context.old(c: Ctx) -> List<&2, CV>:\n  match c:\n    case Ctx{old_context, entered}: old_context",
   "def Context.old(c: Ctx) -> List<&2, CV>:\n  match c:\n    case Ctx{old_context, entered}: List.append(&2, CV, Nil{}, old_context)",
   "`old` REVERSES the snapshot order -- only observable if two kwargs share a key"),
  ("M-r", 'case "NO_COLOR": CV{"NO_COLOR", nc, ""}', 'case "NO_COLOR": CV{"NO_COLOR", False{}, ""}',
   "the snapshot drops the boot no_color value"),
  ("M-s", "def Context.arg(k: String, +v: String) -> CV:\n  CV{k, Bool.not(String.is_empty(v)), v}",
   "def Context.arg(k: String, +v: String) -> CV:\n  CV{k, String.eq(v, \"\"), v}",
   "Context(NO_COLOR=v) uses `v == \"\"` instead of `bool(v)` -- the coercion is INVERTED",
   ),
  ("M-t", 'case "DEFAULT_FLOAT": Flags{nc, v, di, sd}', 'case "DEFAULT_FLOAT": Flags{nc, df, v, sd}',
   "put writes the kwarg into DEFAULT_INT instead of DEFAULT_FLOAT (fields swapped)"),
  ("M-u", "def GlobalCounters.bump_ops(c: Counters, d: U32) -> Counters:\n  match c:\n    case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(ops, d), mem, t, k, used, devs}",
   "def GlobalCounters.bump_ops(c: Counters, d: U32) -> Counters:\n  match c:\n    case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(ops, d), mem, t, k, used, devs}\n\ndef unused_probe(c: Counters) -> Counters:\n  c",
   "a def nothing calls -- must move NOTHING"),
]

def sha(path):
  return hashlib.sha256(open(os.path.join(ROOT, path), "rb").read()).hexdigest()

def run_gate(helpers_rel, tries=25, seed=True):
  os.makedirs(MUT, exist_ok=True)
  helpers = os.path.join(MUT, "helpers.bend")
  # SEED ONCE, NOT EVERY CALL. Two bugs lived here, in opposite directions:
  #  - copy only if absent: a STALE mirror is worse than none. After helpers.bend
  #    grew two gate rows the BASELINE ran against the old copy (62 rows) while
  #    every mutation ran against the new one (64), so all 28 mutations would have
  #    "moved" two rows nothing touched.
  #  - copy EVERY time: the mirror is exactly where the MUTATED source is written,
  #    so re-seeding on each call overwrites the mutation before the lane runs and
  #    every mutation reports NOTHING. Measured: 8 of 8 "NOTHING" including M-e,
  #    which provably moves gc_bumped_ops.
  # So: the caller writes the file it wants (pristine for the baseline, mutated for
  # a mutation) and this never touches it.
  del seed
  g = open(os.path.join(ROOT, GATE)).read()
  g = re.sub(r'^import .*helpers\.bend as H$',
             'import %s as H' % helpers_rel, g, flags=re.M)
  gp = os.path.join(MUT, "gate.bend")
  open(gp, "w").write(g)
  for _ in range(tries):
    r = subprocess.run([os.path.join(ROOT, "bin/bend"), gp], cwd=ROOT, env=ENV,
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
      return r.stdout
  raise SystemExit("gate lane never produced rows:\n" + r.stdout + r.stderr)

import pathlib

# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows

shutil.copy(os.path.join(ROOT, TARGET), os.path.join(MUT, "helpers.bend"))
base_txt = run_gate("./helpers.bend")
before = sha(TARGET)
base = rows(base_txt)
print(f"baseline: {len(base)} rows, sha(helpers.bend)={before[:12]}", flush=True)

src = open(os.path.join(ROOT, TARGET)).read()
TSV = os.path.join(ROOT, ".agents/slop/helpers-tc-mutations.txt")
# RESUME. Three server restarts have killed this run mid-table. The TSV is flushed
# per mutation, so an interrupted run is continued rather than restarted: a mutation
# already recorded is skipped. `--fresh` truncates it first.
DONE = set()
if "--fresh" in sys.argv:
  open(TSV, "w").close()
elif os.path.exists(TSV):
  DONE = {l.split("\t")[0] for l in open(TSV) if l.strip()}
  if DONE: print(f"resuming: {len(DONE)} already recorded: {' '.join(sorted(DONE))}", flush=True)

def emit(mid, why, res):
  # FLUSH EVERY MUTATION. Two server restarts killed this run before and both
  # times the whole table was lost, because the file is only written at the end.
  print(f"{mid}\t{why}\t{res}", file=sys.stdout, flush=True)
  with open(TSV, "a") as fh:
    fh.write(f"{mid}\t{why}\t{res}\n")

for m in MUTATIONS:
  mid, find, repl = m[0], m[1], m[2]
  why = m[3]
  if mid in DONE: continue
  if find == repl:
    emit(mid, why, "CONTROL: 0 rows (unchanged)")
    continue
  if src.count(find) != 1:
    emit(mid, why, f"SKIPPED: pattern occurs {src.count(find)}x, not 1")
    continue
  hp = os.path.join(MUT, "helpers.bend")
  open(hp, "w").write(src.replace(find, repl))
  try:
    txt = run_gate("./helpers.bend", 6)
  except SystemExit as e:
    emit(mid, why, "NO ROWS (did not compile / produced nothing): " + str(e).replace(chr(10), " ")[:110])
    continue
  r = rows(txt)
  moved = sorted(k for k in set(base) | set(r) if base.get(k) != r.get(k))
  emit(mid, why, ", ".join(moved) if moved else "NOTHING (blind spot)")
os.remove(os.path.join(MUT, "helpers.bend"))
after = sha(TARGET)
print(f"after:    sha(helpers.bend)={after[:12]}  UNCHANGED={before == after}")
print(f"\nhelpers.bend sha {before[:12]} -> {after[:12]}  UNCHANGED={before == after}")