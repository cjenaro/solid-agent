module SolidAgent
  class Trace < ApplicationRecord
    belongs_to :conversation
    belongs_to :parent_trace, class_name: 'SolidAgent::Trace', optional: true
  end
end
