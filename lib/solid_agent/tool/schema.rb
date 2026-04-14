module SolidAgent
  module Tool
    class Schema
      attr_reader :name, :description, :input_schema

      def initialize(name:, description:, input_schema:)
        raise ArgumentError, 'name is required' if name.nil?

        @name = name.to_s
        @description = description.to_s
        @input_schema = input_schema
        freeze
      end

      def to_hash
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }
      end
    end
  end
end
