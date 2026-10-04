#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
case "${1:-}" in
  --help|-h|help) exec node "$SCRIPT_DIR/run-codex.js" --help ;;
esac
write_info "Starting LM Studio Codex CLI setup..."
initialize_lmstudio_codex_state
assert_dependencies
ensure_lmstudio_server
select_lmstudio_model
ensure_gateway
export CODEX_HOME="$CODEX_HOME_DIR"
export LMSTUDIO_CODEX_CONTEXT="${SELECTED_MODEL_CONTEXT:-}"
write_ok "Using LM Studio model: $SELECTED_MODEL_ID"
write_info "Working directory: $(pwd)"
exec node "$SCRIPT_DIR/run-codex.js" "$@"
