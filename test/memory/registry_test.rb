require 'test_helper'

class MemoryRegistryTest < ActiveSupport::TestCase
  test 'resolve returns class for known strategy' do
    klass = SolidAgent::Memory::Registry.resolve(:sliding_window)
    assert_equal SolidAgent::Memory::SlidingWindow, klass
  end

  test 'resolve returns FullHistory for :full_history' do
    klass = SolidAgent::Memory::Registry.resolve(:full_history)
    assert_equal SolidAgent::Memory::FullHistory, klass
  end

  test 'resolve returns Compaction for :compaction' do
    klass = SolidAgent::Memory::Registry.resolve(:compaction)
    assert_equal SolidAgent::Memory::Compaction, klass
  end

  test 'resolve raises for unknown strategy' do
    assert_raises(ArgumentError) do
      SolidAgent::Memory::Registry.resolve(:nonexistent)
    end
  end

  test 'build returns strategy instance without block' do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 20)
    assert_instance_of SolidAgent::Memory::SlidingWindow, strategy
    assert_equal 20, strategy.max_messages
  end

  test 'build returns FullHistory instance' do
    strategy = SolidAgent::Memory::Registry.build(:full_history)
    assert_instance_of SolidAgent::Memory::FullHistory, strategy
  end

  test 'build returns Compaction with options' do
    summarizer = ->(_text) { 'summary' }
    strategy = SolidAgent::Memory::Registry.build(:compaction, max_tokens: 4000, summarizer: summarizer)
    assert_instance_of SolidAgent::Memory::Compaction, strategy
    assert_equal 4000, strategy.max_tokens
  end

  test 'build with block returns Chain' do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 30) do |m|
      m.then :compaction, max_tokens: 4000
    end

    assert_instance_of SolidAgent::Memory::Chain, strategy
    assert_equal 2, strategy.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, strategy.strategies.first
    assert_instance_of SolidAgent::Memory::Compaction, strategy.strategies.last
  end

  test 'build with block containing multiple thens' do
    strategy = SolidAgent::Memory::Registry.build(:full_history) do |m|
      m.then :sliding_window, max_messages: 10
      m.then :compaction, max_tokens: 2000
    end

    assert_instance_of SolidAgent::Memory::Chain, strategy
    assert_equal 3, strategy.strategies.length
  end

  test 'ChainBuilder collects strategies' do
    builder = SolidAgent::Memory::ChainBuilder.new
    builder.then :sliding_window, max_messages: 10
    builder.then :compaction, max_tokens: 2000

    assert_equal 2, builder.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, builder.strategies.first
    assert_instance_of SolidAgent::Memory::Compaction, builder.strategies.last
  end

  test 'STRATEGIES constant has all known strategies' do
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:sliding_window)
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:full_history)
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:compaction)
  end

  test 'built chain strategies are functional' do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 5) do |m|
      m.then :full_history
    end

    messages = build_messages(10)
    result = strategy.filter(messages)
    assert_equal 5, result.length
  end
end
