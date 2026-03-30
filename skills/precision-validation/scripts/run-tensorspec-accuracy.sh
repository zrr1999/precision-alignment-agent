#!/usr/bin/env bash
# precision-validation / run-tensorspec-accuracy.sh
# Run tensor-spec accuracy check (dual backend comparison).
# Usage: bash run-tensorspec-accuracy.sh VENV_PATH CASE_FILE LOG_DIR
set -euo pipefail

VENV_PATH="${1:?Usage: run-tensorspec-accuracy.sh VENV_PATH CASE_FILE LOG_DIR}"
CASE_FILE="${2:?Usage: run-tensorspec-accuracy.sh VENV_PATH CASE_FILE LOG_DIR}"
LOG_DIR="${3:?Usage: run-tensorspec-accuracy.sh VENV_PATH CASE_FILE LOG_DIR}"

mkdir -p "$LOG_DIR"
echo "Running tensor-spec accuracy check..."
echo "Case file: $CASE_FILE"
echo "Log dir: $LOG_DIR"
uvx tensor-spec check \
    --backend paddle --backend torch \
    --case-file "$CASE_FILE" \
    --python "$VENV_PATH/bin/python" \
    --log-file "$LOG_DIR/accuracy.jsonl" \
    --verbose || true
echo "---"
echo "Results: $LOG_DIR/accuracy.jsonl"
