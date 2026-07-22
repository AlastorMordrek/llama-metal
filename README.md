# llama-metal — llama.cpp with Metal GPU acceleration for any Mac

> **⚠️ LEGACY BRANCH — `main-legacy`**
> 
> This branch is **frozen** for archival. It contains llama.cpp at tag **b6123** (June 2025) with iRon-Llama AMD Metal patches and packaging scripts (install.sh, uninstall.sh).
>
> **The current `main` branch** has been replaced with llama.cpp **master** (July 2026, commit `1f66c3ce1`) plus our own AMD Metal patches. The new main branch:
> - Supports GGUF v3 natively (no patch needed)
> - Supports IQ and MXFP4 quantization formats (IQ1_S through IQ4_XS)
> - Supports Gemma 3, Qwen2VL, Qwen3VL, MiniCPM-V, Llama 4, diffusion, TTS
> - 1.9x faster than this legacy branch on the same model
> - Includes server web UI, Jinja templating, speculative decoding
>
> Use the current `main` branch for all new work. This `main-legacy` branch is kept for reference and rollback only.
>
> ---

One command to get llama.cpp running with Metal GPU on Apple Silicon or Intel + AMD.

```
./install.sh
```

## What it does

Detects your GPU and builds the right configuration:
- **Apple Silicon** — native Metal GPU (no patches needed)
- **Intel + AMD Radeon** — Metal GPU with community patches (iRon-Llama AMD fix)
- **Intel iGPU only** — CPU-only with Apple Accelerate BLAS

## Why

Upstream llama.cpp produces garbage output on AMD Radeon Pro GPUs in Intel Macs. This repo bundles tested community patches that fix AMD Metal rendering, so your GPU works correctly.

Apple Silicon Macs use native Metal support with no patches needed.

## Quick Start

```
git clone https://github.com/AlastorMordrek/llama-metal
cd llama-metal
./install.sh
```

Then download a model and run:

```
# Download a model (~500 MB)
curl -L -o model.gguf https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf

# Benchmark
llama-bench -m model.gguf -p 64 -n 64

# Chat
llama-cli -m model.gguf -p "Hello" -n 50

# Start API server (OpenAI-compatible)
llama-server -m model.gguf --port 8010
```

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- ~2 GB disk space for build
- A GGUF model file (download from HuggingFace)

## AMD GPU Users

Your GPU needs these environment variables — the installer creates wrapper scripts that set them automatically:

```
GGML_METAL_DEVICE_INDEX=1    # Force AMD dGPU, skip Intel iGPU
GGML_METAL_N_CB=4            # Command buffer count
```

## Uninstall

```
./uninstall.sh
```

## Prior Art

Built on:
- [llama.cpp](https://github.com/ggerganov/llama.cpp) by Georgi Gerganov and contributors
- [iRon-Llama](https://github.com/Basten7/iRon-Llama) AMD Metal patches by Basten7
