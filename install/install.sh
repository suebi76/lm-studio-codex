#!/usr/bin/env bash
set -uo pipefail

INSTALL_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_ROOT/bin-unix"
USER_BIN_DIR="${HOME}/.local/bin"

# shellcheck source=lib/common.sh
. "$INSTALL_ROOT/lib/common.sh"

install_missing=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-missing)
      install_missing=1
      shift
      ;;
    --help|-h)
      printf 'Usage: ./install/install.sh [--install-missing]\n'
      exit 0
      ;;
    *)
      stop_with_help "Unknown argument: $1" "Use './install/install.sh --install-missing' to try installing Node/Codex automatically."
      exit 1
      ;;
  esac
done

try_install_missing_dependency() {
  case "$1" in
    "Node.js")
      if [ "$(uname -s)" = "Darwin" ] && command_available brew; then
        write_info "Installing Node.js with Homebrew..."
        brew install node
      else
        write_warn "Install Node.js manually: $(dependency_fix_message "Node.js")"
      fi
      ;;
    "Codex CLI")
      if command_available npm; then
        write_info "Installing Codex CLI with npm..."
        npm install -g @openai/codex
      else
        write_warn "npm is not available. Install Node.js first, then run: npm install -g @openai/codex"
      fi
      ;;
    "LM Studio CLI")
      if command_available npx; then
        write_info "Trying to install the LM Studio CLI with npx..."
        npx lmstudio install-cli || write_warn "Could not install lms automatically. Enable/install the lms CLI from LM Studio."
      else
        write_warn "Install LM Studio manually from https://lmstudio.ai, open it once, and enable/install the lms CLI."
      fi
      ;;
  esac
}

ensure_path_line() {
  local profile_file="$1"
  local marker='export PATH="$HOME/.local/bin:$PATH"'

  if [ ! -f "$profile_file" ]; then
    touch "$profile_file"
  fi

  if ! grep -Fq "$marker" "$profile_file"; then
    {
      printf '\n# LM Studio Codex global commands\n'
      printf '%s\n' "$marker"
    } >> "$profile_file"
    write_ok "Added ~/.local/bin to PATH in $profile_file"
  else
    write_ok "~/.local/bin is already configured in $profile_file"
  fi
}

write_info "Installing LM Studio Codex CLI helpers..."
write_info "Install root: $INSTALL_ROOT"

initialize_lmstudio_codex_state
chmod +x "$INSTALL_ROOT/install.sh" "$BIN_DIR"/* "$INSTALL_ROOT/lib"/*.sh
mkdir -p "$USER_BIN_DIR"

missing_before=()
while IFS= read -r found; do
  [ -n "$found" ] && missing_before+=("$found")
done < <(missing_dependency_names)
if [ "${#missing_before[@]}" -gt 0 ]; then
  write_warn "Some dependencies are missing:"
  for item in "${missing_before[@]}"; do
    printf '  - %s: %s\n' "$item" "$(dependency_fix_message "$item")"
  done

  if [ "$install_missing" -eq 1 ]; then
    for item in "${missing_before[@]}"; do
      try_install_missing_dependency "$item"
    done
  else
    write_info "Installer will still create commands. Run './install/install.sh --install-missing' to try installing Node/Codex automatically."
  fi
else
  write_ok "All required commands are already available"
fi

commands=(lm-studio lm-studio-doctor lm-studio-model lm-studio-status lm-studio-stop lm-studio-app)
for command_name in "${commands[@]}"; do
  target="$BIN_DIR/$command_name"
  link="$USER_BIN_DIR/$command_name"
  rm -f "$link"
  ln -s "$target" "$link"
done

write_ok "Installed global commands in $USER_BIN_DIR:"
for command_name in "${commands[@]}"; do
  printf '  %s\n' "$command_name"
done

case ":$PATH:" in
  *":$USER_BIN_DIR:"*) write_ok "$USER_BIN_DIR is already active in this terminal PATH" ;;
  *) write_warn "$USER_BIN_DIR is not active in this terminal PATH yet" ;;
esac

if [ -n "${SHELL:-}" ] && [ "$(basename -- "$SHELL")" = "zsh" ]; then
  ensure_path_line "$HOME/.zshrc"
else
  ensure_path_line "$HOME/.bashrc"
  if [ "$(uname -s)" = "Darwin" ]; then
    ensure_path_line "$HOME/.zshrc"
  fi
fi

missing_after=()
while IFS= read -r found; do
  [ -n "$found" ] && missing_after+=("$found")
done < <(missing_dependency_names)
if [ "${#missing_after[@]}" -gt 0 ]; then
  printf '\n' >&2
  write_warn "Installation finished, but these dependencies still need attention:"
  for item in "${missing_after[@]}"; do
    printf '  - %s: %s\n' "$item" "$(dependency_fix_message "$item")"
  done
else
  write_ok "Preflight passed. You can open a new VS Code terminal and run: lm-studio"
fi

write_info "Open a new VS Code terminal if an existing terminal does not see the updated PATH."
