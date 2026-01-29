---
name: paddle-precision-testing
description: Use PaddleAPITest for precision alignment testing between Paddle and PyTorch APIs. Focus on accuracy testing with strict tolerance (--atol=0 --rtol=0). Use when aligning Paddle API precision with PyTorch, running accuracy tests, analyzing precision errors, or when the user mentions precision alignment, accuracy test, PaddleAPITest, or precision validation.
---

# PaddleAPITest 精度对齐测试指南

用于精度对齐场景，通过对比 Paddle 和 PyTorch API 的前反向结果来验证精度对齐。**由 V - 精度验证师负责执行**。

## 核心命令格式

**文件模式（批量测试）**：
```bash
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config_file="error_config_layer_norm_v2.txt"
```

**单配置模式（单个测试）**：
```bash
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config='paddle.Tensor.lerp(x=Tensor([4],"float32"), y=Tensor([4],"float32"), weight=0.5, )'
```

**关键参数说明**：
- `--atol=0 --rtol=0`: 严格的精度要求（绝对误差和相对误差都为 0）
- `--accuracy=True`: 启用精度对比测试（Paddle vs PyTorch）
- `--api_config_file`: 配置文件路径（批量测试）
- `--api_config`: 单个配置字符串（单配置测试）
- `--log_dir`: 指定日志目录位置（可选，默认位置在 tester/api_config/test_log）

## 环境要求

- Python >= 3.10（engineV2 推荐）
- PaddlePaddle（develop 版本）
- PyTorch（用于精度对比）
- PaddleAPITest 代码库路径
- 依赖库：`func_timeout pandas pebble pynvml pyyaml typer`

## 使用场景

### 场景 1: 测试错误配置文件
```bash
# 测试包含错误配置的文件
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config_file="error_config_layer_norm_v2.txt"

# 指定日志目录
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config_file="error_config_layer_norm_v2.txt" --log_dir="./logs"
```

### 场景 2: 测试单个 API 配置
```bash
# 快速验证单个配置
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config='paddle.nn.functional.softmax(Tensor([2, 3, 4],"float32"), axis=-1, )'
```

### 场景 3: 建立精度基线
```bash
# 针对特定 API 筛选配置
cd ${PADDLEAPITEST_PATH}
grep "paddle.nn.functional.softmax" tester/api_config/5_accuracy/*.txt > softmax_configs.txt

# 运行精度测试建立基线（使用 --log_dir 指定日志位置）
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config_file="softmax_configs.txt" --log_dir="./baseline_logs" >> baseline.log 2>&1
```

### 场景 4: 验证修复效果
```bash
# 修复后重新测试（使用 --log_dir 指定日志位置）
python engineV2.py --atol=0 --rtol=0 --accuracy=True --api_config_file="error_config_layer_norm_v2.txt" --log_dir="./verify_logs" >> verify.log 2>&1

# 对比修复前后结果
diff baseline.log verify.log
```

### 场景 5: 分析失败用例
```bash
# 查看错误分类
# - accuracy_gpu_error.txt: GPU 精度错误
# - accuracy_gpu_kernel.txt: 内核错误
# - accuracy_cpu_error.txt: CPU 精度错误
# - accuracy_cpu_kernel.txt: CPU 内核错误

# 分析错误模式
grep "paddle.nn.functional.softmax" tester/api_config/5_accuracy/accuracy_gpu_error.txt
```

## 配置格式

配置使用双引号，格式示例：
```
paddle.Tensor.lerp(x=Tensor([4],"float32"), y=Tensor([4],"float32"), weight=0.5, )
paddle.nn.functional.softmax(Tensor([2, 3, 4],"float32"), axis=-1, )
```

**注意**：配置文件中统一使用双引号，命令行参数建议使用单引号包裹。

## 结果分析

测试结果存储在 `tester/api_config/5_accuracy/` 目录：
- `accuracy_*.txt`: 测试通过
- `accuracy_gpu_error.txt`: GPU 精度错误（前向或反向精度不匹配）
- `accuracy_gpu_kernel.txt`: GPU 内核抛出错误
- `accuracy_cpu_error.txt`: CPU 精度错误
- `accuracy_cpu_kernel.txt`: CPU 内核错误
- `accuracy_gpu_error_dtype_diff.txt`: dtype 对齐后可通过（非关键问题）
- `accuracy_gpu_error_grads_diff.txt`: 反向梯度无法比较（需单独分析）

## 精度对齐关键点

### 测试注意事项

1. **前向和反向都要测试**：精度错误可能是前向问题，也可能是反向问题。如果有前向问题，通常意味着反向也有问题。

2. **CPU 和 GPU 都要验证**：CPU 和 GPU 上运行的结果可能存在差异，需要分别验证。

3. **不同 dtype 都要覆盖**：float16、float32、float64 可能有不同的实现路径。

4. **使用严格精度要求**：`--atol=0 --rtol=0` 确保完全对齐。

### 错误分析流程

1. **定位错误配置**
   ```bash
   grep "${API_NAME}" tester/api_config/5_accuracy/accuracy_gpu_error.txt
   ```

2. **分析错误模式**
   - 检查 dtype 分布（float16/float32/float64）
   - 检查 shape 模式
   - 检查参数组合

3. **分类错误类型**
   - 前向精度问题
   - 反向梯度问题
   - 内核实现问题
   - 数据类型转换问题

## 与精度对齐工作流的集成

在精度对齐流程中：
1. **建立基线**：使用 PaddleAPITest 建立当前失败基线
2. **修复实现**：根据对比分析修复 CUDA Kernel
3. **验证修复**：使用 PaddleAPITest 验证修复效果
4. **最终验收**：确保所有相关 case 通过

## 故障排查

**测试报错时**：
1. 检查配置格式是否正确（双引号、括号匹配）
2. 确认 Paddle 和 PyTorch 版本兼容
3. 查看日志文件中的具体错误信息
4. 对于精度不统一的情况，尝试添加 `--test_amp=True`

**需要退出测试时**：
添加 `--exit_on_error=True`，遇到错误会立即退出（exit_code=1）

## 职责说明

**V - 精度验证师负责**：
- 使用 PaddleAPITest 进行精度对齐测试
- 建立精度基线、验证修复效果、分析精度差异
- 确保精度与 PyTorch 完全对齐

**注意**：功能正确性验证需要使用 Paddle 单测和 CI/CE 测试（见 `paddle-functional-testing` skill）。
