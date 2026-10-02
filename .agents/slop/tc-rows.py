#!/usr/bin/env python3
"""tc-rows.py -- emit the FIXTURE LISTS and the expected-row files for
tinybendygrad/codegen/decomp/transcendental.bend.

The fixture strings are taken from the ORACLE's own row NAMES, so a fixture and
the row that names it agree by construction: nothing here re-spells a number
that CPython printed. `main` in the Bend file loops over these lists, which is
why a fixture is a String and not an F32 literal -- `F32.read` then goes through
the same decimal parse CPython did.
"""
import sys, re

VALUE = '.agents/slop/tc-rows-value.txt'
COEF = '.agents/slop/tc-rows-coef.txt'


def names(pref, path=VALUE, drop=()):
  """the fixture suffixes the oracle used under `pref`, in file order, minus
  the `drop`ped prefixes (a longer row prefix such as `xf_xexp2_sp_` also
  starts with `xf_xexp2_`, and the longer one is its own fixture set)"""
  out = []
  for L in open(path):
    n = L.split('=', 1)[0]
    if not n.startswith(pref): continue
    t = n[len(pref):]
    if any(t.startswith(d) for d in drop): continue
    out.append(t)
  return out


def bendlist(nm, items, q=True):
  if q:
    body = ('String.split("' + '|'.join(items) + "\", '|')") if q else body
  else:
    body = ' <> '.join(items)
  print(f'def {nm}() -> List<&2, {"String" if q else "U32"}>:')
  print('  ' + body)


def main():
  mode = sys.argv[1]
  if mode == 'fixtures':
    groups = [
      ('fx.sinpoly', 'xf_sin_poly_', ()),
      ('fx.shr', 'xf_shr23_', ()),
      ('fx.shl', 'xf_shl23_', ()),
      ('fx.rintk', 'xf_rintk_', ()),
      ('fx.ilogb', 'xf_ilogb2k_', ()),
      # ONE LIST PER ROW-NAME PREFIX.  A list built from `xf_frexp_` carries
      # `m_0.5`/`e_0.5` and `main` then prefixes `xf_frexp_m_` on top, so every
      # row came out as `xf_frexp_m_m_0.5` and the 22 real rows were MISSING.
      # MEASURED: a name-only diff reported them missing while the mangled names
      # sat in EXTRA, which is exactly what a missing row and a right row look
      # like together.
      ('fx.frexp_m', 'xf_frexp_m_', ()),
      ('fx.frexp_e', 'xf_frexp_e_', ()),
      ('fx.cw_r', 'xf_cody_waite_r_', ()),
      ('fx.cw_q', 'xf_cody_waite_q_', ()),
      ('fx.sps', 'xf_sps_', ()),
      ('fx.xsinfast', 'xf_xsin_fast_', ('slow_',)),
      ('fx.xsinslow', 'xf_xsin_slow_small_', ()),
      ('fx.xexp2', 'xf_xexp2_', ('sp_',)),
      ('fx.xexp2sp', 'xf_xexp2_sp_', ()),
      ('fx.xlog2', 'xf_xlog2_', ('sp_',)),
      ('fx.xlog2sp', 'xf_xlog2_sp_', ()),
      ('fx.inf', 'xf_lazy1_', ()),
    ]
    for g in groups:
      bendlist(g[0], names(g[1], drop=g[2]))
    # the guard fixtures, taken once from the xg_ rows
    # the GUARD FIXTURES, taken off ONE guard id.  Stripping suffixes instead
    # flattens guard and fixture together and yields a cross product, which is
    # MEASURED: it produced 14x18 rows named `xg_a_b` instead of 14x18 named
    # `xg_a_<fixture>`.
    bendlist('fx.g', names('xg_xexp2_ge_up_'))
    # the two infinities and the NaN, which the lazy_map_numbers rows need
    bendlist('fx.special', names('xf_lazy0_'))
    # the xpow fixtures the source answers WITHOUT a transcendental: `e == 0`
    # (:265) and `base == 0` (:259 with log2(0) = -Inf).
    keep = []
    for L in open(VALUE):
      n = L.split('=')[0]
      if not n.startswith('xf_xpow_'): continue
      b, e = n[len('xf_xpow_'):].rsplit('_', 1)
      if float(e) == 0.0 or float(b) == 0.0: keep.append(n[len('xf_xpow_'):])
    bendlist('fx.xpowval', keep)
  elif mode == 'pairs':
    # (d, e) fixtures for ldexp2k / ldexp3k, and (d, q) for sps/spl, taken
    # from the oracle's own names so they cannot drift.
    print('# ldexp2k / ldexp3k: "d_e"')
    bendlist('fx.ldexp', sorted({L.split('=')[0][len('xf_ldexp2k_'):]
                                 for L in open(VALUE) if L.startswith('xf_ldexp2k_')}))
    print('# pow2if: plain integers')
    bendlist('fx.pow2if', sorted({L.split('=')[0][len('xf_pow2if_'):]
                                  for L in open(VALUE) if L.startswith('xf_pow2if_')}))
    print('# spl: "d_q", the LARGE sibling of the sps fixtures')
    bendlist('fx.spl', sorted({L.split('=')[0][len('xf_spl_'):]
                              for L in open(VALUE) if L.startswith('xf_spl_')}))
    print('# the four xpow predicate families')
    bendlist('fx.xpowp', sorted({L.split('=')[0][len('xp_xpow_non_int_'):]
                                 for L in open(VALUE)
                                 if L.startswith('xp_xpow_non_int_')}))
    print('# xpow: "base_exponent"')
    print('# (the fixture lists themselves live in `fixtures` mode)')
    bendlist('fx.lazy', sorted({L.split('=')[0][len('xf_lazy0_'):]
                                 for L in open(VALUE) if L.startswith('xf_lazy0_')}))
  elif mode == 'rows':
    # the static (non-looped) rows: scalars, tables, dtypes
    for L in open(COEF):
      print(L.rstrip())


if __name__ == '__main__':
  main()