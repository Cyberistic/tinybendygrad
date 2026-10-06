import os, re, subprocess, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
old = subprocess.run(["git", "show", "HEAD:checks/sweep.py"], cwd=ROOT,
                     capture_output=True, text=True).stdout
body = re.search(r"LIVE_UNITS = \((.*?)\n\)", old, re.S).group(1)
names = re.findall(r'"([A-Za-z0-9_-]+)"', body)
tot = 0
for n in names:
    c = sum(len(fs) for _d, _dd, fs in os.walk(os.path.join(ROOT, ".agents/slop", n)))
    tot += c
print(f"old LIVE_UNITS: {len(names)} names, {tot} files")
