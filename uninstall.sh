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
        rm -f "$HOME/.local/bin/$bin"
        echo "Removed $HOME/.local/bin/$bin"
        REMOVED=1
    fi
done

for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$profile" ] && grep -q "# Added by llama-metal installer" "$profile" 2>/dev/null; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            sed -i '' '/# Added by llama-metal installer/d' "$profile"
            sed -i '' '/^$/N;/^\n$/d' "$profile"
        else
            sed -i '/# Added by llama-metal installer/d' "$profile"
            sed -i '/^$/N;/^\n$/d' "$profile"
        fi
        echo "Cleaned PATH entries from $profile"
        REMOVED=1
    fi
done

if [ -d "$SCRIPT_DIR/build" ]; then
    echo ""
    echo "Build directory exists (~500 MB)."
    read -r -p "Remove it? [y/N] " ans
    ans="$(echo "${ans:-n}" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans" = "y" ] || [ "$ans" = "yes" ]; then
        rm -rf "$SCRIPT_DIR/build"
        echo "Removed build directory."
        REMOVED=1
    fi
fi

echo ""
if [ "$REMOVED" -eq 0 ]; then
    echo "Nothing to uninstall. llama-metal is not installed."
else
    echo "llama-metal has been removed."
    echo "To reinstall: cd $(pwd) && ./install.sh"
fi
