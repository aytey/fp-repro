# A machine that can build the fork and capture benchmarks with it.
#
#   docker build -t fp-repro -f docker/Dockerfile .
#
# NOT BUILT OR TESTED. It is written from the recipes that did work -- KLEE's
# own Dockerfile and dependency images, STP's CI, Bitwuzla's configure, and
# FP_PORT_2026.md's build section -- but no container runtime was available on
# the machine that wrote it, so treat the first build as a debugging session
# rather than a reproduction. `make image` then `make klee test` is the check:
# KLEE's own test/Floats suite is 83 tests and passes on the pinned commit.
#
# Why not KLEE's stock image: it carries STP 2.3.4, which has no floating-point
# theory, and no Bitwuzla at all. Those two stages are the difference.

FROM ghcr.io/klee/llvm:160_O_D_A_ubuntu_jammy-20251001 AS llvm_base
FROM ghcr.io/klee/uclibc:klee_uclibc_v1.4_160_ubuntu_jammy-20251001 AS uclibc_base
FROM ghcr.io/klee/z3:4.8.15_ubuntu_jammy-20251001 AS z3_base
FROM ghcr.io/klee/gtest:1.16.0_ubuntu_jammy-20251001 AS gtest_base
FROM ghcr.io/klee/sqlite:3400100_ubuntu_jammy-20251001 AS sqlite3_base

# ---------------------------------------------------------------- STP with FP
FROM llvm_base AS stp_build
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      bison build-essential ccache cmake flex git libgmp-dev ninja-build \
      python3 python3-pip python3-setuptools zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
ARG STP_COMMIT=9997879e9b06e5f919b92832be60dbf9a881d646
RUN git clone https://github.com/stp/stp /tmp/stp \
    && git -C /tmp/stp checkout ${STP_COMMIT}
# ENABLE_AUTO_DOWNLOAD lets STP fetch its own SAT solvers and SymFPU, which is
# what its CI does; SymFPU is what makes the floating-point theory and the
# vc_fp* C API KLEE's builder calls exist at all.
RUN cmake -S /tmp/stp -B /tmp/stp/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/stp \
      -DSTP_DEP_DIR=/tmp/stp/deps/install \
      -DFETCHCONTENT_BASE_DIR=/tmp/stp/deps/fetch \
      -DENABLE_AUTO_DOWNLOAD=ON \
      -DUSE_CADICAL=ON -DUSE_CRYPTOMINISAT=OFF -DUSE_MINISAT=ON \
      -DBUILD_SHARED_LIBS=ON -DENABLE_TESTING=OFF \
    && cmake --build /tmp/stp/build --target install

# ------------------------------------------------------------------ Bitwuzla
FROM llvm_base AS bitwuzla_build
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git libgmp-dev meson ninja-build pkg-config python3 \
    && rm -rf /var/lib/apt/lists/*
ARG BITWUZLA_COMMIT=eb9ebd82b00279d95606366fdd53bb413c58c9f9
RUN git clone https://github.com/bitwuzla/bitwuzla /tmp/bitwuzla \
    && git -C /tmp/bitwuzla checkout ${BITWUZLA_COMMIT}
RUN cd /tmp/bitwuzla && ./configure.py --prefix /opt/bitwuzla --shared \
    && cd build && ninja install

# ---------------------------------------------------------------------- KLEE
FROM llvm_base AS klee_build
USER root
COPY --from=uclibc_base /tmp /tmp/
COPY --from=z3_base /tmp /tmp/
COPY --from=gtest_base /tmp /tmp/
COPY --from=sqlite3_base /tmp /tmp/
COPY --from=stp_build /opt/stp /opt/stp
COPY --from=bitwuzla_build /opt/bitwuzla /opt/bitwuzla
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake curl file git libgmp-dev libsqlite3-dev ninja-build \
      python3 python3-pip python3-venv zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
# wllvm keeps bitcode beside the objects, which is how the libraries are built.
RUN python3 -m venv /opt/pyenv && /opt/pyenv/bin/pip install --no-cache-dir wllvm lit==22.*

COPY src/klee /src/klee
# -include cstdint: LLVM 16's headers are missing transitive includes and do
# not compile under GCC 14+ without it, and neither does KLEE against them.
RUN cmake -S /src/klee -B /build/klee -G Ninja \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_FLAGS="-include cstdint" \
      -DENABLE_SOLVER_STP=ON  -DSTP_DIR=/opt/stp/lib/cmake/STP \
      -DENABLE_SOLVER_Z3=ON \
      -DENABLE_SOLVER_BITWUZLA=ON \
        -DBitwuzla_INCLUDE_DIRS=/opt/bitwuzla/include \
        -DBitwuzla_LIBRARIES=/opt/bitwuzla/lib/libbitwuzla.so \
      -DENABLE_SYSTEM_TESTS=ON -DENABLE_UNIT_TESTS=OFF \
      -DLIT_TOOL=/opt/pyenv/bin/lit \
      -DLLVMCC=/usr/bin/clang -DLLVMCXX=/usr/bin/clang++ \
    && cmake --build /build/klee

ENV PATH=/opt/pyenv/bin:/build/klee/bin:/opt/stp/bin:/opt/bitwuzla/bin:$PATH
ENV KLEE_BIN=/build/klee/bin/klee \
    KLEE_SRC=/src/klee \
    LLVM_PREFIX=/usr \
    BITWUZLA_BIN=/opt/bitwuzla/bin/bitwuzla \
    STP_BIN=/opt/stp/bin/stp \
    PYENV=/opt/pyenv \
    FP_BENCH_WORK=/work \
    CAPTURE_OUT=/work/capture
WORKDIR /repro
