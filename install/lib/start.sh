#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

main() {
  write_info "Starting LM Studio Codex CLI setup..."
  initialize_lmstudio_codex_state
  assert_dependencies || return 1
  ensure_lmstudio_server || return 1
  select_lmstudio_model || return 1
  ensure_gateway || return 1

  export CODEX_HOME="$CODEX_HOME_DIR"
  write_ok "Using LM Studio model: $SELECTED_MODEL_ID"
  write_info "Starting Codex in: $(pwd)"

  codex_args=()
  if [ "${LMSTUDIO_CODEX_USE_DAEMON:-}" = "1" ]; then
    write_warn "Codex daemon is enabled by LMSTUDIO_CODEX_USE_DAEMON=1. Portable installs in long paths may hit socket path limits."
  else
    codex_args+=(--no-daemon)
    write_info "Running Codex with --no-daemon to avoid socket path limits in portable installs."
  fi
  codex_args+=("$@")

  codex "${codex_args[@]}"
}

if ! main "$@"; then
  printf '\n[lm-studio] Startup failed.\n' >&2
  printf "[lm-studio] Run 'lm-studio-status' for diagnostics after fixing the issue.\n" >&2
  exit 1
fi
