"""IS THE REORDERING THE ONE I INTENDED? A sorted diff proves the 445 `name=value`
lines are byte-identical; it says nothing about WHICH FILE each landed in or about
how far it moved. This answers both, and it is the check that would catch a row
that kept its text but changed owner.

  python3 .agents/slop/cl_split_rows.py
"""
import pathlib, subprocess, sys, tempfile, collections

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "bin/bend"
PRE = ROOT / ".agents/slop/runs/base_runtime_ops_cl.bend.txt"
FILES = ["ops_cl", "ops_cuda", "ops_hip"]

# the OWNING FILE of a row, by its name. This is the whole point of the split:
# every row now sits in the file that ports the .py the row is about.
CROSS = {n for n in PRE_ROWS} if False else None


def owner(name: str) -> str:
  """the file that ports the .py the row is about -- the whole point of the split.

  `x_*` is `t_cross`, which is three-vendor by construction. `chk_<v>_*` and
  `vend_*_<v>` name their vendor in a MIDDLE token, so a suffix split on the
  last `_` is wrong for them (`vend_count_hp` splits to `hp`, `chk_cu_launch` to
  `alloc`); the vendor token is matched wherever it sits.
  """
  if name.startswith("x_"):
    return "ops_hip"
  if name == "timing_hp_scale_bits":
    return "ops_hip"                      # hp:57's `ret.value * 1e-3`
  toks = set(name.split("_"))
  if toks & {"hp", "hip"}:
    return "ops_hip"
  if toks & {"cu", "cuda"}:
    return "ops_cuda"
  if name.startswith("cu_") or name.startswith("cu-"):
    return "ops_cuda"
  if name.startswith("hp_") or name.startswith("hp-"):
    return "ops_hip"
  return "ops_cl"                         # `cl_*`, and the substrate's own rows


ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "bin/bend"
PRE = ROOT / ".agents/slop/runs/base_runtime_ops_cl.bend.txt"
FILES = ["ops_cl", "ops_cuda", "ops_hip"]

with tempfile.TemporaryDirectory() as td:
  td = pathlib.Path(td)
  per_file = {}
  for f in FILES:
    # bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes
    # prints ZERO rows, which is indistinguishable from "not started", so retry.
    for _ in range(5):
      subprocess.run([BEND, ROOT / f"tinybendygrad/runtime/{f}.bend"],
                     stdout=(td / f"{f}.txt").open("w"), stderr=subprocess.DEVNULL)
      if (td / f"{f}.txt").read_text().strip():
        break
    rows = [ln for ln in (td / f"{f}.txt").read_text().splitlines() if "=" in ln]
    per_file[f] = rows
    print(f"  runtime/{f}.bend  {len(rows)} rows")
    if not rows:
      sys.exit(f"{f}.bend printed ZERO rows -- that is the stack overflow, not a result")
  new = per_file["ops_cl"] + per_file["ops_cuda"] + per_file["ops_hip"]

pre = [ln for ln in PRE.read_text().splitlines() if "=" in ln]
assert len(pre) == len(new) == 445, (len(pre), len(new))
assert sorted(pre) == sorted(new), "a byte diff would have caught this first"

pre_at = {ln.split("=", 1)[0]: i for i, ln in enumerate(pre)}
new_at = {ln.split("=", 1)[0]: i for i, ln in enumerate(new)}
file_at = {ln.split("=", 1)[0]: f for f in FILES for ln in per_file[f]}

moved = [n for n in pre_at if pre_at[n] != new_at[n]]
print("\n  445 rows, 445 names, every name=value line byte-identical")
print(f"  rows whose POSITION changed: {len(moved)} (the regrouping by owning file)")
worst = max(moved, key=lambda n: abs(pre_at[n] - new_at[n]))
print(f"  largest move: {worst} {pre_at[worst]} -> {new_at[worst]}")

bad = [(n, f, owner(n)) for n, f in file_at.items() if owner(n) != f]
print(f"  rows in the file that does NOT own them: {len(bad)}")
for n, f, o in sorted(bad):
    print(f"    {n:28} in {f} should be {o}")
if bad:
    sys.exit("OWNERSHIP MISMATCH")

per = collections.Counter(file_at.values())
print(f"\n  rows per file: {dict(per)}")
print(f"  the {sum(1 for n in file_at if n.startswith('x_'))} `x_*` cross-vendor rows "
      f"are all in ops_hip.bend, the only file that can import both others")
