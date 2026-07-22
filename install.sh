#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OS="$(uname -s)"
HOSTNAME="$(hostname -s 2>/dev/null || echo "your-computer")"

echo "=== llama-metal Installer ==="
echo ""

if [ "$OS" != "Darwin" ]; then
    echo "llama-metal currently supports macOS only."
    echo "Linux and Windows support is planned for future releases."
    exit 1
fi

REQUIRED_MISSING=""
command -v cmake &>/dev/null || REQUIRED_MISSING="$REQUIRED_MISSING cmake"

if [ -n "$REQUIRED_MISSING" ]; then
    echo "Required tools not found:$REQUIRED_MISSING"
    echo ""
    if command -v brew &>/dev/null; then
        read -r -p "Install with Homebrew? [Y/n] " ans
        ans="$(echo "${ans:-y}" | tr '[:upper:]' '[:lower:]')"
        if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
            brew install$REQUIRED_MISSING
        else
            exit 1
        fi
    else
        echo "Install Homebrew first: https://brew.sh"
        exit 1
    fi
fi

echo "Detecting GPU..."
ARCH="$(uname -m)"
GPU_TYPE="cpu-only"

if [ "$ARCH" = "arm64" ]; then
    GPU_TYPE="apple-silicon"
elif system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "AMD Radeon"; then
    GPU_TYPE="amd-metal"
fi

echo ""
echo "--------------------------------------------------"
case "$GPU_TYPE" in
    apple-silicon)
        echo "  Apple Silicon (M-series) — native Metal support"
        METAL_FLAGS="-DGGML_METAL=ON -DGGML_ACCELERATE=ON"
        ;;
    amd-metal)
        echo "  Intel Mac + AMD Radeon GPU — Metal with AMD patches"
        echo ""
        echo "  This repo includes community patches from iRon-Llama"
        echo "  that fix AMD Radeon GPU output on Intel Macs."
        METAL_FLAGS="-DGGML_METAL=ON -DGGML_METAL_MGPU=ON -DGGML_ACCELERATE=ON"
        ;;
    *)
        echo "  Intel Mac (no AMD dGPU) — CPU-only with Accelerate BLAS"
        METAL_FLAGS="-DGGML_ACCELERATE=ON"
        ;;
esac
echo "--------------------------------------------------"
echo ""

if command -v brew &>/dev/null; then
    OPTDEPS_MISSING=""
    if [ "$GPU_TYPE" != "cpu-only" ] && ! command -v glslang &>/dev/null; then
        OPTDEPS_MISSING="$OPTDEPS_MISSING glslang"
    fi
    if ! brew list libomp &>/dev/null 2>&1; then
        OPTDEPS_MISSING="$OPTDEPS_MISSING libomp"
    fi
    if [ -n "$OPTDEPS_MISSING" ]; then
        echo "Optional build dependencies:$OPTDEPS_MISSING"
        echo "These improve performance. Building still works without them."
        read -r -p "Install them with Homebrew? [Y/n] " ans
        ans="$(echo "${ans:-y}" | tr '[:upper:]' '[:lower:]')"
        if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
            brew install$OPTDEPS_MISSING
        fi
        echo ""
    fi
fi

BUILD_DIR="$SCRIPT_DIR/build"

echo "Building llama.cpp (this may take a few minutes)..."
echo ""

OMP_FLAG=""
if brew list libomp &>/dev/null 2>&1; then
    OMP_FLAG="-DOpenMP_ROOT=$(brew --prefix)/opt/libomp"
fi

cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    $METAL_FLAGS \
    $OMP_FLAG \
    -DCMAKE_C_FLAGS="-march=native -O3" \
    -DCMAKE_CXX_FLAGS="-march=native -O3" \
    2>&1 | tail -1

NCPU="$(sysctl -n hw.ncpu)"
cmake --build "$BUILD_DIR" -j"$NCPU" 2>&1 | tail -3

echo ""
echo "Build complete."

BIN_SRC="$BUILD_DIR/bin"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

install_binary() {
    local name="$1"
    local src="$BIN_SRC/$name"
    if [ ! -f "$src" ]; then
        return 0
    fi
    local wrapper="$BIN_DIR/$name"

    cat > "$wrapper" << EOFWRAPPER
#!/usr/bin/env bash
export DYLD_LIBRARY_PATH="$BIN_SRC:\$DYLD_LIBRARY_PATH"
EOFWRAPPER

    if [ "$GPU_TYPE" = "amd-metal" ]; then
        cat >> "$wrapper" << 'EOFWRAPPER'
export GGML_METAL_DEVICE_INDEX=1
export GGML_METAL_N_CB=4
EOFWRAPPER
    fi

    cat >> "$wrapper" << EOFWRAPPER
exec "$src" "\$@"
EOFWRAPPER
    chmod +x "$wrapper"
    echo "  $name"
}

echo ""
echo "Installing binaries..."
install_binary "llama-server"
install_binary "llama-cli"
install_binary "llama-bench"
install_binary "llama-perplexity"
install_binary "llama-quantize"
install_binary "llama-embedding"
install_binary "llama-gguf"
install_binary "llama-simple-chat"

echo ""
echo "--------------------------------------------------"
echo "  llama-metal is installed on $HOSTNAME."
echo "  Binaries: $BIN_DIR"
echo "--------------------------------------------------"
echo ""

SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
EXPORT_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""

case "$SHELL_NAME" in
    zsh)  PROFILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
        if [ "$OS" = "Darwin" ]; then
            PROFILE="$HOME/.bash_profile"
            [ -f "$PROFILE" ] || PROFILE="$HOME/.bashrc"
        else
            PROFILE="$HOME/.bashrc"
            [ -f "$PROFILE" ] || PROFILE="$HOME/.bash_profile"
        fi
        ;;
    *)    PROFILE="$HOME/.profile" ;;
esac

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "  Adding ~/.local/bin to $PROFILE"
    echo "" >> "$PROFILE"
    echo "# Added by llama-metal installer ($(date))" >> "$PROFILE"
    echo "$EXPORT_LINE" >> "$PROFILE"
    export PATH="$BIN_DIR:$PATH"
fi

echo "  Quick reference:"
echo ""
echo "    Download a GGUF model to get started:"
echo "      curl -L -o model.gguf https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf"
echo ""
echo "    Start an OpenAI-compatible API server:"
echo "      llama-server -m model.gguf --port 8010"
echo ""
echo "    Chat from the terminal:"
echo "      llama-cli -m model.gguf -p \"Hello\""
echo ""
echo "    Benchmark your setup:"
echo "      llama-bench -m model.gguf -p 64 -n 64"
echo ""
if [ "$GPU_TYPE" = "amd-metal" ]; then
    echo "  AMD GPU: GGML_METAL_DEVICE_INDEX=1 GGML_METAL_N_CB=4 (set automatically)"
fi
echo "--------------------------------------------------"
echo ""
echo "To uninstall:"
echo "  ./uninstall.sh"
