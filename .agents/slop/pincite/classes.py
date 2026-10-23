#!/usr/bin/env python3
"""Classify every citation under (a) the CURRENT gate and (b) the REPAIRED gate."""
from __future__ import annotations
import collections, importlib.util, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATES = ROOT / "gates"
sys.path.insert(0, str(GATES))
spec = importlib.util.spec_from_file_location("pin_cite", GATES / "pin-cite-gate.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

HERE = Path(__file__).resolve().parent
blobs = json.loads((HERE / "blobs.json").read_text())
cites = json.loads((HERE / "citations.json").read_text())

IDENT = mod.IDENT
def tok_in(text: str, t: str) -> bool:
    return re.search(rf"\b{re.escape(t)}\b", text) is not None

def holds_old(lines, lo, hi, toks):
    return mod.holds(lines, lo, hi, toks)[0]

def holds_new(lines, lo, hi, toks):
    """REPAIR 1: also test the claim tokens against the WHOLE cited range."""
    if not (0 < lo <= len(lines)):
        return False
    if holds_old(lines, lo, hi, toks):
        return True
    if hi > lo:
        body = "\n".join(lines[lo - 1:hi])
        for t in toks:
            if tok_in(body, t):
                return True
    return False

def eval_path(path, lo, hi, toks, hf):
    revs = sorted({k.split(":", 1)[0] for k in blobs.get(path, {})},
                  key=lambda r: -blob_rev_index(path, r))
    # NEWEST FIRST: the cache keys are "<rev>:<path>"; order by the corpus order
    out = []
    for r in revs:
        text = blobs[path].get(f"{r}:{path}", "")
        out.append((r, text.splitlines()))
    return out

REV_ORDER: dict[str, list[str]] = {}
def blob_rev_index(path, rev):
    return REV_ORDER.setdefault(path, []).index(rev) if rev in REV_ORDER.get(path, []) else 0

def main() -> int:
    # build revision order per path from the cache (need the corpus order)
    spec2 = importlib.util.spec_from_file_location("pin_cite2", GATES / "pin-cite-gate.py")
    # reuse the census's Upstream to get the true newest-first order
    census = mod.load_census()
    corpus = census.Upstream(mod.UPSTREAM)
    order: dict[str, list[str]] = {}
    for path in blobs:
        corpus.load(path)
        pairs = corpus._steps.get(path) or []
        order[path] = [corpus.order[gi] for gi, _c in pairs]
    out = []
    for c in cites:
        path = c["path"]
        if not path or path not in blobs:
            continue
        revs = order.get(path, [])
        per = [(r, blobs[path].get(f"{r}:{path}", "")) for r in revs]
        toks = c["toks"]
        file_texts = [t for _r, t in per]
        # token presence in the file AT SOME REVISION
        present = {t: any(tok_in(text, t) for text in file_texts) for t in toks}
        res = {}
        for name, hf in (("old", holds_old), ("new", holds_new)):
            newest = ""
            for r, text in per:
                if hf(text.splitlines(), c["lo"], c["hi"], toks):
                    newest = r
                    break
            pin = per[0][1] if per else ""
            at_pin = hf(pin.splitlines(), c["lo"], c["hi"], toks)
            res[name] = {"newest": newest, "at_pin": at_pin}
        out.append({**c, "present": present, "revs": len(revs),
                    "old": res["old"], "new": res["new"]})
    (HERE / "classified.json").write_text(json.dumps(out))
    print(f"classified={len(out)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
