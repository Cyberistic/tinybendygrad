#!/usr/bin/env python3
"""
Every place the Bend port names an env flag in a def and returns a CONSTANT for it.
That is the cleanest mechanical signal of "the port substituted the default":

    def HCQ_CACHE_THRESH() -> U32: 64        # ContextVar("HCQ_CACHE_THRESH", 64)

Also prints the same defs where the constant is NOT the default, and every gate row
(`row(` / `urow(` / `srow(` / `py=`) whose text names a flag or encodes a value equal
to a flag's default.

Run: uv run python .agents/slop/flag-def-scan.py > .agents/slop/flag-def-scan.txt
"""
import ast, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, "tinybendygrad")
PY = os.path.join(REPO, "tinygrad")
SKIP = ("autogen", "__pycache__", "test", "docs", "examples")


def defaults():
  out = {}
  for root, dirs, files in os.walk(PY):
    dirs[:] = [d for d in dirs if d not in SKIP]
    for f in files:
      if not f.endswith(".py"):
        continue
      try:
        tree = ast.parse(open(os.path.join(root, f), encoding="utf-8",
                               errors="replace").read())
      except (SyntaxError, OSError):
        continue
      for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
          continue
        n = getattr(node.func, "id", None) or getattr(node.func, "attr", None)
        if n not in ("ContextVar", "getenv") or not node.args:
          continue
        k = node.args[0]
        if not (isinstance(k, ast.Constant) and isinstance(k.value, str)):
          continue
        d = node.args[1] if n == "ContextVar" and len(node.args) > 1 else (
            node.args[1] if len(node.args) > 1 else None)
        if d is None:
          continue
        try:
          v = ast.literal_eval(d)
        except (ValueError, SyntaxError):
          continue
        out.setdefault(k.value, []).append((type(v).__name__, v))
  return out


def main():
  ds = defaults()
  flags = sorted(ds)
  print("# (1) a Bend def NAMED AFTER a flag that returns a constant")
  print("# (2) gate rows (`row(`/`urow(`/`srow(`/`lrow(`/...) that NAME a flag")
  print("# (3) `py=` expectations anywhere in .agents/slop/*.py that mention a flag")
  print()
  n1 = n2 = 0
  for root, dirs, files in os.walk(BEND):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for f in sorted(files):
      if not f.endswith(".bend"):
        continue
      p = os.path.join(root, f)
      rel = os.path.relpath(p, BEND)
      lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
      for i, ln in enumerate(lines, 1):
        code = ln.split("#")[0].rstrip()
        s = ln.strip()
        if s.startswith("#"):
          continue
        m = re.match(r"def ([A-Z][A-Z0-9_]*)\(\)\s*->\s*(\w+)\s*:\s*(.+)$", code)
        if m and m.group(1) in ds:
          print("1) %-34s def %s() -> %s: %s   [defaults %s]" %
                ("%s:%d" % (rel, i), m.group(1), m.group(2), m.group(3).strip()[:60],
                 ds[m.group(1)]))
          n1 += 1
        if re.match(r"(?:def|\s)\w*[rows]?\(\s*\"", code) or re.search(r"\brow\(", code):
          for fl in flags:
            if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(fl), code):
              print("2) %-34s %s   [defaults %s]" %
                    ("%s:%d" % (rel, i), code.strip()[:100], ds[fl]))
              n2 += 1
              break
  print()
  print("# (1) count %d   (2) count %d" % (n1, n2))


if __name__ == "__main__":
  main()