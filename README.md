# 精度对齐智能体（Precision Alignment Agent）

自动对齐 Paddle 与 PyTorch API 的数值精度，通过「分析问题 → 生成修复方案 → 构造/运行测试 → 验证精度 → 生成 PR」的闭环流程，辅助完成精度对齐工作。

## 项目定位

- **目标**：为 Paddle 生态提供一个可复用的「精度对齐工作流」，尽量减少人工在对齐过程中的重复劳动。
- **能力**：
  - **自动分析**：对 Paddle / PyTorch 在同一 API 下的行为差异进行分析；
  - **辅助修复**：在 Paddle 源码中定位可能的精度问题并给出修改建议；
  - **验证对齐**：调用 PaddleTest / PaddleAPITest 等工具跑通相关测试，查看误差情况；
  - **生成 PR 草稿**：在工作树上完成代码修改后，协助整理为可提交的 PR。

> 说明：本仓库本身是一个「工具工程」，你可以用它来驱动精度对齐任务，也可以直接对其进行二次开发。

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

## 启动一次精度对齐任务

项目提供了一个快速启动命令，用于为指定 API 建立工作树并拉起精度对齐 Agent：

```bash
just quick-start <api_name> "<additional_info>"
```

- **`api_name`**：当前要对齐的 Paddle API 名称，例如 `paddle.nn.functional.softmax`；
- **`additional_info`**：额外上下文信息，例如「在哪个模型中暴露出问题、复现脚本位置等」，这部分后面考虑用更合适的方式代替。

该命令会完成以下操作：

1. 准备并规范化以下路径（可通过环境变量覆盖默认值）：
   - `PADDLE_PATH`
   - `PYTORCH_PATH`
   - `PADDLETEST_PATH`
   - `PADDLEAPITEST_PATH`
2. 在 Paddle 仓库中：
   - 切换到 `PAA/develop` 分支并拉取最新代码；
   - 为当前 `api_name` 创建独立的 worktree（分支名形如 `precision-alignment-agent/<api_name>`）；
3. 在对应 worktree 下：
   - 创建 `build/` 目录；
   - 调用 `agentic-venv-setup` 创建虚拟环境并安装相关依赖；
   - 调用 `agentic-paddle-build-and-install` 编译并安装 Paddle。
4. 返回本仓库根目录，使用 `opencode` 启动名为 `precision-alignment` 的 Agent，进入交互式的精度对齐会话。

## 主要 Agentic 命令（给 Agent / 高级用户用）

在 `Justfile` 中，还预置了一些以 `agentic-` 为前缀的命令，主要用于自动化工作流或高级手动操作：

- **`agentic-venv-setup VENV_PATH PADDLE_PATH`**：使用 `uv` 创建虚拟环境并安装 Paddle wheel 与常用依赖；
- **`agentic-paddle-build-and-install VENV_PATH PADDLE_PATH`**：在已有的 `build/` 目录中编译 Paddle 并安装到指定虚拟环境；
- **`agentic-run-paddle-unittest VENV_PATH PADDLE_PATH TEST_FILE`**：在 `FLAGS_use_accuracy_compatible_kernel=0/1` 两种模式下运行 Paddle 单测；
- **`agentic-run-paddletest VENV_PATH PADDLETEST_PATH TEST_FILE`**：在两种精度模式下运行 PaddleTest 功能测试；
- **`agentic-run-precision-test VENV_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR`**：调用 PaddleAPITest 的 `engineV2.py` 进行精度验证，并输出日志目录。

通常情况下，这些命令由 Agent 自动调用；除非你在开发 / 调试 Agent 本身，否则不需要手动执行。

## 开发与贡献

- **开发本项目**：你可以直接修改本仓库中的 Agent 配置、skills、工具脚本等，以适配自己的工作流；
- **贡献建议**：
  - 先在本地验证 `Justfile` 中相关命令可用；
  - 尽量保持命令接口（参数名 / 环境变量名）向后兼容；
  - 如需新增复杂用法，优先更新 `README` 中的「快速开始」和「主要命令」说明。

## 许可证

本项目遵循 Paddle 生态默认的开源许可协议（具体以仓库根目录下的许可证文件为准）。
