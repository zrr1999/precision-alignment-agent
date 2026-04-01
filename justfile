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
    uvx role-forge add "$(pwd)" --project-dir "$(pwd)" -y 2>/dev/null && echo "✔ Platform configs generated" || echo "⚠ role-forge not available, run 'just adapt' later"

    echo ""
    echo "✔ Setup complete!"
    echo "Tip: Install global MCP for better performance: https://mcp.context7.com/install"

# 从 roles/ 适配生成各平台配置
adapt:
    uvx role-forge add "$(pwd)" --project-dir "$(pwd)" -y

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
start branch_name tool="opencode" additional_prompt="" runtime="direct":
    #!/usr/bin/env bash
    set -euo pipefail
    PILOT_ROOT=$(pwd)

    _paths="$(just _resolve-paths)" || { echo "❌ Path resolution failed" >&2; exit 1; }
    eval "$_paths"

    _wt="$(just _setup-worktree "$PILOT_ROOT" "$PADDLE_PATH" "{{ branch_name }}")" || { echo "❌ Worktree setup failed" >&2; exit 1; }
    eval "$_wt"

    just agentic-venv-setup "$PADDLE_PATH"
    just agentic-paddle-build-and-install "$PADDLE_PATH"

    cd "$PILOT_ROOT"
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

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT" "{{ branch_name }}" "{{ runtime }}" "$PADDLE_PATH"

# 复用现有任务分支/工作树，优先跳过已有的 build 和 venv
resume branch_name tool="opencode" additional_prompt="" runtime="direct":
    #!/usr/bin/env bash
    set -euo pipefail
    PILOT_ROOT=$(pwd)

    _paths="$(just _resolve-paths)" || { echo "❌ Path resolution failed" >&2; exit 1; }
    eval "$_paths"

    _wt="$(just _resume-worktree "$PILOT_ROOT" "$PADDLE_PATH" "{{ branch_name }}")" || { echo "❌ Worktree resume failed" >&2; exit 1; }
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

    cd "$PILOT_ROOT"
    AGENT="paddle-agent"
    ADDITIONAL_PROMPT={{ quote(additional_prompt) }}
    PROMPT="[paddle_path=$PADDLE_PATH, \
            pytorch_path=$PYTORCH_PATH, \
            paddletest_path=$PADDLETEST_PATH, \
            paddleapitest_path=$PADDLEAPITEST_PATH, \
            venv_path=$VENV_PATH] \
            $WORKTREE_CONTEXT \
            $ADDITIONAL_PROMPT"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT" "{{ branch_name }}" "{{ runtime }}" "$PADDLE_PATH"

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
_setup-worktree PILOT_ROOT PADDLE_SRC branch_name:
    #!/usr/bin/env bash
    set -euo pipefail

    WORKTREE_DIR="{{ PILOT_ROOT }}/.paddle-pilot/worktree/Paddle_{{ branch_name }}"
    BRANCH_NAME="paddle-pilot/{{ branch_name }}"
    WORKTREE_CONTEXT=""

    branch_exists() {
        git rev-parse --verify --quiet "$1" >/dev/null
    }

    mkdir -p "{{ PILOT_ROOT }}/.paddle-pilot/worktree"

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

_resume-worktree PILOT_ROOT PADDLE_SRC branch_name:
    #!/usr/bin/env bash
    set -euo pipefail

    WORKTREE_DIR="{{ PILOT_ROOT }}/.paddle-pilot/worktree/Paddle_{{ branch_name }}"
    BRANCH_NAME="paddle-pilot/{{ branch_name }}"

    branch_exists() {
        git rev-parse --verify --quiet "$1" >/dev/null
    }

    mkdir -p "{{ PILOT_ROOT }}/.paddle-pilot/worktree"

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

# 附加到某个分支对应的 zellij session
zellij-attach branch_name:
    #!/usr/bin/env bash
    set -euo pipefail
    RUNTIME_FILE=".paddle-pilot/sessions/{{ branch_name }}/runtime.json"
    if [ ! -f "$RUNTIME_FILE" ]; then
        echo "❌ Runtime metadata not found: $RUNTIME_FILE" >&2
        exit 1
    fi
    SESSION_NAME="$(python -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("zellij_session_name", ""))' "$RUNTIME_FILE")"
    if [ -z "$SESSION_NAME" ]; then
        echo "❌ Branch '{{ branch_name }}' was not launched with runtime=zellij." >&2
        exit 1
    fi
    exec zellij attach "$SESSION_NAME"

# 查看某个分支记录的 runtime 元数据，以及对应 zellij session 是否还在线
zellij-runtime-status branch_name:
    #!/usr/bin/env bash
    set -euo pipefail
    RUNTIME_FILE=".paddle-pilot/sessions/{{ branch_name }}/runtime.json"
    if [ ! -f "$RUNTIME_FILE" ]; then
        echo "❌ Runtime metadata not found: $RUNTIME_FILE" >&2
        exit 1
    fi

    python -c 'import json, sys; data = json.load(open(sys.argv[1], encoding="utf-8")); [print(f"{key}: {data.get(key)}") for key in ["runtime", "tool", "agent", "branch_name", "worktree_dir", "prompt_file", "launched_at", "zellij_session_name", "zellij_pane_id", "zellij_tab_id", "pane_name"]]' "$RUNTIME_FILE"

    SESSION_NAME="$(python -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("zellij_session_name", ""))' "$RUNTIME_FILE")"
    PANE_ID="$(python -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("zellij_pane_id", ""))' "$RUNTIME_FILE")"

    if [ -n "$SESSION_NAME" ] && command -v zellij >/dev/null 2>&1; then
        if zellij list-sessions 2>/dev/null | tr -d '\r' | grep -Fx "$SESSION_NAME" >/dev/null; then
            echo "session_running: true"
            if [ -n "$PANE_ID" ]; then
                echo "pane_snapshot:"
                zellij --session "$SESSION_NAME" action list-panes --all | awk -v pane="$PANE_ID" 'NR==1 || $1==pane'
            fi
        else
            echo "session_running: false"
        fi
    fi

# 根据 tool 类型启动 agent（支持 opencode / claude / ducc / copilot）
# prompt 会持久化到 .paddle-pilot/sessions/{branch_name}/，便于 zellij runtime 和后续 reattach
_launch-agent tool agent prompt branch_name runtime worktree_dir:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Launching agent '{{ agent }}' with tool '{{ tool }}' via runtime '{{ runtime }}'..."

    REPO_ROOT="$(pwd)"
    SESSION_DIR="$REPO_ROOT/.paddle-pilot/sessions/{{ branch_name }}"
    PROMPT_FILE="$SESSION_DIR/launch-prompt.txt"
    RUNTIME_FILE="$SESSION_DIR/runtime.json"
    mkdir -p "$SESSION_DIR"
    printf '%s' {{ quote(prompt) }} > "$PROMPT_FILE"

    sanitize_name() {
        local raw="$1"
        raw="$(printf '%s' "$raw" | tr '/[:space:]' '--' | tr -cs '[:alnum:]._-' '-')"
        raw="${raw#-}"
        raw="${raw%-}"
        if [ -z "$raw" ]; then
            raw="pilot"
        fi
        printf '%s' "$raw"
    }

    build_agent_command() {
        local tool="$1"
        local agent="$2"
        local prompt_file="$3"
        case "$tool" in
            opencode)
                printf 'cat %q | opencode --agent %q' "$prompt_file" "$agent"
                ;;
            copilot)
                printf 'copilot --agent %q --yolo -i "$(cat %q)"' "$agent" "$prompt_file"
                ;;
            claude|ducc)
                printf 'cat %q | %q --agent %q' "$prompt_file" "$tool" "$agent"
                ;;
            *)
                echo "Error: unsupported tool '$tool'. Use 'opencode', 'claude', 'ducc', or 'copilot'." >&2
                exit 1
                ;;
        esac
    }

    write_runtime_file() {
        python -c 'import json, os, sys; data = {"runtime": os.environ["PILOT_RUNTIME"], "tool": os.environ["PILOT_TOOL"], "agent": os.environ["PILOT_AGENT"], "branch_name": os.environ["PILOT_BRANCH_NAME"], "worktree_dir": os.environ["PILOT_WORKTREE_DIR"], "prompt_file": os.environ["PILOT_PROMPT_FILE"], "launch_command": os.environ["PILOT_LAUNCH_COMMAND"], "launched_at": os.environ["PILOT_LAUNCHED_AT"], "zellij_session_name": os.environ.get("PILOT_ZELLIJ_SESSION_NAME") or None, "zellij_pane_id": os.environ.get("PILOT_ZELLIJ_PANE_ID") or None, "zellij_tab_id": int(os.environ["PILOT_ZELLIJ_TAB_ID"]) if os.environ.get("PILOT_ZELLIJ_TAB_ID") else None, "pane_name": os.environ.get("PILOT_PANE_NAME") or None}; open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")' "$RUNTIME_FILE"
    }

    AGENT_COMMAND="$(build_agent_command "{{ tool }}" "{{ agent }}" "$PROMPT_FILE")"
    export PILOT_RUNTIME="{{ runtime }}"
    export PILOT_TOOL="{{ tool }}"
    export PILOT_AGENT="{{ agent }}"
    export PILOT_BRANCH_NAME="{{ branch_name }}"
    export PILOT_WORKTREE_DIR="{{ worktree_dir }}"
    export PILOT_PROMPT_FILE="$PROMPT_FILE"
    export PILOT_LAUNCH_COMMAND="$AGENT_COMMAND"
    export PILOT_LAUNCHED_AT="$(date -Iseconds)"
    export PILOT_ZELLIJ_SESSION_NAME=""
    export PILOT_ZELLIJ_PANE_ID=""
    export PILOT_ZELLIJ_TAB_ID=""
    export PILOT_PANE_NAME=""

    case "{{ runtime }}" in
        direct)
            write_runtime_file
            bash -lc "$AGENT_COMMAND"
            ;;
        zellij)
            if ! command -v zellij >/dev/null 2>&1; then
                echo "❌ runtime=zellij requested but zellij is not installed or not in PATH." >&2
                exit 1
            fi

            SESSION_NAME="$(sanitize_name "paddle-pilot-{{ branch_name }}")"
            PANE_NAME="$(sanitize_name "{{ agent }}-{{ tool }}-$(date +%Y%m%d-%H%M%S)")"

            if ! zellij list-sessions 2>/dev/null | tr -d '\r' | grep -Fx "$SESSION_NAME" >/dev/null; then
                echo "▶ Creating background zellij session: $SESSION_NAME"
                zellij attach --create-background "$SESSION_NAME" >/dev/null
            fi

            echo "▶ Launching agent in detached zellij session '$SESSION_NAME'..."
            # Use the action API to add a pane to an existing detached session without attaching.
            PANE_ID="$(zellij --session "$SESSION_NAME" action new-pane --cwd "{{ worktree_dir }}" --name "$PANE_NAME" | tr -d '\r')"
            if [ -n "$PANE_ID" ]; then
                zellij --session "$SESSION_NAME" action paste --pane-id "$PANE_ID" "$AGENT_COMMAND" >/dev/null
                zellij --session "$SESSION_NAME" action send-keys --pane-id "$PANE_ID" "Enter" >/dev/null
            fi

            if [ -z "$PANE_ID" ]; then
                read -r PANE_ID TAB_ID < <(
                    { zellij --session "$SESSION_NAME" action list-panes --json 2>/dev/null || true; } | python -c 'import json, sys; pane_name = sys.argv[1]; raw = sys.stdin.read().strip(); panes = json.loads(raw) if raw else []; match = next((pane for pane in panes if pane.get("title") == pane_name), None); prefix = "plugin" if match and match.get("is_plugin") else "terminal"; tab_id = "" if not match or match.get("tab_id") is None else match.get("tab_id"); print("" if match is None else f"{prefix}_{match['"'"'id'"'"']} {tab_id}")' "$PANE_NAME"
                )
            else
                TAB_ID="$({ zellij --session "$SESSION_NAME" action list-panes --json 2>/dev/null || true; } | python -c 'import json, sys; pane_id = sys.argv[1]; raw = sys.stdin.read().strip(); panes = json.loads(raw) if raw else []; match = next((pane for pane in panes if ("plugin_" if pane.get("is_plugin") else "terminal_") + str(pane["id"]) == pane_id), None); print("" if not match or match.get("tab_id") is None else match.get("tab_id"))' "$PANE_ID")"
            fi

            export PILOT_ZELLIJ_SESSION_NAME="$SESSION_NAME"
            export PILOT_ZELLIJ_PANE_ID="$PANE_ID"
            export PILOT_ZELLIJ_TAB_ID="$TAB_ID"
            export PILOT_PANE_NAME="$PANE_NAME"
            write_runtime_file

            echo "✔ Zellij session ready: $SESSION_NAME"
            if [ -n "$PANE_ID" ]; then
                echo "✔ Agent pane: $PANE_ID"
            fi
            echo "Tip: run 'just zellij-attach {{ branch_name }}' to attach."
            ;;
        *)
            echo "Error: unsupported runtime '{{ runtime }}'. Use 'direct' or 'zellij'." >&2
            exit 1
            ;;
    esac

# ============================================================================
# Agentic Commands — thin wrappers to skills/*/scripts/
#
# Agents should prefer calling scripts directly via the skill SKILL.md.
# These recipes exist so `just start` / `just resume` keep working.
# ============================================================================

# --- paddle-build ---

agentic-venv-setup PADDLE_PATH:
    bash skills/paddle-build/scripts/venv-setup.sh {{ PADDLE_PATH }}

agentic-paddle-build-and-install PADDLE_PATH:
    bash skills/paddle-build/scripts/paddle-build.sh {{ PADDLE_PATH }}

# --- paddle-test ---

agentic-run-paddle-unittest PADDLE_PATH TEST_FILE:
    bash skills/paddle-test/scripts/run-unittest.sh {{ PADDLE_PATH }} {{ TEST_FILE }}

agentic-run-paddletest PADDLE_PATH PADDLETEST_PATH TEST_FILE:
    bash skills/paddle-test/scripts/run-paddletest.sh {{ PADDLE_PATH }} {{ PADDLETEST_PATH }} {{ TEST_FILE }}

# --- precision-validation ---

agentic-get-precision-test-configs API_NAME PADDLEAPITEST_PATH:
    bash skills/precision-validation/scripts/get-configs.sh {{ API_NAME }} {{ PADDLEAPITEST_PATH }}

agentic-run-precision-test PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    bash skills/precision-validation/scripts/run-precision-test.sh {{ PADDLE_PATH }} {{ PADDLEAPITEST_PATH }} {{ CONFIG_FILE }} {{ LOG_DIR }}

agentic-run-precision-cpu-test PADDLE_PATH PADDLEAPITEST_PATH CONFIG_FILE LOG_DIR:
    bash skills/precision-validation/scripts/run-precision-cpu-test.sh {{ PADDLE_PATH }} {{ PADDLEAPITEST_PATH }} {{ CONFIG_FILE }} {{ LOG_DIR }}

agentic-run-tensorspec-paddleonly VENV_PATH CASE_FILE LOG_DIR:
    bash skills/precision-validation/scripts/run-tensorspec-paddleonly.sh {{ VENV_PATH }} {{ CASE_FILE }} {{ LOG_DIR }}

agentic-run-tensorspec-accuracy VENV_PATH CASE_FILE LOG_DIR:
    bash skills/precision-validation/scripts/run-tensorspec-accuracy.sh {{ VENV_PATH }} {{ CASE_FILE }} {{ LOG_DIR }}
