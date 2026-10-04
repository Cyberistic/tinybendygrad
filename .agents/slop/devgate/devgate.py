#!/usr/bin/env python3
"""devgate -- is the `DEV` assignment in this file a SETTING, or a COMMENT?

`Device.DEFAULT` is resolved when `tinygrad` is imported. So an assignment to the
environment that appears AFTER the import in the same file does not configure the
device: it is a comment, and the code believes it chose. MEASURED, no `DEV` in env:

    os.environ['DEV']='NULL';  from tinygrad import Device   ->  NULL   (early)
    from tinygrad import Device;  os.environ['DEV']='NULL'   ->  METAL  (late)

and the late form is worse when a `DEV` IS inherited: asking CPU under an inherited
`DEV=NULL` yields `NULL`, silently, reading as if it took effect.

So order is not a style question. devgate classifies, per file:

    EARLY     every DEV write precedes every tinygrad import          correct
    LATE      some DEV write follows an import                       INERT
    BOTH      the file writes DEV on both sides of an import         worse than either
    VENDORED  a vendored tree (tinygrad/, xd1/, opstree/, references/)
    NOPARSE   the file does not parse; devgate refuses to guess

THIS IS A CLASSIFIER, NOT A LINTER. It is built on `ast`, so a READ
(`os.environ.get('DEV')`, `os.getenv('DEV')`, upstream's own
`DEV = ContextVar("DEV")`) is never counted as a write -- which is exactly the
16-of-17 false-positive class C3b fell into, and `ast` cannot repeat it because a
read is not an assignment node.

Usage:  devgate.py FILE_OR_DIR...      classify, print one row per file
        devgate.py --plants           run the plant corpus, report the error rate
        devgate.py --check DIR...     rc 1 if any LATE file is in scope
"""
from __future__ import annotations

import argparse
import ast
import os
import re
import sys
import warnings
from dataclasses import dataclass, field

# ---------------------------------------------------------------- what counts as a write
# ENV_ASSIGN: the last dotted attribute before the subscript must be `environ`.
# A bare `DEV = ...` is a module-global binding, NOT an environment write -- upstream's
# `device.py` declares `DEV = ContextVar("DEV")` and that is a CONTRACT, not a defect.
ENV_OBJ = {"environ", "environb"}


def _subscript_key(node: ast.Subscript) -> str | None:
    """The string literal a subscript is keyed by, or None if it is not a literal."""
    s = node.slice
    if isinstance(s, ast.Constant) and isinstance(s.value, str):
        return s.value
    return None


def _is_env_store(target: ast.expr, shadowed: bool = False) -> str | None:
    """Return the DEV key if `target` is an environment DEV store, else None."""
    if not isinstance(target, ast.Subscript) or _subscript_key(target) != "DEV":
        return None
    obj = target.value
    if isinstance(obj, ast.Attribute) and obj.attr in ENV_OBJ:
        return "DEV"
    if isinstance(obj, ast.Name) and obj.id in ENV_OBJ and not shadowed:
        return "DEV"
    return None


@dataclass
class Event:
    line: int
    kind: str  # "WRITE" | "READ" | "IMPORT"
    text: str
    module_scope: bool = False


@dataclass
class Verdict:
    path: str
    lines: int
    writes: list[Event] = field(default_factory=list)
    reads: list[Event] = field(default_factory=list)
    imports: list[Event] = field(default_factory=list)
    unresolved: list[Event] = field(default_factory=list)
    owner: dict[int, str] = field(default_factory=dict)
    vendored: bool = False
    noparse: str | None = None

    @property
    def first_write(self) -> int | None:
        return min((e.line for e in self.writes), default=None)

    @property
    def first_import(self) -> int | None:
        """The earliest import of ANY scope. NOT the boundary -- use `first_module_import`;
        this one exists for the replay, which orders events by line and needs no verdict."""
        return min((e.line for e in self.imports), default=None)

    @property
    def module_imports(self) -> list[Event]:
        """Imports that run when the module body runs -- unconditionally, before any code
        in the file. THESE are the only boundary devgate may prove an order against."""
        return [e for e in self.imports if e.module_scope]

    @property
    def first_module_import(self) -> int | None:
        return min((e.line for e in self.module_imports), default=None)

    @property
    def klass(self) -> str:
        """The class.

        A write is PROVABLY EFFECTIVE when nothing that certainly runs first resolves the
        device: no module-scope import before it, and no import inside its OWN scope before it.
        Everything else is either certainly inert (`LATE`) or undecidable from source
        (`DEFERRED`) -- and MEASURED, calling the undecidable ones `LATE` produced a finding
        that `graphcmp.py` -- which really does ask for `--dev NULL` and really does get
        `NULL` -- contradicts. devgate reports what it can prove and names the rest."""
        if self.noparse: return "NOPARSE"
        if not self.writes and not self.unresolved: return "NONE"
        if self.vendored: return "VENDORED"
        if self.first_write is None: return "UNRESOLVED"
        if not self.imports: return "UNRESOLVED" if self.unresolved else "IMPORTLESS"
        inert = [w for w in self.writes if not self._provably_effective(w)]
        if inert and len(inert) < len(self.writes): return "BOTH"
        if inert: return "LATE" if self.first_module_import is not None else "DEFERRED"
        return "EARLY"

    @property
    def order_inert(self) -> bool:
        """The ORDER answer alone, with no policy label on top: is some write behind a
        module-scope import? This is the question the regex scan also answers."""
        i = self.first_module_import
        return i is not None and any(w.line > i for w in self.writes)

    def _provably_effective(self, w: Event) -> bool:
        """No module-scope import before `w`, and none in `w`'s own scope before it."""
        if self.first_module_import is not None and self.first_module_import < w.line:
            return False
        scope = self.owner.get(w.line, "")
        return not any(e.line < w.line and self.owner.get(e.line, "") == scope
                       for e in self.imports)

    @property
    def inert_lines(self) -> list[int]:
        """DEV writes that land after a module-scope import: the lines that do nothing."""
        first = self.first_module_import
        if first is None: return []
        return sorted(e.line for e in self.writes if e.line > first)


# ---------------------------------------------------------------- the loader-function trap
def loader_functions(tree: ast.Module) -> set[str]:
    """Names of functions that (transitively) pull tinygrad in.

    A tinygrad import hidden inside a def is only an import when the def is CALLED.
    `graphcmp.py` spells its import boundary `load_tinygrad()`; recognising that shape
    is what lets devgate see that `:2977` sets DEV and `:2978` crosses the boundary.
    """
    reaches: set[str] = set()
    changed = True
    while changed:
        changed = False
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            if node.name in reaches: continue
            if _calls_tinygrad(node) or any(
                _callee(c) in reaches for c in ast.walk(node) if isinstance(c, ast.Call)):
                reaches.add(node.name)
                changed = True
    return reaches


def _callee(call: ast.Call) -> str | None:
    """The name a call targets. Reading every `Name` instead of the callee snowballs the
    closure until every function in the file is a boundary -- MEASURED, that turned
    `graphcmp.py`'s `_variable()` into an import event and reported a LATE that a real run
    contradicts."""
    f = call.func
    return f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)


def _calls_tinygrad(fn: ast.FunctionDef) -> bool:
    for node in ast.walk(fn):
        if isinstance(node, ast.Import):
            if any(a.name.split(".")[0] == "tinygrad" for a in node.names): return True
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] == "tinygrad": return True
        elif isinstance(node, ast.Call):
            fnid = node.func
            if isinstance(fnid, ast.Attribute) and fnid.attr == "import_module":
                if node.args and isinstance(node.args[0], ast.Constant) \
                   and node.args[0].value == "tinygrad": return True
    return False


def is_tinygrad_import(node: ast.AST) -> bool:
    if isinstance(node, ast.Import):
        return any(a.name.split(".")[0] == "tinygrad" for a in node.names)
    if isinstance(node, ast.ImportFrom):
        return (node.module or "").split(".")[0] == "tinygrad"
    if isinstance(node, ast.Call):
        fnid = node.func
        if isinstance(fnid, ast.Attribute) and fnid.attr == "import_module":
            return bool(node.args and isinstance(node.args[0], ast.Constant)
                        and node.args[0].value == "tinygrad")
    return False


VENDOR_PREFIX = ("tinygrad/", "references/", "xd1/", "opstree/")

# A call only counts as a DEV event if it is one of these, on this kind of receiver. The list is a
# WHITELIST on purpose: `ContextVar('DEV')` in upstream's device.py mentions the literal DEV and is
# not a write, and an open-ended rule is what let C3b count a read as a write.
ENV_WRITE_ATTRS = {"setdefault", "update"}
ENV_READ_ATTRS = {"get", "getenv"}
OS_WRITE_NAMES = {"putenv", "unsetenv"}


def _module_index(root: str) -> dict[str, str]:
    """basename (no .py) -> path, for every .py under `root`. Lets devgate follow an
    aliased import (`import graphcmp as G`) to the file that really holds the boundary."""
    idx: dict[str, str] = {}
    for dp, dn, fns in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIR]
        for f in fns:
            if f.endswith(".py") and not f.startswith("."):
                idx.setdefault(f[:-3], os.path.join(dp, f))
    return idx


def _module_aliases(tree: ast.Module) -> dict[str, str]:
    """local binding -> module basename, from `import x as y` / `from a.b import x as y`."""
    out: dict[str, str] = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                out[a.asname or a.name.split(".")[0]] = a.name.split(".")[0]
        elif isinstance(n, ast.ImportFrom):
            for a in n.names: out[a.asname or a.name] = a.name
    return out


_LOADER_CACHE: dict[str, frozenset[str]] = {}


def resolve_external_loaders(tree: ast.Module, idx: dict[str, str]) -> set[str]:
    """Local names that reach a tinygrad import through ANOTHER module.

    `G.load_tinygrad()` with `import graphcmp as G` is a real import boundary; devgate just
    has to open the other file to see it. Without this, 9 real corpus-path provisioners were
    reported UNRESOLVED -- a verdict about devgate's reach, not about the code."""
    out: set[str] = set()
    aliases = _module_aliases(tree)                       # hoisted: O(tree), not O(calls)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call): continue
        f = node.func
        if not isinstance(f, ast.Attribute): continue
        owner_mod = aliases.get(f.value.id if isinstance(f.value, ast.Name)
                                else _qualname(f.value))
        if not owner_mod: continue
        path = idx.get(owner_mod)
        if not path: continue
        if path not in _LOADER_CACHE:
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", SyntaxWarning)
                    _LOADER_CACHE[path] = frozenset(loader_functions(ast.parse(src_of(path))))
            except SyntaxError:
                _LOADER_CACHE[path] = frozenset()
        if f.attr in _LOADER_CACHE[path]: out.add(f.attr)
    return out


def _qualname(node: ast.expr) -> str:
    if isinstance(node, ast.Name): return node.id
    if isinstance(node, ast.Attribute): return node.attr
    return ""


def _dev_call_class(call: ast.Call, shadowed: bool) -> str | None:
    """WRITE | READ | None for a call that mentions the literal 'DEV'."""
    if not _mentions_dev(call): return None
    fnid = call.func
    if not isinstance(fnid, ast.Attribute):
        # a bare NAME: `putenv('DEV', x)` only if os.putenv was star-imported; anything else
        # (ContextVar('DEV'), ...) is not an environment event at all.
        return "WRITE" if fnid.id in OS_WRITE_NAMES else None
    if shadowed and isinstance(fnid.value, ast.Name): return None
    if fnid.attr in OS_WRITE_NAMES: return "WRITE"
    if fnid.attr in ENV_WRITE_ATTRS and _is_env_obj(fnid.value): return "WRITE"
    if fnid.attr in ENV_READ_ATTRS and _is_env_obj(fnid.value): return "READ"
    return None


def _mentions_dev(node: ast.AST) -> bool:
    """The literal 'DEV' anywhere inside -- a subscript key, an arg, or a dict value."""
    return any(isinstance(n, ast.Constant) and n.value == "DEV" for n in ast.walk(node))


def _is_env_obj(node: ast.AST) -> bool:
    if isinstance(node, ast.Attribute): return node.attr in ENV_OBJ
    if isinstance(node, ast.Name): return node.id in ENV_OBJ
    return False


def _enclosing_functions(tree: ast.Module) -> dict[int, str]:
    """lineno of a node -> the innermost FunctionDef that encloses it."""
    owner: dict[int, str] = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for sub in ast.walk(node):
                if sub is not node and isinstance(sub, ast.AST) and hasattr(sub, "lineno"):
                    owner.setdefault(sub.lineno, node.name)
    return owner


def classify(path: str, rel: str | None = None, vendored: bool | None = None,
             idx: dict[str, str] | None = None) -> Verdict:
    rel = rel or path
    src = open(path, errors="replace").read()
    v = Verdict(path=rel, lines=len(src.splitlines()))
    v.vendored = any(p in rel.replace(os.sep, "/") for p in VENDOR_PREFIX) \
        if vendored is None else vendored
    try:
        with warnings.catch_warnings():          # upstream files carry invalid escapes; not ours
            warnings.simplefilter("ignore", SyntaxWarning)
            tree = ast.parse(src)
    except SyntaxError as e:
        v.noparse = f"{e.lineno}: {e.msg}"
        return v

    owner = _enclosing_functions(tree)
    v.owner = owner
    loaders = loader_functions(tree)
    # Only pay for cross-module resolution in a file that actually writes DEV: the question
    # devgate answers is about the boundary in THAT file, and 2k read-only files have none.
    if idx and "DEV" in src:
        loaders |= resolve_external_loaders(tree, idx)
    # a bare `environ = ...` anywhere means the name is not os.environ, so `environ['DEV'] = x`
    # is a dict store. (PLANT envd-not-env: reported clean, and it is NOT clean.)
    shadowed = any(isinstance(n, ast.Assign) and
                   any(isinstance(t, ast.Name) and t.id in ENV_OBJ for t in n.targets)
                   for n in ast.walk(tree))

    for node in ast.walk(tree):
        if is_tinygrad_import(node):
            # An import nested in a def is an import only when the def is called; its call site
            # is the event. (PLANT loader-fn-never-called: the def is dead, so nothing is imported.)
            if node.lineno not in owner:
                v.imports.append(Event(node.lineno, "IMPORT", ast.unparse(node),
                                       module_scope=True))
            continue
        if isinstance(node, (ast.Assign, ast.AugAssign)):
            for t in (node.targets if isinstance(node, ast.Assign) else [node.target]):
                if _is_env_store(t, shadowed):
                    v.writes.append(Event(node.lineno, "WRITE", ast.unparse(t)))
            continue
        if isinstance(node, ast.Call):
            cls = _dev_call_class(node, shadowed)
            if cls:
                (v.writes if cls == "WRITE" else v.reads).append(
                    Event(node.lineno, cls, ast.unparse(node)))
                continue
            name = _callee(node)
            if name in loaders:
                # A loader called at MODULE SCOPE is as unconditional as the import it defers.
                # A loader called only from inside another def is not, and stays DEFERRED.
                v.imports.append(Event(node.lineno, "IMPORT", f"{name}()  # deferred tinygrad",
                                       module_scope=node.lineno not in owner))
            elif name and "tinygrad" in name.lower():
                v.unresolved.append(Event(node.lineno, "UNRESOLVED", f"{name}()"))

    v.writes.sort(key=lambda e: e.line)
    v.reads.sort(key=lambda e: e.line)
    v.imports.sort(key=lambda e: e.line)
    seen, uniq = set(), []
    for e in v.writes:                       # one line can be reached twice (Call inside Assign)
        if e.line not in seen: seen.add(e.line); uniq.append(e)
    v.writes = uniq
    return v


# ---------------------------------------------------------------- corpus walk
SKIP_DIR = ("__pycache__", ".git", "node_modules", ".venv", "venv")

# A file devgate cannot parse is not thereby innocent, so a lexical fallback keeps it in scope
# rather than dropping it. Lexical is the RIGHT tool here precisely because AST is unavailable.
def src_of(p: str) -> str:
    try: return open(p, errors="replace").read()
    except OSError: return ""


def _textual_dev(src: str) -> bool:
    return '"DEV"' in src or "'DEV'" in src


def corpus(roots: list[str]) -> list[Verdict]:
    out = []
    idx = _module_index(roots[0]) if roots else {}
    for root in roots:
        for dp, dn, fns in os.walk(root):
            dn[:] = [d for d in dn if d not in SKIP_DIR]
            for f in sorted(fns):
                if not f.endswith(".py"): continue
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, root)
                try: v = classify(p, rel, idx=idx)
                except Exception as e:  # NEVER guess; a crash is a finding, not a silent skip
                    v = Verdict(path=rel, lines=0, noparse=f"devgate crashed: {e!r}")
                # THE DENOMINATOR IS "THIS FILE WRITES DEV". A file that only READS Device.DEFAULT, or that
                # calls a helper whose name merely mentions tinygrad, has no order question to answer.
                if v.writes or (v.noparse and _textual_dev(src_of(p))): out.append(v)
    return out


def report(vs: list[Verdict], verbose: bool = False) -> int:
    denom = [v for v in vs if v.klass in ("EARLY", "LATE", "BOTH", "DEFERRED",
                              "IMPORTLESS", "UNRESOLVED")]
    counts: dict[str, list[str]] = {}
    for v in vs: counts.setdefault(v.klass, []).append(v.path)
    print(f"denominator (assigns DEV and reaches tinygrad): {len(denom)}")
    for k in ("EARLY", "LATE", "BOTH", "DEFERRED", "IMPORTLESS", "UNRESOLVED",
                           "VENDORED", "NOPARSE"):
        if k in counts: print(f"  {k:11s} {len(counts[k]):4d}")
    if verbose:
        for k in ("LATE", "BOTH", "NOPARSE", "IMPORTLESS", "UNRESOLVED", "DEFERRED"):
            for v in vs:
                if v.klass != k: continue
                inert = ",".join(map(str, v.inert_lines)) or "-"
                print(f"  {k:10s} {v.path}:{v.first_write} (module-import @"
                      f"{v.first_module_import}) inert:{inert}")
    return len(denom)

# ---------------------------------------------------------------- plants: devgate's own error rate
# Every plant has a ground truth KNOWN BY CONSTRUCTION. devgate is wrong if it disagrees.
# These test the PARSE (the part replay cannot test): indented imports, reads that are not
# writes, vendored contracts, the loader-function shape, and both-orders-in-one-file.
PLANTS: list[tuple[str, str, str]] = [
    # (label, expected class, source)
    ("early-module", "EARLY",
     "import os\nos.environ['DEV']='NULL'\nfrom tinygrad import Device\n"),
    ("late-module", "LATE",
     "from tinygrad import Device\nimport os\nos.environ['DEV']='NULL'\n"),
    ("early-indented-import", "EARLY",
     "import os\nos.environ['DEV']='NULL'\nif 1:\n    from tinygrad import Device\n"),
    ("late-indented-import", "LATE",
     "if 1:\n    from tinygrad import Device\nimport os\nos.environ['DEV']='NULL'\n"),
    ("both-orders", "BOTH",
     "import os\nos.environ['DEV']='NULL'\nfrom tinygrad import Device\nos.environ['DEV']='CPU'\n"),
    ("read-is-not-a-write", "NONE",
     "import os\nx = os.environ.get('DEV')\ny = os.getenv('DEV')\nfrom tinygrad import Device\n"),
    ("setdefault-is-a-write", "LATE",
     "from tinygrad import Device\nos.environ.setdefault('DEV','NULL')\n"),
    ("setdefault-early", "EARLY",
     "import os\nos.environ.setdefault('DEV','NULL')\nfrom tinygrad import Device\n"),
    ("update-is-a-write", "LATE",
     "from tinygrad import Device\nos.environ.update({'DEV':'NULL'})\n"),
    ("putenv-is-a-write", "LATE",
     "from tinygrad import Device\nos.putenv('DEV','NULL')\n"),
    ("putenv-single-quotes", "LATE",           # C3b's SET list missed this spelling
     "from tinygrad import Device\nos.putenv('DEV','NULL')\n"),
    ("loader-fn-early", "EARLY",
     "import os\nos.environ['DEV']='NULL'\ndef load_tinygrad():\n    import tinygrad\nload_tinygrad()\n"),
    ("loader-fn-late", "LATE",
     "def load_tinygrad():\n    import tinygrad\nload_tinygrad()\nimport os\nos.environ['DEV']='NULL'\n"),
    ("loader-fn-never-called", "IMPORTLESS",
     "import os\nos.environ['DEV']='NULL'\ndef load_tinygrad():\n    import tinygrad\n"),
    ("loader-fn-two-hops", "LATE",
     "def a():\n    b()\ndef b():\n    import tinygrad\na()\nimport os\nos.environ['DEV']='NULL'\n"),
    ("loader-imported-elsewhere", "UNRESOLVED",
     "import os\nfrom other import load_tinygrad\nos.environ['DEV']='NULL'\nload_tinygrad()\n"),
    ("contract-is-not-a-write", "NONE",
     "DEV = ContextVar('DEV')\nfrom tinygrad import Device\n"),
    ("importlib", "LATE",
     "import importlib, os\nimportlib.import_module('tinygrad')\nos.environ['DEV']='NULL'\n"),
    ("subdir-import", "EARLY",
     "import os\nos.environ['DEV']='NULL'\nfrom tinygrad.uop.ops import UOp\n"),
    ("write-after-both-imports", "LATE",
     "import os\nfrom tinygrad import Tensor\nos.environ['DEV']='NULL'\nfrom tinygrad import Device\n"),
    # module-scope import runs unconditionally; a function-local one runs only when called.
    ("module-scope-call-is-a-boundary", "LATE",
     "def f():\n    from tinygrad import Device\nf()\nimport os\nos.environ['DEV']='NULL'\n"),
    ("module-scope-late-is-provable", "LATE",
     "from tinygrad import Device\nimport os\nos.environ['DEV']='NULL'\n"),
    ("never-called-is-not-a-boundary", "IMPORTLESS",
     "import os\nos.environ['DEV']='NULL'\ndef f():\n    from tinygrad import Device\n"),
    ("call-site-inside-a-def", "EARLY",
     "import os\nos.environ['DEV']='NULL'\ndef load_tinygrad():\n    import tinygrad\n"
     "def main():\n    load_tinygrad()\n"),
    # a boundary in a DIFFERENT function, reached before this one, is undecidable from source
    ("write-then-boundary-in-one-scope", "EARLY",
     "import os\ndef load_tinygrad():\n    import tinygrad\ndef main():\n"
     "    os.environ['DEV']='NULL'\n    load_tinygrad()\n"),
    # devgate DECLINES to call this LATE: a boundary under a condition would make that unsound,
    # so the class is DEFERRED and the runtime check in DEV-GATE.md is what resolves it.
    ("boundary-then-write-in-one-scope", "DEFERRED",
     "import os\ndef load_tinygrad():\n    import tinygrad\ndef main():\n"
     "    load_tinygrad()\n    os.environ['DEV']='NULL'\n"),
    ("envd-not-env", "NONE",                  # `environ` as a local name is NOT os.environ
     "environ = {}\nenviron['DEV'] = 'NULL'\nfrom tinygrad import Device\n"),
]


def run_plants(verbose: bool = True, heldout: bool = False) -> tuple[int, int]:
    import tempfile
    bad = 0
    # MEASURED BUG, IN MY OWN READOUT: this returned `len(PLANTS)` unconditionally, so
    # --heldout reported "26/27" while running 15 plants. `n` is now the count it RAN.
    cases = HELDOUT if heldout else PLANTS
    for label, want, src in cases:
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write(src); p = f.name
        try:
            got = classify(p, f"plant:{label}").klass
        finally:
            os.unlink(p)
        ok = got == want
        bad += not ok
        if verbose or not ok:
            print(f"  {'ok  ' if ok else 'FAIL'} {label:26s} want={want:11s} got={got}")
    return len(cases), bad


# ---------------------------------------------------------------- HELD-OUT plants
# Written AFTER the classifier above was frozen, so their error rate is an estimate rather
# than a fixpoint. They were not used to change any rule; the first run of them was the run
# reported in DEV-GATE.md. Ground truth is known by construction, as above.
HELDOUT: list[tuple[str, str, str]] = [
    ("ho-module-late", "LATE",
     "from tinygrad import Device\nimport os\nos.environ['DEV']='NULL'\n"),
    ("ho-module-early", "EARLY",
     "import os\nos.environ['DEV']='NULL'\nfrom tinygrad import Device\n"),
    ("ho-late-under-if", "LATE",
     "from tinygrad import Device\nimport os\nif os.name == 'posix':\n    os.environ['DEV']='NULL'\n"),
    ("ho-late-in-class-body", "LATE",
     "from tinygrad import Device\nimport os\nclass C:\n    os.environ['DEV']='NULL'\n"),
    ("ho-early-in-try", "EARLY",
     "import os\ntry:\n    os.environ['DEV']='NULL'\nexcept Exception: pass\n"
     "from tinygrad import Device\n"),
    ("ho-setdefault-late", "LATE",
     "import os\nfrom tinygrad import Device\nos.environ.setdefault('DEV','NULL')\n"),
    ("ho-putenv-late", "LATE",
     "import os\nfrom tinygrad import Device\nos.putenv('DEV','NULL')\n"),
    ("ho-read-only", "NONE",
     "import os\nfrom tinygrad import Device\nprint(os.environ.get('DEV'), os.getenv('DEV'))\n"),
    ("ho-getenv-call-literal", "NONE",
     "import os\nfrom tinygrad import Device\nos.getenv('DEV', 'CPU')\n"),
    ("ho-contextvar", "NONE",
     "from contextvars import ContextVar\nDEV = ContextVar('DEV')\nfrom tinygrad import Device\n"),
    ("ho-both-sides", "BOTH",
     "import os\nos.environ['DEV']='CPU'\nfrom tinygrad import Device\nos.environ['DEV']='NULL'\n"),
    ("ho-nested-def-import-ignored", "IMPORTLESS",
     "import os\nos.environ['DEV']='NULL'\ndef f():\n    def g():\n        import tinygrad\n"
     "    g()\n"),
    ("ho-environ-shadow-late", "NONE",
     "from tinygrad import Device\nenviron = {'DEV': 'x'}\nenviron['DEV']='NULL'\n"),
    ("ho-loader-module-scope", "LATE",
     "def load():\n    import tinygrad\nload()\nimport os\nos.environ['DEV']='NULL'\n"),
    ("ho-no-tinygrad-at-all", "IMPORTLESS",
     "import os\nos.environ['DEV']='NULL'\n"),
]


# ---------------------------------------------------------------- replay: devgate's SEMANTICS
# devgate predicts that a LATE file's DEV write cannot affect Device.DEFAULT. That claim is
# testable: take the classified event ORDER and execute exactly that sequence in a fresh
# process with no DEV in the environment. This tests the RULE against a real interpreter.
def replay_order(order: list[tuple[str, str]], wants: list[str]) -> str:
    """Execute a classified event ORDER in a fresh process with no DEV in the environment.

    This is the only test of the RULE rather than the PARSE: it asks a real interpreter what
    device each ordering actually yields. `order` is [(kind, line)]; `wants[i]` is the device
    asked by the i-th write, and they must DIFFER -- asking every write for the same device
    cannot reveal which one was ignored, which is the whole question."""
    import subprocess, tempfile
    body = ["import os, sys", f"sys.path.insert(0, {os.getcwd()!r})"]
    k = 0
    for kind, _line in order:
        if kind == "WRITE":
            body.append(f"os.environ['DEV']={wants[k]!r}"); k += 1
        else:
            body.append("import tinygrad")
    body += ["from tinygrad import Device", "print(Device.DEFAULT)"]
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write("\n".join(body) + "\n"); p = f.name
    try:
        env = {k2: val for k2, val in os.environ.items() if k2 != "DEV"}
        r = subprocess.run([sys.executable, p], capture_output=True, text=True, env=env,
                           cwd=os.getcwd(), timeout=180)
        return (r.stdout.strip().splitlines()
                or [f"ERR:{r.stderr.strip()[-90:]}"])[-1]
    finally:
        os.unlink(p)


# Two DIFFERENT devices the ask can be: NULL is inert-proof, CPU is what this host has. If the
# late write really were inert, DEFAULT equals the FIRST ask and never the second.
ASK_A, ASK_B = "NULL", "CPU"


def semantics(plant_sets: list[list[tuple[str, str, str]]]) -> tuple[int, int]:
    """Replay every order-bearing plant. The FIRST write's ask must land iff the file is not LATE."""
    agree = disagree = 0
    import tempfile
    for cases in plant_sets:
        for label, want, src in cases:
            with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
                f.write(src); p = f.name
            try: v = classify(p, f"plant:{label}")
            finally: os.unlink(p)
            if v.klass not in ("EARLY", "LATE", "BOTH"): continue   # no order predicted
            order = [(e.kind, str(e.line)) for e in
                     sorted(v.writes + v.imports, key=lambda e: e.line)]
            nw = len(v.writes)
            wants = ([ASK_A] + [ASK_B] * (nw - 1)) if v.klass == "BOTH" else [ASK_A] * nw
            got = replay_order(order, wants)
            landed = got == wants[0]
            ok = landed if v.klass in ("EARLY", "BOTH") else not landed
            agree += ok; disagree += not ok
            print(f"  {'ok  ' if ok else 'FAIL'} {v.klass:6s} {label:34s} "
                  f"asked {wants[0]} then {'/'.join(wants[1:]) or '-'} -> got {got}")
    return agree, disagree


def replay(v: Verdict, want: str = "NULL") -> str:
    import subprocess, tempfile
    asked = want
    body = ["import os, sys", "sys.path.insert(0, %r)" % os.getcwd()]
    for e in sorted(v.writes + v.imports, key=lambda e: e.line):
        if e.kind == "WRITE": body.append(f"os.environ['DEV']={asked!r}")
        else: body.append("import tinygrad")
    body.append("from tinygrad import Device")
    body.append("print(Device.DEFAULT)")
    src = "\n".join(body) + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(src); p = f.name
    try:
        env = {k: val for k, val in os.environ.items() if k != "DEV"}
        r = subprocess.run([sys.executable, p], capture_output=True, text=True, env=env,
                           cwd=os.getcwd(), timeout=180)
        return (r.stdout.strip().splitlines() or [f"ERR:{r.stderr.strip()[-120:]}"])[-1]
    finally:
        os.unlink(p)


# ---------------------------------------------------------------- lexical cross-check
# A SECOND instrument with NO shared code: regex over lines instead of `ast`. Same question,
# independent parse. C3b was a regex scan too, and its 16-of-17 false-positive class came from
# treating a READ as a write -- so this one only accepts an ASSIGNMENT spelling.
WRITE_RE = re.compile(
    r"""(?:^|[^\w.])os\.environ\[["']DEV["']\]\s*=(?!=)      # os.environ['DEV'] = ...
      | (?:^|[^\w.])environ\[["']DEV["']\]\s*=(?!=)
      | os\.environ\.setdefault\(\s*["']DEV["']
      | os\.environ\.update\(\s*\{[^}]*["']DEV["']
      | os\.putenv\(\s*["']DEV["']""", re.X)
IMPORT_RE = re.compile(r"^\s*(?:import\s+tinygrad\b|from\s+tinygrad\b"
                       r"|\w+\.import_module\(\s*['\"]tinygrad)")


def lexical(path: str) -> tuple[list[int], list[int]]:
    src = open(path, errors="replace").read()
    writes = [i for i, ln in enumerate(src.splitlines(), 1) if WRITE_RE.search(ln)]
    imports = [i for i, ln in enumerate(src.splitlines(), 1) if IMPORT_RE.search(ln)]
    return writes, imports


def crosscheck(roots: list[str]) -> tuple[int, int]:
    """Compare the AST classifier with the regex scan on the ONE question they share: is this
    file's DEV write inert? A different CLASS LABEL is not a disagreement -- the vendored
    scoping is a policy devgate applies on top, and both instruments see the same order."""
    idx = _module_index(roots[0])
    same = diff = labels = 0
    for p in _all_py(roots):
        rel = os.path.relpath(p, roots[0])
        try: v = classify(p, rel, idx=idx)
        except Exception: continue
        if not v.writes: continue
        w, im = lexical(p)
        # the order question, asked identically of both instruments
        ast_inert = v.order_inert
        lex_inert = bool(w and im and min(w) > min(im))
        if ast_inert == lex_inert:
            same += 1
            if v.klass == "VENDORED": labels += 1
        else:
            diff += 1
            print(f"  DISAGREE {rel}: ast={v.klass} (write {v.first_write}, "
                  f"module-import {v.first_module_import})  "
                  f"regex={'inert' if lex_inert else 'effective'} (write {min(w) if w else None}, "
                  f"import {min(im) if im else None})")
    print(f"crosscheck on the ORDER question: {same} agree, {diff} disagree, over "
          f"{same + diff} files that write DEV")
    print(f"  ({labels} of the agreements are VENDORED -- same order, a label devgate adds on top)")
    return same, diff


def _all_py(roots: list[str]):
    for root in roots:
        for dp, dn, fns in os.walk(root):
            dn[:] = [d for d in dn if d not in SKIP_DIR]
            for f in sorted(fns):
                if f.endswith(".py"): yield os.path.join(dp, f)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="*", default=["."])
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--plants", action="store_true")
    ap.add_argument("--heldout", action="store_true",
                    help="the held-out plant set -- the honest error rate")
    ap.add_argument("--replay", action="store_true", help="execute each LATE file's event order")
    ap.add_argument("--check", action="store_true", help="rc 1 if any LATE file is in scope")
    ap.add_argument("--crosscheck", action="store_true",
                    help="AST classifier vs an independent regex scan")
    ap.add_argument("--why", action="store_true",
                help="one row per file showing the write line and the boundary it precedes")
    a = ap.parse_args(argv)

    if a.crosscheck:
        same, diff = crosscheck(a.roots)
        return 0 if diff == 0 else 1

    if a.plants or a.heldout:
        n, bad = run_plants(heldout=a.heldout)
        tag = "HELD-OUT plants" if a.heldout else "plants (a FIXPOINT: these fixed the rules)"
        print(f"\n{tag}: {n - bad}/{n} correct, {bad} misclassified")
        ag, dis = semantics([HELDOUT if a.heldout else PLANTS])
        print(f"semantics, EXECUTED: {ag}/{ag + dis} orderings behave as predicted, {dis} do not")
        return 0 if not bad else 1

    vs = corpus(a.roots)
    denom = report(vs, a.verbose)

    if a.why:
        # "cannot say why the other 29 are fine" is the failure this table exists to prevent:
        # every file shows ITS OWN write line and ITS OWN boundary line, so the order is
        # checkable by reading, per file, without trusting the classifier's summary.
        print("\nwrite -> boundary, per file (boundary '-' = no import anywhere in the file):")
        for v in sorted(vs, key=lambda x: x.path):
            b = v.first_module_import
            bs = f"{b}" if b is not None else "-"
            for w in v.writes:
                why = "same scope, no boundary before it" if b is None or w.line < b \
                    else "INERT" if b is not None and w.line > b else "?"
                print(f"  {v.klass:10s} {v.path}:{w.line} -> boundary {bs:>5s}   {why}")

    if a.replay:
        print("\nreplay of each non-EARLY file's event ORDER (no DEV in env, asked NULL):")
        agree = dis = 0
        for v in vs:
            if v.klass not in ("EARLY", "LATE", "BOTH", "VENDORED", "IMPORTLESS"): continue
            if v.vendored: continue
            got = replay(v)
            want = "NULL" if v.klass in ("EARLY", "VENDORED", "IMPORTLESS") else "!NULL"
            ok = (got == "NULL") if want == "NULL" else (got != "NULL")
            agree += ok; dis += not ok
            print(f"  {'ok  ' if ok else 'FAIL'} {v.klass:11s} {v.path:52s} asked NULL -> got {got}")
        print(f"\nreplay: {agree}/{agree + dis} agree with the prediction, {dis} disagree")
    if a.check:
        late = [v for v in vs if v.klass in ("LATE", "BOTH")]
        print(f"\n{'DEV-GATE OK' if not late else 'DEV-GATE FAILED'}: "
              f"{len(late)} file(s) assign DEV after importing tinygrad")
        for v in late:
            print(f"    {v.path}:{v.inert_lines}")
        return 1 if late else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
