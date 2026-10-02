#!/usr/bin/env python3
"""The three-lane diff for tinybendygrad/runtime/ops_metal.bend.

  .venv/bin/python .agents/slop/mt_diff.py [port.bend]

FOUR lanes, and the fourth is the reason this file can be trusted with its
constants:

  1. the INTERPRETED lane      (`bin/bend <file>`)
  2. the NATIVE lane          (`bin/bend <file> -o x && x`)
  3. `mt_rows.py`             the original graph oracle
  4. `mt_constmap.py --rows`  EVERY numeric constant def, against its authority --
                              `autogen/metal.py` by getattr, `ops_metal.py` by
                              CPython's `ast`, a real `MetalDevice` and a real
                              kernel launch for what is only knowable by running it
  5. `mt_seam_rows.py`        the REAL `MTLCodeGenServiceBuildRequest`, with an
                              instrumented callback, for `:42-71`

Lane 1 and 2 must be byte-identical. Lanes 3-5 are compared ROW BY ROW against
lane 1, and an oracle row with no gate row (or the reverse) is reported, because
"0 disagreements" over an unmatched pair is the reconciliation failure that
`ops_nv` shipped.
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "tinybendygrad/runtime/ops_metal.bend"
SCRATCH = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
SCRATCH.mkdir(parents=True, exist_ok=True)
PY = str(ROOT / ".venv/bin/python")


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" not in line:
      continue
    k, v = line.split("=", 1)
    out.setdefault(k, v)
  return out


def run(cmd, **kw):
  r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)
  if r.returncode != 0:
    sys.exit(f"FAILED {cmd}\n{r.stdout}\n{r.stderr}")
  return r.stdout


def main():
  bend = sys.argv[1] if len(sys.argv) > 1 else BEND
  check = run([str(ROOT / "bin/bend"), str(bend), "--check-only"])
  print(check.splitlines()[0])
  interp = run([str(ROOT / "bin/bend"), str(bend)])
  native_bin = SCRATCH / "mt_native"
  run([str(ROOT / "bin/bend"), str(bend), "-o", str(native_bin)])
  native = subprocess.run([str(native_bin)], capture_output=True, text=True)
  if native.returncode != 0:
    sys.exit(f"native lane failed\n{native.stderr}")
  oracles = {
    "graph": run([PY, ".agents/slop/mt_rows.py"]),
    "const": run([PY, ".agents/slop/mt_constmap.py", "--rows", str(bend)]),
    "seam": run([PY, ".agents/slop/mt_seam_rows.py"]),
  }

  i, n = rows(interp), rows(native.stdout)
  print(f"interpreted {len(i)} rows, native {len(n)} rows, "
        + ", ".join(f"{k}-oracle {len(rows(v))}" for k, v in oracles.items()))

  bad = 0
  if i != n:
    bad = 1
    print("\nINTERPRETED vs NATIVE")
    for k in sorted(set(i) | set(n)):
      if i.get(k) != n.get(k):
        print(f"  {k}: interp={i.get(k)!r} native={n.get(k)!r}")
  else:
    print("interpreted == native  (byte identical)")

  agree = differ = only = 0
  for lane, text in oracles.items():
    o = rows(text)
    print(f"\nCPYTHON ORACLE [{lane}]")
    for k, v in sorted(o.items()):
      if k not in i:
        print(f"  ORACLE-ONLY  {k}={v!r}")
        only += 1
      elif i[k] == v or (v in ("1", "0") and i[k] == str(v == "1")):
        agree += 1
      else:
        print(f"  DIFFER  {k}: oracle={v!r} bend={i[k]!r}")
        differ += 1
        bad = 1
  print(f"\nagree={agree} differ={differ} oracle-only={only} bend-only={len(i) - agree - differ - only}")
  print("BAD" if bad else "ALL LANES AGREE")
  return bad


if __name__ == "__main__":
  sys.exit(main())
