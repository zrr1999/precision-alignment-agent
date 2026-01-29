# 列出所有可用的命令
default:
    @just --list

# 安装所有依赖
setup:
    curl -LsSf https://astral.sh/uv/install.sh | sh
    curl -fsSL https://bun.sh/install | bash
    eval "$(wget -O- https://get.x-cmd.com)"
    x env use gh

    # 安装 AI coding agent
    bun install -g opencode-ai

    # 安装系统 skills
    git clone https://github.com/ast-grep/agent-skill.git ~/.config/opencode/skills/ast-grep

# 快速启动精度对齐流程
# 用法示例：
#   just quick-start api_name='paddle.pow'
# 可选的环境变量（未设置时会传入 `{user input}` 占位，交给 Agent 向用户询问）：
#   PADDLE_PATH      - Paddle 代码库路径
#   PYTORCH_PATH     - PyTorch 代码库路径
#   PADDLETEST_PATH  - PaddleAPITest 代码库路径
#   VENV_PATH        - 用于测试的虚拟环境路径
quick-start api_name:
    # 为环境变量设置默认占位符，未配置时传入 {user input}
    PADDLE="${PADDLE_PATH:-{user input}}"; \
    PYTORCH="${PYTORCH_PATH:-{user input}}"; \
    PADDLETEST="${PADDLETEST_PATH:-{user input}}"; \
    VENV="${VENV_PATH:-{user input}}"; \
    opencode --agent precision-alignment --prompt "api_name={{api_name}} paddle_path=$PADDLE pytorch_path=$PYTORCH paddletest_path=$PADDLETEST venv_path=$VENV"
