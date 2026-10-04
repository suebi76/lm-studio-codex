# Choosing a Model

Use a chat/instruct model with documented tool-calling support. A coding-oriented model is a reasonable starting point, but a family name, a large parameter count or a community filename does not establish compatibility. Quantization, chat templates, LM Studio runtimes and loaded context all affect results.

After loading one model, run `lm-studio-doctor`. It checks streamed output, JSON, a tool call and its result, then a real Codex answer. Treat a failed tool round trip as a failed agent setup, even when ordinary chat looks good.

Begin with a small read-only project task, then a bounded edit with a test. Review the diff. Passing Doctor is evidence of basic capability, not a guarantee for autonomous repository work.

Choose a context size that fits your hardware and leaves room for Codex instructions, tools, source files and outputs. An 8192-token context can be too small for substantial agent work; arbitrarily maximizing it can exhaust memory. The launcher uses the loaded context size when LM Studio exposes it.

To compare models fairly, use the same small project task and record correctness, time to first output, total time, tool failures and memory use. No model is hardcoded by this project.

To switch, wait for the current task to end, unload the old model and load the new one. The next request follows the loaded model without restarting the terminal. Use `:new` if the replacement cannot fit the previous session's history.
