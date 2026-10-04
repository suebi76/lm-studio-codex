const fs = require("node:fs");
const http = require("node:http");
const https = require("node:https");
const { once } = require("node:events");
const { createHash } = require("node:crypto");

const PORT = Number(process.env.LMSTUDIO_CODEX_GATEWAY_PORT || 18123);
const LMSTUDIO_BASE_URL = process.env.LMSTUDIO_BASE_URL || "http://127.0.0.1:1234";
const MODEL_STATE_FILE = process.env.LMSTUDIO_CODEX_MODEL_STATE_FILE || "";
const GATEWAY_ID = "lm-studio-codex-gateway";
const REVISION = createHash("sha256").update(fs.readFileSync(__filename)).digest("hex");
const TRANSPORT = process.env.LMSTUDIO_CODEX_TRANSPORT || "chat";
const REQUEST_TIMEOUT_MS = Number(process.env.LMSTUDIO_CODEX_TIMEOUT_MS || 600000);
if (!["chat", "responses"].includes(TRANSPORT) || !Number.isFinite(REQUEST_TIMEOUT_MS) || REQUEST_TIMEOUT_MS < 100) {
  throw new Error("Invalid transport (use chat or responses) or LMSTUDIO_CODEX_TIMEOUT_MS (minimum 100).");
}
const MAX_BODY_BYTES = 16 * 1024 * 1024;

function clientError(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function sseHeaders(res) {
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache, no-transform",
    connection: "keep-alive",
    "x-accel-buffering": "no",
  });
}

function sse(res, event, data) {
  data.sequence_number = res.sequenceNumber || 0;
  res.sequenceNumber = data.sequence_number + 1;
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function id(prefix) {
  return `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
}

function textFromContent(content) {
  if (content == null) return "";
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) {
    if (typeof content.text === "string") return content.text;
    if (typeof content.output_text === "string") return content.output_text;
    if (typeof content.input_text === "string") return content.input_text;
    return "";
  }

  return content
    .map((part) => {
      if (typeof part === "string") return part;
      if (!part || typeof part !== "object") return "";
      if (typeof part.text === "string") return part.text;
      if (typeof part.output_text === "string") return part.output_text;
      if (typeof part.input_text === "string") return part.input_text;
      if (part.type === "input_image") throw clientError("Images require LMSTUDIO_CODEX_TRANSPORT=responses and a vision model.");
      throw clientError(`Unsupported content type: ${part.type}`);
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function normalizeInput(input) {
  if (input == null) return [];
  if (typeof input === "string") {
    return [{ type: "message", role: "user", content: input }];
  }
  return Array.isArray(input) ? input : [input];
}

function convertResponsesInputToChat(body) {
  const messages = [];
  const systemParts = [];

  if (body.instructions) systemParts.push(String(body.instructions));

  for (const item of normalizeInput(body.input)) {
    if (!item || typeof item !== "object") continue;

    if (item.type === "message" || item.role) {
      const role = item.role || "user";
      const text = textFromContent(item.content);
      if (!text) continue;

      if (role === "system" || role === "developer") {
        systemParts.push(text);
      } else if (role === "assistant") {
        messages.push({ role: "assistant", content: text });
      } else {
        messages.push({ role: "user", content: text });
      }
      continue;
    }

    if (item.type === "function_call_output") {
      messages.push({
        role: "tool",
        tool_call_id: item.call_id,
        content: typeof item.output === "string" ? item.output : JSON.stringify(item.output ?? ""),
      });
      continue;
    }

    if (item.type === "function_call") {
      const previous = messages[messages.length - 1];
      const call = {
        id: item.call_id || item.id || id("call"),
        type: "function",
        function: { name: chatToolName(item.name, item.namespace), arguments: item.arguments || "{}" },
      };
      if (previous?.role === "assistant" && previous.tool_calls) {
        previous.tool_calls.push(call);
      } else messages.push({
        role: "assistant",
        content: null,
        tool_calls: [call],
      });
      continue;
    }
    if (item.type !== "reasoning") throw clientError(`Unsupported input type: ${item.type}. Try the responses transport.`);
  }

  if (systemParts.length > 0) {
    messages.unshift({
      role: "system",
      content: systemParts.join("\n\n"),
    });
  }

  return messages;
}

function chatToolName(name, namespace) {
  if (!namespace) return name;
  const hash = createHash("sha256").update(JSON.stringify([namespace, name])).digest("hex").slice(0, 16);
  return `ns_${hash}_${name.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 44)}`;
}

function convertTools(tools, toolNames = new Map()) {
  if (!Array.isArray(tools)) return undefined;
  const converted = [];
  function add(tool, namespace) {
    if (tool?.type !== "function" || typeof tool.name !== "string" || !tool.name) {
      throw clientError(`Unsupported tool: ${tool?.type}:${tool?.name}. Use LMSTUDIO_CODEX_TRANSPORT=responses for custom tools.`);
    }
    const name = chatToolName(tool.name, namespace);
    if (toolNames.has(name)) throw clientError(`Duplicate tool name: ${name}`);
    toolNames.set(name, namespace ? { name: tool.name, namespace } : { name: tool.name });
    converted.push({ type: "function", function: {
      name, description: tool.description || "",
      parameters: tool.parameters || { type: "object", properties: {} },
    } });
  }
  for (const tool of tools) {
    if (tool?.type === "namespace" && typeof tool.name === "string" && tool.name && Array.isArray(tool.tools)) {
      for (const member of tool.tools) add(member, tool.name);
    } else add(tool);
  }
  return converted.length ? converted : undefined;
}

async function readRequestBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) { req.resume(); throw clientError("Request exceeds 16 MiB.", 413); }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
    return body;
  } catch { throw clientError("Expected a JSON object."); }
}

async function loadedModel(details = false) {
  const response = await fetch(`${LMSTUDIO_BASE_URL}/api/v1/models`, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) {
    throw new Error(`LM Studio model list failed with HTTP ${response.status}`);
  }
  const data = await response.json();
  const loaded = [];

  for (const model of data.models || []) {
    if (model.type !== "llm") continue;
    for (const instance of model.loaded_instances || []) {
      loaded.push({ id: instance.id || model.key, contextLength: instance.config?.context_length });
    }
  }

  if (loaded.length === 0) {
    throw new Error("No LLM is currently loaded in LM Studio.");
  }

  if (loaded.length > 1) {
    throw new Error(
      `Multiple LLMs are loaded in LM Studio (${loaded.map(model => model.id).join(", ")}). Unload all but one model, then run lm-studio again.`
    );
  }

  return details ? loaded[0] : loaded[0].id;
}

async function modelList() {
  const model = await loadedModel();
  return {
    object: "list",
    data: [
      {
        id: "lmstudio-loaded",
        object: "model",
        owned_by: "lmstudio",
      },
      {
        id: model,
        object: "model",
        owned_by: "lmstudio",
      },
    ],
  };
}

// Native HTTP avoids fetch's independent five-minute body/header idle limits.
// The caller's AbortSignal owns the complete generation budget and cancellation.
async function generationRequest(url, options) {
  const address = new URL(url);
  const transport = address.protocol === "https:" ? https : http;
  const incoming = await new Promise((resolve, reject) => {
    const request = transport.request(address, {
      method: options.method, headers: options.headers, signal: options.signal,
    }, resolve);
    request.on("error", reject);
    request.end(options.body);
  });
  async function text() {
    const chunks = [];
    let size = 0;
    for await (const chunk of incoming) {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) { incoming.destroy(); throw new Error("LM Studio response exceeds 16 MiB."); }
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString("utf8");
  }
  return { ok: incoming.statusCode >= 200 && incoming.statusCode < 300,
    status: incoming.statusCode, body: incoming, text, json: async () => JSON.parse(await text()) };
}

async function handleResponses(req, res) {
  const body = await readRequestBody(req);
  const model = await loadedModel();
  if (body.model && body.model !== "lmstudio-loaded" && body.model !== model) {
    throw clientError(`Requested model is no longer loaded. Current model: ${model}. Use lmstudio-loaded.`);
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(new Error("LM Studio request timed out.")), REQUEST_TIMEOUT_MS);
  const abort = () => { if (!res.writableEnded) controller.abort(new Error("Client disconnected.")); };
  res.on("close", abort);
  const started = Date.now();
  console.log(JSON.stringify({ event: "request.started", model, transport: TRANSPORT }));
  try {
    if (TRANSPORT === "responses") {
      return await forwardResponses(body, model, res, controller.signal);
    }
    if (body.previous_response_id) throw clientError("Chat transport requires full input history, not previous_response_id.");
  const responseId = id("resp");
  res.responseId = responseId;
  const created = Math.floor(Date.now() / 1000);
  const output = [];
  const stream = body.stream !== false;
  const toolNames = new Map();
  const tools = convertTools(body.tools, toolNames);
  const messages = convertResponsesInputToChat(body);

  const chatBody = {
    model,
    messages,
    stream: true,
    stream_options: { include_usage: true },
  };

  if (tools) {
    chatBody.tools = tools;
    chatBody.tool_choice = typeof body.tool_choice === "object"
      ? { type: "function", function: { name: chatToolName(body.tool_choice.name, body.tool_choice.namespace) } }
      : body.tool_choice || "auto";
    if (typeof body.parallel_tool_calls === "boolean") chatBody.parallel_tool_calls = body.parallel_tool_calls;
  }
  if (body.text?.format && body.text.format.type !== "text") {
    const format = body.text.format;
    chatBody.response_format = format.type === "json_schema"
      ? { type: "json_schema", json_schema: { name: format.name, schema: format.schema, strict: format.strict } }
      : format;
  }

  if (typeof body.temperature === "number") chatBody.temperature = body.temperature;
  if (typeof body.max_output_tokens === "number") chatBody.max_tokens = body.max_output_tokens;

  const upstream = await generationRequest(`${LMSTUDIO_BASE_URL}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(chatBody),
    signal: controller.signal,
  });

  if (!upstream.ok || !upstream.body) {
    const detail = await upstream.text().catch(() => "");
    throw clientError(`LM Studio chat completion failed with HTTP ${upstream.status}: ${detail}`, upstream.status >= 400 ? upstream.status : 502);
  }

  if (!stream) {
    const completion = await collectChatStream(upstream, toolNames);
    return json(res, 200, completeResponse(responseId, created, model, completion.output, completion.usage));
  }

  sseHeaders(res);
  sse(res, "response.created", {
    type: "response.created",
    response: {
      id: responseId,
      object: "response",
      created_at: created,
      status: "in_progress",
      model,
      output: [],
    },
  });

  const state = {
    responseId,
    created,
    model,
    output,
    message: null,
    text: "",
    toolCalls: new Map(),
    toolNames,
  };

  await streamChatAsResponses(upstream, res, state, controller.signal);

  sse(res, "response.completed", {
    type: "response.completed",
    response: completeResponse(responseId, created, model, output, state.usage),
  });
  res.end();
  } finally {
    clearTimeout(timeout);
    res.off("close", abort);
    controller.abort();
    console.log(JSON.stringify({ event: "request.finished", model, durationMs: Date.now() - started }));
  }
}

async function forwardResponses(body, model, res, signal) {
  const upstream = await generationRequest(`${LMSTUDIO_BASE_URL}/v1/responses`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ ...body, model, stream: body.stream !== false }), signal,
  });
  if (!upstream.ok) throw clientError(`LM Studio Responses HTTP ${upstream.status}: ${await upstream.text()}`, upstream.status);
  if (body.stream === false) {
    const result = await upstream.json();
    if (!["completed", "incomplete"].includes(result.status)) throw new Error(`LM Studio returned status ${result.status}`);
    return json(res, 200, result);
  }
  sseHeaders(res);
  let terminal = false;
  for await (const event of parseSse(upstream.body, false)) {
    if (!event.type) throw new Error("Responses stream event is missing type.");
    sse(res, event.type, event);
    if (["response.completed", "response.failed", "response.incomplete"].includes(event.type)) terminal = true;
    if (res.writableNeedDrain) await once(res, "drain", { signal });
  }
  if (!terminal) throw new Error("LM Studio stream ended before a terminal Responses event.");
  res.end();
}

function completeResponse(responseId, created, model, output, usage) {
  return {
    id: responseId,
    object: "response",
    created_at: created,
    status: "completed",
    model,
    output,
    usage: usage || null,
  };
}

async function collectChatStream(upstream, toolNames) {
  const output = [];
  const state = { output, message: null, text: "", toolCalls: new Map(), toolNames };
  for await (const chunk of parseSse(upstream.body)) {
    applyChatChunk(chunk, null, state);
  }
  finalizeState(null, state);
  return { output, usage: state.usage };
}

async function streamChatAsResponses(upstream, res, state, signal) {
  for await (const chunk of parseSse(upstream.body)) {
    applyChatChunk(chunk, res, state);
    if (res.writableNeedDrain) await once(res, "drain", { signal });
  }
  finalizeState(res, state);
}

async function* parseSse(stream, requireDone = true) {
  const decoder = new TextDecoder();
  let buffer = "";

  for await (const chunk of stream) {
    buffer += decoder.decode(chunk, { stream: true });
    let boundary;
    while ((boundary = /\r?\n\r?\n/.exec(buffer))) {
      const frame = buffer.slice(0, boundary.index);
      buffer = buffer.slice(boundary.index + boundary[0].length);
      const dataLines = frame
        .split(/\r?\n/)
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice(5).trimStart());
      if (dataLines.length === 0) continue;
      const data = dataLines.join("\n");
      if (data === "[DONE]") return;
      let parsed;
      try { parsed = JSON.parse(data); }
      catch { throw new Error("Malformed JSON in LM Studio stream."); }
      if (parsed.error) throw new Error(`LM Studio stream error: ${JSON.stringify(parsed.error)}`);
      yield parsed;
    }
    if (buffer.length > MAX_BODY_BYTES) throw new Error("LM Studio stream frame exceeds 16 MiB.");
  }
  if (requireDone || buffer.trim()) throw new Error("LM Studio stream closed before completion.");
}

function ensureMessage(res, state) {
  if (state.message) return state.message;

  const item = {
    id: id("msg"),
    type: "message",
    status: "in_progress",
    role: "assistant",
    content: [],
  };
  state.message = item;
  state.output.push(item);

  if (res) {
    const outputIndex = state.output.length - 1;
    sse(res, "response.output_item.added", {
      type: "response.output_item.added",
      output_index: outputIndex,
      item,
    });
    sse(res, "response.content_part.added", {
      type: "response.content_part.added",
      item_id: item.id,
      output_index: outputIndex,
      content_index: 0,
      part: { type: "output_text", text: "" },
    });
  }

  return item;
}

function ensureToolCall(res, state, index, delta) {
  if (state.toolCalls.has(index)) return state.toolCalls.get(index);

  const item = {
    id: id("fc"),
    type: "function_call",
    status: "in_progress",
    call_id: delta.id || id("call"),
    name: "",
    arguments: "",
  };
  state.toolCalls.set(index, item);
  state.output.push(item);

  if (res) {
    sse(res, "response.output_item.added", {
      type: "response.output_item.added",
      output_index: state.output.length - 1,
      item,
    });
  }

  return item;
}

function applyChatChunk(chunk, res, state) {
  if (chunk.usage) state.usage = {
    input_tokens: chunk.usage.prompt_tokens || 0,
    output_tokens: chunk.usage.completion_tokens || 0,
    total_tokens: chunk.usage.total_tokens || 0,
    input_tokens_details: { cached_tokens: chunk.usage.prompt_tokens_details?.cached_tokens || 0 },
    output_tokens_details: { reasoning_tokens: chunk.usage.completion_tokens_details?.reasoning_tokens || 0 },
  };
  const choice = chunk.choices && chunk.choices[0];
  if (!choice) return;
  if (choice.finish_reason) state.finishReason = choice.finish_reason;

  const delta = choice.delta || {};

  if (typeof delta.content === "string" && delta.content.length > 0) {
    const item = ensureMessage(res, state);
    const outputIndex = state.output.indexOf(item);
    state.text += delta.content;

    if (res) {
      sse(res, "response.output_text.delta", {
        type: "response.output_text.delta",
        item_id: item.id,
        output_index: outputIndex,
        content_index: 0,
        delta: delta.content,
      });
    }
  }

  for (const toolDelta of delta.tool_calls || []) {
    const index = toolDelta.index ?? 0;
    const item = ensureToolCall(res, state, index, toolDelta);
    if (toolDelta.id) item.call_id = toolDelta.id;
    if (toolDelta.function?.name) {
      item.name += toolDelta.function.name;
    }
    if (toolDelta.function?.arguments) {
      item.arguments += toolDelta.function.arguments;
      if (res) {
        sse(res, "response.function_call_arguments.delta", {
          type: "response.function_call_arguments.delta",
          item_id: item.id,
          output_index: state.output.indexOf(item),
          delta: toolDelta.function.arguments,
        });
      }
    }
  }
}

function finalizeState(res, state) {
  if (!state.finishReason) throw new Error("LM Studio returned no finish_reason.");
  if (!["stop", "tool_calls", "function_call"].includes(state.finishReason)) {
    throw new Error(`LM Studio response incomplete (${state.finishReason}). Increase output/context limits or inspect model settings.`);
  }
  if (!state.message && state.toolCalls.size === 0) throw new Error("LM Studio returned no text or tool calls. Check reasoning/output limits and model template.");
  for (const item of state.toolCalls.values()) {
    if (!item.name) throw new Error("LM Studio returned an unnamed tool call.");
    const original = state.toolNames?.get(item.name);
    if (original) Object.assign(item, original);
    try { JSON.parse(item.arguments); } catch { throw new Error(`Invalid tool arguments for ${item.name}.`); }
  }
  if (state.message) {
    const item = state.message;
    const outputIndex = state.output.indexOf(item);
    item.status = "completed";
    item.content = [{ type: "output_text", text: state.text }];

    if (res) {
      sse(res, "response.output_text.done", {
        type: "response.output_text.done",
        item_id: item.id,
        output_index: outputIndex,
        content_index: 0,
        text: state.text,
      });
      sse(res, "response.content_part.done", {
        type: "response.content_part.done",
        item_id: item.id,
        output_index: outputIndex,
        content_index: 0,
        part: { type: "output_text", text: state.text },
      });
      sse(res, "response.output_item.done", {
        type: "response.output_item.done",
        output_index: outputIndex,
        item,
      });
    }
  }

  for (const item of state.toolCalls.values()) {
    item.status = "completed";
    if (res) {
      sse(res, "response.function_call_arguments.done", {
        type: "response.function_call_arguments.done",
        item_id: item.id,
        output_index: state.output.indexOf(item),
        arguments: item.arguments,
      });
      sse(res, "response.output_item.done", {
        type: "response.output_item.done",
        output_index: state.output.indexOf(item),
        item,
      });
    }
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);

    if (req.headers.origin) throw clientError("Browser-origin requests are not supported.", 403);
    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, {
        ok: true,
        gateway: GATEWAY_ID,
        port: PORT,
        baseUrl: LMSTUDIO_BASE_URL,
        stateFile: MODEL_STATE_FILE,
        revision: REVISION,
        pid: process.pid,
        script: __filename,
        transport: TRANSPORT,
        timeoutMs: REQUEST_TIMEOUT_MS,
      });
    }
    if (req.method === "GET" && url.pathname === "/ready") {
      const model = await loadedModel(true);
      return json(res, 200, { model: model.id, contextLength: model.contextLength, transport: TRANSPORT });
    }

    if (req.method === "GET" && url.pathname === "/v1/models") {
      return json(res, 200, await modelList());
    }

    if (req.method === "POST" && url.pathname === "/v1/responses") {
      return await handleResponses(req, res);
    }

    return json(res, 404, { error: { message: "Not found" } });
  } catch (error) {
    const message = error && error.stack ? error.stack : String(error);
    console.error(message);
    if (!res.headersSent) {
      return json(res, error.status || 502, { error: { message: error.message || String(error) } });
    }
    if (!res.destroyed) sse(res, "response.failed", {
      type: "response.failed",
      response: { id: res.responseId || id("resp"), object: "response", status: "failed", output: [], error: { code: "upstream_error", message: error.message || String(error) } },
    });
    res.end();
  }
});

if (require.main === module) {
  server.on("error", error => {
    console.error(`Gateway could not listen on 127.0.0.1:${PORT}: ${error.code || error.message}. Check for another service or run lm-studio-stop for this installation.`);
    process.exitCode = 1;
  });
  server.listen(PORT, "127.0.0.1", () => {
  console.log(`LM Studio Responses gateway listening on http://127.0.0.1:${PORT}`);
  });
}
module.exports = { server, parseSse, convertResponsesInputToChat, convertTools };
