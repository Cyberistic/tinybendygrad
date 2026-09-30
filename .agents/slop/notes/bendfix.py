#!/usr/bin/env python3
"""Apply the mechanical fixes `bend --check-only` asks for, one error per run.

Two of the three error shapes in helpers.bend have exactly one right answer and
no judgement in it: "X (consumed more than once)" wants a `+` on that binder, and
"NOT A PARAMETER" at a def line wants the parameter's `+`. Everything else --
binder order, arity, coverage -- needs a human, so this refuses to guess and
says so.

usage: bendfix.py FILE [--apply]
       with --apply the fixes are written; without it they are printed.
"""
import re
import subprocess
import sys

BEND = "./bin/bend"


def check(path):
  out = subprocess.run([BEND, path, "--check-only"], capture_output=True, text=True)
  return out.stdout + out.stderr


def parse(err):
  loc = re.search(r"^\s*\d+>\|", err, re.M) and re.search(r"^(\d+)>\s*\|", err, re.M)
  m = re.search(r"- expected : (\S+)\n- observed : \S+ \(consumed more than once\)", err)
  if m:
    return "double-use", m.group(1), int(loc.group(1)) if loc else None
  return None, None, None


def apply_double_use(path, name, loc):
  lines = open(path).read().split("\n")
  if loc is None:
    return None, None
  # the binder is either a parameter in the flagged def header or a case binder
  i = loc - 1
  if re.match(r"^\s*case ", lines[i]):
    if f"+{name}" in lines[i]:
      return None, None
    lines[i] = re.sub(rf"(?<![\w+]){re.escape(name)}(?![\w])", f"+{name}", lines[i])
    return i + 1, lines[i]
  j = i
  while j >= 0 and not re.match(r"^def ", lines[j]):
    j -= 1
  if j < 0 or not re.search(rf"\+?{re.escape(name)}\s*:", lines[j]):
    return None, None
  lines[j] = re.sub(rf"(?<![\w+])\+?{re.escape(name)}(\s*:)", rf"+{name}\1", lines[j])
  return j + 1, lines[j]


def main():
  path = sys.argv[1]
  do = "--apply" in sys.argv
  for _ in range(200):
    err = check(path)
    if "SOME PROOFS FAIL" not in err:
      print(err.strip() or "clean")
      return
    kind, name, loc = parse(err)
    if kind != "double-use":
      print(err)
      return
    ln, new = apply_double_use(path, name, loc)
    if ln is None:
      print(f"no binder `{name}` found\n{err}")
      return
    if do:
      lines = open(path).read().split("\n")
      lines[ln - 1] = new
      open(path, "w").write("\n".join(lines))
      print(f"{ln}: +{name}")
    else:
      print(f"would set {ln}: {new}")


if __name__ == "__main__":
  main()
