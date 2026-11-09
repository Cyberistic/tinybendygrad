// ../../../packages/course-voice/src/track.ts
var clamp01 = (n) => n < 0 ? 0 : n > 1 ? 1 : n;
function indexAt(t, ms) {
  let lo = 0;
  let hi = t.beats.length - 1;
  while (lo < hi) {
    const mid = lo + hi + 1 >> 1;
    if (t.beats[mid].start <= ms)
      lo = mid;
    else
      hi = mid - 1;
  }
  return lo;
}
function positionAt(t, ms) {
  if (t.beats.length === 0)
    return;
  const index = indexAt(t, ms);
  const beat = t.beats[index];
  const span = Math.max(beat.end - beat.start, 0.000001);
  return {
    beat,
    index,
    progress: clamp01((ms - beat.start) / span),
    remaining: Math.max(beat.end - ms, 0)
  };
}
// data.json
var data_default = {
  lesson: {
    id: "02.4",
    stage: "02",
    order: 4,
    kind: "line",
    title: "the UOp is a singleton",
    summary: "Fifteen lines that make equality free, and every graph algorithm after them simple.",
    minutes: 6,
    refs: [
      {
        file: "tinygrad/uop/ops.py",
        start: 181,
        end: 194,
        sha: "f7371d2cfe8f0736520625a0d27412a537c94de523a252cb7f9e1c8e622d144f",
        lines: [
          "class UOpMetaClass(type):",
          "  ucache:dict[tuple, weakref.ReferenceType[UOp]] = {}",
          "  def __call__(cls, op:Ops, src:tuple[UOp,...]=tuple(), arg:Any=None):",
          "    # NOTE: the key must separate nodes of different dtype: a CONST's dtype is the type of its arg, and True == 1 as dict keys",
          "    if (wret:=UOpMetaClass.ucache.get(key:=(op, src, arg, type(arg)), None)) is not None and (ret:=wret()) is not None: return ret",
          "    UOpMetaClass.ucache[key] = weakref.ref(created:=super().__call__(op, src, arg))",
          "    if SPEC > 1:",
          "      from tinygrad.uop.spec import spec_full",
          "      if SPEC > 2:",
          "        # SPEC=3 checks the shape",
          "        _ = created._shape",
          "      with Context(CHECK_OOB=0): fret = cast(bool|None, spec_full.rewrite(created))",
          '      if fret is not True: raise RuntimeError(f"SPEC ISSUE {fret}: {created}")',
          "    return created"
        ]
      }
    ],
    claims: [
      {
        id: "02.4.1",
        ref: 0,
        kind: "effect",
        lines: [
          184
        ],
        text: "The cache key is (op, src, arg, type(arg)) — four things, no identity. And type(arg) is there because True == 1 as a dict key, so a CONST's dtype would otherwise collide with a different node."
      },
      {
        id: "02.4.2",
        ref: 0,
        kind: "trap",
        lines: [
          184
        ],
        text: "A hit must return a live object. The weakref may have died, so the check is `is not None` twice: the entry exists, and the referent exists. Returning a dead pointer is a crash, not a miss."
      },
      {
        id: "02.4.3",
        ref: 0,
        kind: "cost",
        lines: [
          185
        ],
        text: "A miss stores a weak reference before the constructor returns. Drop every Tensor and the graph frees itself. No global registry, no shutdown step, no leak."
      },
      {
        id: "02.4.4",
        ref: 0,
        kind: "effect",
        lines: [
          186,
          187,
          188,
          189,
          190,
          191,
          192,
          193
        ],
        text: "The SPEC block runs only when SPEC > 1, and it runs on the freshly created node. It is a debug validator bolted into the constructor, not part of the semantics."
      },
      {
        id: "02.4.5",
        ref: 0,
        kind: "reason",
        lines: [
          194
        ],
        text: "return created, on both paths. From here on `is` is equality, so the pattern matcher, the scheduler and the linearizer are all allowed to compare nodes by pointer."
      }
    ],
    beats: [
      {
        id: "b1",
        text: "Everything in this compiler compares nodes. If comparison means walking two trees, every rewrite is quadratic. So tinygrad makes equal nodes identical, and equality becomes a pointer compare.",
        cue: {
          claims: [
            "02.4.5"
          ]
        },
        direction: "no highlight yet; frame the problem"
      },
      {
        id: "b2",
        text: "This runs before any UOp exists. It is a metaclass, so every construction goes through call. It builds a key: op, src, arg, and the type of arg. Four things, no identity.",
        cue: {
          claims: [
            "02.4.1"
          ],
          lines: [
            181,
            184
          ]
        },
        direction: "highlight the class line, then the key"
      },
      {
        id: "b3",
        text: "Why the type of arg? Because True equals one as a dict key. Without it, a constant storing True and a constant storing one are the same node. The comment says this. It is the kind of bug that would take a day to find.",
        cue: {
          claims: [
            "02.4.1"
          ],
          lines: [
            183,
            184
          ]
        },
        direction: "read the comment aloud"
      },
      {
        id: "b4",
        text: "A hit has to return something alive. The cache holds a weak reference, so the entry can outlive the node. Two checks, not one: the slot exists, and the referent still exists. A dead pointer here is a crash, not a miss.",
        cue: {
          claims: [
            "02.4.2"
          ],
          lines: [
            184
          ]
        },
        direction: "underline the nested is-not-None"
      },
      {
        id: "b5",
        text: "A miss constructs the node, then stores a weak reference to it. Which means: drop every Tensor and the graph collects itself. There is no registry to clean up and no shutdown path to get wrong.",
        cue: {
          claims: [
            "02.4.3"
          ],
          lines: [
            185
          ]
        },
        direction: "trace the assignment"
      },
      {
        id: "b6",
        text: "The SPEC block is a validator, not semantics. It only runs when the flag is above one, and it runs on the node that already exists. Useful, but not part of the story.",
        cue: {
          claims: [
            "02.4.4"
          ],
          lines: [
            186,
            193
          ]
        },
        direction: "dismissive, move past quickly"
      },
      {
        id: "b7",
        text: "And return created on both paths. That is it. Fifteen lines, and every algorithm after this is allowed to be simple.",
        cue: {
          claims: [
            "02.4.5"
          ],
          lines: [
            194
          ]
        },
        direction: "land it"
      }
    ]
  },
  timeline: {
    lesson: "02.4",
    mode: "clips",
    audio: null,
    duration: 78.622,
    gap: 0.18,
    verified: true,
    draft: true,
    voice: "Samantha",
    beats: [
      {
        id: "b1",
        start: 0,
        end: 11.665
      },
      {
        id: "b2",
        start: 11.845,
        end: 24.161
      },
      {
        id: "b3",
        start: 24.341,
        end: 36.534
      },
      {
        id: "b4",
        start: 36.714,
        end: 50.294
      },
      {
        id: "b5",
        start: 50.474,
        end: 61.268
      },
      {
        id: "b6",
        start: 61.448,
        end: 71.48
      },
      {
        id: "b7",
        start: 71.66,
        end: 78.622
      }
    ]
  },
  clips: [
    {
      id: "b1",
      src: "b1.m4a"
    },
    {
      id: "b2",
      src: "b2.m4a"
    },
    {
      id: "b3",
      src: "b3.m4a"
    },
    {
      id: "b4",
      src: "b4.m4a"
    },
    {
      id: "b5",
      src: "b5.m4a"
    },
    {
      id: "b6",
      src: "b6.m4a"
    },
    {
      id: "b7",
      src: "b7.m4a"
    }
  ]
};

// app.ts
var lesson = data_default.lesson;
var timeline = data_default.timeline;
var clips = data_default.clips;
var clipOf = new Map(clips.map((c) => [c.id, c.src]));
var $ = (sel) => document.querySelector(sel);
var el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls)
    n.className = cls;
  if (text !== undefined)
    n.textContent = text;
  return n;
};
function linesFor(beat) {
  const out = new Map;
  const add = (refIdx, line) => {
    const key = lesson.refs[refIdx].file;
    if (!out.has(key))
      out.set(key, new Set);
    out.get(key).add(line);
  };
  if (beat.cue?.lines?.length) {
    for (const n of beat.cue.lines)
      add(0, n);
  }
  for (const cid of beat.cue?.claims ?? []) {
    const claim = lesson.claims.find((c) => c.id === cid);
    if (!claim)
      continue;
    for (const n of claim.lines)
      add(claim.ref, n);
  }
  return out;
}
var index = 0;
var playing = false;
var audio = new Audio;
function renderSources() {
  const host = $("#sources");
  host.innerHTML = "";
  lesson.refs.forEach((ref, i) => {
    const block = el("section", "ref");
    const head = el("header", "refhead");
    head.append(el("span", "path", ref.file), el("span", "range", `${ref.start}–${ref.end}`));
    const code = el("div", "code");
    ref.lines.forEach((text, n) => {
      const row = el("div", "row");
      row.dataset.file = ref.file;
      row.dataset.line = String(ref.start + n);
      row.dataset.ref = String(i);
      row.append(el("span", "ln", String(ref.start + n)), el("span", "ct", text || " "));
      code.append(row);
    });
    block.append(head, code);
    host.append(block);
  });
}
function paint(i) {
  index = Math.max(0, Math.min(i, lesson.beats.length - 1));
  const beat = lesson.beats[index];
  const want = linesFor(beat);
  for (const row of document.querySelectorAll(".row")) {
    const on = want.get(row.dataset.file)?.has(Number(row.dataset.line));
    row.classList.toggle("on", !!on);
  }
  for (const [n, item] of beatItems.entries())
    item.classList.toggle("cur", n === index);
  const claims = (beat.cue?.claims ?? []).map((id) => lesson.claims.find((c) => c.id === id)).filter(Boolean);
  $("#claim").innerHTML = claims.map((c) => `<p><b>${c.kind}</b> ${c.text}</p>`).join("");
  $("#said").textContent = beat.text;
  $("#beatno").textContent = `${index + 1} / ${lesson.beats.length}`;
  const pos = positionAt(timeline, timeline.beats[index]?.start ?? 0);
  if (pos)
    $("#progress").value = String(pos.progress);
  $("#tracklabel").textContent = beat.id;
  const src = clipOf.get(beat.id);
  if (src && audio.src !== new URL(src, location.href).href)
    audio.src = src;
}
function play() {
  playing = true;
  document.body.classList.add("playing");
  audio.play().catch(() => {
    playing = false;
  });
}
function pause() {
  playing = false;
  document.body.classList.remove("playing");
  audio.pause();
}
audio.onended = () => index + 1 < lesson.beats.length ? (paint(index + 1), playing && play()) : pause();
$("#play").onclick = () => playing ? pause() : play();
$("#next").onclick = () => {
  paint(index + 1);
  if (playing)
    play();
};
$("#prev").onclick = () => {
  paint(index - 1);
  if (playing)
    play();
};
addEventListener("keydown", (e) => {
  if (e.code === "Space") {
    e.preventDefault();
    playing ? pause() : play();
  }
  if (e.key === "ArrowRight") {
    paint(index + 1);
    if (playing)
      play();
  }
  if (e.key === "ArrowLeft") {
    paint(index - 1);
    if (playing)
      play();
  }
});
var beatItems = new Map;
function renderBeats() {
  const host = $("#beats");
  lesson.beats.forEach((b, i) => {
    const item = el("button", "beat");
    item.append(el("span", "bi", b.id), el("span", "bt", b.text.slice(0, 64) + "…"));
    item.onclick = () => {
      paint(i);
      if (playing)
        play();
    };
    beatItems.set(i, item);
    host.append(item);
  });
}
renderSources();
renderBeats();
$("#title").textContent = lesson.title;
$("#id").textContent = lesson.id;
$("#summary").textContent = lesson.summary;
var deep = new URLSearchParams(location.search).get("beat");
paint(deep ? Math.max(0, lesson.beats.findIndex((b) => b.id === deep)) : 0);
