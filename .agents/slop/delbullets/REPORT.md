# delbullets REPORT — the audit's 12 DELETABLE, re-derived and re-classified

**Subject:** `.agents/slop/bullets/REPORT.md`'s DELETABLE set (12 bullets of `AGENTS.md`), the set the
audit called *"unfalsifiable prescription — advice/taste/preference"* and never actioned.
**Read-only:** `AGENTS.md` was NOT edited; no commit; no `bend`; `.venv/bin/python` only.
**Date:** 2026-10-06. **Run from** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.

---

## 1. Re-derivation of the count

The audit's rule, read from `.agents/slop/bullets/REPORT.md` §1–§3: population = `^ *- ` bullets with
tables excluded = **38**; of these **24 carry NEITHER a case-insensitive `measured` token NOR a
`(checks|gates)/*.py` / `file:line` instrument**. The 24 split as **11 MEASURED + 12 DELETABLE + 1
UNVERIFIABLE** (`REPORT.md:109-111`, arithmetic `11 + 12 + 1 = 24` reproduced).

DELETABLE set as the audit names it (`REPORT.md:116`): **L15, L16, L17, L18, L19, L215, L227, L228,
L229, L230, L231, L232** — count them: `15,16,17,18,19` = 5, `+215` = 6, `+227..232` = 12.

**I reproduce the number 12.** `REPLACEMENTS.md` splits the same 24 as *"DELETABLE (12) /
UNVERIFIABLE (1)"* (`REPLACEMENTS.md:8`); its MEASURED list is 11 OLD/NEW pairs (`REPLACEMENTS.md` §1–§11),
and `11 + 12 + 1 = 24`. Consistent.

**Line numbers are stale.** The audit read a **428-line** `AGENTS.md`; today's is **452 lines**
(`wc -l AGENTS.md` = 452) because other units applied replacements. So `old L` → `current L` shifts.
All `file:line` below are **current**.

---

## 2. Each of the 12, decided — 11 DIRECTIVE · 1 CLAIM+MEASURABLE · 0 CLAIM+DELETABLE

Outcome rule (the orchestrator's, not the audit's): the file's own header scopes the
measurement-or-delete rule to *"EVERY PRESCRIPTION BELOW THAT MAKES A CLAIM ABOUT THIS TREE"*. So:

- **DIRECTIVE** — instructs an agent, asserts nothing about the tree → **needs no measurement; KEEP**.
- **CLAIM + MEASURABLE** — asserts something about the tree, and a command settles it → **KEEP, add the number**.
- **CLAIM + DELETABLE** — asserts about the tree, unmeasurable, and is advice → delete.

| current | old L | exact text (abbreviated) | outcome | evidence |
|---|---|---|---|---|
| 16 | 15 | "use concise, clean code. No hacks… paragraph-long comment… Find a better way." | **DIRECTIVE** | Style instruction; no proposition about the tree. The audit's own what-is-lost cell admits *"not a tree claim."* |
| 17 | 16 | "Security is above all… then effectful, fast, pretty." | **DIRECTIVE** | Priority ordering; nothing asserted about the repo. Audit cell: *"taste."* |
| 18 | 17 | "Shareable logic should be reused… Hoist up…" | **DIRECTIVE** | DRY reminder; no claim. |
| 19 | 18 | "Use Jiujitsu version control… commit often… use the jj mcp." | **DIRECTIVE** | Process instruction. (The trailing "you have access to the jj mcp" is a tool-availability aside, satisfied by the harness's `jj` MCP tools.) Not a tree claim. |
| 20 | 19 | "…Markdown files to track agent state… under .agents/slop/" | **DIRECTIVE** | Placement instruction; no claim. |
| 240 | 215 | "tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. Do not insert the unneeded kernel modules." | **CLAIM + MEASURABLE** | The first sentence is a claim about vendored `tinygrad/`; **measurable and TRUE** — see §3. |
| 252 | 227 | "Highly prefer E2E tests… produce a verifiable and repeatable artifact." | **DIRECTIVE** | Testing preference/process. Audit cell: *"taste/process."* |
| 253 | 228 | "If you must test… FIRST write all the ways it could fail, THEN the code." | **DIRECTIVE** | Process ordering. |
| 254 | 229 | "Tautological tests considered harmful." | **DIRECTIVE** | Value judgment, no tree claim. |
| 255 | 230 | "Change-detector tests considered harmful." | **DIRECTIVE** | Value judgment, no tree claim. |
| 256 | 231 | "Do not create regression tests… without a genuine gap…" | **DIRECTIVE** | Process rule. |
| 257 | 232 | "Inject time instead of sleeping…" | **DIRECTIVE** | Design rule. |

**Counts (rule: outcome per the table above, population = the audit's 12):**

| outcome | count | of 12 |
|---|---|---|
| DIRECTIVE (audit wrong — no measurement needed) | **11** | of 12 |
| CLAIM + MEASURABLE (audit wrong — it IS measurable) | **1** | of 12 |
| CLAIM + DELETABLE (delete) | **0** | of 12 |

**The audit was wrong on all 12.** Its DELETABLE class conflated *"directive"* with *"unfalsifiable
claim"*: it classified by *"can I attach a number?"* rather than *"does it assert anything about the
tree?"*. **A directive needs no number; deleting it removes guidance, not an untrustworthy claim.**
This is the one insight worth more than a tidier file: *the header's rule is about claims, and 11 of
the audit's 12 "deletables" are not claims.*

---

## 3. The one measurable claim: L240 (PCI drivers) — verified TRUE

Claim: *"tinygrad has user space PCI drivers for AMD and NVIDIA GPUs."*

Commands (`.venv` not involved; `rg` on PATH):

```
rg -l 'PCIDevice' tinygrad/            -> 8 files
rg -n '^class (PCIDevice|USBPCIDevice|RemotePCIDevice)' tinygrad/runtime/support/system.py
  206:class PCIDevice:
  270:class USBPCIDevice(PCIDevice):
  385:class RemotePCIDevice(PCIDevice):
rg -n 'PCIIfaceBase|USBPCIDevice' tinygrad/runtime/ops_amd.py tinygrad/runtime/ops_nv.py
  ops_amd.py:738:class PCIIface(PCIIfaceBase):
  ops_amd.py:818: ... USBPCIDevice("AM", *visible[dev_id]) ...
  ops_nv.py:531:class PCIIface(PCIIfaceBase):
rg -n 'from tinygrad.runtime.support.system import PCIDevice' tinygrad/runtime/support/nv/nvdev.py
  7:from tinygrad.runtime.support.system import PCIDevice
```

`tinygrad/runtime/support/system.py:206` defines the userspace `PCIDevice` (mmap of BARs via
`/dev/vfio`, `pci_scan_bus`); **AMD** (`ops_amd.py`) and **NVIDIA** (`ops_nv.py` + `support/nv/nvdev.py`)
both consume it. So the sentence is **true and measurable**, and the bullet is **CLAIM + MEASURABLE**,
not DELETABLE. Replacement text is in `DELETE.md`.

Note: this also corrects the audit's rationale — it wrote the line is *"advice about upstream, not a
claim about this tree"* (`REPORT.md:88`). `tinygrad/` is **vendored inside this repo** (the same tree
`AGENTS.md:228-239` pins at `ad117c928^:tinygrad/uop/ops.py`), so a claim about `tinygrad/` is a claim
about this tree, and the directive it carries ("do not insert the unneeded kernel modules") stays.

---

## 4. The L18 / L19 redundancy flag — does NOT reproduce

The audit's finding 7 (`REPORT.md:145-147`): L18 (Jiujitsu) and L19 (markdown-under-slop) are
*"redundant with the harness instructions at the top of every session"*, so deleting them loses
nothing. **I could not reproduce a second witness.**

- `rg -l -i 'jiujitsu' --hidden --glob '!*.git*' .` → **`AGENTS.md` and `.agents/slop/bullets/REPORT.md`
  only** (the second is the audit quoting the first).
- No global instruction file exists: `~/.config/opencode/` has no `.md`;
  `rg -l -i 'jiujitsu' ~/.config` → nothing; the session's OpenCode `# Harness` block contains no
  such rule.

**Conclusion: the "harness witness" the audit saw was the injected copy of `AGENTS.md` itself** —
one witness counted twice, the exact failure `AGENTS.md:21` names (*"A DOCUMENT RESTATING A DOCUMENT
IS ONE WITNESS, NOT TWO"*). **The flag does not hold; deleting current L19/L20 loses the only copy.**
If the orchestrator sees the identical text in its harness *outside* `AGENTS.md`, the flag stands —
but that is not reproducible from this tree or config, so I did not include them in any deletion list.

---

## 5. Deliverables and non-actions

- `.agents/slop/delbullets/DELETE.md` — **empty deletion list** (0 CLAIM+DELETABLE), with the exact
  current text of all 12 (tagged KEEP) and the paste-ready L240 replacement.
- Nothing was deleted; `AGENTS.md` untouched; no commit.

## 6. Instruments used (all read-only)

| what | command |
|---|---|
| current bullet lines | `rg -n '^ *- ' AGENTS.md` |
| file length | `wc -l AGENTS.md` (= 452) |
| PCI claim | `rg -l 'PCIDevice' tinygrad/`; `rg -n '^class …' tinygrad/runtime/support/system.py`; `rg -n 'PCIIfaceBase|USBPCIDevice' tinygrad/runtime/ops_amd.py tinygrad/runtime/ops_nv.py` |
| second witness | `rg -l -i 'jiujitsu' --hidden --glob '!*.git*' .`; `rg -l -i 'jiujitsu' ~/.config` |
