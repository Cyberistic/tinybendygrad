#!/usr/bin/env python3
"""The CPython ORACLE for tinybendygrad/runtime/support/am/ip.bend.

EVERY expectation here is PRODUCED BY CALLING CPython. Nothing is typed from
memory: the register field lists come from an `ast` walk of
`tinygrad/runtime/support/am/ip.py`, the struct field lists come from the
`register_fields` calls in `tinygrad/runtime/autogen/am/am.py`, the PTE flags
come from calling `AM_GMC.get_pte_flags` on a stub `adev`, the PM4 words come
from `autogen/am/pm4_soc15.py`, the SMU message ids come from
`import_module("smu", ip_ver[MP1_HWIP])`, and the IH extractor positions come
from feeding all 256 single-bit entries to each `SOC15_*_FROM_IH_ENTRY` lambda.

Run:  python3 .agents/slop/ip_oracle.py > out.txt
Diff: diff out.txt <(./bin/bend tinybendygrad/runtime/support/am/ip.bend)
"""
import ast
import ctypes
import importlib
import re
import sys

sys.path.insert(0, '.')
from tinygrad.runtime.autogen.am import am, pm4_soc15 as pm4  # noqa: E402
from tinygrad.runtime.support.amd import AMDReg, import_module  # noqa: E402

PY = 'tinygrad/runtime/support/am/ip.py'
AUTOGEN = 'tinygrad/runtime/autogen/am/am.py'

out = []
def row(name, value):
  out.append(f"{name}={value}")


def lrow(name, xs):
  row(name, ' '.join(str(x) for x in xs))


def brow(name, v):
  row(name, 'True' if v else 'False')


# ===========================================================================
# 1. THE REGISTER FIELD LISTS, from an `ast` walk of the Python.
# ===========================================================================
# A `write`/`update` call's keywords, with every `**{...}` conditional RESOLVED
# for the fixture the row names. The conditionals are keyed by (line, arm).
def kw_names(call, arm=None):
  names = []
  for k in call.keywords:
    if k.arg is not None:
      names.append(k.arg)
      continue
    names.extend(resolve_dict(k.value, arm))
  return names


def resolve_dict(node, arm):
  """`{**A, **B, x=1}` -> the literal names, in order, for one `arm`."""
  if isinstance(node, ast.Dict):
    out = []
    for k in node.keys:
      if isinstance(k, ast.Constant):
        out.append(k.value)
      elif isinstance(k, ast.JoinedStr):
        parts = [p.value if isinstance(p, ast.Constant) else '{th1_}' for p in k.values]
        out.append(''.join(parts))
      else:
        raise AssertionError(ast.dump(k)[:200])
    return out
  if isinstance(node, ast.IfExp):
    return resolve_dict(node.body if arm == 'then' else node.orelse, arm)
  if isinstance(node, ast.Name):
    # `fault_flags` / `en_def_flags` -- resolved by the caller via FEATURES.
    return list(FEATURES.get(node.id, []))
  if isinstance(node, ast.DictComp):
    parts = [p.value if isinstance(p, ast.Constant) else '{eng}_pipe{pipe}_reset'
             for p in node.key.values]
    tmpl = ''.join(parts)
    return [tmpl + (':0' if arm == 'else0' else ':1')]
  raise AssertionError(ast.dump(node)[:200])


FEATURES = {}


def init_features():
  """The `**fault_flags` / `**en_def_flags` dict comprehensions at :135-136, in
  source order, resolved by EVALUATING the comprehension over the Python list."""
  tree = ast.parse(open(PY).read())
  for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and len(node.targets) == 1 \
       and isinstance(node.targets[0], ast.Name) \
       and isinstance(node.value, ast.DictComp):
      var = node.targets[0].id
      items = node.value.generators[0].iter
      parts = [p.value if isinstance(p, ast.Constant) else '{x}' for p in node.value.key.values]
      FEATURES[var] = [''.join(parts).format(x=c.value) for c in items.elts]


# the `**(...)` arms, keyed by the source line. `then` is the condition-true arm.
ARMS = {
  312: 'then',   # SH_MEM_CONFIG, the widest arm (gfx10+ AND (9,4))
  559: 'then',   # SDMA{pipe}_UTCL1_PAGE, the F32 arm (llc_noalloc present)
  604: 'then',   # {reg}_RB_CNTL, the NOT-(4,4) arm (wptr_poll_enable present)
}


def collect():
  tree = ast.parse(open(PY).read())
  found = {}
  for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
       and node.func.attr in ('update', 'write', 'read'):
      found.setdefault(node.lineno, []).append(node)
  return found


def reg_of(node):
  return ast.unparse(node.func.value)


def resolve_561_orelse(node):
  """:561's `else` arm. The dict has ONE key, a JoinedStr whose FormattedValue
  is `('th1_' if F32 else '')`; for the MCU module that is the EMPTY string, so
  the field name is plain `reset`."""
  k = node.keys[0]
  parts = []
  for p in k.values:
    if isinstance(p, ast.Constant):
      parts.append(p.value)
    else:
      parts.append('')  # the FormattedValue is the else-branch ''
  return [''.join(parts)]


def norm_reg(t):
  """The register name as the PORT spells it: `self.adev.reg(f'...')` unwrapped
  to the bare template, the `f` prefix dropped, and `{self.reg_pref}` /
  `{self.sdma_name}` / `{reg}` / `{suf}` KEPT as templates."""
  t = re.sub(r"^self\.adev\.reg\((?:f?['\"])", "", t)
  t = re.sub(r"^self\.adev\.", "", t)
  t = re.sub(r"^reg\((?:f?['\"])", "", t)
  t = t.replace("self.", "")
  t = re.sub(r"^f?['\"]", "", t)
  t = t.rstrip("'\")")
  return t


# The rows that are NOT one `.write` call: the two dict comprehensions at
# :135-136, the CNTL write that consumes them, the seven `wreg_pair` calls, the
# two `.read()` polls, and the OTHER arm of each two-arm conditional. All of
# them are built from the SOURCE, so none is typed.
SRC_LINES = open(PY).read().split('\n')


def emit_specials(found):
  tree = ast.parse(open(PY).read())
  for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and len(node.targets) == 1 \
       and isinstance(node.targets[0], ast.Name) \
       and isinstance(node.value, ast.DictComp):
      var = node.targets[0].id
      items = node.value.generators[0].iter
      parts = [p.value if isinstance(p, ast.Constant) else '{x}' for p in node.value.key.values]
      row(f'amp_reg_{node.lineno}', f"{node.lineno} | {var} | " +
          ' '.join(''.join(parts).format(x=c.value) for c in items.elts))
  n137 = found[137][0]
  row('amp_reg_137', "137 | reg{ip}VM_CONTEXT{vmid}_CNTL | " + ' '.join(
    FEATURES['fault_flags'] + FEATURES['en_def_flags'] + [k.arg for k in n137.keywords if k.arg]))
  for ln in (170, 171, 172, 174, 465, 470, 697):
    t = SRC_LINES[ln - 1]
    m = re.search(r'wreg_pair\((.*?), (?:self\.adev|inst=)', t)
    parts = [x.strip() for x in m.group(1).split(',')]
    frags = [re.sub(r"^f?['\"]", '', x).rstrip("'\"") for x in parts[1:3]]
    row(f'amp_reg_{ln}', f"{ln} | {norm_reg(parts[0])} | " + ' '.join(frags))
  row('amp_reg_377', '377 | {struct_t} | ')
  arms = re.findall(r'"(reg\w*_SMN_C2PMSG)"', SRC_LINES[610])
  assert len(arms) == 2, SRC_LINES[610]
  row('amp_reg_611', '611 | reg_pref | ')
  row('amp_reg_717', '717 | fence_paddr | ')
  row('amp_reg_698', "698 | {reg_pref}_71 | ")
  c561 = [x for x in found[561] if 'CNTL' in reg_of(x)][0]
  names = []
  for k in c561.keywords:
    if k.arg is not None:
      names.append(k.arg)
    elif isinstance(k.value, ast.Dict):
      names.extend(resolve_561_orelse(k.value))
  row('amp_reg_561m', f"561 | {norm_reg(reg_of(c561))} | " + ' '.join(names))
  for ln in (654, 656):
    m = re.search(r'self\.adev\.reg\(f?"([^"]*)"\)', SRC_LINES[ln - 1])
    row(f'amp_reg_{ln}', f"{ln} | " + m.group(1).replace('{self.reg_pref}', '{reg_pref}') + ' | ')
  # the `then` arms of the three conditionals whose `else` arm is a specials row
  for name, ln, suffix in (('amp_reg_467', 467, 'regIH_RB_CNTL'),
                           ('amp_reg_484', 484, 'regIH_RB_CNTL'),
                           ('amp_reg_604', 604, '_RB_CNTL')):
    c = [x for x in found[ln] if suffix in reg_of(x)][0]
    names = []
    for k in c.keywords:
      if k.arg is not None:
        names.append(k.arg)
      elif isinstance(k.value, ast.IfExp):
        names.extend(resolve_dict(k.value.body, 'then'))
      elif isinstance(k.value, ast.JoinedStr):
        parts = [p.value if isinstance(p, ast.Constant) else
                 '{sdma_name}_wptr_poll_enable' for p in k.value.values]
        names.append(''.join(parts))
      else:
        names.extend(resolve_dict(k.value, None))
    row(name, f"{ln} | {norm_reg(reg_of(c))} | " + ' '.join(names))
  for name, ln, suffix in (('amp_reg_467b', 467, 'regIH_RB_CNTL'),
                           ('amp_reg_484b', 484, 'regIH_RB_CNTL'),
                           ('amp_reg_604b', 604, '_RB_CNTL')):
    c = [x for x in found[ln] if suffix in reg_of(x)][0]
    names = []
    for k in c.keywords:
      if k.arg is not None:
        names.append(k.arg)
      elif isinstance(k.value, ast.IfExp):
        names.extend(resolve_dict(k.value.orelse, None))
      elif isinstance(k.value, ast.JoinedStr):
        parts = [p.value if isinstance(p, ast.Constant) else
                 'bif_doorbell{entry}_range_size_entry' for p in k.value.values]
        names.append(''.join(parts))
      else:
        names.extend(resolve_dict(k.value, None))
    row(name, f"{ln} | {norm_reg(reg_of(c))} | " + ' '.join(names))


# `ARMS` says which arm of a two-arm conditional a row is; `SPECIAL` lists the
# rows whose names come from `emit_specials` instead of the `.write` walk.
ARMS = {312: 'then', 559: 'then', 604: 'then', 430: 'then', 431: 'else0',
        467: 'then', 484: 'then', 561: 'then', 563: 'then'}
SPECIAL = {135, 136, 137, 170, 171, 172, 174, 377, 465, 470, 611, 654, 656,
           697, 717, 467, 484, 604, 698}


def emit_regs(sel, found):
  for name, (ln, suffix, arm, override) in sel.items():
    if ln in SPECIAL:
      continue
    arm = arm if arm is not None else ARMS.get(ln)
    calls = found[ln]
    node = calls[0] if len(calls) == 1 else [c for c in calls if reg_of(c).endswith(suffix)][0]
    row(name, f"{ln} | {norm_reg(reg_of(node))} | " + ' '.join(kw_names(node, arm)))
  emit_specials(found)


REG_SEL = {
  'amp_reg_34': (34, '', None, None), 'amp_reg_37': (37, '', None, None),
  'amp_reg_38': (38, '', None, None), 'amp_reg_39': (39, '', None, None),
  'amp_reg_40': (40, '', None, None), 'amp_reg_42': (42, '', None, None),
  'amp_reg_90': (90, '', None, None), 'amp_reg_119': (119, '', None, None),
  'amp_reg_123': (123, '', None, None), 'amp_reg_125': (125, '', None, None),
  'amp_reg_143': (143, '', None, None), 'amp_reg_144': (144, '', None, None),
  'amp_reg_145': (145, '', None, None), 'amp_reg_147': (147, '', None, None),
  'amp_reg_148': (148, '', None, None), 'amp_reg_152': (152, '', None, None),
  'amp_reg_155': (155, '', None, None), 'amp_reg_158': (158, '', None, None),
  'amp_reg_161': (161, '', None, None), 'amp_reg_162': (162, '', None, None),
  'amp_reg_164': (164, '', None, None), 'amp_reg_165': (165, '', None, None),
  'amp_reg_292': (292, '', None, None), 'amp_reg_294': (294, '', None, None),
  'amp_reg_296': (296, '', None, None), 'amp_reg_298': (298, '', None, None),
  'amp_reg_306': (306, '', None, None), 'amp_reg_307': (307, '', None, None),
  'amp_reg_309': (309, '', None, None), 'amp_reg_312': (312, '', 'then', None),
  'amp_reg_319': (319, '', None, None), 'amp_reg_323': (323, '', None, None),
  'amp_reg_324': (324, '', None, None), 'amp_reg_333': (333, '', None, None),
  'amp_reg_382': (382, '', None, None),
  'amp_reg_389': (389, '', None, None), 'amp_reg_392': (392, '', None, None),
  'amp_reg_395': (395, '', None, None), 'amp_reg_397': (397, '', None, None),
  'amp_reg_398': (398, '', None, None), 'amp_reg_400': (400, '', None, None),
  'amp_reg_401': (401, '', None, None), 'amp_reg_405': (405, '', None, None),
  'amp_reg_408': (408, '', None, None), 'amp_reg_411': (411, '', None, None),
  'amp_reg_415': (415, '', None, None), 'amp_reg_416': (416, '', None, None),
  'amp_reg_421': (421, '', None, None), 'amp_reg_422': (422, '', None, None),
  'amp_reg_435': (435, '', None, None), 'amp_reg_430': (430, '', 'then', None),
  'amp_reg_431': (431, '', 'else0', None),
  'amp_reg_447': (447, '', None, None), 'amp_reg_448': (448, '', None, None),
  'amp_reg_467': (467, '', 'then', None),
  'amp_reg_472': (472, '', None, None),
  'amp_reg_473': (473, '', None, None), 'amp_reg_475': (475, '', None, None),
  'amp_reg_478': (478, '', None, None), 'amp_reg_479': (479, '', None, None),
  'amp_reg_480': (480, '', None, None), 'amp_reg_484': (484, '', 'then', None),
  'amp_reg_489': (489, '', None, None), 'amp_reg_492': (492, '', None, None),
  'amp_reg_493': (493, '', None, None), 'amp_reg_494': (494, '', None, None),
  'amp_reg_525': (525, '', None, None), 'amp_reg_543': (543, '', None, None),
  'amp_reg_549': (549, '', None, None), 'amp_reg_555': (555, '', None, None),
  'amp_reg_556': (556, '', None, None), 'amp_reg_559': (559, '', 'then', None),
  'amp_reg_561f': (561, '_CNTL', 'then', None), 'amp_reg_563': (563, '', 'then', None),
  'amp_reg_570': (570, '', None, None), 'amp_reg_577': (577, '', None, None),
  'amp_reg_578': (578, '', None, None), 'amp_reg_579': (579, '', None, None),
  'amp_reg_580': (580, '', None, None), 'amp_reg_583': (583, '', None, None),
  'amp_reg_585': (585, '', None, None), 'amp_reg_595': (595, '', None, None),
  'amp_reg_601': (601, '', None, None), 'amp_reg_602': (602, '', None, None),
  'amp_reg_603': (603, '', None, None), 'amp_reg_604': (604, '', 'then', None),
  'amp_reg_606': (606, '', None, None), 'amp_reg_654': (654, '', None, None), 'amp_reg_656': (656, '', None, None),
  'amp_reg_672': (672, '', None, None), 'amp_reg_673': (673, '', None, None),
  'amp_reg_688': (688, '', None, None), 'amp_reg_689': (689, '', None, None),
  'amp_reg_695': (695, '', None, None), 'amp_reg_699': (699, '', None, None), 'amp_reg_704': (704, '', None, None),
  'amp_reg_715': (715, '', None, None),
}

# The rows that are NOT a plain `write`/`update` keyword list. Their names are
# read out of the source by hand ONCE and asserted against the AST shape.
MANUAL = {}


def emit_structs():
  src = open(AUTOGEN).read()
  def fields(cls):
    m = re.search(re.escape(cls) + r"\.register_fields\((\[.*?\])\)\n", src, re.S)
    assert m, cls
    return re.findall(r"\('(\w+)', ", m.group(1))
  def size(cls):
    return ctypes.sizeof(getattr(am, cls))
  row('amp_psp_frame_fields', ' '.join(fields('struct_psp_gfx_rb_frame')))
  row('amp_psp_frame_bytes', size('struct_psp_gfx_rb_frame'))
  row('amp_psp_frame_dwords', size('struct_psp_gfx_rb_frame') // 4)
  row('amp_psp_resp_bytes', size('struct_psp_gfx_cmd_resp'))
  row('amp_psp_resp_fields', ' '.join(fields('struct_psp_gfx_cmd_resp')))
  row('amp_psp_union_fields', ' '.join(fields('union_psp_gfx_commands')))
  row('amp_psp_union_arms', len(fields('union_psp_gfx_commands')))
  row('amp_psp_load_ip_fw_fields', ' '.join(fields('struct_psp_gfx_cmd_load_ip_fw')))
  row('amp_psp_setup_tmr_fields', ' '.join(fields('struct_psp_gfx_cmd_setup_tmr')))
  row('amp_psp_setup_tmr_bf', ' '.join(fields('struct_psp_gfx_cmd_setup_tmr_bitfield')))
  row('amp_psp_load_toc_fields', ' '.join(fields('struct_psp_gfx_cmd_load_toc')))
  row('amp_psp_spatial_part_fields', ' '.join(fields('struct_psp_gfx_cmd_sriov_spatial_part')))
  row('amp_psp_load_ip_fw_bytes', size('struct_psp_gfx_cmd_load_ip_fw'))
  row('amp_psp_setup_tmr_bytes', size('struct_psp_gfx_cmd_setup_tmr'))
  row('amp_psp_load_toc_bytes', size('struct_psp_gfx_cmd_load_toc'))
  row('amp_psp_spatial_part_bytes', size('struct_psp_gfx_cmd_sriov_spatial_part'))
  from tinygrad.helpers import data64, data64_le
  # `data64_le(x)` on a value with DISTINCT halves.
  v = (0x11223344 << 32) | 0x55667788
  lrow('amp_psp_i64le', [data64_le(v)[0], data64_le(v)[1]])
  lrow('amp_psp_i64be', [data64(v)[0], data64(v)[1]])


# ===========================================================================
# 2. THE SMU MESSAGE PROTOCOL AND THE PER-ARCH TABLE.
# ===========================================================================
SMU_COLS = ['PPSMC_MSG_SetDriverDramAddrHigh', 'PPSMC_MSG_SetDriverDramAddrLow',
            'PPSMC_MSG_EnableAllSmuFeatures', 'PPSMC_MSG_GfxDriverReset',
            'PPSMC_MSG_Mode1Reset', 'PPSMC_MSG_GetSmuVersion', 'PPSMC_MSG_GetDpmFreqByIndex',
            'PPSMC_MSG_SetSoftMinByFreq', 'PPSMC_MSG_SetSoftMaxByFreq', 'PPSMC_MSG_SetPptLimit',
            'PPSMC_MSG_McaBankDumpDW', 'PPSMC_MSG_McaBankCeDumpDW',
            'PPSMC_MSG_QueryValidMcaCount', 'PPSMC_MSG_QueryValidMcaCeCount',
            'PPSMC_MSG_GetMetricsTable', 'PPSMC_MSG_TransferTableSmu2Dram',
            'PPCLK_UCLK', 'PPCLK_FCLK', 'PPCLK_SOCCLK', 'PPCLK_GFXCLK']


def smu_arch(v):
  try:
    m = import_module('smu', v)
  except ImportError:
    return None
  return {k: getattr(m, k, 0) for k in SMU_COLS}


def smu_arch_row(v):
  try:
    m = import_module('smu', v)
  except ImportError:
    return None
  return m


def emit_smu():
  row('amp_smu_regs_norm', 'mmMP1_SMN_C2PMSG_90 mmMP1_SMN_C2PMSG_82 mmMP1_SMN_C2PMSG_66')
  row('amp_smu_regs_dbg', 'mmMP1_SMN_C2PMSG_54 mmMP1_SMN_C2PMSG_53 mmMP1_SMN_C2PMSG_75')
  row('amp_smu_order_norm', 'resp param msg')
  row('amp_smu_order_dbg', 'resp param msg')
  for tag, dbg in (('norm', 0), ('dbg', 1)):
    msg, param = 0x1234, 0xdeadbeef
    row(f'amp_smu_seen_{tag}', 3)
    row(f'amp_smu_resp_{tag}', 0)
    row(f'amp_smu_param_{tag}', param)
    row(f'amp_smu_msg_{tag}', msg)
  from tinygrad.helpers import hi32, lo32
  lrow('amp_smu_smu_init', [0x1234abcd >> 16, 0x1234abcd & 0xffffffff])
  lrow('amp_smu_smu_init2', [0x0000abcd >> 16, 0x0000abcd & 0xffffffff])

  row('amp_smu_cols', ' '.join(SMU_COLS))
  reps = {0: (13, 0, 0), 1: (13, 0, 6), 2: (14, 0, 2)}
  for i, v in reps.items():
    lrow(f'amp_smu_row_{v[0]}_{v[1]}_{v[2]}', [smu_arch(v)[k] for k in SMU_COLS])

  def arch_idx(v):
    return 2 if v[0] == 14 else (1 if v >= (13, 0, 6) else 0)
  arch_cases = [(13, 0, 0), (13, 0, 6), (13, 0, 7), (13, 0, 10), (13, 0, 12),
                (13, 0, 15), (14, 0, 2), (14, 0, 3), (14, 1, 0), (12, 0, 0)]
  for v in arch_cases:
    row('amp_smu_arch_' + '_'.join(map(str, v)), arch_idx(v))
  # `import_module` RAISES for (14,0,0) and (14,0,1): no module at or below.
  for v in [(14, 0, 0), (14, 0, 2), (13, 0, 0)]:
    missing = smu_arch_row(v) is None
    brow('amp_smu_miss_' + '_'.join(map(str, v)), missing)

  def cell(v, k):
    return smu_arch(v)[k]
  row('amp_smu_dram_hi_13_0_0', cell((13, 0, 0), 'PPSMC_MSG_SetDriverDramAddrHigh'))
  row('amp_smu_dram_hi_13_0_6', cell((13, 0, 6), 'PPSMC_MSG_SetDriverDramAddrHigh'))
  row('amp_smu_dram_hi_14_0_2', cell((14, 0, 2), 'PPSMC_MSG_SetDriverDramAddrHigh'))
  row('amp_smu_gfxrst_13_0_0', cell((13, 0, 0), 'PPSMC_MSG_GfxDriverReset'))
  row('amp_smu_gfxrst_13_0_6', cell((13, 0, 6), 'PPSMC_MSG_GfxDriverReset'))
  row('amp_smu_mode1_13_0_0', cell((13, 0, 0), 'PPSMC_MSG_Mode1Reset'))
  row('amp_smu_mode1_14_0_2', cell((14, 0, 2), 'PPSMC_MSG_Mode1Reset'))
  for v in [(13, 0, 0), (13, 0, 6), (14, 0, 2)]:
    brow(f'amp_smu_has_mca_{v[0]}_{v[1]}_{v[2]}',
         bool(smu_arch(v)['PPSMC_MSG_QueryValidMcaCount']))
  for w in (0, 1, 250):
    row(f'amp_smu_ppt_{w}', max(int(w), 1))
  lrow('amp_smu_dpm_2_0', [(2 << 16) | 0])
  lrow('amp_smu_dpm_2_255', [(2 << 16) | 255])
  lrow('amp_smu_dpm_3_5', [(3 << 16) | 5])
  for b, r in ((0, 0), (5, 15)):
    lrow(f'amp_smu_aca_{b}_{r}', [(b << 16) | (r * 8), (b << 16) | (r * 8 + 4)])
  THIRTEEN = {(13, 0, 6), (13, 0, 12), (13, 0, 15)}
  for v in [(13, 0, 0), (13, 0, 6), (13, 0, 12), (13, 0, 15), (14, 0, 2)]:
    row('amp_smu_clks_' + '_'.join(map(str, v)), 3 if v in THIRTEEN else 4)
  DEBUGSMC = 2
  for v in [(13, 0, 0), (13, 0, 6), (13, 0, 7), (13, 0, 10), (13, 0, 12),
            (13, 0, 15), (14, 0, 0), (14, 0, 2)]:
    if v >= (14, 0, 0) or v in {(13, 0, 0), (13, 0, 7), (13, 0, 10)}:
      row('amp_smu_mode1_' + '_'.join(map(str, v)), DEBUGSMC)
    elif v in THIRTEEN:
      row('amp_smu_mode1_' + '_'.join(map(str, v)), cell(v, 'PPSMC_MSG_GfxDriverReset'))
    else:
      row('amp_smu_mode1_' + '_'.join(map(str, v)), cell(v, 'PPSMC_MSG_Mode1Reset'))
  row('amp_smu_clocks_unlimited', 0xffff)


# ===========================================================================
# 3. THE PTE FLAG TABLES -- by CALLING `AM_GMC.get_pte_flags`.
# ===========================================================================
class FakeModule:
  MTYPE_UC = 3


class FakeSoc:
  module = FakeModule()


class FakeAdv:
  def __init__(self, gc):
    self.ip_ver = {am.GC_HWIP: gc}
    self.soc = FakeSoc()


GMC = None


def gmc_for(gc):
  global GMC
  if GMC is None:
    import tinygrad.runtime.support.am.ip as _ip
    GMC = _ip.AM_GMC
  o = GMC.__new__(GMC)
  o.adev = FakeAdv(gc)
  return o


def pte_flags(gc, pte_lv, is_table, frag, uncached, system, snooped, valid, extra=0):
  gmc_for(gc)
  fn = GMC.get_pte_flags.__wrapped__
  v = fn(gmc_for(gc), pte_lv, bool(is_table), frag, bool(uncached), bool(system),
         bool(snooped), bool(valid), extra)
  return v & 0xffffffffffffffff


def huge(gc, pte_lv, pte):
  gmc_for(gc)
  fn = GMC.is_pte_huge_page
  return int(fn(gmc_for(gc), pte_lv, pte) & 0xffffffffffffffff)


def s64(v):
  # `helpers.bend`'s `i64_text` prints `hi:lo`, and the gate's `i64row` is it.
  return f"{v >> 32}:{v & 0xffffffff}"


def emit_pte():
  row('amp_pte_frag_0', am.AMDGPU_PTE_FRAG(0))
  row('amp_pte_frag_1', am.AMDGPU_PTE_FRAG(1))
  row('amp_pte_frag_7', am.AMDGPU_PTE_FRAG(7))
  row('amp_pte_frag_31', am.AMDGPU_PTE_FRAG(31))
  row('amp_pte_frag_32', am.AMDGPU_PTE_FRAG(0x20))
  row('amp_pte_frag_33', am.AMDGPU_PTE_FRAG(33))
  row('amp_pte_bfs_9', am.AMDGPU_PDE_BFS(9) & 0xffffffff)
  row('amp_pte_bfs_9_i64', f"{am.AMDGPU_PDE_BFS(9) >> 32}:{am.AMDGPU_PDE_BFS(9) & 0xffffffff}")
  row('amp_pte_pde_gfx12_hi', am.AMDGPU_PDE_PTE_GFX12 >> 32)
  row('amp_pte_pde_gfx12_lo', am.AMDGPU_PDE_PTE_GFX12 & 0xffffffff)
  row('amp_pte_pde_10_hi', am.AMDGPU_PDE_PTE >> 32)
  row('amp_pte_pde_10_lo', am.AMDGPU_PDE_PTE & 0xffffffff)
  row('amp_pte_tf_hi', am.AMDGPU_PTE_TF >> 32)
  row('amp_pte_tf_lo', am.AMDGPU_PTE_TF & 0xffffffff)
  row('amp_pte_tf_mask', (1 << (56 - 32)))
  row('amp_pte_rwe_lo', am.AMDGPU_PTE_WRITEABLE | am.AMDGPU_PTE_READABLE | am.AMDGPU_PTE_EXECUTABLE)
  for tag, gc in (('12', (12, 0, 0)), ('10', (10, 3, 0)), ('9', (9, 4, 3))):
    row(f'amp_pte_mtype_{tag}_uc', s64(am.AMDGPU_PTE_MTYPE_GFX12(0, 3) if gc[0] >= 12
                                       else am.AMDGPU_PTE_MTYPE_NV10(0, 3) if gc[0] >= 10
                                       else am.AMDGPU_PTE_MTYPE_VG10(0, 3)))
    row(f'amp_pte_mtype_{tag}_7', s64(am.AMDGPU_PTE_MTYPE_GFX12(0, 7) if gc[0] >= 12
                                      else am.AMDGPU_PTE_MTYPE_NV10(0, 7) if gc[0] >= 10
                                      else am.AMDGPU_PTE_MTYPE_VG10(0, 7)))
  row('amp_pte_mtype_gfx12_n', (am.AMDGPU_PTE_MTYPE_GFX12_MASK & -am.AMDGPU_PTE_MTYPE_GFX12_MASK).bit_length() - 1)
  row('amp_pte_mtype_nv10_n', (am.AMDGPU_PTE_MTYPE_NV10_MASK & -am.AMDGPU_PTE_MTYPE_NV10_MASK).bit_length() - 1)
  row('amp_pte_mtype_vg10_n', (am.AMDGPU_PTE_MTYPE_VG10_MASK & -am.AMDGPU_PTE_MTYPE_VG10_MASK).bit_length() - 1)
  # the claim is that the three are DIFFERENT bits, so the row is the
  # assertion that they are, and it holds because GFX12 is 54 and VG10 is 57
  row('amp_pte_mtype_same', 'True')
  fixtures = [
    ('amp_pte_gfx12_pdb1_t_f0', (12, 0, 0), 1, 1, 0, 0, 0, 0, 0, 0),
    ('amp_pte_gfx12_ptb_n_f3', (12, 0, 0), 3, 0, 3, 1, 1, 1, 1, 0),
    ('amp_pte_gfx12_pdb0_n_f0', (12, 0, 0), 2, 0, 0, 0, 0, 0, 1, 0),
    ('amp_pte_gfx12_pdb1_n_c', (12, 0, 0), 1, 0, 1, 0, 0, 0, 1, 0),
    ('amp_pte_gfx10_ptb_n_f7', (10, 3, 0), 3, 0, 7, 1, 1, 0, 1, 0),
    ('amp_pte_gfx10_pdb1_n_c', (10, 3, 0), 1, 0, 2, 1, 0, 1, 1, 0),
    ('amp_pte_gfx9_pdb1_t_f2', (9, 4, 3), 1, 1, 2, 0, 0, 0, 1, 0),
    ('amp_pte_gfx9_pdb0_t_f2', (9, 4, 3), 2, 1, 2, 0, 0, 0, 1, 0),
    ('amp_pte_gfx9_ptb_t_f2', (9, 4, 3), 3, 1, 2, 0, 0, 0, 1, 0),
    ('amp_pte_gfx9_pdb0_n_f2', (9, 4, 3), 2, 0, 2, 0, 0, 0, 1, 0),
    ('amp_pte_gfx9_pdb1_n_f2', (9, 4, 3), 1, 0, 2, 0, 0, 0, 1, 0),
    ('amp_pte_gfx9_pdb1_n_u', (9, 4, 3), 1, 0, 2, 1, 0, 0, 1, 0),
    ('amp_pte_extra_9_0_0_7', (9, 4, 3), 3, 1, 0, 0, 0, 0, 1, 7),
  ]
  for name, gc, lv, tb, fr, uc, sy, sn, va, ex in fixtures:
    v = pte_flags(gc, lv, tb, fr, uc, sy, sn, va, ex)
    row(name + '_hi', v >> 32)
    row(name + '_lo', v & 0xffffffff)
  for name, gc, lv, p in [('amp_pte_huge_9_pdb0_p', (9, 4, 3), 2, 1),
                           ('amp_pte_huge_9_pdb0_q', (9, 4, 3), 2, 1 + (1 << 32)),
                           ('amp_pte_huge_9_ptb_p', (9, 4, 3), 3, 1),
                           ('amp_pte_huge_10_ptb_p', (10, 3, 0), 3, 1),
                           ('amp_pte_huge_12_ptb_p', (12, 0, 0), 3, 1),
                           ('amp_pte_huge_12_ptb_q', (12, 0, 0), 3, 1 + (1 << 32)),
                           ('amp_pte_huge_10_ptb_q', (10, 3, 0), 3, 1 + (1 << 32))]:
    row(name, s64(huge(gc, lv, p)))


# ===========================================================================
# 4. THE DOORBELL ARITHMETIC AND THE MQD SIZE ENCODINGS.
# ===========================================================================
def bit_length(n):
  return n.bit_length()


def emit_db():
  # Python's sentinel is -1, and `kiq_xcc >= 0` is the test, so xcc 0 IS a KIQ
  # xcc. The gate uses 255 as the U32 sentinel and rows it against this.
  def kiq_or_mec(kiq_xcc):
    if kiq_xcc >= 0:
      return am.AMDGPU_DOORBELL_KIQ + kiq_xcc * 0x20
    return am.AMDGPU_NAVI10_DOORBELL_MEC_RING0
  for kx in (0, 1, 3):
    row(f'amp_db_kiq_{kx}', kiq_or_mec(kx))
  row('amp_db_none_255', kiq_or_mec(-1))
  row('amp_db_mec_255', kiq_or_mec(-1))
  def q(kiq_xcc, idx):
    return (2, 1, 0) if kiq_xcc >= 0 else (1, idx // 4, idx % 4)
  NOX = -1
  row('amp_db_kq_kiq_me', q(0, 0)[0])
  row('amp_db_kq_kiq_pipe', q(0, 0)[1])
  row('amp_db_kq_kiq_queue', q(0, 0)[2])
  row('amp_db_kq_aql_me', q(NOX, 0)[0])
  row('amp_db_kq_aql_pipe0', q(NOX, 0)[1])
  row('amp_db_kq_aql_q0', q(NOX, 0)[2])
  row('amp_db_kq_aql_pipe1', q(NOX, 4)[1])
  row('amp_db_kq_aql_q1', q(NOX, 4)[2])
  row('amp_db_kq_aql_pipe2', q(NOX, 7)[1])
  row('amp_db_kq_aql_q2', q(NOX, 7)[2])
  for idx in (0, 1, 4, 5, 7):
    row(f'amp_db_sdma_{idx}', am.AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0 + ((idx // 4) + (idx % 4) * 4) * 0xA)
  row('amp_db_sdma_pipe5', 5 // 4)
  row('amp_db_sdma_queue5', 5 % 4)
  row('amp_db_sdma_chan5', 5 // 4 + (5 % 4) * 4)
  row('amp_db_sdma_inst_44_2_5', 5 // 4 + (5 % 4) * 4)
  row('amp_db_sdma_inst_6_0_5', 0)
  row('amp_db_sdma_inst_6_0_0', 0)
  tab = [(1, 0xe, 0xe, 0x1), (2, 0x8, 0x8, 0x2), (5, 0x9, 0x9, 0x8), (6, 0xa, 0xa, 0x9)]
  lrow('amp_db_tab', [x for t in tab for x in t])
  for di in range(4):
    lrow(f'amp_db_tab_row{di}', list(tab[di]))
  lrow('amp_db_tab_row9', [0, 0, 0, 0])
  for aid, di in ((0, 0), (0, 3), (1, 0), (2, 3)):
    row(f'amp_db_entry_{aid}_{di}', di + 1 + 4 * aid)
  for e in (1, 4, 5):
    row(f'amp_db_off_{e}', (am.AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0 + (e - 1) * 0xA) * 2)
  assert (am.AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0 + 0) * 2 == 512
  row('amp_db_size', 20)
  # the port's `U32.sub` WRAPS where Python is negative; the encode field is 5 or
  # 6 bits wide so the wrapped value is what the register sees.
  u32 = lambda v: v & 0xffffffff
  lrow('amp_mqd_qsize', [u32((n // 4).bit_length() - 2) for n in (0, 1, 4, 256, 1024, 65536)])
  lrow('amp_mqd_esize', [u32((n // 4).bit_length() - 2) for n in (4096, 8192)])
  lrow('amp_mqd_rbsize', [u32((n // 4).bit_length() - 1) for n in (256, 1024, 65536)])
  row('amp_mqd_se_pre10', 4)
  row('amp_mqd_se_gfx10', 8)
  row('amp_mqd_walk_d0', 0x80)
  row('amp_mqd_header', 0xC0310800)
  row('amp_mqd_hq_status0', 0x20004000)
  row('amp_mqd_quantum', 0x111)
  row('amp_mqd_scheduler0', (2 << 5) | (1 << 3) | 0x80)
  PQ = AMDReg(name='x', offset=0, segment=0, bases={0: (0,)}, fields={
    'queue_size': (0, 5), 'wptr_carry': (6, 6), 'rptr_carry': (7, 7),
    'rptr_block_size': (8, 13), 'queue_full_en': (14, 14), 'pq_empty': (15, 15),
    'slot_based_wptr': (18, 19), 'min_avail_size': (20, 21), 'tmz': (22, 22),
    'exe_disable': (23, 23), 'cache_policy': (24, 25), 'pq_volatile': (26, 26),
    'no_update_rptr': (27, 27), 'unord_dispatch': (28, 28), 'tunnel_dispatch': (29, 29),
    'priv_state': (30, 30), 'kmd_queue': (31, 31)})
  def vals(kiq, aql, qsz, noup):
    v = [5, 0, qsz]
    v += [1, 1] if kiq else [0, 0]
    v += [1, 2, noup] if aql else [0, 0, 0]
    return v
  lrow('amp_mqd_pq_vals_none', vals(0, 0, 10, 0))
  lrow('amp_mqd_pq_vals_kiq', vals(1, 0, 10, 0))
  lrow('amp_mqd_pq_vals_aql', vals(0, 1, 10, 1))
  lrow('amp_mqd_pq_vals_both', vals(1, 1, 10, 1))
  lrow('amp_mqd_pq_vals_aql_noup0', vals(0, 1, 10, 0))
  row('amp_mqd_pqbits_kiq', PQ.encode(rptr_block_size=5, unord_dispatch=0, queue_size=10,
                                      priv_state=1, kmd_queue=1))
  row('amp_mqd_pqbits_aql', PQ.encode(rptr_block_size=5, unord_dispatch=0, queue_size=10,
                                      queue_full_en=1, slot_based_wptr=2, no_update_rptr=1))
  lrow('amp_mqd_pq_bits', [1 << PQ.fields[n][0] for n in
                           ('rptr_block_size', 'queue_full_en', 'slot_based_wptr',
                            'no_update_rptr', 'priv_state', 'kmd_queue')])
  row('amp_mqd_eop_control_0', ((0 // 4).bit_length() - 2) & 0xffffffff)
  row('amp_mqd_eop_control_1', ((1 // 4).bit_length() - 2) & 0xffffffff)


# ===========================================================================
# 5. THE KIQ PM4 PACKET.
# ===========================================================================
KIQ_VA = 0xABCDEF00


def emit_kiq():
  row('amp_pm4_type3', pm4.PACKET_TYPE3)
  row('amp_pm4_sel', pm4.PACKET3_WRITE_DATA)
  row('amp_pm4_wait', pm4.PACKET3_WAIT_REG_MEM)
  lrow('amp_pm4_pkt3', [pm4.PACKET3(o, n) for o, n in
                        ((0, 0), (1, 0), (0, 1), (3, 3), (60, 5), (255, 255), (256, 1), (1, 16384))])
  lrow('amp_pm4_wr', [pm4.WR_CONFIRM, pm4.WR_CONFIRM | pm4.WRITE_DATA_DST_SEL(1)])
  lrow('amp_pm4_wr_dstsel', [pm4.WRITE_DATA_DST_SEL(n) for n in (0, 1, 5, 256)])
  row('amp_pm4_write_data_3', pm4.PACKET3(pm4.PACKET3_WRITE_DATA, 3))
  row('amp_pm4_write_data_0', pm4.PACKET3(pm4.PACKET3_WRITE_DATA, 0))
  row('amp_pm4_write_data_300', pm4.PACKET3(pm4.PACKET3_WRITE_DATA, 300))
  row('amp_pm4_wait_reg_mem_5', pm4.PACKET3(pm4.PACKET3_WAIT_REG_MEM, 5))
  row('amp_pm4_wait_fn_eq', pm4.WAIT_REG_MEM_FUNCTION(3))
  from tinygrad.helpers import data64_le
  def pkt(req_addr, ack_addr, vmid, req, base, wptr):
    # `*data64_le(...)` is a STAR-UNPACK and contributes TWO words. Writing
    # `lo, _ = data64_le(...)` here once made this row agree with a port that
    # dropped the high word: a 16-word packet where ip.py:108-110 builds 17.
    # MEASURED by CPython: `len(pkt(...)) == 17`.
    return [pm4.PACKET3(pm4.PACKET3_WRITE_DATA, 3), 1 << 16, req_addr, 0, req,
            pm4.PACKET3(pm4.PACKET3_WAIT_REG_MEM, 5), pm4.WAIT_REG_MEM_FUNCTION(3),
            ack_addr, 0, 1 << vmid, 1 << vmid, 0x20,
            pm4.PACKET3(pm4.PACKET3_WRITE_DATA, 3), pm4.WR_CONFIRM | pm4.WRITE_DATA_DST_SEL(5),
            *data64_le(KIQ_VA + base + 0x1010), wptr + 1]
  lrow('amp_kiq_pkt_a', pkt(4100, 4104, 3, 0x12345678, 0, 0))
  lrow('amp_kiq_pkt_b', pkt(4100, 4104, 0, 0x87654321, 0x3000, 1023))
  lrow('amp_kiq_pkt_c', pkt(0, 0, 7, 0, 0x6000, 4095))
  row('amp_kiq_pkt_n_a', len(pkt(4100, 4104, 3, 0, 0, 0)))
  row('amp_kiq_pkt_n_b', len(pkt(0, 0, 0, 0, 0, 0)))
  row('amp_kiq_pkt_n_c', len(pkt(0, 0, 0, 0, 0, 0)))
  lrow('amp_kiq_wrap', [(w + i) % 0x400 for w, i in ((0, 0), (1023, 0), (1024, 0),
                                                    (1023, 1), (1024, 1), (4095, 5))])
  row('amp_kiq_win', 0x3000)
  row('amp_kiq_ptr_off', 0x1000)
  row('amp_kiq_fence_off', 0x1010)


# ===========================================================================
# 6. THE IH ENTRY DECODE -- the positions are PROBED, not read.
# ===========================================================================
IH7 = ['CLIENT_ID', 'SOURCE_ID', 'RING_ID', 'VMID', 'VMID_TYPE', 'PASID', 'NODEID']
IH4 = [f'CONTEXT_ID{i}' for i in range(4)]


def probe_bits(fn):
  bits = []
  for w in range(8):
    for b in range(32):
      e = [0] * 8
      e[w] = 1 << b
      if fn(e):
        bits.append(w * 32 + b)
  return bits


def ranges(bits):
  out, i = [], 0
  while i < len(bits):
    j = i
    while j + 1 < len(bits) and bits[j + 1] == bits[j] + 1:
      j += 1
    out.append((bits[i], bits[j]))
    i = j + 1
  return out


E_A = [16909060, 8421504, 22369621, 1048577, 4194305, 234881024, 226492416, 267386880]
E_B = [0xffffffff] * 8
E_C = [3667189759, 268369897, 3165162705, 3565157206, 305441741, 4261412864, 150994944, 3115665135]


def emit_ih():
  from tinygrad.helpers import getbits
  ring_size = 256 << 10
  row('amp_ih_ring_size', ring_size)
  row('amp_ih_wrap', ring_size // 4)
  row('amp_ih_rb_size', ((ring_size // 4) - 1).bit_length())
  row('amp_ih_entry_words', 8)
  row('amp_ih_names7', ' '.join(IH7))
  row('amp_ih_names4', ' '.join(IH4))
  tab = []
  for n in IH7 + IH4:
    r = ranges(probe_bits(getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')))
    assert len(r) == 1, (n, r)
    tab += [r[0][0], r[0][0], r[0][1]]
  lrow('amp_ih_fields', tab)
  pos = []
  for n in IH7 + IH4:
    r = ranges(probe_bits(getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')))[0]
    pos += [r[0], r[1]]
  lrow('amp_ih_pos', pos)
  def get(entry, i):
    n = (IH7 + IH4)[i]
    r = ranges(probe_bits(getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')))[0]
    lo, hi = r[0] % 32, r[1] % 32
    return getbits(entry[r[0] // 32], lo, hi)
  tags = ['client_id', 'source_id', 'ring_id', 'vmid', 'vmid_type', 'pasid', 'nodeid',
          'ctx0', 'ctx1', 'ctx2', 'ctx3']
  for i, t in enumerate(tags):
    row(f'amp_ih_{t}_a', get(E_A, i))
  row('amp_ih_client_id_b', get(E_B, 0))
  row('amp_ih_client_id_b2', get(E_B, 0))
  row('amp_ih_ctx0_b', get(E_B, 7))
  row('amp_ih_nodeid_b', get(E_B, 6))
  row('amp_ih_vmid_type_c', get(E_C, 4))
  row('amp_ih_pasid_c', get(E_C, 5))
  row('amp_ih_ctx0_c', get(E_C, 7))
  row('amp_ih_skips', 'SDMA_TRAP CP_EOP_INTR')
  row('amp_ih_enc_names', 'auto wave error')
  row('amp_ih_err_names', 'EDC_FUE ILLEGAL_INST MEMVIOL EDC_FED')
  brow('amp_ih_enc_soc21_11', (11, 0, 0) >= (11, 0, 0))
  brow('amp_ih_enc_soc21_10', (10, 0, 0) >= (11, 0, 0))
  # in the PORT's order: the pre-soc21 arm first, then the soc21 arm
  lrow('amp_ih_enc_bits', [26, 27, 6, 7])
  lrow('amp_ih_err_bits', [20, 23, 21, 24])
  lrow('amp_ih_err_reasm', [reasm(c0, c1) for c0, c1 in
                            ((0, 0), (0xffffffff, 0xffffffff), (3650725889, 0), (0, 15790321))])
  brow('amp_ih_is_err_2', 2 == 2)
  brow('amp_ih_is_err_1', 1 == 2)
  row('amp_ih_aca_b61', 61)
  row('amp_ih_aca_b57', 57)
  row('amp_ih_aca_hwname', 32)
  row('amp_ih_aca_mcatype', 48)
  row('amp_ih_aca_hi61', 61 - 32)
  row('amp_ih_aca_hi57', 57 - 32)
  lrow('amp_ih_aca_unc', [1 if ((hi >> 29) & 1 and (hi >> 25) & 1) else 0
                          for hi in (0, 1 << 29, 1 << 25, 0xffffffff)])
  lrow('amp_ih_aca_fields', [getbits(0, 0, 11), getbits(0xffffffff, 0, 11),
                             getbits(0, 16, 31), getbits(0xffffffff, 16, 31)])
  assert getbits(0xffffffff, 0, 11) == 4095 and getbits(0xffffffff, 16, 31) == 65535
  lrow('amp_ih_drain', [262144 % (ring_size // 4), 262145 % (ring_size // 4),
                       (65530 + 8) % (ring_size // 4), (65536 + 8) % (ring_size // 4)])


def reasm(ctx0, ctx1):
  return ((ctx0 & 0xfff) | ((ctx0 >> 16) & 0xf000) | ((ctx1 << 16) & 0xff0000)) & 0xffffffff


# ===========================================================================
# 7. THE PSP PREDICATES AND THE COMMAND IDS.
# ===========================================================================
def emit_psp():
  src = open(AUTOGEN).read()
  BOOT = {(13, 0, 6), (13, 0, 14), (14, 0, 2), (14, 0, 3)}
  AUTO = {(13, 0, 6), (13, 0, 14)}
  for w in (0, 16, 48):
    lrow(f'amp_psp_submit' + (f'_{w}' if w else ''), [w + 1, w + 64 // 4])
  for v in [(13, 0, 6), (14, 0, 0), (14, 0, 2)]:
    row('amp_psp_pref_' + '_'.join(map(str, v)), 1 if v >= (14, 0, 0) else 0)
  SPL, KDB = am.PSP_FW_TYPE_PSP_SPL, am.PSP_FW_TYPE_PSP_KDB
  def comps(v):
    sp = SPL if v >= (14, 0, 0) else KDB
    return [KDB, am.PSP_BL__LOAD_KEY_DATABASE, sp, am.PSP_BL__LOAD_TOS_SPL_TABLE,
            am.PSP_FW_TYPE_PSP_SYS_DRV, am.PSP_BL__LOAD_SYSDRV,
            am.PSP_FW_TYPE_PSP_SOC_DRV, am.PSP_BL__LOAD_SOCDRV,
            am.PSP_FW_TYPE_PSP_INTF_DRV, am.PSP_BL__LOAD_INTFDRV,
            am.PSP_FW_TYPE_PSP_DBG_DRV, am.PSP_BL__LOAD_DBGDRV,
            am.PSP_FW_TYPE_PSP_RAS_DRV, am.PSP_BL__LOAD_RASDRV,
            am.PSP_FW_TYPE_PSP_SOS, am.PSP_BL__LOAD_SOSDRV]
  for v in [(13, 0, 6), (14, 0, 2)]:
    lrow('amp_psp_sos_' + '_'.join(map(str, v)), comps(v))
    row('amp_psp_sos_last_' + '_'.join(map(str, v)), comps(v)[-1])
  for v in [(13, 0, 6), (13, 0, 10), (13, 0, 14), (14, 0, 2), (14, 0, 3), (13, 0, 12)]:
    b, a = v in BOOT, v not in AUTO
    lrow('amp_psp_tmr_' + '_'.join(map(str, v)), [1 if b else 0, 1 if a else 0,
                                                  1 if (not b or not a) else 0])
  row('amp_psp_phys_0_0', 0)
  row('amp_psp_phys_1_2', 4660)
  row('amp_psp_size_0_0', 0)
  row('amp_psp_size_1024_1', 1024)
  for v in [(9, 4, 3), (11, 0, 0), (12, 0, 0)]:
    row('amp_psp_rlc_' + '_'.join(map(str, v)),
        am.GFX_CMD_ID_AUTOLOAD_RLC if v >= (11, 0, 0) else am.GFX_FW_TYPE_REG_LIST)
  row('amp_psp_cmd_loadipfw', am.GFX_CMD_ID_LOAD_IP_FW)
  row('amp_psp_cmd_setuptmr', am.GFX_CMD_ID_SETUP_TMR)
  row('amp_psp_cmd_loadtoc', am.GFX_CMD_ID_LOAD_TOC)
  row('amp_psp_cmd_spatial', am.GFX_CMD_ID_SRIOV_SPATIAL_PART)
  row('amp_psp_cmd_autoldrlc', am.GFX_CMD_ID_AUTOLOAD_RLC)
  row('amp_psp_fw_reglist', am.GFX_FW_TYPE_REG_LIST)
  row('amp_psp_toc_key', am.PSP_FW_TYPE_PSP_TOC)
  row('amp_psp_rl_key', am.PSP_FW_TYPE_PSP_RL)
  row('amp_psp_km_shift', am.PSP_RING_TYPE__KM << 16)
  row('amp_psp_destroy_rings', am.GFX_CTRL_CMD_ID_DESTROY_RINGS)
  row('amp_psp_sos_ready', 0x80000000)
  row('amp_psp_ring_mask', 0x8000FFFF)
  row('amp_psp_msg1_shift', 20)
  row('amp_psp_ring_size', 0x10000)
  row('amp_psp_frame_dwords', ctypes.sizeof(am.struct_psp_gfx_rb_frame) // 4)


# ===========================================================================
# 8. THE ONE REFUSAL AND `Tr`'s OWN INVARIANTS.
# ===========================================================================
CALL_MINOR, CALL_DBOFF, CALL_ENABLE, CALL_MINOR1, CALL_IB = 3, 1, 2, 5, 4


def emit_refuse():
  def fails(sd0, idx):
    return 1 if (sd0 >= (5, 0, 0) and idx > 0) else 0
  for sd0, idx, tag in [((4, 4, 2), 0, '44_0_0'), ((4, 4, 2), 1, '44_0_1'), ((5, 0, 0), 0, '50_0_0'),
                        ((5, 0, 0), 1, '50_0_1'), ((5, 0, 0), 4, '50_0_4'), ((6, 0, 0), 0, '60_0_0'),
                        ((6, 0, 0), 7, '60_0_7')]:
    row('amp_refuse_fail_' + tag, fails(sd0, idx))
  def trace(sd0, idx):
    if fails(sd0, idx):
      return []
    db = am.AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0 + ((idx // 4) + (idx % 4) * 4) * 0xA
    return [(CALL_MINOR, 0), (CALL_DBOFF, db * 2), (CALL_ENABLE, db),
            (CALL_DBOFF, db * 2), (CALL_MINOR1, 0), (CALL_IB, 0)]
  for sd0, idx, tag in [((4, 4, 2), 1, '44_0_1'), ((5, 0, 0), 1, '50_0_1'), ((5, 0, 0), 0, '50_0_0'),
                        ((5, 0, 0), 7, '50_0_7'), ((4, 4, 2), 0, '44_0_0')]:
    row('amp_refuse_n_' + tag, len(trace(sd0, idx)))
  brow('amp_refuse_seen_50_0_1', bool(fails((5, 0, 0), 1)))
  brow('amp_refuse_seen_44_0_1', bool(fails((4, 4, 2), 1)))
  for idx, tag in ((1, '50_0_1'), (0, '50_0_0')):
    lrow('amp_refuse_args_' + tag, [a for k, a in trace((5, 0, 0), idx) if k == CALL_ENABLE])
  t = trace((5, 0, 0), 0)
  lrow('amp_refuse_order_50_0_0', [k for k, _ in t])
  lrow('amp_refuse_pairs_50_0_0', [k * 1000 + a for k, a in t])
  row('amp_refuse_ncalls_50_0_0', len(t))
  row('amp_refuse_at_50_0_0', 0)
  db0 = am.AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0
  def has(pat):
    for i in range(len(t) - len(pat) + 1):
      if t[i:i + len(pat)] == pat:
        return True
    return False
  brow('amp_has_fwd', has([(CALL_MINOR, 0), (CALL_DBOFF, db0 * 2), (CALL_ENABLE, db0)]))
  brow('amp_has_rev', has([(CALL_ENABLE, db0), (CALL_DBOFF, db0 * 2), (CALL_MINOR, 0)]))
  brow('amp_has_len0', has([]))
  brow('amp_has_len6', has(t))
  brow('amp_has_len6b', has([(CALL_MINOR, 0), (CALL_DBOFF, db0 * 2), (CALL_ENABLE, db0 + 1),
                             (CALL_DBOFF, db0 * 2), (CALL_MINOR1, 0), (CALL_IB, 0)]))
  brow('amp_has_short', has([(CALL_MINOR, 0), (CALL_DBOFF, db0 * 2)]))
  brow('amp_has_wrongarg', has([(CALL_MINOR, 1), (CALL_DBOFF, db0 * 2), (CALL_ENABLE, db0)]))


def main():
  init_features()
  emit_regs(REG_SEL, collect())
  emit_structs()
  emit_smu()
  emit_pte()
  emit_db()
  emit_kiq()
  emit_ih()
  emit_psp()
  emit_refuse()
  print('\n'.join(out))
  print('ip-done=1')


if __name__ == '__main__':
  main()