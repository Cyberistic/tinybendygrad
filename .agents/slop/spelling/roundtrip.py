#!/usr/bin/env python3
"""S-roundtrip -- does the generator reproduce the PRODUCT byte for byte?

The product `tinybendygrad/runtime/autogen/libclang.bend` is emitted in TWO steps:

    1. `.agents/slop/ag-emit.bend` (compiled by `bin/bend`) reads
       `.agents/slop/ag-libclang.tramp` and prints the raw file.
    2. `.agents/slop/clangshim/apply-port-lane.py` applies its fixes and appends
       the FFI lane.

This runs both, on this machine, and compares the result to the file on disk by
MD5, because `--check` alone can only say "the FIX agrees with the file" -- and a
product hand-edited until it agreed with the fix would satisfy `--check` exactly
as well.  The question "did the generator make this file, or did a person?" is
not the same question, and only the round trip answers it.

    python3 .agents/slop/spelling/roundtrip.py            # emit, fix, compare
    python3 .agents/slop/spelling/roundtrip.py --plants   # + two controls

`md5 -q` takes ONE file and a pipe swallows its exit status, so both digests are
taken here, over bytes this process already holds.

CONTROLS (the project rule is that a 0 is a theorem or a blind spot, never a
coverage claim):

  PLANT-A   put the Base-colliding declarations BACK into the PRODUCT and ask
            `bend --check-only`.  It must name `duplicate declaration`.  That is
            the wall `agent-core.md:149` records, and the reason a two-entry
            blocklist exists at all.
  DISARM-A  re-express the same removal by NAME instead of by literal text --
            the change this unit makes to the generator -- and require the
            rebuilt bytes to be IDENTICAL to the shipped rebuild.  A disarm that
            moves something is not a failed disarm, it is a defect.
"""
from __future__ import annotations

import argparse, hashlib, importlib.util, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BEND = REPO / "bin" / "bend"
EMIT = REPO / ".agents/slop/ag-emit.bend"
APPLIER = REPO / ".agents/slop/clangshim/apply-port-lane.py"
PRODUCT = REPO / "tinybendygrad/runtime/autogen/libclang.bend"


def load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def emit(stage: Path) -> bytes:
    """The emitter reads `ag-libclang.tramp` by a path relative to the CWD, so it
    must RUN from the repo root; only its OUTPUT lands in `stage`."""
    bin_ = stage / "ag-emit.bin"
    shutil.copy(EMIT, stage / "ag-emit.bend")
    subprocess.run([str(BEND), str(stage / "ag-emit.bend"), "-o", str(bin_)],
                   cwd=REPO, check=True, capture_output=True)
    return subprocess.run([str(bin_)], cwd=REPO, check=True, capture_output=True).stdout


def names(text: str) -> list[str]:
    return sorted(set(re.findall(r"^type (\w+) is Data:", text, re.M)))


def pin_root(src: str) -> str:
    """A copy of the applier in a scratch directory derives `REPO` from its OWN
    location and then reads `base.bend` out of `$TMPDIR`'s parent."""
    return src.replace("REPO = SHIM.parents[2]", f"REPO = Path({str(REPO)!r})")


# The two text bodies DISARM-A swaps. Named so a change to the rule is a loud
# `assert` here rather than a silent no-op control that always passes.
RULE_BODY = (
    '    for n in sorted(base_types()):\n'
    '        text = re.sub(rf"(?m)^type {n} is Data:\\n  {n}\\{{\\}}\\n\\n", "", text)\n')
LITERAL_BODY = (
    '    text = text.replace("type U32 is Data:\\n  U32{}\\n\\n", "")\n'
    '    text = text.replace("type Unit is Data:\\n  Unit{}\\n\\n", "")\n')


def run(tag: str, rebuilt: bytes) -> bool:
    prod = PRODUCT.read_bytes()
    ok = rebuilt == prod
    print(f"{tag:<8} {'PASS' if ok else 'FAIL'}   rebuilt={md5(rebuilt)}/{len(rebuilt)}B  "
          f"product={md5(prod)}/{len(prod)}B")
    if not ok:
        rl, pl = rebuilt.decode(errors="replace").split("\n"), prod.decode(errors="replace").split("\n")
        for i, (x, y) in enumerate(zip(rl, pl), 1):
            if x != y:
                print(f"    first difference, line {i}:")
                print(f"      rebuilt: {x[:120]}")
                print(f"      product: {y[:120]}")
                break
        else:
            print(f"    identical for {min(len(rl), len(pl))} lines; "
                  f"rebuilt has {len(rl)}, product has {len(pl)}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", action="store_true")
    a = ap.parse_args()

    with tempfile.TemporaryDirectory(prefix="s-roundtrip") as td:
        stage = Path(td)
        raw = emit(stage)
        print(f"EMITTER  rc=0   raw={md5(raw)}/{len(raw)}B/{raw.decode().count(chr(10))}L")

        mod = load(APPLIER)
        minted, shipped = names(raw.decode()), names(PRODUCT.read_text())
        dropped = [n for n in minted if n not in shipped]
        print(f"MINTED   {len(minted)} distinct `type X is Data` names; "
              f"the product carries none of {dropped}")

        if not run("BASE", mod.fix(raw.decode()).encode()):
            return 1

        if a.plants:
            # ---- PLANT-A: each collision, re-inserted into the PRODUCT ALONE.
            # ONE AT A TIME, and this is a fix to the first version of this
            # control: planting both and demanding `bend` name both reports FAIL,
            # because `bend` stops a batch parse at the FIRST error and said so
            # (`agent-core.md:43`). A control whose failure is the compiler's
            # documented stopping behaviour is a control that cannot fail.
            for n in dropped:
                prod = re.sub(rb"(?m)^import Base\n",
                              b"import Base\n\ntype " + n.encode() + b" is Data:\n  "
                              + n.encode() + b"{}\n", PRODUCT.read_bytes(), count=1)
                f = Path(td) / f"planted-{n}.bend"
                f.write_bytes(prod)
                cp = subprocess.run([str(BEND), str(f), "--check-only"],
                                    capture_output=True, text=True)
                named = [l.strip() for l in (cp.stdout + cp.stderr).split("\n")
                         if "duplicate declaration" in l]
                ok = cp.returncode == 1 and named and n in named[0]
                print(f"PLANT-A[{n:<4}] {'PASS' if ok else 'FAIL'}   re-inserted "
                      f"`type {n} is Data` into the product alone -> bend rc={cp.returncode}")
                for l in named:
                    print(f"              {l}")

            # ---- DISARM-A: same removal, a DIFFERENT EXPRESSION -------------
            # The disarm replaces the name-derived rule with the two-entry
            # literal list it replaced, and the two rebuilds must be BYTE-IDENTICAL:
            # a rule that behaves differently from the list is not a rewrite.
            #
            # NOTE the first attempt at this control set `DROPPED = []`, i.e. it
            # REMOVED the fix rather than re-expressing it, and reported FAIL with
            # a 56-byte difference.  A disarm that moves something is not a failed
            # disarm -- it is a control that was never a disarm.  `DROPPED` no
            # longer exists in `apply-port-lane.py`, so the list is spliced into a
            # copy that overrides the rule instead.
            # A copy of the applier in a scratch directory resolves `REPO` from
            # its OWN location and then reads `base.bend` out of `$TMPDIR`'s
            # parent.  Pin the root: this is the second harness defect of this
            # session and, like the first, it raised rather than reported -- which
            # is the good kind, because a control that cannot run cannot lie.
            src = pin_root(APPLIER.read_text())
            shutil.copy(APPLIER.parent / "ffi-lane.bend", Path(td) / "ffi-lane.bend")
            dis = Path(td) / "disarm.py"
            lit = src.replace(RULE_BODY, LITERAL_BODY)
            assert lit != src, "DISARM-A did not find the derived rule to replace"
            dis.write_text(lit)
            disout = load(dis).fix(raw.decode()).encode()
            base = mod.fix(raw.decode()).encode()
            same = disout == base
            print(f"DISARM-A {'PASS' if same else 'FAIL'}   the two-entry literal list "
                  f"rebuilds {md5(disout)}; identical to the derived rule: "
                  f"{'yes' if same else 'NO'}")

            # ---- PLANT-B: a Base name the literal list never named -----------
            # `F32` is declared by Base (`base.bend:60`) and is in NEITHER `DROPPED`
            # NOR `EXTRA`.  Minting it must still be refused, which is the whole
            # difference between a rule and a list.
            F32_PLANT = src.replace(
                'EXTRA = ["CXDiagnostic"',
                'EXTRA = ["F32", "CXDiagnostic"')
            fb = Path(td) / "plantB.py"
            fb.write_text(F32_PLANT)
            fbout = load(fb).fix(raw.decode())
            minted_f32 = bool(re.search(r"(?m)^type F32 is Data", fbout))
            print(f"PLANT-B  {'PASS' if not minted_f32 else 'FAIL'}   `F32` appended to "
                  f"EXTRA (a Base name: base.bend:60) -> still minted in the output: "
                  f"{minted_f32}")
            # ---- PLANT-B[first]: the rule runs FIRST instead of LAST ---------
            # The rule must run AFTER `EXTRA` gets its chance to mint, or the mint
            # re-introduces exactly what the rule removed.  This control MOVES the
            # call rather than adding a second one: the first attempt ADDED it at
            # the top and left the real one in place, so it proved nothing and
            # reported FAIL -- a control that cannot fail is not a control.
            moved = F32_PLANT.replace("    text = drop_base_types(text)\n", "")
            assert "drop_base_types(text)" not in moved, "the rule's real call was not removed"
            moved = moved.replace(
                "def fix(text: str) -> str:", "def fix(text: str) -> str:\n    text = drop_base_types(text)")
            first = Path(td) / "plantB-first.py"
            first.write_text(moved)
            try:
                firstout = load(first).fix(raw.decode())
                still = bool(re.search(r"(?m)^type F32 is Data", firstout))
                why = "minted"
            except AssertionError as e:
                still, why = False, f"assertion: {e}"
            # the plant must SURVIVE a rule that runs first: that is the hole
            print(f"PLANT-B[first] {'PASS' if still else 'FAIL'}   the same plant with the "
                  f"rule moved BEFORE the mint -> F32 survives: {still} ({why}); "
                  f"a rule that runs first is a hole, not a fix")
    return 0


if __name__ == "__main__":
    sys.exit(main())