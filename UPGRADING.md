# Upgrading

## 0.1.0 → 0.2.0

### Vision / Multimodal Support

0.2.0 adds end-to-end image support. Agents can now receive images via URL or base64-encoded data alongside text prompts.

#### Step 1: Run the new migration

A new migration adds `image_url` and `image_data` columns to the `solid_agent_messages` table:

```bash
bin/rails solid_agent:install:migrations
bin/rails db:migrate
```

This is non-destructive — existing messages are unaffected. The new columns are nullable.

#### Step 2: Start using vision

No code changes are required for existing agents. String input continues to work exactly as before.

To send images, pass a hash instead of a string:

```ruby
# Before (still works)
MyAgent.perform_now("What time is it?")

# New — image by URL
MyAgent.perform_now({
  text: "What's in this image?",
  image_url: "https://example.com/photo.jpg"
})

# New — image by base64
require "base64"
image_data = Base64.strict_encode64(File.read("photo.png"))

MyAgent.perform_now({
  text: "Describe this screenshot",
  image_data: {
    data: image_data,
    media_type: "image/png"
  }
})
```

#### Step 3: Use a vision-capable model

Make sure your agent uses a model that supports image inputs:

```ruby
class ImageAnalyzer < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O  # or GPT_4O_MINI, GPT_5_4, etc.

  instructions "You analyze images."
end
```

Vision-capable models by provider:

| Provider | Models |
|---|---|
| OpenAI | GPT-4o, GPT-4o-mini, GPT-5.4, o3 |
| Anthropic | All Claude models |
| Google | All Gemini models |
| Ollama | llava, and other vision-capable models |

See [Providers — Vision](providers.md#vision--multimodal-support) for details.

### Other 0.2.0 changes

- Streaming support via `on_chunk` callback
- Agent callbacks: `before_invoke`, `after_invoke`, `on_context_overflow`
- Temperature and max_tokens pass-through
- `retry_on` with configurable attempts
- `tool_choice` DSL
- SSE MCP transport for remote MCP servers
- Real-time dashboard updates via ActionCable
