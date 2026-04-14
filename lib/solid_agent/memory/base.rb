module SolidAgent
  module Memory
    class Base
      def initialize(**options); end

      def filter(messages)
        messages
      end

      def build_context(messages, system_prompt:)
        result = filter(messages)
        if system_prompt && !system_prompt.empty?
          [build_system_message(system_prompt)] + result
        else
          result
        end
      end

      def compact!(messages)
        raise NotImplementedError, "#{self.class}#compact! must be implemented"
      end

      private

      def build_system_message(content)
        SolidAgent::Message.new(role: 'system', content: content)
      end

      def total_token_count(messages)
        messages.sum { |m| m.token_count.to_i }
      end
    end
  end
end
