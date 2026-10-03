#!/usr/bin/env bash
set -uo pipefail

INSTALL_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_BIN_DIR="${HOME}/.local/bin"

# shellcheck source=lib/common.sh
. "$INSTALL_ROOT/lib/common.sh"

commands=(lm-studio lm-studio-model lm-studio-status lm-studio-stop lm-studio-app)

initialize_lmstudio_codex_state
stop_gateway_on_port

for command_name in "${commands[@]}"; do
  link="$USER_BIN_DIR/$command_name"
  if [ -L "$link" ]; then
    target="$(readlink "$link" 2>/dev/null || true)"
    case "$target" in
      "$INSTALL_ROOT"/bin-unix/*) rm -f "$link" ;;
    esac
  fi
done

write_ok "Removed LM Studio Codex global commands from $USER_BIN_DIR."
write_info "Shell profile PATH entries are left in place because ~/.local/bin may be used by other tools."
