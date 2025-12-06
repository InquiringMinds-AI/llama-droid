#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid chat wrapper
# Interactive chat with local LLM
#

# Find llama.cpp installation
if [ -n "$LLAMA_DIR" ]; then
    : # Use provided LLAMA_DIR
elif [ -d "$HOME/llama.cpp" ]; then
    LLAMA_DIR="$HOME/llama.cpp"
elif [ -d "$HOME/Projects/llama.cpp" ]; then
    LLAMA_DIR="$HOME/Projects/llama.cpp"
else
    echo "Error: Cannot find llama.cpp installation"
    echo "Set LLAMA_DIR environment variable or run install.sh"
    exit 1
fi

# Find build directory (may be 'build' or 'build-opencl')
if [ -d "$LLAMA_DIR/build-opencl/bin" ]; then
    BUILD_DIR="$LLAMA_DIR/build-opencl"
elif [ -d "$LLAMA_DIR/build/bin" ]; then
    BUILD_DIR="$LLAMA_DIR/build"
else
    echo "Error: Cannot find llama.cpp build directory"
    echo "Run install.sh first"
    exit 1
fi

MODELS_DIR="${MODELS_DIR:-$HOME/models}"
LLAMA_CLI="$BUILD_DIR/bin/llama-cli"

# Set library path for GPU
export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:$BUILD_DIR/lib

# Model name to filename mapping
declare -A MODEL_FILES=(
    ["qwen-0.5b"]="qwen2.5-0.5b-instruct-q4_0.gguf"
    ["qwen-1.5b"]="qwen2.5-1.5b-instruct-q4_0.gguf"
    ["qwen-3b"]="qwen2.5-3b-instruct-q4_0.gguf"
    ["llama-1b"]="Llama-3.2-1B-Instruct-Q4_0.gguf"
    ["llama-3b"]="Llama-3.2-3B-Instruct-Q4_0.gguf"
)

# Alternative filenames (for manually downloaded models)
declare -A MODEL_FILES_ALT=(
    ["qwen-0.5b"]="qwen2.5-0.5b-q4_0.gguf"
    ["qwen-1.5b"]="qwen2.5-1.5b-q4_0.gguf"
    ["qwen-3b"]="qwen2.5-3b-q4_0.gguf"
    ["llama-1b"]="llama-3.2-1b-q4_0.gguf"
    ["llama-3b"]="llama-3.2-3b-q4_0.gguf"
)

# Get the actual filename for an installed model
get_model_path() {
    local model="$1"
    if [ -f "$MODELS_DIR/${MODEL_FILES[$model]}" ]; then
        echo "$MODELS_DIR/${MODEL_FILES[$model]}"
    elif [ -f "$MODELS_DIR/${MODEL_FILES_ALT[$model]}" ]; then
        echo "$MODELS_DIR/${MODEL_FILES_ALT[$model]}"
    fi
}

show_help() {
    echo "llama-droid chat"
    echo ""
    echo "Usage: $0 [model-name] [options]"
    echo ""
    echo "Arguments:"
    echo "  model-name    Model to use (default: auto-detect first available)"
    echo "                Shortcuts: qwen-0.5b, qwen-1.5b, qwen-3b, llama-1b, llama-3b"
    echo "                Or full path to .gguf file"
    echo ""
    echo "Options:"
    echo "  -c, --ctx N   Context size (default: 4096)"
    echo "  -t, --threads N  CPU threads (default: 4)"
    echo "  --no-gpu      Disable GPU, use CPU only"
    echo "  -h, --help    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                     # Auto-detect model"
    echo "  $0 qwen-0.5b           # Use Qwen 0.5B"
    echo "  $0 qwen-1.5b -c 2048   # Qwen 1.5B with 2K context"
    echo "  $0 ~/models/custom.gguf  # Custom model path"
    echo ""
    echo "Installed models:"
    for name in qwen-0.5b qwen-1.5b qwen-3b llama-1b llama-3b; do
        local path=$(get_model_path "$name")
        if [ -n "$path" ]; then
            echo "  - $name"
        fi
    done
}

# Check llama-cli exists
if [ ! -f "$LLAMA_CLI" ]; then
    echo "Error: llama-cli not found at $LLAMA_CLI"
    echo "Run install.sh first"
    exit 1
fi

# Parse arguments
MODEL=""
CTX_SIZE="4096"
THREADS="4"
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--ctx)
            CTX_SIZE="$2"
            shift 2
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        --no-gpu)
            EXTRA_ARGS="$EXTRA_ARGS -ngl 0"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            MODEL="$1"
            shift
            ;;
    esac
done

# Resolve model path
MODEL_PATH=""

if [ -n "$MODEL" ]; then
    # Check if it's a shortcut name
    if [ -n "${MODEL_FILES[$MODEL]}" ]; then
        MODEL_PATH=$(get_model_path "$MODEL")
        if [ -z "$MODEL_PATH" ]; then
            echo "Error: Model not found: $MODEL"
            echo ""
            echo "Download it with:"
            echo "  download-model.sh $MODEL"
            exit 1
        fi
    # Check if it's a direct path
    elif [ -f "$MODEL" ]; then
        MODEL_PATH="$MODEL"
    # Check if it's a filename in models dir
    elif [ -f "$MODELS_DIR/$MODEL" ]; then
        MODEL_PATH="$MODELS_DIR/$MODEL"
    else
        echo "Error: Model not found: $MODEL"
        echo ""
        echo "Download it with:"
        echo "  download-model.sh $MODEL"
        exit 1
    fi
else
    # Auto-detect first available model
    for name in qwen-0.5b qwen-1.5b llama-1b qwen-3b llama-3b; do
        MODEL_PATH=$(get_model_path "$name")
        if [ -n "$MODEL_PATH" ]; then
            echo "Auto-selected: $name"
            break
        fi
    done

    if [ -z "$MODEL_PATH" ]; then
        echo "Error: No models found in $MODELS_DIR"
        echo ""
        echo "Download a model first:"
        echo "  download-model.sh qwen-0.5b"
        exit 1
    fi
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found: $MODEL_PATH"
    exit 1
fi

echo "Model: $(basename $MODEL_PATH)"
echo "Context: $CTX_SIZE tokens"
echo ""
echo "Starting chat... (Ctrl+C to exit)"
echo ""

exec "$LLAMA_CLI" \
    -m "$MODEL_PATH" \
    -c "$CTX_SIZE" \
    -t "$THREADS" \
    --color \
    -cnv \
    $EXTRA_ARGS
