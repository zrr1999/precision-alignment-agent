#!/usr/bin/env bash
# Paddle Pilot - One-click installer
# Usage: curl -fsSL https://raw.githubusercontent.com/zrr1999/paddle-pilot/main/install.sh | bash
#
# Options (via environment variables):
#   PADDLE_PILOT_DIR       - Installation directory (default: ./paddle-pilot)
#   PADDLE_PILOT_BRANCH    - Git branch to clone (default: main)

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
PADDLE_PILOT_DIR="${PADDLE_PILOT_DIR:-paddle-pilot}"
PADDLE_PILOT_BRANCH="${PADDLE_PILOT_BRANCH:-main}"
PADDLE_PILOT_REPO="https://github.com/zrr1999/paddle-pilot.git"

# ─── Banner ──────────────────────────────────────────────────────────────────
printf "${BOLD}${CYAN}"
cat << 'BANNER'

  ╔═══════════════════════════════════════════════════╗
  ║         Paddle Pilot Installer                     ║
  ║    Auto-align Paddle ↔ PyTorch API precision       ║
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

# ─── Install just ────────────────────────────────────────────────────────────
step "Installing just"

if has just; then
    success "just already installed: $(just --version)"
else
    info "Installing just via official script..."
    $FETCH https://just.systems/install.sh | bash -s -- --to /usr/local/bin 2>/dev/null || \
    $FETCH https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin"
    [ -f "$HOME/.local/bin/just" ] && ! has just && export PATH="$HOME/.local/bin:$PATH"
    if has just; then
        success "just installed: $(just --version)"
    else
        error "Failed to install just. Please install it manually: https://just.systems"
        exit 1
    fi
fi

# ─── Clone the project ──────────────────────────────────────────────────────
step "Cloning paddle-pilot"

if [ -d "$PADDLE_PILOT_DIR/.git" ]; then
    info "Directory $PADDLE_PILOT_DIR already exists, pulling latest changes..."
    cd "$PADDLE_PILOT_DIR"
    git pull origin "$PADDLE_PILOT_BRANCH" || warn "Failed to pull, continuing with existing code"
else
    info "Cloning from $PADDLE_PILOT_REPO (branch: $PADDLE_PILOT_BRANCH)..."
    git clone --branch "$PADDLE_PILOT_BRANCH" "$PADDLE_PILOT_REPO" "$PADDLE_PILOT_DIR"
    cd "$PADDLE_PILOT_DIR"
fi
success "Project cloned to $(pwd)"

# ─── Setup environment via just ──────────────────────────────────────────────
step "Setting up environment"

read -rp "Run 'just setup' to install all dependencies? [Y/n] " ans
if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
    just setup
else
    warn "Skipped. Run 'just setup' manually later."
fi

read -rp "Run 'just setup-repos' to clone Paddle repos? [Y/n] " ans
if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
    just setup-repos
else
    warn "Skipped. Run 'just setup-repos' manually later."
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
printf "  ${CYAN}1.${RESET} cd %s\n" "$PADDLE_PILOT_DIR"
printf "  ${CYAN}2.${RESET} gh auth login                             ${DIM}# Authenticate GitHub CLI${RESET}\n"
printf "  ${CYAN}3.${RESET} just alignment-start <api_name>           ${DIM}# Start precision alignment${RESET}\n"
printf "\n"
printf "${DIM}For more info: https://github.com/zrr1999/paddle-pilot${RESET}\n"
printf "\n"
