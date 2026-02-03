---
name: paddle-functional-testing
description: Run Paddle internal unit tests and PaddleTest repository tests for CI/CE validation. Prefer Justfile agentic commands (see just-workflow). Use when running ctest, unit tests, validating functional correctness, checking for regressions, or when the user mentions unit test, ctest, pytest, CI test, CE test, or PaddleTest.
---

# Paddle 功能测试指南

用于运行 Paddle 内部单测和 PaddleTest 仓库测试，验证功能正确性和回归问题。**由 D - 故障诊断官负责执行**。

## 优先使用 Justfile 命令（just-workflow）

执行功能测试时**优先使用**项目根目录 `Justfile` 中的 agentic 命令（详见 `just-workflow` skill）：

| 场景 | 命令 | 参数 |
|------|------|------|
| Paddle 内部单测 | `just agentic-run-paddle-unittest` | `VENV_PATH` `TEST_FILE`（测试脚本路径） |
| PaddleTest 功能测试 | `just agentic-run-paddletest` | `VENV_PATH` `PADDLETEST_PATH` `TEST_FILE`（pytest 模块/文件名，如 `test_layer_norm.py`） |

示例（在项目根目录，环境变量或路径已设置）：

```bash
# Paddle 内部单测
just agentic-run-paddle-unittest "${VENV_PATH}" "path/to/test_layer_norm_op.py"

# PaddleTest（TEST_FILE 为 framework/api/paddlebase 下的 pytest 目标）
just agentic-run-paddletest "${VENV_PATH}" "${PADDLETEST_PATH}" "test_layer_norm.py"
```

上述命令内部会使用 `uv run -p "{{VENV_PATH}}"` 及正确的工作目录，无需手写 `cd`/`pytest` 路径。

---

## 备用：直接运行方式

在无法使用 Justfile（如环境未配置 just、或需在非项目根执行）时，可按下述方式直接运行。

### Paddle 内部单测

```bash
# 运行特定测试文件（需在对应 venv 下）
uv run -p "${VENV_PATH}" python "path/to/test_layer_norm_op.py"
# 或
python test/legacy_test/test_layer_norm_op.py
```

### PaddleTest 仓库测试

```bash
cd "${PADDLETEST_PATH}/framework/api/paddlebase"
uv run -p "${VENV_PATH}" python -m pytest "test_layer_norm.py" -v
# 或
pytest test_layer_norm.py -v
```

### pytest 常用参数

- `-v` / `-vv`：详细输出
- `-k "expr"`：只运行匹配的测试
- `-x`：首个失败即停止
- `--tb=short`：简短 traceback

## 故障排查

- **找不到测试**：确认路径、工作目录；PaddleTest 需在 `framework/api/paddlebase` 下跑 pytest。
- **测试失败**：用 `-vv` 看详细输出，检查环境（GPU/CPU、Paddle 安装、venv）。
- **导入错误**：确认 Paddle 已安装、Python/venv 正确、必要时设置 PYTHONPATH。

## 职责说明

**D - 故障诊断官**：优先通过 `just agentic-run-paddle-unittest` / `just agentic-run-paddletest` 运行 Paddle 单测与 PaddleTest，验证功能正确性与回归；必要时使用上述备用命令。功能正确性验证用本 skill；精度对齐验证用 PaddleAPITest（见 `precision-testing` skill）。
