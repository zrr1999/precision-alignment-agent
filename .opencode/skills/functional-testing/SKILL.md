---
name: paddle-functional-testing
description: Run Paddle internal unit tests and PaddleTest repository tests for CI/CE validation. Use when running ctest, unit tests, validating functional correctness, checking for regressions, or when the user mentions unit test, ctest, pytest, CI test, CE test, or PaddleTest.
---

# Paddle 功能测试指南

用于运行 Paddle 内部单测和 PaddleTest 仓库测试，验证功能正确性和回归问题。**由 D - 故障诊断官负责执行**。

## Paddle 内部单测

### 运行方式

**直接运行 Python 测试文件**：
```bash
# 运行特定测试文件
python test/legacy_test/test_layer_norm_op.py

# 运行其他测试文件
python test/legacy_test/test_softmax_op.py
```

**注意**：Paddle 内部测试可以直接运行，无需额外的编译配置。

## PaddleTest 仓库测试

### 运行方式

**进入指定路径后使用 pytest**：
```bash
# 1. 进入 PaddleTest 仓库的 framework/api/paddlebase 目录
cd ${PADDLETEST_PATH}/framework/api/paddlebase

# 2. 运行 pytest 测试
pytest test_layer_norm.py
pytest test_softmax.py

# 运行特定测试函数
pytest test_layer_norm.py::test_layer_norm_op

# 运行多个测试文件
pytest test_layer_norm.py test_softmax.py
```

## 常见使用场景

### 场景 1: 测试 Paddle 内部特定算子
```bash
# 运行 layer_norm 测试
python test/legacy_test/test_layer_norm_op.py

# 运行 softmax 测试
python test/legacy_test/test_softmax_op.py
```

### 场景 2: 验证修复效果（CI/CE 流程）
```bash
# 修复后运行相关测试，验证功能正确性和回归
python test/legacy_test/test_layer_norm_op.py

# 如果失败，查看详细输出（pytest 会自动显示）
```

### 场景 3: 运行 PaddleTest 仓库测试
```bash
# 进入 PaddleTest 目录
cd ${PADDLETEST_PATH}/framework/api/paddlebase

# 运行相关测试
pytest test_layer_norm.py

# 运行所有相关测试
pytest test_*.py
```

### 场景 4: 调试失败的测试
```bash
# Paddle 内部测试：直接运行查看输出
python test/legacy_test/test_layer_norm_op.py

# PaddleTest：使用 pytest 的详细输出
cd ${PADDLETEST_PATH}/framework/api/paddlebase
pytest test_layer_norm.py -v  # 详细输出
pytest test_layer_norm.py -vv  # 更详细输出
```

## pytest 常用参数

**-v, -vv**: 详细输出
- `-v`: 显示测试名称
- `-vv`: 显示更详细的输出

**-k**: 运行匹配表达式的测试
```bash
pytest -k "layer_norm"  # 运行包含 layer_norm 的测试
```

**-x**: 遇到第一个失败就停止
```bash
pytest -x test_layer_norm.py
```

**--tb=short**: 简短的错误追踪
```bash
pytest --tb=short test_layer_norm.py
```

## 故障排查

### 测试找不到
**问题**：找不到测试文件

**解决**：
1. 确认测试文件路径正确
2. 确认在正确的目录下运行
3. 对于 PaddleTest，确认已进入 `framework/api/paddlebase` 目录

### 测试失败
**问题**：测试运行但失败

**解决**：
1. 查看详细输出（pytest 使用 `-vv`）
2. 检查测试环境（GPU/CPU、依赖等）
3. 确认 Paddle 已正确安装
4. 查看测试日志和错误信息

### 导入错误
**问题**：无法导入模块

**解决**：
1. 确认 Paddle 已正确安装
2. 确认 Python 环境正确
3. 检查 PYTHONPATH 设置

## 最佳实践

1. **每次修改后运行相关测试**：确保修改没有破坏现有功能
2. **先运行单个测试文件**：快速验证修复是否有效
3. **再运行相关测试套件**：确保没有回归
4. **使用详细输出调试**：pytest 使用 `-vv` 查看详细信息
5. **为新功能添加测试**：所有代码贡献都需要包含测试

## 职责说明

**D - 故障诊断官负责**：
- 运行 Paddle 内部单测（直接运行 Python 测试文件）验证功能正确性
- 运行 PaddleTest 仓库的测试（在 `framework/api/paddlebase` 目录下使用 pytest）验证回归问题
- 确保修复没有引入功能性问题

**注意**：功能测试主要验证功能正确性，精度对齐需要使用 PaddleAPITest（见 `precision-testing` skill）。
