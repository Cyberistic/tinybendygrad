"""Census the STRUCTURAL shape changes of a re-vendor, and who in this tree still reads them.

    .venv/bin/python checks/revendor-struct.py [--rows FILE] [--only KIND]

WHY THIS FILE EXISTS. `72f98ffe0 "move size from ParamArg to src"` moved a field off a
dataclass, the port kept modelling it, and `.agents/slop/graphcmp.py` read it -- so the
34-graph corpus's CPython lane RAISED instead of DISAGREEING, and a raiser is invisible to a
gate that runs its own driver. The population is 86 files and +2376/-2433 lines of which almost
none is structural, so "read the diff" is not a method. THE POPULATION IS DERIVED BY A RULE
WRITTEN BESIDE IT (`in_population`), never hand-listed, and EVERY REJECTION RULE PRINTS THE
COUNT IT DROPPED: a wrong exclusion writes no row, and no row does not argue back.

FOUR VERDICTS PLUS THE FIFTH. `UNREAD` (safe) · `READ-AND-STILL-CORRECT` (proven by ARITHMETIC,
not assumed) · `READ-AND-BROKEN` · `UNKNOWN` (and what would decide it) · and
`READ-AND-NOT-NOTICED`, which is the shape that survived a whole session here: a read that
RAISES, on code nothing runs routinely.

THE FIVE BREAK CLASSES THIS INSTRUMENT IS BUILT TO SEE, because a sibling unit MEASURED all
five in one driver (`deff135d5`) and a census that cannot see them is a census of nothing:
  1 a FIELD removed from a dataclass, read as an attribute          -> FIELD-REMOVED
  2 a field removed at position k, POSITIONAL callers silently shift -> FIELD-REMOVED + ARITY
  3 a parameter's DEFAULT flipped, and the caller OMITS it            -> SIG-PARAM-DEFAULT + CALL
  4 a parameter removed, a POSITIONAL caller raises TypeError         -> SIG-PARAM-REMOVED + ARITY
  5 an ENUM MEMBER removed (`Ops.GROUP`, `Ops.FLIP`)                  -> ENUM-MEMBER-REMOVED
Class 3 is invisible to a census that only records KEYWORDS, because the affected caller passes
nothing at all; class 2 and 4 are invisible to a census that records only keywords, because the
affected caller passes POSITIONALLY. So call sites are recorded with their ARITY, and the verdict
is computed from it.

WHAT IS AND IS NOT MEASURED, and the limit stated rather than assumed:
  * Readers are found by `os.walk` + AST + IMPORT RESOLUTION. Never a grep for a name: a prior
    unit found 24 "call sites" of `full_rewrite` that were `test/helpers.py`'s own
    `full_rewrite`, and `rg -l gatekit` overcounts by 9.3% because 7 files only NAME it in prose.
  * BOTH `HEAD` AND THE LIVE WORKTREE ARE CENSUSED, because they are different truths: this tree
    has three units in it, and `graphcmp.py:710` read `pa.size` at 13:40 and did not at 13:42.
  * A field read through a LOCAL (`pa.size`) needs the local's class, so parameter annotations,
    annotated assignments, constructor assignments and `globals().update(Y=mod.Y)` aliases are
    inferred. A local that acquires a tinygrad class by RETURN VALUE, through a dict, or across
    a comprehension is NOT resolvable: `BLIND WIDTH` counts exactly those, per source.
  * `.bend`/`.sh`/`.mjs` are a SEPARATE, WEAKER class: Bend has no import graph, so a token
    there is a MENTION and not a read. Counted separately, never merged into the Python count.
"""
import ast
import json
import re
import subprocess
import sys
import warnings
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "gates"))
from gatekit import DEAD, PASS, verdict_of  # noqa: E402

# This file parses 2317 OTHER people's files, and five of them carry an invalid escape sequence
# in a DOCSTRING (`.agents/slop/handtyped-audit.py:428` and four more). Python 3.12 turns each into
# a SyntaxWarning on stderr, so the census's own output carried five lines it did not produce --
# an instrument whose output it cannot account for is an instrument whose row count it cannot own.
warnings.filterwarnings("ignore", category=SyntaxWarning)

ROOT = Path(__file__).resolve().parent.parent
OLD, NEW = "91b8cb5fa", "upstream"
SOURCES = ("HEAD", "worktree")


def git(*args):
    return subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout


def batch_blobs(rev, paths):
    """`{path: text}` in ONE `git cat-file --batch`, because one subprocess PER FILE is what
    made this census take four minutes: `git cat-file` costs ~4 ms to start and the tree has
    1937 tracked `.py` files read against two sources.

    PARSED BY THE SIZE IN THE HEADER, IN BYTES, NOT BY SPLITTING ON NEWLINES. A line-based parse
    desynchronised on the first blob and read a content line as a header -- `int('==')` -- which
    is what made 1725 of 1937 files report BLOB-ABSENT. An instrument that cannot read its own
    input must say so, and `BLOB-ABSENT` is the number that said it. `--batch -z` was the second
    attempt and it is NOT headerless either; it still prints `<oid> <type> <size>`.
    """
    p = subprocess.run(("git", "cat-file", "--batch"), cwd=ROOT,
                       input=b"".join(f"{rev}:{x}\n".encode() for x in paths),
                       capture_output=True)
    buf, out = p.stdout, {}
    i = n = 0
    while i < len(buf) and n < len(paths):
        j = buf.index(b"\n", i)
        head = buf[i:j].split()
        i = j + 1
        if len(head) < 3 or head[1] in (b"missing", b"ambiguous"):
            n += 1
            continue
        size = int(head[2])
        out[paths[n]] = buf[i:i + size].decode("utf-8", "replace")
        i += size + 1
        n += 1
    return out


# -------------------------------------------------------------------------------- fingerprints


def d(node):
    return "" if node is None else ast.dump(node, annotate_fields=False)


def params(fn):
    """A `def`'s signature as STRUCTURED PARTS, because the verdict for two of the five break
    classes is arithmetic on the ORDER and the POSITIONAL-vs-KEYWORD-ONLY kind, and a
    stringified signature cannot be subtracted.

    The first version of this function returned a string and re-parsed it with a regex, which
    truncated at the first `)` -- and an `ast.dump` default is full of them -- so it reported
    `SIG-PARAM-REMOVED=54` where the truth is 9. A wrong count in the direction of MORE breakage
    is not a harmless error: it is a census that cries wolf on 45 records that never moved.
    """
    a = fn.args
    pos = [x.arg for x in (*a.posonlyargs, *a.args)]
    kw = [x.arg for x in a.kwonlyargs]
    # `ast.arguments.defaults` ALIGNS TO THE TAIL of `args`, not to its head: zipping it against
    # `a.args` pairs `self` with the first default. That made `UOp.toposort` report a flipped
    # default for `gate` -- which did not move -- and `enter_calls`, the one that DID flip True ->
    # False, as `required`. Both records were wrong, in opposite directions, on the exact
    # signature the sibling unit measured as break 3.
    dflt = {x.arg: d(v) for x, v in zip(a.args[len(a.args) - len(a.defaults):], a.defaults)}
    dflt.update({x.arg: d(v) for x, v in zip(a.kwonlyargs, a.kw_defaults)})
    ann = {x.arg: d(x.annotation) for x in (*a.posonlyargs, *a.args, *a.kwonlyargs)}
    return {"pos": tuple(pos), "kw": tuple(kw), "dflt": dflt, "ann": ann,
            "var": a.vararg.arg if a.vararg else "", "vkw": a.kwarg.arg if a.kwarg else "",
            "ret": d(fn.returns)}


def nt_fields(cls):
    for node in cls.body:
        if isinstance(node, ast.Assign) and d(node.value).startswith("Tuple("):
            try:
                return [ast.literal_eval(e) for e in node.value.elts]
            except ValueError:
                return None
    return None


def fingerprint(src, where):
    """The module's STRUCTURAL shape. Bodies are dropped on purpose: they are upstream's work.

    Everything kept here is something a reader can be BROKEN by: a field it subscripts, a
    keyword it passes, a constant it reads, a member it matches on, and the ORDER of each,
    because a removal at position k silently shifts every positional caller after it.
    """
    try:
        tree = ast.parse(src, where)
    except SyntaxError as exc:
        return None, f"SYNTAX@{exc.lineno}"
    cls, fn, const = {}, {}, {}
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            fields, enum = [], {}
            for st in node.body:
                if isinstance(st, ast.AnnAssign) and isinstance(st.target, ast.Name):
                    fields.append((st.target.id, d(st.annotation), d(st.value)))
                elif isinstance(st, ast.Assign):
                    for t in st.targets:
                        if isinstance(t, ast.Name):
                            enum[t.id] = d(st.value)
                elif isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    fn[f"{node.name}.{st.name}"] = params(st)
            cls[node.name] = {"base": [d(b) for b in node.bases], "fields": fields,
                              "enum": enum, "nt": nt_fields(node)}
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            fn[node.name] = params(node)
        elif isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    const[t.id] = d(node.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            const[node.target.id] = d(node.value) if node.value else ""
    return {"cls": cls, "fn": fn, "const": const}, None


def record(kind, mod, sym, old, target, order, at=None, ctor=None):
    return {"kind": kind, "module": mod, "symbol": sym, "old": old[:100], "target": target,
            "order": list(order), "at": at, "ctor": ctor}


def changes(old, new, mod, name2=None):
    """The structural differences between two fingerprints, each with the target a reader hits.

    `order` IS THE OLD ORDERED PARAMETER/FIELD LIST and `at` IS THE INDEX THAT MOVED, because
    the verdict for classes 2 and 4 is arithmetic on those two and nothing else.

    `Class.__init__` RECORDS ARE RE-TARGETED AT THE CLASS. A reader never calls `Buffer.__init__`;
    it calls `Buffer(...)`, and `__init__`'s parameters ARE the dataclass's fields, so a record
    filed against `fn:...Buffer.__init__#size` finds no reader and reports UNREAD for a
    constructor that 64 `.bend` files and 12 Python files actually use.
    """
    name2 = name2 or {}
    out = []
    for name, o in sorted(old["cls"].items()):
        n = new["cls"].get(name)
        here = [f[0] for f in o["fields"]]
        if n is None:
            out.append(record("CLASS-REMOVED", mod, name, "", f"cls:{mod}.{name}#", here))
            continue
        if o["base"] != n["base"]:
            # A BASE CHANGE IS A STRUCTURAL CHANGE, and the first version of this file computed
            # `base` and never compared it: `HIPDevice(Compiled)` -> `HIPDevice(CUDADevice)`
            # deletes the subclass's own `__init__` and swaps every inherited member, and the
            # census reported only the `__init__` deletion with no statement about WHY.
            out.append(record("CLASS-BASE-CHANGED", mod, name,
                              f"{o['base']} -> {n['base']}", f"cls:{mod}.{name}#", here))
        nf = {f[0]: f[1:] for f in n["fields"]}
        for i, (f, ann, dv) in enumerate(o["fields"]):
            tgt = f"cls:{mod}.{name}#{f}"
            if f not in nf:
                out.append(record("FIELD-REMOVED", mod, f"{name}.{f}", ann, tgt, here, i))
            elif nf[f][1] != dv:
                out.append(record("FIELD-DEFAULT", mod, f"{name}.{f}", dv, tgt, here, i))
            elif nf[f][0] != ann:
                out.append(record("FIELD-TYPE", mod, f"{name}.{f}", ann, tgt, here, i))
        for m in sorted(set(nf) - set(here)):
            out.append(record("FIELD-ADDED", mod, f"{name}.{m}", "", f"cls:{mod}.{name}#{m}",
                              here, len(here)))
        for m, dv in o["enum"].items():
            if m not in n["enum"]:
                out.append(record("ENUM-MEMBER-REMOVED", mod, f"{name}.{m}", dv,
                                  f"cls:{mod}.{name}#{m}", list(o["enum"])))
        if o["nt"] != n["nt"]:
            out.append(record("NAMEDTUPLE-FIELDS", mod, name, json.dumps(o["nt"]),
                              f"cls:{mod}.{name}#", o["nt"] or []))
    for f, o in sorted(old["fn"].items()):
        n = new["fn"].get(f)
        tgt = f"fn:{mod}.{f}#"
        ctor = f.endswith(".__init__")
        if ctor:
            tgt = f"cls:{mod}.{f[:-9]}#"
        here = list(o["pos"]) + list(o["kw"])
        if n is None:
            out.append(record("DEF-REMOVED", mod, f, json.dumps(o)[:100], tgt, here, None, ctor))
            continue
        if o == n:
            continue
        idx = {name: i for i, name in enumerate(o["pos"])}
        for name in dict.fromkeys(here):
            # `self`/`cls` CANNOT be passed by a caller, so a change to one is a change to a body,
            # not to a shape. Emitting a record for it produced 4 of the 5 first-batch rows on
            # `Allocator.__init__(self)` and `Compiled.rt_buffer(self)`, all UNREAD.
            if name in ("self", "cls"):
                continue
            at = idx.get(name)
            if name not in n["pos"] and name not in n["kw"]:
                out.append(record("SIG-PARAM-REMOVED", mod, f"{f}({name})",
                                  str(o["dflt"].get(name, "required")), tgt + name, here, at))
            elif name in o["pos"] and name in n["kw"]:
                # `def f(a, b)` -> `def f(a, *, b)`: nothing raises at the definition and every
                # positional `f(1, 2)` becomes a TypeError. The sibling unit measured exactly this
                # shape as `_storage()`'s keyword-only `**kw` in `deff135d5`.
                out.append(record("SIG-PARAM-KIND", mod, f"{f}({name})", "positional->kwonly",
                                  tgt + name, here, at))
            elif name in n["kw"] and name not in o["kw"]:
                out.append(record("SIG-PARAM-ADDED", mod, f"{f}({name})", "kwonly",
                                  tgt + name, here, None))
            elif o["dflt"].get(name, "required") != n["dflt"].get(name, "required"):
                out.append(record("SIG-PARAM-DEFAULT", mod, f"{f}({name})",
                                  str(o["dflt"].get(name, "required")), tgt + name, here, at))
        if o["ret"] != n["ret"]:
            out.append(record("SIG-RETURN", mod, f, str(o["ret"])[:100], tgt, here))
        if (o["var"], o["vkw"]) != (n["var"], n["vkw"]):
            out.append(record("SIG-VARARGS", mod, f,
                              f"*{o['var']}/**{o['vkw']}->*{n['var']}/**{n['vkw']}", tgt, here))
    for c, v in sorted(old["const"].items()):
        if c not in new["const"]:
            out.append(record("CONST-REMOVED", mod, c, v, f"mod:{mod}.{c}#", []))
        elif new["const"][c] != v:
            out.append(record("CONST-VALUE", mod, c, v, f"mod:{mod}.{c}#", []))
    for r in out:
        if r["kind"] in ("CONST-REMOVED", "CLASS-REMOVED") and name2.get(r["symbol"]) is None:
            home = next((k for k in sorted(name2) if k.rsplit(".", 1)[-1] == r["symbol"]), None)
            if home and r["module"] not in home:
                # A NAME THAT MOVED MODULES IS A REMOVAL FOR EVERY `from X import Y`. Treating it
                # as an ordinary CONST-REMOVED and reading UNREAD for it is how 3 classes and 4
                # constants disappeared from the census: `CUDAQueue` went `ops_cuda` -> `ops_hip`
                # and `HCQ_RUNTIME_DEV` went `device` -> `engine/realize`, and an importer of the
                # old path raises ImportError.
                r["kind"] = r["kind"].replace("REMOVED", "MOVED")
                r["old"] = f"{r['module']}.{r['symbol']} -> {home}  |  {r['old']}"
    return out


# ----------------------------------------------------------------------- the population rule


def in_population(old_fp, new_fp, reject):
    """THE RULE, IN ONE PLACE. A file is in the population iff BOTH revisions' blobs parse as
    Python AND the module's structural fingerprint is not equal.

    `OLD-UNPARSEABLE` IS THE DANGEROUS REJECTION: a blob this Python cannot parse makes every
    dataclass field in it invisible to the census, and an invisible file wears the same number as
    an honest zero. That is why the count is printed rather than assumed.
    """
    if old_fp is None:
        reject["OLD-UNPARSEABLE"] += 1
        return False
    if new_fp is None:
        reject["NEW-UNPARSEABLE"] += 1
        return False
    if old_fp == new_fp:
        reject["FINGERPRINT-EQUAL"] += 1
        return False
    return True


# ------------------------------------------------------------------------------ tinygrad map


def tinygrad_map(rev):
    """`dotted name` -> (kind, owning dotted name) for every public name `rev` exposes.

    BUILT BY DISCOVERY (`git ls-tree -r`), never a hand list: `checks/gates-pop.py`'s `HOMES`
    tuple is this tree's recorded instance of a universe named by hand.
    """
    mods, name2, errs = {}, {}, defaultdict(int)
    paths = [p for p in git("ls-tree", "-r", "--name-only", rev, "tinygrad").split()
             if p.endswith(".py")]
    cached = batch_blobs(rev, paths)
    for p in paths:
        src = cached.get(p)
        if src is None:
            errs["BLOB-ABSENT"] += 1
            continue
        mod = p[:-3].removesuffix("/__init__").replace("/", ".")
        fp, err = fingerprint(src, p)
        if fp is None:
            errs[f"UNPARSEABLE-{err}"] += 1
            mods[mod] = None
            continue
        mods[mod] = fp
        for c in fp["cls"]:
            name2[f"{mod}.{c}"] = ("class", f"{mod}.{c}", bool(fp["cls"][c]["enum"]))
        for f in fp["fn"]:
            name2[f"{mod}.{f}"] = ("def", f"{mod}.{f}", False)
        for c, body in fp["cls"].items():
            # METHODS ARE REGISTERED AS NAMES. Most of a tinygrad API is reached as `u.resize()`,
            # and a census that resolves only `Name.attr` through an import sees NONE of it: the
            # first version of this file reported `UOp.toposort`'s flipped default as having no
            # reader while `graphcmp.py` calls it 16 times -- the sibling unit measured the damage
            # (`deff135d5` break 3) and the census could not see the caller at all.
            for m in (k.split(".", 1)[1] for k in fp["fn"] if k.startswith(f"{c}.")):
                name2[f"{mod}.{c}.{m}"] = ("method", f"{mod}.{c}.{m}", False)
        for c in fp["const"]:
            name2[f"{mod}.{c}"] = ("const", f"{mod}.{c}", False)
    for mod, fp in list(mods.items()):
        if fp is None:
            continue
        is_pkg = (mod.replace(".", "/") + "/__init__.py") in cached
        pkg = mod if is_pkg else mod.rsplit(".", 1)[0]
        for cand in (mod.replace(".", "/") + "/__init__.py", mod.replace(".", "/") + ".py"):
            src = cached.get(cand)
            if src is None:
                continue
            for node in ast.walk(ast.parse(src)):
                if not isinstance(node, ast.ImportFrom) or not node.level:
                    continue
                base = pkg
                for _ in range(node.level - 1):
                    base = base.rsplit(".", 1)[0]
                if node.module:
                    base = f"{base}.{node.module}"
                for a in node.names:
                    if a.name != "*":
                        name2[f"{mod}.{a.name}"] = ("reexport", f"{base}.{a.name}", False)
            break
    # FOLLOW THE RE-EXPORT CHAIN TO THE DEFINITION. `from tinygrad import ParamArg` must reach
    # `tinygrad.uop.ops.ParamArg`, or a reader that imported the short spelling files its site
    # under a name no structural record ever carries and the record reads UNREAD.
    for name in [n for n, v in name2.items() if v[0] == "reexport"]:
        seen, cur = {name}, name2[name][1]
        while name2.get(cur, ("",))[0] == "reexport" and cur not in seen:
            seen.add(cur)
            cur = name2[cur][1]
        name2[name] = name2.get(cur, ("reexport", cur, False))
    return mods, name2, dict(errs)


# ------------------------------------------------------------------------- the reader census


def resolve(node, bind):
    """`expr` -> the tinygrad name it denotes, or None."""
    if isinstance(node, ast.Name):
        return bind.get(node.id)
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
        return f"{bind[node.value.id]}.{node.attr}" if node.value.id in bind else None
    return None


def reader_census(rev, name2, src):
    """Walk this tree's `.py` with `os.walk` + import resolution; record every READ.

    A site is `(file, lineno, kind, target, source, n_positional, keywords)`. The arity is there
    because classes 2 and 4 of the break list are decided by it: a positional caller whose count
    passes the index that moved is BROKEN without being run.
    """
    sites, reject, blind = [], defaultdict(int), 0
    paths = [p for p in git("ls-tree", "-r", "--name-only", rev).split()
             if p.endswith(".py") and not p.startswith("tinygrad/")]
    cached = batch_blobs(rev, paths) if src == "HEAD" else {}
    for rel in paths:
        path = ROOT / rel
        text = path.read_text(errors="replace") if src == "worktree" and path.exists() \
            else cached.get(rel)
        if text is None:
            reject["BLOB-ABSENT"] += 1
            continue
        try:
            tree = ast.parse(text, rel)
        except SyntaxError:
            reject["READER-UNPARSEABLE"] += 1
            continue
        bind, shadow = {}, set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    bind[a.asname or a.name.split(".")[0]] = a.name if a.asname \
                        else a.name.split(".")[0]
            elif isinstance(node, ast.ImportFrom):
                mod = node.module or ""
                if not mod or (node.level and not mod):
                    continue
                for a in node.names:
                    bind[a.asname or a.name] = f"{mod}.{a.name}"
            elif isinstance(node, ast.Assign):
                shadow |= {t.id for t in node.targets if isinstance(t, ast.Name)}
        # A NAME THAT IS BOTH IMPORTED AND LOCALLY ASSIGNED is ambiguous: `test/helpers.py`'s own
        # `full_rewrite` is exactly this, and it is the recorded source of 24 phantom call sites.
        # It is KEPT (a dropped reader is worse than a possible false one) and COUNTED.
        reject["AMBIGUOUS-IMPORT-AND-ASSIGN-KEPT"] += len(shadow & set(bind))
        shadow -= set(bind)
        # `locals_` are the names whose CLASS this instrument infers, so a FIELD read through a
        # LOCAL (`pa.size`) is a read and not an invisible one. FOUR inferences and no more: a
        # PARAMETER ANNOTATION, an ANNOTATED ASSIGNMENT, a CONSTRUCTOR ASSIGNMENT, and an ALIAS
        # (`X = mod.Y` or `globals().update(Y=mod.Y)` -- which is how `.agents/slop/graphcmp.py`
        # injects `ParamArg`, and without it the ONE KNOWN BREAKAGE of this whole census is
        # INVISIBLE to the instrument built to find it).
        locals_ = {}
        for fn in [n for n in ast.walk(tree) if isinstance(
                n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))]:
            for arg in (*fn.args.posonlyargs, *fn.args.args, *fn.args.kwonlyargs):
                if isinstance(arg.annotation, ast.Name):
                    locals_[arg.arg] = bind.get(arg.annotation.id)
        # INFERENCE 5, AND THE LAST: a local assigned from a call to a LOCAL FUNCTION whose RETURN
        # ANNOTATION is a tinygrad class. Without it `SE = do_split_ends(SE_E)` leaves `SE`
        # unclassed and `SE.toposort()` invisible -- and `toposort`'s default is exactly the flag
        # that flipped, so the instrument's own known breakage sat one inference short.
        returns = {}
        for fn in [n for n in ast.walk(tree) if isinstance(
                n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
            if isinstance(fn.returns, ast.Name) and bind.get(fn.returns.id) in name2 \
                    and name2[bind[fn.returns.id]][0] == "class":
                returns[fn.name] = bind[fn.returns.id]
        for node in ast.walk(tree):
            pairs = []
            if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) \
                    and isinstance(node.annotation, ast.Name):
                pairs = [(bind.get(node.annotation.id), [node.target])]
            elif isinstance(node, ast.Assign):
                t = node.targets[0]
                names = [t] if isinstance(t, ast.Name) else getattr(t, "elts", [])
                val = node.value.func if isinstance(node.value, ast.Call) else node.value
                pairs = [(resolve(val, bind) or (
                    returns.get(val.id) if isinstance(val, ast.Name) else None), names)]
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                    and node.func.attr == "update" and isinstance(node.func.value, ast.Call) \
                    and isinstance(node.func.value.func, ast.Name) \
                    and node.func.value.func.id in ("globals", "locals", "vars"):
                pairs = [(resolve(kw.value, bind), [ast.Name(id=kw.arg)])
                         for kw in node.keywords if kw.arg]
            for tgt, names in pairs:
                if tgt in name2 and name2[tgt][0] == "class":
                    for n in names:
                        if isinstance(n, ast.Name):
                            locals_[n.id] = tgt
        class_of = {h: name2[t][1] for h, t in locals_.items() if t in name2}
        touches_tinygrad = bool(class_of) or any(v in name2 for v in bind.values())
        if not touches_tinygrad:
            reject["BINDS-NO-TINYGRAD-NAME"] += 1
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
                head = node.value.id
                if head in shadow:
                    continue
                cls = class_of.get(head)
                if cls:
                    sites.append((rel, node.lineno, "FIELD", f"cls:{cls}#{node.attr}", src, 0, ()))
                elif head not in class_of:
                    blind += 1
                dotted = f"{bind[head]}.{node.attr}" if head in bind else None
                if dotted and dotted in name2:
                    sites.append((rel, node.lineno, "NAME", f"mod:{dotted}#", src, 0, ()))
            elif isinstance(node, ast.Call):
                callee = resolve(node.func, bind)
                if callee is None and isinstance(node.func, ast.Name):
                    callee = class_of.get(node.func.id)
                if callee is None and isinstance(node.func, ast.Attribute) \
                        and isinstance(node.func.value, ast.Name) \
                        and node.func.value.id not in shadow \
                        and (c := class_of.get(node.func.value.id)):
                    callee = f"{c}.{node.func.attr}"
                if callee not in name2:
                    continue
                kw = tuple(k.arg for k in node.keywords if k.arg)
                npos = len(node.args) + (1 if any(isinstance(a, ast.Starred) for a in node.args)
                                         else 0)
                sites.append((rel, node.lineno, "CALL", f"call:{name2[callee][0]}:"
                              f"{name2[callee][1]}", src, npos, kw))
                if name2[callee][0] == "class":
                    for n in node.args:  # a bare positional dataclass construction
                        if isinstance(n, ast.Starred):
                            blind += 1
    return sites, dict(reject), blind


# ------------------------------------------------------------------- the token class (weaker)

TOKENS = (".bend", ".sh", ".mjs", ".py")


def token_mentions(rev, recs):
    """THE TOKEN CLASS: `.bend`, `.sh`, `.mjs`, `.py`. A token match, and NO resolution.

    DECLARED WEAKER ON PURPOSE. Bend has no import graph, so a name in a `.bend` file is a
    MENTION and not a read -- exactly the collision that produced 24 phantom `full_rewrite` call
    sites, and exactly what a regex over source text does when it reads a docstring: the sibling
    unit measured `graphcmp.py:1373` documenting `Ops.FLIP` in prose as a false member.
    `corroborated` is the OWNING name and the FIELD/MEMBER name inside a 40-line window, which is
    the weakest thing worth printing and is never promoted to a read.

    `.py` IS IN THIS CLASS ONLY TO ADJUDICATE `UNKNOWN`. A `.py` token for a record the AST census
    already resolved cannot be a new reader -- the census saw every `.py` attribute and every
    `.py` call -- so a `.py` token site on an `UNKNOWN` record is BY CONSTRUCTION a site the
    import resolver could not attribute, and naming it is what turns "UNKNOWN" into "these six
    lines decide it".
    """
    files = [p for p in git("ls-tree", "-r", "--name-only", rev).split() if p.endswith(TOKENS)
             and not p.startswith("tinygrad/")]
    want = {}
    for r in recs:
        owner = r["target"].split("#")[0].split(":")[-1].rsplit(".", 1)[-1]
        field = r["target"].split("#")[1] if "#" in r["target"] else ""
        if owner:
            want.setdefault(owner, set()).add(field)
    out = []
    for rel in files:
        try:
            lines = (ROOT / rel).read_text(errors="replace").splitlines()
        except OSError:
            continue
        toks = [set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", l)) for l in lines]
        for lineno, tokens in enumerate(toks, 1):
            for owner, fields in want.items():
                if owner not in tokens:
                    continue
                for field in fields:
                    if field in tokens:
                        out.append((rel, lineno, f"{owner}#{field}", "same-line"))
                    elif field and field in set().union(
                            *toks[max(0, lineno - 20):lineno + 20]):
                        out.append((rel, lineno, f"{owner}#{field}", "near"))
    return files, out


def control(recs, rev_old, rev_new):
    """THE POSITIVE CONTROL, and it is the reason any of the above can be believed.

    Every record claims "this name was in the OLD blob and is not in the NEW one, in THIS class,
    in this module". That claim is RE-READ FROM THE BLOBS AND CHECKED per record, with a FRESH
    parse of each revision and a FRESH walk of the class body -- NOT with the fingerprints the
    records were derived from, which would only prove the code agrees with itself. A census that
    cannot detect anything reports a clean zero, so the control must be able to FAIL.

    IT IS CLASS-SCOPED, AND THE UNSCOPED VERSION WAS WRONG ON 4 OF 128 CHECKS. A regex over the
    whole module saw `MultiBuffer.nbytes` and answered "still present" for a `Buffer.nbytes`
    property that upstream really did delete, and saw `var_prefix: str = "const "` -- an
    ANNOTATION upstream kept -- and answered the same for a later plain-Assign override it really
    did delete. Both records were TRUE and the control called them false, which is how a control
    that cannot fail becomes a control nobody reads.
    """
    paths = [p for p in changed_paths() if p.endswith(".py")]
    old, new = batch_blobs(rev_old, paths), batch_blobs(rev_new, paths)

    def members(src, mod):
        """`{class-or-None: {bucket: names}}`, where a bucket is one of `BUCKETS`."""
        try:
            tree = ast.parse(src)
        except SyntaxError:
            return {}
        out = {}
        for node in tree.body:
            if isinstance(node, ast.ClassDef):
                body = out.setdefault(node.name, {b: (set() if b != "args" else {})
                                                  for b in BUCKETS})
                body["cls"].add(node.name)
                for st in node.body:
                    if isinstance(st, ast.AnnAssign) and isinstance(st.target, ast.Name):
                        body["field"].add(st.target.id)
                    elif isinstance(st, ast.Assign):
                        body["assign"] |= {t.id for t in st.targets if isinstance(t, ast.Name)}
                    elif isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        body["def"].add(st.name)
                        body.setdefault("args", {}).setdefault(
                            st.name, {a.arg for a in (*st.args.posonlyargs, *st.args.args,
                                                     *st.args.kwonlyargs)})
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                top = out.setdefault(None, {b: (set() if b != "args" else {})
                                            for b in BUCKETS})
                top["def"].add(node.name)
                top["args"][node.name] = {
                    a.arg for a in (*node.args.posonlyargs, *node.args.args,
                                    *node.args.kwonlyargs)}
            elif isinstance(node, ast.Assign):
                out.setdefault(None, {b: (set() if b != "args" else {}) for b in BUCKETS}
                               )["mod"] |= {
                    t.id for t in node.targets if isinstance(t, ast.Name)}
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                # ANNOTATED MODULE CONSTANTS. `pm_float_decomp: PatternMatcher = ...` is the form
                # upstream uses for most of them, and a control that only read `Assign` reported 7
                # correct records as violations -- all 7 were this one line.
                out.setdefault(None, {b: (set() if b != "args" else {}) for b in BUCKETS}
                               )["mod"].add(node.target.id)
        return out

    tally, VIOLATIONS = defaultdict(int), []
    for r in recs:
        p = r["module"].replace(".", "/") + ".py"
        if p not in old:
            p = r["module"].replace(".", "/") + "/__init__.py"
        om = members(old.get(p) or "", r["module"])
        nm = members(new.get(p) or "", r["module"])
        kind, cls, name = r["kind"], None, r["symbol"].split("(")[0].split(".")[-1]
        member = r["target"].split("#")[1] if "#" in r["target"] else ""
        if kind.startswith(("FIELD-", "ENUM-MEMBER-REMOVED", "NAMEDTUPLE")):
            cls, key = r["target"].split("#")[0].split(":")[-1].rsplit(".", 1)[-1], \
                "field" if kind.startswith("FIELD-") else "assign"
            probe = member
        elif kind in ("SIG-RETURN", "SIG-VARARGS", "CLASS-BASE-CHANGED"):
            tally[f"n/a-{kind}"] += 1
            continue
        elif kind.startswith("SIG-"):
            # The FUNCTION must be present in both revisions and the PARAMETER gone from the new
            # one. Checking the function's presence alone called 54 real records wrong.
            owner, _, probe = r["symbol"].partition("(")
            probe = probe.rstrip(")")
            cls = owner.split(".")[0] if "." in owner else cls
            oargs = (om.get(cls) or out_none(om)).get("args", {}).get(owner.split(".")[-1], set())
            nargs = (nm.get(cls) or out_none(nm)).get("args", {}).get(owner.split(".")[-1], set())
            claim = ("REMOVAL" if kind in ("SIG-PARAM-REMOVED", "SIG-PARAM-KIND")
                     else "ADDITION" if kind == "SIG-PARAM-ADDED" else "CHANGE")
            ok = ((probe in oargs) != (probe in nargs)) if claim == "REMOVAL" \
                else (not probe in oargs and probe in nargs) if claim == "ADDITION" \
                else probe in oargs and probe in nargs
            tally[f"ARG-{claim}-{'CONFIRMED' if ok else 'VIOLATED'}"] += 1
            if not ok:
                tally[f"ARG-VIOLATED:{kind}"] += 1
                VIOLATIONS.append((kind, r["target"]))
            continue
        elif kind.startswith(("DEF-REMOVED", "CLASS-")):
            if kind == "CLASS-REMOVED":
                # A CLASS NAME IS NOT IN THE `def` BUCKET, and the first version of this control
                # looked for it there and reported 3 correctly-deleted classes as violations --
                # `CUDAQueue`, `HIPAllocator` and `HIPProgram` really are gone from all of upstream
                # (measured with `git grep 'class CUDAQueue' upstream -- tinygrad`, 0 hits), which
                # is upstream consolidating CUDA and HIP.
                cls, key, probe = cls, "cls", name
            elif kind == "DEF-REMOVED" and "." in r["symbol"]:
                cls, key, probe = r["symbol"].split(".")[0], "def", r["symbol"].split(".")[-1]
            else:
                cls, key, probe = cls, "def", name
        elif kind.startswith("CONST-"):
            key, probe = "mod", name
        else:
            key, probe = None, None
        if kind in ("CLASS-REMOVED", "CLASS-MOVED"):
            found_o, found_n = probe in om, probe in nm
        elif probe is None:
            tally["n/a-COULD-NOT-CHECK"] += 1
            continue
        else:
            found_o = probe in (om.get(cls) or out_none(om))[key]
            found_n = probe in (nm.get(cls) or out_none(nm))[key]
        claim = ("REMOVAL" if kind in ("FIELD-REMOVED", "DEF-REMOVED", "CLASS-REMOVED",
                                       "ENUM-MEMBER-REMOVED", "CONST-REMOVED", "CONST-MOVED",
                                       "CLASS-MOVED")
                 else "ADDITION" if kind == "FIELD-ADDED" else "CHANGE")
        ok = (found_o and not found_n) if claim == "REMOVAL" \
            else (not found_o and found_n) if claim == "ADDITION" else (found_o and found_n)
        tally[f"{claim}-{'CONFIRMED' if ok else 'VIOLATED'}"] += 1
        if not ok:
            tally[f"VIOLATED:{kind}"] += 1
            tally.setdefault  # keep the counter named above; the violators are printed below
            VIOLATIONS.append((kind, r["target"]))
    return dict(tally), VIOLATIONS


BUCKETS = ("field", "assign", "cls", "def", "mod", "args")


def out_none(m):
    return m.get(None) or {b: (set() if b != "args" else {}) for b in BUCKETS}


def changed_paths():
    return ["tinygrad/" + p for p in
            git("diff", "--name-only", f"{OLD}:tinygrad", f"{NEW}:tinygrad").split()]


# ------------------------------------------------------------------------------ the verdict


def adjudicate(recs, rev):
    """THE ADJUDICATION PASS, and it exists because 5 inferences could not resolve 33 real sites.

    For each `UNKNOWN` record, the `.py` TOKEN sites are read back and the LINE is classified:
    does it CALL the member, and does it pass the flipped parameter? A line that does neither is
    a REJECTION and is counted, because "the token was there but the line is prose" is the
    failure mode the sibling unit measured in `graphcmp.py:1373`. Nothing here is promoted to a
    verdict -- it is the evidence a human needs to close an `UNKNOWN`, printed with its
    denominators so the reader can argue with the classification and not only with the count.
    """
    tally, rows = defaultdict(int), []
    for r in recs:
        if r["verdict"] != "UNKNOWN" or not r["py_tokens"]:
            continue
        member, field = r["target"].split(":")[-1].split("#")
        member = member.rsplit(".", 1)[-1]
        cache = {}
        for rel, ln, _ in r["py_tokens"]:
            if rel not in cache:
                cache[rel] = batch_blobs(rev, [rel]).get(rel, "").splitlines()
            lines = cache[rel]
            if ln > len(lines):
                tally["LINE-OUT-OF-RANGE"] += 1
                continue
            text = lines[ln - 1]
            calls = bool(re.search(rf"\b{re.escape(member)}\s*\(", text))
            passes = bool(re.search(rf"\b{re.escape(field)}\s*=", text))
            tally["OMITS" if calls and not passes else
                  "PASSES-EXPLICITLY" if passes else "NO-CALL-ON-LINE"] += 1
            if calls and not passes:
                rows.append((rel, ln, text.strip()[:100]))
    return dict(tally), rows


# WHAT COUNTS AS ROUTINE, DECLARED BESIDE THE VERDICT THAT USES IT.
# A reader under one of these directories is run by something in this tree: `gates/` and `checks/`
# ARE the gates, `oracles/` is what the gates diff against, `test/` is upstream's suite and
# AGENTS.md calls it the ORACLE. Everything else -- `.agents/slop/`, `extra/`, `examples/` -- is a
# unit's scratch work or a demo, and a raiser there is invisible to every gate because no gate
# runs it. THAT IS THE WHOLE OF THE FIFTH VERDICT: not "broken" but "broken where nobody looks".
ROUTINE = ("gates/", "checks/", "oracles/", "test/", "examples/")
ROUTINE_COUNT = {}


def is_routine(path):
    for prefix in ROUTINE:
        if path.startswith(prefix):
            ROUTINE_COUNT[prefix] = ROUTINE_COUNT.get(prefix, 0) + 1
            return True
    ROUTINE_COUNT["non-routine"] = ROUTINE_COUNT.get("non-routine", 0) + 1
    return False


def ctor_accepts(new_mods, name2, cls, npos, kws, depth=0):
    """Does the NEW inheritance chain of `cls` accept a call with this arity and these keywords?

    THE ANSWER IS DECIDABLE, WHICH IS WHY IT IS COMPUTED INSTEAD OF CALLED `UNKNOWN`.
    `HIPDevice(Compiled)` lost its own `__init__` when it became `HIPDevice(CUDADevice)`, so a
    caller of `HIPDevice(device)` now runs the BASE's `__init__`.

    BASES ARE RESOLVED ACROSS MODULES, or the walk is a lie. The first version searched only the
    class's own module and concluded "no `__init__` in the chain: `object.__init__` takes no
    arguments" for BOTH `HIPDevice` and `HostAllocator` -- and `CUDADevice` lives in
    `tinygrad.runtime.ops_cuda`, so the walk simply never saw it. A WRONG REASON IS WORSE THAN NO
    REASON, and a confident `object.__init__` is the most wrong thing this file could print.
    An UNRESOLVABLE base now answers `None`, which is `UNKNOWN`, not `False`.
    """
    mod, _, short = cls.rpartition(".")
    spec = (new_mods.get(mod) or {}).get("cls", {}).get(short)
    if spec is None:
        return None, f"{cls} is not in the new map"
    for base in spec["base"]:
        m = re.fullmatch(r"Name\('([^']+)'.*", base) or re.fullmatch(r"'([^']+)'", base)
        bname = m.group(1) if m else None
        if not bname:
            return None, f"base {base[:60]} is not a bare Name this instrument can resolve"
        chain = name2.get(bname if "." in bname else f"{mod}.{bname}", ("", bname, False))[1]
        bmod, _, bshort = chain.rpartition(".")
        init = (new_mods.get(bmod) or {}).get("fn", {}).get(f"{bshort}.__init__")
        if init:
            ok = npos <= len(init["pos"]) + (1 if init["vkw"] else 0) and \
                all(k in list(init["pos"]) + list(init["kw"]) for k in kws)
            return ok, (f"base {chain}.__init__ takes {list(init['pos'])}"
                        f"{'+kwonly' + str(list(init['kw'])) if init['kw'] else ''}"
                        f"{'+**' + init['vkw'] if init['vkw'] else ''}")
        if depth < 12:
            ok, why = ctor_accepts(new_mods, name2, chain, npos, kws, depth + 1)
            if ok is not None:
                return ok, why
    return (False, f"{cls} inherits object.__init__, which takes no arguments") \
        if depth >= 6 else (None, f"chain of {cls} exceeds the depth bound of 12")


def verdict(r, reads, mentions, new_mods, name2):
    """THE FOUR-WAY VERDICT, PLUS THE FIFTH. Decided by ARITHMETIC wherever it can be.

    `reads` are the resolved sites for this target, each `(file, ln, kind, src, npos, kws)`.
    `order` is the OLD ordered field/parameter list and `at` the index that moved, so the
    positional question is: does any caller's positional count pass `at`?

    A CORROBORATED `.bend` MENTION IS NOT A READ and is never reported as one. Bend has no import
    graph, so `Buffer` in a `.bend` file could be the port's own `Buffer`; the verdict for that
    population is UNKNOWN with the deciding experiment named, which is the honest answer and is
    also the falsifier of "ParamArg.size is the only structural break".
    """
    base, field = r["target"].split("#")[0], r["target"].split("#")[1]
    calls = [s for s in reads if s[2] == "CALL"]
    attrs = [s for s in reads if s[2] != "CALL"]
    sites = calls or attrs
    if not sites:
        if mentions:
            return "UNKNOWN", (f"{len(mentions)} corroborated .bend mention(s), 0 resolved Python "
                               f"reader; decides it: run the .bend lane, or resolve Bend's imports")
        return "UNREAD", "no resolved reader, no corroborated mention"
    broken, why = False, ""
    if r["kind"] in ("FIELD-REMOVED", "SIG-PARAM-REMOVED", "SIG-PARAM-KIND", "FIELD-ADDED"):
        at = r["at"] if r["at"] is not None else 0
        shifted = [s for s in calls if s[4] > at]
        broken = bool(shifted)
        why = (f"{len(shifted)}/{len(calls)} call(s) pass position {at} positionally; "
               f"{len(attrs)} attribute read(s)")
    elif r["kind"] == "SIG-PARAM-DEFAULT":
        omitting = [s for s in calls if field not in s[5]]
        broken = bool(omitting)
        why = (f"default flipped; {len(omitting)}/{len(calls)} call(s) OMIT `{field}` and take "
               f"the new value")
    elif r["kind"] == "DEF-REMOVED" and r["ctor"]:
        # The subclass's own `__init__` is gone. The CLASS still exists, so "the name is GONE" is
        # a WRONG REASON and a wrong reason is worse than none; the class now constructs through
        # its base, and that is decidable by walking the chain.
        answers = [(s, ctor_accepts(new_mods, name2, base.split(":")[-1], s[4], s[5]))
                   for s in calls]
        bad = [(s, w) for s, (ok, w) in answers if ok is False]
        unknown = [w for _, (ok, w) in answers if ok is None]
        broken = bool(bad)
        if unknown and not bad:
            return "UNKNOWN", (f"the subclass __init__ is gone and the chain is UNRESOLVED: "
                               f"{unknown[0]}")
        why = ("class now constructs through its base: "
               + (f"{len(bad)}/{len(calls)} call(s) REJECTED by the base; e.g. "
                  f"{bad[0][1]}" if bad else
                  f"{len(calls)} call(s) all accepted by the base"))
    elif r["kind"] == "CLASS-BASE-CHANGED":
        # The class still exists, so "the name is GONE upstream" is a WRONG REASON. What moved is
        # every member the class no longer defines for itself, and nothing in this instrument can
        # decide that without diffing the two bases' surfaces.
        return "UNKNOWN", (f"the base changed, so every inherited member is a candidate: "
                           f"{len(calls)} call(s); decides it: diff the two bases' public surfaces")
    elif r["kind"] in ("ENUM-MEMBER-REMOVED", "CLASS-REMOVED", "DEF-REMOVED", "CONST-REMOVED"):
        broken = True  # the name no longer exists upstream: `getattr`/`Attribute` raises
        why = f"the name is GONE upstream: {len(attrs)} attribute read(s), {len(calls)} call(s)"
    else:
        why = f"{len(attrs)} attribute read(s), {len(calls)} call(s)"
    if not broken:
        return "READ-AND-STILL-CORRECT", why
    routine = [s for s in sites if is_routine(s[0])]
    if routine:
        return "READ-AND-BROKEN", why + f"; {len(routine)}/{len(sites)} site(s) under a ROUTINE dir"
    return "READ-AND-NOT-NOTICED", why + "; 0 sites under a ROUTINE dir, so no gate runs it"


# ------------------------------------------------------------------------------- the census


def census():
    # `git diff A:tinygrad B:tinygrad` reports paths RELATIVE TO `tinygrad/` -- `uop/ops.py`, not
    # `tinygrad/uop/ops.py` -- so `cat-file` silently answers with the OLD blob for every path and
    # the census reports FINGERPRINT-EQUAL for the whole population. The prefix is restored here.
    changed = ["tinygrad/" + p for p in
               git("diff", "--name-only", f"{OLD}:tinygrad", f"{NEW}:tinygrad").split()]
    py = [p for p in changed if p.endswith(".py")]
    head = git("rev-parse", "--short", "HEAD").strip()

    pop_reject, recs = defaultdict(int), []
    _, new_names, _ = tinygrad_map(NEW)
    for p in py:
        ofp, oerr = fingerprint(batch_blobs(OLD, [p]).get(p) or "", f"{OLD}:{p}")
        nfp, nerr = fingerprint(batch_blobs(NEW, [p]).get(p) or "", f"{NEW}:{p}")
        if in_population(ofp, nfp, pop_reject):
            recs += changes(ofp, nfp, p[:-3].removesuffix("/__init__").replace("/", "."),
                            new_names)
        elif ofp is None or nfp is None:
            pop_reject[f"DETAIL:{oerr or nerr}"] += 1

    new_mods, name2, maperrs = tinygrad_map(NEW)
    sites, reject, blind = [], defaultdict(int), 0
    for src in SOURCES:
        s, rej, b = reader_census("HEAD", name2, src)
        sites += s
        for k, v in rej.items():
            reject[f"{src}/{k}"] += v
        blind += b
    tfiles, tsites = token_mentions("HEAD", recs)

    by_target = defaultdict(list)
    for f, ln, kind, t, src, npos, kws in sites:
        by_target[t].append((f, ln, kind, src, npos, kws))
        # A CONSTRUCTOR CALL IS ALSO A READ OF EVERY FIELD-SLOT, so it is indexed under the class
        # too. Without this second key every re-targeted `Class.__init__(param)` record found no
        # caller at all -- which is how `Buffer.__init__(size) -> nbytes` (upstream RENAMED the
        # parameter, and every `Buffer(..., size=...)` keyword caller now raises TypeError) was
        # reported as "0 resolved Python readers" by an instrument that had 118 .bend mentions of
        # `Buffer` and the answer was one dict key away.
        if kind == "CALL" and t.startswith("call:class:"):
            by_target[f"cls:{t.split(':', 2)[2]}#"].append((f, ln, kind, src, npos, kws))
    mention_by = defaultdict(list)
    for rel, ln, tgt, how in tsites:
        mention_by[tgt].append((rel, ln, how))

    for r in recs:
        base, field = r["target"].split("#")
        r["reads"] = by_target.get(r["target"], []) + (
            by_target.get(base, []) if base.startswith("cls:") else [])
        r["mentions"] = mention_by.get(f"{base.rsplit('.', 1)[-1]}#{field}", [])
        r["py_tokens"] = [m for m in r["mentions"] if m[0].endswith(".py")]
        r["verdict"], r["why"] = verdict(r, r["reads"], r["mentions"], new_mods, name2)
    return {"head": head, "changed": changed, "py": py, "pop_reject": dict(pop_reject),
            "recs": recs, "maperrs": maperrs, "reject": dict(reject), "blind": blind,
            "tfiles": len(tfiles), "tsites": len(tsites),
            "pytok": sum(len(r["py_tokens"]) for r in recs)}


def report(c):
    recs = c["recs"]
    adj = adjudicate(recs, "HEAD")
    byk, byv = defaultdict(int), defaultdict(int)
    for r in recs:
        byk[r["kind"]] += 1
        byv[r["verdict"]] += 1
    print(f"HEAD           {c['head']}   (the census is pinned to it; the worktree is live)")
    print(f"POPULATION     {len(c['changed'])} changed files, {len(c['py'])} .py, "
          f"{len(c['changed']) - len(c['py'])} non-.py (rejected: not Python, no shape)")
    print("  rejected     " + ", ".join(f"{k}={v}" for k, v in sorted(c["pop_reject"].items())))
    print(f"  IN           {len({r['module'] for r in recs})} modules, {len(recs)} records")
    print("  by kind      " + ", ".join(f"{k}={v}" for k, v in sorted(byk.items())))
    print(f"TINYGRAD MAP   " + (", ".join(f"{k}={v}" for k, v in sorted(c["maperrs"].items()))
                               or "0 unusable blobs; errors: none"))
    print(f"READER POP     " + ", ".join(f"{k}={v}" for k, v in sorted(c["reject"].items())))
    print(f"  BLIND WIDTH  {c['blind']} attribute reads on a local of UNKNOWN class, summed over "
          f"{len(SOURCES)} sources")
    print(f"TOKEN CLASS    {c['tfiles']} .bend/.sh/.mjs/.py files, {c['tsites']} corroborated mentions "
          f"({c['pytok']} of them in .py, which is the adjudication list for UNKNOWN)")
    print("ROUTINE RULE   " + (", ".join(f"{k}={v}" for k, v in sorted(ROUTINE_COUNT.items()))
                              or "no BROKEN record reached the rule, so it has no denominator"))
    tally, bad = control(recs, OLD, NEW)
    print("CONTROL        " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    for kind, tgt in bad[:12]:
        print(f"      VIOLATED {kind} {tgt}")
    print("ADJUDICATION   " + (", ".join(f"{k}={v}" for k, v in sorted(adj[0].items()))
                              or "no UNKNOWN record had a .py token site"))
    for rel, ln, text in adj[1][:24]:
        print(f"      OMITS {rel}:{ln}  {text}")
    print(f"VERDICT        {verdict_of(PASS if recs else DEAD)}   " + ", ".join(
        f"{k}={v}" for k, v in sorted(byv.items())))
    for r in recs:
        if r["verdict"] == "UNREAD" and "--all" not in sys.argv:
            continue
        where = r["reads"] or [(a, b, h, 0, ()) for a, b, h in r["mentions"]]
        print(f"  {r['verdict']:24} {r['kind']:21} {r['module']}.{r['symbol']:32} "
              f"reads={len(where)} {r['why']}")
        for w in where[:3]:
            print(f"      {w[0]}:{w[1]} {w[2]}"
                  + (f" npos={w[3]}" if len(w) > 4 else ""))
        for m in r["py_tokens"][:6]:
            print(f"      PY-TOKEN {m[0]}:{m[1]} ({m[2]})")
    return recs


if __name__ == "__main__":
    out = census()
    recs = report(out)
    if "--rows" in sys.argv:
        Path(sys.argv[sys.argv.index("--rows") + 1]).write_text(json.dumps(
            {"head": out["head"], "old": OLD, "new": NEW, "recs": recs}, indent=1))
    sys.exit(PASS if recs else DEAD)