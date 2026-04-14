require 'test_helper'

class ChainTest < ActiveSupport::TestCase
  def setup
    @window = SolidAgent::Memory::SlidingWindow.new(max_messages: 5)
    @history = SolidAgent::Memory::FullHistory.new
    @chain = SolidAgent::Memory::Chain.new(strategies: [@window, @history])
  end

  test 'stores strategies' do
    assert_equal 2, @chain.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, @chain.strategies.first
    assert_instance_of SolidAgent::Memory::FullHistory, @chain.strategies.last
  end

  test 'filter applies strategies in sequence' do
    messages = build_messages(10)
    result = @chain.filter(messages)
    assert_equal 5, result.length
    assert_equal 'Message 6', result.first.content
  end

  test 'build_context filters then adds system prompt' do
    messages = build_messages(10)
    result = @chain.build_context(messages, system_prompt: 'Be helpful')
    assert_equal 6, result.length
    assert_equal 'system', result.first.role
    assert_equal 'Message 6', result[1].content
  end

  test 'compact! chains through all strategies' do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)
    chain = SolidAgent::Memory::Chain.new(strategies: [window])
    messages = build_messages(10)
    result = chain.compact!(messages)
    assert_equal 3, result.length
  end

  test 'chain with compaction strategy' do
    summarizer = ->(text) { "Summary: #{text.truncate(20)}" }
    compaction = SolidAgent::Memory::Compaction.new(max_tokens: 50, summarizer: summarizer)
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 10)
    chain = SolidAgent::Memory::Chain.new(strategies: [window, compaction])

    messages = build_messages(20, token_count: 5)
    result = chain.compact!(messages)
    assert result.length <= 10
  end

  test 'chain with single strategy delegates' do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)
    chain = SolidAgent::Memory::Chain.new(strategies: [window])
    messages = build_messages(10)

    filtered = chain.filter(messages)
    assert_equal 3, filtered.length
  end

  test 'chain with empty strategies returns messages unchanged' do
    chain = SolidAgent::Memory::Chain.new(strategies: [])
    messages = build_messages(5)

    result = chain.filter(messages)
    assert_equal 5, result.length
  end

  test 'compact! with empty strategies returns messages unchanged' do
    chain = SolidAgent::Memory::Chain.new(strategies: [])
    messages = build_messages(5)

    result = chain.compact!(messages)
    assert_equal 5, result.length
  end

  test 'three-strategy chain' do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 8)
    history = SolidAgent::Memory::FullHistory.new
    window2 = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)

    chain = SolidAgent::Memory::Chain.new(strategies: [window, history, window2])
    messages = build_messages(20)

    result = chain.filter(messages)
    assert_equal 3, result.length
    assert_equal 'Message 18', result.first.content
  end
end
