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
    bunx skills add PFCCLab/paddle-skills
    bunx skills add ast-grep/agent-skill

# 初始化仓库
setup-repos username:
    mkdir -p .paa/repos
    git clone https://github.com/{{ username }}/Paddle.git .paa/repos/Paddle
    git clone https://github.com/{{ username }}/PaddleTest.git .paa/repos/PaddleTest
    git clone https://github.com/{{ username }}/PaddleAPITest.git .paa/repos/PaddleAPITest
    git clone https://github.com/{{ username }}/pytorch.git .paa/repos/pytorch

# 快速启动精度对齐流程
# TODO: 移除 additional_info 使用更明确的内容
quick-start api_name additional_info:
    #!/usr/bin/env bash
    set -euo pipefail

    PAA_ROOT=$(pwd)

    # 为环境变量设置默认占位符
    PADDLE_PATH="${PADDLE_PATH:=.paa/repos/Paddle}"
    PYTORCH_PATH="${PYTORCH_PATH:=.paa/repos/pytorch}"
    PADDLETEST_PATH="${PADDLETEST_PATH:=.paa/repos/PaddleTest}"
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paa/repos/PaddleAPITest}"

    # 规范化为绝对路径
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
    if [ -d "$PAA_ROOT/.paa/worktree/Paddle_{{api_name}}" ]; then
        cd "$PAA_ROOT/.paa/worktree/Paddle_{{api_name}}"
    else
        git worktree add $PAA_ROOT/.paa/worktree/Paddle_{{api_name}} -b precision-alignment-agent/{{api_name}}
    fi

    echo "PADDLE_PATH: $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}"
    VENV_PATH="${VENV_PATH:-$PADDLE_PATH/venv}"

    cd $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}
    just agentic-venv-setup $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}/venv $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}
    source .venv/bin/activate
    mkdir -p build
    cd build
    cmake .. -DPADDLE_VERSION=0.0.0 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DPY_VERSION=3.10 -DCUDA_ARCH_NAME=Auto -DWITH_GPU=ON -DWITH_DISTRIBUTE=ON -DWITH_UNITY_BUILD=OFF -DWITH_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DWITH_CINN=ON -GNinja
    just agentic-paddle-build-and-install $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}/venv $PAA_ROOT/.paa/worktree/Paddle_{{api_name}}

    echo "Successfully setup worktree and created venv"

    cd $PAA_ROOT

    echo "Starting precision alignment workflow for {{ api_name }} \
        (additional info: {{ additional_info }}), with inputs: \
        paddle_path=$PADDLE_PATH, \
        pytorch_path=$PYTORCH_PATH, \
        paddletest_path=$PADDLETEST_PATH, \
        venv_path=$VENV_PATH"

    opencode \
      --agent precision-alignment \
      --prompt "Start precision alignment workflow for {{ api_name }} \
        (session_id: $(date +'%Y%m%d-%H%M%S') , additional info: {{ additional_info }}), with inputs: \
        paddle_path=$PADDLE_PATH, \
        pytorch_path=$PYTORCH_PATH, \
        paddletest_path=$PADDLETEST_PATH, \
        venv_path=$VENV_PATH"

# ============================================================================
# Agentic Commands - For Agent Use Only
#
# Convention: Only commands prefixed with "agentic-" can be used by agents.
# All commands require environment variables to be set.
# ============================================================================

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

agentic-venv-setup VENV_PATH PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "{{ VENV_PATH }}" ]; then
        uv venv --no-project --relocatable --seed "{{ VENV_PATH }}"
    fi
    cd {{ VENV_PATH }}/..
    uv pip install func_timeout pandas pebble pynvml pyyaml typer httpx numpy torchvision torch==2.9.1
    uv pip install -r {{ PADDLE_PATH }}/python/requirements.txt

# Build and install Paddle in virtual environment
agentic-paddle-build-and-install VENV_PATH PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building Paddle..."
    cd {{ PADDLE_PATH }}/build
    # Suppress normal ninja output; errors still go to stderr
    ninja -j$(nproc)
    echo "Installing Paddle..."
    cd {{ VENV_PATH }}/..
    uv pip install {{ PADDLE_PATH }}/build/python/dist/*.whl --no-deps --force-reinstall
    echo "Paddle build and install completed successfully."

# Run Paddle internal unit test for a specific API
agentic-run-paddle-unittest VENV_PATH PADDLE_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PADDLE_PATH }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=0) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=0 \
    uv run --no-project -p "{{ VENV_PATH }}" python "{{ TEST_FILE }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=1) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "{{ VENV_PATH }}" python "{{ TEST_FILE }}"

# Run PaddleTest functional test for a specific API
agentic-run-paddletest VENV_PATH PADDLETEST_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PADDLETEST_PATH }}"

    echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=0) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=0 \
    uv run --no-project -p "{{ VENV_PATH }}" python -m pytest "{{ TEST_FILE }}" -v

    echo "Running PaddleTest(FLAGS_use_accuracy_compatible_kernel=1) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "{{ VENV_PATH }}" python -m pytest "{{ TEST_FILE }}" -v

# Run PaddleAPITest precision validation (returns log directory path)
agentic-run-precision-test VENV_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PADDLEAPITEST_PATH }}"
    echo "Removing old log files..."
    rm -f PAA_test_log/{{ LOG_DIR }}/*.txt
    rm -f PAA_test_log/{{ LOG_DIR }}/*.log
    echo "Running PaddleAPITest(FLAGS_use_accuracy_compatible_kernel=1) with config: {{ CONFIG_FILE }}..."

    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "{{ VENV_PATH }}" python engineV2.py \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{ CONFIG_FILE }}" \
        --log_dir="PAA_test_log/{{ LOG_DIR }}"

    # Find and output the latest log directory
    echo "---"
    echo "Log directory: PAA_test_log/{{ LOG_DIR }}"
    echo "Full path: {{ PADDLEAPITEST_PATH }}/PAA_test_log/{{ LOG_DIR }}"
