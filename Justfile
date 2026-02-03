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
quick-start api_name additional_info:
    # 为环境变量设置默认占位符，未配置时传入 {user input}
    PADDLE="${PADDLE_PATH:-{user input}"; \
    PYTORCH="${PYTORCH_PATH:-{user input}"; \
    PADDLETEST="${PADDLETEST_PATH:-{user input}"; \
    VENV="${VENV_PATH:-{user input}"; \
    opencode --agent precision-alignment --prompt "Start precision alignment workflow for {{api_name}}(additonal info: {{additional_info}}), inputs: paddle_path=$PADDLE, pytorch_path=$PYTORCH, paddletest_path=$PADDLETEST, venv_path=$VENV"

# ============================================================================
# Agentic Commands - For Agent Use Only
# 
# Convention: Only commands prefixed with "agentic-" can be used by agents.
# All commands require environment variables to be set.
# ============================================================================

agentic-repos-setup PADDLE_PATH PADDLETEST_PATH PADDLEAPITEST_PATH PYTORCH_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Setting up external repos..."
    rm -rf .paa_repos
    mkdir -p .paa_repos
    ln -sf "{{PADDLE_PATH}}" .paa_repos/Paddle
    ln -sf "{{PADDLETEST_PATH}}" .paa_repos/PaddleTest
    ln -sf "{{PADDLEAPITEST_PATH}}" .paa_repos/PaddleAPITest
    ln -sf "{{PYTORCH_PATH}}" .paa_repos/PyTorch
    echo "External repos setup complete: .paa_repos/Paddle, .paa_repos/PaddleTest, .paa_repos/PaddleAPITest, .paa_repos/PyTorch"

agentic-venv-setup VENV_PATH PADDLE_PATH: 
    #!/usr/bin/env bash
    set -euo pipefail
    uv venv --no-project --relocatable --seed --allow-existing "{{VENV_PATH}}"
    cd {{VENV_PATH}}/..
    uv pip install func_timeout pandas pebble pynvml pyyaml typer httpx numpy torchvision torch==2.9.1
    uv pip install {{PADDLE_PATH}}/build/python/dist/*.whl --force-reinstall

# Verify Paddle installation in virtual environment
agentic-paddle-install VENV_PATH PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir "{{VENV_PATH}}"
    cd "{{VENV_PATH}}"
    uv pip install {{PADDLE_PATH}}/build/python/dist/*.whl --no-deps --force-reinstall

# Run Paddle internal unit test for a specific API
agentic-run-paddle-unittest VENV_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running Paddle unittest for {{TEST_FILE}}..."
    uv run --no-project -p "{{VENV_PATH}}" python "{{TEST_FILE}}"

# Run PaddleTest functional test for a specific API
agentic-run-paddletest VENV_PATH PADDLETEST_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running PaddleTest for {{TEST_FILE}}..."
    cd "{{PADDLETEST_PATH}}/framework/api/paddlebase"
    uv run --no-project -p "{{VENV_PATH}}" python -m pytest "{{TEST_FILE}}" -v

# Run PaddleAPITest precision validation (returns log directory path)
agentic-run-precision-test VENV_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{PADDLEAPITEST_PATH}}"
    echo "Running PaddleAPITest with config: {{CONFIG_FILE}}..."
    uv run --no-project -p "{{VENV_PATH}}" python engineV2.py \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{CONFIG_FILE}}" \
        --log_dir="{{LOG_DIR}}"
    
    # Find and output the latest log directory
    echo "---"
    echo "Log directory: {{LOG_DIR}}"
    echo "Full path: {{PADDLEAPITEST_PATH}}/{{LOG_DIR}}"
