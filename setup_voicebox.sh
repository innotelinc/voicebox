#!/usr/bin/env bash
# =============================================================================
# Voicebox Ubuntu Setup Script
# https://github.com/innotelinc/voicebox
#
# Installs all prerequisites and sets up Voicebox for development on Ubuntu.
# Note: Pre-built Linux binaries are not yet released upstream (coming soon),
# so this script builds from source.
#
# Usage:
#   chmod +x setup_voicebox.sh
#   ./setup_voicebox.sh
#
# Optional flags:
#   --skip-rust     Skip Rust installation (if already installed)
#   --skip-bun      Skip Bun installation (if already installed)
#   --skip-python   Skip Python setup (if already installed)
#   --no-gpu        Skip CUDA check (CPU-only PyTorch)
# =============================================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_RUST=false
SKIP_BUN=false
SKIP_PYTHON=false
NO_GPU=false

for arg in "$@"; do
  case $arg in
    --skip-rust)   SKIP_RUST=true ;;
    --skip-bun)    SKIP_BUN=true ;;
    --skip-python) SKIP_PYTHON=true ;;
    --no-gpu)      NO_GPU=true ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ██╗   ██╗ ██████╗ ██╗ ██████╗███████╗██████╗  ██████╗ ██╗  ██╗"
echo "  ██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔══██╗██╔═══██╗╚██╗██╔╝"
echo "  ██║   ██║██║   ██║██║██║     █████╗  ██████╔╝██║   ██║ ╚███╔╝ "
echo "  ╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ██╔══██╗██║   ██║ ██╔██╗ "
echo "   ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗██████╔╝╚██████╔╝██╔╝ ██╗"
echo "    ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "  Ubuntu Setup Script for ${BLUE}https://github.com/jamiepine/voicebox${NC}"
echo ""

# ── Check Ubuntu ──────────────────────────────────────────────────────────────
step "Checking system"

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  warn "This script is designed for Ubuntu. Proceeding anyway..."
else
  UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
  info "Ubuntu $UBUNTU_VERSION detected"
fi

ARCH=$(uname -m)
info "Architecture: $ARCH"

if [[ "$ARCH" != "x86_64" ]]; then
  warn "Non-x86_64 architecture detected ($ARCH). Build may require adjustments."
fi

# ── System dependencies ───────────────────────────────────────────────────────
step "Installing system dependencies"

sudo apt-get update -qq

PKGS=(
  # Build essentials
  build-essential curl wget git pkg-config
  # Tauri / Rust / WebKit requirements
  libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev
  librsvg2-dev libssl-dev
  # Audio (for voice synthesis features)
  libsndfile1-dev libportaudio2 portaudio19-dev ffmpeg
  # Python build deps
  python3 python3-pip python3-venv python3-dev
  # Misc
  ca-certificates gnupg lsb-release software-properties-common
)

sudo apt-get install -y "${PKGS[@]}"
success "System dependencies installed"

# ── Python version check ──────────────────────────────────────────────────────
step "Checking Python version"

PYTHON_BIN=""
for bin in python3.12 python3.11 python3; do
  if command -v "$bin" &>/dev/null; then
    VER=$("$bin" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    MAJOR=${VER%%.*}
    MINOR=${VER##*.}
    if [[ "$MAJOR" -eq 3 && "$MINOR" -ge 11 ]]; then
      PYTHON_BIN="$bin"
      info "Using $bin (version $VER)"
      break
    fi
  fi
done

if [[ -z "$PYTHON_BIN" ]]; then
  warn "Python 3.11+ not found. Installing Python 3.12 via deadsnakes PPA..."
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
  sudo apt-get install -y python3.12 python3.12-venv python3.12-dev
  PYTHON_BIN="python3.12"
  success "Python 3.12 installed"
fi

# ── Rust ──────────────────────────────────────────────────────────────────────
if [[ "$SKIP_RUST" == false ]]; then
  step "Installing Rust (via rustup)"
  if command -v rustc &>/dev/null; then
    RUST_VER=$(rustc --version)
    info "Rust already installed: $RUST_VER"
    rustup update stable
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    success "Rust installed"
  fi
  # Make cargo available in this session
  export PATH="$HOME/.cargo/bin:$PATH"
  rustup target add x86_64-unknown-linux-gnu 2>/dev/null || true
else
  info "Skipping Rust installation (--skip-rust)"
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if ! command -v cargo &>/dev/null; then
  error "cargo not found. Please ensure Rust is installed and ~/.cargo/bin is in PATH."
fi
success "Rust/Cargo: $(cargo --version)"

# ── Bun ───────────────────────────────────────────────────────────────────────
if [[ "$SKIP_BUN" == false ]]; then
  step "Installing Bun (JS runtime)"
  if command -v bun &>/dev/null; then
    info "Bun already installed: $(bun --version)"
    bun upgrade 2>/dev/null || true
  else
    curl -fsSL https://bun.sh/install | bash
    success "Bun installed"
  fi
  export PATH="$HOME/.bun/bin:$PATH"
else
  info "Skipping Bun installation (--skip-bun)"
  export PATH="$HOME/.bun/bin:$PATH"
fi

if ! command -v bun &>/dev/null; then
  error "bun not found. Please ensure ~/.bun/bin is in PATH."
fi
success "Bun: $(bun --version)"

# ── Clone / update repo ───────────────────────────────────────────────────────
step "Cloning Voicebox repository"

INSTALL_DIR="$HOME/voicebox"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Repository already exists at $INSTALL_DIR — pulling latest changes"
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone https://github.com/innotelinc/voicebox.git "$INSTALL_DIR"
  success "Cloned to $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ── Node / JS dependencies ────────────────────────────────────────────────────
step "Installing JS dependencies (bun install)"
bun install
success "JS dependencies installed"

# ── Python virtual environment & backend deps ─────────────────────────────────
if [[ "$SKIP_PYTHON" == false ]]; then
  step "Setting up Python backend"

  VENV_DIR="$INSTALL_DIR/backend/.venv"

  if [[ ! -d "$VENV_DIR" ]]; then
    $PYTHON_BIN -m venv "$VENV_DIR"
    success "Created venv at $VENV_DIR"
  else
    info "Existing venv found at $VENV_DIR"
  fi

  # Activate venv
  source "$VENV_DIR/bin/activate"

  # Upgrade pip inside venv
  pip install --upgrade pip setuptools wheel -q

  # ── GPU / CUDA detection ───────────────────────────────────────────────────
  if [[ "$NO_GPU" == false ]]; then
    info "Checking for NVIDIA GPU / CUDA..."
    if command -v nvidia-smi &>/dev/null; then
      CUDA_VER=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9.]+" || echo "")
      if [[ -n "$CUDA_VER" ]]; then
        success "NVIDIA GPU found, CUDA $CUDA_VER"
        TORCH_EXTRA="--index-url https://download.pytorch.org/whl/cu121"
        info "Will install CUDA-enabled PyTorch (cu121). Edit this script if you need a different CUDA version."
      else
        warn "nvidia-smi found but couldn't detect CUDA version. Installing CPU PyTorch."
        TORCH_EXTRA=""
      fi
    else
      warn "No NVIDIA GPU detected. Installing CPU-only PyTorch (inference will be slow)."
      TORCH_EXTRA="--index-url https://download.pytorch.org/whl/cpu"
    fi
  else
    info "--no-gpu flag set, installing CPU-only PyTorch"
    TORCH_EXTRA="--index-url https://download.pytorch.org/whl/cpu"
  fi

  # Install PyTorch first (separate step so the index-url applies only to it)
  pip install torch torchaudio $TORCH_EXTRA -q
  success "PyTorch installed"

  # Install the rest of backend dependencies
  if [[ -f "$INSTALL_DIR/backend/requirements.txt" ]]; then
    pip install -r "$INSTALL_DIR/backend/requirements.txt" -q
    success "Backend Python dependencies installed"
  else
    warn "backend/requirements.txt not found — installing common packages"
    pip install fastapi uvicorn openai-whisper soundfile librosa numpy -q
  fi

  deactivate
else
  info "Skipping Python setup (--skip-python)"
fi

# ── Shell config update ───────────────────────────────────────────────────────
step "Updating shell configuration"

SHELL_RC="$HOME/.bashrc"
[[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"

EXPORT_BLOCK='
# >>> Voicebox additions >>>
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
# <<< Voicebox additions <<<'

if ! grep -q "Voicebox additions" "$SHELL_RC" 2>/dev/null; then
  echo "$EXPORT_BLOCK" >> "$SHELL_RC"
  info "Added PATH exports to $SHELL_RC"
else
  info "PATH exports already present in $SHELL_RC"
fi

# ── Convenience launcher script ───────────────────────────────────────────────
step "Creating launcher scripts"

LAUNCH_DEV="$INSTALL_DIR/start-dev.sh"
cat > "$LAUNCH_DEV" << 'EOF'
#!/usr/bin/env bash
# Start Voicebox in development mode
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"

echo "[voicebox] Activating Python venv..."
source backend/.venv/bin/activate

echo "[voicebox] Starting development server..."
bun run dev
EOF
chmod +x "$LAUNCH_DEV"

LAUNCH_BACKEND="$INSTALL_DIR/start-backend.sh"
cat > "$LAUNCH_BACKEND" << 'EOF'
#!/usr/bin/env bash
# Start only the Voicebox Python backend (FastAPI on port 8000)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/backend"

source .venv/bin/activate

echo "[voicebox] Starting FastAPI backend on http://localhost:8000 ..."
echo "[voicebox] API docs available at http://localhost:8000/docs"
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
EOF
chmod +x "$LAUNCH_BACKEND"

success "Launcher scripts created"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Setup complete! 🎉${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Location:${NC}  $INSTALL_DIR"
echo ""
echo -e "  ${BOLD}Start development (full app):${NC}"
echo -e "    cd $INSTALL_DIR && ./start-dev.sh"
echo ""
echo -e "  ${BOLD}Start backend only (API):${NC}"
echo -e "    cd $INSTALL_DIR && ./start-backend.sh"
echo -e "    API docs → http://localhost:8000/docs"
echo ""
echo -e "  ${BOLD}Or use the Makefile:${NC}"
echo -e "    cd $INSTALL_DIR && make help"
echo ""
echo -e "  ${BOLD}Note:${NC} Pre-built Linux binaries are not yet released upstream."
echo -e "  You're running from source. Reload your shell first:"
echo -e "    source $SHELL_RC"
echo ""
