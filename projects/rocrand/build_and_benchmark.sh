#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./build_and_benchmark.sh <mode> [build-dir] [rocm-prefix]
# Modes:
#   config  - deletes build dir and runs CMake configure only
#   build   - builds the already-configured tree
#   test    - runs only the single benchmark: device_kernel<lfsr113,log-normal-float>
# Defaults:
#   build-dir: ./build
#   rocm-prefix: /opt/rocm
# Environment overrides:
#   CXX: path to hipcc (or other HIP-capable compiler)
#   JOBS: parallel build jobs (default: nproc)
#   GPU_TARGETS: comma-separated GPU arch list (default: gfx1200)
#   VERBOSE: set to 1 to show compile/link commands (default: 1)
#   TRIALS: benchmark trials per GB iteration (default: 1000)
#   SIZE: number of generated items (default: 134217728)
#   RUN_TESTS: when running full builds, set 0 to skip ctest

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <config|build|test> [build-dir] [rocm-prefix]" >&2
  exit 2
fi

MODE="$1"; shift || true

PROJECT_ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-${PROJECT_ROOT_DIR}/build}"
ROCM_PREFIX="${2:-/opt/rocm}"

CXX_DEFAULT="${ROCM_PREFIX}/bin/hipcc"
CXX_COMPILER="${CXX:-${CXX_DEFAULT}}"
JOBS="${JOBS:-$(nproc)}"
GPU_TARGETS_VAL="${GPU_TARGETS:-gfx1100}"
VERBOSE_BUILD="${VERBOSE:-1}"
TRIALS="${TRIALS:-5000}"
SIZE="${SIZE:-134217728}"

cmake_config() {
  # Fresh configure requested: remove and recreate build dir
  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}"

  EXTRA_CMAKE_ARGS=()
  if [[ "${VERBOSE_BUILD}" == "1" ]]; then
    EXTRA_CMAKE_ARGS+=( -DCMAKE_VERBOSE_MAKEFILE=ON )
  fi

  cmake -S "${PROJECT_ROOT_DIR}" -B "${BUILD_DIR}" \
    -DBUILD_TEST=ON -DBUILD_BENCHMARK=ON \
    -DCMAKE_PREFIX_PATH="${ROCM_PREFIX};${ROCM_PREFIX}/hip" \
    -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
    -DGPU_TARGETS="${GPU_TARGETS_VAL}" \
    -DAMDGPU_TARGETS="${GPU_TARGETS_VAL}" \
    "${EXTRA_CMAKE_ARGS[@]}"
}

cmake_build() {
  if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    echo "[ERROR] Build directory not configured: ${BUILD_DIR}" >&2
    echo "        Run: $0 config [build-dir] [rocm-prefix]" >&2
    exit 1
  fi
  BUILD_ARGS=( --build "${BUILD_DIR}" -j "${JOBS}" )
  if [[ "${VERBOSE_BUILD}" == "1" ]]; then
    BUILD_ARGS+=( --verbose )
  fi
  cmake "${BUILD_ARGS[@]}"
}

run_single_benchmark() {
  local BENCH_BIN="${BUILD_DIR}/benchmark/benchmark_rocrand_device_api"
  if [[ ! -x "${BENCH_BIN}" ]]; then
    echo "[ERROR] Benchmark binary not found: ${BENCH_BIN}" >&2
    echo "        Build it first: $0 build [build-dir] [rocm-prefix]" >&2
    exit 1
  fi
  set -x
  # Include suffix like '/manual_time' by using a regex that allows any suffix
  "${BENCH_BIN}" \
    --benchmark_filter='device_kernel<lfsr113,log-normal-float>.*' \
    --trials "${TRIALS}" \
    --size "${SIZE}" \
    --benchmark_color=false \
    --benchmark_format=csv
  set +x
}

case "${MODE}" in
  config)
    echo "[INFO] Configuring (GPU_TARGETS=${GPU_TARGETS_VAL}; VERBOSE=${VERBOSE_BUILD})..."
    cmake_config
    ;;
  build)
    echo "[INFO] Building..."
    cmake_build
    if [[ "${RUN_TESTS:-0}" != "0" ]]; then
      echo "[INFO] Running ctest..."
      (cd "${BUILD_DIR}" && ctest --output-on-failure) || true
    fi
    ;;
  test)
    echo "[INFO] Running single benchmark: device_kernel<lfsr113,log-normal-float>*"
    run_single_benchmark
    ;;
  *)
    echo "[ERROR] Unknown mode: ${MODE}" >&2
    echo "Usage: $0 <config|build|test> [build-dir] [rocm-prefix]" >&2
    exit 2
    ;;
 esac
