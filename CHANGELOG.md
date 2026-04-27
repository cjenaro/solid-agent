# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
