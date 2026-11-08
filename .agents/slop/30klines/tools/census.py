#!/usr/bin/env python3
"""Write content/census.json from tinygrad's OWN line counter.

sz.py is the project's instrument, not ours: it counts the distinct lines that
carry a whitelisted token, skips docstrings, and skips runtime/autogen and
viz/assets. Re-implementing that rule here would be a second copy that rots,
so this loads sz.py by path and calls gen_stats — a generator's own
declaration, which is the only kind of denominator worth trusting.

sz.py imports tabulate and tinygrad.uop, so run it with its deps:

    uv run --no-project --with tabulate --with numpy --python 3.12 \
      python .agents/slop/30klines/tools/census.py

The tree defaults to the vendored latest upstream, because the course cites
that tree, not this repo's pinned one.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent.parent   # repo root
DEFAULT_TREE = ROOT / "references" / "tinygrad-latest"
NONCORE = {"tinygrad/llm", "tinygrad/nn", "tinygrad/renderer", "tinygrad/runtime", "tinygrad/viz"}


def load_sz():
  spec = importlib.util.spec_from_file_location("sz", ROOT / "sz.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def git_commit(tree: pathlib.Path) -> str | None:
  try:
    return subprocess.run(["git", "-C", str(tree), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
  except (subprocess.CalledProcessError, FileNotFoundError):
    return None


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--tree", default=str(DEFAULT_TREE))
  args = ap.parse_args()
  tree = pathlib.Path(args.tree).resolve()
  if not (tree / "tinygrad").is_dir():
    print(f"no tinygrad/ under {tree}", file=sys.stderr)
    return 2

  table = load_sz().gen_stats(str(tree))
  files = {name: lines for name, lines, _ in table}
  groups: dict[str, int] = {}
  for name, lines, _ in table:
    key = "/".join(name.split("/")[:2])
    groups[key] = groups.get(key, 0) + lines

  out = {
    "tree": str(tree.relative_to(ROOT)) if tree.is_relative_to(ROOT) else str(tree),
    "commit": git_commit(tree),
    "instrument": "sz.py gen_stats",
    "total": sum(files.values()),
    "core": sum(v for k, v in groups.items() if k not in NONCORE),
    "groups": dict(sorted(groups.items(), key=lambda kv: -kv[1])),
    "files": dict(sorted(files.items())),
  }
  path = HERE.parent / "content" / "census.json"
  path.write_text(json.dumps(out, indent=2) + "\n")

  print(f"{'group':26} lines")
  for k, v in out["groups"].items():
    print(f"  {k:24} {v:>6}")
  print(f"\n  {'core':24} {out['core']:>6}")
  print(f"  {'total':24} {out['total']:>6}")
  print(f"  {'files':24} {len(files):>6}")
  print(f"\nwrote {path.relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
