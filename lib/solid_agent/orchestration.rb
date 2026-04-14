module SolidAgent
  module Orchestration
    class Error < SolidAgent::Error; end
    class DelegateError < Error; end

    PendingToolCall = Struct.new(:name, :tool, :arguments, :tool_call_id, keyword_init: true)
  end
end
