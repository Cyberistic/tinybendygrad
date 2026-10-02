import io

NL = chr(10)
P = "tinybendygrad/runtime/support/usb.bend"
s = io.open(P).read()
a = s.index("def usb_chunk.step(")
b = s.index(NL + NL, a)
NEW = '''# ONE CALL PER DEF, and the composition is the ORDER. Nesting seven
# `Tr.emit`s inside each other is a counting exercise with no compiler help, and a
# miscount is a silent change to which call is recorded first; one def per call
# makes the sequence read top-down and each def independently gateable.
def usb_chunk.alloc(+t: Tr) -> Tr: Tr.emit(K_ALLOC_XFER(), 0, 0, t)

def usb_chunk.submit(+t: Tr) -> Tr: Tr.emit(K_SUBMIT_XFER(), 0, 0, t)

# :350-351 the three `field("...")` stores, and the ORDINALS are what make them
# the right stores: `usb_fld_transfer_status_ix`, `_length_ix` and `_buffer_ix`
# hold those names in that order, and `M38` (status/length transposed) is the
# mutation that moves them.
def usb_chunk.fields(+t: Tr) -> Tr:
  Tr.emit(K_BULK_XFER(), K_XFER_STATUS(), K_XFER_LENGTH(), K_XFER_BUFFER(), t)

# :348 `usb_ctrl(h, 0x40, 0xF2, wire // 512, ((end - wire) // SLOT) | (wire // SLOT << 8), ...)`
def usb_chunk.f2(+half: U32, +wire: U32, +t: Tr) -> Tr:
  Tr.emit(K_CTRL_XFER(), RTYPE_OUT(), REQ_F2(), chunk_wvalue(wire), chunk_windex(half, wire), t)

# :347 `usb_drained(h, n)`, whose 0xE4 read carries the FENCE ADDRESS and a
# length of ONE -- the byte that makes the predicate mod 256.
def usb_chunk.drained(+t: Tr) -> Tr:
  Tr.emit(K_CTRL_XFER(), RTYPE_IN(), REQ_E4(), WIN_FENCE_LO(), 1, t)

# :342 `usb_reap(h, xfer)`, and :326's `libusb_handle_events_timeout` with a ZERO
# timeout: the poll loop itself is the UOp graph and the seam's.
def usb_chunk.reap(+t: Tr) -> Tr: Tr.emit(K_EVENTS(), 0, 0, t)

# :343 `memcpy(stage + end - wire, addr, size)`
def usb_chunk.memcpy(+half: U32, +wire: U32, +t: Tr) -> Tr:
  Tr.emit(K_MEMCPY(), chunk_off(half, wire), 0, 0, t)

# :342..:352 READ TOP-DOWN AND RECORDED BOTTOM-UP, and this composition is that
# order. `status_ok` is the port's answer to :355's pending clear, which is a
# store into `status` and therefore already covered by `usb_chunk.fields`.
def usb_chunk.step(+half: U32, +wire: U32, +status_ok: Bool, +t: Tr) -> Tr:
  usb_chunk.memcpy(half, wire, usb_chunk.reap(usb_chunk.drained(
    usb_chunk.f2(half, wire, usb_chunk.fields(usb_chunk.submit(usb_chunk.alloc(t)))))))'''
s = s[:a] + NEW + s[b:]
io.open(P, "w").write(s)
print("ok")