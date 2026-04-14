module SolidAgent
  module Types
    class ToolCall
      attr_reader :id, :name, :arguments, :call_index

      def initialize(id:, name:, arguments:, call_index: 0)
        @id = id
        @name = name
        @arguments = arguments
        @call_index = call_index
        freeze
      end

      def to_hash
        { id: id, name: name, arguments: arguments, call_index: call_index }
      end
    end
  end
end
