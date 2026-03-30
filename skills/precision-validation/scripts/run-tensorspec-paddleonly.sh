#!/usr/bin/env bash
# precision-validation / run-tensorspec-paddleonly.sh
# Run tensor-spec paddleonly check (single backend, crash detection).
# Usage: bash run-tensorspec-paddleonly.sh VENV_PATH CASE_FILE LOG_DIR
set -euo pipefail

VENV_PATH="${1:?Usage: run-tensorspec-paddleonly.sh VENV_PATH CASE_FILE LOG_DIR}"
CASE_FILE="${2:?Usage: run-tensorspec-paddleonly.sh VENV_PATH CASE_FILE LOG_DIR}"
LOG_DIR="${3:?Usage: run-tensorspec-paddleonly.sh VENV_PATH CASE_FILE LOG_DIR}"

mkdir -p "$LOG_DIR"
echo "Running tensor-spec paddleonly check..."
echo "Case file: $CASE_FILE"
echo "Log dir: $LOG_DIR"
uvx tensor-spec check \
    --backend paddle \
    --case-file "$CASE_FILE" \
    --python "$VENV_PATH/bin/python" \
    --log-file "$LOG_DIR/paddleonly.jsonl" \
    --verbose || true
echo "---"
echo "Results: $LOG_DIR/paddleonly.jsonl"
