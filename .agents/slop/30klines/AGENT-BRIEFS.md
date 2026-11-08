# Agent briefs

Six tracks. They can run in parallel only because the contracts below are fixed first.
Read `SPEC.md` before anything. The mockups in `mock/` are the design source of truth; `design.css`
is the token file, not a sketch.

**Sequencing**

```
week 1   A (shell)  ‖  B (engine + schema)  ‖  C (recorder, Python, independent)
week 2   F (content, first stage)  ‖  D (visualizer)  ‖  C (second fixture)
week 3   E (playground tier 1→2)  ‖  D (remaining adapters)  ‖  F
```

**Shared contract, agreed before track A writes a line**

1. `packages/course-schema` exports `SourceRef`, `Claim`, `Lesson`, `Stage`, `TraceStep` as
   `Schema.Class`. No other package defines these shapes.
2. Every line a learner sees as "covered" comes from `manifest.declared`. Nobody types a number.
3. A visual may not exist without a `TraceStep` id. No hand-drawn graphs, ever.
4. All colour comes from `mock/design.css` tokens. No hex codes in components.

---

## Track A — shell & design system

**Mission.** Make the place feel like a printed lab notebook, and make the ten stages navigable.

**Owns.** `apps/webapp/src/routes/`, `packages/ui/`, `mock/design.css` → real tokens.

**Deliverables.**
- Token package generated from the mock stylesheet; light + dark; no component-level overrides.
- Chrome: top bar, breadcrumb, three-pane lesson frame, transport bar, course map.
- Routes per `SPEC.md §4`, with `?step=` preserved on navigation.
- Keyboard: `space ← → j k g p / ?`.

**Acceptance.**
- `mock/03`, `04`, `06` reproduce at 1600×1000 to within a few pixels using the real components.
- Collapses to one column under 1100px without losing the transport or the source pane.
- Lighthouse ≥ 95 on `/course`; CLS 0; every interactive element reachable by keyboard.
- `prefers-reduced-motion` disables stagger and slide, not content.

**Non-goals.** Do not build a component library. Do not add an icon set. Do not design a second
visual language for the dark playground — it is the same tokens with `data-theme=dark`.

---

## Track B — course engine

**Mission.** Make it impossible to publish a claim that is not true.

**Owns.** `packages/course-schema/`, `packages/course-engine/`, `tools/verify/`.

**Deliverables.**
- The five types, decoders, and a `Lesson` validator that rejects a lesson with no claims.
- `SourceRef.sha` verification: hash the exact lines from `vendor/tinygrad`, compare, fail the build
  with the lesson id and the drift distance.
- `manifest.json`: per-file census, per-stage budget, `declared` line set, coverage fold.
- `bun run verify:refs`, `verify:coverage`, `verify:traces`.
- Progress persistence: local-first (no account), syncable later. Completing a lesson is derivable
  from the URL trail, not a mutable counter.

**Acceptance.**
- Edit one line in `vendor/tinygrad/tinygrad/uop/ops.py`; `verify:refs` fails and names lesson 02.4.
- Hand-edit a number in `manifest.json`; `verify:coverage` recomputes and rejects it.
- `count.py`'s numbers and `manifest.json` agree, or the build fails.

**Non-goals.** No CMS, no database for content, no "approximately right" line ranges. If a ref
cannot be verified, the lesson does not ship.

---

## Track C — the recorder

**Mission.** Produce the traces everything else renders. This is the compiler of the course.

**Owns.** `tools/recorder/`, `traces/`, `fixtures/`.

**Deliverables.**
- `record.py` that runs pinned tinygrad with hooks on `UOpMetaClass.__call__`, `graph_rewrite`,
  `linearize`, `to_program` and emits per-step JSON.
- Eight-line fixture recorded across all ten stages, on `WEBGPU` and on `CPU`.
- Graph diffs with stable node ids across steps.
- A `source` ref on every step.

**Acceptance.**
- Two consecutive runs are byte-identical.
- A step's `before`/`after` reproduces the real graph: replaying the diffs yields the same final
  node set as an unintercepted run.
- Every step names the function and file:line that produced it.
- Trace size per stage < 400 KB uncompressed; the visualizer must stay interactive.

**Non-goals.** Do not invent steps for teaching convenience. If a rewrite is boring, it still gets
recorded — the lesson chooses what to show, the recorder does not.

**Note.** `SPEC > 1` runs a spec check inside `__call__`. Hook around it or disable it, and say which
in the output, because it changes the timing numbers.

---

## Track D — visualizer

**Mission.** One framework, ten adapters, synchronized with the source.

**Owns.** `packages/visualizer/`.

**Deliverables.**
- A `GraphView` that takes `(nodes, edges, layout)` and nothing else.
- ELK layout presets per stage: layered for UOp, clustered for schedule, ranked for linearize.
- Selection sync: source line → nodes → step; and the reverse.
- Before/after diff rendering: added, removed, changed, with the changed edge as the only coloured
  element.
- Step scrubber with the rewrite filmstrip (`mock/03`).

**Acceptance.**
- 300 nodes at 60 fps while scrubbing; layout under 150ms for 500 nodes.
- Clicking a claim in the lesson highlights exactly the nodes that claim's step touched, and no
  others.
- Removing the trace id makes the component refuse to render. It has no fallback data.

**Non-goals.** Do not write a layout algorithm. Do not animate a graph with more than 200 nodes.
Do not add a minimap, a legend panel, or a node inspector until a lesson needs one.

---

## Track E — playground runtime

**Mission.** Let a learner change something and see the machine answer.

**Owns.** `packages/playground/`.

**Phases, strictly in order.**

1. **Fixture mode.** Load a recorded trace, replay it, edit only the *inputs* (shapes, dtypes,
   constants). No compilation in the browser. Ships in week 3.
2. **Subset mode.** A TypeScript port of the UOp core + WGSL emission over a declared op set,
   oracle-diffed against pinned tinygrad across a corpus.
3. **WebGPU dispatch.** Execute the emitted WGSL. Report the real adapter; never fake it.

**Acceptance.**
- Phase 1: editing a shape re-derives from the trace and shows which kernels split differently.
- Phase 2: for every fixture in the corpus, emitted WGSL is byte-identical to upstream's
  `renderer/wgsl.py` output, or the divergence is in a declared allowlist with a reason.
- Phase 2: the capability count is computed from the op table and shown as `n of 75`.
- Phase 3: an unsupported op is refused **by name**, not silently.

**Non-goals.** Do not port `runtime/`. Do not claim Pyodide works. Do not add a "just run it on CPU"
escape hatch that hides a WebGPU failure — the readout names the device that ran.

---

## Track F — content

**Mission.** Write the lessons. This is the long pole and it starts the day the schema lands.

**Owns.** `content/lessons/`, `content/stages/`.

**Deliverables.** Stage 01 and 02 fully: 8 lessons each, every claim with a verified `SourceRef`,
one sentence per line of code, and a stated "what to watch for".

**Rules of writing.**

- One claim = one idea that could be false. "This returns the cached node" is a claim. "This is
  important" is not.
- Prefer the counterfactual: *what would break if this line were deleted?*
- Name the cost. Every design choice in a compiler buys something and pays for something.
- No analogy survives first contact with the code. If a metaphor needs a paragraph of disclaimers,
  cut it.
- The prose tells the learner what to look at; the visual shows the consequence.

**Acceptance.**
- `verify:refs` green; every claim has a kind; no lesson exceeds 7 claims.
- A reader who knows Python but not compilers can do stage 01 without leaving the page.
- Every lesson names the next one and why.

**Non-goals.** Do not write stage 03 before stage 02 is reviewed. The fast-forward only works if the
surface is solid.
