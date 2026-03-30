#!/usr/bin/env bash
# precision-validation / get-configs.sh
# Extract precision test configs for an API from PaddleAPITest paa.txt.
# Usage: bash get-configs.sh API_NAME PADDLEAPITEST_PATH OUTPUT_DIR
set -euo pipefail

API_NAME="${1:?Usage: get-configs.sh API_NAME PADDLEAPITEST_PATH [OUTPUT_DIR]}"
PADDLEAPITEST_PATH="${2:?Usage: get-configs.sh API_NAME PADDLEAPITEST_PATH [OUTPUT_DIR]}"
OUTPUT_DIR="${3:-.paddle-pilot/config}"

mkdir -p "$OUTPUT_DIR"
cat "$PADDLEAPITEST_PATH/.api_config/paa-v0/paa/paa.txt" | grep "$API_NAME" > "$OUTPUT_DIR/$API_NAME.txt"
echo "Config file saved to $OUTPUT_DIR/$API_NAME.txt"
