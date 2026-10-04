#!/usr/bin/env bash

COMMON_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="$(CDPATH= cd -- "$COMMON_DIR/.." && pwd)"
STATE_DIR="$INSTALL_ROOT/state"
LOG_DIR="$INSTALL_ROOT/logs"
if [ -n "${LMSTUDIO_CODEX_HOME:-}" ]; then
  CODEX_HOME_DIR="$LMSTUDIO_CODEX_HOME"
elif [ "$(uname -s)" = "Darwin" ]; then
  CODEX_HOME_DIR="$HOME/.lmsc/c"
else
  CODEX_HOME_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lmsc/c"
fi
MODEL_STATE_FILE="$STATE_DIR/selected-model.json"
GATEWAY_URL="http://127.0.0.1:18123/health"
LMSTUDIO_BASE_URL="${LMSTUDIO_BASE_URL:-http://127.0.0.1:1234}"

write_info() {
  printf '[lm-studio] %s\n' "$1"
}

write_ok() {
  printf '[lm-studio] OK: %s\n' "$1"
}

write_warn() {
  printf '[lm-studio] WARNING: %s\n' "$1" >&2
}

stop_with_help() {
  local message="$1"
  shift || true

  printf '\n[lm-studio] ERROR: %s\n' "$message" >&2
  if [ "$#" -gt 0 ]; then
    printf '\nWhat to do:\n' >&2
    local line
    for line in "$@"; do
      printf '  - %s\n' "$line" >&2
    done
  fi
  return 1
}

initialize_lmstudio_codex_state() {
  mkdir -p "$STATE_DIR" "$LOG_DIR" "$CODEX_HOME_DIR"
  if [ ! -f "$CODEX_HOME_DIR/config.toml" ]; then
    cp "$INSTALL_ROOT/templates/config.toml" "$CODEX_HOME_DIR/config.toml"
  fi
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

http_get() {
  local url="$1"
  if command_available curl; then
    curl -fsS --max-time 2 "$url"
    return $?
  fi

  if command_available node; then
    node -e '
const http = require("http");
const https = require("https");
const url = process.argv[1];
const lib = url.startsWith("https:") ? https : http;
const req = lib.get(url, { timeout: 2000 }, res => {
  let body = "";
  res.setEncoding("utf8");
  res.on("data", chunk => body += chunk);
  res.on("end", () => {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      process.stdout.write(body);
      process.exit(0);
    }
    process.exit(1);
  });
});
req.on("timeout", () => req.destroy(new Error("timeout")));
req.on("error", () => process.exit(1));
' "$url"
    return $?
  fi

  return 1
}

test_http_ok() {
  http_get "$1" >/dev/null 2>&1
}

get_gateway_health_json() {
  http_get "$GATEWAY_URL" 2>/dev/null || true
}

get_gateway_health_field() {
  local field="$1"
  local json
  json="$(get_gateway_health_json)"
  if [ -z "$json" ] || ! command_available node; then
    return 1
  fi
  printf '%s' "$json" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const value = JSON.parse(input)[process.argv[1]];
    if (value === undefined || value === null) process.exit(1);
    process.stdout.write(String(value));
  } catch {
    process.exit(1);
  }
});
' "$field"
}

get_state_file_absolute_path() {
  local dir
  dir="$(CDPATH= cd -- "$(dirname -- "$MODEL_STATE_FILE")" && pwd)"
  printf '%s/%s' "$dir" "$(basename -- "$MODEL_STATE_FILE")"
}

stop_gateway_on_port() {
  local pid command_line
  while read -r pid command_line; do
    if [ "$command_line" = "node $INSTALL_ROOT/lib/lmstudio-responses-gateway.js" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < <(ps -axo pid=,args=)
  rm -f "$LOG_DIR/gateway.pid"

}

missing_dependency_names() {
  local missing=()
  command_available node || missing+=("Node.js")
  command_available codex || missing+=("Codex CLI")
  command_available lms || missing+=("LM Studio CLI")
  printf '%s\n' "${missing[@]}"
}

dependency_fix_message() {
  case "$1" in
    "Node.js")
      if [ "$(uname -s)" = "Darwin" ]; then
        printf 'Install Node.js LTS from https://nodejs.org or run: brew install node'
      else
        printf 'Install Node.js LTS from https://nodejs.org, or use your distro package manager, for example: sudo apt install nodejs npm'
      fi
      ;;
    "Codex CLI")
      printf 'Install Codex CLI after Node.js is installed: npm install -g @openai/codex'
      ;;
    "LM Studio CLI")
      printf 'Install LM Studio from https://lmstudio.ai, open it once, and enable/install the lms CLI. If available, try: npx lmstudio install-cli'
      ;;
  esac
}

assert_dependencies() {
  local missing=()
  local found
  while IFS= read -r found; do
    [ -n "$found" ] && missing+=("$found")
  done < <(missing_dependency_names)
  if [ "${#missing[@]}" -eq 0 ]; then
    node -e 'if(Number(process.versions.node.split(".")[0]) < 22) process.exit(1)' || {
      stop_with_help "Node.js 22 or newer is required." "Install Node.js LTS from https://nodejs.org"
      return 1
    }
    write_ok "Required commands found: node, codex, lms"
    return 0
  fi

  local fixes=()
  local item
  for item in "${missing[@]}"; do
    fixes+=("$item: $(dependency_fix_message "$item")")
  done

  local joined
  joined="$(IFS=', '; printf '%s' "${missing[*]}")"
  stop_with_help "Missing required dependency: $joined" "${fixes[@]}"
}

ensure_lmstudio_server() {
  if ! test_http_ok "$LMSTUDIO_BASE_URL/v1/models"; then
    write_info "LM Studio server is not responding on $LMSTUDIO_BASE_URL. Starting it with lms..."
    node "$COMMON_DIR/run-lms.js" server start || return 1

    local ready=0
    local i
    for i in $(seq 1 30); do
      sleep 0.5
      if test_http_ok "$LMSTUDIO_BASE_URL/v1/models"; then
        ready=1
        break
      fi
    done

    if [ "$ready" -ne 1 ]; then
      stop_with_help "LM Studio server did not become reachable at $LMSTUDIO_BASE_URL." \
        "Open LM Studio manually." \
        "Enable the local server in LM Studio." \
        "Confirm that http://127.0.0.1:1234/v1/models opens or returns JSON."
      return 1
    fi
  else
    write_ok "LM Studio server is reachable at $LMSTUDIO_BASE_URL"
  fi
}

get_loaded_lmstudio_models_tsv() {
  local loaded_json
  if ! loaded_json="$(node "$COMMON_DIR/run-lms.js" ps --json)"; then
    stop_with_help "Could not run 'lms ps --json'." \
      "Open LM Studio and make sure the lms CLI is enabled." \
      "Try running 'lms ps --json' manually in a new terminal."
    return 1
  fi

  if [ -z "$loaded_json" ]; then
    stop_with_help "Could not read loaded LM Studio models with 'lms ps --json'." \
      "Open LM Studio." \
      "Load at least one chat/instruct LLM." \
      "Run 'lms ps --json' manually to confirm the LM Studio CLI works."
    return 1
  fi

  printf '%s' "$loaded_json" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const models = Array.isArray(data) ? data : [];
    for (const model of models.filter(item => item && item.type === "llm")) {
      const fields = [
        model.identifier,
        model.displayName,
        model.modelKey,
        model.architecture,
        model.contextLength
      ].map(value => String(value ?? "").replace(/[\t\r\n]/g, " "));
      console.log(fields.join("\t"));
    }
  } catch {
    process.exit(64);
  }
});
'
  local parse_status=$?
  if [ "$parse_status" -ne 0 ]; then
    stop_with_help "LM Studio returned invalid JSON for 'lms ps --json'." \
      "Update LM Studio." \
      "Run 'lms ps --json' manually and check whether it prints valid JSON."
    return 1
  fi
}

get_selected_model_state_field() {
  local field="$1"
  if [ ! -f "$MODEL_STATE_FILE" ] || ! command_available node; then
    return 1
  fi
  node -e '
const fs = require("fs");
try {
  const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const value = state[process.argv[2]];
  if (value === undefined || value === null) process.exit(1);
  process.stdout.write(String(value));
} catch {
  process.exit(1);
}
' "$MODEL_STATE_FILE" "$field"
}

save_selected_model_from_tsv() {
  local line="$1"
  node -e '
const fs = require("fs");
const [id, displayName, modelKey, architecture] = process.argv[2].split("\t");
const state = {
  id,
  displayName,
  modelKey,
  architecture,
  selectedAt: new Date().toISOString()
};
fs.writeFileSync(process.argv[1], JSON.stringify(state, null, 2) + "\n");
' "$MODEL_STATE_FILE" "$line"
}

select_lmstudio_model() {
  local loaded_tsv
  loaded_tsv="$(get_loaded_lmstudio_models_tsv)" || return 1

  if [ -z "$loaded_tsv" ]; then
    stop_with_help "No LLM is loaded in LM Studio." \
      "Open LM Studio." \
      "Load a chat/instruct model." \
      "Run 'lm-studio' again."
    return 1
  fi

  local count
  count="$(printf '%s\n' "$loaded_tsv" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  if [ "$count" = "1" ]; then
    save_selected_model_from_tsv "$loaded_tsv"
    SELECTED_MODEL_ID="$(printf '%s' "$loaded_tsv" | awk -F '\t' '{print $1}')"
    SELECTED_MODEL_CONTEXT="$(printf '%s' "$loaded_tsv" | awk -F '\t' '{print $5}')"
    write_ok "Selected the only loaded model: $SELECTED_MODEL_ID"
    return 0
  fi

  stop_with_help "More than one LLM is loaded in LM Studio." \
    "Unload all but one model in LM Studio." \
    "Run 'lm-studio' again after only the intended model is loaded."
}

ensure_gateway() {
  local health_gateway health_state_file expected_state_file
  health_gateway="$(get_gateway_health_field gateway 2>/dev/null || true)"
  health_state_file="$(get_gateway_health_field stateFile 2>/dev/null || true)"
  expected_state_file="$(get_state_file_absolute_path)"

  if [ -n "$health_gateway" ] && { [ "$health_gateway" != "lm-studio-codex-gateway" ] || [ "$health_state_file" != "$expected_state_file" ]; }; then
    stop_with_help "Port 18123 belongs to another service or installation." "Stop it from its owning installation. No foreign process was stopped."
    return 1
  fi

  local revision health_revision health_base health_transport health_timeout
  revision="$(node -e 'const fs=require("fs"),c=require("crypto"); console.log(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$INSTALL_ROOT/lib/lmstudio-responses-gateway.js")"
  health_revision="$(get_gateway_health_field revision 2>/dev/null || true)"
  health_base="$(get_gateway_health_field baseUrl 2>/dev/null || true)"
  health_transport="$(get_gateway_health_field transport 2>/dev/null || true)"
  health_timeout="$(get_gateway_health_field timeoutMs 2>/dev/null || true)"
  if [ -n "$health_gateway" ] && { [ "$health_revision" != "$revision" ] || [ "$health_base" != "$LMSTUDIO_BASE_URL" ] || [ "$health_transport" != "${LMSTUDIO_CODEX_TRANSPORT:-chat}" ] || [ "$health_timeout" != "${LMSTUDIO_CODEX_TIMEOUT_MS:-600000}" ]; }; then
    write_info "Restarting this installation's gateway after a code/configuration change..."
    stop_gateway_on_port
    sleep 0.5
    health_gateway="$(get_gateway_health_field gateway 2>/dev/null || true)"
    if [ -n "$health_gateway" ]; then
      stop_with_help "The previous gateway did not stop." "Run lm-studio-stop, inspect its message, then retry."
      return 1
    fi
  fi

  if [ -n "$health_gateway" ]; then
    write_ok "Gateway is already running on port 18123"
    return 0
  fi

  # Recover an owned older gateway whose health check depends on a loaded model.
  stop_gateway_on_port

  local gateway_script="$INSTALL_ROOT/lib/lmstudio-responses-gateway.js"
  local stdout_log="$LOG_DIR/gateway.out.log"
  local stderr_log="$LOG_DIR/gateway.err.log"
  local pid_file="$LOG_DIR/gateway.pid"

  write_info "Starting local Codex <-> LM Studio gateway on http://127.0.0.1:18123..."
  LMSTUDIO_BASE_URL="$LMSTUDIO_BASE_URL" \
  LMSTUDIO_CODEX_GATEWAY_PORT=18123 \
  LMSTUDIO_CODEX_MODEL_STATE_FILE="$MODEL_STATE_FILE" \
    nohup node "$gateway_script" >"$stdout_log" 2>"$stderr_log" </dev/null &
  local gateway_pid=$!
  printf '%s\n' "$!" > "$pid_file"

  local ready=0
  local i
  for i in $(seq 1 30); do
    sleep 0.3
    if [ "$(get_gateway_health_field pid 2>/dev/null || true)" = "$gateway_pid" ] && [ "$(get_gateway_health_field revision 2>/dev/null || true)" = "$revision" ]; then
      ready=1
      break
    fi
  done

  if [ "$ready" -ne 1 ]; then
    local error_tail=""
    if [ -f "$stderr_log" ]; then
      error_tail="$(tail -n 20 "$stderr_log" 2>/dev/null || true)"
    fi
    stop_with_help "The local gateway did not start." \
      "Check the error log: $stderr_log" \
      "Make sure port 18123 is not blocked." \
      "Try 'lm-studio-stop' and then run 'lm-studio' again." \
      "Last gateway error: $error_tail"
    return 1
  fi

  write_ok "Gateway is running"
}
