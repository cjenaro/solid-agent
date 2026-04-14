# Multi-Agent Orchestration

Build systems where multiple agents collaborate. Solid Agent provides two patterns: **supervisor delegation** (heavyweight, full trace) and **agent-as-tool** (lightweight, inline span). They can be mixed freely.

## Including the Orchestration DSL

Orchestration methods are available via `SolidAgent::Orchestration::DSL`, which is an `ActiveSupport::Concern`. Include it in any agent that acts as a supervisor:

```ruby
class ProjectManagerAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL
end
```

## Supervisor Delegation

Spawns a child `Trace` for each delegation. The child runs its own full ReAct loop, observable and resumable independently.

```ruby
class ProjectManagerAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    You are a project manager. Break down tasks and delegate to specialists.
    Use the research, writing, and analysis tools to complete work.
  PROMPT

  delegate :research, to: ResearchAgent, description: "Research a topic thoroughly"
  delegate :writing, to: WriterAgent, description: "Write content based on research"
  delegate :analysis, to: AnalysisAgent, description: "Analyze data and provide insights"

  concurrency 3
end
```

### Execution Flow

```
Trace #1 (ProjectManagerAgent)
  THINK -> "I need to research the topic first"
  ACT   -> delegate(:research, input: "Market trends in AI")
    Trace #2 (child, parent_trace_id: 1, trace_type: delegate)
      Full independent ReAct loop
  THINK -> "Now I need to write a report"
  ACT   -> delegate(:writing, input: "Write a market analysis report")
    Trace #3 (child, parent_trace_id: 1, trace_type: delegate)
  THINK -> Synthesize results -> final answer
```

Child traces are linked to the parent via `parent_trace_id`. Each child has its own spans, token tracking, and status. The dashboard shows parent-child relationships with drill-down links.

### Delegate Tool Schema

The delegate is presented to the supervisor LLM as a tool with a single `input` parameter (string). The LLM writes its instructions in natural language:

```ruby
# Schema exposed to the supervisor LLM
{
  name: "research",
  description: "Research a topic thoroughly",
  inputSchema: {
    type: "object",
    properties: {
      input: { type: "string", description: "The task to delegate to the agent" }
    },
    required: ["input"]
  }
}
```

## Agent-as-Tool

Runs the sub-agent inline within the parent's ReAct loop. Logged as a span, not a separate trace. Lighter weight than delegation.

```ruby
class ProjectManagerAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  agent_tool :quick_summary, agent: SummaryAgent, description: "Generate a quick summary"
  agent_tool :translate, agent: TranslatorAgent, description: "Translate text to another language"

  delegate :deep_research, to: ResearchAgent, description: "Research a topic thoroughly"
end
```

### When to Use Which

| | Supervisor Delegation | Agent-as-Tool |
|---|---|---|
| Observable independently | Yes (child trace) | No (parent span) |
| Resumable independently | Yes | No |
| Overhead | Higher (new trace, full loop) | Lower (inline) |
| Best for | Complex subtasks | Simple, fast subtasks |
| Dashboard visibility | Separate trace row | Span within parent trace |

Rule of thumb: use delegation when the subtask is complex enough to warrant its own trace with independent iteration limits, timeout, and memory. Use agent-as-tool for quick helper tasks like summarization or translation.

## Mixing Both Patterns

Both can coexist in one supervisor:

```ruby
class ContentPipelineAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  delegate :research, to: ResearchAgent, description: "Research a topic"
  delegate :write_draft, to: WriterAgent, description: "Write a draft article"

  agent_tool :summarize, agent: SummaryAgent, description: "Generate a brief summary"

  instructions <<~PROMPT
    You manage content creation. Use research and write_draft for heavy work.
    Use summarize for quick summaries when needed.
  PROMPT

  concurrency 3
end
```

## Parallel Execution

Parallel execution is controlled by the supervisor's `concurrency` setting and the LLM's behavior. When the LLM returns multiple tool calls in a single response, the runtime executes up to `concurrency` in parallel.

```ruby
class ProjectManagerAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    When tasks are independent, invoke multiple tools in the same response
    to run them in parallel. When one task depends on another, invoke
    them sequentially.
  PROMPT

  delegate :competitor_research, to: ResearchAgent, description: "Research competitors"
  delegate :market_research, to: ResearchAgent, description: "Research market conditions"
  delegate :trend_analysis, to: AnalysisAgent, description: "Analyze trends"

  concurrency 3
end
```

The `ParallelExecutor` batches tool calls by the concurrency limit and runs each batch via threads. Each thread checks out its own ActiveRecord connection from the pool.

## Error Propagation

Control how failures in delegates are handled:

```ruby
class ProjectManagerAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  delegate :research, to: ResearchAgent, description: "Research a topic"
  delegate :writing, to: WriterAgent, description: "Write content"
  delegate :code_review, to: CodeReviewAgent, description: "Review code"

  on_delegate_failure :research, strategy: :retry, attempts: 2
  on_delegate_failure :writing, strategy: :report_error
  on_delegate_failure :code_review, strategy: :fail_parent
end
```

Three strategies:

| Strategy | Behavior |
|---|---|
| `:retry` | Retries the delegate up to `attempts` times. Returns the error message if all attempts fail. |
| `:report_error` | Returns the error string to the supervisor LLM. The supervisor decides what to do. |
| `:fail_parent` | Lets the exception propagate, failing the parent trace. Use for critical failures. |

The default strategy (when `on_delegate_failure` is not set) is `:report_error`.

## Practical Example: Building a Team of Specialists

```ruby
class ResearchAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    You are a research specialist. Given a topic, find relevant information
    from available data sources and compile a structured summary with
    key findings and citations.
  PROMPT

  tool :search_documents, description: "Search internal documents" do |query:|
    Document.search(query).map { |d| { title: d.title, excerpt: d.excerpt(200) } }.to_json
  end

  tool :search_web, description: "Search the web" do |query:|
    WebSearchService.search(query).to_json
  end

  memory :sliding_window, max_messages: 30
  max_iterations 15
end

class WriterAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::Anthropic::CLAUDE_SONNET_4

  instructions <<~PROMPT
    You are a professional writer. Given research findings and a target
    format, produce polished content. Follow the requested tone, length,
    and structure.
  PROMPT

  tool :save_draft, description: "Save a draft document" do |title:, content:|
    draft = Draft.create!(title: title, content: content)
    { id: draft.id, url: draft_path(draft) }.to_json
  end

  memory :sliding_window, max_messages: 40
  max_iterations 10
end

class EditorAgent < SolidAgent::Base
  provider :anthropic
  model SolidAgent::Models::Anthropic::CLAUDE_SONNET_4

  instructions <<~PROMPT
    You are an editor. Review content for clarity, grammar, factual accuracy,
    and adherence to style guidelines. Provide specific suggestions.
  PROMPT

  max_iterations 8
end

class ContentOrchestrator < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    You orchestrate content creation. The workflow is:
    1. Research the topic (delegate to :research)
    2. Write a draft based on research (delegate to :writing)
    3. Edit the draft (delegate to :editing)

    Each step depends on the previous one. Run them sequentially by
    invoking one delegate at a time.
  PROMPT

  delegate :research, to: ResearchAgent, description: "Research a topic"
  delegate :writing, to: WriterAgent, description: "Write a draft"
  delegate :editing, to: EditorAgent, description: "Edit and review content"

  agent_tool :summarize, agent: SummaryAgent, description: "Quick summary"

  on_delegate_failure :research, strategy: :retry, attempts: 2
  on_delegate_failure :writing, strategy: :report_error
  on_delegate_failure :editing, strategy: :report_error

  concurrency 1
  max_iterations 15
  timeout 10.minutes
end
```

Run it:

```ruby
trace = ContentOrchestrator.perform_now(
  "Write a 500-word article about recent advances in quantum computing"
)
```

Check the dashboard to see the parent trace with its three child traces, each with its own span tree.
