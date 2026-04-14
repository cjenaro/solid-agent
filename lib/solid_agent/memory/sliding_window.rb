module SolidAgent
  module Memory
    class SlidingWindow < Base
      attr_reader :max_messages

      def initialize(max_messages: 50, **options)
        @max_messages = max_messages
        super
      end

      def filter(messages)
        messages.last(@max_messages)
      end

      def compact!(messages)
        filter(messages)
      end
    end
  end
end
