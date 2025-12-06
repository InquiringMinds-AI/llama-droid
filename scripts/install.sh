#!/data/data/com.termux/files/usr/bin/bash
#
# llama-droid installer
# Builds llama.cpp with OpenCL GPU acceleration for Android
#

set -e

echo "=== llama-droid installer ==="
echo ""

# Check we're in Termux
if [ ! -d "/data/data/com.termux" ]; then
    echo "Error: This script must be run in Termux"
    exit 1
fi

# Install dependencies
echo "[1/6] Installing dependencies..."
pkg update -y
pkg install -y git cmake clang clinfo ocl-icd opencl-headers

# Set up library path
echo "[2/6] Configuring OpenCL library path..."
if ! grep -q "LD_LIBRARY_PATH=/vendor/lib64" ~/.bashrc 2>/dev/null; then
    echo 'export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib' >> ~/.bashrc
fi
export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib

# Verify GPU access
echo "[3/6] Checking GPU access..."
if ! clinfo 2>/dev/null | grep -q "Adreno"; then
    echo "Warning: Adreno GPU not detected via clinfo"
    echo "Trying alternative library path..."
    export LD_LIBRARY_PATH=/system/vendor/lib64:$PREFIX/lib
    if ! clinfo 2>/dev/null | grep -q "Adreno"; then
        echo "Error: Could not detect Adreno GPU"
        echo "Your device may not be supported or OpenCL libraries are missing"
        exit 1
    fi
fi
echo "GPU detected: $(clinfo 2>/dev/null | grep 'Device Name' | head -1 | cut -d: -f2)"

# Clone llama.cpp
echo "[4/6] Cloning llama.cpp..."
LLAMA_DIR="$HOME/llama.cpp"
if [ -d "$LLAMA_DIR" ]; then
    echo "llama.cpp already exists at $LLAMA_DIR"
    cd "$LLAMA_DIR"
    git fetch --tags
else
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    cd "$LLAMA_DIR"
fi

# Checkout stable version
echo "[5/6] Checking out stable version (b5026)..."
git checkout b5026

# Build with OpenCL
echo "[6/6] Building with OpenCL + Adreno optimizations..."
rm -rf build
cmake -B build \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_OPENCL=ON \
    -DGGML_OPENCL_EMBED_KERNELS=ON \
    -DGGML_OPENCL_USE_ADRENO_KERNELS=ON

cmake --build build --config Release -j4

echo ""
echo "=== Build complete! ==="
echo ""
echo "Binaries are in: $LLAMA_DIR/build/bin/"
echo ""
echo "To run, set library path first:"
echo "  export LD_LIBRARY_PATH=/vendor/lib64:\$PREFIX/lib:$LLAMA_DIR/build/lib"
echo ""
echo "Download a model:"
echo "  mkdir -p ~/models"
echo "  curl -L -o ~/models/qwen2.5-0.5b-q4_0.gguf \\"
echo "    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf'"
echo ""
echo "Run benchmark:"
echo "  $LLAMA_DIR/build/bin/llama-bench -m ~/models/qwen2.5-0.5b-q4_0.gguf -p 512 -n 128"
echo ""
echo "Interactive chat:"
echo "  $LLAMA_DIR/build/bin/llama-cli -m ~/models/qwen2.5-0.5b-q4_0.gguf -cnv"
echo ""
