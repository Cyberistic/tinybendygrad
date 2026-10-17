"""Print the ENCLOSING FUNCTION of every site where a git enumeration is turned into PATHS.

A path-keyed container is only reachable through one shape: git emits a line, the line is
split, and the path half is used as a key. `partition("\\t")` / `split("\\t")` is that split --
`git ls-tree`, `git ls-files --stage` and `git diff --name-status` all emit TAB-separated
`meta\\tpath`. So the population of INTEREST is every function that both calls a git enumerator
AND tab-partitions its output. Those functions are printed whole, because the container type is
one line of reasoning and it has to be done against code.

  usage: .venv/bin/python funcs.py  > funcs.out
"""

import ast
import sys

ENUM = {"ls-tree", "ls-files", "status", "diff"}


def s(text) -> bool:
	return isinstance(text, str)


def scan(node: ast.AST) -> tuple[set[str], bool, bool]:
	"""(git verbs named, tab-partitioned?, any append/setadd?)"""
	verbs, tab, keyed = set(), False, False
	for sub in ast.walk(node):
		if isinstance(sub, ast.Constant) and s(sub.value):
			words = {w.strip("\"'`()$|&<>{}[]*?,;") for w in sub.value.replace("|", " ").split()}
			if "git" in words or words & {"ls-tree", "ls-files", "ls_files"}:
				verbs |= words & ENUM
			if "\t" in sub.value:   # a REAL tab: the AST constant holds the character, not the escape
				tab = True
		if isinstance(sub, ast.Call):
			nm = getattr(sub.func, "attr", None) or getattr(sub.func, "id", None)
			if nm in ("append", "add"):
				keyed = True
	return verbs, tab, keyed


def scan2(node: ast.AST) -> tuple[set[str], bool, bool]:
	"""The SECOND shape: no tab, because `git ls-tree --name-only` and `git diff --name-only`
	emit bare paths. The tell is `.splitlines()` / `.split("n")` / `set(...)` applied inside a
	function that also calls a git enumerator."""
	verbs, linewise, keyed = set(), False, False
	for sub in ast.walk(node):
		if isinstance(sub, ast.Constant) and s(sub.value):
			words = {w.strip("\"'`()$|&<>{}[]*?,;") for w in sub.value.replace("|", " ").split()}
			if "git" in words:
				verbs |= words & ENUM
		if isinstance(sub, ast.Call):
			nm = getattr(sub.func, "attr", None) or getattr(sub.func, "id", None)
			if nm in ("splitlines", "split"):
				linewise = True
			if nm in ("append", "add", "set", "defaultdict", "Counter"):
				keyed = True
	return verbs, linewise, keyed


def main():
	files = [ln.strip() for ln in open(".agents/slop/dictkeyed/p42.rows", encoding="utf-8") if ln.strip()]
	total = 0
	for rel in files:
		src = open(rel, encoding="utf-8").read()
		lines = src.splitlines()
		try:
			tree = ast.parse(src, rel)
		except SyntaxError:
			continue
		funcs = [n for n in ast.walk(tree)
		         if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
		for f in funcs:
			verbs, tab, keyed = scan(f)
			shape = "TAB"
			if not (verbs and tab):
				v2, linewise, k2 = scan2(f)
				if not (v2 and linewise) or tab:
					continue
				verbs, keyed, shape = v2, keyed or k2, "LINEWISE"
			total += 1
			lo, hi = f.lineno, f.end_lineno or f.lineno
			print(f"\n===== {rel}:{lo}-{hi}  fn={f.name}  verbs={sorted(verbs)} "
			      f"shape={shape} keyed_container={keyed}")
			for i in range(lo, min(hi, lo + 26) + 1):
				if i - 1 < len(lines):
					print(f"  {i:5d}| {lines[i-1]}")
			if hi > lo + 26:
				print(f"  ... ({hi - lo - 26} more lines)")
	print(f"\n# FUNCTIONS THAT TURN A GIT ENUMERATION INTO PATHS: {total}", file=sys.stderr)


if __name__ == "__main__":
	main()
