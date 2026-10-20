"""Every in-code pin on a tinygrad/ blob, and whether the re-vendor moves it.

A pin that names a blob the re-vendor replaces must move in the SAME commit --
AGENTS.md's rule for a rename, applied to a re-vendor. This finds them all first.
"""
import os
import re
import subprocess as S

PAT = re.compile(r'"(tinygrad/[A-Za-z0-9_./]+\.py)"\s*:\s*"([0-9a-f]{40,64})"')
OLD, NEW = "002630241", "refs/remotes/upstream/master"


def blob(rev, path):
  r = S.run(["git", "rev-parse", f"{rev}:{path}"], capture_output=True, text=True)
  return r.stdout.strip() if r.returncode == 0 else None


def main():
  pins = {}
  for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", "artifacts", "__pycache__", ".jj", ".venv")]
    for f in files:
      if not f.endswith(".py"):
        continue
      p = os.path.join(root, f)
      try:
        t = open(p, encoding="utf-8", errors="replace").read()
      except OSError:
        continue
      for path, sha in PAT.findall(t):
        pins.setdefault(path, []).append((p, sha))

  moved, still = [], []
  for path in sorted(pins):
    o, n = blob(OLD, path), blob(NEW, path)
    (moved if o != n else still).append((path, o, n, pins[path]))

  print(f"  in-code tinygrad blob pins: {len(pins)} paths, {sum(len(v) for v in pins.values())} sites\n")
  for path, o, n, sites in moved:
    print(f"  MOVED  {path}")
    print(f"         {(o or 'ABSENT-OLD')[:12]} -> {(n or 'GONE')[:12]}   {len(sites)} site(s)")
    for p, _ in sites:
      print(f"           {p}")
  for path, o, n, sites in still:
    print(f"  SAME   {path}  {(o or '')[:12]}   {len(sites)} site(s)")
  print(f"\n  -> {len(moved)} path(s) MOVE; {len(still)} stay.")
  print(f"  -> {sum(len(v[3]) for v in moved)} PIN SITE(S) MUST MOVE IN THE SAME COMMIT.")


if __name__ == "__main__":
  main()