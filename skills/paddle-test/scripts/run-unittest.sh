#!/usr/bin/env bash
# paddle-test / run-unittest.sh
# Run Paddle internal unit test with both accuracy-compatible kernel modes.
# Usage: bash run-unittest.sh PADDLE_PATH TEST_FILE
set -euo pipefail

PADDLE_PATH="${1:?Usage: run-unittest.sh PADDLE_PATH TEST_FILE}"
TEST_FILE="${2:?Usage: run-unittest.sh PADDLE_PATH TEST_FILE}"

cd "$PADDLE_PATH"

echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=0) for $TEST_FILE..."
FLAGS_use_accuracy_compatible_kernel=0 \
uv run --no-project python "$TEST_FILE"

echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=1) for $TEST_FILE..."
FLAGS_use_accuracy_compatible_kernel=1 \
uv run --no-project python "$TEST_FILE"
