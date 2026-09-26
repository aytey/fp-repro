# Reproduction driver. Every target is a thin call into one of the submodules,
# with the paths they expect set from the variables below, so that what runs is
# the same script that produced the published numbers.
#
#   make help
#
# Override anything on the command line, or put it in local.mk:
#
#   echo 'KLEE_BIN = /my/klee/build/bin/klee' > local.mk

-include local.mk

# Where things are. The defaults suit the container; a native build points them
# at its own prefixes.
KLEE_SRC      ?= $(CURDIR)/src/klee
KLEE_BUILD    ?= $(CURDIR)/build/klee
KLEE_BIN      ?= $(KLEE_BUILD)/bin/klee
FP_BENCH_SRC  ?= $(CURDIR)/src/fp_bench
CORPUS_SRC    ?= $(CURDIR)/src/corpus
BENCH_SRC     ?= $(CURDIR)/src/bench
STP_DIR       ?= /opt/stp/lib/cmake/STP
BITWUZLA_BIN  ?= /opt/bitwuzla/bin/bitwuzla
LIT           ?= lit

# Where work lands. Tens of GB for the libraries; fastest on a RAM disk.
FP_BENCH_WORK ?= $(CURDIR)/work
CAPTURE_OUT   ?= $(FP_BENCH_WORK)/capture
CORPUS_OUT    ?= $(CURDIR)/out/corpus

# What to run on.
LIB           ?= f2clapack-f64
TAG           ?=          # dump-queries.sh's optional tag, e.g. q128 or f16
JOBS          ?= 16
BUDGET        ?= 120
CAP           ?= 60

EXPORTS = KLEE_SRC=$(KLEE_SRC) KLEE_BUILD=$(KLEE_BUILD) KLEE_BIN=$(KLEE_BIN) \
          FP_BENCH_SRC=$(FP_BENCH_SRC) FP_BENCH_WORK=$(FP_BENCH_WORK) \
          CAPTURE_OUT=$(CAPTURE_OUT) BITWUZLA_BIN=$(BITWUZLA_BIN)

.PHONY: help submodules image shell klee test libs capture curate verify replay clean

help:
	@echo "make submodules   fetch the pinned sources (or clone with --recurse-submodules)"
	@echo "make image        build the container (see docker/Dockerfile -- untested)"
	@echo "make klee         build the KLEE fork natively"
	@echo "make test         KLEE's own suite; test/Floats is the floating-point part"
	@echo "make libs         LIB=$(LIB): fetch, build to bitcode, generate drivers"
	@echo "make capture      LIB=$(LIB): run it under KLEE, dump the queries"
	@echo "make curate       inventory + curate a capture into a corpus"
	@echo "make verify       differential-check the SMT-LIB printer on LIB"
	@echo "make replay       run a campaign over a corpus with the harness"
	@echo
	@echo "Paths and pins: README.md and VERSIONS.md. Override in local.mk."

submodules:
	git submodule update --init --recursive

image:
	docker build -t fp-repro -f docker/Dockerfile .

shell: ; docker run --rm -it -v $(CURDIR):/repro -v $(FP_BENCH_WORK):/work fp-repro bash

# The two flags are not optional: LLVM 16's headers need -include cstdint under
# GCC 14+, and the FP backends have to be switched on explicitly.
klee:
	cmake -S $(KLEE_SRC) -B $(KLEE_BUILD) -G Ninja \
	  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_FLAGS="-include cstdint" \
	  -DENABLE_SOLVER_STP=ON -DSTP_DIR=$(STP_DIR) \
	  -DENABLE_SOLVER_Z3=ON -DENABLE_SOLVER_BITWUZLA=ON \
	  -DENABLE_SYSTEM_TESTS=ON -DLIT_TOOL=$(shell command -v $(LIT)) \
	  -DLLVMCC=$(shell command -v clang) -DLLVMCXX=$(shell command -v clang++)
	cmake --build $(KLEE_BUILD)

test:
	cd $(KLEE_BUILD) && $(LIT) -s test/Floats

libs:
	$(EXPORTS) $(FP_BENCH_SRC)/common/build-lib.sh $(LIB)
	$(EXPORTS) $(FP_BENCH_SRC)/common/build-drivers.sh $(LIB)

# One library, one arm: what fp_bench's own dump script does. The four-arm
# capture that produced bench-v3 is corpus/tools/capture5.sh, driven the same way.
capture:
	$(EXPORTS) FP_BENCH_OUT=$(CAPTURE_OUT)/$(LIB) BUDGET=$(BUDGET) \
	  $(FP_BENCH_SRC)/common/dump-queries.sh $(LIB) $(TAG)

capture-all-arms:
	$(EXPORTS) $(CORPUS_SRC)/tools/capture5.sh $(JOBS) $(BUDGET) $(CAP)

curate:
	python3 $(CORPUS_SRC)/tools/inventory.py $(CAPTURE_OUT) $(CAPTURE_OUT)/inventory.tsv $(JOBS)
	python3 $(CORPUS_SRC)/tools/curate.py $(CAPTURE_OUT)/inventory.tsv $(CAPTURE_OUT) $(CORPUS_OUT)
	python3 $(CORPUS_SRC)/tools/check_bits_bindings.py $(CORPUS_OUT)/queries $(CORPUS_OUT)/manifest.tsv

verify:
	$(EXPORTS) $(CORPUS_SRC)/tools/three_way.sh $(LIB) $(DRV) bitwuzla $(BUDGET)

replay:
	cd $(BENCH_SRC) && python3 ./run_comparison.py $(CONFIG) --dir $(CORPUS_OUT)/queries

clean: ; rm -rf $(KLEE_BUILD) out
