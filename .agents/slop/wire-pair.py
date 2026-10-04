#!/usr/bin/env python3
"""wire-pair.py -- ONE (port, oracle) pair: shared row names, and every disagreement NAMED.

This exists because a survey answers a different question. `rebase-scan-oracles.py` asks "does
this oracle share ANY row name with this port"; that is how a wire-up LIST is computed, and it
is not a verdict. Four things this adds, each of which has cost real time on this tree:

  * Every disagreement is named, with both values. A count is not a bug report. The six
    `PTX tensor_cores sm_75` rows that used to read `py=[half->float]` were only fixable
    because the names were printed. See RETIRED CONTROL below -- those six are gone.
  * UNSHARED names are counted from BOTH sides. An oracle that shares a handful of names
    gates that handful; the rest are decoration. `ops_cpu` is wired on a partial
    intersection (rebase-gate.py records it; this script prints the live counts and does
    not re-type them). A number typed here is how "3 of 1042" survived after 1042 had
    stopped being that oracle's size.
  * The oracle's exit status and its row count are reported SEPARATELY from the shared count,
    because GUARD 2 ("a lane that printed nothing compared nothing") is decided on the LANE and
    not on the intersection -- a shared count of 0 and a lane of 0 rows are different failures.
  * It says whether the port's rows are FULLY covered. Agreement on a subset is a different
    claim from agreement on every port row, even though both can print disagree=0.

RETIRED CONTROL. The standing control used to be:

    wire-pair.py tinybendygrad/renderer/tc_ptx.bend ".agents/slop/tcptx-oracle.py rows"

and the docstring demanded 6 disagreements, on the theory that a 0 meant this script had
stopped working. That bug was fixed. `dtypes.half.name` is `"f16"` (tinygrad/dtype.py:120-137);
the aliases at :140-142 do not change `.name`. The six stale `py=` literals (`half->float`
and the other pre-rename spellings) were corrected in the port. A live pair against
`tcptx-oracle.py stage2` -- stage2 is the half this port prints; `rows` is stage1+stage2 --
reads 0 disagreements on the shared names. Demanding that the 6 stay red is a trap: the
moment the control fails, the tempting repair is to put the bug back.

A count-based control is retired for that reason. It asserts a bug, not the instrument.
When the bug is fixed the control fails for the right reason and invites the wrong repair.
Do not re-add those rows to make a run red.

The on-disk cache `$TMPDIR/rebase-wired-rows/tinybendygrad_renderer_tc_ptx.bend.json` was
written at 14:33, before the 14:59 fix, and still holds the six. A reader that trusts it
without an mtime check resurrects the retired bug and calls it a live disagreement. This
script refuses a cache older than the source.

STANDING CONTROL. `python3 .agents/slop/wire-pair.py --control`

It does not look for a known-bad count on the live tree. It writes a self-contained fixture
(no relative import -- a scratch copy of a real port cannot resolve `import ./../helpers.bend`)
into a work directory outside `tinybendygrad/`, then:

  1. CLEAN    unmodified fixture agrees with its oracle, including `control row` (a space
              in the name). A `^(\\S+) = ` parser drops that name; this phase is then not CLEAN.
  2. RED      the COPY is mutated. The needle must occur exactly once, or the script prints
              `PATCH DID NOT APPLY` and exits 1. The moved rows are named. A mutation that
              moves nothing is a broken harness, not a pass.
  3. CLEAN    the copy is restored from the pristine bytes and agrees again.

The live tree is never opened for writing.

  usage: python3 .agents/slop/wire-pair.py --control
         python3 .agents/slop/wire-pair.py PORT ORACLE_SPEC [ORACLE_SPEC...]
         PORT is a .bend path, ORACLE_SPEC is `path` or `path arg` exactly as BASE_ORACLES.
"""
import hashlib, os, pathlib, subprocess, sys
import patch_not_apply as PNA

from wire_parse import read_fresh_cache, rows, stripped_env, write_cache

REPO = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
WORK = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "opencode" / "wire-pair-control"

# The fixture is the control's own port. It is generated into WORK on every run and
# never written under tinybendygrad/. Two emitters, because this tree has both and a
# parser that keeps only one will look clean on the other.
FIXTURE = """\
import Base

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print("control row = clean")
    IO.print("control_tight=clean")
"""
ORACLE_TEXT = "control row = clean\ncontrol_tight=clean\n"
PATCHES = (
  ('IO.print("control row = clean")', 'IO.print("control row = RED-PLANTED")', "control row"),
  ('IO.print("control_tight=clean")', 'IO.print("control_tight=RED-PLANTED")', "control_tight"),
)
CLEAN_VALUE = "clean"
RED_VALUE = "RED-PLANTED"


def bend_rows(port, tries=3):
  src = REPO / port
  cached, why = read_fresh_cache(CACHE, port, src)
  if why == "fresh":
    return cached
  if why == "stale":
    print(f"  ({port} cache is older than the source; not using it)", file=sys.stderr)
  for i in range(tries):
    r = subprocess.run(["./bin/bend", port], cwd=REPO, capture_output=True, text=True, timeout=1800)
    d = rows(r.stdout)
    if d:
      write_cache(CACHE, port, d)
      return d
    print(f"  ({port} printed 0 rows on attempt {i + 1})", file=sys.stderr)
  return {}


def run(argv, timeout=1800):
  try:
    return subprocess.run(argv, cwd=REPO, capture_output=True, text=True,
                          env=stripped_env({"DEV": "NULL"}), timeout=timeout)
  except subprocess.TimeoutExpired:
    return None


def bend_file(path, tries=3):
  """Run bend on a path that is not a repo port. No cache: a cached mutant is how a
  control reports the previous run's answer."""
  for i in range(tries):
    r = subprocess.run(["./bin/bend", str(path)], cwd=REPO, capture_output=True, text=True,
                       timeout=1800)
    d = rows(r.stdout)
    if d:
      return d, r
    err = " ".join(r.stderr.split())[-160:]
    print(f"  ({path.name} printed 0 rows on attempt {i + 1}; {err})", file=sys.stderr)
  return {}, None


def plant(text, needle, repl):
  """Exactly one occurrence, or the patch did not apply. A miss used to be reported
  as '0 rows', which is indistinguishable from a fixture bend never started."""
  n = text.count(needle)
  if n != 1:
    print("%s  needle=%r occurrences=%d" % (PNA.not_applied(), needle, n))
    return None
  return text.replace(needle, repl, 1)


def phase(tag, got, expect):
  shared = sorted(set(got) & set(expect))
  bad = [k for k in shared if got[k] != expect[k]]
  missing = [k for k in expect if k not in got]
  print(f"  phase {tag}: shared={len(shared)} disagree={len(bad)}"
        + (f"  missing={missing}" if missing else ""))
  for k in bad:
    print(f"    MOVED {k}\n      bend   {got.get(k, '')[:220]}\n      oracle {expect[k][:220]}")
  return shared, bad, missing


def control():
  """CLEAN, then RED, then CLEAN, on a copy. Exits 1 unless all three hold and the
  planted rows are the ones that moved."""
  if "tinybendygrad" in WORK.parts or "tinygrad" in WORK.parts:
    print("REFUSING: control work dir is inside a live tree")
    return 1
  if WORK.resolve().is_relative_to(REPO / "tinybendygrad"):
    print("REFUSING: control work dir resolves inside tinybendygrad")
    return 1
  # The guard must be seen to fire. A needle that is not in the text is the case
  # a dead patch used to report as "0 rows".
  print("GUARD absent-needle (not a phase; a dead patch must say so, not '0 rows'):")
  if plant("no needle here", PATCHES[0][0], PATCHES[0][1]) is not None:
    print("GUARD FAILED: an absent needle was treated as applied")
    return 1

  WORK.mkdir(parents=True, exist_ok=True)
  port = WORK / "fixture.bend"
  oracle = WORK / "oracle.py"
  pristine = FIXTURE.encode()
  port.write_bytes(pristine)
  oracle.write_text("print(" + repr(ORACLE_TEXT) + ", end='')\n")
  expect = rows(ORACLE_TEXT)
  print(f"CONTROL work={WORK}  (copy; the live tree is not opened for writing)")
  print(f"  fixture sha256={hashlib.sha256(pristine).hexdigest()}")

  try:
    got, _ = bend_file(port)
    shared, bad, missing = phase("clean", got, expect)
    if not got or missing or bad or any(got[k] != CLEAN_VALUE for k in expect):
      print("CONTROL FAIL at clean: an unmodified fixture that is not CLEAN means the "
            "instrument cannot see agreement. A `^(\\S+) = ` parser drops `control row`.")
      return 1
    print("  reading: CLEAN")

    text = port.read_text()
    for needle, repl, _name in PATCHES:
      text = plant(text, needle, repl)
      if text is None:
        return 1
    port.write_text(text)
    if port.read_bytes() == pristine:
      print("PATCH DID NOT APPLY  the copy is byte-identical to the pristine fixture")
      return 1

    got, _ = bend_file(port)
    shared, bad, missing = phase("mutated", got, expect)
    moved = [k for k in expect if k in got and got[k] != expect[k]]
    if not got:
      print("CONTROL FAIL at mutated: bend printed 0 rows. That is not 0 disagreements.")
      return 1
    extra = [k for k in bad if k not in expect]
    if missing or set(moved) != set(expect) or any(got[k] != RED_VALUE for k in expect) or extra:
      print("MUTATION MOVED NO ROW" if not moved else
            "CONTROL FAIL at mutated: the rows that moved are not exactly the planted ones")
      return 1
    print("  reading: RED")

    port.write_bytes(pristine)
    if port.read_bytes() != pristine:
      print("RESTORE FAILED: the copy is not the pristine bytes")
      return 1
    got, _ = bend_file(port)
    shared, bad, missing = phase("restored", got, expect)
    if not got or missing or bad or any(got[k] != CLEAN_VALUE for k in expect):
      print("CONTROL FAIL at restored: the copy was put back and the instrument is still red")
      return 1
    print("  reading: CLEAN")
    print("CONTROL PASS  clean / red / restored")
    return 0
  finally:
    for p in (port, oracle):
      p.unlink(missing_ok=True)


def main():
  if "--control" in sys.argv:
    return control()
  a = [x for x in sys.argv[1:] if x != "--control"]
  if len(a) < 2:
    print("usage: wire-pair.py --control   |   wire-pair.py PORT ORACLE_SPEC...", file=sys.stderr)
    return 2
  port, specs = a[0], a[1:]
  b = bend_rows(port)
  print(f"{port}: {len(b)} rows")
  for spec in specs:
    argv = spec.split()
    r = run([sys.executable, *argv])
    if r is None:
      print(f"\n{spec}: TIMED OUT -- a probe that hangs is not an oracle")
      continue
    o = rows(r.stdout)
    shared = sorted(set(o) & set(b))
    bad = [k for k in shared if o[k] != b[k]]
    only_o, only_b = sorted(set(o) - set(b)), sorted(set(b) - set(o))
    print(f"\n{spec}")
    print(f"  rc={r.returncode} oracle_rows={len(o)} shared={len(shared)} disagree={len(bad)}"
          f"  oracle_only={len(only_o)} port_only={len(only_b)}"
          f"  {'PORT FULLY COVERED' if b and not only_b else 'PORT PARTLY COVERED' if b else 'PORT PRINTED NOTHING'}")
    if r.returncode:
      print(f"  stderr: {' '.join(r.stderr.split())[-300:]}")
    for k in bad[:40]:
      print(f"  DISAGREE {k}\n    bend   {b[k][:220]}\n    oracle {o[k][:220]}")
    if len(bad) > 40:
      print(f"  ... {len(bad) - 40} more")
    if only_o and len(only_o) <= 15:
      print(f"    oracle-only: {only_o}")
    if only_b and len(only_b) <= 15:
      print(f"    port-only: {only_b}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
