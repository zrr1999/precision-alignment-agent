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
    bun install -g ocx

    # 安装系统 skills
    git clone https://github.com/ast-grep/agent-skill.git ~/.config/opencode/skills/ast-grep

# 快速启动精度对齐流程
quick-start api_name:
    # 为环境变量设置默认占位符，未配置时传入 {user input}
    PADDLE="${PADDLE_PATH:-{user input}}"; \
    PYTORCH="${PYTORCH_PATH:-{user input}}"; \
    PADDLETEST="${PADDLETEST_PATH:-{user input}}"; \
    VENV="${VENV_PATH:-{user input}}"; \
    opencode --agent precision-alignment --prompt "api_name={{api_name}} paddle_path=$PADDLE pytorch_path=$PYTORCH paddletest_path=$PADDLETEST venv_path=$VENV"
