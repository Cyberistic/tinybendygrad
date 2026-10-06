#!/usr/bin/env python3
"""nvdup-fix-nv.py -- CLOSE THE 27 ORACLE-SIDE DUPLICATES OF `ops_nv`, and delete the FOUR
STRUCTURALLY DEAD ARMS a multiplicity census cannot see.  Count-asserted; `--check` writes
nothing; every hunk is matched on its EXACT TEXT, never on a line number alone.

    .venv/bin/python .agents/slop/nvdup/nvdup-fix-nv.py --check    # runs both oracles, writes nothing
    .venv/bin/python .agents/slop/nvdup/nvdup-fix-nv.py --apply    # writes, keeping the pre-fix copy beside the evidence

THE ONE RULE THIS FILE APPLIES, AND WHERE IT STOPS.  Two sites for one name is always a
duplicate; which of the two a fix deletes is decided by WHICH ONE IS THE MEASUREMENT:

  * both sites CALL CPython and agree                   -> delete the later one
  * one site TYPES the answer                           -> delete the typed one
  * the two sites ask CPython two DIFFERENT questions   -> DELETE NEITHER, report both `file:line`

`nv_reloc_bad_n` is the third case.  Its two sites measure different SUBJECTS: :720 asks
`len(reloc_fold(...))`, and `reloc_fold` is a helper defined 16 lines below in this same file, so
:720 is a row about the oracle.  `agent-core.md`: "a row whose expected value is a def of the
thing under test is not a test".  The site deleted here is the one with no upstream subject, so
the fix does not take a side on the semantic dispute -- it drops the party that had no standing.
`nvdup-report.md` carries the dispute with both `file:line`.

EVERY COUNT IS MEASURED BEFORE IT IS ASSERTED.  The patched source is RUN in a `$TMPDIR` copy
(`nv-oracle.py:16` derives its import root from `__file__`, so `PYTHONPATH` carries the repo and
the copy stays out of the tree), and the expected rows/distinct/values are read off that run.
`agent-core.md`'s table of hand-typed `py=` constants is made of expectations that were right
about the intent and wrong about the count, and the dup unit's own fixer failed on exactly that,
so nothing here is typed.
"""
import argparse, hashlib, importlib.util, os, pathlib, subprocess, sys, tempfile
from collections import Counter

REPO = pathlib.Path(__file__).resolve().parents[3]
ORACLE = REPO / ".agents/slop" / "nv-oracle.py"
HERE = pathlib.Path(__file__).resolve().parent
PY = sys.executable


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, str(path))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load(REPO / ".agents/slop" / "rebase-gate.py", "rebase_gate")
ROW = RG.row

# (old, new) EXACT text, asserted present EXACTLY ONCE before anything is written.  Zero matches
# and two matches both fail: a fixer that applies to the first of two candidates edits the wrong
# row.  `new=None` deletes.
HUNKS = [
  # --- 1/27  ONE SITE, emitted twice.  The fixture tuple holds the same number twice, because
  # `2 * STEP - 1 == 4294967295` when `STEP == 1 << 31`.  So this is NOT "two emission sites":
  # one loop, one line, one name reached twice.  Dropping the alias keeps `4294967295`.
  ("""for sz in (0, 1, 0x300, STEP, STEP + 1, 2 * STEP - 1, 4294967294, 4294967295):""",
   """for sz in (0, 1, 0x300, STEP, STEP + 1, 4294967294, 4294967295):"""),

  # --- 1/27  `nv_reloc_kind_n`.  :692 TYPES 3; :1222 CALLS `len(DT)`.  This file's own standard,
  # in the comment above :1222, is "A row that prints a literal in both lanes is the shape of a
  # test that cannot fail".  The caller survives.
  ("""row("nv_reloc_kind_n", 3)\n""", None),

  # --- 3/27  `nv_reloc_msg_0/3/100`.  :701 TYPES "unknown NV reloc %d"; :1156 is CPython's own
  # `str(_e)` out of the raise.  Measured equal, so the typed copy is the one that goes.
  ("""for _t in (0, 3, 100):
    row("nv_reloc_msg_%d" % _t, "unknown NV reloc %d" % _t)
""", None),

  # --- 2/27  `nv_reloc_bad_n` / `nv_reloc_bad_refused`, the :719-721 copies.  Deleting the
  # `reloc_fold` row leaves `nv_reloc_bad_refused` sourced from CPython's caught `RuntimeError`
  # at :1161 rather than from the typed `"True"` that was here -- which is the refusal becoming
  # ADDRESSABLE, not merely un-duplicated.
  ("""_bad = reloc_fold([(16, 8, 2), (48, 8, 3), (64, 8, 0x38)])
row("nv_reloc_bad_n", len(_bad))
row("nv_reloc_bad_refused", "True")
""", None),

  # --- 2/27  `nv_launch_ok_1024_1024` / `nv_launch_ok_1024_8192`.  The loop folds the local shape
  # `(_p, 1, 1)` and the explicit rows fold `(32, 32, 1)`.  TWO FIXTURES, ONE NAME, answers that
  # COINCIDE -- which is why a value-only classifier calls this P1 and misses the real shape.  The
  # loop keeps its two unique members, which are also its two `False` measurements.
  ("""for _p, _mt in ((1024, 1024), (1024, 512), (2048, 8192), (1024, 8192)):""",
   """for _p, _mt in ((1024, 512), (2048, 8192)):"""),

  # --- 1/27  `nv_bpt_1_48428`.  :878 is `_bpt(32, 48, 4)`; the loop member `("1_48428", 1, 48, 4)`
  # is `_bpt(round_up(1, 32), 48, 4)` -- the same call.  The loop's fixture is the one that scales.
  ("""row("nv_bpt_1_48428", _bpt(32, 48, 4))\n""", None),

  # --- 5/27  `nv_errstr_0/2/8/999/4096`, the foot copy.  Both sites call `get_error_str`; :379
  # keeps the block that names upstream's :35 and :37-38.
  ("""for _s in (0, 2, 8, 999, 4096):
    row("nv_errstr_%d" % _s, get_error_str(_s))
""", None),

  # --- 9/27  `nv_iowr_*`.  The two fixture tuples are MEASURED to be the same nine NAMES, which
  # is what this file's own comment at :420-425 said while both copies stood.
  ("""# :43-45 `nv_iowr`'s command word.
for _sz, _nr in ((0, 0), (4, 1), (64, 0x2c), (40, 0x2b), (96, 0x41), (1280, 2),
                 (8191, 136), (8192, 1), (8192, 255)):
    row("nv_iowr_%d_%d" % (_sz, _nr), _iowr_cmd(_sz, _nr))
""", None),

  # --- 3/27  `nv_paccess_0/2/4`.  `row("nv_paccess_N", ...)` is TEXTUALLY IDENTICAL at both
  # sites, so a bare-text hunk would match twice and could not say which is which.  Each hunk is
  # therefore anchored on the pair it forms with its neighbour, which is unique to the foot block
  # (`1`, `3` and `8` are not in the :385-387 set).
  ("""row("nv_paccess_0", NV_PFAULT_ACCESS_TYPE[0])
row("nv_paccess_1", NV_PFAULT_ACCESS_TYPE[1])
""", """row("nv_paccess_1", NV_PFAULT_ACCESS_TYPE[1])
"""),
  ("""row("nv_paccess_2", NV_PFAULT_ACCESS_TYPE[2])
row("nv_paccess_3", NV_PFAULT_ACCESS_TYPE[3])
""", """row("nv_paccess_3", NV_PFAULT_ACCESS_TYPE[3])
"""),
  ("""row("nv_paccess_4", NV_PFAULT_ACCESS_TYPE[4])
row("nv_paccess_8", NV_PFAULT_ACCESS_TYPE[8])
""", """row("nv_paccess_8", NV_PFAULT_ACCESS_TYPE[8])
"""),

  # --- 1 DEAD ARM, NOT one of the 27, and invisible to a multiplicity census because it emits
  # nothing.  All three elements of `(0, 3, 100)` fall through `reloc_of`'s arms to its `raise`,
  # so this line is unreachable for every iteration -- MEASURED 3 of 3 by `nvdup-probe.py`.  The
  # non-raising case IS measured, at :699, as `nv_reloc_msg_2=""`.
  ("""        row("nv_reloc_msg_%d" % _t, "")
""", None),

  # --- 1 DEAD ARM, NOT one of the 27, and THE ROW THE BRIEF NAMES.
  # `nv_reloc_bad_refused="False"` is NOT an overwrite of a live negative.  The comprehension on the
  # line above aborts on its SECOND element -- `(48, 8, 3)` raises -- so this line NEVER EXECUTES
  # and the name is emitted `True` (:721, typed) and `True` (:1161, from a caught exception).
  # Deleting it deletes code that emits nothing.  The rule's negative case is measured at :718 as
  # `nv_reloc_ok_refused="False"`, and BOTH sides print it (measured).
  ("""    row("nv_reloc_bad_refused", "False")
""", None),

  # --- 2 MORE DEAD ARMS, NOT duplicates, found by `nvdup-deadarm.py` on the FIXED file.
  # `_smem_cfg` is `min(c * 1024 for c in [32, 64, 100] if c * 1024 >= shmem) // 4096 + 1`
  # (:639), so every `shmem > 102400` leaves the generator EMPTY and `min()` raises -- both
  # fixtures here are 131072, so BOTH try-arms are unreachable.  MEASURED by the census, not by
  # reading: 2 dead sites, and `nvdup-probe.py` answers the same question for `reloc_of`.
  # Neither line emits a row, so neither costs a measurement and neither is in the 27; both are
  # the SAME defect as `nv_reloc_bad_refused`, in the same file, and the rule's accepted side is
  # already measured BY CALL at :659 (`nv_smemcfg_0..102400`) and :660-663
  # (`nv_smemcfg_msg_102400=""`), so both dead arms are redundant as well as dead.
  ("""    _sm = _smem_cfg(131072)
    row("nv_smemcfg_too_big", "False")
""", """    _smem_cfg(131072)
"""),
  ("""    _smem_cfg(131072)
    row("nv_smemcfg_msg_big", "")
except ValueError as _e:""",
   """    _smem_cfg(131072)
except ValueError as _e:"""),

  # the comment at :420-425 asserts a duplication that this fix removes; it must not outlive it.
  ("""# The 9 names below are emitted a SECOND time in the stage-3/4 block -- MEASURED,
# the two fixture tuples are the SAME 9 pairs, so the collision costs no coverage
# and one of each pair is invisible to the gate. Both call the same helper, so the
# duplicate can no longer disagree with itself.""",
   """# The stage-3/4 block emitted these SAME 9 names a second time from a second
# fixture tuple -- MEASURED, the two tuples were the same 9 pairs and one of each
# pair was invisible to the gate.  That copy is deleted; the 9 names below are the
# whole population.  `.agents/slop/nvdup/` carries the census and the multiset proof."""),
]


def apply_hunks(text, tag):
  for old, new in HUNKS:
    n = text.count(old)
    if n != 1:
      raise SystemExit(f"{tag}: hunk matched {n} times, expected 1:\n---\n{old}\n---")
    text = text.replace(old, new or "", 1)
  return text


def run(source_text, tag):
  """The lane text from the oracle actually RUNNING -- never from the file, and never from a
  transcription of what the file should print."""
  with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
    f.write(source_text)
    tmp = pathlib.Path(f.name)
  try:
    env = dict(os.environ, PYTHONPATH=str(REPO))
    r = subprocess.run([PY, str(tmp)], cwd=REPO, capture_output=True, text=True, env=env)
    if r.returncode != 0:
      raise SystemExit(f"{tag}: oracle exited {r.returncode}\n{r.stderr[-900:]}")
    return r.stdout
  finally:
    tmp.unlink()


def census(text):
  rows = [ROW(l) for l in text.splitlines() if ROW(l) is not None]
  c = Counter(r[0] for r in rows)
  return {"rows": len(rows), "distinct": len(c), "dup": {k: v for k, v in c.items() if v > 1},
          "names": set(c), "values": {r[1] for r in rows}}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--apply", action="store_true")
  ap.add_argument("--check", action="store_true")
  a = ap.parse_args()
  if not (a.apply or a.check):
    print("give --check (writes nothing) or --apply")
    return 2

  src = ORACLE.read_text()
  cb = census(run(src, "BEFORE"))
  print(f"BEFORE  rows={cb['rows']}  distinct={cb['distinct']}  DUPLICATE NAMES={len(cb['dup'])}"
        f"  surplus={cb['rows'] - cb['distinct']}  sha256(nv-oracle.py)="
        f"{hashlib.sha256(src.encode()).hexdigest()[:16]}")

  after_src = apply_hunks(src, "apply_hunks")
  ca = census(run(after_src, "PATCHED"))
  print(f"AFTER   rows={ca['rows']}  distinct={ca['distinct']}  DUPLICATE NAMES={len(ca['dup'])}"
        f"  surplus={ca['rows'] - ca['distinct']}")
  print(f"  duplicate NAMES: {len(cb['dup'])} -> {len(ca['dup'])}  "
        f"closed={sorted(set(cb['dup']) - set(ca['dup']))}")
  print(f"  distinct names:  {cb['distinct']} -> {ca['distinct']}  "
        f"(EQUAL = no name invented and none lost)")
  print(f"  VALUE SET identical: {cb['values'] == ca['values']}   "
        f"only in BEFORE {sorted(cb['values'] - ca['values'])[:6]}   "
        f"only in AFTER {sorted(ca['values'] - cb['values'])[:6]}")
  print(f"  names LOST entirely: {sorted(cb['names'] - ca['names'])}   "
        f"names GAINED: {sorted(ca['names'] - cb['names'])}")
  print(f"  source lines: {len(src.splitlines())} -> {len(after_src.splitlines())}   "
        f"hunks: {len(HUNKS)}")

  for cond, msg in ((ca["distinct"] == cb["distinct"], "a name was invented or lost"),
                    (ca["values"] == cb["values"], "a VALUE moved"),
                    (not ca["dup"], f"duplicates remain: {sorted(ca['dup'])}")):
    if not cond:
      print(f"ASSERTION FAILED: {msg}")
      return 1

  if a.check:
    print("CHECK OK -- nothing written.  27 duplicate names closed, 0 remain, value set identical.")
    return 0
  BAK = HERE / "nv-oracle-PREFIX.py"
  BAK.write_text(src)
  ORACLE.write_text(after_src)
  print(f"APPLIED.  pre-fix copy kept at {BAK.relative_to(REPO)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())