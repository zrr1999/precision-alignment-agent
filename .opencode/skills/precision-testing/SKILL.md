---
name: paddle-precision-testing
description: Use PaddleAPITest for precision alignment testing between Paddle and PyTorch APIs. Prefer Justfile agentic command (see just-workflow). Focus on accuracy testing with strict tolerance (--atol=0 --rtol=0). Use when aligning Paddle API precision with PyTorch, running accuracy tests, analyzing precision errors, or when the user mentions precision alignment, accuracy test, PaddleAPITest, or precision validation.
---

# PaddleAPITest 精度对齐测试指南

用于精度对齐场景，通过对比 Paddle 和 PyTorch API 的前反向结果来验证精度对齐。**由 V - 精度验证师负责执行**。

## 优先使用 Justfile 命令（just-workflow）

执行精度测试时**优先使用**项目根目录 `Justfile` 中的 agentic 命令（详见 `just-workflow` skill）：

| 场景 | 命令 | 参数 |
|------|------|------|
| PaddleAPITest 精度验证 | `just agentic-run-precision-test` | `VENV_PATH` `PADDLEAPITEST_PATH` `CONFIG_FILE` `LOG_DIR` |

该命令会以 `--atol=0 --rtol=0 --accuracy=True` 运行 `engineV2.py`，并输出日志目录路径。

示例（在项目根目录，环境变量或路径已设置）：

```bash
just agentic-run-precision-test "${VENV_PATH}" "${PADDLEAPITEST_PATH}" "error_config_layer_norm_v2.txt" "./logs"
```

输出会包含日志目录及完整路径（如 `{{PADDLEAPITEST_PATH}}/{{LOG_DIR}}`）。

---

## 备用：直接运行方式

在无法使用 Justfile 时，可手动执行：

**文件模式（批量）**：

```bash
cd "${PADDLEAPITEST_PATH}"
uv run -p "${VENV_PATH}" python engineV2.py \
  --atol=0 --rtol=0 --accuracy=True \
  --api_config_file="error_config_layer_norm_v2.txt" \
  --log_dir="./logs"
```

**单配置模式**：

```bash
uv run -p "${VENV_PATH}" python engineV2.py \
  --atol=0 --rtol=0 --accuracy=True \
  --api_config='paddle.Tensor.lerp(x=Tensor([4],"float32"), y=Tensor([4],"float32"), weight=0.5, )'
```

**关键参数**：`--atol=0 --rtol=0`、`--accuracy=True`、`--api_config_file` / `--api_config`、`--log_dir`（可选）。

## 环境与配置

- 环境：python >= 3.10，PaddlePaddle（develop），PyTorch，PaddleAPITest 代码库；依赖：`func_timeout pandas pebble pynvml pyyaml typer` 等（Justfile `agentic-venv-setup` 已包含）。
- 配置格式示例：`paddle.Tensor.lerp(x=Tensor([4],"float32"), y=Tensor([4],"float32"), weight=0.5, )`；配置文件用双引号，命令行单配置用单引号。

## 结果与错误分类

结果在 `tester/api_config/5_accuracy/` 及 `--log_dir` 指定目录。常见错误文件：`accuracy_gpu_error.txt`、`accuracy_gpu_kernel.txt`、`accuracy_cpu_error.txt`、`accuracy_cpu_kernel.txt` 等；可用 `grep "${API_NAME}"` 定位错误配置。

## 与工作流集成

1. 建立基线：用 PaddleAPITest 建立失败基线（优先 `just agentic-run-precision-test`）。
2. 修复实现：根据对比分析修复 CUDA Kernel。
3. 验证修复：再次运行精度测试，对比日志。
4. 最终验收：确保相关 case 通过。

## 故障排查

- 配置格式：双引号/括号匹配、单引号包裹命令行配置。
- 版本：确认 Paddle 与 PyTorch 兼容。
- 精度/AMP：必要时尝试 `--test_amp=True`；需遇错即退可加 `--exit_on_error=True`。

## 职责说明

**V - 精度验证师**：优先通过 `just agentic-run-precision-test` 进行精度对齐测试、建立基线、验证修复；必要时使用上述备用命令。功能正确性验证用 Paddle 单测/CI/CE（见 `paddle-functional-testing` skill）。
