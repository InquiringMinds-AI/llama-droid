"""CLI entry point for llama-droid."""

import sys


def main():
    """Main CLI entry point."""
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        from .mcp_server import main as serve_main
        serve_main()
    else:
        print("llama-droid - Local LLM runtime for Android")
        print("")
        print("Usage:")
        print("  llama-droid serve    Start MCP server")
        print("")
        print("For shell scripts, use:")
        print("  scripts/chat.sh      Interactive chat")
        print("  scripts/server.sh    HTTP API server")
        print("  scripts/download-model.sh  Download models")
        sys.exit(0)


if __name__ == "__main__":
    main()
