# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-04-28

### Fixed
- `self_and_descendant_spans` is now public so `tool_summary` and `total_cost` work correctly
- Remove built `.gem` from git tracking

## [0.4.0] - 2026-04-28

### Added
- **GPT-5.4 Nano and Mini models** — `SolidAgent::Models::OpenAi::GPT_5_4_NANO` and `GPT_5_4_MINI` with current pricing ($0.20/$1.25 and $0.75/$4.50 per 1M tokens). `Models::OpenAi.find(model_id)` for lookup by string.
- **Automatic `max_completion_tokens`** — the OpenAI provider now uses `max_completion_tokens` for GPT-5.x and o3/o4 models (required by the API) and `max_tokens` for older models. No more need for custom provider subclasses.
- **Automatic image detail** — inline base64 images get `detail: "low"` or `"auto"` based on size, reducing token consumption without a custom provider.
- **Cost tracking** — `Trace#cost` (own), `Trace#total_cost` (recursive with children), `Trace#model_name`, `Trace#tool_summary`, `Trace#total_iterations`. Cost is computed from stored usage + model pricing.
- **Trace show page redesign** — summary cards (duration, iterations, tokens, cost), tool call pills, delegated runs table with per-child cost.
- **Cost column** added to traces index and dashboard.

### Changed
- OpenAI provider `build_request` now handles `max_completion_tokens` / `max_tokens` dispatch internally based on model family.

## [0.3.3] - 2026-04-27

### Fixed
- Timeout error message now shows the actual timeout used (not always the default 30s)

## [0.3.2] - 2026-04-27

### Added
- **Per-tool timeout** — tools can now declare `timeout N` (seconds) to override the default 30s execution timeout. Works on both `Tool::Base` subclasses (`class GetVideoInfoTool < SolidAgent::Tool::Base; timeout 60; end`) and inline tools (`tool :my_tool, timeout: 120 do ... end`).
- **Dashboard trace state management** — "Cancel" button on running/pending traces, "Cancel all running" bulk action on the traces index. Status can be manually changed to any valid state.
- `cancelled` added to valid trace statuses.

## [0.3.1] - 2026-04-27

### Fixed
- **ExecutionEngine timeout no longer kills subagent tools** — `DelegateTool` and `AgentTool` are now exempt from the 30-second tool execution timeout. Subagents manage their own timeout via the child agent's React loop (`timeout` DSL). Previously, every delegate/agent_tool call was cut short after 30s, leaving child traces stuck in `running` status forever.
- **`AgentTool#execute` no longer calls `perform_now` twice** — the first (untracked) invocation was removed; the agent now runs exactly once, inside the span-tracking block.

## [0.3.0] - 2026-04-27

### Changed
- **Unified tool system** — `delegate` and `agent_tool` orchestration tools are now registered in the same `Tool::Registry` as regular tools. No more separate execution paths in the React loop.
- `ExecutionEngine` accepts `context:` kwarg (trace + conversation) and passes it through to tools that accept it (DelegateTool/AgentTool).
- `ExecutionEngine#execute_all` now uses threads with ActiveRecord connection pool checkout for all tools when concurrency > 1.
- `React::Loop` reverted to clean single-path: all tool calls go through `execute_all`, concurrency applies uniformly.
- `RunJob` registers orchestration tools in the agent's tool registry before building the execution engine.
- `Tool::Registry#register` accepts duck-typed tools (anything responding to `to_tool_schema`).

### Removed
- `orchestration_tools`, `error_strategies` params from `React::Loop` constructor.
- Orchestration-specific branching code from the React loop (split/merge orchestration vs regular, `execute_orchestration_call` helper).

## [0.2.4] - 2026-04-27

### Added
- Parallel execution of orchestration tool calls (delegates/agent_tools), batched by the agent's `concurrency` setting with ActiveRecord connection pool checkout per thread
- `ExecutionEngine` exposes `concurrency` via `attr_reader`

## [0.2.3] - 2026-04-27

### Fixed
- `DelegateTool` and `AgentTool` now return `result.output` instead of `result.to_s` — previously the coordinator saw `#<SolidAgent::Agent::Result:0x...>` garbage text instead of the subagent's actual output

## [0.2.2] - 2026-04-27

### Fixed
- `Base.perform_now` accepts optional `trace:` and `conversation:` kwargs so `DelegateTool` can pass pre-created child traces
- `RunJob` passes `orchestration_tools` and `error_strategies` to `React::Loop` when agent includes `Orchestration::DSL`

## [0.2.1] - 2026-04-27

### Fixed
- Wire orchestration tools (`delegate`, `agent_tool`) into the React loop — schemas are now sent to the LLM and tool calls are routed to `DelegateTool`/`AgentTool` with error strategies. Previously the orchestration DSL was defined but never connected to the execution path.

## [0.2.0] - 2026-04-27

### Added
- Streaming support for LLM token delivery via `on_chunk` callback
- Agent callbacks: `before_invoke`, `after_invoke`, `on_context_overflow`
- Temperature and max_tokens pass-through to all providers
- `retry_on` implementation with configurable retry attempts
- `tool_choice` DSL for controlling model tool usage (`auto`, `required`, `none`, or specific tool)
- OpenAI embedder for vector similarity search
- Multimodal message support — images via URL or base64 (end-to-end: DB, entry points, provider serialization)
- `Tool::ImageResult` — tools can return images alongside text. The React loop injects images as user messages after all tool results, keeping the message sequence valid across all providers (OpenAI, Anthropic, Google, Ollama)
- SSE MCP transport for remote MCP servers
- Real-time dashboard updates via ActionCable
- MIT LICENSE file
- CHANGELOG

### Fixed
- Added missing `has_many :messages` association to `Trace` model (was called in `RunJob` but never declared)
- Image tool results are now queued and appended after all tool result messages, preventing OpenAI's "tool_call_ids did not have response messages" error when multiple tools are called in parallel

## [0.1.0] - 2025-01-01

### Added
- Initial release
- ReAct loop with automatic iteration
- OpenAI, Anthropic, Google, Ollama, Mistral providers
- OpenAI-compatible endpoint support
- Sliding window, full history, and compaction memory strategies
- Observational memory with vector similarity search
- Ruby tool DSL with typed parameters
- MCP client with stdio transport
- Multi-agent orchestration (delegate, agent_tool, parallel)
- Observability dashboard (traces, spans, conversations)
- Solid Queue integration for async execution
