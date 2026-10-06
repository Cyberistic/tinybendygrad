"""Group the assertion/exception signatures ('E ' lines) across the per-file BEND outputs.

Normalises digits so like failures collapse, and prints counts. Distinguishes the BEND-ONLY failures
(not seen under the CPU control) from all failures.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
BEND = HERE / "bend"

all_counts: dict[str, int] = {}
per_file: dict[str, list[str]] = {}
for out in sorted(BEND.glob("*.out")):
    text = out.read_text()
    sigs = []
    for ln in text.splitlines():
        if ln.startswith("E "):
            s = re.sub(r"\d+", "N", ln[2:].strip())
            s = re.sub(r"\s+", " ", s)
            sigs.append(s)
            all_counts[s] = all_counts.get(s, 0) + 1
    if sigs:
        per_file[out.stem] = sigs

print("TOP SIGNATURES (all BEND files, normalised digits):")
for s, n in sorted(all_counts.items(), key=lambda kv: -kv[1])[:15]:
    print(f"  {n:3d}  {s}")

print()
print("TOP SIGNATURES excluding the missing-module collection errors:")
c = {s: n for s, n in all_counts.items() if not s.startswith("ModuleNotFoundError")}
for s, n in sorted(c.items(), key=lambda kv: -kv[1])[:15]:
    print(f"  {n:3d}  {s}")
