/**
 * examples/beautiful_mnist.ts — the TypeScript twin of examples/beautiful_mnist.py
 *
 * model based off https://medium.com/data-science/going-beyond-99-mnist-handwritten-digits-recognition-cfff96337392
 *
 * SECTION MAP (py line -> ts symbol). Every py line lands in exactly one of these.
 *   py:1-5    imports, getenv, mnist() ....... SEAMS (this header), Constants, getenv, pick()
 *   py:7-16   Model.layers .................... Model.layers, verbatim and in order
 *   py:18     @function ....................... @function_ on Model.__call__
 *   py:19     x.sequential(self.layers) ........ Model.__call__
 *   py:21     @TinyJit ......................... @TinyJit on Model.train_step
 *   py:22     @Context(TRAINING=1) ............. @Context({ TRAINING: 1 }) on Model.train_step
 *   py:23-27  the step body .................... Model.train_step + request(), the flat wire
 *   py:29     @TinyJit ......................... @TinyJit on Model.get_test_acc
 *   py:30     argmax(axis=1)==Y).mean()*100 .... Model.get_test_acc
 *   py:33     mnist(fashion=getenv(...)) ....... pick() over FileSource / FetchSource / SyntheticSource
 *   py:36     Muon / SGD / Adam ............... selectOptimizer
 *   py:38-43  the loop and the loss curve ...... train(), LossCurve, stepLine, printLossCurve
 *   py:40     GlobalCounters.reset() ............... GlobalCounters.reset
 *   py:45-48  the eval-accuracy gate ........... verifyEvalAcc, EvalAccBelowTarget
 *
 * THE WEBGPU WALL -- three seams the browser/WebGPU phase touches, and nothing else.
 *
 *   1. THE WIRE (request()/item()). `sdk.executeTask(data: number[]): number[]` is flat f32 in,
 *      flat f32 out, with no shape, no dtype and no kernel name in its type. So the ABI is spelled
 *      ONCE, here: [op, optimizer, batch, ...pixels, ...labels] -> one scalar, or the logits. Header
 *      then buffers is the Bend v1.1 packet shape (tinygrad/runtime/ops_bend.py, "THE WIRE, v1.1").
 *      A real backend replaces these two functions and nothing above them: nothing above them knows
 *      the layout, so there is no rewrite to do.
 *   2. THE DATA LANE (DataSource). mnist() pulls four gzipped IDX files; node reads them off disk
 *      (FileSource), a browser fetches the same URLs (FetchSource), `--dry` seeds them
 *      (SyntheticSource). Same 28*28 pixels, same labels, whichever lane runs.
 *   3. THE KERNEL TABLE (KERNELS). @register_kernel names every task this example needs, so "what
 *      does the WebGPU phase have to implement" is a printed list rather than tribal knowledge.
 *
 * WHY THIS IS NOT A REWRITE OF py:26-27. py's Tensor does forward + autograd + optimizer inside
 * train_step. Here that body is the Bend task's job, and this file owns exactly the parts that were
 * never Tensor's: the layer stack the task implements, the batch sampler, the loop, the accounting,
 * the curve, and the gate. train_step therefore returns a loss scalar, and get_test_acc keeps the
 * two reductions (argmax, mean) that py:30 spells in Tensor and a browser lane can also do.
 *
 * RUN. node cannot execute this file directly: it strips types, and decorators are not erasable.
 * Build it, then run it:
 *   tsc --strict --experimentalDecorators --target es2022 examples/beautiful_mnist.ts
 *   node <out>/examples/beautiful_mnist.js --dry
 */

import { readFile } from "node:fs/promises"
import { gunzipSync } from "node:zlib"
import { BendLibrarySDK } from "../langs/sdk/bend_sdk"

// **************** constants (py:25,36,42,46) ****************

/** 28*28: the input width py:16 flattens to, and the stride every batch gather walks */
const MNIST_PIXELS = 28 * 28
/** py:16 `nn.Linear(576, 10)` */
const MNIST_CLASSES = 10
/** py:25 `getenv("BS", 512)`, py:39 `getenv("STEPS", 70)`, py:42's hardcoded 10 */
const DEFAULT_BS = 512
const DEFAULT_STEPS = 70
const DEFAULT_EVAL_EVERY = 10
/** py:5, but on disk: where `--source=file` looks for the four gzipped IDX files */
const DEFAULT_MNIST_DIR = "data/mnist"

/** py:36's optimizer choice is wire, not config: it changes which step kernel runs */
type Optimizer = "muon" | "sgd" | "adam"
const OPTIMIZER_ID: Readonly<Record<Optimizer, number>> = { muon: 0, sgd: 1, adam: 2 }
/** py:36 `Muon if getenv("MUON") else SGD if getenv("SGD") else Adam` */
function selectOptimizer(env: getenv): Optimizer {
  if (env.flag("MUON")) return "muon"
  if (env.flag("SGD")) return "sgd"
  return "adam"
}

/** py:26's crossentropy+backward+schedule_step is one task; py:19's forward is the other */
const OP_FORWARD = 1
const OP_TRAIN = 2
/** a forward pass carries no labels; py:19 has no Y either */
const NO_LABELS = new Uint8Array(0)

// **************** getenv (py:5) **************** */

/**
 * py:5's `getenv`, kept under its own name (parity, not idiom) and made a class because it carries
 * state py does not: the browser lane has no process.env. py's truthiness rule is preserved exactly --
 * unset reads as "", so it is falsy, and FASHION=0 is still truthy here as it is there.
 * `--flag`/`--flag=value` layer over the process env so both lanes read the same names: --dry,
 * --steps=N, --bs=N, --eval-every=N, --seed=N, --mnist=<dir>, --source=file|fetch, --fashion, --muon,
 * --sgd, --target-eval-acc-pct=N (py:25,33,36,39,42,46), each spelled with its env var's underscores.
 */
class getenv {
  private readonly vars: Readonly<Record<string, string | undefined>>
  constructor(vars: Readonly<Record<string, string | undefined>>) {
    this.vars = vars
  }
  /** py:5's getenv, plus the `--flag` layer, over one shared variable table */
  static fromProcess(argv: readonly string[]): getenv {
    const vars: Record<string, string | undefined> = { ...process.env }
    for (const arg of argv) {
      if (!arg.startsWith("--")) continue
      const [flag = "", value = "1"] = arg.slice(2).split("=")
      vars[flag.replaceAll("-", "_").toUpperCase()] = value
    }
    return new getenv(vars)
  }
  string(name: string): string {
    return this.vars[name] ?? ""
  }
  flag(name: string): boolean {
    return this.string(name) !== ""
  }
  number(name: string, fallback: number): number {
    const value = this.string(name)
    return value === "" ? fallback : Number(value)
  }
}

// **************** counters (py:40) **************** */

/**
 * py:40's GlobalCounters, which exists so DEBUG=2 timing reads one step rather than the whole run.
 * reset() runs at the top of a step, as in py, so after the loop the pair is the last step's -- which
 * is also the pair worth reporting.
 */
class GlobalCounters {
  forwards = 0
  tasks = 0
  reset(): void {
    this.forwards = 0
    this.tasks = 0
  }
}
const global_counters = new GlobalCounters()

// **************** decorators (py:18,21,22,29) ****************

type MethodDecorator = (target: object, key: string | symbol, descriptor: PropertyDescriptor) => PropertyDescriptor | void
/** the (images, labels) -> scalar shape TinyJit and Context wrap */
type Step = (this: unknown, images: Float32Array, labels: Uint8Array) => number
type Forward = (this: unknown, images: Float32Array) => readonly number[]

/** the tasks this example needs, by name -- the list a WebGPU backend has to implement */
const KERNELS = new Set<string>()
/**
 * py counterpart: a device registers its named kernels once, as
 * `BendDevice(device, HostAllocator, [BendRenderer], BendProgram)` does in
 * tinygrad/runtime/ops_bend.py. Here registration is the name table, and naming one kernel twice is
 * a bug in this file, so it stops the import instead of silently overriding.
 */
function register_kernel(name: string): MethodDecorator {
  if (KERNELS.has(name)) throw new Error(`kernel ${name} is registered twice`)
  KERNELS.add(name)
  return () => undefined
}
/**
 * py:21,29 `@TinyJit` -- capture on the first call, replay after it. TinyJit raises JitError once the
 * args stop matching the capture (`tinygrad/engine/jit.py`, "args mismatch in JIT"), so this does
 * too: shapes are fixed at capture and drift is named rather than quietly re-captured.
 */
function TinyJit(_target: object, key: string | symbol, descriptor: PropertyDescriptor): PropertyDescriptor {
  const inner: Step = descriptor.value
  let captured: string | undefined
  return {
    ...descriptor,
    value: function (this: unknown, images: Float32Array, labels: Uint8Array): number {
      const shape = `${images.length}/${labels.length}`
      if (captured === undefined) captured = shape
      else if (captured !== shape) throw new JitError(key.toString(), captured, shape)
      return inner.call(this, images, labels)
    },
  }
}
/**
 * py:22 `@Context(TRAINING=1)` -- a scoped context variable: named, set for the call, restored after,
 * so everything below it sees it. BatchNorm's batch statistics there, the request header's op here.
 */
const context: Record<string, number> = { TRAINING: 0 }
function Context(vars: Record<string, number>): MethodDecorator {
  return (_target, _key, descriptor) => {
    const inner: Step = descriptor.value
    const was = Object.keys(vars).map((name) => [name, context[name]] as const)
    return {
      ...descriptor,
      value: function (this: unknown, images: Float32Array, labels: Uint8Array): number {
        Object.assign(context, vars)
        try {
          return inner.call(this, images, labels)
        } finally {
          for (const [name, value] of was) context[name] = value
        }
      },
    }
  }
}
/**
 * py:18 `@function` (`tinygrad/function.py`) -- wraps __call__ so the captured work is named and
 * counted when DEBUG is on; that file also tracks depth, and the count is what the curve block reports.
 * Spelled `function_` because `function` is a JavaScript reserved word and cannot be a decorator name:
 * tsc rejects `@function` outright with TS1146, so this is the same name with the wall escaped, not a
 * rename.
 */
function function_(_target: object, _key: string | symbol, descriptor: PropertyDescriptor): PropertyDescriptor {
  const inner: Forward = descriptor.value
  return {
    ...descriptor,
    value: function (this: unknown, images: Float32Array): readonly number[] {
      global_counters.forwards++
      return inner.call(this, images)
    },
  }
}

// **************** errors ****************

/** py:29's JitError: the capture no longer describes the call */
class JitError extends Error {
  readonly key: string
  readonly captured: string
  readonly shape: string
  constructor(key: string, captured: string, shape: string) {
    super(`${key} was captured with ${captured} and called with ${shape}`)
    this.key = key
    this.captured = captured
    this.shape = shape
  }
}
/** the wall where a flat wire could go wrong, raised instead of a silent NaN nobody can trace */
class TaskProtocolError extends Error {
  readonly op: number
  readonly got: readonly number[]
  constructor(op: number, got: readonly number[]) {
    super(`op ${op} returned ${got.length} scalars; the wire promises exactly one`)
    this.op = op
    this.got = got
  }
}
/** a data lane that could not deliver: no file, no network, or a truncated IDX body */
class DataLaneError extends Error {
  readonly file: string
  readonly status: number
  constructor(file: string, status: number) {
    super(`data lane could not read ${file} (status ${status})`)
    this.file = file
    this.status = status
  }
}

// **************** the wire (py:26,27,30) -- SEAM 1 ****************

/** the batch one step runs on: py:25's `X_train[samples], Y_train[samples]` */
interface Batch {
  readonly images: Float32Array
  readonly labels: Uint8Array
}

/**
 * SEAM 1, in: header then batch. Replace this and the callee of sdk.executeTask, and nothing else.
 * The batch count comes from the images, not the labels: py:19's forward pass has no Y at all, so a
 * forward request is the same header with an empty label section.
 */
function request(op: number, optimizer: Optimizer, images: Float32Array, labels: Uint8Array): number[] {
  return [op, OPTIMIZER_ID[optimizer], images.length / MNIST_PIXELS, ...images, ...labels]
}
/** py:30/42/43 `.item()`: the task's answer as a plain number, and the only arity it may answer with */
function item(op: number, out: readonly number[]): number {
  if (out.length !== 1) throw new TaskProtocolError(op, out)
  return out[0]
}

// **************** the model (py:7-30) ****************

/** py:9-16, in order. Declarative on purpose: the schedule that runs it is the task's own body. */
type Layer =
  | { readonly kind: "conv2d"; readonly inChannels: number; readonly outChannels: number; readonly kernel: number }
  | { readonly kind: "relu" }
  | { readonly kind: "batchNorm"; readonly channels: number }
  | { readonly kind: "maxPool2d" }
  | { readonly kind: "flatten" }
  | { readonly kind: "linear"; readonly inFeatures: number; readonly outFeatures: number }

class Model {
  /** py:9-16 */
  readonly layers: readonly Layer[] = [
    { kind: "conv2d", inChannels: 1, outChannels: 32, kernel: 5 },
    { kind: "relu" },
    { kind: "conv2d", inChannels: 32, outChannels: 32, kernel: 5 },
    { kind: "relu" },
    { kind: "batchNorm", channels: 32 },
    { kind: "maxPool2d" },
    { kind: "conv2d", inChannels: 32, outChannels: 64, kernel: 3 },
    { kind: "relu" },
    { kind: "conv2d", inChannels: 64, outChannels: 64, kernel: 3 },
    { kind: "relu" },
    { kind: "batchNorm", channels: 64 },
    { kind: "maxPool2d" },
    { kind: "flatten" },
    { kind: "linear", inFeatures: 576, outFeatures: MNIST_CLASSES },
  ]

  private readonly sdk: BendLibrarySDK
  private readonly optimizer: Optimizer
  constructor(sdk: BendLibrarySDK, optimizer: Optimizer) {
    this.sdk = sdk
    this.optimizer = optimizer
  }

  /** py:19 `x.sequential(self.layers)`; the layer stack above is what this task implements */
  @register_kernel("beautiful_mnist/forward")
  @function_
  __call__(images: Float32Array): readonly number[] {
    return this.execute(OP_FORWARD, images, NO_LABELS)
  }

  /** py:23-27 one step. The batch is py:25; fwd + crossentropy + backward + schedule_step is the task */
  @register_kernel("beautiful_mnist/train_step")
  @TinyJit
  @Context({ TRAINING: 1 })
  train_step(images: Float32Array, labels: Uint8Array): number {
    return item(OP_TRAIN, this.execute(OP_TRAIN, images, labels))
  }

  /** py:30, with only its two reductions in TS: argmax over the 10 logits, then mean of the hits */
  @TinyJit
  get_test_acc(images: Float32Array, labels: Uint8Array): number {
    const logits = this.__call__(images)
    let hits = 0
    for (let i = 0; i < labels.length; i++) {
      let best = 0
      for (let c = 1; c < MNIST_CLASSES; c++) if (logits[i * MNIST_CLASSES + c] > logits[i * MNIST_CLASSES + best]) best = c
      if (best === labels[i]) hits++
    }
    return (hits / labels.length) * 100
  }

  /** every pixel in and every loss out crosses this one call */
  private execute(op: number, images: Float32Array, labels: Uint8Array): readonly number[] {
    global_counters.tasks++
    return this.sdk.executeTask(request(context.TRAINING === 1 ? OP_TRAIN : op, this.optimizer, images, labels))
  }
}

// **************** the data lane (py:6,7,8,33) -- SEAM 2 ****************

/**
 * SEAM 2. py:6 is one fetch plus one gunzip, indexed by py:7-8; as an interface the browser phase
 * swaps the implementation and the loop never learns which lane fed it.
 */
interface DataSource {
  images(): Promise<Float32Array>
  labels(): Promise<Uint8Array>
}

/** py:33's four tensors, grouped the way the loop pulls them: train, then test */
interface Dataset {
  readonly train: DataSource
  readonly test: DataSource
}

/** py:7's `[0x10:]` and `[8:]` -- the IDX header each file opens with */
const IDX_IMAGE_HEADER = 0x10
const IDX_LABEL_HEADER = 8
/** py:5 */
const MNIST_BASE = "https://storage.googleapis.com/cvdf-datasets/mnist/"
const FASHION_BASE = "http://fashion-mnist.s3-website.eu-central-1.amazonaws.com/"

/** py:7-8 after the header. Bytes become f32 the way py leaves them: raw 0..255, no rescale */
function pixels(body: Uint8Array): Float32Array {
  const out = new Float32Array(body.length - IDX_IMAGE_HEADER)
  for (let i = 0; i < out.length; i++) out[i] = body[IDX_IMAGE_HEADER + i]
  return out
}
function digits(body: Uint8Array): Uint8Array {
  return body.slice(IDX_LABEL_HEADER)
}

/** py:6 with the bytes already on disk: node today. Reads the same four gzipped IDX files. */
class FileSource implements DataSource {
  private readonly root: string
  private readonly stem: string
  constructor(root: string, stem: string) {
    this.root = root
    this.stem = stem
  }
  images(): Promise<Float32Array> {
    return this.body(`${this.stem}-images-idx3-ubyte.gz`).then(pixels)
  }
  labels(): Promise<Uint8Array> {
    return this.body(`${this.stem}-labels-idx1-ubyte.gz`).then(digits)
  }
  private async body(file: string): Promise<Uint8Array> {
    return gunzipSync(await readFile(`${this.root}/${file}`))
  }
}

/**
 * py:6 in the browser lane: the same four URLs, over `fetch` and the platform's own gzip. This lane
 * needs no browser -- node carries both globals -- so the seam is checkable from a terminal too.
 */
class FetchSource implements DataSource {
  private readonly base: string
  private readonly stem: string
  constructor(base: string, stem: string) {
    this.base = base
    this.stem = stem
  }
  images(): Promise<Float32Array> {
    return this.body(`${this.stem}-images-idx3-ubyte.gz`).then(pixels)
  }
  labels(): Promise<Uint8Array> {
    return this.body(`${this.stem}-labels-idx1-ubyte.gz`).then(digits)
  }
  private async body(file: string): Promise<Uint8Array> {
    const response = await fetch(this.base + file)
    const stream = response.body
    if (!response.ok || stream === null) throw new DataLaneError(file, response.status)
    const gunzipped = await new Response(stream.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()
    return new Uint8Array(gunzipped)
  }
}

/**
 * The `--dry` lane: seeded, MNIST-shaped, and weakly learnable -- one bright stripe at the sample's
 * own label, noise elsewhere. Purely random pixels with random labels are unlearnable, so a run
 * against them pins the loss at the ln(10) floor and the curve proves nothing; this keeps the same
 * bytes and the same 28*28 shape, with just enough signal for the curve to actually descend.
 */
class SyntheticSource implements DataSource {
  private readonly count: number
  private readonly seed: number
  private drawn: Batch | undefined
  constructor(count: number, seed: number) {
    this.count = count
    this.seed = seed
  }
  images(): Promise<Float32Array> {
    return Promise.resolve(this.draw().images)
  }
  labels(): Promise<Uint8Array> {
    return Promise.resolve(this.draw().labels)
  }
  private draw(): Batch {
    if (this.drawn === undefined) {
      const labels = Uint8Array.from({ length: this.count }, (_, i) => digit(this.seed + i))
      // the noise is a function of the position alone, so it is the SAME in every sample: per-sample
      // noise would be a fingerprint the model can memorize, and the curve would fall without ever
      // generalizing -- which is exactly what a loss curve is supposed to disprove.
      const images = Float32Array.from({ length: this.count * MNIST_PIXELS }, (_, i) => {
        const at = i % MNIST_PIXELS
        return at % MNIST_CLASSES === labels[Math.floor(i / MNIST_PIXELS)] ? 255 : byte(this.seed + at) % 64
      })
      this.drawn = { images, labels }
    }
    return this.drawn
  }
}

/** one lane's factory, over mnist()'s two file stems: `train-` and `t10k-` */
interface Lane {
  readonly name: string
  readonly source: (stem: string) => DataSource
}

/** py:33 with `--source` naming the lane: `--dry` seeds it, `fetch` is the browser lane, `file` is node */
function pick(env: getenv): Lane {
  const seed = env.number("SEED", 0)
  const base = env.flag("FASHION") ? FASHION_BASE : MNIST_BASE
  const root = env.string("MNIST") === "" ? DEFAULT_MNIST_DIR : env.string("MNIST")
  const count = (stem: string): number => (stem === "train" ? env.number("BS", DEFAULT_BS) : 256)
  if (env.flag("DRY")) return { name: "synthetic", source: (stem) => new SyntheticSource(count(stem), seed) }
  if (env.string("SOURCE") === "fetch") return { name: "fetch", source: (stem) => new FetchSource(base, stem) }
  return { name: "file", source: (stem) => new FileSource(root, stem) }
}

// **************** the batch (py:25) ****************

/**
 * py:25 `Tensor.randint(getenv("BS", 512), high=X_train.shape[0])` -- sampled with replacement, and
 * seeded so a run is repeatable. Gathered here rather than inside the task, because the payload
 * carries pixels and labels, not indices.
 */
function sampleBatch(train: Batch, size: number, seed: number): Batch {
  const images = new Float32Array(size * MNIST_PIXELS)
  const labels = new Uint8Array(size)
  const count = train.labels.length
  for (let i = 0; i < size; i++) {
    const at = Math.floor(unit(seed + i) * count)
    labels[i] = train.labels[at]
    images.set(train.images.subarray(at * MNIST_PIXELS, (at + 1) * MNIST_PIXELS), i * MNIST_PIXELS)
  }
  return { images, labels }
}
/** mulberry32: one word of state, no dependency, and the same number for a given seed every run */
function unit(state: number): number {
  let t = (state + 0x6d2b79f5) >>> 0
  t = Math.imul(t ^ (t >>> 15), 1 | t)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
function byte(state: number): number {
  return Math.floor(unit(state) * 256)
}
/** a label is a class index, not a byte: py:26 indexes the 10 logits with it */
function digit(state: number): number {
  return Math.floor(unit(state) * MNIST_CLASSES)
}

// **************** the loss curve (py:38-43) ****************

interface CurveRow {
  readonly step: number
  readonly loss: number
  readonly testAcc: number
}

/** py:38-43: `test_acc = float('nan')` until the first eval, then every line py:43 keeps on screen */
class LossCurve {
  private readonly rows: CurveRow[] = []
  add(step: number, loss: number, testAcc: number): void {
    this.rows.push({ step, loss, testAcc })
  }
  get testAcc(): number {
    return this.rows.length === 0 ? Number.NaN : this.rows[this.rows.length - 1].testAcc
  }
  /** the block: one line per step, in py:43's own format */
  render(): readonly string[] {
    return this.rows.map((row) => stepLine(row.step, row.loss, row.testAcc))
  }
}

/** py:43 `f"loss: {loss.item():6.2f} test_accuracy: {test_acc:5.2f}%"`, with py's own nan */
function stepLine(step: number, loss: number, testAcc: number): string {
  return `step ${String(step).padStart(4)}  loss: ${fixed(loss, 6)}  test_accuracy: ${fixed(testAcc, 5)}%`
}
function fixed(value: number, width: number): string {
  return (Number.isNaN(value) ? "nan" : value.toFixed(2)).padStart(width)
}

/** the printed artifact: py:38-43's curve, as a block */
function printLossCurve(curve: LossCurve): void {
  for (const line of curve.render()) console.log(line)
}

// **************** the loop (py:38-43) ****************

async function load(source: DataSource): Promise<Batch> {
  const [images, labels] = await Promise.all([source.images(), source.labels()])
  return { images, labels }
}

/** py:38-43 */
async function train(model: Model, data: Dataset, env: getenv): Promise<LossCurve> {
  // --dry is one step by default, and evaluates on it: STEPS still wins, so --dry --steps=8 draws a curve
  const steps = env.number("STEPS", env.flag("DRY") ? 1 : DEFAULT_STEPS)
  const every = Math.max(1, env.number("EVAL_EVERY", env.flag("DRY") ? 1 : DEFAULT_EVAL_EVERY))
  const bs = env.number("BS", DEFAULT_BS)
  const seed = env.number("SEED", 0)
  const trainSet = await load(data.train)
  const testSet = await load(data.test)
  const curve = new LossCurve()
  let testAcc = Number.NaN
  for (let i = 0; i < steps; i++) {
    global_counters.reset() // py:40, so a DEBUG=2 timing reads one step
    const batch = sampleBatch(trainSet, bs, seed + i)
    const loss = model.train_step(batch.images, batch.labels)
    if (i % every === every - 1) testAcc = model.get_test_acc(testSet.images, testSet.labels)
    curve.add(i, loss, testAcc)
  }
  return curve
}

// **************** the eval gate (py:45-48) ****************

const GREEN = "\u001b[32m"
const RESET = "\u001b[0m"

/** py:47-48's `raise ValueError(colored(f"{test_acc=} < {target}", "red"))`: the red string became this */
class EvalAccBelowTarget extends Error {
  readonly testAcc: number
  readonly target: number
  constructor(testAcc: number, target: number) {
    super(`testAcc=${testAcc} < ${target}`)
    this.testAcc = testAcc
    this.target = target
  }
}

function verifyEvalAcc(testAcc: number, target: number): void {
  if (target <= 0) return
  if (testAcc >= target && testAcc !== 100.0) console.log(`${GREEN}testAcc=${testAcc} >= ${target}${RESET}`)
  else throw new EvalAccBelowTarget(testAcc, target)
}

// **************** entrypoint (py:32-48) ****************/

async function main(): Promise<void> {
  const env = getenv.fromProcess(process.argv.slice(2))
  const sdk = new BendLibrarySDK()
  sdk.init({ forceJS: env.flag("DRY") })
  const lane = pick(env)
  const data: Dataset = { train: lane.source("train"), test: lane.source("t10k") }
  const curve = await train(new Model(sdk, selectOptimizer(env)), data, env)
  console.log(`backend ${sdk.backend}  lane ${lane.name}  kernels ${[...KERNELS].join(", ")}`)
  console.log(`last step: ${global_counters.forwards} forward, ${global_counters.tasks} task`)
  printLossCurve(curve)
  verifyEvalAcc(curve.testAcc, env.number("TARGET_EVAL_ACC_PCT", 0))
}

main().catch((error: unknown) => {
  console.error(error)
  process.exitCode = 1
})
