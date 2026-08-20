#!/usr/bin/env bash
# ==============================================================================
# Build & Run script for llama.cpp DFlash2 (PR #27342)
# ==============================================================================
set -euo pipefail

# ---- Config ----
IMAGE_NAME="llama-dflash2"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
PORT="${PORT:-8080}"

# ---- Parse args ----
ACTION="${1:-build}"
shift || true

case "$ACTION" in
    # ---- Build GPU image ----
    "build"|"build-gpu")
        echo "[*] Building GPU image: ${IMAGE_NAME}"
        docker build -t "${IMAGE_NAME}" \
            -f Dockerfile.cuda \
            --build-arg GIT_URL=https://github.com/z-lab/llama.cpp-fork.git \
            --build-arg GIT_BRANCH=dflash2 \
            --build-arg GGML_CUDA=ON \
            --build-arg CUDA_ARCH="${CUDA_ARCH:-rapids}" \
            .
        echo "[done] Image built: ${IMAGE_NAME}"
        ;;

    # ---- Build CPU-only image ----
    "build-cpu")
        echo "[*] Building CPU image: ${IMAGE_NAME}-cpu"
        docker build -t "${IMAGE_NAME}-cpu" \
            -f Dockerfile.cpu \
            --build-arg GIT_URL=https://github.com/z-lab/llama.cpp-fork.git \
            --build-arg GIT_BRANCH=dflash2 \
            .
        echo "[done] Image built: ${IMAGE_NAME}-cpu"
        ;;

    # ---- Run with DFlash2 ----
    # Usage: ./build.sh run <target_model.gguf> <draft_model.gguf> [extra args...]
    "run")
        TARGET_MODEL="${1:?Usage: run <target.gguf> <draft.gguf> [extra args...]}"
        DRAFT_MODEL="${2:?Usage: run <target.gguf> <draft.gguf> [extra args...]}"
        shift 2 || true

        echo "[*] Starting llama-server with DFlash2"
        echo "    Target: ${TARGET_MODEL}"
        echo "    Draft:  ${DRAFT_MODEL}"

        docker run --rm -it \
            --gpus all \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            "${IMAGE_NAME}" \
            -m "/models/${TARGET_MODEL}" \
            -md "/models/${DRAFT_MODEL}" \
            --spec-type draft-dflash \
            --spec-draft-n-max "${SPEC_N_MAX:-4}" \
            -c "${CTX_SIZE:-32768}" \
            -ngl "${NGL:-99}" \
            -ngld "${NGLD:-99}" \
            -fa on \
            -ctk q8_0 -ctv q8_0 \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    # ---- Run CPU-only ----
    "run-cpu")
        TARGET_MODEL="${1:?Usage: run-cpu <target.gguf> <draft.gguf> [extra args...]}"
        DRAFT_MODEL="${2:?Usage: run-cpu <target.gguf> <draft.gguf> [extra args...]}"
        shift 2 || true

        docker run --rm -it \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            "${IMAGE_NAME}-cpu" \
            -m "/models/${TARGET_MODEL}" \
            -md "/models/${DRAFT_MODEL}" \
            --spec-type draft-dflash \
            --spec-draft-n-max "${SPEC_N_MAX:-4}" \
            -c "${CTX_SIZE:-8192}" \
            -ngl 0 \
            -fa on \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    # ---- Run MTP (built-in, no draft model) for comparison ----
    "run-mtp")
        TARGET_MODEL="${1:?Usage: run-mtp <target.gguf> [extra args...]}"
        shift 1 || true

        docker run --rm -it \
            --gpus all \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            "${IMAGE_NAME}" \
            -m "/models/${TARGET_MODEL}" \
            --spec-type draft-mtp \
            --spec-draft-n-max "${SPEC_N_MAX:-4}" \
            -c "${CTX_SIZE:-32768}" \
            -ngl "${NGL:-99}" \
            -fa on \
            -ctk q8_0 -ctv q8_0 \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    # ---- Run baselines (no speculative decoding) ----
    "run-base")
        TARGET_MODEL="${1:?Usage: run-base <target.gguf> [extra args...]}"
        shift 1 || true

        docker run --rm -it \
            --gpus all \
            -p "${PORT}:8080" \
            -v "${MODEL_DIR}:/models:ro" \
            "${IMAGE_NAME}" \
            -m "/models/${TARGET_MODEL}" \
            -c "${CTX_SIZE:-32768}" \
            -ngl "${NGL:-99}" \
            -fa on \
            -ctk q8_0 -ctv q8_0 \
            --host 0.0.0.0 --port 8080 \
            "$@"
        ;;

    "help"|*)
        cat << 'USAGE'
llama.cpp DFlash2 (PR #27342) build & run script

USAGE:
  ./build.sh build           Build GPU Docker image (CUDA)
  ./build.sh build-cpu       Build CPU-only Docker image
  ./build.sh run <target> <draft> [extra...]    Run with DFlash2 (GPU)
  ./build.sh run-cpu <target> <draft> [extra...] Run with DFlash2 (CPU)
  ./build.sh run-mtp <target> [extra...]         Run with built-in MTP
  ./build.sh run-base <target> [extra...]        Run without spec decode

ENVIRONMENT:
  MODEL_DIR   Host directory with GGUF files (default: ~/models)
  PORT        Host port mapping (default: 8080)
  CUDA_ARCH   CUDA arch, e.g. 89 (4090), 80 (A100), 120 (Blackwell)
  SPEC_N_MAX  Speculative draft depth (default: 4)
  CTX_SIZE    Context size (default: 32768)
  NGL         Target GPU layers (default: 99)
  NGLD        Draft GPU layers (default: 99)

DFlash2 MODELS:
  Target:  Qwen3.8-27B-Q4_K_M.gguf (from unsloth/ggml-org)
  Draft:   Qwen3.8-27B-DFlash2-Q4_K_M.gguf (from incoai/z-lab)
            https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF

KNOWN ISSUES:
  - Vision/multimodal not supported with DFlash2 (M-RoPE position conflict)
  - Windows MSVC has "invalid vector subscript" bug; Linux builds are clean
  - Multi-request parallelism may degrade (Intel B70: drops to baseline)
USAGE
        ;;
esac
