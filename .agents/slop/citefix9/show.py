import sys
from pathlib import Path
rel, lo, hi = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
src = Path(rel).read_text().splitlines()
for i in range(lo, min(hi, len(src)) + 1):
    print(f"{i:5d}|{src[i-1]}")
