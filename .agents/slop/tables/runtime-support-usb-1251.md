<!-- FROM: tinybendygrad/runtime/support/usb.bend:1251 -->
# BLOCK:
# THE STRING TABLE. `usb.py` has twenty-one user-visible strings and every one
#
# FOUR of them cannot be rendered here and are named as the seam: `{address:#x}`
# and `{ltssm:02X}` need hex (Bend 2.0.34 has `U32.show` and no radix), and
# `libusb_strerror` is a C call whose return is the message's tail.
# | WALL(p3) tinygrad/runtime/support/usb.py:16   `libusb_strerror(rc)`. -- BLOCKED. #   `libusb_strerror(rc)` IS A C LIBRARY CALL, and the message also interpolates `fn.__name__` --
#   the NAME OF A PYTHON FUNCTION OBJECT. The port declares its own C; it has no generic `fn(*args)`.
# | wall(p3) tinygrad/runtime/support/usb.py:102  `0x{ltssm:02X}`. -- blocked. #   the format is not the blocker -- the port has `byte_hex`/`hex_of`/`hex_digits` in
#   `helpers.bend`. What is missing is the PCIe LINK-UP CHECK that raises with it.
# | WALL(p3) tinygrad/runtime/support/usb.py:129  `address={address:#x}`. -- BLOCKED. #   `address={address:#x}` -- the same shape as the marker above: a format in a raise site this
#   driver layer does not have.
# | WALL(p3) tinygrad/runtime/support/usb.py:133  `f'Reserved (0b{cpl_status:03b})'`. -- BLOCKED. #   A `dict.get` ON `status_map` PLUS A BINARY FORMAT, again in a raise the port does not have.
# END BLOCK
