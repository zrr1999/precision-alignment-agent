#!/usr/bin/env bash
# paddle-build / venv-setup.sh
# Create or update relocatable venv with Paddle deps.
# Usage: bash venv-setup.sh PADDLE_PATH
set -euo pipefail

PADDLE_PATH="${1:?Usage: venv-setup.sh PADDLE_PATH}"

cd "$PADDLE_PATH"
if [ ! -d "$PADDLE_PATH/.venv" ]; then
    uv venv --relocatable --seed --python 3.12
fi
source .venv/bin/activate
uvx prek install
uv pip install -r "$PADDLE_PATH/python/requirements.txt"
uv pip install wheel func_timeout pandas pebble pynvml pyyaml typer httpx "numpy<2.0" torchvision torch==2.9.1
uv pip install tensor_spec
echo "Dependencies install completed successfully in $PADDLE_PATH."
