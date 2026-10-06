#!/usr/bin/env python3
"""APPLY / REVERT one narrowing plant in the SCRATCH tree, and print the edit.

The plant is always the SAME DIRECTION: make the port type the NARROWER one, and
let the compiler name every site that was relying on the looseness.  That is the
only way to get a blast radius that is not a reading of the source -- a comment
can be wrong and a compile error cannot.

  opshapes.py loop  apply|revert   # delete CallInfo.dtype
  opshapes.py flip  apply|revert   # ATuple: List<&2,U32> -> List<&2,Bool>
  opshapes.py lin   apply|revert   # applied_opts: List<&2,U32> -> List<&2,Bool>

NEVER pointed at the live tree: it refuses unless the tree holds a `.agents/slop/
graphcmp.bend` and `tinybendygrad/uop/ops.bend`, and it writes only under `--tree`.
"""
from __future__ import annotations

import pathlib
import sys

EDITS = {
    # (file, [(find, replace), ...]) -- every `find` must be UNIQUE in its file or
    # this raises, because a silent double-application is how a plant stops being a
    # plant and starts being a decoration.
    "loop": [
        ("uop/ops.bend", [
            ("  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}\n",
             "  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool}\n"),
            ("def CallInfo.of() -> CallInfo:\n  CallInfo{None{}, False{}, False{}, S.void()}\n",
             "def CallInfo.of() -> CallInfo:\n  CallInfo{None{}, False{}, False{}}\n"),
            ("    case CallInfo{name, precompile, precompile_backward, dtype}: name\n",
             "    case CallInfo{name, precompile, precompile_backward}: name\n"),
            ("    case CallInfo{name, precompile, precompile_backward, dtype}: precompile\n",
             "    case CallInfo{name, precompile, precompile_backward}: precompile\n"),
            ("    case CallInfo{name, precompile, precompile_backward, dtype}: precompile_backward\n",
             "    case CallInfo{name, precompile, precompile_backward}: precompile_backward\n"),
            ("def CallInfo.dtype(x: CallInfo) -> S.Dt:\n  match x:\n"
             "    case CallInfo{name, precompile, precompile_backward, dtype}: dtype\n\n", ""),
            ("    case CallInfo{name, precompile, precompile_backward, dtype} CallInfo{n2, p2, b2, d2}:\n"
             "      Bool.and(eq_opt_str(name, n2), Bool.and(eq_bool(precompile, p2),\n"
             "        Bool.and(eq_bool(precompile_backward, b2), eq_dt(dtype, d2))))\n",
             "    case CallInfo{name, precompile, precompile_backward} CallInfo{n2, p2, b2}:\n"
             "      Bool.and(eq_opt_str(name, n2), Bool.and(eq_bool(precompile, p2),\n"
             "        eq_bool(precompile_backward, b2)))\n"),
            ("def sg.ci() -> Arg: ACall{CallInfo{None{}, False{}, False{}, S.void()}}\n",
             "def sg.ci() -> Arg: ACall{CallInfo{None{}, False{}, False{}}}\n"),
            ("    Node{OpsCALL{}, [11], ACall{CallInfo{None{}, True{}, False{}, S.void()}}, TNone{}},\n",
             "    Node{OpsCALL{}, [11], ACall{CallInfo{None{}, True{}, False{}}}, TNone{}},\n"),
        ]),
        # NOT MINE -- the two READERS of the field.  `call_dt` is repointed at the
        # BODY, which is `dtype_from_uop`'s CALL arm at HEAD (`return src[0].dtype`),
        # and `arg_call` is DELETED because HEAD's `spec.py:112` is a pure TYPE test --
        # `lambda x: isinstance(x.arg, CallInfo)` -- with no `x.dtype is x.arg.dtype`
        # half to answer.
        ("uop/fold.bend", [
            ("def call_dt(arg: O.Arg) -> S.Dt:\n  match arg:\n"
             "    case O.ACall{ci}: O.CallInfo.dtype(ci)\n    case _: S.void()\n\n", ""),
            ("def call_ds(arg: O.Arg) -> Maybe<&2, DtShape>:\n"
             "  call_ds.go(call_dt(arg), S.void())\n",
             "def call_ds(+ss: List<&2, Derived>) -> Maybe<&2, DtShape>:\n"
             "  call_ds.go(src_dt(0, ss), S.void())\n"),
            ("    case O.OpsCALL{}: call_ds(arg)\n", "    case O.OpsCALL{}: call_ds(ss)\n"),
            ("    O.ACall{O.CallInfo{None{}, False{}, False{}, S.int32()}}, O.TNone{})\n",
             "    O.ACall{O.CallInfo{None{}, False{}, False{}}}, O.TNone{})\n"),
        ]),
        ("uop/spec.bend", [
            ("def arg_call.go(a: O.Arg) -> Maybe<&2, S.Dt>:\n  match a:\n"
             "    case O.ACall{ci}: Some{O.CallInfo.dtype(ci)}\n    case _: None{}\n",
             "def arg_call.go(a: O.Arg) -> Bool:\n  match a:\n"
             "    case O.ACall{ci}: True{}\n    case _: False{}\n"),
            ("# `isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype` -- spec.py:113. The\n"
             "# `isinstance` half is the arm; the `dtype is` half is the comparison below.\n"
             "def arg_call(a: O.Arg) -> Maybe<&2, S.Dt>:\n  arg_call.go(a)\n",
             "# `isinstance(x.arg, CallInfo)` -- spec.py:112 AT HEAD, a pure TYPE test. The\n"
             "# `x.dtype is x.arg.dtype` half this def answered was added by 6f4bfde23 and is\n"
             "# GONE at HEAD; `git log -S'x.dtype is x.arg.dtype' -- tinygrad/uop/spec.py`\n"
             "# returns that commit and the rebase that removed it, and nothing since.\n"
             "def arg_call(a: O.Arg) -> Bool:\n  arg_call.go(a)\n"),
            ("def sh_23.body.pick(ci: Maybe<&2, S.Dt>, d: Maybe<&2, S.Dt>) -> Bool:\n"
             "  match ci d:\n    case Some{a} Some{b}: O.eq_dt(a, b)\n    case _ _: False{}\n\n"
             "def sh_23.body.go(ci: Maybe<&2, S.Dt>, d: Maybe<&2, S.Dt>) -> Bool:\n"
             "  sh_23.body.pick(ci, d)\n\n"
             "def sh_23.body(+fx: F.Folded, +self: U32) -> Bool:\n"
             "  sh_23.body.go(arg_call(sp_arg(fx, self)), sp_dt(fx, self))\n",
             "def sh_23.body(+fx: F.Folded, +self: U32) -> Bool:\n"
             "  arg_call(sp_arg(fx, self))\n"),
        ]),
        ("uop/render.bend", [
            ("  O.CallInfo{Some{\"f\"}, False{}, False{}, S.int32()}\n",
             "  O.CallInfo{Some{\"f\"}, False{}, False{}}\n"),
            ("  O.CallInfo{None{}, False{}, False{}, S.weakint()}\n",
             "  O.CallInfo{None{}, False{}, False{}}\n"),
        ]),
        ("engine/jit.bend", [
            ("                  O.ACall{O.CallInfo{None{}, False{}, False{}, S.void()}}, O.TNone{})\n",
             "                  O.ACall{O.CallInfo{None{}, False{}, False{}}}, O.TNone{})\n"),
        ]),
        ("engine/realize.bend", [
            ("  O.CallInfo{Some{nm}, False{}, False{}, S.void()}\n",
             "  O.CallInfo{Some{nm}, False{}, False{}}\n"),
        ]),
        # NOT MINE, SETTLED -- the TWO COUPLINGS the brief named, plus the fixture
        # that hard-codes the fourth field in the first place.
        (".agents/slop/graphcmp.bend", [
            ("    case O.CallInfo{cname, precompile, precompile_backward, cdtype}:\n"
             "      String.concat([\"cI(\", nm(cname), \",\", bo(precompile), \",\", bo(precompile_backward), \",\", dt(cdtype), \")\"])\n",
             "    case O.CallInfo{cname, precompile, precompile_backward}:\n"
             "      String.concat([\"cI(\", nm(cname), \",\", bo(precompile), \",\", bo(precompile_backward), \")\"])\n"),
            ("    O.ACall{O.CallInfo{Some{\"hcq_fence\"}, False{}, False{}, S.void()}}, O.TNone{})\n",
             "    O.ACall{O.CallInfo{Some{\"hcq_fence\"}, False{}, False{}}}, O.TNone{})\n"),
        ]),
    ],
    "flip": [
        ("uop/ops.bend", [
            ("  ATuple{ys: List<&2, U32>}\n", "  ATuple{ys: List<&2, Bool>}\n"),
            ("def eq_arg.ATuple(y: Arg, +ys: List<&2, U32>) -> Bool:\n",
             "def eq_arg.ATuple(y: Arg, +ys: List<&2, Bool>) -> Bool:\n"),
        ]),
    ],
    "lin": [
        ("uop/ops.bend", [
            ("  KernelInfo{name: String, applied_opts: List<&2, U32>, "
             "opts_to_apply: Maybe<&2, List<&2, U32>>, beam: U32}\n",
             "  KernelInfo{name: String, applied_opts: List<&2, Bool>, "
             "opts_to_apply: Maybe<&2, List<&2, Bool>>, beam: U32}\n"),
            ("def KernelInfo.applied_opts(x: KernelInfo) -> List<&2, U32>:\n",
             "def KernelInfo.applied_opts(x: KernelInfo) -> List<&2, Bool>:\n"),
            ("def KernelInfo.opts_to_apply(x: KernelInfo) -> Maybe<&2, List<&2, U32>>:\n",
             "def KernelInfo.opts_to_apply(x: KernelInfo) -> Maybe<&2, List<&2, Bool>>:\n"),
            ("def KernelInfo.eq_opts(x: Maybe<&2, List<&2, U32>>, y: Maybe<&2, List<&2, U32>>) -> Bool:\n",
             "def KernelInfo.eq_opts(x: Maybe<&2, List<&2, Bool>>, y: Maybe<&2, List<&2, Bool>>) -> Bool:\n"),
        ]),
    ],
}


LIVE = pathlib.Path(__file__).resolve().parents[3]


def restore(tree: pathlib.Path, spec: list) -> None:
    """The DISARM.  Every plant that DELETES text cannot be reverted by
    substitution -- the anchor the text hung on is the text -- so the disarm copies
    the file back from the live repo and then PROVES it with a byte comparison.  A
    disarm that cannot be checked is a wish, and `diff -r` is the check."""
    import filecmp
    import shutil

    def resolve(root: pathlib.Path, rel: str) -> pathlib.Path:
        """`rel` at the root first (`.agents/slop/graphcmp.bend`), else under
        `tinybendygrad/` (`uop/ops.bend`).  Same order as `edit`, so apply and
        disarm cannot disagree about which file they mean."""
        p = root / rel
        return p if p.exists() else root / "tinybendygrad" / rel

    for rel, _ in spec:
        src, dst = resolve(LIVE, rel), resolve(tree, rel)
        shutil.copyfile(src, dst)
        if not filecmp.cmp(src, dst, shallow=False):
            raise SystemExit(f"DISARM FAILED: {rel} is not byte-identical to {src} after restore")
        print(f"  restored {rel}  ({src.stat().st_size} B, byte-identical to live)")


def edit(tree: pathlib.Path, spec: list, forward: bool) -> None:
    for rel, pairs in spec:
        # `rel` is tried against the SCRATCH ROOT first (so the settled
        # `.agents/slop/graphcmp.bend` is in the list) and then against
        # `tinybendygrad/` (so `uop/ops.bend` is written the way the repo spells it).
        p = tree / rel
        if not p.exists():
            p = tree / "tinybendygrad" / rel
        t = p.read_text()
        for a, b in pairs:
            if forward:
                if t.count(a) != 1:
                    raise SystemExit(f"PLANT ABORTED: {rel}: {t.count(a)} matches for {a!r}, need exactly 1")
                t = t.replace(a, b)
            else:
                # A DELETION pair has `b == ""` and `text.count("") == len(text) + 1`,
                # so the guard for it cannot be on `b`.  MORE IMPORTANTLY it is not
                # REVERTIBLE by substitution: the text the plant removed is gone, so
                # there is no anchor to put it back at.  That is why `revert` restores
                # the whole file from the live repo and proves it with `diff -r`
                # instead -- see `restore`.
                raise SystemExit("revert does not substitute; use `restore`")
        p.write_text(t)
        print(f"  {'applied' if forward else 'reverted'} {rel}")


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[1] not in EDITS or sys.argv[2] not in ("apply", "revert"):
        print(__doc__)
        return 2
    tree = pathlib.Path(sys.argv[3]).resolve()
    if not (tree / ".agents/slop/graphcmp.bend").exists() or not (tree / "tinybendygrad/uop/ops.bend").exists():
        print(f"REFUSING: {tree} is not a scratch tree (needs .agents/slop/graphcmp.bend + tinybendygrad/)")
        return 2
    if sys.argv[2] == "apply":
        edit(tree, EDITS[sys.argv[1]], True)
    else:
        restore(tree, EDITS[sys.argv[1]])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())