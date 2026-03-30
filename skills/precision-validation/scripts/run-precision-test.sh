#!/usr/bin/env bash
# precision-validation / run-precision-test.sh
# Run PaddleAPITest precision validation (GPU).
# Usage: bash run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR
set -euo pipefail

PADDLE_PATH="${1:?Usage: run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR}"
PADDLEAPITEST_PATH="${2:?Usage: run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR}"
CONFIG_FILE="${3:?Usage: run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR}"
LOG_DIR="${4:?Usage: run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR}"

VENV_PATH="$PADDLE_PATH/.venv"
cd "$PADDLEAPITEST_PATH"
echo "Removing old log files..."
rm -f "paddle_pilot_test_log/$LOG_DIR"/*.txt
rm -f "paddle_pilot_test_log/$LOG_DIR"/*.log
echo "Running PaddleAPITest(FLAGS_use_accuracy_compatible_kernel=1) with config: $CONFIG_FILE..."

FLAGS_use_accuracy_compatible_kernel=1 \
uv run --no-project -p "$VENV_PATH" python engineV2.py \
    --atol=0 \
    --rtol=0 \
    --accuracy=True \
    --api_config_file="$CONFIG_FILE" \
    --log_dir="paddle_pilot_test_log/$LOG_DIR"

echo "---"
echo "Log directory: paddle_pilot_test_log/$LOG_DIR"
echo "Full path: $PADDLEAPITEST_PATH/paddle_pilot_test_log/$LOG_DIR"
