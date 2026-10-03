# Model Recommendations

Local Coding-Agent workflows need more than good chat quality. Prefer models that are strong at:

- instruction following
- repository-scale code understanding
- JSON output
- tool/function calling
- long context
- stable behavior across multi-step tasks

Run this after loading a model in LM Studio:

```bash
lm-studio-doctor
```

The Doctor checks the real loaded model through the same gateway Codex uses. Trust that result more than the model family name.

## Recommended Families

These are good starting points for LM Studio + Codex CLI:

- Qwen Coder / large Qwen instruct models: usually the best first choice for local coding-agent work.
- DeepSeek Coder / DeepSeek V3 or newer coding-capable variants: strong for larger code tasks if your hardware can run them comfortably.
- Kimi K2 / Kimi Code style models: good candidates for agentic workflows and tool-heavy sessions.
- Devstral: designed for multi-step coding-agent tasks.
- Codestral: good for code generation and editing; use Doctor results to judge longer agent sessions.

## Usable With Caution

- Gemma instruct models can work for small coding tasks, but check JSON and tool-call reliability before long autonomous runs.
- General Llama, Mistral, Phi, Granite, and StarCoder variants depend heavily on size, quantization, and instruct tuning. Prefer coder/instruct variants.
- Very small models can be useful for quick edits, but often struggle with long context and tool-call discipline.

## Practical Rule

For this project, load exactly one model in LM Studio, then run:

```bash
lm-studio-doctor
```

Green text, JSON, tool-call, and Codex smoke checks mean the model is a good candidate. Warnings mean it may still be useful, but keep tasks smaller and review changes carefully.

To switch models:

1. Stop the current Codex run.
2. Unload the old model in LM Studio.
3. Load the new model.
4. Run `lm-studio-doctor`.
5. Run `lm-studio`.
