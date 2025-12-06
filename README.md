# llama-droid

**Run LLMs locally on Android with GPU acceleration.** No root required. Privacy-first.

Uses [llama.cpp](https://github.com/ggerganov/llama.cpp) with OpenCL backend optimized for Qualcomm Adreno GPUs.

## Performance

Tested on Samsung Galaxy S25 (Snapdragon 8 Elite, Adreno 830):

| Model | Prompt Processing | Token Generation |
|-------|-------------------|------------------|
| Qwen2.5-0.5B Q4_0 | 388 tok/s | 63.5 tok/s |

## Requirements

- Android device with Qualcomm Snapdragon SoC (8 Gen 1, Gen 2, Gen 3, or 8 Elite)
- 8GB+ RAM recommended (12GB+ for larger models)
- Termux from F-Droid (NOT Google Play)
- ~1GB storage for llama.cpp build + models

### Tested Devices

| Device | SoC | GPU | Status |
|--------|-----|-----|--------|
| Samsung Galaxy S25 | Snapdragon 8 Elite | Adreno 830 | ✓ 63.5 tok/s |

## Quick Start

```bash
# Install dependencies
pkg update && pkg upgrade
pkg install git cmake clang clinfo ocl-icd opencl-headers

# Set up OpenCL library path
echo 'export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib' >> ~/.bashrc
source ~/.bashrc

# Verify GPU access
clinfo | head -20
# Should show "QUALCOMM Snapdragon" and "Adreno"

# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# IMPORTANT: Use version b5026 or earlier (newer versions may segfault)
git checkout b5026

# Build with OpenCL + Adreno optimizations
cmake -B build \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_OPENCL=ON \
  -DGGML_OPENCL_EMBED_KERNELS=ON \
  -DGGML_OPENCL_USE_ADRENO_KERNELS=ON

cmake --build build --config Release -j4

# Download a model
mkdir -p ~/models
curl -L -o ~/models/qwen2.5-0.5b-q4_0.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"

# Run benchmark
export LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:~/llama.cpp/build/lib
./build/bin/llama-bench -m ~/models/qwen2.5-0.5b-q4_0.gguf -p 512 -n 128

# Interactive chat
./build/bin/llama-cli -m ~/models/qwen2.5-0.5b-q4_0.gguf -cnv
```

## Recommended Models

Models must use Q4_0 quantization for optimal Adreno performance.

| Model | Size | RAM Needed | Use Case |
|-------|------|------------|----------|
| SmolLM2-135M | ~100MB | 1GB | Testing, simple tasks |
| Qwen2.5-0.5B | ~400MB | 2GB | Fast assistant, coding |
| Qwen2.5-1.5B | ~1GB | 4GB | Better quality |
| Llama-3.2-1B | ~700MB | 3GB | General assistant |
| Llama-3.2-3B | ~2GB | 6GB | High quality |
| Phi-3-mini-4k | ~2GB | 6GB | Reasoning tasks |

## Build Flags Explained

| Flag | Purpose |
|------|---------|
| `GGML_OPENCL=ON` | Enable OpenCL GPU backend |
| `GGML_OPENCL_EMBED_KERNELS=ON` | Embed OpenCL kernels in binary |
| `GGML_OPENCL_USE_ADRENO_KERNELS=ON` | Use Adreno-optimized kernels |
| `BUILD_SHARED_LIBS=ON` | Build shared libraries |

## Troubleshooting

### "clinfo" shows no devices

Your device may need the OpenCL libraries copied manually:

```bash
# Try alternative library path
export LD_LIBRARY_PATH=/system/vendor/lib64:$PREFIX/lib

# Or copy libraries (some devices)
cp /vendor/lib64/libOpenCL.so ~/
cp /vendor/lib64/libOpenCL_adreno.so ~/
export LD_LIBRARY_PATH=$HOME:$LD_LIBRARY_PATH
```

### Segmentation fault on newer llama.cpp versions

Use version b5026 or earlier:

```bash
git checkout b5026
```

### Slow performance (CPU-only inference)

Check that OpenCL is working:

```bash
./build/bin/llama-cli --version 2>&1 | grep -i opencl
# Should show "ggml_opencl: selecting device: QUALCOMM Adreno"
```

### Out of memory

- Use smaller models (0.5B, 1B)
- Use Q4_0 quantization (smallest)
- Close other apps
- Reduce context size: `-c 2048`

## Architecture

```
llama-droid/
├── README.md           # This file
├── scripts/
│   ├── install.sh      # One-line installer
│   └── benchmark.sh    # Run benchmarks
└── models/             # Model download scripts
```

## Roadmap

- [ ] Pre-built binaries for common devices
- [ ] MCP server for Claude Code integration
- [ ] Model downloader with HuggingFace integration
- [ ] GUI app (future)

## License

MIT License

## Credits

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - The inference engine
- [Qualcomm OpenCL backend](https://www.qualcomm.com/developer/blog/2024/11/introducing-new-opn-cl-gpu-backend-llama-cpp-for-qualcomm-adreno-gpu) - GPU acceleration

Built by [InquiringMinds-AI](https://github.com/InquiringMinds-AI).
