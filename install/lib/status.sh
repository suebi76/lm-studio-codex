#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

initialize_lmstudio_codex_state
missing=()
while IFS= read -r found; do
  [ -n "$found" ] && missing+=("$found")
done < <(missing_dependency_names)

printf 'Install root: %s\n' "$INSTALL_ROOT"
printf 'Codex home:   %s\n' "$CODEX_HOME_DIR"

if [ "${#missing[@]}" -eq 0 ]; then
  printf 'Dependencies: OK\n'
else
  printf 'Dependencies: missing %s\n' "$(IFS=', '; printf '%s' "${missing[*]}")"
  for item in "${missing[@]}"; do
    printf '  - %s\n' "$(dependency_fix_message "$item")"
  done
fi

selected_id="$(get_selected_model_state_field id 2>/dev/null || true)"
if [ -n "$selected_id" ]; then
  printf 'Selected:     %s\n' "$selected_id"
else
  printf 'Selected:     none\n'
fi

gateway_port="$(get_gateway_health_field port 2>/dev/null || true)"
gateway_model="$(http_get 'http://127.0.0.1:18123/ready' 2>/dev/null || true)"
if [ -n "$gateway_port" ]; then
  printf 'Gateway:      running on port %s\n' "$gateway_port"
  printf 'Live readiness: %s\n' "${gateway_model:-LM Studio/model is not ready}"
else
  printf 'Gateway:      not running\n'
fi
