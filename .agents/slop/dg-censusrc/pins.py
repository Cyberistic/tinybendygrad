"""STATIC: read PINS out of checks/differ.py by AST (never execute differ.py), compare
against the recorded D0-run-summary.txt rows. Prints item/recorded/expected/verdict."""
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
src = (ROOT / "checks/differ.py").read_text()
tree = ast.parse(src)

pins = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and any(
        isinstance(t, ast.Name) and t.id == "PINS" for t in node.targets
    ):
        for k, v in zip(node.value.keys, node.value.values):
            pins[k.value] = ast.literal_eval(v)
        break

summary = {}
for line in (ROOT / "runs/graphcmp/D/D0-run-summary.txt").read_text().splitlines():
    if "=" in line:
        k, _, val = line.partition("=")
        summary[k] = val

rows = []
for key, want in pins.items():
    got = summary.get(key, "ABSENT")
    rows.append((key, got, want, "PASS" if got == want else "FAIL"))

red = [r for r in rows if r[3] == "FAIL"]
print(f"pins={len(rows)} pass={len(rows)-len(red)} fail={len(red)}")
for key, got, want, verdict in rows:
    if verdict == "FAIL":
        print(f"FAIL\t{key}\trecorded={got!r}\texpected={want!r}")
missing = sorted(set(summary) - set(pins))
print(f"summary_rows={len(summary)} pins_without_summary_row={missing}")
sys.exit(0)