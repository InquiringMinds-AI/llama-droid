#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid benchmark script
# Tests inference speed with available models
#

set -e

LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
LLAMA_BENCH="$LLAMA_DIR/build/bin/llama-bench"

# Set library path
export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:$LLAMA_DIR/build/lib

# Check llama-bench exists
if [ ! -f "$LLAMA_BENCH" ]; then
    echo "Error: llama-bench not found at $LLAMA_BENCH"
    echo "Run install.sh first"
    exit 1
fi

# Find models
echo "=== llama-droid benchmark ==="
echo ""
echo "Device: $(getprop ro.product.model 2>/dev/null || echo 'Unknown')"
echo "SoC: $(getprop ro.hardware 2>/dev/null || echo 'Unknown')"
echo "GPU: $(clinfo 2>/dev/null | grep 'Device Name' | head -1 | cut -d: -f2 | xargs)"
echo ""

# Check for models
if [ ! -d "$MODELS_DIR" ] || [ -z "$(ls -A $MODELS_DIR/*.gguf 2>/dev/null)" ]; then
    echo "No models found in $MODELS_DIR"
    echo ""
    echo "Download a model first:"
    echo "  mkdir -p ~/models"
    echo "  curl -L -o ~/models/qwen2.5-0.5b-q4_0.gguf \\"
    echo "    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf'"
    exit 1
fi

echo "Running benchmarks..."
echo ""

for model in $MODELS_DIR/*.gguf; do
    if [ -f "$model" ]; then
        echo "=== $(basename $model) ==="
        $LLAMA_BENCH -m "$model" -p 512 -n 128 -r 1 2>&1 | tail -5
        echo ""
    fi
done

echo "=== Benchmark complete ==="
