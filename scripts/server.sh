#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid server wrapper
# Starts llama.cpp HTTP API server
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
LLAMA_SERVER="$BUILD_DIR/bin/llama-server"

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
    echo "llama-droid server"
    echo ""
    echo "Usage: $0 [model-name] [options]"
    echo ""
    echo "Starts an OpenAI-compatible HTTP API server."
    echo ""
    echo "Arguments:"
    echo "  model-name    Model to use (default: auto-detect first available)"
    echo "                Shortcuts: qwen-0.5b, qwen-1.5b, qwen-3b, llama-1b, llama-3b"
    echo "                Or full path to .gguf file"
    echo ""
    echo "Options:"
    echo "  -p, --port N     Port to listen on (default: 8080)"
    echo "  -H, --host ADDR  Host to bind to (default: 127.0.0.1)"
    echo "  -c, --ctx N      Context size (default: 4096)"
    echo "  -t, --threads N  CPU threads (default: 4)"
    echo "  --no-gpu         Disable GPU, use CPU only"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                        # Start with auto-detected model"
    echo "  $0 qwen-1.5b              # Use Qwen 1.5B"
    echo "  $0 qwen-0.5b -p 3000      # Custom port"
    echo "  $0 llama-1b -H 0.0.0.0    # Listen on all interfaces"
    echo ""
    echo "API endpoints:"
    echo "  POST /completion          - Generate completion"
    echo "  POST /v1/chat/completions - OpenAI-compatible chat"
    echo "  GET  /health              - Health check"
    echo ""
    echo "Test with:"
    echo "  curl http://localhost:8080/v1/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
}

# Check llama-server exists
if [ ! -f "$LLAMA_SERVER" ]; then
    echo "Error: llama-server not found at $LLAMA_SERVER"
    echo "Run install.sh first"
    exit 1
fi

# Parse arguments
MODEL=""
PORT="8080"
HOST="127.0.0.1"
CTX_SIZE="4096"
THREADS="4"
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -H|--host)
            HOST="$2"
            shift 2
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

echo "=== llama-droid server ==="
echo ""
echo "Model: $(basename $MODEL_PATH)"
echo "Context: $CTX_SIZE tokens"
echo "Server: http://$HOST:$PORT"
echo ""
echo "API endpoints:"
echo "  http://$HOST:$PORT/v1/chat/completions  (OpenAI-compatible)"
echo "  http://$HOST:$PORT/completion           (llama.cpp native)"
echo "  http://$HOST:$PORT/health               (health check)"
echo ""
echo "Press Ctrl+C to stop"
echo ""

exec "$LLAMA_SERVER" \
    -m "$MODEL_PATH" \
    -c "$CTX_SIZE" \
    -t "$THREADS" \
    --host "$HOST" \
    --port "$PORT" \
    $EXTRA_ARGS
