# Reproducing the floating-point benchmark work

Five repositories, pinned at exact commits, and the machine to run them on.
This one holds no code of its own: it is the entry point, the pins, and a
driver thin enough to read.

    git clone --recurse-submodules https://github.com/aytey/fp-repro
    cd fp-repro
    make help

## What the pieces are

| | |
| --- | --- |
| `src/klee` | KLEE 3.2 with klee-float's floating-point support forward-ported onto it, plus STP and Bitwuzla backends and a solver-independent SMT-LIB printer. This is the executor. |
| `src/fp_bench` | Nineteen driver sets over fifteen builds of eleven numerical libraries, at binary16, 32, 64 and 128. Generates the drivers from each library's own headers, builds it to bitcode, runs it under KLEE and dumps the queries. `SELECTION.md` records why these libraries and not the sixteen others surveyed. |
| `src/corpus` | 34,268 captured queries in six sets, and the tools that made them: capture, inventory, curation, and the checks that gate them. Its README is the corpus's own record, including the biases. |
| `src/bench` | The replay harness: runs solver configurations over a corpus, three repetitions with revalidation, and 27 campaign configs. `campaigns/` holds the campaigns as they were actually run. |
| `src/stp` | STP at a master commit carrying the floating-point theory and the C API KLEE's builder calls. |

`VERSIONS.md` says what each pin is and which of them you cannot move.

## Two ways to get a machine

**The container** — `make image`, then `make shell`. It builds LLVM 16, an STP
with SymFPU, Bitwuzla, Z3 and klee-uclibc into one image.
**It has not been built or tested**: the machine it was written on had no
container runtime. The recipes inside it are the ones that worked natively, but
expect to debug the first build. `docker/Dockerfile` says so at the top.

**Natively** — you need LLVM and clang 16 (13–16 works, 17+ compiles and cannot
execute), Bitwuzla, and a Python environment with `wllvm`. Then:

```sh
make stp klee test      # STP from the pin, then KLEE, then KLEE's own suite
```

`make stp` builds the pinned STP with SymFPU, which is what supplies the
floating-point theory and the `vc_fp*` C API KLEE's builder calls. Pointing
`STP_DIR` at an STP you already have works only if it is new enough — an older
one fails to compile the KLEE pin with `FP_ABSTRACTION was not declared`, which
names the symbol and not the cause. `test/Floats` is 83 tests and passes at the
pinned commit. Put your paths in `local.mk`; `LLVM_PREFIX` is required, and everything else about LLVM is derived from it — the runtime has to be compiled by the clang that matches, or LLVM 16's `llvm-ar` rejects its own runtime archive.

## The five steps, and what each costs

```sh
make libs    LIB=f2clapack-f64     # fetch, build to bitcode, generate drivers
make capture LIB=f2clapack-f64     # run under KLEE, dump every query it asks
make curate                        # inventory, de-duplicate, sample, check
make verify  LIB=f2clapack-f64 DRV=dgecon_   # differential-check the printer
make replay  CONFIG=configs/fp_abstraction_v6.yaml
```

`make libs` is the slow one and the one that goes wrong: each library is fetched
and built with a bitcode-preserving compiler, some need patches, and the working
area runs to tens of GB. `fp_bench`'s README documents every environment
variable it reads and what has to be on the machine first. Building all fifteen
is a day's work; one library is minutes.

`make capture` as written is one library under one solver. The four-arm capture
that produced the shipped corpus is `make capture-all-arms`, which runs every
driver under STP exact, STP with the floating-point abstraction, STP with both
abstractions, and Bitwuzla, and takes about two hours at 16-way.

## What you will not get, and should not expect to

**The corpus back, byte for byte.** A capture is bound by wall-clock budgets, so
what it reaches depends on the machine and its load. The shipped queries are in
`src/corpus` precisely because they cannot be regenerated exactly; a fresh
capture is a comparable corpus, not the same one.

**The libraries.** No library source or bitcode is committed anywhere here. It
is fetched and built, which is why a version bump is a version bump rather than
a re-vendoring.

**A quick answer about which solver is faster.** `src/corpus`'s README and
`src/fp_bench`'s `RESULTS.md` both spend more words on the conditions than the
numbers, for good reason: what a capture solver could answer decides which
queries exist at all.
