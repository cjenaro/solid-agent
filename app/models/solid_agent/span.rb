module SolidAgent
  class Span < ApplicationRecord
    self.table_name = 'solid_agent_spans'
    belongs_to :trace, class_name: 'SolidAgent::Trace'
  end
end
