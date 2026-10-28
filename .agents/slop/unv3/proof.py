#!/usr/bin/env python3
"""proof.py -- THE COMMENT-ONLY PROOF FOR THE SLICE'S FILES.

    .venv/bin/python .agents/slop/unv3/proof.py

FOR EVERY FILE THE SLICE OWNS: STRIP THE COMMENTS AND COMPARE THE CODE AGAINST
`HEAD`'s STRIPPED CODE. A COMMENT-ONLY EDIT LEAVES THE SAME CODE HASH; A CODE EDIT
DOES NOT, AND THIS IS THE CHECK THAT SAYS SO.

THE STRIPPER IS `checks/port-compile-gate.py`'s `strip_comments`, **LOADED BY PATH**
(`AGENTS.md`'s rule: one rule, one place), NOT COPIED. A SECOND COPY OF A STRIPPER
IS A CONTRACT WITH NO GENERATOR AND ROTS WITHOUT ANYONE NOTICING.
"""
import hashlib, importlib.util, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("pcg", ROOT / "checks/port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)

SLICE = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unv3.rows")


def slice_files() -> list[str]:
  out: list[str] = []
  for line in SLICE.read_text().splitlines():
    if not line.strip():
      continue
    rel = line.split("\t")[0]
    if rel.endswith(".bend") and rel not in out:
      out.append(rel)
  return out


def code_hash(text: str) -> str:
  """THE HASH OF THE CODE, with the BLANK LINES DROPPED."""
  stripped = pcg.strip_comments(text)
  body = "\n".join(ln for ln in stripped.split("\n") if ln.strip())
  return hashlib.sha256(body.encode()).hexdigest()


def main() -> int:
  bad = 0
  for rel in slice_files():
    live = ROOT / rel
    if not live.is_file():
      continue
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT, capture_output=True, text=True)
    if head.returncode != 0:
      print(f"SKIP  {rel}: not in HEAD")
      continue
    a, b = code_hash(head.stdout), code_hash(live.read_text())
    if a == b:
      print(f"CODE-IDENTICAL  {rel}  {a[:16]}")
    else:
      print(f"CODE-CHANGED    {rel}  HEAD={a[:16]} LIVE={b[:16]}")
      bad += 1
  print(f"\n{len(slice_files())} files, {bad} with CHANGED CODE")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
