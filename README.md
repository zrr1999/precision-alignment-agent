# Paddle Pilot

自动化 Paddle 研发 Agent 系统，支持精度对齐、Bug 修复等多种任务，通过「分析问题 → 生成修复方案 → 构建/运行测试 → 验证 → 生成 PR」的闭环流程，辅助完成 Paddle 开发工作。

## 架构概览

系统采用**路由式三层编排**：Router → Director → Specialist。

```
paddle-agent (Router)
  ├── precision-alignment (Director)
  │     ├── @tracer          代码追踪（只读）
  │     ├── @researcher      PR 先例研究（只读）
  │     ├── @aligner         精度代码修改
  │     ├── @builder         构建 + 冒烟测试 + 提交
  │     ├── @validator       精度验证测试
  │     ├── @optimizer       性能优化
  │     ├── @benchmarker     性能基准测试
  │     └── @reviewer        最终审查 + 创建 PR
  │
  └── bug-fix (Director)
        ├── @tracer          代码追踪（只读）
        ├── @researcher      PR 先例研究（只读）
        ├── @debugger        运行时调试 + 根因分析
        ├── @aligner         代码修改
        ├── @builder         构建 + 冒烟测试 + 提交
        ├── @validator       Bug 修复验证（tensor-spec）
        └── @reviewer        最终审查 + 创建 PR
```

### 精度对齐工作流

1. **探索与学习**（并行）：Tracer 追踪 Paddle/PyTorch 实现路径，Researcher 搜索历史 PR
2. **规划**：Director 基于报告制定修复计划
3. **修复与验证循环**（最多 5 次迭代）：Aligner → Builder → Validator → 评估
4. **优化与基准**（可选）：Optimizer 性能调优，Benchmarker 对比测试
5. **最终审查**：Reviewer 验证并创建 PR

### Bug 修复工作流

1. **探索**：Tracer 追踪代码路径，Researcher 搜索相似 PR
2. **调试**：Debugger 复现、定位根因
3. **修复与验证循环**（最多 5 次迭代）：Aligner → Builder → Validator(tensor-spec) → 评估
4. **最终审查**：Reviewer 验证并创建 PR

## 准备工作

在开始前，建议你已经具备：

- 一台可编译 Paddle 的开发环境（Linux，已安装 CMake、Ninja、CUDA 等编译依赖）；
- GitHub 账户，以及对 Paddle 相关仓库的访问权限；
- 基本的 Paddle / PyTorch 使用与 C++ / Python 调试能力。

## 安装与初始化

### 1. 安装依赖

仓库根目录执行：

```bash
just setup
```

该命令会安装：

- `uv`、`bun`、`gh` 等基础环境；
- `opencode-ai`、`ocx`、`repomix` 等 AI Coding Agent 相关工具；
- 默认的系统级 skills（paddle-skills、ast-grep、repomix-explorer 等）；
- 本仓库本地 Git hooks（`pre-commit` + `commit-msg`，其中 `commit-msg` 使用 `zendev` 校验提交标题）；
- 通过 `role-forge` 生成各平台 Agent 配置。

若只想重新安装 hooks，可单独执行：

```bash
just install
```

### 2. 克隆相关代码仓库

```bash
just setup-repos <your_github_username>
```

这会在 `.paddle-pilot/repos/` 目录下克隆：

- `Paddle`
- `PaddleTest`
- `PaddleAPITest`
- `pytorch`

你也可以手动管理这些仓库，只需在启动时通过环境变量传入路径即可。

## 启动任务

### 新建任务

创建 worktree、编译安装 Paddle、启动 Agent：

```bash
just start <branch_name> [tool] [additional_prompt] [runtime]
```

### 恢复任务

复用现有 worktree 和构建产物，继续之前的工作：

```bash
just resume <branch_name> [tool] [additional_prompt] [runtime]
```

`tool` 参数支持 `opencode`（默认）、`claude`、`ducc`、`copilot`。

`runtime` 参数支持：

- `direct`（默认）：保持当前行为，在当前终端直接启动 agent；
- `zellij`：把 agent 启动到独立的 Zellij session/pane 中，便于后续 attach / reattach。

### Zellij runtime（实验性）

若你安装了 Zellij `0.44+`，可以把任务运行在 Zellij 里：

```bash
just start <branch_name> opencode "" zellij
just resume <branch_name> opencode "" zellij
```

启动后，Paddle Pilot 会把 runtime 元数据写到：

```text
.paddle-pilot/sessions/<branch_name>/runtime.json
```

其中包含当前 runtime、tool、worktree、prompt 文件、以及最近一次 zellij session / pane 信息。

常用命令：

```bash
just zellij-runtime-status <branch_name>
just zellij-attach <branch_name>
```

这一步先解决“可恢复会话”和“稳定定位 pane”的基础能力；HTTPS attach、只读 watch、实时 subscribe 等更强编排能力会在后续阶段继续补齐。

路径可通过环境变量覆盖：`PADDLE_PATH`、`PYTORCH_PATH`、`PADDLETEST_PATH`、`PADDLEAPITEST_PATH`。

## 开发说明

关键目录：

| 目录 | 说明 |
|------|------|
| `roles/` | 规范 Agent 定义（YAML frontmatter + Markdown prompt），唯一真实来源 |
| `roles.toml` | role-forge 多平台配置 |
| `skills/` | 仓库内维护的本地 skills 源码与脚本 |
| `.agents/skills/` | Agent 运行时可见的 skills 目录（包含本地镜像与已安装 skills） |
| `knowledge/` | 人工维护的知识库（Agent 只读） |
| `.opencode/`、`.claude/` | 由 [role-forge](https://github.com/zrr1999/role-forge) 生成的平台配置，勿手动编辑 |
| `.paddle-pilot/` | 运行时数据（repos、worktree、sessions、config、memory） |

### 编辑 Agent

1. 编辑 `roles/{name}.md` 中的规范定义（YAML frontmatter = 元数据，正文 = prompt）
2. 运行 `just adapt` 重新生成各平台配置
3. **不要直接编辑** `.opencode/` 或 `.claude/` 下的生成文件

### 提交规范

本仓库通过 `zendev-commit-msg` 校验 commit title；默认在 `just setup`（或单独执行 `just install`）时安装。

提交标题需要遵循 `emoji + conventional commit` 格式，例如：

```text
✨ feat: add zellij runtime metadata
♻️ refactor: refresh Paddle Pilot branding
📝 docs: update README
```

Git 自动生成的 `Merge`、`Revert`、`fixup!`、`squash!` 消息仍然允许通过。

## 许可证

本项目遵循 Paddle 生态默认的开源许可协议（具体以仓库根目录下的许可证文件为准）。
