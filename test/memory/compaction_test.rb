require 'test_helper'

class CompactionTest < ActiveSupport::TestCase
  def setup
    @summarizer = ->(text) { "Summary of: #{text.truncate(50)}" }
    @strategy = SolidAgent::Memory::Compaction.new(
      max_tokens: 100,
      summarizer: @summarizer
    )
  end

  test 'stores max_tokens' do
    assert_equal 100, @strategy.max_tokens
  end

  test 'default max_tokens is 8000' do
    strategy = SolidAgent::Memory::Compaction.new
    assert_equal 8000, strategy.max_tokens
  end

  test 'stores summarizer' do
    assert_equal @summarizer, @strategy.summarizer
  end

  test 'filter returns all messages unchanged' do
    messages = build_messages(5, token_count: 10)
    result = @strategy.filter(messages)
    assert_equal messages, result
  end

  test 'build_context adds system prompt' do
    messages = build_messages(3, token_count: 10)
    result = @strategy.build_context(messages, system_prompt: 'Be helpful')
    assert_equal 4, result.length
    assert_equal 'system', result.first.role
  end

  test 'compact! returns messages when under token limit' do
    messages = build_messages(5, token_count: 10)
    result = @strategy.compact!(messages)
    assert_equal 5, result.length
    assert_equal messages, result
  end

  test 'compact! summarizes older messages when over limit' do
    messages = build_messages(20, token_count: 10)
    result = @strategy.compact!(messages)
    assert result.length < 20, 'Expected fewer messages after compaction'
    assert_equal 'system', result.first.role
    assert result.first.content.start_with?('[Summary of earlier conversation]'),
           "Expected summary prefix, got: #{result.first.content}"
  end

  test 'compact! preserves recent messages after summary' do
    messages = build_messages(20, token_count: 10)
    result = @strategy.compact!(messages)
    assert result.last.content.start_with?('Message'), "Expected recent message, got: #{result.last.content}"
    recent_original = messages.last.content
    assert_equal recent_original, result.last.content
  end

  test 'compact! without summarizer returns messages unchanged' do
    strategy = SolidAgent::Memory::Compaction.new(max_tokens: 10)
    messages = build_messages(20, token_count: 10)
    result = strategy.compact!(messages)
    assert_equal 20, result.length
  end

  test 'needs_compaction? returns true when over limit' do
    messages = build_messages(20, token_count: 10)
    assert @strategy.needs_compaction?(messages)
  end

  test 'needs_compaction? returns false when under limit' do
    messages = build_messages(5, token_count: 10)
    refute @strategy.needs_compaction?(messages)
  end

  test 'needs_compaction? returns false at exact limit' do
    messages = build_messages(10, token_count: 10)
    refute @strategy.needs_compaction?(messages)
  end

  test 'compact! with mixed token counts' do
    messages = [
      SolidAgent::Message.new(role: 'user', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'assistant', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'user', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'assistant', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'user', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'assistant', content: 'Long', token_count: 15),
      SolidAgent::Message.new(role: 'user', content: 'Short', token_count: 2),
      SolidAgent::Message.new(role: 'assistant', content: 'Short', token_count: 2)
    ]
    strategy = SolidAgent::Memory::Compaction.new(max_tokens: 50, summarizer: @summarizer)
    result = strategy.compact!(messages)
    assert result.length < messages.length
  end
end
