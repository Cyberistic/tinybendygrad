#!/usr/bin/env python3
"""ANALYSIS HARNESS for gates/pin-cite-gate.py. Caches the upstream blobs so the
analysis can be re-run cheaply. Read-only: it touches nothing under tinybendygrad/."""
from __future__ import annotations
import collections, importlib.util, json, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATES = ROOT / "gates"
sys.path.insert(0, str(GATES))

spec = importlib.util.spec_from_file_location("pin_cite", GATES / "pin-cite-gate.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

CACHE = Path(__file__).resolve().parent / "blobs.json"

def main() -> int:
    census = mod.load_census()
    up, local = mod.collect(census, ROOT)
    corpus = census.Upstream(mod.UPSTREAM)
    by_path: dict[str, list[dict]] = collections.defaultdict(list)
    for c in up:
        c.setdefault("toks", [])
        path, how = corpus.resolve(c["subject"], history=True, prefer_dir=c.get("prefer_dir", ""))
        c["path"], c["how"] = path, how
        if path:
            by_path[path].append(c)
    if CACHE.exists():
        blobs = json.loads(CACHE.read_text())
    else:
        raw: dict[str, dict[str, str]] = {}
        for path in by_path:
            corpus.load(path)
            pairs = corpus._steps.get(path) or []
            revs = [corpus.order[gi] for gi, _c in pairs]
            raw[path] = mod.batch_blobs({f"{r}:{path}" for r in revs})
        blobs = {p: {k: v for k, v in d.items()} for p, d in raw.items()}
        CACHE.write_text(json.dumps(blobs))
    rows = []
    for path, cs in by_path.items():
        for c in cs:
            rows.append({
                "rel": c["rel"], "at": c["at"], "subject": c["subject"], "path": path,
                "lo": c["lo"], "hi": c["hi"], "explicit": c.get("explicit"),
                "line": c["line"], "toks": c["toks"],
            })
    (Path(__file__).resolve().parent / "citations.json").write_text(json.dumps(rows))
    print(f"citations={len(rows)} paths={len(by_path)} blobs={len(blobs)} cache={CACHE}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
