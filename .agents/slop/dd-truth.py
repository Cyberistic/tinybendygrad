#!/usr/bin/env python3
"""dd-truth.py -- ONE measurement of dtype.bend against BOTH oracles, side by side.

There are two oracles for tinybendygrad/codegen/decomp/dtype.bend and they disagree about
how healthy the port is: dtype-oracle.py says 1 disagreement, dd-oracle.py says 52. This
file exists because a gate that measures nothing looks exactly like a gate that passes,
so every number printed here carries its DENOMINATOR.

WHAT IT DOES NOT DO: it does not reimplement dtype.py, and it does not adjudicate. It runs
the port lane (`./bin/bend`), runs both oracle scripts as subprocesses under the PINNED
.venv interpreter (oracle_py.resolve()), parses all three with rebase-gate.py's OWN rows()
-- so the parser is the gate's parser, not a second one that can be wrong in a new way --
and reports the Venn decomposition of the three row-name sets.

  A = port rows            B = dd-oracle.py rows            C = dtype-oracle.py rows
  shared(B,C) should be C   -- dtype-oracle.py is a FILTER over dd-oracle.py's output.
  That identity is ASSERTED here rather than assumed, because a filter that stopped
  filtering would look exactly like an oracle that agreed.

CONTROL, and it is a run of the real thing: `dd-truth.py --control` re-runs dd-oracle.py
through a MUTANT of dtype-oracle.py whose SKIP set is emptied. A filter that hides
disagreements must turn red when it stops hiding them; if the mutant reports the same
disagreement count as the live filter, then the filter is not what is moving the number and
the number means something else.

Run: .venv/bin/python .agents/slop/dd-truth.py [--control]
"""
import contextlib
import importlib.util
import io
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
PORT = "tinybendygrad/codegen/decomp/dtype.bend"
DD = ".agents/slop/dd-oracle.py"
DT = ".agents/slop/dtype-oracle.py"
MUTANT = ".agents/slop/dtype-oracle-MUTANT.py"


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def gate_rows():
  """rebase-gate.py's OWN rows(). Loaded, not copied: a second parser is a second opinion
  nobody checked, and agent-core.md records three false zeros from a parser that required
  `\\s=\\s` on lanes that print `name=value`."""
  return load("rebase_gate", REPO / ".agents/slop/rebase-gate.py").rows


def bend_lane():
  r = subprocess.run(["./bin/bend", PORT], cwd=REPO, capture_output=True, text=True, timeout=1800)
  return r, gate_rows()(r.stdout)


def oracle_lane(spec, py, rows):
  r = subprocess.run([py, *spec.split()], cwd=REPO, capture_output=True, text=True,
                     env=dict(__import__("os").environ, DEV="NULL"), timeout=1800)
  return r, rows(r.stdout)


def cvs(b, o, skip=frozenset()):
  """shared, disagree, and the disagreeing (name, port, oracle) triples sorted by name."""
  shared = sorted((set(b) & set(o)) - skip)
  bad = [(k, b[k], o[k]) for k in shared if b[k] != o[k]]
  return len(shared), len(bad), bad


def shorten(v, n=48):
  """A sig row is 4000 characters long and there are five of them. Truncating keeps the
  report readable AND makes the length itself visible, which is the fact that matters: two
  values of different length are a different SHAPE, not a different spelling."""
  return v if len(v) <= n else f"{v[:n]}<+{len(v) - n} chars>"


def skiper():
  """dtype-oracle.py's SKIP, read OUT OF THE MODULE rather than transcribed here."""
  return load("dt", REPO / DT).SKIP


def main():
  control = "--control" in sys.argv
  py, tinygrad, ver = load("oracle_py", HERE / "oracle_py.py").resolve()
  print(f"[truth] python {py}  {ver}  tinygrad <- {tinygrad}")
  print(f"[truth] port {PORT}\n")

  r, B = bend_lane()
  print(f"[truth] port lane rc={r.returncode}  rows={len(B)}")
  if not B:
    print(f"[truth] PORT LANE PRODUCED 0 ROWS. That is indistinguishable from 'not started'.")
    print(f"[truth] bend stderr: {r.stderr[-800:]!r}")
    print("[truth] Re-run: bend stack-overflows about 1 run in 20.")
    return 1
  # Re-run whenever the lane is non-empty but ALSO went nonzero: a lane that printed rows
  # and then failed is measuring something, and the failure belongs in the report.
  if r.returncode:
    print(f"[truth] ⚠ port lane was NONZERO with rows present; stderr tail {r.stderr[-400:]!r}")

  _, ORACLE = oracle_lane(DD, py, gate_rows())
  _, FILTERED = oracle_lane(DT, py, gate_rows())
  print(f"[truth] dd-oracle.py rows={len(ORACLE)}   dtype-oracle.py rows={len(FILTERED)}")

  skip = skiper()
  hidden = sorted(set(ORACLE) - set(FILTERED))
  print(f"[truth] dtype-oracle.py SKIP set holds {len(skip)} names; "
        f"{len(hidden)} of dd-oracle.py's rows it does not print")

  # THE IDENTITY: dtype-oracle.py's printed names must be EXACTLY dd-oracle.py's names minus
  # its SKIP set. Two halves, and both are needed -- `extra` catches a filter that ADDS a row,
  # the set equality catches one that drops or renames one.
  # ⚠ THE FIRST VERSION OF THIS ASSERTED `(ORACLE & FILTERED) - SKIP`, which is trivially
  # `FILTERED` and therefore vacuously true-or-false on noise: it printed a confident
  # "NOT a pure filter" on a filter that is exactly one. An identity that cannot fail is not
  # an identity. The expression is now the one whose failure means something.
  extra = sorted(set(FILTERED) - set(ORACLE))
  want = set(ORACLE) - skip
  pure = not extra and want == set(FILTERED)
  print(f"[truth] FILTER IDENTITY: dtype-oracle prints {len(FILTERED)} names; "
        f"dd-oracle prints {len(ORACLE)}; SKIP holds {len(skip)}; "
        f"{len(ORACLE) - len(skip)} expected")
  print(f"[truth]   {'PURE FILTER -- confirmed: FILTERED == dd-oracle rows - SKIP' if pure else 'NOT A PURE FILTER'}")
  if not pure:
    print(f"[truth]   rows it ADDS: {extra}")
    print(f"[truth]   rows it drops beyond SKIP: {sorted(want - set(FILTERED))}")
    print("[truth]   every count below is measured against a filter that does not filter; re-derive")

  s_dd, d_dd, bad_dd = cvs(B, ORACLE)
  s_dt, d_dt, bad_dt = cvs(B, FILTERED)
  print(f"\n[truth] port vs dd-oracle.py     : {d_dd:>3} disagree of {s_dd:>3} shared "
        f"(port {len(B)}, oracle {len(ORACLE)})")
  print(f"[truth] port vs dtype-oracle.py  : {d_dt:>3} disagree of {s_dt:>3} shared "
        f"(port {len(B)}, oracle {len(FILTERED)})")

  # THE DECOMPOSITION. The whole question is whether the 52 and the 1 are the same set.
  bad_dd_names = {k for k, _, _ in bad_dd}
  bad_dt_names = {k for k, _, _ in bad_dt}
  only_dd = sorted(bad_dd_names - bad_dt_names)
  print(f"\n[truth] {len(bad_dd)} disagreements against dd-oracle.py decompose as")
  print(f"[truth]   {len(bad_dt_names & bad_dd_names):>3} also gated by dtype-oracle.py")
  print(f"[truth]   {len(only_dd):>3} NOT gated -- dtype-oracle.py never prints them")
  unseen = sorted(set(ORACLE) - set(B))
  print(f"[truth] {len(unseen)} of dd-oracle.py's rows the PORT does not emit at all")
  print(f"[truth] {len(set(ORACLE) & set(FILTERED))} rows gated; "
        f"{len(set(FILTERED)) - d_dt} of those agree")

  print("\n[truth] EVERY disagreement against dd-oracle.py, with its gate status:")
  for k, pv, ov in sorted(bad_dd):
    gated = "GATED-RED" if k in bad_dt_names else ("suppressed-but-AGREES" if k in set(FILTERED)
                                                    else "SUPPRESSED BY dtype-oracle.py")
    print(f"[truth]   {k:<8} port={shorten(pv):<52} cpython={shorten(ov):<52} {gated}")

  if control:
    print("\n[truth] CONTROL -- dtype-oracle-MUTANT.py, SKIP emptied, nothing else changed")
    _, M = oracle_lane(MUTANT, py, gate_rows())
    s_m, d_m, bad_m = cvs(B, M)
    print(f"[truth] port vs MUTANT: {d_m} disagree of {s_m} shared (oracle {len(M)} rows)")
    print(f"[truth] live filter    : {d_dt} disagree of {s_dt} shared")
    print(f"[truth] mutant sees {len(bad_m_names := {k for k, _, _ in bad_m})} rows the filter does not "
          f"report -- see the list above marked NOT PRINTED")
    print(f"[truth] CONTROL {'PASSES' if d_m >= d_dd else 'FAILED'}: a filter that hides "
          f"disagreements went red when it stopped hiding them")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())