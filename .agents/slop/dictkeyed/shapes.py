"""MEASURE each DATA-MODEL SHAPE on the malformed commit and on the control.

Four shapes, four reproductions, each copied from the instrument that uses it. The question
each one answers is the same and it is not "is it a dict":

    what does this reader report for a tree in which one path is enumerated three times?

  OVERWRITE   `d[path] = v`                 -> the answer is 7253. git emitted 7505.
  ACCUMULATE  `d[k] = d.get(k,0) + 1`       -> the count INFLATES. visible, but as a number
                                                 about a DIRECTORY, never about a path.
  SET         `set(...splitlines())`        -> dedup at insert. same 7253.
  LIST        `[p for p in ...]` / `.splitlines()` -> 7505. BOTH COPIES SURVIVE.

Read-only. `git ls-tree` never writes.

  usage: env -u GIT_INDEX_FILE .venv/bin/python shapes.py
"""

import os
import subprocess

SUBJECT, CONTROL = "591f6b499", "HEAD"
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"


def out(rev, *args):
	p = subprocess.run(["git", "ls-tree", *args, rev], capture_output=True, text=True)
	if p.returncode != 0:
		raise RuntimeError(p.stderr.strip())
	return p.stdout


def overwrite(rev):
	"""checks/index-arm-gate.py:114-119 and gates/docnum-census.py:173-178, same shape."""
	ent = {}
	for line in out(rev, "-r").splitlines():
		meta, _, path = line.partition("\t")
		f = meta.split()
		if len(f) >= 3:
			ent[path] = f[2]
	return ent


def accumulate(rev):
	"""gates/gendirs.py:485-498 -- keyed by os.path.dirname(path), value is a COUNT."""
	d, empty = {}, {}
	for line in out(rev, "-r").splitlines():
		meta, _, path = line.partition("\t")
		p = meta.split()
		if len(p) < 3 or p[1] != "blob":
			continue
		k = os.path.dirname(path)
		d[k] = d.get(k, 0) + 1
		if p[2] == EMPTY:
			empty[k] = empty.get(k, 0) + 1
	return d, empty


def as_set(rev):
	"""gates/msgdiff-gate.py:295, gates/indexread-gate.py:150, and the four SET comprehensions."""
	return set(out(rev, "-r", "--name-only").splitlines())


def as_list(rev):
	"""checks/pathresolve.py:327, gates/gates-pop.py:807, checks/repro-paths.py:81,
	checks/slop-declare.py:151, gates/citations-census-gate.py:192, checks/runs-artifacts.py:547."""
	return out(rev, "-r", "--name-only").splitlines()


def scalar_counter(rev):
	"""checks/diary-census.py:282-288 -- a bare n += 1 over the same lines."""
	n = e = 0
	for line in out(rev, "-r").splitlines():
		meta, _, _p = line.partition("\t")
		parts = meta.split()
		if len(parts) >= 3 and parts[1] == "blob":
			n += 1
			e += parts[2] == EMPTY
	return n


def main():
	print(f"{'shape':<12} {'rev':<10} {'git emitted':>12} {'reader reports':>15}  {'delta':>7}  verdict")
	print("-" * 78)
	for rev, tag in ((SUBJECT, "SUBJECT"), (CONTROL, "CONTROL")):
		emitted = len(out(rev, "-r").splitlines())
		rows = [
			("OVERWRITE", len(overwrite(rev)), "COLLAPSED" if len(overwrite(rev)) != emitted else "clean"),
			("SET", len(as_set(rev)), "COLLAPSED" if len(as_set(rev)) != emitted else "clean"),
			("LIST", len(as_list(rev)), "both copies survive" if len(as_list(rev)) != len(set(as_list(rev))) else "clean"),
			("COUNTER", scalar_counter(rev), "INFLATED" if scalar_counter(rev) != emitted else "clean"),
		]
		for name, got, verdict in rows:
			print(f"{name:<12} {rev:<10} {emitted:>12} {got:>15}  {got - emitted:>+7}  {verdict}")
		if rev == SUBJECT:
			d, _ = accumulate(rev)
			print(f"{'ACCUMULATE':<12} {rev:<10} {emitted:>12} {sum(d.values()):>15}  "
			      f"{sum(d.values()) - emitted:>+7}  INFLATED")
			d2, _ = accumulate(CONTROL)
			print(f"{'ACCUMULATE':<12} {CONTROL:<10} {len(out(CONTROL, '-r').splitlines()):>12} "
			      f"{sum(d2.values()):>15}  {sum(d2.values()) - len(out(CONTROL, '-r').splitlines()):>+7}  "
			      f"clean")
		print("-" * 78)

	print()
	print("WHERE THE 252 LOST ENTRIES GO, by directory (the ACCUMULATE view):")
	d_sub, _ = accumulate(SUBJECT)
	d_ctl, _ = accumulate(CONTROL)
	moved = {k: (d_sub[k], d_ctl.get(k, 0)) for k in d_sub if d_sub[k] != d_ctl.get(k, 0)}
	for k, (a, b) in sorted(moved.items()):
		print(f"  {k:<40} subject={a:<5} control={b:<5} delta={a - b:+}")
	print(f"  directories whose COUNT moved: {len(moved)}")
	print(f"  the OVERWRITE/SET views name NONE of them -- they are invisible there.")


if __name__ == "__main__":
	main()
