#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid update script
# Updates llama.cpp to a newer version with automatic rollback on failure
#

set -e

# Default stable version (known to work)
STABLE_VERSION="b5026"

# Find llama.cpp installation
if [ -n "$LLAMA_DIR" ]; then
    : # Use provided LLAMA_DIR
elif [ -d "$HOME/llama.cpp" ]; then
    LLAMA_DIR="$HOME/llama.cpp"
elif [ -d "$HOME/Projects/llama.cpp" ]; then
    LLAMA_DIR="$HOME/Projects/llama.cpp"
else
    echo "Error: Cannot find llama.cpp installation"
    echo "Set LLAMA_DIR environment variable or run install.sh first"
    exit 1
fi

MODELS_DIR="${MODELS_DIR:-$HOME/models}"

show_help() {
    echo "llama-droid update"
    echo ""
    echo "Usage: $0 [version] [options]"
    echo ""
    echo "Updates llama.cpp to a new version with automatic rollback if build fails"
    echo "or the new version crashes during testing."
    echo ""
    echo "Arguments:"
    echo "  version       Tag or commit to update to (default: latest release)"
    echo "                Examples: b5100, b5200, master, HEAD"
    echo ""
    echo "Options:"
    echo "  --list        List available versions"
    echo "  --current     Show current version"
    echo "  --stable      Revert to known stable version ($STABLE_VERSION)"
    echo "  --test-only   Just run tests on current build"
    echo "  -h, --help    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              # Update to latest release"
    echo "  $0 b5100        # Update to specific version"
    echo "  $0 --stable     # Revert to stable version"
    echo "  $0 --list       # Show available versions"
    echo ""
    echo "Current llama.cpp location: $LLAMA_DIR"
}

get_current_version() {
    cd "$LLAMA_DIR"
    git describe --tags --always 2>/dev/null || git rev-parse --short HEAD
}

list_versions() {
    echo "Recent llama.cpp releases:"
    echo ""
    cd "$LLAMA_DIR"
    git fetch --tags --quiet 2>/dev/null || true
    git tag -l 'b*' | sort -V | tail -20 | while read tag; do
        if [ "$tag" = "$(get_current_version)" ]; then
            echo "  $tag  (current)"
        else
            echo "  $tag"
        fi
    done
    echo ""
    echo "Current version: $(get_current_version)"
    echo "Stable version:  $STABLE_VERSION"
}

run_test() {
    echo "Running quick sanity test..."

    # Find a model to test with
    local test_model=""
    for model in "$MODELS_DIR"/*.gguf; do
        if [ -f "$model" ]; then
            test_model="$model"
            break
        fi
    done

    if [ -z "$test_model" ]; then
        echo "Warning: No models found for testing, skipping test"
        return 0
    fi

    # Find build directory
    local build_dir=""
    if [ -d "$LLAMA_DIR/build-opencl/bin" ]; then
        build_dir="$LLAMA_DIR/build-opencl"
    elif [ -d "$LLAMA_DIR/build/bin" ]; then
        build_dir="$LLAMA_DIR/build"
    else
        echo "Error: No build directory found"
        return 1
    fi

    export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:$build_dir/lib

    echo "Testing with: $(basename "$test_model")"

    # Run a quick inference test with timeout
    if timeout 60 "$build_dir/bin/llama-cli" \
        -m "$test_model" \
        -p "Test prompt" \
        -n 5 \
        --no-display-prompt \
        2>&1 | grep -q "error\|Segmentation fault\|SIGBUS\|Killed"; then
        echo "Test FAILED: Runtime error detected"
        return 1
    fi

    # Check if we got any output (basic sanity)
    local output=$(timeout 30 "$build_dir/bin/llama-cli" \
        -m "$test_model" \
        -p "Say hello:" \
        -n 10 \
        --no-display-prompt \
        2>/dev/null)

    if [ -z "$output" ]; then
        echo "Test FAILED: No output generated"
        return 1
    fi

    echo "Test PASSED"
    return 0
}

build_llama() {
    echo "Building llama.cpp with OpenCL + Adreno optimizations..."
    cd "$LLAMA_DIR"

    # Clean old build
    rm -rf build-opencl

    # Build
    cmake -B build-opencl \
        -DBUILD_SHARED_LIBS=ON \
        -DGGML_OPENCL=ON \
        -DGGML_OPENCL_EMBED_KERNELS=ON \
        -DGGML_OPENCL_USE_ADRENO_KERNELS=ON

    cmake --build build-opencl --config Release -j4

    echo "Build complete"
}

update_to_version() {
    local target_version="$1"
    local current_version=$(get_current_version)

    echo "=== llama-droid update ==="
    echo ""
    echo "Current version: $current_version"
    echo "Target version:  $target_version"
    echo ""

    cd "$LLAMA_DIR"

    # Fetch latest
    echo "Fetching latest from upstream..."
    git fetch --tags

    # Check if version exists
    if ! git rev-parse "$target_version" >/dev/null 2>&1; then
        echo "Error: Version '$target_version' not found"
        echo ""
        echo "Use --list to see available versions"
        exit 1
    fi

    # Checkout new version
    echo "Checking out $target_version..."
    git checkout "$target_version"

    # Build
    if ! build_llama; then
        echo ""
        echo "Build FAILED, rolling back to $current_version..."
        git checkout "$current_version"
        build_llama
        echo "Rolled back to $current_version"
        exit 1
    fi

    # Test
    if ! run_test; then
        echo ""
        echo "Tests FAILED, rolling back to $current_version..."
        git checkout "$current_version"
        build_llama
        echo "Rolled back to $current_version"
        exit 1
    fi

    echo ""
    echo "=== Update successful! ==="
    echo "Updated from $current_version to $(get_current_version)"
}

get_latest_release() {
    cd "$LLAMA_DIR"
    git fetch --tags --quiet 2>/dev/null || true
    git tag -l 'b*' | sort -V | tail -1
}

# Main
case "${1:-}" in
    -h|--help)
        show_help
        ;;
    --list)
        list_versions
        ;;
    --current)
        echo "Current version: $(get_current_version)"
        echo "Location: $LLAMA_DIR"
        ;;
    --stable)
        update_to_version "$STABLE_VERSION"
        ;;
    --test-only)
        run_test
        ;;
    "")
        # Update to latest
        latest=$(get_latest_release)
        if [ -z "$latest" ]; then
            echo "Error: Could not determine latest release"
            exit 1
        fi
        current=$(get_current_version)
        if [ "$latest" = "$current" ]; then
            echo "Already at latest version: $current"
            exit 0
        fi
        update_to_version "$latest"
        ;;
    *)
        update_to_version "$1"
        ;;
esac
