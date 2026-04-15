require 'solid_agent/tool/schema'

module SolidAgent
  module Tool
    class InlineTool
      attr_reader :schema

      def initialize(name:, description:, parameters:, block:)
        @block = block
        @defaults = {}
        @required_keys = []

        properties = {}
        required = []
        parameters.each do |param|
          properties[param[:name]] = { type: param[:type].to_s, description: param[:description] }.compact
          required << param[:name].to_s if param[:required]
          @defaults[param[:name].to_sym] = param[:default] if param.key?(:default) && !param[:default].nil?
          @required_keys << param[:name].to_sym if param[:required]
        end

        @schema = Schema.new(
          name: name.to_s,
          description: description,
          input_schema: {
            type: 'object',
            properties: properties,
            required: required
          }
        )
      end

      def execute(arguments)
        symbolized = arguments.transform_keys(&:to_sym)
        @required_keys.each do |key|
          raise ArgumentError, "Missing required parameter: #{key}" unless symbolized.key?(key)
        end
        @defaults.each { |k, v| symbolized[k] ||= v }
        @block.call(**symbolized)
      end
    end
  end
end
