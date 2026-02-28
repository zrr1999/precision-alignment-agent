# 精度对齐智能体（Precision Alignment Agent）

自动对齐 Paddle 与 PyTorch API 的数值精度，通过「分析问题 → 生成修复方案 → 构建/运行测试 → 验证精度 → 生成 PR」的闭环流程，辅助完成精度对齐工作。

## 架构概览

系统采用**扁平编排**模型：一个主 Agent（Orchestrator）直接协调六个专用子 Agent。

```
Main Agent (Orchestrator)
  ├── @explorer        代码追踪（只读）
  ├── @learner         PR 先例研究（只读）
  ├── @aligner         精度代码修改（写入）
  ├── @diagnostician   构建 + 冒烟测试 + 提交
  ├── @validator       精度验证测试
  └── @reviewer        最终审查 + 创建 PR
```

工作流分为 5 个阶段：

1. **探索与学习**（并行）：Explorer 追踪 Paddle/PyTorch 实现路径，Learner 搜索历史 PR
2. **规划**：Orchestrator 基于报告制定修复计划
3. **修复循环**（AD 循环，最多 5 次迭代）：Aligner → Diagnostician → 评估
4. **精度验证**（PV 循环）：Validator 运行 PaddleAPITest
5. **最终审查**：Reviewer 验证并创建 PR

## 准备工作

在开始前，建议你已经具备：

- 一台可编译 Paddle 的开发环境（Linux / macOS，已安装 CMake、Ninja、CUDA 等编译依赖）；
- GitHub 账户，以及对 Paddle 相关仓库的访问权限；
- 基本的 Paddle / PyTorch 使用与 C++ / Python 调试能力。

## 安装与初始化

### 1. 安装依赖

仓库根目录执行：

```bash
just setup
```

该命令会安装：

- `uv`、`bun`、`x-cmd` 等基础环境；
- `opencode-ai`、`ocx`、`repomix` 等 AI Coding Agent 相关工具；
- 默认的系统级 skills（paddle-skills、ast-grep 等）。

### 2. 克隆相关代码仓库

如果你希望由本项目自动克隆 Paddle 相关仓库，可执行：

```bash
just setup-repos <your_github_username>
```

这会在当前仓库下创建 `.paa/repos/` 目录，并克隆：

- `Paddle`
- `PaddleTest`
- `PaddleAPITest`
- `pytorch`

你也可以手动管理这些仓库，只需在启动时通过环境变量传入路径即可。

## 启动任务

### 精度分析（只读）

仅做代码追踪和分析，不修改任何代码：

```bash
just analysis-start <api_name> "<additional_info>"
```

### 精度对齐（完整流程）

创建 worktree、编译安装 Paddle、启动完整的精度对齐 Agent：

```bash
just alignment-start <api_name>
```

两个命令均支持通过 `tool` 参数选择底层 AI Coding Agent（默认 `opencode`，也支持 `claude` 和 `ducc`）：

```bash
just alignment-start <api_name> claude
```

路径可通过 `PADDLE_PATH`、`PYTORCH_PATH`、`PADDLETEST_PATH`、`PADDLEAPITEST_PATH` 环境变量覆盖。

## 开发说明

关键目录：

- `.agents/roles/` — 规范 Agent 定义（YAML frontmatter + Markdown prompt），唯一真实来源
- `.agents/skills/` — 平台无关的 skills
- `knowledge/` — 人工维护的知识库（Agent 只读）
- `.opencode/`、`.claude/` — 由 [agent-caster](https://github.com/gouzil/agent-caster) 生成的平台配置，勿手动编辑
- `.paa/` — 运行时数据（repos、worktree、sessions、config、memory）

### 编辑 Agent

1. 编辑 `.agents/roles/{name}.md` 中的规范定义（YAML frontmatter = 元数据，正文 = prompt）
2. 运行 `just adapt` 重新生成各平台配置
3. **不要直接编辑** `.opencode/` 或 `.claude/` 下的生成文件

## 许可证

本项目遵循 Paddle 生态默认的开源许可协议（具体以仓库根目录下的许可证文件为准）。
