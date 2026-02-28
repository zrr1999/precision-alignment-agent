# Knowledge Base (人工知识库)

本目录包含 **人工维护的 Paddle 相关知识**，供 Precision Alignment Agent 系统的各个智能体**只读访问**。

## 访问权限

- **智能体权限**: 只读（Read-only）
- **维护方式**: 人工编辑和更新
- **版本控制**: 通过 Git 管理

**重要**: 智能体不得修改此目录下的任何内容。自动生成的知识应存放在 `.paa/memory/` 目录下。

---

## 内容说明

### `commons/` - 通用知识

包含跨 API 通用的知识：

- `accuracy-compatible-kernel.md`: `FLAGS_use_accuracy_compatible_kernel` 精度兼容性开关的使用说明和策略
- 其他通用的精度对齐知识

**目标读者**: 所有智能体

---

## 贡献指南

### 如何添加新知识

1. **确定分类**: 放入 `commons/` 或按需创建新的子目录
2. **创建 Markdown 文件**: 使用描述性文件名
3. **添加 YAML frontmatter**: 包含元数据
4. **编写结构化内容**: 使用清晰的标题和示例

### 文件模板

```markdown
---
title: {知识点标题}
category: {commons|flags|kernel-patterns|api-mappings|best-practices}
created_at: {YYYY-MM-DD}
updated_at: {YYYY-MM-DD}
tags: [tag1, tag2, tag3]
target_agents: [Aligner, Explorer, ...]
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

## 与自动知识库的关系

| 特性 | `knowledge/` (人工) | `.paa/memory/` (自动) |
|------|---------------------|----------------------|
| **内容来源** | 人工编写和维护 | 智能体自动生成 |
| **智能体权限** | 只读 (Read-only) | 读写 (Read-Write) |
| **内容性质** | 通用知识、最佳实践 | 特定任务的执行记录和学习 |
| **更新频率** | 按需更新 | 每次任务自动更新 |
| **版本控制** | 提交到 Git | 可选提交（作为历史记录） |

---

## 查询优先级

当智能体需要查询知识时，建议的查询顺序：

1. **首先查询** `knowledge/` - 获取通用知识和最佳实践
2. **然后查询** `.paa/memory/` - 获取历史任务的具体经验
3. **综合分析** - 结合两者制定策略
