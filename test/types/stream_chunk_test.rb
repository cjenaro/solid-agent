require 'test_helper'
require 'solid_agent'

class TypesStreamChunkTest < ActiveSupport::TestCase
  test 'creates text delta chunk' do
    chunk = SolidAgent::Types::StreamChunk.new(delta_content: 'Hello', delta_tool_calls: [], usage: nil, done: false)
    assert_equal 'Hello', chunk.delta_content
    assert_not chunk.done?
  end

  test 'creates tool call delta chunk' do
    chunk = SolidAgent::Types::StreamChunk.new(
      delta_content: nil,
      delta_tool_calls: [{ 'index' => 0, 'id' => 'call_1', 'name' => 'search' }],
      usage: nil,
      done: false
    )
    assert_equal 1, chunk.delta_tool_calls.length
  end

  test 'creates done chunk' do
    chunk = SolidAgent::Types::StreamChunk.new(
      delta_content: nil,
      delta_tool_calls: [],
      usage: SolidAgent::Types::Usage.new(input_tokens: 100, output_tokens: 50),
      done: true
    )
    assert chunk.done?
    assert_equal 150, chunk.usage.total_tokens
  end
end
