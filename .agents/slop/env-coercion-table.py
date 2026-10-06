#!/usr/bin/env python3
"""
MEASURE tinygrad's getenv coercion table FROM LIVE CPYTHON.

  tinygrad/helpers.py:162  def getenv(key, default=0): return type(default)(os.getenv(key, default))
  tinygrad/helpers.py:186  self.value, self.key = getenv(key, default_value), key

The ONLY coercion is `type(default)` applied to whatever `os.getenv` returned: the
raw string when the key is set, the DEFAULT OBJECT ITSELF when it is not.  Nothing
in tinygrad validates a flag value; a bad one raises out of the import.

Everything below is measured by CALLING CPython:
  part 1 spies on `os.getenv` before tinygrad.helpers is imported, so the
         (key, default, type(default)) triples are the interpreter's own, not a
         transcription of the source;
  part 2 calls `H.getenv` itself with fresh keys, one per (default type, probe);
  part 3 re-imports tinygrad in a fresh process with the env actually set, for one
         real flag of each default type, to confirm part 2 is not an artefact.

Run:  uv run python .agents/slop/env-coercion-table.py > .agents/slop/env-coercion-table.txt
"""
import ast, json, os, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# probes chosen to separate int() / str() / float() / bool() apart
PROBES = ["<unset>", "", "0", "1", "2", "3", "-1", "true", "false", "True", "no",
          "off", "0.5", "1e3", "1.5", "abc", " 2 ", "010", "1_000", "0x10",
          "nan", "inf", "-0", "256", "1,000"]


def probe_coercion(defaults):
  """part 2: call H.getenv for real, in one process, fresh key per call."""
  body = r'''
import sys, os, json
sys.path.insert(0, @@REPO@@)
import tinygrad.helpers as H
jobs = json.loads(sys.argv[1])
out = []
for key, dflt, probe, unset in jobs:
  if unset: os.environ.pop(key, None)
  else: os.environ[key] = probe
  try:
    v = H.getenv(key, eval(dflt))
    out.append([key, repr(v), type(v).__name__])
  except BaseException as e:
    out.append([key, "{}: {}".format(type(e).__name__, e), "RAISED"])
print("@@" + json.dumps(out))
'''.replace("@@REPO@@", repr(REPO))
  jobs = []
  for di, (dflt, _) in enumerate(defaults):
    for pi, probe in enumerate(PROBES):
      jobs.append(["K%d_%d" % (di, pi), dflt, probe, probe == "<unset>"])
  p = subprocess.run([sys.executable, "-c", body, json.dumps(jobs)],
                     capture_output=True, text=True, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return json.loads(ln[2:])
  raise SystemExit("probe failed:\n" + p.stderr)


def spy_defaults():
  """part 1: the (key, default, type(default)) triples helpers.py's import makes."""
  body = r'''
import sys, os, json
sys.path.insert(0, @@REPO@@)
real = os.getenv
seen = []
def spy(key, default=None):
  seen.append([key, repr(default), type(default).__name__])
  return real(key, default)
os.getenv = spy
import tinygrad.helpers as H
print("@@" + json.dumps(seen))
'''.replace("@@REPO@@", repr(REPO))
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return json.loads(ln[2:])
  raise SystemExit("spy failed:\n" + p.stderr)


def live_flag(key, probe):
  """part 3: one real flag, real process, real environment."""
  env = dict(os.environ)
  for k in list(env):
    if k in ("DEV", "VIZ", "DEBUG", "JIT", "NO_COLOR", "SPEC", "CPU_COUNT"):
      env.pop(k, None)
  if probe != "<unset>":
    env[key] = probe
  body = r'''
import sys
sys.path.insert(0, @@REPO@@)
import tinygrad.helpers as H
print("@@" + repr(getattr(H, @@KEY@@).value))
'''.replace("@@REPO@@", repr(REPO)).replace("@@KEY@@", json.dumps(key))
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, env=env, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return ln[2:]
  return "RAISED: " + (p.stderr.strip().splitlines() or ["?"])[-1]


def live_getenv(key, probe, default_expr):
  """part 6: one H.getenv call whose DEFAULT is a bool, in a fresh process."""
  env = dict(os.environ)
  env.pop(key, None)
  if probe != "<unset>":
    env[key] = probe
  body = r'''
import sys, os
sys.path.insert(0, @@REPO@@)
import tinygrad.helpers as H
try: print("@@" + repr(H.getenv(@@KEY@@, @@DEF@@)))
except BaseException as e: print("@@RAISED: %s: %s" % (type(e).__name__, e))
'''.replace("@@REPO@@", repr(REPO)).replace("@@KEY@@", json.dumps(key)).replace("@@DEF@@", default_expr)
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, env=env, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return ln[2:]
  return "RAISED: " + (p.stderr.strip().splitlines() or ["?"])[-1]


def live_colored(probe):
  """part 7: the real helpers.colored observable, one process per probe."""
  env = dict(os.environ)
  env.pop("NO_COLOR", None)
  if probe != "<unset>":
    env["NO_COLOR"] = probe
  body = r'''
import sys, os
sys.path.insert(0, @@REPO@@)
import tinygrad.helpers as H
print("@@%r bool(NO_COLOR)=%s" % (H.colored("S","red"), bool(H.NO_COLOR)))
'''.replace("@@REPO@@", repr(REPO))
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, env=env, cwd=REPO)
  for ln in p.stdout.splitlines():
    if ln.startswith("@@"):
      return ln[2:]
  return "RAISED: " + (p.stderr.strip().splitlines() or ["?"])[-1]


def main():
  print("# tinygrad getenv coercion -- measured from live CPython")
  print("# produced by .agents/slop/env-coercion-table.py")
  print("#   form: type(default)(os.getenv(key, default))     helpers.py:162")
  print("#   called: self.value = getenv(key, default_value)   helpers.py:186")
  print()

  print("## PART 1 -- every os.getenv call tinygrad.helpers makes at import, with the")
  print("## default it passes.  This is the interpreter's own reading, obtained by")
  print("## replacing os.getenv with a spy BEFORE the import, so no value is transcribed.")
  seen = spy_defaults()
  by_type = {}
  for key, dflt, tname in seen:
    by_type.setdefault(tname, []).append((key, dflt))
  for tname in sorted(by_type):
    keys = by_type[tname]
    print("  type(default) == %-6s  %d calls: %s" % (tname, len(keys), ", ".join(k for k, _ in keys)))
    for k, d in keys:
      print("        %-28s default=%s" % (k, d))
  print()

  print("## PART 2 -- the coercion itself: type(default)(os.getenv(key, default))")
  print("## one real H.getenv call per cell, in a fresh key so functools.cache is cold.")
  defaults = [("0", "int (the no-default case, helpers.py:158)"),
              ("1", "int"),
              ("-1", "int"),
              ("2", "int"),
              ("False", "bool"),
              ("True", "bool"),
              ("0.0", "float"),
              ("'float32'", "str"),
              ("''", "str"),
              ("b'x'", "bytes, for completeness")]
  rows = probe_coercion(defaults)
  print()
  hdr = "  %-10s %-34s" % ("probe", "input")
  for dflt, label in defaults:
    hdr += " | %-20s" % ("type(%s)=%s" % (dflt, label.split()[0]))
  print(hdr)
  for pi, probe in enumerate(PROBES):
    line = "  %-10s %-34s" % (repr(probe), "<unset>" if probe == "<unset>" else "os.getenv returns a str")
    for di in range(len(defaults)):
      val, vt = rows[di * len(PROBES) + pi][1:]
      line += " | %-20s" % ("RAISED" if vt == "RAISED" else val)
    print(line)
  print()

  print("## PART 3 -- the same cells against REAL flags in a REAL process, so part 2 is")
  print("## not an artefact of calling getenv directly.  One flag per default type.")
  for key, probe in [("NO_COLOR", "0"), ("NO_COLOR", ""), ("NO_COLOR", "1"),
                     ("DEBUG", "0"), ("DEBUG", "3"), ("DEBUG", "true"),
                     ("DEFAULT_FLOAT", "bfloat16"), ("EMULATED_DTYPES", "bfloat16,half"),
                     ("SPEC", "-1"), ("PARALLEL", "3")]:
    print("  %-18s %-8s -> %s" % (key, repr(probe), live_flag(key, probe)))
  print()

  print("## PART 4 -- the bool trap, spelled out with the ContextVar dunders")
  body = r'''
import sys, os
sys.path.insert(0, @@REPO@@)
os.environ["NO_COLOR"] = "0"
import tinygrad.helpers as H
print("  NO_COLOR.value  =", repr(H.NO_COLOR.value))
print("  bool(NO_COLOR)  =", bool(H.NO_COLOR))
print("  NO_COLOR == 0   =", H.NO_COLOR == 0)
print("  NO_COLOR >= 1   =", H.NO_COLOR >= 1)
os.environ.pop("NO_COLOR")
'''.replace("@@REPO@@", repr(REPO))
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, cwd=REPO)
  sys.stdout.write(p.stdout)
  if p.returncode: sys.stdout.write("  RAISED: " + p.stderr.strip().splitlines()[-1] + "\n")
  print()

  print("## PART 5 -- DEV is not a plain ContextVar: _DEV overrides value with a setter,")
  print("## so `bool(DEV)` is bool([Target()]) which is True for EVERY environment.")
  body = r'''
import sys, os, subprocess
sys.path.insert(0, @@REPO@@)
for probe in ["<unset>", "", "0", "CPU", "PYTHON"]:
  env = dict(os.environ); env.pop("DEV", None)
  if probe != "<unset>": env["DEV"] = probe
  src = "import sys;sys.path.insert(0,\\"" + @@RPT@@ + "\\");import tinygrad.helpers as H;print(bool(H.DEV), H.DEV.value)"
  print("  DEV=%-10s -> %s" % (repr(probe), subprocess.run([sys.executable,"-c",src],
        capture_output=True,text=True,env=env).stdout.strip()))
'''.replace("@@REPO@@", repr(REPO)).replace("@@RPT@@", REPO)
  p = subprocess.run([sys.executable, "-c", body], capture_output=True, text=True, cwd=REPO)
  sys.stdout.write(p.stdout)
  if p.returncode: sys.stdout.write("  RAISED: " + p.stderr.strip().splitlines()[-1] + "\n")
  print()

  print("## PART 6 -- the three flags whose DEFAULT IS A BOOL: PMA (ops_nv.py:27),")
  print("## SQTT (ops_amd.py:31) and PMC (ops_amd.py:34) all take")
  print("## abs(VIZ.value)>=2, so with VIZ unset their default is `False` and")
  print("## type(default) is `bool`.  These are the ONLY bool-coerced flags.")
  for probe in ["<unset>", "", "0", "1", "false", "no"]:
    r = live_getenv("PMA_shape", probe, "abs(H.VIZ.value)>=2")
    print("  PMA-shaped getenv %-8s -> %s" % (repr(probe), r))
  print()

  print("## PART 7 -- NO_COLOR END TO END through helpers.colored, which is the")
  print("## observable the port's `colored`/`no_color_of` has to reproduce.")
  print("## helpers.py:41 is `if NO_COLOR: return st`, so colour is OFF iff")
  print("## bool(int(os.getenv('NO_COLOR', 0))) is True.")
  for probe in ["<unset>", "", "0", "1", "00", "-0", "2", "0.0", "false", "0 "]:
    print("  NO_COLOR=%-9s -> %s" % (repr(probe), live_colored(probe)))
  print()
  print("## the port's own rule for the same input, helpers.bend:49")
  print("##   no_color_of(v) = no_color_of.go(String.is_empty(v))")
  print("##   no_color_of.go(True) = False ; no_color_of.go(False) = True")
  print("## i.e. no_color_of(v) = not String.is_empty(v).  Which says: any")
  print("## non-empty text switches colour OFF.  CPython says: a non-empty text")
  print("## that int() reads as 0 leaves colour ON.  The two disagree on every")
  print("## int-zero string.")


if __name__ == "__main__":
  main()