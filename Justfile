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

# ============================================================================
# Agentic Commands - For Agent Use Only
# 
# Convention: Only commands prefixed with "agentic-" can be used by agents.
# All commands require environment variables to be set.
# ============================================================================

# Verify Paddle installation in virtual environment
agentic-verify-paddle-install VENV_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Verifying Paddle installation in {{VENV_PATH}}..."
    uv run -p "{{VENV_PATH}}" python -c "import paddle; print(f'Paddle version: {paddle.__version__}'); print(f'CUDA devices: {paddle.device.cuda.device_count()}')"

# Run Paddle internal unit test for a specific API
agentic-run-paddle-unittest VENV_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running Paddle unittest for {{TEST_FILE}}..."
    uv run -p "{{VENV_PATH}}" python "{{TEST_FILE}}"

# Run PaddleTest functional test for a specific API
agentic-run-paddletest VENV_PATH PADDLETEST_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running PaddleTest for {{TEST_FILE}}..."
    cd "{{PADDLETEST_PATH}}/framework/api/paddlebase"
    uv run -p "{{VENV_PATH}}" python -m pytest "{{TEST_FILE}}" -v

# Run PaddleAPITest precision validation (returns log directory path)
agentic-run-precision-test VENV_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{PADDLEAPITEST_PATH}}"
    echo "Running PaddleAPITest with config: {{CONFIG_FILE}}..."
    uv run -p "{{VENV_PATH}}" python engineV2.py \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{CONFIG_FILE}}" \
        --log_dir="{{LOG_DIR}}"
    
    # Find and output the latest log directory
    echo "---"
    echo "Log directory: {{LOG_DIR}}"
    echo "Full path: {{PADDLEAPITEST_PATH}}/{{LOG_DIR}}"

# Extract precision test results from latest log directory
agentic-get-precision-results PADDLEAPITEST_PATH LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{PADDLEAPITEST_PATH}}/{{LOG_DIR}}"
    
    echo "Latest log directory: {{LOG_DIR}}"
    echo ""
    echo "GPU Results:"
    echo "  Passed:    $(wc -l < "{{LOG_DIR}}/accuracy_gpu.txt" 2>/dev/null || echo 0)"
    echo "  Errors:    $(wc -l < "{{LOG_DIR}}/accuracy_gpu_error.txt" 2>/dev/null || echo 0)"
    echo "  Crashes:   $(wc -l < "{{LOG_DIR}}/accuracy_gpu_kernel.txt" 2>/dev/null || echo 0)"
    echo ""
    echo "CPU Results:"
    echo "  Passed:    $(wc -l < "{{LOG_DIR}}/accuracy_cpu.txt" 2>/dev/null || echo 0)"
    echo "  Errors:    $(wc -l < "{{LOG_DIR}}/accuracy_cpu_error.txt" 2>/dev/null || echo 0)"
    echo "  Crashes:   $(wc -l < "{{LOG_DIR}}/accuracy_cpu_kernel.txt" 2>/dev/null || echo 0)"
