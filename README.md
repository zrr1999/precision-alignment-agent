# 精度对齐智能体（Precision Alignment Agent）

自动对齐 Paddle 与 PyTorch API 的数值精度，通过「分析问题 → 生成修复方案 → 构造/运行测试 → 验证精度 → 生成 PR」的闭环流程，辅助完成精度对齐工作。

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
- `opencode-ai`、`ocx` 等 AI Coding Agent 相关工具；
- 默认的系统级 skills。

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

你也可以手动管理这些仓库，只需在之后的步骤中通过环境变量传入路径即可。

## 启动精度对齐任务

```bash
just quick-start <api_name> "<additional_info>"
```

- **`api_name`**：要对齐的 Paddle API，如 `paddle.nn.functional.softmax`
- **`additional_info`**：可选，如问题复现场景、模型或脚本路径

会为当前 API 创建 worktree、编译安装 Paddle、启动精度对齐 Agent 进入交互会话。路径可通过 `PADDLE_PATH`、`PYTORCH_PATH`、`PADDLETEST_PATH`、`PADDLEAPITEST_PATH` 环境变量覆盖。

## 许可证

本项目遵循 Paddle 生态默认的开源许可协议（具体以仓库根目录下的许可证文件为准）。
