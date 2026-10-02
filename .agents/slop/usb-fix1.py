import io

# The ROW SECTION bodies end in `]))`: `]` closes the row list, `)` closes
# `lines_of`, `)` closes `IO.print`. The extra `)` that kept failing is the third
# close of a `do IO<Unit>:` block, and these sections have no block.
p = ".agents/slop/usb-build.py"
s = io.open(p).read()
bad = 'u1("usb_synth_v_absent", enum_val("SYNTH_NOPE", E_SYNTH()))]))'
good = 'u1("usb_synth_v_absent", enum_val("SYNTH_NOPE", E_SYNTH()))]))'.replace("])))", "]))")
assert bad in s
s = s.replace(bad, good)
io.open(p, "w").write(s)
print(repr(good[-8:]))