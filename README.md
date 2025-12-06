# llama-droid

**Run LLMs locally on Android with GPU acceleration.** No root required. Privacy-first.

Uses [llama.cpp](https://github.com/ggerganov/llama.cpp) with OpenCL backend optimized for Qualcomm Adreno GPUs.

## Performance

Tested on Samsung Galaxy S25 (Snapdragon 8 Elite, Adreno 830):

| Model | Size | Quantization | Prompt (tok/s) | Generation (tok/s) |
|-------|------|--------------|----------------|-------------------|
| Qwen2.5-0.5B | 403 MB | Q4_0 | 388 | 63.5 |
| Qwen2.5-1.5B | 1.0 GB | Q4_0 | 379 | 34.5 |
| Llama-3.2-1B | 730 MB | Q4_0 | 331 | 37.7 |
| Llama-3.2-3B | 1.8 GB | Q4_0 | 194 | 18.5 |
| Phi-3-mini-4k | 2.3 GB | Q4_K_M | 11 | 4.1 |

**Notes:**
- Q4_0 quantization is optimized for Adreno GPUs and runs significantly faster
- Q4_K_M (Phi-3) uses different kernels that aren't as well optimized for Adreno
- 0.5B-1.5B models are best for real-time chat (30+ tok/s generation)
- 3B models are usable but slower (~18 tok/s generation)

## Requirements

- Android device with Qualcomm Snapdragon SoC (8 Gen 1, Gen 2, Gen 3, or 8 Elite)
- 8GB+ RAM recommended (12GB+ for larger models)
- Termux from F-Droid (NOT Google Play)
- ~1GB storage for llama.cpp build + models

### Tested Devices

| Device | SoC | GPU | Best Result |
|--------|-----|-----|-------------|
| Samsung Galaxy S25 | Snapdragon 8 Elite | Adreno 830 | 63.5 tok/s (0.5B) |

## Quick Start

```bash
# Clone llama-droid
git clone https://github.com/InquiringMinds-AI/llama-droid.git
cd llama-droid

# Run installer (builds llama.cpp with GPU support)
./scripts/install.sh

# Download a model
./scripts/download-model.sh qwen-0.5b

# Start chatting!
./scripts/chat.sh
```

That's it! The scripts handle all the complexity.

## Scripts

### download-model.sh

Download models with friendly names:

```bash
./scripts/download-model.sh list          # Show available models
./scripts/download-model.sh qwen-0.5b     # Download Qwen 0.5B (fastest)
./scripts/download-model.sh qwen-1.5b     # Download Qwen 1.5B (best balance)
./scripts/download-model.sh llama-3b      # Download Llama 3.2 3B
```

### chat.sh

Interactive chat with sensible defaults:

```bash
./scripts/chat.sh                    # Auto-detect model
./scripts/chat.sh qwen-1.5b          # Use specific model
./scripts/chat.sh qwen-0.5b -c 2048  # Custom context size
./scripts/chat.sh --no-gpu           # CPU-only mode
```

### server.sh

Start an OpenAI-compatible HTTP API:

```bash
./scripts/server.sh                  # Start server on localhost:8080
./scripts/server.sh qwen-1.5b        # Use specific model
./scripts/server.sh -p 3000          # Custom port
./scripts/server.sh -H 0.0.0.0       # Listen on all interfaces
```

Test the API:
```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

### benchmark.sh

Run benchmarks on all downloaded models:

```bash
./scripts/benchmark.sh
```

### update.sh

Update llama.cpp with automatic rollback on failure:

```bash
./scripts/update.sh              # Update to latest release
./scripts/update.sh b5100        # Update to specific version
./scripts/update.sh --list       # Show available versions
./scripts/update.sh --stable     # Revert to known stable (b5026)
./scripts/update.sh --test-only  # Test current build
```

If the new version fails to build or crashes during testing, it automatically rolls back to the previous working version.

## Manual Installation

<details>
<summary>Click to expand manual installation steps</summary>

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

</details>

## Recommended Models

**Important:** Use Q4_0 quantization for optimal Adreno GPU performance. Q4_K and Q5_K are significantly slower.

| Model | Size | Speed | Use Case |
|-------|------|-------|----------|
| Qwen2.5-0.5B Q4_0 | 403 MB | 63.5 tok/s | Fast assistant, quick responses |
| Qwen2.5-1.5B Q4_0 | 1.0 GB | 34.5 tok/s | Better quality, still fast |
| Llama-3.2-1B Q4_0 | 730 MB | 37.7 tok/s | General assistant |
| Llama-3.2-3B Q4_0 | 1.8 GB | 18.5 tok/s | High quality, usable speed |

### Model Download Links

```bash
# Qwen2.5-0.5B (recommended for speed)
curl -L -o ~/models/qwen2.5-0.5b-q4_0.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"

# Qwen2.5-1.5B (best balance)
curl -L -o ~/models/qwen2.5-1.5b-q4_0.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_0.gguf"

# Llama-3.2-1B
curl -L -o ~/models/llama-3.2-1b-q4_0.gguf \
  "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_0.gguf"

# Llama-3.2-3B (if you want higher quality)
curl -L -o ~/models/llama-3.2-3b-q4_0.gguf \
  "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_0.gguf"
```

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
├── README.md              # This file
├── scripts/
│   ├── install.sh         # Build llama.cpp with GPU support
│   ├── download-model.sh  # Download models from HuggingFace
│   ├── chat.sh            # Interactive chat wrapper
│   ├── server.sh          # HTTP API server wrapper
│   ├── benchmark.sh       # Run benchmarks
│   └── update.sh          # Update llama.cpp with rollback
├── llama_droid/           # Python package
│   ├── __init__.py
│   ├── cli.py             # CLI entry point
│   └── mcp_server.py      # MCP server implementation
├── pyproject.toml         # Python package config
└── LICENSE
```

## MCP Server

llama-droid includes an MCP (Model Context Protocol) server for integration with Claude Code, Claude Desktop, Cursor, and other MCP-compatible clients.

### Setup

```bash
# Install the Python package
pip install -e .

# Add to ~/.claude/mcp.json
{
  "mcpServers": {
    "llm": {
      "command": "llama-droid",
      "args": ["serve"],
      "env": {
        "LD_LIBRARY_PATH": "/vendor/lib64:/data/data/com.termux/files/usr/lib"
      }
    }
  }
}

# Restart Claude Code to connect
```

### Available Tools

| Tool | Description |
|------|-------------|
| `llm_complete` | Generate text completion |
| `llm_chat` | Chat with message history |
| `llm_list_models` | List available models |
| `llm_status` | Check server status |
| `llm_start` | Start server with specific model |
| `llm_stop` | Stop server to free resources |

### Privacy Use Case

Use local LLM for privacy-sensitive tasks:
- Email summarization without sending to cloud
- Processing personal documents locally
- Any task where data shouldn't leave your device

The MCP server runs llama-server on localhost only (127.0.0.1) and uses stdio transport - no network exposure.

## Roadmap

- [ ] Pre-built binaries for common devices
- [ ] GUI app (future)

## License

MIT License

## Credits

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - The inference engine
- [Qualcomm OpenCL backend](https://www.qualcomm.com/developer/blog/2024/11/introducing-new-opn-cl-gpu-backend-llama-cpp-for-qualcomm-adreno-gpu) - GPU acceleration

Built by [InquiringMinds-AI](https://github.com/InquiringMinds-AI).
