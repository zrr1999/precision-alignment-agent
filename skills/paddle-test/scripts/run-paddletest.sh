#!/usr/bin/env bash
# paddle-test / run-paddletest.sh
# Run PaddleTest functional test with both accuracy-compatible kernel modes.
# Usage: bash run-paddletest.sh PADDLE_PATH PADDLETEST_PATH TEST_FILE
set -euo pipefail

PADDLE_PATH="${1:?Usage: run-paddletest.sh PADDLE_PATH PADDLETEST_PATH TEST_FILE}"
PADDLETEST_PATH="${2:?Usage: run-paddletest.sh PADDLE_PATH PADDLETEST_PATH TEST_FILE}"
TEST_FILE="${3:?Usage: run-paddletest.sh PADDLE_PATH PADDLETEST_PATH TEST_FILE}"

VENV_PATH="$PADDLE_PATH/.venv"
cd "$PADDLETEST_PATH"

echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=0) for $TEST_FILE..."
FLAGS_use_accuracy_compatible_kernel=0 \
uv run --no-project -p "$VENV_PATH" python -m pytest "$TEST_FILE" -v

echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=1) for $TEST_FILE..."
FLAGS_use_accuracy_compatible_kernel=1 \
uv run --no-project -p "$VENV_PATH" python -m pytest "$TEST_FILE" -v
