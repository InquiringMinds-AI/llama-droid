"""
MCP server for llama-droid.
Exposes local LLM inference as tools for Claude Code and other MCP clients.

Security model:
- stdio transport only (no network exposure)
- llama-server backend on localhost only (127.0.0.1)
- No shell execution from LLM output
- Text in, text out only
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from typing import Any, Optional

JSONRPC_VERSION = "2.0"
SERVER_NAME = "llama-droid"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"

# Default configuration
DEFAULT_LLAMA_SERVER_PORT = 8079  # Different from common ports to avoid conflicts
DEFAULT_MODEL = "qwen-0.5b"
DEFAULT_CTX_SIZE = 4096

# Model name to filename mapping
MODEL_FILES = {
    "qwen-0.5b": "qwen2.5-0.5b-instruct-q4_0.gguf",
    "qwen-1.5b": "qwen2.5-1.5b-instruct-q4_0.gguf",
    "qwen-3b": "qwen2.5-3b-instruct-q4_0.gguf",
    "llama-1b": "Llama-3.2-1B-Instruct-Q4_0.gguf",
    "llama-3b": "Llama-3.2-3B-Instruct-Q4_0.gguf",
}

# Alternative filenames
MODEL_FILES_ALT = {
    "qwen-0.5b": "qwen2.5-0.5b-q4_0.gguf",
    "qwen-1.5b": "qwen2.5-1.5b-q4_0.gguf",
    "qwen-3b": "qwen2.5-3b-q4_0.gguf",
    "llama-1b": "llama-3.2-1b-q4_0.gguf",
    "llama-3b": "llama-3.2-3b-q4_0.gguf",
}


def log(msg: str):
    """Log to stderr (stdout is for JSON-RPC)."""
    print(f"[llama-droid] {msg}", file=sys.stderr, flush=True)


def send_response(id: Any, result: Any = None, error: Any = None):
    """Send a JSON-RPC response."""
    response = {"jsonrpc": JSONRPC_VERSION, "id": id}
    if error:
        response["error"] = error
    else:
        response["result"] = result
    print(json.dumps(response), flush=True)


def send_notification(method: str, params: Any = None):
    """Send a JSON-RPC notification."""
    notification = {"jsonrpc": JSONRPC_VERSION, "method": method}
    if params:
        notification["params"] = params
    print(json.dumps(notification), flush=True)


def find_llama_dir() -> Optional[str]:
    """Find llama.cpp installation directory."""
    candidates = [
        os.path.expanduser("~/llama.cpp"),
        os.path.expanduser("~/Projects/llama.cpp"),
    ]
    for path in candidates:
        if os.path.isdir(path):
            return path
    return None


def find_build_dir(llama_dir: str) -> Optional[str]:
    """Find llama.cpp build directory."""
    candidates = [
        os.path.join(llama_dir, "build-opencl"),
        os.path.join(llama_dir, "build"),
    ]
    for path in candidates:
        if os.path.isdir(os.path.join(path, "bin")):
            return path
    return None


def find_model_path(model_name: str) -> Optional[str]:
    """Find model file path."""
    models_dir = os.path.expanduser("~/models")

    # Check standard filename
    if model_name in MODEL_FILES:
        path = os.path.join(models_dir, MODEL_FILES[model_name])
        if os.path.isfile(path):
            return path

    # Check alternate filename
    if model_name in MODEL_FILES_ALT:
        path = os.path.join(models_dir, MODEL_FILES_ALT[model_name])
        if os.path.isfile(path):
            return path

    # Check if it's a direct path
    if os.path.isfile(model_name):
        return model_name

    # Check if it's a filename in models dir
    path = os.path.join(models_dir, model_name)
    if os.path.isfile(path):
        return path

    return None


def list_available_models() -> list[dict]:
    """List all available models."""
    models_dir = os.path.expanduser("~/models")
    available = []

    for name in ["qwen-0.5b", "qwen-1.5b", "qwen-3b", "llama-1b", "llama-3b"]:
        path = find_model_path(name)
        if path:
            size_mb = os.path.getsize(path) / (1024 * 1024)
            available.append({
                "name": name,
                "path": path,
                "size_mb": round(size_mb, 1),
            })

    # Also list any other .gguf files
    if os.path.isdir(models_dir):
        for f in os.listdir(models_dir):
            if f.endswith(".gguf"):
                # Skip if already listed
                full_path = os.path.join(models_dir, f)
                if not any(m["path"] == full_path for m in available):
                    size_mb = os.path.getsize(full_path) / (1024 * 1024)
                    available.append({
                        "name": f,
                        "path": full_path,
                        "size_mb": round(size_mb, 1),
                    })

    return available


class LlamaServer:
    """Manages llama-server backend process."""

    def __init__(self):
        self.process: Optional[subprocess.Popen] = None
        self.port = DEFAULT_LLAMA_SERVER_PORT
        self.model_path: Optional[str] = None
        self.model_name: Optional[str] = None

    def is_running(self) -> bool:
        """Check if server is running and responding."""
        if self.process is None or self.process.poll() is not None:
            return False

        try:
            url = f"http://127.0.0.1:{self.port}/health"
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=2) as resp:
                return resp.status == 200
        except:
            return False

    def start(self, model_name: str = DEFAULT_MODEL, ctx_size: int = DEFAULT_CTX_SIZE) -> bool:
        """Start llama-server with specified model."""
        if self.is_running():
            if self.model_name == model_name:
                return True  # Already running with same model
            self.stop()  # Stop to switch models

        model_path = find_model_path(model_name)
        if not model_path:
            log(f"Model not found: {model_name}")
            return False

        llama_dir = find_llama_dir()
        if not llama_dir:
            log("llama.cpp installation not found")
            return False

        build_dir = find_build_dir(llama_dir)
        if not build_dir:
            log("llama.cpp build directory not found")
            return False

        server_bin = os.path.join(build_dir, "bin", "llama-server")
        if not os.path.isfile(server_bin):
            log(f"llama-server not found at {server_bin}")
            return False

        # Set up environment
        env = os.environ.copy()
        lib_path = f"/vendor/lib64:{os.environ.get('PREFIX', '/data/data/com.termux/files/usr')}/lib:{build_dir}/lib"
        env["LD_LIBRARY_PATH"] = lib_path

        # Start server
        cmd = [
            server_bin,
            "-m", model_path,
            "-c", str(ctx_size),
            "--host", "127.0.0.1",  # Localhost only - security
            "--port", str(self.port),
            "-t", "4",
        ]

        log(f"Starting llama-server with {model_name}...")
        try:
            self.process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            log(f"Failed to start llama-server: {e}")
            return False

        # Wait for server to be ready
        for _ in range(30):  # 30 second timeout
            if self.is_running():
                self.model_path = model_path
                self.model_name = model_name
                log(f"llama-server ready on port {self.port}")
                return True
            time.sleep(1)

        log("llama-server failed to start in time")
        self.stop()
        return False

    def stop(self):
        """Stop llama-server."""
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None
            self.model_path = None
            self.model_name = None
            log("llama-server stopped")

    def complete(self, prompt: str, max_tokens: int = 256, temperature: float = 0.7) -> Optional[str]:
        """Generate completion."""
        if not self.is_running():
            return None

        url = f"http://127.0.0.1:{self.port}/completion"
        data = json.dumps({
            "prompt": prompt,
            "n_predict": max_tokens,
            "temperature": temperature,
            "stop": ["</s>", "<|im_end|>", "<|endoftext|>"],
        }).encode("utf-8")

        try:
            req = urllib.request.Request(
                url,
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                return result.get("content", "")
        except Exception as e:
            log(f"Completion error: {e}")
            return None

    def chat(self, messages: list[dict], max_tokens: int = 256, temperature: float = 0.7) -> Optional[str]:
        """Chat completion with message history."""
        if not self.is_running():
            return None

        url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
        data = json.dumps({
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }).encode("utf-8")

        try:
            req = urllib.request.Request(
                url,
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                choices = result.get("choices", [])
                if choices:
                    return choices[0].get("message", {}).get("content", "")
                return ""
        except Exception as e:
            log(f"Chat error: {e}")
            return None

    def status(self) -> dict:
        """Get server status."""
        return {
            "running": self.is_running(),
            "model": self.model_name,
            "model_path": self.model_path,
            "port": self.port,
        }


# Global server instance
llama_server = LlamaServer()


# MCP Tool definitions
TOOLS = [
    {
        "name": "llm_complete",
        "description": "Generate text completion using local LLM. Use for privacy-sensitive tasks that shouldn't be sent to cloud APIs.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "The prompt to complete"
                },
                "max_tokens": {
                    "type": "integer",
                    "description": "Maximum tokens to generate (default: 256)",
                    "default": 256
                },
                "temperature": {
                    "type": "number",
                    "description": "Sampling temperature 0-2 (default: 0.7)",
                    "default": 0.7
                },
                "model": {
                    "type": "string",
                    "description": "Model to use: qwen-0.5b, qwen-1.5b, llama-1b, llama-3b (default: auto)"
                }
            },
            "required": ["prompt"]
        }
    },
    {
        "name": "llm_chat",
        "description": "Chat with local LLM using message history. Use for privacy-sensitive conversations.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "messages": {
                    "type": "array",
                    "description": "Chat messages with role and content",
                    "items": {
                        "type": "object",
                        "properties": {
                            "role": {
                                "type": "string",
                                "enum": ["system", "user", "assistant"]
                            },
                            "content": {
                                "type": "string"
                            }
                        },
                        "required": ["role", "content"]
                    }
                },
                "max_tokens": {
                    "type": "integer",
                    "description": "Maximum tokens to generate (default: 256)",
                    "default": 256
                },
                "temperature": {
                    "type": "number",
                    "description": "Sampling temperature 0-2 (default: 0.7)",
                    "default": 0.7
                },
                "model": {
                    "type": "string",
                    "description": "Model to use: qwen-0.5b, qwen-1.5b, llama-1b, llama-3b (default: auto)"
                }
            },
            "required": ["messages"]
        }
    },
    {
        "name": "llm_list_models",
        "description": "List available local LLM models.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "llm_status",
        "description": "Check local LLM server status.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "llm_start",
        "description": "Start local LLM server with specified model.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "description": "Model to load: qwen-0.5b, qwen-1.5b, llama-1b, llama-3b"
                },
                "ctx_size": {
                    "type": "integer",
                    "description": "Context size in tokens (default: 4096)",
                    "default": 4096
                }
            }
        }
    },
    {
        "name": "llm_stop",
        "description": "Stop local LLM server to free resources.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    }
]


def handle_tool_call(name: str, arguments: dict) -> Any:
    """Handle a tool call and return the result."""

    if name == "llm_complete":
        prompt = arguments.get("prompt", "")
        max_tokens = arguments.get("max_tokens", 256)
        temperature = arguments.get("temperature", 0.7)
        model = arguments.get("model")

        # Start server if needed
        if model:
            if not llama_server.start(model):
                return {"error": f"Failed to start server with model: {model}"}
        elif not llama_server.is_running():
            # Auto-select first available model
            models = list_available_models()
            if not models:
                return {"error": "No models available. Download one with: download-model.sh qwen-0.5b"}
            if not llama_server.start(models[0]["name"]):
                return {"error": "Failed to start server"}

        result = llama_server.complete(prompt, max_tokens, temperature)
        if result is None:
            return {"error": "Completion failed"}
        return {"completion": result, "model": llama_server.model_name}

    elif name == "llm_chat":
        messages = arguments.get("messages", [])
        max_tokens = arguments.get("max_tokens", 256)
        temperature = arguments.get("temperature", 0.7)
        model = arguments.get("model")

        # Start server if needed
        if model:
            if not llama_server.start(model):
                return {"error": f"Failed to start server with model: {model}"}
        elif not llama_server.is_running():
            models = list_available_models()
            if not models:
                return {"error": "No models available. Download one with: download-model.sh qwen-0.5b"}
            if not llama_server.start(models[0]["name"]):
                return {"error": "Failed to start server"}

        result = llama_server.chat(messages, max_tokens, temperature)
        if result is None:
            return {"error": "Chat failed"}
        return {"response": result, "model": llama_server.model_name}

    elif name == "llm_list_models":
        models = list_available_models()
        return {"models": models, "count": len(models)}

    elif name == "llm_status":
        status = llama_server.status()
        status["available_models"] = len(list_available_models())
        return status

    elif name == "llm_start":
        model = arguments.get("model", DEFAULT_MODEL)
        ctx_size = arguments.get("ctx_size", DEFAULT_CTX_SIZE)

        if llama_server.start(model, ctx_size):
            return {"success": True, "model": model, "status": llama_server.status()}
        else:
            return {"success": False, "error": f"Failed to start with model: {model}"}

    elif name == "llm_stop":
        llama_server.stop()
        return {"success": True, "message": "Server stopped"}

    else:
        return {"error": f"Unknown tool: {name}"}


def handle_request(request: dict) -> None:
    """Handle a JSON-RPC request."""
    method = request.get("method")
    id = request.get("id")
    params = request.get("params", {})

    if method == "initialize":
        send_response(id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {
                "tools": {},
            },
            "serverInfo": {
                "name": SERVER_NAME,
                "version": SERVER_VERSION,
            }
        })

    elif method == "notifications/initialized":
        # Client acknowledged initialization
        pass

    elif method == "tools/list":
        send_response(id, {"tools": TOOLS})

    elif method == "tools/call":
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        try:
            result = handle_tool_call(tool_name, arguments)
            send_response(id, {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(result, indent=2)
                    }
                ]
            })
        except Exception as e:
            send_response(id, error={
                "code": -32000,
                "message": str(e)
            })

    elif method == "ping":
        send_response(id, {})

    else:
        if id is not None:
            send_response(id, error={
                "code": -32601,
                "message": f"Method not found: {method}"
            })


def main():
    """Main entry point for MCP server."""
    log("Starting MCP server...")

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            try:
                request = json.loads(line)
                handle_request(request)
            except json.JSONDecodeError as e:
                log(f"JSON parse error: {e}")
                continue
    except KeyboardInterrupt:
        pass
    finally:
        llama_server.stop()
        log("MCP server stopped")


if __name__ == "__main__":
    main()
