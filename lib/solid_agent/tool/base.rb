require 'solid_agent/tool/schema'

module SolidAgent
  module Tool
    class Base
      class << self
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@tool_parameters, [])
        end

        def name(tool_name)
          @tool_name = tool_name.to_s
        end

        def description(desc)
          @tool_description = desc
        end

        def timeout(seconds)
          @tool_timeout = seconds
        end

        def tool_timeout
          @tool_timeout
        end

        def parameter(param_name, type:, required: false, default: nil, description: nil)
          @tool_parameters ||= []
          @tool_parameters << {
            name: param_name,
            type: type,
            required: required,
            default: default,
            description: description
          }
        end

        attr_reader :tool_name, :tool_description

        def tool_parameters
          @tool_parameters || []
        end

        def to_schema
          properties = {}
          required = []

          tool_parameters.each do |param|
            properties[param[:name]] = {
              type: param[:type].to_s,
              description: param[:description]
            }.compact
            required << param[:name].to_s if param[:required]
          end

          Schema.new(
            name: tool_name,
            description: tool_description,
            input_schema: {
              type: 'object',
              properties: properties,
              required: required
            }
          )
        end
      end

      def execute(arguments)
        symbolized = arguments.transform_keys(&:to_sym)
        validate_required!(symbolized)
        apply_defaults!(symbolized)
        call(**symbolized)
      end

      private

      def validate_required!(arguments)
        self.class.tool_parameters.select { |p| p[:required] }.each do |param|
          raise ArgumentError, "Missing required parameter: #{param[:name]}" unless arguments.key?(param[:name])
        end
      end

      def apply_defaults!(arguments)
        self.class.tool_parameters.each do |param|
          arguments[param[:name]] = param[:default] if !arguments.key?(param[:name]) && !param[:default].nil?
        end
      end
    end
  end
end
