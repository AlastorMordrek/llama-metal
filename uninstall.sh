#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== llama-metal Uninstaller ==="
echo ""

REMOVED=0

BINARIES=(
    llama-server llama-cli llama-bench llama-perplexity
    llama-quantize llama-embedding llama-gguf llama-simple-chat
)

for bin in "${BINARIES[@]}"; do
    if [ -f "$HOME/.local/bin/$bin" ]; then
        echo "Removing $HOME/.local/bin/$bin..."
        rm -f "$HOME/.local/bin/$bin"
        REMOVED=1
    fi
done

for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$profile" ] && grep -q "# Added by llama-metal installer" "$profile" 2>/dev/null; then
        echo "Removing installer entries from $profile..."
        if [[ "$(uname -s)" == "Darwin" ]]; then
            sed -i '' '/# Added by llama-metal installer/d' "$profile"
            sed -i '' '/^$/N;/^\n$/d' "$profile"
        else
            sed -i '/# Added by llama-metal installer/d' "$profile"
            sed -i '/^$/N;/^\n$/d' "$profile"
        fi
        REMOVED=1
    fi
done

if [ -d "$SCRIPT_DIR/build" ]; then
    echo ""
    read -r -p "Remove build directory (~500 MB)? [y/N] " ans
    ans="$(echo "${ans:-n}" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
        rm -rf "$SCRIPT_DIR/build"
        REMOVED=1
    fi
fi

if [ "$REMOVED" -eq 0 ]; then
    echo "Nothing to uninstall."
else
    echo ""
    echo "llama-metal has been removed. To reinstall: ./install.sh"
fi
