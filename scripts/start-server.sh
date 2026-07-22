#!/usr/bin/env bash
set -euo pipefail

MODEL="${LLAMA_METAL_MODEL:-}"
PORT="${LLAMA_METAL_PORT:-8010}"

if [ -z "$MODEL" ]; then
    echo "Error: No model specified."
    echo ""
    echo "Set the LLAMA_METAL_MODEL environment variable:"
    echo "  export LLAMA_METAL_MODEL=~/models/qwen2.5-0.5b-instruct.gguf"
    echo ""
    echo "Or pass the model directly:"
    echo "  llama-server -m ~/models/qwen2.5-0.5b-instruct.gguf"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model file not found: $MODEL"
    exit 1
fi

exec llama-server \
    --port "$PORT" \
    -m "$MODEL" \
    -ngl 99 \
    --temp 0.7 \
    -c 4096 \
    -b 16 \
    -ub 16 \
    -t 6 \
    --mlock \
    --jinja \
    --prio 2 \
    --embeddings \
    --pooling mean
