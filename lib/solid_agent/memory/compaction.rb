module SolidAgent
  module Memory
    class Compaction < Base
      attr_reader :max_tokens, :summarizer

      def initialize(max_tokens: 8000, summarizer: nil, **options)
        @max_tokens = max_tokens
        @summarizer = summarizer
        super
      end

      def filter(messages)
        messages
      end

      def compact!(messages)
        return messages if total_token_count(messages) <= @max_tokens
        return messages unless @summarizer

        summarize_older(messages)
      end

      def needs_compaction?(messages)
        total_token_count(messages) > @max_tokens
      end

      private

      def summarize_older(messages)
        split_index = find_split_index(messages)
        return messages if split_index <= 0

        older = messages[0...split_index]
        recent = messages[split_index..]

        combined_text = older.map(&:content).compact.join("\n")
        summary_text = @summarizer.call(combined_text)
        summary_msg = build_system_message("[Summary of earlier conversation]: #{summary_text}")

        [summary_msg] + recent
      end

      def find_split_index(messages)
        total = 0
        half_budget = @max_tokens / 2
        messages.each_with_index do |msg, idx|
          total += msg.token_count.to_i
          return idx + 1 if total > half_budget
        end
        messages.length
      end
    end
  end
end
