require 'test_helper'

class DashboardControllerTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::MemoryEntry.delete_all
    SolidAgent::Message.delete_all
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')
  end

  test 'dashboard_stats returns correct structure' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'ResearchAgent',
      trace_type: :agent_run, status: 'completed',
      usage: { 'input_tokens' => 100, 'output_tokens' => 50 }
    )

    controller = SolidAgent::DashboardController.new
    stats = controller.send(:dashboard_stats)

    assert_equal 1, stats[:total_traces]
    assert_equal 0, stats[:active_traces]
    assert_equal 1, stats[:total_conversations]
    assert_equal 150, stats[:total_tokens]
    assert_includes stats[:agents], 'ResearchAgent'
  end

  test 'recent_traces returns last 10 traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    11.times do |i|
      SolidAgent::Trace.create!(
        conversation: conversation, agent_class: "Agent#{i}",
        trace_type: :agent_run, status: 'completed'
      )
    end

    controller = SolidAgent::DashboardController.new
    traces = controller.send(:recent_traces)

    assert_equal 10, traces.size
  end

  test 'dashboard_stats counts active traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'Test',
      trace_type: :agent_run, status: 'running'
    )
    SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'Test',
      trace_type: :agent_run, status: 'completed'
    )

    controller = SolidAgent::DashboardController.new
    stats = controller.send(:dashboard_stats)

    assert_equal 1, stats[:active_traces]
    assert_equal 2, stats[:total_traces]
  end
end
