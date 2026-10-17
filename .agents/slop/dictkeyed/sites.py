"""Extract the KEYED-ASSIGNMENT lines from each candidate instrument, so the DICT-KEYED
classification is made against the bytes and not against my reading of a summary.

The binary question "is it a dict" is NOT the question. The question is what a SECOND
occurrence of the same path does to the state:

  OVERWRITE   `d[p] = v`                 -> the second occurrence is DESTROYED. Silent.
  ACCUMULATE  `d[k] = d.get(k,0) + 1`    -> the second occurrence MOVES A COUNT. Visible as a
                                            number, invisible as an identity.
  APPEND      `d[k].append(v)`           -> a dict OF LISTS holds both copies.
  SETINSERT   `s.add(p)`                 -> deduplicated at insert. Silent.
  LISTAPPEND  `out.append(v)`            -> both copies survive. Representable.

  usage: .venv/bin/python sites.py
"""

import ast
import re
import sys

OVERWRITE = re.compile(r"^\s*(\w+)\[([^\]]+)\]\s*=\s*(?!.*\+=)")
ACCUM = re.compile(r"^\s*(\w+)\[([^\]]+)\]\s*=\s*\1\.get\([^)]*\)\s*[+\-]")
APPEND = re.compile(r"^\s*(\w+)\[([^\]]+)\]\.append\(")
ADD = re.compile(r"^\s*(\w+)\.add\(")
LAPPEND = re.compile(r"^\s*(\w+)\.append\(")


def git_call_lines(src: str) -> set[int]:
	"""Line numbers that are part of a git enumerator call, so a keyed write is only
	attributed to a reader when it is NEAR one -- otherwise every dict in a 900-line file
	is blamed on the git reader three functions away."""
	lines = set()
	tree = ast.parse(src)
	for node in ast.walk(tree):
		if isinstance(node, ast.Call):
			args = [a for a in node.args]
			names = []
			if isinstance(node.func, ast.Name):
				names.append(node.func.id)
			for a in args:
				if isinstance(a, ast.Constant) and isinstance(a.value, str):
					words = {w.strip("\"'`()$|&<>{}[]*?,;") for w in a.value.split()}
					names += sorted(words & {"ls-tree", "ls-files", "status", "diff"})
			if names:
				for ln in range(node.lineno, (node.end_lineno or node.lineno) + 1):
					lines.add(ln)
	return lines


def main():
	files = [ln.strip() for ln in open(".agents/slop/dictkeyed/p42.rows", encoding="utf-8") if ln.strip()]
	for rel in files:
		src = open(rel, encoding="utf-8").read()
		try:
			gl = git_call_lines(src)
		except SyntaxError:
			print(f"{rel}\tUNPARSEABLE")
			continue
		rows = []
		for i, line in enumerate(src.splitlines(), 1):
			if not line.strip() or line.lstrip().startswith("#"):
				continue
			kind = None
			for rx, name in ((ACCUM, "ACCUMULATE"), (APPEND, "DICT-OF-LIST"),
			                 (OVERWRITE, "OVERWRITE"), (ADD, "SET-ADD"), (LAPPEND, "LIST-APPEND")):
				if rx.match(line):
					kind = name
					break
			if kind:
				near = "near-git" if any(abs(i - g) <= 6 for g in gl) else "far-from-git"
				rows.append(f"{i}:{kind}:{near}")
		if rows:
			print(f"{rel}\t{'; '.join(rows)}")
		else:
			print(f"{rel}\t(no keyed-assignment line in the file)", file=sys.stderr)


if __name__ == "__main__":
	main()
