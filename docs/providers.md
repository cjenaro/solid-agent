# Providers

Solid Agent communicates with LLM providers through an adapter layer. Providers never touch HTTP directly -- they produce `HTTP::Request` structs and consume `HTTP::Response` structs.

## Supported Providers

| Provider | Symbol | Class |
|---|---|---|
| OpenAI | `:openai` | `SolidAgent::Provider::OpenAi` |
| Anthropic | `:anthropic` | `SolidAgent::Provider::Anthropic` |
| Google Gemini | `:google` | `SolidAgent::Provider::Google` |
| Ollama (local) | `:ollama` | `SolidAgent::Provider::Ollama` |
| OpenAI-compatible | `:openai_compatible` | `SolidAgent::Provider::OpenAiCompatible` |

## Configuration

```ruby
SolidAgent.configure do |config|
  config.default_provider = :openai

  config.providers[:openai] = {
    api_key: ENV["OPENAI_API_KEY"]
  }

  config.providers[:anthropic] = {
    api_key: ENV["ANTHROPIC_API_KEY"]
  }

  config.providers[:google] = {
    api_key: ENV["GOOGLE_API_KEY"]
  }

  config.providers[:ollama] = {
    base_url: "http://localhost:11434"
  }

  config.providers[:openai_compatible] = {
    base_url: "http://localhost:8000/v1",
    api_key: "local-key"
  }
end
```

Per-agent overrides:

```ruby
class MyAgent < SolidAgent::Base
  provider :anthropic
  model SolidAgent::Models::Anthropic::CLAUDE_SONNET_4
end
```

## Provider Details

### OpenAI

```ruby
SolidAgent::Provider::OpenAi.new(
  api_key: "sk-...",
  default_model: SolidAgent::Models::OpenAi::GPT_4O,
  base_url: nil  # defaults to https://api.openai.com/v1/chat/completions
)
```

- Endpoint: `https://api.openai.com/v1/chat/completions`
- Auth: `Authorization: Bearer <api_key>`
- Tool format: OpenAI function calling (`{ type: "function", function: { ... } }`)
- Streaming: SSE with `data: {...}` lines, terminated by `data: [DONE]`

Available models:

| Constant | Model ID | Context Window | Max Output | Input $/M | Output $/M |
|---|---|---|---|---|---|
| `GPT_5_4_PRO` | gpt-5.4-pro | 1,050,000 | 128,000 | $30.00 | $180.00 |
| `GPT_5_4` | gpt-5.4 | 1,050,000 | 128,000 | $2.50 | $15.00 |
| `O3_PRO` | o3-pro | 200,000 | 100,000 | $20.00 | $80.00 |
| `O3` | o3 | 200,000 | 100,000 | $2.00 | $8.00 |
| `GPT_4O` | gpt-4o | 128,000 | 16,384 | $2.50 | $10.00 |
| `GPT_4O_MINI` | gpt-4o-mini | 128,000 | 16,384 | $0.15 | $0.60 |

### Anthropic

```ruby
SolidAgent::Provider::Anthropic.new(
  api_key: "sk-ant-...",
  default_model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4
)
```

- Endpoint: `https://api.anthropic.com/v1/messages`
- Auth: `x-api-key` header + `anthropic-version: 2023-06-01`
- System prompt extracted from messages and sent as `body.system` (Anthropic convention)
- Tool results serialized as `tool_result` content blocks with `role: "user"`
- Streaming: SSE with `event:` and `data:` lines

Available models:

| Constant | Model ID | Context Window | Max Output | Input $/M | Output $/M |
|---|---|---|---|---|---|
| `CLAUDE_OPUS_4_6` | claude-opus-4-6 | 1,000,000 | 128,000 | $5.00 | $25.00 |
| `CLAUDE_SONNET_4_6` | claude-sonnet-4-6 | 1,000,000 | 64,000 | $3.00 | $15.00 |
| `CLAUDE_OPUS_4_5` | claude-opus-4-5 | 200,000 | 64,000 | $5.00 | $25.00 |
| `CLAUDE_SONNET_4_5` | claude-sonnet-4-5 | 200,000 | 64,000 | $3.00 | $15.00 |
| `CLAUDE_SONNET_4` | claude-sonnet-4-0 | 200,000 | 64,000 | $3.00 | $15.00 |
| `CLAUDE_HAIKU_4_5` | claude-haiku-4-5 | 200,000 | 64,000 | $1.00 | $5.00 |

### Google Gemini

```ruby
SolidAgent::Provider::Google.new(
  api_key: "...",
  default_model: SolidAgent::Models::Google::GEMINI_2_5_PRO
)
```

- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
- Auth: API key as query parameter
- System prompt sent as `systemInstruction`
- Assistant messages mapped to `role: "model"`
- Streaming: `streamGenerateContent` endpoint with SSE `data:` lines

Available models:

| Constant | Model ID | Context Window | Max Output | Input $/M | Output $/M |
|---|---|---|---|---|---|
| `GEMINI_2_5_PRO` | gemini-2.5-pro | 1,048,576 | 65,536 | $1.25 | $10.00 |
| `GEMINI_2_5_FLASH` | gemini-2.5-flash | 1,048,576 | 65,536 | $0.30 | $2.50 |
| `GEMINI_2_5_FLASH_LITE` | gemini-2.5-flash-lite | 1,048,576 | 65,536 | $0.10 | $0.40 |
| `GEMINI_2_0_FLASH` | gemini-2.0-flash | 1,048,576 | 8,192 | $0.10 | $0.40 |

### Ollama (Local)

```ruby
SolidAgent::Provider::Ollama.new(
  base_url: "http://localhost:11434"
)
```

- Endpoint: `http://localhost:11434/api/chat`
- No API key required
- Uses OpenAI-compatible tool format
- Token tracking: Ollama does not return usage data, so token counts are zero

Available models:

| Constant | Model ID | Context Window | Max Output |
|---|---|---|---|
| `LLAMA_3_3_70B` | llama3.3:70b | 128,000 | 4,096 |
| `QWEN_2_5_72B` | qwen2.5:72b | 128,000 | 8,192 |
| `DEEPSEEK_V3` | deepseek-v3:671b | 128,000 | 8,192 |

Use any Ollama model by creating a `SolidAgent::Model` directly:

```ruby
MyModel = SolidAgent::Model.new("phi4:latest", context_window: 128_000, max_output: 4_096)

class MyAgent < SolidAgent::Base
  provider :ollama
  model MyModel
end
```

### OpenAI-Compatible

Connects to any server implementing the OpenAI chat completions API:

```ruby
SolidAgent::Provider::OpenAiCompatible.new(
  base_url: "http://localhost:8000/v1",
  api_key: "local-key",
  default_model: "my-model"
)
```

Extends `OpenAi` and overrides the base URL. Compatible with LiteLLM, vLLM, Text Generation Inference, and similar servers.

## Adding a Custom HTTP Adapter

The HTTP adapter resolves at runtime via `SolidAgent::HTTP::Adapters`:

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.http_adapter = :net_http  # default
end
```

Provide a custom adapter class:

```ruby
class MyHttpAdapter
  def call(request)
    # request is a SolidAgent::HTTP::Request
    # must return a SolidAgent::HTTP::Response
    response = my_http_client.post(request.url, body: request.body, headers: request.headers)

    SolidAgent::HTTP::Response.new(
      status: response.status,
      headers: response.headers.to_h,
      body: response.body,
      error: nil
    )
  end
end

SolidAgent.configure do |config|
  config.http_adapter = MyHttpAdapter
end
```

The adapter must respond to `call(request) -> Response`. The `HTTP::Adapters.resolve` method handles symbols, classes, and instances.

## Streaming

Providers support streaming via `SolidAgent::Types::StreamChunk`:

```ruby
request = provider.build_request(
  messages: messages,
  tools: [],
  stream: true,
  model: model,
  max_tokens: model.max_output
)

# Broadcast via Solid Cable in the run loop
provider.complete(messages:, stream: true) do |chunk|
  SolidAgent::Streaming.broadcast(conversation_id, chunk)
end
```

Each chunk carries:

```ruby
SolidAgent::Types::StreamChunk.new(
  delta_content: "Hello",      # text delta
  delta_tool_calls: [],         # partial tool call deltas
  usage: nil,                   # final usage (only on last chunk for some providers)
  done: false                   # true on final chunk
)
```

## Error Handling and Retries

### Error Hierarchy

```ruby
SolidAgent::Error                    # base
SolidAgent::ProviderError < Error    # generic provider error
SolidAgent::RateLimitError           # HTTP 429, includes retry_after
SolidAgent::ContextLengthError       # token limit exceeded
SolidAgent::ProviderTimeoutError     # HTTP 408/504
```

### Provider Error Mapping

Each provider maps HTTP status codes to error classes:

| Status | Error |
|---|---|
| 429 | `RateLimitError` (OpenAI includes `retry_after` header) |
| 400 with context/token keywords | `ContextLengthError` |
| 408, 504 | `ProviderTimeoutError` |
| Other | `ProviderError` |

### Retries

Configure retries per agent:

```ruby
class MyAgent < SolidAgent::Base
  retry_on SolidAgent::RateLimitError, attempts: 3
end
```

This stores the error class and attempt count. The `RunJob` can use this configuration to retry the entire run on rate limit errors.

### Cost Tracking

`SolidAgent::Types::Usage` computes cost from token counts and model pricing:

```ruby
usage = SolidAgent::Types::Usage.new(
  input_tokens: 1000,
  output_tokens: 500,
  input_price_per_million: 2.5,
  output_price_per_million: 10.0
)

usage.total_tokens  # => 1500
usage.cost          # => 0.0075
```

Token counts are accumulated per trace and stored in the `usage` JSON column:

```ruby
trace = SolidAgent::Trace.find(42)
trace.usage
# => { "input_tokens" => 4500, "output_tokens" => 1200 }
trace.total_tokens  # => 5700
```
