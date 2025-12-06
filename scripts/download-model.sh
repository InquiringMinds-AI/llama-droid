#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid model downloader
# Downloads GGUF models from HuggingFace
#

set -e

MODELS_DIR="${MODELS_DIR:-$HOME/models}"

# Model registry: name -> url, size
declare -A MODEL_URLS=(
    ["qwen-0.5b"]="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"
    ["qwen-1.5b"]="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_0.gguf"
    ["qwen-3b"]="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_0.gguf"
    ["llama-1b"]="https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_0.gguf"
    ["llama-3b"]="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_0.gguf"
)

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

declare -A MODEL_SIZES=(
    ["qwen-0.5b"]="403 MB"
    ["qwen-1.5b"]="1.0 GB"
    ["qwen-3b"]="1.9 GB"
    ["llama-1b"]="730 MB"
    ["llama-3b"]="1.8 GB"
)

declare -A MODEL_SPEEDS=(
    ["qwen-0.5b"]="63.5 tok/s"
    ["qwen-1.5b"]="34.5 tok/s"
    ["qwen-3b"]="~15 tok/s"
    ["llama-1b"]="37.7 tok/s"
    ["llama-3b"]="18.5 tok/s"
)

show_help() {
    echo "llama-droid model downloader"
    echo ""
    echo "Usage: $0 <model-name> | list | help"
    echo ""
    echo "Available models (Q4_0 quantization for Adreno GPU):"
    echo ""
    printf "  %-12s %-10s %-12s %s\n" "NAME" "SIZE" "SPEED" "DESCRIPTION"
    printf "  %-12s %-10s %-12s %s\n" "----" "----" "-----" "-----------"
    printf "  %-12s %-10s %-12s %s\n" "qwen-0.5b" "${MODEL_SIZES[qwen-0.5b]}" "${MODEL_SPEEDS[qwen-0.5b]}" "Fastest, good for quick tasks"
    printf "  %-12s %-10s %-12s %s\n" "qwen-1.5b" "${MODEL_SIZES[qwen-1.5b]}" "${MODEL_SPEEDS[qwen-1.5b]}" "Best balance of speed/quality"
    printf "  %-12s %-10s %-12s %s\n" "qwen-3b" "${MODEL_SIZES[qwen-3b]}" "${MODEL_SPEEDS[qwen-3b]}" "Higher quality, slower"
    printf "  %-12s %-10s %-12s %s\n" "llama-1b" "${MODEL_SIZES[llama-1b]}" "${MODEL_SPEEDS[llama-1b]}" "Meta's Llama 3.2"
    printf "  %-12s %-10s %-12s %s\n" "llama-3b" "${MODEL_SIZES[llama-3b]}" "${MODEL_SPEEDS[llama-3b]}" "Larger Llama, good quality"
    echo ""
    echo "Examples:"
    echo "  $0 qwen-0.5b    # Download Qwen 0.5B model"
    echo "  $0 list         # Show available models"
    echo ""
    echo "Models are saved to: $MODELS_DIR"
}

# Check if model is installed (check both standard and alt filenames)
is_model_installed() {
    local model="$1"
    [ -f "$MODELS_DIR/${MODEL_FILES[$model]}" ] || [ -f "$MODELS_DIR/${MODEL_FILES_ALT[$model]}" ]
}

# Get the actual filename for an installed model
get_model_path() {
    local model="$1"
    if [ -f "$MODELS_DIR/${MODEL_FILES[$model]}" ]; then
        echo "$MODELS_DIR/${MODEL_FILES[$model]}"
    elif [ -f "$MODELS_DIR/${MODEL_FILES_ALT[$model]}" ]; then
        echo "$MODELS_DIR/${MODEL_FILES_ALT[$model]}"
    fi
}

list_models() {
    echo "Available models:"
    echo ""
    printf "  %-12s %-10s %-12s %s\n" "NAME" "SIZE" "SPEED" "INSTALLED"
    printf "  %-12s %-10s %-12s %s\n" "----" "----" "-----" "---------"

    for model in qwen-0.5b qwen-1.5b qwen-3b llama-1b llama-3b; do
        local installed="no"
        if is_model_installed "$model"; then
            installed="yes"
        fi
        printf "  %-12s %-10s %-12s %s\n" "$model" "${MODEL_SIZES[$model]}" "${MODEL_SPEEDS[$model]}" "$installed"
    done
    echo ""
}

download_model() {
    local model="$1"
    local url="${MODEL_URLS[$model]}"
    local filename="${MODEL_FILES[$model]}"

    if [ -z "$url" ]; then
        echo "Error: Unknown model '$model'"
        echo ""
        show_help
        exit 1
    fi

    mkdir -p "$MODELS_DIR"
    local filepath="$MODELS_DIR/$filename"

    if [ -f "$filepath" ]; then
        echo "Model already exists: $filepath"
        echo "Delete it first if you want to re-download."
        exit 0
    fi

    echo "Downloading $model (${MODEL_SIZES[$model]})..."
    echo "URL: $url"
    echo "Destination: $filepath"
    echo ""

    curl -L --progress-bar -o "$filepath" "$url"

    echo ""
    echo "Download complete!"
    echo ""
    echo "Run with:"
    echo "  chat.sh $model"
    echo ""
    echo "Or benchmark with:"
    echo "  benchmark.sh"
}

# Main
case "${1:-help}" in
    help|--help|-h)
        show_help
        ;;
    list|ls)
        list_models
        ;;
    *)
        download_model "$1"
        ;;
esac
