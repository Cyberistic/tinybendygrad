#!/usr/bin/env python3
"""THE INTERPRETER AN ENTRY POINT SHIPS, read from ITS SHEBANG.

Loaded by path by `divergence.py` and `siblings.py`, and by `gates/gate-surface.py` for its
own `reach()` -- ONE reader, so the census and the measurement cannot disagree about what a
file declared to be run with.

WHY THE SHEBANG AND NOT THE SUFFIX. `gates/gates-pop.py:141` writes `SUFFIXES = (".py", ".sh")`
and `gates/gate-surface.py:357` writes `if p.suffix != ".py": continue`. Both are suffix sets,
and doctrine 1 in `AGENTS.md` is explicit: *"A BASENAME SHAPE, A SUFFIX SET, AND A HAND LIST
ARE NOT POPULATIONS."* A `#!` line is a **declaration the file ships about itself** -- the
kernel's own rule for what to exec, and the only marker here that the file's author wrote on
the file's behalf. `checks/oracle-txt-census.py:164` already reached this verdict on its own
subject: *"A shebang is the one marker that is a DECLARATION rather than an inference."*

THE SIX-WAY CLASSIFICATION IS NOT A LIST OF FILES. It is a list of interpreter NAMES, which is
a different kind of claim: the population is every file that declares one, and the file's suffix
is never consulted. A `.sh` carrying `#!/usr/bin/env python3` classifies PYTHON here, and a
`.py` carrying `#!/bin/zsh` classifies SHELL here, and both would be invisible to a suffix set.

`env` IS RESOLVED, NOT ASSUMED. `#!` puts ONE token after the path on Linux and the kernel does
not run `env` at all, so a line naming `/usr/bin/env python3` is a declaration of an interpreter
*request*, and reading the first token would classify every `#!/usr/bin/env X` file as
"env" -- 0 of 17 discriminating. `-S`/`--split-string` and `NAME=value` assignments are skipped
because `env` skips them.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# The 6-255 exit space is the SHELL's, and 127 is its `command not found`; it is NOT one of the
# five verdicts and is NOT a USAGE. Kept here as a name so no caller re-derives the claim.
COMMAND_NOT_FOUND = 127

SHELLS = frozenset({"sh", "bash", "zsh", "dash", "ksh", "mksh", "ash", "busybox"})
NODE_NAMES = frozenset({"node", "nodejs"})
PYTHON_NAMES = ("python",)

_ENV_SKIP = frozenset({"-S", "--split-string", "--ignore-environment", "-i", "-"})
_SHEBANG = re.compile(r"^#!\s*(?P<rest>\S.*)$")


def _kind(name: str) -> str:
    """`name` -> PYTHON | SHELL | NODE | OTHER. The CLASS of the declared interpreter, by name."""
    base = name.rsplit("/", 1)[-1]
    if base in SHELLS:
        return "SHELL"
    if base in NODE_NAMES:
        return "NODE"
    if base.startswith(PYTHON_NAMES):
        return "PYTHON"
    return "OTHER"


class Declaration:
    """What ONE file says about how it must be run. `argv0` is what this harness actually execs."""

    __slots__ = ("path", "argv0", "kind", "declared", "why")

    def __init__(self, path, argv0, kind, declared, why):
        self.path, self.argv0, self.kind, self.declared, self.why = path, argv0, kind, declared, why

    def __repr__(self):
        return f"Declaration({self.path.name!r}, {self.kind}, argv0={self.argv0!r})"


def _py_interpreter() -> str:
    """`.venv/bin/python`, per `AGENTS.md`: *"RUN PYTHON THROUGH `.venv/bin/python`, NOT BARE
    `python`/`python3`. MEASURED HERE: PATH's `python3` is 3.14 and has no `.pth`."* A declaration
    naming `/usr/bin/env python3` is honoured by KIND, not by path -- 3.14 cannot run a port
    oracle, so honouring the literal path would be a second, quieter instance of this defect."""
    v = ROOT / ".venv" / "bin" / "python"
    return str(v) if v.is_file() else "python3"


def declared_interpreter(path) -> Declaration:
    """`Declaration` for `path`, or one with `argv0=None` and a `why` -- never an exception.

    A file with no shebang, an unresolvable one, or a truncated one is a STATE with a reason
    string, because "this instrument could not read it" and "this file declared nothing" are
    different findings and a caller that cannot tell them apart will call a gate broken.
    """
    path = Path(path)
    try:
        with path.open("rb") as fh:
            first = fh.readline(4096).decode("utf-8", "replace")
    except OSError as e:
        return Declaration(path, None, "UNREADABLE", "", f"{type(e).__name__}: {e}")
    m = _SHEBANG.match(first.rstrip("\n"))
    if not m:
        return Declaration(path, None, "NONE", "", "no `#!` on the first line")
    tokens = m.group("rest").split()
    while tokens and ("=" in tokens[0] and not tokens[0].startswith("=")):
        tokens.pop(0)                                  # `env FOO=bar python3`
    if tokens and tokens[0].rsplit("/", 1)[-1] == "env":
        tokens.pop(0)
        while tokens and (tokens[0] in _ENV_SKIP or ("=" in tokens[0] and not tokens[0].startswith("="))):
            tokens.pop(0)
    if not tokens:
        return Declaration(path, None, "NONE", "", "`#!` present but names no interpreter")
    named = tokens[0]
    kind = _kind(named)
    argv0 = {"PYTHON": _py_interpreter, "SHELL": lambda: named, "NODE": lambda: "node"}.get(
        kind, lambda: named)()
    return Declaration(path, argv0, kind, named, f"shebang names {named!r} -> {kind}")


def shipped_vocabulary() -> dict:
    """`gates/gatekit.py`'s `VERDICT`, LOADED BY PATH -- never retyped here.

    Re-typing `{0:"PASS",...}` would be a SECOND copy of the vocabulary, and a runner holding
    two copies is blind exactly where they disagree -- which is the defect
    `gates/gate-surface.py`'s own clause V exists for. Never by import: importing `gatekit`
    executes its module body.
    """
    import importlib.util

    p = ROOT / "gates" / "gatekit.py"
    spec = importlib.util.spec_from_file_location("gatekit_under_interp", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return dict(mod.VERDICT)


def token_of(rc, vocab=None) -> str:
    """`rc` -> the verdict TOKEN, and the FOURTH kind named rather than folded.

    `gatekit.charge()` maps every unassigned code to `REFUSED`, so a shell's 127 -- COMMAND NOT
    FOUND, the gate could not run at all -- arrives as "a precondition was absent", which is a
    claim about the TREE about a failure that happened to the HARNESS. 127 is named here as its
    own kind, and so is any other code the owner does not spell. The exit code is never the
    answer; the token is.
    """
    vocab = shipped_vocabulary() if vocab is None else vocab
    if rc in vocab and not isinstance(rc, bool):
        return vocab[rc]
    if rc == COMMAND_NOT_FOUND:
        return "COMMAND-NOT-FOUND(127)"
    return f"UNASSIGNED({rc})"


def load(path):
    """Load this module BY PATH from another instrument. `gates/` and `.agents/slop/` are not
    packages, so a name import would be shadowable and a shadowed population is chosen by
    whoever binds the name first."""
    import importlib.util

    spec = importlib.util.spec_from_file_location("interp_under_caller", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod