---
name: precision-validation
description: Run PaddleAPITest precision tests and tensor-spec checks. Use when validating precision alignment (atol=0, rtol=0), extracting API configs, or running bug-fix crash/accuracy checks.
---

# Precision Validation

Precision-level validation for Paddle APIs. Covers PaddleAPITest (precision alignment workflow) and tensor-spec (bug-fix workflow).

**All commands must be run from the agent project root** (the directory containing the justfile). Pass paths as parameters.

**Do not confuse PaddleAPITest with PaddleTest:** PaddleAPITest = precision validation (this skill, atol=0/rtol=0). PaddleTest = functional tests (use `paddle-test` skill instead).

## 1. Extract Precision Config

Get API-specific test configs from PaddleAPITest's config registry:

```bash
bash skills/precision-validation/scripts/get-configs.sh API_NAME PADDLEAPITEST_PATH [OUTPUT_DIR]
```

- Extracts matching lines from `paa.txt` into a config file
- Default output: `.paddle-pilot/config/{API_NAME}.txt`
- Example: `get-configs.sh paddle.pow /path/to/PaddleAPITest`

## 2. PaddleAPITest Precision Test (GPU)

Run precision validation with strict tolerances:

```bash
bash skills/precision-validation/scripts/run-precision-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR
```

- Runs `engineV2.py` with `--atol=0 --rtol=0 --accuracy=True`
- `FLAGS_use_accuracy_compatible_kernel=1` is set internally
- Logs go to `PADDLEAPITEST_PATH/paddle_pilot_test_log/{LOG_DIR}/`

## 3. PaddleAPITest Precision Test (CPU)

Same as GPU but with `--test_cpu=1`:

```bash
bash skills/precision-validation/scripts/run-precision-cpu-test.sh PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR
```

## 4. Tensor-Spec Paddleonly (Bug-Fix Stage A)

Single-backend crash detection:

```bash
bash skills/precision-validation/scripts/run-tensorspec-paddleonly.sh VENV_PATH CASE_FILE LOG_DIR
```

- Runs `uvx tensor-spec check --backend paddle`
- Detects crashes, exceptions, shape mismatches
- Results: `{LOG_DIR}/paddleonly.jsonl`

## 5. Tensor-Spec Accuracy (Bug-Fix Stage B)

Dual-backend precision comparison:

```bash
bash skills/precision-validation/scripts/run-tensorspec-accuracy.sh VENV_PATH CASE_FILE LOG_DIR
```

- Compares Paddle vs PyTorch output
- Results: `{LOG_DIR}/accuracy.jsonl`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `PADDLE_PATH` | Absolute path to Paddle source tree (venv is at `.venv` inside) |
| `PADDLEAPITEST_PATH` | Absolute path to PaddleAPITest repo |
| `CONFIG_FILE` | PaddleAPITest config filename (e.g., `error_config_layer_norm_v2.txt`) |
| `LOG_DIR` | Log output directory name (relative to `paddle_pilot_test_log/`) |
| `VENV_PATH` | Absolute path to the virtual environment (for tensor-spec) |
| `CASE_FILE` | Tensor-spec case file path |
| `API_NAME` | API name for config extraction (e.g., `paddle.pow`) |

## Result Files

- **PaddleAPITest**: `accuracy_*_error.txt` / `accuracy_*_kernel.txt` under log directory
- **Tensor-spec**: `.jsonl` files with per-case pass/fail

## Notes

- This skill is used **only** by the Validator role.
- Passing PaddleTest path instead of PaddleAPITest path is a common mistake — they are different repos.
- Old log files are automatically cleaned before each run.
- `FLAGS_use_accuracy_compatible_kernel` is set internally. Do **not** add it again.
