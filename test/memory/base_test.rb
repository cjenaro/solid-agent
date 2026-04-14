require 'test_helper'

class MemoryBaseTest < ActiveSupport::TestCase
  def setup
    @base = SolidAgent::Memory::Base.new
  end

  test 'build_context works with default filter' do
    messages = build_messages(3)
    result = @base.build_context(messages, system_prompt: 'You are helpful')
    assert_equal 4, result.length
    assert_equal 'system', result.first.role
  end

  test 'compact! raises NotImplementedError' do
    messages = build_messages(3)
    assert_raises(NotImplementedError) do
      @base.compact!(messages)
    end
  end

  test 'filter returns messages unchanged by default' do
    messages = build_messages(3)
    result = @base.filter(messages)
    assert_equal messages, result
  end

  test 'build_system_message creates system Message' do
    msg = @base.send(:build_system_message, 'Be helpful')
    assert_instance_of SolidAgent::Message, msg
    assert_equal 'system', msg.role
    assert_equal 'Be helpful', msg.content
  end

  test 'total_token_count sums message token counts' do
    messages = build_messages(3, token_count: 10)
    assert_equal 30, @base.send(:total_token_count, messages)
  end

  test 'total_token_count handles nil token_count' do
    messages = [
      SolidAgent::Message.new(role: 'user', content: 'hi', token_count: 5),
      SolidAgent::Message.new(role: 'user', content: 'hello')
    ]
    assert_equal 5, @base.send(:total_token_count, messages)
  end

  test 'build_context with system prompt prepends system message' do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: 'Be helpful')
    assert_equal 3, result.length
    assert_equal 'system', result.first.role
    assert_equal 'Be helpful', result.first.content
    assert_equal 'Message 1', result[1].content
  end

  test 'build_context without system prompt returns filtered only' do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: nil)
    assert_equal 2, result.length
  end

  test 'build_context ignores empty system prompt' do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: '')
    assert_equal 2, result.length
  end
end
