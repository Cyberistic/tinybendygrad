# boot42 inversion -- MEASURED before/after, by whole `name=value` line.
# before = the port with `Fld.of("minor_extended_revision", 11, 8)`
# after  = the port with `Fld.of("minor_extended_revision", 8, 11)`
# sha256(after) rows = 298e71965962a2d58b629464f7145284dfc6978dccf0f5b4bcebabac709cbf4a
# sha256(before) rows = 9a9d60fe9fc41812dfe3405c19fb50719ef87f18ab106d05d08595425ada46a3

rows compared: 793   rows moved: 22
new rows added: 26   of which moved: 6
new rows correctly NOT moved (the five sound fields): 20

| row | before (11,8) | after (8,11) | new? |
|---|---|---|---|
| `nv_boot42_chipid_over` | `minor_extended_revision=523776,minor_revision=0,major_revision=0,implementation=15,architecture=63,chip_id=1023` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=15,architecture=63,chip_id=1023` |  |
| `nv_boot42_merext_hi` | `8` | `11` | YES |
| `nv_boot42_merext_lo` | `11` | `8` | YES |
| `nv_decode_arch_1a` | `minor_extended_revision=212992,minor_revision=0,major_revision=0,implementation=0,architecture=26,chip_id=416` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=0,architecture=26,chip_id=416` |  |
| `nv_decode_arch_1b` | `minor_extended_revision=221184,minor_revision=0,major_revision=0,implementation=0,architecture=27,chip_id=432` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=0,architecture=27,chip_id=432` |  |
| `nv_decode_arch_3f` | `minor_extended_revision=516096,minor_revision=0,major_revision=0,implementation=0,architecture=63,chip_id=1008` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=0,architecture=63,chip_id=1008` |  |
| `nv_decode_boot42_full` | `minor_extended_revision=524287,minor_revision=15,major_revision=15,implementation=15,architecture=63,chip_id=1023` | `minor_extended_revision=15,minor_revision=15,major_revision=15,implementation=15,architecture=63,chip_id=1023` |  |
| `nv_decode_impl_d` | `minor_extended_revision=6656,minor_revision=0,major_revision=0,implementation=13,architecture=0,chip_id=13` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=13,architecture=0,chip_id=13` |  |
| `nv_encode_boot42_full` | `1073739776` | `1073741568` |  |
| `nv_fld_minor_extended_revision` | `11:8:4294967294` | `8:11:4` | YES |
| `nv_fldmask_minor_extended_revision` | `4294965248` | `3840` | YES |
| `nv_fldmax_minor_extended_revision` | `2097151` | `15` | YES |
| `nv_fldwidth_minor_extended_revision` | `4294967294` | `4` | YES |
| `nv_mask_all` | `4294965248` | `1073741568` |  |
| `nv_mask_one` | `4294965248` | `3840` |  |
| `nv_mask_two_far` | `4294965248` | `1056968448` |  |
| `nv_maskinv_all` | `minor_extended_revision=2097151,minor_revision=15,major_revision=15,implementation=15,architecture=63,chip_id=1023` | `minor_extended_revision=15,minor_revision=15,major_revision=15,implementation=15,architecture=63,chip_id=1023` |  |
| `nv_maskinv_impl` | `minor_extended_revision=7680,minor_revision=0,major_revision=0,implementation=15,architecture=0,chip_id=15` | `minor_extended_revision=0,minor_revision=0,major_revision=0,implementation=15,architecture=0,chip_id=15` |  |
| `nv_maskinv_two_far` | `minor_extended_revision=2097151,minor_revision=15,major_revision=15,implementation=15,architecture=63,chip_id=1023` | `minor_extended_revision=15,minor_revision=0,major_revision=0,implementation=0,architecture=63,chip_id=1008` |  |
| `nv_reg_NV_PMC_BOOT_42_maxw` | `4294967294` | `10` |  |
| `nv_reg_NV_PMC_BOOT_42_ranges` | `minor_extended_revision=11:8;minor_revision=12:15;major_revision=16:19;implementation=20:23;architecture=24:29;chip_id=20:29` | `minor_extended_revision=8:11;minor_revision=12:15;major_revision=16:19;implementation=20:23;architecture=24:29;chip_id=20:29` |  |
| `nv_reg_NV_PMC_BOOT_42_wide` | `1` | `0` |  |

## the 26 new rows, ALL of them, so the 20 that did not move are visible:

- `nv_boot42_merext_hi` = 11   <- MOVED
- `nv_boot42_merext_lo` = 8   <- MOVED
- `nv_fld_architecture` = 24:29:6
- `nv_fld_chip_id` = 20:29:10
- `nv_fld_implementation` = 20:23:4
- `nv_fld_major_revision` = 16:19:4
- `nv_fld_minor_extended_revision` = 8:11:4   <- MOVED
- `nv_fld_minor_revision` = 12:15:4
- `nv_fldmask_architecture` = 1056964608
- `nv_fldmask_chip_id` = 1072693248
- `nv_fldmask_implementation` = 15728640
- `nv_fldmask_major_revision` = 983040
- `nv_fldmask_minor_extended_revision` = 3840   <- MOVED
- `nv_fldmask_minor_revision` = 61440
- `nv_fldmax_architecture` = 63
- `nv_fldmax_chip_id` = 1023
- `nv_fldmax_implementation` = 15
- `nv_fldmax_major_revision` = 15
- `nv_fldmax_minor_extended_revision` = 15   <- MOVED
- `nv_fldmax_minor_revision` = 15
- `nv_fldwidth_architecture` = 6
- `nv_fldwidth_chip_id` = 10
- `nv_fldwidth_implementation` = 4
- `nv_fldwidth_major_revision` = 4
- `nv_fldwidth_minor_extended_revision` = 4   <- MOVED
- `nv_fldwidth_minor_revision` = 4
