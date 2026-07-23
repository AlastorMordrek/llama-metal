#!/usr/bin/env bash
set -euo pipefail

# When piped from stdin (curl | bash), BASH_SOURCE[0] is empty.
# Clone the repo locally and re-execute from there.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ ! -f "$(dirname "${BASH_SOURCE[0]:-$PWD}")/CMakeLists.txt" ]; then
    TARGET="${LLAMA_METAL_DIR:-$HOME/llama-metal}"
    echo "=== llama-metal Installer ==="
    echo ""
    echo "Downloading to $TARGET..."
    mkdir -p "$(dirname "$TARGET")"
    git clone --depth=1 https://github.com/AlastorMordrek/llama-metal.git "$TARGET"
    cd "$TARGET"
    exec bash install.sh
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OS="$(uname -s)"
HOSTNAME="$(hostname -s 2>/dev/null || echo "your-computer")"

echo "=== llama-metal Installer ==="
echo ""

if [ "$OS" != "Darwin" ]; then
    echo "llama-metal currently supports macOS only."
    echo "Linux support is planned for a future release."
    exit 1
fi

ARCH="$(uname -m)"
GPU_TYPE="cpu-only"

echo "Detecting GPU..."
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
        echo "  Your Mac has a unified GPU. No patches needed."
        METAL_FLAGS="-DGGML_METAL=ON -DGGML_ACCELERATE=ON"
        ;;
    amd-metal)
        echo "  Intel Mac + AMD Radeon — Metal with AMD patches"
        echo ""
        echo "  This fork includes community-tested fixes that make"
        echo "  AMD Radeon GPUs produce correct output on Intel Macs."
        METAL_FLAGS="-DGGML_METAL=ON -DGGML_ACCELERATE=ON"
        ;;
    *)
        echo "  Intel Mac (no AMD discrete GPU) — CPU only"
        echo "  Metal backend not available on this hardware."
        METAL_FLAGS="-DGGML_ACCELERATE=ON"
        ;;
esac
echo "--------------------------------------------------"
echo ""

if ! command -v cmake &>/dev/null; then
    echo "Required tool 'cmake' not found."
    echo ""
    if command -v brew &>/dev/null; then
        read -r -p "Install cmake with Homebrew? [Y/n] " ans
        ans="$(echo "${ans:-y}" | tr '[:upper:]' '[:lower:]')"
        if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
            brew install cmake
        else
            echo "Aborting. Install cmake and re-run: ./install.sh"
            exit 1
        fi
    else
        echo "Install Homebrew first: https://brew.sh"
        echo "Then re-run: ./install.sh"
        exit 1
    fi
fi

if command -v brew &>/dev/null; then
    OPTDEPS=""
    if ! brew list libomp &>/dev/null 2>&1; then
        OPTDEPS="$OPTDEPS libomp"
    fi
    if [ "$GPU_TYPE" != "cpu-only" ] && ! command -v glslang &>/dev/null; then
        OPTDEPS="$OPTDEPS glslang"
    fi
    if [ -n "$OPTDEPS" ]; then
        echo "Optional build dependencies:$OPTDEPS"
        echo "These improve performance. Building still works without them."
        read -r -p "Install with Homebrew? [Y/n] " ans
        ans="$(echo "${ans:-y}" | tr '[:upper:]' '[:lower:]')"
        if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
            brew install $OPTDEPS
        fi
        echo ""
    fi
fi

BUILD_DIR="$SCRIPT_DIR/build"

echo "Building llama.cpp (this takes a few minutes)..."
echo ""

OMP_FLAG=""
if brew list libomp &>/dev/null 2>&1; then
    OMP_FLAG="-DOpenMP_ROOT=$(brew --prefix)/opt/libomp"
fi

echo "  Configuring..."
cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    $METAL_FLAGS \
    $OMP_FLAG \
    -DGGML_NATIVE=ON

echo ""
echo "  Compiling..."
NCPU="$(sysctl -n hw.ncpu)"
cmake --build "$BUILD_DIR" -j"$NCPU"

echo ""
echo "Build complete."

BIN_SRC="$BUILD_DIR/bin"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

install_wrapper() {
    local name="$1"
    local src="$BIN_SRC/$name"
    if [ ! -f "$src" ]; then
        return 0
    fi
    local wrapper="$BIN_DIR/$name"

    cat > "$wrapper" << WRAPPER_HEAD
#!/usr/bin/env bash
export DYLD_LIBRARY_PATH="$BIN_SRC:\$DYLD_LIBRARY_PATH"
WRAPPER_HEAD

    if [ "$GPU_TYPE" = "amd-metal" ]; then
        cat >> "$wrapper" << 'WRAPPER_AMD'
export GGML_METAL_DEVICE_INDEX=0
export GGML_METAL_N_CB=4
WRAPPER_AMD
    fi

    cat >> "$wrapper" << WRAPPER_TAIL
exec "$src" "\$@"
WRAPPER_TAIL
    chmod +x "$wrapper"
    echo "  $name"
}

echo ""
echo "Installing binaries..."
INSTALLED=0
for bin in llama-server llama-cli llama-bench llama-perplexity llama-quantize llama-embedding llama-gguf llama-simple-chat; do
    if [ -f "$BIN_SRC/$bin" ]; then
        install_wrapper "$bin"
        INSTALLED=1
    fi
done

if [ "$INSTALLED" -eq 0 ]; then
    echo "  No binaries found at $BIN_SRC"
    echo "  Something went wrong during the build."
    exit 1
fi

echo ""
echo "--------------------------------------------------"
echo "  llama-metal is ready on $HOSTNAME."
echo "  Binaries: $BIN_DIR"
echo "--------------------------------------------------"
echo ""

echo "  Your terminal doesn't know about these commands yet."
echo ""
echo "  Would you like to add ~/.local/bin to your PATH so"
echo "  'llama-cli', 'llama-server', etc. work everywhere?"
echo ""
echo "    [Y] Yes — add to PATH (recommended, default)"
echo "    [N] No — I'll manage it myself"
echo ""

read -r -p "Your choice [Y/n]: " raw
choice="$(echo "${raw:-y}" | tr '[:upper:]' '[:lower:]')"

if [ "$choice" = "y" ] || [ "$choice" = "yes" ]; then
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
        if grep -qF "$EXPORT_LINE" "$PROFILE" 2>/dev/null; then
            echo "~/.local/bin already in $PROFILE — skipping."
        else
            echo "" >> "$PROFILE"
            echo "# Added by llama-metal installer ($(date))" >> "$PROFILE"
            echo "$EXPORT_LINE" >> "$PROFILE"
            echo "Added ~/.local/bin to $PROFILE"
        fi
        export PATH="$BIN_DIR:$PATH"
    fi
    CMD_PREFIX=""
else
    echo "Skipping PATH setup. Use full paths or cd to $BIN_DIR"
    CMD_PREFIX="$BIN_DIR/"
fi

echo ""
echo "--------------------------------------------------"
echo "  Quick reference:"
echo ""
echo "    Download a model:"
echo "      curl -L -o model.gguf https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf"
echo ""
echo "    Chat from the terminal:"
echo "      ${CMD_PREFIX}llama-cli -m model.gguf -p \"Hello\""
echo ""
echo "    Start an API server:"
echo "      ${CMD_PREFIX}llama-server -m model.gguf --port 8010"
echo ""
echo "    Benchmark your setup:"
echo "      ${CMD_PREFIX}llama-bench -m model.gguf -p 64 -n 64"
echo "--------------------------------------------------"
echo ""
echo "To uninstall:"
echo "  cd $(pwd) && ./uninstall.sh"
