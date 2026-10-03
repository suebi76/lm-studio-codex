#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

skip_codex_smoke=0
doctor_warned=0
doctor_failed=0
doctor_timeout_sec="${LMSTUDIO_DOCTOR_TIMEOUT_SEC:-45}"
case "$doctor_timeout_sec" in
  ''|*[!0-9]*) doctor_timeout_sec=45 ;;
esac
doctor_timeout_ms=$((doctor_timeout_sec * 1000))

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-codex-smoke)
      skip_codex_smoke=1
      shift
      ;;
    --help|-h)
      printf 'Usage: lm-studio-doctor [--skip-codex-smoke]\n'
      exit 0
      ;;
    *)
      stop_with_help "Unknown argument: $1" "Use 'lm-studio-doctor --skip-codex-smoke' to skip the Codex CLI smoke test."
      exit 1
      ;;
  esac
done

doctor_pass() {
  printf '[lm-studio] OK: %s\n' "$1"
}

doctor_warn() {
  doctor_warned=1
  printf '[lm-studio] WARNING: %s\n' "$1" >&2
}

doctor_fail() {
  doctor_failed=1
  printf '[lm-studio] FAIL: %s\n' "$1" >&2
}

model_recommendation() {
  local model_id="$1"
  local lower
  lower="$(printf '%s' "$model_id" | tr '[:upper:]' '[:lower:]')"

  printf '\nModel recommendation:\n'
  if [[ "$lower" == *qwen* && "$lower" == *coder* ]]; then
    doctor_pass "Recommended for local coding agents. Qwen Coder models are usually strong at code and tool-style workflows."
  elif [[ "$lower" == *qwen* ]]; then
    doctor_pass "Good candidate. For heavier agent work, prefer a Qwen Coder or large Qwen instruct model if it fits your hardware."
  elif [[ "$lower" == *deepseek* && ( "$lower" == *coder* || "$lower" == *v3* || "$lower" == *v4* ) ]]; then
    doctor_pass "Recommended if your hardware can run it comfortably. DeepSeek coding/V3-style models are strong for larger code tasks."
  elif [[ "$lower" == *kimi* || "$lower" == *moonshot* ]]; then
    doctor_pass "Good candidate for agentic workflows, especially Kimi K2/K-code style models with tool-use support."
  elif [[ "$lower" == *devstral* || "$lower" == *codestral* ]]; then
    doctor_pass "Good coding-agent candidate. Devstral is the better fit for multi-step agent work; Codestral is stronger for coding completion/editing."
  elif [[ "$lower" == *gemma* ]]; then
    doctor_warn "Gemma can work for smaller coding tasks, but watch the JSON/tool-call checks. For autonomous repo edits, a coder/agent model is usually safer."
  elif [[ "$lower" == *llama* || "$lower" == *mistral* || "$lower" == *phi* || "$lower" == *granite* || "$lower" == *starcoder* ]]; then
    doctor_warn "Usable depending on size and quantization. Prefer an instruct/coder variant and trust the Doctor checks over the model family name."
  else
    doctor_warn "Unknown model family. If text, JSON, and tool-call checks pass, try it on small repo tasks first."
  fi
}

run_gateway_runtime_checks() {
  LMSTUDIO_DOCTOR_TIMEOUT_MS="$doctor_timeout_ms" node <<'NODE'
const http = require("http");

let warned = false;
let failed = false;
const timeoutMs = Number(process.env.LMSTUDIO_DOCTOR_TIMEOUT_MS || 45000);

function pass(message) {
  console.log(`[lm-studio] OK: ${message}`);
}

function warn(message) {
  warned = true;
  console.error(`[lm-studio] WARNING: ${message}`);
}

function fail(message) {
  failed = true;
  console.error(`[lm-studio] FAIL: ${message}`);
}

function requestJson(path, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const req = http.request({
      hostname: "127.0.0.1",
      port: 18123,
      path,
      method: "POST",
      timeout: timeoutMs,
      headers: {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(payload),
      },
    }, res => {
      let data = "";
      res.setEncoding("utf8");
      res.on("data", chunk => data += chunk);
      res.on("end", () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          return;
        }
        try {
          resolve(JSON.parse(data));
        } catch (error) {
          reject(error);
        }
      });
    });
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
    req.end(payload);
  });
}

function outputText(response) {
  const parts = [];
  for (const item of response.output || []) {
    if (item.type !== "message") continue;
    for (const content of item.content || []) {
      if (content.type === "output_text" && content.text) parts.push(content.text);
    }
  }
  return parts.join("\n");
}

async function gatewayResponse(input, extra = {}) {
  return requestJson("/v1/responses", {
    model: "lmstudio-loaded",
    input,
    stream: false,
    temperature: 0,
    max_output_tokens: 128,
    ...extra,
  });
}

(async () => {
  try {
    const textResponse = await gatewayResponse("Reply exactly: LM_STUDIO_GATEWAY_OK", { max_output_tokens: 512 });
    const text = outputText(textResponse);
    if (text.includes("LM_STUDIO_GATEWAY_OK")) {
      pass("Gateway text response works");
    } else {
      warn(`Gateway responded, but the model did not follow an exact short instruction. Output: ${text}`);
    }
  } catch (error) {
    fail(`Gateway text response failed: ${error.message}`);
    console.error("[lm-studio] WARNING: Skipping JSON and tool-call checks because the model did not answer the basic gateway test.");
    process.exit(2);
  }

  try {
    const jsonResponse = await gatewayResponse('Return only this compact JSON object and no markdown: {"ok":true,"kind":"doctor"}', { max_output_tokens: 512 });
    const text = outputText(jsonResponse);
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) {
      warn(`Model did not return parseable JSON. Output: ${text}`);
    } else {
      const parsed = JSON.parse(match[0]);
      if (parsed.ok === true && parsed.kind === "doctor") {
        pass("Model can produce simple JSON");
      } else {
        warn(`Model returned JSON, but not the requested object. Output: ${text}`);
      }
    }
  } catch (error) {
    warn(`JSON check failed: ${error.message}`);
  }

  try {
    const toolResponse = await gatewayResponse(
      "Call the doctor_ping tool exactly once with ok=true. Do not answer in normal text.",
      {
        tools: [{
          type: "function",
          name: "doctor_ping",
          description: "Use this to confirm that tool calling works.",
          parameters: {
            type: "object",
            properties: { ok: { type: "boolean" } },
            required: ["ok"],
            additionalProperties: false,
          },
        }],
      }
    );
    const toolCalls = (toolResponse.output || []).filter(item => item.type === "function_call");
    if (toolCalls.length === 0) {
      warn(`No tool call was produced. This model may be weak for Coding-Agent workflows. Output: ${outputText(toolResponse)}`);
    } else if (toolCalls[0].name !== "doctor_ping") {
      warn(`Model produced a tool call, but with the wrong function name: ${toolCalls[0].name}`);
    } else {
      const args = JSON.parse(toolCalls[0].arguments || "{}");
      if (args.ok === true) {
        pass("Model can produce a simple tool call");
      } else {
        warn(`Model produced a tool call, but with unexpected arguments: ${toolCalls[0].arguments}`);
      }
    }
  } catch (error) {
    warn(`Tool-call check failed: ${error.message}`);
  }

  if (failed) process.exit(2);
  if (warned) process.exit(1);
})();
NODE
}

run_codex_smoke() {
  if [ "$skip_codex_smoke" -eq 1 ]; then
    doctor_warn "Codex smoke test skipped by user"
    return
  fi

  local stdout_log="$LOG_DIR/doctor-codex.out.log"
  local stderr_log="$LOG_DIR/doctor-codex.err.log"
  rm -f "$stdout_log" "$stderr_log"

  write_info "Running Codex CLI smoke test..."
  codex_args=(--no-daemon exec --skip-git-repo-check "Reply exactly: LM_STUDIO_CODEX_DOCTOR_OK")
  if [ "${LMSTUDIO_CODEX_USE_DAEMON:-}" = "1" ]; then
    codex_args=(exec --skip-git-repo-check "Reply exactly: LM_STUDIO_CODEX_DOCTOR_OK")
  fi
  CODEX_HOME="$CODEX_HOME_DIR" codex "${codex_args[@]}" >"$stdout_log" 2>"$stderr_log" &
  local pid=$!
  local waited=0
  local status=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    if [ "$waited" -ge 120 ]; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$pid" >/dev/null 2>&1 || true
      status=124
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if [ "$status" -ne 124 ]; then
    wait "$pid"
    status=$?
  fi

  if [ "$status" -eq 0 ] && grep -q "LM_STUDIO_CODEX_DOCTOR_OK" "$stdout_log"; then
    doctor_pass "Codex CLI can complete a simple request through LM Studio"
  elif [ "$status" -eq 0 ]; then
    doctor_warn "Codex CLI completed, but the model did not return the exact marker. See $stdout_log"
  elif [ "$status" -eq 124 ]; then
    doctor_fail "Codex CLI smoke test timed out after 120 seconds. See $stderr_log"
  else
    doctor_fail "Codex CLI smoke test failed with exit code $status. See $stderr_log"
  fi
}

main() {
  write_info "Running LM Studio Codex doctor..."
  initialize_lmstudio_codex_state
  assert_dependencies || return 1
  ensure_lmstudio_server || return 1
  select_lmstudio_model || return 1
  ensure_gateway || return 1

  doctor_pass "Preflight checks passed"
  doctor_pass "Loaded model: $SELECTED_MODEL_ID"
  model_recommendation "$SELECTED_MODEL_ID"

  printf '\nRuntime checks:\n'
  run_gateway_runtime_checks
  local gateway_status=$?
  if [ "$gateway_status" -eq 2 ]; then
    doctor_failed=1
  elif [ "$gateway_status" -eq 1 ]; then
    doctor_warned=1
  fi

  if [ "$doctor_failed" -eq 1 ]; then
    write_warn "Skipping Codex smoke check because the gateway runtime check failed."
  else
    run_codex_smoke
  fi

  printf '\n'
  if [ "$doctor_failed" -eq 1 ]; then
    doctor_fail "Doctor finished with failures. Fix the failed checks before using this model for agent work."
    return 1
  fi
  if [ "$doctor_warned" -eq 1 ]; then
    write_warn "Doctor finished with warnings. The setup can run, but this model may be unreliable for longer coding-agent sessions."
    return 0
  fi
  doctor_pass "Doctor finished cleanly. This model/setup looks ready for Coding-Agent workflows."
}

main
exit $?
