<!-- FROM: tinybendygrad/runtime/support/amd.bend:29 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers. Def names are
# UPSTREAM names: `AMDReg.encode`, `import_module.override`, `import_pmc.key`.
#
#   :5-8   AMDReg             PORTED `AMDReg.addr` `AMDReg.addr_ok` (the shadow)
#   :10    AMDReg.encode      PORTED `AMDReg.encode` -- the `int.__or__` fold
#                                        over `value << fields[name][0]`
#   :11    AMDReg.decode      PORTED `getbits` `AMDReg.decode` -- the join
#                                        ORDER is the field order
#   :13-14 AMDReg.fields_mask PORTED `AMDReg.width` `AMDReg.fields_mask`
#   :17-21 AMDIP              PORTED `import_asic_regs.n` `AMDReg.fields`
#   :23-26 AMDIP.__getattr__  PORTED `AMDIP.name10` `AMDIP.ga` -- the
#                                        `reg` -> `mm` rewrite, which replaces
#                                        EVERY occurrence, and the refusal
#   :31-37 import_module      PORTED `import_module.override` `import_module.vers`
#                                        `import_module.vle` `import_module.kids`
#                                        `import_module.pick_last` `import_module.err`
#   :39    import_soc         PORTED `import_soc.name`
#   :41-44 import_pmc         PORTED `import_pmc.key` `import_pmc.hex2`
#   :46-47 import_asic_regs   PORTED `import_asic_regs.n` `import_asic_regs.first`
# END BLOCK
