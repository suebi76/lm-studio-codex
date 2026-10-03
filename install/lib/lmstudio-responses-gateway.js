const fs = require("node:fs");
const http = require("node:http");

const PORT = Number(process.env.LMSTUDIO_CODEX_GATEWAY_PORT || 18123);
const LMSTUDIO_BASE_URL = process.env.LMSTUDIO_BASE_URL || "http://127.0.0.1:1234";
const FIXED_MODEL = process.env.LMSTUDIO_CODEX_MODEL || "";
const MODEL_STATE_FILE = process.env.LMSTUDIO_CODEX_MODEL_STATE_FILE || "";
const GATEWAY_ID = "lm-studio-codex-gateway";

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
      if (part.type === "input_image") return "[image]";
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
      messages.push({
        role: "assistant",
        content: null,
        tool_calls: [
          {
            id: item.call_id || item.id || id("call"),
            type: "function",
            function: {
              name: item.name,
              arguments: item.arguments || "{}",
            },
          },
        ],
      });
    }
  }

  if (systemParts.length > 0) {
    messages.unshift({
      role: "system",
      content: systemParts.join("\n\n"),
    });
  }

  return messages;
}

function convertTools(tools) {
  if (!Array.isArray(tools)) return undefined;

  const converted = tools
    .filter((tool) => tool && tool.type === "function" && tool.name)
    .map((tool) => ({
      type: "function",
      function: {
        name: tool.name,
        description: tool.description || "",
        parameters: tool.parameters || { type: "object", properties: {} },
      },
    }));

  return converted.length ? converted : undefined;
}

async function readRequestBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function loadedModel() {
  if (FIXED_MODEL) return FIXED_MODEL;

  if (MODEL_STATE_FILE && fs.existsSync(MODEL_STATE_FILE)) {
    try {
      const state = JSON.parse(fs.readFileSync(MODEL_STATE_FILE, "utf8"));
      if (state && typeof state.id === "string" && state.id.length > 0) {
        return state.id;
      }
    } catch {
      // Fall through to LM Studio introspection.
    }
  }

  const response = await fetch(`${LMSTUDIO_BASE_URL}/api/v1/models`);
  if (!response.ok) {
    throw new Error(`LM Studio model list failed with HTTP ${response.status}`);
  }
  const data = await response.json();
  const loaded = [];

  for (const model of data.models || []) {
    if (model.type !== "llm") continue;
    for (const instance of model.loaded_instances || []) {
      loaded.push(instance.id || model.key);
    }
  }

  if (loaded.length === 0) {
    throw new Error("No LLM is currently loaded in LM Studio.");
  }

  if (loaded.length > 1) {
    throw new Error(
      `Multiple LLMs are loaded in LM Studio (${loaded.join(", ")}). Unload all but one model, then run lm-studio again.`
    );
  }

  return loaded[0];
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

async function handleResponses(req, res) {
  const body = await readRequestBody(req);
  const model = body.model && body.model !== "lmstudio-loaded" ? body.model : await loadedModel();
  const responseId = id("resp");
  const created = Math.floor(Date.now() / 1000);
  const output = [];
  const stream = body.stream !== false;
  const tools = convertTools(body.tools);
  const messages = convertResponsesInputToChat(body);

  const chatBody = {
    model,
    messages,
    stream: true,
  };

  if (tools) {
    chatBody.tools = tools;
    chatBody.tool_choice = "auto";
  }

  if (typeof body.temperature === "number") chatBody.temperature = body.temperature;
  if (typeof body.max_output_tokens === "number") chatBody.max_tokens = body.max_output_tokens;

  const upstream = await fetch(`${LMSTUDIO_BASE_URL}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(chatBody),
  });

  if (!upstream.ok || !upstream.body) {
    const detail = await upstream.text().catch(() => "");
    throw new Error(`LM Studio chat completion failed with HTTP ${upstream.status}: ${detail}`);
  }

  if (!stream) {
    const completion = await collectChatStream(upstream);
    return json(res, 200, completeResponse(responseId, created, model, completion.output));
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
  };

  await streamChatAsResponses(upstream, res, state);

  sse(res, "response.completed", {
    type: "response.completed",
    response: completeResponse(responseId, created, model, output),
  });
  res.end();
}

function completeResponse(responseId, created, model, output) {
  return {
    id: responseId,
    object: "response",
    created_at: created,
    status: "completed",
    model,
    output,
    usage: null,
  };
}

async function collectChatStream(upstream) {
  const output = [];
  const state = { output, message: null, text: "", toolCalls: new Map() };
  for await (const chunk of parseSse(upstream.body)) {
    applyChatChunk(chunk, null, state);
  }
  finalizeState(null, state);
  return { output };
}

async function streamChatAsResponses(upstream, res, state) {
  for await (const chunk of parseSse(upstream.body)) {
    applyChatChunk(chunk, res, state);
  }
  finalizeState(res, state);
}

async function* parseSse(stream) {
  const decoder = new TextDecoder();
  let buffer = "";

  for await (const chunk of stream) {
    buffer += decoder.decode(chunk, { stream: true });
    let boundary;
    while ((boundary = buffer.indexOf("\n\n")) !== -1) {
      const frame = buffer.slice(0, boundary);
      buffer = buffer.slice(boundary + 2);
      const dataLines = frame
        .split(/\r?\n/)
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice(5).trimStart());
      if (dataLines.length === 0) continue;
      const data = dataLines.join("\n");
      if (data === "[DONE]") return;
      try {
        yield JSON.parse(data);
      } catch {
        // Ignore malformed upstream frames.
      }
    }
  }
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
    name: delta.function?.name || "",
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
  const choice = chunk.choices && chunk.choices[0];
  if (!choice) return;

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
    if (toolDelta.id && !item.call_id) item.call_id = toolDelta.id;
    if (toolDelta.function?.name) {
      const nameDelta = toolDelta.function.name;
      if (!item.name || nameDelta.startsWith(item.name)) {
        item.name = nameDelta;
      } else if (!item.name.endsWith(nameDelta)) {
        item.name += nameDelta;
      }
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

    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, {
        ok: true,
        gateway: GATEWAY_ID,
        port: PORT,
        baseUrl: LMSTUDIO_BASE_URL,
        stateFile: MODEL_STATE_FILE,
        model: await loadedModel(),
      });
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
      return json(res, 500, { error: { message } });
    }
    res.end();
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`LM Studio Responses gateway listening on http://127.0.0.1:${PORT}`);
});
