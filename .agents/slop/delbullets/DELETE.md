# DELETE — `AGENTS.md` lines to remove (CLAIM + DELETABLE)

**ANSWER: EMPTY. 0 lines.** None of the audited 12 DELETABLE bullets is a CLAIM + DELETABLE
(an unmeasurable assertion about this tree). **11 are DIRECTIVE and 1 is CLAIM + MEASURABLE** — see
`REPORT.md` §2 for the evidence. **The audit was wrong on all 12, so there is nothing for the
orchestrator to delete.**

Rule that produced this: outcome is **CLAIM + DELETABLE** only if the bullet (a) asserts something
about this tree, (b) cannot be measured by any command I could find, and (c) is advice. A line that
*instructs an agent and asserts nothing* is a **DIRECTIVE** and is out of scope of the file's own
header rule (*"EVERY PRESCRIPTION BELOW THAT MAKES A CLAIM ABOUT THIS TREE CARRIES THE MEASUREMENT"*).

---

## The 12, with exact current text — every one is KEEP, none is a delete

Line numbers are **current** (`AGENTS.md` is 452 lines today; the audit's numbers were against a
428-line revision and are stale). `old L` = the audit's line.

| current | old L | class | exact text |
|---|---|---|---|
| 16 | 15 | DIRECTIVE | `- You must use concise, clean code. No hacks should be used. If you need to write a paragraph-long comment to justify your code, you are doing it wrong. Find a better way.` |
| 17 | 16 | DIRECTIVE | `- Security is above all. Always make it secure (typesafe, fail-safe, auth), then make it work and effectful (effectjs), then make it fast, then make it pretty.` |
| 18 | 17 | DIRECTIVE | `- Shareable logic should be reused. Avoid copy-pasting code. Hoist up if it's needed elsewhere.` |
| 19 | 18 | DIRECTIVE | `- Use Jiujitsu version control for all your code. Make sure to commit often and write meaningful commit messages. If you launch multiple agents, use jiujitsu workspaces to manage them. If you are unsure about how to use Jiujitsu, ask for help. You have access to the jj mcp.` |
| 20 | 19 | DIRECTIVE | `- If you need to create Markdown files to track agent state, always place them under .agents/slop/` |
| 240 | 215 | **CLAIM + MEASURABLE** | `- tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. Do not insert the unneeded kernel modules.` |
| 252 | 227 | DIRECTIVE | `- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.` |
| 253 | 228 | DIRECTIVE | `- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.` |
| 254 | 229 | DIRECTIVE | `- Tautological tests considered harmful.` |
| 255 | 230 | DIRECTIVE | `- Change-detector tests considered harmful.` |
| 256 | 231 | DIRECTIVE | `- Do not create regression tests for bug fixes without a genuine gap in behavior testing.` |
| 257 | 232 | DIRECTIVE | `- Inject time instead of sleeping: production code needing "now" takes it as a parameter, so tests pass a deterministic value instead of faking timers.` |

## The one REPLACEMENT to apply (not a deletion) — L240

**OLD** (current `AGENTS.md:240`, quoted exactly):

```
- tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. Do not insert the unneeded kernel modules.
```

**NEW** (paste-ready; adds the measurement the header demands, keeps the directive):

```
- tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. **MEASURED: `rg -l 'PCIDevice' tinygrad/` = 8 files; the `PCIDevice` class is at `tinygrad/runtime/support/system.py:206` (with `USBPCIDevice` and `RemotePCIDevice`), and both `tinygrad/runtime/ops_amd.py:738` and `tinygrad/runtime/ops_nv.py:531` define `PCIIface(PCIIfaceBase)`.** Do not insert the unneeded kernel modules.
```

## The L18 / L19 "redundant with the harness" flag — DOES NOT HOLD on available evidence

Reason: **I cannot find a second witness.** The audit (`REPORT.md` §4.7) claimed L18 (Jiujitsu) and
L19 (markdown under `.agents/slop/`) are *"also present in the injected harness instructions at the
top of every session"*, so deleting them loses nothing. **Measured: the only live file that mentions
`jiujitsu` is `AGENTS.md` itself** (`rg -l -i 'jiujitsu' --hidden --glob '!*.git*' .` →
`AGENTS.md`, `.agents/slop/bullets/REPORT.md`; the second is the audit quoting the first). There is
no global instruction file: `~/.config/opencode/` holds no `.md`; `rg -l -i 'jiujitsu' ~/.config`
→ nothing. The OpenCode harness block in this session (`# Harness`) contains no such rule.

So the "harness" witness the audit saw was, on the evidence, **the injected copy of `AGENTS.md`
itself** — one witness counted twice, which is exactly the error `AGENTS.md:21` names
(*"A DOCUMENT RESTATING A DOCUMENT IS ONE WITNESS, NOT TWO"*). **Deleting L19/L20 loses the only
copy. Do not delete them on the redundancy ground.** (If the orchestrator can see the same text in
its own harness *outside* `AGENTS.md`, the flag stands and deletion is free — but that is not
reproducible from this tree or config.)
