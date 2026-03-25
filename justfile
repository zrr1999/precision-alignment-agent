# 列出所有可用的命令
default:
    @just --list

# ============================================================================
# Setup & Configuration
# ============================================================================

# 安装所有依赖
setup:
    #!/usr/bin/env bash
    set -euo pipefail

    has() { command -v "$1" &>/dev/null; }

    if has curl; then
        FETCH="curl -fsSL"
    elif has wget; then
        FETCH="wget -qO-"
    else
        echo "Error: neither curl nor wget found." >&2; exit 1
    fi

    # --- uv ---
    if has uv; then
        echo "✔ uv already installed: $(uv --version)"
    else
        echo "▶ Installing uv..."
        $FETCH https://astral.sh/uv/install.sh | sh
        [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env" 2>/dev/null || true
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" 2>/dev/null || true
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        has uv && echo "✔ uv installed: $(uv --version)" || echo "⚠ uv installed but not in PATH, restart your shell"
    fi

    # --- bun ---
    if has bun; then
        echo "✔ bun already installed: $(bun --version)"
    else
        echo "▶ Installing bun..."
        $FETCH https://bun.sh/install | bash
        [ -f "$HOME/.bun/bin/bun" ] && export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"
        has bun && echo "✔ bun installed: $(bun --version)" || echo "⚠ bun installed but not in PATH, restart your shell"
    fi

    # --- gh ---
    if has gh; then
        echo "✔ gh already installed: $(gh --version | head -1)"
    else
        echo "▶ Installing gh via x-cmd..."
        if ! has x; then
            eval "$($FETCH https://get.x-cmd.com)" 2>/dev/null || true
        fi
        if has x; then
            x env use gh
            echo "✔ gh installed"
        else
            echo "⚠ Failed to install gh via x-cmd. Install manually: https://cli.github.com"
        fi
    fi

    # --- 全局工具 ---
    echo "▶ Installing global tools..."
    bun install -g opencode-ai 2>/dev/null && echo "✔ opencode-ai installed" || echo "⚠ Failed to install opencode-ai"
    bun install -g ocx 2>/dev/null && echo "✔ ocx installed" || echo "⚠ Failed to install ocx"
    bun install -g repomix 2>/dev/null && echo "✔ repomix installed" || echo "⚠ Failed to install repomix"

    # --- Claude Code skills ---
    echo "▶ Installing Claude Code skills..."
    bunx skills add PFCCLab/paddle-skills -g -y --skill "*" -a claude-code 2>/dev/null && echo "✔ paddle-skills installed" || echo "⚠ Failed to install paddle-skills"
    bunx skills add anthropics/skills -g -y --skill skill-creator -a claude-code 2>/dev/null && echo "✔ skill-creator installed" || echo "⚠ Failed to install skill-creator"
    bunx skills add yamadashy/repomix -g -y --skill repomix-explorer -a claude-code 2>/dev/null && echo "✔ repomix-explorer installed" || echo "⚠ Failed to install repomix-explorer"
    bunx skills add ast-grep/agent-skill -g -y --skill "*" -a claude-code 2>/dev/null && echo "✔ ast-grep installed" || echo "⚠ Failed to install ast-grep"
    bunx skills add OthmanAdi/planning-with-files -g -y --skill "planning-with-files" -a claude-code 2>/dev/null && echo "✔ planning-with-files installed" || echo "⚠ Failed to install planning-with-files"

    # --- 生成平台配置 ---
    echo "▶ Generating platform configs..."
    uvx role-forge render 2>/dev/null && echo "✔ Platform configs generated" || echo "⚠ role-forge not available, run 'just adapt' later"

    echo ""
    echo "✔ Setup complete!"
    echo "Tip: Install global MCP for better performance: https://mcp.context7.com/install"

# 从 roles/ 适配生成各平台配置
adapt:
    uvx role-forge render

# 更新配置和 skills（adapt + skills update）
update:
    #!/usr/bin/env bash
    set -euo pipefail
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paddle-pilot/repos/PaddleAPITest}"

    git pull
    just adapt
    bunx skills update -g

    cd $PADDLEAPITEST_PATH
    bash auto_get_api_config.sh paa

# 初始化仓库
setup-repos username="":
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_NAMES=("Paddle" "PaddleTest" "PaddleAPITest" "pytorch")
    UPSTREAMS=("PaddlePaddle/Paddle" "PaddlePaddle/PaddleTest" "PFCCLab/PaddleAPITest" "pytorch/pytorch")

    # 检查是否全部已 clone
    ALL_CLONED=true
    for REPO_NAME in "${REPO_NAMES[@]}"; do
        if [ ! -d ".paddle-pilot/repos/$REPO_NAME" ]; then
            ALL_CLONED=false
            break
        fi
    done

    if $ALL_CLONED; then
        echo "✔ All repos already cloned, nothing to do"
        exit 0
    fi

    USERNAME="{{ username }}"

    if [ -z "$USERNAME" ]; then
        read -rp "GitHub username: " USERNAME
        if [ -z "$USERNAME" ]; then
            echo "✘ Username is required." >&2; exit 1
        fi
    fi

    mkdir -p .paddle-pilot/repos

    for i in "${!UPSTREAMS[@]}"; do
        UPSTREAM="${UPSTREAMS[$i]}"
        REPO_NAME="${REPO_NAMES[$i]}"
        TARGET=".paddle-pilot/repos/$REPO_NAME"

        if [ -d "$TARGET" ]; then
            echo "✔ $REPO_NAME already cloned, skipping"
            continue
        fi

        FORK_URL="https://github.com/$USERNAME/$REPO_NAME.git"
        if git ls-remote "$FORK_URL" &>/dev/null; then
            echo "▶ Cloning $USERNAME/$REPO_NAME..."
            git clone "$FORK_URL" "$TARGET"
        else
            echo "⚠ Fork not found: $USERNAME/$REPO_NAME"
            read -rp "  Fork $UPSTREAM to your account? [Y/n] " ans
            if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
                gh repo fork "$UPSTREAM" --clone --clone-dir "$TARGET"
                echo "✔ Forked and cloned $UPSTREAM"
            else
                echo "▶ Skipping $REPO_NAME"
                continue
            fi
        fi

        # 添加 upstream remote
        cd "$TARGET"
        if ! git remote get-url upstream &>/dev/null; then
            git remote add upstream "https://github.com/$UPSTREAM.git"
        fi
        cd - >/dev/null
    done

    echo "✔ Repos ready at .paddle-pilot/repos/"

# 启动 paddle-agent
start branch_name tool="opencode" additional_prompt="":
    #!/usr/bin/env bash
    set -euo pipefail
    PAA_ROOT=$(pwd)

    _paths="$(just _resolve-paths)" || { echo "❌ Path resolution failed" >&2; exit 1; }
    eval "$_paths"

    _wt="$(just _setup-worktree "$PAA_ROOT" "$PADDLE_PATH" "{{ branch_name }}")" || { echo "❌ Worktree setup failed" >&2; exit 1; }
    eval "$_wt"

    just agentic-venv-setup "$PADDLE_PATH"
    just agentic-paddle-build-and-install "$PADDLE_PATH"

    cd "$PAA_ROOT"
    AGENT="paddle-agent"
    ADDITIONAL_PROMPT={{ quote(additional_prompt) }}
    PROMPT="[paddle_path=$PADDLE_PATH, \
            pytorch_path(v2.9.1)=$PYTORCH_PATH, \
            paddletest_path=$PADDLETEST_PATH, \
            paddleapitest_path=$PADDLEAPITEST_PATH, \
            venv_path=$VENV_PATH] \
            $WORKTREE_CONTEXT \
            需要把用户的要求全量修完，剩余 case 如确实不能修，必须给出可核查的实现/上游限制依据，不接受泛泛理由。\
            $ADDITIONAL_PROMPT"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT"

# 复用现有任务分支/工作树，优先跳过已有的 build 和 venv
resume branch_name tool="opencode" additional_prompt="":
    #!/usr/bin/env bash
    set -euo pipefail
    PAA_ROOT=$(pwd)

    _paths="$(just _resolve-paths)" || { echo "❌ Path resolution failed" >&2; exit 1; }
    eval "$_paths"

    _wt="$(just _resume-worktree "$PAA_ROOT" "$PADDLE_PATH" "{{ branch_name }}")" || { echo "❌ Worktree resume failed" >&2; exit 1; }
    eval "$_wt"

    if [ ! -d "$VENV_PATH" ]; then
        echo "▶ .venv missing, recreating environment..." >&2
        just agentic-venv-setup "$PADDLE_PATH"
    else
        echo "✔ Reusing existing venv: $VENV_PATH" >&2
    fi

    if compgen -G "$PADDLE_PATH/build/python/dist/*.whl" >/dev/null; then
        echo "✔ Reusing existing build artifacts" >&2
    else
        echo "▶ Build artifacts missing, rebuilding Paddle..." >&2
        just agentic-paddle-build-and-install "$PADDLE_PATH"
    fi

    cd "$PAA_ROOT"
    AGENT="paddle-agent"
    ADDITIONAL_PROMPT={{ quote(additional_prompt) }}
    PROMPT="[paddle_path=$PADDLE_PATH, \
            pytorch_path=$PYTORCH_PATH, \
            paddletest_path=$PADDLETEST_PATH, \
            paddleapitest_path=$PADDLEAPITEST_PATH, \
            venv_path=$VENV_PATH] \
            $WORKTREE_CONTEXT \
            $ADDITIONAL_PROMPT"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT"

# ============================================================================
# Internal Recipes (prefixed with _)
# ============================================================================

# Resolve all repo paths to absolute paths. Outputs eval-able KEY=VALUE lines to stdout.
# Informational messages go to stderr.
_resolve-paths:
    #!/usr/bin/env bash
    set -euo pipefail

    PADDLE_PATH="${PADDLE_PATH:=.paddle-pilot/repos/Paddle}"
    PYTORCH_PATH="${PYTORCH_PATH:=.paddle-pilot/repos/pytorch}"
    PADDLETEST_PATH="${PADDLETEST_PATH:=.paddle-pilot/repos/PaddleTest}"
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paddle-pilot/repos/PaddleAPITest}"

    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    PYTORCH_PATH="$(cd "$PYTORCH_PATH" && pwd)"
    PADDLETEST_PATH="$(cd "$PADDLETEST_PATH" && pwd)"
    PADDLEAPITEST_PATH="$(cd "$PADDLEAPITEST_PATH" && pwd)"

    echo "  PADDLE_PATH:       $PADDLE_PATH" >&2
    echo "  PYTORCH_PATH:      $PYTORCH_PATH" >&2
    echo "  PADDLETEST_PATH:   $PADDLETEST_PATH" >&2
    echo "  PADDLEAPITEST_PATH:$PADDLEAPITEST_PATH" >&2

    printf 'PADDLE_PATH=%q\n' "$PADDLE_PATH"
    printf 'PYTORCH_PATH=%q\n' "$PYTORCH_PATH"
    printf 'PADDLETEST_PATH=%q\n' "$PADDLETEST_PATH"
    printf 'PADDLEAPITEST_PATH=%q\n' "$PADDLEAPITEST_PATH"

# Setup worktree with interactive reuse prompts. Outputs eval-able KEY=VALUE lines to stdout.
# If worktree already exists, asks user whether to create a fresh branch (default: No).
#   - No:  reuse existing worktree, WORKTREE_CONTEXT contains resume notice for agent.
#   - Yes: create fresh branch (clean git tracking), optionally keep build/ and .venv/.
_setup-worktree PAA_ROOT PADDLE_SRC branch_name:
    #!/usr/bin/env bash
    set -euo pipefail

    WORKTREE_DIR="{{ PAA_ROOT }}/.paddle-pilot/worktree/Paddle_{{ branch_name }}"
    BRANCH_NAME="paddle-pilot/{{ branch_name }}"
    WORKTREE_CONTEXT=""

    branch_exists() {
        git rev-parse --verify --quiet "$1" >/dev/null
    }

    mkdir -p "{{ PAA_ROOT }}/.paddle-pilot/worktree"

    # Sync base branch
    cd "{{ PADDLE_SRC }}"
    git switch -c paddle-pilot/develop 2>/dev/null || git switch paddle-pilot/develop
    echo "▶ Syncing upstream develop..." >&2
    git pull upstream develop >&2
    echo "▶ Pruning stale worktree metadata..." >&2
    git worktree prune --verbose >&2 || true

    if [ -d "$WORKTREE_DIR" ]; then
        echo "" >&2
        echo "⚠  Worktree already exists: $WORKTREE_DIR" >&2
        cd "$WORKTREE_DIR"
        CURRENT_BRANCH=$(git branch --show-current)
        LAST_COMMIT=$(git log --oneline -1)
        echo "   Branch:      $CURRENT_BRANCH" >&2
        echo "   Last commit:  $LAST_COMMIT" >&2
        DIRTY=""
        STATUS_OUTPUT="$(git status --porcelain --ignore-submodules=all 2>/dev/null || true)"
        if [ -n "$STATUS_OUTPUT" ]; then
            DIRTY=" (has uncommitted changes)"
            echo "   Status:      uncommitted changes present" >&2
        fi
        echo "" >&2

        read -rp "Create fresh branch? (overwrites existing) [y/N] " fresh < /dev/tty
        if [[ "${fresh:-N}" =~ ^[Yy]$ ]]; then
            # --- Fresh branch ---
            read -rp "Keep existing build directory? [Y/n] " keep_build < /dev/tty

            BUILD_BACKUP=""
            if [[ "${keep_build:-Y}" =~ ^[Yy]$ ]]; then
                BUILD_BACKUP=$(mktemp -d)
                echo "   Saving build & venv..." >&2
                [ -d "$WORKTREE_DIR/build" ] && mv "$WORKTREE_DIR/build" "$BUILD_BACKUP/build"
                [ -d "$WORKTREE_DIR/.venv" ] && mv "$WORKTREE_DIR/.venv" "$BUILD_BACKUP/.venv"
            fi

            echo "   Removing old worktree..." >&2
            cd "{{ PADDLE_SRC }}"
            git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR"
            git worktree prune --verbose >&2 || true
            if branch_exists "$BRANCH_NAME"; then
                if ! git branch -D "$BRANCH_NAME" >&2; then
                    echo "❌ Branch $BRANCH_NAME already exists and could not be deleted. It may still be checked out in another worktree." >&2
                    exit 1
                fi
            fi
            git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" >&2

            if [ -n "$BUILD_BACKUP" ]; then
                [ -d "$BUILD_BACKUP/build" ] && mv "$BUILD_BACKUP/build" "$WORKTREE_DIR/build"
                [ -d "$BUILD_BACKUP/.venv" ] && mv "$BUILD_BACKUP/.venv" "$WORKTREE_DIR/.venv"
                rm -rf "$BUILD_BACKUP"
                echo "   ✔ Restored build & venv" >&2
            fi
            echo "   ✔ Fresh worktree created" >&2
        else
            # --- Reuse existing worktree ---
            echo "   ✔ Reusing existing worktree" >&2
            read -rp "Pull latest from upstream develop? [y/N] " do_pull < /dev/tty
            if [[ "${do_pull:-N}" =~ ^[Yy]$ ]]; then
                echo "   ▶ Pulling upstream develop..." >&2
                git pull upstream develop >&2 || echo "   ⚠ Pull failed, continuing with current state" >&2
                LAST_COMMIT=$(git log --oneline -1)
            fi
            WORKTREE_CONTEXT="IMPORTANT: This is a RESUMED session on existing branch '$CURRENT_BRANCH' (last commit: $LAST_COMMIT)${DIRTY}. Check git log and existing work before making changes."
        fi
    else
        if branch_exists "$BRANCH_NAME"; then
            git worktree add "$WORKTREE_DIR" "$BRANCH_NAME" >&2
            WORKTREE_CONTEXT="IMPORTANT: This is a RESUMED session on existing branch '$BRANCH_NAME' reattached to a recreated worktree. Check git log and existing work before making changes."
            echo "   ✔ Reattached existing branch to new worktree: $WORKTREE_DIR" >&2
        else
            git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" >&2
            echo "   ✔ New worktree created: $WORKTREE_DIR" >&2
        fi
    fi

    printf 'PADDLE_PATH=%q\n' "$WORKTREE_DIR"
    printf 'VENV_PATH=%q\n' "$WORKTREE_DIR/.venv"
    printf 'WORKTREE_CONTEXT=%q\n' "$WORKTREE_CONTEXT"

_resume-worktree PAA_ROOT PADDLE_SRC branch_name:
    #!/usr/bin/env bash
    set -euo pipefail

    WORKTREE_DIR="{{ PAA_ROOT }}/.paddle-pilot/worktree/Paddle_{{ branch_name }}"
    BRANCH_NAME="paddle-pilot/{{ branch_name }}"

    branch_exists() {
        git rev-parse --verify --quiet "$1" >/dev/null
    }

    mkdir -p "{{ PAA_ROOT }}/.paddle-pilot/worktree"

    cd "{{ PADDLE_SRC }}"
    git switch -c paddle-pilot/develop 2>/dev/null || git switch paddle-pilot/develop
    echo "▶ Pruning stale worktree metadata..." >&2
    git worktree prune --verbose >&2 || true

    if [ -d "$WORKTREE_DIR" ]; then
        cd "$WORKTREE_DIR"
        CURRENT_BRANCH=$(git branch --show-current)
        LAST_COMMIT=$(git log --oneline -1)
        STATUS_OUTPUT="$(git status --porcelain --ignore-submodules=all 2>/dev/null || true)"
        DIRTY=""
        if [ -n "$STATUS_OUTPUT" ]; then
            DIRTY=" (has uncommitted changes)"
        fi
        echo "✔ Reusing existing worktree: $WORKTREE_DIR" >&2
        read -rp "Pull latest from upstream develop? [y/N] " do_pull < /dev/tty
        if [[ "${do_pull:-N}" =~ ^[Yy]$ ]]; then
            echo "  ▶ Pulling upstream develop..." >&2
            git pull upstream develop >&2 || echo "  ⚠ Pull failed, continuing with current state" >&2
            LAST_COMMIT=$(git log --oneline -1)
        fi
        WORKTREE_CONTEXT="IMPORTANT: This is a RESUMED session on existing branch '$CURRENT_BRANCH' (last commit: $LAST_COMMIT)${DIRTY}. Check git log and existing work before making changes."
    elif branch_exists "$BRANCH_NAME"; then
        git worktree add "$WORKTREE_DIR" "$BRANCH_NAME" >&2
        WORKTREE_CONTEXT="IMPORTANT: This is a RESUMED session on existing branch '$BRANCH_NAME' reattached to a recreated worktree. Check git log and existing work before making changes."
        echo "✔ Reattached existing branch to new worktree: $WORKTREE_DIR" >&2
    else
        echo "❌ No existing task found for $BRANCH_NAME. Run 'just start {{ branch_name }} ...' first." >&2
        exit 1
    fi

    printf 'PADDLE_PATH=%q\n' "$WORKTREE_DIR"
    printf 'VENV_PATH=%q\n' "$WORKTREE_DIR/.venv"
    printf 'WORKTREE_CONTEXT=%q\n' "$WORKTREE_CONTEXT"

# 根据 tool 类型启动 agent（支持 opencode / claude / ducc）
# prompt 写入临时文件再通过 stdin 管道传入，避免 shell 转义和参数长度问题
_launch-agent tool agent prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Launching agent '{{ agent }}' with tool '{{ tool }}'..."

    PROMPT_FILE=$(mktemp /tmp/paa-prompt-XXXXXX.txt)
    printf '%s' {{ quote(prompt) }} > "$PROMPT_FILE"
    trap 'rm -f "$PROMPT_FILE"' EXIT

    case "{{ tool }}" in
        opencode)
            # cat "$PROMPT_FILE" | opencode run --agent {{ quote(agent) }}
            cat "$PROMPT_FILE" | opencode --agent {{ quote(agent) }}
            ;;
        copilot)
            copilot --agent {{ quote(agent) }} --yolo -i "$(cat $PROMPT_FILE)"
            ;;
        claude|ducc)
            cat "$PROMPT_FILE" | {{ tool }} --agent {{ quote(agent) }}
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
# All commands require explicit path parameters.
# ============================================================================

# --- Build & Environment ---

# Create or update relocatable venv with Paddle deps (torch, func_timeout, etc.) and Paddle python/requirements.txt.
agentic-venv-setup PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ PADDLE_PATH }}/
    if [ ! -d "{{ PADDLE_PATH }}/.venv" ]; then
        uv venv --relocatable --seed --python 3.12
    fi
    source .venv/bin/activate
    uvx prek install
    uv pip install -r {{ PADDLE_PATH }}/python/requirements.txt
    uv pip install wheel func_timeout pandas pebble pynvml pyyaml typer httpx "numpy<2.0" torchvision torch==2.9.1
    uv pip install tensor_spec
    echo "Dependencies install completed successfully in {{PADDLE_PATH}}."

# Build and install Paddle in virtual environment
agentic-paddle-build-and-install PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building Paddle..."
    cd "{{ PADDLE_PATH }}"
    source .venv/bin/activate
    mkdir -p build
    cd build
    cmake .. -DPADDLE_VERSION=0.0.0 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCUDA_ARCH_NAME=Auto -DWITH_GPU=ON -DWITH_DISTRIBUTE=ON -DWITH_UNITY_BUILD=OFF -DWITH_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DWITH_CINN=ON -GNinja \
    -DPY_VERSION=3.12 -DPYTHON_EXECUTABLE=$(which python) -DPYTHON_INCLUDE_DIR=$(python -c "import sysconfig; print(sysconfig.get_path('include'))") -DPYTHON_LIBRARY=$(python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))")/libpython3.so
    ninja -j$(nproc)
    echo "Installing Paddle..."
    cd "{{ PADDLE_PATH }}"
    uv pip install {{ PADDLE_PATH }}/build/python/dist/*.whl --no-deps --force-reinstall
    echo "Paddle build and install completed successfully."

# --- Testing: Paddle Unit Tests & PaddleTest ---

# Run Paddle internal unit test for a specific API
agentic-run-paddle-unittest PADDLE_PATH TEST_FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PADDLE_PATH }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=0) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=0 \
    uv run --no-project python "{{ TEST_FILE }}"

    echo "Running Paddle unittest(FLAGS_use_accuracy_compatible_kernel=1) for {{ TEST_FILE }}..."
    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project python "{{ TEST_FILE }}"

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

# --- Testing: PaddleAPITest Precision ---

# Extract precision test configs for an API from PaddleAPITest paa.txt into .paddle-pilot/config/{API_NAME}.txt for Validator use.
agentic-get-precision-test-configs API_NAME PADDLEAPITEST_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    cat {{PADDLEAPITEST_PATH}}/.api_config/paa-v0/paa/paa.txt | grep {{API_NAME}} > .paddle-pilot/config/{{API_NAME}}.txt
    echo "config file is saved to $(pwd)/.paddle-pilot/config/{{API_NAME}}.txt"

# Run PaddleAPITest precision validation (returns log directory path)
agentic-run-precision-test PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    cd "{{ PADDLEAPITEST_PATH }}"
    echo "Removing old log files..."
    rm -f paddle_pilot_test_log/{{ LOG_DIR }}/*.txt
    rm -f paddle_pilot_test_log/{{ LOG_DIR }}/*.log
    echo "Running PaddleAPITest(FLAGS_use_accuracy_compatible_kernel=1) with config: {{ CONFIG_FILE }}..."

    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "$VENV_PATH" python engineV2.py \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{ CONFIG_FILE }}" \
        --log_dir="paddle_pilot_test_log/{{ LOG_DIR }}"

    # Find and output the latest log directory
    echo "---"
    echo "Log directory: paddle_pilot_test_log/{{ LOG_DIR }}"
    echo "Full path: {{ PADDLEAPITEST_PATH }}/paddle_pilot_test_log/{{ LOG_DIR }}"

# Run PaddleAPITest precision cpu validation (returns log directory path)
agentic-run-precision-cpu-test PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    cd "{{ PADDLEAPITEST_PATH }}"
    echo "Removing old log files..."
    rm -f paddle_pilot_test_log/{{ LOG_DIR }}/*.txt
    rm -f paddle_pilot_test_log/{{ LOG_DIR }}/*.log
    echo "Running PaddleAPITest(FLAGS_use_accuracy_compatible_kernel=1) with config: {{ CONFIG_FILE }}..."

    FLAGS_use_accuracy_compatible_kernel=1 \
    uv run --no-project -p "$VENV_PATH" python engineV2.py \
        --test_cpu=1 \
        --atol=0 \
        --rtol=0 \
        --accuracy=True \
        --api_config_file="{{ CONFIG_FILE }}" \
        --log_dir="paddle_pilot_test_log/{{ LOG_DIR }}"

    # Find and output the latest log directory
    echo "---"
    echo "Log directory: paddle_pilot_test_log/{{ LOG_DIR }}"
    echo "Full path: {{ PADDLEAPITEST_PATH }}/paddle_pilot_test_log/{{ LOG_DIR }}"

# --- Testing: tensor-spec (Bug-Fix Workflow) ---
# Usage: `uvx tensor-spec check` — no local clone needed.
#   1 backend  → paddleonly (crash detection)
#   2 backends → accuracy comparison

# Run tensor-spec paddleonly check (single backend, crash detection). For bug-fix validation Stage A.
agentic-run-tensorspec-paddleonly VENV_PATH CASE_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ LOG_DIR }}"
    echo "Running tensor-spec paddleonly check..."
    echo "Case file: {{ CASE_FILE }}"
    echo "Log dir: {{ LOG_DIR }}"
    uvx tensor-spec check \
        --backend paddle \
        --case-file "{{ CASE_FILE }}" \
        --python "{{ VENV_PATH }}/bin/python" \
        --log-file "{{ LOG_DIR }}/paddleonly.jsonl" \
        --verbose || true
    echo "---"
    echo "Results: {{ LOG_DIR }}/paddleonly.jsonl"

# Run tensor-spec accuracy check (dual backend comparison). For bug-fix validation Stage B.
agentic-run-tensorspec-accuracy VENV_PATH CASE_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ LOG_DIR }}"
    echo "Running tensor-spec accuracy check..."
    echo "Case file: {{ CASE_FILE }}"
    echo "Log dir: {{ LOG_DIR }}"
    uvx tensor-spec check \
        --backend paddle --backend torch \
        --case-file "{{ CASE_FILE }}" \
        --python "{{ VENV_PATH }}/bin/python" \
        --log-file "{{ LOG_DIR }}/accuracy.jsonl" \
        --verbose || true
    echo "---"
    echo "Results: {{ LOG_DIR }}/accuracy.jsonl"
