require 'test_helper'

class NullExporterTest < ActiveSupport::TestCase
  def setup
    @exporter = SolidAgent::Telemetry::NullExporter.new
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
  end

  test 'export_trace returns nil without error' do
    assert_nil @exporter.export_trace(@trace)
  end

  test 'shutdown returns nil' do
    assert_nil @exporter.shutdown
  end

  test 'flush returns nil' do
    assert_nil @exporter.flush
  end
end
