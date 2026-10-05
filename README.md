TinyBendyGrad: An experimental slopfork (slop-port?) of tinygrad from Python to [bend](https://github.com/bendlang/bend), where spec is written as proofs and laws, because why can't a DSP-style turing-incomplete IR be lean-complete and formally verifiable? :)

If you're not familiar, tinygrad is expertly written by humans over the last ~5 years, with strict rules against AI code usage. An ironical consequence of it being _tiny_ and _beautiful_ is that a clanker can _bend_ (haha) it into shape in any language within a few hours. The entirty of tinygrad can _almost_ fit into the context window! The antimatter of the tinygrad no-AI philosophy: a _bendygrad_ that is _tiny_, _inhumane_, and _provably correct_.
(edit: I'm almost one week in, this did NOT take a few hours. clankers are stupid.)


For fun, experimentation, and skills. Most code is slop. The logic behind verifiable proofs of spec live in `spec/` (to be rewritten by a mere human eventually). The interpertation of said spec by the robots lives in `.agemts/slop/`. Use tinygrad instead. tinygrad good. I like tinygrad. 


## more yaps

tinygrad in python does not make sense. tinygrad is pure category theory. One could say, tinygrad is inherently monoidal. Kernel fusion utilizes monoidal coherence for uops (associative, with identity, and thus are • bifunctor creating symmetric structural maps). Reduce ops is the 101 of pentagon identity. All tensors follow the lazy/writer moand pattern (If a monoidal category represents the space of tensors and operations, the monad is the mechanism tinygrad uses to build, sequence, and delay the execution of that space); in the sense that if you instantiate a tensor or call an operation, tinygrad returns a lazy DAG. The dx is injecting values into a monadic context (e.g. `x = Tensor([1.0, 2.0, 3.0])`), where you sequence (as in, bind!) operations (e.g. `y = x.exp().log2().sum() `) while inherently maintaining the context through the DAG (forgetful-to-free functor? idk). You see where I'm going with this? `.realize()` is the monad escape (collapsing the monad graph). The DSP nature of it (with it being SSA) makes it, in a way, _affine_; this is especially highlighted in the `shapetracker` where it translates indices using strided, linear (affine!) transformations. Even if we do _not_ necessarily need a functional programming language for tinygrad, thinking about it and aligning with category theory terminology makes us not reinvent patterns and discover pre-estbalished identities. For example, the rewriter applies basic algebra idempotence, composition, annihilation patterns, and hands it over to the combinatorial adjunction (a beam planner is just syntactic (uop combinations) vs metric (hardware) space adjunction). I can yap about this all day, just thinking about what else you can map, you can see all different patterns such as beam  monotonicity (perf is posets towards a global optimal), topological monoid (literally toposort), functorial consistency (per-device binfunctors in placement to transfer), to morphism (lowering)..  after all, tinygrad is inherently monoidal.

if only there was a typed, affine, proof-based language which utilizes all of these properties while (kinda) keeping the syntax of python :)



## even more yaps

yeah yeah speed doesn't matter for generating the graph, but it does feel good to get OOM's of speed. like I ported sz.py to sz.bend and it's almost x3 faster? 
also bend compiles to both C and js, and through C you can use the headers and basically port tinygrad to any language you want? can even do WASM and basically run it anywhere. 
after the port, my next objective is to port tinybendygrad to python (exercising my free will and wasting tokens). 
also of course typescript through js and through emscripten (wasm)
you can just do things
I love AI



