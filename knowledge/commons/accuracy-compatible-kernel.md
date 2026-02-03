---
title: FLAGS_use_accuracy_compatible_kernel
category: flags
created_at: 2026-01-29
updated_at: 2026-01-29
tags: [flags, backward-compatibility, accuracy, performance, kernel-selection]
target_agents: [Planner, Aligner]
summary: 控制 Paddle 是否使用与 PyTorch 完全兼容的 kernel 实现，管理精度与性能的权衡
---

## 概述

`FLAGS_use_accuracy_compatible_kernel` 是 Paddle 中的一个全局 feature flag（环境变量），用于控制在精度对齐场景下的 kernel 选择策略。

### 核心原则

- **如果 Paddle 实现更好**（精度或性能优于 PyTorch）：
  - 默认使用 Paddle 的优化实现
  - 通过此 flag 提供 PyTorch 兼容模式（完全对齐）

- **如果 PyTorch 实现更好**：
  - 直接改进 Paddle 实现，无需使用 flag
  - 不应保留"劣质"实现

---

## 使用场景

### 场景 1: Paddle 精度/性能更优

**情况**: Paddle 的实现在某些方面优于 PyTorch（更高精度、更快速度、更好数值稳定性）

**策略**:
```yaml
默认行为: FLAGS_use_accuracy_compatible_kernel = 0  # 使用 Paddle 优化实现
兼容模式: FLAGS_use_accuracy_compatible_kernel = 1  # 使用 PyTorch 兼容实现
```

**典型用例**:
- 用户从 PyTorch 迁移代码，需要结果完全一致以验证迁移正确性
- 用户依赖 PyTorch 的特定数值行为（即使不是最优的）
- 调试和对比两种实现的差异

**示例**: 假设 Paddle 的 `pow` 算子使用更精确的累加顺序
```python
# 默认: 使用 Paddle 优化的实现（精度更高）
paddle.pow(x, 2.0)

# 兼容模式: 完全匹配 PyTorch 的行为
os.environ['FLAGS_use_accuracy_compatible_kernel'] = '1'
paddle.pow(x, 2.0)  # 现在与 torch.pow(x, 2.0) 完全一致
```

### 场景 2: PyTorch 实现更优

**情况**: PyTorch 的实现在精度或性能上更好

**策略**:
```
❌ 不使用 flag，直接改进 Paddle 实现
✅ 让 Paddle 的实现达到或超越 PyTorch
```

**理由**: 没有理由保留一个劣质的实现供用户选择

---
