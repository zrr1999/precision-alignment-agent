#!/bin/bash

# Verify that the script is run from the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$SCRIPT_DIR" != "$PWD" ]; then
    echo "Error: This script must be run from the project root directory." >&2
    echo "  Script location: $SCRIPT_DIR" >&2
    echo "  Current directory: $PWD" >&2
    echo "  Please run: cd $SCRIPT_DIR && ./setup.sh" >&2
    exit 1
fi

# Install basic tools.
curl -LsSf https://astral.sh/uv/install.sh | sh
curl -fsSL https://bun.com/install | bash
eval "$(wget -O- https://get.x-cmd.com)"
x env use gh

# Install AI coding agent.
bun install -g opencode-ai

# Install skills.
git clone https://github.com/openprose/prose.git ~/.config/opencode/skills/open-prose
git clone https://github.com/ast-grep/agent-skill.git ~/.config/opencode/skills/ast-grep

# Create symlinks to skills directory
# After verification, $PWD == $SCRIPT_DIR, so use $PWD for better performance
mkdir -p "$PWD/.cursor" "$PWD/.opencode"
ln -sf "$PWD/skills" "$PWD/.cursor"
ln -sf "$PWD/skills" "$PWD/.opencode"
