import Base

# ===========================================================================
# sz.py in Bend: the tokens and the counted lines of every .py and .js file under a
# tree, and the two tables sz.py prints from them. `spec/sz.md` is what the port
# cost; `.agents/slop/notes/compare/sz.md` is the def-by-def comparison.
#
# It is the only unit in this tree checked against something outside itself: every
# number it prints is one CPython `tokenize` answer away, so `./bin/bend
# tinybendygrad/sz.bend` and `python3 sz.py` are diff-able byte for byte, and they
# are, on all 222 counted files of this tree and on the whole table.
#
# Two measured things about the host, both in `spec/sz.md`:
#
#   - 7 of the 220 defs reach a foreign or @unsafe def, and all 7 are the walk:
#     Sz.read_dir, Sz.is_dir, walk.item, walk.scan, walk, and the two defs of the
#     mode dispatch that call it. The lexer, both tables, gen_diff and the printed
#     form reach no effect at all, which is why the file is split where it is.
#   - the INTERPRETED lane dies on any single file of 28988 bytes or more, with
#     `bend: memory fault (machine stack overflow?)`; 28987 is the largest that
#     passes. It is the byte count and nothing else: a 63-space `.js` file, which
#     never runs the lexer, has the same cliff, and two `.py` files totalling
#     29000 bytes are fine in one process, so it is a per-file host limit. The
#     compiled lane reads a 1048576-byte `.js` and a 114688-byte `.py` without
#     complaint, so `sz` is a compiled-lane tool and any fixture at or above 28988
#     bytes can only be run compiled.
#
# WHERE TO LOOK BEFORE TOUCHING THIS FILE, in order:
#
#   - ~/Documents/tinyquery/sz.odin -- the reference implementation. The same
#     program in a systems language: its os.walker owns termination AND symlink
#     policy, the two things this port reimplements by hand. It is a word-counter,
#     not a tokenizer; that is most of why it is 247 lines and this is 1675.
#   - .agents/slop/notes/bend2-constraints.md -- the measured Bend rules this file
#     depends on (fuel must decrease and be the first parameter; a Data param
#     needs + for a second read; the memory-fault entry; the benchmark lessons
#     on why 'x100-x1000 slower' and 'exactly 32768' were both wrong). Also the
#     peer-language reference solutions for the walls here (Koka Perceus reuse,
#     packed strings, os.walk as library maturity).
#   - .agents/slop/tools/szfuzz.py -- the property harness: random trees diffed
#     against sz.py's own gen_stats. Run it after any lexer or walk change.
#
# Two landmines the next reader must not rediscover:
#
#   - The walk's fuel (16777216n) is a never-hit cap for the termination checker;
#     the real termination is the todo list draining (case Nil{} returns on empty
#     regardless of fuel). There is no closed-form name count, so 2^24 is
#     deliberate. But Sz.is_dir used to use stat(), which FOLLOWS symlinks, while
#     os.walk(followlinks=False) never descends a symlinked directory -- on a
#     symlink cycle this port spins until the fuel runs out and then SILENTLY
#     TRUNCATES. The fix is stat -> lstat in runtime/sz.c; szfuzz generates
#     symlink cases that pin it.
# ===========================================================================

# ===========================================================================
# A row of either table: the path as os.path.relpath gives it, the lines, the
# tokens, and -- in the diff table only -- how many lines and tenths of a ratio it
# gained or lost. An F32 carries those two because they are signed and U32 is not,
# and their magnitudes, line counts and tenths, are ones it holds exactly. A row
# with no name is one a tree does not have.
# ===========================================================================

type Row is Data: Row{name: String, lines: U32, toks: U32, dl: F32, dt: F32}

def Row.name(r: Row) -> String:
  match r:
    case Row{name, _, _, _, _}: name

def Row.lines(r: Row) -> U32:
  match r:
    case Row{_, lines, _, _, _}: lines

def Row.toks(r: Row) -> U32:
  match r:
    case Row{_, _, toks, _, _}: toks

def Row.dl(r: Row) -> F32:
  match r:
    case Row{_, _, _, dl, _}: dl

def Row.dt(r: Row) -> F32:
  match r:
    case Row{_, _, _, _, dt}: dt

def Row.none() -> Row:
  Row{"", 0, 0, (0.0 : F32), (0.0 : F32)}

def Row.found(r: Row) -> Bool:
  # 1 when a tree has the file, which a row with no name is the one it does not
  Bool.not(String.eq(Row.name(r), ""))

type Dir is Data: Dir{full: String, rel: String}

# It: one name of the walk, already decided, carrying the two paths os.path.join
# and os.path.relpath give it. A file sz.py counts is an F, a subdirectory is a D,
# and both carry the pair, so the walk never carries a row: a file's row is built
# by sz.rows out of the F, which is why the row-building is downstream of nothing.
type It is Data:
  F{full: String, rel: String}
  D{full: String, rel: String}

def Dir.full(d: Dir) -> String:
  match d:
    case Dir{full, rel}: full

def Dir.rel(d: Dir) -> String:
  match d:
    case Dir{full, rel}: rel

# ===========================================================================
# The two questions os.walk asks, as effects: the names in a directory, and
# whether a name is a directory. A directory that cannot be read is no names and a
# name that cannot be stat'd is no, which is what os.walk answers. Reading a file
# is Base's File.open/read/close, which is why the walk and the lexer are not
# foreign: these two are the whole of it. bend 2.0.34's base.bend can ask neither,
# so each is @unsafe -- a promise the checker reads and never checks, like a foreign
# def -- and each TODO names the primitive it waits for.
# ===========================================================================

# TODO(p3) base.bend: File.list(path) -> List<String>  -- no opendir/readdir, so the
# names of a directory in the order the host lists them are a foreign call, and
# os.walk keeps that order: runtime/sz.c says why.
@unsafe
def Sz.read_dir(path: String) -> IO(List<String>):
  import "./runtime/sz.c"
  import "./runtime/sz.js"

# TODO(p3) base.bend: Path.is_dir(path) -> Bool  -- no stat, so "is this name a
# directory" is a foreign call, and it is the one that decides whether os.walk
# walks into a name or counts it.
@unsafe
def Sz.is_dir(path: String) -> IO(U32):
  import "./runtime/sz.c"
  import "./runtime/sz.js"

# ===========================================================================
# is_docstring
#
#   t.type == token.STRING and t.string.startswith('"""') and
#   t.line.strip().startswith('"""')
#
# In byte terms: a triple-double-quoted string with no prefix whose line has nothing
# but whitespace in front of it. "Nothing but whitespace" is exactly "no counted
# token has reached this line", which is what `last` already says, so the lexer
# samples it when the string opens and the test is two comparisons. A `'''` string is
# not a docstring, and neither is a prefixed one.
# ===========================================================================

def is_docstring(quote3: U32, bl: U32) -> U32:
  # 1 when the string is a docstring: a triple-double-quoted one whose line has
  # nothing but whitespace in front of it
  match quote3 bl:
    case 1 1: 1
    case _ _: 0

def skip(+d: String) -> Bool:
  # the two directories sz.py never counts
  Bool.or(String.contains(d, "tinygrad/runtime/autogen"),
    String.contains(d, "tinygrad/viz/assets"))

def counted(+name: String) -> Bool:
  # a name gen_stats counts: sz.py's two `continue`s together, a .py or .js name on
  # a path it never skips
  Bool.and(Bool.or(String.ends_with(name, ".py"), String.ends_with(name, ".js")),
    Bool.not(skip(name)))

def is_js(name: String) -> Bool:
  String.ends_with(name, ".js")

def is_js_token(s: String) -> Bool:
  # len(s) and not s.startswith('//')
  match s:
    case SNil{}: False{}
    case _: Bool.not(String.starts_with(s, "//"))

# ===========================================================================
# The character tests, as numbers.
#
# Bend's checker will not let a match scrutinise a computed value, so every test a
# match reads arrives as a parameter: eq(x, y) is 0 or 1, cls3 is 1 for whitespace,
# 2 for a digit and 3 for an identifier start, brm is 1 for '{' and 2 for '}', isdig
# is 1 when the char is a digit of the radix, and pfx2b is 0 for no prefix, 1 for
# br/rb and 2 for fr/rf. The rest are literal matches on a code.
# ===========================================================================

def eq(x: U32, y: U32) -> U32:
  Bool.pick(U32, U32.is_eq(x, y), 1, 0)

def is_zero(x: U32) -> U32:
  Bool.pick(U32, U32.is_zero(x), 1, 0)

def is_upper(+c: U32) -> U32:
  Bool.to_u32(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)))

def lc(+c: U32) -> U32:
  # ASCII to lower, which is all a string prefix ever needs
  U32.add(c, U32.mul(32, is_upper(c)))

def is_digit(+c: U32) -> Bool:
  Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

def is_alpha(+c: U32) -> Bool:
  # Python identifiers: ASCII letters and '_', plus every non-ASCII code point up to
  # the last one Unicode has, which is one below the sentinel lex() appends. CPython
  # also NFKC-normalises those; see the comparison table.
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)),
                   Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122))),
          Bool.or(U32.is_eq(c, 95),
                  Bool.and(U32.is_ge(c, 128), U32.is_le(c, 1114111))))

def is_hspace(+c: U32) -> Bool:
  # str.split()'s separator, the ASCII part: this is the .js lane's word separator.
  # Python's set is wider -- U+00A0, U+2000..U+200A and the rest -- and no .js file in
  # the tree holds one; see the comparison table.
  Bool.or(U32.is_eq(c, 32), Bool.or(U32.is_eq(c, 9),
    Bool.or(Bool.and(U32.is_ge(c, 11), U32.is_le(c, 13)),
            Bool.and(U32.is_ge(c, 28), U32.is_le(c, 31)))))

def cls3(+c: U32) -> U32:
  Bool.pick(U32, is_hspace(c), 1, Bool.pick(U32, is_digit(c), 2,
    Bool.pick(U32, is_alpha(c), 3, 0)))

def brm(c: U32) -> U32:
  match c:
    case 123: 1
    case 125: 2
    case _: 0

def op2eq(c0: U32) -> U32:
  # the operators that pair with '=': the '=' arm of the longest match
  match c0:
    case 33: 1
    case 37: 1
    case 38: 1
    case 42: 1
    case 43: 1
    case 45: 1
    case 47: 1
    case 58: 1
    case 60: 1
    case 61: 1
    case 62: 1
    case 64: 1
    case 94: 1
    case 124: 1
    case _: 0

def op2same(c0: U32) -> U32:
  # ** // << >> : the operators that double, and with '=' the three-char ones
  match c0:
    case 42: 1
    case 47: 1
    case 60: 1
    case 62: 1
    case _: 0

def isdig.abcdef(+c: U32) -> Bool:
  # a-f, lowercased: the hex digits a decimal digit test misses
  Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102))

def isdig.dec(+c: U32) -> U32:
  Bool.pick(U32, is_digit(c), 1, 0)

def isdig.bin(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 49)), 1, 0)

def isdig.oct(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 55)), 1, 0)

def isdig.hex(+c: U32) -> U32:
  Bool.pick(U32, Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),
                         isdig.abcdef(lc(c))), 1, 0)

def isdig(r: U32, +c: U32) -> U32:
  # whether c is a digit of radix r, 0 being decimal. It is what decides whether an
  # underscore sits inside the number: 0x1_f is one number, 1_abc is a number and a
  # name.
  match r:
    case 2: isdig.bin(c)
    case 8: isdig.oct(c)
    case 16: isdig.hex(c)
    case _: isdig.dec(c)

def pfx1(a: U32) -> U32:
  # the one-letter string prefixes, lowercased: 0 none, 1 a plain one, 2 f
  match a:
    case 98: 1
    case 114: 1
    case 117: 1
    case 102: 2
    case _: 0

def pfx2b(a: U32, b: U32) -> U32:
  # the two-letter prefixes, both arguments already lowercased
  match a b:
    case 98 114: 1
    case 114 98: 1
    case 102 114: 2
    case 114 102: 2
    case _ _: 0

# ===========================================================================
# The lexer
#
# One char per step, one def, one state. Bend has no lookahead and no rewind, so a
# token one char cannot decide is left OPEN in the state and the next char decides
# it; that is what Pnd is. The alternative, a three-char window, needs the window
# shifted on every step, and a list can only be passed on as a bare tail.
#
# Acc holds the two counts gen_stats wants plus where the scan is. `last` is the
# highest line a counted token has reached, so a token spanning lines adds only the
# lines past it -- sz.py's len(set(x for t in tokens for x in range(t.start[0],
# t.end[0] + 1))). `bad` is 0, or the number of the error the tokenizer raises.
# ===========================================================================

type Acc is Data:
  Acc{tok: U32, lines: U32, last: U32, line: U32, bad: U32}

# Pnd: the open token. P0 is none. Die{0} is the end of the file, and the rest are
# the errors, carried out to main so the message is printed where an exception would
# be. New{c} and Dot are "c is consumed and its kind is not decided yet", which is
# how a token that has already opened begins; every handler that ends one hands the
# char in hand to p0. Sq is a plain string's
# body, with the line and the whitespace flag it opened on, which is what the
# docstring test and the line span need. Cr is a CR whose LF, if any, is the same
# line ending.
type Pnd is Data:
  P0{}
  Nxt{c: U32}
  Die{code: U32, line: U32}
  New{c: U32}
  Dot{}
  Nm{n: U32, a: U32, b: U32}
  Nb{e: U32, u: U32, z: U32, r: U32}
  Op{c0: U32, n: U32}
  Cmt{}
  Bs{k: U32}
  Cr{}
  Sq{q: U32, k: U32, tri: U32, pf: U32, frm: U32, bl: U32}

# St: Top, or Code inside an f-string field, where a '}' and a ':' mean something
# different, or Lit in an f-string's text or format spec, carrying the state to go
# back to when the quote ends.
type St is Data:
  Top{}
  Code{depth: U32, back: St}
  Lit{q: U32, back: St, close: U32, tri: U32, k: U32}

type Xs is Data: Xs{p: Pnd, st: St, a: Acc}

# --- the counts ----------------------------------------------------------

def nl(a: Acc) -> Acc:
  match a:
    case Acc{tok, lines, last, +line, bad}:
      Acc{tok, lines, last, U32.add(line, 1), bad}

def add_lines.go(+tok: U32, lines: U32, +last: U32, +line: U32, frm: U32, bad: U32,
  more: U32) -> Acc:
  # One counted token covering lines frm..line. Tokens come in order, so frm is never
  # below `last`, and the lines it adds are the ones past max(frm, last + 1).
  match more:
    case 0: Acc{U32.add(tok, 1), lines, last, line, bad}
    case _:
      n = U32.add(U32.sub(line, U32.max(frm, U32.add(last, 1))), 1)
      Acc{U32.add(tok, 1), U32.add(lines, n), line, line, bad}

def add_lines(a: Acc, frm: U32) -> Acc:
  match a:
    case Acc{tok, lines, +last, +line, bad}:
      add_lines.go(tok, lines, last, line, frm, bad, Bool.to_u32(U32.is_lt(last, line)))

def emit1(a: Acc) -> Acc:
  match a:
    case Acc{tok, lines, +last, +line, bad}:
      add_lines.go(tok, lines, last, line, line, bad, Bool.to_u32(U32.is_lt(last, line)))

def a.die(st: St, this: Acc, code: U32) -> Xs:
  # the error CPython's tokenizer raises here, with the line it detected it on
  match this:
    case Acc{tok, lines, last, +line, bad}: Xs{Die{code, line}, st, this}

def a.bad(this: Acc, code: U32) -> Acc:
  match this:
    case Acc{tok, lines, last, line, bad}: Acc{tok, lines, last, line, code}

# --- the string token ----------------------------------------------------
#
# k: 0 the opening quote is consumed, 1 a second quote (so it may be a triple),
# 2 a single-quoted body, 3 a triple-quoted body, 4 a triple body plus one quote,
# 5 plus two, 6 an escape, 7 a CR whose LF, if any, is the same line ending.

def str.sq(q: U32, pf: U32, st: St, a: Acc) -> Xs:
  match a:
    case Acc{tok, lines, +last, +line, bad}: Xs{Sq{q, 0, 0, pf, line,
      Bool.to_u32(U32.is_ne(line, last))}, st, a}

def str.go(isf: U32, q: U32, pf: U32, st: St, a: Acc) -> Xs:
  # the quote is consumed: an f-string's text is scanned here, a plain string's body
  # is a token of its own
  match isf:
    case 1: Xs{P0{}, Lit{q, st, 0, 0, 0}, a}
    case _: str.sq(q, pf, st, a)

def str.start(q: U32, pf: U32, isf: U32, st: St, a: Acc) -> Xs:
  str.go(isf, q, pf, st, a)

def p0.ws(c: U32, st: St, a: Acc) -> Xs:
  # whitespace, which is never skippable when it is a line ending
  match c:
    case 10: Xs{P0{}, st, nl(a)}
    case 13: Xs{Cr{}, st, a}
    case _: Xs{P0{}, st, a}

def p0.num(c: U32, st: St, a: Acc) -> Xs:
  # a digit opens a number, and a leading zero says a radix letter may follow
  match c:
    case 48: Xs{Nb{0, 0, 1, 0}, st, a}
    case _: Xs{Nb{0, 0, 0, 0}, st, a}

def p0.op(c: U32, st: St, a: Acc) -> Xs:
  # the rest: a newline, an operator, a quote, a comment, a continuation, a lone dot,
  # or the end of the file
  match c:
    case 10: Xs{P0{}, st, nl(a)}
    case 13: Xs{Cr{}, st, a}
    case 35: Xs{Cmt{}, st, a}
    case 46: Xs{Dot{}, st, a}
    case 92: Xs{Bs{0}, st, a}
    case 34: str.start(34, 0, 0, st, a)
    case 39: str.start(39, 0, 0, st, a)
    case 1114112: a.die(st, a, 0)
    case _: Xs{Op{c, 1}, st, a}

def p0(c: U32, k: U32, st: St, a: Acc) -> Xs:
  # nothing open: c opens a token, or it is whitespace, a comment or a continuation
  match k:
    case 1: p0.ws(c, st, a)
    case 2: p0.num(c, st, a)
    case 3: Xs{New{c}, st, a}
    case _: p0.op(c, st, a)

def p0.end(c: U32, st: St, a: Acc) -> Xs:
  # A token has ended on the char in hand, which was only looked at and never taken
  # in, so it is read again as the start of whatever comes next -- an f-string's text
  # and its fields included, which is why the state goes along with it. The char
  # travels in the state because the step that gets here has already read it.
  Xs{Nxt{c}, st, a}

def pnew.dot(+c: U32, kc: U32, +st: St, +a: Acc) -> Xs:
  # '.' is a number only if a digit follows it; otherwise it is a token of its own
  # and the char in hand is read again, save another '.', which makes '...'
  match kc:
    case 2: Xs{Nb{1, 0, 0, 0}, st, a}
    case _: Bool.pick(Xs, U32.is_eq(c, 46), Xs{Op{46, 2}, st, a},
      p0.end(c, st, emit1(a)))

def pnew.pre(pfx: U32, +q: U32, st: St, a: Acc) -> Xs:
  # the one-letter prefix makes a string of the quote, and f makes an f-string
  match pfx:
    case 0: p0.end(q, st, emit1(a))
    case 2: str.go(1, q, 1, st, a)
    case _: str.go(0, q, 1, st, a)

def qc(c: U32) -> U32:
  # 1 for a quote, which is the only thing a one-letter prefix can sit in front of
  match c:
    case 34: 1
    case 39: 1
    case _: 0

def pnew.pfx(q: U32, pfx: U32, +c: U32, st: St, a: Acc) -> Xs:
  match q:
    case 0: p0.end(c, st, emit1(a))
    case _: pnew.pre(pfx, c, st, a)

def pnew(c0: U32, +c: U32, kc: U32, st: St, a: Acc) -> Xs:
  # c0 is an identifier start, already consumed: a name, or a one-letter prefix
  match kc:
    case 2: Xs{Nm{2, c0, c}, st, a}
    case 3: Xs{Nm{2, c0, c}, st, a}
    case _: pnew.pfx(qc(c), pfx1(lc(c0)), c, st, a)

def pnm.str(n: U32, +c: U32, q: U32, p2: U32, st: St, a: Acc) -> Xs:
  # A quote ends the name, and a two-letter prefix in front of one makes a string;
  # anything else ends the name as a name of its own.
  match n q:
    case 2 1:
      match p2:
        case 1: str.start(c, 2, 0, st, a)
        case 2: str.start(c, 2, 1, st, a)
        case _: p0.end(c, st, emit1(a))
    case _ _: p0.end(c, st, emit1(a))

def pnm.pre(+x1: U32, +x2: U32, n: U32, +c: U32, st: St, a: Acc) -> Xs:
  pnm.str(n, c, qc(c), pfx2b(lc(x1), lc(x2)), st, a)

def pnm(n: U32, x1: U32, x2: U32, st: St, a: Acc, c: U32, kc: U32) -> Xs:
  # a name runs while the char in hand is a digit or an identifier char
  match kc:
    case 2: Xs{Nm{U32.add(n, 1), x1, x2}, st, a}
    case 3: Xs{Nm{U32.add(n, 1), x1, x2}, st, a}
    case _: pnm.pre(x1, x2, n, c, st, a)

def sq.count(doc: U32, frm: U32, a: Acc) -> Acc:
  # a docstring is filtered out before the lines are counted, so it adds nothing
  match doc:
    case 1: a
    case _: add_lines(a, frm)

def sq.end(+q: U32, tri: U32, pf: U32, frm: U32, bl: U32, +c: U32, st: St, a: Acc) -> Xs:
  # the closing quote is consumed, so the token ends here and c opens the next one
  doc = is_docstring(U32.and(eq(pf, 0), U32.and(eq(tri, 1), eq(q, 34))), bl)
  Xs{P0{}, st, sq.count(doc, frm, a)}

def sq.qend(k: U32, q: U32, pf: U32, frm: U32, bl: U32, +c: U32, st: St, a: Acc) -> Xs:
  # our quote in a body: a single-quoted string ends here, a triple-quoted one has to
  # see three of them first
  match k:
    case 2: sq.end(q, 0, pf, frm, bl, c, st, a)
    case 3: Xs{Sq{q, 4, 1, pf, frm, bl}, st, a}
    case 4: Xs{Sq{q, 5, 1, pf, frm, bl}, st, a}
    case _: sq.end(q, 1, pf, frm, bl, c, st, a)

def sq.eof(tri: U32, st: St, a: Acc) -> Xs:
  match tri:
    case 0: a.die(st, a, 1)
    case _: a.die(st, a, 2)

def sq.nl(q: U32, pf: U32, frm: U32, bl: U32, tri: U32, st: St, a: Acc) -> Xs:
  # a newline ends a single-quoted string and is one more line in a triple
  match tri:
    case 0: a.die(st, a, 1)
    case _: Xs{Sq{q, 3, 1, pf, frm, bl}, st, nl(a)}

def sq.cr(q: U32, pf: U32, frm: U32, bl: U32, tri: U32, st: St, a: Acc) -> Xs:
  # a CR is the newline Python's universal-newline read would have handed the
  # tokenizer, so it ends a single-quoted string and is a line in a triple-quoted one
  match tri:
    case 0: a.die(st, a, 1)
    case _: Xs{Sq{q, 7, tri, pf, frm, bl}, st, nl(a)}

def sq.esc(q: U32, pf: U32, frm: U32, bl: U32, tri: U32, +c: U32, st: St,
  a: Acc) -> Xs:
  # The escaped char is gone and the string goes on; a CR or an LF under it is the
  # line ending, and a line ending in a string that is not triple-quoted is the
  # error CPython's tokenizer raises.
  match tri:
    case 0:
      match c:
        case 10: a.die(st, a, 1)
        case 13: a.die(st, a, 1)
        case _: Xs{Sq{q, 2, 0, pf, frm, bl}, st, a}
    case _:
      match c:
        case 10: Xs{Sq{q, 3, 1, pf, frm, bl}, st, nl(a)}
        case 13: Xs{Sq{q, 7, 1, pf, frm, bl}, st, nl(a)}
        case _: Xs{Sq{q, 3, 1, pf, frm, bl}, st, a}

def sq.body(q: U32, k: U32, tri: U32, pf: U32, frm: U32, bl: U32, +c: U32, eqq: U32,
  st: St, a: Acc) -> Xs:
  match c:
    case 92: Xs{Sq{q, 6, tri, pf, frm, bl}, st, a}
    case 1114112: sq.eof(tri, st, a)
    case 10: sq.nl(q, pf, frm, bl, tri, st, a)
    case 13: sq.cr(q, pf, frm, bl, tri, st, a)
    case _:
      match eqq:
        case 1: sq.qend(k, q, pf, frm, bl, c, st, a)
        case _: Xs{Sq{q, k, tri, pf, frm, bl}, st, a}

def sq.arm(q: U32, k: U32, tri: U32, pf: U32, frm: U32, bl: U32, +c: U32, eqq: U32,
  st: St, a: Acc) -> Xs:
  match k:
    case 0:
      match eqq:
        case 1: Xs{Sq{q, 1, tri, pf, frm, bl}, st, a}
        case _: sq.body(q, 2, 0, pf, frm, bl, c, eqq, st, a)
    case 1:
      match eqq:
        case 1: Xs{Sq{q, 3, 1, pf, frm, bl}, st, a}
        case _: p0.end(c, st, sq.count(0, frm, a))
    case 2: sq.body(q, 2, 0, pf, frm, bl, c, eqq, st, a)
    case 3: sq.body(q, 3, 1, pf, frm, bl, c, eqq, st, a)
    case 4:
      match eqq:
        case 1: Xs{Sq{q, 5, 1, pf, frm, bl}, st, a}
        case _: sq.body(q, 3, 1, pf, frm, bl, c, eqq, st, a)
    case 5:
      match eqq:
        case 1: sq.end(q, 1, pf, frm, bl, c, st, a)
        case _: sq.body(q, 3, 1, pf, frm, bl, c, eqq, st, a)
    case 6: sq.esc(q, pf, frm, bl, tri, c, st, a)
    case _: Xs{Sq{q, 3, tri, pf, frm, bl}, st, a}

def sq.go(+q: U32, k: U32, tri: U32, pf: U32, frm: U32, bl: U32, +c: U32, st: St,
  a: Acc) -> Xs:
  sq.arm(q, k, tri, pf, frm, bl, c, eq(c, q), st, a)

# --- an f-string's text and format spec ----------------------------------
#
# k: 0 the opening quote is consumed, 1 a second quote, 2 a single-quoted body,
# 3 a triple-quoted body, 4 plus one quote, 5 plus two, 6 an escape, 7 a CR,
# 8 a '{' seen, 9 a '}' seen. close is 1 in a format spec.

def lit.ret(tri: U32) -> U32:
  match tri:
    case 0: 2
    case _: 3

def lit.end(back: St, +c: U32, a: Acc) -> Xs:
  # the f-string's closing quote is a token of its own: nothing, and the next char in
  # hand opens what follows
  Xs{P0{}, back, a}

def lit.field(st2: St, +c: U32, a: Acc) -> Xs:
  # a '{' opens a field: it is a counted token of its own, and the char in hand was
  # never part of it
  p0.end(c, st2, emit1(a))

def lit.nl(close: U32, tri: U32, q: U32, back: St, a: Acc) -> Xs:
  # a bare newline is a line in a triple-quoted f-string, and two different errors in
  # a single-quoted one, in the text and in a spec
  match close tri:
    case 0 0: a.die(Lit{q, back, close, tri, 0}, a, 5)
    case 1 0: a.die(Lit{q, back, close, tri, 0}, a, 7)
    case _ _: Xs{P0{}, Lit{q, back, close, 1, 3}, nl(a)}

def lit.cr(close: U32, tri: U32, q: U32, back: St, a: Acc) -> Xs:
  match tri:
    case 0: a.die(Lit{q, back, close, tri, 0}, a, 5)
    case _: Xs{P0{}, Lit{q, back, close, 1, 7}, nl(a)}

def lit.sw(close: U32, +tri: U32, +q: U32, back: St, +c: U32, a: Acc) -> Xs:
  # the escaped char is gone; a CR or an LF under it is a line, and an LF after a CR
  # is the same line ending
  match c:
    case 10: Xs{P0{}, Lit{q, back, close, tri, lit.ret(tri)}, nl(a)}
    case 13: Xs{P0{}, Lit{q, back, close, tri, 7}, nl(a)}
    case _: Xs{P0{}, Lit{q, back, close, tri, lit.ret(tri)}, a}

def lit.br(q: U32, back: St, +close: U32, +tri: U32, +c: U32, bc: U32, a: Acc) -> Xs:
  # '{' opens a field and '}' closes one, except in the text, where a brace waits to
  # see whether the next char makes it an escape. A field of a format spec reads
  # like the spec itself, because its '}' is the spec's field's and ends that one.
  match close bc:
    case 0 1: Xs{P0{}, Lit{q, back, 0, tri, 8}, a}
    case 0 2: Xs{P0{}, Lit{q, back, 0, tri, 9}, a}
    case 1 1: Xs{P0{}, Lit{q, back, close, tri, 8}, a}
    case _ _: Xs{P0{}, back, emit1(a)}

def lit.esc(close: U32, +tri: U32, q: U32, back: St, +c: U32, bc: U32, a: Acc) -> Xs:
  # a brace straight after a backslash is still a brace: CPython's FSTRING_MIDDLE
  # stops there, so '{' opens a field and '}' closes one
  match bc:
    case 1: lit.field(Code{0, Lit{q, back, close, tri, lit.ret(tri)}}, c, a)
    case 2: lit.br(q, back, close, tri, c, 2, a)
    case _: lit.sw(close, tri, q, back, c, a)

def lit.qend(k: U32, q: U32, back: St, close: U32, tri: U32, +c: U32, a: Acc) -> Xs:
  # our quote in a body: a single-quoted f-string ends here, a triple-quoted one has
  # to see three of them first
  match k:
    case 2: lit.end(back, c, a)
    case 3: Xs{P0{}, Lit{q, back, close, tri, 4}, a}
    case 4: Xs{P0{}, Lit{q, back, close, tri, 5}, a}
    case _: lit.end(back, c, a)

def lit.quoted(k: U32, q: U32, back: St, close: U32, tri: U32, +c: U32, eqq: U32,
  a: Acc) -> Xs:
  match eqq:
    case 1: lit.qend(k, q, back, close, tri, c, a)
    case _: Xs{P0{}, Lit{q, back, close, tri, k}, a}

def lit.body(q: U32, back: St, close: U32, tri: U32, k: U32, +c: U32, eqq: U32,
  a: Acc) -> Xs:
  match c:
    case 92: Xs{P0{}, Lit{q, back, close, tri, 6}, a}
    case 1114112: a.die(Lit{q, back, close, tri, 0}, a, 5)
    case 10: lit.nl(close, tri, q, back, a)
    case 13: lit.cr(close, tri, q, back, a)
    case 123: lit.br(q, back, close, tri, c, 1, a)
    case 125: lit.br(q, back, close, tri, c, 2, a)
    case _: lit.quoted(k, q, back, close, tri, c, eqq, a)

def lit.go(q: U32, back: St, close: U32, +tri: U32, k: U32, +c: U32, eqq: U32,
  bc: U32, a: Acc) -> Xs:
  match k:
    case 0:
      match eqq:
        case 1: Xs{P0{}, Lit{q, back, close, tri, 1}, a}
        case _: lit.body(q, back, close, tri, 2, c, eqq, a)
    case 1:
      match eqq:
        case 1: Xs{P0{}, Lit{q, back, close, 1, 3}, a}
        case _: p0.end(c, back, a)
    case 2: lit.body(q, back, close, tri, 2, c, eqq, a)
    case 3: lit.body(q, back, close, tri, 3, c, eqq, a)
    case 4:
      match eqq:
        case 1: Xs{P0{}, Lit{q, back, close, 1, 5}, a}
        case _: lit.body(q, back, close, tri, 3, c, eqq, a)
    case 5:
      match eqq:
        case 1: lit.end(back, c, a)
        case _: lit.body(q, back, close, tri, 3, c, eqq, a)
    case 6: lit.esc(close, tri, q, back, c, bc, a)
    case 7: Xs{P0{}, Lit{q, back, close, tri, lit.ret(tri)}, a}
    case 8:
      match bc:
        case 1: Xs{P0{}, Lit{q, back, close, tri, lit.ret(tri)}, a}
        case _: lit.field(Code{0, Lit{q, back, close, tri, lit.ret(tri)}}, c, a)
    case _:
      match bc:
        case 2: Xs{P0{}, Lit{q, back, close, tri, lit.ret(tri)}, a}
        case _: a.die(Lit{q, back, close, tri, 0}, a, 6)

# --- the number ----------------------------------------------------------
#
# e: 0 the integer part, 1 after a dot, 2 the exponent's digits, 3 an e with no sign
# yet, 4 an e and a sign, 5 a j, 6 a radix literal's digits, 7 a radix letter whose
# digit has not arrived. u is the radix letter while e is 7 and 1 under an underscore
# otherwise, z says the literal began with a zero, and r is its radix.

def pnb.rest(r: U32, +c: U32, st: St, a: Acc) -> Xs:
  # a radix literal continues with its own digits and underscores
  match c:
    case 95: Xs{Nb{6, 1, 0, r}, st, a}
    case _: p0.end(c, st, emit1(a))

def pnb.radix.go(r: U32, +c: U32, st: St, a: Acc, d: U32) -> Xs:
  match d:
    case 1: Xs{Nb{6, 0, 0, r}, st, a}
    case _: pnb.rest(r, c, st, a)

def pnb.radix(r: U32, letter: U32, st: St, a: Acc, d: U32) -> Xs:
  # the radix letter needs a digit of that radix after it, or the zero is the whole
  # number and the letter starts a name
  match d:
    case 1: Xs{Nb{6, 0, 0, r}, st, a}
    case _: Xs{New{letter}, st, emit1(a)}

def pnb.pfx(z: U32, +c: U32, st: St, a: Acc) -> Xs:
  # a lone zero then x, b or o: the literal is in that radix
  match z c:
    case 1 120: Xs{Nb{7, 120, 0, 16}, st, a}
    case 1 88: Xs{Nb{7, 88, 0, 16}, st, a}
    case 1 98: Xs{Nb{7, 98, 0, 2}, st, a}
    case 1 66: Xs{Nb{7, 66, 0, 2}, st, a}
    case 1 111: Xs{Nb{7, 111, 0, 8}, st, a}
    case 1 79: Xs{Nb{7, 79, 0, 8}, st, a}
    case _ _: p0.end(c, st, emit1(a))

def pnb.exp(st: St, a: Acc, +c: U32, kc: U32) -> Xs:
  # after e or E: an optional sign then a digit, or the number ended before the e
  match c:
    case 43: Xs{Nb{4, 0, 0, 0}, st, a}
    case 45: Xs{Nb{4, 0, 0, 0}, st, a}
    case _:
      match kc:
        case 2: Xs{Nb{2, 0, 0, 0}, st, a}
        case _: Xs{New{101}, st, emit1(a)}

def pnb.dot(e: U32, z0: U32, st: St, a: Acc, +c: U32) -> Xs:
  # one dot, and only before any exponent
  match z0:
    case 1: Xs{Nb{1, 0, 0, 0}, st, a}
    case _: p0.end(c, st, emit1(a))

def pnb.dec(e: U32, z: U32, st: St, a: Acc, +c: U32, kc: U32, z0: U32) -> Xs:
  match c:
    case 95: Xs{Nb{e, 1, z, 0}, st, a}
    case 46: pnb.dot(e, z0, st, a, c)
    case 101: Xs{Nb{3, 0, 0, 0}, st, a}
    case 106: Xs{Nb{5, 0, 0, 0}, st, a}
    case 74: Xs{Nb{5, 0, 0, 0}, st, a}
    case _:
      match kc:
        case 2: Xs{Nb{e, 0, z, 0}, st, a}
        case _: pnb.pfx(z, c, st, a)

def pnb.und(e: U32, z: U32, r: U32, st: St, a: Acc, d: U32) -> Xs:
  # an underscore stays inside the number only if a digit of its own class follows
  match d:
    case 1: Xs{Nb{e, 0, z, r}, st, a}
    case _: Xs{New{95}, st, emit1(a)}

def pnb.phase(e: U32, z: U32, r: U32, st: St, a: Acc, +c: U32, kc: U32, d: U32,
  z0: U32) -> Xs:
  match e:
    case 5: p0.end(c, st, emit1(a))
    case 3: pnb.exp(st, a, c, kc)
    case 4:
      match kc:
        case 2: Xs{Nb{2, 0, 0, 0}, st, a}
        case _: Xs{New{101}, st, emit1(a)}
    case 6: pnb.radix.go(r, c, st, a, d)
    case 7: pnb.radix(r, z, st, a, d)
    case _: pnb.dec(e, z, st, a, c, kc, z0)

def pnb.go(u: U32, +e: U32, z: U32, r: U32, st: St, a: Acc, +c: U32, kc: U32,
  d: U32) -> Xs:
  match u:
    case 1: pnb.und(e, z, r, st, a, d)
    case _: pnb.phase(e, z, r, st, a, c, kc, d, is_zero(e))

def pnb(u: U32, e: U32, z: U32, +r: U32, st: St, a: Acc, +c: U32, kc: U32) -> Xs:
  pnb.go(u, e, z, r, st, a, c, kc, isdig(r, c))

def op_len.hit(t: U32, m: U32) -> U32:
  match t:
    case 1: m
    case _: 0

def op_len(+c0: U32, n: U32, +c: U32) -> U32:
  # the longest match, one char at a time: 0 means c does not extend the operator
  match n:
    case 1: op_len.hit(U32.or(U32.or(U32.and(eq(c, 61), op2eq(c0)),
                                     U32.and(eq(c, c0), op2same(c0))),
                            U32.or(U32.and(eq(c0, 45), eq(c, 62)),
                                   U32.and(eq(c0, 46), eq(c, 46)))), 2)
    case 2: op_len.hit(U32.or(U32.and(eq(c, 61), op2same(c0)),
                              U32.and(eq(c0, 46), eq(c, 46))), 3)
    case _: 0

def pop.open(depth: U32, back: St, +c: U32, a: Acc) -> Xs:
  # a bracket opens: the char in hand was never part of the operator, so the state
  # reads it again, one level in
  p0.end(c, Code{U32.add(depth, 1), back}, emit1(a))

def pop.shut(depth: U32, back: St, +c: U32, a: Acc) -> Xs:
  p0.end(c, Code{U32.sub(depth, 1), back}, emit1(a))

def pop.rbrace(depth: U32, zero: U32, back: St, +c: U32, a: Acc) -> Xs:
  # a '}' at a field's top level is the field's end, and its text is read again
  match zero:
    case 1: p0.end(c, back, emit1(a))
    case _: p0.end(c, Code{U32.sub(depth, 1), back}, emit1(a))

def pop.colon(depth: U32, zero: U32, back: St, +c: U32, a: Acc) -> Xs:
  # a ':' at a field's top level opens a format spec, whatever follows it
  match zero:
    case 1:
      match back:
        case Lit{+bq, lb, c2, +btri, bk}:
          p0.end(c, Lit{bq, back, 1, btri, lit.ret(btri)}, emit1(a))
        case _: p0.end(c, Code{depth, back}, emit1(a))
    case _: p0.end(c, Code{depth, back}, emit1(a))

def pop.field(+c0: U32, +n: U32, depth: U32, zero: U32, back: St, +c: U32,
  a: Acc) -> Xs:
  # bracket depth: a ':' only opens a format spec at a field's top level, and a '}'
  # only closes the field there
  match c0:
    case 40: pop.open(depth, back, c, a)
    case 91: pop.open(depth, back, c, a)
    case 123: pop.open(depth, back, c, a)
    case 41: pop.shut(depth, back, c, a)
    case 93: pop.shut(depth, back, c, a)
    case 125: pop.rbrace(depth, zero, back, c, a)
    case 58: pop.colon(depth, zero, back, c, a)
    case _: p0.end(c, Code{depth, back}, emit1(a))

def pop.end(+c0: U32, +n: U32, st: St, a: Acc, +c: U32) -> Xs:
  # the operator is closed: count it, then apply the field rules. An f-string state
  # never gets here: route sends those to lit.go.
  match st:
    case Code{+depth, back}: pop.field(c0, n, depth, is_zero(depth), back, c, a)
    case _: p0.end(c, st, emit1(a))

def pop.go(m: U32, +c0: U32, +n: U32, st: St, a: Acc, +c: U32) -> Xs:
  match m:
    case 0: pop.end(c0, n, st, a, c)
    case _: Xs{Op{c0, m}, st, a}

def pop(+c0: U32, +n: U32, st: St, a: Acc, +c: U32) -> Xs:
  pop.go(op_len(c0, n, c), c0, n, st, a, c)

def pcmt(st: St, a: Acc, c: U32) -> Xs:
  match c:
    case 10: Xs{P0{}, st, nl(a)}
    case 13: Xs{Cr{}, st, a}
    case _: Xs{Cmt{}, st, a}

def pbs(k: U32, st: St, a: Acc, c: U32) -> Xs:
  # a line continuation: a newline under the backslash, and nothing else
  match k:
    case 0:
      match c:
        case 10: Xs{P0{}, st, nl(a)}
        case 13: Xs{Bs{1}, st, a}
        case 1114112: a.die(st, a, 4)
        case _: a.die(st, a, 3)
    case _:
      match c:
        case 10: Xs{P0{}, st, nl(a)}
        case 1114112: a.die(st, a, 4)
        case _: a.die(st, a, 3)

# --- the step ------------------------------------------------------------
#
# One state routes: an f-string reads its own text, everything else reads by what is
# open. k is the class of the char in hand, which every handler that cannot decide on
# c alone is given, so no step ever looks past the char it is reading. An error raises
# itself again on every char after it, which is what makes it sticky; in an f-string
# that re-raise comes from the f-string state instead, so the newline-in-a-spec error
# is reported as an unterminated f-string.

def pend(p: Pnd, st: St, a: Acc, +c: U32) -> Xs:
  match p:
    case P0{}: p0(c, cls3(c), st, a)
    case Nxt{c1}: Xs{Nxt{c1}, st, a}
    case Die{code, line}: Xs{Die{code, line}, st, a}
    case New{c0}: pnew(c0, c, cls3(c), st, a)
    case Dot{}: pnew.dot(c, cls3(c), st, a)
    case Nm{n, x1, x2}: pnm(n, x1, x2, st, a, c, cls3(c))
    case Nb{e, u, z, r}: pnb(u, e, z, r, st, a, c, cls3(c))
    case Op{c0, n}: pop(c0, n, st, a, c)
    case Cmt{}: pcmt(st, a, c)
    case Bs{k}: pbs(k, st, a, c)
    case Cr{}: Xs{P0{}, st, nl(a)}
    case Sq{q, k, tri, pf, frm, bl}: sq.go(q, k, tri, pf, frm, bl, c, st, a)

def route(p: Pnd, st: St, a: Acc, +c: U32) -> Xs:
  # An f-string's own text is routed here and by no other def, so the error that
  # raises itself again on every char after it -- which is what makes it sticky --
  # has to be caught before that, or an f-string would swallow one.
  match p st:
    case Die{code, line} _: Xs{Die{code, line}, st, a}
    case _ Lit{+q, back, close, tri, k}:
      lit.go(q, back, close, tri, k, c, eq(c, q), brm(c), a)
    case _ _: pend(p, st, a, c)

def again(x: Xs, +c: U32) -> Xs:
  # what a re-read char left behind, fed the char that came after it
  match x:
    case Xs{p, st, a}: route(p, st, a, c)

def step(x: Xs, +c: U32) -> Xs:
  # A char that ended a token is read twice: once to close the token, and once to
  # open what follows, which is why the state carries it and not the list. pend only
  # ever sees the state again, never the char it ended on.
  match x:
    case Xs{Nxt{c1}, st, a}: again(route(P0{}, st, a, c1), c)
    case Xs{p, st, a}: route(p, st, a, c)

def fin.eof(tri: U32, a: Acc) -> Acc:
  match tri:
    case 0: a.bad(a, 1)
    case _: a.bad(a, 2)

def fin.top(st: St, a: Acc) -> Acc:
  match st:
    case Top{}: a
    case Code{depth, back}: fin.top(back, a)
    case Lit{q, back, close, tri, k}: a.bad(a, 5)

def fin(x: Xs) -> Acc:
  match x:
    case Xs{p, st, a}:
      match p:
        case Die{code, line}: a.bad(a, code)
        case Cr{}: fin.top(st, nl(a))
        case Sq{q, k, tri, pf, frm, bl}: fin.eof(tri, a)
        case _: fin.top(st, a)

def go(bs: List<&2, U32>, x: Xs) -> Acc:
  # One char per step: the list is the first argument and always shrinks. The step is
  # bound before the call: handing the emitter the whole lexer as the argument of the
  # one self-call in this def sends it round its own cycle.
  match bs:
    case Nil{}: fin(x)
    case c <> r:
      nx = step(x, c)
      go(r, nx)

def chars.go(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}: acc
    case SCon{h, t}: chars.go(t, Char.to_u32(h) <> acc)

def chars(s: String) -> List<&2, U32>:
  # The file's chars, in order, then a sentinel one past the last code point, so the
  # token the file ends on always has a char to close it with; no char in a file is.
  List.append(&2, U32, List.reverse(&2, U32, chars.go(s, Nil{})), [1114112])

def lex(s: String) -> Acc:
  go(chars(s), Xs{P0{}, Top{}, Acc{0, 0, 0, 1, 0}})

# ===========================================================================
# The .js lane
#
# str.split() on a stripped line, and a line that counts when it has something on
# it that is not a '//' comment. String.trim is str.strip, so the strip is the
# same set; cls3 is the ASCII half of what str.split() breaks on (see the
# comparison table).
# ===========================================================================

def js.space(+c: U32) -> U32:
  # 1 for a char str.split() breaks a line on, which is the ASCII half of its set
  Bool.to_u32(is_hspace(c))

def js.word(+n: U32, +k: U32) -> U32:
  # one char of a word count, which is the words so far doubled plus whether the
  # last char was a space, packed in one number so the fold stays one def
  U32.add(U32.mul(2, U32.add(U32.div(n, 2), U32.and(U32.mod(n, 2),
    U32.sub(1, k)))), k)

def js.words(s: String, n: U32) -> U32:
  match s:
    case SNil{}: U32.div(n, 2)
    case SCon{h, t}: js.words(t, js.word(n, js.space(Char.to_u32(h))))

def js.trim(s: String) -> String:
  # str.strip, which is the whitespace set of both
  String.trim(s)

def js.line(+t: String) -> (U32 & U32):
  # a line: what it counts, and how many words it has. A comment counts for
  # neither, which is what is_js_token asks of the stripped line
  Bool.pick((U32 & U32), is_js_token(t), (1, js.words(t, 2)), (0, 0))

def js.count.put(a: (U32 & U32), b: (U32 & U32)) -> (U32 & U32):
  (x, y) = a
  (u, v) = b
  (U32.add(x, u), U32.add(y, v))

def js.count.go(ls: List<&2, String>, m: (U32 & U32)) -> (U32 & U32):
  match ls:
    case Nil{}: m
    case s <> r: js.count.go(r, js.count.put(js.line(js.trim(s)), m))

def js.count(s: String) -> (U32 & U32):
  js.count.go(String.lines(s), (0, 0))

def js.row.put(m: (U32 & U32), p: String) -> Row:
  (l, t) = m
  Row{p, l, t, (0.0 : F32), (0.0 : F32)}

def js.row(s: String, p: String) -> Row:
  js.row.put(js.count(s), p)

# ===========================================================================
# One file
# ===========================================================================

def sz.closed(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(f)
    IO.pure(String, s)

def sz.read(full: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(full, "r"))
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 2147483647)
    sz.closed(m)

def sz.checked(bad: U32, r: Row) -> IO(Row):
  # a line the tokenizer cannot read is the one sz.py dies on
  match bad:
    case 0: IO.pure(Row, r)
    case b: IO.die(Row, b, "a line the tokenizer cannot read")

def sz.py(a: Acc, p: String) -> IO(Row):
  match a:
    case Acc{tok, lines, last, line, bad}:
      sz.checked(bad, Row{p, lines, tok, (0.0 : F32), (0.0 : F32)})

def sz.lane(js: Bool, +s: String, +p: String) -> IO(Row):
  # a .js file is split on whitespace, a .py file is tokenized
  Bool.pick(IO(Row), js, IO.pure(Row, js.row(s, p)), sz.py(lex(s), p))

# ===========================================================================
# gen_stats: the walk
#
# os.walk yields a directory's files first and then its subdirectories, each in
# the order the directory itself lists them, and the table keeps that order, so
# the two effects must not sort: sorting would permute the rows of every table
# with two files of the same length. A path is a path to read and a path to print,
# which is base_path joined to what os.path.relpath gives, so the walk starts at
# base_path/tinygrad and never carries base_path again.
#
# The walk is the impure half and sz.rows is the other: `walk` answers with every
# counted file as a path to read and a path to print, in os.walk's order, and
# sz.rows reads and lexes them, so the lexer and both tables are downstream of no
# effect. The walk's one impure step is a name: walk.item stats it and walk lists
# a directory, and the two effects are in those two defs and nowhere else.
# ===========================================================================

def Sz.root(base: String) -> It:
  # the one directory os.walk starts at
  D{base ++ "/tinygrad", "tinygrad"}

def walk.item(p: (List<&2, It> & List<&2, It>), +n: String, +dd: Dir) -> IO((List<&2, It> & List<&2, It>)):
  # One name of one directory, and what os.walk makes of it: a subdirectory on the
  # back of the directories, a file sz.py counts on the back of the files, and a name
  # on one of the two paths sz.py never counts, or one of neither, dropped. The file
  # is an F carrying its two paths and NO row: the row is built later, by sz.rows.
  #
  # The two lists are separate because os.walk yields the files before the
  # subdirectories, and the grouping has to be built HERE, where the stat is, because
  # the stat is what says which group a name is in. It is not the lexing that makes
  # the pair necessary, and moving the lexing out did not remove it: the only way to
  # one list is to readdir backwards, and a tail cannot be pushed at.
  (a, b) = p
  +a : List<&2, It> = a
  +b : List<&2, It> = b
  +pf : String = Dir.full(dd) ++ "/" ++ n
  +pr : String = Dir.rel(dd) ++ "/" ++ n
  do IO<(List<&2, It> & List<&2, It>)>:
    i : U32 <- Sz.is_dir(pf)
    Bool.pick(IO((List<&2, It> & List<&2, It>)), U32.is_zero(i),
      Bool.pick(IO((List<&2, It> & List<&2, It>)), counted(pr),
        IO.pure((List<&2, It> & List<&2, It>), (List.append(&2, It, a, [F{pf, pr}]), b)),
        IO.pure((List<&2, It> & List<&2, It>), (a, b))),
      IO.pure((List<&2, It> & List<&2, It>), (a, List.append(&2, It, b, [D{pf, pr}]))))

def walk.join(p: (List<&2, It> & List<&2, It>), rest: List<&2, It>) -> List<&2, It>:
  # os.walk yields a directory's files and then its subdirectories, so the files go
  # in front of the subdirectories and both in front of what was left of the walk
  (a, b) = p
  List.append(&2, It, a, List.append(&2, It, b, rest))

def walk.scan(names: List<String>, +dd: Dir, p: (List<&2, It> & List<&2, It>),
  rest: List<&2, It>) -> IO(List<&2, It>):
  # One directory's names, in the order it lists them. The recursion over a
  # directory's names is a def of its own and not walk, because one arm of a def may
  # not make two self-calls, so it cannot also be the recursion over the directories.
  match names:
    case Nil{}: IO.pure(List<&2, It>, walk.join(p, rest))
    case n <> t:
      do IO<List<&2, It>>:
        q : (List<&2, It> & List<&2, It>) <- walk.item(p, n, dd)
        walk.scan(t, dd, q, rest)

def walk(k: Nat, out: List<&2, Dir>, todo: List<&2, It>) -> IO(List<&2, Dir>):
  # The walk, on a Nat: one step per item of the todo, which is one counted file or
  # one subdirectory -- a name gen_stats never counts is never an item, so it costs
  # no step -- and a list tail cannot carry what a tail call would have to add, so
  # the count of steps left is what decreases. The answer is the files popped, in
  # the order they were popped, which is os.walk's order; a D with no fuel left to
  # walk is not in it, silently, and the fuel is 16777216 steps against this tree's
  # 289, which is a bound os.walk does not have. Measured: a fuel of 100 drops 40 of
  # this tree's rows, so the bound is not decorative.
  match k:
    case 0n: IO.pure(List<&2, Dir>, out)
    case 1n+j:
      match todo:
        case Nil{}: IO.pure(List<&2, Dir>, out)
        case F{full, rel} <> rest:
          do IO<List<&2, Dir>>:
            walk(j, List.append(&2, Dir, out, [Dir{full, rel}]), rest)
        case D{full, rel} <> rest:
          do IO<List<&2, Dir>>:
            +fu : String = full
            +re : String = rel
            names : List<String> <- Sz.read_dir(fu)
            q : List<&2, It> <- walk.scan(names, Dir{fu, re}, (Nil{}, Nil{}), rest)
            walk(j, out, q)

# ===========================================================================
# The row-building, which the walk hands its files to and which touches no effect
# but Base's File: the .js lane is whitespace, the .py lane is the lexer.
# ===========================================================================

def sz.rows(its: List<&2, Dir>, +xs: List<&2, Row>) -> IO(List<&2, Row>):
  # One row per counted file, in the order the walk found them, and nothing at all
  # for a file with no lines, which is the one thing that keeps gen_stats from
  # counting it.
  match its:
    case Nil{}: IO.pure(List<&2, Row>, xs)
    case Dir{full, rel} <> rest:
      do IO<List<&2, Row>>:
        +fu : String = full
        s : String <- sz.read(fu)
        r : Row <- sz.lane(is_js(fu), s, rel)
        +rr : Row = r
        x : List<&2, Row> = Bool.pick(List<&2, Row>, U32.is_gt(Row.lines(rr), 0),
          List.append(&2, Row, xs, [rr]), xs)
        sz.rows(rest, x)

# ===========================================================================
# The ratio, as tenths
#
# Every ratio is printed with one decimal, so it is carried as tenths: ten tokens
# over lines, rounded to a whole number with halves to even, which is what "%.1f"
# does to the quotient. A difference is signed, so it keeps its tenths in an F32,
# which holds a count of lines and a count of tenths exactly.
# ===========================================================================

def tenth.half(c: Cmp, +q: U32) -> U32:
  # a remainder over half the divisor rounds the quotient up, exactly half to even
  match c:
    case GT{}: U32.add(q, 1)
    case LT{}: q
    case _: U32.add(q, U32.and(q, 1))

def tenth.put(+q: U32, n: U32, +den: U32) -> U32:
  tenth.half(U32.cmp(U32.mul(2, U32.sub(n, U32.mul(q, den))), den), q)

def tenth(+num: U32, +den: U32) -> U32:
  tenth.put(U32.div(U32.mul(10, num), den), U32.mul(10, num), den)

def tenths(t: U32, l: U32) -> U32:
  tenth(t, l)

def tenths.show(+d: U32) -> String:
  # tenths as the one decimal "%.1f" prints them as
  U32.show(U32.div(d, 10)) ++ "." ++ U32.show(U32.mod(d, 10))

def ratio(t: U32, l: U32) -> String:
  tenths.show(tenths(t, l))

def ratio.diff(+x: F32) -> String:
  # a signed difference of tenths, the sign the +.1f format always gives
  Bool.pick(String, F32.is_lt(x, (0.0 : F32)),
    "-" ++ tenths.show(F32.to_u32(F32.neg(x))), "+" ++ tenths.show(F32.to_u32(x)))

def diff(+x: F32) -> String:
  # a signed line count, the sign the +d format always gives
  Bool.pick(String, F32.is_lt(x, (0.0 : F32)),
    "-" ++ U32.show(F32.to_u32(F32.neg(x))), "+" ++ U32.show(F32.to_u32(x)))

def display_diff(+x: F32) -> String:
  # sz.py's display_diff: a plus only where the sum grew, and the signed count
  # itself, sign and all, where it did not
  Bool.pick(String, F32.is_gt(x, (0.0 : F32)), "+" ++ U32.show(F32.to_u32(x)),
    Bool.pick(String, F32.is_lt(x, (0.0 : F32)),
      "-" ++ U32.show(F32.to_u32(F32.neg(x))), "0"))

def dten.put(c: Cmp, tn: U32, +ln: U32, to: U32, +lo: U32) -> F32:
  # ten times the difference of two ratios: (tn*lo - to*ln) over ln*lo, signed
  match c:
    case GT{}: U32.to_f32(tenth(U32.sub(U32.mul(tn, lo), U32.mul(to, ln)),
      U32.mul(ln, lo)))
    case LT{}: F32.neg(U32.to_f32(tenth(U32.sub(U32.mul(to, ln), U32.mul(tn, lo)),
      U32.mul(ln, lo))))
    case _: (0.0 : F32)

def dten(+tn: U32, +ln: U32, +to: U32, +lo: U32) -> F32:
  dten.put(U32.cmp(U32.mul(tn, lo), U32.mul(to, ln)), tn, ln, to, lo)

# ===========================================================================
# gen_diff: what changed between two trees
# ===========================================================================

def pick.go(+r: Row, n: String, +acc: List<&2, Row>) -> List<&2, Row>:
  Bool.pick(List<&2, Row>, String.eq(Row.name(r), n),
    List.append(&2, Row, [r], acc), acc)

def pick.rs(rs: List<&2, Row>, +n: String, acc: List<&2, Row>) -> List<&2, Row>:
  match rs:
    case Nil{}: acc
    case r <> t: pick.rs(t, n, pick.go(r, n, acc))

def pick.put(xs: List<&2, Row>) -> Row:
  match xs:
    case Nil{}: Row.none()
    case r <> t: r

def pick(rs: List<&2, Row>, n: String) -> Row:
  # the row of that name, or a row with no name, where the tree has none
  pick.put(pick.rs(rs, n, Nil{}))

def add.go(+r: Row) -> Row:
  # a file the old tree lacks: every line and the whole ratio is new
  Row{Row.name(r), Row.lines(r), Row.toks(r), U32.to_f32(Row.lines(r)),
    U32.to_f32(tenths(Row.toks(r), Row.lines(r)))}

def del.go(+r: Row) -> Row:
  # a file the new tree lacks: every line and the whole ratio is gone
  Row{Row.name(r), 0, 0, F32.neg(U32.to_f32(Row.lines(r))),
    F32.neg(U32.to_f32(tenths(Row.toks(r), Row.lines(r))))}

def diff.go(+o: Row, +r: Row) -> Row:
  # a file both trees have, with what it gained or lost
  Row{Row.name(r), Row.lines(r), Row.toks(r),
    U32.to_f32(U32.sub(Row.lines(r), Row.lines(o))),
    dten(Row.toks(r), Row.lines(r), Row.toks(o), Row.lines(o))}

def changed(+o: Row, +r: Row) -> Bool:
  # where the lines or the ratio moved. The ratio is compared as the exact
  # quotients sz.py subtracts, which no two of them share a float for
  Bool.or(U32.is_ne(Row.lines(o), Row.lines(r)), U32.is_ne(
    U32.mul(Row.toks(o), Row.lines(r)), U32.mul(Row.toks(r), Row.lines(o))))

def added.put(o: Row, r: Row, +acc: List<&2, Row>) -> List<&2, Row>:
  Bool.pick(List<&2, Row>, Bool.not(Row.found(o)),
    List.append(&2, Row, [add.go(r)], acc), acc)

def added.rs(+old: List<&2, Row>, new: List<&2, Row>, acc: List<&2, Row>) -> List<&2, Row>:
  match new:
    case Nil{}: acc
    case r <> t:
      +rr : Row = r
      added.rs(old, t, added.put(pick(old, Row.name(rr)), rr, acc))

def added(old: List<&2, Row>, new: List<&2, Row>) -> List<&2, Row>:
  List.reverse(&2, Row, added.rs(old, new, Nil{}))

def deleted.put(o: Row, r: Row, +acc: List<&2, Row>) -> List<&2, Row>:
  Bool.pick(List<&2, Row>, Bool.not(Row.found(o)),
    List.append(&2, Row, [del.go(r)], acc), acc)

def deleted.rs(+new: List<&2, Row>, old: List<&2, Row>, acc: List<&2, Row>) -> List<&2, Row>:
  match old:
    case Nil{}: acc
    case r <> t:
      +rr : Row = r
      deleted.rs(new, t, deleted.put(pick(new, Row.name(rr)), rr, acc))

def deleted(new: List<&2, Row>, old: List<&2, Row>) -> List<&2, Row>:
  List.reverse(&2, Row, deleted.rs(new, old, Nil{}))

def same.put(+o: Row, +r: Row, +acc: List<&2, Row>) -> List<&2, Row>:
  Bool.pick(List<&2, Row>, Bool.and(Row.found(o), changed(o, r)),
    List.append(&2, Row, [diff.go(o, r)], acc), acc)

def same.rs(+old: List<&2, Row>, new: List<&2, Row>, acc: List<&2, Row>) -> List<&2, Row>:
  match new:
    case Nil{}: acc
    case r <> t:
      +rr : Row = r
      same.rs(old, t, same.put(pick(old, Row.name(rr)), rr, acc))

def same(+old: List<&2, Row>, +new: List<&2, Row>) -> List<&2, Row>:
  List.reverse(&2, Row, same.rs(old, new, Nil{}))

def gen_diff(+old: List<&2, Row>, +new: List<&2, Row>) -> List<&2, Row>:
  # the three sets, added then deleted then unchanged, each in the order sz.py's
  # own set iteration gives them
  List.append(&2, Row, List.append(&2, Row, added(old, new), deleted(new, old)),
    same(old, new))

# ===========================================================================
# tabulate, hand-rolled
#
# The "simple" format with the first row as the header: a column as wide as its
# widest cell, or as its own header plus MIN_PADDING, two spaces between columns,
# a row of dashes under the header, the name flush left and the numbers flush
# right, and no trailing space. Both tables are laid out by the same code, the
# diff one under a flag.
# ===========================================================================

type Wid is Data: Wid{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32}

def wider(+s: String, w: U32) -> U32:
  U32.max(U32.from_nat(String.length(s)), w)

def rpad(+s: String, w: U32) -> String:
  s ++ String.repeat(" ", Nat.sub(U32.to_nat(w), String.length(s)))

def lpad(+s: String, w: U32) -> String:
  String.repeat(" ", Nat.sub(U32.to_nat(w), String.length(s))) ++ s

def dash(w: U32) -> String:
  String.repeat("-", U32.to_nat(w))

def widths(r: Row, w: Wid) -> Wid:
  # the widest cell of each column so far. A stats table measures the diff table's
  # two extra columns too, where they stay under their own header
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      +rr : Row = r
      Wid{wider(Row.name(rr), x0), wider(U32.show(Row.lines(rr)), x1),
        wider(diff(Row.dl(rr)), x2), wider(ratio(Row.toks(rr), Row.lines(rr)), x3),
        wider(ratio.diff(Row.dt(rr)), x4)}

def tab.wide(rs: List<&2, Row>, w: Wid) -> Wid:
  match rs:
    case Nil{}: w
    case r <> t:
      match w:
        case Wid{x0, x1, x2, x3, x4}: tab.wide(t, widths(r, Wid{x0, x1, x2, x3, x4}))

def tab.row3(name: String, +lines: U32, toks: U32, w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      rpad(name, x0) ++ "  " ++ lpad(U32.show(lines), x1) ++ "  " ++
        lpad(ratio(toks, lines), x3)

def tab.row5(name: String, +lines: U32, toks: U32, dl: F32, dt: F32, w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      rpad(name, x0) ++ "  " ++ lpad(U32.show(lines), x1) ++ "  " ++
        lpad(diff(dl), x2) ++ "  " ++ lpad(ratio(toks, lines), x3) ++ "  " ++
        lpad(ratio.diff(dt), x4)

def tab.hd3(w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      rpad("Name", x0) ++ "  " ++ lpad("Lines", x1) ++ "  " ++
        lpad("Tokens/Line", x3)

def tab.hd5(w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      rpad("Name", x0) ++ "  " ++ lpad("Lines", x1) ++ "  " ++ lpad("Diff", x2)
        ++ "  " ++ lpad("Tokens/Line", x3) ++ "  " ++ lpad("Diff", x4)

def tab.sep3(w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      dash(x0) ++ "  " ++ dash(x1) ++ "  " ++ dash(x3)

def tab.sep5(w: Wid) -> String:
  match w:
    case Wid{x0, x1, x2, x3, x4}:
      dash(x0) ++ "  " ++ dash(x1) ++ "  " ++ dash(x2) ++ "  " ++ dash(x3) ++
        "  " ++ dash(x4)

def tab.go3(rs: List<&2, Row>, +w: Wid) -> String:
  match rs:
    case Nil{}: ""
    case r <> Nil{}:
      +rr : Row = r
      tab.row3(Row.name(rr), Row.lines(rr), Row.toks(rr), w)
    case r <> t:
      +rr : Row = r
      tab.row3(Row.name(rr), Row.lines(rr), Row.toks(rr), w) ++ "\n" ++ tab.go3(t, w)

def tab.go5(rs: List<&2, Row>, +w: Wid) -> String:
  match rs:
    case Nil{}: ""
    case r <> Nil{}:
      +rr : Row = r
      tab.row5(Row.name(rr), Row.lines(rr), Row.toks(rr), Row.dl(rr), Row.dt(rr), w)
    case r <> t:
      +rr : Row = r
      tab.row5(Row.name(rr), Row.lines(rr), Row.toks(rr), Row.dl(rr), Row.dt(rr), w)
        ++ "\n" ++ tab.go5(t, w)

def tab.put(rs: List<&2, Row>, d: U32, +w: Wid, srt: List<&2, Row>) -> String:
  match d:
    case 0: tab.hd3(w) ++ "\n" ++ tab.sep3(w) ++ "\n" ++ tab.go3(srt, w)
    case _: tab.hd5(w) ++ "\n" ++ tab.sep5(w) ++ "\n" ++ tab.go5(srt, w)

def tab.le(a: Row, b: Row) -> Bool:
  # the sort tabulate is given: most lines first, a tie in the order it came
  U32.is_ge(Row.lines(a), Row.lines(b))

def tabulate(+rs: List<&2, Row>, d: U32) -> String:
  # the table, its rows sorted as sz.py sorts them before handing them over
  tab.put(rs, d, tab.wide(rs, Wid{6, 7, 6, 13, 6}), List.sort(~Row, ~tab.le, rs))

# ===========================================================================
# The rest of the output: the group summary, the totals, MAX_LINE_COUNT
# ===========================================================================

def group.go(xs: List<&2, String>, +n: U32, +out: String) -> String:
  # sz.py's group key: the first two of a path's components save its last, which is
  # the file itself. They are joined under a leading '/', which group drops.
  match xs:
    case Nil{}: out
    case _ <> Nil{}: out
    case h <> t: Bool.pick(String, U32.is_ge(n, 2), out, group.go(t, U32.add(n, 1), out ++ "/" ++ h))

def group(s: String) -> String:
  # sz.py's group key: the first two components of a file's directory
  String.drop(group.go(String.split(s, '/'), 0, ""), 1n)

def group.after(+a: Row, +b: Row) -> Bool:
  # 1 when a's group sorts after b's. Only that matters: the summary adds up each
  # group, so a group's files need to be one run of the sorted rows, and where in
  # the run they fall does not.
  Cmp.is_gt(String.order(group(Row.name(a)), group(Row.name(b))))

def group.le(a: Row, b: Row) -> Bool:
  # rows in group order, so each group is one run of the sorted rows
  Bool.not(group.after(a, b))

def gline(g: String, s: U32, n: U32) -> String:
  # one group of the summary: its lines and how many files they are in
  rpad(g, 30) ++ " : " ++ lpad(U32.show(s), 6) ++ " in " ++ lpad(U32.show(n), 2)
    ++ " files\n"

type Run is Data: Run{text: String, g: String, s: U32, n: U32}

def summary.put(+r: Row, x: Run, +gg: String) -> Run:
  # the row's group is the run's, so the row goes on it; a run that has not
  # started is the one an empty tree leaves behind, and its line is not written
  Run{text, g, s, n} = x
  +g2 : String = g
  +nn : U32 = n
  +ss : U32 = s
  +tt : String = text
  Bool.pick(Run, U32.is_eq(nn, 0), Run{tt, gg, Row.lines(r), 1},
    Bool.pick(Run, String.eq(g2, gg), Run{tt, gg, U32.add(ss, Row.lines(r)), U32.add(nn, 1)},
      Run{tt ++ gline(g2, ss, nn), gg, Row.lines(r), 1}))

def summary.fin(x: Run) -> String:
  Run{text, g, s, n} = x
  text ++ gline(g, s, n)

def summary(rs: List<&2, Row>, x: Run) -> String:
  # the groups in order, each summed over its run of the sorted rows
  match rs:
    case Nil{}: summary.fin(x)
    case r <> t:
      +rr : Row = r
      summary(t, summary.put(rr, x, group(Row.name(rr))))

def core(g: String) -> U32:
  # 0 for the directories sz.py leaves out of the core count
  match g:
    case "tinygrad/llm": 0
    case "tinygrad/nn": 0
    case "tinygrad/renderer": 0
    case "tinygrad/runtime": 0
    case "tinygrad/viz": 0
    case _: 1

def core.of(+r: Row) -> U32:
  # the lines a file adds to the core count, which is none of them when its group is
  # not core
  U32.mul(core(group(Row.name(r))), Row.lines(r))

def core.go(s: U32, r: Row) -> U32:
  U32.add(s, core.of(r))

def core.lines(rs: List<&2, Row>) -> U32:
  List.foldl(~&2, ~Row, ~U32, ~core.go, rs, 0)

def total.go(s: U32, r: Row) -> U32:
  U32.add(s, Row.lines(r))

def total.rs(rs: List<&2, Row>) -> U32:
  List.foldl(~&2, ~Row, ~U32, ~total.go, rs, 0)

def sum.dl(s: F32, r: Row) -> F32:
  F32.add(s, Row.dl(r))

def sum.dl.rs(+rs: List<&2, Row>) -> F32:
  List.foldl(~&2, ~Row, ~F32, ~sum.dl, rs, (0.0 : F32))

def sz.text.stats(+rs: List<&2, Row>) -> String:
  # The ops and flags lines are not here: len(Ops) and len(ContextVar._cache) are
  # tinygrad's own reflection, which no tokenizer can see (see the table). IO.print
  # ends the last line, so no def here ends in a newline.
  tabulate(rs, 0) ++ "\n\n" ++ summary(List.sort(~Row, ~group.le, rs),
    Run{SNil{}, "", 0, 0}) ++ "\n core lines: " ++ U32.show(core.lines(rs)) ++
    "\ntotal lines: " ++ U32.show(total.rs(rs))

def sz.text.diff(+rs: List<&2, Row>) -> String:
  "### Changes\n```\n" ++ tabulate(rs, 1) ++ "\n\n\ntotal lines changes: " ++
    display_diff(sum.dl.rs(rs)) ++ "\n```"

def sz.text(rs: List<&2, Row>, d: U32) -> String:
  match d:
    case 0: sz.text.stats(rs)
    case _: sz.text.diff(rs)

def num.go(s: String, n: U32) -> U32:
  match s:
    case SNil{}: n
    case SCon{h, t}:
      +c : U32 = Char.to_u32(h)
      num.go(t, U32.add(U32.mul(10, n), Bool.pick(U32, U32.is_ge(c, 48),
        U32.sub(c, 48), 0)))

def num(s: String) -> U32:
  # MAX_LINE_COUNT as a count of lines: -1 is no limit, which reads as more lines
  # than any tree has, and any other negative is a limit nothing meets
  match s:
    case SCon{Chr{45}, SCon{Chr{49}, SNil{}}}: 4294967295
    case SCon{Chr{45}, _}: 0
    case _: num.go(s, 0)

def sz.limit(+n: U32, total: U32) -> IO(Unit):
  # the assert sz.py makes once the totals are out
  Bool.pick(IO(Unit), U32.is_le(total, n), IO.pure(Unit, Unit{}),
    IO.die(Unit, 1, "OVER " ++ U32.show(n) ++ " LINES"))

def sz.checked.env(m: Result<&1, &1, U32 & String, String>, total: U32) -> IO(Unit):
  match m:
    case Done{value}: sz.limit(num(value), total)
    case _: IO.pure(Unit, Unit{})

def sz.checked.rs(rs: List<&2, Row>) -> IO(Unit):
  do IO<Unit>:
    m : Result<&1, &1, U32 & String, String> <- IO.get_env("MAX_LINE_COUNT")
    sz.checked.env(m, total.rs(rs))

def sz.after(rs: List<&2, Row>, d: U32) -> IO(Unit):
  match d:
    case 0: sz.checked.rs(rs)
    case _: IO.pure(Unit, Unit{})

def sz.put(+rs: List<&2, Row>, +d: U32) -> IO(Unit):
  do IO<Unit>:
    p : Unit <- IO.print(sz.text(rs, d))
    sz.after(rs, d)

def sz.show(+rs: List<&2, Row>, d: U32) -> IO(Unit):
  # sz.py prints nothing at all for a tree with no rows in it
  Bool.pick(IO(Unit), List.is_empty(&2, Row, rs), IO.pure(Unit, Unit{}),
    sz.put(rs, d))

def sz.one(its: List<&2, Dir>) -> IO(Unit):
  do IO<Unit>:
    rs : List<&2, Row> <- sz.rows(its, Nil{})
    sz.show(rs, 0)

def sz.two(old: List<&2, Dir>, new: List<&2, Dir>) -> IO(Unit):
  do IO<Unit>:
    a : List<&2, Row> <- sz.rows(old, Nil{})
    b : List<&2, Row> <- sz.rows(new, Nil{})
    sz.show(gen_diff(a, b), 1)

def sz.main(as: List<String>) -> IO(Unit):
  # gen_stats' three modes: the tree under the cwd, under one path, or the
  # difference of two. This is the one def that walks, so the two effects reach
  # nothing else in the file: sz.one and sz.two take a list of files and print a
  # table from it, and a table can be printed from a list of files.
  match as:
    case Nil{}:
      do IO<Unit>:
        x : List<&2, Dir> <- walk(16777216n, Nil{}, [Sz.root(".")])
        sz.one(x)
    case a <> Nil{}:
      do IO<Unit>:
        x : List<&2, Dir> <- walk(16777216n, Nil{}, [Sz.root(a)])
        sz.one(x)
    case a <> b <> _:
      do IO<Unit>:
        x : List<&2, Dir> <- walk(16777216n, Nil{}, [Sz.root(a)])
        y : List<&2, Dir> <- walk(16777216n, Nil{}, [Sz.root(b)])
        sz.two(x, y)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    sz.main(List.tail(&1, String, as))

# ===========================================================================
# The mutation table. One edit at a time, compiled from a scratch copy (the file
# itself is never edited), run on four fixtures, and compared with the unmutated
# binary: `tree` this repo against `sz.py`, `edge` the trees from sz-mktrees.py,
# `diff` those two against each other, and `order` 15 files ALL TIED at 3 lines and
# 3.0 tokens/line, so the stable sort on -lines prints os.walk's order verbatim and
# any permutation of it is visible. A cell is the number of printed lines that moved,
# 9 meaning 9 or more. Reproduce with `.agents/slop/tools/mutate-sz.py`.
#
#   mutation                                  tree  edge  diff  order
#   join: dirs before files                      9     5   same      9
#   join: the rest of the walk is dropped         9     9   same      9
#   item: a directory is a file                   9     9     8   exit 21
#   counted: the skip test is gone                9     9   same      9
#   rows: no line_count > 0 test                  9     8   same   same
#   rows: printed with the full path, not rel     9     9     9      9
#   root: the walk starts at base, not base/...   9     9     4      9
#   fuel: 16777216 steps -> 400                 same  same  same   same
#   fuel: 16777216 steps -> 100                   9     -     -      -
#
# What the table says, which is why it is here and not just a habit:
#
#   - `diff` is `same` on 4 of the 9 and is the WEAKEST of the four fixtures, not
#     the strongest: it is 11 lines, and a permutation of rows whose line counts
#     stay apart sorts back to the same table. `order` exists because of that row.
#   - `rows: no line_count > 0 test` is the one mutation `order` cannot see, because
#     every file in that fixture has lines. A LOCALISED row: only `edge` (which has an
#     empty and a comments-only file) and `tree` (which has files with no counted
#     line) see it.
#   - `counted: the skip test is gone` adds exactly two rows, `runtime/autogen/
#     skipped.py` and `viz/assets/skipped.js`, and moves 9 because the name column
#     widens under them. Two rows out of nine is the reason the two skipped
#     directories are a FIXTURE and not a comment.
#   - `fuel -> 400` is invisible EVERYWHERE, and that is the point of the two fuel
#     rows. The fuel is one step per item of the todo -- a counted file or a
#     directory, not a readdir name -- and this tree's todo is 289 items, so 400 does
#     not bite and 100 does. A single fuel mutation at 400 would have read as "the
#     bound is untested" when the truth is "400 is above every fixture".
# ===========================================================================
