#!/usr/bin/env bash
# paddle-build / paddle-build.sh
# Build and install Paddle in the worktree's virtual environment.
# Usage: bash paddle-build.sh PADDLE_PATH
set -euo pipefail

PADDLE_PATH="${1:?Usage: paddle-build.sh PADDLE_PATH}"

echo "Building Paddle..."
cd "$PADDLE_PATH"
source .venv/bin/activate
mkdir -p build
cd build
cmake .. -DPADDLE_VERSION=0.0.0 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCUDA_ARCH_NAME=Auto -DWITH_GPU=ON -DWITH_DISTRIBUTE=ON -DWITH_UNITY_BUILD=OFF -DWITH_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DWITH_CINN=ON -GNinja \
-DPY_VERSION=3.12 -DPYTHON_EXECUTABLE=$(which python) -DPYTHON_INCLUDE_DIR=$(python -c "import sysconfig; print(sysconfig.get_path('include'))") -DPYTHON_LIBRARY=$(python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))")/libpython3.so
ninja -j$(nproc)
echo "Installing Paddle..."
cd "$PADDLE_PATH"
uv pip install "$PADDLE_PATH"/build/python/dist/*.whl --no-deps --force-reinstall
echo "Paddle build and install completed successfully."
