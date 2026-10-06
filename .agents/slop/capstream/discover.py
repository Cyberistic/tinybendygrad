#!/usr/bin/env python3
"""Re-derive the `CAPTURED-STREAM` population by DISCOVERY, then split it by refusal reason.

The content rule is `sloptxt/classify.py`'s, REIMPLEMENTED here so the recount is
independent (a re-derivation that calls the original is not a second witness). The
ownership walk is `checks/no-txt.py`'s, same as `sloptxt/features.py`.

Population by discovery: `os.walk` + `.endswith('.txt')` + no-txt's SKIP/SKIP_PREFIX.
Refusal reason, per file, in the order `sloptxt/plan.py` used:

  DECLARED   basename is in `checks/differ.py`'s `declared()` set (generator's own name).
  REFERENCED a committed CODE file names the basename or the repo-relative path.
  NEITHER    neither -- this is the group a rename is allowed to move.

No `.txt` is read for its class by name; only bytes.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")
NAME_RE = re.compile(rb"[\w./\-]+\.txt")


def owned(rel):
    parts = rel.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def find_txt():
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dp, f), ROOT)
                if owned(rel):
                    yield rel


# --- content rule (mirror of sloptxt/classify.py) ---------------------------------
def symbol_safe(k):
    return k and all(c.isalnum() or c in "_.:/()[]<>+-*" for c in k) and not k[0].isspace()


def kv_frac(lines):
    live = [l for l in lines if l.strip()]
    if not live:
        return 0.0
    return sum(1 for l in live if (i := l.find("=")) > 0 and symbol_safe(l[:i])) / len(live)


def is_canon(line):
    toks = line.split()
    return bool(toks) and all((c := t.find(":")) > 0 and t[:c].isdigit() for t in toks)


def row_frac(lines):
    body = [l for l in lines if l.strip() and not l.lstrip().startswith("#")]
    return sum(1 for l in body if is_canon(l)) / len(body) if body else 0.0


def is_prose(line):
    toks = line.split()
    if len(toks) < 6 or "=" in line:
        return False
    return sum(1 for t in toks if len(t) >= 2 and t.isalpha()) / len(toks) >= 0.6


def prose_frac(lines):
    live = [l for l in lines if l.strip()]
    n = sum(1 for l in live if is_prose(l))
    return n / len(live) if len(live) >= 3 and n >= 3 else 0.0


def tab_frac(lines):
    live = [l for l in lines if l.strip()]
    if len(live) < 3:
        return False
    counts = {l.count("\t") for l in live}
    return len(counts) == 1 and 0 not in counts


def source_kind(text):
    lines = text.splitlines()
    if lines and lines[0].startswith("#!"):
        return "SOURCE"
    if sum(1 for l in lines if l.startswith(("def ", "class ", "fn ", "struct ", "impl ", "pub "))) >= 2:
        return "SOURCE"
    if sum(1 for l in lines if l.startswith(("import ", "from ")) and "=" not in l) >= 2:
        return "SOURCE"
    return None


def classify(text):
    if not text.encode("utf-8", errors="replace"):
        return "EMPTY", ""
    if sk := source_kind(text):
        return sk, "source"
    lines = text.splitlines()
    if kv_frac(lines) >= 0.9:
        return "ROWDUMP", f"kv={kv_frac(lines):.2f}"
    if (rf := row_frac(lines)) >= 0.5:
        return "ROWDUMP", f"canon-rows={rf:.2f}"
    if tab_frac(lines):
        return "TABULAR", "tab"
    if (pf := prose_frac(lines)) >= 0.5:
        return "PROSE", f"prose={pf:.2f}"
    return "CAPTURED-STREAM", "default"


# --- refusal reasons --------------------------------------------------------------
def declared():
    spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks/differ.py"))
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    return set(d.declared())


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def readers_map(targets):
    by_base = {}
    for t in targets:
        by_base.setdefault(os.path.basename(t), []).append(t)
    refs = {t: [] for t in targets}
    for f in tracked():
        if not f.endswith(CODE_EXT):
            continue
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 2_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        for m in NAME_RE.finditer(data):
            base = os.path.basename(m.group(0).decode("utf-8", "replace"))
            if base in by_base:
                ln = data[: m.start()].count(b"\n") + 1
                for t in by_base[base]:
                    refs[t].append(f"{f}:{ln}")
    return refs


def main():
    targets = sorted(find_txt())
    cls = {}
    for t in targets:
        raw = open(os.path.join(ROOT, t), "rb").read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            cls[t] = ("UNCLASSIFIED", "non-utf8")
            continue
        cls[t] = classify(text)
    DEC = declared()
    refs = readers_map(targets)

    reason = {}
    for t in targets:
        c, _ = cls[t]
        if c == "EMPTY":
            reason[t] = "EMPTY"
        elif os.path.basename(t) in DEC:
            reason[t] = "DECLARED"
        elif refs[t]:
            reason[t] = "REFERENCED"
        else:
            reason[t] = "NEITHER"

    caps = [t for t in targets if cls[t][0] == "CAPTURED-STREAM"]
    split = Counter(reason[t] for t in caps)
    print(f"owned .txt (fresh walk): {len(targets)}")
    print(f"class census: {Counter(c for c, _ in cls.values()).most_common()}")
    print(f"CAPTURED-STREAM denominator: {len(caps)}")
    print(f"CAPTURED-STREAM by refusal: {split.most_common()}")
    print("NEITHER (rename candidates):")
    for t in caps:
        if reason[t] == "NEITHER":
            print(f"  {t}")

    out = {
        "targets": targets,
        "class": {t: cls[t][0] for t in targets},
        "rule": {t: cls[t][1] for t in targets},
        "reason": reason,
        "refs": {t: sorted(set(refs[t])) for t in targets if refs[t]},
    }
    json.dump(out, open(os.path.join(ROOT, ".agents/slop/capstream/discover.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
