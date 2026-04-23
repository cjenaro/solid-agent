# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added
- Streaming support for LLM token delivery via `on_chunk` callback
- Agent callbacks: `before_invoke`, `after_invoke`, `on_context_overflow`
- Temperature and max_tokens pass-through to all providers
- `retry_on` implementation with configurable retry attempts
- `tool_choice` DSL for controlling model tool usage (`auto`, `required`, `none`, or specific tool)
- OpenAI embedder for vector similarity search
- Multimodal message support — images via URL or base64 (end-to-end: DB, entry points, provider serialization)
- SSE MCP transport for remote MCP servers
- Real-time dashboard updates via ActionCable
- MIT LICENSE file
- CHANGELOG

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
