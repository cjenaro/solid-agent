require 'test_helper'

class FullHistoryTest < ActiveSupport::TestCase
  def setup
    @strategy = SolidAgent::Memory::FullHistory.new
  end

  test 'filter returns all messages unchanged' do
    messages = build_messages(100)
    result = @strategy.filter(messages)
    assert_equal 100, result.length
    assert_equal messages, result
  end

  test 'filter returns empty array for no messages' do
    result = @strategy.filter([])
    assert_equal [], result
  end

  test 'build_context adds system prompt before all messages' do
    messages = build_messages(3)
    result = @strategy.build_context(messages, system_prompt: 'Be helpful')
    assert_equal 4, result.length
    assert_equal 'system', result.first.role
    assert_equal 'Be helpful', result.first.content
    assert_equal 'Message 1', result[1].content
    assert_equal 'Message 3', result.last.content
  end

  test 'build_context without system prompt returns all messages' do
    messages = build_messages(3)
    result = @strategy.build_context(messages, system_prompt: nil)
    assert_equal 3, result.length
  end

  test 'compact! returns all messages unchanged' do
    messages = build_messages(50)
    result = @strategy.compact!(messages)
    assert_equal 50, result.length
    assert_equal messages, result
  end

  test 'compact! with empty messages returns empty' do
    result = @strategy.compact!([])
    assert_equal [], result
  end
end
