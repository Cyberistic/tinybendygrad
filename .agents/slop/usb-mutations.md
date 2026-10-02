| # | rows moved | the edit | what it is testing |
| --- | --- | --- | --- |
| M1 | 11 | `usb_wire`: 512 -> 0 in the first add | :253's sentinel block. Eleven fixtures, and every one of them is below SLOT so the block is what rounds them UP to a whole slot. |
| M2 | 15 | `usb_wire`: SLOT -> 512 in the divisor | the SLOT granularity itself, and the three fixtures at SLOT/2SLOT boundaries are the ones that separate it from 512. |
| M3 | 3 | `usb_sentinel`: the 0xFFFFFF mask -> 0xFFFF | :254's 24-bit mask. `usb_sentinel_0` and `usb_sentinel_max24` are the fixtures that see it; the COLLISION rows are the ones that say why 24 and not 16. |
| M4 | 5 | `usb_sentinel`: the 0x51 magic -> 0x50 | the high byte. This is the constant the differ caught me getting wrong (1363148800), so the row set has to see a change here. |
| M5 | 4 | `usb_split`: `full > 1` -> `full >= 1` | :260's `full if full > 1 else 0` -- the no-one-trip-loops rule. The `_full1` and `_full1_p1` fixtures are the boundary and they are the only ones that separate `>` from `>=`. |
| M6 | 0 | `usb_split`: `nranges` counts full as `full != 0` -> `tail != 0` | the two halves SWAPPED. A sum is commutative so this is a weak mutation; only `_nranges` can see it and the value is the same -- a THEOREM, not a coverage gap. |
| M7 | 3 | `usb_window`: copyin and copyout share CHUNK | :257's `CHUNK if host else 2*CHUNK`. The two window rows and the two split fixtures move, which is the whole point of pairing them. |
| M8 | 5 | `pcie_byte_en`: `<< offset` -> `<< 0` | :118's shift AMOUNT. Five of the eight fixtures use offset 0 and do not move, so this measures 3 of 8 -- a partial-zero, reported as such. |
| M9 | 10 | `pcie_read_mask`: `1 << (8*size)` -> `1 << size` | :135's mask. `usb_pcie_mask_1` is a THEOREM here (8*1 - 1 == 1 - 1 is false, so it does move), and `_mask_4` is the row that sees the 1<<32 saturation. |
| M10 | 1 | `pcie_no_completion`: the second fast path's mask -> the first's | :122's TWO fast paths becoming one. Only the fixtures that separate 0x30 from 0x40 can see it. |
| M11 | 5 | `pcie_cfg_fmt`: `int(bus > 0)` -> `1` | :139's bus term. The `_b0` fixtures move and the `_b1`/`_b255` ones do not. |
| M12 | 3 | `pcie_cfg_addr`: `dev << 19` -> `dev << 18` | :140's device shift, which is 19 and not the PCI-standard 11. Only the fixtures with a non-zero device move, so this measures 2 of 10. |
| M13 | 1 | `pcie_cfg_addr_ok`: drop the `bus >> 8` bound | :138's four bounds. The `usb_cfg_rd_b256` fixture is the one that sees it. |
| M14 | 2 | `xdata_nchunks`: the `length == 0` guard -> `1` | :161's loop for an EMPTY read. `usb_xdata_0_nchunks` is the fixture and it is one row from `_xdata_1_nchunks`. |
| M15 | 3 | `scsi_padded`: 512 -> 256 | :172's `round_up(len(buf), 512)`. The `_511`/`_512`/`_513` fixtures are the boundary triple and all three move. |
| M16 | 10 | `scsi_windex`: the `<< 8` -> `<< 7` | :173's slot-count shift. Only the fixtures whose padded length EXCEEDS 0x4000 have a non-zero count, so this measures 3 of 11. |
| M17 | 8 | `copyout_second`: drop the explicit clamp (the U32-wrap bug) | THE REGRESSION. `size - CHUNK` wraps in a U32 and `U32.max(4294967295, 0)` is 4294967295 where Python's `max(-1, 0)` is 0. The differ found this and `usb_co_chunk_m1_second` / `_wire` are the rows that hold it. |
| M18 | 2 | `copyout_wire`: drop the second-half sentinel term | :375's `(second > 0) ? 512 : 0`. Only the fixtures that SPILL into the second half move, which is `_chunk_p1` and `_2chunk`. |
| M19 | 20 | `chunk_end`: `(half + 1) * HALF` -> `half * HALF` | :338. Every `chunk_rows` fixture moves because both halves share the derivation. |
| M20 | 5 | `chunk_sentinel_word`: `end // 4 - 1` -> `end // 4` | :344's dword index. Five fixtures, five moves -- one row per (half, wire). |
| M21 | 5 | `chunk_windex`: `wire // SLOT << 8` -> `wire // SLOT << 4` | :348's slot-count shift. |
| M22 | 4 | `table_size_word`: `+ TABLE_SIZE_OFF` -> `+ 0` | :321's `+ 8`. Both table columns move together, so the ADDRESS column is the negative case. |
| M23 | 5 | `off_of_index_sz`: `el_sz` -> `0` | :182's integer arm's SIZE, which is `el_sz` and not the slice's extent. Only the `_int_sz` rows move and NOT the `_slice_sz` rows, which is the arm separation. |
| M24 | 1 | `off_of_slice_sz`: `(stop - start)` -> `(stop)` | :181's slice extent. `usb_mmio_slice2_9_el4_slice_sz` moves and the `slice0_4` one does not -- the second is the boundary that separates them. |
| M25 | 3 | `drained_step`: `> 1` -> `> 0` | :334's `> 1`. The `_ahead2` fixture is the boundary and the wrap fixtures are the negative case. |
| M26 | 3 | `drained_step`: drop the `& 0xff` | the ONE-BYTE read's reason for existing: without the mask a fence AHEAD of need wraps into the far side. `usb_drain_wrap_*` is the row set and every wrap fixture moves. |
| M27 | 1 | `is_remote_prefix`: `starts_with` -> `contains` | :387's `str(p.tag).startswith((...))`. `usb_remote_xusb_host` is the negative case and it is the ONLY fixture that separates the two. |
| M28 | 1 | `product_ok`: the second prefix -> the first | :52's `or`. `usb_prod_as2462_x_either` is the only fixture that moves. |
| M29 | 5 | `cpl_name`: fall back to `Completer Abort` instead of Reserved | :133's `.get(cpl_status, f'Reserved (0b...)')`. The five statuses with no map entry are the fixtures and the three with one are the negative case. |
| M30 | 1 | `reply_ok`: drop the `status == 0` test | :92's three-tuple compare. `usb_reply_ok_nonzero_status` is the fixture, one row from `usb_reply_ok_exact`. |
| M31 | 73 | `sym_at_head`: answer the NEXT symbol instead of this one | THE OFF-BY-ONE THIS FILE SHIPPED FOR AN HOUR: every order row named the symbol AFTER the one it meant, every COUNT stayed right, and only the whole-string order rows plus the CPython oracle could see it. Same class, one index, same arity, same length. The edit is the whole def body because `sym_at_head` is the head-at-zero ARM lifted into its own def exactly so this edit compiles. |
| M32 | 4 | `usb_enum.device`: the descriptor read AFTER the ref triple | :33-35 read the descriptor BEFORE the comparison. Four order rows move, and the oracle is the AST so the direction is not a matter of taste. |
| M33 | 5 | `usb_open.detach`: emit the detach branch unconditionally | :55-57's `if libusb_kernel_driver_active`. The `_nodetach` order row moves and the `_detach` one does not -- and they are ONE call string apart in the output, so the negative case is right there. |
| M34 | 3 | `usb_open.after`: `Tr.raise` -> `Tr.emit` on the product read | THE CHECKED/RAW SPLIT. If the string read cannot refuse, then `usb_open_refuse_4_product` grows to the full seven-call trace and every later ordinal shifts -- which is exactly what the four `usb_open_refuse_*` rows are for. |
| M35 | 26 | `Tr.sym`: the separator `,` -> `|` | the ORDER rows' own encoding. Every order row is a whole value, so a separator that lost a call would still be a different string -- this is the check that the string is not accidentally insensitive to a dropped element. |
| M36 | 1 | `enum_nm`: LAST-wins -> FIRST-wins | the LAST-wins rule the generated dicts have. `usb_classcode_6_name` is the ONLY row in the file that sees it, because 6 is the only repeated value in twenty-one tables -- a one-row fixture for a real rule. |
| M37 | 1 | `enum_val`: LAST-wins -> FIRST-wins | the same rule the other way. No name repeats in these tables, so this is a BLIND SPOT BY CONSTRUCTION and the report says so. |
| M38 | 6 | `F_TRANSFER`: swap `status` and `length` | THE FIELD-ORDER MUTATION. `ops_cl`'s unit found `Sig`'s field names INVERTED and this is the same class of bug: `usb_chunk` addresses three of these by NAME, so a transposed pair writes the timeout where the status goes. The `usb_fld_*_ix` rows are the ones that see it. |
| M39 | 5 | `F_DEVICE_DESCRIPTOR`: swap `idVendor` and `idProduct` | the two names `list_devices` compares, and the pair the comparison cannot survive being transposed: `usb_list_match_vendor_only` and `_product_only` are its negative cases. |
| M40 | 1 | `F_DEVICE_DESCRIPTOR`: drop `bNumConfigurations` | a DROPPED field. The whole-string row moves and a field COUNT would not -- which is why the field list is diffed as a string. |
| M41 | 18 | `CHUNK`: `HALF - 512` -> `HALF` | :208's reserved sentinel block. This is the constant that sets HALF-DEPENDENT arithmetic everywhere, so it is the widest mutation in the file and the row count says how wide. |
| M42 | 2 | `CDB_SIZE`: 31 -> 37 | `struct.calcsize("<IIIBBB16s")`. 37 is what a reader gets by counting 16s as four more uint32, and `usb_reply_read_len` (13) is the row that says the reply disagrees with it. |
| M43 | 4 | `ep_dir`: `& 128` -> `& 127` | the `LIBUSB_ENDPOINT_IN` bit, which the oracle reads from the header as 128. |
| M44 | 3 | `pcie_cfg_addr`: drop the `fn << 16` term | :140's FUNCTION nibble. Only the fixtures with a non-zero fn move. |
| M45 | 2 | `SENTINEL_MASK`: 0xFFFFFF -> 0xFFFFFFFF | :254's mask width, and the row that says why 24 and not 32: the COLLISION fixture at 2^24 moves and the one at 2^23 does not. |
