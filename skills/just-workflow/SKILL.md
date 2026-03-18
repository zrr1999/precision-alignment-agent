---
name: just-workflow
description: Use justfile agentic commands to run workflows (venv, Paddle install, unit test, PaddleTest, precision test). Prefer these commands over raw bash when running tests or setting up environments.
---

# Just Workflow Skill

For testing and environment-related operations, **prioritize the justfile commands defined in this skill**. The `justfile` is located at the project root.

**Do not confuse PaddleTest with PaddleAPITest:** they are different repos and different commands. **PaddleTest** = functional tests (`agentic-run-paddletest`, `PADDLETEST_PATH`) — used by Diagnostician and Reviewer. **PaddleAPITest** = precision validation (`agentic-run-precision-test`, `PADDLEAPITEST_PATH`) — used **only** by Validator. Passing the wrong path (e.g. PaddleTest path to Validator) will cause failures.

## Where to run just (mandatory)

**All `just` commands must be run from the directory that contains the justfile**—i.e. the agent project root (the paddle-pilot repo root, typically the same directory from which the agent is invoked). **Do not** `cd` into `paddle_path`, `pytorch_path`, `paddletest_path`, or any other development repo and run `just` there; the justfile is not in those repos. Pass paths to Paddle/PaddleTest/etc. as **parameters** to the recipes (e.g. `VENV_PATH`, `PADDLE_PATH`, `PADDLETEST_PATH`), and invoke `just` from the agent main directory only.

## Core Usage

| Scenario | Command | Parameters | Description |
|----------|---------|------------|-------------|
| Repos Setup | `just agentic-repos-setup` | `PADDLE_PATH` `PADDLETEST_PATH` `PADDLEAPITEST_PATH` `PYTORCH_PATH` | Link external repos into .paddle-pilot/worktree/ (TODO: pending) |
| Environment Setup | `just agentic-venv-setup` | `VENV_PATH` `PADDLE_PATH` | Create/update relocatable venv, install dependencies and Paddle whl |
| Get Precision Config | `just agentic-get-precision-test-configs` | `API_NAME` `PADDLEAPITEST_PATH` | Extract API configs from paa.txt to .paddle-pilot/config/{API_NAME}.txt |
| Paddle Install | `just agentic-paddle-install` | `VENV_PATH` `PADDLE_PATH` | Create venv in specified directory and install only Paddle whl (no other dependencies) |
| Paddle Unit Test | `just agentic-run-paddle-unittest` | `VENV_PATH` `TEST_FILE` | Run Paddle internal unit tests using specified venv (directly execute Python test file) |
| PaddleTest | `just agentic-run-paddletest` | `VENV_PATH` `PADDLETEST_PATH` `TEST_FILE` | Run specified test file with pytest under `framework/api/paddlebase` in PaddleTest |
| PaddleAPITest | `just agentic-run-precision-test` | `VENV_PATH` `PADDLEAPITEST_PATH` `CONFIG_FILE` `LOG_DIR` | Run PaddleAPITest precision validation (atol=0, rtol=0, accuracy=True) and output log directory path |

## Parameter Descriptions

| Parameter | Description |
|-----------|-------------|
| `VENV_PATH` | Absolute path to the virtual environment |
| `PADDLE_PATH` | Absolute path to Paddle codebase |
| `PADDLETEST_PATH` | Absolute path to PaddleTest codebase |
| `PADDLEAPITEST_PATH` | Absolute path to PaddleAPITest codebase |
| `TEST_FILE` | Test file path (for unit tests) or filename (for PaddleTest, e.g., `test_layer_norm.py`) |
| `CONFIG_FILE` | PaddleAPITest config filename or path (e.g., `error_config_layer_norm_v2.txt`) |
| `LOG_DIR` | Log output directory name or path (optional, default `./logs`) |

## Examples

```bash
# List all commands
just

# Environment setup: create venv and install Paddle with dependencies
just agentic-venv-setup /path/to/venv /path/to/Paddle

# Verify Paddle installation only
just agentic-paddle-install /path/to/venv /path/to/Paddle

# Get precision test configs for an API (output: .paddle-pilot/config/{api_name}.txt)
just agentic-get-precision-test-configs paddle.pow /path/to/PaddleAPITest

# Paddle internal unit test (TEST_FILE is relative path to test script)
just agentic-run-paddle-unittest /path/to/venv /path/to/Paddle test/legacy_test/test_layer_norm_op.py

# PaddleTest (TEST_FILE is pytest-recognizable module/file, e.g., test_layer_norm.py)
just agentic-run-paddletest /path/to/venv /path/to/PaddleTest test_layer_norm.py

# PaddleAPITest precision test (CONFIG_FILE is config filename/path, LOG_DIR is log output directory/path)
just agentic-run-precision-test /path/to/venv /path/to/PaddleAPITest error_config_layer_norm_v2.txt ./logs
```

## Notes

- **Use only `agentic-` recipes**: These are for Agent use; recipes without this prefix are for human use.
- **Environment variables**: All agentic commands depend on the caller having set `VENV_PATH`, `PADDLE_PATH`, `PADDLETEST_PATH`, `PADDLEAPITEST_PATH`, etc. (see each command's parameters). You may add env vars before `just` (e.g. `VAR=value just agentic-...`) when needed.
- **Built-in env vars in justfile**: `agentic-run-paddle-unittest`, `agentic-run-paddletest`, and `agentic-run-precision-test` already set `FLAGS_use_accuracy_compatible_kernel` internally. Do **not** add it again.
- **TEST_FILE distinction**: For Paddle internal unit tests, it's the full Python file path; for PaddleTest, it's a pytest-recognizable module/filename.
- **Troubleshooting**: Check command output for errors, and verify that passed paths match the parameter meanings defined in the root `justfile`.
- **Precision test (Validator)**: Results and logs go to the `LOG_DIR` (or default) under PaddleAPITest; error files include `accuracy_*_error.txt` / `accuracy_*_kernel.txt`. Use the log directory path reported by the command in session reports.
- **Functional test (Diagnostician)**: Interpret as OK / FAILED (N) / ERROR (env or setup). Run smoke test after each Aligner change; run broader coverage before handoff.
