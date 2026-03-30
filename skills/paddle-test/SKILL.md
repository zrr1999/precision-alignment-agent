---
name: paddle-test
description: Run Paddle unit tests and PaddleTest functional tests. Use when verifying code changes, running smoke tests after builds, or validating functional correctness.
---

# Paddle Test Runner

Run Paddle internal unit tests and PaddleTest functional tests. Both test types run twice — with `FLAGS_use_accuracy_compatible_kernel` set to 0 and 1 — to catch precision-related regressions.

**All commands must be run from the agent project root** (the directory containing the justfile). Pass paths as parameters.

**Do not confuse PaddleTest with PaddleAPITest:** PaddleTest = functional tests (this skill). PaddleAPITest = precision validation (use `precision-validation` skill instead).

## Paddle Unit Test

Run Paddle's own internal test files directly:

```bash
bash skills/paddle-test/scripts/run-unittest.sh PADDLE_PATH TEST_FILE
```

- `TEST_FILE` is a path relative to `PADDLE_PATH` (e.g., `test/legacy_test/test_layer_norm_op.py`)
- Runs via `uv run --no-project python`
- Tests execute twice (flag=0, flag=1)

## PaddleTest Functional Test

Run tests from the PaddleTest repo with pytest:

```bash
bash skills/paddle-test/scripts/run-paddletest.sh PADDLE_PATH PADDLETEST_PATH TEST_FILE
```

- `TEST_FILE` is a pytest-recognizable module/file (e.g., `test_layer_norm.py`)
- Uses the venv from `PADDLE_PATH/.venv`
- Tests execute twice (flag=0, flag=1)

## Parameters

| Parameter | Description |
|-----------|-------------|
| `PADDLE_PATH` | Absolute path to Paddle source tree (venv is at `.venv` inside) |
| `PADDLETEST_PATH` | Absolute path to PaddleTest repo |
| `TEST_FILE` | For unit tests: relative path to test script. For PaddleTest: pytest module/filename |

## Result Interpretation

- **OK**: All tests pass in both flag modes → safe to proceed
- **FAILED (N)**: N test cases failed → investigate failures, likely a code regression
- **ERROR**: Environment or setup issue → check venv, imports, missing deps

## Notes

- `FLAGS_use_accuracy_compatible_kernel` is set **internally** by the scripts. Do **not** add it again.
- Builder uses these for smoke testing after each Aligner change.
- Reviewer uses these for independent coverage verification before PR.
- For precision-level validation (atol=0, rtol=0), use the `precision-validation` skill instead.
