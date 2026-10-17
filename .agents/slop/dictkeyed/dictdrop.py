"""MEASURE the dict-drop. Read-only; `git ls-tree` never writes.

The claim under test (from a dispatched unit): `checks/index-arm-gate.py:114-119` builds
    ent = {}; for line in out.splitlines(): ent[path] = fields[2]
which is a dict keyed by PATH. A dict CANNOT represent a duplicate key. So if a committed
tree enumerates one path twice, the second write overwrites the first and the tool sees one
entry where git emitted two.

This file reproduces that EXACT build (same partition, same split, same guard) so the
number below is the gate's own arithmetic, not a paraphrase of it.

  usage: env -u GIT_INDEX_FILE .venv/bin/python dictdrop.py
"""

import subprocess
from collections import Counter


def ls_tree(rev: str, tree_flag: bool = False) -> list[str]:
	argv = ["git", "ls-tree", "-r"] + (["-t"] if tree_flag else []) + [rev]
	p = subprocess.run(argv, capture_output=True, text=True, check=False)
	if p.returncode != 0:
		raise RuntimeError(f"ls-tree {rev} rc={p.returncode}: {p.stderr.strip()}")
	return p.stdout.splitlines()


def gate_dict(lines: list[str]) -> dict[str, str]:
	"""index-arm-gate.py:114-119 VERBATIM in shape."""
	ent: dict[str, str] = {}
	for line in lines:
		meta, _, path = line.partition("\t")
		fields = meta.split()
		if len(fields) >= 3:
			ent[path] = fields[2]
	return ent


def classify(lines: list[str]) -> tuple[Counter, dict[str, list[str]]]:
	"""Which paths repeat, and do the repeats carry the SAME oid (REPEATED) or different
	ones (CONFLICTING)? A CONFLICTING duplicate is not a reduntant copy, it is two claims
	about what a path IS -- the index cannot hold that shape either, but the blast radius
	differs, so the two must not share an arm."""
	seen: dict[str, list[str]] = {}
	for line in lines:
		meta, _, path = line.partition("\t")
		fields = meta.split()
		if len(fields) >= 3:
			seen.setdefault(path, []).append(fields[2])
	dups = {p: oids for p, oids in seen.items() if len(oids) > 1}
	kinds = Counter("REPEATED" if len(set(oids)) == 1 else "CONFLICTING" for oids in dups.values())
	return kinds, dups


def probe(rev: str, tree_flag: bool = False) -> dict:
	lines = ls_tree(rev, tree_flag)
	ent = gate_dict(lines)
	kinds, dups = classify(lines)
	return {
		"rev": rev, "lines": len(lines), "dict": len(ent),
		"drop": len(lines) - len(ent),
		"dup_paths": len(dups),
		"extra": sum(len(o) - 1 for o in dups.values()),
		"kinds": dict(kinds),
		"sample": sorted(dups.items())[:2],
	}


def main():
	print("== SUBJECT: the malformed commit ==")
	for flag in (False, True):
		r = probe("591f6b499", flag)
		t = "-t " if flag else "  "
		print(f"  ls-tree -r {t} 591f6b499  lines={r['lines']:6d}  dict={r['dict']:6d}  "
		      f"DROP={r['drop']:4d}  dup_paths={r['dup_paths']:3d}  extra={r['extra']:4d}  {r['kinds']}")
		if flag:
			print(f"    sample duplicate: {r['sample']}")

	print()
	print("== CONTROLS: commits known-good for tree shape ==")
	for rev in ("HEAD", "HEAD~1", "ad117c928"):
		try:
			r = probe(rev)
		except Exception as exc:  # noqa: BLE001 -- a control that cannot be read is a FAILURE
			print(f"  {rev}: UNREADABLE {exc}")
			continue
		print(f"  ls-tree -r {rev:12s} lines={r['lines']:6d}  dict={r['dict']:6d}  "
		      f"DROP={r['drop']:4d}  dup_paths={r['dup_paths']:3d}  {r['kinds']}")

	print()
	print("== the one gate question: does index-arm-gate see it? ==")
	sub = probe("591f6b499")
	ctl = probe("HEAD")
	print(f"  n_tree that census() would report for 591f6b499 = {sub['dict']}  (git emitted {sub['lines']})")
	print(f"  n_tree that census() would report for HEAD      = {ctl['dict']}  (git emitted {ctl['lines']})")
	print(f"  -> the gate has NO SHAPE for a duplicate; its five shapes are "
	      f"DELETION/INTENT/FOREIGN/STALE/EMPTIED, all index-vs-tree.")

	print()
	print("== can the INDEX hold the shape? ==")
	p = subprocess.run(["git", "ls-tree", "591f6b499", "--", "gates"], capture_output=True, text=True, check=False)
	print(f"  git ls-tree 591f6b499 -- gates  rc={p.returncode}  lines={len(p.stdout.splitlines())}")
	for line in p.stdout.splitlines():
		print(f"    {line}")


if __name__ == "__main__":
	main()
