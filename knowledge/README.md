# Paddle Knowledge Base (人工知识库)

本目录包含 **人工维护的 Paddle 相关知识**，供 Precision Alignment Agent 系统的各个智能体**只读访问**。

## 🔒 访问权限

- **智能体权限**: 只读（Read-only）
- **维护方式**: 人工编辑和更新
- **版本控制**: 通过 Git 管理

**重要**: 智能体不得修改此目录下的任何内容。自动生成的知识应存放在 `.paa-knowledge/` 目录下。

---

## 📂 目录结构

```
paddle-knowledge/
├── flags/                 # Feature Flags 与兼容性开关
├── kernel-patterns/       # CUDA Kernel 实现模式
├── api-mappings/          # Paddle-PyTorch API 映射
└── best-practices/        # 最佳实践与工程指南
```

---

## 📖 各目录说明

### `flags/` - Feature Flags

包含 Paddle 中各种 feature flags 的详细说明，包括：
- `FLAGS_use_accuracy_compatible_kernel`: 精度兼容性开关
- 其他性能、精度相关的 flags
- 使用场景和最佳实践

**目标读者**: Planner, Aligner

### `kernel-patterns/` - Kernel 实现模式

记录常见的 CUDA kernel 实现模式和精度相关技巧：
- Dtype 提升规则
- 累加顺序对精度的影响
- 数值稳定性技巧
- 常见精度陷阱

**目标读者**: Aligner, Planner

### `api-mappings/` - API 映射

Paddle 与 PyTorch API 的对应关系：
- API 签名差异
- 行为差异
- 精度关键的 API 列表

**目标读者**: Planner, Explorer

### `best-practices/` - 最佳实践

工程实践和开发指南：
- PR 提交规范
- 测试策略
- 性能优化建议

**目标读者**: 所有智能体

---

## ✍️ 贡献指南

### 如何添加新知识

1. **确定分类**: 选择合适的子目录
2. **创建 Markdown 文件**: 使用描述性文件名
3. **添加 YAML frontmatter**: 包含元数据
4. **编写结构化内容**: 使用清晰的标题和示例

### 文件模板

```markdown
---
title: {知识点标题}
category: {flags|kernel-patterns|api-mappings|best-practices}
created_at: {YYYY-MM-DD}
updated_at: {YYYY-MM-DD}
tags: [tag1, tag2, tag3]
target_agents: [Planner, Aligner, ...]
summary: {一句话概述}
---

## 概述

{详细说明}

## 使用场景

{何时使用}

## 示例

{代码示例}

## 相关知识

- 链接到其他相关文档
```

---

## 🔄 与自动知识库的关系

| 特性 | `paddle-knowledge/` (人工) | `.paa-knowledge/` (自动) |
|------|---------------------------|--------------------------|
| **内容来源** | 人工编写和维护 | 智能体自动生成 |
| **智能体权限** | 只读 (Read-only) | 读写 (Read-Write) |
| **内容性质** | 通用知识、最佳实践 | 特定任务的执行记录 |
| **更新频率** | 按需更新 | 每次任务自动更新 |
| **版本控制** | 应提交到 Git | 可选提交 (作为历史记录) |

---

## 📋 查询优先级

当智能体需要查询知识时，建议的查询顺序：

1. **首先查询** `paddle-knowledge/` - 获取通用知识和最佳实践
2. **然后查询** `.paa-knowledge/` - 获取历史任务的具体数据
3. **综合分析** - 结合两者制定策略
