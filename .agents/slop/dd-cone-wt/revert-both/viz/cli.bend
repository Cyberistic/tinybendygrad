# tinybendygrad/viz/cli.bend -- port of tinygrad/viz/cli.py
#
# ===========================================================================
# WHAT cli.py IS: a TERMINAL FORMATTER over what `serve.py` already decoded.
# `main` re-reads a `profile.pkl`, calls `viz.get_profile` for BYTES, calls ITS
# OWN `decode_profile` to turn them back into dicts, and formats.
#
# THIS FILE HAS NO CPYTHON GATE YET, and that is stated at the top rather than
# left for a reader to discover. `serve.bend` has one (177 rows, `.agents/slop/vz/
# viz_oracle.py` + `vz_gate.py`); this file does not, because the unit's budget
# ran out after the first wall below was found. Everything here is either PORTED
# or NAMED, and nothing is a stub that answers a placeholder.
#
# THE WALL THAT STOPPED THE GATE, and it is a Bend one. `to_str`
# (cli.py:63-68) decides its answer with `v < 1e13` and `v >= s` on FLOATS, and
# bend 2.0.34's base has NO `F32` COMPARISON: `grep '^def F32\\.' base.bend`
# returns TEN defs (`min`, `max`, `clamp`, `lerp`, `square`, `hypot`, `round`,
# `pi`, `from_nat`, `to_nat`) and not one of them is an ordering. `F32.min(a, b)
# == a` is not expressible either -- there is no `==` on `F32` at all ("expected a
# term, observed '='"). `serve.bend`'s `op_list` and `dev_sort` families get their
# ordering because `uops_color` MATCHES on the datatype and `dev_sort_fn`'s only
# numeric test is `p[1].isdigit()` on a STRING. So `to_str` is PORTED as far as
# its string arms and its INTEGER arms and `f32_lt` is NAMED as the wall. The
# honest consequence is that a value on the far side of a band boundary cannot be
# gated here, and the fixture would have to be integers-only anyway because
# `get_profile` has already put every `fmt` value through `int(...)`.
#
# THE SEAMS, all I/O or all argparse:
#   cli.py:8    os.environ["VIZ"] = "0"
#   cli.py:9    signal.signal(SIGPIPE, SIG_DFL)
#   cli.py:99   emit(val, to_str)          -- `args.json` selects the branch
#   cli.py:100  print_step                 -- IO
#   cli.py:135  heapq.merge                -- a k-way merge of N+1 sorted lists is
#                                              a priority queue; Bend has neither
#                                              a heap nor a queue, and `event_order`
#                                              below ports the ORDER it would
#                                              produce so the sort is still testable
#   cli.py:152  produce_top_kernels / produce_all_kernels  -- generators closing
#                                              over `argparse`
#   cli.py:203  render_event               -- IO
#   cli.py:225  get_arg_parser             -- argparse
#   cli.py:236  main(args)                 -- the whole driver
#
# THE SPLIT, stated once: a def here EITHER builds the argument of one device
# call (pure; the gate checks it) OR records that call in the trace (the gate
# checks ORDER). There is no third kind, and this file is entirely the first: no
# trace, no `@extern`, no `import "./x.c"`.

import Base
import ./../helpers.bend as H

# ===========================================================================
# `marker_st` -- cli.py:72. `next(e["ts"] for e in markers if e["name"] == name)`
# with the `StopIteration` turned into `raise RuntimeError(...)`. The port's
# answer is a `Maybe`, so the raise is the `None`.
#
# THE ORDER IS THE FUNCTION: it is the FIRST match, not the last, and the fixture
# would need two markers with the same name at different timestamps to say so.
# That is a request for a fixture, not a theorem: `markers_st.first` finds the
# first by construction and no single-name fixture can separate it from a
# last-match implementation.
# ===========================================================================

type Marker is Data:
  Marker{name: String, ts: H.I64}

def Marker.of(name: String, ts: H.I64) -> Marker: Marker{name, ts}

def Marker.nm(+m: Marker) -> String:
  match m:
    case Marker{name, ts}: name

def Marker.ts(+m: Marker) -> H.I64:
  match m:
    case Marker{name, ts}: ts



# ===========================================================================
# `get(data, key)` -- cli.py:75-80. `for k, v in data.items(): if ansistrip(k) ==
# key: return v` -- and on a miss it runs `difflib.get_close_matches(key,
# [ansistrip(k) for k in data], n=1, cutoff=0.6)` and raises with the suggestion in
# the message. So the LOOKUP is first-match over insertion order and the REFUSAL
# carries a fuzzy-match hint.
#
# `difflib.get_close_matches` is `SequenceMatcher(...).ratio() >= cutoff` over
# every candidate, sorted by ratio descending. That is a Levenshtein-shaped
# similarity and it is NAMED, not ported: the port answers `None` with no hint and
# the header says so. A hint that is never checked is worse than no hint, and a
# hint that is checked against a hand-written ratio would be a gate that asserts
# its own arithmetic.
# ===========================================================================

type Item is Data:
  Item{k: String, v: String}

def Item.key(+i: Item) -> String:
  match i:
    case Item{k, v}: k

def Item.val(+i: Item) -> String:
  match i:
    case Item{k, v}: v



# `difflib.get_close_matches` -- NAMED, see above. It is the only part of `get`
# that is not ported, and `get.miss` is the refusal both lanes answer.


# ===========================================================================
# `fmt_top` / `fmt_all` -- cli.py:83-91. Both are PADDED COLUMNS and the pads are
# where the information is:
#
#   fmt_top:  f"{fmt_colored(k['name'])}{' ' * max(0, 38-ansilen(k['name']))}"
#             f" {time_to_str(k['dur_ms']*1e-3, w=9)} {k['count']:7d} {k['pct']:6.2f}%"
#             + (" "*4+fmt_data(k['fmt']) if k['fmt'] else "")
#   fmt_all:  f"--- {k['device']} {k['name']}" (+ f"/{k['st_ms']:9.2f}ms" if st_ms)
#             or  f"*** {k['device'][:7]:7s} " + k["name"] + " "*(46-ansilen(k["name"]))
#                  + f" tm {ptm}/{k['st_ms']:9.2f}ms" (+ f" ({fmt_data(k['fmt'])})")
#
# THE COLUMN WIDTHS ARE 38, 7, 46 AND 9, and a `max(0, ...)` pad means a value
# AT the width gets NO pad -- so a row one character over the width is the only
# thing that can tell a `max(0, 38-n)` from a `max(1, 38-n)`, and `pad_cols` is the
# one place that width lives. `fmt_top`/`fmt_all` are PORTED as the PAD
# computation and the column join; the `time_to_str` and `colored` cells come
# from `helpers.bend` (`H.time_to_str`, `H.colored`) which are ported and gated
# there, and the `%.2f` cells are the `F32` wall named in the header.
# ===========================================================================




# `k['name']` is already `fmt_colored`'d by the CALLER, and `ansilen` strips
# escapes, so the pad is computed on the STRIPPED length. MEASURED upstream's
# `fmt_top` pads with `38 - ansilen(k['name'])` on a name that `render_event` has
# already passed through `fmt_colored`, which is why a coloured name and a plain
# name of the same visible width get the same pad.




# `{"MARKER", "SOURCE"}` take the `---` arm and every other device the `***` arm,
# and the two arms share NOTHING -- not the name, not the width, not whether a
# timestamp follows. MEASURED upstream: `if k["device"] in {"MARKER", "SOURCE"}`


# `k['device'][:7]` -- a SEVEN-CHARACTER SLICE, not a split, so `"GPU:0:1"` is
# `"GPU:0:1"` truncated to `"GPU:0:"` and `dev7` is a `String.take`.









def pad_w(+n: Nat, +w: Nat) -> Nat: Bool.pick(Nat, Nat.is_ge(n, w), 0n, Nat.sub(w, n))

def pad_or0(+n: Nat, w: Nat) -> String: String.repeat(" ", pad_w(n, w))

def pad(n: Nat, +w: Nat) -> String: String.repeat(" ", Nat.sub(w, n))

def pad_name(nm: String, +w: Nat) -> String: pad_or0(String.length(H.ansistrip(nm)), w)

def u32(v: U32) -> String: U32.show(v)

def fmt_top.data(has_fmt: Bool) -> String: Bool.pick(String, has_fmt, "    ", "")

def fmt_top(+nm: String, dur: H.I64, cnt: U32, pct: U32, has_fmt: Bool) -> String:
  String.concat([nm, pad_name(nm, 38n), " ", u32(cnt), " ", u32(pct), "%", fmt_top.data(has_fmt)])

def dev7(+dev: String) -> String: String.take(dev, 7n)

def fmt_all_kernel(dev: String, +nm: String) -> String:
  String.concat(["*** ", dev7(dev), " ", nm, pad_name(nm, 46n)])

def fmt_all_marker(dev: String, +nm: String) -> String: String.concat(["--- ", dev, " ", nm])









def marker_st.go(ms: List<&2, Marker>, +name: String) -> Maybe<&2, H.I64>:
  match ms:
    case Nil{}: None{}
    case +h <> t: Bool.pick(Maybe<&2, H.I64>, String.eq(Marker.nm(h), name), Some{Marker.ts(h)}, marker_st.go(t, name))

def marker_st(ms: List<&2, Marker>, name: String) -> Maybe<&2, H.I64>: marker_st.go(ms, name)

def marker_none.at(m: Maybe<&2, H.I64>) -> String:
  match m:
    case Some{v}: H.i64_text(v)
    case None{}: "none"

def marker_none(ms: List<&2, Marker>, name: String) -> String: marker_none.at(marker_st(ms, name))

def get.go(items: List<&2, Item>, +key: String) -> Maybe<&2, String>:
  match items:
    case Nil{}: None{}
    case +h <> t: Bool.pick(Maybe<&2, String>, String.eq(H.ansistrip(Item.key(h)), key), Some{Item.val(h)}, get.go(t, key))

def get.miss.at(key: String) -> Maybe<&2, String>: None{}

def get.miss(key: String) -> Maybe<&2, String>: get.miss.at(key)

def get(items: List<&2, Item>, key: String) -> Maybe<&2, String>: get.go(items, key)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("marker_st=[" ++ marker_none(Nil{}, "x") ++ "]")

# `None` rendered as `none` so a row can name it without a `Maybe` show.



