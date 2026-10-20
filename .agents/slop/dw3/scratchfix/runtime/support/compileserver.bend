# tinybendygrad/runtime/support/compileserver.bend -- port of tinygrad/runtime/support/compileserver.py
#
# ===========================================================================
# THIRTEEN LINES, AND THE PORT IS MOSTLY THE PROTOCOL.
#
#   if __name__ == "__main__":
#     assert len(sys.argv) >= 3, f"usage: {sys.argv[0]} <compiler> <arch> [<args>]"
#     compiler = fromimport(*sys.argv[1].split(':'))(sys.argv[2], *(ast.literal_eval(arg) for arg in sys.argv[3:]))
#     while (amt := sys.stdin.buffer.read(4)):
#       try:   lib = compiler.compile(sys.stdin.buffer.read(struct.unpack("I", amt)[0]).decode())
#       except Exception as e:
#         lib = b""
#         print(e, file=sys.stderr, flush=True)
#       sys.stdout.buffer.write(struct.pack("I", len(lib)) + lib)
#       sys.stdout.buffer.flush()
#
# Everything here is EXACTLY a length-prefixed frame in both directions, and the
# framing is the port's whole content:
#
#   REQUEST   4-byte LITTLE-ENDIAN length, then that many bytes of source
#   RESPONSE  4-byte LITTLE-ENDIAN length, then that many bytes of library
#
# Three things about it are load bearing and all three are silent when wrong:
#
#   1. THE LENGTH IS LITTLE ENDIAN. `struct.unpack("I", ...)` with no prefix
#      character is native, and native is little on every platform tinygrad
#      runs on; `struct.pack(">I", 1)` is `01000000` and `struct.pack("I", 1)`
#      is `01000000` too... no: the FIRST byte is the LOW byte, so
#      `struct.pack("I", 1).hex()` is `01000000`. MEASURED against CPython and
#      both are rows in the gate, so a swapped endianness moves them.
#   2. AN ERROR IS NOT AN ERROR FRAME. The `except` sets `lib = b""`, so the
#      response is a VALID frame carrying ZERO bytes, and the diagnostic goes to
#      stderr. So the reader cannot distinguish "the compiler failed" from "the
#      compiler returned an empty library" by the protocol -- which is exactly
#      what `device.py:355` relies on when it raises `CompileError` on an empty
#      read. MEASURED end to end: a frame set of four requests where two fail
#      still answers four frames, and the server's exit code is 0.
#   3. THE LOOP IS DRIVEN BY THE PIPE, NOT BY EOF ON THE SOURCE. A zero-length
#      REQUEST frame is `\x00\x00\x00\x00`, which is a real frame: the read of
#      four bytes succeeds, the length is zero, and `compile("")` runs. Only the
#      FOUR-BYTE READ returning empty ends the loop. `cs.read4` and
#      `cs.frame_n` are the two ends of that.
#
# MEASURED, by running the REAL `compileserver.py` as a subprocess against a
# stub compiler module (`.agents/slop/cs_oracle.py`, section `cs`):
#   four requests -> four responses, `lens=18|0|0|19`, exit 0, stderr non-empty
#   a spec with no ':'  -> TypeError, exit 1
#   a spec with two ':' -> TypeError, exit 1
#   a spec ":S"        -> ValueError: Empty module name, exit 1
#   a spec "S:"        -> ModuleNotFoundError, exit 1
#   argc 0, 1 or 2     -> the usage assert, exit 1
#
# ===========================================================================
# THE WALL, and it is the only one, and it is not the framing.
#
# The server is a LONG-LIVED process holding a duplex pipe. `Process.run`
# (base.bend:182, measured in compiler_amd.bend's header) spawns a process,
# feeds it stdin, collects stdout and stderr, and exits -- it cannot hold a pipe
# open across requests, and `base.bend` has no `Pipe`. So the REQUEST/RESPONSE
# pair is ported as two frames and the LOOP that drives them is declared.
# The stateless alternative is a `Process.run` per request, which is what
# `compiler_qcom.bend`'s WALL 2 says, and it costs one process spawn per
# compile -- which is why upstream keeps a server at all.
#   TODO(p3) compileserver.py:7  -- `sys.stdin.buffer.read(4)` as a loop head.
#   TODO(p3) compileserver.py:8  -- `sys.stdin.buffer.read(n)`.
#   TODO(p3) compileserver.py:12 -- `sys.stdout.buffer.write(...)`.
#   TODO(p3) compileserver.py:13 -- `sys.stdout.buffer.flush()`.
#   TODO(p3) device.py:352      -- the Popen that holds the pipe open.
#
# `ast.literal_eval` is the other unported piece: it parses a Python literal
# from a STRING, and bend has no parser (and writing one is Turing
# completeness, which this repository forbids without approval). The extras
# arrive as a `List<&2, String>` and the gate pins the COUNT, which is the part
# a wrong port would change.
#   TODO(p3) compileserver.py:6 -- `ast.literal_eval(arg)`.
import Base

type Tr is Data:
  Tr{items: List<&2, String>}

def Tr.of() -> Tr: Tr{[]}

def Tr.items(tr: Tr) -> List<&2, String>:
  match tr:
    case Tr{items}: items

def Tr.put(nm: String, arg: String, tr: Tr) -> Tr:
  Tr{List.append(&2, String, Tr.items(tr), [String.concat([nm, "(", arg, ")"])] )}

def Tr.n(tr: Tr) -> U32: U32.from_nat(List.length(&2, String, Tr.items(tr)))

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# ===========================================================================
# the four bytes, as a lowercase hex string. bend has no `U32.get`, so the
# index is a two-arm ladder over a FOUR element list, which is a literal.
# the nth byte of a FOUR element list. `n: Nat` decrements as the walk descends,
# so the decrease check is satisfied and the accumulator stays a `U32`.
# THE FRAME. A little-endian 32-bit length, so byte 0 is the LOW byte.
# `cs.pack` builds the four bytes IN ADDRESS ORDER -- which is the whole point:
# if the byte order were a convention rather than a decision, `cs.unpack` would
# answer the same number for both orders and the gate could not see the swap.
# ===========================================================================
# the nth byte of a FOUR element list. When the REMAINING index is zero the
# HEAD is the answer; the first version had the two arms the other way round and
# `cs.unpack_be_1` answered `00000100` for `00000001`, which is how the gate
# caught it and which no count could.
# ONE def, not a `.go`/`.step` pair: a split of one self-recursive walk is
# mutual recursion and is refused, so the `Bool.pick` goes INLINE in the cons
# arm. When the REMAINING index is zero the HEAD is the answer; the first
# version had the two arms the other way round and `cs.unpack_be_1` answered
# `00000100` for `00000001`, which is how the gate caught it and which no count
# could have.
def q.at(+xs: List<&2, U32>, +n: Nat) -> U32:
  match xs:
    case Nil{}: 0
    case +h <> t: Bool.pick(U32, Nat.is_eq(n, 0n), h, q.at(t, Nat.sub(n, 1n)))

def q.head_of(xs: List<&2, U32>) -> U32: q.at(xs, 0n)
def q.second_of(xs: List<&2, U32>) -> U32: q.at(xs, 1n)
def q.third_of(xs: List<&2, U32>) -> U32: q.at(xs, 2n)
def q.fourth_of(xs: List<&2, U32>) -> U32: q.at(xs, 3n)

# lowercase hex, two digits per byte. bend has no hex LITERALS, so the alphabet
# is `Char.from_u32` and the offset for a digit >= 10 is 97 - 48 - 10 = 39.
def hx2.digit(+d: U32) -> Char:
  Char.from_u32(U32.add(U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), 39, 0)), d))

def hx2.pair(+b: U32) -> String: String.from_list([hx2.digit(U32.shrn(b, 4n)), hx2.digit(U32.and(b, 15))])

def hx2.go(bs: List<&2, U32>, +acc: String) -> String:
  match bs:
    case Nil{}: acc
    case +h <> t: hx2.go(t, String.append(acc, hx2.pair(h)))

def hx2.str(+bs: List<&2, U32>) -> String: hx2.go(bs, "")

def U32.get(+i: U32, +bs: List<&2, U32>) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), q.head_of(bs),
    Bool.pick(U32, U32.is_eq(i, 1), q.second_of(bs),
      Bool.pick(U32, U32.is_eq(i, 2), q.third_of(bs), q.fourth_of(bs))))

def cs.pack(+v: U32) -> List<&2, U32>:
  [U32.and(v, 255), U32.and(U32.shrn(v, 8n), 255),
   U32.and(U32.shrn(v, 16n), 255), U32.shrn(v, 24n)]

def cs.unpack(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))

def cs.unpack_be(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  U32.or(U32.or(U32.shln(b0, 24n), U32.shln(b1, 16n)), U32.or(U32.shln(b2, 8n), b3))

def cs.pack_str(+v: U32) -> String: hx2.str(cs.pack(v))

# `cs.unpack_of` exists so `cs.unpack` is reachable from the gate; without it the
# def is DEAD and every mutation of it moves nothing.
def cs.unpack_of(+bs: List<&2, U32>) -> U32:
  cs.unpack(q.head_of(bs), q.second_of(bs), q.third_of(bs), q.fourth_of(bs))

def cs.unpack_str(+bs: List<&2, U32>) -> String: hx2.str(bs)

def cs.unpack_be_str(+bs: List<&2, U32>) -> String: hx2.str(cs.pack(cs.unpack_be(
  U32.get(0, bs), U32.get(1, bs), U32.get(2, bs), U32.get(3, bs))))

# THE RESPONSE, and the ERROR POLICY. `lib = b""` on an exception, then the
# frame is written anyway -- so the frame count is INDEPENDENT of whether any
# request failed. `cs.respond_n` is the row that says so.
# ===========================================================================
def cs.ok(+lib: U32) -> U32: lib

def cs.on_error(+lib: U32) -> U32: 0

def cs.respond_n(+n: U32, +ok: Bool) -> U32: n

def cs.respond_lens(+libs: List<&2, U32>) -> String: hx2.str(libs)

# the total RESPONSE length: four bytes of header plus every payload. `f(acc,h)`
# is `U32.add(acc, h)` in base's own argument order, which is accumulator FIRST.
def add2(acc: U32, h: U32) -> U32: U32.add(acc, h)

def cs.frame_total(+lens: List<&2, U32>) -> U32: List.foldl(&2, U32, U32, add2, lens, 0)

# ===========================================================================
# THE REQUEST LOOP HEAD. `while (amt := sys.stdin.buffer.read(4))` ends on an
# EMPTY read, not on a zero length: a zero length is a frame whose payload is
# the empty string and `compile("")` still runs. `cs.more` is that test and it
# is the difference between one request and a hang.
# ===========================================================================
def cs.more(+available: U32) -> Bool: U32.is_gt(available, 0)

def cs.n_needed() -> U32: 4

# ===========================================================================
# argv. The assert is `len(sys.argv) >= 3` -- script, spec, arch -- and the
# spec is `module:attr`, split on ':'. `cs.spec_n` is the field count and
# `cs.spec_ok` is the two-field test; a spec with NO colon is a one-field
# `fromimport` call, which Python answers with a TypeError, and a spec with
# THREE is a three-argument `fromimport`, also a TypeError. Those two are the
# rows, because "split on ':'" without the arity is not the same function.
# ===========================================================================
def cs.spec_n(+spec: String) -> U32: U32.from_nat(List.length(&2, String, String.split(spec, ':')))

def cs.spec_ok(+spec: String) -> Bool: U32.is_eq(cs.spec_n(spec), 2)

def cs.argv_ok(+argc: U32) -> Bool: U32.is_ge(argc, 3)

def cs.argv_min() -> U32: 3

def cs.usage(+argv0: String) -> String:
  String.concat(["usage: ", argv0, " <compiler> <arch> [<args>]"])

def cs.extra_n(+argc: U32) -> U32: U32.sub(argc, 3)

# ===========================================================================
# THE GATE. Every expectation is a row of `.agents/slop/cs_oracle.py` section
# `cs`, which runs the REAL `compileserver.py` in a subprocess.
# ===========================================================================
def t_frame() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cs.pack_0", cs.pack_str(0))
    b : Unit <- srow("cs.pack_1", cs.pack_str(1))
    c : Unit <- srow("cs.pack_255", cs.pack_str(255))
    d : Unit <- srow("cs.pack_256", cs.pack_str(256))
    e : Unit <- srow("cs.pack_65535", cs.pack_str(65535))
    f : Unit <- srow("cs.pack_2147483647", cs.pack_str(2147483647))
    g : Unit <- srow("cs.pack_4294967295", cs.pack_str(4294967295))
    h : Unit <- srow("cs.pack_305419896", cs.pack_str(305419896))
    i : Unit <- srow("cs.unpack_be_1", cs.unpack_be_str(cs.pack(1)))
    j : Unit <- srow("cs.unpack_be_305419896", cs.unpack_be_str(cs.pack(305419896)))
    # `cs.unpack` HAD NO CALLER, and the mutation that made it big-endian moved
    # ZERO rows -- the "a def nothing calls is invisible to every other check"
    # rule, found by the mutation table and not by reading.
    k : Unit <- srow("cs.unpack_le_1", U32.show(cs.unpack_of(cs.pack(1))))
    l : Unit <- srow("cs.unpack_le_0100", U32.show(cs.unpack_of(cs.pack(256))))
    m : Unit <- srow("cs.unpack_le_0010", U32.show(cs.unpack_of(cs.pack(1048576))))
    n : Unit <- srow("cs.unpack_le_305419896", U32.show(cs.unpack_of(cs.pack(305419896))))
    o : Unit <- srow("cs.unpack_le_max", U32.show(cs.unpack_of(cs.pack(4294967295))))
    IO.print("cs_frame_done=1")

def t_loop() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cs.more_0", U32.show(Bool.to_u32(cs.more(0))))
    b : Unit <- srow("cs.more_1", U32.show(Bool.to_u32(cs.more(1))))
    c : Unit <- srow("cs.more_4", U32.show(Bool.to_u32(cs.more(4))))
    d : Unit <- srow("cs.n_needed", U32.show(cs.n_needed()))
    e : Unit <- srow("cs.on_error_0", U32.show(cs.on_error(0)))
    f : Unit <- srow("cs.on_error_99", U32.show(cs.on_error(99)))
    g : Unit <- srow("cs.ok_99", U32.show(cs.ok(99)))
    h : Unit <- srow("cs.respond_n_4_1", U32.show(cs.respond_n(4, True{})))
    i : Unit <- srow("cs.respond_n_4_0", U32.show(cs.respond_n(4, False{})))
    IO.print("cs_loop_done=1")

def t_argv() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cs.argv_ok_2", U32.show(Bool.to_u32(cs.argv_ok(2))))
    b : Unit <- srow("cs.argv_ok_3", U32.show(Bool.to_u32(cs.argv_ok(3))))
    c : Unit <- srow("cs.argv_ok_4", U32.show(Bool.to_u32(cs.argv_ok(4))))
    d : Unit <- srow("cs.argv_min", U32.show(cs.argv_min()))
    e : Unit <- srow("cs.usage", cs.usage("/P"))
    f : Unit <- srow("cs.spec_n_a_b", U32.show(cs.spec_n("mod:Name")))
    g : Unit <- srow("cs.spec_n_none", U32.show(cs.spec_n("Name")))
    h : Unit <- srow("cs.spec_n_three", U32.show(cs.spec_n("a:b:c")))
    i : Unit <- srow("cs.spec_n_colon", U32.show(cs.spec_n(":Name")))
    j : Unit <- srow("cs.spec_n_trailing", U32.show(cs.spec_n("Name:")))
    k : Unit <- srow("cs.spec_ok_2", U32.show(Bool.to_u32(cs.spec_ok("mod:Name"))))
    l : Unit <- srow("cs.spec_ok_1", U32.show(Bool.to_u32(cs.spec_ok("Name"))))
    m : Unit <- srow("cs.spec_ok_3", U32.show(Bool.to_u32(cs.spec_ok("a:b:c"))))
    n : Unit <- srow("cs.extra_n_3", U32.show(cs.extra_n(3)))
    o : Unit <- srow("cs.extra_n_6", U32.show(cs.extra_n(6)))
    IO.print("cs_argv_done=1")

# the trace: the ORDER of the calls, for one request and for one failure
def Tr.first_of(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def Tr.last_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: ""

def Tr.last_name(tr: Tr) -> String: Tr.last_of(List.last(&2, String, Tr.items(tr)))

def srv(+n: U32) -> Tr:
  s0 = Tr.put("stdin.read", U32.show(cs.n_needed()), Tr.of())
  s1 = Tr.put("stdin.read", U32.show(n), s0)
  s2 = Tr.put("compile", "src.decode()", s1)
  Tr.put("stdout.write", "pack(I,len(lib))+lib", s2)

def srv_err(+n: U32) -> Tr:
  s0 = Tr.put("stdin.read", U32.show(cs.n_needed()), Tr.of())
  s1 = Tr.put("stdin.read", U32.show(n), s0)
  s2 = Tr.put("compile", "raises", s1)
  s3 = Tr.put("stderr.write", "str(e)", s2)
  s4 = Tr.put("stdout.write", "pack(I,0)", s3)
  Tr.put("stdout.flush", "", s4)

def t_trace() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("tr.srv.n", U32.show(Tr.n(srv(3))))
    b : Unit <- srow("tr.srv_err.n", U32.show(Tr.n(srv_err(3))))
    c : Unit <- srow("tr.srv.first", Tr.first_of(Tr.items(srv(3))))
    d : Unit <- srow("tr.srv.last", Tr.last_name(srv(3)))
    e : Unit <- srow("tr.srv_err.first", Tr.first_of(Tr.items(srv_err(3))))
    f : Unit <- srow("tr.srv_err.last", Tr.last_name(srv_err(3)))
    IO.print("cs_trace_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_frame()
    b : Unit <- t_loop()
    c : Unit <- t_argv()
    d : Unit <- t_trace()
    IO.print("compileserver-done=1")