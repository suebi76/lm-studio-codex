#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

show_usage() {
  printf 'Usage: lm-studio-model [--list|-l]\n'
}

list_models=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list|-l|-List)
      list_models=1
      shift
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      stop_with_help "Unknown argument: $1" "Use 'lm-studio-model --list' to list the loaded model."
      exit 1
      ;;
  esac
done

main() {
  initialize_lmstudio_codex_state
  assert_dependencies || return 1
  ensure_lmstudio_server || return 1

  if [ "$list_models" -eq 1 ]; then
    local loaded_tsv current_id
    loaded_tsv="$(get_loaded_lmstudio_models_tsv)" || return 1
    if [ -z "$loaded_tsv" ]; then
      stop_with_help "No LLM is loaded in LM Studio." \
        "Open LM Studio." \
        "Load a chat/instruct model." \
        "Run 'lm-studio-model --list' again."
      return 1
    fi
    current_id="$(get_selected_model_state_field id 2>/dev/null || true)"
    while IFS=$'\t' read -r identifier display_name _model_key _architecture; do
      [ -n "$identifier" ] || continue
      if [ "$identifier" = "$current_id" ]; then
        printf '* %s - %s\n' "$identifier" "$display_name"
      else
        printf '  %s - %s\n' "$identifier" "$display_name"
      fi
    done <<EOF_MODELS
$loaded_tsv
EOF_MODELS
    return 0
  fi

  select_lmstudio_model || return 1
  write_ok "Current LM Studio model for Codex: $SELECTED_MODEL_ID"
}

if ! main; then
  printf '\n[lm-studio] Model selection failed.\n' >&2
  exit 1
fi
