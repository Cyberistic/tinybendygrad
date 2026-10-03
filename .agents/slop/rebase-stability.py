#!/usr/bin/env python3
"""rebase-stability.py -- the EVIDENCE a --record needs before it is allowed.

WHY THIS EXISTS. `rebase-gate.py --record` freezes whatever the tree printed at the moment
it ran. Two of the lanes in BASE_ORACLES can never report UNCHANGED afterwards, and one of
them is documented in that file's own comments: `elf.bend`'s oracle prints 14 `elf_built_*`
rows carrying the RUNTIME ADDRESSES of the libstub.dylib the fixtures link against, so ASLR
changes them on every process launch. Recording that lane freezes a lane whose verdict is
permanently RE-PORTED, and a permanently-RE-PORTED lane teaches the reader that RE-PORTED is
noise -- which is the exact failure a gate exists to prevent.

So --record must be gated on MEASUREMENT, and this is the measurement. For every wired port:

    run 1 and run 2 of run_port(), and record, per lane:
      n1, n2          row counts. A COUNT that moves between runs makes the lane unrecordable
                      even when every value agrees, because GUARD 1 is an absolute count and
                      would answer BROKEN (or RE-PORTED) at random.
      same            rows dicts compared whole, per lane. Not per row name -- agent-core.md
                      records that a name-comparing harness reported 0 for all 30 mutations.
      interp_eq_native  within EACH run, interpreted == native. A bend interpreter that
                      stack-overflows on 1 run in 20 prints NOTHING, so a partial run shows up
                      as interpreted != native. This is a free second witness on the lane that
                      `same` alone would rate as stable twice in a row.

RECORDABLE MEANS ALL SEVEN OF THESE. Each one is here because a weaker test has already rated a
lane as stable when it was not, and the two strongest instances are THIS FILE'S OWN FIRST
DRAFT -- it shipped twice, once for each half of GUARD 4.

  1 EVERY LANE EXITED 0, IN BOTH RUNS.
    ⚠ THE FIRST DRAFT OF THIS FILE REPORTED `dead_lanes` AND DID NOT USE THEM. So
    `tinybendygrad/dtype.bend` -- wired on purpose to `dtype_tables.py`, which EXITS 0 printing
    TSV and therefore emits zero `name=value` rows -- measured as "stable across 2 runs" on two
    identical EMPTY row sets. Recording that writes a zero-row baseline for the one port whose
    entire purpose is to be BROKEN, and the gate would then answer NOT-STARTED forever instead
    of naming a failed oracle. The instrument was rating the ABSENCE of output as stability.

  2 EVERY LANE PRODUCED AT LEAST ONE ROW, IN BOTH RUNS. GUARD 2's input, applied at RECORD time
    rather than only at verdict time -- a lane that was empty when recorded stays empty.

  3 THE LANE'S COUNT IS EQUAL ACROSS BOTH RUNS AND ITS ROWS ARE BYTE-IDENTICAL ACROSS BOTH.
    Whole-dict equality, so a lost row and a changed row are one failure here.

  4 INTERPRETED == NATIVE WITHIN BOTH RUNS.

  5 ZERO DISAGREEMENTS ON EVERY SHARED LANE PAIR, IN BOTH RUNS. GUARD 4 restated as a
    RECORDING PRECONDITION. A baseline asserts that the port and CPython agree, so recording a
    red and then reading UNCHANGED off it would LAUNDER the red -- the one outcome worse than
    not recording at all. Not theoretical: rebase-gate.py's own comments carry documented
    disagreements for `runtime/ops_qcom.bend` (`qc_ctz_zero`) and `engine/jit.bend` (4 rows).

Anything else is EXCLUDED, and the reason is carried in the output -- never a judgement call at
record time.

THE ROWS THEMSELVES ARE STORED for the ports that PASS, because they are the evidence:
`rebase-gate.py --record-stable` copies them verbatim rather than re-running the tree, since a
re-run is a DIFFERENT measurement and would silently replace the evidence with a fresh,
unverified one. Excluded ports keep counts, reasons and shared-row counts.

  usage: .venv/bin/python .agents/slop/rebase-stability.py [--only PORT] [--workers N]
         writes .agents/slop/rebase/stability.json and prints one line per port

INVOKE WITH .venv/bin/python. The editable tinygrad install exists only there (3.12); PATH's
python3 is 3.14 and every oracle dies with ModuleNotFoundError, which is GUARD 3, not a port bug.
"""
import argparse, concurrent.futures as cf, importlib.util, json, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "rebase" / "stability.json"


def load_gate():
  spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def dead_of(lanes):
  """Lanes that failed to RUN. `check` is excluded because `--check-only` exits 1 even on a
  clean file (dtype.bend's 14 permanently unfilled laws), which agent-core.md records as a trap
  that already cost one agent a 10-minute retry loop."""
  return sorted(k for k, l in lanes.items() if l["rc"] != 0 and k != "check")


def shared_of(rows):
  """Row names each lane pair corroborates, and how many of them disagree. The number of
  claims the lane actually makes -- a gate's strength is the intersection, not the oracle's
  output size. Same pairing rule as the gate's GUARD 4: EVERY pair must share something and
  agree on all of it."""
  lanes = sorted(rows)
  out = {}
  for i, a in enumerate(lanes):
    for b in lanes[i + 1:]:
      sh = set(rows[a]) & set(rows[b])
      out[f"{a}|{b}"] = {
        "shared": len(sh),
        "disagree": sum(1 for k in sh if rows[a][k] != rows[b][k]),
      }
  return out


def freeze_hazard(port, rows_by_lane):
  """RULE 7: a recorded row whose value is a property of the MACHINE or the INTERPRETER rather
  than of the ported code. Returns a reason string, or "" if there is none.

  Rules 1-6 are all about the two runs AGREEING. This one is about them agreeing for a reason
  that has nothing to do with the port, and it cannot be derived from the measurement, so it is
  a named list with the offending ROWS attached -- and every entry below was read out of the
  measured evidence, not inferred from a filename.

  WHY IT IS A SEPARATE RULE. GUARD 1 is an ABSOLUTE comparison over every recorded lane, so a
  recorded row that moves for any reason other than a port change produces RE-PORTED on a port
  that did not move. Two of these are not hypothetical, and this project has already published
  three contradictory numbers today over exactly one of them:

    * `runtime/ops_python.bend` -- 182 of the oracle's 241 rows are ungated, and among them
      `py_version_tuple`, which the oracle emits as `tuple(sys.version_info[:2])`
      (ops-python-render-oracle.py:64). MEASURED value in this tree: `(3, 12)`. It is a literal
      reading of the INTERPRETER THAT RAN THE ORACLE -- `.venv` is 3.12 and PATH's python3 is
      3.14. Repoint the venv, or run the gate under the other interpreter, and this row moves on
      a port nobody edited. A baseline containing it is a tripwire wired to the environment.

    * `runtime/ops_cpu.bend` -- 17 of 20 oracle rows are ungated, and they are HOST answers:
      MEASURED `findlib_m=/usr/lib/libm.dylib`,
      `findlib_rt=/System/Library/Frameworks/System.framework/System`,
      `findlib_objc=None`, plus `# OSX=True WIN=False` straight from
      `from tinygrad.helpers import OSX, WIN`. An OS point release or a different machine moves
      them. rebase-gate.py already names them "HOST answers ... which the port cannot be expected
      to reproduce off-Mac".

  The third entry is the same species with a different trigger -- not environment, but VOLUME:

    * `runtime/ops_amd.bend` -- 601 ungated oracle rows of 1010 (59%). rebase-gate.py's own
      comment says "Not --record'ed: the oracle emits 601 further rows, and GUARD 1 would freeze
      them". Those rows are `amd_alloc_*` / `amd_arch_*`; none of them is gated by the port, so a
      change in any of them is invisible to GUARD 4 and visible only as a false RE-PORTED.
    * `renderer/amd/generate.bend` -- 53 ungated oracle rows of 779: `parse_xml`'s decisions over
      the real pinned ISA XML, `extract_pcode`'s dict, module-order tables (`order archs`), the
      `pdf error class`. Same reason, and the briefing names it MUST-NOT-RECORD.

  The entry is CHECKED AGAINST THE MEASUREMENT rather than trusted: if the named rows are no
  longer present, or are no longer ungated, that is reported as a STALE entry rather than
  silently passing. A hazard list that cannot notice it has stopped applying is worse than no
  list, because it reads as a live finding."""
  entry = FREEZE_HAZARD.get(port)
  if not entry:
    return ""
  why, witnesses = entry
  port_rows = set(rows_by_lane.get("interpreted", {}))
  cpy = sorted(k for k in rows_by_lane if k.startswith("cpython:"))
  if not cpy:
    return f"STALE FREEZE_HAZARD entry: {why} -- but no cpython lane was measured"
  missing = [w for w in witnesses if not any(w in set(rows_by_lane[k]) - port_rows for k in cpy)]
  if len(missing) == len(witnesses):
    return (f"STALE FREEZE_HAZARD entry for {port}: none of {witnesses} is an ungated oracle "
            f"row any more, so the recorded reason ({why}) no longer applies. Re-measure and "
            "either drop this entry or replace its witnesses")
  return f"{why} (witness rows present: {', '.join(w for w in witnesses if w not in missing)})"


# port: (why it is unrecordable, [ungated oracle rows that prove it -- MEASURED, and re-checked])
FREEZE_HAZARD = {
  "tinybendygrad/runtime/ops_python.bend": (
    "the oracle records sys.version_info as a gate row, so the recording is wired to the "
    "interpreter rather than to the port",
    ["py_version_tuple", "py_version_ge_312"]),
  "tinybendygrad/runtime/ops_cpu.bend": (
    "the oracle records HOST answers (absolute library paths on THIS machine) as gate rows",
    ["findlib_m", "findlib_rt", "findlib_objc", "# OSX"]),
  "tinybendygrad/runtime/ops_amd.bend": (
    "601 of the oracle's 1010 rows are ungated, so GUARD 1 would freeze 601 rows that no port "
    "row corroborates",
    ["amd_arch_ok_11_999", "amd_alloc_vram", "amd_alloc_enomem_0"]),
  "tinybendygrad/renderer/amd/generate.bend": (
    "53 of the oracle's 779 rows are ungated (pinned-ISA parse_xml decisions, extract_pcode's "
    "dict, module-order tables), so GUARD 1 would freeze them",
    ["order archs", "arch xml", "ORACLE ROW COUNT"]),
}


def measure(port, oracle, runs=2):
  g = load_gate()
  bend = REPO / port
  seen, lanes_by_run = [], []
  for _ in range(runs):
    lanes, rows = g.run_port(bend, tuple(oracle), native=True)
    seen.append(rows)
    lanes_by_run.append(lanes)

  first = {k: len(v) for k, v in seen[0].items()}
  reasons = []

  # RULE 1 + 2, over EVERY run. The first draft checked only run 2 for dead lanes and checked
  # none for emptiness, so a lane that failed once out of two still rated as stable.
  for i, lanes in enumerate(lanes_by_run):
    dead = dead_of(lanes)
    if dead:
      detail = "; ".join(f"{k}: {lanes[k]['err'][:110]}" for k in dead)
      reasons.append(f"run {i+1}: lane(s) exited non-zero: {', '.join(dead)} -- {detail}")
    empty = sorted(k for k in seen[i] if not seen[i][k])
    if empty:
      reasons.append(f"run {i+1}: lane(s) produced ZERO rows: {', '.join(empty)}. An oracle that "
                     "emits no name=value rows compared nothing, and two empty runs are equally "
                     "empty -- recording that freezes silence")

  # RULE 3, across both runs.
  for lane in sorted(first):
    counts = [len(r.get(lane, {})) for r in seen]
    if len(set(counts)) != 1:
      reasons.append(f"{lane}: ROW COUNT MOVED between runs {counts}")
    elif not all(r.get(lane, {}) == seen[0].get(lane, {}) for r in seen):
      keys = {k for r in seen for k in r.get(lane, {})}
      diff = sorted(k for k in keys if len({r.get(lane, {}).get(k) for r in seen}) > 1)
      reasons.append(f"{lane}: {len(diff)} row(s) DIFFER between runs, e.g. {diff[:3]}")

  # RULE 4, within each run.
  for i in range(runs):
    i_l, n_l = seen[i].get("interpreted", {}), seen[i].get("native", {})
    if "interpreted" in first and "native" in first and i_l != n_l:
      d = sorted(set(i_l) ^ set(n_l)) or [k for k in set(i_l) & set(n_l) if i_l[k] != n_l[k]]
      reasons.append(f"run {i+1}: interpreted != native ({len(d)} row(s)), so at least one bend "
                     f"run was PARTIAL (a stack overflow prints nothing), e.g. {d[:3]}")

  # RULE 5 + 6, in both runs. GUARD 4 RESTATED AS A RECORDING PRECONDITION, and it has TWO
  # halves, which is exactly how it went half-recorded here:
  #
  #   5 ZERO disagreements on every shared lane pair -- a baseline asserts the port and CPython
  #     agree, so recording a red and reading UNCHANGED off it LAUNDERS the red. Measured, not
  #     theoretical: this rule is what excluded `codegen/decomp/dtype.bend` (1 shared row
  #     disagrees, in BOTH runs) and `runtime/ops_python` stays honest only because it is
  #     checked at all.
  #   6 EVERY lane pair SHARES AT LEAST ONE ROW NAME. ⚠ THE FIRST DRAFT CHECKED ONLY
  #     DISAGREEMENT, so an INCOMPARABLE pair passed it: zero disagreements over zero shared
  #     rows is a vacuous truth, and it is the exact bug this project has paid for seven times.
  #     It rated `renderer/cstyle.bend` recordable -- 225 stable bend rows, a stable oracle, and
  #     ZERO shared row names -- which the real gate reports BROKEN ("lane pair(s) share NO row
  #     names, so they compared nothing"). A baseline for that port would have been a recording
  #     of silence. "No disagreements" and "compared something" are different claims and the
  #     precondition needs both.
  for i in range(runs):
    for pair, s in shared_of(seen[i]).items():
      if not s["shared"]:
        reasons.append(f"run {i+1}: lane pair `{pair}` shares NO row name, so it compares "
                       "nothing -- GUARD 4 reports this BROKEN, and a baseline here would be a "
                       "recording of silence")
      elif s["disagree"]:
        reasons.append(f"run {i+1}: lane pair `{pair}` DISAGREES on {s['disagree']} of "
                       f"{s['shared']} shared row(s) -- recording this would launder a red")

  haz = freeze_hazard(port, seen[0])
  if haz:
    reasons.append(f"FREEZE HAZARD: {haz}")

  port_rec = {
    "port": port, "oracle": list(oracle), "runs": runs,
    "row_counts_run1": first,
    "row_counts_run2": {k: len(v) for k, v in seen[-1].items()},
    "shared_run1": shared_of(seen[0]),
    "reasons": reasons,
    "recordable": not reasons,
  }
  # Oracle rows the PORT does not print. Recorded, and it is the number that decides how much
  # of a recorded baseline is a claim about CPython's environment rather than about the port:
  # GUARD 1 is absolute over every recorded lane, so a row nobody gates can still move the
  # verdict. `elf.bend` (689 extra), `renderer/amd/generate.bend` (53) and
  # `runtime/ops_amd.bend` (192) are excluded for exactly this, independently of stability.
  cpy = sorted(k for k in first if k.startswith("cpython:"))
  port_rec["oracle_rows_not_gated"] = (
    {k: len(set(seen[0][k]) - set(seen[0].get("interpreted", {}))) for k in cpy} if cpy else {})
  if port_rec["recordable"]:
    port_rec["rows"] = seen[0]  # the evidence --record-stable copies verbatim
  return port_rec


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--only", default=None)
  ap.add_argument("--runs", type=int, default=2)
  ap.add_argument("--workers", type=int, default=4)
  ap.add_argument("--out", default=str(OUT))
  a = ap.parse_args()
  g = load_gate()
  # run_port() writes its native binary to /tmp/rebase-gate/<BEND STEM>.bin, and two wired
  # ports share the stem `dtype` (dtype.bend, codegen/decomp/dtype.bend). Sharding is by STEM,
  # not by port, so the two never land in different workers and clobber each other's binary.
  stem = {p: pathlib.Path(p).stem for p in g.BASE_ORACLES}
  shard = {}
  for s in sorted({v for v in stem.values()}):
    shard.setdefault(len(shard) % a.workers, []).extend(
      p for p in sorted(g.BASE_ORACLES) if stem[p] == s)
  todo = [p for ps in shard.values() for p in ps if not a.only or a.only in p]
  res, nrec = {}, 0
  with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
    fut = {ex.submit(measure, p, g.BASE_ORACLES[p], a.runs): p for p in todo}
    for f in cf.as_completed(fut):
      p = fut[f]
      try:
        r = f.result()
      except Exception as e:  # a measurement that crashed is NOT a stable lane
        r = {"port": p, "reasons": [f"measurement crashed: {e!r}"], "recordable": False}
      res[p] = r
      nrec += bool(r.get("recordable"))
      sh = ",".join(f"{k.split('|')[0][:6]}={v['shared']}/{v['disagree']}"
                    for k, v in r.get("shared_run1", {}).items())
      extra = sum(r.get("oracle_rows_not_gated", {}).values())
      print(f"{'REC ' if r.get('recordable') else 'EXCL'} {p:<44} "
            f"rows {list(r.get('row_counts_run1', {}).values())} shared[{sh}] "
            f"ungated+{extra} "
            f"{'; '.join(r['reasons']) or f'stable across {a.runs} runs'}", flush=True)
  out = pathlib.Path(a.out)
  out.write_text(json.dumps(res, indent=1, sort_keys=True))
  print(f"\n{nrec} recordable / {len(res)} measured -> {out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())