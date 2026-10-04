#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
case "${1:-}" in
  --help|-h) printf 'Usage: lm-studio-doctor [--skip-codex-smoke]\n'; exit 0 ;;
  ''|--skip-codex-smoke) ;;
  *) stop_with_help "Unknown argument: $1" "Use lm-studio-doctor --help"; exit 1 ;;
esac
initialize_lmstudio_codex_state
assert_dependencies
ensure_lmstudio_server
select_lmstudio_model
ensure_gateway
export CODEX_HOME="$CODEX_HOME_DIR"
export LMSTUDIO_CODEX_CONTEXT="${SELECTED_MODEL_CONTEXT:-}"
exec node "$SCRIPT_DIR/doctor-runtime.js" "$@"
