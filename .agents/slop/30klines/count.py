"""Line census over the tinygrad spine. Denotes teachable lines: code only.

The progress bar needs a denominator it can defend, so this counts by rule and
prints every bucket rather than one number. Run from the repo root:

    .venv/bin/python .agents/slop/30klines/count.py
"""
import pathlib, sys

ROOTS = ["tinygrad/tensor.py", "tinygrad/mixin", "tinygrad/uop", "tinygrad/dtype.py", "tinygrad/device.py",
         "tinygrad/schedule", "tinygrad/codegen", "tinygrad/renderer", "tinygrad/engine", "tinygrad/helpers.py"]
OUTSIDE = ["tinygrad/runtime", "tinygrad/nn", "tinygrad/llm", "tinygrad/viz", "tinygrad/examples"]


def files(root: str, skip_autogen: bool = True):
  p = pathlib.Path(root)
  if p.is_file():
    return [p]
  return [q for q in p.rglob("*.py") if not (skip_autogen and "autogen" in q.parts)]


def classify(paths):
  total = comment = blank = code = 0
  for f in paths:
    lines = f.read_text().splitlines()
    total += len(lines)
    in_block = None
    for raw in lines:
      s = raw.strip()
      if not s:
        blank += 1
        continue
      if in_block:
        comment += 1
        if in_block in s:
          in_block = None
        continue
      if s.startswith("#"):
        comment += 1
        continue
      for q in ('"""', "'''"):
        if s.startswith(q):
          comment += 1
          if s.count(q) < 2:
            in_block = q
          break
      else:
        code += 1
  return dict(files=len(paths), total=total, code=code, comment=comment, blank=blank)


spine = [f for r in ROOTS for f in files(r)]
rest = [f for r in OUTSIDE for f in files(r)]
spine = list(dict.fromkeys(spine))
rest = [f for f in dict.fromkeys(rest) if f not in spine]
allh = spine + rest

for name, paths in (("SPINE", spine), ("OUTSIDE", rest), ("TREE", allh)):
  print(name, classify(paths))

by_dir = {}
for f in spine:
  key = f.parent if f.parent.name not in ("tinygrad",) else pathlib.Path("tinygrad/")
  by_dir.setdefault(str(key), []).append(f)
for k in sorted(by_dir, key=lambda k: -classify(by_dir[k])["code"]):
  print(f"{k:32} {classify(by_dir[k])}")

print("\nSPINE BY FILE (code lines)")
for f in sorted(spine, key=lambda f: -classify([f])["code"])[:24]:
  c = classify([f])
  print(f"{str(f):44} code={c['code']:5} total={c['total']:5}")
