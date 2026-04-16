require 'test_helper'

class ExporterTest < ActiveSupport::TestCase
  test 'base exporter raises NotImplementedError on export_trace' do
    exporter = SolidAgent::Telemetry::Exporter.new
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    trace = SolidAgent::Trace.create!(conversation: conversation, agent_class: 'TestAgent', trace_type: :agent_run)

    assert_raises(NotImplementedError) { exporter.export_trace(trace) }
  end

  test 'base exporter shutdown is a no-op' do
    exporter = SolidAgent::Telemetry::Exporter.new
    assert_nil exporter.shutdown
  end

  test 'base exporter flush is a no-op' do
    exporter = SolidAgent::Telemetry::Exporter.new
    assert_nil exporter.flush
  end
end
