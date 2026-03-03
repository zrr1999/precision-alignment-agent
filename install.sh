#!/usr/bin/env bash
# Precision Alignment Agent (PAA) - One-click installer
# Usage: curl -fsSL https://raw.githubusercontent.com/zrr1999/precision-alignment-agent/main/install.sh | bash
#
# Options (via environment variables):
#   PAA_DIR       - Installation directory (default: ./precision-alignment-agent)
#   PAA_SKIP_DEPS - Set to 1 to skip installing bun/uv/just/gh (default: 0)
#   PAA_BRANCH    - Git branch to clone (default: main)

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { printf "${BLUE}▶${RESET} %s\n" "$*"; }
success() { printf "${GREEN}✔${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${RESET} %s\n" "$*"; }
error()   { printf "${RED}✘${RESET} %s\n" "$*" >&2; }
step()    { printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

# ─── Config ──────────────────────────────────────────────────────────────────
PAA_DIR="${PAA_DIR:-precision-alignment-agent}"
PAA_BRANCH="${PAA_BRANCH:-main}"
PAA_SKIP_DEPS="${PAA_SKIP_DEPS:-0}"
PAA_REPO="https://github.com/zrr1999/precision-alignment-agent.git"

# ─── Banner ──────────────────────────────────────────────────────────────────
printf "${BOLD}${CYAN}"
cat << 'BANNER'

  ╔═══════════════════════════════════════════════════╗
  ║    Precision Alignment Agent (PAA) Installer      ║
  ║    Auto-align Paddle ↔ PyTorch API precision      ║
  ╚═══════════════════════════════════════════════════╝

BANNER
printf "${RESET}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
has() { command -v "$1" &>/dev/null; }

ensure_curl_or_wget() {
    if has curl; then
        FETCH="curl -fsSL"
    elif has wget; then
        FETCH="wget -qO-"
    else
        error "Neither curl nor wget found. Please install one of them first."
        exit 1
    fi
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"

ensure_curl_or_wget
success "HTTP client: $(has curl && echo curl || echo wget)"

if ! has git; then
    error "git is required but not found. Please install git first."
    exit 1
fi
success "git: $(git --version | head -1)"

OS="$(uname -s)"
ARCH="$(uname -m)"
info "Platform: ${OS}/${ARCH}"

# ─── Install dependencies ───────────────────────────────────────────────────
if [ "$PAA_SKIP_DEPS" != "1" ]; then

    # --- just (task runner) ---
    step "Installing just"
    if has just; then
        success "just already installed: $(just --version)"
    else
        info "Installing just..."
        if has cargo; then
            cargo install just
        elif [ "$OS" = "Linux" ]; then
            $FETCH https://just.systems/install.sh | bash -s -- --to /usr/local/bin 2>/dev/null || \
            $FETCH https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin"
        elif [ "$OS" = "Darwin" ]; then
            if has brew; then
                brew install just
            else
                $FETCH https://just.systems/install.sh | bash -s -- --to /usr/local/bin 2>/dev/null || \
                $FETCH https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin"
            fi
        fi
        # Add to PATH if installed to ~/.local/bin
        if [ -f "$HOME/.local/bin/just" ] && ! has just; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
        if has just; then
            success "just installed: $(just --version)"
        else
            warn "Failed to install just. Please install it manually: https://just.systems"
        fi
    fi

    # --- uv (Python package manager) ---
    step "Installing uv"
    if has uv; then
        success "uv already installed: $(uv --version)"
    else
        info "Installing uv..."
        $FETCH https://astral.sh/uv/install.sh | sh
        # Source env to pick up uv
        [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env" 2>/dev/null || true
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" 2>/dev/null || true
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        if has uv; then
            success "uv installed: $(uv --version)"
        else
            warn "uv installed but not in PATH. You may need to restart your shell."
        fi
    fi

    # --- bun (JavaScript runtime) ---
    step "Installing bun"
    if has bun; then
        success "bun already installed: $(bun --version)"
    else
        info "Installing bun..."
        $FETCH https://bun.sh/install | bash
        # Source env
        [ -f "$HOME/.bun/bin/bun" ] && export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"
        if has bun; then
            success "bun installed: $(bun --version)"
        else
            warn "bun installed but not in PATH. You may need to restart your shell."
        fi
    fi

    # --- gh (GitHub CLI) ---
    step "Installing gh"
    if has gh; then
        success "gh already installed: $(gh --version | head -1)"
    else
        info "Installing gh via x-cmd..."
        if ! has x; then
            eval "$($FETCH https://get.x-cmd.com)" 2>/dev/null || true
        fi
        if has x; then
            x env use gh
            success "gh installed"
        else
            warn "Failed to install gh via x-cmd. You can install it manually: https://cli.github.com"
        fi
    fi

else
    step "Skipping dependency installation (PAA_SKIP_DEPS=1)"
fi

# ─── Clone the project ──────────────────────────────────────────────────────
step "Cloning precision-alignment-agent"

if [ -d "$PAA_DIR/.git" ]; then
    info "Directory $PAA_DIR already exists, pulling latest changes..."
    cd "$PAA_DIR"
    git pull origin "$PAA_BRANCH" || warn "Failed to pull, continuing with existing code"
else
    info "Cloning from $PAA_REPO (branch: $PAA_BRANCH)..."
    git clone --branch "$PAA_BRANCH" "$PAA_REPO" "$PAA_DIR"
    cd "$PAA_DIR"
fi
success "Project cloned to $(pwd)"

# ─── Install global tools ───────────────────────────────────────────────────
step "Installing global tools"

if has bun; then
    info "Installing opencode-ai..."
    bun install -g opencode-ai 2>/dev/null && success "opencode-ai installed" || warn "Failed to install opencode-ai"

    info "Installing ocx..."
    bun install -g ocx 2>/dev/null && success "ocx installed" || warn "Failed to install ocx"

    info "Installing repomix..."
    bun install -g repomix 2>/dev/null && success "repomix installed" || warn "Failed to install repomix"
else
    warn "bun not available, skipping global tool installation"
fi

# ─── Install Claude Code skills ──────────────────────────────────────────────
step "Installing Claude Code skills"

if has bunx; then
    SKILLS=(
        "PFCCLab/paddle-skills|-g -y --skill * -a claude-code"
        "anthropics/skills|-g -y --skill skill-creator -a claude-code"
        "yamadashy/repomix|-g -y --skill repomix-explorer -a claude-code"
        "ast-grep/agent-skill|-g -y --skill * -a claude-code"
        'OthmanAdi/planning-with-files|-g -y --skill "planning-with-files" -a claude-code'
    )

    for entry in "${SKILLS[@]}"; do
        IFS='|' read -r repo flags <<< "$entry"
        skill_name="$(basename "$repo")"
        info "Installing skill: $skill_name..."
        eval "bunx skills add $repo $flags" 2>/dev/null && success "$skill_name installed" || warn "Failed to install $skill_name"
    done
else
    warn "bunx not available, skipping skills installation"
fi

# ─── Generate platform configs ───────────────────────────────────────────────
step "Generating platform configs"

if has uv; then
    info "Running agent-caster to generate platform configs..."
    uvx agent-caster cast 2>/dev/null && success "Platform configs generated" || warn "agent-caster not available or failed, you can run 'just adapt' later"
else
    warn "uv not available, skipping config generation. Run 'just adapt' after installing uv."
fi

# ─── Done ────────────────────────────────────────────────────────────────────
printf "\n"
printf "${BOLD}${GREEN}"
cat << 'DONE'
  ╔═══════════════════════════════════════════════════╗
  ║            Installation complete!                  ║
  ╚═══════════════════════════════════════════════════╝
DONE
printf "${RESET}\n"

printf "${BOLD}Next steps:${RESET}\n"
printf "  ${CYAN}1.${RESET} cd %s\n" "$PAA_DIR"
printf "  ${CYAN}2.${RESET} just setup-repos <your_github_username>  ${DIM}# Clone Paddle repos${RESET}\n"
printf "  ${CYAN}3.${RESET} gh auth login                            ${DIM}# Authenticate GitHub CLI${RESET}\n"
printf "  ${CYAN}4.${RESET} just alignment-start <api_name>          ${DIM}# Start precision alignment${RESET}\n"
printf "\n"
printf "${DIM}For more info: https://github.com/zrr1999/precision-alignment-agent${RESET}\n"
printf "${DIM}Tip: Install global MCP for better performance: https://mcp.context7.com/install${RESET}\n"
printf "\n"
