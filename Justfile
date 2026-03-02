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
    bun install -g repomix

    # 安装系统 skills
    bunx skills add PFCCLab/paddle-skills -g -y --skill "*"
    bunx skills add anthropics/skills -g -y --skill skill-creator
    bunx skills add yamadashy/repomix -g -y --skill repomix-explorer
    bunx skills add ast-grep/agent-skill -g -y --skill "*"
    bunx skills add OthmanAdi/planning-with-files -g -y --skill ""planning-with-files""

    # 提示安装全局 mcp
    echo "For better performance, please manually install global mcp: https://mcp.context7.com/install"

# 从 agents/ 适配生成各平台配置
adapt:
    uvx agent-caster cast

# 更新配置和 skills（adapt + skills update）
update:
    just adapt
    bunx skills update

# 初始化仓库
setup-repos username:
    mkdir -p .paa/repos
    git clone https://github.com/{{ username }}/Paddle.git .paa/repos/Paddle
    git clone https://github.com/{{ username }}/PaddleTest.git .paa/repos/PaddleTest
    git clone https://github.com/{{ username }}/PaddleAPITest.git .paa/repos/PaddleAPITest
    git clone https://github.com/{{ username }}/pytorch.git .paa/repos/pytorch

analysis-start api_name additional_prompt tool="opencode":
    #!/usr/bin/env bash
    set -euo pipefail

    PAA_ROOT=$(pwd)

    PADDLE_PATH="${PADDLE_PATH:=.paa/repos/Paddle}"
    PYTORCH_PATH="${PYTORCH_PATH:=.paa/repos/pytorch}"
    PADDLETEST_PATH="${PADDLETEST_PATH:=.paa/repos/PaddleTest}"
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paa/repos/PaddleAPITest}"

    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    PYTORCH_PATH="$(cd "$PYTORCH_PATH" && pwd)"
    PADDLETEST_PATH="$(cd "$PADDLETEST_PATH" && pwd)"
    PADDLEAPITEST_PATH="$(cd "$PADDLEAPITEST_PATH" && pwd)"

    echo "PYTORCH_PATH: $PYTORCH_PATH"
    echo "PADDLETEST_PATH: $PADDLETEST_PATH"
    echo "PADDLEAPITEST_PATH: $PADDLEAPITEST_PATH"

    echo "Setting up worktree"
    mkdir -p .paa/worktree
    cd $PADDLE_PATH
    git switch -c PAA/develop 2>/dev/null || git switch PAA/develop
    git pull upstream develop
    if [ -d "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}" ]; then
        cd "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}"
    else
        git worktree add $PAA_ROOT/.paa/worktree/Paddle_{{ api_name }} -b precision-alignment-agent/{{ api_name }}
    fi

    PADDLE_PATH=$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}
    VENV_PATH=$PADDLE_PATH/.venv
    echo "PADDLE_PATH: $PADDLE_PATH"

    cd $PAA_ROOT

    AGENT="precision-analysis"
    PROMPT="Start EXPLORE-ONLY (read-only) precision analysis for {{ api_name }}. \
        This session is for research and code tracing only. \
        Additional user prompt: {{ additional_prompt }}. \
        Inputs: paddle_path=$PADDLE_PATH, \
        pytorch_path=$PYTORCH_PATH, \
        paddletest_path=$PADDLETEST_PATH, \
        paddleapitest_path=$PADDLEAPITEST_PATH, \
        venv_path=$VENV_PATH"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT"

# 快速启动精度对齐流程
alignment-start api_name tool="opencode" additional_prompt="":
    #!/usr/bin/env bash
    set -euo pipefail

    PAA_ROOT=$(pwd)

    PADDLE_PATH="${PADDLE_PATH:=.paa/repos/Paddle}"
    PYTORCH_PATH="${PYTORCH_PATH:=.paa/repos/pytorch}"
    PADDLETEST_PATH="${PADDLETEST_PATH:=.paa/repos/PaddleTest}"
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paa/repos/PaddleAPITest}"

    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    PYTORCH_PATH="$(cd "$PYTORCH_PATH" && pwd)"
    PADDLETEST_PATH="$(cd "$PADDLETEST_PATH" && pwd)"
    PADDLEAPITEST_PATH="$(cd "$PADDLEAPITEST_PATH" && pwd)"

    echo "PYTORCH_PATH: $PYTORCH_PATH"
    echo "PADDLETEST_PATH: $PADDLETEST_PATH"
    echo "PADDLEAPITEST_PATH: $PADDLEAPITEST_PATH"

    echo "Setting up worktree"
    mkdir -p .paa/worktree
    cd $PADDLE_PATH
    git switch -c PAA/develop 2>/dev/null || git switch PAA/develop
    git pull upstream develop
    if [ -d "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}" ]; then
        cd "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}"
    else
        git worktree add $PAA_ROOT/.paa/worktree/Paddle_{{ api_name }} -b precision-alignment-agent/{{ api_name }}
    fi

    PADDLE_PATH=$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}
    VENV_PATH=$PADDLE_PATH/.venv
    echo "PADDLE_PATH: $PADDLE_PATH"

    cd $PADDLEAPITEST_PATH
    bash auto_get_api_config.sh paa

    cd $PADDLE_PATH
    just agentic-venv-setup $PADDLE_PATH
    mkdir -p build
    cd build
    just agentic-paddle-build-and-install $PADDLE_PATH

    echo "Successfully setup worktree and created venv"

    cd $PAA_ROOT

    AGENT="precision-alignment"
    PROMPT="Start precision alignment workflow for {{ api_name }} \
        (additional prompt: {{ additional_prompt }}), with inputs: \
        paddle_path=$PADDLE_PATH, \
        pytorch_path=$PYTORCH_PATH, \
        paddletest_path=$PADDLETEST_PATH, \
        paddleapitest_path=$PADDLEAPITEST_PATH, \
        venv_path=$VENV_PATH"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT"

# ============================================================================
# Internal Recipes (prefixed with _)
# ============================================================================

# 根据 tool 类型启动 agent（支持 opencode / claude / ducc）
_launch-agent tool agent prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Launching agent '{{ agent }}' with tool '{{ tool }}'..."
    case "{{ tool }}" in
        opencode)
            opencode --agent "{{ agent }}" --prompt "{{ prompt }}"
            ;;
        claude|ducc)
            {{ tool }} --agent "{{ agent }}" "{{ prompt }}"
            ;;
        *)
            echo "Error: unsupported tool '{{ tool }}'. Use 'opencode', 'claude', or 'ducc'."
            exit 1
            ;;
    esac

# ============================================================================
# Agentic Commands - For Agent Use Only
#
# Convention: Only commands prefixed with "agentic-" can be used by agents.
# All commands require environment variables to be set.
# ============================================================================

# Link external repos (Paddle, PaddleTest, PaddleAPITest, PyTorch) into .paa/worktree/ for agent use. TODO: implementation pending.
agentic-repos-setup PADDLE_PATH PADDLETEST_PATH PADDLEAPITEST_PATH PYTORCH_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "TODO"
    # echo "Setting up external repos..."
    # mkdir -p .paa/worktree
    # ln -sf "{{ PADDLE_PATH }}" .paa/worktree/Paddle
    # ln -sf "{{ PADDLETEST_PATH }}" .paa/worktree/PaddleTest
    # ln -sf "{{ PADDLEAPITEST_PATH }}" .paa/worktree/PaddleAPITest
    # ln -sf "{{ PYTORCH_PATH }}" .paa/worktree/PyTorch
    # echo "External repos setup complete: .paa/worktree/Paddle, .paa/worktree/PaddleTest, .paa/worktree/PaddleAPITest, .paa/worktree/PyTorch"

# Create or update relocatable venv with Paddle deps (torch, func_timeout, etc.) and Paddle python/requirements.txt.
agentic-venv-setup PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    if [ ! -d "$VENV_PATH" ]; then
        uv venv --no-project --relocatable --seed "$VENV_PATH"
    fi
    cd {{ PADDLE_PATH }}/
    uvx prek install

    cd "$VENV_PATH/.."
    uv pip install func_timeout pandas pebble pynvml pyyaml typer httpx numpy torchvision torch==2.9.1
    uv pip install -r {{ PADDLE_PATH }}/python/requirements.txt

# Build and install Paddle in virtual environment
agentic-paddle-build-and-install PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    echo "Building Paddle..."
    cd "$VENV_PATH"
    source bin/activate
    cd {{ PADDLE_PATH }}/build
    cmake .. -DPADDLE_VERSION=0.0.0 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DPY_VERSION=3.10 -DCUDA_ARCH_NAME=Auto -DWITH_GPU=ON -DWITH_DISTRIBUTE=ON -DWITH_UNITY_BUILD=OFF -DWITH_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DWITH_CINN=ON -GNinja
    ninja -j$(nproc)
    echo "Installing Paddle..."
    cd "$VENV_PATH/.."
    uv pip install {{ PADDLE_PATH }}/build/python/dist/*.whl --no-deps --force-reinstall
    echo "Paddle build and install completed successfully."

# Run Paddle internal unit test for a specific API
agentic-run-paddle-unittest PADDLE_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    cd "{{ PADDLE_PATH }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=0) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=0 \
    uv run --no-project -p "$VENV_PATH" python "{{ TEST_FILE }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=1) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "$VENV_PATH" python "{{ TEST_FILE }}"

# Run PaddleTest functional test for a specific API
agentic-run-paddletest PADDLE_PATH PADDLETEST_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    cd "{{ PADDLETEST_PATH }}"

    echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=0) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=0 \
    uv run --no-project -p "$VENV_PATH" python -m pytest "{{ TEST_FILE }}" -v

    echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=1) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "$VENV_PATH" python -m pytest "{{ TEST_FILE }}" -v

# Extract precision test configs for an API from PaddleAPITest paa.txt into .paa/config/{API_NAME}.txt for Validator use.
agentic-get-precision-test-configs API_NAME PADDLEAPITEST_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    cat {{PADDLEAPITEST_PATH}}/.api_config/paa-v0/paa/paa.txt | grep {{API_NAME}} > .paa/config/{{API_NAME}}.txt
    echo "config file is saved to $(pwd)/.paa/config/{{API_NAME}}.txt"

# Run PaddleAPITest precision validation (returns log directory path)
agentic-run-precision-test PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    cd "{{ PADDLEAPITEST_PATH }}"
    echo "Removing old log files..."
    rm -f PAA_test_log/{{ LOG_DIR }}/*.txt
    rm -f PAA_test_log/{{ LOG_DIR }}/*.log
    echo "Running PaddleAPITest(FLAGS_use_accuracy_compatible_kernel=1) with config: {{ CONFIG_FILE }}..."

    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "$VENV_PATH" python engineV2.py \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{ CONFIG_FILE }}" \
        --log_dir="PAA_test_log/{{ LOG_DIR }}"

    # Find and output the latest log directory
    echo "---"
    echo "Log directory: PAA_test_log/{{ LOG_DIR }}"
    echo "Full path: {{ PADDLEAPITEST_PATH }}/PAA_test_log/{{ LOG_DIR }}"
