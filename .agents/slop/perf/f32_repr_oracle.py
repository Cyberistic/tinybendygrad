"""f32_repr_oracle.py -- compare tinybendygrad/uop/f32_repr.bend against CPython's repr.

The port cannot build an F32 from its bits (Base exposes `F32.bits` and nothing that goes the other
way), so the population is carried as DECIMAL LITERALS: each is `repr(float(f32))` from CPython,
which reads back to exactly that f32 in both lanes. The driver is generated here rather than
hand-written because the population is the point -- a hand list of four values would be a fixture
against nobody.

Writes .agents/slop/perf/f32_repr.rows: `<literal>|<cpython repr>|<bend repr>|<ok>`.
"""
import pathlib
import random
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
DRV = ROOT / ".agents/slop/perf/f32_repr_drv.bend"
ROWS = ROOT / ".agents/slop/perf/f32_repr.rows"


def f32(x: float) -> float:
  return struct.unpack("<f", struct.pack("<f", x))[0]


def population() -> list[float]:
  rnd = random.Random(11)
  out = []
  for _ in range(400):
    v = struct.unpack("<f", struct.pack("<I", rnd.getrandbits(32)))[0]
    if v == v and abs(v) != float("inf"):
      out.append(v)
  for k in range(-126, 128):
    v = struct.unpack("<f", struct.pack("<I", (127 + k) << 23))[0]
    out += [v, -v]
  for i in range(1, 2**23, 65521):
    out.append(struct.unpack("<f", struct.pack("<I", i))[0])
  out += [0.0, 1.0, 0.5, 3.0, 1e16, 1e15, 1e-4, 1e-5, 1.4426950408889634, 0.1,
          1 / 3, 3.4028235e38, 1.1754944e-38, 1.4e-45]
  seen, uniq = set(), []
  for v in out:
    v = f32(v)
    if v != v or abs(v) == float("inf"):
      continue
    b = struct.unpack("<I", struct.pack("<f", v))[0]
    if b in seen:
      continue
    seen.add(b)
    uniq.append(v)
  return uniq


def lit_expr(s: str) -> str:
  """A NEGATIVE LITERAL IS NOT A TERM IN A CALL POSITION on this tree ("expected a term, observed
  '-': the reader's `-` is a subtraction that wants both sides), so it is spelled as one."""
  return f"(0.0-{s[1:]} : F32)" if s.startswith("-") else s


def main() -> int:
  vals = population()
  lits = [repr(v) for v in vals]
  src = ["import Base", "import ./../../../tinybendygrad/uop/f32_repr.bend as R", "",
         "def j(xs: List<&1, String>, +acc: String) -> String:",
         "  match xs:", "    case Nil{}: acc",
         '    case h <> t: j(t, String.concat([acc, "\\n", h]))', "",
         "def main() -> IO(Unit):",
         '  do IO<Unit>: IO.print(j([' + ", ".join(f"R.repr({lit_expr(s)})" for s in lits) + '], ""))', ""]
  DRV.write_text("\n".join(src))
  r = subprocess.run(["./bin/bend", str(DRV.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True)
  got = r.stdout.lstrip("\n").splitlines()   # the fold prepends a newline to the first row
  if r.returncode != 0 or len(got) != len(lits):
    print(f"driver rc={r.returncode} rows={len(got)} want={len(lits)}")
    print((r.stdout + r.stderr)[:1200])
    return 1
  bad = 0
  rows = []
  for lit, g in zip(lits, got):
    ok = lit == g
    bad += not ok
    rows.append(f"{lit}|{lit}|{g}|{'yes' if ok else 'no'}")
  ROWS.write_text("# f32_repr.rows -- .agents/slop/perf/f32_repr_oracle.py\n"
                  "# literal|cpython_repr|bend_repr|ok\n" + "\n".join(rows) + "\n")
  print(f"f32_repr: {len(lits)} values, {len(lits) - bad} identical, {bad} differ")
  for row in rows:
    if row.endswith("|no"):
      print("  " + row)
  return 0 if bad == 0 else 1


if __name__ == "__main__":
  raise SystemExit(main())
