"""CLASSIFY each discovered git-reading instrument by its DATA MODEL.

For every file in `p42.rows`, find each FUNCTION that calls a git enumerator, then report
which container the function assigns into. The question is narrow and mechanical:

    can this function's return state represent the SAME PATH TWICE?

  DICT-KEYED  -> `d[p] = v` / `d[p].append` into a dict -> a second write OVERWRITES the first.
                A duplicate is not merely unreported, it is UNREPRESENTABLE.
  SET         -> same, plus silently deduplicated at insert.
  LIST        -> `out.append(...)` -> both copies survive. Representable.
  NONE        -> the function returns a count, or reads OIDs/pins only, not paths.

A `git ls-tree` LINE is `<mode> <type> <oid>\\t<path>`. This file reuses index-arm-gate.py's
`partition("\\t")` so the path key is identified the same way every instrument here does it.

  usage: .venv/bin/python classify.py  -> writes classify.rows (TSV)
"""

import ast
import os
import sys

ENUM = {"ls-tree", "ls-files", "status", "diff", "for-each-ref", "show-ref"}
MUTABLE = (ast.Dict, ast.Set, ast.List)


def calls_git_enum(node: ast.AST) -> set[str]:
	"""Verbs of git ENUMERATORS named by string constants anywhere under `node`."""
	found: set[str] = set()
	for sub in ast.walk(node):
		if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
			words = {w.strip("\"'`()$|&<>{}[]*?,;") for w in sub.value.replace("|", " ").split()}
			if "git" in words:
				found |= words & ENUM
	return found


def container_kinds(node: ast.AST) -> set[str]:
	"""How the function builds its result. Names come from the AST, not from a text match on
	`dict(`: an annotation-only mention of a dict is not a construction."""
	kinds: set[str] = set()
	for sub in ast.walk(node):
		if isinstance(sub, ast.Assign):
			for tgt in sub.targets:
				if isinstance(tgt, (ast.Dict, ast.Set, ast.List)):
					kinds.add({"Dict": "DICT", "Set": "SET", "List": "LIST"}[type(tgt).__name__])
					# `{p: v for ...}` -- a keyed comprehension
				elif isinstance(tgt, ast.Name) and isinstance(sub.value, (ast.DictComp, ast.SetComp)):
					kinds.add({"DictComp": "DICT", "SetComp": "SET"}[type(sub.value).__name__])
				elif isinstance(tgt, ast.Name) and isinstance(sub.value, ast.Call):
					fn = sub.value.func
					name = getattr(fn, "id", None) or getattr(fn, "attr", None)
					if name in ("dict", "Counter", "defaultdict"):
						kinds.add("DICT")
					elif name in ("set", "frozenset"):
						kinds.add("SET")
					elif name == "list":
						kinds.add("LIST")
	return kinds


def returns(node: ast.AST) -> str:
	for sub in ast.walk(node):
		if isinstance(sub, ast.Return):
			try:
				return type(sub.value).__name__ if sub.value is not None else "None"
			except Exception:  # noqa: BLE001
				return "?"
	return "-"


def main():
	files = [ln.strip() for ln in open(".agents/slop/dictkeyed/p42.rows", encoding="utf-8") if ln.strip()]
	rows = []
	for rel in files:
		path = os.path.join(os.getcwd(), rel)
		try:
			src = open(path, encoding="utf-8").read()
			tree = ast.parse(src, path)
		except (SyntaxError, ValueError, OSError) as exc:
			rows.append((rel, "UNREADABLE", str(exc)[:50], "-", "-"))
			continue
		# module-level, and every function. A file may build its dict outside any def.
		scopes = [tree] + [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
		for scope in scopes:
			verbs = calls_git_enum(scope)
			if not verbs:
				continue
			name = getattr(scope, "name", "<module>")
			kinds = container_kinds(scope)
			if kinds:
				model = "+".join(sorted(kinds))
				rep = "NO" if ("DICT" in kinds or "SET" in kinds) else "YES"
			else:
				model, rep = "NONE(count-or-oid)", "n/a"
			rows.append((rel, name, ",".join(sorted(verbs)), model, rep))
	with open(".agents/slop/dictkeyed/classify.rows", "w", encoding="utf-8") as fh:
		fh.write("instrument\tscope\treader\thas_keyed_container\tduplicate_representable\n")
		for r in rows:
			fh.write("\t".join(r) + "\n")
	by_file: dict[str, list[tuple]] = {}
	for r in rows:
		by_file.setdefault(r[0], []).append(r)
	dup, undup = [], []
	for rel, scopes in sorted(by_file.items()):
		models = {s[3] for s in scopes}
		(dup if ("DICT" in models or "SET" in models) else undup).append(rel)
	print(f"instruments examined      : {len(files)}", file=sys.stderr)
	print(f"scopes with a git enum    : {len(rows)}", file=sys.stderr)
	print(f"files with a DICT/SET     : {len(dup)}", file=sys.stderr)
	print(f"files WITHOUT             : {len(undup)}", file=sys.stderr)
	for r in undup:
		print("   no-keyed-container: " + r, file=sys.stderr)


if __name__ == "__main__":
	main()
