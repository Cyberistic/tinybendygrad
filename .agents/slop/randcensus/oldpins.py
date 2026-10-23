#!/usr/bin/env python3
"""oldpins.py -- THE OLD PORT PINS, PARSED OUT OF THE GATE FILE AT A NAMED COMMIT.

    .venv/bin/python .agents/slop/randcensus/oldpins.py [<lane.out> ...]

THE OLD PINS ARE NOT TRANSCRIBED HERE.  The first version of this file TRANSCRIBED them
and got `st_after_g` WRONG -- it dropped `ADD/2 SHRINK/3 CAST/1 ADD/2` -- and the wrong
transcription read as "the gate's pin was dead from birth", which was a FALSE CLAIM ABOUT
THE TREE.  So the old pins are PARSED from `gates/rand_census-gate.py` AS IT STOOD AT
`9b1be76b4` (the commit that set them), which is fetched once into
`gate-at-9101.py` by `git show` and then READ.

`git show` is a READ.  It is run with `env -u GIT_INDEX_FILE` because the tree's index is
armed (AGENTS.md) and the reading must not depend on it.
"""
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
AT = "9b1be76b4"
ARCHIVE = HERE / f"gate-at-{AT[:7]}.py"

if not ARCHIVE.is_file():
  env = dict(os.environ)
  env.pop("GIT_INDEX_FILE", None)
  ARCHIVE.write_bytes(subprocess.run(
    ["git", "show", f"{AT}:gates/rand_census-gate.py"],
    cwd=str(ROOT), capture_output=True, check=True, env=env).stdout)

_spec = importlib.util.spec_from_file_location("gate_old", ARCHIVE)
_mod = importlib.util.module_from_spec(_spec)
sys.path.insert(0, str(ROOT / "gates"))   # the archived gate imports `gatekit`
_spec.loader.exec_module(_mod)
OLD = {k: v[1] for k, v in _mod.DIVERGES.items()}   # the PORT side, which is what moved
OLD_PY = {k: v[0] for k, v in _mod.DIVERGES.items()}

if __name__ == "__main__":
  import difflib
  for path in sys.argv[1:]:
    rows = {}
    for l in Path(path).read_text().splitlines():
      if "=" in l:
        rows[l.split("=", 1)[0]] = l
    hits = 0
    print(f"-- {path}")
    for k, want in OLD.items():
      got = rows.get(k, "<absent>")
      if want in got:
        hits += 1
        print(f"   MATCH  {k}")
      else:
        print(f"   MISS   {k}")
        a, b = want.split(), got.split()
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b).get_opcodes():
          if tag != "equal":
            print(f"        {tag}: pin={a[i1:i2]}  lane={b[j1:j2]}")
    print(f"   OLD PORT PINS: {hits} of {len(OLD)} match")
