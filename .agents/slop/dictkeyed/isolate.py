"""ISOLATE the duplicate's effect WITHIN ONE COMMIT. The previous table was contaminated.

`shapes.py` compared 591f6b499 against HEAD and reported `gates 378 vs 277, delta +101`. THAT
DELTA IS NOT THE DUPLICATE. 591f6b499 is an older commit: its `gates` tree object `5dee0c1b` holds
**126** entries while HEAD's `gates/` holds **279**, so most of +101 is the tree having GROWN.
A cross-commit diff cannot separate "this path is enumerated twice" from "this path is newer".

The only clean comparison is the commit against ITSELF WITH THE DUPLICATE REMOVED, and that is
arithmetic over one `ls-tree`: the deduplicated population is `distinct paths`, so

    per-directory counts over DISTINCT paths   == what a correct reader would report
    per-directory counts over EMITTED lines    == what gendirs.py reports

and the difference IS the duplicate, with no second commit anywhere in the measurement.

  usage: env -u GIT_INDEX_FILE .venv/bin/python isolate.py
"""

import os
import subprocess
from collections import Counter

SUBJECT, CONTROL = "591f6b499", "HEAD"


def lines(rev):
	p = subprocess.run(["git", "ls-tree", "-r", rev], capture_output=True, text=True)
	if p.returncode != 0:
		raise RuntimeError(p.stderr.strip())
	return p.stdout.splitlines()


def entries(ls):
	"""(dirname, name) -> [oid, ...] -- a dict of LISTS, which is the ONLY structure that can
	represent a duplicate. `gendirs.py` uses a dict of ints; this is what it is missing."""
	seen: dict[tuple[str, str], list[str]] = {}
	for line in ls:
		meta, _, path = line.partition("\t")
		f = meta.split()
		if len(f) >= 3:
			seen.setdefault((os.path.dirname(path), path), []).append(f[2])
	return seen


def main():
	for rev, tag in ((SUBJECT, "SUBJECT"), (CONTROL, "CONTROL")):
		ls = lines(rev)
		seen = entries(ls)
		dupes = {k: v for k, v in seen.items() if len(v) > 1}
		extra = sum(len(v) - 1 for v in dupes.values())
		once = sum(1 for v in seen.values() if len(v) == 1)
		repeated = len(dupes)
		print(f"\n===== {tag}  {rev}")
		print(f"  lines git emitted ............... {len(ls)}")
		print(f"  distinct (dir,path) pairs ....... {len(seen)}")
		print(f"  arithmetic check: {once}x1 + {repeated}x3 = {once + repeated * 3} "
		      f"{'OK' if once + repeated * 3 == len(ls) else 'MISMATCH'}")
		print(f"  entries lost by a dict ......... {len(ls) - len(seen)}")
		print(f"  repeated entries ................ {repeated} paths, each "
		      f"{len(next(iter(dupes.values()))) if dupes else 0}x")
		if dupes:
			# PER PATH, not across paths. Flattening every repeated OID into one set answers a
			# different question ("how many distinct blobs are involved", which is one per path
			# and therefore always 126 here) than the one being asked ("does ONE path carry two
			# blobs"). Only the per-path test distinguishes REPEATED from CONFLICTING.
			conflicting = {k: v for k, v in dupes.items() if len(set(v)) > 1}
			print(f"  per-path OID test ............... {len(dupes) - len(conflicting)} REPEATED "
			      f"(same blob), {len(conflicting)} CONFLICTING (two OIDs)")
			if conflicting:
				for k, v in list(sorted(conflicting.items()))[:3]:
					print(f"      CONFLICTING {k[1]}: {sorted(set(v))}")

		# gendirs.py's exact arithmetic, vs the deduplicated truth, SAME COMMIT.
		# `emitted` counts LINES per dir (what `d[k] = d.get(k,0)+1` produces);
		# `truth`   counts DISTINCT PATHS per dir (what a reader that can represent a duplicate
		#           would produce). The first version of this line summed `len(v)` in BOTH, so
		#           truth == emitted always and the table reported "none" on a tree that HAS a
		#           duplicate -- a clean wrong answer, which is worse than an exception.
		emitted = Counter(k[0] for k, v in seen.items() for _ in v)
		truth = Counter(k[0] for k in seen)
		moved = {d: (emitted[d], truth[d]) for d in set(emitted) | set(truth)
		         if emitted[d] != truth[d]}
		print(f"  gendirs.py per-dir INFLATION (same commit, no cross-commit diff):")
		for d, (a, b) in sorted(moved.items()):
			print(f"    {d or '<root>':<20} emits {a:<6} distinct {b:<6} delta {a - b:+d}")
		if not moved:
			print(f"    none -- this commit has no duplicate")


if __name__ == "__main__":
	main()
