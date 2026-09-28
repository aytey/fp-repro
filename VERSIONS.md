# What this is pinned to, and why each pin matters

Every submodule is at an exact commit. The versions outside the submodules are
pinned in `docker/Dockerfile`, and the reasons below are the ones that bite if
you ignore them.

| | pin | why this one |
| --- | --- | --- |
| `src/klee` | `aytey/klee` @ `fa5ccccf` (branch `aytey_20260824_fp_port`) | KLEE 3.2 with klee-float's floating-point support forward-ported, the STP and Bitwuzla backends, and the solver-independent SMT-LIB printer |
| `src/fp_bench` | `aytey/klee_fp_bench` @ `028a7eb0` | the driver generator and the capture scripts |
| `src/corpus` | `aytey/fp-benchmarks` @ `c2de422c` | the captured queries, and the inventory/curation tools that made them |
| `src/bench` | `aytey/stp-bench` @ `8ca0cb6a` | the replay harness, its 27 campaign configs, and the campaigns as run |
| `src/stp` | `stp/stp` @ `9997879e` | master, which now carries the floating-point abstraction and the FP C API KLEE's builder calls |
| LLVM / clang | 16 | the fork needs 13–16. **Not 17 or later**: for those, `lib/Module/CMakeLists.txt` selects `assert(0)` stubs, so it compiles and cannot execute. clang 15 is the lowest that does `_Float16` on x86 |
| Bitwuzla | `bitwuzla/bitwuzla` @ `eb9ebd82` | the second backend, and the reference printer the differential harness checks against |
| Z3 | 4.8.15 | third backend; only needed if you want its arm |
| klee-uclibc | `klee_uclibc_v1.4` for LLVM 16 | KLEE's libc |

## Two traps that are not version numbers

**LLVM 16 does not build with GCC 14+ without `-include cstdint`**, and the same
flag is needed when building KLEE against it. Both are set in the Dockerfile.

**STP built with `ENABLE_STP=ON` silently becomes KLEE's default solver**, because
3.2's default-solver ladder tests STP first. Anything that means to use another
backend has to say `--solver-backend=` explicitly; the capture scripts do.
