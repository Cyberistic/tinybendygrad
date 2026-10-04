#!/usr/bin/env python3
"""
Extract the ENUMERATED LIST from tinygrad/runtime/autogen/libclang.py by
PARSING IT WITH `ast`.  Nothing here is typed from memory: every name, arity,
annotation and `@dll.bind` payload is read out of the committed file.

Three DATA artefacts (the brief: "the list is data, not FFI"):

  ag-libclang.tramp   one TRAMPOLINE row per `@dll.bind` def
      name|retbind|rethint|[pname|pbind|phint]*
  ag-libclang.ty      one row per distinct upstream spelling
      TY|ctypes_or_hint_spelling|{bind,hint}
  ag-libclang.meta     the census, with denominators

`|` is the field separator because no C type spelling or Python annotation in
libclang.py contains one, and because `String.split` in bend takes a single
Char.  `c.CFUNCTYPE[None, [ctypes.c_void_p]]` DOES contain a space and a comma,
which is why a whitespace format is unusable.

Run:  .venv/bin/python .agents/slop/ag-libclang-rows.py
"""
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tinygrad" / "runtime" / "autogen" / "libclang.py"
OUT = ROOT / ".agents" / "slop"


def split_top(s: str) -> list[str]:
    """split a `@dll.bind(...)` argument list on TOP-LEVEL commas only"""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out]


def is_tramp(n) -> bool:
    return isinstance(n, ast.FunctionDef) and any(
        ast.unparse(d).startswith("dll.bind(") for d in n.decorator_list)


def main() -> int:
    tree = ast.parse(SRC.read_text())

    tramps, rows = [], []
    used: dict[str, set[str]] = {}
    for n in tree.body:
        if not is_tramp(n):
            continue
        binds = [ast.unparse(d) for d in n.decorator_list if ast.unparse(d).startswith("dll.bind(")]
        tys = split_top(binds[0][len("dll.bind("):-1])
        ret = ast.unparse(n.returns) if n.returns else ""
        if len(tys) != len(n.args.args) + 1:
            print(f"ARITY MISMATCH {n.name}: {len(tys)} binds vs {len(n.args.args)}+1 params",
                  file=sys.stderr)
            return 1
        cells = [n.name, tys[0], ret]
        for i, a in enumerate(n.args.args):
            cells += [a.arg, tys[i + 1], ast.unparse(a.annotation) if a.annotation else ""]
        rows.append("|".join(cells))
        tramps.append(n.name)
        for t in tys:
            used.setdefault(t, set()).add("bind")
        for a in n.args.args:
            if a.annotation:
                used.setdefault(ast.unparse(a.annotation), set()).add("hint")
        used.setdefault(ret, set()).add("hint")

    aliases, records, enums, extras, nonbind = [], [], [], [], []
    rec_fields = 0
    for n in tree.body:
        if isinstance(n, ast.ClassDef):
            records.append(n.name)
            rec_fields += sum(1 for s in n.body if isinstance(s, ast.AnnAssign))
        elif isinstance(n, ast.AnnAssign):
            # the ANNOTATION only: the whole unparse of an enum dict contains
            # "TypeAlias" inside CXCursor_TypeAliasTemplateDecl, which silently
            # swallowed 2 of the 47 enum dicts on the first run of this script.
            anno = ast.unparse(n.annotation)
            v = ast.unparse(n.value) if n.value else ""
            if anno == "TypeAlias":
                aliases.append((ast.unparse(n.target), v))
            elif anno == "dict[int, str]":
                enums.append((ast.unparse(n.target), v.count(":=")))
        elif isinstance(n, ast.Assign):
            extras.append(ast.unparse(n))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and not is_tramp(n):
            nonbind.append(n.name)

    (OUT / "ag-libclang.tramp").write_text("\n".join(rows) + "\n")
    (OUT / "ag-libclang.ty").write_text(
        "\n".join(f"TY|{k}|{''.join(sorted(v))}" for k, v in sorted(used.items())) + "\n")
    (OUT / "ag-libclang.meta").write_text("\n".join([
        f"tramps {len(tramps)}",
        f"nonbind_top_level_defs {len(nonbind)} {' '.join(nonbind)}".rstrip(),
        f"records {len(records)}",
        f"record_fields {rec_fields}",
        f"enum_dicts {len(enums)}",
        f"enum_constants {sum(c for _, c in enums)}",
        f"type_aliases {len(aliases)}",
        f"assigns {len(extras)}",
        f"distinct_upstream_types {len(used)}",
    ]) + "\n")
    (OUT / "ag-libclang.alias").write_text("\n".join(f"AL ~ {a} ~ {b}" for a, b in aliases) + "\n")
    (OUT / "ag-libclang.enum").write_text(
        "\n".join(f"EN|{a}|{b}" for a, b in enums) + "\n")
    print(f"tramps={len(tramps)} types={len(used)} records={len(records)} rec_fields={rec_fields} "
          f"enums={len(enums)} enum_consts={sum(c for _, c in enums)} aliases={len(aliases)}")
    print("nonbind top-level defs:", nonbind)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())