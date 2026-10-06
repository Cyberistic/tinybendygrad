#!/usr/bin/env python3
"""Classify the five not-source `.bend` files the port shipped.

Populations by DISCOVERY, never a hand list:
  * importers   -- every `.bend` under `tinybendygrad/`, regex-scanned for `import ... .bend`
  * citers      -- `git grep -l -F <basename> HEAD` (whole repo)
  * byte-copies -- `git rev-parse HEAD:<path>` per path, then `git ls-files -s` blob match

The five paths are the task's population, named once in FILES below because the task named them;
everything else about each row is measured. Output goes to stdout; `classify.rows` is the capture.
"""
from __future__ import annotations

import os
import re
import subprocess

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"

# path -> (kind_claimed, where_it_now_lives)
FILES = {
    "tinybendygrad/runtime/zzdiag.bend": "runtime/zzdiag.bend",
    "tinybendygrad/runtime/zzread.bend": "runtime/zzread.bend",
    "tinybendygrad/runtime/zzsplit.bend": "runtime/zzsplit.bend",
    "tinybendygrad/runtime/support/zz_objc_mutant.bend": "runtime/support/zz_objc_mutant.bend",
    "tinybendygrad/runtime/support/am/ip_scratch_sweep.bend": "runtime/support/am/ip_scratch_sweep.bend",
}
RELOCATED_ROOT = ".agents/slop/portzz/relocated"

IMPORT = re.compile(r"^\s*import\s+(?:\./)?([^\s]+\.bend)", re.M)


def sh(*a: str) -> str:
    return subprocess.run(a, cwd=ROOT, capture_output=True, text=True).stdout


def bend_importers(basename: str) -> list[str]:
    """Every `.bend` under tinybendygrad/ that imports a path ending in `basename`."""
    out = []
    for d, _, fs in os.walk(os.path.join(ROOT, "tinybendygrad")):
        for f in fs:
            if not f.endswith(".bend"):
                continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, ROOT)
            for m in IMPORT.finditer(open(p, encoding="utf-8", errors="replace").read()):
                tgt = os.path.normpath(os.path.join(os.path.dirname(rel), m.group(1)))
                if os.path.basename(tgt) == basename:
                    out.append(rel)
    return sorted(set(out))


def main() -> int:
    print("kind\tpath\tlines\ttracked\tin_HEAD\timported_by_bend\tbyte_copies_in_index\tciters_outside_slop")
    for path in sorted(FILES):
        on_disk = path if os.path.exists(os.path.join(ROOT, path)) else os.path.join(RELOCATED_ROOT, FILES[path])
        lines = sum(1 for _ in open(os.path.join(ROOT, on_disk), encoding="utf-8", errors="replace"))
        tracked = "yes" if sh("git", "ls-files", "--error-unmatch", "--", path).strip() == path else "no"
        head = "yes" if sh("git", "cat-file", "-e", f"HEAD:{path}").strip() == "" else "no"
        base = os.path.basename(path)
        importers = bend_importers(base)
        blob = sh("git", "rev-parse", f"HEAD:{path}").strip()
        copies = [ln.split("\t", 1)[1] for ln in sh("git", "ls-files", "-s").splitlines()
                  if ln.split("\t", 1)[0].split()[1] == blob] if blob else []
        citers = [c for c in sh("git", "grep", "-l", "-F", base, "HEAD").splitlines()
                  if c and not c.endswith("/" + FILES[path])]
        outside = [c for c in citers if not c.startswith("HEAD:.agents/slop/")]
        print("\t".join([
            base, path, str(lines), tracked, head,
            ",".join(importers) or "-", str(max(len(copies), 0)), ",".join(outside) or "-",
        ]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
