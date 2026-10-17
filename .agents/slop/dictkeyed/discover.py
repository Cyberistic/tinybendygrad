"""DISCOVER the population of instruments that read git state.

Rule of doctrine 1: a population is (a) a generator's declaration loaded by path,
(b) a directory walk, or (c) a regex over the tree's own write sites. This is (b)
plus an AST pass, so a mention of `git ls-tree` in a PROSE COMMENT cannot put a
file in the population -- only a string constant that survives `ast.parse` can.

The vocabulary is the set of git plumbing/porcelain READERS, recorded here in one
place because it is the classifier, not the population.

  usage: .venv/bin/python discover.py   -> writes discover.rows (TSV)
"""

import ast
import os
import sys

ROOTS = ("checks", "gates", "bin")

# Git readers that can produce a LIST OF PATH ENTRIES. `rev-parse`/`log` alone are
# not path enumerators; they enter the population only if the file also enumerates.
ENUMERATORS = {
	"ls-tree",      # committed tree
	"ls-files",     # the INDEX
	"status",       # porcelain -> path lines
	"diff",         # --name-status / --name-only
	"for-each-ref", # packed-refs / refs
	"show-ref",
}
REFS = {
	"rev-parse", "cat-file", "show", "log", "rev-list", "rev-parse",
	"symbolic-ref", "describe", "merge-base", "stash",
}
VOCAB = ENUMERATORS | REFS


def consts(tree):
	"""Every string constant in the module -- AST nodes only, never comments."""
	for node in ast.walk(tree):
		if isinstance(node, ast.Constant) and isinstance(node.value, str):
			yield node.value, node.lineno


def verbs_in(texts):
	"""Git verbs named by string constants.

	A verb counts only if the SAME string constant also names `git`. Without that
	conjunction `diff` matches `difflib.unified_diff` and `show` matches prose, and
	the classifier would grow a population of Python standard library calls. The
	tightened predicate is what `discover.rows` records, and its hits are re-read by
	hand before anything is called DICT-KEYED.
	"""
	found = set()
	for text, _ in texts:
		words = {w.strip("\"'`()$|&<>{}[]*?,;") for w in text.replace("|", " ").replace(";", " ").split()}
		if "git" not in words:
			continue
		found |= (words & VOCAB)
	return found


def imports_slop(tree):
	names = []
	for node in ast.walk(tree):
		if isinstance(node, ast.Import):
			names += [a.name for a in node.names]
		elif isinstance(node, ast.ImportFrom):
			names.append(node.module or "")
	return [n for n in names if "slop" in n or "agents" in n]


def main():
	root = os.getcwd()
	rows = []
	py_seen = sh_seen = 0
	for base in ROOTS:
		top = os.path.join(root, base)
		if not os.path.isdir(top):
			rows.append((base, "ROOT-ABSENT", "-", "-", "-"))
			continue
		for dirpath, dirnames, filenames in os.walk(top):
			dirnames[:] = [d for d in dirnames if d not in ("__pycache__", "artifacts")]
			for fn in sorted(filenames):
				path = os.path.join(dirpath, fn)
				rel = os.path.relpath(path, root)
				if fn.endswith(".py"):
					py_seen += 1
					try:
						tree = ast.parse(open(path, encoding="utf-8").read(), path)
					except (SyntaxError, ValueError) as exc:
						rows.append((rel, "UNPARSEABLE", "-", "-", str(exc)[:60]))
						continue
					texts = list(consts(tree))
					verbs = verbs_in(texts)
					if not verbs:
						continue
					slop = imports_slop(tree)
					rows.append((
						rel,
						" ".join(sorted(verbs)),
						",".join(sorted(verbs & ENUMERATORS)) or "-",
						"IMPORTS-SLOP:" + ",".join(slop) if slop else "-",
						f"lines={len(open(path, encoding='utf-8').read().splitlines())}",
					))
				elif fn.endswith(".sh"):
					sh_seen += 1
	with open(".agents/slop/dictkeyed/discover.rows", "w", encoding="utf-8") as fh:
		fh.write("instrument\tverbs_as_string_constants\tenumerators\tslop_import\tmeta\n")
		for row in rows:
			fh.write("\t".join(row) + "\n")
	print(f"py walked={py_seen} sh walked={sh_seen} rows={len(rows)}", file=sys.stderr)
	print(f"in-population(files naming a git verb)={sum(1 for r in rows if r[1].startswith(('ls-', 'status', 'diff', 'for-each', 'show-ref', 'rev-', 'cat-', 'show', 'log', 'symbolic', 'describe', 'merge-base', 'stash')))}", file=sys.stderr)


if __name__ == "__main__":
	main()
