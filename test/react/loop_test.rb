require 'test_helper'
require 'solid_agent'
require 'solid_agent/react/loop'

class FakeHttpAdapter
  attr_reader :requests

  def initialize
    @requests = []
  end

  def call(request)
    @requests << request
    SolidAgent::HTTP::Response.new(status: 200, headers: {}, body: '{}')
  end
end

class FakeProvider
  attr_reader :call_count

  def initialize(responses)
    @responses = responses
    @call_count = 0
  end

  def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
    SolidAgent::HTTP::Request.new(
      method: :post, url: 'https://fake.test/v1/chat',
      headers: {}, body: '{}', stream: false
    )
  end

  def parse_response(_raw_response)
    @call_count += 1
    @responses[@call_count - 1] || @responses.last
  end
end

class FakeMemory
  def build_context(messages, system_prompt:)
    messages
  end

  def compact!(messages)
    messages.last(5)
  end
end

class ReactLoopTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      status: 'running',
      started_at: Time.current
    )
  end

  test 'simple loop: think once, no tools, done' do
    provider = FakeProvider.new([
                                  SolidAgent::Types::Response.new(
                                    messages: [SolidAgent::Types::Message.new(role: 'assistant',
                                                                              content: 'The answer is 42')],
                                    tool_calls: [],
                                    usage: SolidAgent::Types::Usage.new(input_tokens: 100, output_tokens: 50),
                                    finish_reason: 'stop'
                                  )
                                ])
    memory = FakeMemory.new
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1)
    http_adapter = FakeHttpAdapter.new

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: memory,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'You are a test agent.',
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes,
      http_adapter: http_adapter
    )

    result = loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'What is 6*7?')])
    assert result.completed?
    assert_equal 'The answer is 42', result.output
    assert_equal 1, provider.call_count
  end

  test 'loop with tool call then final answer' do
    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
                        name: :add, description: 'Add', parameters: [
                                                          { name: :a, type: :integer, required: true },
                                                          { name: :b, type: :integer, required: true }
                                                        ],
                        block: proc { |a:, b:| a + b }
                      ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    provider = FakeProvider.new([
                                  SolidAgent::Types::Response.new(
                                    messages: [SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [
                                                                                SolidAgent::Types::ToolCall.new(id: 'c1', name: 'add', arguments: { 'a' => 3, 'b' => 4 })
                                                                              ])],
                                    tool_calls: [SolidAgent::Types::ToolCall.new(id: 'c1', name: 'add',
                                                                                 arguments: { 'a' => 3, 'b' => 4 })],
                                    usage: SolidAgent::Types::Usage.new(input_tokens: 50, output_tokens: 20),
                                    finish_reason: 'tool_calls'
                                  ),
                                  SolidAgent::Types::Response.new(
                                    messages: [SolidAgent::Types::Message.new(role: 'assistant', content: '3 + 4 = 7')],
                                    tool_calls: [],
                                    usage: SolidAgent::Types::Usage.new(input_tokens: 80, output_tokens: 30),
                                    finish_reason: 'stop'
                                  )
                                ])

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'You are helpful.',
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes,
      http_adapter: FakeHttpAdapter.new
    )

    result = loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'What is 3+4?')])
    assert result.completed?
    assert_equal '3 + 4 = 7', result.output
    assert_equal 2, provider.call_count
  end

  test 'loop stops at max iterations' do
    always_tool = SolidAgent::Types::Response.new(
      messages: [SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [
                                                  SolidAgent::Types::ToolCall.new(id: 'c1', name: 'ping', arguments: {})
                                                ])],
      tool_calls: [SolidAgent::Types::ToolCall.new(id: 'c1', name: 'ping', arguments: {})],
      usage: SolidAgent::Types::Usage.new(input_tokens: 10, output_tokens: 5),
      finish_reason: 'tool_calls'
    )
    provider = FakeProvider.new([always_tool])

    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
                        name: :ping, description: 'Ping', parameters: [], block: proc { 'pong' }
                      ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'Keep going',
      max_iterations: 2,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes,
      http_adapter: FakeHttpAdapter.new
    )

    result = loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Go')])
    assert result.completed?
  end

  test 'creates spans for each iteration' do
    provider = FakeProvider.new([
                                  SolidAgent::Types::Response.new(
                                    messages: [SolidAgent::Types::Message.new(role: 'assistant', content: 'Done')],
                                    tool_calls: [],
                                    usage: SolidAgent::Types::Usage.new(input_tokens: 10, output_tokens: 5),
                                    finish_reason: 'stop'
                                  )
                                ])

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1),
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'Test',
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes,
      http_adapter: FakeHttpAdapter.new
    )

    loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hi')])
    @trace.reload
    assert @trace.spans.length >= 1
    think_span = @trace.spans.find { |s| s.span_type == 'llm' }
    assert think_span
    assert_equal 10, think_span.tokens_in
  end

  test 'llm spans have gen_ai semantic convention attributes' do
    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
                        name: :test_tool, description: 'Test', parameters: [], block: proc { 'ok' }
                      ))
    fake_response = SolidAgent::Types::Response.new(
      messages: [SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [
                                                  SolidAgent::Types::ToolCall.new(id: 'c1', name: 'test_tool', arguments: {})
                                                ])],
      tool_calls: [SolidAgent::Types::ToolCall.new(id: 'c1', name: 'test_tool', arguments: {})],
      usage: SolidAgent::Types::Usage.new(input_tokens: 50, output_tokens: 20),
      finish_reason: 'tool_calls'
    )

    provider = FakeProvider.new([fake_response])
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace, provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'You are helpful',
      max_iterations: 3, max_tokens_per_run: 1000, timeout: 30,
      http_adapter: FakeHttpAdapter.new,
      provider_name: :openai
    )

    loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hello')])

    llm_span = @trace.spans.find { |s| s.span_type == 'llm' }
    assert llm_span, 'expected an llm span to be created'
    metadata = llm_span.metadata || {}
    assert_equal 'chat', metadata['gen_ai.operation.name']
    assert_equal 'openai', metadata['gen_ai.provider.name']
  end

  test 'tool spans have execute_tool semantic convention attributes' do
    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
                        name: :test_tool, description: 'Test', parameters: [], block: proc { 'ok' }
                      ))
    fake_response = SolidAgent::Types::Response.new(
      messages: [SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [
                                                  SolidAgent::Types::ToolCall.new(id: 'c1', name: 'test_tool', arguments: {})
                                                ])],
      tool_calls: [SolidAgent::Types::ToolCall.new(id: 'c1', name: 'test_tool', arguments: {})],
      usage: SolidAgent::Types::Usage.new(input_tokens: 50, output_tokens: 20),
      finish_reason: 'tool_calls'
    )

    provider = FakeProvider.new([fake_response])
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace, provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'You are helpful',
      max_iterations: 3, max_tokens_per_run: 1000, timeout: 30,
      http_adapter: FakeHttpAdapter.new,
      provider_name: :openai
    )

    loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hello')])

    tool_span = @trace.spans.find { |s| s.span_type == 'tool' }
    assert tool_span, 'expected a tool span to be created'
    metadata = tool_span.metadata || {}
    assert_equal 'execute_tool', metadata['gen_ai.operation.name']
    assert_equal 'test_tool', metadata['gen_ai.tool.name']
  end
end
