module SolidAgent
  module Memory
    class FullHistory < Base
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end
  end
end
