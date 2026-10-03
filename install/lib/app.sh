#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

main() {
  initialize_lmstudio_codex_state
  assert_dependencies || return 1
  ensure_lmstudio_server || return 1
  select_lmstudio_model || return 1
  ensure_gateway || return 1

  export CODEX_HOME="$CODEX_HOME_DIR"
  write_ok "Gateway is ready for LM Studio model: $SELECTED_MODEL_ID"
  write_info "Opening ChatGPT/Codex desktop app. If it was already open, start a new local Codex session after this."
  codex app
}

if ! main "$@"; then
  printf '\n[lm-studio] Desktop app startup failed.\n' >&2
  exit 1
fi
