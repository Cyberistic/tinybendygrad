#!/usr/bin/env python3
"""pin-tree-oracle.py -- which tree each wired gate actually imports, and the
verdict under the pin (6c3d401cf324) and under .agents/slop/xd1/head.

Read-only on tinybendygrad/** and tinygrad/**. Tree swaps happen in a copy under
the opencode temp dir. Resume-safe: a finished attempt is not re-run.

    env -u PYTHONPATH -u TG_TREE -u TG_FORCE \
      .venv/bin/python .agents/slop/pin-tree-oracle.py --phase identity
"""
from __future__ import annotations

import ast
import patch_not_apply as PNA
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PY = REPO / ".venv" / "bin" / "python"
PIN = "6c3d401cf324"
RUNS = REPO / "runs" / "pin-tree-oracle"
SCRATCH = Path(os.environ.get("TMPDIR", "/tmp")) / "pin-tree-oracle"
SITE = SCRATCH / "site"
XD1_PIN = REPO / ".agents" / "slop" / "xd1" / "pin"
XD1_HEAD = REPO / ".agents" / "slop" / "xd1" / "head"
OPSTREE = REPO / ".agents" / "slop" / "opstree"
VENDOR = REPO  # package is REPO/tinygrad; sys.path root is the repo

# Trees the force-finder can point at. Values are sys.path roots (parent of tinygrad/).
TREES = {
    "pin": XD1_PIN,
    "xd1head": XD1_HEAD,
    "vendor": VENDOR,
    "opstree": OPSTREE,
}



# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows


def sh(argv, **kw):
    return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, **kw)


def git_blob(rev: str, path: str) -> str | None:
    """Blob hash, or None. A missing path is a failed rev-parse, never the empty blob."""
    d = sh(["git", "rev-parse", "--verify", f"{rev}:{path}"])
    if d.returncode:
        return None
    h = d.stdout.strip()
    return h or None


def file_blob(path: Path) -> str | None:
    if not path.is_file():
        return None
    d = sh(["git", "hash-object", str(path)])
    return d.stdout.strip() if d.returncode == 0 else None


def extract(rev: str, path: str, dest: Path) -> int:
    """git show to a file, then the byte count. Never grep the stream."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    d = sh(["git", "show", f"{rev}:{path}"])
    if d.returncode:
        dest.write_text("")
        return -1
    dest.write_bytes(d.stdout.encode())
    return dest.stat().st_size


def tree_manifest(root: Path, prefix: str = "tinygrad") -> dict[str, str]:
    """{relpath: blob} for every file under root/prefix. relpath includes prefix."""
    base = root / prefix
    out = {}
    if not base.is_dir():
        return out
    for dirpath, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            p = Path(dirpath) / f
            rel = prefix + "/" + str(p.relative_to(base))
            b = file_blob(p)
            if b:
                out[rel] = b
    return out


def git_manifest(rev: str, prefix: str = "tinygrad") -> dict[str, str]:
    d = sh(["git", "ls-tree", "-r", rev, "--", prefix])
    if d.returncode:
        raise SystemExit(f"ls-tree {rev} failed: {d.stderr.strip()[:200]}")
    out = {}
    for line in d.stdout.splitlines():
        # <mode> <type> <hash>\t<path>
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 3 and parts[1] == "blob":
            out[path] = parts[2]
    return out


def classify_root(logged: str) -> str:
    p = Path(logged).resolve()
    pairs = [
        (XD1_HEAD / "tinygrad", "xd1head"),
        (XD1_PIN / "tinygrad", "pin"),
        (OPSTREE / "tinygrad", "opstree"),
        (REPO / "tinygrad", "vendor"),
        (SCRATCH / "planted" / "tinygrad", "planted"),
        (SCRATCH / "head-copy" / "tinygrad", "head-copy"),
        (SCRATCH / "vendor-copy" / "tinygrad", "vendor-copy"),
    ]
    for root, name in pairs:
        try:
            p.relative_to(root.resolve())
            return name
        except ValueError:
            pass
    return f"OTHER:{p}"


def load_oracles() -> dict[str, str]:
    src = (REPO / ".agents" / "slop" / "rebase-gate.py").read_text()
    tree = ast.parse(src)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "BASE_ORACLES" for t in node.targets
        ):
            raw = ast.literal_eval(node.value)
            return {k: v[0] for k, v in raw.items()}
    raise SystemExit("BASE_ORACLES not found")


def write_site() -> None:
    SITE.mkdir(parents=True, exist_ok=True)
    (SITE / "sitecustomize.py").write_text(SITECUSTOMIZE)


SITECUSTOMIZE = r'''
import os, sys, builtins
from importlib.machinery import ModuleSpec
from importlib.util import spec_from_file_location

_tree = os.environ.get("TG_FORCE") or ""
_log = os.environ.get("TG_IMPORT_LOG") or ""
_seen = set()

def _note(name, mod):
    if not _log:
        return
    f = getattr(mod, "__file__", None)
    key = (name, f)
    if key in _seen or not f:
        return
    _seen.add(key)
    try:
        with open(_log, "a") as fh:
            fh.write(f"{name}\t{f}\n")
    except OSError:
        pass

if _tree:
    class _ForceTinygrad:
        @classmethod
        def find_spec(cls, fullname, path=None, target=None):
            if fullname != "tinygrad" and not fullname.startswith("tinygrad."):
                return None
            rel = fullname.replace(".", os.sep)
            base = os.path.join(_tree, rel)
            init = os.path.join(base, "__init__.py")
            py = base + ".py"
            if os.path.isfile(init):
                return spec_from_file_location(
                    fullname, init, submodule_search_locations=[base])
            if os.path.isfile(py):
                return spec_from_file_location(fullname, py)
            if os.path.isdir(base):
                spec = ModuleSpec(fullname, None, is_package=True)
                spec.submodule_search_locations = [base]
                return spec
            return None
    sys.meta_path.insert(0, _ForceTinygrad)

_real = builtins.__import__
def _hook(name, globals=None, locals=None, fromlist=(), level=0):
    mod = _real(name, globals, locals, fromlist, level)
    if isinstance(name, str) and (name == "tinygrad" or name.startswith("tinygrad.")):
        _note(name, mod)
    if fromlist and isinstance(name, str):
        for item in fromlist:
            sub = f"{name}.{item}" if name else item
            m = sys.modules.get(sub)
            if m is not None and (sub == "tinygrad" or sub.startswith("tinygrad.")):
                _note(sub, m)
    return mod
builtins.__import__ = _hook
'''


def slug(port: str) -> str:
    return port.replace("/", "_").replace(".bend", "")


def oracle_env(force: str | None, log: Path | None) -> dict[str, str]:
    """Clean env. PYTHONPATH is set only as the treatment (sitecustomize dir)."""
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "TG_TREE", "TG_FORCE", "TG_IMPORT_LOG")}
    env["DEV"] = "NULL"
    env["PYTHONPATH"] = str(SITE)
    if force:
        env["TG_FORCE"] = force
    if log:
        env["TG_IMPORT_LOG"] = str(log)
    return env


def run_oracle(spec: str, force_root: Path | None, dest: Path, timeout: int) -> dict:
    argv = spec.split()
    script = REPO / argv[0]
    log = dest.with_suffix(".imports")
    if log.exists():
        log.unlink()
    env = oracle_env(str(force_root) if force_root else None, log)
    t0 = time.time()
    try:
        c = subprocess.run(
            [str(PY), str(script), *argv[1:]],
            cwd=REPO, capture_output=True, text=True, env=env, timeout=timeout,
        )
        rc, out, err = c.returncode, c.stdout, c.stderr
        timed_out = False
    except subprocess.TimeoutExpired as e:
        rc, timed_out = 124, True
        out = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        err = (e.stderr or b"").decode() if isinstance(e.stderr, bytes) else (e.stderr or "")
        err += "\nTIMEOUT"
    dest.write_text(out)
    dest.with_suffix(".err").write_text(err)
    imports = []
    if log.exists():
        for line in log.read_text().splitlines():
            if "\t" in line:
                name, path = line.split("\t", 1)
                imports.append({"name": name, "file": path, "tree": classify_root(path)})
    meta = {
        "rc": rc,
        "timeout": timed_out,
        "elapsed": round(time.time() - t0, 2),
        "nrows": len(rows(out)),
        "bytes": len(out.encode()),
        "imports": imports,
        "err_tail": "\n".join(err.strip().splitlines()[-8:]),
    }
    dest.with_suffix(".meta.json").write_text(json.dumps(meta, indent=1))
    return meta


def attempt_path(kind: str, key: str, n: int) -> Path:
    d = RUNS / kind
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{key}__{n}.out"


def finished(path: Path) -> dict | None:
    meta = path.with_suffix(".meta.json")
    if path.exists() and meta.exists():
        return json.loads(meta.read_text())
    return None


def run_until(spec: str, force_root: Path | None, key: str, timeout: int, tries: int = 2) -> dict:
    """Re-run a 0-row result. A 0-row stdout is indistinguishable from not started."""
    last = None
    for n in range(1, tries + 1):
        dest = attempt_path("oracle", key, n)
        meta = finished(dest)
        if meta is None:
            meta = run_oracle(spec, force_root, dest, timeout)
        last = {"attempt": n, "out": str(dest), **meta}
        if meta["nrows"] > 0 or meta["timeout"]:
            return last
    return last


def run_bend(port: str, n: int, timeout: int = 180) -> dict:
    dest = attempt_path("bend", slug(port), n)
    meta_p = dest.with_suffix(".meta.json")
    if dest.exists() and meta_p.exists():
        return json.loads(meta_p.read_text())
    t0 = time.time()
    try:
        c = subprocess.run(
            [str(REPO / "bin" / "bend"), str(REPO / port)],
            cwd=REPO, capture_output=True, text=True, timeout=timeout,
        )
        rc, out, err = c.returncode, c.stdout, c.stderr
        timed_out = False
    except subprocess.TimeoutExpired as e:
        rc, timed_out = 124, True
        out = e.stdout if isinstance(e.stdout, str) else (e.stdout or b"").decode()
        err = e.stderr if isinstance(e.stderr, str) else (e.stderr or b"").decode()
    dest.write_text(out)
    dest.with_suffix(".err").write_text(err)
    overflow = "stack overflow" in err.lower() or "the machine stack overflowed" in err
    meta = {
        "rc": rc, "timeout": timed_out, "overflow": overflow,
        "elapsed": round(time.time() - t0, 2),
        "nrows": len(rows(out)), "bytes": len(out.encode()),
        "err_tail": "\n".join(err.strip().splitlines()[-6:]),
        "out": str(dest),
    }
    meta_p.write_text(json.dumps(meta, indent=1))
    return meta


def best_bend(port: str) -> dict:
    """Modal row-count over up to 3 runs. Never let a 0 win if a later run has rows.
    An overflow with partial rows is kept but labelled."""
    seen = []
    for n in range(1, 4):
        meta = run_bend(port, n)
        seen.append(meta)
        if meta["nrows"] > 0 and not meta["overflow"] and not meta["timeout"]:
            # one confirming run
            meta2 = run_bend(port, n + 1) if n < 3 else meta
            if n < 3:
                seen.append(meta2)
            break
        if meta["timeout"]:
            break
    counts = {}
    for m in seen:
        counts[m["nrows"]] = counts.get(m["nrows"], 0) + 1
    mode = max(counts, key=lambda k: (counts[k], k))
    chosen = next(m for m in seen if m["nrows"] == mode)
    chosen = dict(chosen)
    chosen["attempts"] = len(seen)
    chosen["distinct_counts"] = sorted(counts)
    return chosen


def verdict_of(port_rows: dict, oracle_meta: dict, oracle_text: str) -> dict:
    """GUARD 3, then 2, then 4, against the interpreted lane only. No baseline."""
    o = rows(oracle_text)
    if oracle_meta.get("timeout"):
        return {"state": "BROKEN", "why": "oracle TIMEOUT", "shared": 0, "disagree": []}
    if oracle_meta["rc"] != 0:
        return {
            "state": "BROKEN",
            "why": f"oracle rc={oracle_meta['rc']}: {oracle_meta.get('err_tail', '')[:240]}",
            "shared": len(set(port_rows) & set(o)),
            "disagree": [],
            "oracle_rows": len(o),
        }
    if not o:
        return {"state": "BROKEN", "why": "oracle produced ZERO name=value rows", "shared": 0, "disagree": []}
    if not port_rows:
        return {"state": "NO-PORT-ROWS", "why": "bend produced ZERO rows", "shared": 0, "disagree": [], "oracle_rows": len(o)}
    shared = set(port_rows) & set(o)
    if not shared:
        return {"state": "BROKEN", "why": "lane pair shares NO row names", "shared": 0, "disagree": [], "oracle_rows": len(o)}
    bad = []
    for k in sorted(shared):
        if port_rows[k] != o[k]:
            bad.append({"name": k, "port": port_rows[k], "oracle": o[k]})
    if bad:
        return {"state": "DISAGREE", "why": f"{len(bad)} shared row(s) disagree", "shared": len(shared), "disagree": bad, "oracle_rows": len(o)}
    return {"state": "AGREE", "why": f"{len(shared)} shared rows agree", "shared": len(shared), "disagree": [], "oracle_rows": len(o)}


def phase_identity() -> dict:
    print("identity: hashing trees", flush=True)
    pin_git = git_manifest(PIN)
    up_git = git_manifest("upstream/master")
    origin_git = git_manifest("origin/master")
    pin_disk = tree_manifest(XD1_PIN)
    head_disk = tree_manifest(XD1_HEAD)
    vendor_disk = tree_manifest(VENDOR)
    op_disk = tree_manifest(OPSTREE)

    def cmp(a, b, label):
        only_a = sorted(set(a) - set(b))
        only_b = sorted(set(b) - set(a))
        differ = sorted(p for p in set(a) & set(b) if a[p] != b[p])
        same = len(set(a) & set(b)) - len(differ)
        return {"label": label, "same": same, "differ": len(differ),
                "only_left": len(only_a), "only_right": len(only_b),
                "differ_paths": differ, "only_left_paths": only_a[:40],
                "only_right_paths": only_b[:40]}

    # Claim re-verify by EXTRACT, then wc, then read. Not a grep on the stream.
    claim_dir = RUNS / "claims"
    claim_dir.mkdir(parents=True, exist_ok=True)
    claims = {}
    for rev, name in ((PIN, "pin"), ("upstream/master", "upstream"), ("origin/master", "origin")):
        for rel in ("tinygrad/uop/render.py", "tinygrad/uop/ops.py"):
            dest = claim_dir / f"{name}__{rel.replace('/', '_')}"
            n = extract(rev, rel, dest)
            text = dest.read_text() if n > 0 else ""
            claims[f"{name}:{rel}"] = {
                "bytes": n,
                "blob": git_blob(rev, rel),
                "AddrSpace": text.count("AddrSpace"),
                "CustomFunction": text.count("CustomFunction"),
                "axis_id[0]": text.count("axis_id[0]"),
                "dtype_clause": 'if self.dtype is not dtypes.void' in text,
            }
    for label, root in (("xd1pin", XD1_PIN), ("xd1head", XD1_HEAD), ("vendor", VENDOR)):
        for rel in ("tinygrad/uop/render.py", "tinygrad/uop/ops.py"):
            p = root / rel
            text = p.read_text() if p.is_file() else ""
            claims[f"{label}:{rel}"] = {
                "bytes": p.stat().st_size if p.is_file() else -1,
                "blob": file_blob(p),
                "AddrSpace": text.count("AddrSpace"),
                "CustomFunction": text.count("CustomFunction"),
                "axis_id[0]": text.count("axis_id[0]"),
                "dtype_clause": "if self.dtype is not dtypes.void" in text,
            }

    # CallInfo.__repr__ extracted to its own file so the clause is a measurement.
    reprs = {}
    for label, text_src in (
        ("pin", (claim_dir / "pin__tinygrad_uop_ops.py").read_text()),
        ("upstream", (claim_dir / "upstream__tinygrad_uop_ops.py").read_text()),
        ("xd1head", (XD1_HEAD / "tinygrad/uop/ops.py").read_text()),
        ("vendor", (VENDOR / "tinygrad/uop/ops.py").read_text()),
        ("xd1pin", (XD1_PIN / "tinygrad/uop/ops.py").read_text()),
    ):
        start = text_src.find("class CallInfo")
        chunk = text_src[start:start + 2500] if start >= 0 else ""
        (claim_dir / f"callinfo_{label}.txt").write_text(chunk)
        reprs[label] = {
            "found": start >= 0,
            "chunk_bytes": len(chunk.encode()),
            "has_dtype_clause": "if self.dtype is not dtypes.void" in chunk,
            "has_CustomFunction_nearby": "CustomFunction" in text_src,
        }

    doc = {
        "pin": PIN,
        "upstream": sh(["git", "rev-parse", "upstream/master"]).stdout.strip(),
        "origin": sh(["git", "rev-parse", "origin/master"]).stdout.strip(),
        "cmp": {
            "xd1pin_vs_pin": cmp(pin_disk, pin_git, "xd1/pin vs 6c3d401cf324"),
            "xd1head_vs_upstream": cmp(head_disk, up_git, "xd1/head vs upstream/master"),
            "xd1head_vs_pin": cmp(head_disk, pin_git, "xd1/head vs pin"),
            "vendor_vs_pin": cmp(vendor_disk, pin_git, "vendor vs pin"),
            "vendor_vs_upstream": cmp(vendor_disk, up_git, "vendor vs upstream/master"),
            "vendor_vs_origin": cmp(vendor_disk, origin_git, "vendor vs origin/master"),
            "opstree_vs_upstream": cmp(op_disk, up_git, "opstree vs upstream/master"),
            "pin_vs_origin_render_ops": {
                "render_pin": git_blob(PIN, "tinygrad/uop/render.py"),
                "render_origin": git_blob("origin/master", "tinygrad/uop/render.py"),
                "render_upstream": git_blob("upstream/master", "tinygrad/uop/render.py"),
                "ops_pin": git_blob(PIN, "tinygrad/uop/ops.py"),
                "ops_origin": git_blob("origin/master", "tinygrad/uop/ops.py"),
                "ops_upstream": git_blob("upstream/master", "tinygrad/uop/ops.py"),
            },
        },
        "claims": claims,
        "callinfo": reprs,
    }
    (RUNS / "identity.json").write_text(json.dumps(doc, indent=1))
    c = doc["cmp"]
    print(f"  xd1/pin vs pin: same={c['xd1pin_vs_pin']['same']} differ={c['xd1pin_vs_pin']['differ']} only_disk={c['xd1pin_vs_pin']['only_left']} only_git={c['xd1pin_vs_pin']['only_right']}")
    print(f"  xd1/head vs upstream: same={c['xd1head_vs_upstream']['same']} differ={c['xd1head_vs_upstream']['differ']}")
    print(f"  vendor vs pin: same={c['vendor_vs_pin']['same']} differ={c['vendor_vs_pin']['differ']}")
    print(f"  render blobs pin={c['pin_vs_origin_render_ops']['render_pin']} origin={c['pin_vs_origin_render_ops']['render_origin']} upstream={c['pin_vs_origin_render_ops']['render_upstream']}")
    print(f"  xd1/head render blob={claims['xd1head:tinygrad/uop/render.py']['blob']} AddrSpace={claims['xd1head:tinygrad/uop/render.py']['AddrSpace']} axis_id0={claims['xd1head:tinygrad/uop/render.py']['axis_id[0]']}")
    print(f"  xd1/head ops blob={claims['xd1head:tinygrad/uop/ops.py']['blob']} CustomFunction={claims['xd1head:tinygrad/uop/ops.py']['CustomFunction']}")
    return doc


def phase_oracles(which: list[str] | None = None) -> None:
    write_site()
    oracles = load_oracles()
    (RUNS / "roster.json").write_text(json.dumps(oracles, indent=1))
    print(f"roster: {len(oracles)} wired gates", flush=True)
    # pin tree must exist and be the package root
    if not (XD1_PIN / "tinygrad" / "__init__.py").is_file():
        raise SystemExit(f"pin tree missing: {XD1_PIN}")
    jobs = []
    for port, spec in oracles.items():
        if which and port not in which and not any(w in port for w in which):
            continue
        jobs.append((port, spec, None, f"{slug(port)}__natural"))
        jobs.append((port, spec, XD1_PIN, f"{slug(port)}__pin"))
        jobs.append((port, spec, XD1_HEAD, f"{slug(port)}__xd1head"))
    print(f"oracle jobs: {len(jobs)}", flush=True)
    # sequential would be safer for import caches; processes are isolated. 6-wide.
    import concurrent.futures as cf
    def one(job):
        port, spec, root, key = job
        print(f"  start {key}", flush=True)
        meta = run_until(spec, root, key, timeout=240, tries=2)
        print(f"  done  {key} rc={meta['rc']} rows={meta['nrows']} {meta['elapsed']}s", flush=True)
        return key, meta
    with cf.ThreadPoolExecutor(max_workers=6) as ex:
        list(ex.map(one, jobs))


def phase_bend(which: list[str] | None = None) -> None:
    oracles = load_oracles()
    import concurrent.futures as cf
    ports = [p for p in oracles if not which or p in which or any(w in p for w in which)]
    print(f"bend jobs: {len(ports)}", flush=True)
    def one(port):
        print(f"  bend {port}", flush=True)
        meta = best_bend(port)
        print(f"  bend done {port} rows={meta['nrows']} attempts={meta['attempts']} counts={meta['distinct_counts']}", flush=True)
        return port, meta
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        list(ex.map(one, ports))


def load_text(path: str) -> str:
    return Path(path).read_text() if path and Path(path).is_file() else ""


def latest_attempt(kind: str, key: str) -> tuple[dict, str]:
    """Prefer the attempt with the most rows; a later 0 does not erase an earlier run."""
    best_m, best_t, best_n = None, "", -1
    for n in range(1, 5):
        dest = attempt_path(kind, key, n)
        meta_p = dest.with_suffix(".meta.json")
        if not meta_p.exists():
            continue
        meta = json.loads(meta_p.read_text())
        text = dest.read_text() if dest.exists() else ""
        if meta.get("nrows", 0) > best_n:
            best_n = meta["nrows"]
            best_m, best_t = meta, text
    if best_m is None:
        return {"rc": 127, "nrows": 0, "err_tail": "NOT RUN", "imports": []}, ""
    return best_m, best_t


def phase_report() -> None:
    ident = json.loads((RUNS / "identity.json").read_text())
    oracles = json.loads((RUNS / "roster.json").read_text()) if (RUNS / "roster.json").exists() else load_oracles()
    table = []
    diffs = {}
    for port, spec in oracles.items():
        bend_m = None
        bend_text = ""
        # bend meta is stored beside the out file; best_bend wrote attempt files
        bend_candidates = []
        for n in range(1, 5):
            dest = attempt_path("bend", slug(port), n)
            mp = dest.with_suffix(".meta.json")
            if mp.exists():
                m = json.loads(mp.read_text())
                m["text"] = dest.read_text() if dest.exists() else ""
                bend_candidates.append(m)
        if bend_candidates:
            bend_m = max(bend_candidates, key=lambda m: m["nrows"])
            bend_text = bend_m["text"]
        port_rows = rows(bend_text)
        nat_m, nat_t = latest_attempt("oracle", f"{slug(port)}__natural")
        pin_m, pin_t = latest_attempt("oracle", f"{slug(port)}__pin")
        head_m, head_t = latest_attempt("oracle", f"{slug(port)}__xd1head")
        trees = sorted({i["tree"] for i in nat_m.get("imports", []) if i["name"] == "tinygrad" or i["name"].startswith("tinygrad.")})
        # top-level tinygrad file if present
        top = next((i for i in nat_m.get("imports", []) if i["name"] == "tinygrad"), None)
        v_nat = verdict_of(port_rows, nat_m, nat_t)
        v_pin = verdict_of(port_rows, pin_m, pin_t)
        v_head = verdict_of(port_rows, head_m, head_t)
        pin_rows, head_rows = rows(pin_t), rows(head_t)
        # stable diff: names present in both, values differ. Also names only on one side.
        both = set(pin_rows) & set(head_rows)
        changed = []
        for k in sorted(both):
            if pin_rows[k] != head_rows[k]:
                changed.append({"name": k, "pin": pin_rows[k], "xd1head": head_rows[k],
                                "port": port_rows.get(k)})
        only_pin = sorted(set(pin_rows) - set(head_rows))
        only_head = sorted(set(head_rows) - set(pin_rows))
        flip = v_nat["state"] != v_pin["state"]
        table.append({
            "port": port, "oracle": spec,
            "natural_trees": trees,
            "natural_top": top["file"] if top else None,
            "natural_top_tree": top["tree"] if top else None,
            "bend_rows": len(port_rows),
            "bend_attempts": len(bend_candidates),
            "v_natural": {k: v_nat[k] for k in ("state", "why", "shared")},
            "v_pin": {k: v_pin[k] for k in ("state", "why", "shared")},
            "v_xd1head": {k: v_head[k] for k in ("state", "why", "shared")},
            "flip_if_pin": flip,
            "pin_vs_head_changed": len(changed),
            "only_pin": len(only_pin),
            "only_head": len(only_head),
            "pin_rc": pin_m["rc"], "head_rc": head_m["rc"], "nat_rc": nat_m["rc"],
            "pin_err": pin_m.get("err_tail", "")[:300] if pin_m["rc"] else "",
            "head_err": head_m.get("err_tail", "")[:300] if head_m["rc"] else "",
        })
        diffs[port] = {"changed": changed, "only_pin": only_pin, "only_head": only_head,
                       "pin_disagree": v_pin["disagree"][:40],
                       "head_disagree": v_head["disagree"][:40],
                       "nat_disagree": v_nat["disagree"][:40]}
    doc = {"identity_summary": {
        "xd1pin_vs_pin": ident["cmp"]["xd1pin_vs_pin"],
        "vendor_vs_pin_differ": ident["cmp"]["vendor_vs_pin"]["differ"],
        "xd1head_vs_upstream_differ": ident["cmp"]["xd1head_vs_upstream"]["differ"],
    }, "table": table, "diffs": diffs}
    # drop the long path lists from the summary copy
    (RUNS / "report.json").write_text(json.dumps(doc, indent=1))
    flips = [t for t in table if t["flip_if_pin"]]
    print(f"gates={len(table)} flip_if_standardise_on_pin={len(flips)}")
    for t in table:
        print(f"  {t['v_natural']['state']:<12} -> pin {t['v_pin']['state']:<12} head {t['v_xd1head']['state']:<12} tree={t['natural_top_tree']}  {t['port']}")


def phase_control() -> None:
    """One gate, both ways, on an unmodified copy; then one planted swap."""
    write_site()
    spec = ".agents/slop/xd1/render-gate-oracle.py --gate"
    # unmodified copy of xd1/head
    copy = SCRATCH / "head-copy"
    if not (copy / "tinygrad" / "uop" / "render.py").is_file():
        if copy.exists():
            shutil.rmtree(copy)
        shutil.copytree(XD1_HEAD, copy, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))
    planted = SCRATCH / "planted"
    if planted.exists():
        shutil.rmtree(planted)
    shutil.copytree(copy, planted, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))
    target = planted / "tinygrad" / "uop" / "render.py"
    src = target.read_text()
    old = 'return \'\\n\'.join([f"{k} = {strip_parens(v)}" for k,v in ret.items()])'
    new = 'return \'\\n\'.join([f"{k} =X {strip_parens(v)}" for k,v in ret.items()])'
    if old not in src:
        raise SystemExit(PNA.not_applied(
            "plant anchor missing in render.py copy -- refusing to guess"))
    target.write_text(src.replace(old, new, 1))
    # confirm live tree was not touched
    live = (XD1_HEAD / "tinygrad" / "uop" / "render.py").read_text()
    if "=X " in live:
        raise SystemExit("LIVE TREE WAS MODIFIED -- abort")

    runs = {
        "natural_1": run_oracle(spec, None, attempt_path("control", "natural", 1), 180),
        "natural_2": run_oracle(spec, None, attempt_path("control", "natural", 2), 180),
        "forced_copy_1": run_oracle(spec, copy, attempt_path("control", "forced_copy", 1), 180),
        "forced_copy_2": run_oracle(spec, copy, attempt_path("control", "forced_copy", 2), 180),
        "planted": run_oracle(spec, planted, attempt_path("control", "planted", 1), 180),
    }
    texts = {k: attempt_path("control", k.split("_1")[0].split("_2")[0] if False else "", 1) for k in ()}
    def text_of(key, n):
        return attempt_path("control", key, n).read_text()
    n1, n2 = rows(text_of("natural", 1)), rows(text_of("natural", 2))
    f1, f2 = rows(text_of("forced_copy", 1)), rows(text_of("forced_copy", 2))
    pl = rows(text_of("planted", 1))
    def diff(a, b):
        both = set(a) & set(b)
        return sorted(k for k in both if a[k] != b[k]), sorted(set(a) - set(b)), sorted(set(b) - set(a))
    d_self = diff(n1, n2)
    d_ways = diff(n1, f1)
    d_plant = diff(f1, pl)
    # imports
    def trees(key, n):
        meta = json.loads(attempt_path("control", key, n).with_suffix(".meta.json").read_text())
        return sorted({i["tree"] for i in meta.get("imports", [])})
    doc = {
        "natural_vs_natural_changed": d_self[0],
        "natural_vs_forced_copy_changed": d_ways[0],
        "forced_vs_planted_changed": d_plant[0][:30],
        "forced_vs_planted_n": len(d_plant[0]),
        "natural_trees": trees("natural", 1),
        "forced_copy_trees": trees("forced_copy", 1),
        "planted_trees": trees("planted", 1),
        "natural_rows": len(n1),
        "forced_rows": len(f1),
        "planted_rows": len(pl),
        "live_untouched": "=X " not in live,
        "rcs": {k: v["rc"] for k, v in runs.items()},
    }
    (RUNS / "control.json").write_text(json.dumps(doc, indent=1))
    print(json.dumps({k: doc[k] for k in doc if k != "forced_vs_planted_changed"}, indent=1))
    print(f"planted moved {doc['forced_vs_planted_n']} rows; first: {d_plant[0][:8]}")


def main() -> int:
    phase = "all"
    which = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--phase":
            phase = args[i + 1]
            i += 2
        elif args[i] == "--only":
            which.append(args[i + 1])
            i += 2
        else:
            raise SystemExit(f"unknown arg {args[i]}")
    RUNS.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if phase in ("identity", "all"):
        phase_identity()
    if phase in ("oracles", "all"):
        phase_oracles(which or None)
    if phase in ("bend", "all"):
        phase_bend(which or None)
    if phase in ("control", "all"):
        phase_control()
    if phase in ("report", "all"):
        phase_report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
