require 'test_helper'

class SlidingWindowTest < ActiveSupport::TestCase
  def setup
    @strategy = SolidAgent::Memory::SlidingWindow.new(max_messages: 5)
  end

  test 'default max_messages is 50' do
    strategy = SolidAgent::Memory::SlidingWindow.new
    assert_equal 50, strategy.max_messages
  end

  test 'custom max_messages' do
    strategy = SolidAgent::Memory::SlidingWindow.new(max_messages: 10)
    assert_equal 10, strategy.max_messages
  end

  test 'filter returns last N messages' do
    messages = build_messages(10)
    result = @strategy.filter(messages)
    assert_equal 5, result.length
    assert_equal 'Message 6', result.first.content
    assert_equal 'Message 10', result.last.content
  end

  test 'filter returns all messages when under limit' do
    messages = build_messages(3)
    result = @strategy.filter(messages)
    assert_equal 3, result.length
  end

  test 'filter returns all when count equals max' do
    messages = build_messages(5)
    result = @strategy.filter(messages)
    assert_equal 5, result.length
  end

  test 'build_context adds system prompt and filters' do
    messages = build_messages(10)
    result = @strategy.build_context(messages, system_prompt: 'You are helpful')
    assert_equal 6, result.length
    assert_equal 'system', result.first.role
    assert_equal 'Message 6', result[1].content
  end

  test 'compact! returns last N messages' do
    messages = build_messages(10)
    result = @strategy.compact!(messages)
    assert_equal 5, result.length
    assert_equal 'Message 6', result.first.content
  end

  test 'compact! with under-limit messages returns all' do
    messages = build_messages(3)
    result = @strategy.compact!(messages)
    assert_equal 3, result.length
  end

  test 'handles empty messages' do
    result = @strategy.filter([])
    assert_equal [], result
  end

  test 'handles single message' do
    messages = build_messages(1)
    result = @strategy.filter(messages)
    assert_equal 1, result.length
  end
end
