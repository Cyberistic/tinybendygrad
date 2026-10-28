#!/usr/bin/env python3
"""comment-only proof: every file I touched strips to the SAME code hash as HEAD."""
import hashlib, importlib.util, subprocess, sys
from pathlib import Path
ROOT = Path('/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
spec = importlib.util.spec_from_file_location('pcg', ROOT/'checks/port-compile-gate.py')
pcg = importlib.util.module_from_spec(spec); spec.loader.exec_module(pcg)
MINE = [l.strip() for l in open(sys.argv[1]) if l.strip()]
def code_hash(text: str) -> str:
    body = pcg.strip_comments(text)
    return hashlib.sha256("\n".join(l for l in body.split("\n") if l.strip()).encode()).hexdigest()
same, diff = [], []
for rel in MINE:
    head = subprocess.run(['git','show',f'HEAD:{rel}'], cwd=ROOT, capture_output=True, text=True)
    if head.returncode != 0:
        print("NEW FILE (no HEAD):", rel); diff.append(rel); continue
    h_head = code_hash(head.stdout)
    h_now  = code_hash((ROOT/rel).read_text())
    if h_head == h_now: same.append(rel)
    else: diff.append(rel)
print(f"COMMENT-ONLY (same code hash as HEAD): {len(same)} of {len(MINE)}")
for rel in diff: print("   NOT COMMENT-ONLY:", rel)
