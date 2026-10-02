#!/usr/bin/env python3
"""rebase-break.py -- PROVE an oracle is capable of being red, by breaking the PORT and
reverting it.

WHY THIS IS A SCRIPT AND NOT A THING YOU DO BY HAND. "An oracle you have not seen fail is an
oracle you have not tested", and the reason is not philosophical: `support/memory.bend`'s
differ reported `0 disagreements` over 547 rows that existed on only ONE side, so a green
run there was the absence of a comparison dressed as its result. A perturbation that is
performed, observed and reverted under a SHA-256 check is the only version of this that can
be cited in a report.

THE REVERT IS ASSERTED, NOT INTENDED. The port is copied aside, one line is rewritten, the
oracle is re-run, and the copy is restored and its digest compared with the original. If the
digests differ the script exits 1 with the file left ALONE and the reason, because a
half-reverted port is worse than a red one.

    python3 .agents/slop/rebase-break.py --port P --oracle O [--find SUBST] [--replace SUBST]
"""
import argparse, hashlib, pathlib, shutil, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]


def sha(p):
  return hashlib.sha256(p.read_bytes()).hexdigest()


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def lanes(port, oracle, py):
  a = subprocess.run(["./bin/bend", str(port)], cwd=REPO, capture_output=True, text=True)
  o = subprocess.run([py, str(oracle)], cwd=REPO, capture_output=True, text=True,
                     env=dict(__import__("os").environ, DEV="NULL"))
  return a, o, rows(a.stdout), rows(o.stdout)


def report(tag, prows, orows):
  shared = sorted(set(prows) & set(orows))
  red = [(k, prows[k], orows[k]) for k in shared if prows[k] != orows[k]]
  print(f"  {tag}: port_rows={len(prows)} oracle_rows={len(orows)} shared={len(shared)} "
        f"DISAGREE={len(red)}")
  for k, p, o in red:
    print(f"    RED {k}: port={p!r} oracle={o!r}")
  return red


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port", required=True)
  ap.add_argument("--oracle", required=True)
  ap.add_argument("--find", required=True, help="the exact line text to perturb")
  ap.add_argument("--replace", required=True)
  a = ap.parse_args()

  port, oracle = REPO / a.port, REPO / a.oracle
  py = str(REPO / ".venv/bin/python")
  # A backup beside the port, named for the PORT, and deleted on a verified revert: a
  # leftover copy of a 3000-line port in .agents/slop/rebase/ is how one unit's oracle went
  # missing before its commit, and a backup that outlives its perturbation is worse than no
  # backup because the next run cannot tell which perturbation it is reverting.
  keep = HERE / "rebase" / f"break-backup-{pathlib.Path(a.port).stem}.bend"
  keep.parent.mkdir(exist_ok=True)

  before_sha = sha(port)
  print(f"BREAK PROOF  {a.port}  against {a.oracle}")
  print(f"  port sha256 before = {before_sha}")

  _, _, p0, o0 = lanes(port, oracle, py)
  red0 = report("BEFORE", p0, o0)

  shutil.copy2(port, keep)
  text = keep.read_text()
  if text.count(a.find) != 1:
    print(f"  ABORT: the perturbation string occurs {text.count(a.find)} times in "
          f"{port.name}; it must occur exactly ONCE or this proves nothing")
    return 1
  port.write_text(text.replace(a.find, a.replace))
  print(f"  perturbed: {a.find!r} -> {a.replace!r}")

  try:
    _, _, p1, o1 = lanes(port, oracle, py)
    red1 = report("PERTURBED", p1, o1)
    moved = sorted(k for k in set(p0) & set(p1) if p0[k] != p1[k])
    print(f"  rows the perturbation moved: {moved}")
    if not moved:
      print("  RED PROOF FAILED: the perturbation moved NO port row, so it gated nothing")
      return 1
    new_red = [r for r in red1 if r not in red0]
    if not new_red:
      print("  RED PROOF FAILED: the perturbation moved a port row and the oracle did NOT "
            "notice -- the oracle is not comparing that row")
      return 1
    print(f"  RED PROVED: {len(new_red)} row(s) newly disagree with the oracle after the "
          f"perturbation, and were green before it")
  finally:
    shutil.copy2(keep, port)

  after_sha = sha(port)
  if after_sha != before_sha:
    print(f"  REVERT FAILED: {port.name} is not byte-identical to how it started. The "
          "perturbation is still in it and the backup is at " + str(keep))
    return 1
  keep.unlink(missing_ok=True)
  print("  REVERT VERIFIED byte-identical, backup discarded")
  return 0


if __name__ == "__main__":
  sys.exit(main())