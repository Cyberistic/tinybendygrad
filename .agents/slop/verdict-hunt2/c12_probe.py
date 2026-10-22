#!/usr/bin/env python3
"""c12_probe.py -- direct probes of the kernel's PARSER (C1) and its
SUBSUMPTION `Term.fits` (C2), at v2.0.37.

The kernel CLI takes a `.bendtt` file and prints ALL PROOFS CHECK / SOME PROOFS
FAIL.  So these are MEASUREMENTS OF THE KERNEL ITSELF, not of the translator.

C1 -- the `.bendtt` PARSER (`bendtt.lean:594-845`, inside the trust base:
`Parse.gap`, `Parse.at`, `Parse.span` are `partial def`, i.e. NOT proved).
  p_parse_comment   a comment inside a term: does the parser skip it?
  p_parse_eof_hash  a '#' at EOF with no newline
  p_parse_crlf      CR / TAB / NBSP whitespace
  p_parse_uni       a multi-byte character in a name
  p_parse_shadow    a def whose NAME equals a bound VARIABLE's name: the
                    kernel's `Term.parse_name` reads a name in the binder
                    scope as a `Var` and anything else as a `Ref`
                    (`bendtt.lean:695-699`), so a `Ref x0` under a λ that
                    binds `x0` is read as the VARIABLE -- a mis-parse.

C2 -- `Term.fits` (`bendtt.lean:1018-1029`) against `bend.ts`'s
`term_compare "LE"`.  The interesting cases:
  p_fits_empty_lab  a `Lab` at the EMPTY enum: `Enu [C0]` used where
                    `Enu []` is expected.  `fits (Enu ks) (Enu js)` is
                    `ks ⊆ js`, so `[C0] ⊆ []` is FALSE -- the kernel should
                    REJECT.  (the opposite direction, `Enu []` used where
                    `Enu [C0]` is expected, is `[] ⊆ [C0]` = TRUE)
  p_fits_empty_any  the reverse: `Enu []` used where `Enu [C0]` is expected
  p_fits_all_dom    the REVERSED DOMAIN of `fits`'s `All` case: a function
                    from `<C0>` used where a function from `<>` is expected
  p_efq_anycod     `Efq` at `∀x0 : <> -> <C0>`: the `Efq` rule
                    (`bendtt.lean:1207-1213`) constrains only the DOMAIN
  p_tup_empty       a `Tup` at the `Empty` Sigma whose TAG has type `<C0>`
                    -- the shape a proof of `Empty` would have if the tag
                    could be built
  p_ctrl_ok         a control that must be accepted
"""
import os
import subprocess
import sys

KERNEL = os.environ.get("BENDTT")
OUT = os.environ.get("OUT", ".")
if not KERNEL:
    print("set BENDTT to the kernel binary")
    sys.exit(2)

EMPTY_BOOK = """\
Empty.arms : ∀x0 : <> -> *(.Q2) =
  λ{}

Empty : *(.Q2) =
  Σx0 : <> -> (Empty.arms x0)
"""

PROBES = [
    # --- C1: the parser -------------------------------------------------
    ("p_parse_comment", "a comment inside a term", EMPTY_BOOK + """
bad : ∀x0 : Empty -> Empty =   # this is a comment
  λ+x0 => λ{(,): λ{}}
"""),
    ("p_parse_eof_hash", "a '#' at EOF with no newline", EMPTY_BOOK + """
bad : ∀x0 : Empty -> Empty =
  λ+x0 => λ{(,): λ{}}
#"""),
    ("p_parse_crlf", "CR / TAB whitespace", EMPTY_BOOK.replace("\n", "\r\n") + """
bad : ∀x0 : Empty -> Empty =
\tλ+x0 => λ{(,): λ{}}
"""),
    ("p_parse_uni", "a multi-byte character in a name", EMPTY_BOOK + """
bäd : ∀x0 : Empty -> Empty =
  λ+x0 => λ{(,): λ{}}
"""),
    ("p_parse_shadow", "a def whose name equals a bound variable's name",
     EMPTY_BOOK + """
x0 : *(.Q2) =
  *(.Q2)

bad : ∀x0 : Empty -> Empty =
  λ+x0 => λ{(,): λ{}}
"""),
    # --- C2: the subsumption --------------------------------------------
    ("p_fits_empty_lab", "a Lab at the EMPTY enum", EMPTY_BOOK + """
bad : <> = .C0
"""),
    ("p_fits_empty_any", "the empty enum used where <C0> is expected", EMPTY_BOOK + """
bad : <C0> = <>
"""),
    ("p_fits_all_dom", "fits' All case REVERSES the domain", EMPTY_BOOK + """
bad : ∀x0 : <C0> -> <> =
  λ{.C0: <>; λ{}}
"""),
    ("p_fits_all_dom2", "the same, the other way round", EMPTY_BOOK + """
bad : ∀x0 : <> -> <C0> =
  λ{}
"""),
    ("p_efq_anycod", "Efq at a function from the empty enum", EMPTY_BOOK + """
bad : ∀x0 : <> -> <C0> =
  λ{}
"""),
    ("p_tup_empty", "a Tup at the Empty Sigma, tag of type <C0>", EMPTY_BOOK + """
bad : Empty = (.C0, <()>)
"""),
    ("p_tup_empty2", "the same, tag of type <>", EMPTY_BOOK + """
bad : Empty = (<>, <()>)
"""),
    ("p_ctrl_ok", "a control that must be accepted", EMPTY_BOOK + """
bad : ∀x0 : Empty -> Empty =
  λ+x0 => λ{(,): λ{}}
"""),
]


def main():
    for name, why, text in PROBES:
        path = os.path.join(OUT, name + ".bendtt")
        with open(path, "w") as f:
            f.write(text)
        p = subprocess.run([KERNEL, path], capture_output=True, text=True, timeout=120)
        out = (p.stdout + p.stderr).strip().replace("\n", " | ")
        verdict = "ACCEPT" if p.returncode == 0 and out == "ALL PROOFS CHECK" else "REJECT"
        print("%-18s %-6s rc=%d  %s" % (name, verdict, p.returncode, out[:150]))
        print("                   (%s)" % why)


if __name__ == "__main__":
    main()
